extends GutTest
## Повторная приёмка T-098 (tester, независимо от `test_plan_last_workout.gd` исполнителя):
## REQ-UIX-03 крит. 3 — выбор тренировки запоминается между запусками (`last_workout_id`, У-14).
## (а) список A, B, C → выбрать B → перезапуск **приложения целиком** (новый `main.tscn` на том же
##     каталоге данных) → на экране выбора тренировки «выбрано» ровно у B; переходы
##     план → главный → план выбор не сбрасывают;
## (б) сохранённой тренировки нет в списке: событие Intervals.icu **другого дня** и событие,
##     **удалённое из календаря** того же дня — экран без ошибки, предвыбор по REQ-INT-04 крит. 1
##     (одна тренировка на сегодня — она; несколько — ничего);
## (в) профиль, сохранённый без поля, — как (б) (в т.ч. при одной тренировке на сегодня);
## (г) профили A и B видят **одно и то же** событие Intervals.icu (один id): выбор в A не
##     даёт предвыбора в B и не пишет поле B (у исполнителя id списков A и B не пересекались).

const MAIN_SCENE: String = "res://src/app/main.tscn"
const PLAN_SCENE: String = "res://src/ui/plan/plan_screen.tscn"
const ACC_FULL: String = "res://tests/fixtures/workouts_acceptance/acc_full.zwo"
const SIMPLE: String = "res://tests/fixtures/workouts/simple.zwo"
const SWEET_SPOT: String = "res://tests/fixtures/workouts/sweet_spot_text.mrc"
const EVENTS: String = "res://tests/fixtures/intervals/events_today.json"
const TODAY: String = "2026-10-02"
const TOMORROW: String = "2026-10-03"
const KEY: String = "plan-last-workout-reaccept-0001"

var _dir: String = ""


func before_each() -> void:
	_dir = "user://test_plan_last_workout_reaccept_%d_%d/" % [Time.get_ticks_usec(), randi() % 1000000]


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


# --- (а) перезапуск приложения ----------------------------------------------------------------

func _main() -> AppMain:
	var main: AppMain = load(MAIN_SCENE).instantiate()
	main.data_dir = _dir
	main.trainer_kind = TrainerFactory.KIND_FAKE
	main.transport = MockHttpTransport.new()
	main.env_reader = Callable()
	add_child(main)
	return main


func _selected_names(plan: PlanScreen) -> Array[String]:
	var out: Array[String] = []
	for i in plan.cards().size():
		if plan.selected_cards().has(plan.cards()[i]):
			out.append(str(plan.items()[i]["name"]))
	return out


func test_req_uix_03_c3_a_choice_survives_full_app_restart() -> void:
	var repo := ProfileRepository.new(_dir + "profiles/")
	repo.create("Даша")
	var main := _main()
	assert_true(main.app_state.select_profile(main.repo.list()[0].id))
	assert_true(main.app_state.navigate(AppState.Screen.PLAN))
	var plan := main.plan_screen()
	for f in [ACC_FULL, SIMPLE, SWEET_SPOT]:
		var r: ParseResult = plan.import_path(ProjectSettings.globalize_path(f))
		assert_true(r != null and r.ok(), "импорт %s" % f.get_file())
	assert_eq(plan.items().size(), 3, "список A, B, C")
	var b_name := str(plan.items()[1]["name"])
	plan.cards()[1].pressed.emit()
	await wait_process_frames(2)
	assert_eq(_selected_names(plan), [b_name] as Array[String], "выбрана B")
	# Переходы внутри запуска выбор не сбрасывают.
	main.app_state.navigate(AppState.Screen.HOME)
	await wait_process_frames(2)
	main.app_state.navigate(AppState.Screen.PLAN)
	await wait_process_frames(2)
	assert_eq(_selected_names(plan), [b_name] as Array[String], "план → главный → план: по-прежнему B")
	main.queue_free()
	await wait_process_frames(2)
	# Перезапуск: новое приложение на том же каталоге.
	var again := _main()
	assert_true(again.app_state.select_profile(again.repo.list()[0].id))
	assert_true(again.app_state.navigate(AppState.Screen.PLAN))
	await wait_process_frames(2)
	var plan2 := again.plan_screen()
	assert_eq(plan2.items().size(), 3)
	assert_eq(_selected_names(plan2), [b_name] as Array[String], "(а) после перезапуска «выбрано» ровно у B")
	assert_false((plan2.get_node("%StartButton") as Button).disabled, "запуск B доступен одним действием")
	again.queue_free()
	await wait_process_frames(2)


# --- (б), (в), (г): экран плана с Intervals.icu --------------------------------------------------

var _repo: ProfileRepository
var _state: AppState
var _store: MemorySecureStore
var _mock: MockHttpTransport
var _cache: PlanCache
var _library: WorkoutLibrary


func _restart() -> void:
	_repo = ProfileRepository.new(_dir + "profiles/")
	_state = AppState.new(_repo)
	_state.start()
	_cache = PlanCache.new(_dir + "plans/")
	_library = WorkoutLibrary.new(_dir + "workouts/")


func _setup_profiles(names: Array[String]) -> Array[Profile]:
	_repo = ProfileRepository.new(_dir + "profiles/")
	_store = MemorySecureStore.new()
	_mock = MockHttpTransport.new()
	var out: Array[Profile] = []
	for n in names:
		var p := _repo.create(n)
		p.intervals_athlete_id = "i4242"
		_repo.save(p)
		var client := IntervalsIcuClient.for_profile(_mock, _store, p)
		_store.set_secret(client.secret_key(), KEY)
		out.append(p)
	_restart()
	_state.select_profile(out[0].id)
	return out


func _screen(day: String) -> PlanScreen:
	var s: PlanScreen = load(PLAN_SCENE).instantiate()
	s.today = day
	s.setup(_state, _repo, _store, _mock, _cache, _library)
	add_child_autofree(s)
	return s


## Велотренировки фикстуры с данными id (дата — `day`): 2001 (Ride, workout_doc), 2002
## (VirtualRide, текст) и 2006 — копия 2002 под другим id и названием (третья велотренировка дня;
## 2004 в фикстуре — бег, экран его не показывает).
func _events(ids: Array[int], day: String) -> Array:
	var json := JSON.new()
	assert_eq(json.parse(FileAccess.get_file_as_string(EVENTS)), OK)
	var by_id: Dictionary = {}
	for e: Dictionary in json.data:
		by_id[int(e["id"])] = e
	var extra: Dictionary = (by_id[2002] as Dictionary).duplicate(true)
	extra["id"] = 2006
	extra["name"] = "Endurance text 2"
	by_id[2006] = extra
	var out: Array = []
	for id in ids:
		var copy: Dictionary = (by_id[id] as Dictionary).duplicate(true)
		copy["start_date_local"] = day + "T00:00:00"
		out.append(copy)
	return out


func _load(s: PlanScreen, ids: Array[int], day: String) -> void:
	_mock.enqueue_json("GET", "/events", 200, _events(ids, day))
	var r: ApiResult = await s.load_today()
	assert_true(r.ok, "план загружен: %s" % r.message)


func _index_of_id(s: PlanScreen, id: String) -> int:
	for i in s.items().size():
		if str(s.items()[i]["id"]) == id:
			return i
	return -1


func test_req_uix_03_c3_b_intervals_event_of_another_day() -> void:
	var profiles := _setup_profiles(["A"] as Array[String])
	var s := _screen(TODAY)
	await _load(s, [2001, 2002] as Array[int], TODAY)
	var i := _index_of_id(s, "icu:2002")
	assert_gte(i, 0, "предусловие: событие 2002 в списке")
	s.cards()[i].pressed.emit()
	assert_eq(_repo.get_by_id(profiles[0].id).last_workout_id, "icu:2002", "выбор записан")
	s.queue_free()
	# Завтра: одно другое событие — предвыбор по INT-04 крит. 1.
	_restart()
	_state.select_profile(profiles[0].id)
	var s2 := _screen(TOMORROW)
	await _load(s2, [2001] as Array[int], TOMORROW)
	assert_eq(s2.remembered_index(), -1, "(б) сохранённой тренировки в списке нет")
	assert_eq(s2.selected_cards().size(), 1, "(б) единственная тренировка дня предвыбрана")
	assert_eq(str(s2.selected_item().get("id", "")), "icu:2001")
	assert_eq(_repo.get_by_id(profiles[0].id).last_workout_id, "icu:2002", "автопредвыбор профиль не переписывает")
	s2.queue_free()
	# Завтра: две тренировки — предвыбора нет (выбирает пользователь), ошибки нет. Кэш дня
	# сброшен: иначе предвыбор из кэша (одна тренировка) сохраняется как текущий выбор экрана.
	_restart()
	_cache.clear(profiles[0].id)
	_state.select_profile(profiles[0].id)
	var s3 := _screen(TOMORROW)
	await _load(s3, [2001, 2006] as Array[int], TOMORROW)
	assert_eq(s3.selected_cards().size(), 0, "(б) несколько тренировок дня — ничего не выбрано")
	assert_eq(s3.items().size(), 2)


func test_req_uix_03_c3_b_intervals_event_deleted_from_calendar_same_day() -> void:
	var profiles := _setup_profiles(["A"] as Array[String])
	var s := _screen(TODAY)
	await _load(s, [2001, 2002, 2006] as Array[int], TODAY)
	s.cards()[_index_of_id(s, "icu:2002")].pressed.emit()
	assert_eq(_repo.get_by_id(profiles[0].id).last_workout_id, "icu:2002")
	# Тот же день, тот же экран: «Обновить» — событие 2002 удалено из календаря.
	await _load(s, [2001, 2006] as Array[int], TODAY)
	assert_eq(_index_of_id(s, "icu:2002"), -1, "предусловие: события больше нет")
	assert_eq(s.selected_cards().size(), 0, "(б) удалённое событие не выбрано, несколько — без предвыбора")
	# Перезапуск в тот же день: осталось одно событие.
	s.queue_free()
	_restart()
	_state.select_profile(profiles[0].id)
	var s2 := _screen(TODAY)
	await _load(s2, [2006] as Array[int], TODAY)
	assert_eq(s2.selected_cards().size(), 1, "(б) осталась одна — предвыбрана по INT-04 крит. 1")
	assert_eq(str(s2.selected_item().get("id", "")), "icu:2006")


func test_req_uix_03_c3_c_profile_without_field_behaves_like_b() -> void:
	var profiles := _setup_profiles(["A"] as Array[String])
	var path := _dir + "profiles/" + ProfileRepository.FILE_NAME
	var json := JSON.new()
	assert_eq(json.parse(FileAccess.get_file_as_string(path)), OK)
	var data: Dictionary = json.data
	for entry: Dictionary in data["profiles"]:
		assert_true(entry.has("last_workout_id"), "предусловие: поле пишется в файл")
		entry.erase("last_workout_id")
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(data))
	f.close()
	_restart()
	assert_true(_state.select_profile(profiles[0].id), "(в) профиль без поля читается")
	var s := _screen(TODAY)
	await _load(s, [2002] as Array[int], TODAY)
	assert_eq(s.selected_cards().size(), 1, "(в) как (б): одна тренировка на сегодня предвыбрана")
	assert_eq(str(s.selected_item().get("id", "")), "icu:2002")


func test_req_uix_03_c3_d_same_event_in_two_profiles_choice_is_per_profile() -> void:
	var profiles := _setup_profiles(["A", "B"] as Array[String])
	var s := _screen(TODAY)
	await _load(s, [2001, 2002, 2006] as Array[int], TODAY)
	s.cards()[_index_of_id(s, "icu:2006")].pressed.emit()
	assert_eq(_repo.get_by_id(profiles[0].id).last_workout_id, "icu:2006", "A: выбор записан")
	# Переключение на B в том же запуске.
	_state.switch_profile()
	assert_true(_state.select_profile(profiles[1].id))
	s.refresh()
	await _load(s, [2001, 2002, 2006] as Array[int], TODAY)
	assert_gte(_index_of_id(s, "icu:2006"), 0, "предусловие: у B то же событие")
	assert_eq(s.selected_cards().size(), 0, "(г) выбор A не предвыбирает B")
	assert_eq(_repo.get_by_id(profiles[1].id).last_workout_id, "", "(г) поле B не тронуто")
	s.cards()[_index_of_id(s, "icu:2001")].pressed.emit()
	s.queue_free()
	# Перезапуск: у каждого профиля свой выбор.
	_restart()
	_state.select_profile(profiles[0].id)
	var sa := _screen(TODAY)
	await _load(sa, [2001, 2002, 2006] as Array[int], TODAY)
	assert_eq(str(sa.selected_item().get("id", "")), "icu:2006", "A после перезапуска — её выбор")
	sa.queue_free()
	_restart()
	_state.select_profile(profiles[1].id)
	var sb := _screen(TODAY)
	await _load(sb, [2001, 2002, 2006] as Array[int], TODAY)
	assert_eq(str(sb.selected_item().get("id", "")), "icu:2001", "B после перезапуска — её выбор")
