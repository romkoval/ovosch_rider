class_name FitEncoder
extends RefCounted
## Кодировщик заезда в файл FIT (REQ-LOC-05 крит. 1–4, REQ-STR-02 крит. 2,
## REQ-WRK-05 крит. 2 — паузы как `event timer stop_all/start`).
##
## Структура файла (Garmin FIT SDK, protocol 2.0): заголовок 14 байт с
## сигнатурой `.FIT` и CRC заголовка; сообщения `file_id` (activity,
## manufacturer development), `file_creator`, `device_info`, `event` (timer
## start; на каждую паузу `stop_all` и `start`; `stop_all` в конце), `record`
## на каждый сэмпл (timestamp, power, heart_rate, cadence, speed, distance —
## отсутствующие значения invalid, не 0), `lap` на каждый шаг плана
## (по `step_index` потока), `session` (sport cycling, sub_sport
## virtual_activity, времена, средние/максимумы, NP, работа), `activity`;
## CRC-16 всего файла в конце.
##
## Время: метки `record` — unix-время старта + активное время сэмпла + сумма
## пауз, завершившихся к этому сэмплу (на паузе слоты не пишутся, В-4), поэтому
## `total_timer_time` = число сэмплов (активное время), `total_elapsed_time` =
## активное + паузы. Скорость — из потока согласно `speed_source` заезда (В-8),
## дистанция — интеграл скорости (`SampleStream.distance_m`).

const PRODUCT_ID: int = 1
const SOFTWARE_VERSION: int = 100
const PRODUCT_NAME: String = "ovosch-rider"
const PRODUCT_NAME_SIZE: int = 16

const LOCAL_FILE_ID: int = 0
const LOCAL_FILE_CREATOR: int = 1
const LOCAL_DEVICE_INFO: int = 2
const LOCAL_EVENT: int = 3
const LOCAL_RECORD: int = 4
const LOCAL_LAP: int = 5
const LOCAL_SESSION: int = 6
const LOCAL_ACTIVITY: int = 7


## Собранный поток сообщений: определения и данные.
class Writer:
	extends RefCounted
	var buf := StreamPeerBuffer.new()
	## local → Array of [field_num, size, base_type]
	var defs: Dictionary = {}

	func define(local: int, global_num: int, fields: Array) -> void:
		defs[local] = fields
		buf.put_u8(FitDefinitions.HDR_DEFINITION | (local & FitDefinitions.HDR_LOCAL_MASK))
		buf.put_u8(0)  # reserved
		buf.put_u8(0)  # architecture: little-endian
		buf.put_u16(global_num)
		buf.put_u8(fields.size())
		for f in fields:
			buf.put_u8(int(f[0]))
			buf.put_u8(int(f[1]))
			buf.put_u8(int(f[2]))

	## Данные в порядке полей определения; null — invalid-значение.
	func data(local: int, values: Array) -> void:
		var fields: Array = defs[local]
		assert(values.size() == fields.size(), "FitEncoder: число значений не совпадает с определением")
		buf.put_u8(local & FitDefinitions.HDR_LOCAL_MASK)
		for i in fields.size():
			_put(int(fields[i][1]), int(fields[i][2]), values[i])

	func _put(size: int, base_type: int, value: Variant) -> void:
		if base_type == FitDefinitions.T_STRING:
			var text: PackedByteArray = str(value).to_utf8_buffer() if value != null else PackedByteArray()
			for i in size:
				buf.put_u8(text[i] if i < text.size() and i < size - 1 else 0)
			return
		if base_type == FitDefinitions.T_FLOAT32:
			if value == null:
				buf.put_u32(FitDefinitions.INVALID[base_type])
			else:
				buf.put_float(float(value))
			return
		var v: int = int(FitDefinitions.INVALID[base_type]) if value == null else int(value)
		match base_type:
			FitDefinitions.T_ENUM, FitDefinitions.T_UINT8, FitDefinitions.T_UINT8Z, FitDefinitions.T_BYTE:
				buf.put_u8(clampi(v, 0, 0xFF))
			FitDefinitions.T_SINT8:
				buf.put_8(clampi(v, -128, 127))
			FitDefinitions.T_UINT16, FitDefinitions.T_UINT16Z:
				buf.put_u16(clampi(v, 0, 0xFFFF))
			FitDefinitions.T_SINT16:
				buf.put_16(clampi(v, -32768, 32767))
			FitDefinitions.T_UINT32, FitDefinitions.T_UINT32Z:
				buf.put_u32(clampi(v, 0, 0xFFFFFFFF))
			FitDefinitions.T_SINT32:
				buf.put_32(clampi(v, -2147483648, 2147483647))
			_:
				push_error("FitEncoder: неподдерживаемый базовый тип 0x%02X" % base_type)
				for i in size:
					buf.put_u8(0xFF)

	func bytes() -> PackedByteArray:
		return buf.data_array


## Закодировать заезд. Сводка берётся из `ride.summary`, если она соответствует
## потоку, иначе пересчитывается (без изменения заезда).
static func encode(ride: Ride) -> PackedByteArray:
	var samples: SampleStream = ride.samples
	var n: int = samples.size()
	var summary: RideSummary = ride.summary
	if summary == null or summary.duration_sec != n:
		summary = RideSummary.compute(samples, ride.ftp_w(), ride.power_zones(), ride.hr_zones())
	var started: int = ride.started_at_unix if ride.started_at_unix > 0 else FitDefinitions.FIT_EPOCH_UNIX
	var pauses: Array[Dictionary] = ride.pause_events()
	var paused_total: int = 0
	for p in pauses:
		paused_total += roundi(float(p["duration_sec"]))
	var end_unix: int = started + n + paused_total
	var timestamps: PackedInt64Array = _record_timestamps(samples, started, pauses)

	var w := Writer.new()
	_write_file_id(w, started)
	_write_file_creator(w)
	_write_device_info(w, started)
	_define_event(w)
	_event(w, started, FitDefinitions.EVENT_TYPE_START)
	_define_record(w)
	_write_records_with_pauses(w, samples, timestamps, started, pauses)
	_event(w, end_unix, FitDefinitions.EVENT_TYPE_STOP_ALL)
	var laps: int = _write_laps(w, samples, timestamps, started, end_unix)
	_write_session(w, ride, summary, started, end_unix, n, laps)
	_write_activity(w, end_unix, n)

	var body: PackedByteArray = w.bytes()
	var out := StreamPeerBuffer.new()
	out.put_u8(FitDefinitions.HEADER_SIZE)
	out.put_u8(FitDefinitions.PROTOCOL_VERSION)
	out.put_u16(FitDefinitions.PROFILE_VERSION)
	out.put_u32(body.size())
	out.put_data(FitDefinitions.SIGNATURE.to_ascii_buffer())
	out.put_u16(FitCrc.compute(out.data_array, 0, 12))
	out.put_data(body)
	var file_crc: int = FitCrc.compute(out.data_array)
	out.put_u16(file_crc)
	return out.data_array


## Метки времени записей (unix): старт + активное время + паузы, завершившиеся к сэмплу.
static func _record_timestamps(samples: SampleStream, started: int, pauses: Array[Dictionary]) -> PackedInt64Array:
	var out := PackedInt64Array()
	out.resize(samples.size())
	var k: int = 0
	var paused: int = 0
	for i in samples.size():
		var t: int = samples.time_sec[i]
		while k < pauses.size() and int(floor(float(pauses[k]["at_sec"]))) <= t:
			paused += roundi(float(pauses[k]["duration_sec"]))
			k += 1
		out[i] = started + t + paused
	return out


static func _write_file_id(w: Writer, started: int) -> void:
	w.define(LOCAL_FILE_ID, FitDefinitions.MSG_FILE_ID, [
		[FitDefinitions.FILE_ID_TYPE, 1, FitDefinitions.T_ENUM],
		[FitDefinitions.FILE_ID_MANUFACTURER, 2, FitDefinitions.T_UINT16],
		[FitDefinitions.FILE_ID_PRODUCT, 2, FitDefinitions.T_UINT16],
		[FitDefinitions.FILE_ID_TIME_CREATED, 4, FitDefinitions.T_UINT32],
		[FitDefinitions.FILE_ID_PRODUCT_NAME, PRODUCT_NAME_SIZE, FitDefinitions.T_STRING],
	])
	w.data(LOCAL_FILE_ID, [FitDefinitions.FILE_TYPE_ACTIVITY, FitDefinitions.MANUFACTURER_DEVELOPMENT,
		PRODUCT_ID, FitDefinitions.to_fit_time(started), PRODUCT_NAME])


static func _write_file_creator(w: Writer) -> void:
	w.define(LOCAL_FILE_CREATOR, FitDefinitions.MSG_FILE_CREATOR, [
		[FitDefinitions.FILE_CREATOR_SOFTWARE_VERSION, 2, FitDefinitions.T_UINT16],
		[FitDefinitions.FILE_CREATOR_HARDWARE_VERSION, 1, FitDefinitions.T_UINT8],
	])
	w.data(LOCAL_FILE_CREATOR, [SOFTWARE_VERSION, null])


static func _write_device_info(w: Writer, started: int) -> void:
	w.define(LOCAL_DEVICE_INFO, FitDefinitions.MSG_DEVICE_INFO, [
		[FitDefinitions.F_TIMESTAMP, 4, FitDefinitions.T_UINT32],
		[FitDefinitions.DEVICE_INFO_DEVICE_INDEX, 1, FitDefinitions.T_UINT8],
		[FitDefinitions.DEVICE_INFO_MANUFACTURER, 2, FitDefinitions.T_UINT16],
		[FitDefinitions.DEVICE_INFO_PRODUCT, 2, FitDefinitions.T_UINT16],
		[FitDefinitions.DEVICE_INFO_SOFTWARE_VERSION, 2, FitDefinitions.T_UINT16],
		[FitDefinitions.DEVICE_INFO_PRODUCT_NAME, PRODUCT_NAME_SIZE, FitDefinitions.T_STRING],
	])
	w.data(LOCAL_DEVICE_INFO, [FitDefinitions.to_fit_time(started), FitDefinitions.DEVICE_INDEX_CREATOR,
		FitDefinitions.MANUFACTURER_DEVELOPMENT, PRODUCT_ID, SOFTWARE_VERSION, PRODUCT_NAME])


static func _define_event(w: Writer) -> void:
	w.define(LOCAL_EVENT, FitDefinitions.MSG_EVENT, [
		[FitDefinitions.F_TIMESTAMP, 4, FitDefinitions.T_UINT32],
		[FitDefinitions.EVENT_EVENT, 1, FitDefinitions.T_ENUM],
		[FitDefinitions.EVENT_EVENT_TYPE, 1, FitDefinitions.T_ENUM],
		[FitDefinitions.EVENT_EVENT_GROUP, 1, FitDefinitions.T_UINT8],
	])


static func _event(w: Writer, unix: int, event_type: int) -> void:
	w.data(LOCAL_EVENT, [FitDefinitions.to_fit_time(unix), FitDefinitions.EVENT_TIMER, event_type, 0])


static func _define_record(w: Writer) -> void:
	w.define(LOCAL_RECORD, FitDefinitions.MSG_RECORD, [
		[FitDefinitions.F_TIMESTAMP, 4, FitDefinitions.T_UINT32],
		[FitDefinitions.RECORD_POWER, 2, FitDefinitions.T_UINT16],
		[FitDefinitions.RECORD_HEART_RATE, 1, FitDefinitions.T_UINT8],
		[FitDefinitions.RECORD_CADENCE, 1, FitDefinitions.T_UINT8],
		[FitDefinitions.RECORD_SPEED, 2, FitDefinitions.T_UINT16],
		[FitDefinitions.RECORD_DISTANCE, 4, FitDefinitions.T_UINT32],
	])


## Записи с вкраплёнными событиями пауз (stop_all / start) в хронологическом порядке.
static func _write_records_with_pauses(w: Writer, s: SampleStream, timestamps: PackedInt64Array,
		started: int, pauses: Array[Dictionary]) -> void:
	var k: int = 0
	var paused: int = 0
	for i in s.size():
		var t: int = s.time_sec[i]
		while k < pauses.size() and int(floor(float(pauses[k]["at_sec"]))) <= t:
			paused = _emit_pause(w, pauses[k], started, paused)
			k += 1
		w.data(LOCAL_RECORD, [
			FitDefinitions.to_fit_time(int(timestamps[i])),
			s.power_w[i] if s.has_power[i] else null,
			s.heart_rate_bpm[i] if s.has_heart_rate[i] else null,
			s.cadence_rpm[i] if s.has_cadence[i] else null,
			roundi(s.speed_kmh[i] / 3.6 * 1000.0) if s.has_speed[i] else null,
			roundi(s.distance_m[i] * 100.0),
		])
	# Паузы после последнего сэмпла (например, завершение на паузе).
	while k < pauses.size():
		paused = _emit_pause(w, pauses[k], started, paused)
		k += 1


static func _emit_pause(w: Writer, pause: Dictionary, started: int, paused_before: int) -> int:
	var at: int = int(floor(float(pause["at_sec"])))
	var stop_unix: int = started + at + paused_before
	_event(w, stop_unix, FitDefinitions.EVENT_TYPE_STOP_ALL)
	var duration: int = roundi(float(pause["duration_sec"]))
	if bool(pause.get("resumed", false)):
		_event(w, stop_unix + duration, FitDefinitions.EVENT_TYPE_START)
	return paused_before + duration


## `lap` на каждый шаг плана по `step_index` потока; без сэмплов — один пустой lap.
static func _write_laps(w: Writer, s: SampleStream, timestamps: PackedInt64Array, started: int, end_unix: int) -> int:
	w.define(LOCAL_LAP, FitDefinitions.MSG_LAP, [
		[FitDefinitions.F_TIMESTAMP, 4, FitDefinitions.T_UINT32],
		[FitDefinitions.F_MESSAGE_INDEX, 2, FitDefinitions.T_UINT16],
		[FitDefinitions.LAP_START_TIME, 4, FitDefinitions.T_UINT32],
		[FitDefinitions.LAP_TOTAL_ELAPSED_TIME, 4, FitDefinitions.T_UINT32],
		[FitDefinitions.LAP_TOTAL_TIMER_TIME, 4, FitDefinitions.T_UINT32],
		[FitDefinitions.LAP_TOTAL_DISTANCE, 4, FitDefinitions.T_UINT32],
		[FitDefinitions.LAP_AVG_POWER, 2, FitDefinitions.T_UINT16],
		[FitDefinitions.LAP_MAX_POWER, 2, FitDefinitions.T_UINT16],
		[FitDefinitions.LAP_AVG_HEART_RATE, 1, FitDefinitions.T_UINT8],
		[FitDefinitions.LAP_MAX_HEART_RATE, 1, FitDefinitions.T_UINT8],
		[FitDefinitions.LAP_AVG_CADENCE, 1, FitDefinitions.T_UINT8],
		[FitDefinitions.LAP_EVENT, 1, FitDefinitions.T_ENUM],
		[FitDefinitions.LAP_EVENT_TYPE, 1, FitDefinitions.T_ENUM],
		[FitDefinitions.LAP_LAP_TRIGGER, 1, FitDefinitions.T_ENUM],
		[FitDefinitions.LAP_SPORT, 1, FitDefinitions.T_ENUM],
	])
	var n: int = s.size()
	if n == 0:
		w.data(LOCAL_LAP, [FitDefinitions.to_fit_time(end_unix), 0, FitDefinitions.to_fit_time(started),
			(end_unix - started) * 1000, 0, 0, null, null, null, null, null,
			FitDefinitions.EVENT_LAP, FitDefinitions.EVENT_TYPE_STOP, FitDefinitions.LAP_TRIGGER_MANUAL, FitDefinitions.SPORT_CYCLING])
		return 1
	var laps: int = 0
	var first: int = 0
	while first < n:
		var last: int = first
		while last + 1 < n and s.step_index[last + 1] == s.step_index[first]:
			last += 1
		var count: int = last - first + 1
		var power_sum: int = 0
		var power_n: int = 0
		var max_p: int = -1
		var hr_sum: int = 0
		var hr_n: int = 0
		var max_h: int = -1
		var cad_sum: int = 0
		var cad_n: int = 0
		for i in range(first, last + 1):
			if s.has_power[i]:
				power_sum += s.power_w[i]
				power_n += 1
				max_p = maxi(max_p, s.power_w[i])
			if s.has_heart_rate[i]:
				hr_sum += s.heart_rate_bpm[i]
				hr_n += 1
				max_h = maxi(max_h, s.heart_rate_bpm[i])
			if s.has_cadence[i]:
				cad_sum += s.cadence_rpm[i]
				cad_n += 1
		var start_unix: int = int(timestamps[first])
		var lap_end_unix: int = int(timestamps[last]) + 1
		var dist_before: float = s.distance_m[first - 1] if first > 0 else 0.0
		w.data(LOCAL_LAP, [
			FitDefinitions.to_fit_time(lap_end_unix),
			laps,
			FitDefinitions.to_fit_time(start_unix),
			(lap_end_unix - start_unix) * 1000,
			count * 1000,
			roundi((s.distance_m[last] - dist_before) * 100.0),
			roundi(float(power_sum) / float(power_n)) if power_n > 0 else null,
			max_p if power_n > 0 else null,
			roundi(float(hr_sum) / float(hr_n)) if hr_n > 0 else null,
			max_h if hr_n > 0 else null,
			roundi(float(cad_sum) / float(cad_n)) if cad_n > 0 else null,
			FitDefinitions.EVENT_LAP, FitDefinitions.EVENT_TYPE_STOP, FitDefinitions.LAP_TRIGGER_MANUAL,
			FitDefinitions.SPORT_CYCLING,
		])
		laps += 1
		first = last + 1
	return laps


static func _write_session(w: Writer, ride: Ride, summary: RideSummary, started: int, end_unix: int,
		n: int, laps: int) -> void:
	w.define(LOCAL_SESSION, FitDefinitions.MSG_SESSION, [
		[FitDefinitions.F_TIMESTAMP, 4, FitDefinitions.T_UINT32],
		[FitDefinitions.F_MESSAGE_INDEX, 2, FitDefinitions.T_UINT16],
		[FitDefinitions.SESSION_START_TIME, 4, FitDefinitions.T_UINT32],
		[FitDefinitions.SESSION_TOTAL_ELAPSED_TIME, 4, FitDefinitions.T_UINT32],
		[FitDefinitions.SESSION_TOTAL_TIMER_TIME, 4, FitDefinitions.T_UINT32],
		[FitDefinitions.SESSION_TOTAL_DISTANCE, 4, FitDefinitions.T_UINT32],
		[FitDefinitions.SESSION_TOTAL_WORK, 4, FitDefinitions.T_UINT32],
		[FitDefinitions.SESSION_AVG_SPEED, 2, FitDefinitions.T_UINT16],
		[FitDefinitions.SESSION_AVG_POWER, 2, FitDefinitions.T_UINT16],
		[FitDefinitions.SESSION_MAX_POWER, 2, FitDefinitions.T_UINT16],
		[FitDefinitions.SESSION_NORMALIZED_POWER, 2, FitDefinitions.T_UINT16],
		[FitDefinitions.SESSION_THRESHOLD_POWER, 2, FitDefinitions.T_UINT16],
		[FitDefinitions.SESSION_AVG_HEART_RATE, 1, FitDefinitions.T_UINT8],
		[FitDefinitions.SESSION_MAX_HEART_RATE, 1, FitDefinitions.T_UINT8],
		[FitDefinitions.SESSION_AVG_CADENCE, 1, FitDefinitions.T_UINT8],
		[FitDefinitions.SESSION_MAX_CADENCE, 1, FitDefinitions.T_UINT8],
		[FitDefinitions.SESSION_SPORT, 1, FitDefinitions.T_ENUM],
		[FitDefinitions.SESSION_SUB_SPORT, 1, FitDefinitions.T_ENUM],
		[FitDefinitions.SESSION_EVENT, 1, FitDefinitions.T_ENUM],
		[FitDefinitions.SESSION_EVENT_TYPE, 1, FitDefinitions.T_ENUM],
		[FitDefinitions.SESSION_FIRST_LAP_INDEX, 2, FitDefinitions.T_UINT16],
		[FitDefinitions.SESSION_NUM_LAPS, 2, FitDefinitions.T_UINT16],
		[FitDefinitions.SESSION_TRIGGER, 1, FitDefinitions.T_ENUM],
	])
	var avg_speed: Variant = roundi(summary.distance_m / float(n) * 1000.0) if n > 0 else null
	w.data(LOCAL_SESSION, [
		FitDefinitions.to_fit_time(end_unix),
		0,
		FitDefinitions.to_fit_time(started),
		(end_unix - started) * 1000,
		n * 1000,
		roundi(summary.distance_m * 100.0),
		roundi(summary.work_kj * 1000.0),
		avg_speed,
		_or_invalid(summary.avg_power_w),
		_or_invalid(summary.max_power_w),
		_or_invalid(summary.normalized_power_w),
		ride.ftp_w() if ride.ftp_w() > 0 else null,
		_or_invalid(summary.avg_hr),
		_or_invalid(summary.max_hr),
		_or_invalid(summary.avg_cadence),
		_or_invalid(summary.max_cadence),
		FitDefinitions.SPORT_CYCLING,
		FitDefinitions.SUB_SPORT_VIRTUAL_ACTIVITY,
		FitDefinitions.EVENT_SESSION,
		FitDefinitions.EVENT_TYPE_STOP,
		0,
		laps,
		FitDefinitions.SESSION_TRIGGER_ACTIVITY_END,
	])


static func _write_activity(w: Writer, end_unix: int, n: int) -> void:
	w.define(LOCAL_ACTIVITY, FitDefinitions.MSG_ACTIVITY, [
		[FitDefinitions.F_TIMESTAMP, 4, FitDefinitions.T_UINT32],
		[FitDefinitions.ACTIVITY_TOTAL_TIMER_TIME, 4, FitDefinitions.T_UINT32],
		[FitDefinitions.ACTIVITY_NUM_SESSIONS, 2, FitDefinitions.T_UINT16],
		[FitDefinitions.ACTIVITY_TYPE, 1, FitDefinitions.T_ENUM],
		[FitDefinitions.ACTIVITY_EVENT, 1, FitDefinitions.T_ENUM],
		[FitDefinitions.ACTIVITY_EVENT_TYPE, 1, FitDefinitions.T_ENUM],
		[FitDefinitions.ACTIVITY_LOCAL_TIMESTAMP, 4, FitDefinitions.T_UINT32],
	])
	var tz_bias_sec: int = int(Time.get_time_zone_from_system().get("bias", 0)) * 60
	w.data(LOCAL_ACTIVITY, [
		FitDefinitions.to_fit_time(end_unix),
		n * 1000,
		1,
		FitDefinitions.ACTIVITY_TYPE_MANUAL,
		FitDefinitions.EVENT_ACTIVITY,
		FitDefinitions.EVENT_TYPE_STOP,
		FitDefinitions.to_fit_time(end_unix + tz_bias_sec),
	])


static func _or_invalid(value: int) -> Variant:
	return value if value != RideSummary.NO_DATA else null
