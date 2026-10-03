extends GutTest
## Независимые приёмочные тесты экрана тренировки (тестировщик; T-031/T-024, HEAD c5d7c59;
## под ТЗ ред. 2 — HUD-01 крит. 3 (факт — герой), HUD-02 крит. 4 (●/▲/▼, разница, токены `hud.*`),
## HUD-03/04 («нет данных» — пустая фишка `hud.text2`), HUD-06 (акцент `hud.warn`) — после T-073).
## Покрытие на уровне сцены: REQ-HUD-01 крит. 1–3; REQ-HUD-02..08 (тексты узлов, цвета
## `ZonePalette`, значок/разница/цвет отклонения, акцент отсчёта, подсказка); REQ-WRK-03 крит. 1;
## REQ-WRK-04 крит. 1; REQ-WRK-05 крит. 4; REQ-WRK-06 крит. 2; REQ-WRK-07 крит. 1, 4;
## REQ-NFR-04 крит. 1, 2; REQ-NFR-08 крит. 1; REQ-DEV-08 крит. 1–4 и REQ-DEV-07 крит. 1
## (экран + сессия на `TrainerFactory.create_ble(StubBleBridge)`).
## Сцены — headless через `add_child_autofree`; время — подставленные часы тикера.

const SCENE: String = "res://src/ui/workout/workout_screen.tscn"
const MAIN_SCENE: String = "res://src/app/main.tscn"
const DEV: String = "tacx-neo"

var _now_usec: int = 0
var _keep_calls: Array[bool] = []
var _trainer: FakeTrainer
var _profile: Profile
var _state: AppState
var _repo: ProfileRepository
var _dir: String
var _previous_locale: String
var _bridge: StubBleBridge = null
var _ble: TrainerDevice = null
var _connections: ConnectionManager = null


func before_each() -> void:
	_now_usec = 3_000_000
	_keep_calls = []
	_dir = "user://test_acc_wscreen_%d_%d/" % [Time.get_ticks_usec(), randi() % 1000000]
	_repo = ProfileRepository.new(_dir + "profiles/")
	_state = AppState.new(_repo)
	_trainer = FakeTrainer.new(9)
	_trainer.connect_delay_sec = 0.0
	_trainer.power_noise_w = 0.0
	_trainer.power_tau_sec = 0.01
	_trainer.cadence_noise_rpm = 0.0
	_trainer.connect_device("acc")
	_profile = Profile.create("Rider")
	_profile.ftp_w = 200
	_profile.max_hr = 180
	_profile.resistance_level_default = 50
	_previous_locale = TranslationServer.get_locale()
	TranslationServer.set_locale("en")
	_bridge = null
	_ble = null
	_connections = null


func after_each() -> void:
	TranslationServer.set_locale(_previous_locale)
	if _bridge != null:
		_bridge.pending.clear()
	if _ble is BleTrainer:
		(_ble as BleTrainer).dispose()
	if _connections != null:
		_connections.dispose()
	_remove_tree(ProjectSettings.globalize_path(_dir))
	assert_false(DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(_dir)), "временный каталог удалён")


static func _remove_tree(abs_path: String) -> void:
	if not DirAccess.dir_exists_absolute(abs_path):
		return
	var d := DirAccess.open(abs_path)
	if d == null:
		return
	for f in d.get_files():
		DirAccess.remove_absolute(abs_path.path_join(f))
	for sub in d.get_directories():
		_remove_tree(abs_path.path_join(sub))
	DirAccess.remove_absolute(abs_path)


func _clock() -> int:
	return _now_usec


func _keep(on: bool) -> void:
	_keep_calls.append(on)


static func _plan(steps: Array) -> Workout:
	var typed: Array[WorkoutStep] = []
	for s in steps:
		typed.append(s)
	return Workout.make("acc-plan", typed)


## План 60 с 50 %, 30 с 100 %, 90 с 60 % (как у экрана разработчика).
static func _default_plan() -> Workout:
	return _plan([WorkoutStep.percent(60, 50.0, WorkoutStep.StepKind.WARMUP), WorkoutStep.percent(30, 100.0, WorkoutStep.StepKind.INTERVAL_ON), WorkoutStep.percent(90, 60.0, WorkoutStep.StepKind.COOLDOWN)])


func _screen(workout: Workout = null, trainer: TrainerDevice = null, start: bool = true, connections: ConnectionManager = null) -> WorkoutScreen:
	var s: WorkoutScreen = load(SCENE).instantiate()
	s.clock_usec = _clock
	s.keep_awake_setter = _keep
	add_child_autofree(s)
	s.setup(workout if workout != null else _default_plan(), _profile, trainer if trainer != null else _trainer, _state, connections)
	if start:
		assert_true(s.start(), "предусловие: экран запущен")
	return s


func _advance(s: WorkoutScreen, sec: float) -> void:
	_now_usec += int(round(sec * 1_000_000.0))
	if s.ticker() != null:
		s.ticker().poll()


func _press(s: Node, unique_name: String) -> void:
	(s.get_node("%" + unique_name) as Button).pressed.emit()


func _cmds(type: String, since: int = 0) -> Array:
	var out: Array = []
	for i in range(since, _trainer.commands.size()):
		var c: Dictionary = _trainer.commands[i]
		if c["type"] == type:
			out.append([c["value"], float(c["at_sec"])])
	return out


func _types(since: int = 0) -> Array[String]:
	var out: Array[String] = []
	for i in range(since, _trainer.commands.size()):
		out.append(str(_trainer.commands[i]["type"]))
	return out


func _label(s: Node, unique_name: String) -> Label:
	return s.get_node("%" + unique_name) as Label


## Ручная телеметрия при замолчавшем эмуляторе — для точных значений мощности/пульса.
func _manual_second(s: WorkoutScreen, power: int, hr: int = -1) -> void:
	if power >= 0:
		_trainer.telemetry.emit(TrainerSample.full(_trainer.get_time_sec(), power, 85, 30.0))
	if hr >= 0:
		_trainer.heart_rate.emit(hr)
	_advance(s, 1.0)


# ===========================================================================
# REQ-HUD-01 — целевая мощность: текст с единицей через перевод, «—», размер шрифта
# ===========================================================================

func test_req_hud_01_c1_target_text_with_unit_in_both_locales_and_intensity() -> void:
	var s := _screen()
	assert_eq(s.target_text(), "100 W", "50 %% от FTP 200 с единицей из перевода")
	TranslationServer.set_locale("ru")
	s.refresh()
	assert_eq(s.target_text(), "100 Вт")
	TranslationServer.set_locale("en")
	_press(s, "IntensityPlus")
	assert_eq(s.target_text(), "105 W", "множитель 105 %% отражён в цели (WRK-07 крит. 4)")
	_profile.intensity_default = 110
	var s2 := _screen()
	assert_eq(s2.target_text(), "110 W", "множитель профиля по умолчанию применён при старте")


func test_req_hud_01_c2_free_ride_shows_dash_and_hides_deviation() -> void:
	var s := _screen(_plan([WorkoutStep.free_ride(30), WorkoutStep.percent(30, 50.0)]))
	assert_eq(s.target_text(), "—")
	_advance(s, 3.0)
	assert_eq(s.target_text(), "—")
	assert_eq(s.deviation_text(), "", "без цели индикация скрыта")
	_advance(s, 27.0)
	assert_eq(s.target_text(), "100 W")


## REQ-HUD-01 крит. 3 (ред. 2026-10-03, вариант B `hud.md` п. 5.1): крупнее всего — факт мощности,
## он ≥ 2× шрифта пульса и каденса; цель мельче факта, но не мельче пульса и каденса; ни одна
## другая числовая подпись HUD не набрана шрифтом ≥ шрифта факта.
func test_req_hud_01_c3_hero_power_largest_target_between_and_no_numeric_label_as_large() -> void:
	var s := _screen()
	_advance(s, 2.0)
	var hero := _label(s, "PowerLabel").get_theme_font_size("font_size")
	var target := _label(s, "TargetLabel").get_theme_font_size("font_size")
	var hr := _label(s, "HrLabel").get_theme_font_size("font_size")
	var cadence := _label(s, "CadenceLabel").get_theme_font_size("font_size")
	gut.p("кегли: факт %d, цель %d, пульс %d, каденс %d" % [hero, target, hr, cadence])
	assert_gt(hr, 0)
	assert_gte(hero, 2 * hr, "факт ≥ 2× пульса")
	assert_gte(hero, 2 * cadence, "факт ≥ 2× каденса")
	assert_lt(target, hero, "цель мельче факта")
	assert_gte(target, hr, "цель не мельче пульса")
	assert_gte(target, cadence, "цель не мельче каденса")
	# Все подписи HUD с цифрами (и узлы-значения панели, даже с «—»).
	var numeric_names := ["TargetLabel", "CountdownLabel", "ElapsedLabel", "SpeedLabel", "HrLabel", "CadenceLabel",
		"PowerZoneLabel", "HrZoneLabel"]
	var checked := 0
	for node in (s.get_node("%HudRoot") as Node).find_children("*", "Label", true, false):
		var label := node as Label
		if label == _label(s, "PowerLabel"):
			continue
		var has_digit := RegEx.create_from_string("[0-9]").search(label.text) != null
		if not has_digit and not numeric_names.has(str(label.name)):
			continue
		checked += 1
		var size := label.get_theme_font_size("font_size")
		assert_lt(size, hero, "%s («%s») кеглем %d мельче факта %d" % [label.name, label.text, size, hero])
	assert_gt(checked, 8, "проверено числовых подписей: %d" % checked)


# ===========================================================================
# REQ-HUD-02 — фактическая мощность и отклонение: ●/▲/▼, разница со знаком, токены hud.*
# ===========================================================================

func _deviation(s: WorkoutScreen) -> Array:
	var p := s.metric_panel()
	return [p.deviation_text(), p.deviation_delta_text(), p.deviation_color()]


func test_req_hud_02_power_text_glyph_signed_delta_and_tokens_follow_deviation() -> void:
	var s := _screen(_plan([WorkoutStep.watts(60, 100.0)]))
	_trainer.inject_silence(1_000_000.0)
	assert_eq(s.power_text(), "—", "до данных")
	assert_eq(s.deviation_text(), "")
	assert_eq(s.metric_panel().deviation_delta_text(), "", "до данных разницы нет")
	_manual_second(s, 130)
	assert_eq(s.power_text(), "130 W")
	assert_eq(_deviation(s), ["▲", "+30", UiTokens.HUD_WARN], "выше: ▲, +30, hud.warn")
	_manual_second(s, 70) # среднее 100
	assert_eq(s.power_text(), "100 W", "сглаженное за 3 с")
	assert_eq(_deviation(s), ["●", "0", UiTokens.HUD_DEV_ON], "в цели: ●, 0, hud.dev_on")
	_manual_second(s, 10) # среднее 70
	assert_eq(_deviation(s), ["▼", "−30", UiTokens.HUD_DEV_BELOW], "ниже: ▼, −30 (U+2212), hud.dev_below")
	_manual_second(s, 110)
	_manual_second(s, 110)
	_manual_second(s, 110)
	assert_eq(_deviation(s), ["●", "+10", UiTokens.HUD_DEV_ON], "110 при цели 100 — в пороге 10 Вт, разница +10")
	_manual_second(s, 111)
	_manual_second(s, 111)
	_manual_second(s, 111)
	assert_eq(_deviation(s), ["▲", "+11", UiTokens.HUD_WARN], "111 — выше")


func test_req_hud_02_c4_example_247_vs_300_and_tokens_differ_from_zone_palette() -> void:
	var s := _screen(_plan([WorkoutStep.watts(60, 300.0)]))
	_trainer.inject_silence(1_000_000.0)
	for i in 3:
		_manual_second(s, 247)
	assert_eq(s.power_text(), "247 W")
	assert_eq(_deviation(s), ["▼", "−53", UiTokens.HUD_DEV_BELOW], "факт 247, цель 300 → ▼ «−53»")
	for i in 3:
		_manual_second(s, 285)
	assert_eq(s.metric_panel().deviation_text(), "●", "|285 − 300| = 15 ≤ max(5 %% · 300, 10)")
	assert_eq(s.metric_panel().deviation_delta_text(), "−15")
	assert_eq(UiTokens.HUD_DEV_ON, Color("#2CC9B4"), "hud.dev_on")
	assert_eq(UiTokens.HUD_WARN, Color("#FFC24D"), "hud.warn")
	assert_eq(UiTokens.HUD_DEV_BELOW, Color("#8FC2FF"), "hud.dev_below")
	for token: String in ZonePalette.POWER_TOKENS:
		for c: Color in [UiTokens.HUD_DEV_ON, UiTokens.HUD_WARN, UiTokens.HUD_DEV_BELOW]:
			assert_false(c.is_equal_approx(ZonePalette.color(token)), "цвет отклонения %s ≠ цвету зоны %s" % [c.to_html(false), token])


# ===========================================================================
# REQ-HUD-03 / REQ-HUD-04 — фишки зон: цвет зоны; «нет данных» — без заливки, рамка и «—» hud.text2
# ===========================================================================

## Фишка «нет данных» (`hud.md` п. 5, 11): без заливки, текст «—» цветом `hud.text2`, рамка `hud.text2`.
func _assert_empty_chip(s: WorkoutScreen, chip_name: String, text: String, fill: Color, msg: String) -> void:
	assert_eq(text, "—", "%s: «—»" % msg)
	assert_eq(fill, Color.TRANSPARENT, "%s: без заливки цветом зоны" % msg)
	var chip := _label(s, chip_name)
	assert_eq(chip.get_theme_color("font_color"), UiTokens.HUD_TEXT2, "%s: «—» цветом hud.text2" % msg)
	assert_eq(chip.modulate, Color.WHITE, "%s: текст не тонирован цветом зоны" % msg)
	var box: Variant = s.metric_panel().get("_chip_empty_box")
	if box is StyleBoxFlat:
		var b := box as StyleBoxFlat
		assert_false(b.draw_center, "%s: рамка без заливки" % msg)
		assert_eq(b.border_color, UiTokens.HUD_TEXT2, "%s: рамка hud.text2" % msg)
		assert_gte(b.border_width_left, 1, "%s: рамка 1·s" % msg)


func test_req_hud_03_zone_chip_text_and_color_from_palette_and_empty_chip_without_data() -> void:
	var s := _screen(_plan([WorkoutStep.watts(60, 100.0)]))
	var p := s.metric_panel()
	_trainer.inject_silence(1_000_000.0)
	for pw in [181, 181, 181]:
		_manual_second(s, pw)
	assert_eq(s.power_zone_text(), "Z4")
	assert_eq(p.power_zone_color(), ZonePalette.color("z4"))
	assert_eq(ZonePalette.color_name("z4"), "yellow")
	assert_eq(_label(s, "PowerZoneLabel").get_theme_color("font_color"), UiTokens.HUD_INK, "текст на заливке зоны — hud.ink")
	for pw in [301, 301, 301]:
		_manual_second(s, pw)
	assert_eq(s.power_zone_text(), "Z7")
	assert_eq(p.power_zone_color(), ZonePalette.COLORS["purple"])
	for pw in [0, 0, 0]:
		_manual_second(s, pw)
	assert_eq(s.power_zone_text(), "Z1", "0 Вт → Z1")
	assert_eq(p.power_zone_color(), ZonePalette.COLORS["gray"], "Z1 — серая фишка")
	for i in 3:
		_manual_second(s, -1)
	assert_eq(s.power_text(), "—")
	_assert_empty_chip(s, "PowerZoneLabel", s.power_zone_text(), p.power_zone_color(), "мощность «нет данных»")


func test_req_hud_04_hr_chip_zone_and_color_and_empty_chip_without_sensor_or_max_hr() -> void:
	var s := _screen()
	var p := s.metric_panel()
	_trainer.inject_silence(1_000_000.0)
	_manual_second(s, 100, 150)
	assert_eq(s.hr_text(), "150")
	assert_eq(p.hr_zone_text(), "Z4", "150/180 = 83 %% → Z4")
	assert_eq(p.hr_zone_color(), ZonePalette.color("hr4"))
	# Таблица крит. 1 при max_hr 180.
	for row in [[107, "Z1", "hr1"], [108, "Z2", "hr2"], [126, "Z3", "hr3"], [144, "Z4", "hr4"], [162, "Z5", "hr5"]]:
		_manual_second(s, 100, row[0])
		assert_eq(p.hr_zone_text(), row[1], "%d уд/мин → %s" % [row[0], row[1]])
		assert_eq(p.hr_zone_color(), ZonePalette.color(row[2]), "%d уд/мин — цвет %s" % [row[0], row[2]])
	_manual_second(s, 100)
	assert_eq(s.hr_text(), "—", "без датчика")
	_assert_empty_chip(s, "HrZoneLabel", p.hr_zone_text(), p.hr_zone_color(), "нет датчика пульса")
	_profile.max_hr = 0
	var s2 := _screen()
	_manual_second(s2, 100, 150)
	assert_eq(s2.hr_text(), "150")
	_assert_empty_chip(s2, "HrZoneLabel", s2.metric_panel().hr_zone_text(), s2.metric_panel().hr_zone_color(), "без max_hr зоны нет")


# ===========================================================================
# REQ-HUD-05 / REQ-HUD-06 — метрики, время, отсчёт с акцентом
# ===========================================================================

func test_req_hud_05_metrics_formats_elapsed_excludes_pause() -> void:
	var s := _screen()
	_trainer.set_heart_rate(142)
	_advance(s, 5.0)
	assert_eq(s.hr_text(), "142")
	assert_eq(s.cadence_text(), "85")
	assert_true(RegEx.create_from_string("^[0-9]+\\.[0-9]$").search(s.speed_text()) != null, "скорость с одним знаком: %s" % s.speed_text())
	assert_eq(s.elapsed_text(), "00:05")
	assert_eq(s.step_text(), "Step 1/3")
	_press(s, "PauseButton")
	_advance(s, 10.0)
	assert_eq(s.elapsed_text(), "00:05", "пауза не входит в прошедшее время")
	_press(s, "PauseButton")
	_advance(s, 1.0)
	assert_eq(s.elapsed_text(), "00:06")


func test_req_hud_06_countdown_text_accent_in_last_5s_and_new_duration_on_transition() -> void:
	var s := _screen(_plan([WorkoutStep.percent(10, 50.0), WorkoutStep.percent(90, 100.0)]))
	assert_eq(s.countdown_text(), "00:10")
	assert_false(s.is_countdown_accented())
	_advance(s, 4.0)
	assert_eq(s.countdown_text(), "00:06")
	assert_false(s.is_countdown_accented(), "6 с — без акцента")
	assert_ne(_label(s, "CountdownLabel").modulate, UiTokens.HUD_WARN, "6 с — не hud.warn")
	_advance(s, 1.0)
	assert_eq(s.countdown_text(), "00:05")
	assert_true(s.is_countdown_accented(), "за 5 с — акцент")
	assert_eq(_label(s, "CountdownLabel").modulate, UiTokens.HUD_WARN, "отсчёт цветом hud.warn (HUD-13.7, H10)")
	_advance(s, 5.0)
	assert_eq(s.countdown_text(), "01:30", "на переходе — длительность нового шага")
	assert_false(s.is_countdown_accented())
	assert_ne(_label(s, "CountdownLabel").modulate, UiTokens.HUD_WARN, "после смены шага акцент снят")
	assert_eq(s.step_text(), "Step 2/2")


# ===========================================================================
# REQ-HUD-07 — полоса прогресса
# ===========================================================================

func test_req_hud_07_progress_bar_segments_cursor_statuses_and_intensity() -> void:
	var s := _screen()
	var bar := s.progress_bar()
	assert_not_null(bar)
	var segs := bar.segments()
	assert_eq(segs.size(), 3)
	var total := 0
	for seg in segs:
		total += int(seg["duration_sec"])
	assert_eq(total, 180)
	assert_eq(segs[0]["status"], HudModel.SEGMENT_CURRENT)
	assert_eq(segs[1]["start_watts"], 200)
	assert_eq(segs[1]["zone_token"], "z4")
	assert_eq(bar.cursor(), 0.0)
	_advance(s, 45.0)
	assert_almost_eq(bar.cursor(), 0.25, 1e-9, "45 / 180")
	_press(s, "IntensityPlus")
	_press(s, "IntensityPlus")
	segs = bar.segments()
	assert_eq(segs[1]["start_watts"], 220, "профиль плана отражает множитель 110 %% (WRK-07 крит. 4)")
	assert_eq(segs[1]["zone_token"], "z5")
	_press(s, "SkipButton")
	segs = bar.segments()
	assert_eq(segs[0]["status"], HudModel.SEGMENT_SKIPPED)
	assert_eq(segs[1]["status"], HudModel.SEGMENT_CURRENT)
	assert_eq(segs[2]["status"], HudModel.SEGMENT_UPCOMING)


# ===========================================================================
# REQ-HUD-08 — подсказки
# ===========================================================================

func test_req_hud_08_cue_label_visible_from_step_start_hidden_after_10s_and_truncated() -> void:
	var step := WorkoutStep.percent(60, 50.0)
	step.text_cues.append(TextCue.make(0, "Крути ровно"))
	var long_step := WorkoutStep.percent(60, 60.0)
	long_step.text_cues.append(TextCue.make(0, "y".repeat(130)))
	var s := _screen(_plan([step, long_step]))
	var cue := _label(s, "CueLabel")
	assert_true(cue.visible)
	assert_eq(s.cue_text(), "Крути ровно")
	_advance(s, 9.0)
	assert_true(cue.visible, "9 с — ещё видна")
	_advance(s, 1.0)
	assert_false(cue.visible, "скрыта через 10 с")
	assert_eq(s.cue_text(), "")
	_advance(s, 50.0)
	assert_true(cue.visible, "подсказка нового шага")
	assert_eq(s.cue_text().length(), 120, "обрезана до 120 с «…»")
	assert_true(s.cue_text().ends_with("…"))


# ===========================================================================
# REQ-WRK-03 крит. 1 — ERG одной кнопкой, ряд сопротивления только при выкл.
# ===========================================================================

func test_req_wrk_03_c1_erg_button_toggles_mode_row_visibility_and_commands() -> void:
	var s := _screen()
	_advance(s, 5.0)
	assert_eq((s.get_node("%ErgButton") as Button).text, "ERG on")
	assert_false(s.is_resistance_row_visible(), "при ERG ряд сопротивления скрыт")
	var before := _trainer.commands.size()
	_press(s, "ErgButton")
	assert_false(s.session().erg_enabled)
	assert_eq((s.get_node("%ErgButton") as Button).text, "ERG off")
	assert_true(s.is_resistance_row_visible(), "при выкл. ERG ряд виден")
	assert_eq(_types(before), ["erg", "resistance"])
	assert_eq(_cmds("resistance", before), [[50, 5.0]], "уровень профиля, та же секунда")
	before = _trainer.commands.size()
	_press(s, "ErgButton")
	assert_true(s.session().erg_enabled)
	assert_false(s.is_resistance_row_visible())
	assert_eq(_types(before), ["erg", "target_power"])
	assert_eq(_cmds("target_power", before), [[100, 5.0]])


func test_req_wrk_03_edge_erg_button_on_pause_is_deferred_until_resume() -> void:
	var s := _screen()
	_advance(s, 5.0)
	_press(s, "PauseButton")
	var before := _trainer.commands.size()
	_press(s, "ErgButton")
	assert_false(s.session().erg_enabled, "флаг переключился сразу")
	assert_true(s.is_resistance_row_visible(), "и UI это показывает")
	_advance(s, 3.0)
	assert_eq(_trainer.commands.size(), before, "на паузе команд нет")
	_press(s, "PauseButton") # resume
	assert_eq(_types(before), ["erg", "resistance"], "отложенное переключение ушло при возобновлении")


# ===========================================================================
# REQ-WRK-04 крит. 1 — ±5 %, снап, команда, сохранение в профиль
# ===========================================================================

func test_req_wrk_04_c1_resistance_buttons_step_5_snap_command_and_profile_updated() -> void:
	_profile.resistance_level_default = 52
	var s := _screen()
	var updated: Array[Profile] = []
	s.profile_updated.connect(func(p: Profile) -> void: updated.append(p))
	assert_eq(s.session().resistance_level, 50, "52 из профиля снапнуто к 50 при старте")
	_press(s, "ErgButton") # ERG выкл → ряд виден, команды уходят
	var before := _trainer.commands.size()
	_press(s, "ResistancePlus")
	assert_eq(s.session().resistance_level, 55)
	assert_eq(_label(s, "ResistanceLabel").text, "Resistance 55 %")
	assert_eq(_cmds("resistance", before), [[55, 0.0]], "команда в ту же секунду")
	assert_eq(updated.size(), 1)
	assert_eq(_profile.resistance_level_default, 55, "профиль обновлён для сохранения")
	_press(s, "ResistanceMinus")
	_press(s, "ResistanceMinus")
	assert_eq(s.session().resistance_level, 45)
	assert_eq(_profile.resistance_level_default, 45)
	for i in 15:
		_press(s, "ResistancePlus")
	assert_eq(s.session().resistance_level, 100, "не выше 100")
	var n := updated.size()
	_press(s, "ResistancePlus")
	assert_eq(updated.size(), n, "на границе без изменения — без сигнала")
	for i in 25:
		_press(s, "ResistanceMinus")
	assert_eq(s.session().resistance_level, 0, "не ниже 0")
	TranslationServer.set_locale("ru")
	s.refresh()
	assert_eq(_label(s, "ResistanceLabel").text, "Сопротивление 0 %")


func test_req_wrk_04_c1_resistance_change_in_erg_is_stored_and_profile_updated_but_not_sent() -> void:
	var s := _screen()
	var before := _trainer.commands.size()
	_press(s, "ResistancePlus")
	assert_eq(s.session().resistance_level, 55)
	assert_eq(_profile.resistance_level_default, 55)
	assert_eq(_trainer.commands.size(), before, "при ERG на станок не уходит")
	_press(s, "ErgButton")
	assert_eq(_cmds("resistance", before), [[55, 0.0]], "уходит при выключении ERG")


# ===========================================================================
# REQ-WRK-05 крит. 4 — стоп только через подтверждение
# ===========================================================================

func test_req_wrk_05_c4_stop_requires_confirmation_cancel_does_nothing_confirm_marks_early() -> void:
	var s := _screen()
	var finished: Array[WorkoutSession] = []
	s.session_finished.connect(func(ses: WorkoutSession) -> void: finished.append(ses))
	_advance(s, 20.0)
	_press(s, "StopButton")
	assert_true(s.is_stop_confirmation_pending())
	assert_eq(s.session().get_state(), WorkoutSession.State.RUNNING, "без подтверждения тренировка идёт")
	assert_eq((s.get_node("%StopDialog") as ConfirmationDialog).tr("ui.workout.stop_confirm"), "End the workout early? The ride will be saved as ended early.")
	s.cancel_stop()
	assert_false(s.is_stop_confirmation_pending())
	_advance(s, 5.0)
	assert_eq(s.session().get_state(), WorkoutSession.State.RUNNING)
	assert_eq(s.session().samples.size(), 25, "отмена ничего не сделала")
	assert_eq(finished, [])
	_press(s, "StopButton")
	(s.get_node("%StopDialog") as ConfirmationDialog).canceled.emit()
	assert_false(s.is_stop_confirmation_pending(), "отмена через диалог")
	_press(s, "StopButton")
	(s.get_node("%StopDialog") as ConfirmationDialog).confirmed.emit()
	assert_eq(s.session().get_state(), WorkoutSession.State.FINISHED)
	assert_true(s.session().metadata()["stopped_early"])
	assert_eq(s.session().samples.size(), 25, "данные целы")
	assert_true(s.is_summary_visible())
	assert_true(s.summary_text().contains("(ended early)"), s.summary_text())
	assert_true(s.summary_text().contains("00:25"))
	assert_eq(finished.size(), 1, "хук session_finished — один раз")
	assert_false(s.ticker().is_running())
	assert_false(s.request_stop(), "после финиша стоп недоступен")
	TranslationServer.set_locale("ru")
	s.refresh()
	assert_true(s.summary_text().contains("(завершена досрочно)"))


func test_req_wrk_05_c4_stop_from_pause_works_and_plan_completion_is_not_early() -> void:
	var s := _screen()
	_advance(s, 10.0)
	_press(s, "PauseButton")
	assert_true(s.request_stop())
	s.confirm_stop()
	assert_eq(s.session().get_state(), WorkoutSession.State.FINISHED)
	assert_true(s.session().metadata()["stopped_early"])
	var s2 := _screen(_plan([WorkoutStep.percent(5, 50.0)]))
	_advance(s2, 5.0)
	assert_true(s2.is_summary_visible())
	assert_false(s2.session().metadata()["stopped_early"])
	assert_false(s2.summary_text().contains("early"))


# ===========================================================================
# REQ-WRK-06 крит. 2 / REQ-WRK-07 крит. 1 — пропуск и интенсивность с кнопок
# ===========================================================================

func test_req_wrk_06_c2_skip_button_sends_new_target_same_second_and_updates_step_label() -> void:
	var s := _screen()
	_advance(s, 12.5)
	var before := _trainer.commands.size()
	_press(s, "SkipButton")
	assert_eq(_cmds("target_power", before), [[200, 12.5]], "цель нового шага — немедленно")
	assert_eq(s.step_text(), "Step 2/3")
	assert_eq(s.target_text(), "200 W")
	assert_eq(s.countdown_text(), "00:30")


func test_req_wrk_07_c1_intensity_buttons_step_5pct_clamp_and_target_command() -> void:
	var s := _screen()
	_advance(s, 7.0)
	assert_eq(_label(s, "IntensityLabel").text, "Intensity 100 %")
	var before := _trainer.commands.size()
	_press(s, "IntensityPlus")
	assert_eq(_label(s, "IntensityLabel").text, "Intensity 105 %")
	assert_eq(_cmds("target_power", before), [[105, 7.0]], "новая цель в ту же секунду")
	assert_eq(s.target_text(), "105 W")
	for i in 20:
		_press(s, "IntensityPlus")
	assert_eq(_label(s, "IntensityLabel").text, "Intensity 150 %", "не выше 150")
	assert_eq(s.target_text(), "150 W")
	for i in 40:
		_press(s, "IntensityMinus")
	assert_eq(_label(s, "IntensityLabel").text, "Intensity 50 %", "не ниже 50")
	assert_eq(s.target_text(), "50 W")
	assert_almost_eq(float(s.session().metadata()["intensity"]), 0.5, 1e-9)


# ===========================================================================
# REQ-NFR-04 — KeepAwake через подставленный сеттер
# ===========================================================================

func test_req_nfr_04_c1_c2_keep_awake_lifecycle_on_screen() -> void:
	var s := _screen(null, null, false)
	assert_eq(_keep_calls, [], "до старта — нет вызовов")
	s.start()
	assert_eq(_keep_calls, [true], "старт → запрет гашения")
	_press(s, "PauseButton")
	assert_eq(_keep_calls, [true], "пауза сохраняет запрет")
	_press(s, "PauseButton")
	s.on_screen_exited()
	assert_eq(_keep_calls, [true, false], "уход с экрана снимает")
	s.on_screen_entered()
	assert_eq(_keep_calls, [true, false, true], "возврат восстанавливает")
	_advance(s, 200.0)
	assert_true(s.is_summary_visible())
	assert_eq(_keep_calls, [true, false, true, false], "финиш снимает")
	s.go_home()
	assert_eq(_keep_calls.size(), 4, "повторное снятие без вызова")


func test_req_nfr_04_c1_stop_and_double_start_release_and_reacquire() -> void:
	var s := _screen()
	assert_eq(_keep_calls, [true])
	_press(s, "StopButton")
	s.confirm_stop()
	assert_eq(_keep_calls, [true, false], "стоп снимает")
	assert_true(s.start(), "повторный старт")
	assert_eq(_keep_calls, [true, false, true])
	assert_eq(s.session().get_state(), WorkoutSession.State.RUNNING)


# ===========================================================================
# REQ-NFR-08 крит. 1 — все строки экрана через переводы, оба языка
# ===========================================================================

func _collect_texts(node: Node, out: Array[Dictionary]) -> void:
	if node is Label or node is Button:
		out.append({"name": node.name, "text": node.text, "node": node})
	for child in node.get_children():
		_collect_texts(child, out)


func test_req_nfr_08_c1_no_untranslated_keys_on_screen_in_en_and_ru() -> void:
	var s := _screen()
	_trainer.set_heart_rate(140)
	_advance(s, 3.0)
	for locale in ["en", "ru"]:
		TranslationServer.set_locale(locale)
		s.refresh()
		var texts: Array[Dictionary] = []
		_collect_texts(s, texts)
		assert_gt(texts.size(), 20)
		for t in texts:
			var shown: String = (t["node"] as Node).tr(str(t["text"]))
			assert_false(shown.begins_with("ui."), "%s: непереведённый ключ «%s» (%s)" % [t["name"], shown, locale])
	TranslationServer.set_locale("ru")
	s.refresh()
	assert_eq(s.step_text(), "Шаг 1/3")
	assert_eq(s.target_text(), "100 Вт")
	assert_eq((s.get_node("%PauseButton") as Button).text, "Пауза")
	assert_eq(_label(s, "IntensityLabel").text, "Интенсивность 100 %")
	assert_eq(s.connection_text(), "Станок подключён")
	var dialog := s.get_node("%StopDialog") as ConfirmationDialog
	assert_eq(dialog.tr(dialog.ok_button_text), "Стоп")
	assert_eq(dialog.tr(dialog.cancel_button_text), "Отмена")
	TranslationServer.set_locale("en")
	s.refresh()
	assert_eq(s.connection_text(), "Trainer connected")
	assert_eq((s.get_node("%PauseButton") as Button).text, "Pause")


# ===========================================================================
# REQ-DEV-07 крит. 1 / REQ-DEV-08 крит. 1–4 — экран + сессия на BleTrainer (StubBleBridge)
# ===========================================================================

func _ble_screen(start: bool = true) -> WorkoutScreen:
	_bridge = StubBleBridge.new()
	_ble = TrainerFactory.create_ble(_bridge)
	_ble.connect_device(DEV)
	_bridge.pump()
	assert_eq(_ble.get_connection_state(), TrainerDevice.ConnectionState.CONNECTED, "предусловие: BLE-станок подключён")
	_bridge.auto_connect = false
	return _screen(_plan([WorkoutStep.watts(10, 150.0), WorkoutStep.watts(10, 250.0), WorkoutStep.watts(10, 180.0)]), _ble, start)


func _ble_second(s: WorkoutScreen, power: int) -> void:
	if power >= 0:
		_bridge.emit_notification(DEV, BleUuids.INDOOR_BIKE_DATA, FtmsCodec.encode_indoor_bike_data(32.0, 88.0, power))
	_advance(s, 1.0)


func _cp_writes() -> Array[String]:
	var out: Array[String] = []
	for w in _bridge.writes_to(BleUuids.FTMS_CONTROL_POINT):
		out.append((w["bytes"] as PackedByteArray).hex_encode())
	return out


func test_req_dev_08_c1_c2_dropout_shows_reconnecting_keeps_timer_and_writes_no_data_slots() -> void:
	var s := _ble_screen()
	assert_eq(s.connection_text(), "Trainer connected", "DEV-07 крит. 1: состояние на HUD")
	for i in 3:
		_ble_second(s, 150)
	assert_eq(s.power_text(), "150 W")
	_bridge.emit_disconnected(DEV, BleBridge.DisconnectReason.LINK_LOSS)
	assert_eq(_ble.get_connection_state(), TrainerDevice.ConnectionState.RECONNECTING)
	assert_eq(s.connection_text(), "Reconnecting…", "HUD показывает переподключение")
	_bridge.clear_calls()
	for i in 6:
		_ble_second(s, -1)
	assert_eq(s.session().get_state(), WorkoutSession.State.RUNNING, "сессия жива")
	assert_eq(s.elapsed_text(), "00:09", "таймер идёт")
	assert_eq(s.session().samples.size(), 9, "слоты пишутся")
	for i in range(3, 9):
		assert_false(s.session().samples.has_power[i], "слот %d — «нет данных», не 0" % i)
	assert_eq(s.power_text(), "—", "на HUD «—»")
	assert_gte(_bridge.calls_of("connect_peripheral").size(), 1, "попытки connect каждые 5 с")
	assert_eq(s.session().events.filter(func(e: Dictionary) -> bool: return e["type"] == WorkoutSession.EVENT_DISCONNECT).size(), 1)


func test_req_dev_08_c3_c4_reconnect_sends_request_control_and_target_same_second_data_intact() -> void:
	var s := _ble_screen()
	for i in 4:
		_ble_second(s, 150)
	_bridge.emit_disconnected(DEV, BleBridge.DisconnectReason.LINK_LOSS)
	for i in 3:
		_ble_second(s, -1)
	_bridge.clear_calls()
	_bridge.emit_connected(DEV)
	_bridge.pump()
	assert_eq(_ble.get_connection_state(), TrainerDevice.ConnectionState.CONNECTED)
	assert_eq(_cp_writes(), ["00", "059600"], "Request Control, затем цель 150 Вт — до следующего тика (в ту же секунду)")
	assert_eq(s.connection_text(), "Trainer connected")
	assert_eq(s.session().events.filter(func(e: Dictionary) -> bool: return e["type"] == WorkoutSession.EVENT_RECONNECT).size(), 1)
	for i in 3:
		_ble_second(s, 150)
	var samples := s.session().samples
	assert_eq(samples.size(), 10)
	assert_true(samples.is_monotonic())
	for i in 4:
		assert_true(samples.has_power[i], "сэмплы до обрыва целы (слот %d)" % i)
		assert_eq(samples.power_w[i], 150)
	assert_true(samples.has_power[9], "после восстановления запись продолжается")
	assert_eq(s.power_text(), "150 W")
	assert_eq(s.step_text(), "Step 2/3", "переход на границе 10 с не потерян")


func test_req_dev_08_c3_reconnect_on_pause_sends_only_request_control_target_at_resume() -> void:
	var s := _ble_screen()
	for i in 3:
		_ble_second(s, 150)
	_press(s, "PauseButton")
	_bridge.emit_disconnected(DEV, BleBridge.DisconnectReason.LINK_LOSS)
	assert_eq(s.connection_text(), "Reconnecting…")
	_bridge.clear_calls()
	_bridge.emit_connected(DEV)
	_bridge.pump()
	assert_eq(_cp_writes(), ["00"], "на паузе — только Request Control")
	assert_eq(s.session().samples.size(), 3)
	_press(s, "PauseButton")
	assert_eq(_cp_writes(), ["00", "059600"], "цель — при возобновлении")


func test_req_dev_07_c1_user_disconnect_shows_disconnected_and_no_retries() -> void:
	var s := _ble_screen()
	_ble_second(s, 150)
	_ble.disconnect_device()
	assert_eq(s.connection_text(), "Trainer disconnected")
	_bridge.clear_calls()
	for i in 6:
		_ble_second(s, -1)
	assert_eq(_bridge.calls_of("connect_peripheral").size(), 0)
	assert_eq(s.session().get_state(), WorkoutSession.State.RUNNING, "сессия продолжается без станка")


# ===========================================================================
# Границы: start без setup, двойной start, connections.ticks_devices
# ===========================================================================

func test_edge_start_without_setup_returns_false_and_shows_placeholder() -> void:
	var s: WorkoutScreen = load(SCENE).instantiate()
	s.clock_usec = _clock
	s.keep_awake_setter = _keep
	add_child_autofree(s)
	assert_false(s.start())
	assert_null(s.session())
	assert_true(_label(s, "NoSessionLabel").visible)
	assert_eq(_label(s, "NoSessionLabel").tr(_label(s, "NoSessionLabel").text), "No workout selected")
	assert_false((s.get_node("%HudRoot") as Control).visible)
	assert_eq(_keep_calls, [])
	for b in ["PauseButton", "SkipButton", "StopButton", "ErgButton", "ResistancePlus", "IntensityPlus"]:
		_press(s, b)
	assert_false(s.request_stop())
	assert_null(s.session(), "нажатия без сессии безопасны")


func test_edge_double_start_restarts_with_single_ticker_and_fresh_session() -> void:
	var s := _screen()
	_advance(s, 20.0)
	var first_session := s.session()
	var first_ticker := s.ticker()
	assert_true(s.start())
	assert_ne(s.session(), first_session)
	assert_eq(first_session.get_state(), WorkoutSession.State.FINISHED, "старая сессия остановлена")
	assert_false(first_ticker.is_running())
	assert_eq(s.session().executor.elapsed_sec(), 0)
	await get_tree().process_frame
	var tickers := 0
	for child in s.get_children():
		if child is SessionTicker:
			tickers += 1
	assert_eq(tickers, 1, "старый тикер освобождён")
	_advance(s, 1.0)
	assert_eq(s.session().samples.size(), 1)


func test_edge_connections_ticks_devices_false_during_session_true_after_finish_and_without_connections_ok() -> void:
	_connections = ConnectionManager.new(StubBleBridge.new(), RememberedDevices.new(_dir + "devices/"), TrainerFactory.KIND_FAKE)
	assert_true(_connections.ticks_devices)
	var s := _screen(_plan([WorkoutStep.percent(5, 50.0)]), null, true, _connections)
	assert_false(_connections.ticks_devices, "на время сессии устройства тикает тикер сессии")
	_advance(s, 5.0)
	assert_true(s.is_summary_visible())
	assert_true(_connections.ticks_devices, "после финиша возвращается true")
	assert_true(s.start())
	assert_false(_connections.ticks_devices)
	s.request_stop()
	s.confirm_stop()
	assert_true(_connections.ticks_devices, "после стопа тоже")
	var s2 := _screen(_plan([WorkoutStep.percent(5, 50.0)]))
	_advance(s2, 5.0)
	assert_true(s2.is_summary_visible(), "без connections экран работает")


# ===========================================================================
# main.tscn — кнопка «Тренировка на эмуляторе», хук финиша, сохранение профиля
# ===========================================================================

func test_main_emulator_workout_button_opens_workout_with_profile_ftp_saves_profile_and_hook() -> void:
	var p := _repo.create("Solo")
	var ep := p.duplicate_profile()
	ep.ftp_w = 250
	ep.resistance_level_default = 50
	assert_eq(_repo.save(ep), [])
	var main: AppMain = load(MAIN_SCENE).instantiate()
	main.data_dir = _dir
	main.trainer_kind = TrainerFactory.KIND_FAKE
	add_child_autofree(main)
	assert_eq(main.app_state.current_screen, AppState.Screen.HOME)
	var ws := main.workout_screen()
	assert_not_null(ws)
	ws.clock_usec = _clock
	ws.keep_awake_setter = _keep
	_press(main.visible_screen_node(), "EmulatorWorkoutButton")
	assert_true(main.visible_screen_node() is WorkoutScreen, "открыт экран тренировки")
	assert_not_null(ws.session())
	assert_eq(ws.session().get_state(), WorkoutSession.State.RUNNING)
	assert_eq(ws.target_text(), "125 W", "50 %% от FTP профиля 250")
	assert_eq(_keep_calls, [true])
	# сопротивление → профиль сохранён через main
	_press(ws, "ErgButton")
	_press(ws, "ResistancePlus")
	assert_eq(ProfileRepository.new(_dir + "profiles/").get_by_id(p.id).resistance_level_default, 55, "уровень сохранён в репозитории")
	# финиш → хук main.last_finished_session
	_now_usec += 200_000_000
	ws.ticker().poll()
	assert_true(ws.is_summary_visible())
	assert_eq(main.last_finished_session, ws.session(), "хук session_finished")
	assert_eq(_keep_calls, [true, false])
	# уход с экрана через кнопку «На главный»
	_press(ws, "HomeButton")
	assert_true(main.visible_screen_node() is HomeScreen)
	assert_eq(_keep_calls.size(), 2, "повторного снятия нет")


func test_main_leaving_workout_screen_releases_keep_awake_and_returning_restores() -> void:
	_repo.create("Solo")
	var main: AppMain = load(MAIN_SCENE).instantiate()
	main.data_dir = _dir
	main.trainer_kind = TrainerFactory.KIND_FAKE
	add_child_autofree(main)
	var ws := main.workout_screen()
	ws.clock_usec = _clock
	ws.keep_awake_setter = _keep
	_press(main.visible_screen_node(), "EmulatorWorkoutButton")
	assert_eq(_keep_calls, [true])
	assert_true(main.app_state.navigate(AppState.Screen.HOME))
	assert_eq(_keep_calls, [true, false], "уход с экрана тренировки снимает запрет, сессия при этом идёт")
	assert_eq(ws.session().get_state(), WorkoutSession.State.RUNNING)
	assert_true(main.app_state.navigate(AppState.Screen.WORKOUT))
	assert_eq(_keep_calls, [true, false, true], "возврат восстанавливает")
