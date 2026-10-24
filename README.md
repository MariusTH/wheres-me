# Where's Me (Godot POC)

A hidden-object game in the style of *Where's Waldo*, with a social twist. You build your own avatar, hide it anywhere in a crowded, hand-drawn town (at least 70% of it must stay visible), send the puzzle to a friend as a code, and they search the map to find you. In the **nature museum** you hide a critter instead (the seed picks which: baby T-rex, dodo, mammoth calf, …) among look-alikes in other colours.

This is a local-first proof of concept: it has no backend, no accounts and no networking. Challenges travel as share codes (`WM1-…`; older `HF1-` codes still work). It ships as a web build on itch.io: https://parchnipp.itch.io/wheres-me.

## Requirements
- Godot **4.5.x** (developed with 4.5.1-stable), standard build. No plugins are needed.
- Optional, only for regenerating art: ComfyUI running locally with FLUX.2 Klein 4B base, plus Python 3 with Pillow and numpy. See `docs/ART_STYLE.md`.

## Publish to itch.io (web build)
```bash
tools/publish_itch.sh --dry-run   # export to build/web only
tools/publish_itch.sh             # export + butler push to parchnipp/wheres-me:html5
```
Needs the Godot 4.5.1 web export templates and `butler login` once. The build is single-threaded, so itch.io's SharedArrayBuffer option is not needed. To test locally: `python3 -m http.server 8765 --directory build/web`, then open http://localhost:8765.

## Selfie avatar (web build only)
In the avatar creator, **Look like me (selfie)** lets the player pick a photo, or take one on a phone. MediaPipe runs in the browser (`web/selfie.js`, loaded through `JavaScriptBridge`) and segments hair, skin and clothes and finds face landmarks. `PhotoToLook` (`scripts/selfie/`) then maps those measurements onto the part kit: nearest palette colour in Lab space, hair style from the hair-mask shape, glasses and hat from the accessory regions. The photo never leaves the device. The models (about 20 MB) download from Google's CDN the first time the button is used. iOS Safari only opens a file picker inside a real tap, so Godot registers the button's screen rect and a JavaScript tap listener opens the picker. The mapping thresholds are tuned on very few photos so far.

## Run
**From the editor:** open the folder in Godot (Import → select `project.godot`), then press **F5**.

**From the command line** (macOS path shown):
```bash
GODOT=/Applications/Godot.app/Contents/MacOS/Godot
$GODOT --path .            # play
$GODOT --path . --editor   # open the editor
```
On the first launch, run `$GODOT --headless --path . --import` once (or open the editor) so the PNGs get imported.

## How to play the hide → search loop
1. **Main menu → "Create avatar" (or "Hide yourself").** In the avatar creator, build your look from parts: skin, body, hair, hat, top, pattern, trousers, an extra, and glasses. You can start from a preset or hit **Randomize**, then type the name the seeker will see. **Hide me!** saves your avatar (`user://my_avatar.json`) and opens the town. Next time, "Hide yourself" goes straight to the town.
2. **Tap anywhere on the map** to put yourself there; the tap marks your middle. **Drag yourself** to fine-tune. Dragging anywhere else pans the map.
3. The panel shows **Visible: NN%** live. You may hide anywhere, even in the pond or among the market stalls, as long as **at least 70% of you is visible** in the rendered scene. Tree crowns, awnings, people standing in front of you and buildings all count as cover.
4. **Confirm hiding spot.** The share dialog shows an `WM1-…` code. **Copy code** puts it on the clipboard, and a JSON copy is saved under `user://challenges/`.
5. Either press **Search now (pass the device)**, or have a friend paste the code on the main menu (**Paste** → **Search for them!**). **Load latest saved** opens the newest saved file.
6. **Search.** A big card shows who you're looking for (the map stays hidden behind it). Press **Start** to start the clock, which runs at the top centre and turns orange and then red, pulsing each second, after 1 and 2 minutes. The card at the top left keeps showing the hider's look and name. Tap people; wrong guesses flash red and count. **Give up** reveals the hider.
**Museum mode.** **Hide the … in the museum** on the menu skips the avatar: the seed picks a critter, and you place it anywhere in the nature museum (fossil gallery, great hall under the T-rex and the hanging whale, minerals room, gift shop) with the same 70% rule. The seeker taps critters, not visitors. Every other critter is a hue-shifted look-alike, so the one with the original colours is the right one. A new seed means a new critter and a new museum dressing.

7. **Result.** You get time, taps and wrong guesses, plus **Retry**, **Swap roles: you hide**, or **Menu**.

## Controls
| Action | Mouse / keyboard | Touch |
|---|---|---|
| Pan | Drag (left, right or middle button) | Drag |
| Zoom | Mouse wheel, or trackpad pinch | Pinch |
| Select / guess / place | Click without dragging | Tap |
| Move your avatar (hide mode) | Drag the avatar | Drag the avatar |
| Debug overlay | **F1** cycles: zones, paths, blocked areas and hide points → plus object IDs and depth order → off | |

## Tests
```bash
$GODOT --headless --path . --import            # once, or after adding files
$GODOT --headless --path . -s res://tests/run_tests.gd
```
The run prints PASS/FAIL per test and exits with code 0 only when everything passes. Coverage includes determinism (including a golden hash), challenge round trips (code, JSON and file), malformed input, the 70% visibility rule, tap selection after pan and zoom, depth setup, crowd twins of the hider and scene restarts. See `docs/POC_NOTES.md`.

## Developer flags
Pass these after `--`, for example `$GODOT --path . -- --mode=search --preset=2 --at=1000,700`.

| Flag | Effect |
|---|---|
| `--mode=create\|hide\|search\|debug` | Skip the menu |
| `--map=town_demo_01\|museum_01` | Map for hide, debug and `--at` |
| `--seed=N` | Town seed for hide or debug |
| `--preset=N` | Use avatar preset N (0–7) as your avatar |
| `--challenge=PATH_OR_CODE` | Challenge to search |
| `--at=X,Y` | Build a search challenge on the fly with the hider's feet at X,Y |
| `--place=X,Y` / `--confirm` | Script the hide mode (feet position) |
| `--center=X,Y --zoom=Z` | Initial camera view |
| `--debug=1\|2` | Overlay level |
| `--start` | Search: skip the intro card and start the clock |
| `--tap=X,Y` | Simulate a tap at world coordinates (implies `--start`) |
| `--shot=out.png [--shot-delay=2.5]` | Save a screenshot and quit (needs a window, so not `--headless`) |

## Project layout
```
scenes/       main_menu, town/town_demo, ui/avatar_creator, ui/*_hud, actors/character, props/prop_base
scripts/      app_state (autoload) · town/ (map data, generator, visibility checker, controller, ground)
              actors/ props/ (rendering) · gameplay/ (hide/search, challenge data + codec)
              camera/ debug/ ui/ util/
data/maps/    town_demo_01.json   authored layout, zones, paths, blocked areas, fixed objects
data/assets/  avatar_kit.json     part kit for avatars and the crowd (fields, palettes, weights, presets)
              asset_catalog.json  scenery assets: kind, radius, occluders, params, texture
art/          cleaned game sprites (generated)   art_src/  raw renders, prompts, workflow
tests/        headless test runner + suites
tools/        gen_assets.py (ComfyUI), import_assets.py, clean_sprite.py
docs/         ART_STYLE.md, ASSET_LICENSES.md, POC_NOTES.md
```
