# Where's Wally: design notes for Where's Me

What makes *Where's Wally?* (*Where's Waldo?* in North America) work as a search game, and how Where's Me uses it. This covers the solo modes (Play, Daily challenge) and the rules for how much of a hidden person must show.

We borrow the **principles** only: crowded scenes, partial cover, look-alikes. We don't copy anything from the books themselves (no striped jumper, no characters, no art).

## 1. What the books do

### The scenes
- **A huge crowd, drawn to scale.** A double-page spread holds roughly 300–500 characters, each drawn by Martin Handford. A spread took him weeks; one account says about eight weeks. The density *is* the challenge: there's no single place where the eye can rest.
- **Every corner has a story.** The crowd isn't wallpaper. Small gags (someone slipping, a dog stealing sausages, a knight's armour falling apart) reward slow looking. So searching is fun even before you find him.
- **The hiding spot is chosen during drawing, not before.** Handford: *"As I work my way through a picture, I add Wally when I come to what I feel is a good place to hide him."* The spot fits the scene; it isn't stamped on top of it.

### Where Wally ends up
- **Rarely at the edges.** Ben Blatt (Slate, 2013) measured Wally's positions. Random placement would put him within 1.5" of the top or bottom border about 25% of the time; in the books it's 12%.
- **Rarely dead centre.** The centre is where the eye goes first, and it is also the book's gutter (the fold).
- Randal Olson (2015) mapped every position in the first seven books and computed an optimal search path from a density estimate. It works for most spreads but fails on the outliers. That's a sign of good design: the placement has tendencies but no exploitable rule.

### How much of Wally shows
The books follow an unwritten rule: **Wally is always partly visible, and what shows is almost always the head**: the bobble hat, the glasses, the face. His body is very often behind something (a wall, a crowd, a cart, a doorway), sometimes only the head peeks out. You never get a hidden leg alone; the *recognisable* part is what stays in view. (This is from looking at the books; we found no published statement of it.)

His dog Woof is the deliberate exception: only his tail ever shows. That works because it's a bonus target, not the main one.

### Red herrings
- Many spreads include **red-and-white striped decoys**: awnings, towels, umbrellas, other people in stripes. Later books add the "Wally-Watchers", fans dressed exactly like him.
- In visual-search terms this turns an easy *feature search* (the one red thing pops out) into a *conjunction search* (you need several features at once: stripes **and** glasses **and** hat). Conjunction search is slow and has to be done item by item. That's where the difficulty comes from.

### Pacing across a book
Early spreads are gentler (fewer people, bolder colours), later ones are denser. Each spread also has a checklist of extra things to find, which makes a second look worthwhile.

## 2. What we take into Where's Me

| Books | Where's Me |
|---|---|
| 300–500 people per spread | Town sizes S/M/L/XL: about 290 / 630 / 1250 / 1800 people (`data/maps/town_iso.json` → `sizes`). Easy and Normal sit in the books' range; Hard and Expert go beyond it, since we have zoom and they don't. |
| Body often covered, head nearly always visible | **Head rule** (`VisibilityChecker.HEAD_REGION`, `min_head`): besides "at least X% of you shows", harder levels require part of the head (face, hair, hat) to show. You can tuck most of your body behind a stall, but your face has to peek out. |
| Never at the edges, not dead centre | `AutoHider` skips the outer 8% of the map and a circle around the centre. |
| Hidden where it fits the scene | `AutoHider` mostly samples spots just behind or beside props and buildings, then checks that the visibility falls in the level's band. So the person is *behind something*, not just standing in the crowd. |
| Striped look-alikes | **Decoys** (`scripts/gameplay/decoys.gd`): a few crowd members wear the hider's exact look **with one visible part changed** (hat, hair, glasses, trousers, shirt, pattern, coat). A glance at the shirt is no longer enough; you have to check the whole person. |
| Gentle early spreads, dense late ones | Difficulty levels, and a Daily challenge that builds through the week (Monday easy → Saturday expert, like newspaper crosswords). |

### How much of a person can be hidden

The old rule was "70% must show". It's fair but flat: hiding feels the same everywhere. The levels now trade body cover against the crowd size, and always keep the face findable:

| Level | Town | Visible (whole person) | Head must show | Look-alikes |
|---|---|---|---|---|
| Easy | S | 80–100% | 90% | 0 |
| Normal | M | 60–85% | 75% | 2 |
| Hard | L (classic) | 45–70% | 60% | 4 |
| Expert | XL | 30–55% | 50% | 8 |

- **Half the head is the floor everywhere** (`VisibilityChecker.MIN_HEAD = 0.5`), including Hide (classic): 70% overall *and* half the head. Feet and legs look much the same on everyone, so a spot where the body shows but the face is under a tree crown isn't a fair hide. The head is checked first, and the hide screen shows "Head NN% · Visible NN%". Codes made before this rule keep playing without it.
- The *lower* number is the hide rule: a human hider in a friend game must stay at least that visible. The *upper* number is only for the computer hider, so Play doesn't hand you someone standing in the open on Expert.
- **Why 30% is the floor:** our avatars are small (about 28×64 px at zoom 1). Below about 30% you're left with a few pixels of hat, and a find becomes luck, not skill. The books get away with less because a printed spread is far sharper than a phone screen.
- **Why the head matters more than the percentage:** 45% visible with the face in view is a fair find. 45% visible with only legs sticking out from a hedge is not. You recognise a person by the head, so the head rule protects fairness at every level.

Measured with `AutoHider` (5 seeds per level): Easy 91–100% visible, Normal 62–83%, Hard 46–58%, Expert 41–53% with 86–96% of the head showing. Every pick lands in its band, in under 250 ms.

## 3. Ideas for later
- **Checklists.** A seeded list of 3–5 small extras per town ("a dog in a hat", "someone with a balloon"), like the books' "can you also find…" lists. Gives Daily players something to do after the main find.
- **Scene gags.** A few seeded mini-stories in the crowd (a spilled fruit cart with people chasing apples). This needs art, so later.
- **Bonus target that shows almost nothing** (the Woof idea): a pet that only shows a tail, worth extra points, never required.
- **Online leaderboards and matchmaking.** `Leaderboard` and `Matchmaker` are the seams. A Supabase table (the `go-online` skill's shared Postgres) could take daily scores keyed by date, plus a queue of waiting codes for "Play with random". Nothing else in the game needs to change.

## Sources
- [Where's Wally? (Wikipedia)](https://en.wikipedia.org/wiki/Where%27s_Wally%3F): format, crowd sizes, red herrings, Wally-Watchers
- [Ben Blatt, Slate (2013): a new strategy for locating the missing man](https://www.slate.com/articles/arts/culturebox/2013/11/where_s_waldo_a_new_strategy_for_locating_the_missing_man_in_martin_hanford.html): edge and centre statistics
- [Randal Olson (2015): computing the optimal search strategy for finding Waldo](https://randalolson.com/2015/02/03/heres-waldo-computing-the-optimal-search-strategy-for-finding-waldo/)
- [Wolfram blog: Find Waldo Faster](https://blog.wolfram.com/2015/02/27/find-waldo-faster/)
- [Walker Books: Martin Handford](https://www.walkerbooks.com.au/creator/handford-martin/): working method, the quote about choosing the hiding place
- [Visual search (feature vs. conjunction search)](https://kiwix.lema.org/wikipedia_en_all_mini_2024-02/A/Visual_search)
