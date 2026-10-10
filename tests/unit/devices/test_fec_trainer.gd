extends GutTest
## T-167: станок по FE-C over BLE — определение, подключение, данные (REQ-DEV-11 п.1–5; REQ-WRK-09
## п.1, п.4; регрессия DEV-04 п.4, DEV-05 п.2–3, DEV-06, DEV-10 п.1–2). `StubBleBridge` + фикстура
## `tests/fixtures/fec/neo_fec.json` (сервисы Neo владельца по журналу «BLE-отладки»).

const FIXTURE: String = "res://tests/fixtures/fec/neo_fec.json"
const CONNECTED: int = TrainerDevice.ConnectionState.CONNECTED
const PROPRIETARY: String = "669AA501-0C08-969E-E211-86AD5062675F"

var _fx: Dictionary = {}
var _dir: String
var _bridge: StubBleBridge
var _cm: ConnectionManager


func before_all() -> void:
	_fx = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))


func before_each() -> void:
	_dir = "user://test_fec_trainer_%d_%d/" % [Time.get_ticks_usec(), randi() % 100000]
	_bridge = StubBleBridge.new()
	_cm = ConnectionManager.new(_bridge, RememberedDevices.new(_dir), TrainerFactory.KIND_BLE)
	_cm.set_profile("p")


func after_each() -> void:
	if _cm != null:
		_cm.dispose()
		_cm = null
	if _bridge != null:
		_bridge.dispose()
	_remove_tree(ProjectSettings.globalize_path(_dir))


static func _remove_tree(abs_path: String) -> void:
	if not DirAccess.dir_exists_absolute(abs_path):
		return
	var d := DirAccess.open(abs_path)
	for f in d.get_files():
		DirAccess.remove_absolute(abs_path.path_join(f))
	for sub in d.get_directories():
		_remove_tree(abs_path.path_join(sub))
	DirAccess.remove_absolute(abs_path)


func _bytes(key: String) -> PackedByteArray:
	return BleBytes.from_hex(str(_fx[key]).replace(" ", ""))


## Сервисы фикстуры; `drop_chars` — убрать характеристики (нет FEC2 / FEC3).
func _services(drop_chars: Array[String] = [], with_ftms: bool = false) -> Dictionary:
	var out: Dictionary = {}
	var src: Dictionary = _fx["services"]
	for s: String in src:
		var chars := PackedStringArray()
		for c: String in src[s]:
			if not drop_chars.has(c):
				chars.append(c)
		out[s] = chars
	if with_ftms:
		out[BleUuids.FTMS_SERVICE] = PackedStringArray([BleUuids.INDOOR_BIKE_DATA, BleUuids.FTMS_CONTROL_POINT, BleUuids.FTMS_STATUS])
	return out


func _advert() -> PackedStringArray:
	return PackedStringArray(_fx["advert_services"])


func _trainer() -> BleTrainer:
	return _cm.trainer as BleTrainer


## Вызовы моста по устройству `id` без id (для сравнения журналов разных устройств).
func _journal(id: String) -> Array:
	var out: Array = []
	for c in _bridge.calls:
		if str(c.get("id", "")) == id:
			var copy: Dictionary = c.duplicate()
			copy.erase("id")
			out.append(copy)
	return out


## Ответ станка на запрос возможностей 0x36 (T-168): с FEC3 подключение ждёт его до 2 с.
func _answer_caps(id: String, bits: int = 0x07) -> void:
	for c in _bridge.calls_of("write"):
		var b: PackedByteArray = c.get("bytes", PackedByteArray())
		if str(c.get("id", "")) == id and b.size() == FecCodec.MESSAGE_LENGTH and b[4] == FecCodec.PAGE_REQUEST \
				and b[10] == FecCodec.PAGE_CAPABILITIES:
			_bridge.emit_notification(id, BleUuids.FEC_NOTIFY, FecCodec.encode_message(
				PackedByteArray([FecCodec.PAGE_CAPABILITIES, 0xFF, 0xFF, 0xFF, 0xFF, 0, 0, bits]), FecCodec.ANT_BROADCAST_DATA))
			_bridge.pump()
			return


func _calls_on(id: String, method: String, char_uuid: String) -> int:
	var n := 0
	for c in _bridge.calls_of(method):
		if str(c.get("id", "")) == id and BleUuids.normalize(str(c.get("char", ""))) == BleUuids.normalize(char_uuid):
			n += 1
	return n


func _calls_on_service(id: String, service_uuid: String) -> int:
	var n := 0
	for c in _bridge.calls:
		if str(c.get("id", "")) == id and BleUuids.normalize(str(c.get("service", ""))) == BleUuids.normalize(service_uuid):
			n += 1
	return n


# ---------------------------------------------------------------------------
# REQ-DEV-11 п.1 — тип «станок» по сервисам
# ---------------------------------------------------------------------------

func test_req_dev_11_c1_a_fec_in_advert_is_trainer_regardless_of_name_same_journal() -> void:
	_cm.start_scan()
	var journals: Array = []
	var names: Array[String] = ["Tacx Neo 11565", "Tacx Flux 2", ""]
	for i in names.size():
		var id := "fec%d" % i
		_bridge.set_device_services(id, _services())
		_cm.start_scan()  # подключение останавливает сканирование (DEV-01 п.4)
		_bridge.emit_device_found(id, names[i], -60, PackedStringArray([BleUuids.FEC_SERVICE]))
		assert_eq(_cm.scanner.find(id)["kind"], RememberedDevices.KIND_TRAINER, "«%s» — станок" % names[i])
		_cm.connect_trainer(id)
		_bridge.pump()
		_answer_caps(id)
		assert_eq(_cm.state_of(id), CONNECTED, "«%s» подключён по FE-C" % names[i])
		journals.append(_journal(id))
		_cm.disconnect_device(id)
		_bridge.pump()
	assert_eq(journals[1], journals[0], "журнал не зависит от имени")
	assert_eq(journals[2], journals[0], "и без имени")


func test_req_dev_11_c1_b_cadence_by_advert_becomes_trainer_after_services() -> void:
	var id := "neo"
	_cm.start_scan()
	_bridge.set_device_services(id, _services())
	_bridge.emit_device_found(id, str(_fx["name"]), -60, PackedStringArray([BleUuids.CSC_SERVICE]))
	assert_eq(_cm.scanner.find(id)["kind"], RememberedDevices.KIND_CADENCE, "по рекламе — каденс")
	_cm.connect_sensor(id, RememberedDevices.KIND_CADENCE)
	_bridge.pump()
	_answer_caps(id)
	assert_eq(_cm.scanner.find(id)["kind"], RememberedDevices.KIND_TRAINER, "после services_discovered — станок")
	assert_eq(_cm.trainer_id, id)
	assert_eq(_trainer().get_connection_state(), CONNECTED, "подключён как станок")
	assert_false(_cm.sensor_ids.values().has(id), "среди датчиков его нет")
	assert_eq(_cm.remembered.trainer().get("id", ""), id, "запомнен как станок")
	for d in _cm.remembered.sensors("p"):
		assert_ne(d["id"], id, "в датчиках профиля его нет")
	var states := _cm.device_states()
	assert_eq(states[id]["kind"], RememberedDevices.KIND_TRAINER, "одна строка на id — станок")
	assert_eq(_calls_on(id, "subscribe", BleUuids.CSC_MEASUREMENT), 0, "нет подписки на 2A5B")
	assert_eq(_calls_on(id, "subscribe", BleUuids.CYCLING_POWER_MEASUREMENT), 0, "нет подписки на 2A63")
	assert_eq(_bridge.calls_of("connect_peripheral").size(), 1, "связь не переустанавливалась")
	assert_eq(_bridge.calls_of("disconnect_peripheral").size(), 0)


func test_req_dev_11_c1_b_previously_remembered_as_cadence_is_replaced_by_trainer() -> void:
	var id := "neo"
	_cm.remembered.remember("p", RememberedDevices.make_device(id, "Neo", RememberedDevices.KIND_CADENCE))
	_bridge.set_device_services(id, _services())
	_cm.connect_sensor(id, RememberedDevices.KIND_CADENCE)
	_bridge.pump()
	_answer_caps(id)
	assert_eq(_cm.remembered.find("p", id).get("kind", ""), RememberedDevices.KIND_TRAINER)
	assert_eq(_cm.remembered.sensors("p").size(), 0)


func test_req_dev_11_c1_c_other_csc_and_cps_sensors_connect_as_before() -> void:
	_bridge.set_device_services("neo", _services())
	_cm.connect_trainer("neo")
	_bridge.set_device_services("csc", {BleUuids.CSC_SERVICE: PackedStringArray([BleUuids.CSC_MEASUREMENT])})
	_bridge.set_device_services("pm", {BleUuids.CPS_SERVICE: PackedStringArray([BleUuids.CYCLING_POWER_MEASUREMENT])})
	_cm.connect_sensor("csc", RememberedDevices.KIND_CADENCE)
	_cm.connect_sensor("pm", RememberedDevices.KIND_POWER)
	_bridge.pump()
	_answer_caps("neo")
	assert_eq(_cm.state_of("neo"), CONNECTED)
	assert_eq(_cm.state_of("csc"), CONNECTED)
	assert_eq(_cm.state_of("pm"), CONNECTED)
	assert_eq(_calls_on("csc", "subscribe", BleUuids.CSC_MEASUREMENT), 1)
	assert_eq(_calls_on("pm", "subscribe", BleUuids.CYCLING_POWER_MEASUREMENT), 1)
	assert_eq(_calls_on("neo", "subscribe", BleUuids.CSC_MEASUREMENT) + _calls_on("neo", "subscribe", BleUuids.CYCLING_POWER_MEASUREMENT), 0)


func test_req_dev_11_c1_g_ftms_and_fec_connects_by_ftms() -> void:
	_bridge.set_device_services("both", _services([], true))
	_cm.connect_trainer("both")
	_bridge.pump()
	_answer_caps("both")
	_bridge.pump()
	assert_eq(_cm.state_of("both"), CONNECTED)
	assert_eq(_trainer().protocol, BleTrainer.PROTOCOL_FTMS)
	assert_eq(_calls_on_service("both", BleUuids.FEC_SERVICE), 0, "ни subscribe, ни write на FEC1")
	assert_gt(_calls_on("both", "subscribe", BleUuids.INDOOR_BIKE_DATA), 0, "данные по FTMS")


func test_req_dev_11_c1_d_proprietary_service_untouched() -> void:
	_bridge.set_device_services("neo", _services())
	_cm.connect_trainer("neo")
	_bridge.pump()
	_answer_caps("neo")
	_bridge.emit_notification("neo", BleUuids.FEC_NOTIFY, _bytes("trainer_data_250w_90rpm"))
	_cm.tick(2.0)
	assert_eq(_calls_on_service("neo", PROPRIETARY), 0, "ни одного обращения к фирменному сервису")


# ---------------------------------------------------------------------------
# REQ-DEV-11 п.2 — подключение; WRK-09 п.1, п.4
# ---------------------------------------------------------------------------

func test_req_dev_11_c2_subscribes_fec2_only_no_request_control() -> void:
	_bridge.set_device_services("neo", _services())
	_cm.connect_trainer("neo")
	_bridge.pump()
	_answer_caps("neo")
	assert_eq(_cm.state_of("neo"), CONNECTED)
	assert_eq(_trainer().protocol, BleTrainer.PROTOCOL_FEC)
	var subs := _bridge.calls_of("subscribe")
	assert_eq(subs.size(), 1, "одна подписка")
	assert_eq(BleUuids.normalize(str(subs[0]["char"])), BleUuids.FEC_NOTIFY, "на FEC2")
	var writes := _bridge.calls_of("write")
	assert_eq(writes.size(), 1, "одна запись — запрос возможностей 0x36 (п.2, п.8); Request Control нет")
	assert_eq(BleUuids.normalize(str(writes[0]["char"])), BleUuids.FEC_WRITE)
	assert_eq(writes[0]["bytes"], FecCodec.encode_request_page(FecCodec.PAGE_CAPABILITIES))
	assert_true(_trainer().has_control(), "с FEC3 — управляемый станок (T-168)")


func test_req_dev_11_c2_without_fec2_not_connected_with_error() -> void:
	_bridge.set_device_services("neo", _services(["6E40FEC2-B5A3-F393-E0A9-E50E24DCCA9E"]))
	var errors: Array[int] = []
	_trainer().error.connect(func(code: int, _m: String) -> void: errors.append(code))
	_cm.connect_trainer("neo")
	_bridge.pump()
	_answer_caps("neo")
	assert_ne(_cm.state_of("neo"), CONNECTED, "без FEC2 — не «подключено»")
	assert_has(errors, TrainerDevice.ErrorCode.CONNECTION_FAILED, "ошибка подключения")
	assert_ne(_cm.failure_of("neo"), SensorDevice.FailureReason.NONE, "причина на экране устройств")
	assert_eq(_calls_on_service("neo", BleUuids.FEC_SERVICE), 0, "ни подписок, ни записей на FEC1")


func test_req_dev_11_c2_wrk_09_c1_without_fec3_data_only_power_meter_session() -> void:
	_bridge.set_device_services("neo", _services(["6E40FEC3-B5A3-F393-E0A9-E50E24DCCA9E"]))
	_cm.connect_trainer("neo")
	_bridge.pump()
	_answer_caps("neo")
	assert_eq(_cm.state_of("neo"), CONNECTED, "только данные — подключён")
	var check := _cm.start_check()
	assert_true(check["allowed"])
	assert_eq(check["mode"], TrainerDevice.MODE_POWER_METER, "сессия power_meter (WRK-09 п.1 (б))")
	assert_eq(check["power_source"], SensorHub.SOURCE_TRAINER)
	var dev := _cm.session_device()
	var s := WorkoutSession.new(Workout.make("p", [WorkoutStep.watts(10, 200.0), WorkoutStep.watts(10, 250.0)] as Array[WorkoutStep]), dev, 200)
	_cm.ticks_devices = false
	s.start()
	while s.get_state() != WorkoutSession.State.FINISHED:
		_bridge.emit_notification("neo", BleUuids.FEC_NOTIFY, _bytes("trainer_data_250w_90rpm"))
		s.tick(1.0)
	assert_eq(s.samples.power_w[s.samples.size() - 1], 250, "мощность станка FE-C")
	assert_eq(s.samples.cadence_rpm[s.samples.size() - 1], 90)
	assert_eq(_bridge.calls_of("write").size(), 0, "ни одной записи (WRK-09 п.4)")
	var subs := _bridge.calls_of("subscribe")
	assert_eq(subs.size(), 1, "подписка только на FEC2")
	_cm.release_session_device()


# ---------------------------------------------------------------------------
# REQ-DEV-11 п.3–5 — данные
# ---------------------------------------------------------------------------

func _connected_trainer_samples() -> Array[TrainerSample]:
	_bridge.set_device_services("neo", _services())
	_cm.connect_trainer("neo")
	_bridge.pump()
	_answer_caps("neo")
	var got: Array[TrainerSample] = []
	_trainer().telemetry.connect(func(s: TrainerSample) -> void: got.append(s))
	return got


func test_req_dev_11_c4_power_cadence_and_no_data() -> void:
	var got := _connected_trainer_samples()
	_bridge.emit_notification("neo", BleUuids.FEC_NOTIFY, _bytes("trainer_data_250w_90rpm"))
	_bridge.emit_notification("neo", BleUuids.FEC_NOTIFY, _bytes("trainer_data_1234w_80rpm"))
	_bridge.emit_notification("neo", BleUuids.FEC_NOTIFY,
		FecCodec.encode_message(BleBytes.from_hex(str(_fx["trainer_data_no_data_page"]).replace(" ", "")), FecCodec.ANT_BROADCAST_DATA))
	assert_eq(got.size(), 3)
	assert_eq([got[0].power_w, got[0].cadence_rpm], [250, 90])
	assert_eq([got[1].power_w, got[1].cadence_rpm], [1234, 80])
	assert_false(got[2].has_power, "нет данных, не 0")
	assert_false(got[2].has_cadence)


func test_req_dev_11_c3_invalid_messages_dropped_session_goes_on() -> void:
	_bridge.set_device_services("neo", _services())
	_cm.connect_trainer("neo")
	_bridge.pump()
	_answer_caps("neo")
	var dev := _cm.session_device()
	var s := WorkoutSession.new(Workout.make("p", [WorkoutStep.watts(30, 200.0)] as Array[WorkoutStep]), dev, 200)
	var errors: Array[int] = []
	dev.error.connect(func(c: int, _m: String) -> void: errors.append(c))
	_cm.ticks_devices = false
	s.start()
	var good := _bytes("trainer_data_250w_90rpm")
	# Испорченные копии сообщения 1234 Вт / 80 об/мин: будь они приняты, сэмпл показал бы 1234.
	var other := _bytes("trainer_data_1234w_80rpm")
	var bad: Array[PackedByteArray] = []
	var b1 := other.duplicate()
	b1[12] = 0x5A
	var b2 := other.duplicate()
	b2[1] = 0x08
	var b3 := other.slice(0, 12)
	var b4 := other.duplicate()
	b4[0] = 0xA5
	bad.append_array([b1, b2, b3, b4])
	for i in 4:
		_bridge.emit_notification("neo", BleUuids.FEC_NOTIFY, good)
		s.tick(1.0)
	for b in bad:
		_bridge.emit_notification("neo", BleUuids.FEC_NOTIFY, good)
		_bridge.emit_notification("neo", BleUuids.FEC_NOTIFY, b)
		s.tick(1.0)
	var st := s.samples
	assert_eq(st.size(), 8, "сэмплы пишутся")
	for i in range(4, 8):
		assert_eq(st.power_w[i], 250, "сэмпл %d: мощность не изменилась" % i)
		assert_eq(st.cadence_rpm[i], 90)
	assert_eq(s.get_state(), WorkoutSession.State.RUNNING, "сессия продолжается")
	assert_eq(errors, [] as Array[int], "сигнала ошибки нет")
	_cm.release_session_device()


func test_req_dev_11_c5_speed_not_in_session_heart_rate_below_hrs() -> void:
	var got := _connected_trainer_samples()
	_bridge.emit_notification("neo", BleUuids.FEC_NOTIFY, _bytes("general_fe_28_80kmh"))
	_bridge.emit_notification("neo", BleUuids.FEC_NOTIFY, _bytes("trainer_data_250w_90rpm"))
	assert_true(got.back().has_speed, "скорость станка разобрана (журнал, хаб)")
	assert_almost_eq(got.back().speed_kmh, 28.80, 0.01)
	var hr_page := FecCodec.encode_message(PackedByteArray([0x10, 0x19, 0, 0, 0xFF, 0xFF, 140, 0x34]), FecCodec.ANT_BROADCAST_DATA)
	_bridge.emit_notification("neo", BleUuids.FEC_NOTIFY, hr_page)
	_bridge.emit_notification("neo", BleUuids.FEC_NOTIFY, _bytes("trainer_data_250w_90rpm"))
	assert_false(got.back().has_speed, "FF FF — нет данных")
	var hub := _cm.hub
	var hrs_hr: Array[int] = []
	hub.heart_rate.connect(func(b: int) -> void: hrs_hr.append(b))
	_bridge.emit_notification("neo", BleUuids.FEC_NOTIFY, hr_page)
	hub.tick(1.0)
	assert_eq(hub.heart_rate_source_in_use(), SensorHub.SOURCE_TRAINER, "без HRS — пульс станка")
	assert_eq(hrs_hr.back(), 140)
	_bridge.set_device_services("hrs", {BleUuids.HRS_SERVICE: PackedStringArray([BleUuids.HEART_RATE_MEASUREMENT])})
	_cm.connect_sensor("hrs", RememberedDevices.KIND_HR)
	_bridge.pump()
	_bridge.emit_notification("hrs", BleUuids.HEART_RATE_MEASUREMENT, PackedByteArray([0x06, 72]))
	_bridge.emit_notification("neo", BleUuids.FEC_NOTIFY, hr_page)
	hub.tick(1.0)
	assert_eq(hub.heart_rate_source_in_use(), SensorHub.SOURCE_HEART_RATE_SENSOR, "HRS выше пульса станка")
	assert_eq(hrs_hr.back(), 72)
	# Скорость станка в сэмпл сессии не идёт (У-30).
	var dev := _cm.session_device()
	var s := WorkoutSession.new(Workout.make("p", [WorkoutStep.watts(5, 200.0)] as Array[WorkoutStep]), dev, 200)
	_cm.ticks_devices = false
	s.start()
	while s.get_state() != WorkoutSession.State.FINISHED:
		_bridge.emit_notification("neo", BleUuids.FEC_NOTIFY,
			FecCodec.encode_message(PackedByteArray([0x10, 0x19, 0, 0, 0x10, 0x27, 0xFF, 0x34]), FecCodec.ANT_BROADCAST_DATA))
		_bridge.emit_notification("neo", BleUuids.FEC_NOTIFY, _bytes("trainer_data_250w_90rpm"))
		s.tick(1.0)
	for i in s.samples.size():
		assert_ne(snappedf(s.samples.speed_kmh[i], 0.01), 36.0, "скорость сэмпла — модель, не станок")
	_cm.release_session_device()
