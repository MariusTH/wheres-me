class_name DeepLink
extends RefCounted
## wheresme://play?c=WM1-… links: tapping one opens the app straight into that
## challenge (same seed, same hiding spot) instead of copy-paste.
## Where links arrive:
##   iOS      native/ios/WMNative.m writes the opened URL to user://deeplink.txt
##   desktop  --link=wheresme://play?c=… after "--" on the command line
##   web      ?c=WM1-… in the page URL (local testing; itch.io's iframe drops it)
## AppState polls take() and opens what it returns.

const SCHEME := "wheresme"
const INBOX := "user://deeplink.txt"


## The link for a share code. The code is base64url, so it needs no escaping.
## ChallengeCodec.decode() reads the link (or a whole message ending in it) too.
static func make(code: String) -> String:
	return "%s://play?c=%s" % [SCHEME, code]


## The code in [param url], or "" if it isn't one of our links.
static func code_from(url: String) -> String:
	var s := url.strip_edges().uri_decode()
	var at := s.find(ChallengeCodec.CODE_PREFIX)
	if at < 0:
		return ""
	var code := s.substr(at)
	for stop in ["&", "#", " ", "\n"]:
		var end := code.find(stop)
		if end >= 0:
			code = code.substr(0, end)
	return code


## A link waiting to be opened, or "". Each link is returned once.
static func take() -> String:
	if OS.get_name() == "iOS" and FileAccess.file_exists(INBOX):
		var url := FileAccess.get_file_as_string(INBOX)
		DirAccess.remove_absolute(INBOX)
		return code_from(url)
	return ""


## The code in the page URL on the web build, or "".
static func from_web_page() -> String:
	if not OS.has_feature("web"):
		return ""
	return code_from(String(JavaScriptBridge.eval("window.location.search || ''", true)))
