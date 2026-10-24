// Selfie -> avatar measurements, run entirely in the browser (web export only).
// Loaded by SelfieBridge through JavaScriptBridge.eval(). The photo never
// leaves the device; only the models are downloaded, on first use.
//
// Godot can't open a file picker itself: iOS Safari only allows that inside a
// real tap handler, and Godot handles input a frame later. So Godot registers
// the selfie button's screen rect with setTarget(), and a pointerup/touchend
// listener here opens the picker when the tap lands inside it.
//
// Results go to the callback as JSON strings:
//   {"stage":"analyzing"}                         photo chosen, models running
//   {"ok":true, skin, hair, shirt, hat, hair_ratio, ...}   see PhotoToLook
//   {"ok":false, "error":"no_face"|"cancelled"|"<message>"}
(function () {
  if (window.hfSelfie) return;

  const TASKS = "https://cdn.jsdelivr.net/npm/@mediapipe/tasks-vision@0.10.14";
  const SEG_MODEL = "https://storage.googleapis.com/mediapipe-models/image_segmenter/selfie_multiclass_256x256/float32/latest/selfie_multiclass_256x256.tflite";
  const FACE_MODEL = "https://storage.googleapis.com/mediapipe-models/face_landmarker/face_landmarker/float16/1/face_landmarker.task";
  const MAX_SIDE = 512;
  // selfie_multiclass categories.
  const HAIR = 1, FACE_SKIN = 3, CLOTHES = 4, OTHER = 5;

  let modelsPromise = null;
  let target = null; // {x, y, w, h} normalised to the canvas, plus cb
  let input = null;

  function loadModels() {
    if (!modelsPromise) {
      modelsPromise = (async () => {
        const v = await import(TASKS + "/vision_bundle.mjs");
        const files = await v.FilesetResolver.forVisionTasks(TASKS + "/wasm");
        const [seg, face] = await Promise.all([
          v.ImageSegmenter.createFromOptions(files, {
            baseOptions: { modelAssetPath: SEG_MODEL },
            runningMode: "IMAGE",
            outputCategoryMask: true,
            outputConfidenceMasks: false,
          }),
          v.FaceLandmarker.createFromOptions(files, {
            baseOptions: { modelAssetPath: FACE_MODEL },
            runningMode: "IMAGE",
            numFaces: 1,
          }),
        ]);
        return { seg, face };
      })();
      modelsPromise.catch(() => { modelsPromise = null; });
    }
    return modelsPromise;
  }

  function loadImage(url) {
    return new Promise((resolve, reject) => {
      const img = new Image();
      img.crossOrigin = "anonymous";
      img.onload = () => resolve(img);
      img.onerror = () => reject(new Error("Couldn't read that image."));
      img.src = url;
    });
  }

  function toCanvas(img) {
    const k = Math.min(1, MAX_SIDE / Math.max(img.naturalWidth, img.naturalHeight));
    const c = document.createElement("canvas");
    c.width = Math.round(img.naturalWidth * k);
    c.height = Math.round(img.naturalHeight * k);
    c.getContext("2d", { willReadFrequently: true }).drawImage(img, 0, 0, c.width, c.height);
    return c;
  }

  // Per-channel median, robust against highlights, shadows and stray pixels.
  function Median() {
    const h = [new Uint32Array(256), new Uint32Array(256), new Uint32Array(256)];
    let n = 0;
    return {
      add(r, g, b) { h[0][r]++; h[1][g]++; h[2][b]++; n++; },
      count() { return n; },
      value(minCount) {
        if (n < (minCount || 30)) return null;
        return h.map((hist) => {
          let acc = 0;
          for (let i = 0; i < 256; i++) { acc += hist[i]; if (acc * 2 >= n) return i; }
          return 255;
        });
      },
    };
  }

  async function analyzeCanvas(canvas) {
    const { seg, face } = await loadModels();
    const W = canvas.width, H = canvas.height;
    const px = canvas.getContext("2d", { willReadFrequently: true }).getImageData(0, 0, W, H).data;
    const faces = face.detect(canvas).faceLandmarks;
    if (!faces || faces.length === 0) return { ok: false, error: "no_face" };
    const lm = faces[0];
    const res = seg.segment(canvas);
    const mask = res.categoryMask;
    const mw = mask.width, mh = mask.height;
    const cat = mask.getAsUint8Array().slice();
    res.close();

    let fx0 = 1, fx1 = 0;
    for (const p of lm) { fx0 = Math.min(fx0, p.x); fx1 = Math.max(fx1, p.x); }
    const left = fx0 * W, right = fx1 * W;
    const top = lm[10].y * H, chin = lm[152].y * H; // forehead top, chin
    const faceH = Math.max(1, chin - top);
    const eyeY = (lm[159].y + lm[145].y + lm[386].y + lm[374].y) / 4 * H;
    const eyeTop = eyeY - 0.12 * faceH, eyeBottom = eyeY + 0.1 * faceH;
    const hatTop = top - 0.6 * faceH;

    const skin = Median(), hair = Median(), shirt = Median(), hat = Median();
    let hairN = 0, hairBelow = 0, hairAbove = 0, faceN = 0;
    let eyeArea = 0, eyeAcc = 0, hatArea = 0, hatAcc = 0;
    for (let y = 0; y < H; y++) {
      const my = Math.min(mh - 1, Math.floor(y * mh / H));
      for (let x = 0; x < W; x++) {
        const c = cat[my * mw + Math.min(mw - 1, Math.floor(x * mw / W))];
        const i = (y * W + x) * 4;
        const inFaceCols = x >= left && x <= right;
        const inEyes = inFaceCols && y >= eyeTop && y <= eyeBottom;
        const inHat = inFaceCols && y >= hatTop && y < top;
        if (inEyes) eyeArea++;
        if (inHat) hatArea++;
        if (c === HAIR) {
          hairN++;
          hair.add(px[i], px[i + 1], px[i + 2]);
          if (y > chin + 0.05 * faceH) hairBelow++;
          if (y < top - 0.35 * faceH) hairAbove++;
        } else if (c === FACE_SKIN) {
          faceN++;
          if (inFaceCols && y > top && y < chin) skin.add(px[i], px[i + 1], px[i + 2]);
        } else if (c === CLOTHES) {
          if (y > chin) shirt.add(px[i], px[i + 1], px[i + 2]);
        } else if (c === OTHER) {
          if (inEyes) eyeAcc++;
          if (inHat) { hatAcc++; hat.add(px[i], px[i + 1], px[i + 2]); }
        }
      }
    }
    return {
      ok: true,
      skin: skin.value(),
      hair: hair.value(),
      shirt: shirt.value(),
      hat: hat.value(),
      hair_ratio: hairN / Math.max(1, faceN),
      hair_below_chin: hairBelow / Math.max(1, hairN),
      hair_above_top: hairAbove / Math.max(1, hairN),
      glasses: eyeAcc / Math.max(1, eyeArea),
      hat_cover: hatAcc / Math.max(1, hatArea),
    };
  }

  async function analyzeUrl(url) {
    try {
      return await analyzeCanvas(toCanvas(await loadImage(url)));
    } catch (e) {
      return { ok: false, error: String((e && e.message) || e) };
    }
  }

  function openPicker(cb) {
    if (!input) {
      input = document.createElement("input");
      input.type = "file";
      input.accept = "image/*";
      input.style.display = "none";
      document.body.appendChild(input);
    }
    input.value = "";
    input.oncancel = () => cb(JSON.stringify({ ok: false, error: "cancelled" }));
    input.onchange = async () => {
      const file = input.files && input.files[0];
      if (!file) { cb(JSON.stringify({ ok: false, error: "cancelled" })); return; }
      cb(JSON.stringify({ stage: "analyzing" }));
      const url = URL.createObjectURL(file);
      try { cb(JSON.stringify(await analyzeUrl(url))); }
      finally { URL.revokeObjectURL(url); }
    };
    input.click();
  }

  // touchend and pointerup can both fire for one tap; only the first opens.
  let lastOpen = 0;
  function onRelease(e) {
    const canvas = document.querySelector("canvas");
    if (!target || !canvas || Date.now() - lastOpen < 600) return;
    const p = e.changedTouches ? e.changedTouches[0] : e;
    const r = canvas.getBoundingClientRect();
    const nx = (p.clientX - r.left) / r.width, ny = (p.clientY - r.top) / r.height;
    if (nx >= target.x && nx <= target.x + target.w && ny >= target.y && ny <= target.y + target.h) {
      lastOpen = Date.now();
      openPicker(target.cb);
      loadModels().catch(() => {}); // warm up while the user picks a photo
    }
  }
  window.addEventListener("pointerup", onRelease, true);
  window.addEventListener("touchend", onRelease, true);

  window.hfSelfie = {
    // Rect normalised to the Godot canvas (0..1); cb receives JSON strings.
    setTarget(x, y, w, h, cb) { target = { x, y, w, h, cb }; },
    clearTarget() { target = null; },
    analyzeUrl: (url) => analyzeUrl(url).then((r) => JSON.stringify(r)),
    debugTarget: () => target && { x: target.x, y: target.y, w: target.w, h: target.h },
  };
})();
