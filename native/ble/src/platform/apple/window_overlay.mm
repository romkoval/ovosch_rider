// Overlay window helpers on Apple platforms (T-177 spike, mini-HUD).
// macOS: the NSWindow joins all Spaces and may sit next to full-screen apps
// (canJoinAllSpaces | fullScreenAuxiliary) at the status window level, so the mini-HUD stays
// visible over full-screen video. iOS: no windows to raise — only the activity guard works.
// App Nap guard: NSProcessInfo beginActivityWithOptions (user initiated, latency critical) keeps
// BLE, ERG commands and the 1 Hz recording on time while the app is not focused.
#include "../../window_overlay.h"

#import <Foundation/Foundation.h>
#include <TargetConditionals.h>
#if TARGET_OS_OSX
#import <AppKit/AppKit.h>
#endif

namespace ovosch {
namespace window_overlay {

bool available() {
#if TARGET_OS_OSX
	return true;
#else
	return false;
#endif
}

bool set_overlay(void *native_window, bool enabled, SavedWindowState &saved) {
#if TARGET_OS_OSX
	if (native_window == nullptr) {
		return false;
	}
	SavedWindowState *state = &saved;
	void (^apply)(void) = ^{
		NSWindow *window = (__bridge NSWindow *)native_window;
		if (enabled) {
			if (!state->valid) {
				state->level = (long)window.level;
				state->collection_behavior = (unsigned long)window.collectionBehavior;
				state->valid = true;
			}
			NSWindowCollectionBehavior behavior = window.collectionBehavior;
			// canJoinAllSpaces and moveToActiveSpace are mutually exclusive.
			behavior &= ~NSWindowCollectionBehaviorMoveToActiveSpace;
			behavior |= NSWindowCollectionBehaviorCanJoinAllSpaces | NSWindowCollectionBehaviorFullScreenAuxiliary;
			window.collectionBehavior = behavior;
			window.level = NSStatusWindowLevel;
			window.hidesOnDeactivate = NO;
		} else if (state->valid) {
			window.collectionBehavior = (NSWindowCollectionBehavior)state->collection_behavior;
			window.level = (NSWindowLevel)state->level;
			state->valid = false;
		}
	};
	if ([NSThread isMainThread]) {
		apply();
	} else {
		dispatch_sync(dispatch_get_main_queue(), apply);
	}
	return true;
#else
	(void)native_window;
	(void)enabled;
	(void)saved;
	return false;
#endif
}

void *begin_activity(const std::string &reason) {
	NSString *text = [NSString stringWithUTF8String:reason.c_str()];
	id<NSObject> token = [[NSProcessInfo processInfo]
			beginActivityWithOptions:(NSActivityUserInitiated | NSActivityLatencyCritical)
							  reason:(text != nil ? text : @"ovosch-rider")];
	return (__bridge_retained void *)token;
}

void end_activity(void *token) {
	if (token == nullptr) {
		return;
	}
	id<NSObject> activity = (__bridge_transfer id<NSObject>)token;
	[[NSProcessInfo processInfo] endActivity:activity];
}

} // namespace window_overlay
} // namespace ovosch
