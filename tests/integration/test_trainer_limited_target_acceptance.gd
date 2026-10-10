extends GutTest
## Приёмка T-162 (tester): цель, ограниченная станком, — везде фактическая (REQ-DEV-10 п.6 второй
## абзац, У-26; HUD-01, HUD-02, HUD-10 (столбик текущего шага — толкование реестра), WRK-08 п.2) и
## «ERG недоступен» (DEV-10 п.5). Экран тренировки `workout_screen.tscn` + `BleTrainer` на
## `StubBleBridge` с фикстурой `0x2AD8` 25..1500 Вт, шаг 5; то же на `FakeTrainer`.

const SCENE: String = "res://src/ui/workout/workout_screen.tscn"
const DEV: String = "ftms-162"

var _now_usec: int = 0
var _bridge: StubBleBridge
var _ble: BleTrainer
var _profile: Profile
var _state: AppState
var _repo: ProfileRepository
var _dir: String
var _locale: String


func before_each() -> void:
	_now_usec = 3_000_000
	_locale = TranslationServer.get_locale()
	TranslationServer.set_locale("en")
	_dir = "user://acc_t162_%d_%d/" % [Time.get_ticks_usec(), randi() % 100000]
	_repo = ProfileRepository.new(_dir + "profiles/")
	_state = AppState.new(_repo)
	_profile = Profile.create("Rider")
	_profile.ftp_w = 200
	_bridge = null
	_ble = null


func after_each() -> void:
	TranslationServer.set_locale(_locale)
	if _ble != null:
		_ble.dispose()
	if _bridge != null:
		_bridge.dispose()


func _clock() -> int:
	return _now_usec


func _keep(_on: bool) -> void:
	pass


func _hex(s: String) -> PackedByteArray:
	var out := PackedByteArray()
	for part in s.split(" ", false):
		out.append(part.hex_to_int())
	return out


func _ble_trainer(extra_chars: Array = ["2AD8"], reads: Dictionary = {"2AD8": "19 00 DC 05 05 00"}) -> BleTrainer:
	_bridge = StubBleBridge.new()
	_bridge.set_device_services(DEV, {"1826": PackedStringArray(["2AD2", "2AD9", "2ADA"] + extra_chars)})
	for ch in reads:
		_bridge.set_read_value(str(ch), _hex(str(reads[ch])))
	_ble = TrainerFactory.create_ble(_bridge) as BleTrainer
	_ble.connect_device(DEV)
	for i in 4:
		_bridge.pump()
	assert_eq(_ble.get_connection_state(), TrainerDevice.ConnectionState.CONNECTED, "предусловие: станок подключён")
	return _ble


func _screen(plan: Workout, trainer: TrainerDevice) -> WorkoutScreen:
	var s: WorkoutScreen = load(SCENE).instantiate()
	s.clock_usec = _clock
	s.keep_awake_setter = _keep
	add_child_autofree(s)
	s.setup(plan, _profile, trainer, _state, null)
	assert_true(s.start(), "предусловие: экран запущен")
	return s


## Секунда: пакет станка с мощностью `power` (BLE) и тик экрана.
func _second(s: WorkoutScreen, power: int) -> void:
	if _bridge != null:
		_bridge.emit_notification(DEV, "2AD2", FtmsCodec.encode_indoor_bike_data(30.0, 88.0, power))
	_now_usec += 1_000_000
	if s.ticker() != null:
		s.ticker().poll()
	if _bridge != null:
		_bridge.pump()


func _targets_05() -> Array[String]:
	var out: Array[String] = []
	for w in _bridge.writes_to("2AD9"):
		var b: PackedByteArray = w["bytes"]
		if b.size() > 0 and b[0] == 0x05:
			out.append(b.hex_encode())
	return out


## Столбик текущего шага в профиле плана HUD-10.
func _current_bar(s: WorkoutScreen) -> Dictionary:
	var idx := s.session().executor.current_step_index()
	for seg in s.chart().plan_model().segments():
		if int(seg["index"]) == idx:
			return seg
	return {}


static func _plan_3() -> Workout:
	return Workout.make("lim", [WorkoutStep.watts(10, 1600.0), WorkoutStep.watts(10, 132.0), WorkoutStep.watts(10, 300.0)] as Array[WorkoutStep])


## Проверка шага: команда, HUD-01, HUD-02, сэмплы, столбик HUD-10.
func _check_step(s: WorkoutScreen, plan_w: int, want: int, cmd_hex: String, actual_power: int) -> void:
	var sess := s.session()
	assert_eq(sess.current_target_watts(), want, "%d → цель сессии %d" % [plan_w, want])
	assert_eq(s.target_text(), "%d W" % want, "HUD-01: на HUD «%d»" % want)
	if not cmd_hex.is_empty():
		assert_true(_targets_05().has(cmd_hex), "команда %s: %s" % [cmd_hex, str(_targets_05())])
	var st: Dictionary = s.hud().state()
	assert_eq(int(st["target_w"]), want)
	assert_eq(str(st["power_deviation"]), HudModel.deviation_state(int(st["power_w"]) if st.has("power_w") else actual_power, want),
		"HUD-02: отклонение от фактической цели")
	var k := sess.samples.size() - 1
	assert_eq(sess.samples.target_w[k], want, "WRK-08 п.2: в сэмпле %d" % want)
	var bar := _current_bar(s)
	gut.p("столбик текущего шага (план %d): %s→%s" % [plan_w, str(bar.get("start_watts")), str(bar.get("end_watts"))])
	assert_eq(int(bar.get("start_watts", -1)), want, "HUD-10: столбик текущего шага — %d (толкование реестра)" % want)


func test_req_dev_10_c6_hud_01_02_10_wrk_08_c2_limited_target_everywhere_ble() -> void:
	var t := _ble_trainer()
	var s := _screen(_plan_3(), t)
	for i in 5:
		_second(s, 1500)
	_check_step(s, 1600, 1500, "05dc05", 1500)
	assert_eq(str(s.hud().state()["power_deviation"]), HudModel.deviation_state(1500, 1500), "мощность 1500 при цели 1500 — в цели")
	for i in 7:
		_second(s, 130)
	_check_step(s, 132, 130, "058200", 130)
	for i in 10:
		_second(s, 300)
	_check_step(s, 300, 300, "052c01", 300)
	# Сэмплы шага 1 — все 1500.
	var samples := s.session().samples
	for i in range(1, 10):
		assert_eq(samples.target_w[i], 1500, "сэмпл %d шага 1600 → 1500" % i)


func test_req_dev_10_c6_intensity_110_of_1400_is_1500_everywhere() -> void:
	var t := _ble_trainer()
	var s := _screen(Workout.make("i", [WorkoutStep.watts(20, 1400.0)] as Array[WorkoutStep]), t)
	_second(s, 1400)
	s.session().set_intensity(1.1)
	for i in 3:
		_second(s, 1500)
	_check_step(s, 1540, 1500, "05dc05", 1500)
	assert_false(_targets_05().has("050406"), "1540 станку не уходит")


func test_req_dev_10_c6_fake_trainer_same_range_same_result() -> void:
	var fake := FakeTrainer.new(4)
	fake.connect_delay_sec = 0.0
	fake.power_noise_w = 0.0
	fake.power_range = {"min_w": 25, "max_w": 1500, "increment_w": 5}
	fake.connect_device("fake")
	var s := _screen(_plan_3(), fake)
	for i in 5:
		_second(s, -1)
	assert_eq(s.session().current_target_watts(), 1500)
	assert_eq(s.target_text(), "1500 W")
	assert_eq(s.session().samples.target_w[s.session().samples.size() - 1], 1500)
	assert_eq(int(_current_bar(s).get("start_watts", -1)), 1500, "HUD-10 (толкование реестра)")
	for i in 7:
		_second(s, -1)
	assert_eq(s.session().current_target_watts(), 130)
	assert_eq(s.target_text(), "130 W")
	var sent: Array[int] = []
	for c in fake.commands:
		if str(c.get("type", "")) == "target_power":
			sent.append(int(c.get("value", -1)))
	assert_true(sent.has(1500) and sent.has(130) and not sent.has(1600), "эмулятор получил 1500 и 130: %s" % str(sent))


func test_dev_10_c6_regression_in_range_target_equals_plan_and_fallback_range() -> void:
	var t := _ble_trainer([], {})
	var s := _screen(Workout.make("r", [WorkoutStep.watts(10, 1600.0), WorkoutStep.watts(10, 2400.0)] as Array[WorkoutStep]), t)
	for i in 3:
		_second(s, 1600)
	assert_eq(s.target_text(), "1600 W", "без 2AD8 цель 1600 в запасном диапазоне — как план")
	for i in 10:
		_second(s, 2000)
	assert_eq(s.target_text(), "2000 W", "2400 → 2000 (запасной диапазон, Н-61 (а) — ждёт решения)")
	assert_true(_targets_05().has("05d007"))


## DEV-10 п.5: бит 3 = 0 — ERG недоступен «как в п.4»: 0x05 не уходит, кнопка ERG неактивна.
func test_req_dev_10_c5_bit3_zero_erg_unavailable_no_05_on_screen() -> void:
	var t := _ble_trainer(["2ACC"], {"2ACC": "00 00 00 00 04 20 00 00"})
	assert_false(t.is_erg_available())
	var s := _screen(_plan_3(), t)
	for i in 3:
		_second(s, 150)
	assert_eq(_targets_05(), [] as Array[String], "0x05 не уходит")
	assert_true(s.toolbar().button(&"erg").disabled, "кнопка ERG неактивна")
	s.toolbar().trigger(&"erg")
	_second(s, 150)
	assert_eq(_targets_05(), [] as Array[String], "«включить ERG» команд не создаёт")


## DEV-10 п.5: ответ `80 05 02` на Set Target Power — ERG недоступен до конца подключения
## «с сообщением пользователю (DEV-02.3)»: сообщение должно быть видно на экране тренировки.
func test_req_dev_10_c5_80_05_02_visible_message_to_user() -> void:
	var t := _ble_trainer([], {})
	_bridge.fail_next_control_point(FtmsCodec.RESULT_NOT_SUPPORTED)
	var s := _screen(_plan_3(), t)
	for i in 3:
		_second(s, 150)
	assert_eq(_targets_05().size(), 1, "одна 0x05 и ответ 80 05 02")
	assert_false(s.session().erg_available(), "ERG недоступен")
	for i in 10:
		_second(s, 150)
	assert_eq(_targets_05().size(), 1, "дальше 0x05 не уходит")
	var texts: Array[String] = []
	for n in s.find_children("*", "Label", true, false):
		var l := n as Label
		if l.is_visible_in_tree() and not l.text.is_empty():
			texts.append(l.text)
	var shown := false
	for x in texts:
		if x.containsn("unavailable") or x.containsn("not supported") or x.containsn("rejected") or x.containsn("does not accept"):
			shown = true
	gut.p("видимые надписи: %s" % str(texts))
	assert_true(shown, "DEV-10 п.5 / DEV-02 п.3: сообщение об отказе ERG видно на экране (сейчас только tooltip фишки ERG)")
