extends GutTest
## Независимые приёмочные тесты профилей (тестировщик, T-009).
## Покрытие: REQ-PRF-01 крит. 1, 2, 5, 6; REQ-PRF-02 крит. 1, 3, 4, 5, 6;
## REQ-NFR-06 крит. 1 (поиск платформенных вызовов по `res://src`).
## Крит. 3, 4 REQ-PRF-01 — n/a до T-011.
##
## Заявленная семантика: `validate()` → стабильные коды `Profile.ERR_*`;
## `save()` → массив ошибок (пустой = успех), уникальность имени без учёта регистра;
## `delete()` → `""` / `"profile_not_found"` / `"last_profile"`; первый сохранённый
## профиль становится активным; повреждённый JSON → предупреждение и пустое хранилище.

var _dir: String
var _repo: ProfileRepository
var _saved: Array[String] = []
var _deleted: Array[String] = []
var _active_changes: Array[String] = []


func before_each() -> void:
	_dir = "user://test_acc_profiles_%d_%d/" % [Time.get_ticks_usec(), randi() % 1000000]
	_saved = []
	_deleted = []
	_active_changes = []
	_repo = _open_repo()


func after_each() -> void:
	_remove_tree(ProjectSettings.globalize_path(_dir))
	assert_false(DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(_dir)), "временный каталог удалён")


func _open_repo() -> ProfileRepository:
	var r := ProfileRepository.new(_dir)
	r.profile_saved.connect(func(id: String) -> void: _saved.append(id))
	r.profile_deleted.connect(func(id: String) -> void: _deleted.append(id))
	r.active_profile_changed.connect(func(id: String) -> void: _active_changes.append(id))
	return r


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


func _add(name: String, ftp: int = 200) -> Profile:
	var p := Profile.create(name)
	p.ftp_w = ftp
	assert_eq(_repo.save(p), [], "предусловие: профиль «%s» сохранён" % name)
	return p


func _names(repo: ProfileRepository) -> Array[String]:
	var out: Array[String] = []
	for p in repo.list():
		out.append(p.name)
	return out


func _ids(repo: ProfileRepository) -> Array[String]:
	var out: Array[String] = []
	for p in repo.list():
		out.append(p.id)
	return out


func _write_file(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


# ===========================================================================
# REQ-PRF-01 крит. 1 — создание: имя 1–40 символов, непустое после обрезки
# ===========================================================================

func test_req_prf_01_c1_name_of_1_and_40_chars_is_accepted_and_added_to_list() -> void:
	var one := _repo.create("A")
	assert_not_null(one)
	var forty := _repo.create("Б".repeat(40))
	assert_not_null(forty, "ровно 40 символов (кириллица, считаем в символах)")
	assert_eq(_repo.count(), 2)
	assert_eq(_repo.get_by_id(forty.id).name.length(), 40)
	assert_eq(_names(_repo).size(), 2)


func test_req_prf_01_c1_name_of_41_chars_is_rejected_with_code() -> void:
	var p := Profile.create("x".repeat(41))
	var errors := _repo.save(p)
	assert_eq(errors, [Profile.ERR_NAME_TOO_LONG])
	assert_eq(Profile.ERR_NAME_TOO_LONG, "name_too_long", "стабильный код")
	assert_eq(_repo.count(), 0)
	assert_null(_repo.create("y".repeat(41)))
	assert_eq(_repo.last_errors, [Profile.ERR_NAME_TOO_LONG])


func test_req_prf_01_c1_whitespace_only_name_is_rejected_and_nothing_written() -> void:
	for raw in ["", " ", "   \t  ", "\n"]:
		var p := Profile.create(raw)
		assert_eq(_repo.save(p), [Profile.ERR_NAME_EMPTY], "имя %s" % JSON.stringify(raw))
		assert_null(_repo.create(raw))
	assert_eq(Profile.ERR_NAME_EMPTY, "name_empty")
	assert_eq(_repo.count(), 0)
	assert_eq(_saved, [])
	assert_eq(_repo.active_profile_id, "", "отклонённый профиль не становится активным")
	assert_false(FileAccess.file_exists(_repo.file_path()))


func test_req_prf_01_c1_name_is_trimmed_but_inner_spaces_kept_and_40_after_trim_ok() -> void:
	var p := _repo.create("   Даша  Ковалёва   ")
	assert_eq(p.name, "Даша  Ковалёва")
	var padded := Profile.create("  " + "z".repeat(40) + "  ")
	assert_eq(_repo.save(padded), [], "40 символов после обрезки — допустимо")
	assert_eq(_repo.get_by_id(padded.id).name.length(), 40)
	var again := ProfileRepository.new(_dir)
	assert_eq(again.get_by_id(p.id).name, "Даша  Ковалёва", "на диске имя уже обрезано")


func test_req_prf_01_c1_profile_without_id_is_rejected() -> void:
	var p := Profile.new()
	p.name = "NoId"
	assert_has(_repo.save(p), Profile.ERR_ID_EMPTY)
	assert_eq(_repo.count(), 0)


# ===========================================================================
# REQ-PRF-01 крит. 2 — уникальность без учёта регистра
# ===========================================================================

func test_req_prf_01_c2_roman_and_roman_lowercase_conflict() -> void:
	assert_not_null(_repo.create("Roman"))
	assert_null(_repo.create("roman"))
	assert_eq(_repo.last_errors, [ProfileRepository.ERR_NAME_NOT_UNIQUE])
	assert_eq(ProfileRepository.ERR_NAME_NOT_UNIQUE, "name_not_unique")
	assert_null(_repo.create("ROMAN"))
	assert_null(_repo.create("  rOmAn  "), "обрезка пробелов перед сравнением")
	assert_eq(_repo.count(), 1)
	assert_eq(ProfileRepository.new(_dir).count(), 1)


func test_req_prf_01_c2_cyrillic_case_insensitivity() -> void:
	assert_not_null(_repo.create("Даша"))
	assert_null(_repo.create("ДАША"))
	assert_null(_repo.create("даша"))
	assert_false(_repo.is_name_available("дАшА"))
	assert_true(_repo.is_name_available("Dasha"), "латиница — другое имя")
	assert_eq(_repo.count(), 1)


func test_req_prf_01_c2_renaming_to_another_profiles_name_is_rejected_and_file_unchanged() -> void:
	var a := _add("Alice")
	var b := _add("Bob")
	var edit := b.duplicate_profile()
	edit.name = "ALICE"
	assert_eq(_repo.save(edit), [ProfileRepository.ERR_NAME_NOT_UNIQUE])
	assert_eq(_repo.get_by_id(b.id).name, "Bob")
	assert_eq(ProfileRepository.new(_dir).get_by_id(b.id).name, "Bob")
	assert_true(_repo.is_name_available("alice", a.id), "своё имя при переименовании свободно")


func test_req_prf_01_c2_similar_but_different_names_are_allowed() -> void:
	assert_not_null(_repo.create("Roman"))
	assert_not_null(_repo.create("Roman2"))
	assert_not_null(_repo.create("Roma"))
	assert_null(_repo.create("Roman "), "«Roman » после обрезки — дубликат")
	assert_eq(_repo.count(), 3)


func test_req_prf_01_c2_rejected_edit_of_live_reference_must_not_leak_to_disk_via_later_save() -> void:
	# Негатив: правка живого объекта из репозитория отклонена save(); следующая
	# запись другого профиля не должна «протащить» невалидное имя на диск.
	var a := _add("Alice")
	_add("Bob")
	a.name = "bob" # дубликат
	assert_eq(_repo.save(a), [ProfileRepository.ERR_NAME_NOT_UNIQUE])
	_add("Carol") # любая успешная запись переписывает файл целиком
	var again := ProfileRepository.new(_dir)
	var lowered: Array[String] = []
	for p in again.list():
		lowered.append(Profile.normalized_name(p.name))
	assert_eq(lowered.count("bob"), 1, "на диске не должно быть двух профилей с именем bob; факт: %s" % str(_names(again)))
	assert_eq(again.get_by_id(a.id).name, "Alice", "отклонённое имя не сохранилось")


# ===========================================================================
# REQ-PRF-01 крит. 5 — нельзя удалить последний профиль
# ===========================================================================

func test_req_prf_01_c5_last_profile_cannot_be_deleted_code_last_profile() -> void:
	var only := _add("Solo")
	assert_eq(_repo.delete(only.id), ProfileRepository.ERR_LAST_PROFILE)
	assert_eq(ProfileRepository.ERR_LAST_PROFILE, "last_profile")
	assert_eq(_repo.last_errors, [ProfileRepository.ERR_LAST_PROFILE])
	assert_eq(_repo.count(), 1)
	assert_eq(_repo.active_profile_id, only.id, "активный не сброшен")
	assert_eq(_deleted, [], "сигнал каскада не испускался")
	assert_eq(ProfileRepository.new(_dir).count(), 1)


func test_req_prf_01_c5_after_deleting_down_to_one_the_last_is_protected_again() -> void:
	var a := _add("A")
	var b := _add("B")
	var c := _add("C")
	assert_eq(_repo.delete(c.id), "")
	assert_eq(_repo.delete(b.id), "")
	assert_eq(_repo.delete(a.id), ProfileRepository.ERR_LAST_PROFILE)
	assert_eq(_deleted, [c.id, b.id])
	assert_eq(_repo.count(), 1)


func test_req_prf_01_c5_delete_hook_not_called_for_refused_deletion() -> void:
	var only := _add("Solo")
	var calls: Array[String] = []
	_repo.add_on_delete_hook(func(id: String) -> void: calls.append(id))
	_repo.delete(only.id)
	_repo.delete("ghost")
	assert_eq(calls, [])


# ===========================================================================
# Удаление: активный, несуществующий
# ===========================================================================

func test_req_prf_01_delete_active_profile_makes_first_by_creation_active() -> void:
	var a := _add("A")
	var b := _add("B")
	var c := _add("C")
	a.created_at = 100
	b.created_at = 200
	c.created_at = 300
	_repo.save(a)
	_repo.save(b)
	_repo.save(c)
	_repo.active_profile_id = c.id
	_active_changes = []
	assert_eq(_repo.delete(c.id), "")
	assert_eq(_repo.active_profile_id, a.id, "активным становится первый по дате создания")
	assert_eq(_active_changes, [a.id])
	assert_eq(ProfileRepository.new(_dir).active_profile_id, a.id, "и это сохранено")
	# удаляем активный «первый» → следующий по порядку
	assert_eq(_repo.delete(a.id), "")
	assert_eq(_repo.active_profile_id, b.id)
	assert_eq(_active_changes, [a.id, b.id])


func test_req_prf_01_delete_non_active_keeps_active_and_emits_no_active_change() -> void:
	var a := _add("A")
	var b := _add("B")
	_active_changes = []
	assert_eq(_repo.delete(b.id), "")
	assert_eq(_repo.active_profile_id, a.id)
	assert_eq(_active_changes, [])
	assert_null(_repo.get_by_id(b.id))


func test_req_prf_01_delete_unknown_and_empty_id_report_profile_not_found() -> void:
	_add("A")
	_add("B")
	assert_eq(_repo.delete("no-such-id"), ProfileRepository.ERR_PROFILE_NOT_FOUND)
	assert_eq(_repo.delete(""), ProfileRepository.ERR_PROFILE_NOT_FOUND)
	assert_eq(ProfileRepository.ERR_PROFILE_NOT_FOUND, "profile_not_found")
	assert_eq(_repo.count(), 2)
	assert_eq(_deleted, [])


func test_req_prf_01_delete_twice_second_time_not_found() -> void:
	_add("A")
	var b := _add("B")
	assert_eq(_repo.delete(b.id), "")
	assert_eq(_repo.delete(b.id), ProfileRepository.ERR_PROFILE_NOT_FOUND)
	assert_eq(_deleted, [b.id], "каскад сработал один раз")


# ===========================================================================
# REQ-PRF-01 крит. 6 — список и активный профиль переживают перезапуск
# ===========================================================================

func test_req_prf_01_c6_first_saved_becomes_active_and_persists() -> void:
	var a := _add("A")
	_add("B")
	assert_eq(_repo.active_profile_id, a.id, "первый сохранённый — активный")
	assert_eq(_active_changes, [a.id], "второй не меняет активного")
	var again := ProfileRepository.new(_dir)
	assert_eq(again.count(), 2)
	assert_eq(again.active_profile_id, a.id)
	assert_eq(again.get_active().name, "A")


func test_req_prf_01_c6_active_switch_persists_and_profile_fields_roundtrip() -> void:
	var a := _add("A", 180)
	var b := _add("B", 260)
	b.weight_kg = 82.4
	b.max_hr = 190
	b.intensity_default = 95
	b.resistance_level_default = 35
	assert_eq(_repo.save(b), [])
	_repo.active_profile_id = b.id
	var again := ProfileRepository.new(_dir)
	assert_eq(again.active_profile_id, b.id)
	var b2 := again.get_by_id(b.id)
	assert_eq(b2.ftp_w, 260)
	assert_almost_eq(b2.weight_kg, 82.4, 1e-9)
	assert_eq(b2.max_hr, 190)
	assert_eq(b2.intensity_default, 95)
	assert_eq(b2.resistance_level_default, 35)
	assert_eq(b2.created_at, b.created_at)
	assert_eq(again.get_by_id(a.id).ftp_w, 180)


func test_req_prf_01_c6_two_repositories_on_same_dir_see_data_after_reload() -> void:
	var a := _add("A")
	var second := ProfileRepository.new(_dir)
	assert_eq(second.count(), 1, "второй экземпляр читает диск при создании")
	_add("B")
	assert_eq(second.count(), 1, "без перечитывания второй экземпляр не знает о новых профилях")
	second.load_from_disk()
	assert_eq(second.count(), 2)
	assert_eq(second.active_profile_id, a.id)
	assert_eq(_ids(second), _ids(_repo))


func test_req_prf_01_c6_100_profiles_list_is_stably_ordered_across_reload() -> void:
	for i in 100:
		assert_not_null(_repo.create("P%03d" % i), "создан P%03d" % i)
	assert_eq(_repo.count(), 100)
	var expected: Array[String] = []
	for i in 100:
		expected.append("P%03d" % i)
	assert_eq(_names(_repo), expected, "порядок создания")
	var again := ProfileRepository.new(_dir)
	assert_eq(again.count(), 100)
	assert_eq(_names(again), expected, "после перезапуска порядок тот же")
	assert_eq(_ids(again), _ids(_repo))
	assert_eq(_names(ProfileRepository.new(_dir)), _names(again), "повторное чтение стабильно")


func test_req_prf_01_c6_list_returns_copy_not_internal_storage() -> void:
	_add("A")
	var l := _repo.list()
	l.clear()
	assert_eq(_repo.count(), 1)
	assert_eq(_repo.list().size(), 1)


func test_req_prf_01_c6_corrupted_json_gives_warning_and_empty_repository() -> void:
	_write_file(_dir + ProfileRepository.FILE_NAME, "{ not json at all")
	var broken := ProfileRepository.new(_dir)
	assert_push_warning("повреждён", "предупреждение о повреждённом файле")
	assert_eq(broken.count(), 0)
	assert_eq(broken.active_profile_id, "")
	assert_not_null(broken.create("Fresh"), "можно работать дальше")
	assert_eq(ProfileRepository.new(_dir).count(), 1, "новый файл записан поверх повреждённого")


func test_req_prf_01_c6_json_that_is_not_an_object_is_treated_as_corrupted() -> void:
	_write_file(_dir + ProfileRepository.FILE_NAME, "[1, 2, 3]")
	var broken := ProfileRepository.new(_dir)
	assert_push_warning("повреждён")
	assert_eq(broken.count(), 0)


func test_req_prf_01_c6_garbage_entries_in_profiles_array_are_skipped() -> void:
	var good_id := Profile.generate_id()
	var payload := {
		"schema": 1,
		"active_profile_id": good_id,
		"profiles": [
			1, "str", null, [], {"id": ""}, {"name": "no id"},
			{"id": good_id, "name": "Good", "ftp_w": 210.0},
		],
	}
	_write_file(_dir + ProfileRepository.FILE_NAME, JSON.stringify(payload))
	var r := ProfileRepository.new(_dir)
	assert_eq(r.count(), 1)
	assert_eq(r.active_profile_id, good_id)
	assert_eq(r.get_active().ftp_w, 210)


func test_req_prf_01_c6_profiles_key_not_array_gives_empty_repository() -> void:
	_write_file(_dir + ProfileRepository.FILE_NAME, JSON.stringify({"profiles": "oops", "active_profile_id": 5}))
	var r := ProfileRepository.new(_dir)
	assert_eq(r.count(), 0)
	assert_eq(r.active_profile_id, "")


func test_req_prf_01_c6_setting_unknown_active_id_is_ignored_and_not_persisted() -> void:
	var a := _add("A")
	_repo.active_profile_id = "ghost"
	assert_push_error("не найден")
	assert_eq(_repo.active_profile_id, a.id)
	assert_eq(ProfileRepository.new(_dir).active_profile_id, a.id)
	_active_changes = []
	_repo.active_profile_id = a.id
	assert_eq(_active_changes, [], "повторная установка того же активного не шлёт сигнал")


func test_req_prf_01_c6_storage_file_contains_no_secret_like_fields() -> void:
	_add("A")
	var text := FileAccess.get_file_as_string(_repo.file_path())
	for forbidden in ["access_token", "refresh_token", "api_key", "Bearer "]:
		assert_false(text.contains(forbidden), "в profiles.json нет поля %s" % forbidden)


# ===========================================================================
# REQ-PRF-02 крит. 1 — диапазоны FTP, веса, max_hr
# ===========================================================================

func test_req_prf_02_c1_ftp_boundaries_49_50_600_601() -> void:
	var p := Profile.create("F")
	p.ftp_w = 49
	assert_eq(p.validate(), [Profile.ERR_FTP_OUT_OF_RANGE])
	p.ftp_w = 50
	assert_eq(p.validate(), [])
	p.ftp_w = 600
	assert_eq(p.validate(), [])
	p.ftp_w = 601
	assert_eq(p.validate(), [Profile.ERR_FTP_OUT_OF_RANGE])
	p.ftp_w = 0
	assert_eq(p.validate(), [Profile.ERR_FTP_OUT_OF_RANGE])
	p.ftp_w = -200
	assert_eq(p.validate(), [Profile.ERR_FTP_OUT_OF_RANGE])
	assert_eq(Profile.ERR_FTP_OUT_OF_RANGE, "ftp_out_of_range")


func test_req_prf_02_c1_weight_boundaries_19_9_20_250_250_1() -> void:
	var p := Profile.create("W")
	p.weight_kg = 19.9
	assert_eq(p.validate(), [Profile.ERR_WEIGHT_OUT_OF_RANGE])
	p.weight_kg = 20.0
	assert_eq(p.validate(), [])
	p.weight_kg = 250.0
	assert_eq(p.validate(), [])
	p.weight_kg = 250.1
	assert_eq(p.validate(), [Profile.ERR_WEIGHT_OUT_OF_RANGE])
	p.weight_kg = 0.0
	assert_eq(p.validate(), [Profile.ERR_WEIGHT_OUT_OF_RANGE])
	p.weight_kg = -75.0
	assert_eq(p.validate(), [Profile.ERR_WEIGHT_OUT_OF_RANGE])
	assert_eq(Profile.ERR_WEIGHT_OUT_OF_RANGE, "weight_out_of_range")


func test_req_prf_02_c1_weight_step_0_1_is_applied_on_serialization() -> void:
	var p := Profile.create("W")
	p.weight_kg = 75.26
	assert_eq(p.validate(), [], "значение в диапазоне принимается")
	assert_almost_eq(float(p.to_dict()["weight_kg"]), 75.3, 1e-9, "в файл уходит с шагом 0.1")
	assert_eq(_repo.save(p), [])
	assert_almost_eq(ProfileRepository.new(_dir).get_by_id(p.id).weight_kg, 75.3, 1e-9)


func test_req_prf_02_c1_max_hr_boundaries_0_99_100_220_221() -> void:
	var p := Profile.create("H")
	assert_eq(p.max_hr, 0, "по умолчанию не задан")
	assert_eq(p.validate(), [])
	p.max_hr = 99
	assert_eq(p.validate(), [Profile.ERR_MAX_HR_OUT_OF_RANGE])
	p.max_hr = 100
	assert_eq(p.validate(), [])
	p.max_hr = 220
	assert_eq(p.validate(), [])
	p.max_hr = 221
	assert_eq(p.validate(), [Profile.ERR_MAX_HR_OUT_OF_RANGE])
	p.max_hr = -1
	assert_eq(p.validate(), [Profile.ERR_MAX_HR_OUT_OF_RANGE])
	p.max_hr = 1
	assert_eq(p.validate(), [Profile.ERR_MAX_HR_OUT_OF_RANGE])
	assert_eq(Profile.ERR_MAX_HR_OUT_OF_RANGE, "max_hr_out_of_range")


func test_req_prf_02_c1_multiple_violations_are_all_reported() -> void:
	var p := Profile.create("M")
	p.ftp_w = 1000
	p.weight_kg = 10.0
	p.max_hr = 300
	var errors := p.validate()
	assert_has(errors, Profile.ERR_FTP_OUT_OF_RANGE)
	assert_has(errors, Profile.ERR_WEIGHT_OUT_OF_RANGE)
	assert_has(errors, Profile.ERR_MAX_HR_OUT_OF_RANGE)
	assert_eq(errors.size(), 3)
	assert_eq(_repo.save(p), errors, "репозиторий возвращает те же коды")
	assert_eq(_repo.count(), 0)


func test_req_prf_02_c1_out_of_range_edit_is_rejected_by_repository_and_file_keeps_old_value() -> void:
	var p := _add("Edit", 200)
	var edit := p.duplicate_profile()
	edit.ftp_w = 601
	assert_eq(_repo.save(edit), [Profile.ERR_FTP_OUT_OF_RANGE])
	assert_eq(_repo.get_by_id(p.id).ftp_w, 200)
	assert_eq(ProfileRepository.new(_dir).get_by_id(p.id).ftp_w, 200)


func test_req_prf_02_c1_rejected_edit_of_live_reference_must_not_be_persisted_by_later_save() -> void:
	# Негатив: правка объекта, полученного из репозитория, отклонена save(); затем
	# сохраняется другой профиль. На диске должно остаться последнее валидное значение.
	var a := _add("A", 200)
	a.ftp_w = 601
	assert_eq(_repo.save(a), [Profile.ERR_FTP_OUT_OF_RANGE])
	_add("B")
	var reloaded := ProfileRepository.new(_dir).get_by_id(a.id)
	assert_eq(reloaded.ftp_w, 200, "отклонённое значение FTP=601 не должно оказаться на диске")
	assert_eq(reloaded.validate(), [], "в файле нет невалидных профилей")


func test_req_prf_02_c1_intensity_and_resistance_defaults_ranges() -> void:
	var p := Profile.create("D")
	p.intensity_default = 49
	assert_eq(p.validate(), [Profile.ERR_INTENSITY_OUT_OF_RANGE])
	p.intensity_default = 151
	assert_eq(p.validate(), [Profile.ERR_INTENSITY_OUT_OF_RANGE])
	p.intensity_default = 50
	p.resistance_level_default = -1
	assert_eq(p.validate(), [Profile.ERR_RESISTANCE_OUT_OF_RANGE])
	p.resistance_level_default = 101
	assert_eq(p.validate(), [Profile.ERR_RESISTANCE_OUT_OF_RANGE])
	p.resistance_level_default = 100
	p.intensity_default = 150
	assert_eq(p.validate(), [])


# ===========================================================================
# from_dict — мусор, отсутствующие поля, float вместо int
# ===========================================================================

func test_req_prf_02_from_dict_with_floats_from_json() -> void:
	var p := Profile.from_dict({"id": "abc", "name": "J", "ftp_w": 250.0, "weight_kg": 70.0, "max_hr": 185.0,
		"intensity_default": 90.0, "resistance_level_default": 40.0, "created_at": 1700000000.0})
	assert_eq(p.ftp_w, 250)
	assert_eq(p.max_hr, 185)
	assert_eq(p.intensity_default, 90)
	assert_eq(p.resistance_level_default, 40)
	assert_eq(p.created_at, 1700000000)
	assert_eq(p.validate(), [])
	assert_typeof(p.ftp_w, TYPE_INT)
	assert_typeof(p.max_hr, TYPE_INT)


func test_req_prf_02_from_dict_missing_fields_get_defaults_and_empty_dict_is_invalid() -> void:
	var p := Profile.from_dict({"id": "x", "name": "Min"})
	assert_eq(p.ftp_w, 200)
	assert_almost_eq(p.weight_kg, 75.0, 1e-9)
	assert_eq(p.max_hr, 0)
	assert_null(p.power_zones)
	assert_null(p.hr_zones)
	assert_eq(p.validate(), [])
	var empty := Profile.from_dict({})
	assert_has(empty.validate(), Profile.ERR_ID_EMPTY)
	assert_has(empty.validate(), Profile.ERR_NAME_EMPTY)


func test_req_prf_02_from_dict_with_garbage_types_does_not_crash_and_is_reported_by_validate() -> void:
	var p := Profile.from_dict({
		"id": 12345, "name": ["array"], "ftp_w": "not-a-number", "weight_kg": "heavy",
		"max_hr": true, "power_zone_bounds_pct": "junk", "hr_zone_bounds_pct": {"a": 1},
		"created_at": "yesterday",
	})
	assert_eq(p.id, "12345", "числовой id приводится к строке")
	assert_null(p.power_zones, "строка вместо массива границ игнорируется")
	assert_null(p.hr_zones, "словарь вместо массива границ игнорируется")
	var errors := p.validate()
	assert_has(errors, Profile.ERR_FTP_OUT_OF_RANGE, "«not-a-number» → 0 → вне диапазона")
	assert_has(errors, Profile.ERR_WEIGHT_OUT_OF_RANGE)
	assert_eq(_repo.save(p), errors, "мусор не сохраняется")


func test_req_prf_02_from_dict_with_json_null_in_numeric_field_does_not_crash() -> void:
	# JSON `null` в числовом поле (например, max_hr «не задан» из другой версии/писателя).
	var p := Profile.from_dict({"id": "n", "name": "N", "max_hr": null, "intensity_default": null, "created_at": null})
	assert_not_null(p, "from_dict не должен падать на null")
	if p != null:
		assert_eq(p.max_hr, 0, "null → «не задан»")
		assert_eq(p.validate(), [])


func test_req_prf_02_from_dict_with_garbage_zone_bounds_is_invalid_not_crash() -> void:
	var p := Profile.from_dict({"id": "z", "name": "Z", "power_zone_bounds_pct": ["a", "b"], "hr_zone_bounds_pct": [90, 80]})
	assert_not_null(p.power_zones)
	assert_has(p.validate(), Profile.ERR_POWER_ZONES_INVALID, "нечисловые границы → 0 → невалидны")
	assert_has(p.validate(), Profile.ERR_HR_ZONES_INVALID, "убывающие границы невалидны")
	var empty_bounds := Profile.from_dict({"id": "e", "name": "E", "power_zone_bounds_pct": []})
	assert_has(empty_bounds.validate(), Profile.ERR_POWER_ZONES_INVALID, "пустой массив границ — не «по умолчанию», а ошибка")


func test_req_prf_02_to_dict_from_dict_roundtrip_preserves_everything() -> void:
	var p := Profile.create("Round")
	p.ftp_w = 275
	p.weight_kg = 68.2
	p.max_hr = 192
	p.power_zones = PowerZones.custom(p.ftp_w, [50.0, 70.0, 85.0, 100.0, 115.0, 140.0])
	p.hr_zones = HrZones.custom(p.max_hr, [65.0, 75.0, 85.0, 92.0])
	var copy := Profile.from_dict(p.to_dict())
	assert_eq(copy.to_dict(), p.to_dict())
	assert_eq(copy.power_zones.boundaries_pct, p.power_zones.boundaries_pct)
	assert_eq(copy.hr_zones.boundaries_pct, p.hr_zones.boundaries_pct)
	assert_eq(copy.validate(), [])
	assert_eq(p.to_dict()["schema"], Profile.SCHEMA_VERSION)


# ===========================================================================
# REQ-PRF-02 крит. 3, 4 — зоны пульса: по умолчанию от max_hr; без max_hr — «нет зоны»
# ===========================================================================

func test_req_prf_02_c4_without_max_hr_hr_zone_is_0_for_any_bpm() -> void:
	var p := Profile.create("H")
	assert_false(p.has_hr_zones())
	assert_null(p.effective_hr_zones())
	for bpm in [0, 1, 60, 120, 150, 200, 250]:
		assert_eq(p.hr_zone_of(bpm), 0, "bpm=%d" % bpm)


func test_req_prf_02_c3_default_hr_zones_from_max_hr_180_match_hud_04_table() -> void:
	var p := Profile.create("H")
	p.max_hr = 180
	assert_true(p.has_hr_zones())
	assert_eq(p.hr_zone_of(107), 1)
	assert_eq(p.hr_zone_of(108), 2)
	assert_eq(p.hr_zone_of(126), 3)
	assert_eq(p.hr_zone_of(144), 4)
	assert_eq(p.hr_zone_of(162), 5)
	assert_eq(p.hr_zone_of(0), 0, "bpm 0 — нет данных")
	assert_eq(p.effective_hr_zones().boundaries_pct, [60.0, 70.0, 80.0, 90.0])


func test_req_prf_02_c3_custom_pct_hr_zones_follow_profile_max_hr() -> void:
	var p := Profile.create("H")
	p.max_hr = 200
	p.hr_zones = HrZones.custom(100, [50.0, 60.0, 70.0, 80.0]) # max_hr внутри зон намеренно «чужой»
	assert_eq(p.hr_zone_of(99), 1, "граница считается от max_hr профиля (200), не из объекта зон")
	assert_eq(p.hr_zone_of(100), 2)
	assert_eq(p.hr_zone_of(160), 5)
	p.max_hr = 0
	assert_eq(p.hr_zone_of(160), 0, "без max_hr процентные зоны недоступны")


func test_req_prf_02_c3_c4_overridden_absolute_hr_zones_are_available_without_max_hr() -> void:
	# REQ-PRF-02 крит. 3: границы переопределяются вручную или из Intervals.icu;
	# крит. 4: зоны недоступны, «пока max_hr не задан И зоны не переопределены».
	# Абсолютные границы (уд/мин, как приходят из Intervals.icu) не требуют max_hr.
	var p := Profile.create("H")
	p.hr_zones = HrZones.custom_bpm([108, 126, 144, 162])
	assert_eq(p.validate(), [], "профиль с абсолютными зонами валиден")
	assert_eq(p.hr_zone_of(150), 4, "переопределённые зоны доступны без max_hr; факт зона=%d" % p.hr_zone_of(150))


func test_req_prf_02_c3_overridden_absolute_hr_zones_survive_roundtrip() -> void:
	var p := Profile.create("H")
	p.max_hr = 180
	p.hr_zones = HrZones.custom_bpm([100, 120, 140, 160]) # намеренно не совпадает с 60/70/80/90 % от 180
	assert_eq(p.hr_zone_of(119), 2, "предусловие: до сериализации зоны абсолютные" )
	var copy := Profile.from_dict(p.to_dict())
	assert_eq(copy.hr_zone_of(119), 2, "после to_dict/from_dict абсолютные границы не должны подменяться процентными (по 60 %% от 180 = 108 → было бы Z3)")


# ===========================================================================
# REQ-PRF-02 крит. 5 — независимость профилей
# ===========================================================================

func test_req_prf_02_c5_ftp_change_in_a_does_not_change_b_in_memory_and_on_disk() -> void:
	var a := _add("A", 200)
	var b := _add("B", 200)
	var edit := a.duplicate_profile()
	edit.ftp_w = 300
	assert_eq(_repo.save(edit), [])
	assert_eq(_repo.get_by_id(a.id).ftp_w, 300)
	assert_eq(_repo.get_by_id(b.id).ftp_w, 200)
	var again := ProfileRepository.new(_dir)
	assert_eq(again.get_by_id(a.id).ftp_w, 300)
	assert_eq(again.get_by_id(b.id).ftp_w, 200)
	assert_eq(again.get_by_id(a.id).power_zone_of(230), 3, "зоны A от 300 Вт")
	assert_eq(again.get_by_id(b.id).power_zone_of(230), 5, "зоны B от 200 Вт")


func test_req_prf_02_c5_duplicate_profile_is_independent_including_zones() -> void:
	var a := Profile.create("A")
	a.power_zones = PowerZones.custom(200, [50.0, 70.0, 85.0, 100.0, 115.0, 140.0])
	var copy := a.duplicate_profile()
	copy.ftp_w = 400
	copy.power_zones.boundaries_pct[0] = 10.0
	copy.name = "Other"
	assert_eq(a.ftp_w, 200)
	assert_eq(a.power_zones.boundaries_pct[0], 50.0)
	assert_eq(a.name, "A")
	assert_eq(copy.id, a.id, "копия для редактирования сохраняет id")


func test_req_prf_02_c5_default_zone_objects_are_not_shared_between_profiles() -> void:
	var a := Profile.create("A")
	var b := Profile.create("B")
	a.ftp_w = 200
	b.ftp_w = 300
	var za := a.effective_power_zones()
	za.boundaries_pct[0] = 1.0
	assert_eq(b.effective_power_zones().boundaries_pct[0], 55.0, "границы по умолчанию не разделяются между профилями")
	assert_eq(a.effective_power_zones().boundaries_pct[0], 55.0, "и не мутируются через возвращённый объект")


# ===========================================================================
# REQ-PRF-02 крит. 6 — таблица зон при FTP 200
# ===========================================================================

func test_req_prf_02_c6_power_zone_table_at_ftp_200_via_profile() -> void:
	var p := Profile.create("Z")
	p.ftp_w = 200
	var table := {110: 1, 111: 2, 150: 2, 151: 3, 180: 3, 181: 4, 210: 4, 211: 5, 240: 5, 241: 6, 300: 6, 301: 7}
	for watts in table.keys():
		assert_eq(p.power_zone_of(watts), table[watts], "%d Вт" % watts)
	assert_eq(p.power_zone_of(0), 1, "0 Вт → Z1")
	assert_eq(p.effective_power_zones().boundaries_pct, [55.0, 75.0, 90.0, 105.0, 120.0, 150.0], "Coggan по умолчанию")


func test_req_prf_02_c6_table_holds_after_save_and_reload() -> void:
	var p := _add("Z", 200)
	var again := ProfileRepository.new(_dir).get_by_id(p.id)
	assert_eq(again.power_zone_of(110), 1)
	assert_eq(again.power_zone_of(111), 2)
	assert_eq(again.power_zone_of(300), 6)
	assert_eq(again.power_zone_of(301), 7)


func test_req_prf_02_c6_custom_power_zones_are_recomputed_from_profile_ftp() -> void:
	var p := Profile.create("Z")
	p.ftp_w = 200
	p.power_zones = PowerZones.custom(999, [50.0, 100.0]) # ftp внутри объекта намеренно «чужой»
	assert_eq(p.power_zone_of(100), 1, "границы от FTP профиля: 50 %% от 200 = 100 → Z1")
	assert_eq(p.power_zone_of(101), 2)
	assert_eq(p.power_zone_of(200), 2)
	assert_eq(p.power_zone_of(201), 3)
	p.ftp_w = 400
	assert_eq(p.power_zone_of(201), 2, "смена FTP сдвигает границы")


# ===========================================================================
# REQ-NFR-06 крит. 1 — платформенные вызовы только в ble_* и secure_store*
# ===========================================================================

func test_req_nfr_06_c1_os_calls_only_in_ble_and_secure_store() -> void:
	var offenders: Array[String] = []
	# Ровно то, что перечисляет критерий: OS.get_name(), OS.has_feature() и ветвления по платформе.
	var regex := RegEx.create_from_string(
		"OS\\.get_name\\(|OS\\.has_feature\\(|\\\"(macos|macOS|ios|iOS|android|Android|linux|Linux|windows|Windows|web|Web)\\\"")
	_scan_src("res://src", regex, offenders)
	assert_eq(offenders, [], "платформенные вызовы вне разрешённых файлов: %s" % str(offenders))


func _scan_src(dir_path: String, regex: RegEx, offenders: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var name: String = dir.get_next()
	while name != "":
		var full: String = dir_path.path_join(name)
		if dir.current_is_dir():
			if not name.begins_with("."):
				_scan_src(full, regex, offenders)
		elif name.ends_with(".gd"):
			var allowed: bool = full.begins_with("res://src/storage/secure_store") \
				or full.get_file().begins_with("ble_") and full.begins_with("res://src/devices/")
			if not allowed:
				var line_no: int = 0
				for line in FileAccess.get_file_as_string(full).split("\n"):
					line_no += 1
					if line.strip_edges().begins_with("#"):
						continue
					if regex.search(line) != null:
						offenders.append("%s:%d" % [full, line_no])
		name = dir.get_next()
	dir.list_dir_end()
