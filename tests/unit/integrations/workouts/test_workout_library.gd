extends GutTest
## Тесты WorkoutLibrary и WorkoutSerializer (REQ-IMP-03 крит. 1, REQ-IMP-04 крит. 1, 2, 4, 5, REQ-IMP-05 крит. 1, 3, 4);
## атомарная запись записей библиотеки.

const FIXTURES: String = "res://tests/fixtures/workouts/"
const A: String = "profile-a"
const B: String = "profile-b"

var _dir: String
var _lib: WorkoutLibrary
var _changed: Array[String] = []


func before_each() -> void:
	_dir = "user://test_workouts_%d_%d/" % [Time.get_ticks_usec(), randi() % 100000]
	_lib = WorkoutLibrary.new(_dir)
	_changed = []
	_lib.library_changed.connect(func(id: String) -> void: _changed.append(id))


func after_each() -> void:
	AtomicFile.simulate_write_error_prefix = ""
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


## Копия фикстуры во временный каталог под другим именем (возвращает путь).
func _copy_fixture(name: String, as_name: String, mutate: Callable = Callable()) -> String:
	var text := FileAccess.get_file_as_string(FIXTURES + name)
	if mutate.is_valid():
		text = mutate.call(text)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_dir + "src/"))
	var path := _dir + "src/" + as_name
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()
	return path


# ---------------------------------------------------------------------------
# Импорт (REQ-IMP-03 крит. 1, REQ-IMP-04 крит. 1)
# ---------------------------------------------------------------------------

func test_import_zwo_creates_entry_with_name_duration_and_source() -> void:
	var r := _lib.import_file(A, FIXTURES + "simple.zwo")
	assert_true(r.ok(), str(r.error_messages()))
	assert_true(r.metadata.has("entry_id"))
	var entries := _lib.list(A)
	assert_eq(entries.size(), 1)
	assert_eq(str(entries[0]["name"]), "Simple Endurance", "REQ-IMP-04 крит. 1: название")
	assert_eq(int(entries[0]["duration_sec"]), 1800, "REQ-IMP-04 крит. 1: длительность")
	assert_eq(str(entries[0]["source"]), "zwo")
	assert_eq(str(entries[0]["source_file"]), "simple.zwo", "REQ-IMP-04 крит. 1: имя файла")
	assert_eq(str(entries[0]["id"]), str(r.metadata["entry_id"]))
	assert_eq(_changed, [A], "сигнал library_changed")


func test_import_erg_and_mrc_select_parser_by_extension() -> void:
	var erg := _lib.import_file(A, FIXTURES + "ramp_jump.erg")
	assert_true(erg.ok(), str(erg.error_messages()))
	assert_eq(erg.workout.source, "erg")
	assert_eq(erg.workout.steps[0].target_kind, WorkoutStep.TargetKind.WATTS)
	var mrc := _lib.import_file(A, FIXTURES + "sweet_spot_text.mrc")
	assert_true(mrc.ok(), str(mrc.error_messages()))
	assert_eq(mrc.workout.source, "mrc")
	assert_eq(mrc.workout.steps[0].target_kind, WorkoutStep.TargetKind.PERCENT_FTP)
	assert_eq(_lib.list(A).size(), 2)
	assert_eq(_lib.count(A), 2)


func test_extension_is_case_insensitive() -> void:
	var path := _copy_fixture("simple.zwo", "UPPER.ZWO")
	var r := _lib.import_file(A, path)
	assert_true(r.ok(), "REQ-IMP-03 крит. 1: .ZWO принимается: %s" % str(r.error_messages()))
	assert_true(WorkoutLibrary.is_supported_extension("x.Mrc"))
	assert_false(WorkoutLibrary.is_supported_extension("x.fit"))


func test_unsupported_extension_is_error_and_nothing_stored() -> void:
	var path := _copy_fixture("simple.zwo", "plan.txt")
	var r := _lib.import_file(A, path)
	assert_false(r.ok())
	assert_eq(str(r.errors[0]["key"]), "unsupported_extension", "REQ-IMP-03 крит. 1")
	assert_string_contains(r.user_message("plan.txt"), "plan.txt", "REQ-IMP-05 крит. 1: имя файла в сообщении")
	assert_eq(_lib.list(A).size(), 0)
	assert_eq(_changed.size(), 0)


func test_missing_file_is_error() -> void:
	var r := _lib.import_file(A, _dir + "nope.zwo")
	assert_false(r.ok())
	assert_eq(str(r.errors[0]["key"]), "file_not_found")
	assert_eq(str(r.metadata.get("file_name")), "nope.zwo")


func test_invalid_file_is_rejected_with_user_message_and_nothing_stored() -> void:
	var r := _lib.import_file(A, FIXTURES + "unknown_element.zwo")
	assert_false(r.ok())
	assert_eq(_lib.list(A).size(), 0, "REQ-IMP-05 крит. 2: импорт не выполняется")
	var msg := r.user_message("unknown_element.zwo")
	assert_string_contains(msg, "unknown_element.zwo")
	assert_string_contains(msg, "SolidState")
	assert_string_contains(msg, "строка 6")
	assert_false(msg.contains("res://") or msg.contains(".gd") or msg.contains("Parser"), "REQ-IMP-05 крит. 3: '%s'" % msg)


func test_corrupted_files_do_not_crash() -> void:
	for name in ["not_xml.zwo", "truncated.zwo", "no_course_data.erg", "non_monotonic.erg", "empty.erg"]:
		var r := _lib.import_file(A, FIXTURES + name)
		assert_false(r.ok(), "%s отклонён" % name)
		assert_gt(r.errors.size(), 0, "%s: есть ошибка" % name)
	assert_eq(_lib.list(A).size(), 0)


func test_empty_profile_id_is_error() -> void:
	var r := _lib.import_file("", FIXTURES + "simple.zwo")
	assert_false(r.ok())
	assert_eq(str(r.errors[0]["key"]), "no_profile")


func test_import_text_without_path() -> void:
	var r := _lib.import_text(A, FileAccess.get_file_as_string(FIXTURES + "ramp_jump.erg"), "shared.erg")
	assert_true(r.ok(), str(r.error_messages()))
	assert_eq(str(_lib.list(A)[0]["source_file"]), "shared.erg")


# ---------------------------------------------------------------------------
# Чтение (round trip через WorkoutSerializer)
# ---------------------------------------------------------------------------

func test_get_workout_round_trips_steps_cues_and_cadence() -> void:
	var r := _lib.import_file(A, FIXTURES + "intervals_textevent.zwo")
	var id := str(r.metadata["entry_id"])
	var w := _lib.get_workout(A, id)
	assert_not_null(w)
	var original: Workout = r.workout
	assert_eq(w.steps.size(), original.steps.size())
	assert_eq(w.total_duration_sec(), original.total_duration_sec())
	assert_eq(w.name, original.name)
	assert_eq(w.source, "zwo")
	for i in w.steps.size():
		var a: WorkoutStep = w.steps[i]
		var b: WorkoutStep = original.steps[i]
		assert_eq(a.duration_sec, b.duration_sec, "шаг %d: длительность" % i)
		assert_eq(a.target_kind, b.target_kind, "шаг %d: вид цели" % i)
		assert_eq(a.target_start, b.target_start, "шаг %d: цель" % i)
		assert_eq(a.target_end, b.target_end, "шаг %d: цель конца" % i)
		assert_eq(a.cadence_rpm, b.cadence_rpm, "шаг %d: каденс" % i)
		assert_eq(a.kind, b.kind, "шаг %d: тип" % i)
		assert_eq(a.text_cues.size(), b.text_cues.size(), "шаг %d: подсказки" % i)
		for j in a.text_cues.size():
			assert_eq(a.text_cues[j].at_sec, b.text_cues[j].at_sec)
			assert_eq(a.text_cues[j].text, b.text_cues[j].text)
	assert_eq(w.target_watts_at(700.0, 200), 210, "REQ-IMP-04 крит. 3: тот же Workout для сессии")
	var entry := _lib.get_entry(A, id)
	assert_eq(str(entry["name"]), "VO2 Intervals")
	assert_eq(str(entry["metadata"]["author"]), "ovosch-rider tests")


func test_get_unknown_or_unsafe_id_returns_null() -> void:
	assert_null(_lib.get_workout(A, "missing"))
	assert_eq(_lib.get_entry(A, "missing"), {})
	assert_null(_lib.get_workout(A, "../profiles"))


func test_corrupted_record_file_is_skipped() -> void:
	_lib.import_file(A, FIXTURES + "simple.zwo")
	var f := FileAccess.open(_lib.profile_dir(A) + "broken.json", FileAccess.WRITE)
	f.store_string("{ not json")
	f.close()
	var g := FileAccess.open(_lib.profile_dir(A) + "noworkout.json", FileAccess.WRITE)
	g.store_string(JSON.stringify({"id": "noworkout", "name": "без плана", "duration_sec": 10}))
	g.close()
	assert_eq(_lib.list(A).size(), 1, "записи без поля workout и битый JSON пропущены")
	assert_eq(_lib.get_entry(A, "noworkout"), {})
	assert_null(_lib.get_workout(A, "noworkout"))


# ---------------------------------------------------------------------------
# Изоляция, повторный импорт, удаление (REQ-IMP-04 крит. 2, 4, 5)
# ---------------------------------------------------------------------------

func test_library_of_profile_a_not_visible_in_b() -> void:
	_lib.import_file(A, FIXTURES + "simple.zwo")
	assert_eq(_lib.list(A).size(), 1)
	assert_eq(_lib.list(B).size(), 0, "REQ-IMP-04 крит. 2")
	_lib.import_file(B, FIXTURES + "ramp_jump.erg")
	assert_eq(_lib.list(A).size(), 1)
	assert_eq(str(_lib.list(B)[0]["source"]), "erg")


func test_reimport_same_content_replaces_entry_with_warning() -> void:
	var first := _lib.import_file(A, FIXTURES + "simple.zwo")
	var second := _lib.import_file(A, FIXTURES + "simple.zwo")
	assert_true(second.ok())
	assert_eq(_lib.list(A).size(), 1, "решение 20: тот же файл → запись заменена")
	assert_eq(str(second.metadata["entry_id"]), str(first.metadata["entry_id"]), "id сохранён")
	assert_true(second.warning_messages().any(func(m: String) -> bool: return m.contains("уже импортирован")))
	assert_eq(str(second.warnings[0]["key"]), "duplicate_replaced")


func test_reimport_same_name_different_content_creates_separate_entry() -> void:
	_lib.import_file(A, FIXTURES + "simple.zwo")
	var changed := _copy_fixture("simple.zwo", "simple.zwo",
			func(t: String) -> String: return t.replace("Duration=\"1200\"", "Duration=\"1500\""))
	var r := _lib.import_file(A, changed)
	assert_true(r.ok(), str(r.error_messages()))
	var entries := _lib.list(A)
	assert_eq(entries.size(), 2, "REQ-IMP-04 крит. 4: отдельная запись")
	assert_eq(str(entries[0]["name"]), str(entries[1]["name"]))
	assert_ne(int(entries[0]["duration_sec"]), int(entries[1]["duration_sec"]))


func test_delete_entry() -> void:
	var r := _lib.import_file(A, FIXTURES + "simple.zwo")
	var id := str(r.metadata["entry_id"])
	_lib.import_file(A, FIXTURES + "ramp_jump.erg")
	assert_true(_lib.delete(A, id))
	assert_eq(_lib.list(A).size(), 1)
	assert_null(_lib.get_workout(A, id))
	assert_false(_lib.delete(A, id), "повторное удаление — false")
	assert_false(_lib.delete(A, "../x"))
	assert_eq(_changed.size(), 3)


func test_list_sorted_by_import_time() -> void:
	_lib.import_file(A, FIXTURES + "sweet_spot_text.mrc")
	_lib.import_file(A, FIXTURES + "simple.zwo")
	var entries := _lib.list(A)
	assert_true(int(entries[0]["imported_at"]) <= int(entries[1]["imported_at"]))


func test_delete_all_and_profile_cascade() -> void:
	_lib.import_file(A, FIXTURES + "simple.zwo")
	_lib.import_file(A, FIXTURES + "ramp_jump.erg")
	_lib.import_file(B, FIXTURES + "simple.zwo")
	var repo := ProfileRepository.new(_dir + "profiles/")
	var pa := repo.create("Alice")
	var pb := repo.create("Bob")
	_lib.attach_to_profiles(repo)
	_lib.attach_to_profiles(repo)  # повторная подписка не дублируется
	# Библиотеки заведены под id профилей репозитория
	_lib.import_file(pa.id, FIXTURES + "simple.zwo")
	_lib.import_file(pb.id, FIXTURES + "simple.zwo")
	assert_eq(repo.delete(pa.id), "")
	assert_eq(_lib.list(pa.id).size(), 0, "каскад: библиотека удалённого профиля стёрта")
	assert_eq(_lib.list(pb.id).size(), 1, "библиотека другого профиля цела")
	assert_false(DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(_lib.profile_dir(pa.id))))
	assert_eq(_lib.delete_all(A), 2)
	assert_eq(_lib.list(A).size(), 0)
	assert_eq(_lib.list(B).size(), 1)
	assert_eq(_lib.delete_all("nobody"), 0)


# ---------------------------------------------------------------------------
# WorkoutSerializer
# ---------------------------------------------------------------------------

func test_serializer_round_trip_all_step_kinds() -> void:
	var steps: Array[WorkoutStep] = [
		WorkoutStep.ramp_percent(300, 40.0, 65.0, WorkoutStep.StepKind.WARMUP),
		WorkoutStep.percent(600, 90.0),
		WorkoutStep.watts(120, 250.0, WorkoutStep.StepKind.INTERVAL_ON),
		WorkoutStep.ramp_watts(60, 100.0, 200.0),
		WorkoutStep.free_ride(90),
		WorkoutStep.percent(30, 50.0, WorkoutStep.StepKind.COOLDOWN),
	]
	steps[1].cadence_rpm = 95
	steps[1].text_cues.append(TextCue.make(15, "hold"))
	var w := Workout.make("All kinds", steps, "manual")
	w.description = "desc"
	var back := WorkoutSerializer.from_json(WorkoutSerializer.to_json(w))
	assert_not_null(back)
	assert_eq(back.name, "All kinds")
	assert_eq(back.description, "desc")
	assert_eq(back.source, "manual")
	assert_eq(back.steps.size(), 6)
	for i in 6:
		assert_eq(back.steps[i].kind, steps[i].kind, "шаг %d: тип" % i)
		assert_eq(back.steps[i].target_kind, steps[i].target_kind, "шаг %d: вид цели" % i)
		assert_eq(back.steps[i].target_start, steps[i].target_start)
		assert_eq(back.steps[i].target_end, steps[i].target_end)
		assert_eq(back.steps[i].duration_sec, steps[i].duration_sec)
	assert_eq(back.steps[1].cadence_rpm, 95)
	assert_eq(back.steps[1].text_cues[0].at_sec, 15)
	assert_eq(back.steps[1].text_cues[0].text, "hold")
	assert_true(back.is_valid())


func test_serializer_rejects_garbage() -> void:
	assert_null(WorkoutSerializer.from_json("not json"))
	assert_null(WorkoutSerializer.from_json("{\"name\": \"x\"}"), "нет steps → null")
	assert_null(WorkoutSerializer.from_dict({}))
	var w := WorkoutSerializer.from_dict({"steps": [{"duration_sec": 60, "target_kind": "bogus", "kind": "bogus"}, 5]})
	assert_eq(w.steps.size(), 1, "битые элементы пропущены")
	assert_eq(w.steps[0].target_kind, WorkoutStep.TargetKind.NONE)
	assert_eq(w.steps[0].kind, WorkoutStep.StepKind.STEADY)


# ---------------------------------------------------------------------------
# Атомарная запись записи библиотеки (финальное ревью, REQ-IMP-05 крит. 4)
# ---------------------------------------------------------------------------

func test_write_error_keeps_previous_record_and_reports_storage_write_failed() -> void:
	var text := FileAccess.get_file_as_string(FIXTURES + "simple.zwo")
	var first := _lib.import_text(A, text, "simple.zwo")
	assert_true(first.ok(), str(first.error_messages()))
	var entry_id := str(first.metadata["entry_id"])
	var path := _lib.profile_dir(A) + entry_id + ".json"
	var before := FileAccess.get_file_as_string(path)
	_changed = []
	AtomicFile.simulate_write_error_prefix = path
	var again := _lib.import_text(A, text, "simple_again.zwo")  # тот же хэш — перезапись той же записи
	assert_false(again.ok())
	assert_push_error("AtomicFile")
	assert_push_error("WorkoutLibrary")
	assert_eq(str(again.errors[0].get("key", "")), "storage_write_failed")
	assert_eq(FileAccess.get_file_as_string(path), before, "прежняя запись цела")
	assert_false(FileAccess.file_exists(AtomicFile.tmp_path(path)), "временный файл удалён")
	assert_eq(_changed, [] as Array[String], "без library_changed при сбое")
	AtomicFile.simulate_write_error_prefix = ""
	var entries := WorkoutLibrary.new(_dir).list(A)
	assert_eq(entries.size(), 1)
	assert_eq(str(entries[0]["source_file"]), "simple.zwo", "на диске — прежняя запись")
