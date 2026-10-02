extends GutTest
## Тесты WorkoutSession этапа 3 (REQ-WRK-02 крит. 5 по В-10, REQ-WRK-03, REQ-WRK-04 крит. 1, 3,
## REQ-WRK-05 крит. 2, 4, REQ-WRK-06 крит. 4, REQ-WRK-07 крит. 1, 5, REQ-WRK-08 крит. 4, 5,
## REQ-NFR-01 крит. 2, REQ-DEV-08 крит. 3 — уточнение).

const FTP: int = 200
const SEED: int = 31

var _trainer: FakeTrainer
var _session: WorkoutSession


func before_each() -> void:
	_trainer = FakeTrainer.new(SEED)
	_trainer.connect_delay_sec = 0.0
	_trainer.connect_device("fake-stage3")


func _steps(arr: Array) -> Array[WorkoutStep]:
	var out: Array[WorkoutStep] = []
	for s in arr:
		out.append(s)
	return out


func _plan_with_free_ride() -> Workout:
	return Workout.make("fr", _steps([WorkoutStep.watts(10, 150.0), WorkoutStep.free_ride(10), WorkoutStep.watts(10, 250.0)]))


func _plan_150_250() -> Workout:
	return Workout.make("150→250", _steps([WorkoutStep.watts(10, 150.0), WorkoutStep.watts(10, 250.0)]))


func _make(w: Workout, weight: float = 75.0) -> WorkoutSession:
	_session = WorkoutSession.new(w, _trainer, FTP, 1.0, weight)
	return _session


func _ticks(n: int, delta: float = 1.0) -> void:
	for i in n:
		_session.tick(delta)


func _cmds(type: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for c in _trainer.commands:
		if c["type"] == type:
			out.append(c)
	return out


func _events(type: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e in _session.events:
		if e["type"] == type:
			out.append(e)
	return out


# ---------------------------------------------------------------------------
# REQ-WRK-02 крит. 5 (В-10): FreeRide при включённом ERG
# ---------------------------------------------------------------------------

func test_free_ride_in_erg_switches_trainer_to_resistance_within_same_second() -> void:
	_make(_plan_with_free_ride())
	_session.resistance_level = 40
	_session.start()
	_ticks(10)
	var erg_cmds := _cmds(FakeTrainer.CMD_ERG)
	var res_cmds := _cmds(FakeTrainer.CMD_RESISTANCE)
	assert_eq(erg_cmds.size(), 1, "erg=false ушёл на границе FreeRide")
	assert_eq(erg_cmds[0]["value"], false)
	assert_almost_eq(float(erg_cmds[0]["at_sec"]), 10.0, 1e-6, "не позже 1 с после начала шага")
	assert_eq(res_cmds.size(), 1)
	assert_eq(res_cmds[0]["value"], 40)
	assert_false(_trainer.erg_enabled, "станок в режиме сопротивления")
	assert_true(_session.erg_enabled, "флаг пользователя не изменился")
	assert_true(_session.is_freeride_suspended())
	assert_false(_session.is_erg_active_on_trainer())
	var targets_before := _cmds(FakeTrainer.CMD_TARGET_POWER).size()
	_ticks(9)
	assert_eq(_cmds(FakeTrainer.CMD_TARGET_POWER).size(), targets_before, "за время FreeRide Set Target Power нет")
	assert_eq(_session.samples.target_w[15], 0)


func test_step_after_free_ride_restores_erg_and_target_in_same_second() -> void:
	_make(_plan_with_free_ride())
	_session.start()
	_ticks(20)
	var erg_cmds := _cmds(FakeTrainer.CMD_ERG)
	assert_eq(erg_cmds.size(), 2)
	assert_eq(erg_cmds[1]["value"], true)
	assert_almost_eq(float(erg_cmds[1]["at_sec"]), 20.0, 1e-6)
	var targets := _cmds(FakeTrainer.CMD_TARGET_POWER)
	assert_eq(targets.size(), 2)
	assert_eq(targets[1]["value"], 250)
	assert_almost_eq(float(targets[1]["at_sec"]), 20.0, 1e-6, "цель — в ту же секунду, что и erg=true")
	assert_true(_trainer.erg_enabled)
	assert_eq(_trainer.target_power_w, 250)
	assert_false(_session.is_freeride_suspended())


func test_free_ride_with_user_erg_off_changes_nothing() -> void:
	_make(_plan_with_free_ride())
	_session.erg_enabled = false
	_session.resistance_level = 35
	_session.start()
	_ticks(30)
	assert_eq(_cmds(FakeTrainer.CMD_TARGET_POWER).size(), 0)
	assert_eq(_cmds(FakeTrainer.CMD_ERG).size(), 1, "только erg=false на старте")
	assert_eq(_cmds(FakeTrainer.CMD_RESISTANCE).size(), 1)
	assert_false(_session.is_freeride_suspended())


func test_user_turns_erg_off_during_free_ride_then_on_during_target_step() -> void:
	_make(_plan_with_free_ride())
	_session.start()
	_ticks(15)
	_session.set_erg_enabled(false)
	assert_false(_session.erg_enabled)
	assert_false(_session.is_freeride_suspended(), "выключение пользователем снимает режим шага")
	_ticks(5)  # граница → шаг 250 Вт, ERG выключен пользователем
	assert_eq(_cmds(FakeTrainer.CMD_TARGET_POWER).size(), 1, "вне ERG цель не уходит")
	_session.set_erg_enabled(true)
	assert_eq(_trainer.commands.back()["type"], FakeTrainer.CMD_TARGET_POWER)
	assert_eq(_trainer.commands.back()["value"], 250)


func test_free_ride_first_step_suspends_erg_at_start() -> void:
	_make(Workout.make("fr-first", _steps([WorkoutStep.free_ride(5), WorkoutStep.watts(5, 150.0)])))
	_session.start()
	assert_eq(_cmds(FakeTrainer.CMD_ERG).size(), 1)
	assert_eq(_cmds(FakeTrainer.CMD_ERG)[0]["value"], false)
	assert_false(_trainer.erg_enabled)
	_ticks(5)
	assert_true(_trainer.erg_enabled)
	assert_eq(_cmds(FakeTrainer.CMD_TARGET_POWER).back()["value"], 150)


func test_reconnect_during_free_ride_resends_resistance_mode() -> void:
	_make(_plan_with_free_ride())
	_session.start()
	_ticks(12)
	_trainer.inject_dropout(2.0)
	_ticks(2)
	assert_eq(_trainer.get_connection_state(), TrainerDevice.ConnectionState.CONNECTED)
	var n := _trainer.commands.size()
	assert_eq(_trainer.commands[n - 2]["type"], FakeTrainer.CMD_ERG)
	assert_eq(_trainer.commands[n - 2]["value"], false, "после переподключения на FreeRide — режим сопротивления")
	assert_eq(_trainer.commands[n - 1]["type"], FakeTrainer.CMD_RESISTANCE)


func test_skip_into_free_ride_while_paused_applies_mode_on_resume() -> void:
	_make(_plan_with_free_ride())
	_session.start()
	_ticks(3)
	_session.pause()
	var before := _trainer.commands.size()
	_session.skip_step()
	assert_eq(_trainer.commands.size(), before, "на паузе ничего не шлём")
	assert_true(_session.is_freeride_suspended())
	_session.resume()
	assert_eq(_trainer.commands[before]["type"], FakeTrainer.CMD_ERG)
	assert_eq(_trainer.commands[before]["value"], false)
	assert_eq(_trainer.commands[before + 1]["type"], FakeTrainer.CMD_RESISTANCE)


# ---------------------------------------------------------------------------
# REQ-WRK-03 / REQ-WRK-04
# ---------------------------------------------------------------------------

func test_toggle_erg_is_one_action_and_emits_signal() -> void:
	_make(_plan_150_250())
	var changes: Array[bool] = []
	_session.erg_changed.connect(func(e: bool) -> void: changes.append(e))
	_session.start()
	_ticks(2)
	_session.toggle_erg()
	assert_false(_session.erg_enabled)
	_session.toggle_erg()
	assert_true(_session.erg_enabled)
	assert_eq(changes, [false, true])
	assert_eq(_events(WorkoutSession.EVENT_ERG_OFF).size(), 1)
	assert_eq(_events(WorkoutSession.EVENT_ERG_ON).size(), 1)
	assert_almost_eq(float(_events(WorkoutSession.EVENT_ERG_OFF)[0]["at_sec"]), 2.0, 1e-6)


func test_erg_toggle_does_not_stop_timer_or_recording() -> void:
	_make(_plan_150_250())
	_session.start()
	_ticks(5)
	_session.toggle_erg()
	_ticks(5)
	_session.toggle_erg()
	_ticks(5)
	assert_eq(_session.executor.elapsed_sec(), 15, "REQ-WRK-03 крит. 4: таймер идёт")
	assert_eq(_session.samples.size(), 15, "запись не прерывается")
	assert_true(_session.samples.is_monotonic())
	assert_false(_session.samples.erg_enabled[7])
	assert_true(_session.samples.erg_enabled[12])


func test_erg_default_on_at_start() -> void:
	_make(_plan_150_250())
	assert_true(_session.erg_enabled, "REQ-WRK-03 крит. 5")
	assert_true(_session.is_erg_active_on_trainer())


func test_resistance_level_snaps_to_step_5_and_emits_signal() -> void:
	_make(_plan_150_250())
	var levels: Array[int] = []
	_session.resistance_level_changed.connect(func(p: int) -> void: levels.append(p))
	_session.set_resistance_level(37)
	assert_eq(_session.resistance_level, 35)
	_session.set_resistance_level(38)
	assert_eq(_session.resistance_level, 40)
	_session.set_resistance_level(-10)
	assert_eq(_session.resistance_level, 0)
	_session.set_resistance_level(999)
	assert_eq(_session.resistance_level, 100)
	_session.set_resistance_level(100)
	assert_eq(levels, [35, 40, 0, 100], "повтор того же уровня сигнал не даёт")
	assert_eq(WorkoutSession.snap_resistance(52), 50)
	assert_eq(WorkoutSession.snap_resistance(53), 55)


func test_resistance_level_signal_lets_owner_persist_to_profile() -> void:
	_make(_plan_150_250())
	var profile := Profile.create("Rider")
	_session.resistance_level = profile.resistance_level_default
	_session.resistance_level_changed.connect(func(p: int) -> void: profile.resistance_level_default = p)
	_session.set_resistance_level(65)
	assert_eq(profile.resistance_level_default, 65, "REQ-WRK-04 крит. 1: уровень уходит в профиль через сигнал")
	assert_eq(profile.validate(), [])


func test_resistance_change_in_erg_is_stored_and_sent_only_when_erg_goes_off() -> void:
	_make(_plan_150_250())
	_session.start()
	_ticks(2)
	_session.set_resistance_level(60)
	assert_eq(_cmds(FakeTrainer.CMD_RESISTANCE).size(), 0, "REQ-WRK-04 крит. 3")
	_session.set_erg_enabled(false)
	assert_eq(_cmds(FakeTrainer.CMD_RESISTANCE).back()["value"], 60)
	assert_almost_eq(float(_cmds(FakeTrainer.CMD_RESISTANCE).back()["at_sec"]), 2.0, 1e-6)


func test_resistance_change_while_paused_outside_erg_is_sent_on_resume() -> void:
	_make(_plan_150_250())
	_session.erg_enabled = false
	_session.start()
	_ticks(2)
	_session.pause()
	var before := _trainer.commands.size()
	_session.set_resistance_level(80)
	assert_eq(_trainer.commands.size(), before)
	_session.resume()
	assert_eq(_cmds(FakeTrainer.CMD_RESISTANCE).back()["value"], 80)


# ---------------------------------------------------------------------------
# REQ-WRK-05 / REQ-WRK-06: журнал событий
# ---------------------------------------------------------------------------

func test_pause_event_has_begin_and_end_times() -> void:
	_make(_plan_150_250())
	_session.start()
	_ticks(3)
	_session.pause()
	_ticks(4)  # станок тикает, сессия стоит
	_session.resume()
	var pauses := _events(WorkoutSession.EVENT_PAUSE)
	assert_eq(pauses.size(), 1)
	assert_almost_eq(float(pauses[0]["at_sec"]), 3.0, 1e-6)
	assert_true(pauses[0].has("until_sec"), "REQ-WRK-05 крит. 2: время окончания паузы")
	assert_almost_eq(float(pauses[0]["until_sec"]), 3.0, 1e-6, "сессионное время на паузе не идёт (В-4)")
	assert_eq(_events(WorkoutSession.EVENT_RESUME).size(), 1)
	assert_eq(_session.samples.size(), 3)


func test_skip_event_records_step_index_and_time() -> void:
	_make(_plan_150_250())
	_session.start()
	_ticks(4)
	_session.tick(0.5)
	_session.skip_step()
	var skips := _events(WorkoutSession.EVENT_SKIP)
	assert_eq(skips.size(), 1, "REQ-WRK-06 крит. 4")
	assert_eq(skips[0]["value"], 0, "номер пропущенного шага")
	assert_almost_eq(float(skips[0]["at_sec"]), 4.5, 1e-6)


func test_stop_marks_stopped_early_keeps_data_and_logs_events() -> void:
	_make(_plan_150_250())
	_session.start()
	_ticks(6)
	_session.stop()
	assert_eq(_session.get_state(), WorkoutSession.State.FINISHED)
	assert_true(_session.metadata()["stopped_early"], "REQ-WRK-05 крит. 4")
	assert_eq(_session.metadata()["elapsed_sec"], 6)
	assert_eq(_session.samples.size(), 6, "данные сохранены")
	var types: Array[String] = []
	for e in _session.events:
		types.append(str(e["type"]))
	assert_eq(types, [WorkoutSession.EVENT_START, WorkoutSession.EVENT_STOP, WorkoutSession.EVENT_FINISH])


func test_event_logged_signal_and_full_plan_events() -> void:
	_make(_plan_150_250())
	var logged: Array[String] = []
	_session.event_logged.connect(func(e: Dictionary) -> void: logged.append(str(e["type"])))
	_session.start()
	_ticks(20)
	assert_eq(logged, [WorkoutSession.EVENT_START, WorkoutSession.EVENT_FINISH])
	assert_false(_session.metadata()["stopped_early"])


# ---------------------------------------------------------------------------
# REQ-WRK-07: множитель
# ---------------------------------------------------------------------------

func test_intensity_snaps_and_is_stored_in_metadata_and_events() -> void:
	_make(_plan_150_250())
	var changes: Array[float] = []
	_session.intensity_changed.connect(func(f: float) -> void: changes.append(f))
	_session.start()
	_ticks(2)
	_session.set_intensity(1.12)
	assert_almost_eq(_session.intensity(), 1.1, 1e-9, "шаг 5 %")
	assert_almost_eq(float(_session.metadata()["intensity"]), 1.1, 1e-9, "REQ-WRK-07 крит. 5")
	assert_eq(_cmds(FakeTrainer.CMD_TARGET_POWER).back()["value"], 165)
	_session.set_intensity(1.1)
	assert_eq(changes.size(), 1, "повтор без изменений не логируется")
	assert_eq(_events(WorkoutSession.EVENT_INTENSITY).size(), 1)
	_session.set_intensity(2.0)
	assert_almost_eq(_session.intensity(), 1.5, 1e-9, "кламп 150 %")
	_session.set_intensity(0.1)
	assert_almost_eq(_session.intensity(), 0.5, 1e-9, "кламп 50 %")


# ---------------------------------------------------------------------------
# REQ-WRK-08 крит. 4, 5: возраст данных и источник скорости
# ---------------------------------------------------------------------------

func test_speed_source_trainer_when_trainer_sends_speed() -> void:
	_make(_plan_150_250())
	_session.start()
	_ticks(5)
	assert_eq(_session.samples.speed_source, SampleStream.SPEED_SOURCE_TRAINER, "REQ-WRK-08 крит. 5")
	assert_eq(_session.metadata()["speed_source"], "trainer")
	assert_true(_session.samples.has_speed[3])
	assert_gt(_session.samples.speed_kmh[3], 20.0, "скорость станка в сэмпле")
	assert_gt(_session.samples.total_distance_m(), 0.0)


func test_speed_source_model_when_trainer_has_no_speed_field() -> void:
	_trainer.emit_speed = false
	_trainer.power_noise_w = 0.0
	_make(Workout.make("steady", _steps([WorkoutStep.watts(60, 200.0)])), 75.0)
	_session.start()
	_ticks(60)
	assert_eq(_session.samples.speed_source, SampleStream.SPEED_SOURCE_MODEL)
	assert_eq(_session.metadata()["speed_source"], "model")
	assert_true(_session.samples.has_speed[59], "расчётная скорость присутствует")
	assert_almost_eq(_session.samples.speed_kmh[59], 34.0, 3.0, "200 Вт / 75 кг → 34 ± 3 км/ч")
	assert_true(_session.samples.speed_kmh[1] - _session.samples.speed_kmh[0] <= 5.0, "плавный разгон")
	assert_almost_eq(_session.samples.total_distance_m(), 60.0 * 34.0 / 3.6, 120.0, "дистанция ~ интеграл скорости")


func test_speed_source_is_chosen_once_even_if_speed_appears_later() -> void:
	_trainer.emit_speed = false
	_make(_plan_150_250())
	_session.start()
	_ticks(5)
	_trainer.emit_speed = true
	_ticks(5)
	assert_eq(_session.samples.speed_source, SampleStream.SPEED_SOURCE_MODEL, "выбор делается один раз")
	assert_true(_session.samples.has_speed[9])


func test_speed_source_defaults_to_model_when_no_telemetry_at_all() -> void:
	_trainer.inject_silence(1000.0)
	_make(_plan_150_250())
	_session.start()
	_ticks(20)
	assert_eq(_session.samples.speed_source, SampleStream.SPEED_SOURCE_MODEL)
	assert_false(_session.samples.has_power[10])
	assert_true(_session.samples.has_speed[10], "модель считает по мощности 0")
	assert_eq(_session.samples.speed_kmh[10], 0.0)


func test_data_age_grows_during_silence_and_resets_on_data() -> void:
	_make(_plan_150_250())
	_session.start()
	_ticks(3)
	assert_eq(_session.samples.power_age_sec[2], 0)
	assert_eq(_session.data_age_sec("power"), 0)
	_trainer.inject_silence(6.0)
	_ticks(6)
	assert_false(_session.samples.has_power[8], "слот без телеметрии — «нет данных» (строже крит. 4)")
	assert_eq(_session.samples.power_age_sec[8], 6, "возраст данных 6 с")
	assert_true(SampleStream.is_stale(_session.samples.power_age_sec[8]), "REQ-WRK-08 крит. 4: старше 5 с")
	assert_false(SampleStream.is_stale(_session.samples.power_age_sec[6]), "4 с — ещё не устарели")
	assert_eq(_session.data_age_sec("power"), 6)
	_ticks(1)
	assert_eq(_session.samples.power_age_sec[9], 0, "данные вернулись")
	assert_eq(_session.samples.heart_rate_age_sec[9], -1, "пульса не было ни разу")
	assert_eq(_session.data_age_sec("heart_rate"), -1)


func test_sample_stream_to_dict_from_dict_roundtrip() -> void:
	_make(_plan_150_250())
	_trainer.set_heart_rate(140)
	_session.start()
	_ticks(12)
	var d := _session.samples.to_dict()
	var json: Variant = JSON.parse_string(JSON.stringify(d))
	var copy := SampleStream.from_dict(json)
	assert_eq(copy.size(), 12)
	assert_eq(copy.speed_source, "trainer")
	assert_true(copy.is_monotonic())
	for i in 12:
		var a := _session.samples.row(i)
		var b := copy.row(i)
		for key in ["time_sec", "power_w", "has_power", "cadence_rpm", "has_cadence", "has_speed",
				"heart_rate_bpm", "has_heart_rate", "target_w", "step_index", "erg_enabled", "power_age_sec"]:
			assert_eq(b[key], a[key], "строка %d, поле %s" % [i, key])
		assert_almost_eq(float(b["speed_kmh"]), float(a["speed_kmh"]), 1e-3)
		assert_almost_eq(float(b["distance_m"]), float(a["distance_m"]), 1e-2)
	assert_eq(SampleStream.from_dict({}).size(), 0)
	assert_eq(SampleStream.from_dict({"time_sec": [0, 1], "power_w": [100]}).size(), 1, "колонки обрезаются до кратчайшей")


# ---------------------------------------------------------------------------
# REQ-NFR-01 крит. 2: повтор при ошибке записи
# ---------------------------------------------------------------------------

func test_write_failed_triggers_single_retry_in_same_second() -> void:
	_make(_plan_150_250())
	_session.start()
	_ticks(9)
	_trainer.fail_next_command(TrainerDevice.ErrorCode.WRITE_FAILED)
	_session.tick(1.0)  # граница: цель 250 отвергнута → повтор
	var targets := _cmds(FakeTrainer.CMD_TARGET_POWER)
	assert_eq(targets.size(), 3, "исходная 150, отвергнутая 250, повтор 250")
	assert_eq(targets[2]["value"], 250)
	assert_almost_eq(float(targets[2]["at_sec"]), 10.0, 1e-6, "повтор в ту же секунду")
	assert_eq(_trainer.target_power_w, 250, "повтор применился")
	assert_eq(_events(WorkoutSession.EVENT_RETRY).size(), 1)


func test_write_failed_retry_not_more_than_once_per_second() -> void:
	_make(_plan_150_250())
	_session.start()
	_ticks(2)
	var before := _cmds(FakeTrainer.CMD_TARGET_POWER).size()
	_trainer.fail_next_command(TrainerDevice.ErrorCode.WRITE_FAILED)
	_trainer.error.emit(TrainerDevice.ErrorCode.WRITE_FAILED, "simulated")  # → повтор, который сам отвергнут
	assert_eq(_cmds(FakeTrainer.CMD_TARGET_POWER).size(), before + 1, "один повтор")
	_trainer.error.emit(TrainerDevice.ErrorCode.WRITE_FAILED, "simulated again")
	assert_eq(_cmds(FakeTrainer.CMD_TARGET_POWER).size(), before + 1, "второй отказ в ту же секунду не повторяется")
	_session.tick(1.0)
	_trainer.error.emit(TrainerDevice.ErrorCode.WRITE_FAILED, "next second")
	assert_eq(_cmds(FakeTrainer.CMD_TARGET_POWER).size(), before + 2, "в следующую секунду повтор снова возможен")


func test_control_point_rejected_is_not_retried_by_session() -> void:
	_make(_plan_150_250())
	_session.start()
	_ticks(9)
	_trainer.fail_next_command()
	_session.tick(1.0)
	assert_eq(_cmds(FakeTrainer.CMD_TARGET_POWER).size(), 2, "отказ Control Point сессия не повторяет")
	assert_eq(_events(WorkoutSession.EVENT_RETRY).size(), 0)


func test_write_failed_outside_erg_retries_resistance_level() -> void:
	_make(_plan_150_250())
	_session.erg_enabled = false
	_session.resistance_level = 45
	_session.start()
	_ticks(2)
	var before := _cmds(FakeTrainer.CMD_RESISTANCE).size()
	_trainer.error.emit(TrainerDevice.ErrorCode.WRITE_FAILED, "simulated")
	assert_eq(_cmds(FakeTrainer.CMD_RESISTANCE).size(), before + 1)
	assert_eq(_cmds(FakeTrainer.CMD_RESISTANCE).back()["value"], 45)


func test_write_failed_while_paused_is_ignored() -> void:
	_make(_plan_150_250())
	_session.start()
	_ticks(2)
	_session.pause()
	var before := _trainer.commands.size()
	_trainer.error.emit(TrainerDevice.ErrorCode.WRITE_FAILED, "simulated")
	assert_eq(_trainer.commands.size(), before, "на паузе ничего не шлём (В-4)")


# ---------------------------------------------------------------------------
# Переподключение (REQ-DEV-08 крит. 3 — уточнение) и метаданные
# ---------------------------------------------------------------------------

func test_disconnect_and_reconnect_are_logged_and_reconnect_on_pause_defers_target() -> void:
	_make(_plan_150_250())
	_session.start()
	_ticks(2)
	_session.pause()
	_trainer.inject_dropout(1.0)
	var before := _trainer.commands.size()
	_ticks(1)
	assert_eq(_trainer.get_connection_state(), TrainerDevice.ConnectionState.CONNECTED)
	assert_eq(_trainer.commands.size(), before, "после connected на паузе цель не шлётся")
	assert_eq(_events(WorkoutSession.EVENT_DISCONNECT).size(), 1)
	assert_eq(_events(WorkoutSession.EVENT_RECONNECT).size(), 1)
	_session.resume()
	assert_eq(_trainer.commands.back()["type"], FakeTrainer.CMD_TARGET_POWER)
	assert_eq(_trainer.commands.back()["value"], 150)


func test_metadata_contains_ride_fields() -> void:
	_make(_plan_150_250(), 82.0)
	_session.start()
	_ticks(20)
	var m := _session.metadata()
	assert_eq(m["workout_name"], "150→250")
	assert_eq(m["ftp_w"], FTP)
	assert_almost_eq(float(m["weight_kg"]), 82.0, 1e-9)
	assert_almost_eq(float(m["intensity"]), 1.0, 1e-9)
	assert_eq(m["speed_source"], "trainer")
	assert_eq(m["elapsed_sec"], 20)
	assert_eq(m["planned_sec"], 20)
	assert_eq(m["sample_count"], 20)
	assert_gt(int(m["started_at_unix"]), 0)
	assert_false(m["stopped_early"])
	assert_true(m["erg_enabled"])
