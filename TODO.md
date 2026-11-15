# TODO

## Friend groups: challenge each other, fastest find wins
A group of friends (say 3–8 people) can send challenges to the whole group, and everyone sees who found the hider fastest.

- **Groups.** Create a group, invite friends with a code or link, and see the members. A player can be in several groups.
- **Group challenge.** One member hides and sends the challenge to the group. Every other member searches the same town and spot.
- **Leaderboard per challenge.** Find times (and wrong taps) of everyone who played it, ranked fastest first. Show who hasn't played yet.
- **Group standings.** Running totals over all challenges: wins, average time, hides nobody found.
- **Turns (optional).** Rotate who hides next, or let anyone send one at any time.

Today friend games are 1-to-1 and serverless: codes carry the sender id, round and reply (`FriendsStore`, `ChallengeCodec`). A group needs everyone's results in one place, so this needs a backend: the `Leaderboard` and `Matchmaker` seams in `scripts/social/` are the place to plug it in.
