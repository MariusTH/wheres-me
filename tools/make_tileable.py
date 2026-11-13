"""Make a square texture tile seamlessly and shrink it for the game.

Usage: python3 -I tools/make_tileable.py RAW.png OUT.png [--size 256]

Classic offset-and-blend: the image is shifted by half its size (moving the
seams to the middle), then the centre is cross-faded back to the original
with a soft cross-shaped mask, so the borders keep the shifted (matching)
pixels and the middle keeps the unshifted ones.
"""
import argparse

import numpy as np
from PIL import Image, ImageEnhance


def _smooth_noise(h: int, w: int, rng: np.random.Generator, cells: int = 8) -> np.ndarray:
    """Low-frequency noise in 0..1 (bilinear upscale of a small random grid)."""
    small = Image.fromarray((rng.random((cells, cells)) * 255).astype(np.uint8))
    return np.array(small.resize((w, h), Image.BICUBIC)).astype(np.float32) / 255.0


def tileable(img: np.ndarray, band: float = 0.26) -> np.ndarray:
    h, w = img.shape[:2]
    shifted = np.roll(np.roll(img, h // 2, axis=0), w // 2, axis=1)
    y = np.abs(np.linspace(-1, 1, h))[:, None]
    x = np.abs(np.linspace(-1, 1, w))[None, :]
    # The cross-shaped mask edge wanders with noise so the blend never forms a
    # straight visible line (fixed seed: the same raw gives the same tile).
    wobble = (_smooth_noise(h, w, np.random.default_rng(7)) - 0.5) * band * 0.9
    seam = np.maximum(np.clip((band + wobble - x) / (band * 0.35), 0, 1),
                      np.clip((band + wobble - y) / (band * 0.35), 0, 1))
    seam = seam[..., None]
    return (shifted * (1 - seam) + img * seam).astype(np.uint8)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("raw")
    ap.add_argument("out")
    ap.add_argument("--size", type=int, default=256)
    ap.add_argument("--sat", type=float, default=1.0, help="saturation multiplier (tone down to sit with the houses)")
    ap.add_argument("--bright", type=float, default=1.0, help="brightness multiplier")
    ap.add_argument("--wash", type=float, default=0.0, help="0..1 blend towards paper cream (quieter, softer ground)")
    a = ap.parse_args()
    img = np.array(Image.open(a.raw).convert("RGB")).astype(np.float32)
    out = Image.fromarray(tileable(img)).resize((a.size, a.size), Image.LANCZOS)
    out = ImageEnhance.Brightness(ImageEnhance.Color(out).enhance(a.sat)).enhance(a.bright)
    if a.wash > 0:
        out = Image.blend(out, Image.new("RGB", out.size, (244, 236, 220)), a.wash)
    out.save(a.out)


if __name__ == "__main__":
    main()
