extends GutTest
## Повторная приёмка T-099 (tester, независимо от `test_intervals_icu_repeat_blocks.gd`):
## REQ-HUD-13 крит. 8 для планов Intervals.icu на пути приложения и на границах:
## - план из события Intervals.icu проходит кэш плана (`PlanCache`, JSON на диске) и экран
##   тренировки (`WorkoutScreen` → `IntervalList.model`): до блока 2 + 1 строк, с первой
##   секунды блока 2 + 8, текущая — первый шаг блока; на последней секунде разминки ещё 3;
## - строка свёрнутого блока — **цвета зоны рабочего отрезка**, в том числе когда блок
##   начинается с отдыха (`4x` (1 мин 125 Вт, 2 мин 300 Вт) → зона 300 Вт);
## - пропуск шага внутри блока до его начала раскрывает блок;
## - регрессия REQ-INT-03 крит. 5 (плоская последовательность, повторы × шаги) и крит. 8
##   (сумма длительностей) на плане с блоком.

const WORKOUT_SCENE: String = "res://src/ui/workout/workout_screen.tscn"
const FTP: int = 200
## 2 шага разминки + 4 × (15 с 160 %, 45 с 62.5 %) — пример HUD-13 крит. 8.
const TEXT_PLAN: String = "Warmup\n- 1m 50%\n- 1m 60%\n\n4x\n- 15s 160%\n- 45s 62.5%\n"
## Блок, начинающийся с отдыха: рабочий отрезок (300 Вт) — второй шаг повтора.
const REST_FIRST_PLAN: String = "- 5m 100w\n\n4x\n- 1m 125w\n- 2m 300w\n\n- 5m 100w\n"

var _dir: String = ""
var _now_usec: int = 0
var _trainer: FakeTrainer


func before_each() -> void:
	_dir = "user://test_intervals_repeat_reaccept_%d_%d/" % [Time.get_ticks_usec(), randi() % 1000000]
	_now_usec = 1_000_000
	_trainer = FakeTrainer.new(11)
	_trainer.connect_delay_sec = 0.0
	_trainer.power_noise_w = 0.0
	_trainer.power_tau_sec = 0.01
	_trainer.cadence_noise_rpm = 0.0
	_trainer.connect_device("t099-reaccept")


func after_each() -> void:
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


func _clock() -> int:
	return _now_usec


func _keep(_on: bool) -> void:
	pass


func _parse(text: String, duration: int = 0) -> Workout:
	var event := {"id": 77, "name": "rep", "description": text}
	if duration > 0:
		event["moving_time"] = duration
	var r := IntervalsIcuWorkoutParser.parse(event)
	assert_true(r.ok(), "план разбирается: %s" % str(r.errors))
	return r.workout


## План Intervals.icu через кэш плана на диске (как при запуске без сети).
func _through_cache(w: Workout) -> Workout:
	var cache := PlanCache.new(_dir + "plans/")
	assert_true(cache.save("p1", "2026-10-02", [{"event_id": "77", "name": "rep", "workout": w}]))
	var again := PlanCache.new(_dir + "plans/")
	var loaded := again.get_today("p1", "2026-10-02")
	assert_false(loaded.is_empty(), "кэш прочитан")
	return (loaded["workouts"] as Array)[0]["workout"]


func test_req_hud_13_c8_intervals_plan_through_cache_and_workout_screen() -> void:
	var plan := _through_cache(_parse(TEXT_PLAN))
	assert_eq(plan.repeat_blocks, [{"first": 2, "last": 9, "period": 2, "count": 4}] as Array[Dictionary],
			"блок повторов пережил кэш")
	var profile := Profile.create("Rider")
	profile.ftp_w = FTP
	var s: WorkoutScreen = load(WORKOUT_SCENE).instantiate()
	s.clock_usec = _clock
	s.keep_awake_setter = _keep
	add_child_autofree(s)
	s.setup(plan, profile, _trainer, AppState.new(ProfileRepository.new(_dir + "profiles/")))
	assert_true(s.start())
	var model := s.interval_list().model
	assert_not_null(model, "у списка HUD есть модель")
	assert_eq(model.row_count(), 3, "до начала блока — 3 строки")
	assert_eq(str(model.rows()[2]["kind"]), IntervalListModel.KIND_REPEAT, "третья строка — свёрнутый блок")
	assert_eq(int(model.rows()[2]["repeat_count"]), 4)
	for i in 119:
		_now_usec += 1_000_000
		s.ticker().poll()
	model = s.interval_list().model
	assert_eq(model.row_count(), 3, "последняя секунда разминки — блок свёрнут")
	_now_usec += 1_000_000
	s.ticker().poll()
	model = s.interval_list().model
	assert_eq(model.row_count(), 2 + 8, "с начала блока — 2 + 8")
	assert_eq(model.current_row(), 2, "текущая — первый шаг блока")
	assert_eq(str(model.rows()[2]["status"]), IntervalListModel.STATUS_CURRENT)


func test_req_hud_13_c8_collapsed_row_colour_is_work_zone_when_block_starts_with_rest() -> void:
	var w := _parse(REST_FIRST_PLAN)
	assert_eq(w.repeat_blocks, [Workout.repeat_block(1, 2, 4)] as Array[Dictionary], "предусловие: блок найден")
	var m := IntervalListModel.new(w, FTP)
	assert_eq(m.row_count(), 3, "до блока: шаг, свёрнутый блок, шаг")
	var row: Dictionary = m.rows()[1]
	assert_eq(str(row["kind"]), IntervalListModel.KIND_REPEAT)
	var work_zone := PowerZones.coggan(FTP).zone_of(300)
	var rest_zone := PowerZones.coggan(FTP).zone_of(125)
	assert_ne(work_zone, rest_zone, "предусловие: зоны отдыха и работы разные")
	assert_eq(str(row["color_token"]), ZonePalette.power_token(work_zone),
			"цвет свёрнутой строки — зона рабочего отрезка (300 Вт), а не первого шага блока (125 Вт)")


func test_req_hud_13_c8_collapsed_row_colour_is_work_zone_for_on_off_block() -> void:
	var m := IntervalListModel.new(_parse(TEXT_PLAN), FTP)
	assert_eq(str(m.rows()[2]["color_token"]), ZonePalette.power_token(PowerZones.coggan(FTP).zone_of(320)),
			"блок ON/OFF — цвет зоны 320 Вт")


func test_req_hud_13_c8_skip_into_block_expands_it() -> void:
	var w := _parse(TEXT_PLAN)
	var session := WorkoutSession.new(w, _trainer, FTP)
	session.start()
	var m := IntervalListModel.for_session(session)
	assert_eq(m.row_count(), 3)
	session.tick(1.0)
	session.skip_step()
	session.tick(1.0)
	session.skip_step()
	session.tick(1.0)
	m.sync(session)
	assert_eq(m.row_count(), 2 + 8, "после пропуска разминки — блок раскрыт")
	assert_eq(m.current_row(), 2)


func test_req_int_03_c5_c8_regression_flat_steps_and_total_duration() -> void:
	var w := _parse(TEXT_PLAN, 120 + 4 * 60)
	assert_eq(w.steps.size(), 2 + 4 * 2, "повторы × шаги блока")
	assert_eq(w.total_duration_sec(), 120 + 4 * 60, "сумма длительностей")
	for k in range(2, 10, 2):
		assert_eq(w.steps[k].duration_sec, 15)
		assert_eq(w.steps[k + 1].duration_sec, 45)
	var r := IntervalsIcuWorkoutParser.parse({"id": 1, "name": "x", "description": TEXT_PLAN, "moving_time": 120 + 4 * 60})
	assert_eq(r.warnings.filter(func(e: Dictionary) -> bool: return str(e.get("key", "")) == "duration_mismatch").size(), 0,
			"заявленная длительность совпала — предупреждения нет")
