extends GutTest
## SIM-режим BleTrainer на StubBleBridge (REQ-FRD-04 крит. 1, 3, 6; REQ-FRD-01 крит. 2;
## REQ-FRD-05 крит. 4 — переключение режима на уровне устройства).

const DEV: String = "tacx-neo"
## Набор FTMS-характеристик, как у станка с SIM.
const FTMS_CHARS: Array[String] = ["2AD2", "2AD9", "2ADA", "2AD6", "2ACC", "2AD5"]

var _bridge: StubBleBridge
var _t: BleTrainer
var _errors: Array[Dictionary] = []


func before_each() -> void:
	_errors = []
	_bridge = StubBleBridge.new()
	_t = BleTrainer.new(_bridge)
	_t.error.connect(_on_error)


func after_each() -> void:
	if _t != null:
		_t.dispose()
	if _bridge != null:
		_bridge.dispose()


func _on_error(code: int, message: String) -> void:
	_errors.append({"code": code, "message": message})


func _hex(s: String) -> PackedByteArray:
	return BleBytes.from_hex(s)


## Станок с SIM: 2ACC с битом 13, 2AD5 −10…+20 %, 2AD6 0…100.0.
func _setup_sim_trainer(sim_bit: bool = true) -> void:
	_bridge.set_device_services(DEV, {"1826": FTMS_CHARS})
	_bridge.set_read_value("2ACC", _hex("83 40 00 00 0C 20 00 00" if sim_bit else "83 40 00 00 0C 00 00 00"))
	_bridge.set_read_value("2AD5", _hex("9C FF C8 00 05 00"))
	_bridge.set_read_value("2AD6", _hex("00 00 E8 03 01 00"))


func _connect() -> void:
	_t.connect_device(DEV)
	_bridge.pump()


func _cp_writes() -> Array[String]:
	var out: Array[String] = []
	for w in _bridge.writes_to("2AD9"):
		out.append(BleBytes.to_hex(w["bytes"]))
	return out


func _reads() -> Array[String]:
	var out: Array[String] = []
	for r in _bridge.calls_of("read_characteristic"):
		out.append(r["char"])
	return out


# ---------------------------------------------------------------------------
# Чтение 2ACC и 2AD5 после подключения (REQ-FRD-04 крит. 3, 6)
# ---------------------------------------------------------------------------

func test_req_frd_04_reads_2acc_2ad5_after_connect_then_writes_0x11() -> void:
	_setup_sim_trainer()
	assert_eq(_t.simulation_support(), TrainerDevice.SimulationSupport.UNKNOWN, "до подключения")
	_connect()
	assert_eq(_t.get_connection_state(), TrainerDevice.ConnectionState.CONNECTED)
	var reads := _bridge.calls_of("read_characteristic")
	var chars := _reads()
	assert_true(chars.has("2ACC"), "2ACC прочитан: %s" % str(chars))
	assert_true(chars.has("2AD5"), "2AD5 прочитан: %s" % str(chars))
	for r in reads:
		if r["char"] == "2ACC" or r["char"] == "2AD5":
			assert_eq(r["service"], "1826", "чтение из FTMS (read_characteristic(id, 0x1826, …))")
			assert_eq(r["id"], DEV)
	var first_read: int = _bridge.calls.find(reads[0])
	var request_control: int = _bridge.calls.find(_bridge.writes_to("2AD9")[0])
	assert_true(first_read > request_control, "чтения — после Request Control")
	assert_eq(_t.simulation_support(), TrainerDevice.SimulationSupport.SUPPORTED)
	assert_eq(_t.inclination_range(), Vector2(-10.0, 20.0))
	assert_almost_eq(float(_t.supported_inclination["increment_pct"]), 0.5, 1e-9)
	var calls_before: int = _bridge.calls.size()
	_t.set_simulation(5.0)
	assert_eq(_cp_writes(), ["00", "11 00 00 F4 01 28 14"] as Array[String])
	var w: Dictionary = _bridge.writes_to("2AD9")[1]
	assert_eq(_bridge.calls.find(w), calls_before, "запись 0x11 — после чтений")
	assert_true(w["with_response"], "Control Point — Write Request")
	assert_eq(w["service"], "1826")
	_bridge.pump()
	assert_eq(_errors.size(), 0)
	assert_false(_t.has_control_point_in_flight(), "ответ 80 11 01 принят")
	assert_eq(_t.simulation_support(), TrainerDevice.SimulationSupport.SUPPORTED)


func test_req_frd_04_c3_wide_inclination_range_from_trainer() -> void:
	_setup_sim_trainer()
	_bridge.set_read_value("2AD5", _hex("38 FF 90 01 01 00"))
	_connect()
	assert_eq(_t.inclination_range(), Vector2(-20.0, 40.0))


func test_req_frd_04_c3_fallback_range_when_2ad5_absent_or_unreadable() -> void:
	# 2AD5 не заявлен — не читается, диапазон запасной.
	_bridge.set_device_services(DEV, {"1826": ["2AD2", "2AD9", "2ADA", "2ACC"]})
	_bridge.set_read_value("2ACC", _hex("83 40 00 00 0C 20 00 00"))
	_connect()
	assert_false(_reads().has("2AD5"))
	assert_eq(_t.inclination_range(), Vector2(-10.0, 20.0))
	assert_eq(_errors.size(), 0)
	# Заявлен, но чтение без ответа (CHARACTERISTIC_NOT_FOUND) — тоже запасной, не ошибка станка.
	var b2 := StubBleBridge.new()
	b2.set_device_services("x", {"1826": ["2AD2", "2AD9", "2ADA", "2AD5"]})
	var t2 := BleTrainer.new(b2)
	t2.error.connect(_on_error)
	t2.connect_device("x")
	b2.pump()
	assert_true((b2.calls_of("read_characteristic").map(func(c: Dictionary) -> String: return c["char"])).has("2AD5"))
	assert_eq(t2.inclination_range(), Vector2(TrainerDevice.DEFAULT_INCLINATION_MIN_PCT,
		TrainerDevice.DEFAULT_INCLINATION_MAX_PCT))
	assert_eq(_errors.size(), 0)
	t2.dispose()
	b2.dispose()


func test_bad_2ad5_keeps_fallback() -> void:
	_setup_sim_trainer()
	_bridge.set_read_value("2AD5", _hex("C8 00 9C FF"))
	_connect()
	assert_eq(_t.inclination_range(), Vector2(-10.0, 20.0))
	assert_true(_t.supported_inclination.is_empty())


func test_unknown_services_do_not_read_sim_characteristics() -> void:
	_connect()
	assert_false(_reads().has("2ACC"))
	assert_false(_reads().has("2AD5"))
	assert_eq(_t.simulation_support(), TrainerDevice.SimulationSupport.UNKNOWN)


# ---------------------------------------------------------------------------
# Определение поддержки (REQ-FRD-04 крит. 6)
# ---------------------------------------------------------------------------

func test_req_frd_04_c6_bit_clear_is_unsupported() -> void:
	_setup_sim_trainer(false)
	_connect()
	assert_eq(_t.simulation_support(), TrainerDevice.SimulationSupport.UNSUPPORTED)


func test_req_frd_04_c6_response_0x02_is_error_and_unsupported() -> void:
	_setup_sim_trainer()
	_connect()
	assert_eq(_t.simulation_support(), TrainerDevice.SimulationSupport.SUPPORTED)
	_bridge.fail_next_control_point(FtmsCodec.RESULT_NOT_SUPPORTED)
	_t.set_simulation(3.0)
	_bridge.pump()
	assert_eq(_errors.size(), 1)
	assert_eq(_errors[0]["code"], TrainerDevice.ErrorCode.SIMULATION_REJECTED)
	assert_eq(_t.simulation_support(), TrainerDevice.SimulationSupport.UNSUPPORTED)
	assert_false(_t.simulation_active, "SIM снят: станок остался в прежнем режиме")
	assert_eq(_t.get_connection_state(), TrainerDevice.ConnectionState.CONNECTED, "сессия не прерывается")
	assert_false(_t.has_control_point_in_flight(), "Control Point освобождён")


func test_rejection_is_sticky_on_reconnect_and_reset_for_other_trainer() -> void:
	_setup_sim_trainer()
	_connect()
	_bridge.fail_next_control_point(FtmsCodec.RESULT_NOT_SUPPORTED)
	_t.set_simulation(3.0)
	_bridge.pump()
	# Переподключение к тому же станку: 2ACC перечитан, но отказ помним.
	_bridge.emit_disconnected(DEV, BleBridge.DisconnectReason.LINK_LOSS)
	_bridge.pump()
	assert_eq(_t.get_connection_state(), TrainerDevice.ConnectionState.CONNECTED)
	assert_eq(_t.simulation_support(), TrainerDevice.SimulationSupport.UNSUPPORTED)
	# Другой станок — поддержка определяется заново.
	_t.disconnect_device()
	_bridge.pump()
	_bridge.set_device_services("neo-2", {"1826": FTMS_CHARS})
	_t.connect_device("neo-2")
	_bridge.pump()
	assert_eq(_t.get_connection_state(), TrainerDevice.ConnectionState.CONNECTED)
	assert_eq(_t.simulation_support(), TrainerDevice.SimulationSupport.SUPPORTED)


func test_success_response_marks_supported_when_feature_unknown() -> void:
	_connect()  # список сервисов неизвестен — 2ACC не читается
	assert_eq(_t.simulation_support(), TrainerDevice.SimulationSupport.UNKNOWN)
	_t.set_simulation(1.0)
	_bridge.pump()
	assert_eq(_t.simulation_support(), TrainerDevice.SimulationSupport.SUPPORTED)


func test_other_command_rejection_stays_control_point_rejected() -> void:
	_setup_sim_trainer()
	_connect()
	_bridge.fail_next_control_point(FtmsCodec.RESULT_INVALID_PARAMETER)
	_t.set_target_power(200)
	_bridge.pump()
	assert_eq(_errors[0]["code"], TrainerDevice.ErrorCode.CONTROL_POINT_REJECTED)
	assert_eq(_t.simulation_support(), TrainerDevice.SimulationSupport.SUPPORTED)


# ---------------------------------------------------------------------------
# Команда SIM и режимы
# ---------------------------------------------------------------------------

func test_set_simulation_defaults_rounding_and_params() -> void:
	_setup_sim_trainer()
	_connect()
	_t.set_simulation(12.344)
	_bridge.pump()
	_t.set_simulation(-3.0, 1.5, 0.005, 0.3)
	_bridge.pump()
	assert_eq(_cp_writes().slice(1), ["11 00 00 D2 04 28 14", "11 DC 05 D4 FE 32 1E"] as Array[String])
	assert_almost_eq(_t.simulation_params[0], -3.0, 1e-9)


func test_set_simulation_clamps_out_of_range() -> void:
	_setup_sim_trainer()
	_connect()
	_t.set_simulation(500.0, -50.0, 1.0, -1.0)
	_bridge.pump()
	assert_eq(_cp_writes().back(), "11 01 80 FF 7F FF 00", "обрезано до пределов типов")
	_t.set_simulation(NAN)
	_bridge.pump()
	assert_eq(_cp_writes().back(), "11 00 00 00 00 28 14", "NaN → 0 %")


func test_req_frd_01_c2_sim_turns_erg_off_without_target_power() -> void:
	_setup_sim_trainer()
	_connect()
	_t.set_target_power(250)  # запомнено, ERG по умолчанию включён → 05 уходит
	_bridge.pump()
	_bridge.clear_calls()
	_t.set_simulation(2.0)
	_bridge.pump()
	assert_false(_t.is_erg_enabled(), "SIM выключает ERG")
	assert_true(_t.simulation_active)
	_t.set_target_power(300)
	_bridge.pump()
	assert_eq(_cp_writes(), ["11 00 00 C8 00 28 14"] as Array[String], "в SIM цель только запоминается, 0x05 нет")
	assert_eq(_t.target_power_w, 300)


func test_sim_before_connect_is_memorized_not_written() -> void:
	_setup_sim_trainer()
	_t.set_simulation(4.0)
	assert_eq(_bridge.calls.size(), 0)
	_connect()
	assert_eq(_cp_writes(), ["00"] as Array[String], "после CONNECTED режим повторяет вызывающий")
	assert_true(_t.simulation_active)


func test_req_frd_05_c4_resistance_level_leaves_sim() -> void:
	_setup_sim_trainer()
	_connect()
	_t.set_simulation(4.0)
	_bridge.pump()
	_t.set_resistance_level(50)
	_bridge.pump()
	assert_false(_t.simulation_active)
	assert_false(_t.is_erg_enabled())
	assert_eq(_cp_writes().back().substr(0, 2), "04", "фиксированное сопротивление")
	_t.set_simulation(4.0)
	_bridge.pump()
	assert_eq(_cp_writes().back(), "11 00 00 90 01 28 14", "обратно в SIM")


func test_erg_off_in_sim_switches_to_resistance_and_erg_on_leaves_sim() -> void:
	_setup_sim_trainer()
	_connect()
	_t.set_resistance_level(20)
	_t.set_simulation(4.0)
	_bridge.pump()
	_t.set_erg_enabled(false)
	_bridge.pump()
	assert_false(_t.simulation_active)
	assert_eq(_cp_writes().back().substr(0, 2), "04")
	_t.set_simulation(4.0)
	_t.set_target_power(200)
	_t.set_erg_enabled(true)
	_bridge.pump()
	assert_false(_t.simulation_active)
	assert_eq(_cp_writes().back(), "05 C8 00")


func test_resistance_range_arrival_in_sim_does_not_write_level() -> void:
	_setup_sim_trainer()
	_connect()
	_t.set_simulation(4.0)
	_bridge.pump()
	_bridge.clear_calls()
	_bridge.emit_characteristic_read(DEV, "2AD6", _hex("00 00 C8 00 0A 00"))
	_bridge.pump()
	assert_eq(_cp_writes().size(), 0)


func test_sim_evicts_queued_resistance_and_is_restored_after_permission_lost() -> void:
	_setup_sim_trainer()
	_connect()
	_bridge.auto_control_point_response = false
	_t.set_target_power(200)            # в полёте
	_t.set_erg_enabled(false)           # 04 в очереди
	_t.set_simulation(6.0)              # вытесняет 04
	assert_eq(_t.pending_control_point_commands().size(), 1)
	assert_eq(BleBytes.to_hex(_t.pending_control_point_commands()[0]), "11 00 00 58 02 28 14")
	_t.set_simulation(7.0)              # заменяет предыдущую 11
	assert_eq(_t.pending_control_point_commands().size(), 1)
	assert_eq(BleBytes.to_hex(_t.pending_control_point_commands()[0]), "11 00 00 BC 02 28 14")
	_bridge.auto_control_point_response = true
	_bridge.emit_notification(DEV, "2AD9", _hex("80 05 01"))
	_bridge.pump()
	assert_eq(_cp_writes().back(), "11 00 00 BC 02 28 14")
	# Станок отозвал управление — после Request Control снова уходит SIM.
	_bridge.clear_calls()
	_bridge.emit_notification(DEV, "2ADA", _hex("FF"))
	_bridge.pump()
	assert_eq(_cp_writes(), ["00", "11 00 00 BC 02 28 14"] as Array[String])
	assert_eq(_errors.size(), 0)


func test_opcode_0x11_is_never_sent_without_set_simulation() -> void:
	_setup_sim_trainer()
	_connect()
	_t.set_target_power(200)
	_t.set_erg_enabled(false)
	_t.set_resistance_level(30)
	_bridge.pump()
	for w in _cp_writes():
		assert_false(w.begins_with("11"))
