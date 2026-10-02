extends GutTest
## Тесты HudModel (REQ-HUD-01..09, REQ-WRK-07 крит. 4, REQ-INT-05 крит. 3, REQ-WRK-05 крит. 2 — время без пауз).

const FTP: int = 200

var _trainer: FakeTrainer
var _session: WorkoutSession
var _hud: HudModel
var _profile: Profile


func before_each() -> void:
	_trainer = FakeTrainer.new(11)
	_trainer.connect_delay_sec = 0.0
	_trainer.power_noise_w = 0.0
	_trainer.power_tau_sec = 0.01  # мгновенная сходимость — удобно проверять числа
	_trainer.cadence_noise_rpm = 0.0
	_trainer.connect_device("hud")
	_profile = Profile.create("HUD")
	_profile.ftp_w = FTP
	_profile.max_hr = 180


func _steps(arr: Array) -> Array[WorkoutStep]:
	var out: Array[WorkoutStep] = []
	for s in arr:
		out.append(s)
	return out


func _plan() -> Workout:
	# 10 мин 50 %, 5 мин 100 % + подсказки
	var warm := WorkoutStep.percent(600, 50.0)
	warm.text_cues = [TextCue.make(0, "Разминка"), TextCue.make(30, "Держи каденс")]
	var hard := WorkoutStep.percent(300, 100.0)
	hard.text_cues = [TextCue.make(0, "Поехали")]
	return Workout.make("10/5", _steps([warm, hard]))


func _make(w: Workout = _plan(), with_profile: bool = true) -> HudModel:
	_session = WorkoutSession.new(w, _trainer, FTP)
	_hud = HudModel.new(_session, _profile if with_profile else null)
	return _hud


func _ticks(n: int) -> void:
	for i in n:
		_session.tick(1.0)


# ---------------------------------------------------------------------------
# Чистые функции
# ---------------------------------------------------------------------------

func test_deviation_threshold_max_of_5pct_and_10w() -> void:
	# цель 100 Вт → допуск 10 Вт
	assert_eq(HudModel.deviation_state(110, 100), HudModel.DEVIATION_ON)
	assert_eq(HudModel.deviation_state(111, 100), HudModel.DEVIATION_ABOVE)
	assert_eq(HudModel.deviation_state(90, 100), HudModel.DEVIATION_ON)
	assert_eq(HudModel.deviation_state(89, 100), HudModel.DEVIATION_BELOW)
	# цель 300 Вт → допуск 15 Вт
	assert_eq(HudModel.deviation_state(315, 300), HudModel.DEVIATION_ON)
	assert_eq(HudModel.deviation_state(316, 300), HudModel.DEVIATION_ABOVE, "REQ-HUD-02 крит. 2")
	assert_eq(HudModel.deviation_state(284, 300), HudModel.DEVIATION_BELOW)
	assert_eq(HudModel.deviation_state(200, 0), HudModel.DEVIATION_HIDDEN, "без цели — скрыто")
	assert_eq(HudModel.deviation_state(-1, 200), HudModel.DEVIATION_HIDDEN, "без данных — скрыто")


func test_format_elapsed_mmss_then_hmmss() -> void:
	assert_eq(HudModel.format_elapsed(0), "00:00")
	assert_eq(HudModel.format_elapsed(65), "01:05")
	assert_eq(HudModel.format_elapsed(3599), "59:59")
	assert_eq(HudModel.format_elapsed(3600), "1:00:00", "REQ-HUD-05 крит. 1: от часа — ч:мм:сс")
	assert_eq(HudModel.format_elapsed(3725), "1:02:05")
	assert_eq(HudModel.format_elapsed(-5), "00:00")


func test_format_countdown_and_speed() -> void:
	assert_eq(HudModel.format_countdown(600), "10:00")
	assert_eq(HudModel.format_countdown(5), "00:05")
	assert_eq(HudModel.format_countdown(-1), "00:00")
	assert_eq(HudModel.format_speed(34.26), "34.3")
	assert_eq(HudModel.format_speed(0.0), "0.0")
	assert_eq(HudModel.format_speed(-1.0), HudModel.NO_DATA_TEXT)


func test_truncate_cue_at_120_with_ellipsis() -> void:
	var exact := "a".repeat(120)
	assert_eq(HudModel.truncate_cue(exact), exact, "120 символов — как есть")
	var long := "b".repeat(121)
	var cut := HudModel.truncate_cue(long)
	assert_eq(cut.length(), 120)
	assert_true(cut.ends_with("…"), "REQ-HUD-08 крит. 3")
	assert_eq(HudModel.truncate_cue("short"), "short")


# ---------------------------------------------------------------------------
# Состояние на живой сессии
# ---------------------------------------------------------------------------

func test_idle_state_shows_dashes() -> void:
	var s := _make().state()
	assert_eq(s["target_text"], HudModel.NO_DATA_TEXT, "REQ-HUD-01 крит. 2")
	assert_eq(s["power_text"], HudModel.NO_DATA_TEXT)
	assert_eq(s["power_deviation"], HudModel.DEVIATION_HIDDEN)
	assert_eq(s["power_zone_text"], HudModel.NO_DATA_TEXT, "REQ-HUD-03 крит. 3: нет данных → «—»")
	assert_eq(s["hr_text"], HudModel.NO_DATA_TEXT)
	assert_eq(s["cadence_text"], HudModel.NO_DATA_TEXT)
	assert_eq(s["speed_text"], HudModel.NO_DATA_TEXT)
	assert_eq(s["elapsed_text"], "00:00")
	assert_eq(s["step_text"], HudModel.NO_DATA_TEXT)
	assert_eq(s["cue_text"], "")


func test_target_text_is_step_target_with_intensity_in_whole_watts() -> void:
	_make()
	_session.start()
	assert_eq(_hud.state()["target_w"], 100)
	assert_eq(_hud.state()["target_text"], "100", "REQ-HUD-01 крит. 1: 50 % от 200")
	_session.set_intensity(1.1)
	assert_eq(_hud.state()["target_text"], "110", "множитель применён (WRK-07 крит. 4)")
	assert_eq(_hud.state()["intensity_pct"], 110)


func test_smoothed_power_100_200_300_gives_200_then_267_and_raw_stream_untouched() -> void:
	_make()
	_trainer.inject_silence(1000.0)  # телеметрию эмулятора глушим — подаём свою
	_session.start()
	for p in [100, 200, 300]:
		_trainer.telemetry.emit(TrainerSample.full(0.0, p, 85, 30.0))
		_session.tick(1.0)
	assert_eq(_hud.state()["smoothed_power_w"], 200, "REQ-HUD-09 крит. 1")
	_trainer.telemetry.emit(TrainerSample.full(0.0, 300, 85, 30.0))
	_session.tick(1.0)
	assert_eq(_hud.state()["smoothed_power_w"], 267)
	assert_eq(Array(_session.samples.power_w), [100, 200, 300, 300], "REQ-HUD-09 крит. 4: в поток — сырые значения")


func test_smoothing_with_fewer_than_3_samples_and_missing_slots() -> void:
	_make()
	_trainer.inject_silence(1000.0)
	_session.start()
	_trainer.telemetry.emit(TrainerSample.full(0.0, 100, 85, 30.0))
	_session.tick(1.0)
	assert_eq(_hud.state()["smoothed_power_w"], 100, "REQ-HUD-09 крит. 2")
	_session.tick(1.0)  # нет данных
	assert_eq(_hud.state()["smoothed_power_w"], 100, "крит. 3: пропуск исключён из среднего")
	_session.tick(1.0)
	_session.tick(1.0)
	assert_eq(_hud.state()["smoothed_power_w"], HudModel.NO_DATA, "три пропуска подряд → «—»")
	assert_eq(_hud.state()["power_text"], HudModel.NO_DATA_TEXT)
	assert_eq(_hud.state()["power_deviation"], HudModel.DEVIATION_HIDDEN, "REQ-HUD-02 крит. 3")


func test_deviation_recomputed_each_sample_against_target() -> void:
	_make()
	_trainer.inject_silence(1000.0)
	_session.start()  # цель 100 → допуск 10
	for p in [100, 100, 100]:
		_trainer.telemetry.emit(TrainerSample.full(0.0, p, 85, 30.0))
		_session.tick(1.0)
	assert_eq(_hud.state()["power_deviation"], HudModel.DEVIATION_ON)
	for p in [130, 130, 130]:
		_trainer.telemetry.emit(TrainerSample.full(0.0, p, 85, 30.0))
		_session.tick(1.0)
	assert_eq(_hud.state()["power_deviation"], HudModel.DEVIATION_ABOVE)
	for p in [60, 60, 60]:
		_trainer.telemetry.emit(TrainerSample.full(0.0, p, 85, 30.0))
		_session.tick(1.0)
	assert_eq(_hud.state()["power_deviation"], HudModel.DEVIATION_BELOW)


func test_power_zone_by_smoothed_power_and_profile_zones_with_color_token() -> void:
	_make()
	_trainer.inject_silence(1000.0)
	_session.start()
	for p in [240, 240, 240]:
		_trainer.telemetry.emit(TrainerSample.full(0.0, p, 85, 30.0))
		_session.tick(1.0)
	assert_eq(_hud.state()["power_zone"], 5, "REQ-HUD-03 крит. 1: 240 Вт при FTP 200 → Z5")
	assert_eq(_hud.state()["power_zone_token"], "z5")
	assert_eq(ZonePalette.color_name(_hud.state()["power_zone_token"]), "orange", "REQ-HUD-03 крит. 2")
	for p in [0, 0, 0]:
		_trainer.telemetry.emit(TrainerSample.full(0.0, p, 0, 0.0))
		_session.tick(1.0)
	assert_eq(_hud.state()["power_zone"], 1, "REQ-HUD-03 крит. 3: мощность 0 → Z1")
	assert_eq(_hud.state()["power_zone_text"], "Z1")


func test_power_zone_uses_custom_profile_zone_count() -> void:
	_profile.power_zones = PowerZones.custom(FTP, [50.0, 100.0])  # 3 зоны, как из Intervals.icu
	_make()
	_trainer.inject_silence(1000.0)
	_session.start()
	for p in [240, 240, 240]:
		_trainer.telemetry.emit(TrainerSample.full(0.0, p, 85, 30.0))
		_session.tick(1.0)
	assert_eq(_hud.state()["power_zone"], 3, "по фактическому числу зон профиля (INT-06.2)")


func test_hr_zone_from_profile_and_dash_without_max_hr_or_sensor() -> void:
	_make()
	_trainer.set_heart_rate(144)
	_session.start()
	_ticks(2)
	assert_eq(_hud.state()["hr_bpm"], 144)
	assert_eq(_hud.state()["hr_zone"], 4, "REQ-HUD-04 крит. 1: 144 при max 180 → Z4")
	assert_eq(_hud.state()["hr_zone_token"], "hr4")
	_trainer.set_heart_rate(0)
	_ticks(2)
	assert_eq(_hud.state()["hr_text"], HudModel.NO_DATA_TEXT, "датчика нет → «—»")
	assert_eq(_hud.state()["hr_zone_token"], "", "без цвета")
	_profile.max_hr = 0
	_trainer.set_heart_rate(150)
	_ticks(2)
	assert_eq(_hud.state()["hr_bpm"], 150)
	assert_eq(_hud.state()["hr_zone"], 0, "REQ-HUD-04 крит. 2: max_hr не задан → «—»")
	assert_eq(_hud.state()["hr_zone_text"], HudModel.NO_DATA_TEXT)


func test_hr_zone_table_at_max_180() -> void:
	_make()
	_session.start()
	var expected := {107: 1, 108: 2, 126: 3, 144: 4, 162: 5}
	for bpm in expected:
		_trainer.set_heart_rate(bpm)
		_ticks(1)
		assert_eq(_hud.state()["hr_zone"], expected[bpm], "REQ-HUD-04 крит. 1: %d" % bpm)


func test_without_profile_power_zone_falls_back_to_coggan_and_hr_zone_is_dash() -> void:
	_make(_plan(), false)
	_trainer.set_heart_rate(150)
	_trainer.inject_silence(1000.0)
	_session.start()
	for p in [111, 111, 111]:
		_trainer.telemetry.emit(TrainerSample.full(0.0, p, 85, 30.0))
		_session.tick(1.0)
	assert_eq(_hud.state()["power_zone"], 2)
	assert_eq(_hud.state()["hr_zone"], 0)


func test_cadence_speed_elapsed_formats_and_pause_excluded() -> void:
	_make()
	_session.start()
	_ticks(65)
	var s := _hud.state()
	assert_eq(s["cadence_rpm"], 85)
	assert_eq(s["cadence_text"], "85")
	assert_true(str(s["speed_text"]).is_valid_float() and str(s["speed_text"]).split(".")[1].length() == 1, "скорость с одним знаком: %s" % s["speed_text"])
	assert_eq(s["elapsed_text"], "01:05", "REQ-HUD-05 крит. 1")
	_session.pause()
	_ticks(30)
	assert_eq(_hud.state()["elapsed_sec"], 65, "REQ-HUD-05 крит. 2: пауза не входит")
	_session.resume()
	_ticks(1)
	assert_eq(_hud.state()["elapsed_text"], "01:06")


func test_countdown_and_about_to_change_and_transition_shows_new_step_duration() -> void:
	_make()
	_session.start()
	assert_eq(_hud.state()["countdown_text"], "10:00", "REQ-HUD-06 крит. 1")
	assert_false(_hud.state()["about_to_change"])
	_ticks(594)
	assert_eq(_hud.state()["step_remaining_sec"], 6)
	assert_false(_hud.state()["about_to_change"])
	_ticks(1)
	assert_eq(_hud.state()["step_remaining_sec"], 5)
	assert_true(_hud.state()["about_to_change"], "REQ-HUD-06 крит. 2: за 5 с — «скоро смена»")
	_ticks(5)
	assert_eq(_hud.state()["step_index"], 1)
	assert_eq(_hud.state()["countdown_text"], "05:00", "на тике перехода — длительность нового шага")
	assert_eq(_hud.state()["step_text"], "2/2")
	assert_false(_hud.state()["about_to_change"])


func test_cue_shown_from_step_start_hidden_after_10s_and_cleared_on_step_change() -> void:
	_make()
	_session.start()
	assert_eq(_hud.state()["cue_text"], "Разминка", "REQ-HUD-08 крит. 1: подсказка шага с его начала")
	_ticks(9)
	assert_eq(_hud.state()["cue_text"], "Разминка", "на 9-й секунде ещё видна")
	_ticks(1)
	assert_eq(_hud.state()["cue_text"], "", "REQ-HUD-08 крит. 2: исчезла через 10 с")
	_ticks(20)
	assert_eq(_hud.state()["cue_text"], "Держи каденс", "подсказка с offset 30 — с указанной секунды")
	_ticks(5)
	_session.skip_step()
	assert_eq(_hud.state()["cue_text"], "Поехали", "смена шага скрывает старую, показывает подсказку нового")


func test_long_cue_is_truncated_in_state() -> void:
	var step := WorkoutStep.percent(60, 50.0)
	step.text_cues = [TextCue.make(0, "x".repeat(200))]
	_make(Workout.make("long", _steps([step])))
	_session.start()
	assert_eq(str(_hud.state()["cue_text"]).length(), 120)
	assert_true(str(_hud.state()["cue_text"]).ends_with("…"))


func test_progress_segments_sum_zone_tokens_and_cursor() -> void:
	_make()
	_session.start()
	var segs := _hud.progress_segments()
	assert_eq(segs.size(), 2)
	var total := 0
	for s in segs:
		total += int(s["duration_sec"])
	assert_eq(total, 900, "REQ-HUD-07 крит. 1: сумма длительностей = план")
	assert_eq(segs[0]["start_watts"], 100)
	assert_eq(segs[0]["zone"], 1)
	assert_eq(segs[0]["zone_token"], "z1", "REQ-INT-05 крит. 3: сегмент окрашен по зоне")
	assert_eq(segs[1]["start_sec"], 600)
	assert_eq(segs[1]["start_watts"], 200)
	assert_eq(segs[1]["zone"], 4)
	assert_eq(segs[0]["status"], HudModel.SEGMENT_CURRENT)
	assert_eq(segs[1]["status"], HudModel.SEGMENT_UPCOMING)
	_ticks(450)
	assert_almost_eq(_hud.cursor(), 0.5, 1e-9, "курсор = прошедшее / общее")
	assert_almost_eq(float(_hud.state()["progress"]), 0.5, 1e-9)


func test_progress_segments_recomputed_with_intensity_1_1() -> void:
	_make()
	_session.start()
	_session.set_intensity(1.1)
	var segs := _hud.progress_segments()
	assert_eq(segs[0]["start_watts"], 110, "REQ-WRK-07 крит. 4 / HUD-07 крит. 2")
	assert_eq(segs[1]["start_watts"], 220)
	assert_eq(segs[1]["zone"], 5, "220 Вт при FTP 200 → Z5 (было Z4)")
	assert_eq(segs[1]["zone_token"], "z5")


func test_progress_segments_done_and_skipped_statuses() -> void:
	var w := Workout.make("3", _steps([WorkoutStep.watts(10, 100.0), WorkoutStep.watts(10, 150.0), WorkoutStep.watts(10, 200.0)]))
	_make(w)
	_session.start()
	_ticks(10)
	_session.skip_step()  # пропускаем шаг 1
	var segs := _hud.progress_segments()
	assert_eq(segs[0]["status"], HudModel.SEGMENT_DONE, "REQ-HUD-07 крит. 3: пройден")
	assert_eq(segs[1]["status"], HudModel.SEGMENT_SKIPPED, "пропущен (из журнала событий)")
	assert_eq(segs[2]["status"], HudModel.SEGMENT_CURRENT)
	assert_eq(_hud.skipped_step_indices(), [1])
	_ticks(10)
	segs = _hud.progress_segments()
	assert_eq(segs[2]["status"], HudModel.SEGMENT_DONE, "после финиша всё пройдено")
	assert_eq(segs[1]["status"], HudModel.SEGMENT_SKIPPED, "пропущенный остаётся пропущенным")
	assert_eq(_hud.state()["step_text"], "3/3")


func test_erg_flags_and_connection_in_state() -> void:
	var w := Workout.make("fr", _steps([WorkoutStep.watts(5, 150.0), WorkoutStep.free_ride(5)]))
	_make(w)
	_session.start()
	assert_true(_hud.state()["erg_enabled"])
	assert_true(_hud.state()["erg_active_on_trainer"])
	_ticks(5)
	assert_true(_hud.state()["erg_enabled"], "переключатель пользователя «вкл» на FreeRide (В-10)")
	assert_false(_hud.state()["erg_active_on_trainer"])
	assert_eq(_hud.state()["target_text"], HudModel.NO_DATA_TEXT, "REQ-HUD-01 крит. 2: шаг без цели")
	assert_eq(_hud.state()["connection_state"], TrainerDevice.ConnectionState.CONNECTED)
	_session.set_erg_enabled(false)
	assert_false(_hud.state()["erg_enabled"])


func test_changed_signal_fires_every_second() -> void:
	_make()
	var seen: Array[Dictionary] = []
	_hud.changed.connect(func(s: Dictionary) -> void: seen.append(s))
	_session.start()
	var after_start := seen.size()
	_ticks(5)
	assert_true(seen.size() >= after_start + 5, "минимум одно обновление на секунду: %d" % seen.size())
	assert_eq(seen.back()["elapsed_sec"], 5, "последнее состояние актуально")
