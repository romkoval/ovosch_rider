extends GutTest
## Независимая приёмка T-017/T-018 (коммит 5c2e62f): `BleTrainer` поверх `StubBleBridge`,
## датчики `BleHeartRateSensor`/`BleCadenceSensor`/`BlePowerMeter`, `SensorHub`, `TrainerFactory`.
## Критерии: REQ-DEV-02 к1, 3 (4, 5 через BleTrainer); REQ-DEV-03 к2, 3; REQ-DEV-04 к3, 4;
## REQ-DEV-05 к1, 2, 3; REQ-DEV-07 к1, 2, 3 (датчики); REQ-DEV-08 к1, 3 (+ уточнение по паузе);
## REQ-NFR-01 к2; REQ-WRK-03 к3; REQ-WRK-04 к2, 3; REQ-WRK-08 к4.

const DEV: String = "neo"
const FTP: int = 200

var _bridge: StubBleBridge
var _t: BleTrainer
var _states: Array[int] = []
var _errors: Array[Dictionary] = []
var _samples: Array[TrainerSample] = []
var _hr: Array[int] = []
## Сколько ближайших неудачных write_done превращать в повторный отказ (см. _arm_write_failures).
var _fail_remaining: int = 0


func before_each() -> void:
	_states = []
	_errors = []
	_samples = []
	_hr = []
	_fail_remaining = 0
	_bridge = StubBleBridge.new()
	# Подключаемся к write_done ДО создания BleTrainer, чтобы наш обработчик шёл первым
	# и мог «сломать» повторную запись (сценарий двойного отказа, REQ-NFR-01 крит. 2).
	_bridge.write_done.connect(func(_id: String, _c: String, ok: bool) -> void:
		if not ok and _fail_remaining > 0:
			_fail_remaining -= 1
			_bridge.fail_next_write())
	_t = BleTrainer.new(_bridge)
	_t.connection_state_changed.connect(func(s: int) -> void: _states.append(s))
	_t.error.connect(func(c: int, m: String) -> void: _errors.append({"code": c, "message": m}))
	_t.telemetry.connect(func(s: TrainerSample) -> void: _samples.append(s))
	_t.heart_rate.connect(func(b: int) -> void: _hr.append(b))


func _hex(s: String) -> PackedByteArray:
	var clean := s.replace(" ", "")
	var out := PackedByteArray()
	var i := 0
	while i + 1 < clean.length():
		out.append(("0x" + clean.substr(i, 2)).hex_to_int())
		i += 2
	return out


func _hex_of(bytes: PackedByteArray) -> String:
	var parts: PackedStringArray = []
	for b in bytes:
		parts.append("%02X" % b)
	return " ".join(parts)


func _cp_writes() -> Array[String]:
	var out: Array[String] = []
	for w in _bridge.writes_to("2AD9"):
		out.append(_hex_of(w["bytes"]))
	return out


func _ftms_subscribes() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for s in _bridge.calls_of("subscribe"):
		if s["service"] == "1826":
			out.append(s)
	return out


func _methods() -> Array[String]:
	var out: Array[String] = []
	for c in _bridge.calls:
		out.append(c["method"])
	return out


func _error_codes() -> Array[int]:
	var out: Array[int] = []
	for e in _errors:
		out.append(e["code"])
	return out


## Полное подключение: connect → discover → subscribe → Request Control → 80 00 01 → CONNECTED.
func _connect(range_hex: String = "") -> void:
	if range_hex != "":
		_bridge.set_read_value("2AD6", _hex(range_hex))
	_t.connect_device(DEV)
	_bridge.pump()
	assert_eq(_t.get_connection_state(), TrainerDevice.ConnectionState.CONNECTED, "предусловие: станок подключён")
	_bridge.clear_calls()
	_errors.clear()
	_states.clear()


func _tick_n(obj: Object, n: int, delta: float = 1.0) -> void:
	for i in n:
		obj.tick(delta)


# ===========================================================================
# BleTrainer — REQ-DEV-02
# ===========================================================================

func test_req_dev_02_c1_connect_sequence_subscribe_2ad2_2ada_2ad9_then_request_control() -> void:
	_bridge.set_device_services(DEV, {"1826": ["2AD2", "2AD9", "2ADA", "2AD6"], "180A": ["2A29"]})
	_bridge.set_read_value("2AD6", _hex("00 00 E8 03 01 00"))
	_t.connect_device(DEV)
	assert_eq(_t.get_connection_state(), TrainerDevice.ConnectionState.CONNECTING)
	assert_eq(_bridge.calls_of("connect_peripheral").size(), 1)
	_bridge.pump()
	var m := _methods()
	assert_eq(m[0], "connect_peripheral")
	assert_eq(m[1], "discover_services", "после connected — обнаружение сервисов")
	var subs := _ftms_subscribes()
	assert_eq(subs.size(), 3, "три подписки FTMS (подписки других сервисов, напр. батареи, не считаем)")
	var chars: Array[String] = []
	for s in subs:
		chars.append(s["char"])
	assert_true(chars.has("2AD2") and chars.has("2ADA") and chars.has("2AD9"), "2AD2, 2ADA, 2AD9: %s" % str(chars))
	var first_write := m.find("write")
	var last_sub := m.rfind("subscribe")
	assert_true(first_write > last_sub, "Request Control пишется после всех подписок")
	assert_eq(_cp_writes()[0], "00", "Request Control = 0x00")
	assert_true(_bridge.writes_to("2AD9")[0]["with_response"], "Control Point — Write Request")
	assert_eq(_bridge.calls_of("read_characteristic").size(), 1, "2AD6 прочитан, т.к. заявлен")
	assert_eq(_bridge.calls_of("read_characteristic")[0]["char"], "2AD6")
	assert_eq(_t.get_connection_state(), TrainerDevice.ConnectionState.CONNECTED)
	assert_eq(_states, [TrainerDevice.ConnectionState.CONNECTING, TrainerDevice.ConnectionState.CONNECTED] as Array[int])
	assert_true(_t.control_granted)
	assert_almost_eq(float(_t.resistance_range["max_level"]), 100.0, 1e-9)
	assert_eq(_errors.size(), 0)


func test_req_dev_02_c1_connected_only_after_request_control_response_80_00_01() -> void:
	_bridge.auto_control_point_response = false
	_t.connect_device(DEV)
	_bridge.pump()
	assert_eq(_t.get_connection_state(), TrainerDevice.ConnectionState.CONNECTING,
		"connected/services/подписки есть, но без ответа на Request Control — ещё CONNECTING")
	assert_false(_t.control_granted)
	# Индикация с другим request_opcode не переводит в CONNECTED.
	_bridge.emit_notification(DEV, "2AD9", _hex("80 05 01"))
	assert_eq(_t.get_connection_state(), TrainerDevice.ConnectionState.CONNECTING, "80 05 01 — не ответ на Request Control")
	assert_eq(_errors.size(), 0)
	# Мусор/обрезанный ответ — игнор.
	_bridge.emit_notification(DEV, "2AD9", _hex("80 00"))
	_bridge.emit_notification(DEV, "2AD9", _hex("01 02 03"))
	assert_eq(_t.get_connection_state(), TrainerDevice.ConnectionState.CONNECTING)
	# Настоящий ответ.
	_bridge.emit_notification(DEV, "2AD9", _hex("80 00 01"))
	assert_eq(_t.get_connection_state(), TrainerDevice.ConnectionState.CONNECTED)
	assert_true(_t.control_granted)


func test_req_dev_02_c3_request_control_rejected_is_error_and_disconnected_without_reconnect() -> void:
	_bridge.fail_next_control_point(FtmsCodec.RESULT_NOT_SUPPORTED)  # 80 00 02
	_t.connect_device(DEV)
	_bridge.pump()
	assert_eq(_t.get_connection_state(), TrainerDevice.ConnectionState.DISCONNECTED)
	assert_true(_error_codes().has(TrainerDevice.ErrorCode.CONTROL_POINT_REJECTED), "отказ в управлении — ошибка")
	assert_false(_states.has(TrainerDevice.ConnectionState.RECONNECTING), "переподключения нет")
	assert_false(_states.has(TrainerDevice.ConnectionState.CONNECTED))
	assert_eq(_bridge.calls_of("connect_peripheral").size(), 1, "повторных попыток подключения нет")
	assert_eq(_t.reconnect_attempts(), 0)
	_tick_n(_t, 12)
	_bridge.pump()
	assert_eq(_bridge.calls_of("connect_peripheral").size(), 1, "и по таймеру тоже")
	assert_eq(_t.get_connection_state(), TrainerDevice.ConnectionState.DISCONNECTED)


func test_req_dev_02_c3_command_rejected_keeps_connection_and_reports_error() -> void:
	_connect()
	_bridge.fail_next_control_point(FtmsCodec.RESULT_OPERATION_FAILED)  # 80 05 04
	_t.set_target_power(250)
	_bridge.pump()
	assert_eq(_error_codes(), [TrainerDevice.ErrorCode.CONTROL_POINT_REJECTED] as Array[int])
	assert_true(_errors[0]["message"].contains("set_target_power"), "в сообщении — какая команда")
	assert_eq(_t.get_connection_state(), TrainerDevice.ConnectionState.CONNECTED, "соединение сохраняется")
	assert_eq(_states.size(), 0, "состояние не менялось")
	# Следующая команда проходит.
	_t.set_target_power(260)
	_bridge.pump()
	assert_eq(_errors.size(), 1)
	assert_eq(_cp_writes(), ["05 FA 00", "05 04 01"] as Array[String])
	# invalid_parameter на уровне сопротивления — тоже ошибка без разрыва.
	_t.set_erg_enabled(false)
	_bridge.pump()
	_bridge.fail_next_control_point(FtmsCodec.RESULT_INVALID_PARAMETER)
	_t.set_resistance_level(40)
	_bridge.pump()
	assert_eq(_errors.size(), 2)
	assert_eq(_errors[1]["code"], TrainerDevice.ErrorCode.CONTROL_POINT_REJECTED)
	assert_eq(_t.get_connection_state(), TrainerDevice.ConnectionState.CONNECTED)


func test_req_dev_02_c4_set_target_power_writes_05_fa_00_with_response() -> void:
	_connect()
	_t.set_target_power(250)
	var w := _bridge.writes_to("2AD9")
	assert_eq(w.size(), 1)
	assert_eq(_hex_of(w[0]["bytes"]), "05 FA 00")
	assert_eq(w[0]["service"], "1826")
	assert_true(w[0]["with_response"])
	assert_eq(_t.target_power_w, 250)
	_t.set_target_power(130)
	_t.set_target_power(0)
	_t.set_target_power(3000)
	assert_eq(_cp_writes(), ["05 FA 00", "05 82 00", "05 00 00", "05 D0 07"] as Array[String], "0 допустим, 3000 клампится к 2000")
	_bridge.pump()
	assert_eq(_errors.size(), 0)


func test_req_dev_02_c5_set_resistance_level_writes_04_32_by_default_mapping() -> void:
	_bridge.set_device_services(DEV, {"1826": ["2AD2", "2AD9", "2ADA"]})  # без 2AD6
	_connect()
	assert_eq(_bridge.calls_of("read_characteristic").size(), 0, "2AD6 не заявлен — не читаем")
	assert_true(_t.resistance_range.is_empty())
	_t.set_erg_enabled(false)
	assert_eq(_cp_writes(), ["04 00"] as Array[String], "выключение ERG шлёт текущий уровень (0 %)")
	_t.set_resistance_level(50)
	assert_eq(_cp_writes().back(), "04 32", "50 % без 2AD6 → 5.0 → 04 32")
	_t.set_resistance_level(100)
	assert_eq(_cp_writes().back(), "04 64")
	_t.set_resistance_level(-10)
	assert_eq(_cp_writes().back(), "04 00", "клампится к 0")
	assert_eq(_t.resistance_percent, 0)


func test_req_dev_02_c2_indoor_bike_data_becomes_sample_truncated_ignored_other_id_ignored() -> void:
	_connect()
	_tick_n(_t, 3, 0.5)
	_bridge.emit_notification(DEV, "2AD2", _hex("44 02 48 0D B4 00 FA 00 48"))
	assert_eq(_samples.size(), 1)
	var s := _samples[0]
	assert_true(s.has_power and s.power_w == 250)
	assert_true(s.has_cadence and s.cadence_rpm == 90)
	assert_true(s.has_speed)
	assert_almost_eq(s.speed_kmh, 34.0, 1e-6)
	assert_almost_eq(s.timestamp_sec, 1.5, 1e-9, "метка — часы станка")
	assert_eq(_hr, [72] as Array[int], "пульс из Indoor Bike Data")
	# Без скорости (More Data) и без пульса.
	_bridge.emit_notification(DEV, "2AD2", _hex("45 00 B4 00 FA FF"))
	assert_eq(_samples.size(), 2)
	assert_false(_samples[1].has_speed)
	assert_eq(_samples[1].power_w, -6, "отрицательная мощность доходит как есть")
	assert_eq(_hr.size(), 1)
	# Обрезанный пакет — сэмпла нет, ошибки нет.
	_bridge.emit_notification(DEV, "2AD2", _hex("44 00 48 0D B4"))
	_bridge.emit_notification(DEV, "2AD2", _hex(""))
	assert_eq(_samples.size(), 2, "обрезанный 2AD2 не даёт сэмпла")
	assert_eq(_errors.size(), 0)
	# Чужое устройство — игнор.
	_bridge.emit_notification("other", "2AD2", _hex("44 02 48 0D B4 00 FA 00 48"))
	assert_eq(_samples.size(), 2)
	assert_eq(_hr.size(), 1)
	_bridge.emit_disconnected("other", BleBridge.DisconnectReason.LINK_LOSS)
	assert_eq(_t.get_connection_state(), TrainerDevice.ConnectionState.CONNECTED, "disconnected чужого id не трогает нас")
	_bridge.emit_connected("other")
	assert_eq(_bridge.calls_of("discover_services").size(), 0, "connected чужого id — без действий")


func test_req_dev_02_machine_status_control_lost_requests_control_again() -> void:
	_connect()
	_bridge.emit_notification(DEV, "2ADA", _hex("FF"))
	assert_false(_t.control_granted, "управление отозвано")
	assert_eq(_cp_writes(), ["00"] as Array[String], "повторный Request Control")
	assert_eq(_t.get_connection_state(), TrainerDevice.ConnectionState.CONNECTED, "соединение не рвётся")
	_bridge.pump()
	assert_true(_t.control_granted, "после 80 00 01 управление снова есть")
	assert_eq(_errors.size(), 0)
	# Прочие статусы — без побочных эффектов.
	_bridge.emit_notification(DEV, "2ADA", _hex("08 FA 00"))
	_bridge.emit_notification(DEV, "2ADA", _hex(""))
	assert_eq(_cp_writes().size(), 1)


# ===========================================================================
# BleTrainer — REQ-NFR-01 крит. 2 (повтор записи)
# ===========================================================================

func test_req_nfr_01_c2_write_done_false_retries_same_bytes_once_within_same_second() -> void:
	_connect()
	var t0 := _t.get_time_sec()
	_bridge.fail_next_write()
	_t.set_target_power(250)
	assert_eq(_cp_writes(), ["05 FA 00"] as Array[String])
	_bridge.pump()
	assert_eq(_cp_writes(), ["05 FA 00", "05 FA 00"] as Array[String], "один повтор тех же байт")
	assert_eq(_errors.size(), 0, "повтор удался — ошибки нет")
	assert_almost_eq(_t.get_time_sec(), t0, 1e-9, "повтор — немедленно, в ту же секунду")
	assert_eq(_t.get_connection_state(), TrainerDevice.ConnectionState.CONNECTED)


func test_req_nfr_01_c2_second_write_failure_is_write_failed_error_no_third_attempt() -> void:
	_connect()
	_bridge.fail_next_write()
	_fail_remaining = 1  # первый отказ → ломаем и повторную запись
	_t.set_target_power(250)
	_bridge.pump()
	assert_eq(_cp_writes(), ["05 FA 00", "05 FA 00"] as Array[String], "две попытки, третьей нет")
	assert_eq(_error_codes(), [TrainerDevice.ErrorCode.WRITE_FAILED] as Array[int])
	assert_eq(_t.get_connection_state(), TrainerDevice.ConnectionState.CONNECTED, "соединение сохраняется")
	# Следующая команда — снова с чистого листа (повтор доступен).
	_errors.clear()
	_bridge.clear_calls()
	_bridge.fail_next_write()
	_t.set_target_power(200)
	_bridge.pump()
	assert_eq(_cp_writes(), ["05 C8 00", "05 C8 00"] as Array[String])
	assert_eq(_errors.size(), 0)


func test_req_nfr_01_c2_bridge_error_write_failed_also_triggers_one_retry() -> void:
	# Требование: «при ошибке записи (write_done(ok=false) ИЛИ сигнал error) команда
	# повторяется один раз». Эмулируем мост, сообщающий о неудаче сигналом error.
	_connect()
	_bridge.auto_control_point_response = false
	_t.set_target_power(250)
	assert_eq(_cp_writes(), ["05 FA 00"] as Array[String])
	_bridge.pending.clear()  # write_done от заглушки не придёт — вместо него error(WRITE_FAILED)
	_bridge.emit_error(DEV, BleBridge.ErrorCode.WRITE_FAILED, "write failed")
	assert_eq(_cp_writes(), ["05 FA 00", "05 FA 00"] as Array[String],
		"сигнал error(WRITE_FAILED) по ожидающей записи → один повтор тех же байт")
	assert_eq(_errors.size(), 0, "ошибка пользователю — только после второй неудачи")


# ===========================================================================
# BleTrainer — REQ-WRK-03 крит. 3, REQ-WRK-04 крит. 2, 3
# ===========================================================================

func test_req_wrk_03_c3_erg_on_mid_interval_sends_current_target_immediately() -> void:
	_connect()
	_t.set_target_power(130)
	_t.set_erg_enabled(false)
	assert_eq(_cp_writes(), ["05 82 00", "04 00"] as Array[String])
	_t.set_target_power(200)
	assert_eq(_cp_writes().size(), 2, "вне ERG цель запоминается, не пишется")
	assert_eq(_t.target_power_w, 200)
	var t0 := _t.get_time_sec()
	_t.set_erg_enabled(true)
	assert_eq(_cp_writes().back(), "05 C8 00", "включение ERG → Set Target Power текущей цели (200)")
	assert_almost_eq(_t.get_time_sec(), t0, 1e-9, "без задержки (≤ 1 с)")
	assert_true(_t.erg_enabled)
	# Включение ERG при цели 0 — команды нет (нечего слать).
	_t.set_erg_enabled(false)
	_t.set_target_power(0)
	var n := _cp_writes().size()
	_t.set_erg_enabled(true)
	assert_eq(_cp_writes().size(), n, "цель 0 → Set Target Power не шлётся")


func test_req_wrk_04_c2_resistance_percent_mapped_via_2ad6_range() -> void:
	_connect("00 00 E8 03 01 00")  # Neo: 0..100.0 шаг 0.1 → кодируемый 0..25.5
	assert_true(_t.resistance_range["ok"])
	_t.set_erg_enabled(false)
	_t.set_resistance_level(50)
	assert_eq(_cp_writes().back(), "04 80", "50 % → 12.8 → 04 80")
	_t.set_resistance_level(100)
	assert_eq(_cp_writes().back(), "04 FF")
	_t.set_resistance_level(0)
	assert_eq(_cp_writes().back(), "04 00")
	_t.set_resistance_level(25)
	assert_eq(_cp_writes().back(), "04 40", "25 % → 6.4 → 04 40")


func test_req_wrk_04_c2_narrow_range_and_invalid_range_fallback() -> void:
	_connect("00 00 C8 00 0A 00")  # 0..20.0 шаг 1.0
	_t.set_erg_enabled(false)
	_t.set_resistance_level(50)
	assert_eq(_cp_writes().back(), "04 64", "50 % от 0..20.0 → 10.0 → 04 64")
	_t.set_resistance_level(33)
	assert_eq(_cp_writes().back(), "04 46", "33 % → 6.6 → привязка к шагу 1.0 → 7.0 → 04 46")
	# Невалидный 2AD6 (обрезан) — диапазон не принят, запасное отображение.
	before_each()
	_connect("00 00 C8")
	assert_true(_t.resistance_range.is_empty(), "обрезанный 2AD6 отвергнут")
	_t.set_erg_enabled(false)
	_t.set_resistance_level(50)
	assert_eq(_cp_writes().back(), "04 32")
	# Ошибка чтения 2AD6 — не ошибка станка.
	before_each()
	_bridge.fail_next_read()
	_connect()
	assert_eq(_errors.size(), 0, "READ_FAILED по необязательному 2AD6 — не ошибка станка")
	assert_true(_t.resistance_range.is_empty())


func test_req_wrk_04_c3_resistance_level_stored_in_erg_and_sent_when_erg_off() -> void:
	_connect()
	_t.set_target_power(130)
	_t.set_resistance_level(60)
	assert_eq(_cp_writes(), ["05 82 00"] as Array[String], "в ERG уровень не отправляется")
	assert_eq(_t.resistance_percent, 60, "но сохранён")
	_t.set_resistance_level(70)
	assert_eq(_cp_writes().size(), 1)
	_t.set_erg_enabled(false)
	assert_eq(_cp_writes().back(), "04 46", "при выключении ERG уходит сохранённый уровень 70 % → 7.0")
	_t.set_resistance_level(20)
	assert_eq(_cp_writes().back(), "04 14", "вне ERG — сразу")


# ===========================================================================
# BleTrainer — REQ-DEV-08 крит. 1, 3
# ===========================================================================

func test_req_dev_08_c1_link_loss_reconnecting_attempt_now_and_every_5s() -> void:
	_connect()
	_bridge.auto_connect = false  # станок «не отвечает» — считаем попытки
	_bridge.emit_disconnected(DEV, BleBridge.DisconnectReason.LINK_LOSS)
	assert_eq(_t.get_connection_state(), TrainerDevice.ConnectionState.RECONNECTING)
	assert_eq(_bridge.calls_of("connect_peripheral").size(), 1, "попытка сразу")
	assert_eq(_t.reconnect_attempts(), 1)
	_tick_n(_t, 49, 0.1)  # 4.9 с
	assert_eq(_bridge.calls_of("connect_peripheral").size(), 1, "до 5 с новой попытки нет")
	_t.tick(0.1)
	assert_eq(_bridge.calls_of("connect_peripheral").size(), 2, "попытка на 5 с")
	_tick_n(_t, 10)
	assert_eq(_bridge.calls_of("connect_peripheral").size(), 4, "каждые 5 с: 10 с, 15 с")
	_tick_n(_t, 60)
	assert_eq(_bridge.calls_of("connect_peripheral").size(), 16, "без ограничения числа попыток")
	assert_eq(_t.get_connection_state(), TrainerDevice.ConnectionState.RECONNECTING)
	for c in _bridge.calls_of("connect_peripheral"):
		assert_eq(c["id"], DEV)


func test_req_dev_08_c1_failed_attempt_keeps_reconnecting_then_success_redoes_setup() -> void:
	_connect()
	_bridge.fail_next_connect()  # до emit_disconnected: первая попытка провалится
	_bridge.emit_disconnected(DEV, BleBridge.DisconnectReason.LINK_LOSS)
	_bridge.pump()
	assert_eq(_t.get_connection_state(), TrainerDevice.ConnectionState.RECONNECTING, "ошибка попытки не роняет в DISCONNECTED")
	assert_eq(_errors.size(), 0, "ошибка попытки переподключения не показывается как ошибка подключения")
	_tick_n(_t, 5)
	assert_eq(_bridge.calls_of("connect_peripheral").size(), 2)
	_bridge.pump()  # вторая попытка успешна → заново discover/subscribe/RC
	assert_eq(_t.get_connection_state(), TrainerDevice.ConnectionState.CONNECTED)
	assert_eq(_bridge.calls_of("discover_services").size(), 1, "обнаружение сервисов заново")
	assert_eq(_ftms_subscribes().size(), 3, "подписки FTMS (2AD2/2ADA/2AD9) заново")
	assert_eq(_cp_writes(), ["00"] as Array[String], "Request Control заново; других записей станок сам не делает")
	assert_true(_t.control_granted)
	assert_eq(_states, [TrainerDevice.ConnectionState.RECONNECTING, TrainerDevice.ConnectionState.CONNECTED] as Array[int])
	# Таймер переподключения остановлен.
	_tick_n(_t, 20)
	assert_eq(_bridge.calls_of("connect_peripheral").size(), 2)


func test_req_dev_08_c3_target_set_during_reconnecting_is_stored_not_written_and_not_replayed_by_trainer() -> void:
	_connect()
	_t.set_target_power(130)
	_bridge.pump()
	_bridge.clear_calls()
	_bridge.auto_connect = false
	_bridge.emit_disconnected(DEV, BleBridge.DisconnectReason.LINK_LOSS)
	_t.set_target_power(200)
	_t.set_erg_enabled(true)
	_t.set_resistance_level(30)
	assert_eq(_bridge.calls_of("write").size(), 0, "в RECONNECTING команды не пишутся")
	assert_eq(_t.target_power_w, 200, "но запоминаются")
	assert_eq(_t.resistance_percent, 30)
	_bridge.emit_connected(DEV)
	_bridge.pump()
	assert_eq(_t.get_connection_state(), TrainerDevice.ConnectionState.CONNECTED)
	assert_eq(_cp_writes(), ["00"] as Array[String],
		"после переподключения станок сам пишет только Request Control — цель повторяет сессия (без дублей)")
	# Сессия повторяет цель → уходит ровно то, что она послала.
	_t.set_target_power(200)
	assert_eq(_cp_writes(), ["00", "05 C8 00"] as Array[String])


func test_req_dev_08_c3_session_over_ble_trainer_resends_target_after_reconnect() -> void:
	_connect()
	var w := Workout.make("ble", [WorkoutStep.percent(60, 65.0), WorkoutStep.percent(60, 100.0)] as Array[WorkoutStep])
	var session := WorkoutSession.new(w, _t, FTP)
	session.start()
	_bridge.pump()
	assert_eq(_cp_writes(), ["05 82 00"] as Array[String], "старт: 65 % × 200 = 130 Вт")
	_tick_n(session, 10)
	_bridge.clear_calls()
	_bridge.emit_disconnected(DEV, BleBridge.DisconnectReason.LINK_LOSS)
	assert_eq(_t.get_connection_state(), TrainerDevice.ConnectionState.RECONNECTING)
	_tick_n(session, 2)
	assert_eq(_bridge.calls_of("write").size(), 0, "во время обрыва ничего не пишется")
	_bridge.pump()  # connected → setup → 80 00 01 → CONNECTED → сессия повторяет ERG и цель
	assert_eq(_t.get_connection_state(), TrainerDevice.ConnectionState.CONNECTED)
	var cp := _cp_writes()
	assert_eq(cp[0], "00", "Request Control первым")
	var targets := cp.filter(func(x: String) -> bool: return x == "05 82 00")
	assert_gt(targets.size(), 0, "Set Target Power текущего интервала (130 Вт) после connected")
	gut.p("DEV-08.3: записей Set Target Power 130 Вт после переподключения: %d (ожидаемо ≥ 1; 2 = ERG-resend + цель)" % targets.size())
	assert_eq(_t.target_power_w, 130)
	assert_eq(session.samples.size(), 12, "запись сэмплов не прерывалась")
	assert_false(session.samples.has_power[11], "во время обрыва — «нет данных»")


func test_req_dev_08_c3_reconnect_during_pause_sends_only_request_control_target_on_resume() -> void:
	# Уточнение DEV-08 крит. 3 (daf4ca8): обрыв и восстановление на паузе — после connected
	# только Request Control; цель уходит при resume (WRK-05.3).
	_connect()
	var w := Workout.make("ble", [WorkoutStep.percent(60, 65.0), WorkoutStep.percent(60, 100.0)] as Array[WorkoutStep])
	var session := WorkoutSession.new(w, _t, FTP)
	session.start()
	_bridge.pump()
	_tick_n(session, 10)
	session.pause()
	_bridge.clear_calls()
	_bridge.emit_disconnected(DEV, BleBridge.DisconnectReason.LINK_LOSS)
	_tick_n(session, 3)
	_bridge.pump()
	assert_eq(_t.get_connection_state(), TrainerDevice.ConnectionState.CONNECTED)
	assert_eq(_cp_writes(), ["00"] as Array[String], "на паузе после connected — только Request Control")
	assert_eq(_bridge.calls_of("write").size(), 1)
	session.resume()
	assert_eq(_cp_writes(), ["00", "05 82 00"] as Array[String], "цель — при resume")


func test_req_dev_08_edge_disconnect_request_during_reconnecting_stops_attempts_and_ignores_late_connected() -> void:
	_connect()
	_bridge.emit_disconnected(DEV, BleBridge.DisconnectReason.LINK_LOSS)
	assert_eq(_t.get_connection_state(), TrainerDevice.ConnectionState.RECONNECTING)
	var attempts := _bridge.calls_of("connect_peripheral").size()
	_t.disconnect_device()
	assert_eq(_t.get_connection_state(), TrainerDevice.ConnectionState.DISCONNECTED)
	_tick_n(_t, 20)
	assert_eq(_bridge.calls_of("connect_peripheral").size(), attempts, "после disconnect_device попыток нет")
	_bridge.pump()  # запоздалое connected от первой попытки + disconnected(REQUESTED)
	assert_eq(_t.get_connection_state(), TrainerDevice.ConnectionState.DISCONNECTED, "запоздалое connected игнорируется")
	assert_eq(_bridge.calls_of("discover_services").size(), 0)
	assert_eq(_cp_writes().size(), 0)


func test_req_dev_08_edge_disconnect_during_connecting_recovers() -> void:
	_t.connect_device(DEV)
	assert_eq(_t.get_connection_state(), TrainerDevice.ConnectionState.CONNECTING)
	_bridge.emit_disconnected(DEV, BleBridge.DisconnectReason.LINK_LOSS)
	assert_ne(_t.get_connection_state(), TrainerDevice.ConnectionState.CONNECTED)
	_bridge.pump()
	assert_eq(_t.get_connection_state(), TrainerDevice.ConnectionState.CONNECTED, "в итоге подключение состоялось")
	assert_true(_t.control_granted)
	assert_eq(_errors.size(), 0)
	# Повторный connect_device в CONNECTED — игнор, без второй серии подписок.
	_bridge.clear_calls()
	_t.connect_device(DEV)
	_bridge.pump()
	assert_eq(_bridge.calls.size(), 0)


func test_req_dev_08_edge_two_link_losses_in_a_row_end_connected_once() -> void:
	_connect()
	_bridge.auto_connect = false  # считаем попытки, пока станок «не отвечает»
	_bridge.emit_disconnected(DEV, BleBridge.DisconnectReason.LINK_LOSS)
	assert_eq(_bridge.calls_of("connect_peripheral").size(), 1, "первая попытка — сразу")
	_t.tick(2.0)
	_bridge.emit_disconnected(DEV, BleBridge.DisconnectReason.LINK_LOSS)
	assert_eq(_t.get_connection_state(), TrainerDevice.ConnectionState.RECONNECTING)
	assert_eq(_states.count(TrainerDevice.ConnectionState.RECONNECTING), 1, "RECONNECTING не дублируется")
	assert_eq(_bridge.calls_of("connect_peripheral").size(), 1, "второй обрыв в RECONNECTING не добавляет попытку")
	_t.tick(2.9)  # 4.9 с от первой попытки
	assert_eq(_bridge.calls_of("connect_peripheral").size(), 1, "интервал 5 с не перезапущен вторым обрывом")
	_t.tick(0.1)  # 5.0 с
	assert_eq(_bridge.calls_of("connect_peripheral").size(), 2, "вторая попытка — ровно через 5 с после первой")
	assert_eq(_t.reconnect_attempts(), 2)
	_bridge.emit_connected(DEV)
	_bridge.pump()
	assert_eq(_t.get_connection_state(), TrainerDevice.ConnectionState.CONNECTED)
	assert_eq(_states.count(TrainerDevice.ConnectionState.CONNECTED), 1, "CONNECTED один раз")
	assert_eq(_errors.size(), 0)
	_tick_n(_t, 20)
	assert_eq(_bridge.calls_of("connect_peripheral").size(), 2, "после успеха новых попыток нет")


func test_req_dev_08_edge_connection_failed_from_connecting_is_error_and_disconnected() -> void:
	_bridge.fail_next_connect()
	_t.connect_device(DEV)
	_bridge.pump()
	assert_eq(_t.get_connection_state(), TrainerDevice.ConnectionState.DISCONNECTED)
	assert_eq(_error_codes(), [TrainerDevice.ErrorCode.CONNECTION_FAILED] as Array[int])
	_tick_n(_t, 20)
	assert_eq(_bridge.calls_of("connect_peripheral").size(), 1, "при первичной ошибке подключения автоповтора нет")


# ===========================================================================
# TrainerFactory
# ===========================================================================

func test_trainer_factory_ble_only_with_native_bridge_and_create_ble_injection() -> void:
	assert_false(NativeBleBridge.is_native_available())
	var ble := TrainerFactory.create("ble")
	assert_null(ble, "без нативного моста BleTrainer не создаётся (null, предупреждение)")
	var fake := TrainerFactory.create("fake")
	assert_true(fake is FakeTrainer)
	var injected := TrainerFactory.create_ble(_bridge)
	assert_true(injected is BleTrainer)
	assert_eq((injected as BleTrainer).bridge, _bridge)
	assert_eq(injected.get_connection_state(), TrainerDevice.ConnectionState.DISCONNECTED)


# ===========================================================================
# Датчики — REQ-DEV-07 крит. 1–3, REQ-DEV-08 крит. 1
# ===========================================================================

func test_req_dev_07_c1_sensor_states_follow_bridge_events() -> void:
	var s := BleHeartRateSensor.new(_bridge)
	var states: Array[int] = []
	s.connection_state_changed.connect(func(st: int) -> void: states.append(st))
	assert_eq(s.get_connection_state(), TrainerDevice.ConnectionState.DISCONNECTED, "не подключено")
	s.connect_device("hrs")
	assert_eq(s.get_connection_state(), TrainerDevice.ConnectionState.CONNECTING, "подключение")
	_bridge.pump()
	assert_eq(s.get_connection_state(), TrainerDevice.ConnectionState.CONNECTED, "подключено")
	assert_true(_bridge.is_subscribed("hrs", "180D", "2A37"))
	_bridge.emit_disconnected("hrs", BleBridge.DisconnectReason.LINK_LOSS)
	assert_eq(s.get_connection_state(), TrainerDevice.ConnectionState.RECONNECTING, "переподключение")
	_bridge.pump()
	assert_eq(s.get_connection_state(), TrainerDevice.ConnectionState.CONNECTED)
	s.disconnect_device()
	_bridge.pump()
	assert_eq(s.get_connection_state(), TrainerDevice.ConnectionState.DISCONNECTED)
	assert_eq(states, [TrainerDevice.ConnectionState.CONNECTING, TrainerDevice.ConnectionState.CONNECTED,
		TrainerDevice.ConnectionState.RECONNECTING, TrainerDevice.ConnectionState.CONNECTED,
		TrainerDevice.ConnectionState.DISCONNECTED] as Array[int])
	# Обрыв по запросу (REQUESTED) не ведёт к переподключению.
	s.connect_device("hrs")
	_bridge.pump()
	var attempts_before := _bridge.calls_of("connect_peripheral").size()
	_bridge.emit_disconnected("hrs", BleBridge.DisconnectReason.REQUESTED)
	assert_eq(s.get_connection_state(), TrainerDevice.ConnectionState.DISCONNECTED)
	_tick_n(s, 12)
	assert_eq(_bridge.calls_of("connect_peripheral").size(), attempts_before, "после REQUESTED попыток переподключения нет")


func test_req_dev_07_c2_sensor_reads_battery_on_connect_and_updates_on_notification() -> void:
	_bridge.set_device_services("hrs", {"180D": ["2A37"], "180F": ["2A19"]})
	_bridge.set_read_value("2A19", _hex("55"))
	var s := BleHeartRateSensor.new(_bridge)
	var levels: Array[int] = []
	s.battery_level.connect(func(p: int) -> void: levels.append(p))
	assert_eq(s.get_battery_level(), -1, "до подключения — неизвестно")
	s.connect_device("hrs")
	_bridge.pump()
	var reads := _bridge.calls_of("read_characteristic")
	assert_eq(reads.size(), 1, "read_characteristic(hrs, 180F, 2A19) после подключения")
	assert_eq(reads[0]["id"], "hrs")
	assert_eq(reads[0]["service"], "180F")
	assert_eq(reads[0]["char"], "2A19")
	assert_eq(s.get_battery_level(), 85, "0x55 = 85 %")
	assert_eq(levels, [85] as Array[int])
	assert_true(_bridge.is_subscribed("hrs", "180F", "2A19"), "подписка на нотификации Battery Level")
	_bridge.emit_notification("hrs", "2A19", _hex("32"))
	assert_eq(s.get_battery_level(), 50, "обновление по нотификации")
	assert_eq(levels, [85, 50] as Array[int])
	_bridge.emit_notification("hrs", "2A19", _hex("FF"))
	assert_eq(s.get_battery_level(), 50, "невалидное значение 255 не принимается")
	_bridge.emit_notification("other", "2A19", _hex("0A"))
	assert_eq(s.get_battery_level(), 50, "чужое устройство игнорируется")


func test_req_dev_07_c3_sensor_without_battery_service_is_dash_not_error() -> void:
	_bridge.set_device_services("csc", {"1816": ["2A5B", "2A5C"]})
	var s := BleCadenceSensor.new(_bridge)
	var errs: Array[int] = []
	s.error.connect(func(c: int, _m: String) -> void: errs.append(c))
	s.connect_device("csc")
	_bridge.pump()
	assert_eq(s.get_connection_state(), TrainerDevice.ConnectionState.CONNECTED)
	assert_eq(_bridge.calls_of("read_characteristic").size(), 0, "Battery Service нет — чтение не запрашивается")
	assert_eq(s.get_battery_level(), -1, "«—»")
	assert_eq(errs.size(), 0, "не ошибка")
	# Список сервисов неизвестен: чтение пробуется, отсутствие характеристики — тоже не ошибка.
	var s2 := BlePowerMeter.new(_bridge)
	var errs2: Array[int] = []
	s2.error.connect(func(c: int, _m: String) -> void: errs2.append(c))
	s2.connect_device("pm")
	_bridge.pump()
	assert_eq(s2.get_connection_state(), TrainerDevice.ConnectionState.CONNECTED)
	assert_eq(_bridge.calls_of("read_characteristic").size(), 1)
	assert_eq(s2.get_battery_level(), -1)
	assert_eq(errs2.size(), 0)


func test_req_dev_08_c1_sensor_link_loss_retries_every_5s_and_resubscribes() -> void:
	var s := BleCadenceSensor.new(_bridge)
	s.connect_device("csc")
	_bridge.pump()
	_bridge.clear_calls()
	_bridge.auto_connect = false
	_bridge.emit_disconnected("csc", BleBridge.DisconnectReason.LINK_LOSS)
	assert_eq(s.get_connection_state(), TrainerDevice.ConnectionState.RECONNECTING)
	assert_eq(_bridge.calls_of("connect_peripheral").size(), 1)
	_tick_n(s, 10)
	assert_eq(_bridge.calls_of("connect_peripheral").size(), 3, "сразу, 5 с, 10 с")
	_bridge.emit_connected("csc")
	_bridge.pump()
	assert_eq(s.get_connection_state(), TrainerDevice.ConnectionState.CONNECTED)
	assert_true(_bridge.is_subscribed("csc", "1816", "2A5B"), "подписка восстановлена")
	assert_eq(_bridge.calls_of("discover_services").size(), 1)
	_tick_n(s, 20)
	assert_eq(_bridge.calls_of("connect_peripheral").size(), 3, "после успеха попыток нет")


# ===========================================================================
# Датчики — измерения (REQ-DEV-03 крит. 2, REQ-DEV-04 крит. 3, REQ-DEV-05 крит. 1, 3)
# ===========================================================================

func _connected_sensor(sensor: BleSensorBase, id: String) -> BleSensorBase:
	sensor.connect_device(id)
	_bridge.pump()
	assert_eq(sensor.get_connection_state(), TrainerDevice.ConnectionState.CONNECTED)
	return sensor


func test_req_dev_03_c2_hrs_without_contact_emits_nothing() -> void:
	var s := _connected_sensor(BleHeartRateSensor.new(_bridge), "hrs") as BleHeartRateSensor
	var hr: Array[int] = []
	s.heart_rate.connect(func(b: int) -> void: hr.append(b))
	_bridge.emit_notification("hrs", "2A37", _hex("06 48"))
	assert_eq(hr, [72] as Array[int], "контакт есть → 72")
	assert_true(s.contact_ok)
	_bridge.emit_notification("hrs", "2A37", _hex("04 50"))
	assert_eq(hr.size(), 1, "нет контакта → пульс не испускается (не 0, не 80)")
	assert_false(s.contact_ok)
	_bridge.emit_notification("hrs", "2A37", _hex("00 4B"))
	assert_eq(hr, [72, 75] as Array[int], "контакт не поддерживается → достоверно")
	_bridge.emit_notification("hrs", "2A37", _hex("01 2C 01"))
	assert_eq(hr.back(), 300, "uint16-формат")
	_bridge.emit_notification("hrs", "2A37", _hex("01"))
	assert_eq(hr.size(), 3, "обрезанный пакет — ничего")
	_bridge.emit_notification("hrs", "2A5B", _hex("00 48"))
	assert_eq(hr.size(), 3, "чужая характеристика — ничего")


func test_req_dev_04_c3_cadence_sensor_emits_zero_after_3s_including_from_start() -> void:
	var s := _connected_sensor(BleCadenceSensor.new(_bridge), "csc") as BleCadenceSensor
	var cad: Array[int] = []
	s.cadence.connect(func(r: int) -> void: cad.append(r))
	_bridge.emit_notification("csc", "2A5B", _hex("02 0A 00 00 08"))
	assert_eq(cad.size(), 0, "первое измерение — ещё нет пары")
	s.tick(1.0)
	_bridge.emit_notification("csc", "2A5B", _hex("02 0D 00 00 10"))
	assert_eq(cad, [90] as Array[int], "Δrev 3 / Δt 2048 → 90")
	s.tick(1.0)
	_bridge.emit_notification("csc", "2A5B", _hex("02 0D 00 00 10"))
	assert_eq(cad, [90, 90] as Array[int], "пакет без новых оборотов (< 3 с) — держим и повторяем (датчик жив)")
	s.tick(1.0)
	s.tick(0.9)
	_bridge.emit_notification("csc", "2A5B", _hex("02 0D 00 00 10"))
	assert_eq(cad, [90, 90, 90] as Array[int], "2.9 с без оборотов — ещё 90")
	s.tick(0.1)
	assert_eq(cad.size(), 3, "Н-4: сам по себе тик (без пакета) ничего не испускает")
	_bridge.emit_notification("csc", "2A5B", _hex("02 0D 00 00 10"))
	assert_eq(cad, [90, 90, 90, 0] as Array[int], "Н-4 (а): пакеты идут, обороты стоят ≥ 3 с → cadence(0)")
	_bridge.emit_notification("csc", "2A5B", _hex("02 0D 00 00 10"))
	assert_eq(cad.back(), 0, "и с каждым следующим пакетом — 0")
	assert_eq(cad.size(), 5)
	assert_eq(s.current_cadence(s.get_time_sec()), 0)
	# Н-4 (б): тишина (пакетов нет) — ничего не испускается, значение → «нет данных».
	_tick_n(s, 5)
	assert_eq(cad.size(), 5, "при тишине датчика cadence не испускается (ни 0, ни повтор)")
	assert_eq(s.current_cadence(s.get_time_sec()), -1, "тишина ≥ 3 с → «нет данных» (−1), а не 0")
	# Снова поехали.
	_bridge.emit_notification("csc", "2A5B", _hex("02 0E 00 00 14"))
	assert_eq(cad.back(), 60, "1 оборот за 1024/1024 с → 60 rpm")
	assert_eq(s.current_cadence(s.get_time_sec()), 60)
	# С самого подключения педали стоят: 4 пакета с одинаковым счётчиком за 3 с → 0 (D-2 / Н-4).
	var s2 := _connected_sensor(BleCadenceSensor.new(_bridge), "csc2") as BleCadenceSensor
	var cad2: Array[int] = []
	s2.cadence.connect(func(r: int) -> void: cad2.append(r))
	for i in 4:
		_bridge.emit_notification("csc2", "2A5B", _hex("02 0A 00 00 08"))
		if i < 3:
			s2.tick(1.0)
	assert_eq(cad2, [0] as Array[int], "без предыдущего значения — тоже 0, когда пакеты идут ≥ 3 с")
	_tick_n(s2, 3)
	assert_eq(cad2.size(), 1, "а при тишине — ничего")
	assert_eq(s2.current_cadence(s2.get_time_sec()), -1)


func test_req_dev_05_c1_c3_power_meter_emits_power_and_crank_cadence() -> void:
	var s := _connected_sensor(BlePowerMeter.new(_bridge), "pm") as BlePowerMeter
	var pw: Array[int] = []
	var cad: Array[int] = []
	s.power.connect(func(w: int) -> void: pw.append(w))
	s.cadence.connect(func(r: int) -> void: cad.append(r))
	assert_true(_bridge.is_subscribed("pm", "1818", "2A63"), "подписка на Cycling Power Measurement")
	_bridge.emit_notification("pm", "2A63", _hex("00 00 FA 00"))
	assert_eq(pw, [250] as Array[int], "00 00 FA 00 → 250 Вт")
	assert_eq(cad.size(), 0, "без crank data каденса нет")
	_bridge.emit_notification("pm", "2A63", _hex("20 00 F0 00 0A 00 00 08"))
	s.tick(1.0)
	_bridge.emit_notification("pm", "2A63", _hex("20 00 F5 00 0D 00 00 10"))
	assert_eq(pw, [250, 240, 245] as Array[int])
	assert_eq(cad, [90] as Array[int], "crank data → 90 rpm")
	_bridge.emit_notification("pm", "2A63", _hex("00 00 FA"))
	assert_eq(pw.size(), 3, "обрезанный — ничего")
	_bridge.emit_notification("pm", "2A63", _hex("00 00 06 FF"))
	assert_eq(pw.back(), -250, "отрицательная мощность доходит как есть")


# ===========================================================================
# SensorHub — REQ-DEV-03 крит. 3, REQ-DEV-04 крит. 4, REQ-DEV-05 крит. 2, 3, REQ-WRK-08 крит. 4
# ===========================================================================

var _fake: FakeTrainer
var _hub: SensorHub
var _hub_samples: Array[TrainerSample] = []
var _hub_hr: Array[int] = []


func _make_hub() -> void:
	_hub_samples = []
	_hub_hr = []
	_fake = FakeTrainer.new(5)
	_fake.connect_delay_sec = 0.0
	_fake.power_noise_w = 0.0
	_fake.cadence_noise_rpm = 0.0
	_fake.connect_device("fake")
	_hub = SensorHub.new(_fake)
	_hub.telemetry.connect(func(s: TrainerSample) -> void: _hub_samples.append(s))
	_hub.heart_rate.connect(func(b: int) -> void: _hub_hr.append(b))


func _hrs_in_hub() -> BleHeartRateSensor:
	var s := _connected_sensor(BleHeartRateSensor.new(_bridge), "hrs") as BleHeartRateSensor
	_hub.set_heart_rate_sensor(s)
	return s


func _csc_in_hub() -> BleCadenceSensor:
	var s := _connected_sensor(BleCadenceSensor.new(_bridge), "csc") as BleCadenceSensor
	_hub.set_cadence_sensor(s)
	return s


func _pm_in_hub() -> BlePowerMeter:
	var s := _connected_sensor(BlePowerMeter.new(_bridge), "pm") as BlePowerMeter
	_hub.set_power_meter(s)
	return s


func test_req_wrk_08_c4_hub_one_sample_per_second_and_stale_source_is_no_data() -> void:
	_make_hub()
	_fake.set_heart_rate(140)
	_hub.set_target_power(150)
	_tick_n(_hub, 10)
	assert_eq(_hub_samples.size(), 10, "ровно один сэмпл в секунду")
	for i in 10:
		assert_almost_eq(_hub_samples[i].timestamp_sec, float(i + 1), 1e-9)
	assert_true(_hub_samples[9].has_power and _hub_samples[9].has_cadence and _hub_samples[9].has_speed)
	assert_eq(_hub_hr.size(), 10)
	# Дробные тики — то же число сэмплов.
	_tick_n(_hub, 25, 0.2)
	assert_eq(_hub_samples.size(), 15)
	# Обрыв станка: последнее значение держится < 5 с, затем «нет данных», не 0 и не повтор.
	_fake.inject_dropout(20.0)
	_tick_n(_hub, 4)
	assert_eq(_hub_samples.size(), 19, "сэмплы продолжаются при обрыве")
	assert_true(_hub_samples[18].has_power, "4 с без данных — ещё держим последнее")
	_tick_n(_hub, 2)
	var stale := _hub_samples[20]
	assert_false(stale.has_power, "≥ 5 с без данных → «нет данных»")
	assert_false(stale.has_cadence)
	assert_false(stale.has_speed)
	assert_eq(_hub_hr.size(), 19, "пульс станка тоже устарел")
	assert_eq(_hub.power_source_in_use(), SensorHub.SOURCE_NONE)
	_tick_n(_hub, 20)
	assert_eq(_hub_samples.size(), 41)
	assert_true(_hub_samples[40].has_power, "после восстановления данные снова есть")


func test_req_dev_03_c3_hrs_priority_over_trainer_hr_and_no_contact_5s_gives_no_hr() -> void:
	_make_hub()
	_fake.set_heart_rate(140)
	_hrs_in_hub()
	_bridge.emit_notification("hrs", "2A37", _hex("06 48"))
	_hub.tick(1.0)
	assert_eq(_hub_hr, [72] as Array[int], "HRS (72) приоритетнее пульса станка (140)")
	assert_eq(_hub.heart_rate_source_in_use(), SensorHub.SOURCE_HEART_RATE_SENSOR)
	# HRS без контакта: последнее достоверное (t=0) держится до 5 с → с t=5 уступает станку.
	for i in 6:
		_bridge.emit_notification("hrs", "2A37", _hex("04 48"))  # нет контакта
		_hub.tick(1.0)
	assert_eq(_hub_hr.slice(1, 4), [72, 72, 72] as Array[int], "t=2..4 (< 5 с от последнего достоверного) — 72")
	assert_eq(_hub_hr[4], 140, "t=5 — ровно 5 с без достоверного HRS → пульс станка")
	assert_eq(_hub_hr.back(), 140)
	assert_eq(_hub.heart_rate_source_in_use(), SensorHub.SOURCE_TRAINER)
	# Без пульса на станке — хаб вообще без пульса (не 0).
	_fake.set_heart_rate(0)
	_tick_n(_hub, 6)
	var n := _hub_hr.size()
	_hub.tick(1.0)
	assert_eq(_hub_hr.size(), n, "нет ни одного источника → heart_rate не испускается")
	assert_eq(_hub.heart_rate_source_in_use(), SensorHub.SOURCE_NONE)
	# Контакт вернулся — HRS снова в приоритете.
	_bridge.emit_notification("hrs", "2A37", _hex("06 50"))
	_hub.tick(1.0)
	assert_eq(_hub_hr.back(), 80)


func test_req_dev_04_c4_csc_priority_zero_after_3s_then_yields_to_trainer_after_3s_silence() -> void:
	_make_hub()
	_hub.set_target_power(150)
	_tick_n(_hub, 3)
	assert_eq(_hub_samples.back().cadence_rpm, 85, "без датчика — каденс станка")
	_csc_in_hub()
	_bridge.emit_notification("csc", "2A5B", _hex("02 0A 00 00 08"))
	_hub.tick(1.0)
	assert_eq(_hub_samples.back().cadence_rpm, 85, "одно измерение CSC — ещё нет каденса, станок")
	_bridge.emit_notification("csc", "2A5B", _hex("02 0D 00 00 10"))
	_hub.tick(1.0)
	assert_eq(_hub_samples.back().cadence_rpm, 90, "CSC 90 приоритетнее станка 85")
	assert_eq(_hub.cadence_source_in_use(), SensorHub.SOURCE_CADENCE_SENSOR)
	# Н-4 (а): остановили педали, пакеты идут с тем же счётчиком → с 3-го пакета (≥ 3 с) 0 → хаб 0 (не 85).
	for i in 3:
		_bridge.emit_notification("csc", "2A5B", _hex("02 0D 00 00 10"))
		_hub.tick(1.0)
	assert_eq(_hub_samples.back().cadence_rpm, 0, "пакеты идут, обороты стоят ≥ 3 с → 0 от датчика")
	assert_eq(_hub.cadence_source_in_use(), SensorHub.SOURCE_CADENCE_SENSOR)
	# Н-4 (б): датчик замолчал (последний пакет — на предыдущей секунде) — без удержания нуля:
	# через 3 с тишины каденс уступает станку.
	_tick_n(_hub, 1)
	assert_eq(_hub_samples.back().cadence_rpm, 0, "2 с тишины — последнее значение датчика")
	assert_eq(_hub.cadence_source_in_use(), SensorHub.SOURCE_CADENCE_SENSOR)
	_hub.tick(1.0)
	assert_eq(_hub_samples.back().cadence_rpm, 85, "3 с тишины CSC → каденс станка (ложного нуля нет)")
	assert_eq(_hub.cadence_source_in_use(), SensorHub.SOURCE_TRAINER)
	assert_true(_hub_samples.back().has_power, "мощность/скорость станка по-прежнему живы (их порог 5 с)")
	# Датчик вернулся — снова приоритет CSC.
	_bridge.emit_notification("csc", "2A5B", _hex("02 0F 00 00 18"))  # 2 оборота за 2 с → 60
	_hub.tick(1.0)
	assert_eq(_hub_samples.back().cadence_rpm, 60)
	assert_eq(_hub.cadence_source_in_use(), SensorHub.SOURCE_CADENCE_SENSOR)


func test_req_dev_05_c2_power_source_selection_and_fallback() -> void:
	_make_hub()
	_hub.set_target_power(150)
	_pm_in_hub()
	_bridge.emit_notification("pm", "2A63", _hex("00 00 FA 00"))
	_hub.tick(1.0)
	assert_eq(_hub.power_source, SensorHub.SOURCE_TRAINER, "по умолчанию — станок")
	assert_ne(_hub_samples.back().power_w, 250, "мощность станка, не измерителя")
	assert_eq(_hub.power_source_in_use(), SensorHub.SOURCE_TRAINER)
	_hub.set_power_source(SensorHub.SOURCE_POWER_METER)
	_bridge.emit_notification("pm", "2A63", _hex("00 00 FA 00"))
	_hub.tick(1.0)
	assert_eq(_hub_samples.back().power_w, 250, "выбран измеритель → 250")
	assert_eq(_hub.power_source_in_use(), SensorHub.SOURCE_POWER_METER)
	assert_true(_hub_samples.back().has_speed, "скорость — по-прежнему от станка")
	# Измеритель замолчал 5 с → запасной источник (станок).
	_tick_n(_hub, 5)
	assert_ne(_hub_samples.back().power_w, 250)
	assert_true(_hub_samples.back().has_power)
	assert_eq(_hub.power_source_in_use(), SensorHub.SOURCE_TRAINER)
	# Измеритель ожил — снова он.
	_bridge.emit_notification("pm", "2A63", _hex("00 00 2C 01"))
	_hub.tick(1.0)
	assert_eq(_hub_samples.back().power_w, 300)
	assert_eq(_hub.power_source_in_use(), SensorHub.SOURCE_POWER_METER)
	# Выбор источника при отсутствующем измерителе — запасной станок, без падения.
	_hub.set_power_meter(null)
	_hub.tick(1.0)
	assert_true(_hub_samples.back().has_power)
	assert_eq(_hub.power_source_in_use(), SensorHub.SOURCE_TRAINER)


func test_req_dev_05_c3_cps_cadence_used_without_csc_and_csc_wins_when_both() -> void:
	_make_hub()
	_hub.set_target_power(150)
	_pm_in_hub()
	_bridge.emit_notification("pm", "2A63", _hex("20 00 FA 00 0A 00 00 08"))
	_hub.tick(1.0)
	_bridge.emit_notification("pm", "2A63", _hex("20 00 FA 00 0D 00 00 10"))  # 90 rpm
	_hub.tick(1.0)
	assert_eq(_hub_samples.back().cadence_rpm, 90, "без CSC — каденс из crank data CPS")
	assert_eq(_hub.cadence_source_in_use(), SensorHub.SOURCE_POWER_METER)
	# Подключили CSC с другим каденсом — CSC побеждает.
	_csc_in_hub()
	_bridge.emit_notification("csc", "2A5B", _hex("02 00 00 00 00"))
	_hub.tick(1.0)
	_bridge.emit_notification("csc", "2A5B", _hex("02 02 00 00 04"))  # 2 оборота за 1 с → 120
	_bridge.emit_notification("pm", "2A63", _hex("20 00 FA 00 10 00 00 18"))  # CPS: 3 оборота/2 с → 90
	_hub.tick(1.0)
	assert_eq(_hub_samples.back().cadence_rpm, 120, "CSC и CPS одновременно → CSC")
	assert_eq(_hub.cadence_source_in_use(), SensorHub.SOURCE_CADENCE_SENSOR)
	# Снятие датчика CSC → CPS; снятие измерителя → станок.
	_hub.set_cadence_sensor(null)
	_bridge.emit_notification("pm", "2A63", _hex("20 00 FA 00 13 00 00 20"))  # ещё 3/2 с → 90
	_hub.tick(1.0)
	assert_eq(_hub_samples.back().cadence_rpm, 90, "CSC снят → crank data CPS")
	_hub.set_power_meter(null)
	_hub.tick(1.0)
	assert_eq(_hub_samples.back().cadence_rpm, 85, "измеритель снят → каденс станка")
	assert_eq(_hub.cadence_source_in_use(), SensorHub.SOURCE_TRAINER)
	# Снятые датчики больше не влияют на хаб даже при нотификациях.
	_bridge.emit_notification("csc", "2A5B", _hex("02 04 00 00 08"))
	_hub.tick(1.0)
	assert_eq(_hub_samples.back().cadence_rpm, 85)


func test_hub_removing_hrs_yields_to_trainer_and_hub_over_ble_trainer_delegates() -> void:
	_make_hub()
	_fake.set_heart_rate(140)
	_hrs_in_hub()
	_bridge.emit_notification("hrs", "2A37", _hex("06 48"))
	_hub.tick(1.0)
	assert_eq(_hub_hr.back(), 72)
	_hub.set_heart_rate_sensor(null)
	_hub.tick(1.0)
	assert_eq(_hub_hr.back(), 140, "датчик снят → пульс станка сразу")
	# Хаб поверх BleTrainer: делегирование команд и состояния.
	_connect()
	var hub2 := SensorHub.new(_t)
	var st: Array[int] = []
	hub2.connection_state_changed.connect(func(s: int) -> void: st.append(s))
	assert_eq(hub2.get_connection_state(), TrainerDevice.ConnectionState.CONNECTED)
	hub2.set_target_power(250)
	assert_eq(_cp_writes(), ["05 FA 00"] as Array[String], "команда хаба доходит до Control Point")
	_bridge.emit_disconnected(DEV, BleBridge.DisconnectReason.LINK_LOSS)
	assert_eq(st, [TrainerDevice.ConnectionState.RECONNECTING] as Array[int], "состояние станка пробрасывается")
	_bridge.pump()
	assert_eq(hub2.get_connection_state(), TrainerDevice.ConnectionState.CONNECTED)
