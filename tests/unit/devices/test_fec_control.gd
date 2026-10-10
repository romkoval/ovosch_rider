extends GutTest
## T-168: управление станком по FE-C over BLE (REQ-DEV-11 п.6–10; регрессия WRK-02..05, FRD-04,
## WRK-09 п.4, DEV-05 п.2). `BleTrainer` поверх `StubBleBridge` с FE-C-фикстурой
## `tests/fixtures/fec/neo_fec.json`; ответы станка (0x36, 0x47) подаёт тест.

const FIXTURE: String = "res://tests/fixtures/fec/neo_fec.json"
const DEV: String = "neo"
const CONNECTED: int = TrainerDevice.ConnectionState.CONNECTED

var _fx: Dictionary = {}
var _bridge: StubBleBridge
var _t: BleTrainer
var _errors: Array[int] = []
var _disposables: Array = []


func before_all() -> void:
	_fx = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))


func before_each() -> void:
	_bridge = StubBleBridge.new()
	_t = null
	_errors = []
	_disposables = []


func after_each() -> void:
	for d: Variant in _disposables:
		if d != null and (d as Object).has_method("dispose"):
			(d as Object).call("dispose")
	_disposables = []
	if _t != null:
		_t.dispose()
	if _bridge != null:
		_bridge.dispose()


func _hex(key: String) -> PackedByteArray:
	return BleBytes.from_hex(str(_fx[key]).replace(" ", ""))


func _services(bridge: StubBleBridge, id: String) -> void:
	var out: Dictionary = {}
	for s: String in _fx["services"]:
		out[s] = PackedStringArray(_fx["services"][s])
	bridge.set_device_services(id, out)


func _page_msg(page: Array) -> PackedByteArray:
	return FecCodec.encode_message(PackedByteArray(page), FecCodec.ANT_BROADCAST_DATA)


## FE-C-станок: подключение, ответ на 0x36 (`caps` < 0 — не отвечать), CONNECTED.
func _connect(caps: int = 0x07) -> BleTrainer:
	_services(_bridge, DEV)
	_t = BleTrainer.new(_bridge)
	_t.error.connect(func(c: int, _m: String) -> void: _errors.append(c))
	_t.connect_device(DEV)
	_bridge.pump()
	if caps >= 0:
		_bridge.emit_notification(DEV, BleUuids.FEC_NOTIFY, _page_msg([0x36, 0xFF, 0xFF, 0xFF, 0xFF, 0, 0, caps]))
	_bridge.pump()
	return _t


func _caps(bits: int) -> void:
	_bridge.emit_notification(DEV, BleUuids.FEC_NOTIFY, _page_msg([0x36, 0xFF, 0xFF, 0xFF, 0xFF, 0, 0, bits]))
	_bridge.pump()


func _status(last_command: int, status: int) -> void:
	_bridge.emit_notification(DEV, BleUuids.FEC_NOTIFY, _page_msg([0x47, last_command, 0xFF, status, 0xFF, 0xFF, 0xFF, 0xFF]))


## Записи на FEC3 (байты) по порядку.
func _writes(bridge: StubBleBridge = null) -> Array[PackedByteArray]:
	var b := bridge if bridge != null else _bridge
	var out: Array[PackedByteArray] = []
	for c in b.calls_of("write"):
		if BleUuids.normalize(str(c["char"])) == BleUuids.FEC_WRITE:
			out.append(c["bytes"])
	return out


func _pages(page_number: int, bridge: StubBleBridge = null) -> Array[PackedByteArray]:
	var out: Array[PackedByteArray] = []
	for w in _writes(bridge):
		if w[4] == page_number:
			out.append(w)
	return out


# ---------------------------------------------------------------------------
# REQ-DEV-11 п.6 — ERG, страница 0x31
# ---------------------------------------------------------------------------

func test_req_dev_11_c6_target_power_bytes() -> void:
	_connect()
	assert_eq(_t.get_connection_state(), CONNECTED)
	assert_true(_t.has_control(), "с FEC3 — управляемый")
	_t.set_target_power(150)
	assert_eq(_pages(0x31).back(), _hex("target_power_150w"))
	_t.set_target_power(250)
	assert_eq(_pages(0x31).back(), BleBytes.from_hex("A4094F0531FFFFFFFFFFE803C2"))
	_t.set_target_power(130)
	var b: PackedByteArray = _pages(0x31).back()
	assert_eq([b[10], b[11]], [0x08, 0x02])
	assert_eq(_bridge.calls_of("write")[1]["with_response"], true, "запись с ответом")


func test_req_dev_11_c6_wrk_02_c2_target_written_at_interval_boundary() -> void:
	_connect()
	var s := WorkoutSession.new(Workout.make("p", [WorkoutStep.watts(60, 150.0), WorkoutStep.watts(60, 250.0)] as Array[WorkoutStep]), _t, 200)
	s.start()
	assert_eq(_pages(0x31).back(), _hex("target_power_150w"), "старт — 150 Вт сразу")
	for i in 59:
		s.tick(1.0)
	var before := _pages(0x31).size()
	s.tick(1.0)
	assert_eq(_pages(0x31).size(), before + 1, "на границе интервала — новая цель в ту же секунду")
	assert_eq(_pages(0x31).back(), BleBytes.from_hex("A4094F0531FFFFFFFFFFE803C2"))


func test_req_dev_11_c8_fallback_power_range_2400_to_2000() -> void:
	_connect()
	_t.set_target_power(2400)
	var b: PackedByteArray = _pages(0x31).back()
	assert_eq([b[10], b[11]], [0x40, 0x1F], "2000 Вт")


# ---------------------------------------------------------------------------
# REQ-DEV-11 п.7 — доставка и подтверждение
# ---------------------------------------------------------------------------

func test_req_dev_11_c7_a_one_retry_then_write_failed() -> void:
	_connect()
	_bridge.fail_next_write()
	_t.set_target_power(150)
	_bridge.pump()
	var p31 := _pages(0x31)
	assert_eq(p31.size(), 2, "один повтор той же записи")
	assert_eq(p31[1], p31[0])
	assert_eq(_errors, [] as Array[int], "после успешного повтора ошибки нет")
	_bridge.fail_next_write()
	_t.set_target_power(200)
	_bridge.fail_next_write()  # повтор тоже не удастся
	_bridge.pump()
	assert_has(_errors, TrainerDevice.ErrorCode.WRITE_FAILED, "второй отказ — ошибка записи")


func test_req_dev_11_c7_a_bridge_error_write_failed_also_retries() -> void:
	_connect()
	_t.set_target_power(150)
	var n := _pages(0x31).size()
	_bridge.emit_error(DEV, BleBridge.ErrorCode.WRITE_FAILED, "write failed")
	assert_eq(_pages(0x31).size(), n + 1, "повтор по error(WRITE_FAILED)")


func test_req_dev_11_c7_b_request_47_after_each_31_and_statuses() -> void:
	_connect()
	_t.set_target_power(150)
	var w := _writes()
	assert_eq(w[w.size() - 2][4], 0x31)
	var req: PackedByteArray = w.back()
	assert_eq([req[4], req[10], req[11]], [0x46, 0x47, 0x01], "0x46: байт 6 = 47, байт 7 = 01")
	_status(0x31, FecCodec.COMMAND_PASS)
	assert_eq(_errors, [] as Array[int], "Pass — цель применена")
	for st in [FecCodec.COMMAND_FAIL, FecCodec.COMMAND_REJECTED]:
		_errors.clear()
		_t.set_target_power(160 + st)
		_status(0x31, st)
		assert_eq(_errors, [TrainerDevice.ErrorCode.CONTROL_POINT_REJECTED] as Array[int], "статус %d — ошибка команды" % st)
	_errors.clear()
	_t.set_target_power(170)
	_t.tick(2.1)
	assert_eq(_errors, [] as Array[int], "нет ответа за 2 с — не ошибка пользователю")
	_t.set_target_power(175)
	_status(0x30, FecCodec.COMMAND_REJECTED)
	assert_eq(_errors, [] as Array[int], "байт 1 ≠ 31 — не ошибка")
	_t.set_target_power(180)
	_status(0x31, FecCodec.COMMAND_NOT_SUPPORTED)
	assert_eq(_errors, [] as Array[int], "Not supported — capability change, not a command error (U-36)")
	assert_false(_t.is_erg_available(), "ERG unavailable until the end of the connection")
	var n := _pages(0x31).size()
	_t.set_target_power(190)
	_t.set_erg_enabled(false)
	_t.set_erg_enabled(true)
	assert_eq(_pages(0x31).size(), n, "ERG недоступен до конца подключения — 0x31 больше нет")


# ---------------------------------------------------------------------------
# REQ-DEV-11 п.8 — возможности
# ---------------------------------------------------------------------------

func test_req_dev_11_c8_capabilities_request_and_no_answer_all_available() -> void:
	_connect(-1)
	assert_ne(_t.get_connection_state(), CONNECTED, "ждём 0x36")
	var req: PackedByteArray = _writes()[0]
	assert_eq([req[4], req[10]], [0x46, 0x36], "запрос 0x36 страницей 0x46")
	_t.tick(2.0)
	assert_eq(_t.get_connection_state(), CONNECTED, "нет ответа за 2 с — подключён, всё доступно")
	assert_eq(_t.simulation_support(), TrainerDevice.SimulationSupport.UNKNOWN)
	_t.set_target_power(150)
	assert_eq(_pages(0x31).size(), 1)
	_t.set_simulation(5.0)
	assert_eq(_pages(0x33).size(), 1)


func test_req_dev_11_c8_without_target_power_bit_no_31() -> void:
	_connect(0x05)
	_t.set_target_power(150)
	assert_eq(_pages(0x31).size(), 0, "без бита 1 — ни одной 0x31")


func test_req_dev_11_c8_no_simulation_free_ride_has_no_33_and_hud_message() -> void:
	_connect(0x03)  # 36 FF FF FF FF 00 00 03
	assert_eq(_t.simulation_support(), TrainerDevice.SimulationSupport.UNSUPPORTED)
	var s := FreeRideSession.new(_t, RouteCatalog.MOUNTAINS, 50, 75.0, 200)
	_disposables.append(s)
	var unavailable: Array[bool] = []
	s.simulation_unavailable.connect(func() -> void: unavailable.append(true))
	s.start()
	for i in 30:
		_bridge.emit_notification(DEV, BleUuids.FEC_NOTIFY, _hex("trainer_data_250w_90rpm"))
		s.tick(1.0)
	assert_eq(_pages(0x33).size(), 0, "ни одной 0x33")
	assert_eq(_pages(0x32).size(), 0)
	assert_false(unavailable.is_empty(), "сообщение «станок не поддерживает SIM» (FRD-04 п.6)")
	assert_gt(_pages(0x30).size(), 0, "фиксированное сопротивление")


# ---------------------------------------------------------------------------
# REQ-DEV-11 п.9 — сопротивление, SIM, переподключение и пауза
# ---------------------------------------------------------------------------

func test_req_dev_11_c9_a_basic_resistance_bytes() -> void:
	_connect()
	_t.set_erg_enabled(false)
	_t.set_resistance_level(50)
	assert_eq(_pages(0x30).back(), BleBytes.from_hex("A4094F0530FFFFFFFFFFFF64B3"))
	for pair: Array in [[0, 0x00], [35, 0x46], [100, 0xC8]]:
		_t.set_resistance_level(pair[0])
		assert_eq(_pages(0x30).back()[11], pair[1], "%d %%" % pair[0])


func test_req_dev_11_c9_b_track_and_wind_pages() -> void:
	_connect()
	_t.set_simulation(5.0)
	var w := _writes()
	assert_eq(w[w.size() - 2], FecCodec.encode_message(PackedByteArray([0x32, 0xFF, 0xFF, 0xFF, 0xFF, 0x14, 0x7F, 0x64])),
		"при входе в SIM — сначала 0x32")
	assert_eq(w.back(), BleBytes.from_hex("A4094F0533FFFFFFFF145050C0"))
	for pair: Array in [[-3.0, [0xF4, 0x4C]], [0.0, [0x20, 0x4E]], [12.34, [0xF2, 0x52]]]:
		_t.set_simulation(pair[0])
		var b: PackedByteArray = _pages(0x33).back()
		assert_eq([b[9], b[10]], pair[1], "уклон %.2f %%" % pair[0])
	assert_eq(_pages(0x32).size(), 1, "0x32 — один раз за вход в SIM")
	_t.set_resistance_level(40)
	_t.set_simulation(1.0)
	assert_eq(_pages(0x32).size(), 2, "возврат из фиксированного режима — снова 0x32")
	assert_true(FecCodec.encode_track_resistance(200.01, 0.004).is_empty(), "вне ±200 % — отклонено")


func test_req_dev_11_c9_c_reconnect_resubscribes_and_resends_within_1s() -> void:
	_connect()
	var s := WorkoutSession.new(Workout.make("p", [WorkoutStep.watts(120, 150.0)] as Array[WorkoutStep]), _t, 200)
	s.start()
	for i in 5:
		s.tick(1.0)
	var subs := _bridge.calls_of("subscribe").size()
	var targets := _pages(0x31).size()
	_bridge.emit_disconnected(DEV)
	_bridge.pump()  # connect_peripheral → connected → discover → services
	_bridge.pump()
	assert_eq(_pages(0x46).filter(func(b: PackedByteArray) -> bool: return b[10] == 0x36).size(), 2,
		"capabilities requested again after `connected` (DEV-10 p.5 (e))")
	_caps(0x07)
	assert_eq(_t.get_connection_state(), CONNECTED)
	assert_eq(_bridge.calls_of("subscribe").size(), subs + 1, "повторная подписка на FEC2")
	assert_eq(_pages(0x31).size(), targets + 1, "цель — сразу после CONNECTED")
	# Пауза: после connected — только подписка, команда — после resume.
	s.pause()
	_bridge.emit_disconnected(DEV)
	_bridge.pump()
	_bridge.pump()
	_caps(0x07)  # the 0x36 request is part of the connection handshake, not a mode command
	var paused_writes := _writes().size()
	for i in 3:
		s.tick(1.0)
	assert_eq(_writes().size(), paused_writes, "на паузе записей нет")
	s.resume()
	assert_eq(_pages(0x31).size(), targets + 2, "после resume — цель")


func test_wrk_09_c4_control_not_allowed_no_writes_at_all() -> void:
	_services(_bridge, DEV)
	_t = BleTrainer.new(_bridge)
	_t.set_control_allowed(false)
	_t.connect_device(DEV)
	_bridge.pump()
	assert_eq(_t.get_connection_state(), CONNECTED)
	assert_false(_t.has_control())
	_t.set_target_power(150)
	_t.set_erg_enabled(false)
	_t.set_resistance_level(40)
	_t.set_simulation(3.0)
	assert_eq(_bridge.calls_of("write").size(), 0, "сессия power_meter — ни одной записи")


func test_dev_05_c2_power_meter_priority_control_still_to_fec_trainer() -> void:
	_connect()
	var pm := FakePowerMeter.new()
	pm.set_power(200)
	_disposables.append(pm)
	var hub := SensorHub.new(_t)
	hub.set_power_meter(pm)
	pm.connect_device("pm")
	_disposables.push_front(hub)
	var s := WorkoutSession.new(Workout.make("p", [WorkoutStep.watts(20, 150.0)] as Array[WorkoutStep]), hub, 200)
	assert_eq(s.trainer_mode, TrainerDevice.MODE_SMART)
	s.start()
	for i in 10:
		_bridge.emit_notification(DEV, BleUuids.FEC_NOTIFY, _hex("trainer_data_250w_90rpm"))
		s.tick(1.0)
	assert_eq(s.samples.power_w[s.samples.size() - 1], 200, "мощность — датчик (T-170)")
	assert_eq(_pages(0x31).back(), _hex("target_power_150w"), "управление — на станок FE-C")


# ---------------------------------------------------------------------------
# REQ-DEV-11 п.10 — эквивалентность FTMS и FE-C за TrainerDevice
# ---------------------------------------------------------------------------

## Команды режима из журнала моста в общих терминах: ["target", Вт] | ["resistance"] | ["sim", уклон].
static func _commands(bridge: StubBleBridge) -> Array:
	var out: Array = []
	for c in bridge.calls_of("write"):
		var b: PackedByteArray = c["bytes"]
		var ch := BleUuids.normalize(str(c["char"]))
		if ch == BleUuids.FTMS_CONTROL_POINT:
			match b[0]:
				0x05:
					out.append(["target", BleBytes.s16(b, 1)])
				0x04:
					out.append(["resistance"])
				0x11:
					out.append(["sim", snappedf(BleBytes.s16(b, 3) * 0.01, 0.01)])
		elif ch == BleUuids.FEC_WRITE:
			match b[4]:
				0x31:
					out.append(["target", BleBytes.u16(b, 10) / 4])
				0x30:
					out.append(["resistance"])
				0x33:
					out.append(["sim", snappedf(BleBytes.u16(b, 9) * 0.01 - 200.0, 0.01)])
	return out


func _run_equivalence(fec: bool) -> Dictionary:
	var bridge := StubBleBridge.new()
	_disposables.append(bridge)
	if fec:
		_services(bridge, "t")
	else:
		bridge.set_device_services("t", {BleUuids.FTMS_SERVICE: PackedStringArray([BleUuids.INDOOR_BIKE_DATA,
			BleUuids.FTMS_CONTROL_POINT, BleUuids.FTMS_STATUS])})
	var t := BleTrainer.new(bridge)
	_disposables.push_front(t)
	t.connect_device("t")
	bridge.pump()
	if fec:
		bridge.emit_notification("t", BleUuids.FEC_NOTIFY, _page_msg([0x36, 0xFF, 0xFF, 0xFF, 0xFF, 0, 0, 0x07]))
	bridge.pump()
	var feed := func(watts: int) -> void:
		if fec:
			bridge.emit_notification("t", BleUuids.FEC_NOTIFY, _page_msg([0x19, 1, 85, 0, 0, watts & 0xFF, (watts >> 8) & 0x0F, 0x30]))
		else:
			bridge.emit_notification("t", BleUuids.INDOOR_BIKE_DATA, FtmsCodec.encode_indoor_bike_data(30.0, 85.0, watts))
	var plan := Workout.make("eq", [WorkoutStep.watts(60, 150.0), WorkoutStep.watts(60, 250.0), WorkoutStep.free_ride(60)] as Array[WorkoutStep])
	var s := WorkoutSession.new(plan, t, 200)
	s.start()
	while s.get_state() != WorkoutSession.State.FINISHED:
		var e := s.executor.elapsed_sec()
		if e == 90:
			s.set_erg_enabled(false)
		elif e == 100:
			s.set_erg_enabled(true)
		feed.call(200)
		s.tick(1.0)
		bridge.pump()
	var fr := FreeRideSession.new(t, RouteCatalog.MOUNTAINS, 50, 75.0, 200)
	_disposables.push_front(fr)
	fr.start()
	for i in 60:
		feed.call(220)
		fr.tick(1.0)
		bridge.pump()
	return {"plan": s.samples.to_dict(), "free": fr.samples.to_dict(), "commands": _commands(bridge)}


func test_req_dev_11_c10_ftms_and_fec_same_samples_and_commands() -> void:
	var ftms := _run_equivalence(false)
	var fec := _run_equivalence(true)
	assert_eq(fec["plan"], ftms["plan"], "одинаковые сэмплы плана")
	assert_eq(fec["free"], ftms["free"], "одинаковые сэмплы свободной езды")
	assert_eq(fec["commands"], ftms["commands"], "одинаковая последовательность команд станку")
	assert_gt((fec["commands"] as Array).size(), 5)


func test_req_dev_11_c10_no_protocol_literals_in_session_domain_ui() -> void:
	var offenders: Array[String] = []
	for root in ["res://src/session/", "res://src/domain/", "res://src/ui/"]:
		_scan(root, offenders)
	assert_eq(offenders, [] as Array[String])


func _scan(dir_path: String, out: Array[String]) -> void:
	var d := DirAccess.open(dir_path)
	if d == null:
		return
	for f in d.get_files():
		if not f.ends_with(".gd"):
			continue
		var n := 0
		for line in FileAccess.get_file_as_string(dir_path.path_join(f)).split("\n"):
			n += 1
			var code := line.split("#")[0].to_lower()
			for needle in ["6e40fec", "fe-c", "fe_c", "0x1826", "2ad9"]:
				if code.contains(needle):
					out.append("%s:%d %s" % [f, n, line.strip_edges()])
	for sub in d.get_directories():
		_scan(dir_path.path_join(sub), out)


# ---------------------------------------------------------------------------
# Follow-up U-36 (T-161): FE-C without ERG → fixed resistance 0x30
# ---------------------------------------------------------------------------

func test_req_dev_11_c8_no_target_power_bit_session_uses_basic_resistance() -> void:
	_connect(0x05)  # 36 FF FF FF FF 00 00 05 — no bit 1
	assert_false(_t.is_erg_available())
	var s := WorkoutSession.new(Workout.make("p", [WorkoutStep.watts(60, 150.0), WorkoutStep.free_ride(30), WorkoutStep.watts(60, 250.0)] as Array[WorkoutStep]), _t, 200)
	s.resistance_level = 35
	s.start()
	assert_gt(_pages(0x30).size(), 0, "0x30 right after the start")
	assert_eq(_pages(0x30).back()[11], 0x46, "35 %")
	s.set_resistance_level(40)
	assert_eq(_pages(0x30).back()[11], 0x50, "+ → 40 % at once")
	for i in 150:
		s.tick(1.0)
	assert_eq(_pages(0x31).size(), 0, "no 0x31 during the ride")


func test_req_dev_11_c7_b_not_supported_mid_ride_switches_to_basic_resistance() -> void:
	_connect()
	var s := WorkoutSession.new(Workout.make("p", [WorkoutStep.watts(60, 150.0), WorkoutStep.watts(60, 250.0)] as Array[WorkoutStep]), _t, 200)
	s.start()
	assert_eq(_pages(0x31).size(), 1)
	_status(0x31, FecCodec.COMMAND_NOT_SUPPORTED)
	assert_false(s.erg_available())
	assert_gt(_pages(0x30).size(), 0, "0x30 instead of 0x31")
	assert_eq(_errors, [] as Array[int], "no command error")
	for i in 70:
		s.tick(1.0)
	assert_eq(_pages(0x31).size(), 1, "no 0x31 after the refusal")
	assert_eq(s.samples.target_w[65], 250, "sample target — the plan target")
