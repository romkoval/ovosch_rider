class_name RideRecorder
extends RefCounted
## Потоковая запись заезда на диск во время тренировки (REQ-LOC-07).
##
## Подключается к `WorkoutSession` до старта (при переходе в RUNNING создаёт
## заезд `Ride.from_session` с `metadata.in_progress = true` и сохраняет его)
## или к уже идущей сессии — тогда заезд создаётся сразу с накопленными сэмплами.
## Каждые `FLUSH_INTERVAL_SEC` секунд сессионного времени (по `second_elapsed`
## исполнителя — на паузе время не идёт) дозаписывает новые сэмплы в поток
## (`RideRepository.append_samples`) и записывает метаданные с событиями дешёвым способом
## (`save_progress` — без переименования файлов, см. `FileRideRepository`): на диске всегда
## состояние не старше 10 с (крит. 1, 2), а сброс укладывается в бюджет тика (крит. 4).
## Событие паузы сбрасывает метаданные сразу (по `event_logged`, т.к. сессия
## пишет его в журнал после смены состояния) — пауза не теряется при сбое.
## При FINISHED — финальная запись: сводка, `in_progress = false` (`save`).
##
## Запись маленькими порциями, без сериализации всего заезда (крит. 4:
## тик ≤ 50 мс при 600 накопленных сэмплах; `last_flush_ms` — замер последнего сброса).
## Часы — только сессионные (тики), системное время не используется: тесты
## детерминированы.
##
## Подписки — связанными методами, поэтому сессия держит записывающий через
## Callable: после FINISHED подписки снимаются сами, при отказе от записи до
## конца — `dispose()` (иначе цикл сессия → сигнал → recorder → сессия).

const FLUSH_INTERVAL_SEC: int = 10

## Выполнен сброс на диск (`elapsed_sec` — сессионное время).
signal flushed(elapsed_sec: int)

var repository: RideRepository
var profile: Profile
var session: WorkoutSession
var ride: Ride = null
## Число сброшенных на диск сэмплов.
var flushed_samples: int = 0
## Длительность последнего сброса, мс (для контроля бюджета LOC-07 крит. 4).
var last_flush_ms: int = 0
var flush_count: int = 0
var _finished: bool = false


func _init(repo: RideRepository, rider_profile: Profile, workout_session: WorkoutSession) -> void:
	repository = repo
	profile = rider_profile
	session = workout_session
	session.state_changed.connect(_on_state_changed)
	session.event_logged.connect(_on_event_logged)
	session.executor.second_elapsed.connect(_on_second_elapsed)
	if session.get_state() in [WorkoutSession.State.RUNNING, WorkoutSession.State.PAUSED]:
		_begin()


## Отписаться от сессии (цикл ссылок разрывается; на диск ничего не пишется).
func dispose() -> void:
	if session == null:
		return
	if session.state_changed.is_connected(_on_state_changed):
		session.state_changed.disconnect(_on_state_changed)
	if session.event_logged.is_connected(_on_event_logged):
		session.event_logged.disconnect(_on_event_logged)
	if session.executor.second_elapsed.is_connected(_on_second_elapsed):
		session.executor.second_elapsed.disconnect(_on_second_elapsed)


## Идентификатор записываемого заезда ("" до старта).
func ride_id() -> String:
	return ride.id if ride != null else ""


func is_recording() -> bool:
	return ride != null and not _finished


## Принудительный сброс (например, перед выходом из приложения).
func flush() -> void:
	if ride == null or _finished:
		return
	var t0: int = Time.get_ticks_msec()
	var total: int = session.samples.size()
	if total > flushed_samples:
		if repository.append_samples(ride.id, session.samples, flushed_samples):
			flushed_samples = total
	ride.refresh_from_session(session)
	ride.metadata["in_progress"] = true
	repository.save_progress(ride)
	last_flush_ms = Time.get_ticks_msec() - t0
	flush_count += 1
	flushed.emit(session.executor.elapsed_sec())


func _on_state_changed(state: int) -> void:
	match state:
		WorkoutSession.State.RUNNING:
			if ride == null:
				_begin()
		WorkoutSession.State.FINISHED:
			_finish()


func _on_event_logged(event: Dictionary) -> void:
	if ride == null or _finished:
		return
	if str(event.get("type", "")) == WorkoutSession.EVENT_PAUSE:
		ride.refresh_from_session(session)
		ride.metadata["in_progress"] = true
		repository.save_meta(ride)


func _begin() -> void:
	ride = Ride.from_session(session, profile)
	ride.metadata["in_progress"] = true
	ride.sync_summary_header()
	repository.save(ride)
	flushed_samples = session.samples.size()


func _on_second_elapsed(elapsed_sec: int, _step_offset_sec: int, _remaining_sec: int) -> void:
	if ride == null or _finished:
		return
	if elapsed_sec > 0 and elapsed_sec % FLUSH_INTERVAL_SEC == 0:
		flush()


func _finish() -> void:
	if ride == null or _finished:
		return
	_finished = true
	var t0: int = Time.get_ticks_msec()
	ride.refresh_from_session(session)
	ride.metadata["in_progress"] = false
	ride.metadata["recovered"] = false
	ride.compute_summary()
	repository.save(ride)
	flushed_samples = session.samples.size()
	last_flush_ms = Time.get_ticks_msec() - t0
	flush_count += 1
	flushed.emit(session.executor.elapsed_sec())
	dispose()
