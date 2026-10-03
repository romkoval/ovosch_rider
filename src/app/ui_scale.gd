class_name UiScale
extends Node
## Масштаб интерфейса, цели нажатия и безопасная зона (`docs/game/ui.md` п. 3,
## `docs/game/hud.md` п. 3; REQ-UIX-01, REQ-HUD-13 крит. 10, REQ-UIX-05).
##
## Холст — 1280×720 lp, растяжение `canvas_items` + `expand` (`project.godot`). Поверх него
## `Window.content_scale_factor` = множитель интерфейса:
## - меню: компьютер и планшет 1.0, телефон 1.8 (холст iPhone ≈ 867×400 lp);
## - HUD (экран заезда): компьютер и планшет 1.0, телефон 1.2.
## Экран заезда переключает режим вызовом `set_mode(Mode.HUD)` при входе и
## `set_mode(Mode.MENU)` при выходе.
##
## Узел регистрируется в `project.godot` автозагрузкой `UiScaleRuntime` и применяет
## множитель меню при старте, поэтому `main.gd` его не вызывает. Чистые функции
## (`classify`, `scale_for`, `touch_ui_for`, `touch_hud_for`, `safe_margins_from_rects`)
## тестируются без окна.
##
## Тип устройства определяется без `OS.*` (REQ-NFR-06 крит. 1): сенсорный экран
## (`DisplayServer.is_touchscreen_available()`) и короткая сторона экрана в pt/dp.
## Нет сенсорного экрана — компьютер; есть и короткая сторона < 500 pt — телефон;
## иначе планшет.
##
## Отладка (снимки UI, T-059): `Engine.set_meta("ui_debug_safe_area", …)` подменяет
## безопасную зону — `Vector4(слева, сверху, справа, снизу)` в lp (порядок `Side`) или
## `Dictionary` с ключами `left`, `top`, `right`, `bottom`; `Engine.set_meta("ui_debug_device",
## "phone" | "tablet" | "desktop")` подменяет тип устройства.

signal scale_changed(scale: float)

enum Device { DESKTOP, TABLET, PHONE }
enum Mode { MENU, HUD }

const BASE_SIZE: Vector2i = Vector2i(1280, 720)
## Порог «телефона» по короткой стороне экрана, pt (iOS) / dp (Android).
const PHONE_MAX_SHORT_SIDE_PT: float = 500.0
## Точек на дюйм, соответствующих 1 dp (Android) — для перевода пикселей в pt/dp.
const DP_DPI: float = 160.0

const MENU_SCALE_DESKTOP: float = 1.0
const MENU_SCALE_TABLET: float = 1.0
const MENU_SCALE_PHONE: float = 1.8
const HUD_SCALE_DESKTOP: float = 1.0
const HUD_SCALE_TABLET: float = 1.0
const HUD_SCALE_PHONE: float = 1.2

## `touch_ui` (`ui.md` п. 3): минимальная сторона интерактивного элемента меню, lp.
const TOUCH_UI_DESKTOP: float = 40.0
const TOUCH_UI_TOUCH: float = 52.0
## `touch_hud` (`hud.md` п. 3): цель нажатия кнопок HUD в lp HUD (до множителя `s`);
## физически `touch_hud·s` = 48 / 52 / 86 lp базового холста.
const TOUCH_HUD_DESKTOP: float = 48.0
const TOUCH_HUD_TABLET: float = 52.0
const TOUCH_HUD_PHONE: float = 72.0

const DEBUG_SAFE_AREA_META: StringName = &"ui_debug_safe_area"
const DEBUG_DEVICE_META: StringName = &"ui_debug_device"
const DEVICE_NAMES: Dictionary = {"desktop": Device.DESKTOP, "tablet": Device.TABLET, "phone": Device.PHONE}

var device: Device = Device.DESKTOP
var mode: Mode = Mode.MENU


func _ready() -> void:
	device = detect_device()
	set_mode(Mode.MENU)


## Переключает режим (меню / экран заезда) и применяет множитель к окну.
func set_mode(new_mode: Mode) -> void:
	mode = new_mode
	var s := current_scale()
	var window := get_window()
	if window != null and not is_equal_approx(window.content_scale_factor, s):
		window.content_scale_factor = s
	scale_changed.emit(s)


## Текущий множитель интерфейса.
func current_scale() -> float:
	return scale_for(device, mode)


## `touch_ui` для текущего устройства, lp.
func touch_ui() -> float:
	return touch_ui_for(device)


## `touch_hud` для текущего устройства, lp HUD.
func touch_hud() -> float:
	return touch_hud_for(device)


## Отступы безопасной зоны окна в lp текущего холста: `Vector4(слева, сверху, справа, снизу)`.
func safe_margins() -> Vector4:
	var debug: Variant = debug_safe_area()
	if debug != null:
		return debug
	var window := get_window()
	if window == null:
		return Vector4.ZERO
	var window_rect := Rect2i(window.position, window.size)
	var px_per_lp := _px_per_lp(window)
	return safe_margins_from_rects(DisplayServer.get_display_safe_area(), window_rect, px_per_lp)


## Множитель интерфейса для устройства и режима.
static func scale_for(dev: Device, for_mode: Mode) -> float:
	match dev:
		Device.PHONE:
			return MENU_SCALE_PHONE if for_mode == Mode.MENU else HUD_SCALE_PHONE
		Device.TABLET:
			return MENU_SCALE_TABLET if for_mode == Mode.MENU else HUD_SCALE_TABLET
		_:
			return MENU_SCALE_DESKTOP if for_mode == Mode.MENU else HUD_SCALE_DESKTOP


static func touch_ui_for(dev: Device) -> float:
	return TOUCH_UI_DESKTOP if dev == Device.DESKTOP else TOUCH_UI_TOUCH


static func touch_hud_for(dev: Device) -> float:
	match dev:
		Device.PHONE:
			return TOUCH_HUD_PHONE
		Device.TABLET:
			return TOUCH_HUD_TABLET
		_:
			return TOUCH_HUD_DESKTOP


## Тип устройства по наличию сенсорного экрана и короткой стороне экрана в pt/dp.
static func classify(has_touchscreen: bool, short_side_pt: float) -> Device:
	if not has_touchscreen:
		return Device.DESKTOP
	return Device.PHONE if short_side_pt < PHONE_MAX_SHORT_SIDE_PT else Device.TABLET


## Короткая сторона экрана в pt/dp: пиксели делятся на плотность — масштаб экрана
## (iOS, macOS) или `dpi / 160` (Android), что больше.
static func short_side_pt(screen_px: Vector2i, screen_scale: float, screen_dpi: float) -> float:
	var density := maxf(maxf(screen_scale, screen_dpi / DP_DPI), 1.0)
	return float(mini(screen_px.x, screen_px.y)) / density


## Тип устройства текущего экрана (с учётом отладочной подмены).
static func detect_device() -> Device:
	if Engine.has_meta(DEBUG_DEVICE_META):
		var name := str(Engine.get_meta(DEBUG_DEVICE_META)).to_lower()
		if DEVICE_NAMES.has(name):
			var forced: Device = DEVICE_NAMES[name]
			return forced
		push_warning("UiScale: unknown %s value '%s'" % [DEBUG_DEVICE_META, name])
	var screen := DisplayServer.window_get_current_screen()
	var side := short_side_pt(DisplayServer.screen_get_size(screen), DisplayServer.screen_get_scale(screen), float(DisplayServer.screen_get_dpi(screen)))
	return classify(DisplayServer.is_touchscreen_available(), side)


## Отладочная безопасная зона из `Engine` meta в lp или `null`, если подмены нет.
static func debug_safe_area() -> Variant:
	if not Engine.has_meta(DEBUG_SAFE_AREA_META):
		return null
	var value: Variant = Engine.get_meta(DEBUG_SAFE_AREA_META)
	if value is Vector4:
		return value
	if value is Dictionary:
		var d: Dictionary = value
		return Vector4(float(d.get("left", 0.0)), float(d.get("top", 0.0)), float(d.get("right", 0.0)), float(d.get("bottom", 0.0)))
	push_warning("UiScale: %s must be Vector4 or Dictionary" % DEBUG_SAFE_AREA_META)
	return null


## Отступы безопасной зоны в lp по прямоугольникам в пикселях экрана: части окна, не
## попавшие в безопасную зону, делённые на число пикселей в одном lp. Отрицательные → 0.
static func safe_margins_from_rects(safe_px: Rect2i, window_px: Rect2i, px_per_lp: float) -> Vector4:
	if px_per_lp <= 0.0 or not safe_px.has_area():
		return Vector4.ZERO
	var left := maxi(safe_px.position.x - window_px.position.x, 0)
	var top := maxi(safe_px.position.y - window_px.position.y, 0)
	var right := maxi(window_px.end.x - safe_px.end.x, 0)
	var bottom := maxi(window_px.end.y - safe_px.end.y, 0)
	return Vector4(left, top, right, bottom) / px_per_lp


## Пикселей окна в одном lp текущего холста (растяжение `canvas_items` + `expand`).
static func _px_per_lp(window: Window) -> float:
	var base := Vector2(window.content_scale_size)
	if base.x <= 0.0 or base.y <= 0.0:
		base = Vector2(BASE_SIZE)
	var fit := minf(window.size.x / base.x, window.size.y / base.y)
	return fit * window.content_scale_factor
