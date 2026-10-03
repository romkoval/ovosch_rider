class_name FileRideRepository
extends RideRepository
## Файловое хранилище заездов (REQ-LOC-01 крит. 5, решение В-3).
##
## Раскладка `<dir>/<profile_id>/`:
## - `index.json` — сводки всех заездов профиля (строки списка истории), чтобы
##   `list()` не читал каталоги заездов (500 заездов ≤ 1 с, REQ-LOC-02 крит. 2);
## - `<ride_id>/meta.json` — всё, кроме потока: метаданные, план, события,
##   статус Strava, сводка (`Ride.to_meta_dict`);
## - `<ride_id>/samples.bin` — поток сэмплов в бинарном формате с фиксированной
##   длиной записи (дозапись без перезаписи, LOC-07 крит. 1; усечённый хвост при
##   сбое отбрасывается, читаются все целые записи).
##
## Формат `samples.bin` (little-endian):
## заголовок 16 байт — `OVSR`, version u16, record_size u16, speed_source u8
## (0 — не выбран, 1 — станок, 2 — модель), 7 байт резерва; далее записи по
## `record_size` байт: time_sec i32, power_w i32, target_w i32, step_index i32,
## speed_kmh f32, distance_m f32, cadence i16, heart_rate i16, power_age i16,
## cadence_age i16, heart_rate_age i16, flags u8 (бит 0 has_power, 1 has_cadence,
## 2 has_speed, 3 has_heart_rate, 4 erg_enabled), 1 байт выравнивания.
##
## Периодический сброс во время тренировки (`save_progress`, LOC-07 крит. 4) не переименовывает
## файлы: на ext4 rename поверх существующего файла запускает принудительную запись данных
## (auto_da_alloc) и на нагруженном диске занимает сотни миллисекунд. Поэтому поток
## дописывается в конец `samples.bin`, а метаданные пишутся на место в
## `<ride_id>/meta.progress.json` — без усечения (хвост добивается пробелами) и без rename;
## `index.json` при этом обновляется только в памяти. Читатель берёт `meta.progress.json`, только
## если `meta.json` помечен `in_progress`, копия разбирается и не старше `meta.json` (по
## `event_count`, `elapsed_sec`); оборванная запись копии → используется `meta.json`
## (не старше начала заезда или последней паузы). `save`/`save_meta` пишут атомарно и
## удаляют копию.
##
## Устойчивость: JSON и полная перезапись `samples.bin` идут через временный файл и
## переименование (`AtomicFile`), дозапись — в конец существующего файла; повреждённый
## `index.json` перестраивается по `meta.json` заездов; повреждённый `meta.json`
## исключает заезд из списка; повреждённый `samples.bin` даёт заезд с пустым потоком.

const DEFAULT_DIR: String = "user://rides/"
const INDEX_FILE: String = "index.json"
const META_FILE: String = "meta.json"
## Промежуточная копия метаданных незавершённого заезда (см. `save_progress`).
const PROGRESS_FILE: String = "meta.progress.json"
const SAMPLES_FILE: String = "samples.bin"
const INDEX_SCHEMA_VERSION: int = 1

const SAMPLES_MAGIC: int = 0x5253564F  # "OVSR" little-endian
const SAMPLES_VERSION: int = 1
const SAMPLES_HEADER_SIZE: int = 16
const SAMPLES_RECORD_SIZE: int = 36
const FLAG_POWER: int = 1
const FLAG_CADENCE: int = 2
const FLAG_SPEED: int = 4
const FLAG_HEART_RATE: int = 8
const FLAG_ERG: int = 16

var _dir: String
## Кэш индексов: profile_id → Array[RideSummary] (новые сверху).
var _index_cache: Dictionary = {}
## ride_id → profile_id.
var _locations: Dictionary = {}


func _init(dir_path: String = DEFAULT_DIR) -> void:
	_dir = dir_path if dir_path.ends_with("/") else dir_path + "/"


func dir_path() -> String:
	return _dir


# ---------------------------------------------------------------------------
# RideRepository
# ---------------------------------------------------------------------------

func save(ride: Ride) -> String:
	if ride == null or ride.profile_id.is_empty():
		push_warning("FileRideRepository.save: заезд без профиля не сохраняется")
		return ""
	if ride.id.is_empty():
		ride.id = Ride.generate_id(ride.started_at_unix)
	var dir := _ride_dir(ride.profile_id, ride.id)
	if not _ensure_dir(dir):
		return ""
	if not _write_meta(ride):
		return ""
	if not _write_samples_file(dir.path_join(SAMPLES_FILE), ride.samples):
		return ""
	_locations[ride.id] = ride.profile_id
	_index_put(ride)
	rides_changed.emit(ride.profile_id)
	ride_saved.emit(ride.id)
	return ride.id


func save_meta(ride: Ride) -> bool:
	if ride == null or ride.profile_id.is_empty() or ride.id.is_empty():
		push_warning("FileRideRepository.save_meta: нужен заезд с id и профилем")
		return false
	if not _ensure_dir(_ride_dir(ride.profile_id, ride.id)):
		return false
	if not _write_meta(ride):
		return false
	_locations[ride.id] = ride.profile_id
	_index_put(ride)
	rides_changed.emit(ride.profile_id)
	return true


## Периодический сброс метаданных (LOC-07 крит. 1, 4): запись на место в `meta.progress.json`
## без усечения и rename, индекс — только в памяти (на диске остаётся запись `in_progress`
## от начала заезда). Для завершённого заезда — обычный `save_meta`.
func save_progress(ride: Ride) -> bool:
	if ride == null or ride.profile_id.is_empty() or ride.id.is_empty():
		push_warning("FileRideRepository.save_progress: нужен заезд с id и профилем")
		return false
	if not ride.is_in_progress():
		return save_meta(ride)
	var dir := _ride_dir(ride.profile_id, ride.id)
	if not DirAccess.dir_exists_absolute(dir) or not FileAccess.file_exists(dir.path_join(META_FILE)):
		return save_meta(ride)  # первая запись заезда — атомарно
	if not _write_in_place(dir.path_join(PROGRESS_FILE), JSON.stringify(ride.to_meta_dict()).to_utf8_buffer()):
		return false
	_locations[ride.id] = ride.profile_id
	_index_put(ride, false)
	rides_changed.emit(ride.profile_id)
	return true


func append_samples(id: String, samples: SampleStream, from_index: int) -> bool:
	var profile_id := _profile_of(id)
	if profile_id.is_empty():
		push_warning("FileRideRepository.append_samples: заезд %s не найден" % id)
		return false
	var dir := _ride_dir(profile_id, id)
	if not _ensure_dir(dir):
		return false
	var path := dir.path_join(SAMPLES_FILE)
	var existing: int = _count_records(path)
	if existing < 0 or existing != clampi(from_index, 0, samples.size()):
		# Файла нет, он повреждён или рассинхронизирован с потоком — переписать целиком.
		return _write_samples_file(path, samples)
	var file := FileAccess.open(path, FileAccess.READ_WRITE)
	if file == null:
		push_error("FileRideRepository: не удалось открыть %s (%s)" % [path, error_string(FileAccess.get_open_error())])
		return false
	var source_code: int = _speed_source_code(samples.speed_source)
	file.seek(8)
	if file.get_8() != source_code and source_code != 0:
		file.seek(8)
		file.store_8(source_code)
	file.seek_end()
	file.store_buffer(_encode_records(samples, existing, samples.size()))
	file.close()
	return true


func get_ride(id: String) -> Ride:
	var profile_id := _profile_of(id)
	if profile_id.is_empty():
		return null
	var dir := _ride_dir(profile_id, id)
	var ride := _read_meta(dir.path_join(META_FILE))
	if ride == null:
		return null
	var samples := _read_samples_file(dir.path_join(SAMPLES_FILE))
	ride.samples = samples if samples != null else SampleStream.new()
	if samples != null and ride.samples.speed_source.is_empty():
		ride.samples.speed_source = ride.speed_source()
	return ride


func list(profile_id: String) -> Array[RideSummary]:
	var out: Array[RideSummary] = []
	for s in _index(profile_id):
		out.append(RideSummary.from_dict(s.to_dict()))
	return out


func delete(id: String) -> bool:
	var profile_id := _profile_of(id)
	if profile_id.is_empty():
		return false
	var dir := _ride_dir(profile_id, id)
	var existed: bool = DirAccess.dir_exists_absolute(dir)
	_remove_tree(dir)
	_locations.erase(id)
	var removed: bool = _index_remove(profile_id, id)
	rides_changed.emit(profile_id)
	return existed or removed


func update_upload_status(id: String, status: Dictionary) -> bool:
	var profile_id := _profile_of(id)
	if profile_id.is_empty():
		return false
	var ride := _read_meta(_ride_dir(profile_id, id).path_join(META_FILE))
	if ride == null:
		return false
	if status.has("strava_status") and not Ride.UPLOAD_STATUSES.has(str(status["strava_status"])):
		push_warning("FileRideRepository.update_upload_status: неизвестный статус '%s'" % str(status["strava_status"]))
		return false
	for key in status.keys():
		ride.upload[key] = status[key]
	return save_meta(ride)


func delete_profile_rides(profile_id: String) -> int:
	if profile_id.is_empty():
		return 0
	var count: int = _index(profile_id).size()
	for s in _index(profile_id):
		_locations.erase(s.ride_id)
	_remove_tree(_profile_dir(profile_id))
	_index_cache.erase(profile_id)
	rides_changed.emit(profile_id)
	return count


func recover_in_progress(profile_id: String) -> Array[Ride]:
	var out: Array[Ride] = []
	for s in _index(profile_id).duplicate():
		if not s.in_progress:
			continue
		var ride := get_ride(s.ride_id)
		if ride == null:
			continue
		ride.metadata["in_progress"] = false
		ride.metadata["recovered"] = true
		ride.metadata["stopped_early"] = true
		ride.metadata["elapsed_sec"] = ride.samples.size()
		ride.metadata["sample_count"] = ride.samples.size()
		ride.metadata["distance_m"] = ride.samples.total_distance_m()
		if ride.metadata.get("speed_source", "") == "" and not ride.samples.speed_source.is_empty():
			ride.metadata["speed_source"] = ride.samples.speed_source
		ride.compute_summary()
		save(ride)
		out.append(ride)
	return out


## Перестроить индекс профиля по `meta.json` заездов (после повреждения или вручную).
func rebuild_index(profile_id: String) -> Array[RideSummary]:
	var entries: Array[RideSummary] = []
	var pdir := _profile_dir(profile_id)
	var d := DirAccess.open(pdir)
	if d != null:
		for sub in d.get_directories():
			var ride := _read_meta(pdir.path_join(sub).path_join(META_FILE))
			if ride == null:
				continue
			ride.id = sub if ride.id.is_empty() else ride.id
			ride.sync_summary_header()
			entries.append(ride.summary)
			_locations[ride.id] = profile_id
	_sort_index(entries)
	_index_cache[profile_id] = entries
	_write_index(profile_id, entries)
	return entries


# ---------------------------------------------------------------------------
# Пути
# ---------------------------------------------------------------------------

func _abs(path: String) -> String:
	return ProjectSettings.globalize_path(path)


func _profile_dir(profile_id: String) -> String:
	return _abs(_dir).path_join(profile_id)


func _ride_dir(profile_id: String, id: String) -> String:
	return _profile_dir(profile_id).path_join(id)


func _ensure_dir(abs_dir: String) -> bool:
	var err := DirAccess.make_dir_recursive_absolute(abs_dir)
	if err != OK and err != ERR_ALREADY_EXISTS:
		push_error("FileRideRepository: не удалось создать каталог %s (%s)" % [abs_dir, error_string(err)])
		return false
	return true


## Профиль заезда: кэш расположений, иначе индексы профилей, иначе обход каталогов.
func _profile_of(id: String) -> String:
	if id.is_empty():
		return ""
	if _locations.has(id):
		return str(_locations[id])
	var root := DirAccess.open(_abs(_dir))
	if root == null:
		return ""
	for profile_id in root.get_directories():
		if DirAccess.dir_exists_absolute(_ride_dir(profile_id, id)):
			_locations[id] = profile_id
			return profile_id
	return ""


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
# meta.json
# ---------------------------------------------------------------------------

func _write_meta(ride: Ride) -> bool:
	var dir := _ride_dir(ride.profile_id, ride.id)
	if not _write_text_atomic(dir.path_join(META_FILE), JSON.stringify(ride.to_meta_dict(), "\t")):
		return false
	# Полные метаданные записаны — промежуточная копия больше не нужна.
	var progress := dir.path_join(PROGRESS_FILE)
	if FileAccess.file_exists(progress):
		DirAccess.remove_absolute(progress)
	return true


## `meta.json`, а для незавершённого заезда — более свежая целая копия `meta.progress.json`.
func _read_meta(path: String) -> Ride:
	if not FileAccess.file_exists(path):
		return null
	var data := _parse_json_file(path)
	if data.is_empty():
		push_warning("FileRideRepository: повреждён %s" % path)
		return null
	if _bool_of(data.get("metadata", {}), "in_progress"):
		var progress := _parse_json_file(path.get_base_dir().path_join(PROGRESS_FILE))
		if not progress.is_empty() and str(progress.get("id", "")) == str(data.get("id", "")) \
				and _bool_of(progress.get("metadata", {}), "in_progress") and _not_older(progress, data):
			data = progress
	return Ride.from_meta_dict(data)


## Словарь из JSON-файла или {} (нет файла, оборванная запись, не объект).
static func _parse_json_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK or not (json.data is Dictionary):
		return {}
	return json.data


static func _bool_of(meta: Variant, key: String) -> bool:
	return meta is Dictionary and bool((meta as Dictionary).get(key, false))


## Копия `a` не старше `b`: событий не меньше и сессионное время не меньше.
static func _not_older(a: Dictionary, b: Dictionary) -> bool:
	var ma: Dictionary = a.get("metadata", {}) if a.get("metadata") is Dictionary else {}
	var mb: Dictionary = b.get("metadata", {}) if b.get("metadata") is Dictionary else {}
	var events_a: int = (a.get("events") as Array).size() if a.get("events") is Array else 0
	var events_b: int = (b.get("events") as Array).size() if b.get("events") is Array else 0
	return events_a >= events_b and float(ma.get("elapsed_sec", 0)) >= float(mb.get("elapsed_sec", 0))


## Запись на место без усечения и переименования (дёшево на нагруженном диске): файл не
## укорачивается — хвост прежнего содержимого затирается пробелами (JSON их допускает).
static func _write_in_place(path: String, bytes: PackedByteArray) -> bool:
	var exists := FileAccess.file_exists(path)
	var file := FileAccess.open(path, FileAccess.READ_WRITE if exists else FileAccess.WRITE)
	if file == null:
		push_error("FileRideRepository: не удалось записать %s (%s)" % [path, error_string(FileAccess.get_open_error())])
		return false
	var old_length: int = file.get_length()
	file.seek(0)
	var ok := file.store_buffer(bytes)
	if ok and old_length > bytes.size():
		var pad := PackedByteArray()
		pad.resize(old_length - bytes.size())
		pad.fill(0x20)
		ok = file.store_buffer(pad)
	file.close()
	if not ok:
		push_error("FileRideRepository: не удалось записать %s" % path)
	return ok


## Временный файл → проверка ошибки записи → rename (см. `AtomicFile`).
static func _write_text_atomic(path: String, text: String) -> bool:
	return AtomicFile.write_text(path, text) == OK


# ---------------------------------------------------------------------------
# index.json
# ---------------------------------------------------------------------------

func _index(profile_id: String) -> Array[RideSummary]:
	if _index_cache.has(profile_id):
		return _index_cache[profile_id]
	var path := _profile_dir(profile_id).path_join(INDEX_FILE)
	if not FileAccess.file_exists(path):
		var entries: Array[RideSummary] = []
		if DirAccess.dir_exists_absolute(_profile_dir(profile_id)):
			entries = rebuild_index(profile_id)
		else:
			_index_cache[profile_id] = entries
		return entries
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK or not (json.data is Dictionary) \
			or not ((json.data as Dictionary).get("rides") is Array):
		push_warning("FileRideRepository: повреждён %s, перестраиваю индекс" % path)
		return rebuild_index(profile_id)
	var entries: Array[RideSummary] = []
	for item in (json.data as Dictionary)["rides"]:
		if item is Dictionary:
			var s := RideSummary.from_dict(item)
			if not s.ride_id.is_empty():
				s.profile_id = profile_id
				entries.append(s)
				_locations[s.ride_id] = profile_id
	_sort_index(entries)
	_index_cache[profile_id] = entries
	return entries


## Обновить строку индекса; `persist = false` — только в памяти (периодический сброс).
func _index_put(ride: Ride, persist: bool = true) -> void:
	var entries := _index(ride.profile_id)
	ride.sync_summary_header()
	var copy := RideSummary.from_dict(ride.summary.to_dict())
	var replaced: bool = false
	for i in entries.size():
		if entries[i].ride_id == ride.id:
			entries[i] = copy
			replaced = true
			break
	if not replaced:
		entries.append(copy)
	_sort_index(entries)
	if persist:
		_write_index(ride.profile_id, entries)


func _index_remove(profile_id: String, id: String) -> bool:
	var entries := _index(profile_id)
	for i in entries.size():
		if entries[i].ride_id == id:
			entries.remove_at(i)
			_write_index(profile_id, entries)
			return true
	return false


static func _sort_index(entries: Array[RideSummary]) -> void:
	entries.sort_custom(func(a: RideSummary, b: RideSummary) -> bool:
		if a.started_at_unix != b.started_at_unix:
			return a.started_at_unix > b.started_at_unix
		return a.ride_id > b.ride_id)


func _write_index(profile_id: String, entries: Array[RideSummary]) -> bool:
	if not _ensure_dir(_profile_dir(profile_id)):
		return false
	var items: Array = []
	for s in entries:
		items.append(s.to_dict())
	var data := {"schema": INDEX_SCHEMA_VERSION, "profile_id": profile_id, "rides": items}
	return _write_text_atomic(_profile_dir(profile_id).path_join(INDEX_FILE), JSON.stringify(data))


# ---------------------------------------------------------------------------
# samples.bin
# ---------------------------------------------------------------------------

static func _speed_source_code(source: String) -> int:
	match source:
		SampleStream.SPEED_SOURCE_TRAINER:
			return 1
		SampleStream.SPEED_SOURCE_MODEL:
			return 2
	return 0


static func _speed_source_name(code: int) -> String:
	match code:
		1:
			return SampleStream.SPEED_SOURCE_TRAINER
		2:
			return SampleStream.SPEED_SOURCE_MODEL
	return ""


static func _encode_header(source: String) -> PackedByteArray:
	var buf := StreamPeerBuffer.new()
	buf.put_u32(SAMPLES_MAGIC)
	buf.put_u16(SAMPLES_VERSION)
	buf.put_u16(SAMPLES_RECORD_SIZE)
	buf.put_u8(_speed_source_code(source))
	for i in SAMPLES_HEADER_SIZE - 9:
		buf.put_u8(0)
	return buf.data_array


static func _encode_records(s: SampleStream, from_index: int, to_index: int) -> PackedByteArray:
	var buf := StreamPeerBuffer.new()
	for i in range(from_index, to_index):
		buf.put_32(s.time_sec[i])
		buf.put_32(s.power_w[i])
		buf.put_32(s.target_w[i])
		buf.put_32(s.step_index[i])
		buf.put_float(s.speed_kmh[i])
		buf.put_float(s.distance_m[i])
		buf.put_16(s.cadence_rpm[i])
		buf.put_16(s.heart_rate_bpm[i])
		buf.put_16(s.power_age_sec[i])
		buf.put_16(s.cadence_age_sec[i])
		buf.put_16(s.heart_rate_age_sec[i])
		var flags: int = 0
		if s.has_power[i]:
			flags |= FLAG_POWER
		if s.has_cadence[i]:
			flags |= FLAG_CADENCE
		if s.has_speed[i]:
			flags |= FLAG_SPEED
		if s.has_heart_rate[i]:
			flags |= FLAG_HEART_RATE
		if s.erg_enabled[i]:
			flags |= FLAG_ERG
		buf.put_u8(flags)
		buf.put_u8(0)
	return buf.data_array


## Полная перезапись потока: временный файл и rename, прежний `samples.bin` при сбое цел.
static func _write_samples_file(path: String, samples: SampleStream) -> bool:
	var bytes := _encode_header(samples.speed_source)
	bytes.append_array(_encode_records(samples, 0, samples.size()))
	return AtomicFile.write_bytes(path, bytes) == OK


## Число целых записей в файле; -1 — файла нет или заголовок повреждён.
static func _count_records(path: String) -> int:
	if not FileAccess.file_exists(path):
		return -1
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return -1
	var ok: bool = _check_header(file)
	var length: int = file.get_length()
	file.close()
	if not ok:
		return -1
	return int((length - SAMPLES_HEADER_SIZE) / SAMPLES_RECORD_SIZE)


## Проверяет заголовок открытого файла; курсор остаётся после заголовка.
static func _check_header(file: FileAccess) -> bool:
	if file.get_length() < SAMPLES_HEADER_SIZE:
		return false
	file.seek(0)
	if file.get_32() != SAMPLES_MAGIC:
		return false
	if file.get_16() != SAMPLES_VERSION:
		return false
	if file.get_16() != SAMPLES_RECORD_SIZE:
		return false
	file.seek(SAMPLES_HEADER_SIZE)
	return true


## Поток из файла; null — файла нет или заголовок повреждён. Усечённый хвост отбрасывается.
static func _read_samples_file(path: String) -> SampleStream:
	if not FileAccess.file_exists(path):
		return null
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	if not _check_header(file):
		push_warning("FileRideRepository: повреждён %s" % path)
		file.close()
		return null
	file.seek(8)
	var source_code: int = file.get_8()
	var n: int = int((file.get_length() - SAMPLES_HEADER_SIZE) / SAMPLES_RECORD_SIZE)
	file.seek(SAMPLES_HEADER_SIZE)
	var buf := StreamPeerBuffer.new()
	buf.data_array = file.get_buffer(n * SAMPLES_RECORD_SIZE)
	file.close()
	var s := SampleStream.new()
	s.speed_source = _speed_source_name(source_code)
	for i in n:
		s.time_sec.append(buf.get_32())
		s.power_w.append(buf.get_32())
		s.target_w.append(buf.get_32())
		s.step_index.append(buf.get_32())
		s.speed_kmh.append(buf.get_float())
		s.distance_m.append(buf.get_float())
		s.cadence_rpm.append(buf.get_16())
		s.heart_rate_bpm.append(buf.get_16())
		s.power_age_sec.append(buf.get_16())
		s.cadence_age_sec.append(buf.get_16())
		s.heart_rate_age_sec.append(buf.get_16())
		var flags: int = buf.get_u8()
		buf.get_u8()
		s.has_power.append((flags & FLAG_POWER) != 0)
		s.has_cadence.append((flags & FLAG_CADENCE) != 0)
		s.has_speed.append((flags & FLAG_SPEED) != 0)
		s.has_heart_rate.append((flags & FLAG_HEART_RATE) != 0)
		s.erg_enabled.append((flags & FLAG_ERG) != 0)
	return s
