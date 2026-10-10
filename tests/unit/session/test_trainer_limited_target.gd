extends GutTest
## T-162: цель, ограниченная станком, — везде фактическая (REQ-DEV-10 п.6, У-26): команда, HUD
## (HUD-01, HUD-02), поле цели сэмпла (WRK-08 п.2), столбик текущего шага HUD-10; «ERG недоступен» —
## отдельное состояние сессии и HUD (DEV-10 п.5).

const DEV: String = "t"
const FTP: int = 200

var _bridge: StubBleBridge
var _t: BleTrainer


func before_each() -> void:
	_bridge = StubBleBridge.new()
	_t = null


func after_each() -> void:
	if _t != null:
		_t.dispose()
	_bridge.dispose()


## FTMS-станок с 0x2AD8 25..1500 Вт, шаг 5 (и, если задано, 0x2ACC).
func _ble(feature_hex: String = "") -> BleTrainer:
	var chars := PackedStringArray(["2AD2", "2AD9", "2ADA", "2AD6", "2AD8"])
	if not feature_hex.is_empty():
		chars.append("2ACC")
		_bridge.set_read_value("2ACC", BleBytes.from_hex(feature_hex))
	_bridge.set_device_services(DEV, {"1826": chars})
	_bridge.set_read_value("2AD8", BleBytes.from_hex("1900DC050500"))
	_t = BleTrainer.new(_bridge)
	_t.connect_device(DEV)
	for i in 4:
		_bridge.pump()
	assert_eq(_t.get_connection_state(), TrainerDevice.ConnectionState.CONNECTED)
	return _t


func _fake() -> FakeTrainer:
	var f := FakeTrainer.new(3)
	f.connect_delay_sec = 0.0
	f.power_noise_w = 0.0
	f.power_range = {"min_w": 25, "max_w": 1500, "increment_w": 5}
	f.connect_device("f")
	f.tick(0.1)
	return f


func _plan() -> Workout:
	return Workout.make("lim", [WorkoutStep.watts(10, 1600.0), WorkoutStep.watts(10, 132.0),
		WorkoutStep.watts(10, 300.0)] as Array[WorkoutStep])


func _run(device: TrainerDevice, plan: Workout, intensity: float = 1.0) -> Dictionary:
	var s := WorkoutSession.new(plan, device, FTP, intensity)
	var hud := HudModel.new(s)
	var chart := PlanChartModel.for_session(s)
	s.start()
	var hud_targets: Array[int] = []
	var chart_targets: Array[int] = []
	while s.get_state() != WorkoutSession.State.FINISHED:
		s.tick(1.0)
		_bridge.pump()
		chart.sync(s)
		if s.get_state() != WorkoutSession.State.FINISHED:
			hud_targets.append(int(hud.state()["target_w"]))
			for p: Dictionary in chart.pieces():
				if bool(p.get("current", false)):
					chart_targets.append(int(p["start_watts"]))
					break
	return {"session": s, "hud": hud_targets, "chart": chart_targets}


func _cp_targets() -> Array[int]:
	var out: Array[int] = []
	for c in _bridge.calls_of("write"):
		var b: PackedByteArray = c["bytes"]
		if BleUuids.normalize(str(c["char"])) == BleUuids.FTMS_CONTROL_POINT and b[0] == FtmsCodec.OP_SET_TARGET_POWER:
			out.append(BleBytes.s16(b, 1))
	return out


func test_req_dev_10_c6_limited_target_everywhere_ble() -> void:
	var r := _run(_ble(), _plan())
	var s: WorkoutSession = r["session"]
	assert_eq(_cp_targets(), [1500, 130, 300] as Array[int], "команды: 05 DC 05, 05 82 00, 05 2C 01")
	for i in 10:
		assert_eq(s.samples.target_w[i], 1500, "сэмпл %d: цель 1500" % i)
		assert_eq(s.samples.target_w[10 + i], 130, "сэмпл %d: цель 130" % (10 + i))
		assert_eq(s.samples.target_w[20 + i], 300, "сэмпл %d: цель 300 (регрессия)" % (20 + i))
	assert_eq((r["hud"] as Array).slice(0, 9), [1500, 1500, 1500, 1500, 1500, 1500, 1500, 1500, 1500], "HUD-01: 1500")
	assert_has(r["hud"], 130)
	assert_has(r["chart"], 1500, "HUD-10: столбик текущего шага — 1500")
	assert_has(r["chart"], 130)
	assert_eq(s.planned_target_watts(), 300, "цель плана доступна отдельно")


func test_req_dev_10_c6_intensity_110_of_1400_limited_to_1500() -> void:
	var r := _run(_ble(), Workout.make("i", [WorkoutStep.watts(5, 1400.0)] as Array[WorkoutStep]), 1.1)
	var s: WorkoutSession = r["session"]
	assert_eq(_cp_targets(), [1500] as Array[int], "1540 → 1500")
	assert_eq(s.samples.target_w[2], 1500)
	assert_eq((r["hud"] as Array)[0], 1500)


func test_req_dev_10_c6_fake_trainer_same_result() -> void:
	var f := _fake()
	var r := _run(f, _plan())
	var s: WorkoutSession = r["session"]
	assert_eq(s.samples.target_w[3], 1500)
	assert_eq(s.samples.target_w[13], 130)
	assert_eq(s.samples.target_w[23], 300)
	assert_has(r["chart"], 1500)


func test_req_dev_10_c5_erg_unavailable_is_state_not_target_command() -> void:
	# Target Setting Features без бита 3 (только сопротивление).
	var tsf := BleBytes.to_hex(FtmsCodec.encode_fitness_machine_feature(0, FtmsCodec.TSF_RESISTANCE)).replace(" ", "")
	var t := _ble(tsf)
	var s := WorkoutSession.new(_plan(), t, FTP)
	var hud := HudModel.new(s)
	assert_false(s.erg_available(), "ERG недоступен — состояние сессии")
	s.start()
	for i in 12:
		s.tick(1.0)
		_bridge.pump()
	assert_eq(_cp_targets(), [] as Array[int], "цели на станок не уходят")
	assert_false(hud.state()["erg_available"], "HUD знает состояние")
	assert_false(s.is_erg_active_on_trainer())
	assert_eq(s.samples.target_w[11], 132, "цель сэмпла — как сейчас (цель плана)")
	var levels := 0
	for c in _bridge.calls_of("write"):
		if (c["bytes"] as PackedByteArray)[0] == FtmsCodec.OP_SET_TARGET_RESISTANCE:
			levels += 1
	assert_gt(levels, 0, "станок — на фиксированном сопротивлении")


func test_erg_unavailable_after_not_supported_response_switches_session() -> void:
	var t := _ble()
	var s := WorkoutSession.new(_plan(), t, FTP)
	var changes: Array[bool] = []
	s.erg_availability_changed.connect(func(a: bool) -> void: changes.append(a))
	_bridge.fail_next_control_point(FtmsCodec.RESULT_NOT_SUPPORTED)
	s.start()
	_bridge.pump()
	_bridge.pump()
	assert_eq(changes, [false] as Array[bool], "сигнал «ERG недоступен»")
	assert_false(s.erg_available())
	s.tick(1.0)
	_bridge.pump()
	assert_eq(s.samples.target_w[0], 1600, "без ERG — цель плана")
