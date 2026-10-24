"""Turn a raw ComfyUI render on a flat chroma background into a game sprite.

Usage:
    python3 -I tools/clean_sprite.py RAW.png OUT.png --height 64 [--key auto|RRGGBB]
        [--tolerance 70] [--split-canopy CANOPY_OUT.png --split-y 0.55]

Steps:
1. Key out the background by flood-filling from the image border with colour
   distance <= tolerance (interior pixels of the same colour are kept, so a
   green shirt survives a green screen).
2. Remove enclosed pockets of near-exact key colour, then unmix the key
   colour from a 2 px band around the background (softened alpha, no spill).
3. Autocrop to the opaque bounding box (+2 px margin) and scale to the target
   height (in game pixels, nearest-neighbour is NOT used: Lanczos keeps the
   ink line smooth).
4. Report the ground point: bottom-centre of the opaque pixels in the last
   rows, written as JSON to stdout for the asset catalog.

With --split-canopy the sprite is cut at a fraction of its height: the top
part becomes a separate canopy (foreground occluder) image, both sharing the
same ground point convention.
"""
import argparse
import json
from collections import deque

import numpy as np
from PIL import Image


def key_border(rgb: np.ndarray, key: np.ndarray, tol: float) -> np.ndarray:
    """Boolean mask of background pixels connected to the border."""
    h, w, _ = rgb.shape
    dist = np.sqrt(((rgb.astype(np.float32) - key) ** 2).sum(axis=2))
    candidate = dist <= tol
    bg = np.zeros((h, w), dtype=bool)
    q = deque()
    for x in range(w):
        for y in (0, h - 1):
            if candidate[y, x] and not bg[y, x]:
                bg[y, x] = True
                q.append((y, x))
    for y in range(h):
        for x in (0, w - 1):
            if candidate[y, x] and not bg[y, x]:
                bg[y, x] = True
                q.append((y, x))
    while q:
        y, x = q.popleft()
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            ny, nx = y + dy, x + dx
            if 0 <= ny < h and 0 <= nx < w and candidate[ny, nx] and not bg[ny, nx]:
                bg[ny, nx] = True
                q.append((ny, nx))
    return bg


def defringe(rgba: np.ndarray, bg: np.ndarray, key: np.ndarray, tol: float) -> None:
    """Unmix the key colour from a 2 px band around the background, in place.

    For each band pixel, alpha is estimated from its distance to the key and
    the colour is decontaminated: c = (observed - (1 - a) * key) / a.
    """
    band = np.zeros_like(bg)
    grown = bg.copy()
    for _ in range(2):
        g = grown.copy()
        g[1:, :] |= grown[:-1, :]
        g[:-1, :] |= grown[1:, :]
        g[:, 1:] |= grown[:, :-1]
        g[:, :-1] |= grown[:, 1:]
        grown = g
    band = grown & ~bg
    rgb = rgba[..., :3].astype(np.float32)
    dist = np.sqrt(((rgb - key) ** 2).sum(axis=2))
    a = np.clip((dist - tol * 0.5) / (tol * 2.0), 0.0, 1.0)
    a_band = np.maximum(a[band], 0.05)[:, None]
    unmixed = (rgb[band] - (1.0 - a_band) * key) / a_band
    rgb[band] = np.clip(unmixed, 0, 255)
    rgba[..., :3] = rgb.astype(np.uint8)
    rgba[..., 3][band] = (np.minimum(rgba[..., 3][band] / 255.0, a[band]) * 255).astype(np.uint8)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("raw")
    ap.add_argument("out")
    ap.add_argument("--height", type=int, required=True, help="output sprite height in px")
    ap.add_argument("--key", default="auto", help="hex colour, or auto = median of the border pixels")
    ap.add_argument("--tolerance", type=float, default=70.0)
    ap.add_argument("--split-canopy")
    ap.add_argument("--split-y", type=float, default=0.55, help="cut line as a fraction of height from the top")
    args = ap.parse_args()

    img = Image.open(args.raw).convert("RGBA")
    rgba = np.array(img)
    if args.key == "auto":
        border = np.concatenate([rgba[0, :, :3], rgba[-1, :, :3], rgba[:, 0, :3], rgba[:, -1, :3]])
        key = np.median(border, axis=0).astype(np.float32)
    else:
        key = np.array([int(args.key[i:i + 2], 16) for i in (0, 2, 4)], dtype=np.float32)
    bg = key_border(rgba[..., :3], key, args.tolerance)
    # Enclosed pockets (gaps between bench slats, under arms) are not connected
    # to the border; remove pixels that are very close to the key anywhere.
    dist = np.sqrt(((rgba[..., :3].astype(np.float32) - key) ** 2).sum(axis=2))
    bg |= dist <= args.tolerance * 0.6
    if key[0] > 180 and key[2] > 180 and key[1] < 90:
        # Magenta key: shadowed background (darker magenta) keeps the hue, so
        # also drop strongly magenta pixels. Magenta almost never occurs in
        # the subjects; the green key is not treated this way (leaves).
        rgb = rgba[..., :3].astype(np.float32)
        chroma = rgb - rgb.mean(axis=2, keepdims=True)
        kc = key - key.mean()
        cos = (chroma * kc).sum(axis=2) / (np.linalg.norm(chroma, axis=2) * np.linalg.norm(kc) + 1e-6)
        bg |= (cos > 0.97) & (np.linalg.norm(chroma, axis=2) > 70)
    rgba[..., 3][bg] = 0
    defringe(rgba, bg, key, args.tolerance)

    alpha = rgba[..., 3] > 0
    ys, xs = np.nonzero(alpha)
    if len(xs) == 0:
        raise SystemExit("no foreground pixels left after keying: wrong key colour?")
    y0, y1 = max(ys.min() - 2, 0), min(ys.max() + 3, rgba.shape[0])
    x0, x1 = max(xs.min() - 2, 0), min(xs.max() + 3, rgba.shape[1])
    crop = Image.fromarray(rgba[y0:y1, x0:x1])
    scale = args.height / crop.height
    out = crop.resize((max(1, round(crop.width * scale)), args.height), Image.LANCZOS)
    arr = np.array(out)

    # Ground point: centre of opaque pixels in the bottom 6% of the sprite.
    a = arr[..., 3] > 64
    rows = np.nonzero(a.any(axis=1))[0]
    bottom = rows.max()
    band = a[max(bottom - max(2, int(args.height * 0.06)), 0):bottom + 1]
    bx = np.nonzero(band.any(axis=0))[0]
    ground = [float((bx.min() + bx.max()) / 2.0), float(bottom)]
    info = {"key": [int(c) for c in key], "size": [out.width, out.height], "ground_point": ground}

    if args.split_canopy:
        cut = int(out.height * args.split_y)
        top = arr.copy()
        top[cut:, :, 3] = 0
        base = arr.copy()
        base[:cut, :, 3] = 0
        Image.fromarray(top).save(args.split_canopy)
        Image.fromarray(base).save(args.out)
        info["canopy_cut_y"] = cut
    else:
        out.save(args.out)
    print(json.dumps(info))


if __name__ == "__main__":
    main()
