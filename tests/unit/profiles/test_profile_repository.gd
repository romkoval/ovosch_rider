extends GutTest
## Тесты ProfileRepository (REQ-PRF-01 крит. 1, 2, 5, 6; REQ-PRF-02 крит. 5).

var _dir: String
var _repo: ProfileRepository
var _saved: Array[String] = []
var _deleted: Array[String] = []
var _active_changes: Array[String] = []


func before_each() -> void:
	_dir = "user://test_profiles_%d_%d/" % [Time.get_ticks_usec(), randi() % 100000]
	_saved = []
	_deleted = []
	_active_changes = []
	_repo = _open()


func after_each() -> void:
	_remove_tree(ProjectSettings.globalize_path(_dir))
	assert_false(DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(_dir)), "временный каталог удалён")


func _open() -> ProfileRepository:
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
	var errors := _repo.save(p)
	assert_eq(errors, [], "профиль %s сохранён" % name)
	return p


func test_empty_repository() -> void:
	assert_eq(_repo.list().size(), 0)
	assert_eq(_repo.count(), 0)
	assert_eq(_repo.active_profile_id, "")
	assert_null(_repo.get_active())
	assert_false(FileAccess.file_exists(_repo.file_path()), "пустое хранилище ничего не пишет")


func test_first_saved_profile_becomes_active_and_emits_signals() -> void:
	var p := _add("Даша")
	assert_eq(_repo.count(), 1)
	assert_eq(_repo.active_profile_id, p.id)
	assert_eq(_repo.get_active().name, "Даша")
	assert_eq(_saved, [p.id])
	assert_eq(_active_changes, [p.id])
	assert_true(FileAccess.file_exists(_repo.file_path()))


func test_invalid_profile_is_not_saved() -> void:
	var p := Profile.create("   ")
	var errors := _repo.save(p)
	assert_has(errors, Profile.ERR_NAME_EMPTY, "REQ-PRF-01 крит. 1")
	assert_eq(_repo.count(), 0)
	assert_eq(_repo.last_errors, errors)
	assert_eq(_saved, [])
	assert_false(FileAccess.file_exists(_repo.file_path()))


func test_duplicate_name_is_rejected_case_insensitively() -> void:
	_add("Даша")
	var dup := Profile.create("  даша ")
	assert_eq(_repo.save(dup), [ProfileRepository.ERR_NAME_NOT_UNIQUE], "REQ-PRF-01 крит. 2")
	assert_eq(_repo.count(), 1)
	assert_false(_repo.is_name_available("ДАША"))
	assert_true(_repo.is_name_available("Боб"))


func test_renaming_profile_to_its_own_name_is_allowed() -> void:
	var p := _add("Даша")
	p.name = "даша"
	assert_eq(_repo.save(p), [])
	assert_eq(_repo.get_by_id(p.id).name, "даша")
	assert_true(_repo.is_name_available("Даша", p.id))


func test_create_helper_returns_profile_or_null() -> void:
	var a := _repo.create("Алиса")
	assert_not_null(a)
	assert_eq(_repo.get_by_id(a.id).name, "Алиса")
	var dup := _repo.create("алиса")
	assert_null(dup)
	assert_eq(_repo.last_errors, [ProfileRepository.ERR_NAME_NOT_UNIQUE])
	assert_null(_repo.create(""))
	assert_has(_repo.last_errors, Profile.ERR_NAME_EMPTY)


func test_profiles_and_active_id_persist_between_instances() -> void:
	var a := _add("Алиса", 180)
	var b := _add("Боб", 260)
	b.max_hr = 185
	b.weight_kg = 82.4
	_repo.save(b)
	_repo.active_profile_id = b.id
	var again := ProfileRepository.new(_dir)
	assert_eq(again.count(), 2, "REQ-PRF-01 крит. 6")
	assert_eq(again.active_profile_id, b.id)
	assert_eq(again.get_by_id(a.id).ftp_w, 180)
	var b2 := again.get_by_id(b.id)
	assert_eq(b2.ftp_w, 260)
	assert_eq(b2.max_hr, 185)
	assert_almost_eq(b2.weight_kg, 82.4, 1e-9)
	assert_eq(b2.name, "Боб")


func test_update_existing_profile_keeps_count() -> void:
	var p := _add("Даша", 200)
	p.ftp_w = 230
	assert_eq(_repo.save(p), [])
	assert_eq(_repo.count(), 1)
	assert_eq(ProfileRepository.new(_dir).get_by_id(p.id).ftp_w, 230)


func test_ftp_change_in_one_profile_does_not_affect_another() -> void:
	var a := _add("Алиса", 200)
	var b := _add("Боб", 250)
	a.ftp_w = 300
	_repo.save(a)
	var again := ProfileRepository.new(_dir)
	assert_eq(again.get_by_id(a.id).ftp_w, 300)
	assert_eq(again.get_by_id(b.id).ftp_w, 250, "REQ-PRF-02 крит. 5")
	assert_eq(again.get_by_id(b.id).power_zone_of(260), 4)
	assert_eq(again.get_by_id(a.id).power_zone_of(260), 3)


func test_cannot_delete_last_profile() -> void:
	var p := _add("Даша")
	assert_eq(_repo.delete(p.id), ProfileRepository.ERR_LAST_PROFILE, "REQ-PRF-01 крит. 5")
	assert_eq(_repo.count(), 1)
	assert_eq(_deleted, [])
	assert_eq(ProfileRepository.new(_dir).count(), 1)


func test_delete_unknown_profile_reports_not_found() -> void:
	_add("Даша")
	assert_eq(_repo.delete("nope"), ProfileRepository.ERR_PROFILE_NOT_FOUND)
	assert_eq(_repo.last_errors, [ProfileRepository.ERR_PROFILE_NOT_FOUND])


func test_delete_non_active_profile_runs_hooks_then_signal_and_persists() -> void:
	var a := _add("Алиса")
	var b := _add("Боб")
	var hook_calls: Array[String] = []
	_repo.add_on_delete_hook(func(id: String) -> void:
		hook_calls.append(id)
		assert_eq(_deleted, [], "хук вызывается до сигнала"))
	assert_eq(_repo.delete(b.id), "")
	assert_eq(hook_calls, [b.id])
	assert_eq(_deleted, [b.id])
	assert_eq(_repo.count(), 1)
	assert_eq(_repo.active_profile_id, a.id, "активный не менялся")
	assert_null(ProfileRepository.new(_dir).get_by_id(b.id))


func test_delete_active_profile_switches_active_to_remaining() -> void:
	var a := _add("Алиса")
	var b := _add("Боб")
	_repo.active_profile_id = b.id
	_active_changes = []
	assert_eq(_repo.delete(b.id), "")
	assert_eq(_repo.active_profile_id, a.id)
	assert_eq(_active_changes, [a.id])
	assert_eq(ProfileRepository.new(_dir).active_profile_id, a.id)


func test_set_active_validates_and_persists() -> void:
	var a := _add("Алиса")
	var b := _add("Боб")
	_repo.active_profile_id = "missing"
	assert_push_error("не найден", "ошибка вызывающего фиксируется push_error")
	assert_eq(_repo.active_profile_id, a.id, "несуществующий id игнорируется")
	assert_eq(_repo.last_errors, [ProfileRepository.ERR_PROFILE_NOT_FOUND])
	_repo.active_profile_id = b.id
	assert_eq(_repo.get_active().id, b.id)
	assert_eq(ProfileRepository.new(_dir).active_profile_id, b.id)


func test_list_is_ordered_by_creation() -> void:
	var a := _add("Яна")
	var b := _add("Алиса")
	var c := _add("Миша")
	a.created_at = 100
	b.created_at = 300
	c.created_at = 200
	_repo.save(a)
	_repo.save(b)
	_repo.save(c)
	var names: Array[String] = []
	for p in ProfileRepository.new(_dir).list():
		names.append(p.name)
	assert_eq(names, ["Яна", "Миша", "Алиса"])


func test_corrupted_file_yields_empty_repository_without_crash() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_dir))
	var f := FileAccess.open(_dir + ProfileRepository.FILE_NAME, FileAccess.WRITE)
	f.store_string("{ this is not json")
	f.close()
	var broken := ProfileRepository.new(_dir)
	assert_eq(broken.count(), 0)
	assert_eq(broken.active_profile_id, "")
	assert_not_null(broken.create("Новый"), "после повреждения можно продолжать работу")


func test_missing_active_id_in_file_falls_back_to_first_profile() -> void:
	var a := _add("Алиса")
	_add("Боб")
	var f := FileAccess.open(_repo.file_path(), FileAccess.READ)
	var data: Dictionary = JSON.parse_string(f.get_as_text())
	f.close()
	data["active_profile_id"] = "ghost"
	f = FileAccess.open(_repo.file_path(), FileAccess.WRITE)
	f.store_string(JSON.stringify(data))
	f.close()
	assert_eq(ProfileRepository.new(_dir).active_profile_id, a.id)
