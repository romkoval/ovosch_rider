extends GutTest
## Приёмка T-068 (tester): `SimController` и делегирование SIM в `SensorHub`.
## REQ-FRD-04 крит. 2 (передаваемый уклон g·k/100, округление 0.01 %), крит. 3 (диапазон
## 0x2AD5, запасной −10…+20 %), крит. 4 (не чаще раза в 1 с и порог 0.1 %), крит. 5 (новый
## участок, старт, возобновление, переподключение — не позже 1 с), крит. 6 (нет SIM →
## фиксированное сопротивление, сессия не прерывается); REQ-FRD-05 крит. 1–4; REQ-FRD-01 крит. 2.
##
## Отличия от тестов разработчика: байты Control Point проверяются по `StubBleBridge` для
## всех чисел критериев (k = 0/50/100, спуски, края диапазона станка); задержки — по меткам
## `at_sec` журнала `FakeTrainer` в худшем случае (смена участка сразу после отправки);
## порог — на границе 0.1 % и при медленном дрейфе уклона; отказ SIM — на всех кодах ≠ 0x01;
## переподключение и потеря управления — по BLE; станок, оставшийся в ERG после тренировки
## по плану, — 0x05 всё равно не уходит; SIM через `SensorHub` поверх `BleTrainer`.
##
## Сообщение «станок не поддерживает SIM» на HUD (FRD-04.6, FRD-06.7) — T-084, здесь только
## сигнал контроллера.

const DEV: String = "neo-acc-068"
const CHARS: Array[String] = ["2AD2", "2AD9", "2ADA", "2AD6", "2ACC", "2AD5"]
const FEATURES_SIM: String = "83 40 00 00 0C 20 00 00"
const FEATURES_NO_SIM: String = "83 40 00 00 0C 00 00 00"
## Supported Resistance Level Range 0..100.0, шаг 0.1 (как у Tacx Neo).
const RES_RANGE: String = "00 00 E8 03 01 00"
## Supported Inclination Range −5.0 … +10.0 %, шаг 0.1.
const INCL_NARROW: String = "CE FF 64 00 01 00"
const DT: float = 0.05
const EPS: float = 1e-6

var _ft: FakeTrainer
var _sc: SimController
var _bridge: StubBleBridge
var _ble: BleTrainer
var _hub: SensorHub
var _unavailable: int = 0
var _events: Array[Dictionary] = []


func before_each() -> void:
	_unavailable = 0
	_events = []
	_ft = FakeTrainer.new(3)
	_ft.connect_delay_sec = 0.0
	_ft.connect_device("fake")


func after_each() -> void:
	if _sc != null:
		_sc.dispose()
		_sc = null
	if _hub != null:
		_hub.dispose()
		_hub = null
	if _ble != null:
		_ble.dispose()
		_ble = null
	if _bridge != null:
		_bridge.dispose()
		_bridge = null


func _on_unavailable() -> void:
	_unavailable += 1


func _on_event(type: String, value: Variant) -> void:
	_events.append({"type": type, "value": value})


func _make(device: TrainerDevice, k: int = 50, mode: SimController.Mode = SimController.Mode.SIM,
		level: int = 50) -> SimController:
	_sc = SimController.new(device, k, mode, level)
	_sc.simulation_unavailable.connect(_on_unavailable)
	_sc.ride_event.connect(_on_event)
	return _sc


## Шаг владельца: станок, затем контроллер (контракт `SimController.tick`).
func _step_ft(dt: float, g: float) -> void:
	_ft.tick(dt)
	_sc.tick(dt, g)


func _run_ft(sec: float, g: float, dt: float = DT) -> void:
	for i in roundi(sec / dt):
		_step_ft(dt, g)


func _sims() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for c in _ft.commands:
		if c["type"] == FakeTrainer.CMD_SIM:
			out.append(c)
	return out


func _of(type: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for c in _ft.commands:
		if c["type"] == type:
			out.append(c)
	return out


# --- BLE ---------------------------------------------------------------------

func _ble_setup(chars: Array[String] = CHARS, features: String = FEATURES_SIM, incl: String = "",
		res: String = RES_RANGE) -> void:
	_bridge = StubBleBridge.new()
	_ble = BleTrainer.new(_bridge)
	_bridge.set_device_services(DEV, {"1826": chars})
	if features != "":
		_bridge.set_read_value("2ACC", BleBytes.from_hex(features))
	if incl != "":
		_bridge.set_read_value("2AD5", BleBytes.from_hex(incl))
	if res != "":
		_bridge.set_read_value("2AD6", BleBytes.from_hex(res))
	_ble.connect_device(DEV)
	_bridge.pump()
	assert_eq(_ble.get_connection_state(), TrainerDevice.ConnectionState.CONNECTED, "BLE-станок подключён")


func _cp() -> Array[String]:
	var out: Array[String] = []
	for w in _bridge.writes_to("2AD9"):
		out.append(BleBytes.to_hex(w["bytes"]))
	return out


func _step_ble(dt: float, g: float) -> void:
	_ble.tick(dt)
	_sc.tick(dt, g)
	_bridge.pump()


func _run_ble(sec: float, g: float, dt: float = 0.1) -> void:
	for i in roundi(sec / dt):
		_step_ble(dt, g)


func _first_sim_hex(g: float, k: int) -> String:
	_ble_setup()
	_make(_ble, k)
	_sc.start(g)
	_bridge.pump()
	var cp := _cp()
	var hex: String = cp[1] if cp.size() > 1 else "<нет>"
	_sc.dispose()
	_sc = null
	_ble.dispose()
	_ble = null
	_bridge.dispose()
	_bridge = null
	return hex


# ---------------------------------------------------------------------------
# REQ-FRD-05 крит. 1, 2; REQ-FRD-04 крит. 2 — уклон g · k / 100 в байтах
# ---------------------------------------------------------------------------

func test_req_frd_05_c1_ble_bytes_grade_8_with_steepness_50_0_100() -> void:
	assert_eq(_first_sim_hex(8.0, 50), "11 00 00 90 01 28 14", "g = 8 %, k = 50 % → 4.00 %")
	assert_eq(_first_sim_hex(8.0, 0), "11 00 00 00 00 28 14", "k = 0 % → 0 %")
	assert_eq(_first_sim_hex(8.0, 100), "11 00 00 20 03 28 14", "k = 100 % → 8.00 %")


func test_req_frd_05_c2_ble_descents_scaled_like_climbs() -> void:
	assert_eq(_first_sim_hex(-4.0, 50), "11 00 00 38 FF 28 14", "g = −4 %, k = 50 % → −2.00 %")
	assert_eq(_first_sim_hex(-4.0, 100), "11 00 00 70 FE 28 14", "k = 100 % → −4.00 %")
	assert_eq(_first_sim_hex(-4.0, 25), "11 00 00 9C FF 28 14", "k = 25 % → −1.00 %")
	assert_eq(_first_sim_hex(-0.004, 100), "11 00 00 00 00 28 14", "−0.004 % → 0 (без «−0»)")


func test_req_frd_04_c2_transmitted_grade_rounded_to_hundredths() -> void:
	var cases: Array = [[7.777, 35, 2.72], [3.141, 50, 1.57], [-6.666, 45, -3.0], [9.999, 100, 10.0], [0.123, 5, 0.01]]
	for c in cases:
		var ft := FakeTrainer.new()
		ft.connect_delay_sec = 0.0
		ft.connect_device("x")
		var sc := SimController.new(ft, int(c[1]))
		sc.start(float(c[0]))
		assert_eq(ft.commands.size(), 1, "g=%s k=%s: одна команда" % [c[0], c[1]])
		assert_almost_eq(float(ft.commands[0]["value"]), float(c[2]), 1e-9, "g=%s k=%s → %s" % [c[0], c[1], c[2]])
		sc.dispose()


func test_req_frd_05_c1_steepness_snapped_to_5_and_default_50() -> void:
	var sc := SimController.new(_ft)
	assert_eq(sc.steepness_pct(), 50, "по умолчанию 50 %")
	for pair in [[0, 0], [2, 0], [3, 5], [52, 50], [53, 55], [100, 100], [130, 100], [-20, 0]]:
		sc.set_steepness(int(pair[0]))
		assert_eq(sc.steepness_pct(), int(pair[1]), "k %d → %d" % [pair[0], pair[1]])
	sc.dispose()


# ---------------------------------------------------------------------------
# REQ-FRD-04 крит. 3 — диапазон станка 0x2AD5 и запасной −10…+20 %
# ---------------------------------------------------------------------------

func test_req_frd_04_c3_range_read_after_connect_and_clamps_both_ends() -> void:
	_ble_setup(CHARS, FEATURES_SIM, INCL_NARROW)
	var reads: Array[Dictionary] = []
	for c in _bridge.calls_of("read_characteristic"):
		if c["char"] == "2AD5":
			reads.append(c)
	assert_eq(reads.size(), 1, "2AD5 прочитан после подключения")
	if reads.size() == 1:
		assert_eq(reads[0]["service"], "1826")
		assert_eq(reads[0]["id"], DEV)
	assert_eq(_ble.inclination_range(), Vector2(-5.0, 10.0))
	_make(_ble, 100)
	_sc.start(30.0)
	_bridge.pump()
	_run_ble(1.2, -20.0)
	_run_ble(1.2, 7.25)
	assert_eq(_cp(), ["00", "11 00 00 E8 03 28 14", "11 00 00 0C FE 28 14", "11 00 00 D5 02 28 14"] as Array[String],
		"+30 % → +10.00 %, −20 % → −5.00 %, внутри диапазона — как есть (7.25 %)")


func test_req_frd_04_c3_no_answer_to_2ad5_falls_back_to_minus10_plus20() -> void:
	# 2AD5 заявлен, но станок не отвечает значением (CHARACTERISTIC_NOT_FOUND от моста).
	_ble_setup(CHARS, FEATURES_SIM, "")
	assert_eq(_ble.inclination_range(), Vector2(-10.0, 20.0))
	_make(_ble, 100)
	_sc.start(40.0)
	_bridge.pump()
	_run_ble(1.2, -40.0)
	assert_eq(_cp(), ["00", "11 00 00 D0 07 28 14", "11 00 00 18 FC 28 14"] as Array[String],
		"+40 % → +20.00 %, −40 % → −10.00 %")


func test_req_frd_04_c3_steepness_applied_before_clamp() -> void:
	# 18 % · 50 % = 9 % — в диапазоне −5…+10, не обрезается; 30 % · 50 % = 15 % → 10 %.
	_ble_setup(CHARS, FEATURES_SIM, INCL_NARROW)
	_make(_ble, 50)
	_sc.start(18.0)
	_bridge.pump()
	_run_ble(1.2, 30.0)
	assert_eq(_cp(), ["00", "11 00 00 84 03 28 14", "11 00 00 E8 03 28 14"] as Array[String])


# ---------------------------------------------------------------------------
# REQ-FRD-04 крит. 4 — не чаще раза в 1 с и порог 0.1 %
# ---------------------------------------------------------------------------

func test_req_frd_04_c4_threshold_boundary_0_09_vs_0_10() -> void:
	_make(_ft, 100)
	_sc.start(2.0)
	_run_ft(1.5, 2.09)
	assert_eq(_sims().size(), 1, "Δ = 0.09 % < 0.1 % — не отправляется")
	_run_ft(1.5, 2.10)
	assert_eq(_sims().size(), 2, "Δ = 0.10 % — отправляется")
	assert_almost_eq(float(_sims()[1]["value"]), 2.10, 1e-9)
	_run_ft(1.5, 2.01)
	assert_eq(_sims().size(), 2, "Δ = −0.09 % от последнего отправленного 2.10 — не отправляется")
	_run_ft(1.5, 2.00)
	assert_eq(_sims().size(), 3, "Δ = −0.10 % — отправляется")


func test_req_frd_04_c4_slow_drift_sends_each_time_drift_reaches_threshold() -> void:
	# Уклон растёт на 0.04 %/с: команды — каждый раз, когда отличие от ПОСЛЕДНЕГО
	# отправленного достигает 0.1 %, а не от предыдущего тика.
	_make(_ft, 100)
	_sc.start(0.0)
	var g: float = 0.0
	for sec in 30:
		for i in 20:
			g += 0.04 / 20.0
			_step_ft(DT, g)
	var vals: Array[float] = []
	for c in _sims():
		vals.append(float(c["value"]))
	assert_gte(vals.size(), 11, "за 30 с дрейфа на 1.2 %% — не меньше 11 команд (%s)" % str(vals))
	assert_lte(vals.size(), 14, "и не на каждый тик (%d команд)" % vals.size())
	for i in range(1, vals.size()):
		assert_gte(absf(vals[i] - vals[i - 1]), 0.1 - EPS, "соседние команды отличаются ≥ 0.1 %%: %s" % str(vals.slice(i - 1, i + 1)))


func test_req_frd_04_c4_rapid_changes_never_closer_than_1000_ms() -> void:
	_make(_ft, 100)
	_sc.start(0.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for i in 4000:
		var g: float = rng.randf_range(-15.0, 15.0)
		_step_ft(DT, g)
		if i % 7 == 0:
			_sc.set_steepness([20, 40, 60, 80, 100][i % 5])
	var sims := _sims()
	assert_gt(sims.size(), 150, "уклон скачет — команд много")
	var min_gap: float = INF
	for i in range(1, sims.size()):
		min_gap = minf(min_gap, float(sims[i]["at_sec"]) - float(sims[i - 1]["at_sec"]))
	assert_gte(min_gap, 1.0 - EPS, "минимальный интервал между 0x11: %.3f с" % min_gap)
	assert_lte(sims.size(), 200 + 1, "за 200 с не больше 201 команды (%d)" % sims.size())


func test_req_frd_04_c4_mountains_10_min_free_ride_session_on_fake_trainer() -> void:
	var ft := FakeTrainer.new(9)
	ft.connect_delay_sec = 0.0
	ft.set_rider_power(320)
	ft.connect_device("fake")
	var s := FreeRideSession.new(ft, RouteCatalog.MOUNTAINS, 100, 70.0, 250)
	s.start()
	for i in 6000:
		s.tick(0.1)
	var at: Array[float] = []
	for c in ft.commands:
		if c["type"] == FakeTrainer.CMD_SIM:
			at.append(float(c["at_sec"]))
	assert_gt(at.size(), 5, "SIM-команды идут (%d)" % at.size())
	assert_lte(at.size(), 600, "≤ 600 команд 0x11 за 10 мин (%d)" % at.size())
	var min_gap: float = INF
	for i in range(1, at.size()):
		min_gap = minf(min_gap, at[i] - at[i - 1])
	assert_gte(min_gap, 1.0 - EPS, "интервалы ≥ 1000 мс (мин. %.3f с)" % min_gap)
	assert_gt(s.distance_m(), 3000.0, "проехали по подъёму %.0f м" % s.distance_m())
	s.dispose()


# ---------------------------------------------------------------------------
# REQ-FRD-04 крит. 5 — новый участок, старт, возобновление, переподключение
# ---------------------------------------------------------------------------

func test_req_frd_04_c5_new_section_sent_within_1s_even_right_after_previous_command() -> void:
	_make(_ft, 100)
	_sc.start(3.0)
	_run_ft(4.0, 3.0)
	# Отправка «перед самой границей»: смена на 3.3 % уходит, через 50 мс — граница участка 5 %.
	_step_ft(DT, 3.3)
	assert_eq(_sims().size(), 2, "3.30 % ушёл")
	var last_at: float = float(_sims().back()["at_sec"])
	_step_ft(DT, 5.0)
	var cross_at: float = _ft.get_time_sec()
	assert_lt(cross_at - last_at, 0.5, "граница участка сразу после отправки (%.2f с)" % (cross_at - last_at))
	_run_ft(1.5, 5.0)
	var sent_new: Array[Dictionary] = []
	for c in _sims():
		if absf(float(c["value"]) - 5.0) < EPS:
			sent_new.append(c)
	assert_eq(sent_new.size(), 1, "5.00 % ушёл")
	if sent_new.size() == 1:
		assert_lte(float(sent_new[0]["at_sec"]) - cross_at, 1.0 + EPS,
			"через %.2f с после пересечения границы" % (float(sent_new[0]["at_sec"]) - cross_at))


func test_req_frd_04_c5_start_sends_immediately() -> void:
	for i in 33:
		_ft.tick(0.1)
	_make(_ft, 50)
	var t0: float = _ft.get_time_sec()
	_sc.start(6.0)
	assert_eq(_sims().size(), 1)
	assert_almost_eq(float(_sims()[0]["at_sec"]), t0, EPS, "команда — в момент старта")


func test_req_frd_04_c5_reconnect_resends_same_grade_within_1s_bypassing_threshold() -> void:
	_make(_ft, 50)
	_sc.start(6.0)
	_run_ft(5.0, 6.0)
	assert_eq(_sims().size(), 1, "уклон не менялся — одна команда")
	_ft.inject_dropout(4.0)
	var back_at: float = _ft.get_time_sec() + 4.0
	_run_ft(6.0, 6.0)
	assert_eq(_sims().size(), 2, "после восстановления — повтор текущего уклона без порога")
	if _sims().size() == 2:
		assert_almost_eq(float(_sims()[1]["value"]), 3.0, EPS)
		assert_between(float(_sims()[1]["at_sec"]) - back_at, -EPS, 1.0 + EPS,
			"через %.2f с после CONNECTED" % (float(_sims()[1]["at_sec"]) - back_at))


func test_req_frd_04_c5_resume_resends_within_1s_and_pause_sends_nothing() -> void:
	_make(_ft, 50)
	_sc.start(4.0)
	_run_ft(3.0, 4.0)
	_sc.pause()
	var n: int = _ft.commands.size()
	_run_ft(10.0, 9.0)
	_sc.set_steepness(80)
	_sc.set_resistance_level(70)
	_ft.inject_dropout(2.0)
	_run_ft(4.0, 9.0)
	assert_eq(_ft.commands.size(), n, "на паузе на станок ничего не уходит (уклон, крутизна, обрыв)")
	var t_resume: float = _ft.get_time_sec()
	_sc.resume()
	_run_ft(1.0, 9.0)
	var after: Array[Dictionary] = _ft.commands.slice(n)
	assert_eq(after.size(), 1, "после возобновления — одна команда")
	if after.size() == 1:
		assert_eq(after[0]["type"], FakeTrainer.CMD_SIM)
		assert_almost_eq(float(after[0]["value"]), 7.2, EPS, "9 % · 80 % — текущие уклон и крутизна")
		assert_lte(float(after[0]["at_sec"]) - t_resume, 1.0 + EPS)


func test_req_frd_04_c5_ble_reconnect_writes_0x11_within_1s_and_never_0x05() -> void:
	_ble_setup()
	_make(_ble, 50)
	_sc.start(6.0)
	_bridge.pump()
	_run_ble(3.0, 6.0)
	assert_eq(_cp(), ["00", "11 00 00 2C 01 28 14"] as Array[String])
	_bridge.emit_disconnected(DEV)
	assert_eq(_ble.get_connection_state(), TrainerDevice.ConnectionState.RECONNECTING)
	_bridge.pump()  # мост сразу переподключается: discover → Request Control → CONNECTED
	assert_eq(_ble.get_connection_state(), TrainerDevice.ConnectionState.CONNECTED)
	var t_back: float = _ble.get_time_sec()
	var before: int = _cp().size()
	var sent_at: float = -1.0
	for i in 20:
		_step_ble(0.1, 6.0)
		if sent_at < 0.0 and _cp().slice(before).has("11 00 00 2C 01 28 14"):
			sent_at = _ble.get_time_sec()
	assert_true(_cp().slice(before).has("11 00 00 2C 01 28 14"), "после переподключения — тот же уклон 3.00 %%: %s" % str(_cp()))
	assert_lte(sent_at - t_back, 1.0 + EPS, "через %.2f с после CONNECTED" % (sent_at - t_back))
	for hex in _cp():
		assert_false(hex.begins_with("05"), "0x05 не уходит: %s" % hex)


func test_req_frd_04_c5_ble_control_permission_lost_restores_sim_not_erg() -> void:
	_ble_setup()
	_make(_ble, 100)
	_sc.start(4.0)
	_bridge.pump()
	_run_ble(2.0, 4.0)
	_bridge.emit_notification(DEV, "2ADA", PackedByteArray([0xFF]))
	_bridge.pump()
	_run_ble(2.0, 4.0)
	var cp := _cp()
	assert_eq(cp.slice(cp.size() - 2), ["00", "11 00 00 90 01 28 14"] as Array[String],
		"после потери управления — Request Control и снова SIM 4.00 %%: %s" % str(cp))
	for hex in cp:
		assert_false(hex.begins_with("05"), "0x05 не уходит: %s" % hex)


# ---------------------------------------------------------------------------
# REQ-FRD-04 крит. 6 — нет SIM → фиксированное сопротивление
# ---------------------------------------------------------------------------

func test_req_frd_04_c6_ble_feature_bit_missing_no_0x11_ever_and_fixed_level_sent() -> void:
	_ble_setup(CHARS, FEATURES_NO_SIM)
	_make(_ble, 50, SimController.Mode.SIM, 40)
	_sc.start(8.0)
	_bridge.pump()
	_run_ble(30.0, 12.0, 0.25)
	assert_false(_sc.set_mode(SimController.Mode.SIM), "вернуться в SIM нельзя")
	_run_ble(5.0, 3.0, 0.25)
	assert_eq(_cp(), ["00", "04 66"] as Array[String], "только Request Control и уровень 40 %% (10.2 → 66): %s" % str(_cp()))
	assert_eq(_sc.mode(), SimController.Mode.FIXED)
	assert_eq(_sc.get_state(), SimController.State.RUNNING, "сессия не прерывается")
	assert_gte(_unavailable, 1, "сигнал «нет SIM» для HUD")


func test_req_frd_04_c6_ble_any_result_not_success_falls_back_within_1s() -> void:
	for result in [FtmsCodec.RESULT_NOT_SUPPORTED, FtmsCodec.RESULT_INVALID_PARAMETER,
			FtmsCodec.RESULT_OPERATION_FAILED, FtmsCodec.RESULT_CONTROL_NOT_PERMITTED]:
		_unavailable = 0
		_ble_setup(["2AD2", "2AD9", "2ADA", "2AD6"] as Array[String], "")
		_make(_ble, 50, SimController.Mode.SIM, 50)
		_bridge.fail_next_control_point(result)
		_sc.start(8.0)
		_bridge.pump()
		_run_ble(1.0, 8.0)
		var cp := _cp()
		assert_eq(cp.slice(0, 3), ["00", "11 00 00 90 01 28 14", "04 80"] as Array[String],
			"код 0x%02X: за отказом 0x11 — уровень 50 %% (`04 80`): %s" % [result, str(cp)])
		_run_ble(20.0, 11.0, 0.25)
		assert_eq(_cp().size(), 3, "код 0x%02X: больше 0x11 нет" % result)
		assert_eq(_sc.mode(), SimController.Mode.FIXED, "код 0x%02X: режим FIXED" % result)
		assert_eq(_unavailable, 1, "код 0x%02X: сигнал «нет SIM» один раз" % result)
		assert_eq(_sc.get_state(), SimController.State.RUNNING)
		_sc.dispose()
		_sc = null
		_ble.dispose()
		_ble = null
		_bridge.dispose()
		_bridge = null


# ---------------------------------------------------------------------------
# REQ-FRD-05 крит. 3 — смена крутизны во время езды
# ---------------------------------------------------------------------------

func test_req_frd_05_c3_steepness_change_below_threshold_still_sent_within_1s() -> void:
	_make(_ft, 50)
	_sc.start(1.0)
	_run_ft(5.0, 1.0)
	var t: float = _ft.get_time_sec()
	_sc.set_steepness(55)  # 0.50 → 0.55 %: меньше порога 0.1 %, позиция не меняется
	_run_ft(1.5, 1.0)
	var sims := _sims()
	assert_eq(sims.size(), 2, "новая крутизна ушла, хотя Δ < 0.1 %")
	if sims.size() == 2:
		assert_almost_eq(float(sims[1]["value"]), 0.55, EPS)
		assert_lte(float(sims[1]["at_sec"]) - t, 1.0 + EPS)


func test_req_frd_05_c3_burst_of_changes_rate_limited_and_last_value_sent() -> void:
	_make(_ft, 50)
	_sc.start(6.0)
	_run_ft(0.3, 6.0)
	_sc.set_steepness(60)
	_run_ft(0.1, 6.0)
	_sc.set_steepness(70)
	_run_ft(0.1, 6.0)
	_sc.set_steepness(90)
	var t_last: float = _ft.get_time_sec()
	_run_ft(3.0, 6.0)
	var sims := _sims()
	for i in range(1, sims.size()):
		assert_gte(float(sims[i]["at_sec"]) - float(sims[i - 1]["at_sec"]), 1.0 - EPS, "не чаще раза в 1 с")
	assert_almost_eq(float(sims.back()["value"]), 5.4, EPS, "в итоге ушёл уклон с последней крутизной 90 %")
	assert_lte(float(sims.back()["at_sec"]) - t_last, 1.0 + EPS)


# ---------------------------------------------------------------------------
# REQ-FRD-05 крит. 4 — SIM ↔ фиксированное сопротивление одним действием
# ---------------------------------------------------------------------------

func test_req_frd_05_c4_ble_toggle_to_fixed_level_by_wrk04_then_no_0x11_then_back() -> void:
	_ble_setup()
	_make(_ble, 50, SimController.Mode.SIM, 40)
	_sc.start(6.0)
	_bridge.pump()
	_run_ble(2.0, 6.0)
	var t0: float = _ble.get_time_sec()
	assert_true(_sc.toggle_mode(), "одно действие → FIXED")
	_bridge.pump()
	assert_eq(_cp().back(), "04 66", "40 %% → 10.2 → `04 66` сразу (%.1f с)" % (_ble.get_time_sec() - t0))
	var n_fixed: int = _cp().size()
	for i in 100:
		_step_ble(0.2, 6.0 + float(i % 10))
	assert_eq(_cp().size(), n_fixed, "в FIXED 0x11 нет при любом уклоне")
	_sc.set_resistance_level(100)
	_bridge.pump()
	assert_eq(_cp().back(), "04 FF", "100 % → 25.5 → `04 FF`")
	_sc.set_resistance_level(0)
	_bridge.pump()
	assert_eq(_cp().back(), "04 00", "0 % → `04 00`")
	_run_ble(1.0, 9.0)
	assert_true(_sc.toggle_mode(), "обратно в SIM")
	_run_ble(1.0, 9.0)
	assert_eq(_cp().back(), "11 00 00 C2 01 28 14", "возврат в SIM — текущий уклон 9 %% · 50 %% = 4.50 %%: %s" % str(_cp()))
	for hex in _cp():
		assert_false(hex.begins_with("05"), "0x05 не уходит: %s" % hex)


func test_req_frd_05_c4_fixed_level_is_same_as_workout_session_resistance() -> void:
	# WRK-04.2: тот же уровень и то же отображение процентов, что у тренировки по плану.
	for level in [5, 35, 50, 85]:
		var ft_w := FakeTrainer.new()
		ft_w.connect_delay_sec = 0.0
		ft_w.connect_device("w")
		var ft_f := FakeTrainer.new()
		ft_f.connect_delay_sec = 0.0
		ft_f.connect_device("f")
		var sc := SimController.new(ft_f, 50, SimController.Mode.FIXED, level)
		sc.start(3.0)
		var res: Array[Dictionary] = []
		for c in ft_f.commands:
			if c["type"] == FakeTrainer.CMD_RESISTANCE:
				res.append(c)
		assert_eq(res.size(), 1, "уровень %d %%: одна команда сопротивления" % level)
		if res.size() == 1:
			assert_eq(int(res[0]["value"]), WorkoutSession.snap_resistance(level), "уровень %d %% как у WorkoutSession" % level)
		sc.dispose()


func test_req_frd_05_c4_fixed_switch_and_return_within_1s_on_fake_trainer() -> void:
	_make(_ft, 100, SimController.Mode.SIM, 45)
	_sc.start(2.0)
	_run_ft(0.4, 2.0)
	var t_fixed: float = _ft.get_time_sec()
	_sc.toggle_mode()
	_run_ft(1.0, 2.0)
	var res := _of(FakeTrainer.CMD_RESISTANCE)
	assert_eq(res.size(), 1)
	if res.size() == 1:
		assert_eq(int(res[0]["value"]), 45)
		assert_lte(float(res[0]["at_sec"]) - t_fixed, 1.0 + EPS)
	_run_ft(0.3, 5.0)
	var t_sim: float = _ft.get_time_sec()
	_sc.toggle_mode()
	_run_ft(1.2, 5.0)
	var sims := _sims()
	assert_eq(sims.size(), 2, "возврат в SIM")
	if sims.size() == 2:
		assert_almost_eq(float(sims[1]["value"]), 5.0, EPS)
		assert_lte(float(sims[1]["at_sec"]) - t_sim, 1.0 + EPS, "через %.2f с" % (float(sims[1]["at_sec"]) - t_sim))
	assert_eq(_of(FakeTrainer.CMD_TARGET_POWER).size(), 0)


# ---------------------------------------------------------------------------
# REQ-FRD-01 крит. 2 — ни одной 0x05, первая команда после Request Control — 0x11 или 0x04
# ---------------------------------------------------------------------------

func _drive_ble_free_ride(s: FreeRideSession, seconds: int, power: int, trainer_speed_kmh: float) -> void:
	for sec in seconds:
		_bridge.emit_notification(DEV, "2AD2", FtmsCodec.encode_indoor_bike_data(trainer_speed_kmh, 90.0, power))
		for i in 4:
			s.tick(0.25)
			_bridge.pump()


func test_req_frd_01_c2_ble_trainer_left_in_erg_by_workout_never_gets_0x05_in_free_ride() -> void:
	_ble_setup()
	# Станок живёт дольше сессии: тренировка по плану оставила ERG с целью 200 Вт.
	_ble.set_erg_enabled(true)
	_ble.set_target_power(200)
	_bridge.pump()
	assert_true(_cp().has("05 C8 00"), "до свободной езды станок был в ERG 200 Вт")
	_bridge.clear_calls()
	var s := FreeRideSession.new(_ble, RouteCatalog.HILLS, 50, 75.0, 250)
	s.start()
	_bridge.pump()
	_drive_ble_free_ride(s, 60, 250, 99.0)
	s.pause()
	_drive_ble_free_ride(s, 5, 0, 0.0)
	s.resume()
	_drive_ble_free_ride(s, 10, 250, 99.0)
	s.toggle_mode()
	_drive_ble_free_ride(s, 5, 250, 99.0)
	s.toggle_mode()
	s.set_steepness(80)
	_bridge.emit_disconnected(DEV)
	_bridge.pump()
	_drive_ble_free_ride(s, 10, 250, 99.0)
	s.stop()
	_drive_ble_free_ride(s, 3, 250, 99.0)
	var cp := _cp()
	assert_gt(cp.size(), 3, "команды шли: %s" % str(cp))
	assert_true(cp[0].begins_with("11"), "первая команда свободной езды — SIM 0x11: %s" % str(cp.slice(0, 3)))
	for hex in cp:
		assert_false(hex.begins_with("05"), "Set Target Power 0x05 не уходит за всю сессию: %s" % hex)
	assert_false(_ble.is_erg_enabled(), "ERG станка выключен")
	s.dispose()


func test_req_frd_01_c2_ble_preselected_fixed_first_command_0x04_after_request_control() -> void:
	_bridge = StubBleBridge.new()
	_ble = BleTrainer.new(_bridge)
	_bridge.set_device_services(DEV, {"1826": CHARS})
	_bridge.set_read_value("2ACC", BleBytes.from_hex(FEATURES_SIM))
	_bridge.set_read_value("2AD6", BleBytes.from_hex(RES_RANGE))
	var s := FreeRideSession.new(_ble, RouteCatalog.FLAT, 50, 75.0, 250, SimController.Mode.FIXED, 35)
	s.start()  # станок ещё не подключён: команда уйдёт после CONNECTED
	_ble.connect_device(DEV)
	_bridge.pump()
	_drive_ble_free_ride(s, 5, 200, 30.0)
	var cp := _cp()
	assert_gte(cp.size(), 2)
	assert_eq(cp[0], "00", "сначала Request Control")
	assert_eq(cp[1], "04 59", "затем уровень 35 %% (8.925 → 8.9 → `04 59`): %s" % str(cp))
	for hex in cp:
		assert_false(hex.begins_with("05"))
		assert_false(hex.begins_with("11"), "в фиксированном режиме 0x11 нет")
	s.dispose()


# ---------------------------------------------------------------------------
# SensorHub делегирует SIM станку (T-068, через хаб SIM доходит до BleTrainer)
# ---------------------------------------------------------------------------

func test_req_frd_04_c3_c6_sensor_hub_over_ble_delegates_sim_support_and_range() -> void:
	_ble_setup(CHARS, FEATURES_SIM, INCL_NARROW)
	_hub = SensorHub.new(_ble)
	assert_eq(_hub.simulation_support(), TrainerDevice.SimulationSupport.SUPPORTED)
	assert_eq(_hub.inclination_range(), Vector2(-5.0, 10.0), "диапазон станка через хаб")
	_make(_hub, 100)
	_sc.start(30.0)
	_bridge.pump()
	assert_eq(_cp(), ["00", "11 00 00 E8 03 28 14"] as Array[String], "SIM через хаб → 0x11 на BLE, обрезан до +10 %")
	for i in 12:
		_hub.tick(0.1)
		_sc.tick(0.1, 2.0)
		_bridge.pump()
	assert_eq(_cp().back(), "11 00 00 C8 00 28 14", "следующая команда через хаб — 2.00 %")


func test_req_frd_04_c6_sensor_hub_over_ble_without_sim_bit_falls_back() -> void:
	_ble_setup(CHARS, FEATURES_NO_SIM)
	_hub = SensorHub.new(_ble)
	assert_eq(_hub.simulation_support(), TrainerDevice.SimulationSupport.UNSUPPORTED)
	_make(_hub, 50, SimController.Mode.SIM, 50)
	_sc.start(5.0)
	_bridge.pump()
	assert_eq(_cp(), ["00", "04 80"] as Array[String])
	assert_eq(_unavailable, 1)
