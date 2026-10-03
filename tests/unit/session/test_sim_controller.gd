extends GutTest
## SimController: уклон на станок с крутизной, ограничение диапазоном, частота и порог,
## принудительная отправка, SIM ↔ фиксированное сопротивление, переход без SIM
## (REQ-FRD-04 крит. 2–6, REQ-FRD-05 крит. 1–4, REQ-FRD-01 крит. 2) — на FakeTrainer и StubBleBridge.

const DEV: String = "tacx-neo"
const FTMS_CHARS: Array[String] = ["2AD2", "2AD9", "2ADA", "2AD6", "2ACC", "2AD5"]
const DT: float = 0.1

var _ft: FakeTrainer
var _sc: SimController
var _events: Array[Dictionary] = []
var _unavailable: int = 0
var _errors: Array[int] = []
var _bridge: StubBleBridge = null
var _ble: BleTrainer = null
var _hub: SensorHub = null


func before_each() -> void:
	_events = []
	_unavailable = 0
	_errors = []
	_ft = FakeTrainer.new()
	_ft.connect_delay_sec = 0.0
	_ft.error.connect(_on_error)
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


func _on_error(code: int, _message: String) -> void:
	_errors.append(code)


func _on_event(type: String, value: Variant) -> void:
	_events.append({"type": type, "value": value})


func _on_unavailable() -> void:
	_unavailable += 1


func _make(device: TrainerDevice, steepness: int = 50, mode: SimController.Mode = SimController.Mode.SIM,
		level: int = 50) -> SimController:
	_sc = SimController.new(device, steepness, mode, level)
	_sc.ride_event.connect(_on_event)
	_sc.simulation_unavailable.connect(_on_unavailable)
	return _sc


## Шаг сессии: сначала станок, затем контроллер (порядок, оговорённый контрактом).
func _step(dt: float, grade: float) -> void:
	_ft.tick(dt)
	_sc.tick(dt, grade)


func _run(sec: float, grade: float, dt: float = DT) -> void:
	for i in roundi(sec / dt):
		_step(dt, grade)


func _cmds(type: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for c in _ft.commands:
		if c["type"] == type:
			out.append(c)
	return out


func _sim_values() -> Array[float]:
	var out: Array[float] = []
	for c in _cmds(FakeTrainer.CMD_SIM):
		out.append(float(c["value"]))
	return out


# ---------------------------------------------------------------------------
# StubBleBridge
# ---------------------------------------------------------------------------

func _setup_ble(chars: Array[String] = FTMS_CHARS, sim_bit: bool = true) -> void:
	_bridge = StubBleBridge.new()
	_ble = BleTrainer.new(_bridge)
	_ble.error.connect(_on_error)
	_bridge.set_device_services(DEV, {"1826": chars})
	_bridge.set_read_value("2ACC", BleBytes.from_hex("83 40 00 00 0C 20 00 00" if sim_bit else "83 40 00 00 0C 00 00 00"))
	_bridge.set_read_value("2AD5", BleBytes.from_hex("9C FF C8 00 05 00"))
	_bridge.set_read_value("2AD6", BleBytes.from_hex("00 00 E8 03 01 00"))
	_ble.connect_device(DEV)
	_bridge.pump()
	assert_eq(_ble.get_connection_state(), TrainerDevice.ConnectionState.CONNECTED, "станок подключён")


func _cp_writes() -> Array[String]:
	var out: Array[String] = []
	for w in _bridge.writes_to("2AD9"):
		out.append(BleBytes.to_hex(w["bytes"]))
	return out


func _assert_no_target_power_on_cp() -> void:
	for hex in _cp_writes():
		assert_false(hex.begins_with("05"), "Set Target Power 0x05 не уходит: %s" % hex)


# ---------------------------------------------------------------------------
# REQ-FRD-04 крит. 2, REQ-FRD-05 крит. 1, 2 — передаваемый уклон
# ---------------------------------------------------------------------------

func test_req_frd_05_c1_grade_8_steepness_50_sends_4_00() -> void:
	_make(_ft, 50)
	_sc.start(8.0)
	_assert_sims([4.0], "g = 8 %, k = 50 % → 4.00 %")


func test_req_frd_05_c1_steepness_0_and_100() -> void:
	_make(_ft, 0)
	_sc.start(8.0)
	_assert_sims([0.0], "k = 0 % → 0 %")
	_run(1.0, 8.0)
	_sc.set_steepness(100)
	_assert_sims([0.0, 8.0], "k = 100 % → 8.00 %")


func test_req_frd_05_c2_steepness_applies_to_descents() -> void:
	_make(_ft, 50)
	_sc.start(-4.0)
	_assert_sims([-2.0], "g = −4 %, k = 50 % → −2.00 %")


func test_req_frd_04_c2_rounding_to_hundredths() -> void:
	var r := Vector2(-10.0, 20.0)
	assert_almost_eq(SimController.transmitted_grade(3.333, 50, r), 1.67, 1e-9)
	assert_almost_eq(SimController.transmitted_grade(-3.337, 50, r), -1.67, 1e-9)
	assert_almost_eq(SimController.transmitted_grade(12.345, 100, r), 12.35, 1e-9)
	assert_almost_eq(SimController.transmitted_grade(5.0, 35, r), 1.75, 1e-9)
	# Малый спуск, округлённый к нулю, — это 0, а не −0.
	assert_eq(str(SimController.transmitted_grade(-0.004, 50, r)), "0.0")
	_make(_ft, 50)
	_sc.start(3.333)
	assert_almost_eq(_sim_values()[0], 1.67, 1e-9, "на станок уходит округлённый уклон")


func test_req_frd_05_c1_steepness_snaps_to_step_5_default_50() -> void:
	var sc := SimController.new(_ft)
	assert_eq(sc.steepness_pct(), 50, "крутизна по умолчанию 50 %")
	assert_eq(sc.mode(), SimController.Mode.SIM, "режим по умолчанию SIM")
	sc.set_steepness(42)
	assert_eq(sc.steepness_pct(), 40)
	sc.set_steepness(150)
	assert_eq(sc.steepness_pct(), 100)
	sc.set_steepness(-5)
	assert_eq(sc.steepness_pct(), 0)
	sc.dispose()


# ---------------------------------------------------------------------------
# REQ-FRD-04 крит. 3 — ограничение диапазоном станка
# ---------------------------------------------------------------------------

func test_req_frd_04_c3_clamped_by_default_range() -> void:
	_make(_ft, 100)
	_sc.start(25.0)
	_assert_sims([20.0], "запасной диапазон −10…+20 %")
	_run(1.0, -14.0)
	_assert_sims([20.0, -10.0])


func test_req_frd_04_c3_clamped_by_trainer_range() -> void:
	_ft.set_inclination_range(-5.0, 15.0)
	_make(_ft, 100)
	_sc.start(18.0)
	_run(1.0, -12.0)
	_run(1.0, 9.0)
	_assert_sims([15.0, -5.0, 9.0], "диапазон станка −5…+15 %")
	assert_almost_eq(_sc.target_grade_pct(), 9.0, 1e-9)


# ---------------------------------------------------------------------------
# REQ-FRD-04 крит. 4 — частота и порог
# ---------------------------------------------------------------------------

func test_req_frd_04_c4_threshold_0_1_percent() -> void:
	_make(_ft, 100)
	_sc.start(2.0)
	_run(2.0, 2.05)
	_assert_sims([2.0], "изменение 0.05 % не отправляется")
	_run(2.0, 2.09)
	_assert_sims([2.0], "изменение 0.09 % не отправляется")
	_run(2.0, 2.1)
	_assert_sims([2.0, 2.1], "изменение 0.1 % отправляется")
	# Медленный дрейф: порог считается от последнего отправленного, а не от прошлого тика.
	_run(1.0, 2.15)
	_run(1.0, 2.19)
	assert_eq(_sim_values().size(), 2)
	_run(1.0, 2.2)
	_assert_sims([2.0, 2.1, 2.2])


func test_req_frd_04_c4_not_more_than_once_per_second() -> void:
	_make(_ft, 100)
	_sc.start(0.0)
	# Каждые 0.1 с уклон растёт на 0.2 %: команда — ровно раз в секунду.
	var g: float = 0.0
	for i in 50:
		g += 0.2
		_step(DT, g)
	var sims := _cmds(FakeTrainer.CMD_SIM)
	assert_eq(sims.size(), 6, "0, 1, 2, 3, 4, 5 с: %s" % str(sims))
	for i in range(1, sims.size()):
		var gap_ms: int = roundi((float(sims[i]["at_sec"]) - float(sims[i - 1]["at_sec"])) * 1000.0)
		assert_true(gap_ms >= 1000, "интервал %d мс ≥ 1000" % gap_ms)


func test_req_frd_04_c4_c5_mountains_10_min() -> void:
	var profile: RouteProfile = RouteCatalog.get_route(RouteCatalog.MOUNTAINS).profile
	_make(_ft, 100)
	var speed_ms: float = 10.0
	var s: float = 0.0
	_sc.start(profile.grade_at(s))
	var violation_since: float = -1.0
	var worst_delay: float = 0.0
	for i in roundi(600.0 / DT):
		s += speed_ms * DT
		_step(DT, profile.grade_at(s))
		# Задержка (крит. 5): расхождение ≥ 0.1 % с отправленным живёт не дольше 1 с.
		var now: float = _ft.get_time_sec()
		if absf(_sc.target_grade_pct() - _sc.last_sent_grade_pct()) >= SimController.GRADE_THRESHOLD_PCT - 1e-6:
			if violation_since < 0.0:
				violation_since = now
			worst_delay = maxf(worst_delay, now - violation_since)
		else:
			violation_since = -1.0
	var sims := _cmds(FakeTrainer.CMD_SIM)
	assert_true(sims.size() <= 600, "команд 0x11 за 10 мин: %d ≤ 600" % sims.size())
	assert_true(sims.size() >= 30, "уклон на горах реально передаётся: %d" % sims.size())
	var min_gap_ms: int = 1_000_000
	for i in range(1, sims.size()):
		min_gap_ms = mini(min_gap_ms, roundi((float(sims[i]["at_sec"]) - float(sims[i - 1]["at_sec"])) * 1000.0))
	assert_true(min_gap_ms >= 1000, "минимальный интервал %d мс ≥ 1000" % min_gap_ms)
	assert_true(worst_delay <= 1.0 + 1e-6, "задержка отправки нового уклона %.2f с ≤ 1 с" % worst_delay)
	assert_eq(_cmds(FakeTrainer.CMD_TARGET_POWER).size(), 0)


# ---------------------------------------------------------------------------
# REQ-FRD-04 крит. 5 — задержка и принудительная отправка
# ---------------------------------------------------------------------------

func test_req_frd_04_c5_new_grade_sent_within_1s_of_boundary() -> void:
	_make(_ft, 100)
	_sc.start(2.0)
	_run(5.3, 2.0)
	_step(DT, 6.0)  # граница участка пересечена на 5.4 с
	var sims := _cmds(FakeTrainer.CMD_SIM)
	assert_eq(sims.size(), 2)
	assert_almost_eq(float(sims[1]["at_sec"]), 5.4, 1e-6, "сразу — прошло больше 1 с с прошлой")
	_run(0.3, 6.0)
	_step(DT, 8.0)  # следующая граница на 5.8 с — ждём 1 с с 5.4
	_run(1.0, 8.0)
	sims = _cmds(FakeTrainer.CMD_SIM)
	assert_eq(sims.size(), 3)
	assert_almost_eq(float(sims[2]["at_sec"]), 6.4, 1e-6, "через 1 с после прошлой, 0.6 с после границы")
	assert_almost_eq(float(sims[2]["value"]), 8.0, 1e-9)


func test_req_frd_04_c5_start_sends_immediately_and_is_first_command() -> void:
	_make(_ft, 50)
	_sc.start(0.0)
	assert_eq(_ft.commands.size(), 1, "на старте — ровно одна команда")
	assert_eq(_ft.commands[0]["type"], FakeTrainer.CMD_SIM)
	assert_almost_eq(float(_ft.commands[0]["at_sec"]), 0.0, 1e-9)
	assert_true(_ft.simulation_active)


func test_req_frd_04_c5_reconnect_forces_current_grade() -> void:
	_make(_ft, 50)
	_sc.start(4.0)
	_run(3.0, 4.0)
	_ft.inject_dropout(2.0)
	_run(1.0, 4.0)
	assert_eq(_sim_values().size(), 1, "во время обрыва ничего не шлётся")
	_run(1.5, 4.0)
	var sims := _cmds(FakeTrainer.CMD_SIM)
	assert_eq(sims.size(), 2, "после восстановления — повтор того же уклона без порога")
	assert_almost_eq(float(sims[1]["value"]), 2.0, 1e-9)
	assert_true(float(sims[1]["at_sec"]) >= 5.0 - 1e-6 and float(sims[1]["at_sec"]) <= 6.0 + 1e-6,
		"не позже 1 с после CONNECTED (5 с): %.2f" % float(sims[1]["at_sec"]))
	assert_eq(_errors, [] as Array[int], "без NOT_CONNECTED")


func test_req_frd_04_c5_pause_sends_nothing_resume_forces() -> void:
	_make(_ft, 50)
	_sc.start(6.0)
	_run(2.0, 6.0)
	_sc.pause()
	_run(1.0, 10.0)
	_sc.set_steepness(80)
	_sc.set_mode(SimController.Mode.FIXED)
	_sc.set_mode(SimController.Mode.SIM)
	_sc.set_resistance_level(70)
	_run(3.0, 6.0)
	assert_eq(_ft.commands.size(), 1, "на паузе на станок ничего: %s" % str(_ft.commands))
	_sc.resume()
	var sims := _cmds(FakeTrainer.CMD_SIM)
	assert_eq(sims.size(), 2, "возобновление — сразу текущий уклон")
	assert_almost_eq(float(sims[1]["value"]), 4.8, 1e-9, "6 % × 80 %")
	assert_almost_eq(float(sims[1]["at_sec"]), 6.0, 1e-6)


func test_req_frd_04_c5_resume_same_grade_bypasses_threshold() -> void:
	_make(_ft, 50)
	_sc.start(6.0)
	_run(2.0, 6.0)
	_sc.pause()
	_run(2.0, 6.0)
	_sc.resume()
	_assert_sims([3.0, 3.0], "тот же уклон уходит повторно")


func test_req_frd_04_c5_start_while_connecting_sends_after_connected() -> void:
	var ft := FakeTrainer.new()
	ft.connect_delay_sec = 0.5
	ft.error.connect(_on_error)
	ft.connect_device("fake")
	_ft = ft
	_make(_ft, 50)
	_sc.start(8.0)
	assert_eq(_ft.commands.size(), 0, "без связи команда не уходит")
	_run(0.5, 8.0)
	var sims := _cmds(FakeTrainer.CMD_SIM)
	assert_eq(sims.size(), 1)
	assert_almost_eq(float(sims[0]["at_sec"]), 0.5, 1e-6, "сразу после CONNECTED")
	assert_eq(_errors, [] as Array[int])


# ---------------------------------------------------------------------------
# REQ-FRD-05 крит. 3 — смена крутизны
# ---------------------------------------------------------------------------

func test_req_frd_05_c3_steepness_change_sends_within_1s_rate_limited() -> void:
	_make(_ft, 50)
	_sc.start(8.0)
	_run(3.0, 8.0)
	_sc.set_steepness(60)
	var sims := _cmds(FakeTrainer.CMD_SIM)
	assert_eq(sims.size(), 2, "позиция не менялась, но новый уклон ушёл")
	assert_almost_eq(float(sims[1]["value"]), 4.8, 1e-9)
	assert_almost_eq(float(sims[1]["at_sec"]), 3.0, 1e-6)
	_run(0.3, 8.0)
	_sc.set_steepness(70)
	assert_eq(_cmds(FakeTrainer.CMD_SIM).size(), 2, "не чаще раза в 1 с")
	_run(0.7, 8.0)
	sims = _cmds(FakeTrainer.CMD_SIM)
	assert_eq(sims.size(), 3)
	assert_almost_eq(float(sims[2]["value"]), 5.6, 1e-9)
	assert_almost_eq(float(sims[2]["at_sec"]), 4.0, 1e-6, "через 1 с после прошлой, 0.7 с после смены")


func test_req_frd_05_c3_steepness_change_on_flat_still_sends() -> void:
	_make(_ft, 50)
	_sc.start(0.04)
	_run(2.0, 0.04)
	_sc.set_steepness(100)
	_assert_sims([0.02, 0.04], "без порога 0.1 %")


# ---------------------------------------------------------------------------
# REQ-FRD-05 крит. 4 — SIM ↔ фиксированное сопротивление
# ---------------------------------------------------------------------------

func test_req_frd_05_c4_toggle_to_fixed_and_back() -> void:
	_make(_ft, 50, SimController.Mode.SIM, 40)
	_sc.start(6.0)
	_run(2.5, 6.0)
	assert_true(_sc.toggle_mode())
	assert_eq(_sc.mode(), SimController.Mode.FIXED)
	var res := _cmds(FakeTrainer.CMD_RESISTANCE)
	assert_eq(res.size(), 1, "уровень уходит сразу")
	assert_eq(int(res[0]["value"]), 40)
	assert_almost_eq(float(res[0]["at_sec"]), 2.5, 1e-6)
	assert_false(_ft.simulation_active, "станок на фиксированном сопротивлении")
	assert_eq(_ft.resistance_percent, 40)
	var g: float = 6.0
	for i in 50:
		g += 0.3
		_step(DT, g)
	assert_eq(_sim_values().size(), 1, "в фиксированном режиме команд 0x11 нет")
	_sc.set_resistance_level(55)
	res = _cmds(FakeTrainer.CMD_RESISTANCE)
	assert_eq(res.size(), 2, "изменение уровня — как WRK-04.2")
	assert_eq(int(res[1]["value"]), 55)
	_sc.set_steepness(70)
	assert_eq(_sim_values().size(), 1, "крутизна в фиксированном режиме только запоминается")
	assert_true(_sc.toggle_mode())
	var sims := _cmds(FakeTrainer.CMD_SIM)
	assert_eq(sims.size(), 2, "возврат в SIM — сразу текущий уклон")
	assert_almost_eq(float(sims[1]["value"]), SimController.transmitted_grade(g, 70, Vector2(-10, 20)), 1e-9)
	assert_almost_eq(float(sims[1]["at_sec"]), 7.5, 1e-6)
	assert_true(_ft.simulation_active)
	assert_eq(_cmds(FakeTrainer.CMD_TARGET_POWER).size(), 0)


func test_req_frd_05_c4_resistance_in_sim_only_stored() -> void:
	_make(_ft, 50)
	_sc.start(4.0)
	_sc.set_resistance_level(73)
	assert_eq(_sc.resistance_level(), 75, "шаг 5 %")
	assert_eq(_cmds(FakeTrainer.CMD_RESISTANCE).size(), 0)
	_run(1.0, 4.0)
	_sc.set_mode(SimController.Mode.FIXED)
	assert_eq(int(_cmds(FakeTrainer.CMD_RESISTANCE)[0]["value"]), 75)


func test_req_frd_05_c4_back_to_sim_rate_limited_from_last_sim() -> void:
	_make(_ft, 50)
	_sc.start(4.0)
	_run(0.2, 4.0)
	_sc.set_mode(SimController.Mode.FIXED)
	_run(0.2, 4.0)
	_sc.set_mode(SimController.Mode.SIM)
	assert_eq(_sim_values().size(), 1, "0x11 не чаще раза в 1 с и после переключений")
	_run(0.6, 4.0)
	var sims := _cmds(FakeTrainer.CMD_SIM)
	assert_eq(sims.size(), 2)
	assert_almost_eq(float(sims[1]["at_sec"]), 1.0, 1e-6, "не позже 1 с после возврата")


# ---------------------------------------------------------------------------
# REQ-FRD-01 крит. 2 — нет 0x05, первая команда 0x11 или 0x04
# ---------------------------------------------------------------------------

func test_req_frd_01_c2_preset_fixed_first_command_is_resistance() -> void:
	_make(_ft, 50, SimController.Mode.FIXED, 30)
	_sc.start(5.0)
	_run(10.0, 5.0)
	assert_true(_ft.commands.size() >= 1)
	assert_eq(_ft.commands[0]["type"], FakeTrainer.CMD_RESISTANCE, "первая — уровень сопротивления")
	assert_eq(int(_ft.commands[0]["value"]), 30)
	assert_false(_ft.is_erg_enabled(), "ERG станка выключен — уровень действует")
	assert_eq(_cmds(FakeTrainer.CMD_SIM).size(), 0)
	assert_eq(_cmds(FakeTrainer.CMD_TARGET_POWER).size(), 0)
	for c in _cmds(FakeTrainer.CMD_ERG):
		assert_false(bool(c["value"]), "ERG не включается")


func test_req_frd_01_c2_ble_sim_first_command_is_0x11_no_0x05() -> void:
	_setup_ble()
	_make(_ble, 50)
	_sc.start(8.0)
	_bridge.pump()
	assert_eq(_cp_writes(), ["00", "11 00 00 90 01 28 14"] as Array[String],
		"после Request Control — SIM 4.00 % (`… 90 01 …`)")
	for i in 30:
		_ble.tick(DT)
		_sc.tick(DT, 8.0 + i * 0.1)
		_bridge.pump()
	_sc.set_mode(SimController.Mode.FIXED)
	_bridge.pump()
	_sc.set_mode(SimController.Mode.SIM)
	_bridge.pump()
	_assert_no_target_power_on_cp()
	assert_eq(_errors, [] as Array[int])


func test_req_frd_05_c2_ble_descent_bytes() -> void:
	_setup_ble()
	_make(_ble, 50)
	_sc.start(-4.0)
	_bridge.pump()
	assert_eq(_cp_writes(), ["00", "11 00 00 38 FF 28 14"] as Array[String], "−2.00 %")


func test_req_frd_01_c2_ble_preset_fixed_first_command_is_0x04() -> void:
	_setup_ble()
	_make(_ble, 50, SimController.Mode.FIXED, 50)
	_sc.start(8.0)
	_bridge.pump()
	assert_eq(_cp_writes(), ["00", "04 80"] as Array[String], "50 % по WRK-04.2 → 12.8 → `04 80`")
	_ble.tick(1.0)
	_sc.tick(1.0, 9.0)
	_bridge.pump()
	assert_eq(_cp_writes(), ["00", "04 80"] as Array[String], "в фиксированном режиме 0x11 нет")


func test_req_frd_05_c4_ble_switch_sim_to_fixed_writes_0x04() -> void:
	_setup_ble()
	_make(_ble, 50, SimController.Mode.SIM, 100)
	_sc.start(5.0)
	_bridge.pump()
	_sc.toggle_mode()
	_bridge.pump()
	assert_eq(_cp_writes(), ["00", "11 00 00 FA 00 28 14", "04 FF"] as Array[String])


# ---------------------------------------------------------------------------
# REQ-FRD-04 крит. 6 — нет SIM: переход на фиксированное сопротивление
# ---------------------------------------------------------------------------

func test_req_frd_04_c6_unsupported_at_start_falls_back_to_fixed() -> void:
	_ft.set_simulation_supported(false)
	var modes: Array[int] = []
	_make(_ft, 50, SimController.Mode.SIM, 45)
	_sc.mode_changed.connect(func(m: int) -> void: modes.append(m))
	_sc.start(6.0)
	_run(5.0, 6.0)
	assert_eq(_sc.mode(), SimController.Mode.FIXED)
	assert_eq(_unavailable, 1, "сигнал simulation_unavailable — один раз")
	assert_eq(modes, [SimController.Mode.FIXED] as Array[int])
	assert_eq(_cmds(FakeTrainer.CMD_SIM).size(), 0, "0x11 не отправляется")
	assert_eq(_ft.commands[0]["type"], FakeTrainer.CMD_RESISTANCE)
	assert_eq(int(_ft.commands[0]["value"]), 45)
	assert_eq(_sc.get_state(), SimController.State.RUNNING, "сессия не прерывается")
	assert_eq(_events, [{"type": SimController.EVENT_MODE, "value": "fixed"}] as Array[Dictionary])
	# Попытка вернуться в SIM отклоняется и повторяет сигнал.
	assert_false(_sc.set_mode(SimController.Mode.SIM))
	assert_eq(_sc.mode(), SimController.Mode.FIXED)
	assert_eq(_unavailable, 2)
	assert_eq(_cmds(FakeTrainer.CMD_SIM).size(), 0)


func test_req_frd_04_c6_rejected_sim_command_falls_back_immediately() -> void:
	_ft.fail_next_command(TrainerDevice.ErrorCode.SIMULATION_REJECTED)
	_make(_ft, 50)
	_sc.start(6.0)
	assert_eq(_errors, [TrainerDevice.ErrorCode.SIMULATION_REJECTED] as Array[int])
	assert_eq(_sc.mode(), SimController.Mode.FIXED)
	assert_eq(_unavailable, 1)
	var types: Array[String] = []
	for c in _ft.commands:
		types.append(c["type"])
	assert_eq(types.slice(0, 2), [FakeTrainer.CMD_SIM, FakeTrainer.CMD_RESISTANCE] as Array[String],
		"сразу за отказом — уровень сопротивления")
	_run(5.0, 9.0)
	assert_eq(_cmds(FakeTrainer.CMD_SIM).size(), 1, "больше 0x11 нет")
	assert_eq(_sc.get_state(), SimController.State.RUNNING)


func test_req_frd_04_c6_support_lost_mid_ride() -> void:
	_make(_ft, 50)
	_sc.start(6.0)
	_run(2.0, 6.0)
	_ft.set_simulation_supported(false)
	_step(DT, 6.0)
	assert_eq(_sc.mode(), SimController.Mode.FIXED)
	assert_eq(_unavailable, 1)
	assert_eq(_cmds(FakeTrainer.CMD_RESISTANCE).size(), 1)


func test_req_frd_04_c6_ble_feature_bit_missing_writes_0x04_only() -> void:
	_setup_ble(FTMS_CHARS, false)
	assert_eq(_ble.simulation_support(), TrainerDevice.SimulationSupport.UNSUPPORTED)
	_make(_ble, 50, SimController.Mode.SIM, 50)
	_sc.start(8.0)
	_bridge.pump()
	assert_eq(_cp_writes(), ["00", "04 80"] as Array[String])
	assert_eq(_unavailable, 1)


func test_req_frd_04_c6_ble_rejected_0x11_then_0x04() -> void:
	# 2ACC не заявлен: поддержка UNKNOWN — пробуем SIM, станок отвечает «не поддерживается».
	_setup_ble(["2AD2", "2AD9", "2ADA", "2AD6"] as Array[String])
	assert_eq(_ble.simulation_support(), TrainerDevice.SimulationSupport.UNKNOWN)
	_make(_ble, 50, SimController.Mode.SIM, 50)
	_bridge.fail_next_control_point(FtmsCodec.RESULT_NOT_SUPPORTED)
	_sc.start(8.0)
	_bridge.pump()
	assert_eq(_errors, [TrainerDevice.ErrorCode.SIMULATION_REJECTED] as Array[int])
	assert_eq(_sc.mode(), SimController.Mode.FIXED)
	assert_eq(_unavailable, 1)
	_ble.tick(DT)
	_sc.tick(DT, 8.0)
	_bridge.pump()
	assert_eq(_cp_writes(), ["00", "11 00 00 90 01 28 14", "04 80"] as Array[String],
		"следующим тиком — фиксированное сопротивление")
	_ble.tick(2.0)
	_sc.tick(2.0, 10.0)
	_bridge.pump()
	assert_eq(_cp_writes().size(), 3, "0x11 больше не уходит")


# ---------------------------------------------------------------------------
# События заезда (REQ-FRD-05 крит. 6 — для журнала T-077)
# ---------------------------------------------------------------------------

func test_ride_events_for_mode_and_steepness() -> void:
	_make(_ft, 50)
	_sc.set_steepness(60)
	_sc.set_mode(SimController.Mode.FIXED)
	_sc.set_mode(SimController.Mode.SIM)
	assert_eq(_events.size(), 0, "до старта — настройка, без событий")
	assert_eq(_ft.commands.size(), 0, "до старта команд нет")
	_sc.start(2.0)
	_sc.set_steepness(70)
	_sc.toggle_mode()
	_sc.set_resistance_level(55)
	_sc.toggle_mode()
	assert_eq(_events, [
		{"type": SimController.EVENT_STEEPNESS, "value": 70},
		{"type": SimController.EVENT_MODE, "value": "fixed"},
		{"type": SimController.EVENT_RESISTANCE, "value": 55},
		{"type": SimController.EVENT_MODE, "value": "sim"},
	] as Array[Dictionary])
	_sc.stop()
	var n: int = _ft.commands.size()
	_sc.set_steepness(90)
	_run(3.0, 9.0)
	assert_eq(_events.size(), 4, "после stop() событий нет")
	assert_eq(_ft.commands.size(), n, "после stop() команд нет")


func test_dispose_disconnects_trainer_signals() -> void:
	_make(_ft, 50)
	assert_true(_ft.error.is_connected(_sc._on_trainer_error))
	_sc.dispose()
	assert_false(_ft.error.is_connected(_sc._on_trainer_error))
	assert_false(_ft.connection_state_changed.is_connected(_sc._on_connection_state_changed))
	assert_null(_sc.trainer)


# ---------------------------------------------------------------------------
# SensorHub делегирует SIM станку
# ---------------------------------------------------------------------------

func test_sensor_hub_delegates_simulation() -> void:
	_hub = SensorHub.new(_ft)
	_hub.set_simulation(3.0)
	_assert_sims([3.0])
	assert_eq(_hub.simulation_support(), TrainerDevice.SimulationSupport.SUPPORTED)
	_ft.set_inclination_range(-5.0, 15.0)
	assert_eq(_hub.inclination_range(), Vector2(-5.0, 15.0))
	_ft.set_simulation_supported(false)
	assert_eq(_hub.simulation_support(), TrainerDevice.SimulationSupport.UNSUPPORTED)


func test_sim_controller_over_sensor_hub() -> void:
	_hub = SensorHub.new(_ft)
	_make(_hub, 50)
	_sc.start(8.0)
	for i in 20:
		_hub.tick(DT)
		_sc.tick(DT, 8.0 + i * 0.2)
	assert_true(_sim_values().size() >= 2, "команды SIM доходят до станка через хаб")
	assert_almost_eq(_sim_values()[0], 4.0, 1e-9)


func _assert_sims(expected: Array, message: String = "") -> void:
	var got: Array[float] = _sim_values()
	assert_eq(got.size(), expected.size(), "число команд SIM: %s vs %s. %s" % [str(got), str(expected), message])
	for i in mini(got.size(), expected.size()):
		assert_almost_eq(got[i], float(expected[i]), 1e-9, "команда SIM #%d. %s" % [i, message])


func test_steepness_rule_matches_profile() -> void:
	assert_eq(SimController.DEFAULT_STEEPNESS_PCT, Profile.DEFAULT_SIM_STEEPNESS_PCT)
	for pct in [-10, 0, 2, 3, 42, 47, 50, 98, 100, 130]:
		assert_eq(SimController.snap_steepness(pct), Profile.snap_sim_steepness(float(pct)), "k = %d" % pct)
