"""Generate raw sprite renders with the local ComfyUI (FLUX.2 Klein 4B base).

Usage (from the project root, with ComfyUI running on 127.0.0.1:8188):
    python3 -I tools/gen_assets.py                 # everything still missing
    python3 -I tools/gen_assets.py npc_03 bench    # specific assets (re-renders)
    python3 -I tools/gen_assets.py --list          # print prompts only

People are not generated (they come from the part kit); pass --characters
to render whole-body reference images anyway.

Writes art_src/raw/<key>.png and records prompt / seed / size / workflow per
asset in art_src/manifest.json. Character prompts are derived from the
"look" in data/assets/asset_catalog.json so placeholder and final art match.
Uses art_src/workflows/flux2_klein_4b_base_only.json (template
image_flux2_klein_text_to_image with the uninstalled distilled branch removed).
"""
import json
import shutil
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CATALOG = ROOT / "data/assets/asset_catalog.json"
BASE_WORKFLOW = ROOT / "art_src/workflows/flux2_klein_4b_base_only.json"
RAW_DIR = ROOT / "art_src/raw"
MANIFEST = ROOT / "art_src/manifest.json"
WORK_DIR = ROOT / "art_src/workflows/generated"
COMFY_OUTPUT = Path.home() / "Documents/comfy/ComfyUI/output"

STYLE = ("STYLE: original, colourful hand-drawn hidden-object game illustration, children's picture book "
         "ink and watercolour, slightly irregular dark ink outline, flat warm muted colours with a few saturated "
         "accents, soft daylight from upper left. ")
CAMERA = "Seen from a high-angle, shallow top-down three-quarter view. "
# Objects with a clear front came out rotated diagonally with CAMERA, which
# clashes with the front-facing shops and people; render these square-on.
FRONT_CAMERA = ("Seen straight from the front and slightly above, facing the viewer squarely, "
                "symmetric, not rotated, not at an angle, not isometric. ")
FRONT_FACING = {"bench", "kiosk", "food_cart", "cafe_table", "parasol_table", "stall_red", "stall_blue",
                "stall_green", "crates", "sign_board", "mailbox"}
SIDE_CAMERA = "Seen exactly from the side, flat side profile, not at an angle, not isometric. "
SIDE_VIEW = {"car_red", "car_blue", "car_yellow", "baby_trex", "baby_triceratops", "baby_stegosaurus", "dodo",
             "mammoth_calf", "sabretooth_cub", "trex_skeleton", "mammoth_skeleton", "whale_skeleton"}
FRONT_FACING |= {"triceratops_skull", "display_case", "rope_barrier", "museum_bench", "pillar", "gift_shelf",
                 "ammonite_pedestal", "volcano_model"}
BACKGROUNDS = {
    "green": "Isolated single subject centred, on a plain flat solid pure bright green background, ",
    "magenta": "Isolated single subject centred, on a plain flat solid pure magenta (#FF00FF) background, ",
}
SUFFIX = "no ground shadow, no text, no letters, no labels, no border, no frame, no other objects."

COLOR_NAMES = {
    "#d63c3c": "red", "#f4efe6": "cream white", "#ffffff": "white", "#3d5a99": "navy blue", "#3d6fd1": "blue",
    "#f2c230": "yellow", "#2f6b4f": "dark green", "#2b2230": "black", "#7b4fa0": "purple", "#3b2f4a": "dark purple",
    "#f08a24": "orange", "#4f9a4a": "green", "#c8b27c": "khaki", "#2bb3a6": "teal", "#8a8f99": "grey",
    "#e85d5d": "coral red", "#3a3f58": "dark grey-blue", "#9b59b6": "violet", "#6b6f7a": "grey", "#8a6d4f": "brown",
    "#6b8e23": "olive green", "#b0c4de": "light blue", "#ff9ec4": "pink", "#8b5a2b": "brown leather",
}
HAIR_NAMES = {
    "#3b2a1a": "dark brown", "#5a3825": "brown", "#2a1b14": "very dark brown", "#1b1b1b": "black",
    "#8b5a2b": "chestnut", "#ff7fbf": "bubblegum pink", "#d2691e": "ginger", "#e6c35c": "blonde",
    "#a0522d": "auburn", "#9a9a9a": "grey", "#6b4226": "brown", "#d0d0d0": "white",
}
SKIN_NAMES = {
    "#f2c29b": "fair", "#f6d7b8": "fair", "#fbe0c4": "pale", "#f1c27d": "light",
    "#e0ac69": "light brown", "#c68642": "brown", "#8d5524": "dark brown",
}
HAIR_STYLES = {"short": "short {c} hair", "long": "long straight {c} hair", "bun": "{c} hair in a bun",
               "ponytail": "{c} hair in a ponytail", "curly": "curly {c} hair", "spiky": "spiky {c} hair",
               "bald": "a bald head"}
HATS = {"cap": "a {c} baseball cap", "beanie": "a {c} bobble beanie hat with a white pompom",
        "top": "a tall black top hat", "sun": "a {c} wide-brimmed sun hat", "rain": "a {c} rain hat (sou'wester)",
        "chef": "a tall white chef's hat", "party": "a {c} cone party hat", "beret": "a {c} beret"}

# Non-character assets: key -> (subject, background, width, height).
PROPS = {
    "bench": ("a single wooden park bench with dark green metal legs", "magenta", 768, 512),
    "bin": ("a single small dark green public litter bin with a lid", "magenta", 512, 768),
    "planter": ("a single terracotta planter box with a small round bush and pink flowers", "magenta", 768, 768),
    "lamp_post": ("a single tall dark grey Victorian street lamp post with a warm yellow lamp", "green", 512, 1024),
    "bike": ("a single red bicycle standing on its kickstand, side view", "green", 768, 512),
    "sign_board": ("a single dark A-frame chalkboard pavement sign with a simple white coffee cup drawing and no writing", "green", 512, 768),
    "kiosk": ("a single small cream newspaper kiosk booth with a green and white striped roof and a window", "magenta", 768, 768),
    "food_cart": ("a single cream ice-cream cart with two wheels and a red and yellow striped parasol on top", "green", 768, 1024),
    "dog": ("a single small brown dog standing, side view", "green", 768, 512),
    "cafe_table": ("a single small round cream cafe table with two red bistro chairs", "green", 768, 512),
    "parasol_table": ("a single round cafe table with two blue chairs under a big open blue and white striped parasol", "green", 768, 1024),
    "hydrant": ("a single small red fire hydrant", "green", 512, 768),
    "mailbox": ("a single red post box on a short dark post", "green", 512, 768),
    "flower_bed": ("a single oval flower bed of brown soil with pink, yellow, white and purple flowers, seen almost from above", "green", 1024, 512),
    "bush": ("a single round leafy green bush", "magenta", 768, 768),
    "crates": ("a small stack of three wooden crates full of oranges", "green", 768, 768),
    "car_red": ("a single small rounded red city car facing right", "green", 1024, 512),
    "car_blue": ("a single small rounded blue city car facing right", "green", 1024, 512),
    "car_yellow": ("a single small rounded yellow city car facing right", "magenta", 1024, 512),
    "fountain": ("a single round stone town-square fountain with a central pedestal and a small water spout, blue water in the basin", "magenta", 1024, 768),
    "statue": ("a single grey stone statue of a man in a top hat and long coat standing on a square stone plinth", "green", 512, 1024),
    "stall_red": ("a single wooden market stall with a red and white striped awning on two posts and a counter full of oranges, lemons and tomatoes, front view", "green", 1024, 1024),
    "stall_blue": ("a single wooden market stall with a blue and white striped awning on two posts and a counter full of cabbages, plums and lemons, front view", "green", 1024, 1024),
    "stall_green": ("a single wooden market stall with a green and white striped awning on two posts and a counter full of tomatoes, eggs and oranges, front view", "magenta", 1024, 1024),
    "easel": ("a single wooden painter's easel holding a small landscape painting", "green", 512, 768),
    "duck": ("a single small white duck swimming, side view", "green", 768, 512),
    "pigeon": ("a single small grey pigeon standing, side view", "green", 768, 512),
    "cat_in_tree": ("a single small black cat crouching, side view, yellow eyes", "magenta", 768, 512),
    "tree_round": ("a single round leafy deciduous tree with a short brown trunk and a big bushy green crown", "magenta", 768, 1024),
    "tree_pine": ("a single tall conical dark green pine tree with a short brown trunk", "magenta", 768, 1024),
    "tree_blossom": ("a single round cherry blossom tree with a short brown trunk and a big pink blossom crown", "green", 768, 1024),
    # Nature museum: hideable critters (cute, small, readable silhouettes).
    "baby_trex": ("a single cute small green baby T-rex dinosaur standing on two legs, big head, tiny arms", "magenta", 768, 768),
    "baby_triceratops": ("a single cute small orange baby triceratops dinosaur standing on four legs, three little horns and a frill", "green", 768, 512),
    "baby_stegosaurus": ("a single cute small purple baby stegosaurus dinosaur standing on four legs with yellow back plates", "green", 768, 512),
    "dodo": ("a single cute plump grey-blue dodo bird standing, big hooked yellow beak, small tail tuft", "green", 512, 768),
    "mammoth_calf": ("a single cute small woolly mammoth calf standing, shaggy brown fur, little curved tusks", "green", 768, 768),
    "sabretooth_cub": ("a single cute small sandy sabre-tooth tiger cub standing, two long white fangs, dark stripes", "green", 768, 512),
    # Nature museum: scenery.
    "trex_skeleton": ("a single huge cream fossil T-rex skeleton mounted on a low dark wooden plinth, walking pose", "green", 1024, 1024),
    "mammoth_skeleton": ("a single large cream fossil woolly mammoth skeleton with long curved tusks on a low dark wooden plinth", "green", 1024, 768),
    "whale_skeleton": ("a single long cream blue-whale skeleton hanging horizontally from thin wires", "green", 1024, 512),
    "triceratops_skull": ("a single big fossil triceratops skull with three horns on a square dark wooden pedestal", "green", 768, 768),
    "display_case": ("a single glass museum display case on a dark wooden base with fossils, shells and a small skull inside", "magenta", 768, 768),
    "crystal_cluster": ("a single large purple amethyst crystal geode on a small dark plinth", "green", 512, 768),
    "rope_barrier": ("two short brass museum posts joined by a red velvet rope", "green", 1024, 512),
    "museum_bench": ("a single long dark wooden museum bench without a backrest", "magenta", 1024, 512),
    "potted_palm": ("a single tall leafy palm in a big round white pot", "magenta", 512, 1024),
    "pillar": ("a single tall cream marble classical column on a square base", "green", 512, 1024),
    "gift_shelf": ("a single wooden shop shelf unit with three shelves full of colourful plush toys and books with blank covers", "green", 768, 1024),
    "ammonite_pedestal": ("a single big spiral ammonite fossil on a slim white pedestal", "green", 512, 768),
    "dino_nest": ("a single nest of straw holding four large pale speckled dinosaur eggs", "magenta", 768, 512),
    "volcano_model": ("a single museum model volcano with orange lava streams on a small wooden table", "green", 768, 768),
    "meteorite": ("a single big dark pitted meteorite rock on a low grey stone plinth", "green", 768, 512),
}
# HUD art for the "Where's Me" picture-book theme (not in the asset catalog;
# imported to art/ui by tools/import_assets.py). key -> (subject, background, w, h).
UI = {
    "ui_magnifier": ("a single big round magnifying glass with a thick red and white striped handle and a brass rim, lens empty and clear, tilted slightly", "green", 768, 768),
    "ui_stopwatch": ("a single round old-fashioned silver stopwatch with a red button on top and a plain white face with no numbers and no hands", "green", 768, 768),
    "ui_banner": ("a single wide blank ribbon banner with folded ends, red and white diagonal stripes on the folds and a plain cream centre with nothing written on it", "green", 1024, 512),
    "ui_hat": ("a single red and white horizontally striped woolly bobble hat with a red pompom", "green", 768, 768),
    "ui_map_paper": ("a single sheet of old cream paper with slightly torn deckled edges and faint ink doodles of tiny people around the border, centre left blank", "magenta", 1024, 768),
}
BUILDINGS = {
    "building_bakery": "a two-storey bakery shop with peach walls, brown roof, red and white striped awning, big shop windows with bread, and a blank sign showing only a bread loaf picture",
    "building_cafe": "a three-storey cafe with mint green walls, dark green roof, green and white striped awning, shop windows and a blank sign showing only a coffee cup picture",
    "building_florist": "a two-storey flower shop with pale pink walls, plum roof, pink and white striped awning, flower buckets by the windows and a blank sign showing only a flower picture",
    "building_books": "a three-storey bookshop with lavender walls, dark purple roof, purple striped awning, windows full of books and a blank sign showing only a book picture",
    "building_toys": "a two-storey toy shop with pale yellow walls, red roof, blue and yellow striped awning, windows with toys and a blank sign showing only a ball picture",
    "building_grocer": "a two-storey greengrocer with pale green walls, olive roof, green and white striped awning, fruit crates at the window and a blank sign showing only an apple picture",
    "building_music": "a two-storey music shop with light blue walls, navy roof, black and yellow striped awning and a blank sign showing only a music note picture",
    "building_house_blue": "a two-storey blue townhouse with a dark slate roof, white window frames, flower boxes and a dark front door",
    "building_house_yellow": "a two-storey yellow townhouse with a brown tiled roof, window flower boxes and a brown front door",
}


def color_name(hex_color: str, names: dict) -> str:
    return names.get(hex_color.lower(), "plain")


def character_prompt(look: dict) -> str:
    build = look.get("build", "normal")
    who = {"short": "a small child", "tall": "a tall adult", "wide": "a stocky adult"}.get(build, "an adult")
    skin = SKIN_NAMES.get(look.get("skin", "").lower(), "")
    parts = [f"A single full-body person standing, {who}" + (f" with {skin} skin" if skin else "")]
    hair = HAIR_STYLES[look.get("hair_style", "short")].format(c=color_name(look.get("hair", ""), HAIR_NAMES))
    parts.append(f"with {hair}")
    if look.get("hat", "none") != "none":
        parts.append("wearing " + HATS[look["hat"]].format(c=color_name(look.get("hat_color", ""), COLOR_NAMES)))
    shirt = color_name(look.get("shirt", ""), COLOR_NAMES)
    pattern = look.get("pattern", "plain")
    if look.get("coat"):
        top = f"a {shirt} long coat"
    elif pattern == "stripes":
        top = f"a {shirt} jumper with bold horizontal {color_name(look.get('pattern_color', ''), COLOR_NAMES)} stripes"
    elif pattern == "dots":
        top = f"a {shirt} shirt with {color_name(look.get('pattern_color', ''), COLOR_NAMES)} polka dots"
    elif pattern == "overalls":
        top = f"{color_name(look.get('pants', ''), COLOR_NAMES)} dungarees over a {shirt} shirt"
    else:
        top = f"a {shirt} shirt"
    parts.append(top)
    if pattern != "overalls":
        parts.append(f"{color_name(look.get('pants', ''), COLOR_NAMES)} trousers")
    acc = look.get("accessory", "none")
    acc_c = color_name(look.get("acc_color", ""), COLOR_NAMES)
    if acc == "backpack":
        parts.append(f"a {acc_c} backpack")
    elif acc == "bag":
        parts.append(f"a {acc_c} shoulder bag")
    elif acc == "scarf":
        parts.append(f"a long {acc_c} scarf")
    elif acc == "balloon":
        parts.append(f"holding a {acc_c} balloon on a string")
    if look.get("glasses"):
        parts.append("round glasses")
    return (", ".join(parts) + ". Facing the viewer, feet visible, friendly compact proportions, "
            "clean readable silhouette, the figure fills most of the image height. ")


def build_jobs() -> dict:
    catalog = json.loads(CATALOG.read_text())["assets"]
    jobs = {}
    index = 0
    for key, entry in catalog.items():
        index += 1
        seed = 7000 + index
        if entry.get("kind") == "character":
            # People are built from the part kit (data/assets/avatar_kit.json) and
            # drawn in code; whole-body renders are no longer used. Pass
            # --characters to render reference sheets anyway.
            if "--characters" not in sys.argv:
                continue
            subject = character_prompt(entry["look"])
            # Green clothes on a green screen key poorly: use magenta for those.
            greenish = any(entry["look"].get(f, "") in ("#4f9a4a", "#2f6b4f", "#6b8e23") for f in ("shirt", "pants", "acc_color", "hat_color"))
            bg, w, h = ("magenta" if greenish else "green"), 768, 1024
            prompt = STYLE + subject + BACKGROUNDS[bg] + SUFFIX
        elif key in BUILDINGS:
            bg, w, h = "magenta", 1024, 1024
            prompt = (STYLE + "Flat front-facing elevation of " + BUILDINGS[key] + ", the whole building visible from the "
                      "pavement up to the roof, " + BACKGROUNDS[bg] + SUFFIX)
        elif key in PROPS:
            subject, bg, w, h = PROPS[key]
            camera = FRONT_CAMERA if key in FRONT_FACING else SIDE_CAMERA if key in SIDE_VIEW else CAMERA
            prompt = STYLE + camera + subject.capitalize() + ". " + BACKGROUNDS[bg] + SUFFIX
        else:
            continue
        jobs[key] = {"prompt": prompt, "seed": seed, "width": w, "height": h, "background": bg}
    for i, (key, (subject, bg, w, h)) in enumerate(UI.items()):
        prompt = STYLE + FRONT_CAMERA + subject.capitalize() + ". " + BACKGROUNDS[bg] + SUFFIX
        jobs[key] = {"prompt": prompt, "seed": 9000 + i, "width": w, "height": h, "background": bg}
    return jobs


def run_job(key: str, job: dict) -> Path:
    WORK_DIR.mkdir(parents=True, exist_ok=True)
    wf = WORK_DIR / f"{key}.json"
    shutil.copy(BASE_WORKFLOW, wf)
    prefix = f"hf_{key}"
    subprocess.run(["comfy", "workflow", "set-slot", str(wf),
                    "76.value=" + json.dumps(job["prompt"]),
                    f"75.noise_seed={job['seed']}", f"75.value={job['width']}", f"75.value_1={job['height']}",
                    "9.filename_prefix=" + json.dumps(prefix)], check=True, capture_output=True)
    started = time.time()
    res = subprocess.run(["comfy", "run", "--workflow", str(wf), "--wait"], capture_output=True, text=True)
    if res.returncode != 0:
        raise RuntimeError(f"comfy run failed for {key}: {res.stdout[-800:]} {res.stderr[-800:]}")
    candidates = sorted(COMFY_OUTPUT.glob(f"{prefix}_*.png"), key=lambda p: p.stat().st_mtime)
    if not candidates or candidates[-1].stat().st_mtime < started - 1:
        raise RuntimeError(f"no new output found for {key} in {COMFY_OUTPUT}")
    RAW_DIR.mkdir(parents=True, exist_ok=True)
    out = RAW_DIR / f"{key}.png"
    shutil.copy(candidates[-1], out)
    job["seconds"] = round(time.time() - started, 1)
    return out


def is_blank(path: Path) -> bool:
    from PIL import Image, ImageStat
    return max(ImageStat.Stat(Image.open(path).convert("L")).extrema[0]) < 8


def main() -> None:
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    jobs = build_jobs()
    if "--list" in sys.argv:
        for k, j in jobs.items():
            print(f"{k} [{j['background']} {j['width']}x{j['height']} seed {j['seed']}]\n  {j['prompt']}\n")
        return
    manifest = json.loads(MANIFEST.read_text()) if MANIFEST.exists() else {}
    keys = args or [k for k in jobs if not (RAW_DIR / f"{k}.png").exists()]
    for i, key in enumerate(keys, 1):
        job = dict(jobs[key])
        try:
            path = run_job(key, job)
            if is_blank(path):
                # Seen once at 640px width: an all-black (NaN) render. Retry with another seed.
                print(f"[{i}/{len(keys)}] {key}: blank render, retrying with seed {job['seed'] + 100}", flush=True)
                job["seed"] += 100
                path = run_job(key, job)
                if is_blank(path):
                    raise RuntimeError("render is blank twice")
        except Exception as exc:  # report and continue with the rest of the batch
            print(f"[{i}/{len(keys)}] FAILED {key}: {exc}", flush=True)
            continue
        job.update({"workflow": "art_src/workflows/flux2_klein_4b_base_only.json",
                    "model": "flux-2-klein-base-4b.safetensors", "raw": str(path.relative_to(ROOT)),
                    "generated_at": time.strftime("%Y-%m-%d %H:%M:%S")})
        manifest[key] = job
        MANIFEST.write_text(json.dumps(manifest, indent=1))
        print(f"[{i}/{len(keys)}] {key} done in {job['seconds']}s", flush=True)


if __name__ == "__main__":
    main()
