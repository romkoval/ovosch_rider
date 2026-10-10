extends GutTest
## Независимые приёмочные тесты модели HUD и KeepAwake (тестировщик; коммит bcbbe7c).
## Покрытие: REQ-HUD-01 крит. 1, 2; REQ-HUD-02..09 все `[авто]`; REQ-WRK-07 крит. 4;
## REQ-WRK-03 крит. 1 (состояние ERG на HUD); REQ-NFR-04 крит. 1, 2.
## Телеметрия подаётся вручную через сигналы `FakeTrainer` при `inject_silence`,
## чтобы точно управлять мощностью/пульсом по секундам.

const FTP: int = 200

var _trainer: FakeTrainer
var _session: WorkoutSession
var _hud: HudModel
var _profile: Profile
var _changes: int = 0


func before_each() -> void:
	_changes = 0
	_trainer = FakeTrainer.new(5)
	_trainer.connect_delay_sec = 0.0
	_trainer.connect_device("hud")
	_trainer.inject_silence(1_000_000.0) # станок молчит — данные подаём вручную
	_profile = Profile.create("HUD")
	_profile.ftp_w = FTP
	_profile.max_hr = 180


func _make(steps: Array, intensity: float = 1.0, with_profile: bool = true) -> HudModel:
	var typed: Array[WorkoutStep] = []
	for s in steps:
		typed.append(s)
	_session = WorkoutSession.new(Workout.make("hud", typed), _trainer, FTP, intensity)
	_hud = HudModel.new(_session, _profile if with_profile else null)
	_hud.changed.connect(func(_s: Dictionary) -> void: _changes += 1)
	return _hud


## Подать телеметрию (мощность/каденс/скорость, пульс) и закрыть одну секунду.
func _second(power: int = -1, cadence: int = -1, speed: float = -1.0, hr: int = -1) -> Dictionary:
	if power >= 0 or cadence >= 0 or speed >= 0.0:
		var s := TrainerSample.new()
		s.timestamp_sec = _trainer.get_time_sec()
		if power >= 0:
			s.power_w = power
			s.has_power = true
		if cadence >= 0:
			s.cadence_rpm = cadence
			s.has_cadence = true
		if speed >= 0.0:
			s.speed_kmh = speed
			s.has_speed = true
		_trainer.telemetry.emit(s)
	if hr >= 0:
		_trainer.heart_rate.emit(hr)
	_session.tick(1.0)
	return _hud.state()


func _powers(values: Array) -> Dictionary:
	var st := {}
	for p in values:
		st = _second(p)
	return st


# ===========================================================================
# REQ-HUD-01 — целевая мощность
# ===========================================================================

func test_req_hud_01_c1_target_text_is_step_target_with_intensity_in_whole_watts() -> void:
	_make([WorkoutStep.percent(60, 65.0), WorkoutStep.watts(60, 250.0)], 1.1)
	_session.start()
	var st := _hud.state()
	assert_eq(st["target_w"], 143, "65 %% × 200 × 1.1 = 143")
	assert_eq(st["target_text"], "143", "целое число ватт; единица «Вт»/«W» добавляется сценой")
	_session.set_intensity(0.9)
	assert_eq(_hud.state()["target_text"], "117", "множитель отражён немедленно (WRK-07 крит. 4)")
	for i in 60:
		_second(100)
	assert_eq(_hud.state()["target_text"], "225", "250 × 0.9")


func test_req_hud_01_c2_free_ride_and_idle_show_dash() -> void:
	_make([WorkoutStep.free_ride(30), WorkoutStep.percent(30, 50.0)])
	assert_eq(_hud.state()["target_text"], HudModel.NO_DATA_TEXT, "до старта «—»")
	_session.start()
	var st := _hud.state()
	assert_eq(st["target_text"], "—")
	assert_eq(st["target_w"], HudModel.NO_DATA)
	assert_eq(st["power_deviation"], HudModel.DEVIATION_HIDDEN, "без цели индикация скрыта")
	for i in 30:
		_second(150)
	assert_eq(_hud.state()["target_text"], "100", "на шаге с целью снова число")


# ===========================================================================
# REQ-HUD-02 — фактическая мощность и отклонение
# ===========================================================================

func test_req_hud_02_c1_c3_smoothed_power_shown_and_deviation_recomputed_each_sample() -> void:
	_make([WorkoutStep.watts(60, 100.0)])
	_session.start()
	assert_eq(_hud.state()["power_text"], "—", "до первого сэмпла")
	assert_eq(_hud.state()["power_deviation"], HudModel.DEVIATION_HIDDEN, "без данных скрыта")
	var st := _second(130)
	assert_eq(st["smoothed_power_w"], 130)
	assert_eq(st["power_deviation"], HudModel.DEVIATION_ABOVE)
	st = _second(70) # среднее 100
	assert_eq(st["smoothed_power_w"], 100)
	assert_eq(st["power_deviation"], HudModel.DEVIATION_ON, "пересчитано на этом сэмпле")
	st = _second(10) # среднее 70
	assert_eq(st["power_deviation"], HudModel.DEVIATION_BELOW)
	assert_eq(_session.samples.power_w[2], 10, "в поток идёт сырое значение, не сглаженное")


func test_req_hud_02_c2_threshold_is_max_of_5pct_and_10w() -> void:
	# цель 100: порог 10 Вт
	assert_eq(HudModel.deviation_state(110, 100), HudModel.DEVIATION_ON)
	assert_eq(HudModel.deviation_state(111, 100), HudModel.DEVIATION_ABOVE)
	assert_eq(HudModel.deviation_state(90, 100), HudModel.DEVIATION_ON)
	assert_eq(HudModel.deviation_state(89, 100), HudModel.DEVIATION_BELOW)
	# цель 400: порог 20 Вт (5 %)
	assert_eq(HudModel.deviation_state(420, 400), HudModel.DEVIATION_ON)
	assert_eq(HudModel.deviation_state(421, 400), HudModel.DEVIATION_ABOVE)
	assert_eq(HudModel.deviation_state(379, 400), HudModel.DEVIATION_BELOW)
	# цель 200: порог ровно 10 (5 % = 10)
	assert_eq(HudModel.deviation_state(210, 200), HudModel.DEVIATION_ON)
	assert_eq(HudModel.deviation_state(211, 200), HudModel.DEVIATION_ABOVE)
	# скрыто
	assert_eq(HudModel.deviation_state(150, 0), HudModel.DEVIATION_HIDDEN)
	assert_eq(HudModel.deviation_state(HudModel.NO_DATA, 100), HudModel.DEVIATION_HIDDEN)
	assert_eq(HudModel.deviation_state(0, 100), HudModel.DEVIATION_BELOW, "0 Вт — данные, ниже цели")


func test_req_hud_02_c2_threshold_through_live_state_at_target_100() -> void:
	_make([WorkoutStep.watts(60, 100.0)])
	_session.start()
	assert_eq(_powers([110, 110, 110])["power_deviation"], HudModel.DEVIATION_ON)
	assert_eq(_powers([111, 111, 111])["power_deviation"], HudModel.DEVIATION_ABOVE)


# ===========================================================================
# REQ-HUD-03 — зона мощности
# ===========================================================================

func test_req_hud_03_c1_c2_zone_from_smoothed_power_and_profile_with_palette_tokens() -> void:
	_make([WorkoutStep.watts(60, 100.0)])
	_session.start()
	var expectations := {110: [1, "z1", "gray"], 111: [2, "z2", "blue"], 151: [3, "z3", "green"], 181: [4, "z4", "yellow"],
		211: [5, "z5", "orange"], 241: [6, "z6", "red"], 301: [7, "z7", "purple"]}
	for p in expectations.keys():
		var st := _powers([p, p, p])
		assert_eq(st["power_zone"], expectations[p][0], "%d Вт" % p)
		assert_eq(st["power_zone_text"], "Z%d" % expectations[p][0])
		assert_eq(st["power_zone_token"], expectations[p][1])
		assert_eq(ZonePalette.color_name(st["power_zone_token"]), expectations[p][2])
	# зона — по сглаженной: 100, 100, 400 → 200 → Z4, а не Z7
	var st := _powers([100, 100, 400])
	assert_eq(st["smoothed_power_w"], 200)
	assert_eq(st["power_zone"], 4)


func test_req_hud_03_c1_custom_profile_zones_change_result() -> void:
	_profile.power_zones = PowerZones.custom(FTP, [50.0, 100.0]) # 3 зоны
	_make([WorkoutStep.watts(60, 100.0)])
	_session.start()
	assert_eq(_powers([100, 100, 100])["power_zone"], 1, "100 Вт = 50 %% → Z1 (граница — нижняя зона)")
	assert_eq(_powers([101, 101, 101])["power_zone"], 2)
	assert_eq(_powers([201, 201, 201])["power_zone"], 3)
	assert_eq(_powers([400, 400, 400])["power_zone"], 3, "зон всего 3")


func test_req_hud_03_c3_zero_power_is_z1_and_no_data_is_dash() -> void:
	_make([WorkoutStep.watts(60, 100.0)])
	_session.start()
	var st := _powers([0, 0, 0])
	assert_eq(st["power_zone"], 1, "0 Вт → Z1")
	assert_eq(st["power_zone_text"], "Z1")
	assert_eq(st["power_zone_token"], "z1")
	for i in 3:
		st = _second() # нет данных
	assert_eq(st["power_zone"], 0)
	assert_eq(st["power_zone_text"], "—")
	assert_eq(st["power_zone_token"], "")
	assert_eq(ZonePalette.color(""), ZonePalette.NO_ZONE_COLOR)


func test_req_hud_03_c2_palette_tokens_and_colors() -> void:
	var names: Array[String] = ["gray", "blue", "green", "yellow", "orange", "red", "purple"]
	for z in range(1, 8):
		assert_eq(ZonePalette.power_token(z), "z%d" % z)
		assert_eq(ZonePalette.color_name("z%d" % z), names[z - 1])
		assert_true(ZonePalette.is_valid_token("z%d" % z))
	assert_eq(ZonePalette.power_token(0), "")
	assert_eq(ZonePalette.power_token(8), "")
	assert_eq(ZonePalette.hr_token(5), "hr5")
	assert_eq(ZonePalette.hr_token(6), "")
	var colors := {}
	for z in range(1, 8):
		colors[ZonePalette.color(ZonePalette.power_token(z))] = true
	assert_eq(colors.size(), 7, "семь различных цветов")


# ===========================================================================
# REQ-HUD-04 — зона пульса
# ===========================================================================

func test_req_hud_04_c1_hr_zone_table_at_max_hr_180() -> void:
	_make([WorkoutStep.watts(60, 100.0)])
	_session.start()
	var table := {107: 1, 108: 2, 126: 3, 144: 4, 162: 5}
	for bpm in table.keys():
		var st := _second(100, 80, 30.0, bpm)
		assert_eq(st["hr_bpm"], bpm)
		assert_eq(st["hr_zone"], table[bpm], "%d уд/мин" % bpm)
		assert_eq(st["hr_zone_text"], "Z%d" % table[bpm])
		assert_eq(st["hr_zone_token"], "hr%d" % table[bpm])


func test_req_hud_04_c2_no_sensor_or_no_max_hr_gives_dash_without_color() -> void:
	_make([WorkoutStep.watts(60, 100.0)])
	_session.start()
	var st := _second(100, 80, 30.0) # без пульса
	assert_eq(st["hr_text"], "—")
	assert_eq(st["hr_zone"], 0)
	assert_eq(st["hr_zone_text"], "—")
	assert_eq(st["hr_zone_token"], "")
	before_each()
	_profile.max_hr = 0
	_make([WorkoutStep.watts(60, 100.0)])
	_session.start()
	st = _second(100, 80, 30.0, 150)
	assert_eq(st["hr_text"], "150", "пульс показывается")
	assert_eq(st["hr_zone"], 0, "но зоны без max_hr нет")
	assert_eq(st["hr_zone_text"], "—")
	assert_eq(st["hr_zone_token"], "")


# ===========================================================================
# REQ-HUD-05 — пульс, каденс, скорость, время
# ===========================================================================

func test_req_hud_05_c1_c3_formats_and_dashes() -> void:
	_make([WorkoutStep.watts(7200, 100.0)])
	_session.start()
	var st := _second(150, 87, 33.456, 141)
	assert_eq(st["hr_text"], "141")
	assert_eq(st["cadence_text"], "87")
	# Скорость на HUD — модель (У-30, T-169), поле скорости станка 33.456 не используется.
	assert_eq(st["speed_text"], "%.1f" % float(_session.samples.last_row()["speed_kmh"]), "один знак после точки")
	assert_eq(HudModel.format_speed(33.456), "33.5", "один знак после точки")
	assert_eq(st["elapsed_text"], "00:01")
	st = _second()
	assert_eq(st["hr_text"], "—")
	assert_eq(st["cadence_text"], "—")
	assert_eq(st["speed_text"], "%.1f" % float(_session.samples.last_row()["speed_kmh"]),
		"скорость модели есть и без мощности — тяги нет, она убывает (У-33)")
	assert_eq(HudModel.format_speed(-1.0), "—", "нет скорости — прочерк")
	assert_eq(st["power_text"], "150", "сглаженное ещё держится (1 из 3 слотов)")
	assert_eq(HudModel.format_elapsed(59), "00:59")
	assert_eq(HudModel.format_elapsed(3599), "59:59")
	assert_eq(HudModel.format_elapsed(3600), "1:00:00")
	assert_eq(HudModel.format_elapsed(3661), "1:01:01")
	assert_eq(HudModel.format_elapsed(-5), "00:00")
	assert_eq(HudModel.format_speed(0.04), "0.0")
	assert_eq(HudModel.format_speed(-1.0), "—")


func test_req_hud_05_c2_elapsed_excludes_pause() -> void:
	_make([WorkoutStep.watts(600, 100.0)])
	_session.start()
	for i in 65:
		_second(100)
	assert_eq(_hud.state()["elapsed_text"], "01:05")
	_session.pause()
	for i in 30:
		_second(100)
	assert_eq(_hud.state()["elapsed_text"], "01:05", "пауза не входит")
	assert_eq(_hud.state()["elapsed_sec"], 65)
	_session.resume()
	_second(100)
	assert_eq(_hud.state()["elapsed_text"], "01:06")


# ===========================================================================
# REQ-HUD-06 — обратный отсчёт
# ===========================================================================

func test_req_hud_06_c1_c2_countdown_about_to_change_and_new_step_duration_on_transition() -> void:
	_make([WorkoutStep.watts(10, 100.0), WorkoutStep.watts(90, 150.0)])
	_session.start()
	var st := _hud.state()
	assert_eq(st["step_remaining_sec"], 10)
	assert_eq(st["countdown_text"], "00:10")
	assert_false(st["about_to_change"])
	for i in 4:
		st = _second(100)
	assert_eq(st["countdown_text"], "00:06")
	assert_false(st["about_to_change"], "6 с — ещё нет")
	st = _second(100)
	assert_eq(st["countdown_text"], "00:05")
	assert_true(st["about_to_change"], "за 5 с — «скоро смена»")
	for i in 4:
		st = _second(100)
	assert_eq(st["countdown_text"], "00:01")
	assert_true(st["about_to_change"])
	st = _second(100) # переход
	assert_eq(st["step_text"], "2/2")
	assert_eq(st["countdown_text"], "01:30", "на тике перехода — длительность нового шага")
	assert_false(st["about_to_change"])
	assert_eq(HudModel.format_countdown(-3), "00:00")


# ===========================================================================
# REQ-HUD-07 — полоса прогресса
# ===========================================================================

func test_req_hud_07_c1_segments_sum_and_cursor() -> void:
	_make([WorkoutStep.percent(60, 50.0), WorkoutStep.watts(30, 200.0), WorkoutStep.ramp_percent(30, 50.0, 100.0)])
	var segs := _hud.progress_segments()
	assert_eq(segs.size(), 3)
	var total := 0
	for s in segs:
		total += int(s["duration_sec"])
		for key in ["index", "start_sec", "duration_sec", "start_watts", "end_watts", "zone", "zone_token", "status"]:
			assert_true(s.has(key), "сегмент.%s" % key)
	assert_eq(total, 120, "сумма длительностей = длительность плана")
	assert_eq(segs[1]["start_sec"], 60)
	assert_eq(segs[2]["start_watts"], 100)
	assert_eq(segs[2]["end_watts"], 200)
	assert_eq(segs[0]["zone"], 1)
	assert_eq(segs[0]["zone_token"], "z1")
	assert_eq(segs[1]["zone"], 4)
	assert_eq(_hud.cursor(), 0.0)
	_session.start()
	for i in 30:
		_second(100)
	assert_almost_eq(_hud.cursor(), 0.25, 1e-9, "30 / 120")
	assert_almost_eq(float(_hud.state()["progress"]), 0.25, 1e-9)


func test_req_hud_07_c2_zone_recomputed_with_intensity_1_1() -> void:
	_make([WorkoutStep.watts(60, 200.0)])
	_session.start()
	var seg := _hud.progress_segments()[0]
	assert_eq(seg["start_watts"], 200)
	assert_eq(seg["zone"], 4, "200 Вт = 100 %% → Z4")
	_session.set_intensity(1.1)
	seg = _hud.progress_segments()[0]
	assert_eq(seg["start_watts"], 220, "ватты с множителем")
	assert_eq(seg["zone"], 5, "110 %% → Z5")
	assert_eq(seg["zone_token"], "z5")


func test_req_hud_07_c3_statuses_done_current_skipped_upcoming() -> void:
	_make([WorkoutStep.watts(10, 100.0), WorkoutStep.watts(10, 150.0), WorkoutStep.watts(10, 200.0), WorkoutStep.watts(10, 250.0)])
	_session.start()
	var statuses := func() -> Array:
		var out := []
		for s in _hud.progress_segments():
			out.append(s["status"])
		return out
	assert_eq(statuses.call(), ["current", "upcoming", "upcoming", "upcoming"])
	for i in 10:
		_second(100)
	assert_eq(statuses.call(), ["done", "current", "upcoming", "upcoming"])
	_session.skip_step()
	assert_eq(statuses.call(), ["done", "skipped", "current", "upcoming"])
	for i in 20:
		_second(100)
	assert_eq(_session.get_state(), WorkoutSession.State.FINISHED)
	assert_eq(statuses.call(), ["done", "skipped", "done", "done"], "после финиша все пройдены, пропущенный остаётся пропущенным")
	assert_eq(_hud.skipped_step_indices(), [1])
	assert_almost_eq(_hud.cursor(), 0.75, 1e-9, "30 активных секунд из 40")


func test_req_hud_07_edge_empty_plan_gives_no_segments_and_zero_cursor() -> void:
	_make([])
	assert_eq(_hud.progress_segments(), [])
	assert_eq(_hud.cursor(), 0.0)
	_session.start()
	assert_eq(_session.get_state(), WorkoutSession.State.FINISHED, "пустой план завершается сразу")
	var st := _hud.state()
	assert_eq(st["target_text"], "—")
	assert_eq(st["step_text"], "0/0")
	assert_eq(_hud.cursor(), 0.0)


# ===========================================================================
# REQ-HUD-08 — подсказки
# ===========================================================================

func _step_with_cues(duration: int, cues: Array) -> WorkoutStep:
	var step := WorkoutStep.watts(duration, 100.0)
	for c in cues:
		step.text_cues.append(TextCue.make(c[0], c[1]))
	return step


func test_req_hud_08_c1_c2_cue_from_step_start_and_with_offset_hidden_after_10s() -> void:
	_make([_step_with_cues(60, [[0, "Разминка"], [20, "Прибавь каденс"]]), _step_with_cues(60, [[0, "Интервал"]])])
	_session.start()
	assert_eq(_hud.state()["cue_text"], "Разминка", "подсказка шага — с начала шага")
	for i in 9:
		_second(100)
	assert_eq(_hud.state()["cue_text"], "Разминка", "9 с — ещё видна")
	_second(100)
	assert_eq(_hud.state()["cue_text"], "", "исчезла через 10 с")
	for i in 9:
		_second(100)
	assert_eq(_hud.state()["cue_text"], "", "19 с")
	_second(100)
	assert_eq(_hud.state()["cue_text"], "Прибавь каденс", "подсказка с timeoffset 20 — на 20-й секунде шага")
	for i in 10:
		_second(100)
	assert_eq(_hud.state()["cue_text"], "")


func test_req_hud_08_c2_step_change_clears_cue_and_shows_new_steps_cue() -> void:
	_make([_step_with_cues(10, [[5, "Скоро смена"]]), _step_with_cues(60, [[0, "Новый шаг"]]), WorkoutStep.watts(60, 100.0)])
	_session.start()
	for i in 5:
		_second(100)
	assert_eq(_hud.state()["cue_text"], "Скоро смена")
	for i in 5:
		_second(100)
	assert_eq(_hud.state()["cue_text"], "Новый шаг", "смена шага убрала старую и показала подсказку нового шага")
	# подсказка без замены на следующем шаге — пропадает при смене шага раньше 10 с
	before_each()
	_make([_step_with_cues(5, [[2, "Короткая"]]), WorkoutStep.watts(60, 100.0)])
	_session.start()
	for i in 3:
		_second(100)
	assert_eq(_hud.state()["cue_text"], "Короткая")
	for i in 2:
		_second(100)
	assert_eq(_hud.state()["cue_text"], "", "смена шага через 3 с после показа — подсказка снята")


func test_req_hud_08_c3_120_chars_as_is_and_121_truncated_with_ellipsis() -> void:
	var exact := "x".repeat(120)
	var longer := "y".repeat(121)
	assert_eq(HudModel.truncate_cue(exact), exact)
	var cut := HudModel.truncate_cue(longer)
	assert_eq(cut.length(), 120, "итоговая длина 120 с учётом «…»")
	assert_true(cut.ends_with("…"))
	assert_eq(cut.substr(0, 119), "y".repeat(119))
	_make([_step_with_cues(60, [[0, longer]])])
	_session.start()
	assert_eq(_hud.state()["cue_text"], cut, "обрезка применяется в состоянии")
	before_each()
	_make([_step_with_cues(60, [[0, exact]])])
	_session.start()
	assert_eq(_hud.state()["cue_text"], exact, "120 — как есть")


func test_req_hud_08_edge_cue_offset_beyond_step_is_never_shown() -> void:
	_make([_step_with_cues(10, [[15, "Никогда"]]), WorkoutStep.watts(20, 100.0)])
	_session.start()
	for i in 30:
		_second(100)
		assert_eq(_hud.state()["cue_text"], "", "секунда %d" % (i + 1))


# ===========================================================================
# REQ-HUD-09 — сглаживание 3 с
# ===========================================================================

func test_req_hud_09_c1_c2_c4_100_200_300_gives_200_then_267_fewer_samples_average_raw_untouched() -> void:
	_make([WorkoutStep.watts(60, 200.0)])
	_session.start()
	assert_eq(_second(100)["smoothed_power_w"], 100, "1 сэмпл — среднее доступных")
	assert_eq(_second(200)["smoothed_power_w"], 150, "2 сэмпла → 150")
	assert_eq(_second(300)["smoothed_power_w"], 200, "100, 200, 300 → 200")
	assert_eq(_second(300)["smoothed_power_w"], 267, "200, 300, 300 → 266.7 → 267")
	assert_eq(Array(_session.samples.power_w), [100, 200, 300, 300], "в поток идут несглаженные значения")


func test_req_hud_09_c3_missing_excluded_and_all_missing_is_dash() -> void:
	_make([WorkoutStep.watts(60, 200.0)])
	_session.start()
	_second(100)
	_second()
	var st := _second(300)
	assert_eq(st["smoothed_power_w"], 200, "«нет данных» исключён: (100 + 300) / 2")
	assert_eq(st["power_text"], "200")
	for i in 3:
		st = _second()
	assert_eq(st["smoothed_power_w"], HudModel.NO_DATA)
	assert_eq(st["power_text"], "—", "все три — «—»")
	assert_eq(st["power_deviation"], HudModel.DEVIATION_HIDDEN)
	assert_eq(st["power_zone_text"], "—")


# ===========================================================================
# REQ-WRK-03 крит. 1 / общее состояние HUD
# ===========================================================================

func test_req_wrk_03_c1_hud_state_reflects_erg_flag_and_free_ride_suspension() -> void:
	_make([WorkoutStep.watts(10, 100.0), WorkoutStep.free_ride(10)])
	_session.start()
	var st := _hud.state()
	assert_true(st["erg_enabled"])
	assert_true(st["erg_active_on_trainer"])
	_session.toggle_erg()
	st = _hud.state()
	assert_false(st["erg_enabled"], "состояние видно на HUD сразу")
	_session.toggle_erg()
	for i in 10:
		_second(100)
	st = _hud.state()
	assert_true(st["erg_enabled"], "на FreeRide переключатель пользователя — «вкл»")
	assert_false(st["erg_active_on_trainer"], "но станок в режиме сопротивления (В-10)")


func test_req_hud_without_profile_uses_coggan_by_ftp_and_hr_zone_dash() -> void:
	_make([WorkoutStep.watts(60, 100.0)], 1.0, false)
	_session.start()
	var st := _powers([181, 181, 181])
	assert_eq(st["power_zone"], 4, "Coggan от FTP сессии: 181 Вт → Z4")
	st = _second(181, 80, 30.0, 170)
	assert_eq(st["hr_text"], "170")
	assert_eq(st["hr_zone"], 0, "без профиля зон пульса нет")
	assert_eq(st["hr_zone_text"], "—")


func test_req_hud_changed_signal_fires_every_second_and_on_events() -> void:
	_make([WorkoutStep.watts(60, 100.0)])
	_changes = 0
	_session.start()
	var after_start := _changes
	assert_gt(after_start, 0, "старт (шаг, цель, состояние) пересчитывает")
	for i in 5:
		_second(100)
	assert_gte(_changes - after_start, 5, "не реже раза в секунду")
	var before := _changes
	_session.toggle_erg()
	assert_gt(_changes, before, "смена ERG пересчитывает")
	assert_eq(_hud.state()["session_state"], WorkoutSession.State.RUNNING)
	assert_eq(_hud.state()["connection_state"], TrainerDevice.ConnectionState.CONNECTED)
	assert_eq(_hud.state()["intensity_pct"], 100)


# ===========================================================================
# REQ-NFR-04 — экран не гаснет (KeepAwake с подставленным сеттером)
# ===========================================================================

func _keep_awake(calls: Array) -> KeepAwake:
	return KeepAwake.new(func(on: bool) -> void: calls.append(on))


func test_req_nfr_04_c1_start_sets_keep_on_finish_and_stop_release() -> void:
	var calls: Array = []
	var ka := _keep_awake(calls)
	_make([WorkoutStep.watts(3, 100.0)])
	ka.attach(_session)
	assert_eq(calls, [], "IDLE — сеттер не вызывался")
	assert_false(ka.is_on())
	_session.start()
	assert_eq(calls, [true], "при старте запрет включён")
	assert_true(ka.is_on())
	for i in 3:
		_second(100)
	assert_eq(_session.get_state(), WorkoutSession.State.FINISHED)
	assert_eq(calls, [true, false], "при завершении снят")
	# стоп досрочно
	before_each()
	calls = []
	ka = _keep_awake(calls)
	_make([WorkoutStep.watts(60, 100.0)])
	ka.attach(_session)
	_session.start()
	_session.stop()
	assert_eq(calls, [true, false], "при досрочном стопе снят")


func test_req_nfr_04_c1_screen_exit_releases_and_enter_restores_while_running() -> void:
	var calls: Array = []
	var ka := _keep_awake(calls)
	_make([WorkoutStep.watts(60, 100.0)])
	ka.attach(_session)
	_session.start()
	ka.on_screen_exited()
	assert_eq(calls, [true, false], "уход с экрана тренировки снимает запрет независимо от сессии")
	assert_eq(_session.get_state(), WorkoutSession.State.RUNNING)
	ka.on_screen_entered()
	assert_eq(calls, [true, false, true], "возврат на экран при RUNNING — снова запрет")
	ka.detach()
	assert_eq(calls, [true, false, true, false])
	_session.stop()
	assert_eq(calls.size(), 4, "после detach сессия не влияет")


func test_req_nfr_04_c2_pause_keeps_lock_without_extra_calls() -> void:
	var calls: Array = []
	var ka := _keep_awake(calls)
	_make([WorkoutStep.watts(60, 100.0)])
	ka.attach(_session)
	_session.start()
	_session.pause()
	assert_eq(calls, [true], "на паузе запрет сохраняется — повторного вызова нет")
	assert_true(ka.is_on())
	assert_true(KeepAwake.wants_keep_on(WorkoutSession.State.PAUSED))
	_session.resume()
	assert_eq(calls, [true])
	_session.pause()
	ka.on_screen_exited()
	assert_eq(calls, [true, false], "уход с экрана на паузе — снимает")
	ka.on_screen_entered()
	assert_eq(calls, [true, false, true], "возврат на паузе — восстанавливает")


func test_req_nfr_04_attach_to_running_session_applies_immediately_and_rule_table() -> void:
	var calls: Array = []
	var ka := _keep_awake(calls)
	_make([WorkoutStep.watts(60, 100.0)])
	_session.start()
	ka.attach(_session)
	assert_eq(calls, [true])
	assert_false(KeepAwake.wants_keep_on(WorkoutSession.State.IDLE))
	assert_true(KeepAwake.wants_keep_on(WorkoutSession.State.RUNNING))
	assert_true(KeepAwake.wants_keep_on(WorkoutSession.State.PAUSED))
	assert_false(KeepAwake.wants_keep_on(WorkoutSession.State.FINISHED))
	var changed: Array = []
	ka.changed.connect(func(on: bool) -> void: changed.append(on))
	ka.release()
	ka.release()
	assert_eq(calls, [true, false], "повторный release без вызова")
	assert_eq(changed, [false])
