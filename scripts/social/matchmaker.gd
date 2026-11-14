class_name Matchmaker
extends RefCounted
## "Play with random" seam. Today there is no server, so a random opponent is
## a practice partner: a computer player who hides with AutoHider and searches
## your hiding spots (FriendsStore.bot_searches). An online matchmaker would
## pair you with a real player's waiting code instead and return a normal
## friend id; the Friends screen doesn't need to change.


## Whether random opponents are real people yet.
static func is_online() -> bool:
	return false


## Starts a game with a random opponent at [param difficulty]; returns the
## friend id to play with.
static func find_random(difficulty: String) -> String:
	return FriendsStore.create_bot(difficulty)
