# POC notes: architecture, tests, limitations, next steps

## Status against the brief
| Milestone | State |
|---|---|
| M0 Inspect | Done. The repo started empty. Godot 4.5.1. ComfyUI running locally with FLUX.2 Klein 4B base. Blender MCP was available but not needed. |
| M1 Scene foundation | Done. Authored 3200×2200 town (shops and fountain plaza, park with pond, market, houses and gardens), camera with pan and zoom. |
| M2 Hide/search loop | Done. Avatar creator (part kit), free placement with a live visibility readout and drag to adjust, search with correct/wrong feedback, give up, result, retry and swap roles. |
| M3 Depth and occlusion | Done. A single Y-sorted `World` with ground-point origins. Tree crowns, stall awnings and parasols are a raised canopy layer. Ground decals sit below. |
| M4 Seeded dressing | Done. Per-zone and per-path RNG streams, minimum spacing, density targets, stable IDs, golden-hash test. |
| M5 Challenge persistence | Done. Schema v2: `HF1-` share code (base64url JSON) carrying the hider's name and look plus the exact position. Raw JSON paste and files in `user://challenges/` also work. |
| M6 Polish/validation | Done. Generated art set, docs, and 18 automated tests. |
| 2026-10-24 | Renamed to **Where's Me** (`WM1-` codes, `HF1-` still decodes). Search intro card + Start, running clock top centre. Selfie → avatar in the web build (MediaPipe JS + `PhotoToLook`). **Nature museum** map with critter hiding (schema v3). Picture-book HUD theme. Web export preset + `tools/publish_itch.sh`. |

## Architecture
```
AppState (autoload)          mode + current challenge; all scene changes go through it
MapDefinition  ◄── data/maps/town_demo_01.json   authored, stable: bounds, ground paint,
                                                  zones, paths, blocked areas, fixed objects
AssetCatalog   ◄── data/assets/asset_catalog.json  kinds, radii, occluders, looks, textures
AvatarKit      ◄── data/assets/avatar_kit.json     part kit: fields, palettes, crowd weights, presets
TownGenerator.generate(map, seed) -> TownLayout   pure function, no scene access
    WorldObjectData[]  (id, asset_key, world_position=ground point, depth_mode, tags,
                        occlusion_role, is_interactive, flip_h, look, source)
VisibilityChecker + MaskCanvas      the 70%-visible hide rule, CPU-measured with the real drawing code
TownController       builds GroundLayer + a Y-sorted World of CharacterActor/PropActor;
                     spatial query character_at(); owns no game rules
HideController / SearchController   game rules per mode; talk to HideHud / SearchHud
ChallengeData + ChallengeCodec      versioned JSON (v2), share code, files, validation
Avatar creator (scripts/ui/avatar_creator.gd)   UI generated from the kit; saved to user://my_avatar.json
MapCamera                           pan, zoom, pinch; tap vs drag; screen_to_world()
MapDebugOverlay                     F1: zones, paths, blocked areas, IDs, depth order
```
Key decisions:
- **Hand-authored base plus seeded dressing.** Roads, buildings, the pond, market stalls, landmarks and visual jokes are fixed in JSON. The seed only affects props, crowd looks and positions. Each zone and path has its own RNG stream (`DetHash.sub_seed(seed, zone_id)`), so editing one zone doesn't move objects in another. Positions are integer-snapped. The global RNG is never used for map data, and a test enforces this.
- **One part kit for everyone.** `AvatarKit.random_look(rng)` builds each crowd member from the same parts the player uses in the creator. It consumes exactly one RNG value per field in `field_order`, with per-value crowd weights, so changing the kit's fields, palettes or weights changes every crowd. When that happens, bump `TownGenerator.GENERATOR_VERSION`. If a crowd member is an exact twin of the hider, `TownController.ensure_unique()` changes their top colour deterministically, so hider and seeker see the same crowd.
- **Hide rule: anywhere, at least 70% visible.** `VisibilityChecker` samples the avatar every 2 px using the real `PlaceholderArt.draw_character()` code drawn into a `MaskCanvas`, a CPU stand-in that implements the CanvasItem draw calls the art uses and textured sprites' alpha. It then draws everything that renders on top into the same mask: people and props standing in front (larger feet y), foreground-layer props, and every canopy (tree crowns, awnings, parasols). Soft shadows (alpha < 0.5) don't count. The fraction left uncovered must be ≥ 0.70. There are no walkable-area or "too exposed" rules; the only other check is that the body is inside the world bounds. A check costs about 4.5 ms in the crowded plaza, so it runs live while dragging.
- **Challenge = map_id + map_version + generator_version + seed + hider + position.** The map isn't serialised; it's regenerated. The hider's look is validated against the kit on import. Search mode re-runs the visibility rule at the stored spot and refuses the challenge if it fails, which catches most map or generator mismatches with a clear message.
- **Depth.** Every object's node origin is its ground point. One `y_sort_enabled` node holds people, props, trees and building facades. Foreground parts (tree crowns, stall awnings, parasols) are children with `z_index = 20`, so they cover the heads of people underneath while their legs stay visible. Flower beds and ducks are ground decals (`z_index = -1`). In hide mode canopies stay opaque, so the hider sees exactly what the seeker will.
- **Art is data-driven.** People are always drawn in code from their look. All 39 scenery assets (props, trees, stalls, cars and the 9 shop and house fronts) are painted sprites from the ComfyUI pipeline (`docs/ART_STYLE.md`). The ground is still code-painted. Deleting an asset's `texture` field falls back to its code-drawn placeholder.
- **Taps** only consider people (`is_interactive`). Props, animals and decals never count. The front-most person (largest feet y) under the tap wins. Hit areas grow by a few screen pixels, scaled by zoom. In hide mode, a press on your own avatar drags it (`MapCamera.drag_interceptor`); any other press pans the map.

## Data sizes (seed 481516)
631 objects, of which 441 are people, and 0 generator shortfalls.

## Tests
Run `godot --headless --path . -s res://tests/run_tests.gd`. Last run: **25 passed, 0 failed**, exit code 0.

| Suite | Tests |
|---|---|
| test_map_determinism | Same seed gives an identical signature (IDs, asset keys, positions, flips, crowd looks). The global RNG is reseeded between runs and doesn't leak in. Fresh map loads match. Different seeds change only dressing; fixed objects never move. IDs are unique and positions integer. Crowd looks are valid and almost all distinct. **Golden SHA-256** of seed 481516. |
| test_challenge_codec | Round trip by share code (including whitespace from chat apps), JSON and file. Every field is preserved, including name, look, seed and exact position. Long names are clamped. 17 kinds of malformed input are rejected with a message (old or new schema, bad look part or value, …). Search verification catches map-version and generator mismatches, spots buried behind buildings, and off-map spots. |
| test_visibility | Open ground is 100% visible, with no "too exposed" rule. The avatar mask is a sane size. Under a tree crown: rejected. A person 30 px in front: rejected, and the reason quotes the percentage. A person behind doesn't count. A bench in front covers only the legs: allowed. Behind a shop facade: about 0%. Flat flower beds never cover. Off-map is rejected. Performance stays under 50 ms per check (measured 4.5 ms). |
| test_scene_runtime | Real `town_demo.tscn`: screen→world→tap hits the target at 4 pan and zoom combinations. A wrong tap counts but doesn't win; a correct tap wins. Y-sort and ground-point origins, canopy layers and decals are checked. Three restarts leave no duplicates and exactly one target. A crowd twin of the hider gets a different look. Hide mode: no avatar before the first tap; a buried spot is invalid and Confirm is refused; the pond is allowed when visible; whole-pixel snapping; Confirm builds a challenge that verifies for the seeker. |

Visual checks were done with the `--shot` developer flag: creator, hide mode at a valid spot (77%) and an invalid one (54%), share dialog, search, found result, and the debug overlay at overview zoom.

## Museum mode (critters)
- `MapDefinition.hide_subject` is `"critter"` for the museum. `TownGenerator.critter_for_seed()` picks the hidden critter from the seed, and the challenge stores it (`hider.critter`, schema v3) so verify can reject a mismatch.
- Critters are props with `kind: "critter"`; their tap areas come from their sprite rect. Generated critters get `WorldObjectData.hue` (one extra RNG value, drawn only for critters, so maps without critters keep their RNG streams and the town's golden hash is unchanged). The hidden critter is spawned with hue 0.
- `VisibilityChecker.check_subject()` measures any subject (avatar or critter sprite) with the same 70% rule. `WorldActor` is the shared base of `CharacterActor` and `PropActor` (markers, hit rects, wrong-tap flash).

## Known limitations
- **Not anti-cheat.** The share code contains the answer in plain base64; this is a local POC.
- **Draw order is verified structurally only.** Y-sort correctness is checked through node setup (sorted parent, ground-point origins, canopy z) and by eye in screenshots, not by pixel comparison, because headless Godot doesn't render.
- **Building facades are single sprites.** Characters behind a facade are hidden by it, which the visibility rule accounts for, and characters overlapping its base are drawn in front, which is correct for a front-facing street.
- **Generated art varies in proportion** between characters. Every sprite is normalised to the same in-game height per build, but widths differ. Re-render any outlier with `tools/gen_assets.py <key>` after tuning its prompt.
- **One map**, no movement, no audio, no mobile export preset. Pinch zoom is implemented (touch and trackpad) but only tested on desktop.
- **`user://` paths are per OS user.** "Load latest saved" only sees challenges on the same device; the share code is the cross-device path.
- **Wrong-tap limit** is supported by the data (`rules.wrong_tap_limit`) but has no UI to set it; it defaults to 0, meaning unlimited.
- **People are code-drawn.** The part kit is rendered in code; a painted part kit (layered sprites per part) is the next art step. Whole-body generated characters from the first art pass are kept in `art_src/reference_characters/` as style reference only.
- **v1 challenge codes are rejected.** They used preset avatars and hide points; there were no real users, so there's no migration.

## Next steps (roadmap)
1. **Movement (phase A/B).** Pedestrians follow the authored `paths` (data already in the map; `MapPath.point_at()` exists). Add `simulation_version` and a fixed tick to the challenge so the hider's position is reproducible on every device.
2. Hosted challenges and share links. The codec already produces a URL-safe string.
3. More maps; a path and zone authoring overlay (draw polylines in the debug view and save them to the map JSON).
4. Painted part kit for people (layered sprites per part on a shared body template), keeping the code-drawn kit as fallback.
5. Hint system (for example "near something red"); difficulty rating from visibility and crowd density around the hider.
6. Mobile polish: export presets, larger tap targets at minimum zoom, haptics.
