"""Clean raw renders (art_src/raw) into game sprites (art/) and update the
asset catalog with texture paths, ground points and occluder shapes.

Usage (project root):
    python3 -I tools/import_assets.py            # every raw render present
    python3 -I tools/import_assets.py bench dog  # specific assets

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
    "bench": {"height": 34}, "bin": {"height": 26}, "planter": {"height": 32}, "lamp_post": {"height": 84},
    "bike": {"height": 30}, "sign_board": {"height": 28}, "kiosk": {"height": 78}, "food_cart": {"height": 88},
    "dog": {"height": 22}, "cafe_table": {"height": 30}, "parasol_table": {"height": 78, "split": 0.5},
    "hydrant": {"height": 22}, "mailbox": {"height": 34}, "flower_bed": {"width": 64}, "bush": {"height": 32},
    "crates": {"height": 34}, "car_red": {"height": 44}, "car_blue": {"height": 44}, "car_yellow": {"height": 44},
    "fountain": {"width": 170}, "statue": {"height": 112},
    "stall_red": {"height": 108, "split": 0.42}, "stall_blue": {"height": 108, "split": 0.42},
    "stall_green": {"height": 108, "split": 0.42},
    "easel": {"height": 52}, "duck": {"height": 14}, "pigeon": {"height": 12},
    "cat_in_tree": {"height": 18, "lift": 100},
    "tree_round": {"height": 150, "split": 0.62}, "tree_pine": {"height": 150, "split": 0.7},
    "tree_blossom": {"height": 150, "split": 0.62},
    # Nature museum. Critters are a bit smaller than people (62).
    "baby_trex": {"height": 38}, "baby_triceratops": {"height": 28}, "baby_stegosaurus": {"height": 30},
    "dodo": {"height": 32}, "mammoth_calf": {"height": 34}, "sabretooth_cub": {"height": 26},
    "trex_skeleton": {"height": 220}, "mammoth_skeleton": {"height": 160}, "whale_skeleton": {"width": 420},
    "triceratops_skull": {"height": 70}, "display_case": {"height": 64}, "crystal_cluster": {"height": 50},
    "rope_barrier": {"height": 30}, "museum_bench": {"height": 26}, "potted_palm": {"height": 74},
    "pillar": {"height": 180}, "gift_shelf": {"height": 84}, "ammonite_pedestal": {"height": 50},
    "dino_nest": {"height": 22}, "volcano_model": {"height": 56}, "meteorite": {"height": 38},
}
CHARACTER_HEIGHT = {"normal": 62, "tall": 68, "short": 50, "wide": 62}
FOLDERS = {"character": "characters", "building": "buildings", "tree": "props", "prop": "props", "critter": "critters"}


def spec_for(key: str, entry: dict) -> dict:
    if entry["kind"] == "character":
        return {"height": CHARACTER_HEIGHT[entry["look"].get("build", "normal")]}
    if entry["kind"] == "building":
        return {"width": int(entry["params"]["width"])}
    return SPEC[key]


def alpha_bbox(path: Path):
    a = np.array(Image.open(path).convert("RGBA"))[..., 3] > 64
    ys, xs = np.nonzero(a)
    return xs.min(), ys.min(), xs.max() + 1, ys.max() + 1


def import_one(key: str, entry: dict) -> None:
    spec = spec_for(key, entry)
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
        elif key == "parasol_table":
            new.append({"shape": "circle", "center": [rect[0] + rect[2] // 2, rect[1] + rect[3] // 2], "radius": round(min(rect[2], rect[3]) * 0.45), "layer": "foreground"})
        else:
            new.append({"shape": "rect", "rect": rect, "layer": "foreground"})
            bx0, by0, bx1, by1 = alpha_bbox(out)
            counter_top = by1 - (by1 - by0) * 0.35
            new.append({"shape": "rect", "rect": to_game(bx0, counter_top, bx1, by1), "layer": "y_sort"})
    elif key == "fountain":
        new = occluders  # only the narrow pedestal hides people; keep the authored shape
    else:
        new.append({"shape": "rect", "rect": to_game(*alpha_bbox(out)), "layer": "y_sort"})
    entry["occluders"] = new


# HUD art (not in the catalog): output height in px, kept large for crisp UI.
UI_SPEC = {"ui_magnifier": 360, "ui_stopwatch": 200, "ui_banner": 240, "ui_hat": 200, "ui_map_paper": 900}


def import_ui(key: str) -> None:
    folder = ROOT / "art/ui"
    folder.mkdir(parents=True, exist_ok=True)
    subprocess.run([sys.executable, "-I", str(ROOT / "tools/clean_sprite.py"), str(RAW / f"{key}.png"), str(folder / f"{key}.png"),
                    "--height", str(UI_SPEC[key])], check=True, capture_output=True, text=True)


def main() -> None:
    args = sys.argv[1:]
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
    # People are drawn from the part kit; whole-body renders are reference only.
    keys = sys.argv[1:] or [k for k in assets if (RAW / f"{k}.png").exists() and assets[k]["kind"] != "character"]
    for key in keys:
        try:
            import_one(key, assets[key])
            print(f"imported {key}: {assets[key]['texture']} h={assets[key]['height_px']}")
        except Exception as exc:
            print(f"FAILED {key}: {exc}")
    CATALOG.write_text(json.dumps(data, indent=2) + "\n")


if __name__ == "__main__":
    main()
