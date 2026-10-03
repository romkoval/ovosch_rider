extends GutTest
## Компоненты управления HUD (T-074, `docs/game/hud.md` п. 10): фишка «ДАЛЕЕ»
## (REQ-HUD-06 крит. 2 — отображение «скоро смена»), карточка паузы (REQ-WRK-05 — пауза,
## возобновление, досрочное завершение с подтверждением крит. 4), панель инструментов
## (REQ-WRK-03 крит. 1 — ERG одним действием; REQ-FRD-05 крит. 4, 6 — SIM ↔ сопротивление
## и крутизна) и горячие клавиши. Критерии карточки: панель скрыта через 4 ± 0.5 с без
## ввода; в свободной езде нет «Пропустить шаг» и ERG; каждая кнопка и клавиша выдаёт свой
## сигнал; цели нажатия ≥ 44 lp.

const PAUSE_SCENE: String = "res://src/ui/hud/pause_overlay.tscn"
const TOOLBAR_SCENE: String = "res://src/ui/hud/hud_toolbar.tscn"
const MIN_TOUCH_LP: float = 44.0

var _previous_locale: String


func before_each() -> void:
	_previous_locale = TranslationServer.get_locale()
	TranslationServer.set_locale("ru")


func after_each() -> void:
	TranslationServer.set_locale(_previous_locale)


func _toolbar() -> HudToolbar:
	var t: HudToolbar = (load(TOOLBAR_SCENE) as PackedScene).instantiate()
	add_child_autofree(t)
	t.set_compact(false)
	t.set_touch_target(UiScale.TOUCH_HUD_DESKTOP)
	return t


func _overlay() -> PauseOverlay:
	var o: PauseOverlay = (load(PAUSE_SCENE) as PackedScene).instantiate()
	add_child_autofree(o)
	return o


func _key(keycode: Key, physical: Key = KEY_NONE, unicode: int = 0) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = keycode
	e.physical_keycode = physical
	e.unicode = unicode
	e.pressed = true
	return e


func _names(buttons: Array[Button]) -> Array[String]:
	var out: Array[String] = []
	for b in buttons:
		out.append(String(b.name))
	return out


func _assert_touch(buttons: Array[Button], where: String) -> void:
	assert_gt(buttons.size(), 0, where + ": кнопки есть")
	for b in buttons:
		var s := b.get_combined_minimum_size()
		assert_true(s.x >= MIN_TOUCH_LP and s.y >= MIN_TOUCH_LP, "%s: %s %s ≥ 44 lp" % [where, b.name, s])


# ---------------------------------------------------------------------------
# NextChip — REQ-HUD-06 крит. 2
# ---------------------------------------------------------------------------

func test_req_hud_06_c2_next_chip_shows_next_step_and_seconds() -> void:
	var chip := NextChip.new()
	add_child_autofree(chip)
	assert_false(chip.is_shown(), "до «скоро смена» фишки нет")
	assert_false(chip.visible)
	var zone := ZonePalette.color(ZonePalette.power_token(5))
	chip.show_next(60, NextChip.format_target(125), zone)
	chip.set_seconds_left(5)
	assert_true(chip.is_shown())
	assert_true(chip.visible)
	assert_eq(chip.line_text(), "1:00 · 125 Вт")
	assert_eq(chip.seconds_text(), "5")
	assert_eq(chip.zone_color(), zone, "полоса — цвет зоны следующего шага")
	chip.set_seconds_left(1)
	assert_eq(chip.seconds_text(), "1")
	chip.set_seconds_left(9)
	assert_eq(chip.seconds_text(), "5", "секунды ограничены 5")
	chip.hide_chip()
	assert_false(chip.is_shown(), "на смене шага фишка уходит")


func test_req_hud_06_c2_next_chip_fades_in_200ms() -> void:
	var chip := NextChip.new()
	add_child_autofree(chip)
	chip.show_next(30, NextChip.format_target(200), Color.RED)
	assert_almost_eq(chip.modulate.a, 0.0, 0.01, "появление начинается с прозрачности 0")
	await wait_seconds(NextChip.FADE_SEC + 0.15)
	assert_almost_eq(chip.modulate.a, 1.0, 0.01, "за 200 мс — полностью видна")
	chip.hide_chip()
	await wait_seconds(NextChip.FADE_SEC + 0.15)
	assert_false(chip.visible, "после исчезания узел скрыт")


func test_req_hud_06_c2_next_chip_formats() -> void:
	assert_eq(NextChip.format_duration(60), "1:00")
	assert_eq(NextChip.format_duration(605), "10:05")
	assert_eq(NextChip.format_duration(3600), "1:00:00")
	assert_eq(NextChip.format_target(125), "125 Вт")
	assert_eq(NextChip.format_target(125, 225), "125→225 Вт")
	assert_eq(NextChip.format_target(-1), "свободно")
	TranslationServer.set_locale("en")
	assert_eq(NextChip.format_target(125), "125 W")
	assert_eq(NextChip.format_target(-1), "free ride")


func test_req_hud_06_c2_next_chip_fits_hint_slot() -> void:
	var chip := NextChip.new()
	add_child_autofree(chip)
	chip.show_next(3600, NextChip.format_target(1250, 1500), Color.RED)
	var s := chip.get_combined_minimum_size()
	assert_true(s.y <= NextChip.HEIGHT_LP + 0.5, "высота фишки ≤ 40 lp (слот подсказки), %s" % s)
	assert_true(s.x <= 640.0, "ширина ≤ 0.5·W на 1280, %s" % s)


# ---------------------------------------------------------------------------
# PauseOverlay — REQ-WRK-05
# ---------------------------------------------------------------------------

func test_req_wrk_05_pause_card_with_veil_and_buttons() -> void:
	var o := _overlay()
	assert_false(o.is_shown(), "без паузы вуали нет")
	assert_false(o.visible)
	o.show_pause()
	assert_true(o.is_shown())
	assert_true(o.visible)
	assert_eq(o.view(), PauseOverlay.View.PAUSE)
	var veil: ColorRect = o.get_node("%Veil")
	assert_eq(veil.color, UiTokens.HUD_PAUSE_VEIL, "вуаль hud.ink 0.35")
	assert_eq(_names(o.visible_buttons()), ["ResumeButton", "SkipButton", "FinishButton"] as Array[String])
	_assert_touch(o.visible_buttons(), "карточка паузы")
	assert_true(o.resume_button().get_combined_minimum_size().y >= PauseOverlay.PRIMARY_MIN_LP, "«Продолжить» ≥ 52 lp")


func test_req_wrk_05_free_ride_pause_card_has_no_skip() -> void:
	var o := _overlay()
	o.set_mode(HudToolbar.Mode.FREE_RIDE)
	o.show_pause()
	assert_eq(_names(o.visible_buttons()), ["ResumeButton", "FinishButton"] as Array[String])
	watch_signals(o)
	o.skip_button().pressed.emit()
	assert_signal_not_emitted(o, "skip_requested")


func test_req_wrk_05_pause_buttons_emit_signals() -> void:
	var o := _overlay()
	o.show_pause()
	watch_signals(o)
	o.resume_button().pressed.emit()
	assert_signal_emit_count(o, "resume_requested", 1)
	o.skip_button().pressed.emit()
	assert_signal_emit_count(o, "skip_requested", 1)
	assert_signal_not_emitted(o, "finish_confirmed")


func test_req_wrk_05_c4_finish_requires_confirmation() -> void:
	var o := _overlay()
	o.show_pause()
	watch_signals(o)
	o.finish_button().pressed.emit()
	assert_signal_not_emitted(o, "finish_confirmed", "«Завершить» само по себе не завершает")
	assert_eq(o.view(), PauseOverlay.View.CONFIRM)
	assert_eq(_names(o.visible_buttons()), ["CancelButton", "ConfirmButton"] as Array[String])
	_assert_touch(o.visible_buttons(), "подтверждение")
	o.cancel_button().pressed.emit()
	assert_signal_emit_count(o, "finish_cancelled", 1)
	assert_eq(o.view(), PauseOverlay.View.PAUSE, "отмена — назад к карточке паузы")
	o.finish_button().pressed.emit()
	o.confirm_button().pressed.emit()
	assert_signal_emit_count(o, "finish_confirmed", 1)
	assert_false(o.is_shown(), "после подтверждения вуаль убрана")


func test_req_wrk_05_c4_confirmation_from_toolbar_cancel_hides_overlay() -> void:
	var o := _overlay()
	o.show_finish_confirmation()
	assert_true(o.is_shown())
	assert_eq(o.view(), PauseOverlay.View.CONFIRM)
	o._input(_key(KEY_ESCAPE))
	assert_false(o.is_shown(), "Esc в подтверждении, открытом не с паузы, убирает вуаль")


func test_req_wrk_05_pause_hotkeys() -> void:
	var o := _overlay()
	watch_signals(o)
	o._input(_key(KEY_SPACE))
	assert_signal_not_emitted(o, "resume_requested", "без паузы клавиши не действуют")
	o.show_pause()
	o._input(_key(KEY_SPACE))
	o._input(_key(KEY_ENTER))
	o._input(_key(KEY_KP_ENTER))
	assert_signal_emit_count(o, "resume_requested", 3, "Пробел и Enter — «Продолжить»")
	o.show_finish_confirmation()
	o._input(_key(KEY_SPACE))
	assert_signal_emit_count(o, "resume_requested", 3, "в подтверждении Пробел не продолжает")
	o._input(_key(KEY_ESCAPE))
	assert_signal_emit_count(o, "finish_cancelled", 1, "Esc — возврат из диалога")
	assert_eq(o.view(), PauseOverlay.View.PAUSE)


func test_req_wrk_05_hide_overlay_fades_out() -> void:
	var o := _overlay()
	o.show_pause()
	await wait_seconds(PauseOverlay.FADE_SEC + 0.15)
	assert_almost_eq(o.modulate.a, 1.0, 0.01)
	o.hide_overlay()
	await wait_seconds(PauseOverlay.FADE_SEC + 0.15)
	assert_false(o.visible)


func test_req_wrk_05_card_style_from_tokens() -> void:
	var box := PauseOverlay.card_style()
	assert_eq(box.bg_color, Color(UiTokens.SURFACE1, 0.94))
	assert_eq(box.corner_radius_top_left, 18)


# ---------------------------------------------------------------------------
# HudToolbar — показ и скрытие
# ---------------------------------------------------------------------------

func test_toolbar_hidden_until_input_then_hides_after_4s() -> void:
	var t := _toolbar()
	assert_false(t.is_shown(), "по умолчанию видна только кнопка паузы")
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(3, 0)
	t._input(motion)
	assert_true(t.is_shown(), "движение мыши показывает панель")
	for i in 35:
		t.tick(0.1)
	assert_true(t.is_shown(), "3.5 с без ввода — ещё видна")
	for i in 10:
		t.tick(0.1)
	assert_false(t.is_shown(), "4.5 с без ввода — скрыта (4 ± 0.5 с)")


func test_toolbar_input_restarts_hide_timer() -> void:
	var t := _toolbar()
	t.poke()
	t.tick(3.0)
	var touch := InputEventScreenTouch.new()
	touch.pressed = true
	t._input(touch)
	t.tick(3.0)
	assert_true(t.is_shown(), "касание продлевает показ")
	t._input(_key(KEY_A))
	t.tick(3.9)
	assert_true(t.is_shown(), "любая клавиша продлевает показ")
	t.tick(0.2)
	assert_false(t.is_shown())


func test_toolbar_fades_and_becomes_invisible() -> void:
	var t := _toolbar()
	t.poke()
	await wait_seconds(HudToolbar.FADE_SEC + 0.15)
	assert_almost_eq(t.modulate.a, 1.0, 0.01)
	t.tick(HudToolbar.HIDE_AFTER_SEC)
	await wait_seconds(HudToolbar.FADE_SEC + 0.15)
	assert_false(t.visible, "после скрытия кнопки не принимают нажатия")


func test_toolbar_paused_stays_hidden_and_ignores_hotkeys() -> void:
	var t := _toolbar()
	t.poke()
	t.set_paused(true)
	assert_false(t.is_shown(), "на паузе панели нет")
	t._input(InputEventMouseMotion.new())
	assert_false(t.is_shown(), "на паузе ввод её не показывает")
	watch_signals(t)
	t._unhandled_key_input(_key(KEY_E, KEY_E))
	t._unhandled_key_input(_key(KEY_ESCAPE))
	assert_signal_not_emitted(t, "erg_toggle_requested")
	assert_signal_not_emitted(t, "pause_requested")
	t.set_paused(false)
	t._unhandled_key_input(_key(KEY_E, KEY_E))
	assert_signal_emit_count(t, "erg_toggle_requested", 1)


# ---------------------------------------------------------------------------
# HudToolbar — режим «план» (REQ-WRK-03 крит. 1, REQ-WRK-05)
# ---------------------------------------------------------------------------

func test_req_wrk_03_c1_plan_toolbar_composition() -> void:
	var t := _toolbar()
	t.set_erg_enabled(true)
	assert_eq(_names(t.visible_buttons()), ["ErgButton", "IntensityDown", "IntensityUp", "SkipButton", "FinishButton"] as Array[String],
		"ERG вкл: сопротивления нет")
	assert_eq(t.button(&"erg").text, "ERG вкл")
	t.set_erg_enabled(false)
	assert_eq(_names(t.visible_buttons()), ["ErgButton", "IntensityDown", "IntensityUp", "ResistanceDown", "ResistanceUp", "SkipButton", "FinishButton"] as Array[String],
		"ERG выкл: сопротивление −5 / +5")
	assert_eq(t.button(&"erg").text, "ERG выкл")
	t.set_intensity_pct(105)
	t.set_resistance_pct(40)
	assert_eq(t.value_text(&"intensity"), "105 %", "значение интенсивности между кнопками")
	assert_eq(t.value_text(&"resistance"), "40 %")
	_assert_touch(t.visible_buttons(), "план")


func test_req_wrk_03_c1_plan_buttons_emit_signals() -> void:
	var t := _toolbar()
	t.set_erg_enabled(false)
	watch_signals(t)
	t.button(&"erg").pressed.emit()
	assert_signal_emit_count(t, "erg_toggle_requested", 1, "ERG одним нажатием")
	t.button(&"intensity_down").pressed.emit()
	assert_signal_emitted_with_parameters(t, "intensity_step_requested", [-5])
	t.button(&"intensity_up").pressed.emit()
	assert_signal_emitted_with_parameters(t, "intensity_step_requested", [5])
	t.button(&"resistance_down").pressed.emit()
	assert_signal_emitted_with_parameters(t, "resistance_step_requested", [-5])
	t.button(&"resistance_up").pressed.emit()
	assert_signal_emitted_with_parameters(t, "resistance_step_requested", [5])
	t.button(&"skip").pressed.emit()
	assert_signal_emit_count(t, "skip_requested", 1)
	t.button(&"finish").pressed.emit()
	assert_signal_emit_count(t, "finish_requested", 1)


func test_req_wrk_03_c1_plan_hotkeys_emit_signals() -> void:
	var t := _toolbar()
	watch_signals(t)
	t._unhandled_key_input(_key(KEY_E, KEY_E))
	assert_signal_emit_count(t, "erg_toggle_requested", 1, "E — ERG")
	t._unhandled_key_input(_key(KEY_EQUAL, KEY_EQUAL, 0x2B))
	assert_signal_emitted_with_parameters(t, "intensity_step_requested", [5])
	t._unhandled_key_input(_key(KEY_KP_ADD))
	t._unhandled_key_input(_key(KEY_MINUS, KEY_MINUS))
	assert_signal_emitted_with_parameters(t, "intensity_step_requested", [-5])
	t._unhandled_key_input(_key(KEY_KP_SUBTRACT))
	assert_signal_emit_count(t, "intensity_step_requested", 4, "+ / − и цифровой блок")
	t._unhandled_key_input(_key(KEY_N, KEY_N))
	assert_signal_emit_count(t, "skip_requested", 1, "N — пропустить шаг")
	t._unhandled_key_input(_key(KEY_ESCAPE, KEY_ESCAPE))
	assert_signal_emit_count(t, "pause_requested", 1, "Esc — пауза")


func test_req_wrk_03_c1_letter_hotkeys_follow_physical_key() -> void:
	var t := _toolbar()
	watch_signals(t)
	# Русская раскладка: физическая E даёт «у» (keycode — кириллица).
	t._unhandled_key_input(_key(0x0443 as Key, KEY_E, 0x0443))
	assert_signal_emit_count(t, "erg_toggle_requested", 1)
	t._unhandled_key_input(_key(0x0442 as Key, KEY_N, 0x0442))
	assert_signal_emit_count(t, "skip_requested", 1)
	var echo := _key(KEY_E, KEY_E)
	echo.echo = true
	t._unhandled_key_input(echo)
	assert_signal_emit_count(t, "erg_toggle_requested", 1, "автоповтор клавиши не переключает ERG")


# ---------------------------------------------------------------------------
# HudToolbar — режим «свободная езда» (REQ-FRD-05 крит. 4, 6)
# ---------------------------------------------------------------------------

func test_req_frd_05_c6_free_ride_toolbar_has_no_skip_and_no_erg() -> void:
	var t := _toolbar()
	t.set_mode(HudToolbar.Mode.FREE_RIDE)
	t.set_sim_enabled(true)
	t.set_steepness_pct(50)
	var names := _names(t.visible_buttons())
	assert_eq(names, ["SimButton", "SteepnessDown", "SteepnessUp", "FinishButton"] as Array[String])
	assert_false(names.has("SkipButton"), "в свободной езде нет «Пропустить шаг»")
	assert_false(names.has("ErgButton"), "в свободной езде нет ERG")
	assert_eq(t.button(&"sim").text, "SIM")
	assert_eq(t.value_text(&"steepness"), "50 %", "крутизна видна на панели")
	t.set_sim_enabled(false)
	t.set_resistance_pct(40)
	assert_eq(_names(t.visible_buttons()), ["SimButton", "ResistanceDown", "ResistanceUp", "FinishButton"] as Array[String],
		"фиксированное сопротивление: −5 / +5 вместо крутизны")
	assert_eq(t.button(&"sim").text, "СОПР.")
	assert_eq(t.value_text(&"resistance"), "40 %")
	_assert_touch(t.visible_buttons(), "свободная езда")


func test_req_frd_05_c4_free_ride_buttons_emit_signals() -> void:
	var t := _toolbar()
	t.set_mode(HudToolbar.Mode.FREE_RIDE)
	watch_signals(t)
	t.button(&"sim").pressed.emit()
	assert_signal_emit_count(t, "sim_toggle_requested", 1, "SIM ↔ сопротивление одним нажатием")
	t.button(&"steepness_down").pressed.emit()
	assert_signal_emitted_with_parameters(t, "steepness_step_requested", [-10])
	t.button(&"steepness_up").pressed.emit()
	assert_signal_emitted_with_parameters(t, "steepness_step_requested", [10])
	t.button(&"finish").pressed.emit()
	assert_signal_emit_count(t, "finish_requested", 1)
	t.set_sim_enabled(false)
	t.button(&"resistance_up").pressed.emit()
	assert_signal_emitted_with_parameters(t, "resistance_step_requested", [5])
	assert_signal_not_emitted(t, "erg_toggle_requested")
	assert_signal_not_emitted(t, "skip_requested")


func test_req_frd_05_c4_free_ride_hotkeys() -> void:
	var t := _toolbar()
	t.set_mode(HudToolbar.Mode.FREE_RIDE)
	watch_signals(t)
	t._unhandled_key_input(_key(KEY_E, KEY_E))
	assert_signal_emit_count(t, "sim_toggle_requested", 1, "E — SIM ↔ сопротивление")
	assert_signal_not_emitted(t, "erg_toggle_requested")
	t._unhandled_key_input(_key(KEY_PLUS, KEY_NONE, 0x2B))
	assert_signal_emitted_with_parameters(t, "steepness_step_requested", [10])
	t._unhandled_key_input(_key(KEY_MINUS, KEY_MINUS))
	assert_signal_emitted_with_parameters(t, "steepness_step_requested", [-10])
	t._unhandled_key_input(_key(KEY_N, KEY_N))
	assert_signal_not_emitted(t, "skip_requested", "N в свободной езде ничего не делает")
	t.set_sim_enabled(false)
	t._unhandled_key_input(_key(KEY_EQUAL, KEY_EQUAL))
	assert_signal_emitted_with_parameters(t, "resistance_step_requested", [5])
	t._unhandled_key_input(_key(KEY_ESCAPE))
	assert_signal_emit_count(t, "pause_requested", 1)


# ---------------------------------------------------------------------------
# HudToolbar — телефон и цели нажатия
# ---------------------------------------------------------------------------

func test_toolbar_compact_grid_two_columns_three_rows() -> void:
	var t := _toolbar()
	t.set_touch_target(UiScale.TOUCH_HUD_PHONE)
	t.set_compact(true)
	for erg in [true, false]:
		t.set_mode(HudToolbar.Mode.PLAN)
		t.set_erg_enabled(erg)
		assert_true(t.button_row_count() <= 3, "план, ERG %s: не больше трёх рядов" % erg)
		assert_true(t.max_buttons_per_row() <= HudToolbar.COMPACT_COLUMNS, "по две кнопки в ряд")
		var names := _names(t.visible_buttons())
		assert_true(names.has("ErgButton") and names.has("SkipButton") and names.has("FinishButton"))
		_assert_touch(t.visible_buttons(), "телефон, план")
	t.set_mode(HudToolbar.Mode.FREE_RIDE)
	assert_true(t.button_row_count() <= 3)
	assert_true(t.max_buttons_per_row() <= HudToolbar.COMPACT_COLUMNS)
	for b in t.visible_buttons():
		assert_true(b.get_combined_minimum_size().y >= UiScale.TOUCH_HUD_PHONE, "%s: touch_hud телефона" % b.name)


func test_toolbar_buttons_take_no_focus() -> void:
	var t := _toolbar()
	for b in t.visible_buttons():
		assert_eq(b.focus_mode, Control.FOCUS_NONE, "%s без фокуса: Пробел не повторяет нажатие" % b.name)


func test_toolbar_texts_follow_locale() -> void:
	var t := _toolbar()
	TranslationServer.set_locale("en")
	t.propagate_notification(NOTIFICATION_TRANSLATION_CHANGED)
	assert_eq(t.button(&"erg").text, "ERG on")
	assert_eq(t.button(&"finish").text, "End")


# ---------------------------------------------------------------------------
# Переводы (REQ-NFR-08 крит. 1, 2): ключи компонентов — префикс `KEY` + суффикс
# ---------------------------------------------------------------------------

func test_every_component_key_exists_in_hud_controls_csv() -> void:
	var table: Dictionary = {}
	var f := FileAccess.open("res://assets/i18n/strings_hud_controls.csv", FileAccess.READ)
	assert_not_null(f)
	f.get_csv_line()
	while not f.eof_reached():
		var line := f.get_csv_line()
		if line.size() >= 3 and not line[0].is_empty():
			table[line[0]] = line
	f.close()
	var re := RegEx.create_from_string('KEY \\+ "([a-z0-9_.]+)"')
	var found := 0
	for path in ["res://src/ui/hud/next_chip.gd", "res://src/ui/hud/pause_overlay.gd", "res://src/ui/hud/hud_toolbar.gd"]:
		for m in re.search_all(FileAccess.get_file_as_string(path)):
			found += 1
			var key := "ui.hud_controls." + m.get_string(1)
			assert_true(table.has(key), "%s: ключ %s есть в strings_hud_controls.csv" % [path, key])
	assert_gt(found, 25, "ключи компонентов найдены")


func test_component_texts_are_translated_in_ru_and_en() -> void:
	for locale in ["ru", "en"]:
		TranslationServer.set_locale(locale)
		var o := _overlay()
		o.show_pause()
		o.show_finish_confirmation()
		var t := _toolbar()
		t.set_erg_enabled(false)
		var chip := NextChip.new()
		add_child_autofree(chip)
		chip.show_next(60, NextChip.format_target(100, 200), Color.RED)
		var texts: Array[String] = [chip.line_text()]
		for node in o.find_children("*", "Label", true, false) + o.find_children("*", "Button", true, false) \
				+ chip.find_children("*", "Label", true, false):
			texts.append(String(node.tr(node.text)) if node.auto_translate_mode != Node.AUTO_TRANSLATE_MODE_DISABLED else String(node.text))
		for b in t.visible_buttons():
			texts.append(b.text)
		for id in [&"intensity", &"resistance"]:
			texts.append(t.value_text(id))
		for s in texts:
			assert_false(s.is_empty(), "[%s] текст не пустой" % locale)
			assert_false(s.begins_with("ui."), "[%s] ключ переведён: %s" % [locale, s])
		o.free()
		t.free()
		chip.free()
