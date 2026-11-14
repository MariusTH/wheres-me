// Native iOS glue for Where's Me, without a full Godot plugin (no engine headers).
//
// 1. Share sheet. GDScript calls OS.shell_open("wheresme-share:?text=<percent-encoded>").
//    Godot's iOS shell_open asks UIApplication canOpenURL: and then
//    openURL:options:completionHandler:. Both are swizzled so that our private
//    scheme opens a UIActivityViewController (Messages, WhatsApp, Mail, Copy, ...)
//    instead of leaving the app. Every other URL goes through as usual.
//
// 2. Deep links. wheresme://play?c=WM1-... opens the app (the scheme is
//    registered in Info.plist by addons/wm_ios_native). Godot runs as a
//    UIScene app, so URLs arrive at the scene delegate, at launch in
//    scene:willConnectToSession:options: and later in scene:openURLContexts:.
//    -[UIScene setDelegate:] is swizzled to patch whichever delegate class Godot
//    installs. The URL is written to <Documents>/deeplink.txt (Godot's user://),
//    which DeepLink.gd picks up.
//
// Built into native/ios/build/WMNative.xcframework by tools/build_ios_native.sh
// and linked into the exported Xcode project with -ObjC so +load runs.

#import <UIKit/UIKit.h>
#import <objc/runtime.h>

static NSString *const kWMShareScheme = @"wheresme-share";
static NSString *const kWMLinkScheme = @"wheresme";
static NSString *const kWMLinkFile = @"deeplink.txt";
static NSString *const kWMLogFile = @"wmnative.log";

// Appends a line to <Documents>/wmnative.log, shown by the in-game debug
// console (shake the phone), since NSLog is invisible on TestFlight builds.
static void WMLog(NSString *format, ...) NS_FORMAT_FUNCTION(1, 2);
static void WMLog(NSString *format, ...) {
	va_list args;
	va_start(args, format);
	NSString *msg = [[NSString alloc] initWithFormat:format arguments:args];
	va_end(args);
	NSLog(@"[WMNative] %@", msg);
	@synchronized(kWMLogFile) {
		NSURL *docs = [NSFileManager.defaultManager URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].firstObject;
		NSString *path = [docs URLByAppendingPathComponent:kWMLogFile].path;
		NSDictionary *attrs = [NSFileManager.defaultManager attributesOfItemAtPath:path error:nil];
		if (attrs == nil || attrs.fileSize > 64 * 1024) {
			[@"" writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
		}
		NSDateFormatter *df = [NSDateFormatter new];
		df.dateFormat = @"HH:mm:ss";
		NSString *line = [NSString stringWithFormat:@"%@ %@\n", [df stringFromDate:NSDate.date], msg];
		NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:path];
		[fh seekToEndOfFile];
		[fh writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
		[fh closeFile];
	}
}

// --- share sheet --------------------------------------------------------------

static BOOL WMIsShareURL(NSURL *url) {
	return [url.scheme.lowercaseString isEqualToString:kWMShareScheme];
}

static UIViewController *WMTopViewController(void) {
	UIWindow *window = nil;
	for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
		if (![scene isKindOfClass:UIWindowScene.class]) {
			continue;
		}
		for (UIWindow *w in ((UIWindowScene *)scene).windows) {
			if (w.isKeyWindow) {
				window = w;
				break;
			}
		}
		if (window == nil) {
			window = ((UIWindowScene *)scene).windows.firstObject;
		}
		if (window != nil) {
			break;
		}
	}
	UIViewController *vc = window.rootViewController;
	while (vc.presentedViewController != nil) {
		vc = vc.presentedViewController;
	}
	return vc;
}

static void WMPresentShare(NSURL *url) {
	NSString *text = @"";
	NSURLComponents *components = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
	for (NSURLQueryItem *item in components.queryItems) {
		if ([item.name isEqualToString:@"text"] && item.value != nil) {
			text = item.value;
		}
	}
	dispatch_async(dispatch_get_main_queue(), ^{
		UIViewController *top = WMTopViewController();
		if (top == nil) {
			WMLog(@"share: no view controller to present from");
			return;
		}
		WMLog(@"share: presenting sheet (%lu chars) from %@", (unsigned long)text.length, NSStringFromClass(top.class));
		UIActivityViewController *sheet = [[UIActivityViewController alloc] initWithActivityItems:@[ text ] applicationActivities:nil];
		// iPad presents the sheet as a popover and needs an anchor.
		UIPopoverPresentationController *popover = sheet.popoverPresentationController;
		if (popover != nil) {
			popover.sourceView = top.view;
			CGRect b = top.view.bounds;
			popover.sourceRect = CGRectMake(CGRectGetMidX(b), CGRectGetMaxY(b) - 1, 1, 1);
			popover.permittedArrowDirections = 0;
		}
		[top presentViewController:sheet animated:YES completion:nil];
	});
}

// --- deep links ---------------------------------------------------------------

static void WMDeliverLinks(NSSet<UIOpenURLContext *> *contexts) {
	for (UIOpenURLContext *context in contexts) {
		NSURL *url = context.URL;
		if (![url.scheme.lowercaseString isEqualToString:kWMLinkScheme]) {
			WMLog(@"link: ignoring scheme %@", url.scheme);
			continue;
		}
		NSURL *docs = [NSFileManager.defaultManager URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].firstObject;
		NSError *error = nil;
		BOOL ok = [url.absoluteString writeToURL:[docs URLByAppendingPathComponent:kWMLinkFile] atomically:YES encoding:NSUTF8StringEncoding error:&error];
		WMLog(@"link: received %lu chars, saved=%d %@", (unsigned long)url.absoluteString.length, ok, error.localizedDescription ?: @"");
	}
}

// Replaces (or adds) -sel on cls with block; returns the IMP it replaced, or NULL.
static IMP WMHook(Class cls, SEL sel, const char *types, id block) {
	IMP replacement = imp_implementationWithBlock(block);
	Method existing = class_getInstanceMethod(cls, sel);
	if (existing == NULL) {
		class_addMethod(cls, sel, replacement, types);
		return NULL;
	}
	IMP original = method_getImplementation(existing);
	// Inherited: add an override on cls itself; own method: swap its implementation.
	if (!class_addMethod(cls, sel, replacement, method_getTypeEncoding(existing))) {
		method_setImplementation(existing, replacement);
	}
	return original;
}

static void WMPatchSceneDelegateClass(Class cls) {
	static NSMutableSet<Class> *patched;
	@synchronized(kWMLinkFile) {
		if (patched == nil) {
			patched = [NSMutableSet set];
		}
		if ([patched containsObject:cls]) {
			return;
		}
		[patched addObject:cls];
	}
	WMLog(@"links: patching scene delegate class %@", NSStringFromClass(cls));

	SEL connect = @selector(scene:willConnectToSession:options:);
	__block IMP origConnect = WMHook(cls, connect, "v@:@@@", ^(id me, UIScene *scene, UISceneSession *session, UISceneConnectionOptions *options) {
		WMLog(@"scene connect: %lu URL(s)", (unsigned long)options.URLContexts.count);
		WMDeliverLinks(options.URLContexts);
		if (origConnect != NULL) {
			((void (*)(id, SEL, UIScene *, UISceneSession *, UISceneConnectionOptions *))origConnect)(me, connect, scene, session, options);
		}
	});

	SEL open = @selector(scene:openURLContexts:);
	__block IMP origOpen = WMHook(cls, open, "v@:@@", ^(id me, UIScene *scene, NSSet<UIOpenURLContext *> *contexts) {
		WMLog(@"scene openURLContexts: %lu URL(s)", (unsigned long)contexts.count);
		WMDeliverLinks(contexts);
		if (origOpen != NULL) {
			((void (*)(id, SEL, UIScene *, NSSet<UIOpenURLContext *> *))origOpen)(me, open, scene, contexts);
		}
	});
}

// --- hooks ----------------------------------------------------------------------

@implementation UIScene (WMNative)

- (void)wm_setDelegate:(id<UISceneDelegate>)delegate {
	if (delegate != nil) {
		WMPatchSceneDelegateClass(object_getClass(delegate));
	}
	[self wm_setDelegate:delegate]; // the original, after the exchange
}

@end

@implementation UIApplication (WMNative)

+ (void)load {
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		method_exchangeImplementations(
				class_getInstanceMethod(UIScene.class, @selector(setDelegate:)),
				class_getInstanceMethod(UIScene.class, @selector(wm_setDelegate:)));
		Class cls = UIApplication.class;
		method_exchangeImplementations(
				class_getInstanceMethod(cls, @selector(canOpenURL:)),
				class_getInstanceMethod(cls, @selector(wm_canOpenURL:)));
		method_exchangeImplementations(
				class_getInstanceMethod(cls, @selector(openURL:options:completionHandler:)),
				class_getInstanceMethod(cls, @selector(wm_openURL:options:completionHandler:)));
		NSDictionary *info = NSBundle.mainBundle.infoDictionary;
		WMLog(@"loaded: %@ %@ (%@), iOS %@", info[@"CFBundleIdentifier"], info[@"CFBundleShortVersionString"],
				info[@"CFBundleVersion"], UIDevice.currentDevice.systemVersion);
	});
}

- (BOOL)wm_canOpenURL:(NSURL *)url {
	if (WMIsShareURL(url)) {
		return YES;
	}
	return [self wm_canOpenURL:url];
}

- (void)wm_openURL:(NSURL *)url
		   options:(NSDictionary<UIApplicationOpenExternalURLOptionsKey, id> *)options
 completionHandler:(void (^)(BOOL success))completion {
	if (WMIsShareURL(url)) {
		WMPresentShare(url);
		if (completion != nil) {
			completion(YES);
		}
		return;
	}
	[self wm_openURL:url options:options completionHandler:completion];
}

@end
