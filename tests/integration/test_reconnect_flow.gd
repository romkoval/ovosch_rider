extends GutTest
## Переподключение без потери данных (REQ-DEV-08 крит. 1–4, уточнение крит. 3 по В-4; REQ-DEV-07 крит. 1;
## REQ-WRK-08 крит. 2): `BleTrainer` поверх `StubBleBridge` внутри `WorkoutSession` + `HudModel`.

const DEV: String = "tacx-neo"

var _bridge: StubBleBridge
var _trainer: TrainerDevice
var _session: WorkoutSession
var _hud: HudModel


func before_each() -> void:
	_bridge = StubBleBridge.new()
	_trainer = TrainerFactory.create_ble(_bridge)
	_trainer.connect_device(DEV)
	_bridge.pump()
	assert_eq(_trainer.get_connection_state(), TrainerDevice.ConnectionState.CONNECTED, "предусловие: подключён")
	_bridge.auto_connect = false
	var steps: Array[WorkoutStep] = [WorkoutStep.watts(10, 150.0), WorkoutStep.watts(10, 250.0), WorkoutStep.watts(10, 180.0)]
	_session = WorkoutSession.new(Workout.make("ble", steps), _trainer, 200)
	_hud = HudModel.new(_session)
	TranslationServer.set_locale("en")


func after_each() -> void:
	_bridge.pending.clear()  # неотработанные ответы заглушки держат ссылку на неё саму
	if _trainer is BleTrainer:
		(_trainer as BleTrainer).dispose()


## Секунда сессии с телеметрией станка (`power` < 0 — станок молчит).
func _second(power: int) -> void:
	if power >= 0:
		_bridge.emit_notification(DEV, BleUuids.INDOOR_BIKE_DATA, FtmsCodec.encode_indoor_bike_data(32.0, 88.0, power))
	_session.tick(1.0)


func _cp_writes() -> Array[String]:
	var out: Array[String] = []
	for w in _bridge.writes_to(BleUuids.FTMS_CONTROL_POINT):
		out.append((w["bytes"] as PackedByteArray).hex_encode())
	return out


func _drop() -> void:
	_bridge.emit_disconnected(DEV, BleBridge.DisconnectReason.LINK_LOSS)


func _restore() -> void:
	_bridge.emit_connected(DEV)
	_bridge.pump()


func test_dropout_mid_step_hud_shows_reconnecting_timer_runs_slots_no_data() -> void:
	_session.start()
	for i in 4:
		_second(150)
	_drop()
	assert_eq(_trainer.get_connection_state(), TrainerDevice.ConnectionState.RECONNECTING, "REQ-DEV-08 крит. 1")
	assert_eq(_hud.state()["connection_text"], "Reconnecting…", "HUD показывает переподключение")
	for i in 3:
		_second(-1)
	assert_eq(_session.executor.elapsed_sec(), 7, "крит. 2: таймер сессии идёт")
	assert_eq(_session.samples.size(), 7, "слоты пишутся")
	assert_false(_session.samples.has_power[6], "слот без данных — «нет данных», не 0")
	assert_eq(_session.samples.power_age_sec[6], 3)
	assert_eq(_hud.state()["power_text"], "—")


func test_reconnect_sends_request_control_then_target_in_same_second() -> void:
	_session.start()
	for i in 4:
		_second(150)
	_drop()
	_bridge.clear_calls()
	_second(-1)
	_restore()
	assert_eq(_trainer.get_connection_state(), TrainerDevice.ConnectionState.CONNECTED)
	var writes := _cp_writes()
	assert_eq(writes[0], "00", "Request Control заново")
	assert_eq(writes[1], "059600", "REQ-DEV-08 крит. 3: цель 150 Вт в ту же секунду после connected")
	assert_eq(_hud.state()["connection_text"], "Trainer connected")
	assert_eq(_session.executor.elapsed_sec(), 5, "команды ушли без продвижения времени")


func test_step_change_during_dropout_is_not_lost() -> void:
	_session.start()
	for i in 8:
		_second(150)
	_drop()
	for i in 4:
		_second(-1)  # граница 10 с пройдена в обрыве
	assert_eq(_session.current_target_watts(), 250)
	_bridge.clear_calls()
	_restore()
	assert_eq(_cp_writes(), ["00", "05fa00"], "после восстановления уходит актуальная цель 250 Вт, старая 150 — нет")
	assert_eq((_trainer as BleTrainer).target_power_w, 250)


func test_samples_before_dropout_are_intact_and_recording_continues_after() -> void:
	_session.start()
	for p in [150, 151, 152, 153, 154]:
		_second(p)
	_drop()
	_second(-1)
	_second(-1)
	_restore()
	for i in 3:
		_second(250)
	var s := _session.samples
	assert_eq(s.size(), 10)
	assert_eq(Array(s.power_w.slice(0, 5)), [150, 151, 152, 153, 154], "REQ-DEV-08 крит. 4: сэмплы до обрыва целы")
	assert_false(s.has_power[5])
	assert_false(s.has_power[6])
	assert_true(s.has_power[9], "после восстановления данные снова идут")
	assert_eq(s.power_w[9], 250)
	assert_true(s.is_monotonic())
	var types: Array[String] = []
	for e in _session.events:
		types.append(str(e["type"]))
	assert_has(types, WorkoutSession.EVENT_DISCONNECT)
	assert_has(types, WorkoutSession.EVENT_RECONNECT)


func test_reconnect_while_paused_sends_only_request_control_target_at_resume() -> void:
	_session.start()
	for i in 3:
		_second(150)
	_session.pause()
	_drop()
	_bridge.clear_calls()
	_restore()
	assert_eq(_cp_writes(), ["00"], "уточнение DEV-08.3 (В-4): на паузе — только Request Control")
	assert_eq(_session.samples.size(), 3, "на паузе слоты не пишутся")
	_session.resume()
	assert_eq(_cp_writes(), ["00", "059600"], "цель уходит при resume")


func test_reconnect_attempts_every_5s_keep_session_alive() -> void:
	_session.start()
	_second(150)
	_drop()
	_bridge.clear_calls()
	for i in 10:
		_second(-1)
	assert_eq(_bridge.calls_of("connect_peripheral").size(), 2, "попытки через 5 с без лимита (решение 12)")
	assert_eq(_session.get_state(), WorkoutSession.State.RUNNING)
	assert_eq(_session.executor.elapsed_sec(), 11)
	assert_eq(_hud.state()["connection_text"], "Reconnecting…")
	assert_eq(_hud.state()["connection_state"], TrainerDevice.ConnectionState.RECONNECTING)


func test_user_disconnect_is_final_and_hud_shows_disconnected() -> void:
	_session.start()
	_second(150)
	_trainer.disconnect_device()
	assert_eq(_trainer.get_connection_state(), TrainerDevice.ConnectionState.DISCONNECTED)
	assert_eq(_hud.state()["connection_text"], "Trainer disconnected")
	_bridge.clear_calls()
	for i in 6:
		_second(-1)
	assert_eq(_bridge.calls_of("connect_peripheral").size(), 0, "после disconnect_device попыток нет")
