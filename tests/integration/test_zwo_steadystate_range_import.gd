extends GutTest
## T-149: путь пользователя — импорт экспорта Intervals.icu `.zwo` с `SteadyState` PowerLow/PowerHigh
## через экран плана (`PlanScreen.import_path` → `WorkoutLibrary.import_file`): план появляется
## в библиотеке и выбирается (REQ-IMP-01 п.1, REQ-IMP-03 п.1, REQ-IMP-04 п.1, регрессия REQ-IMP-05 п.2).

const SCENE: String = "res://src/ui/plan/plan_screen.tscn"
const WORKOUT_FIXTURES: String = "res://tests/fixtures/workouts/"
const TODAY: String = "2026-10-04"

var _dir: String
var _repo: ProfileRepository
var _state: AppState
var _library: WorkoutLibrary
var _profile: Profile


func before_each() -> void:
	_dir = "user://test_t149_%d_%d/" % [Time.get_ticks_usec(), randi() % 100000]
	_repo = ProfileRepository.new(_dir + "profiles/")
	_profile = _repo.create("Rider")
	_profile.ftp_w = 200
	_repo.save(_profile)
	_state = AppState.new(_repo)
	_state.start()
	_library = WorkoutLibrary.new(_dir + "workouts/")
	TranslationServer.set_locale("en")


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


func _screen() -> PlanScreen:
	var s: PlanScreen = load(SCENE).instantiate()
	s.today = TODAY
	s.setup(_state, _repo, MemorySecureStore.new(), MockHttpTransport.new(), PlanCache.new(_dir + "plans/"), _library)
	add_child_autofree(s)
	return s


func test_plan_screen_imports_intervals_icu_zwo_with_ranges() -> void:
	var s := _screen()
	var r := s.import_path(WORKOUT_FIXTURES + "intervals_icu_3x6.zwo")
	assert_not_null(r)
	if r == null:
		return
	assert_true(r.ok(), "T-149: .zwo экспорта Intervals.icu импортируется: " + str(r.error_messages()))
	assert_eq(s.import_error_text(), "", "окна ошибки нет")
	assert_eq(_library.count(_profile.id), 1, "план в библиотеке профиля")
	var entries := _library.list(_profile.id)
	if entries.size() == 1:
		assert_eq(str(entries[0]["name"]), "Активация: 3x6 мин на гоночной мощности")
		assert_eq(int(entries[0]["duration_sec"]), 3900)
		var stored := _library.get_workout(_profile.id, str(entries[0]["id"]))
		assert_not_null(stored)
		if stored != null:
			assert_eq(stored.steps.size(), 9)
			assert_eq(stored.power_points(200), r.workout.power_points(200), "из библиотеки — тот же план")
	assert_eq(s.library_items().size(), 1, "карточка плана в списке")
	assert_not_null(s.selected_workout(), "импортированный план выбран")
	if s.selected_workout() != null:
		assert_eq(s.selected_workout().name, "Активация: 3x6 мин на гоночной мощности")
		# 0.90…0.96 → 93 % от FTP 200 = 186 Вт на первом рабочем отрезке (900 с + 1 с).
		assert_eq(s.selected_workout().target_watts_at(901.0, 200), 186)


func test_plan_screen_imports_mrc_of_same_plan_with_same_duration() -> void:
	var s := _screen()
	var z := s.import_path(WORKOUT_FIXTURES + "intervals_icu_3x6.zwo")
	var m := s.import_path(WORKOUT_FIXTURES + "intervals_icu_3x6.mrc")
	assert_true(z != null and z.ok())
	assert_true(m != null and m.ok())
	assert_eq(_library.count(_profile.id), 2, "две записи: .zwo и .mrc")
	if z != null and m != null and z.ok() and m.ok():
		assert_eq(z.workout.total_duration_sec(), m.workout.total_duration_sec())
	# Повторная пересборка списка освобождает старые карточки через queue_free — дать кадр.
	await get_tree().process_frame
