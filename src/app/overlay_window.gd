class_name OverlayWindow
extends RefCounted
## Window mode of the mini-HUD (T-177 spike): the app window becomes a small borderless,
## always-on-top, per-pixel transparent window in the top-right corner of the screen; only the plate
## takes the mouse (`mouse_passthrough_polygon`), the rest passes clicks to the app below. `exit()`
## restores size, position, flags and the canvas size exactly as they were.
##
## The platform part (macOS: show over full-screen apps in every Space, raised window level, App Nap
## guard) lives in the GDExtension class `OvoschWindow` (`native/ble/src/ovosch_window.*`). It is
## optional: without the extension (headless, Linux, stub builds) `native` is null and the call is
## skipped. Tests inject any object with `set_overlay(handle, enabled)`, `begin_activity(reason)`,
## `end_activity()`.

const NATIVE_CLASS: StringName = &"OvoschWindow"
## Gap between the window and the screen edges, lp.
const SCREEN_MARGIN_LP: float = 24.0
const ACTIVITY_REASON: String = "ovosch-rider: workout in progress (mini-HUD)"

## Native helper (`OvoschWindow` or a test double); null — none.
var native: Object = null
var _window: Window = null
var _saved: Dictionary = {}
var _native_applied: bool = false


func _init(native_helper: Object = null) -> void:
	native = native_helper


## The GDExtension helper if it is loaded, else null.
static func create_native() -> Object:
	if ClassDB.class_exists(NATIVE_CLASS) and ClassDB.can_instantiate(NATIVE_CLASS):
		return ClassDB.instantiate(NATIVE_CLASS)
	return null


## The platform helper is loaded and the platform supports the overlay.
static func native_available() -> bool:
	var helper := create_native()
	return helper != null and bool(helper.call("is_available"))


func is_active() -> bool:
	return _window != null


## The native part was applied on `enter` (the extension is present and accepted the window).
func is_native_applied() -> bool:
	return _native_applied


## Turn `window` into the overlay: canvas `size_lp`, clickable part `clickable_lp` (in canvas lp).
func enter(window: Window, size_lp: Vector2i, clickable_lp: Rect2) -> void:
	if window == null or is_active():
		return
	_window = window
	_saved = {
		"size": window.size,
		"position": window.position,
		"borderless": window.borderless,
		"always_on_top": window.always_on_top,
		"transparent": window.transparent,
		"transparent_bg": window.transparent_bg,
		"unresizable": window.unresizable,
		"mouse_passthrough_polygon": window.mouse_passthrough_polygon,
		"content_scale_size": window.content_scale_size,
	}
	var px_per_lp: float = _px_per_lp(window)
	var size_px := Vector2i(roundi(size_lp.x * px_per_lp), roundi(size_lp.y * px_per_lp))
	# Stretch maps `content_scale_size` onto the window and then multiplies by the interface factor:
	# with the base size scaled by the factor the visible canvas is exactly `size_lp`.
	var factor: float = maxf(window.content_scale_factor, 0.01)
	window.content_scale_size = Vector2i(roundi(size_lp.x * factor), roundi(size_lp.y * factor))
	window.borderless = true
	window.unresizable = true
	window.transparent = true
	window.transparent_bg = true
	window.always_on_top = true
	window.size = size_px
	window.position = _corner_position(window, size_px, px_per_lp)
	window.mouse_passthrough_polygon = passthrough_polygon(clickable_lp, px_per_lp)
	_native_applied = false
	if native != null:
		var handle: int = DisplayServer.window_get_native_handle(DisplayServer.WINDOW_HANDLE, window.get_window_id())
		_native_applied = bool(native.call("set_overlay", handle, true))
		native.call("begin_activity", ACTIVITY_REASON)


## Back to the normal window.
func exit() -> void:
	if not is_active():
		return
	var window := _window
	if native != null:
		var handle: int = DisplayServer.window_get_native_handle(DisplayServer.WINDOW_HANDLE, window.get_window_id())
		native.call("set_overlay", handle, false)
		native.call("end_activity")
	window.mouse_passthrough_polygon = _saved["mouse_passthrough_polygon"]
	window.always_on_top = _saved["always_on_top"]
	window.transparent_bg = _saved["transparent_bg"]
	window.transparent = _saved["transparent"]
	window.borderless = _saved["borderless"]
	window.unresizable = _saved["unresizable"]
	window.content_scale_size = _saved["content_scale_size"]
	window.size = _saved["size"]
	window.position = _saved["position"]
	_window = null
	_saved = {}
	_native_applied = false


## Clickable part of the window in window pixels (outside it clicks pass through).
static func passthrough_polygon(rect_lp: Rect2, px_per_lp: float) -> PackedVector2Array:
	var r := Rect2(rect_lp.position * px_per_lp, rect_lp.size * px_per_lp)
	return PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])


## Window pixels per canvas lp: the screen scale (Retina 2) times the interface factor.
static func _px_per_lp(window: Window) -> float:
	var screen_scale: float = DisplayServer.screen_get_scale(window.current_screen)
	if screen_scale <= 0.0:
		screen_scale = 1.0
	return screen_scale * maxf(window.content_scale_factor, 0.01)


## Top-right corner of the usable screen area with a margin.
static func _corner_position(window: Window, size_px: Vector2i, px_per_lp: float) -> Vector2i:
	var usable: Rect2i = DisplayServer.screen_get_usable_rect(window.current_screen)
	if usable.size.x <= 0 or usable.size.y <= 0:
		return window.position
	var margin := roundi(SCREEN_MARGIN_LP * px_per_lp)
	return Vector2i(usable.end.x - size_px.x - margin, usable.position.y + margin)
