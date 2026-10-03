extends GutTest
## SIM-режим эмулятора FakeTrainer (REQ-FRD-04 крит. 1, 3, 6; REQ-FRD-01 крит. 2).

var _t: FakeTrainer
var _errors: Array[Dictionary] = []


func before_each() -> void:
	_errors = []
	_t = FakeTrainer.new(7)
	_t.error.connect(_on_error)


func _on_error(code: int, message: String) -> void:
	_errors.append({"code": code, "message": message})


func _connect_now() -> void:
	_t.connect_delay_sec = 0.0
	_t.connect_device("fake-1")


func _sim_commands() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for c in _t.commands:
		if c["type"] == FakeTrainer.CMD_SIM:
			out.append(c)
	return out


func test_req_frd_04_cmd_sim_in_journal_with_time_and_params() -> void:
	_connect_now()
	_t.tick(2.5)
	_t.set_simulation(4.004)
	_t.set_simulation(-2.0, 1.5, 0.005, 0.3)
	var sims := _sim_commands()
	assert_eq(sims.size(), 2)
	assert_almost_eq(float(sims[0]["value"]), 4.0, 1e-9, "уклон округлён до 0.01 %")
	assert_almost_eq(float(sims[0]["at_sec"]), 2.5, 1e-9)
	assert_almost_eq(float(sims[0]["wind_mps"]), 0.0, 1e-9)
	assert_almost_eq(float(sims[0]["crr"]), 0.004, 1e-9, "Crr по умолчанию")
	assert_almost_eq(float(sims[0]["cw"]), 0.20, 1e-9, "Cw по умолчанию")
	assert_almost_eq(float(sims[1]["value"]), -2.0, 1e-9)
	assert_almost_eq(float(sims[1]["wind_mps"]), 1.5, 1e-9)
	assert_true(_t.simulation_active)
	assert_almost_eq(_t.simulation_grade_pct, -2.0, 1e-9)
	assert_eq(_errors.size(), 0)


func test_req_frd_01_c2_sim_turns_erg_off_without_journal_erg_or_power() -> void:
	_connect_now()
	_t.set_simulation(3.0)
	assert_false(_t.is_erg_enabled(), "SIM выключает ERG")
	for c in _t.commands:
		assert_eq(c["type"], FakeTrainer.CMD_SIM, "в журнале только SIM: %s" % str(c))


func test_power_in_sim_follows_rider_power() -> void:
	_connect_now()
	_t.set_target_power(300)  # ERG включён по умолчанию → 300 Вт
	_t.tick(5.0)
	_t.set_simulation(6.0)
	_t.set_rider_power(180)
	var samples: Array[TrainerSample] = []
	_t.telemetry.connect(func(s: TrainerSample) -> void: samples.append(s))
	_t.tick(10.0)
	assert_almost_eq(float(samples.back().power_w), 180.0, 5.0, "мощность задаёт всадник, ERG не включается")
	assert_false(_t.is_erg_enabled())


func test_mode_switches_leave_sim() -> void:
	_connect_now()
	_t.set_simulation(3.0)
	_t.set_resistance_level(40)
	assert_false(_t.simulation_active, "фиксированное сопротивление")
	_t.set_simulation(3.0)
	_t.set_erg_enabled(true)
	assert_false(_t.simulation_active)
	assert_true(_t.is_erg_enabled())


func test_req_frd_04_c6_unsupported_trainer_rejects_sim() -> void:
	_t.set_simulation_supported(false)
	_connect_now()
	assert_eq(_t.simulation_support(), TrainerDevice.SimulationSupport.UNSUPPORTED)
	_t.set_simulation(5.0)
	assert_eq(_sim_commands().size(), 1, "попытка журналируется")
	assert_eq(_errors.size(), 1)
	assert_eq(_errors[0]["code"], TrainerDevice.ErrorCode.SIMULATION_REJECTED)
	assert_false(_t.simulation_active, "не применено")
	assert_true(_t.is_erg_enabled(), "режим не изменился")
	# Следующая команда другого типа не задета.
	_t.set_resistance_level(30)
	assert_eq(_errors.size(), 1)


func test_supported_by_default() -> void:
	assert_eq(_t.simulation_support(), TrainerDevice.SimulationSupport.SUPPORTED)
	_t.set_simulation_supported(false)
	assert_eq(_t.simulation_support(), TrainerDevice.SimulationSupport.UNSUPPORTED)
	_t.set_simulation_supported(true)
	assert_eq(_t.simulation_support(), TrainerDevice.SimulationSupport.SUPPORTED)


func test_fail_next_command_on_sim_is_simulation_rejected_and_unsupported() -> void:
	_connect_now()
	_t.fail_next_command()
	_t.set_simulation(2.0)
	assert_eq(_errors[0]["code"], TrainerDevice.ErrorCode.SIMULATION_REJECTED)
	assert_eq(_t.simulation_support(), TrainerDevice.SimulationSupport.UNSUPPORTED)


func test_write_failure_on_sim_keeps_support() -> void:
	_connect_now()
	_t.fail_next_command(TrainerDevice.ErrorCode.WRITE_FAILED)
	_t.set_simulation(2.0)
	assert_eq(_errors[0]["code"], TrainerDevice.ErrorCode.WRITE_FAILED)
	assert_eq(_t.simulation_support(), TrainerDevice.SimulationSupport.SUPPORTED)
	assert_false(_t.simulation_active)


func test_sim_when_not_connected_is_not_connected_error() -> void:
	_t.set_simulation_supported(false)
	_t.fail_next_command()
	_t.set_simulation(2.0)
	assert_eq(_errors[0]["code"], TrainerDevice.ErrorCode.NOT_CONNECTED)
	assert_false(_t.simulation_active)
	# Отложенный отказ остался прежним — достаётся следующей команде как отказ Control Point.
	_connect_now()
	_t.set_target_power(200)
	assert_eq(_errors[1]["code"], TrainerDevice.ErrorCode.CONTROL_POINT_REJECTED)


func test_sim_accepted_while_reconnecting() -> void:
	_connect_now()
	_t.inject_dropout(3.0)
	_t.set_simulation(1.0)
	assert_true(_t.simulation_active)
	assert_eq(_errors.size(), 0)


func test_req_frd_04_c3_inclination_range_default_and_custom() -> void:
	assert_eq(_t.inclination_range(), Vector2(-10.0, 20.0), "запасной диапазон")
	_t.set_inclination_range(-15.0, 25.0)
	assert_eq(_t.inclination_range(), Vector2(-15.0, 25.0))
	_t.set_inclination_range(5.0, 5.0)
	assert_eq(_t.inclination_range(), Vector2(-15.0, 25.0), "некорректный диапазон не принимается")


func test_out_of_range_params_clamped() -> void:
	_connect_now()
	_t.set_simulation(400.0, 0.0, 0.1, 3.0)
	var c: Dictionary = _sim_commands()[0]
	assert_almost_eq(float(c["value"]), TrainerDevice.MAX_SIM_GRADE_PCT, 1e-9)
	assert_almost_eq(float(c["crr"]), TrainerDevice.MAX_SIM_CRR, 1e-9)
	assert_almost_eq(float(c["cw"]), TrainerDevice.MAX_SIM_CW, 1e-9)
	assert_eq(_errors.size(), 0)
