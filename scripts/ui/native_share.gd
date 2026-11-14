class_name NativeShare
extends RefCounted
## The phone's own share sheet in the native iOS app (Messages, WhatsApp, Mail,
## Copy, ...). On the web build WebTap does this instead.
## Works through OS.shell_open with a private URL scheme that
## native/ios/WMShare.m intercepts; no Godot plugin singleton needed.

const SCHEME := "wheresme-share"


static func available() -> bool:
	return OS.get_name() == "iOS"


## Opens the share sheet with [param text]. Falls back to a prefilled text
## message, then to the clipboard. Returns what happened: "shared", "sms" or
## "copied".
static func share(text: String) -> String:
	if OS.shell_open("%s:?text=%s" % [SCHEME, text.uri_encode()]) == OK:
		return "shared"
	if OS.shell_open("sms:&body=%s" % text.uri_encode()) == OK:
		return "sms"
	DisplayServer.clipboard_set(text)
	return "copied"
