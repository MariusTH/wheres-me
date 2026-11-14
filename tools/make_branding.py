"""Turn the branding renders (tools/gen_assets.py BRANDING, art_src/raw/) into
the final files in art/branding/:

    app_icon_1024.png   App Store / home-screen icon (opaque RGB; Godot derives
                        every other size from it; also the project icon)
    launch@2x.png       iOS launch screen (storyboard) and Godot boot splash,
    launch@3x.png       landscape art with the title on a paper banner
    itch_cover.png      630x500 itch.io cover

Usage: python3 -I tools/make_branding.py [--icon app_icon_1] [--splash splash_2]
"""
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parent.parent
RAW = ROOT / "art_src/raw"
OUT = ROOT / "art/branding"
FONT = ROOT / "art/fonts/LuckiestGuy-Regular.ttf"
TITLE = "Where's Me?"
INK = (58, 43, 36)
PAPER = (248, 241, 226)
ACCENT = (207, 106, 74)


def arg(name: str, default: str) -> str:
    return sys.argv[sys.argv.index(name) + 1] if name in sys.argv else default


def cover(im: Image.Image, w: int, h: int) -> Image.Image:
    """Scale to fill w x h and crop the overflow, centred."""
    s = max(w / im.width, h / im.height)
    im = im.resize((round(im.width * s), round(im.height * s)), Image.LANCZOS)
    x, y = (im.width - w) // 2, (im.height - h) // 2
    return im.crop((x, y, x + w, y + h))


def title_banner(im: Image.Image, scale: float) -> Image.Image:
    """Title in the game's display font on a soft paper ribbon, centred."""
    im = im.convert("RGBA")
    font = ImageFont.truetype(str(FONT), round(im.height * 0.14 * scale))
    draw = ImageDraw.Draw(im)
    l, t, r, b = draw.textbbox((0, 0), TITLE, font=font)
    tw, th = r - l, b - t
    cx, cy = im.width // 2, round(im.height * 0.47)
    pad_x, pad_y = round(th * 0.9), round(th * 0.45)
    box = (cx - tw // 2 - pad_x, cy - th // 2 - pad_y, cx + tw // 2 + pad_x, cy + th // 2 + pad_y)
    shadow = Image.new("RGBA", im.size, (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle([box[0] + 6, box[1] + 10, box[2] + 6, box[3] + 10], radius=pad_y, fill=(40, 25, 15, 90))
    im = Image.alpha_composite(im, shadow.filter(ImageFilter.GaussianBlur(12)))
    draw = ImageDraw.Draw(im)
    draw.rounded_rectangle(box, radius=pad_y, fill=PAPER + (240,), outline=INK, width=max(3, th // 18))
    stroke = max(2, th // 14)
    draw.text((cx - tw // 2 - l, cy - th // 2 - t + th // 14), TITLE, font=font, fill=INK)  # drop shadow
    draw.text((cx - tw // 2 - l, cy - th // 2 - t), TITLE, font=font, fill=ACCENT, stroke_width=stroke, stroke_fill=INK)
    return im.convert("RGB")


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    icon = Image.open(RAW / f"{arg('--icon', 'app_icon_1')}.png").convert("RGB")
    # Trim the white paper margin so the art is full-bleed (iOS rounds the corners).
    m = round(icon.width * 0.06)
    cover(icon.crop((m, m, icon.width - m, icon.height - m)), 1024, 1024).save(OUT / "app_icon_1024.png")

    splash = Image.open(RAW / f"{arg('--splash', 'splash_2')}.png").convert("RGB")
    for name, (w, h) in {"launch@2x.png": (1920, 1080), "launch@3x.png": (2880, 1620)}.items():
        title_banner(cover(splash, w, h), 1.0).save(OUT / name, optimize=True)
    title_banner(cover(splash, 630, 500), 0.75).save(OUT / "itch_cover.png", optimize=True)
    print("Wrote", ", ".join(sorted(p.name for p in OUT.glob("*.png"))))


if __name__ == "__main__":
    main()
