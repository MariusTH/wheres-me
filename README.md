# Where's Me (Godot POC)

A hidden-object game in the style of *Where's Waldo*, with a social twist. You build your own avatar, hide it anywhere in a crowded, hand-drawn town (at least half your head and 70% of you must stay visible), send the puzzle to a friend as a code, and they search the map to find you.

This is a local-first proof of concept: it has no backend, no accounts and no networking. Challenges travel as share codes (`WM1-…`; older `HF1-` codes still work). It ships as a web build on itch.io: https://parchnipp.itch.io/wheres-me.

## Game modes
- **Play with friends** (Friends screen): **Send a game** (pick a difficulty, hide, share the code), **Play with random**, and a box for codes friends send you. Each game shows whose turn it is (find them / hide and send back / waiting), rounds played, wins, and fastest and average find times. Codes carry the sender's player id, the round, and their result on the code they answer, so the loop works with no server (`FriendsStore`, `scripts/social/`). "Play with random" goes through `Matchmaker`. Until matchmaking is online it pairs you with a practice partner: a computer player who hides with `AutoHider` and gets a simulated search time on your spots.
- **Daily challenge**: the same town and hider for everyone each day (seed from the date). It ramps through the week: Monday easy, Saturday expert. Only the first try counts. Your best score and streak show on the menu (`Progress`). Scores go through the `Leaderboard` seam, which only stores locally for now.
- **Play**: pick Easy / Normal / Hard / Expert and the computer hides someone. Each level sets the town size (S/M/L/XL), how hidden the person is, how much of the head must show, and how many look-alike decoys are in the crowd (`Difficulty`). The design reasoning is in [wherewally.md](wherewally.md).

## Requirements
- Godot **4.5.x** (developed with 4.5.1-stable), standard build. No plugins are needed.
- Optional, only for regenerating art: ComfyUI running locally with FLUX.2 Klein 4B base, plus Python 3 with Pillow and numpy. See `docs/ART_STYLE.md`.

## Publish to itch.io (web build)
```bash
tools/publish_itch.sh --dry-run   # export to build/web only
tools/publish_itch.sh             # export + butler push to parchnipp/wheres-me:html5
```
Needs the Godot 4.5.1 web export templates and `butler login` once. The build is single-threaded, so itch.io's SharedArrayBuffer option is not needed. To test locally: `python3 -m http.server 8765 --directory build/web`, then open http://localhost:8765.

## Publish to TestFlight (iOS)
```
tools/publish_testflight.sh              # build, archive, upload to App Store Connect
tools/publish_testflight.sh --no-upload  # build, archive, export the .ipa to build/ios/ipa only
VERSION=1.0.1 tools/publish_testflight.sh
tools/run_ios_sim.sh ['wheresme://play?c=WM1-…']   # Simulator build (x86_64/Rosetta: slow), optional deep link
```
App "Where's Me?" (Apple ID 6834707882, bundle `com.caboodle.app`, team 5LMLNW3DV5). Needs Xcode, the Godot 4.7.2 iOS export templates, and either your Apple ID signed in under Xcode > Settings > Accounts or an App Store Connect API key (`ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_PATH`). The build number is a UTC timestamp, so every upload is new. Exporting iOS from the editor needs `tools/build_ios_native.sh` first.

Native glue: `native/ios/WMNative.m` (linked by `addons/wm_ios_native`) opens the iOS share sheet (`NativeShare`) and receives `wheresme://play?c=WM1-…` deep links (`DeepLink`). Shared messages end in such a link: tapping it opens the app straight into that challenge; pasting the whole message still works. On desktop: `godot --path . -- --link='wheresme://play?c=WM1-…'`.

Debug console: shake the phone, tap with three fingers, or press F12 (desktop; or start with `-- --console`). It shows device/app info, recent logs and the native iOS log, with Copy / Share for sending to a developer.

Branding: `python3 -I tools/gen_assets.py app_icon_1 splash_1` renders with ComfyUI (see BRANDING in that script), `python3 -I tools/make_branding.py` writes the icon, launch screen / boot splash and itch.io cover to `art/branding/`.

## Phones
The game is portrait-only: phones lock to portrait, the desktop window opens at 450×800, and the itch.io embed should be set to a portrait size (e.g. 450×800, with fullscreen allowed). The UI scales by the screen's shorter side: desktop windows keep the 1280×720 design size, and phones get 480 UI units across the short side, so buttons are about 44 px, Apple's minimum touch size (`AppState._apply_ui_scale`). Below 700 units wide (phone in portrait) screens switch to stacked layouts: the creator gets a compact header, the hide panel becomes a bottom sheet, and the search clock gets its own row. Below 600 tall (phone in landscape) the intro card goes side by side. Screens rebuild when the phone rotates (`AppState.layout_changed`). Try it on desktop with `$GODOT --path . --resolution 393x852`.

iOS Safari only allows the clipboard, the share sheet and the photo picker inside a real tap, and Godot handles input a frame later. Those buttons are `WebTap`s (`scripts/ui/web_tap.gd` + `web/web_tap.js`): Godot registers the button's screen rect, and a browser tap listener runs the action. That covers **Paste** (menu), **Copy code** and **Share…** (share dialog; Share uses the native share sheet when the browser has one), and the selfie picker. Typing uses the web export's virtual-keyboard option; the export's head include forces 16 px inputs so iOS doesn't zoom on focus. The menu's code box is a real browser textarea laid over the Godot one (`WebField`, `scripts/ui/web_field.gd`), so long-press → Paste works. Pasted text can be the whole share message; the decoder finds the `WM1-` code in it.

## Selfie avatar (web build only)
In the avatar creator, **Look like me (selfie)** lets the player pick a photo, or take one on a phone. MediaPipe runs in the browser (`web/selfie.js`, loaded through `JavaScriptBridge`) and segments hair, skin and clothes and finds face landmarks. `PhotoToLook` (`scripts/selfie/`) then maps those measurements onto the part kit: nearest palette colour in Lab space, hair style from the hair-mask shape, glasses and hat from the accessory regions. The photo never leaves the device. The models (about 20 MB) download from Google's CDN the first time the button is used. The picker opens through `WebTap` (see Phones above). The mapping thresholds are tuned on very few photos so far.

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
1. **Main menu → "Create" next to your avatar (or "Hide in this town").** In the avatar creator, build your look from parts: skin, body, hair, hat, top, pattern, trousers, an extra, and glasses. You can start from a preset or hit **Randomize**, then type the name the seeker will see. **Save** (it only shows once you've changed something) saves your avatar (`user://my_avatar.json`) and takes you back to the menu, or on into the hide if the creator was opened on the way there. The menu then shows your avatar, and **Hide in this town** goes straight to the town. **Town no.** picks the town (every number is a different town); **New town** rolls a random one.
2. **Tap anywhere on the map** to put yourself there; the tap marks your middle. **Drag yourself** to fine-tune. Dragging anywhere else pans the map.
3. The panel shows **Head NN% · Visible NN%** live. You may hide anywhere, even in the road, among the market stalls or beside the bins, as long as **at least half your head and 70% of you are visible** in the rendered scene. The head counts first: feet and legs look alike on everyone, so the face, hair and hat are what make you findable. Difficulty levels change the overall percentage, but the head never drops below half. Tree crowns, awnings, people standing in front of you and buildings all count as cover.
4. **Confirm hiding spot.** The share dialog shows an `WM1-…` code. **Copy code** puts it on the clipboard, and a JSON copy is saved under `user://challenges/`.
5. Either press **Search now (pass the device)**, or have a friend paste the code on the main menu (**Paste** → **Find them!**). **Open last saved** opens the newest saved file.
6. **Search.** A big card shows who you're looking for (the map stays hidden behind it). Press **Start** to start the clock, a small quiet one at the top. The card at the top left keeps showing the hider's look and name. **Hide UI** (bottom right, or the H key) clears everything off the map; **Show UI** brings it back. Tap people; wrong guesses flash red and count. **Give up** reveals the hider. The map has a plain paper margin all round, so you can see where the town ends.
   **Help when stuck** (on by default, toggle on the Play page): after 5 minutes 30% of the crowd goes home and the hider steps out to a spot where at least 70% of them shows; after 8 minutes 55% are gone and 90% shows (`SearchHelp`). It only changes your search, not the code.

7. **Result.** You get time, taps and wrong guesses, plus **Retry**, **Swap roles: you hide**, or **Menu**.

## The town (procedural, isometric)
**Hide in town** plays `town_iso`: a wonky storybook town seen at 2:1 isometric and generated from the seed, so every seed is a new town and share codes stay the same size. `data/maps/town_iso.json` is a template, not a layout: `MapDefinition.load_map(id, seed)` sees `"procedural": "wfc"` and calls `WfcTown.build`, which:
1. pins a main east–west and north–south road, then runs Wave Function Collapse (`WfcSolver`, simple-tiled, bitmask domains) on the cells of a 30×30 grid that show on screen. Tiles and socket rules live in the JSON: roads (straight, tees, corners, crossing), house rows (front cell facing a kerb + backyard cell behind) and open ground;
2. rejects solves that fail the template's `quality` rules (connected roads, enough houses and open space) and retries with the next attempt seed, so a seed always rebuilds the same town;
3. gives every road line a seeded width and offset, with jogs on straight stretches (`roads`); fills house rows plot by plot with a seeded subset of the buildings (`house_subset`), small buildings and garden gaps, each plot shifted sideways and back a little (`plots`); and splits open ground into parks (the biggest gets a pond), gardens, yards, markets and plazas (the most central gets the fountain);
4. projects everything to the screen: zones and blocked areas become polygons clipped to the view, the ground stays flat and `GroundLayer` draws it through the projection. `TownGenerator` then dresses the zones with props and the crowd.

Buildings are drawn in thin vertical slices sorted by the wall in front of them, so people beside a house sort correctly, and the 70% rule uses the same slices. Changing `WfcTown`, `WfcSolver` or the template in a way that moves anything needs a `map_version` bump and a new golden hash in `tests/test_iso_town.gd`. Look at towns with `$GODOT --path . -- --mode=debug --seed=7` and the **Seed ±1** buttons.

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
The run prints PASS/FAIL per test and exits with code 0 only when everything passes. Coverage includes determinism (including a golden hash of the town), the town generator's guarantees (connected roads, houses facing a kerb, sliced building depth), challenge round trips (code, JSON and file), malformed input, the visibility rule (head first, then 70% overall), tap selection after pan and zoom, depth setup, crowd twins of the hider and scene restarts. See `docs/POC_NOTES.md`.

## Developer flags
Pass these after `--`, for example `$GODOT --path . -- --mode=search --preset=2 --at=1000,700`.

| Flag | Effect |
|---|---|
| `--mode=create\|hide\|search\|debug\|play\|daily\|friends` | Skip the menu |
| `--difficulty=easy\|normal\|hard\|expert` | Difficulty for `--mode=play` |
| `--size=S\|M\|L\|XL` | Town size for hide or debug |
| `--map=town_iso` | Map for hide, debug and `--at` (the default) |
| `--hud=0` | Hide the HUD (clean screenshots, e.g. the menu backdrop) |
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
scenes/       main_menu, town/town, ui/avatar_creator, ui/*_hud, actors/character, props/prop_base
scripts/      app_state (autoload) · town/ (map data, generator, visibility checker, controller, ground)
              actors/ props/ (rendering) · gameplay/ (hide/search, challenge data + codec)
              camera/ debug/ ui/ util/
data/maps/    town_iso.json       procedural town template (WfcTown)
data/assets/  avatar_kit.json     part kit for avatars and the crowd (fields, palettes, weights, presets)
              asset_catalog.json  scenery assets: kind, radius, occluders, params, texture
art/          cleaned game sprites (generated)   art_src/  raw renders, prompts, workflow
tests/        headless test runner + suites
tools/        gen_assets.py (ComfyUI), import_assets.py, clean_sprite.py
docs/         ART_STYLE.md, ASSET_LICENSES.md, POC_NOTES.md
```
