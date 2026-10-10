// OvoschWindow — GDExtension helper for the mini-HUD window mode (T-177 spike). Used by
// src/app/overlay_window.gd through Object.call; optional: without the extension GDScript skips
// the call. Platform code — window_overlay.h.
#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <cstdint>
#include <godot_cpp/variant/string.hpp>

#include "window_overlay.h"

namespace ovosch {

class OvoschWindow : public godot::RefCounted {
	GDCLASS(OvoschWindow, godot::RefCounted)

public:
	OvoschWindow() = default;
	~OvoschWindow() override;

	// The platform supports the overlay (macOS).
	bool is_available() const;
	// `native_window` — DisplayServer.window_get_native_handle(WINDOW_HANDLE, id).
	bool set_overlay(int64_t native_window, bool enabled);
	// App Nap guard for the time the window is not focused; a second call keeps one activity.
	bool begin_activity(const godot::String &reason);
	void end_activity();

protected:
	static void _bind_methods();

private:
	window_overlay::SavedWindowState saved_;
	void *activity_ = nullptr;
};

} // namespace ovosch
