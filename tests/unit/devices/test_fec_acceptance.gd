extends GutTest
## Приёмка T-167 и T-168 (tester): станок по Tacx FE-C over BLE.
## REQ-DEV-11 п.1–10, REQ-DEV-01 п.1–2, REQ-WRK-09 п.1 (б), п.4, регрессия DEV-10 п.2, WRK-02..05,
## FRD-04 п.6. Байты сообщений собираются в тесте вручную по тексту критериев (не кодеком
## приложения): `A4 09 <ID> 05 <страница 8 байт> <XOR>`. Станок — `BleTrainer` поверх
## `StubBleBridge` (через `ConnectionManager` там, где важны тип и запоминание).

const FEC1: String = "6E40FEC1-B5A3-F393-E0A9-E50E24DCCA9E"
const FEC2: String = "6E40FEC2-B5A3-F393-E0A9-E50E24DCCA9E"
const FEC3: String = "6E40FEC3-B5A3-F393-E0A9-E50E24DCCA9E"
const PROPRIETARY: String = "669AA501-0C08-969E-E211-86AD5062675F"
const NEO: String = "neo-acc"

var _dir: String
var _bridge: StubBleBridge
var _disposables: Array = []


func before_each() -> void:
	_dir = "user://acc_fec_%d_%d/" % [Time.get_ticks_usec(), randi() % 100000]
	_bridge = StubBleBridge.new()
	_disposables = []


func after_each() -> void:
	for d: Variant in _disposables:
		if d != null and is_instance_valid(d) and (d as Object).has_method("dispose"):
			(d as Object).call("dispose")
	_disposables = []
	_bridge.dispose()
	_remove_tree(ProjectSettings.globalize_path(_dir))


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


# ---------------------------------------------------------------------------
# Байты
# ---------------------------------------------------------------------------

static func _hex(s: String) -> PackedByteArray:
	var out := PackedByteArray()
	for part in s.split(" ", false):
		out.append(part.hex_to_int())
	return out


static func _to_hex(b: PackedByteArray) -> String:
	var parts: Array[String] = []
	for x in b:
		parts.append("%02X" % x)
	return " ".join(parts)


## ANT-сообщение по критерию: `A4 09 <id> <канал> <страница> <XOR 12 байт>`.
static func _msg(page: Array, msg_id: int = 0x4E, channel: int = 0x05) -> PackedByteArray:
	var out := PackedByteArray([0xA4, 0x09, msg_id, channel])
	for x in page:
		out.append(int(x))
	var cs := 0
	for x in out:
		cs ^= x
	out.append(cs)
	return out


## Сервисы эталонного Neo после подключения (DEV-11 формулировка, п.1 (б)).
func _neo_services(bridge: StubBleBridge, id: String, with_fec3: bool = true) -> void:
	var fec_chars := PackedStringArray([FEC2])
	if with_fec3:
		fec_chars.append(FEC3)
	bridge.set_device_services(id, {
		"180A": PackedStringArray(["2A29", "2A24"]),
		"1816": PackedStringArray(["2A5B", "2A5C"]),
		"1818": PackedStringArray(["2A63", "2A65"]),
		PROPRIETARY: PackedStringArray(["669AA605-0C08-969E-E211-86AD5062675F"]),
		FEC1: fec_chars,
	})


func _notify(id: String, bytes: PackedByteArray, bridge: StubBleBridge = null) -> void:
	(bridge if bridge != null else _bridge).emit_notification(id, FEC2, bytes)


## Ответ станка на запрос возможностей: страница 0x36, байт 7 — биты.
func _answer_caps(id: String, bits: int, bridge: StubBleBridge = null) -> void:
	_notify(id, _msg([0x36, 0xFF, 0xFF, 0xFF, 0xFF, 0x00, 0x00, bits]), bridge)
	(bridge if bridge != null else _bridge).pump()


## Записи в FEC3 (байты) по порядку.
func _fec3_writes(bridge: StubBleBridge = null) -> Array[PackedByteArray]:
	var out: Array[PackedByteArray] = []
	for c in (bridge if bridge != null else _bridge).calls_of("write"):
		if BleUuids.normalize(str(c["char"])) == FEC3:
			out.append(c["bytes"])
	return out


## Номера страниц записей FEC3 (байт 4), без запросов 0x46.
func _mode_pages(bridge: StubBleBridge = null) -> Array[int]:
	var out: Array[int] = []
	for w in _fec3_writes(bridge):
		if w[4] != 0x46:
			out.append(w[4])
	return out


func _calls_for_char(method: String, char_uuid: String, id: String = "") -> int:
	var n := 0
	for c in _bridge.calls_of(method):
		if not id.is_empty() and str(c.get("id", "")) != id:
			continue
		if BleUuids.normalize(str(c.get("char", ""))) == BleUuids.normalize(char_uuid):
			n += 1
	return n


## Станок FE-C напрямую: подключение, ответ 0x36 (`caps` < 0 — не отвечать), CONNECTED.
func _trainer(caps: int = 0x07, with_fec3: bool = true) -> BleTrainer:
	_neo_services(_bridge, NEO, with_fec3)
	var t := BleTrainer.new(_bridge)
	_disposables.push_front(t)
	t.connect_device(NEO)
	_bridge.pump()
	if caps >= 0:
		_answer_caps(NEO, caps)
	else:
		for i in 25:
			t.tick(0.1)
		_bridge.pump()
	return t


func _cm() -> ConnectionManager:
	var cm := ConnectionManager.new(_bridge, RememberedDevices.new(_dir + "devices/"))
	cm.set_profile("p")
	_disposables.push_front(cm)
	return cm


## Данные станка: страница 0x19 с мощностью и каденсом.
static func _trainer_data(watts: int, rpm: int) -> PackedByteArray:
	return _msg([0x19, 0x01, rpm, 0x00, 0x00, watts & 0xFF, ((watts >> 8) & 0x0F) | 0x30, 0x30])


# ===========================================================================
# REQ-DEV-01 п.1 — фильтр сканирования
# ===========================================================================

func test_req_dev_01_c1_scan_filter_has_five_services_with_fec1() -> void:
	var cm := _cm()
	cm.scanner.start()
	var calls := _bridge.calls_of("start_scan")
	assert_eq(calls.size(), 1)
	var arg: PackedStringArray = calls[0]["service_uuids"]
	var norm: Array[String] = []
	for u in arg:
		norm.append(BleUuids.normalize(u))
	for u in ["1826", FEC1, "180D", "1816", "1818"]:
		assert_true(norm.has(BleUuids.normalize(u)), "в фильтре есть %s: %s" % [u, str(arg)])
	assert_eq(arg.size(), 5, "ровно пять сервисов")


# ===========================================================================
# REQ-DEV-11 п.1 — тип «станок», датчики станка, фирменный сервис
# ===========================================================================

func test_req_dev_11_c1_b_c_neo_cadence_advert_becomes_single_trainer_row_no_csc_cps_subscriptions() -> void:
	var cm := _cm()
	cm.scanner.start()
	_bridge.emit_device_found(NEO, "Tacx Neo 11565", -60, PackedStringArray(["1816"]))
	assert_eq(cm.scanner.find(NEO)["kind"], RememberedDevices.KIND_CADENCE, "по рекламе — каденс (DEV-01 п.2)")
	_neo_services(_bridge, NEO)
	cm.connect_sensor(NEO, RememberedDevices.KIND_CADENCE)
	_bridge.pump()
	_answer_caps(NEO, 0x07)
	for i in 10:
		cm.tick(0.1)
	_bridge.pump()
	assert_eq(cm.scanner.find(NEO)["kind"], RememberedDevices.KIND_TRAINER, "после services_discovered — «станок»")
	assert_eq(cm.state_of(NEO), TrainerDevice.ConnectionState.CONNECTED)
	var remembered := RememberedDevices.new(_dir + "devices/")
	assert_eq(str(remembered.trainer().get("id", "")), NEO, "запомнен как станок на устройстве")
	for s in remembered.sensors("p"):
		assert_ne(str(s.get("id", "")), NEO, "в датчиках профиля его нет")
	# Данные идут, а подписок на CSC/CPS станка нет за всё подключение.
	for i in 5:
		_notify(NEO, _trainer_data(250, 90))
		cm.tick(1.0)
		_bridge.pump()
	assert_eq(_calls_for_char("subscribe", "2A5B", NEO), 0, "нет subscribe на 0x2A5B у станка")
	assert_eq(_calls_for_char("subscribe", "2A63", NEO), 0, "нет subscribe на 0x2A63 у станка")
	var rows := 0
	for d in cm.scanner.devices:
		if str(d.get("id", "")) == NEO:
			rows += 1
	assert_eq(rows, 1, "одна строка на id")
	for kind in [RememberedDevices.KIND_CADENCE, RememberedDevices.KIND_POWER]:
		assert_ne(str(cm.sensor_ids.get(kind, "")), NEO, "отдельного датчика %s с тем же id нет" % kind)
	# (д) фирменный сервис не используется.
	for method in ["subscribe", "write", "read_characteristic"]:
		for c in _bridge.calls_of(method):
			assert_ne(BleUuids.normalize(str(c.get("service", ""))), BleUuids.normalize(PROPRIETARY), "%s на 669AA501" % method)


func test_req_dev_11_c1_g_ftms_plus_fec_connects_by_ftms_without_fec_traffic() -> void:
	_bridge.set_device_services("both", {
		"1826": PackedStringArray([BleUuids.INDOOR_BIKE_DATA, BleUuids.FTMS_CONTROL_POINT, BleUuids.FTMS_STATUS]),
		FEC1: PackedStringArray([FEC2, FEC3])})
	var t := BleTrainer.new(_bridge)
	_disposables.push_front(t)
	t.connect_device("both")
	for i in 3:
		_bridge.pump()
	t.set_target_power(200)
	for i in 3:
		t.tick(0.5)
		_bridge.pump()
	for method in ["subscribe", "write"]:
		for c in _bridge.calls_of(method):
			assert_ne(BleUuids.normalize(str(c.get("service", ""))), BleUuids.normalize(FEC1), "%s на FEC1 при наличии FTMS" % method)


# ===========================================================================
# REQ-DEV-11 п.2 — подключение; WRK-09 п.1 (б), п.4
# ===========================================================================

func test_req_dev_11_c2_subscribe_fec2_then_caps_request_no_request_control() -> void:
	var t := _trainer(0x07)
	assert_eq(t.get_connection_state(), TrainerDevice.ConnectionState.CONNECTED)
	var subs := _bridge.calls_of("subscribe")
	assert_eq(subs.size(), 1, "одна подписка")
	assert_eq(BleUuids.normalize(str(subs[0]["char"])), FEC2)
	var writes := _bridge.calls_of("write")
	assert_eq(writes.size(), 1, "одна запись")
	var w: PackedByteArray = writes[0]["bytes"]
	assert_eq(w[4], 0x46, "это запрос страницы 0x46")
	assert_eq(w[10], 0x36, "байт 6 страницы — 0x36 (возможности)")
	assert_eq(_calls_for_char("write", BleUuids.FTMS_CONTROL_POINT), 0, "FTMS Request Control не уходит")
	# Порядок: подписка раньше запроса возможностей.
	var log_order: Array[String] = []
	for c in _bridge.calls:
		if str(c.get("method", "")) in ["subscribe", "write"]:
			log_order.append(str(c["method"]))
	assert_eq(log_order, ["subscribe", "write"], "сначала subscribe(FEC2), затем запрос 0x36")


func test_req_dev_11_c2_no_caps_answer_connects_after_2s_all_modes_available() -> void:
	var t := _trainer(-1)
	assert_eq(t.get_connection_state(), TrainerDevice.ConnectionState.CONNECTED, "ответа 0x36 нет — подключён через ≤ 2 с")
	assert_true(t.has_control())
	t.set_target_power(150)
	t.tick(0.1)
	_bridge.pump()
	assert_true(_mode_pages().has(0x31), "без ответа все режимы доступны")


func test_req_dev_11_c2_without_fec2_not_connected_error_no_fec_traffic() -> void:
	_bridge.set_device_services(NEO, {FEC1: PackedStringArray([FEC3])})
	var t := BleTrainer.new(_bridge)
	_disposables.push_front(t)
	var errors: Array[int] = []
	t.error.connect(func(c: int, _m: String) -> void: errors.append(c))
	t.connect_device(NEO)
	for i in 3:
		_bridge.pump()
	for i in 30:
		t.tick(0.1)
	assert_ne(t.get_connection_state(), TrainerDevice.ConnectionState.CONNECTED, "без FEC2 — не «подключено»")
	assert_has(errors, TrainerDevice.ErrorCode.CONNECTION_FAILED)
	for method in ["subscribe", "write"]:
		for c in _bridge.calls_of(method):
			assert_ne(BleUuids.normalize(str(c.get("service", ""))), BleUuids.normalize(FEC1), "нет %s на FEC1" % method)


func test_req_dev_11_c2_wrk_09_c1b_c4_without_fec3_power_meter_session_no_writes() -> void:
	var cm := _cm()
	_neo_services(_bridge, NEO, false)
	cm.connect_trainer(NEO)
	for i in 3:
		_bridge.pump()
	for i in 25:
		cm.tick(0.1)
	_bridge.pump()
	assert_eq(cm.state_of(NEO), TrainerDevice.ConnectionState.CONNECTED, "только данные — подключён")
	var check := cm.start_check()
	assert_true(check["allowed"])
	assert_eq(check["mode"], TrainerDevice.MODE_POWER_METER, "сессия power_meter")
	var dev := cm.session_device()
	var s := WorkoutSession.new(Workout.make("p", [WorkoutStep.watts(10, 150.0), WorkoutStep.watts(10, 250.0)] as Array[WorkoutStep]), dev, 200)
	s.start()
	s.set_erg_enabled(false)
	s.set_resistance_level(60)
	s.set_erg_enabled(true)
	while s.get_state() != WorkoutSession.State.FINISHED:
		_notify(NEO, _trainer_data(180, 85))
		s.tick(1.0)
		_bridge.pump()
	assert_eq(_bridge.calls_of("write").size(), 0, "за подключение ни одного write")
	assert_eq(s.samples.power_w[s.samples.size() - 1], 180, "источник мощности — станок")
	var subs := 0
	for c in _bridge.calls_of("subscribe"):
		if str(c["id"]) == NEO:
			subs += 1
			assert_eq(BleUuids.normalize(str(c["char"])), FEC2, "подписка только на FEC2 (WRK-09 п.4)")
	assert_gt(subs, 0)


# ===========================================================================
# REQ-DEV-11 п.3, п.4, п.5 — приём сообщений, данные
# ===========================================================================

func test_req_dev_11_c3_c4_invalid_messages_dropped_in_session() -> void:
	var t := _trainer()
	var s := WorkoutSession.new(Workout.make("p", [WorkoutStep.watts(30, 200.0)] as Array[WorkoutStep]), t, 200)
	var session_errors: Array = []
	t.error.connect(func(c: int, m: String) -> void: session_errors.append([c, m]))
	s.start()
	var good := _hex("A4 09 4E 05 19 01 5A 10 27 FA 00 30 59")
	assert_eq(good, _msg([0x19, 0x01, 0x5A, 0x10, 0x27, 0xFA, 0x00, 0x30]), "фикстура п.4 (а) с верной CS")
	_notify(NEO, good)
	s.tick(1.0)
	assert_eq(s.samples.power_w[0], 250, "п.4 (а): 250 Вт")
	assert_eq(s.samples.cadence_rpm[0], 90, "п.4 (а): 90 об/мин")
	# Те же сообщения, но 400 Вт / 60 об/мин и испорченные — не должны менять поток.
	var bad_base := _msg([0x19, 0x01, 60, 0x10, 0x27, 0x90, 0x01, 0x30])
	var bads: Array[PackedByteArray] = []
	var cs_bad := bad_base.duplicate()
	cs_bad[12] = cs_bad[12] ^ 0x01
	bads.append(cs_bad)
	var len_byte := bad_base.duplicate()
	len_byte[1] = 0x08
	bads.append(len_byte)
	bads.append(bad_base.slice(0, 12))
	var sync := bad_base.duplicate()
	sync[0] = 0xA5
	bads.append(sync)
	bads.append(_msg([0x19, 0x01, 60, 0x10, 0x27, 0x90, 0x01, 0x30], 0x4D))  # ID не 4E/4F
	# Из критерия: (а) с CS 58, с байтом 1 = 08, обрезанное, с A5.
	bads.append(_hex("A4 09 4E 05 19 01 5A 10 27 FA 00 30 58"))
	bads.append(_hex("A4 08 4E 05 19 01 5A 10 27 FA 00 30 59"))
	bads.append(_hex("A4 09 4E 05 19 01 5A 10 27 FA 00 30"))
	bads.append(_hex("A5 09 4E 05 19 01 5A 10 27 FA 00 30 59"))
	for b in bads:
		_notify(NEO, b)
		s.tick(1.0)
		var k := s.samples.size() - 1
		assert_true(s.samples.power_w[k] != 400, "испорченное %s не принято (мощность %d)" % [_to_hex(b), s.samples.power_w[k]])
		assert_true(s.samples.cadence_rpm[k] != 60, "испорченное %s не принято (каденс)" % _to_hex(b))
	assert_eq(s.get_state(), WorkoutSession.State.RUNNING, "сессия продолжается")
	assert_eq(s.samples.size(), 1 + bads.size(), "сэмплы пишутся")
	assert_eq(session_errors, [], "сигнала ошибки нет")
	# Канал не проверяется; страница 0x50 игнорируется без ошибки.
	_notify(NEO, _msg([0x19, 0x01, 70, 0x10, 0x27, 0x2C, 0x01, 0x30], 0x4F, 0x07))
	s.tick(1.0)
	assert_eq(s.samples.power_w[s.samples.size() - 1], 300, "ID 4F и другой канал — принято")
	_notify(NEO, _msg([0x50, 0xFF, 0xFF, 0x01, 0x20, 0x00, 0x01, 0x00]))
	s.tick(1.0)
	assert_eq(session_errors, [], "прочие страницы — без ошибки")


func test_req_dev_11_c4_b_c_1234w_and_no_data_is_not_zero() -> void:
	var t := _trainer()
	var got: Array[TrainerSample] = []
	t.telemetry.connect(func(s: TrainerSample) -> void: got.append(s))
	_notify(NEO, _hex("A4 09 4E 05 19 02 50 00 00 D2 14 30 5B"))
	t.tick(1.0)
	assert_false(got.is_empty())
	if not got.is_empty():
		assert_eq(got.back().power_w, 1234, "п.4 (б): 1234 Вт, статус не влияет")
		assert_eq(got.back().cadence_rpm, 80)
	_notify(NEO, _msg([0x19, 0x03, 0xFF, 0x00, 0x00, 0xFF, 0x0F, 0x30]))
	t.tick(1.0)
	if not got.is_empty():
		assert_false(got.back().has_power and got.back().power_w == 0xFFF, "0xFFF — не мощность")
		assert_false(got.back().has_power, "п.4 (в): мощность «нет данных», не 0")
		assert_false(got.back().has_cadence, "п.4 (в): каденс «нет данных»")


func test_req_dev_11_c5_speed_not_in_sample_hr_below_hrs() -> void:
	var t := _trainer()
	var s := WorkoutSession.new(Workout.make("p", [WorkoutStep.watts(20, 200.0)] as Array[WorkoutStep]), t, 200, 1.0, 75.0)
	s.start()
	for i in 10:
		_notify(NEO, _trainer_data(200, 90))
		_notify(NEO, _hex("A4 09 4E 05 10 19 00 00 40 1F FF 34 7B"))  # 28.80 км/ч, пульса нет
		s.tick(1.0)
	var ref := SpeedModel.new()
	for i in s.samples.size():
		assert_almost_eq(s.samples.speed_kmh[i], ref.step(200.0, 75.0, 1.0), 0.01, "скорость сэмпла — модель, не 28.80")
	var k_last := s.samples.size() - 1
	assert_false(s.samples.has_heart_rate[k_last], "байт 6 = FF — пульса нет (значение %d)" % s.samples.heart_rate_bpm[k_last])
	# Пульс станка 140 без HRS → 140; с HRS 120 → 120 (DEV-03 п.3).
	var page_hr := _msg([0x10, 0x19, 0x00, 0x00, 0x40, 0x1F, 140, 0x34])
	_notify(NEO, page_hr)
	_notify(NEO, _trainer_data(200, 90))
	s.tick(1.0)
	assert_eq(s.samples.heart_rate_bpm[s.samples.size() - 1], 140, "пульс станка без HRS")
	var hub := SensorHub.new(t)
	_disposables.push_front(hub)
	_bridge.set_device_services("hrs", {"180D": PackedStringArray(["2A37"])})
	var hrs := BleHeartRateSensor.new(_bridge)
	_disposables.append(hrs)
	hub.set_heart_rate_sensor(hrs)
	hrs.connect_device("hrs")
	_bridge.pump()
	var hrs_seen: Array[int] = []
	hub.heart_rate.connect(func(b: int) -> void: hrs_seen.append(b))
	for i in 3:
		_bridge.emit_notification("hrs", "2A37", PackedByteArray([0x00, 120]))
		_notify(NEO, page_hr)
		hub.tick(1.0)
	assert_false(hrs_seen.is_empty())
	if not hrs_seen.is_empty():
		assert_eq(hrs_seen.back(), 120, "HRS главнее пульса станка")
		assert_false(hrs_seen.has(140), "пульс станка не перебивает HRS")


# ===========================================================================
# REQ-DEV-11 п.6 — ERG 0x31; п.8 — диапазон; WRK-02 п.2
# ===========================================================================

func test_req_dev_11_c6_plan_targets_exact_bytes_within_1s_of_boundary() -> void:
	var t := _trainer()
	var plan := Workout.make("p", [WorkoutStep.watts(10, 150.0), WorkoutStep.watts(10, 250.0), WorkoutStep.watts(10, 130.0),
		WorkoutStep.watts(10, 2400.0)] as Array[WorkoutStep])
	var s := WorkoutSession.new(plan, t, 200)
	s.start()
	_bridge.pump()
	var at_tick: Dictionary = {}  # число записей 0x31 → секунда, на которой появилась
	var sec := 0
	while s.get_state() != WorkoutSession.State.FINISHED:
		_notify(NEO, _trainer_data(150, 85))
		for k in 4:
			s.tick(0.25)
			_bridge.pump()
			var n := 0
			for w in _fec3_writes():
				if w[4] == 0x31:
					n += 1
			if not at_tick.has(n):
				at_tick[n] = sec + 0.25 * (k + 1)
		sec += 1
	var targets: Array[String] = []
	for w in _fec3_writes():
		if w[4] == 0x31:
			targets.append(_to_hex(w))
	gut.p("0x31: %s; момент записи (число 0x31 → с): %s" % [str(targets), str(at_tick)])
	assert_true(targets.has("A4 09 4F 05 31 FF FF FF FF FF 58 02 73"), "150 Вт — байты критерия")
	assert_true(targets.has("A4 09 4F 05 31 FF FF FF FF FF E8 03 C2"), "250 Вт — байты критерия")
	var has_130 := false
	var has_2000 := false
	for h in targets:
		if h.begins_with("A4 09 4F 05 31 FF FF FF FF FF 08 02"):
			has_130 = true
		if h.begins_with("A4 09 4F 05 31 FF FF FF FF FF 40 1F"):
			has_2000 = true
	assert_true(has_130, "130 Вт — байты 6–7 08 02")
	assert_true(has_2000, "2400 Вт ограничено до 2000 — 40 1F (п.8)")
	assert_true(at_tick.has(2) and float(at_tick[2]) <= 11.0 + 1e-6, "250 Вт записано не позже 1 с после 10-й с (%s)" % str(at_tick.get(2)))
	assert_true(at_tick.has(3) and float(at_tick[3]) <= 21.0 + 1e-6, "130 Вт — не позже 21-й с (%s)" % str(at_tick.get(3)))
	for w in _fec3_writes():
		assert_eq(w.size(), 13)
		var cs := 0
		for i in 12:
			cs ^= w[i]
		assert_eq(w[12], cs, "CS = XOR 12 байт: %s" % _to_hex(w))


# ===========================================================================
# REQ-DEV-11 п.7 — повтор и подтверждение
# ===========================================================================

func test_req_dev_11_c7a_one_retry_same_bytes_on_write_failure() -> void:
	var t := _trainer()
	_bridge.pump()
	var before := _fec3_writes().size()
	_bridge.fail_next_write()
	t.set_target_power(150)
	for i in 4:
		_bridge.pump()
		t.tick(0.1)
	var after := _fec3_writes().slice(before)
	var p31: Array[String] = []
	for w in after:
		if w[4] == 0x31:
			p31.append(_to_hex(w))
	assert_eq(p31.size(), 2, "один повтор: %s" % str(p31))
	if p31.size() == 2:
		assert_eq(p31[0], p31[1], "повтор тех же байт")


func test_req_dev_11_c7b_status_47_after_each_31_not_supported_disables_erg() -> void:
	var t := _trainer()
	var errors: Array = []
	t.error.connect(func(c: int, m: String) -> void: errors.append([c, m]))
	t.set_target_power(150)
	t.tick(0.1)
	_bridge.pump()
	var w := _fec3_writes()
	var idx31 := -1
	for i in w.size():
		if w[i][4] == 0x31:
			idx31 = i
	assert_gt(idx31, -1)
	assert_true(idx31 + 1 < w.size() and w[idx31 + 1][4] == 0x46 and w[idx31 + 1][10] == 0x47 and w[idx31 + 1][11] == 0x01,
		"после 0x31 — запрос 0x46 с байтом 6 = 47, байт 7 = 01")
	# Pass — без ошибки.
	_notify(NEO, _msg([0x47, 0x31, 0xFF, 0x00, 0xFF, 0xFF, 0xFF, 0xFF]))
	t.tick(0.1)
	assert_eq(errors, [], "Pass — ошибки нет")
	# Fail → ошибка команды.
	t.set_target_power(160)
	t.tick(0.1)
	_bridge.pump()
	_notify(NEO, _msg([0x47, 0x31, 0xFF, 0x01, 0xFF, 0xFF, 0xFF, 0xFF]))
	t.tick(0.1)
	assert_eq(errors.size(), 1, "Fail — ошибка команды")
	# Нет ответа 2 с — не ошибка.
	t.set_target_power(170)
	for i in 25:
		t.tick(0.1)
		_bridge.pump()
	assert_eq(errors.size(), 1, "нет ответа — не ошибка пользователю")
	# Байт 1 ≠ 31 — не считается ответом.
	t.set_target_power(175)
	t.tick(0.1)
	_bridge.pump()
	_notify(NEO, _msg([0x47, 0x30, 0xFF, 0x03, 0xFF, 0xFF, 0xFF, 0xFF]))
	t.tick(0.1)
	assert_eq(errors.size(), 1, "статус чужой команды (байт 1 = 30) — не ошибка ERG")
	for i in 25:
		t.tick(0.1)
	# Not supported → ERG недоступен, следующих 0x31 нет.
	t.set_target_power(180)
	t.tick(0.1)
	_bridge.pump()
	_notify(NEO, _msg([0x47, 0x31, 0xFF, 0x02, 0xFF, 0xFF, 0xFF, 0xFF]))
	t.tick(0.1)
	assert_eq(errors.size(), 2, "Not supported — сообщение")
	var n31 := 0
	for x in _fec3_writes():
		if x[4] == 0x31:
			n31 += 1
	t.set_target_power(220)
	t.set_target_power(230)
	for i in 5:
		t.tick(0.5)
		_bridge.pump()
	var n31_after := 0
	for x in _fec3_writes():
		if x[4] == 0x31:
			n31_after += 1
	assert_eq(n31_after, n31, "после Not supported записей 0x31 нет")


# ===========================================================================
# REQ-DEV-11 п.8 — возможности; FRD-04 п.6 (приложение, свободная езда)
# ===========================================================================

func test_req_dev_11_c8_frd_04_c6_caps_without_sim_free_ride_no_33_and_message() -> void:
	var t := _trainer(0x03)
	var fr := FreeRideSession.new(t, RouteCatalog.MOUNTAINS, 50, 75.0, 200)
	_disposables.push_front(fr)
	var events: Array = []
	fr.start()
	for i in 30:
		_notify(NEO, _trainer_data(200, 90))
		fr.tick(1.0)
		_bridge.pump()
	assert_false(_mode_pages().has(0x33), "SIM нет — ни одной 0x33: %s" % str(_mode_pages()))
	assert_false(_mode_pages().has(0x32), "и ни одной 0x32")
	assert_true(_mode_pages().has(0x30), "переход на фиксированное сопротивление (FRD-04 п.6)")
	for e in fr.events:
		events.append(str(e.get("type", "")))
	gut.p("события: %s" % str(events))
	assert_eq(fr.mode(), SimController.Mode.FIXED, "режим — сопротивление")


func test_req_dev_11_c8_without_target_power_bit_plan_has_no_31() -> void:
	var t := _trainer(0x05)
	var s := WorkoutSession.new(Workout.make("p", [WorkoutStep.watts(5, 150.0), WorkoutStep.watts(5, 250.0)] as Array[WorkoutStep]), t, 200)
	s.start()
	while s.get_state() != WorkoutSession.State.FINISHED:
		s.tick(1.0)
		_bridge.pump()
	assert_false(_mode_pages().has(0x31), "без бита 1 — ни одной 0x31")


# ===========================================================================
# REQ-DEV-11 п.9 — сопротивление, SIM, переподключение и пауза
# ===========================================================================

func test_req_dev_11_c9a_basic_resistance_bytes() -> void:
	var t := _trainer()
	t.set_erg_enabled(false)
	var got: Array[String] = []
	for pct in [50, 0, 35, 100]:
		t.set_resistance_level(pct)
		t.tick(0.1)
		_bridge.pump()
		var w := _fec3_writes()
		got.append(_to_hex(w.back()))
	assert_eq(got[0], "A4 09 4F 05 30 FF FF FF FF FF FF 64 B3", "50 %")
	assert_eq(got[1].substr(33, 2), "00", "0 %% → 00: %s" % got[1])
	assert_eq(got[2].substr(33, 2), "46", "35 %% → 46: %s" % got[2])
	assert_eq(got[3].substr(33, 2), "C8", "100 %% → C8: %s" % got[3])


func test_req_dev_11_c9b_sim_track_bytes_and_wind_page_before_first_33_on_each_entry() -> void:
	var t := _trainer()
	var expected := {5.0: "A4 09 4F 05 33 FF FF FF FF 14 50 50 C0", -3.0: "F4 4C", 0.0: "20 4E", 12.34: "F2 52"}
	var got33: Array[String] = []
	for g in [5.0, -3.0, 0.0, 12.34]:
		t.set_simulation(g)
		t.tick(0.1)
		_bridge.pump()
		for w in _fec3_writes():
			if w[4] == 0x33:
				got33.append(_to_hex(w))
	assert_true(got33.has(expected[5.0]), "5.00 %% — байты критерия: %s" % str(got33))
	for g in [-3.0, 0.0, 12.34]:
		var found := false
		for h in got33:
			if h.substr(27, 5) == expected[g]:
				found = true
		assert_true(found, "%.2f %% → байты 5–6 %s: %s" % [g, expected[g], str(got33)])
	var pages := _mode_pages()
	assert_eq(pages.find(0x32), pages.find(0x33) - 1, "0x32 сразу перед первой 0x33: %s" % str(pages))
	assert_eq(pages.count(0x32), 1, "0x32 один раз при входе в SIM")
	for w in _fec3_writes():
		if w[4] == 0x32:
			assert_eq(_to_hex(w.slice(4, 12)), "32 FF FF FF FF 14 7F 64", "страница 0x32")
	# Возврат из фиксированного режима — снова 0x32 перед 0x33.
	t.set_resistance_level(40)
	t.tick(0.1)
	_bridge.pump()
	t.set_simulation(2.0)
	t.tick(0.1)
	_bridge.pump()
	pages = _mode_pages()
	gut.p("страницы: %s" % str(pages))
	assert_eq(pages.count(0x32), 2, "после фиксированного режима — снова 0x32")
	assert_eq(pages[pages.size() - 2], 0x32)
	assert_eq(pages[pages.size() - 1], 0x33)


func test_req_dev_11_c9c_reconnect_running_resubscribe_and_target_within_1s_no_request_control() -> void:
	var t := _trainer()
	var s := WorkoutSession.new(Workout.make("p", [WorkoutStep.watts(120, 150.0)] as Array[WorkoutStep]), t, 200)
	s.start()
	for i in 5:
		_notify(NEO, _trainer_data(150, 85))
		s.tick(1.0)
		_bridge.pump()
	var subs_before := _calls_for_char("subscribe", FEC2)
	var writes_before := _fec3_writes().size()
	_bridge.emit_disconnected(NEO)
	_bridge.pump()
	var t_conn := -1.0
	var t_cmd := -1.0
	var clock := 0.0
	for i in 100:
		s.tick(0.1)
		clock += 0.1
		_bridge.pump()
		if t_conn < 0.0 and t.get_connection_state() == TrainerDevice.ConnectionState.CONNECTED:
			t_conn = clock
		if t_conn >= 0.0 and t_cmd < 0.0:
			for w in _fec3_writes().slice(writes_before):
				if w[4] == 0x31:
					t_cmd = clock
		if t_cmd >= 0.0:
			break
	assert_gt(t_conn, 0.0, "переподключился")
	assert_gt(_calls_for_char("subscribe", FEC2), subs_before, "повторная подписка на FEC2")
	assert_true(t_cmd >= 0.0 and t_cmd - t_conn <= 1.0 + 1e-6, "цель 0x31 не позже 1 с после connected (%.1f → %.1f)" % [t_conn, t_cmd])
	assert_eq(_calls_for_char("write", BleUuids.FTMS_CONTROL_POINT), 0, "FTMS Request Control не уходит")


func test_req_dev_11_c9c_reconnect_on_pause_only_subscribe_target_after_resume() -> void:
	var t := _trainer()
	var s := WorkoutSession.new(Workout.make("p", [WorkoutStep.watts(120, 150.0)] as Array[WorkoutStep]), t, 200)
	s.start()
	for i in 5:
		s.tick(1.0)
		_bridge.pump()
	s.pause()
	_bridge.pump()
	var writes_at_pause := _fec3_writes().size()
	_bridge.emit_disconnected(NEO)
	_bridge.pump()
	for i in 80:
		s.tick(0.1)
		_bridge.pump()
	assert_eq(t.get_connection_state(), TrainerDevice.ConnectionState.CONNECTED, "переподключился на паузе")
	var on_pause := _fec3_writes().slice(writes_at_pause)
	var mode_on_pause := 0
	for w in on_pause:
		if w[4] in [0x30, 0x31, 0x32, 0x33]:
			mode_on_pause += 1
	assert_eq(mode_on_pause, 0, "на паузе записей режима на FEC3 нет: %s" % str(on_pause.map(_to_hex)))
	s.resume()
	var got := false
	for i in 10:
		s.tick(0.1)
		_bridge.pump()
		for w in _fec3_writes().slice(writes_at_pause):
			if w[4] == 0x31:
				got = true
	assert_true(got, "после resume цель не позже 1 с")


# ===========================================================================
# REQ-DEV-10 п.2 (регрессия T-167; DEV-11 п.10): литералы моделей и производителей
# ===========================================================================

func test_req_dev_10_c2_dev_11_c10_no_model_or_vendor_literals_in_devices_and_session() -> void:
	var offenders: Array[String] = []
	var re := RegEx.create_from_string("\"[^\"]*\"")
	for root in ["res://src/devices/", "res://src/session/"]:
		_scan_literals(root, re, offenders)
	assert_eq(offenders, [] as Array[String], "DEV-10 п.2: в строковых литералах нет названий моделей/производителей")


func _scan_literals(dir_path: String, re: RegEx, out: Array[String]) -> void:
	var d := DirAccess.open(dir_path)
	if d == null:
		return
	for f in d.get_files():
		if not f.ends_with(".gd"):
			continue
		var n := 0
		for line in FileAccess.get_file_as_string(dir_path.path_join(f)).split("\n"):
			n += 1
			if line.strip_edges().begins_with("#"):
				continue
			for m in re.search_all(line):
				var lit := m.get_string().to_lower()
				for needle in ["tacx", "neo", "wahoo", "kickr", "elite", "saris", "jetblack", "wattbike"]:
					if lit.contains(needle):
						out.append("%s:%d %s" % [dir_path.path_join(f), n, m.get_string()])
	for sub in d.get_directories():
		_scan_literals(dir_path.path_join(sub), re, out)
