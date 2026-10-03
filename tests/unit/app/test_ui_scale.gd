extends GutTest
## `UiScale` (T-060; `docs/game/ui.md` п. 3, `docs/game/hud.md` п. 3): тип устройства,
## множитель меню и HUD, цели нажатия, безопасная зона в lp, отладочные подмены, растяжение
## холста и автозагрузка в `project.godot`. Основа для REQ-UIX-01 (единая система на всех
## устройствах), REQ-HUD-13 крит. 10 (холст 1280×720, масштаб HUD) и REQ-UIX-05 (цели нажатия).


func after_each() -> void:
	for meta in [UiScale.DEBUG_SAFE_AREA_META, UiScale.DEBUG_DEVICE_META]:
		if Engine.has_meta(meta):
			Engine.remove_meta(meta)
	get_tree().root.content_scale_factor = 1.0


func test_classify_desktop_tablet_phone() -> void:
	assert_eq(UiScale.classify(false, 393.0), UiScale.Device.DESKTOP, "нет сенсорного экрана — компьютер")
	assert_eq(UiScale.classify(false, 1080.0), UiScale.Device.DESKTOP)
	assert_eq(UiScale.classify(true, 393.0), UiScale.Device.PHONE, "iPhone 852×393 pt")
	assert_eq(UiScale.classify(true, 375.0), UiScale.Device.PHONE, "iPhone SE")
	assert_eq(UiScale.classify(true, 412.0), UiScale.Device.PHONE, "Android 915×412 dp")
	assert_eq(UiScale.classify(true, 744.0), UiScale.Device.TABLET, "iPad mini")
	assert_eq(UiScale.classify(true, 1024.0), UiScale.Device.TABLET, "iPad 12.9")
	assert_eq(UiScale.classify(true, 500.0), UiScale.Device.TABLET, "порог 500 pt — уже не телефон")


func test_short_side_pt_uses_screen_scale_or_dpi() -> void:
	assert_almost_eq(UiScale.short_side_pt(Vector2i(2556, 1179), 3.0, 460.0), 393.0, 0.01, "iOS: пиксели / масштаб экрана")
	assert_almost_eq(UiScale.short_side_pt(Vector2i(2400, 1080), 1.0, 420.0), 1080.0 / 2.625, 0.01, "Android: dpi / 160")
	assert_almost_eq(UiScale.short_side_pt(Vector2i(1920, 1080), 1.0, 96.0), 1080.0, 0.01, "плотность ниже 1 не уменьшает")


func test_scale_menu_and_hud_per_device() -> void:
	assert_eq(UiScale.scale_for(UiScale.Device.DESKTOP, UiScale.Mode.MENU), 1.0)
	assert_eq(UiScale.scale_for(UiScale.Device.DESKTOP, UiScale.Mode.HUD), 1.0)
	assert_eq(UiScale.scale_for(UiScale.Device.TABLET, UiScale.Mode.MENU), 1.0)
	assert_eq(UiScale.scale_for(UiScale.Device.TABLET, UiScale.Mode.HUD), 1.0)
	assert_eq(UiScale.scale_for(UiScale.Device.PHONE, UiScale.Mode.MENU), 1.8, "меню телефона — 1.8 (ui.md п. 3)")
	assert_eq(UiScale.scale_for(UiScale.Device.PHONE, UiScale.Mode.HUD), 1.2, "HUD телефона — 1.2 (hud.md п. 3)")


func test_phone_menu_canvas_is_about_867x400_lp() -> void:
	# iPhone 2556×1179 px, канвас 1280×720 с expand: lp по высоте; затем делим на множитель.
	var fit := 1179.0 / 720.0
	var canvas := Vector2(2556.0, 1179.0) / (fit * UiScale.scale_for(UiScale.Device.PHONE, UiScale.Mode.MENU))
	assert_almost_eq(canvas.x, 867.0, 1.0)
	assert_almost_eq(canvas.y, 400.0, 1.0)


func test_touch_targets() -> void:
	assert_eq(UiScale.touch_ui_for(UiScale.Device.DESKTOP), 40.0)
	assert_eq(UiScale.touch_ui_for(UiScale.Device.TABLET), 52.0)
	assert_eq(UiScale.touch_ui_for(UiScale.Device.PHONE), 52.0)
	assert_eq(UiScale.touch_hud_for(UiScale.Device.DESKTOP), 48.0)
	assert_eq(UiScale.touch_hud_for(UiScale.Device.TABLET), 52.0)
	assert_eq(UiScale.touch_hud_for(UiScale.Device.PHONE), 72.0)
	var phone_hud_base_lp := UiScale.touch_hud_for(UiScale.Device.PHONE) * UiScale.scale_for(UiScale.Device.PHONE, UiScale.Mode.HUD)
	assert_almost_eq(phone_hud_base_lp, 86.4, 0.01, "touch_hud·s на телефоне ≈ 86 lp базового холста")


func test_safe_margins_from_rects_converts_px_to_lp() -> void:
	# iPhone: окно на весь экран 2556×1179, безопасная зона без 177 px слева/справа и 63 px снизу.
	var window := Rect2i(0, 0, 2556, 1179)
	var safe := Rect2i(177, 0, 2556 - 354, 1179 - 63)
	var px_per_lp := 1179.0 / 720.0 * 1.2
	var m := UiScale.safe_margins_from_rects(safe, window, px_per_lp)
	assert_almost_eq(m[SIDE_LEFT], 177.0 / px_per_lp, 0.001)
	assert_almost_eq(m[SIDE_RIGHT], 177.0 / px_per_lp, 0.001)
	assert_eq(m[SIDE_TOP], 0.0)
	assert_almost_eq(m[SIDE_BOTTOM], 63.0 / px_per_lp, 0.001)


func test_safe_margins_clamped_and_empty_safe_area_is_zero() -> void:
	# Окно целиком внутри безопасной зоны (компьютер) — отступов нет.
	assert_eq(UiScale.safe_margins_from_rects(Rect2i(0, 25, 1920, 1055), Rect2i(100, 100, 1280, 720), 1.0), Vector4.ZERO)
	assert_eq(UiScale.safe_margins_from_rects(Rect2i(), Rect2i(0, 0, 1280, 720), 1.0), Vector4.ZERO)
	assert_eq(UiScale.safe_margins_from_rects(Rect2i(0, 0, 10, 10), Rect2i(0, 0, 1280, 720), 0.0), Vector4.ZERO)


func test_debug_safe_area_override_vector4_and_dictionary() -> void:
	assert_null(UiScale.debug_safe_area())
	Engine.set_meta(UiScale.DEBUG_SAFE_AREA_META, Vector4(100, 0, 100, 13))
	assert_eq(UiScale.debug_safe_area(), Vector4(100, 0, 100, 13))
	Engine.set_meta(UiScale.DEBUG_SAFE_AREA_META, {"left": 100, "right": 100, "top": 0, "bottom": 13})
	assert_eq(UiScale.debug_safe_area(), Vector4(100, 0, 100, 13))
	var node: UiScale = autofree(UiScale.new())
	add_child(node)
	assert_eq(node.safe_margins(), Vector4(100, 0, 100, 13), "узел отдаёт подменённую зону")


func test_debug_device_override() -> void:
	Engine.set_meta(UiScale.DEBUG_DEVICE_META, "phone")
	assert_eq(UiScale.detect_device(), UiScale.Device.PHONE)
	Engine.set_meta(UiScale.DEBUG_DEVICE_META, "tablet")
	assert_eq(UiScale.detect_device(), UiScale.Device.TABLET)
	Engine.remove_meta(UiScale.DEBUG_DEVICE_META)
	assert_eq(UiScale.detect_device(), UiScale.Device.DESKTOP, "headless без сенсорного экрана — компьютер")


func test_set_mode_switches_window_scale_and_restores() -> void:
	var window := get_tree().root
	var before := window.content_scale_factor
	var node: UiScale = autofree(UiScale.new())
	node.device = UiScale.Device.PHONE
	add_child(node) # _ready определяет устройство заново (headless — компьютер)
	assert_eq(node.device, UiScale.Device.DESKTOP)
	assert_eq(window.content_scale_factor, 1.0)
	node.device = UiScale.Device.PHONE
	watch_signals(node)
	node.set_mode(UiScale.Mode.HUD)
	assert_almost_eq(window.content_scale_factor, 1.2, 0.0001)
	assert_signal_emitted_with_parameters(node, "scale_changed", [1.2])
	assert_eq(node.touch_hud(), 72.0)
	node.set_mode(UiScale.Mode.MENU)
	assert_almost_eq(window.content_scale_factor, 1.8, 0.0001)
	assert_eq(node.touch_ui(), 52.0)
	window.content_scale_factor = before


func test_project_stretch_and_autoload() -> void:
	assert_eq(ProjectSettings.get_setting("display/window/size/viewport_width"), 1280)
	assert_eq(ProjectSettings.get_setting("display/window/size/viewport_height"), 720)
	assert_eq(ProjectSettings.get_setting("display/window/stretch/mode"), "canvas_items")
	assert_eq(ProjectSettings.get_setting("display/window/stretch/aspect"), "expand")
	assert_eq(ProjectSettings.get_setting("autoload/UiScaleRuntime"), "*res://src/app/ui_scale.gd")
	var runtime := get_tree().root.get_node_or_null("UiScaleRuntime")
	assert_not_null(runtime, "автозагрузка UiScaleRuntime поднята")
	assert_true(runtime is UiScale)
	assert_eq(get_tree().root.content_scale_factor, 1.0, "headless — компьютер, меню 1.0")
