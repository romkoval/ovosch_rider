extends GutTest
## Устойчивость профилей (финальное ревью): атомарная запись `profiles.json`, повреждённый
## файл откладывается в `.corrupt`, подписка `RememberedDevices` на удаление профилей
## связанным методом, `delete`/`set_active` не меняют память при сбое записи
## (REQ-PRF-01 крит. 4, 6; REQ-PRF-04 крит. 1).

var _dir: String


func before_each() -> void:
	_dir = "user://test_profiles_hardening_%d_%d/" % [Time.get_ticks_usec(), randi() % 100000]


func after_each() -> void:
	AtomicFile.simulate_write_error_prefix = ""
	var abs := ProjectSettings.globalize_path(_dir)
	var d := DirAccess.open(abs)
	if d != null:
		for f in d.get_files():
			DirAccess.remove_absolute(abs.path_join(f))
		DirAccess.remove_absolute(abs)


func _write(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_dir))
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _corrupt_backups() -> Array[String]:
	var out: Array[String] = []
	var d := DirAccess.open(ProjectSettings.globalize_path(_dir))
	if d == null:
		return out
	for f in d.get_files():
		if f.begins_with(ProfileRepository.FILE_NAME + ".") and f.ends_with(ProfileRepository.CORRUPT_SUFFIX):
			out.append(f)
	return out


func test_profiles_json_write_error_keeps_previous_file() -> void:
	var repo := ProfileRepository.new(_dir)
	assert_not_null(repo.create("Аня"))
	var before := FileAccess.get_file_as_string(repo.file_path())
	AtomicFile.simulate_write_error_prefix = repo.file_path()
	var p := Profile.create("Борис")
	var errors := repo.save(p)
	assert_push_error("AtomicFile")
	assert_push_error("ProfileRepository")
	assert_has(errors, ProfileRepository.ERR_STORAGE_WRITE_FAILED, "ошибка записи видна вызывающему")
	assert_eq(FileAccess.get_file_as_string(repo.file_path()), before, "прежний profiles.json цел")
	assert_false(FileAccess.file_exists(AtomicFile.tmp_path(repo.file_path())), "временный файл удалён")
	AtomicFile.simulate_write_error_prefix = ""
	assert_eq(ProfileRepository.new(_dir).count(), 1)


func test_corrupted_file_is_moved_to_corrupt_backup_not_overwritten() -> void:
	var garbage := "{ \"profiles\": [ обрыв"
	_write(_dir + ProfileRepository.FILE_NAME, garbage)
	var repo := ProfileRepository.new(_dir)
	assert_push_warning("повреждён")
	assert_eq(repo.count(), 0)
	var backups := _corrupt_backups()
	assert_eq(backups.size(), 1, "повреждённый файл отложен: %s" % str(backups))
	if backups.size() == 1:
		assert_eq(FileAccess.get_file_as_string(_dir + backups[0]), garbage, "содержимое сохранено как есть")
	assert_false(FileAccess.file_exists(repo.file_path()), "под основным именем повреждённого файла больше нет")
	assert_not_null(repo.create("Новый"), "работа продолжается")
	assert_eq(ProfileRepository.new(_dir).count(), 1)
	assert_eq(_corrupt_backups().size(), 1, "запись нового файла не затронула копию")


func test_second_corruption_gets_its_own_backup() -> void:
	_write(_dir + ProfileRepository.FILE_NAME, "[1, 2]")
	ProfileRepository.new(_dir)
	_write(_dir + ProfileRepository.FILE_NAME, "{ broken")
	ProfileRepository.new(_dir)
	assert_push_warning("повреждён")
	assert_eq(_corrupt_backups().size(), 2, "имена копий не перезаписывают друг друга")


func test_remembered_devices_attach_is_idempotent_and_does_not_retain_registry() -> void:
	var repo := ProfileRepository.new(_dir + "p/")
	var devices := RememberedDevices.new(_dir + "d/")
	devices.attach_to_profiles(repo)
	devices.attach_to_profiles(repo)
	assert_eq(repo.profile_deleted.get_connections().size(), 1, "повторная подписка — no-op")
	devices.detach_from_profiles(repo)
	assert_eq(repo.profile_deleted.get_connections().size(), 0)
	devices.attach_to_profiles(repo)
	var ref: WeakRef = weakref(devices)
	devices = null
	assert_null(ref.get_ref(), "подписка не удерживает реестр (нет лямбды с self)")
	var a := repo.create("A")
	repo.create("B")
	assert_eq(repo.delete(a.id), "", "удаление после освобождения реестра не падает")
	_remove_sub(_dir + "p/")
	_remove_sub(_dir + "d/")


func _remove_sub(path: String) -> void:
	var abs := ProjectSettings.globalize_path(path)
	var d := DirAccess.open(abs)
	if d == null:
		return
	for f in d.get_files():
		DirAccess.remove_absolute(abs.path_join(f))
	DirAccess.remove_absolute(abs)


# ---------------------------------------------------------------------------
# delete / set_active: сбой записи не проглатывается (финальное ревью)
# ---------------------------------------------------------------------------

func test_delete_write_error_returns_code_and_keeps_state_and_cascade() -> void:
	var repo := ProfileRepository.new(_dir)
	var a := repo.create("Аня")
	var b := repo.create("Борис")
	repo.active_profile_id = a.id
	var before := FileAccess.get_file_as_string(repo.file_path())
	var hook_calls: Array[String] = []
	var deleted: Array[String] = []
	var active_changes: Array[String] = []
	repo.add_on_delete_hook(func(id: String) -> void: hook_calls.append(id))
	repo.profile_deleted.connect(func(id: String) -> void: deleted.append(id))
	repo.active_profile_changed.connect(func(id: String) -> void: active_changes.append(id))
	AtomicFile.simulate_write_error_prefix = repo.file_path()
	var err := repo.delete(a.id)
	assert_push_error("AtomicFile")
	assert_push_error("ProfileRepository")
	assert_eq(err, ProfileRepository.ERR_STORAGE_WRITE_FAILED, "ошибка записи возвращается")
	assert_eq(repo.last_errors, [ProfileRepository.ERR_STORAGE_WRITE_FAILED] as Array[String])
	assert_eq(repo.count(), 2, "профиль остался в памяти")
	assert_not_null(repo.get_by_id(a.id))
	assert_eq(repo.active_profile_id, a.id, "активный не сменился")
	assert_eq(hook_calls, [] as Array[String], "каскад не запущен — секреты и заезды целы")
	assert_eq(deleted, [] as Array[String])
	assert_eq(active_changes, [] as Array[String])
	assert_eq(FileAccess.get_file_as_string(repo.file_path()), before, "файл прежний")
	AtomicFile.simulate_write_error_prefix = ""
	assert_eq(repo.delete(a.id), "", "после устранения сбоя удаление проходит")
	assert_eq(repo.active_profile_id, b.id)
	assert_eq(hook_calls, [a.id] as Array[String])
	assert_eq(ProfileRepository.new(_dir).count(), 1)


func test_set_active_write_error_returns_code_and_keeps_active() -> void:
	var repo := ProfileRepository.new(_dir)
	var a := repo.create("Аня")
	var b := repo.create("Борис")
	assert_eq(repo.active_profile_id, a.id)
	var changes: Array[String] = []
	repo.active_profile_changed.connect(func(id: String) -> void: changes.append(id))
	AtomicFile.simulate_write_error_prefix = repo.file_path()
	assert_eq(repo.set_active(b.id), ProfileRepository.ERR_STORAGE_WRITE_FAILED)
	assert_push_error("AtomicFile")
	assert_push_error("ProfileRepository")
	assert_eq(repo.active_profile_id, a.id, "в памяти прежний активный")
	assert_eq(repo.last_errors, [ProfileRepository.ERR_STORAGE_WRITE_FAILED] as Array[String])
	assert_eq(changes, [] as Array[String], "без active_profile_changed")
	# Присваивание свойства — тот же путь.
	repo.active_profile_id = b.id
	assert_push_error("AtomicFile")
	assert_push_error("ProfileRepository")
	assert_eq(repo.active_profile_id, a.id)
	AtomicFile.simulate_write_error_prefix = ""
	assert_eq(ProfileRepository.new(_dir).active_profile_id, a.id, "на диске прежний активный")
	assert_eq(repo.set_active(b.id), "")
	assert_eq(changes, [b.id] as Array[String])
	assert_eq(ProfileRepository.new(_dir).active_profile_id, b.id)


func test_set_active_unknown_id_returns_not_found() -> void:
	var repo := ProfileRepository.new(_dir)
	var a := repo.create("Аня")
	assert_eq(repo.set_active("nope"), ProfileRepository.ERR_PROFILE_NOT_FOUND)
	assert_push_error("не найден")
	assert_eq(repo.active_profile_id, a.id)
	assert_eq(repo.set_active(a.id), "", "уже активный — успех без записи")
