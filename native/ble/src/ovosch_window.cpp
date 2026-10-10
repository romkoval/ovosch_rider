#include "ovosch_window.h"

#include <godot_cpp/core/class_db.hpp>

#include <cstdint>

using namespace godot;

namespace ovosch {

OvoschWindow::~OvoschWindow() {
	end_activity();
}

void OvoschWindow::_bind_methods() {
	ClassDB::bind_method(D_METHOD("is_available"), &OvoschWindow::is_available);
	ClassDB::bind_method(D_METHOD("set_overlay", "native_window", "enabled"), &OvoschWindow::set_overlay);
	ClassDB::bind_method(D_METHOD("begin_activity", "reason"), &OvoschWindow::begin_activity);
	ClassDB::bind_method(D_METHOD("end_activity"), &OvoschWindow::end_activity);
}

bool OvoschWindow::is_available() const {
	return window_overlay::available();
}

bool OvoschWindow::set_overlay(int64_t native_window, bool enabled) {
	void *handle = reinterpret_cast<void *>(static_cast<intptr_t>(native_window));
	return window_overlay::set_overlay(handle, enabled, saved_);
}

bool OvoschWindow::begin_activity(const String &reason) {
	if (activity_ != nullptr) {
		return true;
	}
	activity_ = window_overlay::begin_activity(std::string(reason.utf8().get_data()));
	return activity_ != nullptr;
}

void OvoschWindow::end_activity() {
	if (activity_ == nullptr) {
		return;
	}
	window_overlay::end_activity(activity_);
	activity_ = nullptr;
}

} // namespace ovosch
