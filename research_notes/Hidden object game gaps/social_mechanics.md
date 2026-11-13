# Social, Async and Viral Sharing Mechanics for "Where's Me" (friend-to-friend hide-and-seek, serverless web)

Scope note: about 17 tool calls of research. Coverage is strongest for Wordle, Draw Something, K-factor, UGC volume, itch.io and link-preview technical limits. It is thinner for BeReal/Locket mechanics, Jackbox, Among Us, Spy Party and "quiz about me" apps; those gaps are listed explicitly. Older classics (Draw Something 2012, Prop Hunt 2007, Mario Maker 2015/2019) are labelled as such.

## 1. Wordle-style shareable results, daily seeds, streaks, and successors

### Takeaway
Wordle spread because of a spoiler-free, player-invented emoji grid. It worked because everyone solves the same puzzle, so the grid tells "how it went" without revealing the answer. A one-a-day cadence created a shared daily conversation in group chats. Successors (Worldle, Framed, Heardle, Costcodle, Quordle) mostly kept the loop (daily puzzle, limited attempts, compact shareable result) and changed the subject. NYT treats streaks/stats and sharing as retention levers but publishes no isolated numbers.

### Cited Findings
- Players invented the emoji grid. Wardle saw people "taking the time to open the emoji keyboard" and typing their grids out, then built it in. In his words the grid "becomes a way in which you can share that story really easily with others." — [Game Developer, Wardle GDC 2022](https://www.gamedeveloper.com/marketing/josh-wardle-reflects-on-the-the-unconventional-road-to-wordle-s-success)
- Wardle deliberately left the URL out of the share text because the grid "has this really beautiful, simple aesthetic." The grids created curiosity, and "it kind of became a club that you're either part of or not part of." — [Game Developer](https://www.gamedeveloper.com/marketing/josh-wardle-reflects-on-the-the-unconventional-road-to-wordle-s-success)
- The once-a-day limit ("three minutes of your time a day, and that's it") produced daily conversation that Wardle called "a huge part of the game and something, frankly, that I wasn't intentional about." He said family group chats were "reinvigorated." — [Game Developer](https://www.gamedeveloper.com/marketing/josh-wardle-reflects-on-the-the-unconventional-road-to-wordle-s-success)
- Fairness mattered: Wardle's partner filtered about 13,000 candidate words down to familiar ones, because an obscure answer makes "you feel like you've been cheated by the game." It was a plain website, never promoted, and NYT bought it for "low seven figures." — [Game Developer](https://www.gamedeveloper.com/marketing/josh-wardle-reflects-on-the-the-unconventional-road-to-wordle-s-success)
- The early share trend is attributed to a New Zealand group chat and an early adopter who started posting grids. — [BuzzFeed News](https://www.buzzfeednews.com/article/stefficao/how-wordle-went-viral-strategy); [RNZ](https://www.rnz.co.nz/national/programmes/the-weekend/audio/2018826546/josh-wardle-the-power-of-wordle)
- Players made 4.8 billion Wordle attempts in one year (NYT figure cited in a listing). — [Engadget](https://www.engadget.com/gaming/best-online-games-puzzles-120059484.html)
- Worldle's creator, after failed attempts at other web games, concluded "it's better to keep it simple" (guess a country silhouette in six tries). Framed uses movie stills with autofill so players can't mistype the title. Heardle reveals a song in six growing clips starting from one second. Costcodle is "Wordle meets The Price is Right" with Costco items. — [PopSci](https://www.popsci.com/diy/best-wordle-spin-offs/); [Den of Geek](https://www.denofgeek.com/games/best-daily-games-wordle-clones-spin-offs)
- Quordle's creator said it reached more than 500,000 daily players with no plans to monetise. — [Den of Geek](https://www.denofgeek.com/games/best-daily-games-wordle-clones-spin-offs)
- NYT Games head Jonathan Knight: "Retention will always be the most important metric for us." The near-term priority is optional free accounts "so that they can capture their stats and streaks." Sharing "facilitates a conversation" via group chats. People "are proud to share their habit." Playing with other people produces "world-class" return rates (Crossplay). — [A Media Operator](https://www.amediaoperator.com/analysis/wordle-tv-show-new-york-times-games-jonathan-knight/); [Creative Review](https://www.creativereview.co.uk/new-york-times-games-wordle-crossplay-design-jonathan-knight/); [Digiday](https://digiday.com/media/the-next-level-for-us-the-new-york-times-eyes-longer-play-sessions-for-games-in-subscription-drive)
- Streaks carry real emotional weight. Streak resets during the move to NYT drew player backlash and press coverage. — [Shacknews](https://www.shacknews.com/article/128799/wordles-move-to-the-nyt-website-has-reset-some-player-streaks); [Tom's Guide](https://www.tomsguide.com/uk/news/wordle-disaster-some-players-lose-their-streaks-in-transfer-to-nyt)
- Connections daily-player figures conflict: one low-quality blog says 2.1M, while an April 2026 piece says "hundreds of thousands." Neither is reliable. — [blog](https://latestnewsofindiafast.blogspot.com/2025/12/nyt-games-year-in-review-2025-puzzle.html); [Pulse](https://www.pulse.bot/media/news/nyt-connections-puzzle-draws-millions-showcasing-surge-in-daily-word-games-f2ec8f64-8afa-4774-b4ba-0a8ba0f3c8cc/)

### Inferences
- The Wordle grid maps directly onto Where's Me results. A compact, emoji-only, spoiler-free line could show time, taps and wrong guesses, e.g. "Where's Me #12 found in 0:47, 🔍🔍❌🔍✅". The key property is that it reveals performance, not the hiding spot.
- Where's Me's puzzles are personal (friend X's hide), not shared (everyone's same word), so the "club" effect needs a shared object. The option is a **daily official hide**: a seeded town plus a designer-placed or seeded avatar that everyone searches the same day, with a spoiler-free grid. This gives the public broadcast channel (Twitter/Discord) while friend codes remain the intimate channel.
- Keep the share text short and visually distinctive. Wardle omitted the URL for aesthetics, but for an unknown itch game a short URL is likely needed for discovery (tension to test).
- Fairness lesson: a hide must be findable. Rules or a validation step should prevent fully occluded or pixel-sized hides, the equivalent of "no obscure words".
- Streaks fit a daily mode and can live in localStorage, with the known risk that cleared storage destroys them.

### Gaps
- No public data isolates how much the share grid or streaks lift retention or acquisition (NYT declines to share).
- No reliable player numbers for Framed, Costcodle, Bandle or Heardle.

## 2. Async friend games (Words With Friends, Draw Something, Gartic Phone, BeReal, Locket, GeoGuessr, iMessage games, Jackbox, Among Us)

### Takeaway
Async, turn-based friend play spreads fast when every turn is a message to a specific friend (Draw Something, GamePigeon, GeoGuessr challenge links). It collapses when content runs out or the creative act loses novelty (Draw Something; 2012, older classic). Free-to-join links matter: GeoGuessr challenges can be played by recipients without an account. Streamer-friendly, funny, low-skill output (Gartic Phone) drives video virality. Daily "everyone at once" rituals (BeReal) spike and then decline without deepening.

### Cited Findings
- **Draw Something (2012, older classic):** DAU peaked at about 14.6M on April 3, 2012 (AppData), with other reports near 15M. Zynga bought OMGPOP in March 2012 for a reported $180M–$210M. Within about a month the game lost 4M+ DAU, with 900K leaving in the last week of April alone. — [CBS News](https://www.cbsnews.com/news/draw-something-sheds-4m-daily-users-in-the-past-month); [GamesBeat](https://gamesbeat.com/draw-something-loses-3-million-players/); [Shacknews](https://www.shacknews.com/article/73622/draw-something-daily-usage-drops-33-percent)
- Proposed reasons for the collapse: monetisation souring the relationship, server strain, and content exhaustion ("more and more users gone through all 900 words"). Caveat: AppData counted only Facebook-login users. — [The Week](https://theweek.com/articles/475789/draw-somethings-disastrous-month-3-theories-behind-slump) (summarised via search; full page didn't load); [CBS News](https://www.cbsnews.com/news/draw-something-sheds-4m-daily-users-in-the-past-month)
- **GeoGuessr:** a Pro subscriber creates challenge links, and anyone can play them without an account or subscription. Parties allow up to 100 guests. Duels came to private parties in Nov 2021 and Ranked Team Duels launched on July 1, 2024. — [TechWiser](https://techwiser.com/play-geoguessr-with-friends/); [Rigorous Themes](https://rigorousthemes.com/blog/how-to-play-geoguessr-for-free-with-friends/); [r/geoguessr dev post 2021](https://lr.eu.psf.lt/r/geoguessr/comments/qwop2o/duels_live_now); [r/geoguessr dev 2024](https://lr.eu.psf.lt/r/geoguessr/comments/1dovt46/ranked_team_duels_launch_july_1st/lacru5w/?context=3)
- **Gartic Phone** (Onrizon, launched Oct/Dec 2020, sources disagree) combines Pictionary and Telephone. It grew via Twitch and YouTube: one RubberRoss session had 2.8M+ views. It launched on Discord in 2023. — [Know Your Meme](https://knowyourmeme.com/editorials/guides/what-is-gartic-phone-and-why-do-streamers-love-it-the-multiplayer-drawing-game-explained); [Streams Charts](https://streamscharts.com/games/gartic-phone)
- **BeReal:** about 20M DAU in Oct 2022 fell to about 10.4M in early 2023 (Apptopia), and weekly downloads were down 95% from 2022 highs. BeReal disputed this, claiming 25M DAU in Sept 2023. — [PetaPixel](https://petapixel.com/2023/02/22/bereal-may-be-on-the-out-users-have-nearly-halved-since-peak); [TechCrunch](https://techcrunch.com/2023/09/29/bereal-pushes-back-at-report-that-its-losing-steam-says-it-now-has-25m-daily-users/?guccounter=1); [Platformer](https://platformer.news/how-bereal-missed-its-moment)
- **Locket** is described as a home-screen widget friend-photo app. Sacra claims it has a larger share of users and time spent than BeReal (not verified). — [Sacra](https://sacra.com/q/how-did-bereal-get-so-popular/)
- **GamePigeon** (iMessage) reached the #1 free spot in the iMessage App Store about six months after launch. Its catalogue is classic two-player games (pool, mini golf, battleship), played turn by turn inside the chat thread. It is iOS-only. — [VentureBeat](https://venturebeat.com/business/forget-stickers-imessages-top-15-apps-and-games); [Wikipedia](https://en.wikipedia.org/wiki/GamePigeon); [Make Tech Easier](https://maketecheasier.com/social-gaming-apps-like-gamepigeon-android/)

### Inferences
- Where's Me already has the Draw Something structure: I make something personal (an avatar plus a hiding spot), you solve it, you make one back. That structure explains the spike potential. Draw Something's collapse warns that the fun must not depend on a finite content list. Hide-and-seek scales with towns and hiding spots, so adding towns/variants and seeded crowd randomisation is the anti-"900 words" measure.
- The GeoGuessr lesson is that recipients should need zero setup. The friend should be searching within seconds of pasting or opening the code, with no avatar creation required before they play. Prompt "now hide yourself" only after the result.
- The Gartic lesson is to make results funny and screenshot- or stream-friendly. A replay of the seeker's taps (a heatmap of wrong guesses over the town) is a natural "look how blind you were" artifact.
- The BeReal and Draw Something pattern of novelty spikes suggests building for a sustainable small-group habit (one friend group re-sharing) rather than expecting a one-off spike.

### Gaps
- No sourced data was found for Words With Friends retention, Jackbox (phone-as-controller) design rationale or sales, Among Us's 2020 spike mechanics, Skribbl, Snapchat games or "make a quiz about me" apps. Searches returned nothing usable within budget.
- No Locket user figures from a reliable source.

## 3. UGC challenge loops (Mario Maker, Dreams, Roblox) and personalised avatars/selfies

### Takeaway
"Create, then challenge" loops generate enormous volumes of content when creation is cheap. Mario Maker 2 passed 2M courses in 11 days and 26M by 2021, all shared via short alphanumeric IDs, the closest analogue to a WM1 code. Evidence that self-similar or selfie avatars increase engagement is mixed, and no study measures their effect on sharing.

### Cited Findings
- Super Mario Maker (Wii U, 2015) had over 1M uploaded levels in its first week. — [MyNintendoNews](https://mynintendonews.com/2015/09/17/super-mario-maker-over-a-million-levels-have-been-uploaded/)
- Super Mario Maker 2 (2019) had 2M courses 11 days after launch, 4M+ by July 2019, 5M+ by August 2019 and 26M+ by May 2021. — [Engadget](https://www.engadget.com/2019/07/09/super-mario-maker-2-million-levels/); [Nintendo Life 2019](https://www.nintendolife.com/news/2019/07/super_mario_maker_2_players_have_already_uploaded_more_than_4_million_courses); [Nintendo Life 2021](https://www.nintendolife.com/news/2021/05/super_mario_maker_2_players_have_now_uploaded_more_than_26_million_courses)
- Courses are shared via short IDs: Wii U used a 16-char format like 2986-0000-0037-CB7E, and SMM2 maker IDs look like 7YW-6XS-XCG. — [GameSkinny](https://www.gameskinny.com/2ruw1/20-super-mario-maker-levels-you-need-to-try); [Nintendo Life](https://www.nintendolife.com/news/2019/08/there_are_now_more_than_5_million_courses_in_super_mario_maker_2)
- Fortnite hide-and-seek and Prop Hunt exist as community Creative maps shared via 12-digit island codes. — [GGRecon](https://www.ggrecon.com/guides/fortnite-hide-and-seek-codes/); [AFK Gaming](https://afkgaming.com/esports/guide/best-hide-and-seek-maps-in-fortnite-all-map-codes)
- Self-similar avatars: in USC ICT / CHI 2018 work, players felt more connected and engaged with a photorealistic self-similar avatar, but a follow-up did not replicate this, suggesting familiarity rather than resemblance as the driver. — [ScienceDaily](https://www.sciencedaily.com/releases/2018/05/180510115037.htm); [USC ICT](https://ict.usc.edu/?p=14146)
- Avatar–player similarity leads to identification, which leads to enjoyment (N=666). — [Hogrefe, Journal of Media Psychology](https://econtent.hogrefe.com/doi/10.1027/1864-1105/a000022)
- Players are split on whether a self-designed avatar is "them" or a separate character (Elden Ring screenshot sharing). — [Immerse News](https://immerse-news.github.io/the-art-of-avatar-creation-b7d291c6cd7f.html)

### Inferences
- A WM1 code is functionally a Mario Maker course ID. Short, human-readable codes with check characters and grouped blocks improve copy and paste and dictation. Keep codes as short as possible.
- The "retaliate" loop is the core viral engine. After a friend finds you, the result screen should immediately offer "Hide yourself for [name]", with their result embedded in your reply so the chain carries history.
- The selfie avatar's value is probably recognisability ("find ME") rather than proven engagement lift. It makes the hide personal and the result screenshot shareable. Privacy matters too: selfie data should stay on device, with only avatar parameters encoded in the code, never the photo.

### Gaps
- No found data on Dreams or Roblox creation-to-share conversion. No study directly measures whether Bitmoji, Mii, Zepeto or face-swap features increase sharing rates. Bitmoji and face-swap usage stats were not researched within budget.

## 4. Hide-and-seek multiplayer precedents (Prop Hunt, GMod, Fortnite, Hide Online, spot-the-imposter)

### Takeaway
Hide-and-seek is a durable, player-driven genre. Prop Hunt began as a 2007 Garry's Mod mod (older classic), remains the most-subscribed GMod workshop addon, and was copied into Call of Duty, Fortnite and Genshin Impact. Its spread was driven by YouTubers and community maps, not by the original developer.

### Cited Findings
- Prop Hunt was created by Andrew "AMT" Theis, first released in Sept 2007, inspired by a Counter-Strike: Source hide-and-seek mod. It was briefly official in GMod in 2010. — [EverybodyWiki](https://en.everybodywiki.com/Prop_Hunt); [Facepunch wiki](https://wiki.facepunch.com/gmod/gamemodes:PropHunt); [GitHub andrewtheis/prophunt](https://github.com/andrewtheis/prophunt)
- Prop Hunt-style modes later appeared in CoD: MW Remastered, Black Ops III, Fortnite and Genshin Impact. YouTubers popularised it. — [Wikipedia (Garry's Mod mirror)](https://wikiwand.com/simple/Garry%27s_Mod); [Know Your Meme](https://knowyourmeme.com/memes/subcultures/garrys-mod)
- Fortnite's hide-and-seek is community-built Creative maps with 12-digit codes. A newer "Meccha Chameleon" blend-in mode inspired many copies. — [GGRecon](https://www.ggrecon.com/guides/fortnite-hide-and-seek-prop-hunt-codes/); [games.gg 2026](https://games.gg/fortnite/guides/fortnite-hide-and-seek-codes-july-2026/)

### Inferences
- Prop Hunt's appeal (the comedy of blending in, the seeker's frustration) is real-time, while Where's Me is async. The transferable part is the comic reveal: show where the hider was and the seeker's misses, which is good for screenshots and video.
- "Blend in" is a strong theme to lean into: costume choices that match a town's crowd, and a "camouflage score".

### Gaps
- No sourced data found for Hide Online (mobile), Spy Party, or "find your friend in a crowd" apps specifically. Searches were not run due to budget.

## 5. Making it work without servers (URL state, share sheet, OG previews, reply chains)

### Takeaway
On itch.io, URL-based state is unreliable: the game runs in an iframe that does not receive the page's query string or hash. Link-preview crawlers also never see `#fragments`. A copy-and-paste text code (the current WM1 approach) is therefore the robust serverless transport on itch. Rich per-hide previews would need either a self-hosted page with real query paths or a tiny serverless function, so the share message text must carry the hook.

### Cited Findings
- itch.io does not pass the parent page's query string into the game iframe. Admins say there is "no official API" for it. A 2024 feature request asks for query forwarding. Opening the raw iframe URL with params works but loses the itch page. — [itch.io forum: pass query params to iframe](https://itch.io/t/4128461/pass-the-query-parameters-down-to-iframe); [itch.io forum: query strings for embedded games](https://itch.io/t/222066/query-strings-for-embedded-games); [itch.io forum: URL parameters](https://itch.io/t/1084510/url-parameters)
- On itch, the URL fragment "is neither read nor written to," probably because of the iframe. `document.referrer` worked in Chrome but lost the query in Firefox. — [itch.io forum](https://itch.io/t/1466512/game-iframe-url-how-to-add-a-query-param); [itch.io forum](https://itch.io/t/2177976/url-queryparam)
- Open Graph crawlers don't run JavaScript and never receive the part after `#`, so hash-encoded state can't produce per-link previews. Previews may canonicalise links and strip fragments. Meta requires OG tags in the first 1MB. — [Phabricator T431181](https://phabricator.wikimedia.org/T431181); [Tor forum](https://forum.torproject.org/t/link-previews-remove-fragment-identifiers-from-urls/1916); [Netlify support](https://answers.netlify.com/t/support-guide-understanding-and-debugging-prerendering/150)
- Fully static games can keep the entire game state in the URL as base64 JSON for link-trading (Val Town staticWordle). — [Val Town](https://val.town/v/stevekrouse/staticWordle)
- Some Wordle clones support shareable custom puzzles or links to specific game numbers (seed by index). — [MikhaD/wordle](https://github.com/MikhaD/wordle); [Yawdle](https://awesome.ecosyste.ms/projects/github.com%2F5310%2Fyawdle)

### Inferences
- Recommended transport is a share message of the form "Find me in Where's Me! [itch link] Code: WM1-XXXX". The static itch page gets a generic but attractive OG image, and the code is pasted in-game. Make paste a single tap and tolerant of whitespace, case and surrounding chat text (extract the WM1-... token with a regex).
- Optional self-hosted mirror (e.g. GitHub Pages) at `/?c=WM1-...`, where a query string, unlike a hash, at least reaches the page. Still no per-code OG image without a server, though a set of pre-rendered static OG images per town (`/t/harbor.html`) is possible.
- Reply codes that carry the previous result can be serverless leaderboards. Encode `{hide, prev_result: {seeker_name, time, taps, misses}}` in the reply code so a back-and-forth chain shows a running scoreboard ("You 2, Ola 1"). Each player keeps a localStorage history per friend name.
- A daily seed needs no server: date to seed to town layout and hide spot (deterministic). This enables a daily Wordle-style mode with a spoiler-free grid.
- Web Share API (`navigator.share`) gives a native share sheet on iOS Safari. Inside itch's iframe it may be blocked by permissions policy, so a clipboard-copy fallback is needed. (Unverified; test on device.)

### Gaps
- No authoritative itch.io documentation was found. The iframe behaviour comes from forum posts and may change.
- iMessage and WhatsApp-specific preview behaviour for query-string URLs was not confirmed by a source.
- Whether itch's game iframe grants `web-share` and `clipboard-write` permissions was not verified.

## 6. Viral coefficient / K-factor and retention data

### Takeaway
K = invites per user × invite conversion. Sustained K > 1 is rare in games, and there is no reliable public game-specific benchmark. Industry reference bands are 0.1–0.5 moderate, 0.5–1 strong organic contribution and >1 viral. Cycle time (install to invite to recipient install) matters as much as K. Public casual-social retention benchmarks were not found in reliable form.

### Cited Findings
- K-factor = invites sent per user × conversion rate. Cycle time is the time from install to invite to the recipient's install. Few games sustain K > 1, with "effectively no reliable public benchmark." Tenjin bands: 0.1–0.5 moderate, 0.5–1 strong, >1 viral. — [Playio blog](https://blog.playio.co/viral-coefficient-organic-uplift-mobile-games); [Tenjin glossary](https://tenjin.com/glossary/k-factor/)
- Adjust framing: K > 1 is self-sustaining, K = 1 is stable, K < 1 means virality alone declines. — [Admiral Media](https://admiral.media/k-factor-mobile-apps/)
- An outlier claim says "high-performing applications" reach K 1.4–2.1 with 5–8% invite conversion. It is uncorroborated, so treat with caution. — [Saxifrage](https://www.saxifrage.xyz/post/k-factor-benchmarks)
- Mobile Dev Memo discusses estimating K when conversions can't be attributed (relevant to serverless, analytics-free setups). Article not fully read. — [Mobile Dev Memo](https://mdm.co/how-to-track-k-factor-when-conversions-are-unknown/)
- NYT: playing with other people yields "really, really healthy" return rates, and multi-game players retain better. — [A Media Operator](https://www.amediaoperator.com/analysis/wordle-tv-show-new-york-times-games-jonathan-knight/)

### Inferences
- Where's Me's invite is the core loop itself: every hide is an invite. Invites per user can therefore be high, and the levers are (a) the number of hides sent per session (encourage hiding for several friends, or group-chat "anyone find me?" codes) and (b) recipient conversion (instant play, no setup).
- A short cycle time is achievable: friend receives code, plays in about 1 minute, prompted to hide back.
- Without a backend, K can't be measured directly. Proxies: itch.io page views and plays, a counter of codes generated versus codes redeemed via a privacy-friendly analytics ping (if acceptable), or a "code generation number" embedded in codes (chain depth) that players could report.

### Gaps
- No reliable published K-factors or D1/D7/D30 retention figures for casual social or async friend games (Draw Something, Words With Friends, GamePigeon) were found.
