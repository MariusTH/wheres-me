// Runs browser actions that iOS Safari only allows inside a real tap
// (clipboard read/write, the share sheet, the photo picker). Loaded by WebTap
// through JavaScriptBridge.eval(). Web export only.
//
// Godot handles input a frame after the browser event, which is too late for
// those APIs. So every WebTap button registers its screen rect here (put()),
// and a capture-phase pointerup/touchend listener runs the button's action
// when a tap lands inside it. Replies go to the button's callback as JSON.
(function () {
  if (window.wmTap) return;

  const targets = new Map(); // id -> {x, y, w, h, action, payload, cb}
  const reply = (t, data) => t.cb(JSON.stringify(data));
  const failure = (e) => ({ ok: false, error: (e && e.name === "AbortError") ? "cancelled" : String((e && e.message) || e) });

  // Older browsers without the async clipboard API: copy through a textarea.
  function legacyCopy(text) {
    const area = document.createElement("textarea");
    area.value = text;
    area.setAttribute("readonly", "");
    area.style.position = "fixed";
    area.style.opacity = "0";
    document.body.appendChild(area);
    area.select();
    area.setSelectionRange(0, text.length);
    const ok = document.execCommand("copy");
    document.body.removeChild(area);
    return ok;
  }

  const actions = {
    async paste(t) {
      try { reply(t, { ok: true, text: await navigator.clipboard.readText() }); }
      catch (e) { reply(t, failure(e)); }
    },
    async copy(t) {
      try {
        if (navigator.clipboard && navigator.clipboard.writeText) await navigator.clipboard.writeText(t.payload);
        else if (!legacyCopy(t.payload)) throw new Error("copy not supported");
        reply(t, { ok: true });
      } catch (e) {
        reply(t, legacyCopy(t.payload) ? { ok: true } : failure(e));
      }
    },
    async share(t) {
      try { await navigator.share({ text: t.payload }); reply(t, { ok: true }); }
      catch (e) { reply(t, failure(e)); }
    },
  };

  // touchend and pointerup can both fire for one tap; only the first counts.
  let last = 0;
  function onRelease(e) {
    const canvas = document.querySelector("canvas");
    if (!canvas || targets.size === 0 || Date.now() - last < 600) return;
    const p = e.changedTouches ? e.changedTouches[0] : e;
    const r = canvas.getBoundingClientRect();
    const nx = (p.clientX - r.left) / r.width, ny = (p.clientY - r.top) / r.height;
    for (const t of targets.values()) {
      if (nx >= t.x && nx <= t.x + t.w && ny >= t.y && ny <= t.y + t.h && actions[t.action]) {
        last = Date.now();
        actions[t.action](t);
        return;
      }
    }
  }
  window.addEventListener("pointerup", onRelease, true);
  window.addEventListener("touchend", onRelease, true);

  window.wmTap = {
    // Rect normalised to the Godot canvas (0..1).
    put(id, x, y, w, h, action, payload, cb) { targets.set(id, { x, y, w, h, action, payload, cb }); },
    clear(id) { targets.delete(id); },
    register(action, fn) { actions[action] = fn; },
    canShare: () => !!navigator.share,
    debugTargets: () => Array.from(targets, ([id, t]) => ({ id, action: t.action, x: t.x, y: t.y, w: t.w, h: t.h })),
  };
})();
