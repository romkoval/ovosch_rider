extends GutTest
## Приёмка T-069 (tester): FIT свободной езды. REQ-FRD-07 крит. 5 (`distance`, высота,
## `grade` в каждом `record`; `total_distance`, `total_ascent` в `session`; `lap` на круг
## трассы плюс неполный последний); регрессия REQ-LOC-05 крит. 1–4 (заезд по плану
## кодируется побайтно как до T-069).
##
## Отличия от тестов разработчика: заезд получен настоящей `FreeRideSession` на
## `FakeTrainer`, записан `RideRecorder` на диск и прочитан обратно; номера полей и масштабы
## FIT — литералы профиля FIT SDK в тесте, а не константы кода; регрессия LOC-05 —
## сравнение байтов с эталоном, который выдал кодировщик до T-069 (коммит 356b940,
## `tests/fixtures/fit/fit_workout_*.fit`, вход — `fit_workout_rides.json`; отличаться может
## только `activity.local_timestamp` — часовой пояс машины — и, значит, CRC файла).

const FIXTURES: String = "res://tests/fixtures/fit/"
const FIXTURE_KEYS: Array[String] = ["600", "short", "empty"]

# Литералы профиля FIT SDK (Profile.xlsx).
const MSG_SESSION: int = 18
const MSG_LAP: int = 19
const MSG_RECORD: int = 20
const MSG_EVENT: int = 21
const MSG_ACTIVITY: int = 34
const F_TIMESTAMP: int = 253
const REC_ALTITUDE: int = 2
const REC_HEART_RATE: int = 3
const REC_DISTANCE: int = 5
const REC_POWER: int = 7
const REC_GRADE: int = 9
const REC_ENH_ALTITUDE: int = 78
const LAP_TOTAL_DISTANCE: int = 9
const LAP_TRIGGER: int = 24
const SES_SUB_SPORT: int = 6
const SES_ELAPSED: int = 7
const SES_TIMER: int = 8
const SES_TOTAL_DISTANCE: int = 9
const SES_TOTAL_ASCENT: int = 22
const SES_NUM_LAPS: int = 26
const ACT_LOCAL_TIMESTAMP: int = 5

var _dir: String = ""


func after_each() -> void:
	if not _dir.is_empty():
		_remove_tree(ProjectSettings.globalize_path(_dir))
		_dir = ""


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


static func _f(msg: Dictionary, field: int) -> Variant:
	return (msg["fields"] as Dictionary).get(field, null)


## Свободная езда настоящей сессией: `seconds` секунд при `power` Вт, с паузой в середине;
## записывается `RideRecorder` и читается с диска.
func _recorded_free_ride(route: String, seconds: int, power: int, with_pause: bool) -> Ride:
	_dir = "user://acc_fit_free_%d/" % Time.get_ticks_usec()
	var repo := FileRideRepository.new(_dir + "rides/")
	var profile := Profile.create("FIT")
	var ft := FakeTrainer.new(31)
	ft.connect_delay_sec = 0.0
	ft.set_rider_power(power)
	ft.connect_device("fake")
	var s := FreeRideSession.new(ft, route, 50, 75.0, 250)
	var rec := RideRecorder.new(repo, profile, s)
	s.start()
	for i in seconds:
		s.tick(1.0)
		if with_pause and i == seconds / 2:
			s.pause()
			s.tick(12.0)
			s.resume()
	s.stop()
	var r := FileRideRepository.new(_dir + "rides/").get_ride(rec.ride_id())
	s.dispose()
	assert_not_null(r, "заезд прочитан с диска")
	return r


func _decode(bytes: PackedByteArray) -> FitDecoder.Result:
	var res := FitDecoder.decode(bytes)
	assert_true(res.ok, "FIT разбирается: %s" % res.error)
	assert_true(res.header_crc_ok, "CRC заголовка")
	assert_true(res.file_crc_ok, "CRC файла")
	return res


# ---------------------------------------------------------------------------
# REQ-FRD-07 крит. 5
# ---------------------------------------------------------------------------

func test_req_frd_07_c5_records_distance_altitude_grade_match_samples_of_recorded_ride() -> void:
	var lap_m: float = RouteCatalog.get_route(RouteCatalog.HILLS).profile.length_m()
	# ≈ 2.5 круга «Холмов» при 300 Вт.
	var r := _recorded_free_ride(RouteCatalog.HILLS, 4200, 300, true)
	if r == null:
		return
	var laps_ridden: float = r.total_distance_m() / lap_m
	assert_between(laps_ridden, 2.05, 2.95, "проехано %.2f круга" % laps_ridden)
	var res := _decode(FitEncoder.encode(r))
	var recs := res.messages_of(MSG_RECORD)
	assert_eq(recs.size(), r.samples.size(), "record на каждый сэмпл")
	var def := res.definition_of(MSG_RECORD)
	assert_eq(def.get(REC_DISTANCE), [4, 0x86], "distance — uint32")
	assert_eq(def.get(REC_ALTITUDE), [2, 0x84], "altitude — uint16")
	assert_eq(def.get(REC_ENH_ALTITUDE), [4, 0x86], "enhanced_altitude — uint32")
	assert_eq(def.get(REC_GRADE), [2, 0x83], "grade — sint16")
	var bad: Array[String] = []
	for i in mini(recs.size(), r.samples.size()):
		var m: Dictionary = recs[i]
		var d: float = float(_f(m, REC_DISTANCE)) / 100.0
		var alt: float = float(_f(m, REC_ALTITUDE)) / 5.0 - 500.0
		var ealt: float = float(_f(m, REC_ENH_ALTITUDE)) / 5.0 - 500.0
		var g: float = float(_f(m, REC_GRADE)) / 100.0
		if absf(d - r.samples.distance_m[i]) > 0.01 or absf(alt - r.samples.altitude_m[i]) > 0.2 \
				or absf(ealt - r.samples.altitude_m[i]) > 0.2 or absf(g - r.samples.grade_pct[i]) > 0.0051:
			bad.append("record %d: d %.3f/%.3f h %.2f/%.2f/%.2f g %.2f/%.2f" % [i, d, r.samples.distance_m[i],
				alt, ealt, r.samples.altitude_m[i], g, r.samples.grade_pct[i]])
	assert_eq(bad.slice(0, 5), [] as Array[String], "дистанция ±0.01 м, высота ±0.2 м, уклон ±0.005 %")
	var ses: Dictionary = res.messages_of(MSG_SESSION)[0]
	assert_almost_eq(float(_f(ses, SES_TOTAL_DISTANCE)) / 100.0, r.total_distance_m(), 0.01, "session.total_distance")
	assert_almost_eq(float(_f(ses, SES_TOTAL_ASCENT)), r.total_ascent_m(), 1.0, "session.total_ascent ±1 м")
	assert_almost_eq(float(_f(ses, SES_TOTAL_ASCENT)), r.samples.total_ascent_m(), 1.0, "набор FRD-07.4 по сэмплам")
	assert_gt(r.total_ascent_m(), 2.0 * 220.0 * 0.9, "за 2+ круга «Холмов» набор > 396 м")


func test_req_frd_07_c5_one_lap_per_full_circuit_plus_partial_last() -> void:
	var lap_m: float = RouteCatalog.get_route(RouteCatalog.HILLS).profile.length_m()
	var r := _recorded_free_ride(RouteCatalog.HILLS, 4200, 300, false)
	if r == null:
		return
	var res := _decode(FitEncoder.encode(r))
	var laps := res.messages_of(MSG_LAP)
	var expected_laps: int = ceili(r.total_distance_m() / lap_m)
	assert_eq(laps.size(), expected_laps, "lap: %d полных + неполный последний" % (expected_laps - 1))
	assert_eq(int(res.first_field(MSG_SESSION, SES_NUM_LAPS)), laps.size(), "session.num_laps")
	var sum: float = 0.0
	var max_step: float = 0.0
	for i in range(1, r.samples.size()):
		max_step = maxf(max_step, r.samples.distance_m[i] - r.samples.distance_m[i - 1])
	for i in laps.size():
		var d: float = float(_f(laps[i], LAP_TOTAL_DISTANCE)) / 100.0
		sum += d
		if i < laps.size() - 1:
			assert_almost_eq(d, lap_m, max_step + 0.01, "круг %d — длина трассы (с точностью до секунды езды)" % (i + 1))
			assert_eq(int(_f(laps[i], LAP_TRIGGER)), 4, "круг %d закрыт position_lap" % (i + 1))
		else:
			assert_lt(d, lap_m, "последний — неполный")
			assert_eq(int(_f(laps[i], LAP_TRIGGER)), 7, "последний закрыт session_end")
	assert_almost_eq(sum, r.total_distance_m(), 0.05, "сумма lap = итоговая дистанция")


func test_req_frd_07_c5_loc_05_timer_events_pause_and_invalid_heart_rate_on_free_ride() -> void:
	var r := _recorded_free_ride(RouteCatalog.SEASIDE, 900, 220, true)
	if r == null:
		return
	var res := _decode(FitEncoder.encode(r))
	var ses: Dictionary = res.messages_of(MSG_SESSION)[0]
	assert_eq(int(_f(ses, SES_SUB_SPORT)), 58, "virtual_activity")
	assert_eq(int(_f(ses, SES_TIMER)), r.samples.size() * 1000, "total_timer_time = активное время")
	assert_eq(int(_f(ses, SES_ELAPSED)) - int(_f(ses, SES_TIMER)), roundi(r.paused_total_sec() * 1000.0),
		"elapsed − timer = paused_total_sec")
	var types: Array[int] = []
	for e in res.messages_of(MSG_EVENT):
		if int(_f(e, 0)) == 0:
			types.append(int(_f(e, 1)))
	assert_eq(types, [0, 4, 0, 4] as Array[int], "timer start, stop_all (пауза), start, stop_all")
	var hr_zero: int = 0
	for m in res.messages_of(MSG_RECORD):
		if _f(m, REC_HEART_RATE) != null:
			hr_zero += 1
	assert_eq(hr_zero, 0, "без датчика пульса heart_rate — invalid, а не 0")


func test_req_frd_07_c5_less_than_one_lap_gives_single_session_end_lap() -> void:
	var r := _recorded_free_ride(RouteCatalog.MOUNTAINS, 300, 250, false)
	if r == null:
		return
	var res := _decode(FitEncoder.encode(r))
	var laps := res.messages_of(MSG_LAP)
	assert_eq(laps.size(), 1)
	if laps.size() == 1:
		assert_almost_eq(float(_f(laps[0], LAP_TOTAL_DISTANCE)) / 100.0, r.total_distance_m(), 0.05)


# ---------------------------------------------------------------------------
# Регрессия REQ-LOC-05 крит. 1–4: заезд по плану — побайтно как до T-069
# ---------------------------------------------------------------------------

static func _ride_from(d: Dictionary) -> Ride:
	# Та же сборка заезда, что в генераторе эталона (код до T-069).
	var r := Ride.new()
	r.id = str(d["id"])
	r.profile_id = "p"
	r.name = str(d["name"])
	r.started_at_unix = int(d["started_at_unix"])
	r.metadata = (d["metadata"] as Dictionary).duplicate(true)
	var ev: Array[Dictionary] = []
	for e in d["events"]:
		ev.append((e as Dictionary).duplicate(true))
	r.events = ev
	r.samples = SampleStream.from_dict(d["samples"])
	return r


func test_req_loc_05_c1_c4_workout_fit_identical_to_pre_t069_encoder() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(FIXTURES + "fit_workout_rides.json"))
	assert_true(parsed is Dictionary, "вход эталона читается")
	if not (parsed is Dictionary):
		return
	var by_key: Dictionary = {}
	for d in parsed["rides"]:
		by_key[str(d["key"])] = d
	for key in FIXTURE_KEYS:
		var expected: PackedByteArray = FileAccess.get_file_as_bytes(FIXTURES + "fit_workout_%s.fit" % key)
		assert_gt(expected.size(), 14, "%s: эталон есть" % key)
		var got: PackedByteArray = FitEncoder.encode(_ride_from(by_key[key]))
		assert_eq(got.size(), expected.size(), "%s: размер файла как до T-069" % key)
		if got.size() != expected.size():
			continue
		# Последние 6 байт — activity.local_timestamp (зависит от часового пояса) и CRC файла.
		var first_diff: int = -1
		for i in got.size() - 6:
			if got[i] != expected[i]:
				first_diff = i
				break
		assert_eq(first_diff, -1, "%s: байты до local_timestamp совпадают с эталоном (первое отличие — байт %d)" % [key, first_diff])
		var res := _decode(got)
		var act: Dictionary = res.messages_of(MSG_ACTIVITY)[0]
		var bias: int = int(Time.get_time_zone_from_system().get("bias", 0)) * 60
		assert_eq(int(_f(act, ACT_LOCAL_TIMESTAMP)) - int(_f(act, F_TIMESTAMP)), bias, "%s: local_timestamp — пояс машины" % key)
		var exp_res := _decode(expected)
		assert_eq(res.count(MSG_RECORD), exp_res.count(MSG_RECORD), "%s: record" % key)
		assert_eq(res.count(MSG_LAP), exp_res.count(MSG_LAP), "%s: lap по шагам" % key)
		assert_false(res.definition_of(MSG_RECORD).has(REC_ALTITUDE), "%s: у плана нет высоты" % key)
		assert_false(res.definition_of(MSG_SESSION).has(SES_TOTAL_ASCENT), "%s: у плана нет total_ascent" % key)
