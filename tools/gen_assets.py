"""Generate raw sprite renders with the local ComfyUI (FLUX.2 Klein 4B base).

Usage (from the project root, with ComfyUI running on 127.0.0.1:8188):
    python3 -I tools/gen_assets.py                       # everything still missing
    python3 -I tools/gen_assets.py iso_well iso_shed     # specific assets (re-renders)
    python3 -I tools/gen_assets.py --list                # print prompts only

People are not generated: they are drawn in code from the part kit.

Writes art_src/raw/<key>.png and records prompt / seed / size / workflow per
asset in art_src/manifest.json. Uses art_src/workflows/flux2_klein_4b_base_only.json
(template image_flux2_klein_text_to_image with the uninstalled distilled branch removed).

Asset tables: the isometric town (ISO_BUILDINGS, ISO_SMALL_BUILDINGS, ISO_PROPS,
ISO_EXTRA_PROPS), props shared with it that read the same from any angle
(SHARED_PROPS), ground textures (GROUND), HUD art (UI) and branding (BRANDING, finished by tools/make_branding.py). tools/import_assets.py reads the same tables.
"""
import json
import shutil
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BASE_WORKFLOW = ROOT / "art_src/workflows/flux2_klein_4b_base_only.json"
RAW_DIR = ROOT / "art_src/raw"
MANIFEST = ROOT / "art_src/manifest.json"
WORK_DIR = ROOT / "art_src/workflows/generated"
COMFY_OUTPUT = Path.home() / "Documents/comfy/ComfyUI/output"

CAMERA = "Seen from a high-angle, shallow top-down three-quarter view. "
# Objects with a clear front (and the HUD art) render square-on.
FRONT_CAMERA = ("Seen straight from the front and slightly above, facing the viewer squarely, "
                "symmetric, not rotated, not at an angle, not isometric. ")
FRONT_FACING = {"mailbox"}
BACKGROUNDS = {
    "green": "Isolated single subject centred, on a plain flat solid pure bright green background, ",
    "magenta": "Isolated single subject centred, on a plain flat solid pure magenta (#FF00FF) background, ",
}
SUFFIX = "no ground shadow, no text, no letters, no labels, no border, no frame, no other objects."

# HUD art in the town's wonky storybook style (not in the asset catalog; imported to art/ui by
# tools/import_assets.py). key -> (subject, background, w, h).
UI = {
    "ui_magnifier": ("a single big round magnifying glass with a turned honey-coloured wooden handle and a slightly crooked "
                     "brass rim with a tiny curl of wrought iron, lens empty and clear, tilted slightly", "magenta", 768, 768),
    "ui_stopwatch": ("a single round old-fashioned silver stopwatch with a red button on top and a plain white face with no numbers and no hands", "green", 768, 768),
}

# --- Wonky isometric town ---------------------------------------------------
WONKY_STYLE = ("STYLE: original whimsical storybook illustration, delicate scratchy dark brown ink linework with fine "
               "hatching, soft faded watercolour washes in muted pastel colours. Exaggerated crooked wonky architecture: "
               "the whole building leans and bends, walls bow and taper, no straight lines anywhere, windows tilted at "
               "slightly different angles, sagging roofline, chimneys bent sideways, asymmetric. Cluttered with charming "
               "details: curly wrought-iron brackets and swirls, little lanterns, potted plants on the sills and steps. "
               "Eccentric and playful, soft daylight from upper left. ")
WONKY_PROP_STYLE = ("STYLE: original whimsical storybook illustration, delicate scratchy dark brown ink linework with fine "
                    "hatching, soft faded watercolour washes in muted pastel colours with a few gentle accents. Charmingly "
                    "wonky and hand-made: slightly crooked and lopsided, no perfectly straight lines, little curly "
                    "wrought-iron flourishes where it fits. Clean readable silhouette, soft daylight from upper left. ")

# Town props that read the same from any angle, used as they are in the isometric town.
# key -> (subject, background, w, h); SHARED_PROP_EXTRA adds colour direction where pale washes made one vanish.
SHARED_PROPS = {
    'tree_round': ('a single round leafy deciduous tree with a short brown trunk and a big bushy green crown', 'magenta', 768, 1024),
    'tree_pine': ('a single tall conical dark green pine tree with a short brown trunk', 'magenta', 768, 1024),
    'tree_blossom': ('a single round cherry blossom tree with a short brown trunk and a big pink blossom crown', 'green', 768, 1024),
    'bush': ('a single round leafy green bush', 'magenta', 768, 768),
    'lamp_post': ('a single tall dark grey Victorian street lamp post with a warm yellow lamp', 'green', 512, 1024),
    'hydrant': ('a single small red fire hydrant', 'green', 512, 768),
    'mailbox': ('a single red post box on a short dark post', 'green', 512, 768),
    'duck': ('a single small white duck swimming, side view', 'green', 768, 512),
    'dog': ('a single small brown dog standing, side view', 'green', 768, 512),
    'pigeon': ('a single small grey pigeon standing, side view', 'green', 768, 512),
}
SHARED_PROP_EXTRA = {
    'tree_round': 'The crown is painted in clearly green layered leaf washes, sap green and olive, not pale.',
    'tree_pine': 'Painted in clearly deep blue-green washes, not pale.',
    'tree_blossom': 'The blossom is clearly rose pink, not pale.',
    'bush': 'Painted in clearly green layered leaf washes, not pale.',
}

# Buildings stand on their own square paved plot at 2:1 isometric. The slab is
# measured on import and scaled to the in-game plot (see import_assets).
ISO_CAMERA = ("Isometric view: classic 2:1 isometric game art projection seen from above at 30 degrees. The building stands "
              "on a small square paved stone plot shaped like a flat diamond, the plot only slightly larger than the house. "
              "Its front wall with the front door faces the lower left, its side wall faces the lower right, both walls "
              "visible, the roof seen from above. The whole building and its plot fit in the image, centred, no street, "
              "no grass, nothing outside the plot, ")
ISO_PROP_CAMERA = "Isometric view: classic 2:1 isometric game art projection seen from above at 30 degrees. "
# House-row buildings (WfcTown picks a seeded subset per town; "_shop_" keys are shops).
# key -> (subject, background). New keys go at the end so existing seeds (13000 + index) stay put.
ISO_BUILDINGS = {
    'iso_house_sage': ('a tall narrow crooked sage green townhouse leaning to the left, steep grey slate roof with a curly iron finial, an arched pink front door up three stone steps, a round window and two arched windows, a bent brick chimney', 'magenta'),
    'iso_house_coral': ('a tall crooked dusty coral red townhouse with a pointed gable, a big round clock face in the gable, a tall arched window with a little curly iron balcony, a round-topped mustard yellow front door, a twisted chimney pot', 'green'),
    'iso_house_butter': ('a short wide wonky butter yellow cottage with a sagging thatched-look brown roof, two crooked chimneys, round porthole windows, a green stable door, flower pots on the sills', 'magenta'),
    'iso_house_lavender': ('a very tall skinny lavender townhouse that bends to the right like a candle flame, three tiny tilted windows stacked up the front, a little turret with a pointy purple roof, a teal door', 'green'),
    'iso_house_teal': ('a crooked dusty teal townhouse with a bulging bay window on the first floor, a lopsided mansard roof with two dormer windows, a red door with a round brass knocker, a crooked iron lamp beside the door', 'magenta'),
    'iso_house_peach': ('a wonky peach townhouse with a wide sagging curved roof like a hat, a round attic window, shutters hanging at angles, a blue door under a striped little canopy, ivy climbing one corner', 'green'),
    'iso_house_mint': ('a narrow mint green house with an onion-shaped roof, a spiral iron staircase curling up the side to a top-floor door, a crooked weather vane, small round windows', 'magenta'),
    'iso_house_rose': ('a squat dusty rose pink cottage with a huge crooked chimney bigger than the house, a round wooden door, two wonky windows with flower boxes, a tiny bird house on the wall', 'green'),
    'iso_house_stone': ('a tall crooked grey stone tower house leaning forward, uneven stone blocks, a pointed slate witch-hat roof, a red arched door, tiny lit windows, a crooked iron balcony at the top', 'magenta'),
    'iso_house_blue': ('a tall powder blue townhouse made of three stacked floors that each lean a different way, white wonky window frames, a yellow door, a chimney with a curly smoke swirl', 'green'),
    'iso_house_cream': ('a wide crooked cream timber-framed house with dark wooden beams, overhanging upper floor, a sagging red tile roof, diamond pane windows, a green door with a horseshoe above it', 'magenta'),
    'iso_house_ochre': ('a narrow ochre yellow townhouse with a stepped crooked gable, a tall arched window with a round top, a tiny juliet balcony with plants, a purple door, a skinny bent chimney', 'magenta'),
    'iso_shop_bakery': ('a crooked peach bakery shop house, a striped red and cream curved awning over a bulging shop window full of bread and cakes, a hanging iron sign showing only a bread loaf picture, a wonky roof with two chimneys', 'green'),
    'iso_shop_books': ('a tall leaning lavender bookshop, a shop window stacked with books, a hanging sign showing only a book picture, a little reading bench by the door, a crooked turret roof', 'green'),
    'iso_shop_florist': ('a crooked pale pink flower shop overflowing with flower buckets and hanging baskets, a green striped awning, a hanging sign showing only a flower picture, a sagging roof', 'green'),
    'iso_shop_cafe': ('a wonky mint green cafe with a curved striped awning, a round shop window with cups and cakes, a hanging sign showing only a coffee cup picture, a crooked chimney with a steam swirl', 'magenta'),
    'iso_shop_toys': ('a crooked butter yellow toy shop with a round shop window full of teddy bears and spinning tops, a red and blue striped awning, a hanging sign showing only a toy ball picture, a lopsided roof', 'magenta'),
    'iso_shop_clocks': ('a tall crooked teal clock shop with many little clocks in the window and a big clock in the gable, a hanging sign showing only a clock picture, a bent iron finial on the roof', 'magenta'),
    'iso_house_plum': ('a tall crooked plum purple townhouse with a pointed gable that droops like a wizard hat, a round stained-glass window, a mint green door with a curly iron lamp, crooked window boxes of red geraniums', 'green'),
    'iso_house_brick': ('a narrow lopsided red brick townhouse with white wonky window frames, a little iron balcony full of pots, a steep black slate roof with two leaning chimneys, a navy blue door with a fanlight', 'green'),
    'iso_house_windmill': ('a squat round cream cottage with a tiny crooked windmill on its roof, little sails turning, a blue round door, round windows with red shutters, a brown cone roof', 'green'),
    'iso_house_moss': ('a crooked olive green cottage with a thick mossy roof that sags in the middle, a round green door, bulging bottle-glass windows, a rain barrel and a watering can by the wall', 'magenta'),
    'iso_house_apricot': ('a tall wobbly apricot orange townhouse with each floor slightly bigger than the one below, a teal door, striped awnings over the windows, a crooked TV aerial and a cat sitting on the roof ridge', 'green'),
    'iso_house_turret': ('a crooked pale yellow house with a fat round corner turret and a pointy red cone roof, a red door, arched windows with lace curtains, a curly weathervane on the turret', 'magenta'),
    'iso_house_boat': ('a wonky pale aqua house shaped a little like an upturned boat with a curved wooden roof, porthole windows, a rope railing, a tiny anchor by the yellow door', 'magenta'),
    'iso_house_steeple': ('a narrow white-washed townhouse with a tall thin crooked steeple roof and a tiny bell, a red arched door, blue window shutters, a crooked flower trellis up one wall', 'green'),
    'iso_house_terrace': ('two crooked joined little townhouses leaning on each other, one dusty pink and one pale blue, different coloured doors, a shared wobbly chimney stack, washing line between the windows', 'green'),
    'iso_house_cocoa': ('a crooked chocolate brown wooden house with cream gingerbread trim on the eaves, a pink door, heart-shaped window cut-outs in the shutters, a candy-striped chimney', 'green'),
    'iso_house_greenhouse': ('a small crooked whitewashed cottage with a lean-to glass greenhouse full of plants against one wall, a sage door, terracotta pots everywhere, a sloping grey roof', 'magenta'),
    'iso_house_tall_red': ('a very tall thin crooked brick red tower house with five tiny floors, a spiral of little windows, a flag on the pointed top, a small green door at the bottom', 'green'),
    'iso_shop_hats': ('a crooked dusty pink hat shop with a giant top hat shaped roof, a big round display window full of hats, a hat pictogram on a hanging iron sign, a striped awning', 'green'),
    'iso_shop_sweets': ('a wonky mint and white candy-striped sweet shop with a lollipop pictogram on the hanging sign, big jars of sweets in the bay window, a scalloped pink awning', 'magenta'),
    'iso_shop_fish': ('a crooked sea blue fishmonger shop with a fish pictogram on the hanging iron sign, a striped blue and white awning, a slanted ice table of fish under the window, nets on the wall', 'green'),
    'iso_shop_cheese': ('a wonky butter yellow cheese shop with a round roof like a cheese wheel, a cheese wedge pictogram on the hanging sign, round cheeses stacked in the window, a red door', 'magenta'),
    'iso_shop_music': ('a crooked teal music shop with a violin pictogram on the hanging iron sign, a trumpet and a drum in the bay window, curly iron music notes on the railings, a cream awning', 'magenta'),
    'iso_shop_bikes': ('a crooked brick orange bicycle shop with a bicycle pictogram on the hanging sign, a wide arched window, two old bicycles leaning outside, a green striped awning', 'green'),
}
# Small buildings (huts, outbuildings) on a smaller plot (ISO_SMALL_PLOT in import_assets), mixed into
# house rows so rows vary in size. key -> (subject, background).
ISO_SMALL_BUILDINGS = {
    'iso_small_cottage': ('a tiny crooked one-room cottage with dusty pink walls, a lumpy thatched roof, one round window, a red door and a bent chimney', 'green'),
    'iso_small_hut': ('a tiny crooked wooden hut painted pale blue with a rusty tin roof, a stovepipe chimney and a wonky porch', 'green'),
    'iso_small_chapel': ('a tiny crooked white chapel with a little leaning bell tower, an arched door and a round window', 'green'),
    'iso_small_watertower': ('a small wonky wooden water tower on four crooked stilts above a little brick shed with a door', 'green'),
    'iso_small_studio': ("a small crooked artist's studio with a big slanted glass skylight roof, paint pots and a ladder by the door", 'magenta'),
    'iso_small_bakehouse': ('a tiny round stone bakehouse with a domed roof and a big crooked chimney puffing a curl of smoke', 'green'),
    'iso_small_lighthouse': ('a short stubby crooked lighthouse striped red and white, with a little cottage attached at its foot', 'green'),
    'iso_small_treehouse': ('a small crooked wooden house built around a thick tree trunk, the leafy tree crown growing up out of its roof', 'magenta'),
}
# Isometric props. key -> (subject, background, in-game size spec, radius, kind). A spec with "split"
# cuts a canopy (awning, parasol) onto the foreground occluder layer. Things that face somewhere face
# the lower left (cars drive down-left; WfcTown mirrors them on lanes running down-right).
ISO_PROPS = {
    'iso_bench': ('A single wooden park bench with dark green metal legs. The bench runs diagonally, facing the lower left', 'magenta', {'height': 34}, 26, 'prop'),
    'iso_bike': ('A single red bicycle standing on its kickstand. The bike is parked diagonally, its front wheel towards the lower left', 'green', {'height': 30}, 18, 'prop'),
    'iso_sign_board': ('A single dark A-frame chalkboard pavement sign with a simple white coffee cup drawing and no writing. The sign faces the lower left', 'green', {'height': 28}, 12, 'prop'),
    'iso_kiosk': ('A single small cream newspaper kiosk booth with a green and white striped roof and a window. Its front window faces the lower left', 'magenta', {'height': 78}, 36, 'prop'),
    'iso_food_cart': ('A single cream ice-cream cart with two wheels and a red and yellow striped parasol on top. The cart stands diagonally, its serving side facing the lower left', 'green', {'height': 88}, 30, 'prop'),
    'iso_cafe_table': ('A single small round cream cafe table with two red bistro chairs', 'green', {'height': 30}, 24, 'prop'),
    'iso_parasol_table': ('A single round cafe table with two blue chairs under a big open blue and white striped parasol', 'green', {'height': 78, 'split': 0.5}, 28, 'prop'),
    'iso_flower_bed': ('A single oval flower bed of brown soil with pink, yellow, white and purple flowers. The bed is a flat diamond-shaped patch seen from above', 'green', {'width': 64}, 30, 'prop'),
    'iso_crates': ('A small stack of three wooden crates full of oranges', 'green', {'height': 34}, 16, 'prop'),
    'iso_planter': ('A single terracotta planter box with a small round bush and pink flowers. The planter box runs diagonally', 'magenta', {'height': 32}, 16, 'prop'),
    'iso_car_red': ('A single small rounded red city car. The car drives diagonally towards the lower left, its front and left side visible. Painted clearly tomato red, not pink', 'green', {'height': 44}, 30, 'prop'),
    'iso_car_blue': ('A single small rounded blue city car. The car drives diagonally towards the lower left, its front and left side visible', 'green', {'height': 44}, 30, 'prop'),
    'iso_car_yellow': ('A single small rounded yellow city car. The car drives diagonally towards the lower left, its front and left side visible', 'magenta', {'height': 44}, 30, 'prop'),
    'iso_fountain': ('A single round stone town-square fountain with a central pedestal and a small water spout, blue water in the basin. The basin is seen from above as an isometric ellipse', 'magenta', {'width': 170}, 95, 'prop'),
    'iso_stall_red': ("A single wooden market stall with a red and white striped awning on two posts and a counter full of oranges, lemons and tomatoes. The stall's counter faces the lower left", 'green', {'height': 108, 'split': 0.42}, 46, 'prop'),
    'iso_stall_blue': ("A single wooden market stall with a blue and white striped awning on two posts and a counter full of cabbages, plums and lemons. The stall's counter faces the lower left", 'green', {'height': 108, 'split': 0.42}, 46, 'prop'),
    'iso_stall_green': ("A single wooden market stall with a green and white striped awning on two posts and a counter full of tomatoes, eggs and oranges. The stall's counter faces the lower left", 'magenta', {'height': 108, 'split': 0.42}, 46, 'prop'),
    'iso_easel': ("A single wooden painter's easel holding a small landscape painting. The easel faces the lower left", 'green', {'height': 52}, 12, 'prop'),
}
# More props to fill gardens, yards and streets (seeds 15000 + index).
ISO_EXTRA_PROPS = {
    'iso_big_bird_blue': ('A huge goofy long-legged blue bird taller than a man, a fluffy round body, tiny wings, a long bendy neck, a big orange beak and a silly curly crest', 'green', {'height': 96}, 16, 'prop'),
    'iso_big_bird_pink': ('An enormous lanky pink bird like a wonky flamingo with knobbly knees, a fluffy feather ruff and a curly crest, looking surprised', 'green', {'height': 100}, 16, 'prop'),
    'iso_big_bird_ostrich': ('A giant fluffy round speckled brown and cream bird like a plump ostrich with very long striped legs and a tiny head with big eyes', 'green', {'height': 90}, 18, 'prop'),
    'iso_big_bird_peacock': ('A giant round teal and gold bird as tall as a child with a huge fanned spotty tail', 'magenta', {'height': 76}, 24, 'prop'),
    'iso_giant_snail': ('A giant friendly snail as big as a dog with a tall swirly pastel striped shell and wobbly eye stalks', 'magenta', {'height': 40}, 18, 'prop'),
    'iso_outhouse': ('A crooked little wooden outhouse with a crescent moon cut into the door and a rusty tin roof', 'green', {'height': 72}, 20, 'prop'),
    'iso_shed': ('A lopsided small garden shed with peeling pastel blue paint, a tiny window, a watering can and a rake leaning on it', 'green', {'height': 66}, 28, 'prop'),
    'iso_dovecote': ('A crooked tall wooden dovecote on a pole: a little house with round holes and white doves sitting on it', 'green', {'height': 100}, 10, 'prop'),
    'iso_well': ('An old round stone wishing well with a little wonky shingle roof, a crank handle and a wooden bucket', 'green', {'height': 66}, 22, 'prop'),
    'iso_washing_line': ('A washing line strung between two crooked wooden posts with colourful laundry hanging on it: shirts, socks and a striped dress. The line runs diagonally', 'green', {'height': 58}, 24, 'prop'),
    'iso_beehives': ('Three crooked stacked wooden beehives painted in pastel colours with a few bees', 'green', {'height': 44}, 20, 'prop'),
    'iso_chicken_coop': ('A small wonky wooden chicken coop on stilts with a ramp and three plump hens pecking around it', 'green', {'height': 56}, 26, 'prop'),
    'iso_wheelbarrow': ('An old wooden wheelbarrow full of orange pumpkins', 'green', {'height': 30}, 14, 'prop'),
    'iso_haystack': ('A round lumpy golden haystack with a pitchfork stuck in it', 'magenta', {'height': 50}, 22, 'prop'),
    'iso_scarecrow': ('A funny scarecrow on a pole with a patched coat, a floppy straw hat and a crow sitting on its arm', 'magenta', {'height': 82}, 10, 'prop'),
    'iso_picnic': ('A red and white checked picnic blanket lying flat on the ground with a wicker basket, a teapot and sandwiches', 'green', {'width': 70}, 22, 'prop'),
    'iso_swing': ('A crooked wooden A-frame swing set with two swings on ropes', 'magenta', {'height': 78}, 26, 'prop'),
    'iso_doghouse': ("A crooked little red doghouse with a sleepy spotted dog's head poking out of the door", 'green', {'height': 40}, 18, 'prop'),
    'iso_van': ('A small rounded wonky delivery van painted mint green with a cream roof. The van drives diagonally towards the lower left, its front and left side visible', 'magenta', {'height': 54}, 30, 'prop'),
    'iso_car_purple': ('A little round bubbly old car painted lavender purple with white wheels. The car drives diagonally towards the lower left, its front and left side visible', 'green', {'height': 42}, 30, 'prop'),
    'iso_wheelie_bins': ('A row of three crooked tall wheelie bins in faded green, blue and brown, one lid propped open with a banana peel hanging out. The row runs diagonally', 'magenta', {'height': 58}, 24, 'prop'),
    'iso_skip': ('A big battered dented green metal rubbish skip with a half-open lid, a broken umbrella and a lampshade sticking out of the top', 'magenta', {'height': 56}, 32, 'prop'),
    'iso_trash_can': ('A round crooked dented metal dustbin with its lid sitting askew and a fish skeleton poking out', 'green', {'height': 40}, 12, 'prop'),
}

# Seamless ground textures (tiled by GroundLayer). Rendered square, then made
# tileable by tools/make_tileable.py and toned down by GROUND_GRADE in tools/import_assets.py.
GROUND_STYLE = ("STYLE: hand-painted storybook illustration texture, confident scratchy dark brown ink outlines around every "
                "shape, rich layered watercolour washes with visible pigment granulation and darker pooled edges, warm "
                "saturated colours. Seen exactly from directly above, flat, evenly lit, the pattern fills the whole image "
                "edge to edge, seamless repeating texture, ")
# Values are deliberately spread (road darkest, pavement lightest) so the
# street reads at a glance behind the inked houses.
GROUND = {
    "ground_road": "an old cobbled street: rounded cobblestones in warm slate grey, dusty plum and brown-grey, each stone "
                   "outlined in dark ink with deep dark gaps between, medium-dark overall",
    "ground_pavement": "a light pavement of large irregular flagstones in warm pale stone and sandy cream, each slab outlined "
                       "in brown ink, a few small green moss tufts in the cracks",
    "ground_grass": "a lush meadow lawn in fresh sap green and yellow-green watercolour, loose ink grass strokes, small "
                    "clumps of darker green and a few tiny white daisies, medium green overall",
    "ground_plaza": "herringbone brick paving in warm terracotta, rose and sandy orange bricks, each brick outlined in "
                    "brown ink with pale mortar",
    "ground_market": "large square clay tiles laid slightly crooked, alternating ochre, mustard and burnt sienna, each tile "
                     "outlined in brown ink",
}



# --- Branding (app icon, splash / launch screen, itch.io cover) --------------
# Full-bleed scenes, no cut-out background. Several seeds per image; the pick and the
# final crops/sizes are made by tools/make_branding.py. key -> (prompt, w, h, seed).
BRANDING_STYLE = ("STYLE: original whimsical storybook illustration, delicate scratchy dark brown ink linework with fine "
                  "hatching, soft watercolour washes in warm pastel colours, cream paper tones, crooked wonky leaning "
                  "houses with curly wrought-iron details. Eccentric, cosy and playful, soft daylight from upper left. ")
ICON_SUBJECT = ("Square app icon artwork filling the whole frame edge to edge, full-bleed background, bold simple readable "
                "shapes, strong contrast. A big round magnifying glass with a honey-coloured turned wooden handle and a "
                "brass rim, tilted, fills most of the frame, held over a tiny busy crooked town street crowded with small "
                "people seen from above. Inside the lens, magnified, one cheerful little person in a mustard yellow coat "
                "and a teal knitted hat waves at the viewer. Background outside the lens slightly muted. "
                "No text, no letters, no border, no frame, no rounded corners.")
SPLASH_SUBJECT = ("Wide panoramic illustration of a crowded wonky storybook town seen from a high angle three-quarter view: "
                  "crooked leaning pastel houses all around the edges, striped market stalls, round trees and pink blossom "
                  "trees, lanterns, a few ducks, many tiny people milling about. The centre of the picture is a calm, "
                  "open, pale cobblestone plaza with lots of empty space. No text, no letters, no border, no frame.")
BRANDING = {
    **{f"app_icon_{i}": (ICON_SUBJECT, 1024, 1024, 9500 + i) for i in range(1, 5)},
    **{f"splash_{i}": (SPLASH_SUBJECT, 1536, 864, 9600 + i) for i in range(1, 4)},
}


def build_jobs() -> dict:
    manifest = json.loads(MANIFEST.read_text()) if MANIFEST.exists() else {}
    jobs = {}

    def add(key: str, prompt: str, seed: int, w: int, h: int, bg: str) -> None:
        jobs[key] = {"prompt": prompt, "seed": seed, "width": w, "height": h, "background": bg}

    # Shared props keep the seed they were first rendered with.
    for i, (key, (subject, bg, w, h)) in enumerate(SHARED_PROPS.items()):
        camera = FRONT_CAMERA if key in FRONT_FACING else CAMERA
        extra = SHARED_PROP_EXTRA[key] + " " if key in SHARED_PROP_EXTRA else ""
        add(key, WONKY_PROP_STYLE + camera + subject.capitalize() + ". " + extra + BACKGROUNDS[bg] + SUFFIX,
            manifest.get(key, {}).get("seed", 7100 + i), w, h, bg)
    for i, (key, (subject, bg)) in enumerate(ISO_BUILDINGS.items()):
        add(key, WONKY_STYLE + ISO_CAMERA + subject + ". " + BACKGROUNDS[bg] + SUFFIX, 13000 + i, 1024, 1024, bg)
    for i, (key, (subject, bg)) in enumerate(ISO_SMALL_BUILDINGS.items()):
        add(key, WONKY_STYLE + ISO_CAMERA + subject + ". " + BACKGROUNDS[bg] + SUFFIX, 16000 + i, 1024, 1024, bg)
    for base, table in ((14000, ISO_PROPS), (15000, ISO_EXTRA_PROPS)):
        for i, (key, (subject, bg, _spec, _radius, _kind)) in enumerate(table.items()):
            add(key, WONKY_PROP_STYLE + ISO_PROP_CAMERA + subject + ". " + BACKGROUNDS[bg] + SUFFIX, base + i, 768, 768, bg)
    for i, (key, subject) in enumerate(GROUND.items()):
        add(key, GROUND_STYLE + subject + ". No objects, no people, no shadows, no text, no border, no frame.",
            12000 + i, 1024, 1024, "none")
    for i, (key, (subject, bg, w, h)) in enumerate(UI.items()):
        add(key, WONKY_PROP_STYLE + FRONT_CAMERA + subject.capitalize() + ". " + BACKGROUNDS[bg] + SUFFIX, 9100 + i, w, h, bg)
    for key, (subject, w, h, seed) in BRANDING.items():
        add(key, BRANDING_STYLE + subject, seed, w, h, "none")
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
    res = subprocess.run(["comfy", "run", "--workflow", str(wf), "--wait", "--timeout", "1800"], capture_output=True, text=True)
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
