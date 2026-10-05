extends GutTest
## Приёмка T-149 (tester): ZWO `SteadyState` с диапазоном `PowerLow`/`PowerHigh` без `Power`
## (экспорт Intervals.icu) → постоянная цель = середина диапазона.
## REQ-IMP-01 п.1 (правило диапазона — Н-51, по карточке T-149), п.4, 5, 6; регрессия
## REQ-IMP-05 п.1, 2, REQ-IMP-04 п.6. Фикстура собрана независимо от фикстур разработчика:
## `tests/fixtures/workouts_acceptance/acc_range_steady.zwo`.

const ACC: String = "res://tests/fixtures/workouts_acceptance/"
const FIXTURE: String = "acc_range_steady.zwo"
const PLAN_SCENE: String = "res://src/ui/plan/plan_screen.tscn"
const TODAY: String = "2026-10-05"

var _dir: String
var _previous_locale: String
var _profile_id: String = ""


func before_each() -> void:
	_dir = "user://acc_t149_%d_%d/" % [Time.get_ticks_usec(), randi() % 1000000]
	_previous_locale = TranslationServer.get_locale()


func after_each() -> void:
	TranslationServer.set_locale(_previous_locale)
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


static func _wrap(body: String) -> String:
	return "<workout_file>\n<name>T</name>\n<workout>\n%s\n</workout>\n</workout_file>" % body


func _parse_fixture() -> ParseResult:
	return ZwoParser.parse(FileAccess.get_file_as_string(ACC + FIXTURE))


func _write_tmp(file_name: String, text: String) -> String:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_dir + "in/"))
	var path := _dir + "in/" + file_name
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()
	return path


func _plan_screen(library: WorkoutLibrary) -> PlanScreen:
	var repo := ProfileRepository.new(_dir + "profiles/")
	var profile := repo.create("Rider")
	profile.ftp_w = 300
	repo.save(profile)
	_profile_id = profile.id
	var state := AppState.new(repo)
	state.start()
	var s: PlanScreen = load(PLAN_SCENE).instantiate()
	s.today = TODAY
	s.setup(state, repo, MemorySecureStore.new(), MockHttpTransport.new(), PlanCache.new(_dir + "plans/"), library)
	add_child_autofree(s)
	return s


static func _has_cyrillic(text: String) -> bool:
	for i in text.length():
		var c := text.unicode_at(i)
		if c >= 0x0400 and c <= 0x04FF:
			return true
	return false


# ---------------------------------------------------------------------------
# REQ-IMP-01 п.1, 6 — шаги, цели, длительности
# ---------------------------------------------------------------------------

func test_req_imp_01_c1_c6_range_steady_states_become_midpoint_targets() -> void:
	var r := _parse_fixture()
	assert_true(r.ok(), "импорт без ошибок: " + str(r.error_messages()))
	assert_eq(r.warnings.size(), 0, "show_avg, <tags>, textevent duration — без предупреждений: " + str(r.warnings))
	if not r.ok():
		return
	var steps := r.workout.steps
	assert_eq(steps.size(), 6, "п.6: число шагов фикстуры")
	assert_eq(r.workout.total_duration_sec(), 1350, "п.6: суммарная длительность фикстуры")
	if steps.size() != 6:
		return
	# Warmup — рампа, как раньше.
	assert_true(steps[0].is_ramp(), "Warmup — рампа")
	assert_almost_eq(steps[0].target_start, 40.0, 0.001)
	assert_almost_eq(steps[0].target_end, 65.0, 0.001)
	# Диапазон 0.88…0.94 → 91 %; постоянная цель, не рампа; каденс сохранён.
	var expected := [
		[480, 91.0, "0.88…0.94 → 91 %"],
		[120, 50.0, "0.5…0.5 → 50 %"],
		[60, 65.0, "границы в обратном порядке 0.70/0.60 → середина 65 %"],
		[90, 80.0, "Power=0.8 главнее диапазона 0.1…0.2"],
	]
	for i in expected.size():
		var s: WorkoutStep = steps[i + 1]
		var what: String = expected[i][2]
		assert_eq(s.duration_sec, int(expected[i][0]), what + ": длительность")
		assert_eq(s.target_kind, WorkoutStep.TargetKind.PERCENT_FTP, what + ": доля FTP")
		assert_false(s.is_ramp(), what + ": постоянная цель")
		assert_almost_eq(s.target_start, float(expected[i][1]), 0.001, what)
		assert_almost_eq(s.target_end, float(expected[i][1]), 0.001, what + ": конец = начало")
	assert_eq(steps[1].cadence_rpm, 95, "Cadence у шага с диапазоном переносится (IMP-01 п.3)")
	assert_true(steps[5].is_ramp(), "Cooldown — рампа")
	assert_almost_eq(steps[5].target_start, 60.0, 0.001)
	assert_almost_eq(steps[5].target_end, 40.0, 0.001)


func test_req_imp_01_c1_targets_in_watts_follow_midpoint_at_ftp_300() -> void:
	var r := _parse_fixture()
	if not r.ok():
		fail_test(str(r.error_messages()))
		return
	# Середина шага 1 (300 + 240 с), шага 3 (300 + 480 + 120 + 30 с), шага 4.
	assert_eq(r.workout.target_watts_at(540.0, 300), 273, "91 % от 300 Вт")
	assert_eq(r.workout.target_watts_at(930.0, 300), 195, "65 % от 300 Вт")
	assert_eq(r.workout.target_watts_at(1005.0, 300), 240, "Power 80 % от 300 Вт")


func test_req_imp_01_c1_lowercase_range_attributes() -> void:
	var r := ZwoParser.parse(_wrap("<steadystate duration=\"30\" powerlow=\"0.55\" powerhigh=\"0.65\"/>"))
	assert_true(r.ok(), "атрибуты в нижнем регистре, как у остальных элементов: " + str(r.error_messages()))
	if r.ok():
		assert_almost_eq(r.workout.steps[0].target_start, 60.0, 0.001)


func test_req_imp_01_c1_invalid_power_is_not_replaced_by_range() -> void:
	# «При наличии Power диапазон не учитывается»: нечисловой Power — ошибка, а не тихая середина.
	var r := ZwoParser.parse(_wrap("<SteadyState Duration=\"60\" Power=\"abc\" PowerLow=\"0.5\" PowerHigh=\"0.6\"/>"))
	assert_false(r.ok(), "нечисловой Power — ошибка импорта")
	assert_null(r.workout)


# ---------------------------------------------------------------------------
# REQ-IMP-01 п.4 — подсказки
# ---------------------------------------------------------------------------

func test_req_imp_01_c4_text_events_inside_range_step_bound_to_it() -> void:
	var r := _parse_fixture()
	if not r.ok():
		fail_test(str(r.error_messages()))
		return
	var cues: Array[TextCue] = r.workout.steps[1].text_cues
	assert_eq(cues.size(), 2, "две подсказки шага с диапазоном")
	if cues.size() == 2:
		assert_eq(cues[0].text, "Старт")
		assert_eq(cues[0].at_sec, 0, "без timeoffset — смещение 0")
		assert_eq(cues[1].text, "Половина")
		assert_eq(cues[1].at_sec, 240, "timeoffset учитывается")
	for i in r.workout.steps.size():
		if i != 1:
			assert_eq(r.workout.steps[i].text_cues.size(), 0, "шаг %d без подсказок" % i)


# ---------------------------------------------------------------------------
# REQ-IMP-01 п.5 — метаданные
# ---------------------------------------------------------------------------

func test_req_imp_01_c5_name_description_author_kept_with_tags() -> void:
	var r := _parse_fixture()
	if not r.ok():
		fail_test(str(r.error_messages()))
		return
	assert_eq(r.workout.name, "Приёмка: диапазоны SteadyState")
	assert_eq(r.workout.description, "Независимая фикстура tester для T-149.")
	assert_eq(str(r.workout.metadata.get("author", "")), "Acceptance Coach", "author → метаданные")


func test_req_imp_01_c5_empty_tags_and_author_in_intervals_header() -> void:
	var xml := "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n<workout_file>\n<author>Coach</author>\n" \
		+ "<name>N</name>\n<sportType>bike</sportType>\n<tags/>\n<workout>\n" \
		+ "<SteadyState show_avg=\"1\" PowerHigh=\"0.6\" PowerLow=\"0.45\" Duration=\"900\"/>\n</workout>\n</workout_file>"
	var r := ZwoParser.parse(xml)
	assert_true(r.ok(), str(r.error_messages()))
	assert_eq(r.warnings.size(), 0)
	if r.ok():
		assert_eq(str(r.workout.metadata.get("author", "")), "Coach")
		assert_almost_eq(r.workout.steps[0].target_start, 52.5, 0.001, "пример карточки: 0.45…0.60 → 52.5 %")


# ---------------------------------------------------------------------------
# REQ-IMP-04 п.6 — сериализация
# ---------------------------------------------------------------------------

func test_req_imp_04_c6_round_trip_of_range_fixture() -> void:
	var r := _parse_fixture()
	if not r.ok():
		fail_test(str(r.error_messages()))
		return
	var back := WorkoutSerializer.from_json(WorkoutSerializer.to_json(r.workout))
	assert_not_null(back)
	if back == null:
		return
	assert_eq(back.steps.size(), r.workout.steps.size())
	for i in back.steps.size():
		assert_true(back.steps[i].same_as(r.workout.steps[i]), "шаг %d после JSON" % i)
	assert_eq(str(back.metadata.get("author", "")), "Acceptance Coach", "метаданные после JSON")


# ---------------------------------------------------------------------------
# REQ-IMP-05 п.1, 2 — ошибки на экране импорта
# ---------------------------------------------------------------------------

func test_req_imp_05_c1_single_bound_error_on_screen_en_has_file_element_line() -> void:
	TranslationServer.set_locale("en")
	var library := WorkoutLibrary.new(_dir + "workouts/")
	var s := _plan_screen(library)
	var path := _write_tmp("one_bound.zwo", _wrap("<SteadyState Duration=\"60\" PowerLow=\"0.5\" PowerHigh=\"0.6\"/>\n<SteadyState Duration=\"300\" PowerLow=\"0.5\"/>"))
	var r := s.import_path(path)
	assert_not_null(r)
	assert_true(r != null and not r.ok(), "одна граница без Power — импорт не выполнен")
	var text := s.import_error_text()
	assert_string_contains(text, "one_bound.zwo", "п.1: имя файла")
	assert_string_contains(text, "SteadyState", "п.1: имя элемента")
	assert_string_contains(text, "line 5", "п.1: номер строки")
	assert_false(_has_cyrillic(text), "п.1: тип проблемы на языке интерфейса (en): " + text)
	assert_eq(library.count(_profile_id), 0, "план не создан")


func test_req_imp_05_c1_single_bound_error_on_screen_ru() -> void:
	TranslationServer.set_locale("ru")
	var library := WorkoutLibrary.new(_dir + "workouts/")
	var s := _plan_screen(library)
	var path := _write_tmp("one_bound_ru.zwo", _wrap("<SteadyState Duration=\"300\" PowerHigh=\"0.6\"/>"))
	var r := s.import_path(path)
	assert_true(r != null and not r.ok())
	var text := s.import_error_text()
	assert_string_contains(text, "one_bound_ru.zwo")
	assert_string_contains(text, "SteadyState")
	assert_string_contains(text, "строка 4")


func test_req_imp_05_c2_unsupported_element_still_rejected_in_range_file() -> void:
	var r := ZwoParser.parse(_wrap("<SteadyState Duration=\"300\" PowerLow=\"0.5\" PowerHigh=\"0.6\" show_avg=\"1\"/>\n<SolidState Duration=\"60\" Power=\"0.5\"/>"))
	assert_false(r.ok(), "регрессия IMP-05 п.2: SolidState по-прежнему не поддерживается")
	assert_null(r.workout, "импорт не выполняется")
	var found := false
	for e: Dictionary in r.errors:
		if str(e.get("element", "")) == "SolidState" and int(e.get("line", 0)) == 5:
			found = true
	assert_true(found, "ошибка с именем элемента и строкой: " + str(r.error_messages()))
