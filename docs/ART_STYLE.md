# Art style: Where's Me POC

## Direction
A colourful, hand-drawn, slightly irregular town in the style of a children's picture book (ink and watercolour), seen from a **high, shallow top-down / three-quarter angle**. Characters have readable silhouettes and expressive outfits. The goal is composition and readability at phone scale, not matching any existing game.

## People
Every person (the player's avatar and the whole crowd) is drawn in code from a part-kit look (`data/assets/avatar_kit.json`, rendered by `PlaceholderArt.draw_character`). This is what makes the creator and the "blend into the crowd" mechanic work. The palettes in the kit are the colour rules for clothing, skin and hair.

The first art pass generated whole-body characters with ComfyUI. They're kept in `art_src/reference_characters/` as style reference only, because a fixed full-body image can't be customised. The planned next step is a painted part kit: each part generated on a shared body template and layered.

## Rules
| Aspect | Rule |
|---|---|
| Camera | Shallow top-down three-quarter for props, people and trees. Buildings are flat front elevations, because their bases line the street. |
| Outline | Dark ink (`#2b2230`), slightly irregular, about 1.5–2 px at gameplay scale. |
| Palette | Warm, muted city colours with a few saturated accents (red, yellow, teal, orange). The ground stays desaturated so people pop. |
| Light | Soft daylight from the upper left. No baked cast shadows on sprites; the engine draws a soft ellipse under each person and prop. |
| Scale (game px) | Adult 62 (tall 68, child 50). Bench 34. Tree 150. Stall 108. Building about 210–230 wide. |
| Text | No text or pseudo-text anywhere. Shop signs carry pictograms only. |
| Background | Every sprite is isolated on flat chroma: bright green, or magenta for green-heavy subjects. Keyed with `tools/clean_sprite.py`. |
| Ground point | Feet or base, bottom-centre of the opaque pixels. Recorded in the catalog. |

## Comfy style block (used verbatim as the prompt prefix)
```
STYLE: original, colourful hand-drawn hidden-object game illustration, children's picture book
ink and watercolour, slightly irregular dark ink outline, flat warm muted colours with a few
saturated accents, soft daylight from upper left.
```
Each asset adds a subject sentence plus `Isolated single subject centred, on a plain flat solid pure bright green (or magenta) background, no ground shadow, no text, no letters, no labels, no border, no frame, no other objects.`

Exact prompts and seeds per asset are in `art_src/manifest.json`. The prompt builder is `tools/gen_assets.py`. It skips people unless you pass `--characters`, which renders whole-body reference images from the catalog looks.

## Model and workflow
- ComfyUI template `image_flux2_klein_text_to_image`, reduced to the **FLUX.2 Klein 4B base** branch: `art_src/workflows/flux2_klein_4b_base_only.json`. It runs 20 steps at CFG 5. The template's distilled-model branch was removed because that model isn't installed.
- Characters render at 768×1024, props at 512–1024 depending on aspect, buildings at 1024². Expect about 60–110 s per image on an M4 Max.
- The `MinimalistVectorArtKlein4B` LoRA is installed but **not used**. A flat-vector look conflicts with the hand-drawn direction.
- A 640 px-wide render once came back all black (NaN). `gen_assets.py` detects blank output and retries with another seed.
- The three-quarter camera prompt made objects with a clear front (stalls, kiosk, benches, cafe tables, the food cart, cars) come out rotated diagonally, which clashed with the square-on shop fronts. They are rendered with `FRONT_CAMERA` (cars with `SIDE_CAMERA`) instead; see `FRONT_FACING` in `tools/gen_assets.py`.

## Pipeline
1. `python3 -I tools/gen_assets.py [keys]` writes the raw render to `art_src/raw/<key>.png`, and the prompt, seed, size and timing to `art_src/manifest.json`.
2. `python3 -I tools/import_assets.py [keys]` keys, defringes, crops and scales each render to 2× game size in `art/...`. It splits tree crowns, stall awnings and parasols into `*_canopy.png`, which go on the foreground occluder layer. It then writes `texture`, `ground_point`, `height_px` and derived occluder shapes into the catalog.
3. Open Godot (or run `--import`) to import the new PNGs.

Sources (`art_src/`, excluded from Godot import by `art_src/.gdignore`) and cleaned game assets (`art/`) are kept separate. To fall back to placeholder art for an asset, delete its `texture` field from the catalog. The game then draws the code placeholder from `look`/`params`.

## Acceptance checks
Review screenshots at default search zoom (1.0) and at the minimum zoom:
- A person is recognisable at the default zoom.
- People differ by silhouette, outfit and colour, not only by tiny facial detail.
- No text or pseudo-text appears on signs.
- There's no green or magenta fringe, clipped outline or excess canvas.
- There are no duplicate objects inside one sprite and no conflicting baked shadows.
- The scene stays coherent with hundreds of sprites.

## Where's Me HUD theme
The UI is a picture-book "search party": red-and-white candy stripes, cream paper with ink outlines, a chunky display font (Luckiest Guy) for titles and buttons, and painted props in `art/ui/`: a striped magnifying glass (the "find this" card shows the target inside its lens), a stopwatch next to the search clock, a blank striped ribbon banner for headings, a striped bobble hat, and a torn paper sheet as the menu background. These are original motifs; don't copy Where's Wally characters or artwork. Prompts are in `UI` in `tools/gen_assets.py`; import with `python3 -I tools/import_assets.py ui_magnifier …` (writes `art/ui/`, not the catalog). Theme code: `scripts/ui/ui_kit.gd` (`banner`, `magnified`, `icon`, `stripes`, `title`). If you re-render the banner or the magnifier, re-check `BANNER_TEXT_AREA` and `LENS_CENTER`/`LENS_RADIUS`.

## Nature museum
Interior map (`data/maps/museum_01.json`): walls are flat ground bands, and floors are code-painted (`marble`, `parquet`, `stone`, `carpet`). Exhibits are front-facing sprites. The whale skeleton is a `foreground` prop hanging over the great hall. The six hideable **critters** (`kind: "critter"`) are cute, side-on and smaller than people (26–38 px). The seed picks which critter is hidden; every other critter is a decoy whose colours are hue-shifted by `shaders/hue_shift.gdshader` (at least a quarter turn, so a decoy never stays in the same colour family), so only the hidden one has its original colours.
