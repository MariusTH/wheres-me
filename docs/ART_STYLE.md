# Art style: Where's Me POC

## Direction
A colourful, hand-drawn, slightly wonky town in the style of a children's picture book (delicate ink linework and soft
pastel watercolour), seen at **2:1 isometric**. Ground, buildings and props share that one camera, so the town reads
as one place rather than front-view houses pasted on a top-down road. Characters have readable silhouettes and
expressive outfits. The goal is composition and readability at phone scale, not matching any existing game.

## People
Every person (the player's avatar and the whole crowd) is drawn in code from a part-kit look
(`data/assets/avatar_kit.json`, rendered by `PlaceholderArt.draw_character`) in the same storybook manner: fine brown
ink, kit colours softened slightly towards paper (the hue stays, so clues like "red hat" still work), tapered limbs,
A-line clothes, a shadow wash on the right and a small per-look lean. This is what makes the creator and the "blend
into the crowd" mechanic work. A painted part kit (each part generated on a shared body template and layered) is a
possible next step.

## Rules
| Aspect | Rule |
|---|---|
| Camera | 2:1 isometric, 30° from above, for buildings, props and ground. Things that face somewhere face the lower left. Trees, bushes, lamps, hydrants, mailboxes and animals read the same from any angle and are shared as they are. |
| Outline | Scratchy dark brown ink with fine hatching, slightly irregular. |
| Palette | Muted pastel washes with a few gentle accents. The ground stays desaturated so people pop. |
| Light | Soft daylight from the upper left. No baked cast shadows on sprites; the ground layer paints soft shadows. |
| Scale (game px) | Adult 62 (tall 68, child 50). Bench 34. Tree 150. Stall 108. House plot 224 corner to corner (112 plan px), small buildings 160 (80). |
| Text | No text or pseudo-text anywhere. Shop signs carry pictograms only. |
| Background | Every sprite is isolated on flat chroma: bright green, or magenta for green-heavy subjects. Keyed with `tools/clean_sprite.py`. |
| Ground point | Feet or base, bottom-centre of the opaque pixels; for buildings, the slab's bottom corner. Recorded in the catalog. |

## The isometric town (town_iso)
- **Ground** stays on a flat plan. `GroundLayer` tiles the painted textures (`ground_road`, `ground_pavement`,
  `ground_grass`, `ground_plaza`, `ground_market`; rendered square, made tileable by `tools/make_tileable.py` and toned
  down by `GROUND_GRADE` in `tools/import_assets.py`) and draws them through the map's `projection` transform, so the
  cobbles foreshorten correctly. Keep the values spread: road darkest, grass mid, pavement lightest. It inks a wobbly
  line along every edge between ground types, lays a stone kerb along roads, gives kerbs facing the viewer a 6 px face
  (`KERB_HEIGHT`) so pavements read as raised, and paints soft shadows. `PaperOverlay` multiplies a faint paper grain
  over everything.
- **Buildings** (`ISO_BUILDINGS`, `ISO_SMALL_BUILDINGS` / `ISO_CAMERA` in `tools/gen_assets.py`) are crooked pastel
  houses and shops (`WONKY_STYLE`), door on the lower-left wall, each standing on a small square paved slab. On import
  the slab's corners are measured and the sprite is scaled so the slab spans exactly its plot diamond (`ISO_PLOT` =
  112, `ISO_SMALL_PLOT` = 80 plan px). The catalog gets `"footprint"`.
- **Depth**: a footprint can't be Y-sorted by one point, so buildings are drawn as 12 px vertical slices
  (`AssetCatalog.strips`), each sorted at the footprint's front edge below it. `VisibilityChecker` uses the same
  slices, so the 70% rule matches what is drawn.
- **Variety**: the building pool is bigger than one town needs; each seed uses a subset (`house_subset` and
  `plots.small_subset` in town_iso.json). Adding a building changes which subset a seed picks, so bump `map_version`.
  House rows mix houses, small buildings and garden gaps, and plots shift sideways and back a little. Every house
  keeps a narrow alley either side (good hiding spots), and nobody stands within `PLOT_MARGIN` of a wall.
- **Props** (`ISO_PROPS`, `ISO_EXTRA_PROPS`) use `WONKY_PROP_STYLE` + `ISO_PROP_CAMERA`; each row carries its in-game
  size, placement radius and kind. Bins (wheelie bins, skip, dustbin), sheds, outhouses, washing lines, wells, big
  weird birds and the like give cover to hide beside. Cars drive down-left; `WfcTown` mirrors them on lanes running
  down-right. `SHARED_PROPS` (trees, bush, lamp post, hydrant, mailbox, duck, dog, pigeon) use the same style with a
  three-quarter camera; `SHARED_PROP_EXTRA` adds colour direction where pale washes made one vanish.
- Only the part of the town on screen is dressed: zones are clipped to the view and their crowd and props scaled to
  the visible share.

## Model and workflow
- ComfyUI template `image_flux2_klein_text_to_image`, reduced to the **FLUX.2 Klein 4B base** branch: `art_src/workflows/flux2_klein_4b_base_only.json`. It runs 20 steps at CFG 5. The template's distilled-model branch was removed because that model isn't installed.
- Isometric props render at 768², buildings at 1024², shared props and HUD art at 512–1024 depending on aspect. Expect about 110 s per prop and 180–200 s per building on an M4 Max.
- The `MinimalistVectorArtKlein4B` LoRA is installed but **not used**. A flat-vector look conflicts with the hand-drawn direction.
- A 640 px-wide render once came back all black (NaN). `gen_assets.py` detects blank output and retries with another seed.

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
The UI belongs to the town, not to a holiday: cream paper panels with soft shadows, warm brown ink outlines, sage
(`UiKit.GOOD`, the main action on every screen) and terracotta (`UiKit.ACCENT`, headings and "find them"), dusty
plum for secondary buttons, a chunky display font (Luckiest Guy) for titles and buttons. Headings sit on a
hand-drawn hanging signboard (`UiKit.banner`, code-drawn so it fits any width), sections are split by a wobbly ink
line (`UiKit.divider`), and menu screens sit on a painting of the real town (`UiKit.backdrop`, `art/ui/menu_town.jpg`,
captured with `--mode=debug --seed=7 --hud=0 --shot=…`). Painted HUD art in `art/ui/`: a magnifying glass with a
wooden handle (the "find this" card shows the target inside its lens) and a stopwatch next to the search clock.
Prompts are in `UI` in `tools/gen_assets.py` (rendered with `WONKY_PROP_STYLE`); import with
`python3 -I tools/import_assets.py ui_magnifier …` (writes `art/ui/`, not the catalog). Theme code:
`scripts/ui/ui_kit.gd`. If you re-render the magnifier, re-check `LENS_CENTER`/`LENS_RADIUS`. These are original
motifs; don't copy Where's Wally characters or artwork.
