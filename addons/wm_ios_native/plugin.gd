@tool
extends EditorPlugin
## Adds the native glue (native/ios/WMNative.m: share sheet + wheresme://
## deep links, built by tools/build_ios_native.sh) to iOS exports.
## See NativeShare and DeepLink.

var _export: EditorExportPlugin


func _enter_tree() -> void:
	_export = WMNativeExport.new()
	add_export_plugin(_export)


func _exit_tree() -> void:
	remove_export_plugin(_export)
	_export = null


class WMNativeExport extends EditorExportPlugin:
	const LIB := "res://native/ios/build/WMNative.xcframework"

	func _get_name() -> String:
		return "WMIosNative"

	func _supports_platform(platform: EditorExportPlatform) -> bool:
		return platform is EditorExportPlatformIOS

	func _export_begin(features: PackedStringArray, _is_debug: bool, _path: String, _flags: int) -> void:
		if not features.has("ios"):
			return
		# Register wheresme:// so links in messages open the app.
		add_apple_embedded_platform_plist_content("""<key>CFBundleURLTypes</key>
<array><dict>
<key>CFBundleURLName</key><string>com.caboodle.app.deeplink</string>
<key>CFBundleURLSchemes</key><array><string>%s</string></array>
</dict></array>
<key>LSApplicationQueriesSchemes</key><array><string>sms</string></array>""" % DeepLink.SCHEME)
		if not DirAccess.dir_exists_absolute(LIB):
			push_warning("WMNative.xcframework missing: no share sheet or deep links in this iOS build. Run tools/build_ios_native.sh first.")
			return
		add_apple_embedded_platform_framework(LIB)  # links (no embed); handles .xcframework dirs
		# Load every Objective-C object in static libs, so WMNative's +load runs.
		add_apple_embedded_platform_linker_flags("-ObjC")
