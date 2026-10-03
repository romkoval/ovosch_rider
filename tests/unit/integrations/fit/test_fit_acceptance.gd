extends GutTest
## Приёмочные тесты экспорта FIT (REQ-LOC-05 крит. 1–4, REQ-STR-02 крит. 2,
## REQ-WRK-05 крит. 2 — паузы в FIT, REQ-NFR-09 крит. 1).
##
## Проверка структуры файла — СВОИМ минимальным декодером (`MiniFit`): заголовок,
## CRC-16 (независимая побитовая реализация CRC-16/ARC, не таблица `FitCrc`),
## definition/data-сообщения little-endian с «сырыми» значениями полей
## (invalid-значения не преобразуются, чтобы сверять их с 0xFFFF/0xFF).
## `FitDecoder` разработчика используется только как перекрёстная проверка.

const FTP: int = 200
const MAX_HR: int = 180
const START_UNIX: int = 1_790_000_000
const FIT_EPOCH: int = 631065600

# Глобальные номера и поля (Garmin FIT SDK, Profile.xlsx) — независимые константы.
const G_FILE_ID := 0
const G_SESSION := 18
const G_LAP := 19
const G_RECORD := 20
const G_EVENT := 21
const G_ACTIVITY := 34
const F_TIMESTAMP := 253
const FILE_ID_TYPE := 0
const FILE_TYPE_ACTIVITY := 4
const REC_HEART_RATE := 3
const REC_CADENCE := 4
const REC_DISTANCE := 5
const REC_SPEED := 6
const REC_POWER := 7
const EV_EVENT := 0
const EV_EVENT_TYPE := 1
const EV_TIMER := 0
const EV_TYPE_START := 0
const EV_TYPE_STOP_ALL := 4
const SES_START_TIME := 2
const SES_SPORT := 5
const SES_SUB_SPORT := 6
const SES_TOTAL_ELAPSED := 7
const SES_TOTAL_TIMER := 8
const SES_TOTAL_DISTANCE := 9
const SES_AVG_HR := 16
const SES_MAX_HR := 17
const SES_AVG_CADENCE := 18
const SES_AVG_POWER := 20
const SES_MAX_POWER := 21
const SES_NUM_LAPS := 26
const SES_NP := 34
const SES_TOTAL_WORK := 48
const LAP_START_TIME := 2
const LAP_TOTAL_ELAPSED := 7
const LAP_TOTAL_TIMER := 8
const SPORT_CYCLING := 2
const SUB_SPORT_VIRTUAL_ACTIVITY := 58
const INVALID_U8 := 0xFF
const INVALID_U16 := 0xFFFF
const INVALID_U32 := 0xFFFFFFFF

var _dir: String
var _repo: FileRideRepository
var _recorder: RideRecorder = null
var _session: WorkoutSession = null
var _trainer: FakeTrainer = null


func before_each() -> void:
	_dir = "user://acc_fit_%d_%d/" % [Time.get_ticks_usec(), randi() % 100000]
	_repo = FileRideRepository.new(_dir)


func after_each() -> void:
	if _recorder != null:
		_recorder.dispose()
		_recorder = null
	_session = null
	_trainer = null
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
# Независимый минимальный декодер FIT
# ---------------------------------------------------------------------------

## CRC-16/ARC побитово: полином 0xA001 (отражённый 0x8005), init 0, без XOR.
static func crc16(bytes: PackedByteArray, from: int = 0, to: int = -1) -> int:
	var end := bytes.size() if to < 0 else to
	var crc := 0
	for i in range(from, end):
		crc ^= bytes[i]
		for bit in 8:
			if crc & 1:
				crc = (crc >> 1) ^ 0xA001
			else:
				crc >>= 1
	return crc & 0xFFFF


class MiniFit:
	extends RefCounted
	var ok := false
	var error := ""
	var header_size := 0
	var data_size := 0
	var signature := ""
	var header_crc_ok := false
	var file_crc_ok := false
	## `{global, fields: {num: raw_int}, types: {num: base_type}}` в порядке файла.
	var messages: Array[Dictionary] = []

	func of(global: int) -> Array[Dictionary]:
		var out: Array[Dictionary] = []
		for m in messages:
			if int(m["global"]) == global:
				out.append(m)
		return out

	func first(global: int) -> Dictionary:
		var list := of(global)
		return list[0] if not list.is_empty() else {}

	static func field(m: Dictionary, num: int) -> int:
		return int((m["fields"] as Dictionary).get(num, -1))


static func _le(bytes: PackedByteArray, at: int, size: int) -> int:
	var v := 0
	for i in size:
		v |= bytes[at + i] << (8 * i)
	return v


static func decode(bytes: PackedByteArray) -> MiniFit:
	var r := MiniFit.new()
	if bytes.size() < 14:
		r.error = "короче заголовка"
		return r
	r.header_size = bytes[0]
	if r.header_size != 12 and r.header_size != 14:
		r.error = "размер заголовка %d" % r.header_size
		return r
	r.data_size = _le(bytes, 4, 4)
	r.signature = bytes.slice(8, 12).get_string_from_ascii()
	if r.header_size == 14:
		r.header_crc_ok = _le(bytes, 12, 2) == crc16(bytes, 0, 12)
	else:
		r.header_crc_ok = true
	var data_end := r.header_size + r.data_size
	if bytes.size() != data_end + 2:
		r.error = "размер файла %d ≠ заголовок %d + данные %d + CRC 2" % [bytes.size(), r.header_size, r.data_size]
		return r
	r.file_crc_ok = _le(bytes, data_end, 2) == crc16(bytes, 0, data_end)
	var defs := {}
	var pos := r.header_size
	while pos < data_end:
		var head := bytes[pos]
		pos += 1
		if head & 0x80:
			r.error = "сжатый заголовок времени"
			return r
		var local := head & 0x0F
		if head & 0x40:
			var arch := bytes[pos + 1]
			if arch != 0:
				r.error = "ожидался little-endian"
				return r
			var global := _le(bytes, pos + 2, 2)
			var nf := bytes[pos + 4]
			pos += 5
			var fields: Array = []
			for i in nf:
				fields.append([bytes[pos], bytes[pos + 1], bytes[pos + 2]])
				pos += 3
			if head & 0x20:
				var nd := bytes[pos]
				pos += 1 + 3 * nd
			defs[local] = {"global": global, "fields": fields}
		else:
			if not defs.has(local):
				r.error = "данные без определения (local %d @ %d)" % [local, pos - 1]
				return r
			var d: Dictionary = defs[local]
			var values := {}
			var types := {}
			for f in d["fields"]:
				var size: int = f[1]
				var base: int = f[2]
				values[int(f[0])] = _le(bytes, pos, size) if size <= 4 and base != 0x07 else -1
				types[int(f[0])] = base
				pos += size
			r.messages.append({"global": int(d["global"]), "fields": values, "types": types})
	if pos != data_end:
		r.error = "сообщения не заканчиваются ровно на границе данных"
		return r
	r.ok = r.header_crc_ok and r.file_crc_ok and r.signature == ".FIT"
	return r


# ---------------------------------------------------------------------------
# Хелперы заездов
# ---------------------------------------------------------------------------

static func _stream(powers: Array, hrs: Array = [], cadences: Array = [], speeds: Array = [], steps: Array = []) -> SampleStream:
	var s := SampleStream.new()
	s.speed_source = SampleStream.SPEED_SOURCE_TRAINER
	for i in powers.size():
		var p: int = int(powers[i])
		var hr: int = int(hrs[i]) if i < hrs.size() else -1
		var cad: int = int(cadences[i]) if i < cadences.size() else -1
		var spd: float = float(speeds[i]) if i < speeds.size() else -1.0
		var sample: TrainerSample = null
		if p >= 0 or cad >= 0 or spd >= 0.0:
			sample = TrainerSample.new()
			sample.has_power = p >= 0
			sample.power_w = maxi(p, 0)
			sample.has_cadence = cad >= 0
			sample.cadence_rpm = maxi(cad, 0)
			sample.has_speed = spd >= 0.0
			sample.speed_kmh = maxf(spd, 0.0)
		s.append(i, sample, hr, 200, int(steps[i]) if i < steps.size() else 0, true)
	return s


func _ride(samples: SampleStream, pauses: Array = [], max_hr: int = MAX_HR) -> Ride:
	var r := Ride.new()
	r.id = Ride.generate_id(START_UNIX)
	r.profile_id = "fit-acc"
	r.started_at_unix = START_UNIX
	r.name = "FIT acceptance"
	r.workout = {"name": "FIT acceptance", "source": "zwo", "steps": []}
	var paused_total := 0.0
	r.events = [{"type": "start", "at_sec": 0.0, "value": 0}]
	for p in pauses:
		var at: float = float(p[0])
		var dur: float = float(p[1])
		r.events.append({"type": "pause", "at_sec": at, "value": at, "duration_sec": dur, "until_sec": at + dur})
		r.events.append({"type": "resume", "at_sec": at, "value": at})
		paused_total += dur
	r.metadata = {"ftp_w": FTP, "weight_kg": 70.0, "max_hr": max_hr, "intensity": 1.0, "stopped_early": false,
		"paused_total_sec": paused_total, "speed_source": samples.speed_source, "in_progress": false, "recovered": false}
	r.samples = samples
	r.compute_summary()
	return r


func _profile() -> Profile:
	var p := Profile.create("Fit")
	p.ftp_w = FTP
	p.weight_kg = 70.0
	p.max_hr = MAX_HR
	return p


func _session_ride(plan: Workout, hr: int = 150, emit_speed: bool = true, script: Callable = Callable()) -> Ride:
	_trainer = FakeTrainer.new(5)
	_trainer.connect_delay_sec = 0.0
	_trainer.power_noise_w = 0.0
	_trainer.cadence_noise_rpm = 0.0
	_trainer.power_tau_sec = 0.001
	_trainer.emit_speed = emit_speed
	_trainer.set_heart_rate(hr)
	_trainer.connect_device("fake-fit")
	var profile := _profile()
	_session = WorkoutSession.new(plan, _trainer, FTP, 1.0, 70.0)
	_recorder = RideRecorder.new(_repo, profile, _session)
	_session.start()
	if script.is_valid():
		script.call(_session)
	else:
		for i in plan.total_duration_sec():
			_session.tick(1.0)
	return _repo.get_ride(_recorder.ride_id())


static func _event_list(fit: MiniFit) -> Array:
	var out: Array = []
	for m in fit.of(G_EVENT):
		if MiniFit.field(m, EV_EVENT) == EV_TIMER:
			out.append([MiniFit.field(m, F_TIMESTAMP) + FIT_EPOCH, MiniFit.field(m, EV_EVENT_TYPE)])
	return out


# ===========================================================================
# CRC: независимая проверка
# ===========================================================================

func test_crc16_reference_vector_own_and_project() -> void:
	var v := "123456789".to_ascii_buffer()
	assert_eq(crc16(v), 0xBB3D, "собственная побитовая CRC-16/ARC: '123456789' → 0xBB3D")
	assert_eq(FitCrc.compute(v), 0xBB3D, "FitCrc проекта на том же векторе")
	var rnd := Crypto.new().generate_random_bytes(257)
	assert_eq(FitCrc.compute(rnd), crc16(rnd), "FitCrc совпадает с побитовой реализацией на случайных данных")


# ===========================================================================
# REQ-LOC-05 крит. 1 — заголовок и CRC
# ===========================================================================

func test_req_loc_05_c1_header_signature_and_both_crcs() -> void:
	var ride := _ride(_stream([100, 150, 200], [120, 125, 130], [80, 85, 90], [25.0, 27.0, 30.0]))
	var bytes := FitEncoder.encode(ride)
	assert_eq(bytes[0], 14, "заголовок 14 байт")
	assert_eq(bytes.slice(8, 12).get_string_from_ascii(), ".FIT", "сигнатура .FIT в байтах 8–11")
	var data_size := _le(bytes, 4, 4)
	assert_eq(bytes.size(), 14 + data_size + 2, "размер файла = заголовок + data_size + CRC")
	assert_eq(_le(bytes, 12, 2), crc16(bytes, 0, 12), "CRC заголовка (первые 12 байт)")
	assert_eq(_le(bytes, bytes.size() - 2, 2), crc16(bytes, 0, bytes.size() - 2), "CRC всего файла")
	var fit := decode(bytes)
	assert_true(fit.ok, "собственный декодер: " + fit.error)
	var dev := FitDecoder.decode(bytes)
	assert_true(dev.ok, "декодер разработчика: " + dev.error)
	assert_eq(dev.messages.size(), fit.messages.size(), "оба декодера видят одинаковое число сообщений")
	# Порча одного байта данных ломает CRC файла.
	var broken := bytes.duplicate()
	broken[20] ^= 0x01
	assert_false(decode(broken).file_crc_ok, "изменённый байт → CRC файла не сходится")


# ===========================================================================
# REQ-LOC-05 крит. 2, 3, 4 — сообщения
# ===========================================================================

func test_req_loc_05_c2_c4_messages_records_events_session_activity() -> void:
	var powers: Array = [100, 150, 200, 250, 300]
	var hrs: Array = [120, 125, 130, 135, 140]
	var cads: Array = [80, 85, 90, 95, 100]
	var speeds: Array = [18.0, 27.0, 36.0, 36.0, 45.0]
	var ride := _ride(_stream(powers, hrs, cads, speeds, [0, 0, 1, 1, 1]))
	var fit := decode(FitEncoder.encode(ride))
	assert_true(fit.ok, fit.error)
	# file_id
	var file_id := fit.first(G_FILE_ID)
	assert_false(file_id.is_empty(), "file_id есть")
	assert_eq(MiniFit.field(file_id, FILE_ID_TYPE), FILE_TYPE_ACTIVITY, "file_id.type = activity")
	assert_eq(int(fit.messages[0]["global"]), G_FILE_ID, "file_id — первое сообщение")
	# record
	var records := fit.of(G_RECORD)
	assert_eq(records.size(), 5, "record на каждый сэмпл")
	var prev_ts := -1
	var prev_dist := -1
	for i in records.size():
		var m := records[i]
		assert_eq(MiniFit.field(m, F_TIMESTAMP) + FIT_EPOCH, START_UNIX + i, "record %d: timestamp = старт + t" % i)
		assert_eq(MiniFit.field(m, REC_POWER), int(powers[i]), "record %d: power" % i)
		assert_eq(MiniFit.field(m, REC_HEART_RATE), int(hrs[i]), "record %d: heart_rate" % i)
		assert_eq(MiniFit.field(m, REC_CADENCE), int(cads[i]), "record %d: cadence" % i)
		assert_eq(MiniFit.field(m, REC_SPEED), roundi(float(speeds[i]) / 3.6 * 1000.0), "record %d: speed м/с × 1000" % i)
		assert_eq(MiniFit.field(m, REC_DISTANCE), roundi(ride.samples.distance_m[i] * 100.0), "record %d: distance = интеграл скорости, см" % i)
		assert_gte(MiniFit.field(m, F_TIMESTAMP), prev_ts, "timestamps монотонны")
		assert_gte(MiniFit.field(m, REC_DISTANCE), prev_dist, "дистанция не убывает")
		prev_ts = MiniFit.field(m, F_TIMESTAMP)
		prev_dist = MiniFit.field(m, REC_DISTANCE)
	# distance: 5 + 7.5 + 10 + 10 + 12.5 м
	assert_eq(MiniFit.field(records[4], REC_DISTANCE), 4500, "итоговая дистанция 45.00 м")
	# events: timer start первым, stop_all последним
	var events := _event_list(fit)
	assert_eq(events.size(), 2, "без пауз — ровно start и stop_all")
	if events.size() == 2:
		assert_eq(events[0], [START_UNIX, EV_TYPE_START], "event timer start в начале")
		assert_eq(events[1], [START_UNIX + 5, EV_TYPE_STOP_ALL], "event timer stop_all в конце")
	# lap на каждый шаг плана
	var laps := fit.of(G_LAP)
	assert_eq(laps.size(), 2, "2 шага (step_index 0, 1) → 2 lap")
	if laps.size() == 2:
		assert_eq(MiniFit.field(laps[0], LAP_TOTAL_TIMER), 2000, "lap 1: 2 с")
		assert_eq(MiniFit.field(laps[1], LAP_TOTAL_TIMER), 3000, "lap 2: 3 с")
		assert_eq(MiniFit.field(laps[0], LAP_START_TIME) + FIT_EPOCH, START_UNIX)
		assert_eq(MiniFit.field(laps[1], LAP_START_TIME) + FIT_EPOCH, START_UNIX + 2)
	# session
	var ses := fit.first(G_SESSION)
	assert_false(ses.is_empty(), "session есть")
	assert_eq(MiniFit.field(ses, SES_SPORT), SPORT_CYCLING, "sport = cycling (2)")
	assert_eq(MiniFit.field(ses, SES_SUB_SPORT), SUB_SPORT_VIRTUAL_ACTIVITY, "sub_sport = virtual_activity (58)")
	assert_eq(MiniFit.field(ses, SES_TOTAL_TIMER), 5000, "total_timer_time = активное время (мс)")
	assert_eq(MiniFit.field(ses, SES_TOTAL_ELAPSED), 5000, "total_elapsed_time без пауз = активное")
	assert_eq(MiniFit.field(ses, SES_START_TIME) + FIT_EPOCH, START_UNIX)
	assert_eq(MiniFit.field(ses, SES_AVG_POWER), ride.summary.avg_power_w, "avg_power = сводка (200)")
	assert_eq(MiniFit.field(ses, SES_AVG_POWER), 200)
	assert_eq(MiniFit.field(ses, SES_MAX_POWER), 300)
	assert_eq(MiniFit.field(ses, SES_NP), ride.summary.normalized_power_w, "normalized_power = сводка")
	assert_eq(MiniFit.field(ses, SES_TOTAL_WORK), roundi(ride.summary.work_kj * 1000.0), "total_work, Дж = сводка")
	assert_eq(MiniFit.field(ses, SES_TOTAL_WORK), 1000, "100+150+200+250+300 = 1000 Дж")
	assert_eq(MiniFit.field(ses, SES_AVG_HR), 130)
	assert_eq(MiniFit.field(ses, SES_MAX_HR), 140)
	assert_eq(MiniFit.field(ses, SES_AVG_CADENCE), 90)
	assert_eq(MiniFit.field(ses, SES_NUM_LAPS), 2)
	assert_eq(MiniFit.field(ses, SES_TOTAL_DISTANCE), 4500)
	# activity
	assert_eq(fit.of(G_ACTIVITY).size(), 1, "activity есть")
	assert_eq(int(fit.messages[fit.messages.size() - 1]["global"]), G_ACTIVITY, "activity — последнее сообщение")
	# Перекрёстная проверка с декодером разработчика.
	var dev := FitDecoder.decode(FitEncoder.encode(ride))
	assert_eq(dev.count(G_RECORD), 5)
	assert_eq(int(dev.first_field(G_SESSION, SES_SUB_SPORT)), SUB_SPORT_VIRTUAL_ACTIVITY)


func test_req_loc_05_c3_missing_values_are_invalid_not_zero() -> void:
	# Сэмпл 0: всё есть; 1: нет пульса; 2: нет каденса; 3: вообще нет телеметрии; 4: каденс 0 (данные есть!).
	var s := _stream([200, 200, 200, -1, 200], [120, -1, 120, -1, 120], [90, 90, -1, -1, 0], [30.0, 30.0, 30.0, -1.0, 30.0])
	var fit := decode(FitEncoder.encode(_ride(s)))
	assert_true(fit.ok, fit.error)
	var rec := fit.of(G_RECORD)
	assert_eq(rec.size(), 5)
	if rec.size() != 5:
		return
	assert_eq(MiniFit.field(rec[1], REC_HEART_RATE), INVALID_U8, "нет пульса → 0xFF")
	assert_eq(MiniFit.field(rec[1], REC_POWER), 200)
	assert_eq(MiniFit.field(rec[2], REC_CADENCE), INVALID_U8, "нет каденса → 0xFF")
	assert_eq(MiniFit.field(rec[3], REC_POWER), INVALID_U16, "нет мощности → 0xFFFF, не 0")
	assert_eq(MiniFit.field(rec[3], REC_HEART_RATE), INVALID_U8)
	assert_eq(MiniFit.field(rec[3], REC_CADENCE), INVALID_U8)
	assert_eq(MiniFit.field(rec[3], REC_SPEED), INVALID_U16, "нет скорости → 0xFFFF")
	assert_eq(MiniFit.field(rec[4], REC_CADENCE), 0, "каденс 0 — реальное значение, не invalid")
	assert_eq(MiniFit.field(rec[0], REC_HEART_RATE), 120)
	# Заезд совсем без пульса/каденса: session avg_hr / avg_cadence invalid.
	var fit2 := decode(FitEncoder.encode(_ride(_stream([200, 200, 200]))))
	var ses := fit2.first(G_SESSION)
	assert_eq(MiniFit.field(ses, SES_AVG_HR), INVALID_U8, "session.avg_heart_rate invalid без пульса")
	assert_eq(MiniFit.field(ses, SES_MAX_HR), INVALID_U8)
	assert_eq(MiniFit.field(ses, SES_AVG_CADENCE), INVALID_U8, "session.avg_cadence invalid без каденса")
	assert_eq(MiniFit.field(ses, SES_AVG_POWER), 200)
	for m in fit2.of(G_RECORD):
		assert_eq(MiniFit.field(m, REC_HEART_RATE), INVALID_U8)
		assert_eq(MiniFit.field(m, REC_CADENCE), INVALID_U8)
	# Заезд без мощности вообще: session avg/max/NP invalid, total_work 0.
	var fit3 := decode(FitEncoder.encode(_ride(_stream([-1, -1], [120, 121]))))
	var ses3 := fit3.first(G_SESSION)
	assert_eq(MiniFit.field(ses3, SES_AVG_POWER), INVALID_U16, "session.avg_power invalid без мощности")
	assert_eq(MiniFit.field(ses3, SES_MAX_POWER), INVALID_U16)
	assert_eq(MiniFit.field(ses3, SES_NP), INVALID_U16)
	assert_eq(MiniFit.field(ses3, SES_TOTAL_WORK), 0)


func test_req_loc_05_c2_c4_pauses_as_timer_events_and_elapsed_minus_timer() -> void:
	var powers: Array = []
	for i in 200:
		powers.append(150)
	var ride := _ride(_stream(powers), [[120.0, 30.0]])
	var fit := decode(FitEncoder.encode(ride))
	assert_true(fit.ok, fit.error)
	var events := _event_list(fit)
	assert_eq(events.size(), 4, "start, stop_all (пауза), start (возобновление), stop_all (конец)")
	if events.size() == 4:
		assert_eq(events[0], [START_UNIX, EV_TYPE_START])
		assert_eq(events[1], [START_UNIX + 120, EV_TYPE_STOP_ALL], "stop_all в at_sec = 120")
		assert_eq(events[2], [START_UNIX + 150, EV_TYPE_START], "start в until_sec = 150")
		assert_eq(events[3], [START_UNIX + 230, EV_TYPE_STOP_ALL], "stop_all в конце: 200 с активного + 30 с паузы")
	var rec := fit.of(G_RECORD)
	assert_eq(rec.size(), 200, "число record = число сэмплов")
	assert_eq(MiniFit.field(rec[119], F_TIMESTAMP) + FIT_EPOCH, START_UNIX + 119, "последний сэмпл до паузы")
	assert_eq(MiniFit.field(rec[120], F_TIMESTAMP) + FIT_EPOCH, START_UNIX + 150, "первый сэмпл после паузы сдвинут на 30 с")
	var prev := -1
	for m in rec:
		assert_gte(MiniFit.field(m, F_TIMESTAMP), prev)
		prev = MiniFit.field(m, F_TIMESTAMP)
	# Порядок сообщений: stop_all и start стоят между record 119 и record 120.
	var seq: Array = []
	for m in fit.messages:
		if int(m["global"]) == G_RECORD or int(m["global"]) == G_EVENT:
			seq.append([int(m["global"]), MiniFit.field(m, F_TIMESTAMP) + FIT_EPOCH])
	var idx_stop := seq.find([G_EVENT, START_UNIX + 120])
	var idx_start := seq.find([G_EVENT, START_UNIX + 150])
	var idx_rec119 := seq.find([G_RECORD, START_UNIX + 119])
	var idx_rec120 := seq.find([G_RECORD, START_UNIX + 150])
	assert_true(idx_rec119 < idx_stop and idx_stop < idx_start and idx_start < idx_rec120, "события паузы хронологически между записями")
	var ses := fit.first(G_SESSION)
	assert_eq(MiniFit.field(ses, SES_TOTAL_TIMER), 200_000, "total_timer_time = 200 с активного")
	assert_eq(MiniFit.field(ses, SES_TOTAL_ELAPSED), 230_000, "total_elapsed_time = 200 + 30 с")
	assert_eq(MiniFit.field(ses, SES_TOTAL_ELAPSED) - MiniFit.field(ses, SES_TOTAL_TIMER), roundi(ride.paused_total_sec() * 1000.0),
			"elapsed − timer = paused_total_sec")


func test_req_loc_05_c2_two_pauses() -> void:
	var powers: Array = []
	for i in 100:
		powers.append(150)
	var ride := _ride(_stream(powers), [[10.0, 5.0], [50.0, 7.0]])
	var fit := decode(FitEncoder.encode(ride))
	assert_true(fit.ok, fit.error)
	var events := _event_list(fit)
	assert_eq(events, [[START_UNIX, EV_TYPE_START], [START_UNIX + 10, EV_TYPE_STOP_ALL], [START_UNIX + 15, EV_TYPE_START],
			[START_UNIX + 55, EV_TYPE_STOP_ALL], [START_UNIX + 62, EV_TYPE_START], [START_UNIX + 112, EV_TYPE_STOP_ALL]],
			"две паузы: вторая сдвинута на длительность первой")
	var ses := fit.first(G_SESSION)
	assert_eq(MiniFit.field(ses, SES_TOTAL_ELAPSED) - MiniFit.field(ses, SES_TOTAL_TIMER), 12_000, "paused_total = 12 с")
	var rec := fit.of(G_RECORD)
	assert_eq(MiniFit.field(rec[99], F_TIMESTAMP) + FIT_EPOCH, START_UNIX + 99 + 12, "последний сэмпл сдвинут на обе паузы")


func test_req_loc_05_c2_speed_follows_speed_source_trainer_vs_model() -> void:
	var plan := Workout.make("Speed", [WorkoutStep.watts(10, 150.0)], "zwo")
	var trainer_ride := _session_ride(plan, 150, true)
	assert_not_null(trainer_ride)
	if trainer_ride != null:
		assert_eq(trainer_ride.speed_source(), SampleStream.SPEED_SOURCE_TRAINER)
		var fit := decode(FitEncoder.encode(trainer_ride))
		assert_true(fit.ok, fit.error)
		var rec := fit.of(G_RECORD)
		assert_eq(rec.size(), 10)
		for i in rec.size():
			assert_eq(MiniFit.field(rec[i], REC_SPEED), roundi(trainer_ride.samples.speed_kmh[i] / 3.6 * 1000.0), "скорость станка в record %d" % i)
			assert_gt(MiniFit.field(rec[i], REC_SPEED), 0)
	_recorder.dispose()
	_recorder = null
	_repo = FileRideRepository.new(_dir + "model/")
	var model_ride := _session_ride(plan, 150, false)
	assert_not_null(model_ride)
	if model_ride != null:
		assert_eq(model_ride.speed_source(), SampleStream.SPEED_SOURCE_MODEL, "станок без скорости → модель")
		var fit := decode(FitEncoder.encode(model_ride))
		assert_true(fit.ok, fit.error)
		var rec := fit.of(G_RECORD)
		assert_eq(rec.size(), 10)
		var any_speed := false
		for i in rec.size():
			assert_eq(MiniFit.field(rec[i], REC_SPEED), roundi(model_ride.samples.speed_kmh[i] / 3.6 * 1000.0), "скорость модели в record %d" % i)
			if MiniFit.field(rec[i], REC_SPEED) > 0:
				any_speed = true
		assert_true(any_speed, "модель даёт ненулевую скорость при 150 Вт")
		assert_eq(MiniFit.field(rec[9], REC_DISTANCE), roundi(model_ride.samples.total_distance_m() * 100.0), "дистанция = интеграл скорости модели")


func test_req_loc_05_c2_laps_per_plan_step_from_session() -> void:
	var plan := Workout.make("Laps", [WorkoutStep.watts(5, 100.0), WorkoutStep.watts(7, 200.0), WorkoutStep.watts(4, 150.0)], "zwo")
	var ride := _session_ride(plan)
	assert_not_null(ride)
	if ride == null:
		return
	var fit := decode(FitEncoder.encode(ride))
	assert_true(fit.ok, fit.error)
	var laps := fit.of(G_LAP)
	assert_eq(laps.size(), 3, "lap на каждый шаг плана")
	if laps.size() == 3:
		assert_eq(MiniFit.field(laps[0], LAP_TOTAL_TIMER), 5000)
		assert_eq(MiniFit.field(laps[1], LAP_TOTAL_TIMER), 7000)
		assert_eq(MiniFit.field(laps[2], LAP_TOTAL_TIMER), 4000)
		var sum := 0
		for l in laps:
			sum += MiniFit.field(l, LAP_TOTAL_TIMER)
		assert_eq(sum, 16_000, "сумма lap = total_timer_time")
		assert_eq(MiniFit.field(laps[1], LAP_START_TIME), MiniFit.field(laps[0], LAP_START_TIME) + 5, "lap 2 начинается после lap 1")
	assert_eq(fit.first(G_SESSION)["fields"][SES_NUM_LAPS], 3)
	assert_eq(fit.of(G_RECORD).size(), 16)


func test_req_loc_05_c2_session_values_equal_summary_from_real_session_with_pause() -> void:
	var plan := Workout.make("Real", [WorkoutStep.watts(40, 150.0), WorkoutStep.watts(40, 250.0)], "zwo")
	var ride := _session_ride(plan, 150, true, func(s: WorkoutSession) -> void:
		for i in 30:
			s.tick(1.0)
		s.pause()
		for i in 8:
			s.tick(1.0)
		s.resume()
		for i in 50:
			s.tick(1.0))
	assert_not_null(ride)
	if ride == null:
		return
	assert_eq(ride.samples.size(), 80)
	var fit := decode(FitEncoder.encode(ride))
	assert_true(fit.ok, fit.error)
	var ses := fit.first(G_SESSION)
	assert_eq(MiniFit.field(ses, SES_AVG_POWER), ride.summary.avg_power_w, "avg_power = сводка")
	assert_eq(MiniFit.field(ses, SES_MAX_POWER), ride.summary.max_power_w, "max_power = сводка")
	assert_eq(MiniFit.field(ses, SES_NP), ride.summary.normalized_power_w, "NP = сводка")
	assert_eq(MiniFit.field(ses, SES_TOTAL_WORK), roundi(ride.summary.work_kj * 1000.0), "work = сводка")
	assert_eq(MiniFit.field(ses, SES_AVG_HR), ride.summary.avg_hr)
	assert_eq(MiniFit.field(ses, SES_TOTAL_TIMER), 80_000)
	assert_eq(MiniFit.field(ses, SES_TOTAL_ELAPSED), 88_000, "80 с + 8 с паузы")
	assert_eq(fit.of(G_RECORD).size(), 80)
	var events := _event_list(fit)
	assert_eq(events.size(), 4)
	if events.size() == 4:
		assert_eq(events[1][1], EV_TYPE_STOP_ALL)
		assert_eq(events[1][0], ride.started_at_unix + 30)
		assert_eq(events[2][1], EV_TYPE_START)
		assert_eq(events[2][0], ride.started_at_unix + 38)
	assert_eq(MiniFit.field(ses, SES_AVG_POWER), 200, "40 с × 150 + 40 с × 250 → 200")


func test_req_loc_05_empty_stream_valid_fit_without_records() -> void:
	var ride := _ride(_stream([]))
	var bytes := FitEncoder.encode(ride)
	var fit := decode(bytes)
	assert_true(fit.ok, "пустой заезд — валидный файл: " + fit.error)
	assert_eq(fit.of(G_RECORD).size(), 0, "без record")
	assert_false(fit.first(G_FILE_ID).is_empty())
	assert_false(fit.first(G_SESSION).is_empty())
	assert_eq(fit.of(G_ACTIVITY).size(), 1)
	assert_eq(MiniFit.field(fit.first(G_SESSION), SES_TOTAL_TIMER), 0)
	assert_eq(MiniFit.field(fit.first(G_SESSION), SES_SPORT), SPORT_CYCLING)
	var events := _event_list(fit)
	assert_eq(events.size(), 2)
	assert_true(FitDecoder.decode(bytes).ok)


func test_req_loc_05_long_ride_timestamps_monotonic_and_counts() -> void:
	var powers: Array = []
	var steps: Array = []
	for i in 3600:
		powers.append(100 + (i % 200))
		steps.append(i / 600)
	var ride := _ride(_stream(powers, [], [], [], steps), [[1000.0, 60.0], [2000.0, 120.0]])
	var bytes := FitEncoder.encode(ride)
	var fit := decode(bytes)
	assert_true(fit.ok, fit.error)
	assert_eq(fit.of(G_RECORD).size(), 3600)
	assert_eq(fit.of(G_LAP).size(), 6)
	var prev := -1
	for m in fit.messages:
		if (m["fields"] as Dictionary).has(F_TIMESTAMP) and int(m["global"]) in [G_RECORD, G_EVENT]:
			var ts := MiniFit.field(m, F_TIMESTAMP)
			assert_true(ts >= prev, "timestamp не убывает")
			prev = ts
	var ses := fit.first(G_SESSION)
	assert_eq(MiniFit.field(ses, SES_TOTAL_TIMER), 3_600_000)
	assert_eq(MiniFit.field(ses, SES_TOTAL_ELAPSED), 3_780_000)


# ===========================================================================
# REQ-STR-02 крит. 2
# ===========================================================================

func test_req_str_02_c2_sport_cycling_sub_sport_virtual_activity() -> void:
	var fit := decode(FitEncoder.encode(_ride(_stream([100, 100]))))
	var ses := fit.first(G_SESSION)
	assert_eq(MiniFit.field(ses, SES_SPORT), 2, "sport = cycling (2)")
	assert_eq(MiniFit.field(ses, SES_SUB_SPORT), 58, "sub_sport = virtual_activity (58)")
	assert_eq(fit.of(G_SESSION).size(), 1, "ровно одна session")


# ===========================================================================
# Дополнение приёмки (второй проход): дробные паузы, завершение на паузе,
# lap через паузу, file_id для Strava.
# ===========================================================================

## Крит. 4: «total_elapsed_time − total_timer_time равно paused_total_sec заезда».
## Реальные паузы дробные (кадры); допуск — половина секунды на весь заезд
## (FIT хранит метки в секундах), но ошибка не должна накапливаться по паузам.
func test_req_loc_05_c4_fractional_pauses_elapsed_minus_timer_equals_paused_total() -> void:
	var plan := Workout.make("Frac", [WorkoutStep.watts(60, 150.0)], "zwo")
	var ride := _session_ride(plan, 150, true, func(s: WorkoutSession) -> void:
		for i in 10:
			s.tick(1.0)
		s.pause()
		for i in 5:
			s.tick(0.5)  # 2.5 с
		s.resume()
		for i in 10:
			s.tick(1.0)
		s.pause()
		for i in 5:
			s.tick(0.5)  # 2.5 с
		s.resume()
		for i in 10:
			s.tick(1.0)
		s.stop())
	assert_not_null(ride)
	if ride == null:
		return
	assert_almost_eq(ride.paused_total_sec(), 5.0, 1e-6, "предпосылка: в метаданных заезда 5.0 с пауз")
	assert_eq(ride.samples.size(), 30)
	var fit := decode(FitEncoder.encode(ride))
	assert_true(fit.ok, fit.error)
	var ses := fit.first(G_SESSION)
	var paused_ms := MiniFit.field(ses, SES_TOTAL_ELAPSED) - MiniFit.field(ses, SES_TOTAL_TIMER)
	gut.p("paused_total_sec %.2f → FIT elapsed − timer = %d мс" % [ride.paused_total_sec(), paused_ms])
	assert_eq(MiniFit.field(ses, SES_TOTAL_TIMER), 30_000)
	assert_almost_eq(float(paused_ms), ride.paused_total_sec() * 1000.0, 500.0,
			"elapsed − timer = paused_total_sec (ожидалось %.0f мс, получено %d мс)" % [ride.paused_total_sec() * 1000.0, paused_ms])


## Крит. 2, 4: заезд завершён досрочно на паузе — файл валиден, число record =
## число сэмплов, elapsed − timer согласуется с paused_total_sec, события не рвут порядок.
func test_req_loc_05_c2_c4_stop_while_paused_yields_valid_consistent_file() -> void:
	var plan := Workout.make("StopPaused", [WorkoutStep.watts(60, 150.0)], "zwo")
	var ride := _session_ride(plan, 150, true, func(s: WorkoutSession) -> void:
		for i in 20:
			s.tick(1.0)
		s.pause()
		for i in 7:
			s.tick(1.0)
		s.stop())
	assert_not_null(ride)
	if ride == null:
		return
	assert_true(ride.stopped_early())
	assert_eq(ride.samples.size(), 20)
	var bytes := FitEncoder.encode(ride)
	var fit := decode(bytes)
	assert_true(fit.ok, fit.error)
	assert_true(FitDecoder.decode(bytes).ok)
	assert_eq(fit.of(G_RECORD).size(), 20, "record = сэмплы")
	var ses := fit.first(G_SESSION)
	assert_eq(MiniFit.field(ses, SES_TOTAL_TIMER), 20_000)
	assert_eq(MiniFit.field(ses, SES_TOTAL_ELAPSED) - MiniFit.field(ses, SES_TOTAL_TIMER), roundi(ride.paused_total_sec() * 1000.0),
			"elapsed − timer = paused_total_sec заезда")
	var events := _event_list(fit)
	assert_eq(events[0][1], EV_TYPE_START)
	assert_eq(events[events.size() - 1][1], EV_TYPE_STOP_ALL, "последнее событие — stop_all")
	var prev := -1
	for e in events:
		assert_gte(int(e[0]), prev, "метки событий не убывают")
		prev = int(e[0])
	gut.p("stop on pause: paused_total_sec в метаданных = %.1f (7 с паузы до stop не учтены)" % ride.paused_total_sec())


## Крит. 2: lap, внутри которого была пауза — elapsed включает паузу, timer нет.
func test_req_loc_05_c2_lap_spanning_pause_elapsed_includes_pause() -> void:
	var powers: Array = []
	var steps: Array = []
	for i in 60:
		powers.append(150)
		steps.append(0 if i < 30 else 1)
	var ride := _ride(_stream(powers, [], [], [], steps), [[10.0, 20.0]])
	var fit := decode(FitEncoder.encode(ride))
	assert_true(fit.ok, fit.error)
	var laps := fit.of(G_LAP)
	assert_eq(laps.size(), 2)
	if laps.size() != 2:
		return
	assert_eq(MiniFit.field(laps[0], LAP_TOTAL_TIMER), 30_000, "lap 1 timer = 30 с активного")
	assert_eq(MiniFit.field(laps[0], LAP_TOTAL_ELAPSED), 50_000, "lap 1 elapsed = 30 + 20 с паузы")
	assert_eq(MiniFit.field(laps[1], LAP_TOTAL_TIMER), 30_000)
	assert_eq(MiniFit.field(laps[1], LAP_TOTAL_ELAPSED), 30_000, "lap 2 без паузы")
	assert_eq(MiniFit.field(laps[1], LAP_START_TIME) + FIT_EPOCH, START_UNIX + 50, "lap 2 начинается после паузы")
	var ses := fit.first(G_SESSION)
	assert_eq(MiniFit.field(ses, SES_TOTAL_ELAPSED), 80_000)
	assert_eq(MiniFit.field(ses, SES_NUM_LAPS), 2)


## Крит. 2 + STR-02: file_id содержит manufacturer, product, time_created = старт
## (без них Strava отклоняет файл как некорректный FIT).
func test_req_loc_05_c2_file_id_has_manufacturer_product_time_created() -> void:
	var fit := decode(FitEncoder.encode(_ride(_stream([100, 100, 100]))))
	assert_true(fit.ok, fit.error)
	var file_id := fit.first(G_FILE_ID)
	assert_eq(MiniFit.field(file_id, FILE_ID_TYPE), FILE_TYPE_ACTIVITY)
	assert_ne(MiniFit.field(file_id, 1), -1, "manufacturer присутствует")
	assert_ne(MiniFit.field(file_id, 1), INVALID_U16, "manufacturer не invalid")
	assert_ne(MiniFit.field(file_id, 2), -1, "product присутствует")
	assert_eq(MiniFit.field(file_id, 4) + FIT_EPOCH, START_UNIX, "time_created = старт заезда")
	assert_eq(fit.of(G_FILE_ID).size(), 1, "ровно один file_id")
