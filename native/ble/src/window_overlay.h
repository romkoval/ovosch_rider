// Overlay window helpers for the mini-HUD (T-177 spike) — plain C++ interface without godot-cpp.
// Implementations: platform/apple/window_overlay.mm (macOS: NSWindow + NSProcessInfo),
// window_overlay_null.cpp (everywhere else: no-op, `available()` == false).
#pragma once

#include <string>

namespace ovosch {
namespace window_overlay {

// Window state saved on enable and restored on disable.
struct SavedWindowState {
	bool valid = false;
	long level = 0;
	unsigned long collection_behavior = 0;
};

// The platform can raise a window over full-screen apps.
bool available();

// `native_window` — NSWindow* from DisplayServer.window_get_native_handle(WINDOW_HANDLE).
// enabled: join all Spaces, show next to full-screen apps (fullScreenAuxiliary), raised level;
// disabled: restore `saved`. Returns true if applied.
bool set_overlay(void *native_window, bool enabled, SavedWindowState &saved);

// App Nap guard: an opaque activity token (nullptr — not supported) and its end.
void *begin_activity(const std::string &reason);
void end_activity(void *token);

} // namespace window_overlay
} // namespace ovosch
