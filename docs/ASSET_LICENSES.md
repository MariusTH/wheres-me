# Asset sources and licences

No third-party art packs are used. Every visual in the game is either drawn in code or generated locally for this project. The only third-party assets are one font and the MediaPipe models the web build downloads at runtime (below).

| Asset group | Source | Creator | Licence / terms | Attribution required | Date |
|---|---|---|---|---|---|
| Code-drawn placeholder art (`scripts/actors/placeholder_art.gd`, `scripts/town/ground_layer.gd`) | Original code, this project | Project | Project-owned | No | 2026-10-21 |
| Generated sprites in `art/` (raw sources in `art_src/raw/`) | Local ComfyUI, model `flux-2-klein-base-4b.safetensors` with `qwen_3_4b` text encoder and `flux2-vae`; prompts and seeds in `art_src/manifest.json` | Generated for this project | Output of FLUX.2 [klein] 4B. Black Forest Labs released the 4B Klein models under Apache-2.0, unlike the non-commercial 9B, but **re-check the licence on the model card you installed before shipping**. | No (record kept here) | 2026-10-21 |
| ComfyUI workflow `art_src/workflows/*.json` | ComfyUI template `image_flux2_klein_text_to_image`, modified | Comfy Org template | Template distributed with ComfyUI | No | 2026-10-21 |
| UI font | Godot's built-in default font | Godot Engine | Bundled with the engine (MIT engine, OFL font) | No | n/a |
| Display font `art/fonts/LuckiestGuy-Regular.ttf` (titles, buttons) | https://github.com/google/fonts/tree/main/apache/luckiestguy | Astigmatic (Brian J. Bonislawsky) | Apache-2.0 | No (keep the licence notice if redistributed as a file) | 2026-10-24 |
| HUD art `art/ui/` (magnifier, stopwatch, banner, hat, paper) | Local ComfyUI, same model as the sprites; prompts in `tools/gen_assets.py` (`UI`) and `art_src/manifest.json` | Generated for this project | As the generated sprites above. Original motifs only (stripes, magnifier); no Where's Wally characters or artwork. | No | 2026-10-24 |
| Selfie models (web build, downloaded at runtime, not bundled): MediaPipe Tasks Vision 0.10.14 (jsDelivr), `selfie_multiclass_256x256`, `face_landmarker` (storage.googleapis.com) | https://ai.google.dev/edge/mediapipe | Google | Apache-2.0 (library and models; check each model card before shipping) | No | 2026-10-24 |

## Not used
- **Kenney packs and LPC.** These were evaluated per the brief and **not downloaded**. Code-drawn placeholders were good enough to validate layout and gameplay. Kenney packs are pixel art and would have clashed with the hand-drawn direction. If one is added later, record the pack URL, licence (Kenney: CC0), download date and attribution here.
- **LoRA `MinimalistVectorArtKlein4B`.** It is installed locally, but its style doesn't fit, so it is unused. If it is ever used, check its own licence separately.

## Policy
- Record every external pack: URL, creator, licence, download date, and whether attribution is required.
- Don't assume one licence covers a whole site; check each pack and its dependencies.
- If licence terms are unclear, treat the asset as a temporary placeholder until resolved.
