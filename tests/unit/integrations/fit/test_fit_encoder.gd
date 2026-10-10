extends GutTest
## Кодировщик FIT (REQ-LOC-05 крит. 1–4, REQ-STR-02 крит. 2, REQ-WRK-05 крит. 2 — паузы,
## REQ-WRK-08 крит. 5 / В-8 — скорость по `speed_source`; REQ-NFR-09 крит. 1).
## Проверки — через `FitDecoder` (round-trip без внешнего SDK).

const FTP: int = 200
const SEED: int = 5
const STARTED: int = 1700000000
const D = preload("res://src/integrations/fit/fit_definitions.gd")


## Заезд с синтетическим потоком: `n` сэмплов, слот 2 — без телеметрии, слот 3 — без пульса.
func _ride(n: int = 6, hr: bool = true) -> Ride:
	var r := Ride.new()
	r.id = "fit-test"
	r.profile_id = "p"
	r.started_at_unix = STARTED
	r.name = "FIT plan"
	r.workout = WorkoutSerializer.to_dict(Workout.make("FIT plan", [WorkoutStep.watts(3, 200.0), WorkoutStep.watts(3, 250.0)] as Array[WorkoutStep]))
	r.metadata = {"ftp_w": FTP, "weight_kg": 75.0, "max_hr": 185, "speed_source": Ride.SPEED_SOURCE_TRAINER_LEGACY,
		"stopped_early": false, "elapsed_sec": n, "paused_total_sec": 0.0, "in_progress": false, "recovered": false}
	r.samples.speed_source = Ride.SPEED_SOURCE_TRAINER_LEGACY
	for i in n:
		# Значения держатся в пределах uint8 FIT для пульса и каденса при любой длине потока.
		var sample: TrainerSample = TrainerSample.full(float(i + 1), 200 + i * 10, 85 + i % 30, 36.0) if i != 2 else null
		var bpm: int = (140 + i % 40) if hr and i != 3 else -1
		r.samples.append(i, sample, bpm, 200, i / 3, true)
	r.events = [{"type": WorkoutSession.EVENT_START, "at_sec": 0.0, "value": 0}]
	r.compute_summary()
	return r


func _decode(ride: Ride) -> FitDecoder.Result:
	var bytes := FitEncoder.encode(ride)
	var res := FitDecoder.decode(bytes)
	assert_true(res.ok, "файл декодируется: %s" % res.error)
	return res


func _f(msg: Dictionary, field: int) -> Variant:
	return (msg["fields"] as Dictionary).get(field, null)


# ---------------------------------------------------------------------------
# REQ-LOC-05 крит. 1: заголовок и CRC
# ---------------------------------------------------------------------------

func test_header_is_14_bytes_with_signature_and_valid_crcs() -> void:
	var bytes := FitEncoder.encode(_ride())
	assert_eq(bytes[0], 14, "размер заголовка")
	assert_eq(bytes[1], 0x20, "protocol 2.0")
	assert_eq(bytes.slice(8, 12).get_string_from_ascii(), ".FIT", "сигнатура в байтах 8–11")
	var data_size: int = bytes[4] | (bytes[5] << 8) | (bytes[6] << 16) | (bytes[7] << 24)
	assert_eq(data_size, bytes.size() - 14 - 2, "data_size = всё без заголовка и CRC")
	var header_crc: int = bytes[12] | (bytes[13] << 8)
	assert_eq(header_crc, FitCrc.compute(bytes, 0, 12), "CRC заголовка")
	var file_crc: int = bytes[bytes.size() - 2] | (bytes[bytes.size() - 1] << 8)
	assert_eq(file_crc, FitCrc.compute(bytes, 0, bytes.size() - 2), "CRC файла")
	assert_eq(FitCrc.compute(bytes), 0, "CRC всего файла включая хвост = 0")


func test_file_decodes_with_test_decoder() -> void:
	var res := _decode(_ride())
	assert_true(res.header_crc_ok)
	assert_true(res.file_crc_ok)
	assert_eq(res.profile_version, D.PROFILE_VERSION)
	assert_eq(res.error, "")


func test_corrupted_byte_breaks_file_crc() -> void:
	var bytes := FitEncoder.encode(_ride())
	bytes[40] ^= 0xFF
	var res := FitDecoder.decode(bytes)
	assert_false(res.file_crc_ok)
	assert_false(res.ok)


# ---------------------------------------------------------------------------
# REQ-LOC-05 крит. 2: состав сообщений
# ---------------------------------------------------------------------------

func test_file_id_is_activity_from_development_manufacturer() -> void:
	var res := _decode(_ride())
	assert_eq(res.count(D.MSG_FILE_ID), 1)
	assert_eq(res.first_field(D.MSG_FILE_ID, D.FILE_ID_TYPE), D.FILE_TYPE_ACTIVITY)
	assert_eq(res.first_field(D.MSG_FILE_ID, D.FILE_ID_MANUFACTURER), D.MANUFACTURER_DEVELOPMENT)
	assert_eq(res.first_field(D.MSG_FILE_ID, D.FILE_ID_TIME_CREATED), D.to_fit_time(STARTED))
	assert_eq(res.first_field(D.MSG_FILE_ID, D.FILE_ID_PRODUCT_NAME), FitEncoder.PRODUCT_NAME)
	assert_eq(res.count(D.MSG_FILE_CREATOR), 1)
	assert_eq(res.count(D.MSG_DEVICE_INFO), 1)
	assert_eq(res.count(D.MSG_ACTIVITY), 1)
	assert_eq(res.count(D.MSG_SESSION), 1)


func test_message_order_file_id_first_activity_last() -> void:
	var res := _decode(_ride())
	assert_eq(int(res.messages[0]["global"]), D.MSG_FILE_ID)
	assert_eq(int(res.messages[res.messages.size() - 1]["global"]), D.MSG_ACTIVITY)
	assert_eq(int(res.messages[res.messages.size() - 2]["global"]), D.MSG_SESSION)


func test_record_count_equals_sample_count() -> void:
	for n in [0, 1, 6, 120]:
		var res := _decode(_ride(n))
		assert_eq(res.count(D.MSG_RECORD), n, "REQ-LOC-05 крит. 4: %d записей" % n)


func test_record_fields_match_stream_values_and_units() -> void:
	var ride := _ride()
	var res := _decode(ride)
	var records := res.messages_of(D.MSG_RECORD)
	var r0 := records[0]
	assert_eq(_f(r0, D.F_TIMESTAMP), D.to_fit_time(STARTED))
	assert_eq(_f(r0, D.RECORD_POWER), 200)
	assert_eq(_f(r0, D.RECORD_HEART_RATE), 140)
	assert_eq(_f(r0, D.RECORD_CADENCE), 85)
	assert_eq(_f(r0, D.RECORD_SPEED), 10000, "36 км/ч = 10 м/с → 10000 мм/с")
	assert_eq(_f(r0, D.RECORD_DISTANCE), 1000, "10 м → 1000 см")
	var r1 := records[1]
	assert_eq(_f(r1, D.RECORD_POWER), 210)
	assert_eq(_f(r1, D.RECORD_DISTANCE), 2000, "дистанция — интеграл скорости")
	var last := records[records.size() - 1]
	assert_eq(_f(last, D.RECORD_DISTANCE), roundi(ride.samples.total_distance_m() * 100.0))


func test_missing_values_are_invalid_not_zero() -> void:
	var ride := _ride()
	var bytes := FitEncoder.encode(ride)
	var res := FitDecoder.decode(bytes)
	var records := res.messages_of(D.MSG_RECORD)
	var no_telemetry := records[2]
	assert_null(_f(no_telemetry, D.RECORD_POWER), "REQ-LOC-05 крит. 3: мощность invalid")
	assert_null(_f(no_telemetry, D.RECORD_CADENCE))
	assert_null(_f(no_telemetry, D.RECORD_SPEED))
	assert_not_null(_f(no_telemetry, D.RECORD_HEART_RATE), "пульс в этом слоте есть")
	assert_null(_f(records[3], D.RECORD_HEART_RATE), "слот без пульса → invalid")
	assert_eq(_f(records[3], D.RECORD_POWER), 230)
	# В сырых байтах: 0xFFFF для uint16 и 0xFF для uint8 — ищем запись слота 2 по метке времени.
	var ts := D.to_fit_time(STARTED + 2)
	var needle := PackedByteArray([ts & 0xFF, (ts >> 8) & 0xFF, (ts >> 16) & 0xFF, (ts >> 24) & 0xFF, 0xFF, 0xFF])
	assert_true(_contains(bytes, needle), "мощность слота 2 закодирована как 0xFFFF")


func test_ride_without_hr_has_invalid_hr_everywhere() -> void:
	var res := _decode(_ride(6, false))
	for rec in res.messages_of(D.MSG_RECORD):
		assert_null(_f(rec, D.RECORD_HEART_RATE))
	assert_null(res.first_field(D.MSG_SESSION, D.SESSION_AVG_HEART_RATE), "сводка без пульса → invalid")
	assert_null(res.first_field(D.MSG_SESSION, D.SESSION_MAX_HEART_RATE))


func test_record_timestamps_are_strictly_increasing() -> void:
	var ride := _ride(30)
	ride.events.append({"type": WorkoutSession.EVENT_PAUSE, "at_sec": 10.0, "value": 10, "duration_sec": 7.0, "until_sec": 17.0})
	ride.events.append({"type": WorkoutSession.EVENT_RESUME, "at_sec": 10.0, "value": 10})
	var res := _decode(ride)
	var prev: int = -1
	for rec in res.messages_of(D.MSG_RECORD):
		var ts: int = int(_f(rec, D.F_TIMESTAMP))
		assert_gt(ts, prev)
		prev = ts
	# События (старт, паузы, стоп) тоже хронологичны; lap/session/activity — итоговые
	# сообщения после записей, их метки времени по спецификации равны концу отрезка.
	var ev_prev: int = -1
	for ev in res.messages_of(D.MSG_EVENT):
		var ts: int = int(_f(ev, D.F_TIMESTAMP))
		assert_gte(ts, ev_prev, "метки времени событий не убывают")
		ev_prev = ts


# ---------------------------------------------------------------------------
# event: старт, паузы, стоп (REQ-WRK-05 крит. 2)
# ---------------------------------------------------------------------------

func test_events_start_and_stop_all_without_pauses() -> void:
	var res := _decode(_ride(6))
	var events := res.messages_of(D.MSG_EVENT)
	assert_eq(events.size(), 2)
	assert_eq(_f(events[0], D.EVENT_EVENT), D.EVENT_TIMER)
	assert_eq(_f(events[0], D.EVENT_EVENT_TYPE), D.EVENT_TYPE_START)
	assert_eq(_f(events[0], D.F_TIMESTAMP), D.to_fit_time(STARTED))
	assert_eq(_f(events[1], D.EVENT_EVENT_TYPE), D.EVENT_TYPE_STOP_ALL)
	assert_eq(_f(events[1], D.F_TIMESTAMP), D.to_fit_time(STARTED + 6))


func test_pause_produces_timer_stop_all_and_start_events_at_wall_times() -> void:
	var ride := _ride(20)
	ride.events.append({"type": WorkoutSession.EVENT_PAUSE, "at_sec": 5.0, "value": 5, "duration_sec": 12.0, "until_sec": 17.0})
	ride.events.append({"type": WorkoutSession.EVENT_RESUME, "at_sec": 5.0, "value": 5})
	ride.metadata["paused_total_sec"] = 12.0
	var res := _decode(ride)
	var events := res.messages_of(D.MSG_EVENT)
	assert_eq(events.size(), 4, "start, stop_all, start, stop_all")
	assert_eq(_f(events[1], D.EVENT_EVENT_TYPE), D.EVENT_TYPE_STOP_ALL)
	assert_eq(_f(events[1], D.F_TIMESTAMP), D.to_fit_time(STARTED + 5))
	assert_eq(_f(events[2], D.EVENT_EVENT_TYPE), D.EVENT_TYPE_START)
	assert_eq(_f(events[2], D.F_TIMESTAMP), D.to_fit_time(STARTED + 17))
	assert_eq(_f(events[3], D.EVENT_EVENT_TYPE), D.EVENT_TYPE_STOP_ALL)
	assert_eq(_f(events[3], D.F_TIMESTAMP), D.to_fit_time(STARTED + 20 + 12))
	# Записи после паузы сдвинуты на её длительность.
	var records := res.messages_of(D.MSG_RECORD)
	assert_eq(_f(records[4], D.F_TIMESTAMP), D.to_fit_time(STARTED + 4))
	assert_eq(_f(records[5], D.F_TIMESTAMP), D.to_fit_time(STARTED + 5 + 12))
	# События паузы стоят между записями хронологически.
	var idx_stop: int = res.messages.find(events[1])
	var idx_rec4: int = res.messages.find(records[4])
	var idx_rec5: int = res.messages.find(records[5])
	assert_true(idx_rec4 < idx_stop and idx_stop < idx_rec5, "stop_all между записями 4 и 5")


func test_two_pauses_accumulate_offsets() -> void:
	var ride := _ride(30)
	ride.events.append({"type": WorkoutSession.EVENT_PAUSE, "at_sec": 5.0, "value": 5, "duration_sec": 3.0, "until_sec": 8.0})
	ride.events.append({"type": WorkoutSession.EVENT_PAUSE, "at_sec": 20.0, "value": 20, "duration_sec": 4.0, "until_sec": 24.0})
	var res := _decode(ride)
	var events := res.messages_of(D.MSG_EVENT)
	assert_eq(events.size(), 6)
	assert_eq(_f(events[3], D.F_TIMESTAMP), D.to_fit_time(STARTED + 20 + 3), "вторая пауза с учётом первой")
	assert_eq(_f(events[4], D.F_TIMESTAMP), D.to_fit_time(STARTED + 20 + 3 + 4))
	var records := res.messages_of(D.MSG_RECORD)
	assert_eq(_f(records[29], D.F_TIMESTAMP), D.to_fit_time(STARTED + 29 + 7))
	assert_eq(res.first_field(D.MSG_SESSION, D.SESSION_TOTAL_ELAPSED_TIME), (30 + 7) * 1000)
	assert_eq(res.first_field(D.MSG_SESSION, D.SESSION_TOTAL_TIMER_TIME), 30 * 1000)


# ---------------------------------------------------------------------------
# session / lap / activity
# ---------------------------------------------------------------------------

func test_session_is_cycling_virtual_activity() -> void:
	var res := _decode(_ride())
	assert_eq(res.first_field(D.MSG_SESSION, D.SESSION_SPORT), 2, "REQ-STR-02 крит. 2: sport = cycling")
	assert_eq(res.first_field(D.MSG_SESSION, D.SESSION_SUB_SPORT), 58, "sub_sport = virtual_activity")


func test_session_times_and_metrics_equal_summary() -> void:
	var ride := _ride(120)
	var res := _decode(ride)
	var s := ride.summary
	assert_eq(res.first_field(D.MSG_SESSION, D.SESSION_START_TIME), D.to_fit_time(STARTED))
	assert_eq(res.first_field(D.MSG_SESSION, D.F_TIMESTAMP), D.to_fit_time(STARTED + 120))
	assert_eq(res.first_field(D.MSG_SESSION, D.SESSION_TOTAL_TIMER_TIME), 120 * 1000, "REQ-LOC-05 крит. 4: активное время")
	assert_eq(res.first_field(D.MSG_SESSION, D.SESSION_TOTAL_ELAPSED_TIME), 120 * 1000)
	assert_eq(res.first_field(D.MSG_SESSION, D.SESSION_AVG_POWER), s.avg_power_w)
	assert_eq(res.first_field(D.MSG_SESSION, D.SESSION_MAX_POWER), s.max_power_w)
	assert_eq(res.first_field(D.MSG_SESSION, D.SESSION_NORMALIZED_POWER), s.normalized_power_w)
	assert_eq(res.first_field(D.MSG_SESSION, D.SESSION_TOTAL_WORK), roundi(s.work_kj * 1000.0), "работа в Дж")
	assert_eq(res.first_field(D.MSG_SESSION, D.SESSION_AVG_HEART_RATE), s.avg_hr)
	assert_eq(res.first_field(D.MSG_SESSION, D.SESSION_MAX_HEART_RATE), s.max_hr)
	assert_eq(res.first_field(D.MSG_SESSION, D.SESSION_AVG_CADENCE), s.avg_cadence)
	assert_eq(res.first_field(D.MSG_SESSION, D.SESSION_TOTAL_DISTANCE), roundi(s.distance_m * 100.0))
	# Номер поля — литерал из профиля FIT SDK: session.threshold_power = 45 (62 — max_pos_vertical_speed).
	assert_eq(D.SESSION_THRESHOLD_POWER, 45, "session.threshold_power — поле 45 профиля FIT")
	assert_eq(res.first_field(D.MSG_SESSION, 45), FTP, "FTP в session.threshold_power (поле 45)")
	assert_null(res.first_field(D.MSG_SESSION, 62), "поле 62 (max_pos_vertical_speed) не пишется")
	assert_eq(res.first_field(D.MSG_SESSION, D.SESSION_NUM_LAPS), res.count(D.MSG_LAP))


func test_one_lap_per_workout_step() -> void:
	var ride := _ride(6)  # step_index: 0,0,0,1,1,1
	var res := _decode(ride)
	var laps := res.messages_of(D.MSG_LAP)
	assert_eq(laps.size(), 2)
	assert_eq(_f(laps[0], D.F_MESSAGE_INDEX), 0)
	assert_eq(_f(laps[1], D.F_MESSAGE_INDEX), 1)
	assert_eq(_f(laps[0], D.LAP_START_TIME), D.to_fit_time(STARTED))
	assert_eq(_f(laps[0], D.LAP_TOTAL_TIMER_TIME), 3000)
	assert_eq(_f(laps[1], D.LAP_START_TIME), D.to_fit_time(STARTED + 3))
	assert_eq(_f(laps[1], D.LAP_TOTAL_TIMER_TIME), 3000)
	assert_eq(_f(laps[0], D.LAP_AVG_POWER), 205, "(200+210)/2 — слот 2 без данных")
	assert_eq(_f(laps[1], D.LAP_MAX_POWER), 250)
	assert_eq(_f(laps[0], D.LAP_SPORT), D.SPORT_CYCLING)
	var timer_sum: int = 0
	for lap in laps:
		timer_sum += int(_f(lap, D.LAP_TOTAL_TIMER_TIME))
	assert_eq(timer_sum, 6000, "сумма lap = total_timer_time")


func test_activity_has_one_session_and_manual_type() -> void:
	var res := _decode(_ride(6))
	assert_eq(res.first_field(D.MSG_ACTIVITY, D.ACTIVITY_NUM_SESSIONS), 1)
	assert_eq(res.first_field(D.MSG_ACTIVITY, D.ACTIVITY_TYPE), D.ACTIVITY_TYPE_MANUAL)
	assert_eq(res.first_field(D.MSG_ACTIVITY, D.ACTIVITY_TOTAL_TIMER_TIME), 6000)
	assert_eq(res.first_field(D.MSG_ACTIVITY, D.F_TIMESTAMP), D.to_fit_time(STARTED + 6))
	assert_not_null(res.first_field(D.MSG_ACTIVITY, D.ACTIVITY_LOCAL_TIMESTAMP))


func test_empty_ride_encodes_to_valid_file() -> void:
	var res := _decode(_ride(0))
	assert_eq(res.count(D.MSG_RECORD), 0)
	assert_eq(res.count(D.MSG_LAP), 1)
	assert_eq(res.first_field(D.MSG_SESSION, D.SESSION_TOTAL_TIMER_TIME), 0)
	assert_null(res.first_field(D.MSG_SESSION, D.SESSION_AVG_POWER))


func test_summary_is_recomputed_when_stale() -> void:
	var ride := _ride(60)
	ride.summary = RideSummary.new()  # сводка не соответствует потоку
	var res := _decode(ride)
	var expected := RideSummary.compute(ride.samples, FTP, ride.power_zones(), ride.hr_zones())
	assert_eq(res.first_field(D.MSG_SESSION, D.SESSION_AVG_POWER), expected.avg_power_w)


# ---------------------------------------------------------------------------
# Заезд из реальной сессии с FakeTrainer: скорость по speed_source (В-8)
# ---------------------------------------------------------------------------

func _session_ride(emit_speed: bool, seconds: int = 20) -> Ride:
	var trainer := FakeTrainer.new(SEED)
	trainer.connect_delay_sec = 0.0
	trainer.emit_speed = emit_speed
	trainer.set_heart_rate(145)
	trainer.connect_device("fake-fit")
	var profile := Profile.create("Rider")
	profile.ftp_w = FTP
	profile.max_hr = 180
	var session := WorkoutSession.new(Workout.make("Session plan", [WorkoutStep.watts(seconds, 200.0)] as Array[WorkoutStep]), trainer, FTP)
	session.start()
	for i in seconds / 2:
		session.tick(1.0)
	session.pause()
	session.tick(5.0)
	session.resume()
	for i in seconds - seconds / 2:
		session.tick(1.0)
	var ride := Ride.from_session(session, profile)
	ride.compute_summary()
	return ride


func test_session_ride_with_model_speed_has_speed_and_distance_in_records() -> void:
	var ride := _session_ride(false)
	assert_eq(ride.speed_source(), SampleStream.SPEED_SOURCE_MODEL)
	var res := _decode(ride)
	var records := res.messages_of(D.MSG_RECORD)
	assert_eq(records.size(), 20)
	var last := records[records.size() - 1]
	assert_gt(int(_f(last, D.RECORD_SPEED)), 0, "расчётная скорость попала в FIT")
	assert_eq(_f(last, D.RECORD_DISTANCE), roundi(ride.samples.total_distance_m() * 100.0))
	assert_eq(res.first_field(D.MSG_SESSION, D.SESSION_TOTAL_TIMER_TIME), 20000)
	assert_eq(res.first_field(D.MSG_SESSION, D.SESSION_TOTAL_ELAPSED_TIME), 25000, "с паузой 5 с")
	assert_eq(res.count(D.MSG_EVENT), 4)


## У-30 (T-169): поле скорости станка не попадает в заезд — в FIT скорость модели.
func test_session_ride_with_trainer_speed_uses_trainer_values() -> void:
	var ride := _session_ride(true)
	assert_eq(ride.speed_source(), SampleStream.SPEED_SOURCE_MODEL)
	var res := _decode(ride)
	var records := res.messages_of(D.MSG_RECORD)
	var i: int = records.size() - 1
	assert_eq(_f(records[i], D.RECORD_SPEED), roundi(ride.samples.speed_kmh[i] / 3.6 * 1000.0))
	assert_eq(_f(records[i], D.RECORD_HEART_RATE), 145)
	assert_eq(res.first_field(D.MSG_SESSION, D.SESSION_AVG_HEART_RATE), 145)


static func _contains(haystack: PackedByteArray, needle: PackedByteArray) -> bool:
	for i in range(0, haystack.size() - needle.size() + 1):
		var match_all := true
		for j in needle.size():
			if haystack[i + j] != needle[j]:
				match_all = false
				break
		if match_all:
			return true
	return false
