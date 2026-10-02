extends GutTest
## Тесты реестра запомненных устройств (REQ-PRF-04 крит. 2–4, REQ-PRF-01 крит. 4, REQ-DEV-06 крит. 1).

const A: String = "aaaaaaaa-0000-4000-8000-000000000001"
const B: String = "bbbbbbbb-0000-4000-8000-000000000002"

var _dir: String
var _dev: RememberedDevices
var _changes: int = 0


func before_each() -> void:
	_dir = "user://test_devices_%d_%d/" % [Time.get_ticks_usec(), randi() % 100000]
	_changes = 0
	_dev = _open()


func after_each() -> void:
	_remove_tree(ProjectSettings.globalize_path(_dir))
	assert_false(DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(_dir)))


func _open() -> RememberedDevices:
	var d := RememberedDevices.new(_dir)
	d.changed.connect(func() -> void: _changes += 1)
	return d


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


func _hr(id: String = "hr-1", name: String = "Garmin HRM") -> Dictionary:
	return RememberedDevices.make_device(id, name, RememberedDevices.KIND_HR)


func _trainer() -> Dictionary:
	return RememberedDevices.make_device("neo-1", "Tacx Neo", RememberedDevices.KIND_TRAINER)


func test_make_device_fills_defaults() -> void:
	var d := RememberedDevices.make_device("x", "X", RememberedDevices.KIND_CADENCE)
	assert_eq(d["id"], "x")
	assert_eq(d["kind"], "cadence")
	assert_true(d["auto_connect"])
	assert_gt(int(d["last_seen_at"]), 0)
	assert_true(RememberedDevices.is_valid_device(d))
	assert_false(RememberedDevices.is_valid_device({"id": "", "kind": "hr"}))
	assert_false(RememberedDevices.is_valid_device({"id": "x", "kind": "toaster"}))


func test_empty_registry() -> void:
	assert_eq(_dev.list(A), [])
	assert_eq(_dev.trainer(), {})
	assert_false(_dev.has_trainer())
	assert_false(_dev.has_profile_devices(A))


func test_remember_sensor_stores_it_in_profile_file() -> void:
	assert_true(_dev.remember(A, _hr()))
	assert_eq(_dev.sensors(A).size(), 1)
	assert_eq(_dev.sensors(A)[0]["name"], "Garmin HRM")
	assert_true(FileAccess.file_exists(_dev.profile_file_path(A)))
	assert_eq(_changes, 1)


func test_sensor_of_profile_a_is_not_visible_in_profile_b() -> void:
	_dev.remember(A, _hr())
	assert_eq(_dev.list(B), [], "REQ-PRF-04 крит. 2")
	assert_eq(_dev.auto_connect_candidates(B), [])
	assert_eq(_dev.auto_connect_candidates(A).size(), 1)


func test_trainer_is_shared_across_profiles() -> void:
	assert_true(_dev.remember(A, _trainer()))
	assert_eq(_dev.trainer()["id"], "neo-1")
	assert_eq(_dev.list(B).size(), 1, "REQ-PRF-04 крит. 3: станок виден и в B")
	assert_eq(_dev.list(B)[0]["kind"], "trainer")
	assert_eq(_dev.auto_connect_candidates(B)[0]["id"], "neo-1")
	assert_false(_dev.has_profile_devices(A), "станок не попал в файл профиля")
	assert_true(FileAccess.file_exists(_dev.trainer_file_path()))


func test_set_trainer_forces_kind_and_replaces_previous() -> void:
	_dev.set_trainer({"id": "old", "name": "Old", "kind": "hr"})
	assert_eq(_dev.trainer()["kind"], "trainer")
	_dev.set_trainer(_trainer())
	assert_eq(_dev.trainer()["id"], "neo-1")
	assert_false(_dev.set_trainer({"id": ""}))


func test_list_puts_trainer_first_then_sensors_by_name() -> void:
	_dev.remember(A, _hr("hr-1", "Wahoo Tickr"))
	_dev.remember(A, RememberedDevices.make_device("cad-1", "Garmin Cadence", RememberedDevices.KIND_CADENCE))
	_dev.set_trainer(_trainer())
	var names: Array[String] = []
	for d in _dev.list(A):
		names.append(str(d["name"]))
	assert_eq(names, ["Tacx Neo", "Garmin Cadence", "Wahoo Tickr"])


func test_remember_same_id_replaces_record() -> void:
	_dev.remember(A, _hr("hr-1", "Old name"))
	_dev.remember(A, _hr("hr-1", "New name"))
	assert_eq(_dev.sensors(A).size(), 1)
	assert_eq(_dev.sensors(A)[0]["name"], "New name")


func test_remember_rejects_invalid_records() -> void:
	assert_false(_dev.remember(A, {"id": "", "kind": "hr"}))
	assert_false(_dev.remember(A, {"id": "x", "kind": "unknown"}))
	assert_false(_dev.remember("", _hr()), "датчику нужен профиль")
	assert_eq(_dev.list(A), [])
	assert_eq(_changes, 0)


func test_forget_sensor_removes_only_it() -> void:
	_dev.remember(A, _hr("hr-1"))
	_dev.remember(A, _hr("hr-2", "Polar"))
	_dev.remember(B, _hr("hr-1"))
	assert_true(_dev.forget(A, "hr-1"))
	assert_eq(_dev.sensors(A).size(), 1)
	assert_eq(_dev.sensors(A)[0]["id"], "hr-2")
	assert_eq(_dev.sensors(B).size(), 1, "тот же id в другом профиле не тронут")
	assert_false(_dev.forget(A, "nope"))


func test_forget_trainer_by_id_clears_shared_trainer() -> void:
	_dev.set_trainer(_trainer())
	assert_true(_dev.forget(A, "neo-1"))
	assert_false(_dev.has_trainer())
	assert_false(FileAccess.file_exists(_dev.trainer_file_path()))
	assert_eq(_dev.list(B), [])


func test_persists_between_instances() -> void:
	_dev.remember(A, _hr())
	_dev.set_trainer(_trainer())
	_dev.set_auto_connect(A, "hr-1", false)
	var again := RememberedDevices.new(_dir)
	assert_eq(again.trainer()["name"], "Tacx Neo")
	assert_eq(again.sensors(A).size(), 1)
	assert_false(again.sensors(A)[0]["auto_connect"])
	assert_eq(again.auto_connect_candidates(A).size(), 1, "только станок")


func test_mark_seen_and_set_auto_connect() -> void:
	_dev.remember(A, _hr())
	assert_true(_dev.mark_seen(A, "hr-1", 1700000000))
	assert_eq(int(_dev.find(A, "hr-1")["last_seen_at"]), 1700000000)
	assert_true(_dev.set_auto_connect(A, "hr-1", false))
	assert_false(_dev.find(A, "hr-1")["auto_connect"])
	assert_false(_dev.mark_seen(A, "ghost"))
	assert_false(_dev.set_auto_connect(A, "ghost", true))
	assert_eq(_dev.find(B, "hr-1"), {})


func test_returned_records_are_copies() -> void:
	_dev.remember(A, _hr())
	_dev.set_trainer(_trainer())
	var t := _dev.trainer()
	t["name"] = "hacked"
	var s := _dev.sensors(A)
	s[0]["name"] = "hacked"
	assert_eq(_dev.trainer()["name"], "Tacx Neo")
	assert_eq(_dev.sensors(A)[0]["name"], "Garmin HRM")


func test_delete_profile_devices_removes_file_but_keeps_trainer() -> void:
	_dev.remember(A, _hr())
	_dev.remember(B, _hr("hr-9", "B's strap"))
	_dev.set_trainer(_trainer())
	_dev.delete_profile_devices(A)
	assert_false(_dev.has_profile_devices(A))
	assert_eq(_dev.sensors(A), [])
	assert_eq(_dev.sensors(B).size(), 1)
	assert_true(_dev.has_trainer(), "REQ-PRF-04 крит. 4")
	assert_eq(RememberedDevices.new(_dir).trainer()["id"], "neo-1")


func test_cascade_from_profile_repository_delete() -> void:
	var repo := ProfileRepository.new(_dir + "profiles/")
	var a := repo.create("Алиса")
	var b := repo.create("Боб")
	_dev.attach_to_profiles(repo)
	_dev.remember(a.id, _hr())
	_dev.remember(b.id, _hr("hr-2", "Polar"))
	_dev.set_trainer(_trainer())
	assert_eq(repo.delete(b.id), "")
	assert_false(_dev.has_profile_devices(b.id), "REQ-PRF-01 крит. 4: датчики удалённого профиля стёрты")
	assert_eq(_dev.sensors(a.id).size(), 1)
	assert_true(_dev.has_trainer(), "общий станок остался")
	assert_eq(repo.delete(a.id), ProfileRepository.ERR_LAST_PROFILE)
	assert_eq(_dev.sensors(a.id).size(), 1, "отказ удаления ничего не трогает")


func test_corrupted_files_are_ignored() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_dir))
	for path in [_dev.trainer_file_path(), _dev.profile_file_path(A)]:
		var f := FileAccess.open(path, FileAccess.WRITE)
		f.store_string("not json {")
		f.close()
	var broken := RememberedDevices.new(_dir)
	assert_false(broken.has_trainer())
	assert_eq(broken.sensors(A), [])
	assert_true(broken.remember(A, _hr()), "после повреждения можно писать дальше")
