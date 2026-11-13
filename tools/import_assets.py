"""Clean raw renders (art_src/raw) into game sprites (art/) and update the
asset catalog with texture paths, ground points and occluder shapes.

Usage (project root):
    python3 -I tools/import_assets.py            # every raw render present
    python3 -I tools/import_assets.py iso_well dog  # specific assets

Sprites are stored at SUPERSAMPLE x their in-game size so they stay crisp
up to the camera's max zoom; "height_px" in the catalog is the in-game size.
Assets with "split" get a separate canopy image (foreground occluder layer)
cut at that fraction of the height. Re-running is safe (idempotent).
Remove an asset's "texture" key from the catalog to fall back to placeholder art.
"""
import json
import subprocess
import sys
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
CATALOG = ROOT / "data/assets/asset_catalog.json"
RAW = ROOT / "art_src/raw"
SUPERSAMPLE = 2

# In-game target size (height in px unless "width" given) and canopy split.
SPEC = {
    # Shared with the isometric town (read the same from any angle).
    "lamp_post": {"height": 84}, "hydrant": {"height": 22}, "mailbox": {"height": 34}, "bush": {"height": 32},
    "dog": {"height": 22}, "duck": {"height": 14}, "pigeon": {"height": 12},
    "tree_round": {"height": 150, "split": 0.62}, "tree_pine": {"height": 150, "split": 0.7},
    "tree_blossom": {"height": 150, "split": 0.62},
}
sys.path.insert(0, str(Path(__file__).resolve().parent))
from gen_assets import ISO_BUILDINGS, ISO_EXTRA_PROPS, ISO_PROPS, ISO_SMALL_BUILDINGS  # noqa: E402

ISO_PROP_TABLE = {**ISO_PROPS, **ISO_EXTRA_PROPS}

# Isometric plots: square plan size (data/maps/town_iso.json grid.plot). The
# slab's diamond spans 2 * ISO_PLOT game px from its left to its right corner.
ISO_PLOT = 112
# Small buildings (huts, outbuildings) stand on a smaller plot (town_iso.json small_plot).
ISO_SMALL_PLOT = 80

FOLDERS = {"tree": "props", "prop": "props"}


def spec_for(key: str) -> dict:
    return ISO_PROP_TABLE[key][2] if key in ISO_PROP_TABLE else SPEC[key]


def alpha_bbox(path: Path):
    a = np.array(Image.open(path).convert("RGBA"))[..., 3] > 64
    ys, xs = np.nonzero(a)
    return xs.min(), ys.min(), xs.max() + 1, ys.max() + 1


def import_one(key: str, entry: dict) -> None:
    spec = spec_for(key)
    folder = ROOT / "art" / FOLDERS[entry["kind"]]
    folder.mkdir(parents=True, exist_ok=True)
    out = folder / f"{key}.png"
    raw = RAW / f"{key}.png"
    if "width" in spec:
        # clean_sprite sizes by height; probe the cropped aspect first.
        probe = subprocess.run([sys.executable, "-I", str(ROOT / "tools/clean_sprite.py"), str(raw), str(out), "--height", "200"],
                               check=True, capture_output=True, text=True)
        w, h = json.loads(probe.stdout)["size"]
        game_h = round(spec["width"] * h / w)
    else:
        game_h = spec["height"]
    cmd = [sys.executable, "-I", str(ROOT / "tools/clean_sprite.py"), str(raw), str(out), "--height", str(game_h * SUPERSAMPLE)]
    canopy = None
    if "split" in spec:
        canopy = folder / f"{key}_canopy.png"
        cmd += ["--split-canopy", str(canopy), "--split-y", str(spec["split"])]
    info = json.loads(subprocess.run(cmd, check=True, capture_output=True, text=True).stdout)
    s = SUPERSAMPLE
    gx, gy = info["ground_point"]
    if "lift" in spec:
        gy += spec["lift"] * s  # drawn this many game px above its anchor (cat sitting in a tree)
    res = lambda p: "res://" + str(p.relative_to(ROOT))
    entry["texture"] = res(out)
    entry["ground_point"] = [gx, gy]
    entry["height_px"] = game_h
    if canopy:
        entry["canopy_texture"] = res(canopy)
        entry["canopy_ground_point"] = [gx, gy]
        entry["canopy_height_px"] = game_h

    # Occluders in game px relative to the ground point, derived from the art.
    def to_game(x0, y0, x1, y1):
        return [round((x0 - gx) / s), round((y0 - gy) / s), round((x1 - x0) / s), round((y1 - y0) / s)]

    occluders = entry.get("occluders")
    if occluders is None:
        return
    new = []
    if canopy:
        cx0, cy0, cx1, cy1 = alpha_bbox(canopy)
        rect = to_game(cx0, cy0, cx1, cy1)
        if entry["kind"] == "tree":
            r = round(min(rect[2], rect[3]) * 0.42)
            new.append({"shape": "circle", "center": [rect[0] + rect[2] // 2, rect[1] + rect[3] // 2], "radius": r, "layer": "foreground"})
        elif key == "iso_parasol_table":
            new.append({"shape": "circle", "center": [rect[0] + rect[2] // 2, rect[1] + rect[3] // 2], "radius": round(min(rect[2], rect[3]) * 0.45), "layer": "foreground"})
        else:
            new.append({"shape": "rect", "rect": rect, "layer": "foreground"})
            bx0, by0, bx1, by1 = alpha_bbox(out)
            counter_top = by1 - (by1 - by0) * 0.35
            new.append({"shape": "rect", "rect": to_game(bx0, counter_top, bx1, by1), "layer": "y_sort"})
    else:
        new.append({"shape": "rect", "rect": to_game(*alpha_bbox(out)), "layer": "y_sort"})
    entry["occluders"] = new


def _iso_plate(path: Path):
    """Left, right and bottom corner of the paved plot in a cleaned iso sprite."""
    a = np.array(Image.open(path).convert("RGBA"))[..., 3] > 64
    ys, xs = np.nonzero(a)
    h = a.shape[0]
    low = ys > ys.max() - h * 0.4
    left, right = xs[low].min(), xs[low].max()
    bottom = ys.max()
    bx = xs[ys >= bottom - max(2, h * 0.008)].mean()
    return float(left), float(right), float(bx), float(bottom)


def import_iso_building(key: str, entry: dict, plot: int = ISO_PLOT) -> None:
    folder = ROOT / "art/buildings"
    folder.mkdir(parents=True, exist_ok=True)
    out, raw = folder / f"{key}.png", RAW / f"{key}.png"
    clean = [sys.executable, "-I", str(ROOT / "tools/clean_sprite.py"), str(raw), str(out), "--height"]
    subprocess.run(clean + ["600"], check=True, capture_output=True, text=True)
    left, right, _, _ = _iso_plate(out)
    game_h = round(600 * 2 * plot / (right - left))
    subprocess.run(clean + [str(game_h * SUPERSAMPLE)], check=True, capture_output=True, text=True)
    left, right, bx, bottom = _iso_plate(out)
    entry["texture"] = "res://" + str(out.relative_to(ROOT))
    entry["ground_point"] = [round(bx, 1), float(bottom)]
    entry["height_px"] = game_h
    entry["footprint"] = [plot, plot]


# HUD art (not in the catalog): output height in px, kept large for crisp UI.
UI_SPEC = {"ui_magnifier": 360, "ui_stopwatch": 200}


def import_ui(key: str) -> None:
    folder = ROOT / "art/ui"
    folder.mkdir(parents=True, exist_ok=True)
    subprocess.run([sys.executable, "-I", str(ROOT / "tools/clean_sprite.py"), str(RAW / f"{key}.png"), str(folder / f"{key}.png"),
                    "--height", str(UI_SPEC[key])], check=True, capture_output=True, text=True)


# (saturation, brightness, wash towards paper) applied after tiling: FLUX paints ground far more
# saturated than the pastel houses, and the road must stay the darkest value.
GROUND_GRADE = {"ground_grass": (0.6, 1.0, 0.3), "ground_road": (0.7, 1.04, 0.34), "ground_pavement": (0.5, 1.0, 0.42),
                "ground_plaza": (0.6, 1.0, 0.4), "ground_market": (0.6, 1.0, 0.4)}


def import_ground(key: str) -> None:
    folder = ROOT / "art/ground"
    folder.mkdir(parents=True, exist_ok=True)
    subprocess.run([sys.executable, "-I", str(ROOT / "tools/make_tileable.py"), str(RAW / f"{key}.png"), str(folder / f"{key}.png"),
                    "--size", "256", "--sat", str(GROUND_GRADE.get(key, (1, 1, 0))[0]),
                    "--bright", str(GROUND_GRADE.get(key, (1, 1, 0))[1]), "--wash", str(GROUND_GRADE.get(key, (1, 1, 0))[2])], check=True, capture_output=True, text=True)


def main() -> None:
    args = sys.argv[1:]
    ground = [a for a in args if a.startswith("ground_")] if args else [p.stem for p in RAW.glob("ground_*.png")]
    for key in ground:
        import_ground(key)
        print(f"imported {key}: art/ground/{key}.png (tileable)")
    args = [a for a in args if not a.startswith("ground_")]
    if sys.argv[1:] and not args:
        return
    ui = [a for a in args if a in UI_SPEC] if args else [k for k in UI_SPEC if (RAW / f"{k}.png").exists()]
    for key in ui:
        import_ui(key)
        print(f"imported {key}: art/ui/{key}.png")
    args = [a for a in args if a not in UI_SPEC]
    if sys.argv[1:] and not args:
        return  # only UI art was asked for
    sys.argv = [sys.argv[0]] + args
    data = json.loads(CATALOG.read_text())
    assets = data["assets"]
    # Isometric props and buildings get a catalog entry the first time their render is imported.
    for key, (_s, _bg, _spec, radius, kind) in ISO_PROP_TABLE.items():
        if key not in assets and (RAW / f"{key}.png").exists() and (not sys.argv[1:] or key in sys.argv[1:]):
            assets[key] = {"kind": kind, "radius": radius, "tags": ["iso"]}
    for key in list(ISO_BUILDINGS) + list(ISO_SMALL_BUILDINGS):
        if key not in assets and (RAW / f"{key}.png").exists() and (not sys.argv[1:] or key in sys.argv[1:]):
            assets[key] = {"kind": "building", "draw": "building", "tags": ["iso"], "radius": 0}
    # People are drawn from the part kit and have no texture.
    keys = sys.argv[1:] or [k for k in assets if (RAW / f"{k}.png").exists() and assets[k]["kind"] != "character"]
    for key in keys:
        try:
            if key in ISO_BUILDINGS:
                import_iso_building(key, assets[key])
            elif key in ISO_SMALL_BUILDINGS:
                import_iso_building(key, assets[key], ISO_SMALL_PLOT)
            else:
                import_one(key, assets[key])
            print(f"imported {key}: {assets[key]['texture']} h={assets[key]['height_px']}")
        except Exception as exc:
            print(f"FAILED {key}: {exc}")
    CATALOG.write_text(json.dumps(data, indent=2) + "\n")


if __name__ == "__main__":
    main()
