extends GutTest
## Устойчивость хранилищ к сбоям записи (финальное ревью): `AtomicFile`, атомарная запись
## `samples.bin`/`meta.json`, атомарная запись и права файла секретов, откат в памяти,
## `SecureStore.loaded_ok()/last_error()/reset_store()`, подписка на удаление профилей
## связанным методом (REQ-LOC-01 крит. 5, REQ-LOC-07 крит. 1, REQ-NFR-05 крит. 1–3, REQ-PRF-03 крит. 1).

const PROFILE: String = "profile-s"
const PASSWORD: String = "hardening-password"
const KEY: String = "profile-s/strava/access_token"

var _dir: String


func before_each() -> void:
	_dir = "user://test_storage_hardening_%d_%d/" % [Time.get_ticks_usec(), randi() % 100000]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_dir))


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


# ---------------------------------------------------------------------------
# AtomicFile
# ---------------------------------------------------------------------------

func test_atomic_file_writes_and_leaves_no_tmp() -> void:
	var path := _dir + "a.json"
	assert_eq(AtomicFile.write_text(path, "first"), OK)
	assert_eq(AtomicFile.write_text(path, "second"), OK)
	assert_eq(FileAccess.get_file_as_string(path), "second")
	assert_false(FileAccess.file_exists(AtomicFile.tmp_path(path)))


func test_atomic_file_write_error_keeps_previous_content() -> void:
	var path := _dir + "b.json"
	assert_eq(AtomicFile.write_text(path, "old"), OK)
	AtomicFile.simulate_write_error_prefix = path
	assert_eq(AtomicFile.write_text(path, "new"), ERR_FILE_CANT_WRITE, "ошибка записи доходит до вызывающего с кодом")
	assert_push_error("AtomicFile")
	assert_eq(FileAccess.get_file_as_string(path), "old", "прежний файл не тронут")
	assert_false(FileAccess.file_exists(AtomicFile.tmp_path(path)), "временный файл удалён")


func test_atomic_file_unopenable_tmp_keeps_previous_content() -> void:
	var path := _dir + "c.json"
	assert_eq(AtomicFile.write_text(path, "old"), OK)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(AtomicFile.tmp_path(path)))
	assert_ne(AtomicFile.write_text(path, "new"), OK)
	assert_push_error("AtomicFile")
	assert_eq(FileAccess.get_file_as_string(path), "old")


# ---------------------------------------------------------------------------
# FileRideRepository: samples.bin и meta.json (п. 5)
# ---------------------------------------------------------------------------

func _stream(n: int) -> SampleStream:
	var s := SampleStream.new()
	s.speed_source = Ride.SPEED_SOURCE_TRAINER_LEGACY
	for i in n:
		s.append(i, TrainerSample.full(float(i + 1), 200 + i, 90, 30.0), 140, 210, 0, true, -1.0, {})
	return s


func _ride(n: int) -> Ride:
	var r := Ride.new()
	r.id = Ride.generate_id(1700000000)
	r.profile_id = PROFILE
	r.started_at_unix = 1700000000
	r.name = "Atomic"
	r.samples = _stream(n)
	return r


func test_samples_bin_rewrite_is_atomic() -> void:
	var repo := FileRideRepository.new(_dir)
	var ride := _ride(5)
	assert_ne(repo.save(ride), "")
	var samples_path := ProjectSettings.globalize_path(_dir).path_join(PROFILE).path_join(ride.id).path_join(FileRideRepository.SAMPLES_FILE)
	var before := FileAccess.get_file_as_bytes(samples_path)
	assert_eq(before.size(), FileRideRepository.SAMPLES_HEADER_SIZE + 5 * FileRideRepository.SAMPLES_RECORD_SIZE)
	ride.samples = _stream(9)
	AtomicFile.simulate_write_error_prefix = samples_path
	assert_eq(repo.save(ride), "", "сбой записи потока — save сообщает об ошибке")
	assert_push_error("AtomicFile")
	assert_eq(FileAccess.get_file_as_bytes(samples_path), before, "прежний samples.bin цел")
	assert_false(FileAccess.file_exists(AtomicFile.tmp_path(samples_path)))
	AtomicFile.simulate_write_error_prefix = ""
	assert_eq(FileRideRepository.new(_dir).get_ride(ride.id).samples.size(), 5, "читается прежний поток")


func test_meta_write_error_is_checked_before_rename() -> void:
	var repo := FileRideRepository.new(_dir)
	var ride := _ride(3)
	assert_ne(repo.save(ride), "")
	var meta_path := ProjectSettings.globalize_path(_dir).path_join(PROFILE).path_join(ride.id).path_join(FileRideRepository.META_FILE)
	var before := FileAccess.get_file_as_string(meta_path)
	ride.name = "Renamed"
	AtomicFile.simulate_write_error_prefix = meta_path
	assert_false(repo.save_meta(ride), "ошибка записи meta.json не теряется")
	assert_push_error("AtomicFile")
	assert_eq(FileAccess.get_file_as_string(meta_path), before, "прежний meta.json цел")
	AtomicFile.simulate_write_error_prefix = ""
	assert_eq(FileRideRepository.new(_dir).get_ride(ride.id).name, "Atomic")


# ---------------------------------------------------------------------------
# EncryptedFileSecureStore: атомарность, откат, коды, права (п. 2, 8)
# ---------------------------------------------------------------------------

func test_encrypted_store_write_error_rolls_back_and_reports_code() -> void:
	var store := EncryptedFileSecureStore.new(_dir, PASSWORD)
	assert_true(store.set_secret(KEY, "old-token-value"))
	assert_eq(store.last_error(), OK)
	var before := FileAccess.get_file_as_bytes(store.file_path())
	AtomicFile.simulate_write_error_prefix = store.file_path()
	assert_false(store.set_secret(KEY, "new-token-value"), "сбой записи — set_secret false")
	assert_push_error("AtomicFile")
	assert_eq(store.last_error(), ERR_FILE_CANT_WRITE, "код ошибки доступен вызывающему")
	assert_eq(store.get_secret(KEY), "old-token-value", "память откатилась к диску")
	assert_false(store.delete_secret(KEY), "удаление тоже не теряет ошибку")
	assert_push_error("AtomicFile")
	assert_true(store.has_secret(KEY))
	assert_eq(FileAccess.get_file_as_bytes(store.file_path()), before, "прежний secrets.bin цел")
	assert_false(FileAccess.file_exists(AtomicFile.tmp_path(store.file_path())), "временный файл удалён")
	AtomicFile.simulate_write_error_prefix = ""
	assert_eq(EncryptedFileSecureStore.new(_dir, PASSWORD).get_secret(KEY), "old-token-value")
	assert_true(store.set_secret(KEY, "new-token-value"))
	assert_eq(store.last_error(), OK, "после успешной записи ошибка сброшена")


func test_not_loaded_store_is_visible_and_resettable_through_interface() -> void:
	var first := EncryptedFileSecureStore.new(_dir, PASSWORD)
	assert_true(first.set_secret(KEY, "token-x"))
	var store: SecureStore = EncryptedFileSecureStore.new(_dir, "other-password")
	assert_engine_error("ERR_FILE_CORRUPT", "ядро сообщает о неверном ключе")
	assert_false(store.loaded_ok(), "хранилище не прочитано — видно через SecureStore")
	assert_false(store.set_secret(KEY, "token-y"))
	assert_push_warning("reset_store")
	assert_eq(store.last_error(), ERR_FILE_CORRUPT, "код: хранилище не прочитано")
	store.reset_store()
	assert_true(store.loaded_ok())
	assert_true(store.set_secret(KEY, "token-y"), "после сброса запись работает")
	assert_eq(store.last_error(), OK)


func test_secrets_file_is_0600_and_dir_is_0700() -> void:
	if not SecureStore.owner_only_permissions_supported():
		pending("права 0600/0700 применяются только на Linux и macOS")
		return
	var sub := _dir + "secure/"
	var store := EncryptedFileSecureStore.new(sub, PASSWORD)
	assert_true(store.set_secret(KEY, "token-perm"))
	assert_eq(FileAccess.get_unix_permissions(store.file_path()) & 0x1FF, SecureStore.FILE_MODE_OWNER_ONLY, "secrets.bin — 0600")
	assert_eq(FileAccess.get_unix_permissions(ProjectSettings.globalize_path(sub).trim_suffix("/")) & 0x1FF,
			SecureStore.DIR_MODE_OWNER_ONLY, "каталог — 0700")
	assert_eq(SecureStore.FILE_MODE_OWNER_ONLY, 384, "0600")
	assert_eq(SecureStore.DIR_MODE_OWNER_ONLY, 448, "0700")


func test_existing_secrets_file_permissions_are_tightened_on_load() -> void:
	if not SecureStore.owner_only_permissions_supported():
		pending("только Linux и macOS")
		return
	var store := EncryptedFileSecureStore.new(_dir, PASSWORD)
	assert_true(store.set_secret(KEY, "token-old-install"))
	FileAccess.set_unix_permissions(store.file_path(), 420)  # 0644 — как у прежних версий
	EncryptedFileSecureStore.new(_dir, PASSWORD)
	assert_eq(FileAccess.get_unix_permissions(store.file_path()) & 0x1FF, SecureStore.FILE_MODE_OWNER_ONLY)


# ---------------------------------------------------------------------------
# Подписка на удаление профилей связанным методом (п. 14)
# ---------------------------------------------------------------------------

func test_secure_store_attach_is_idempotent_and_does_not_retain_store() -> void:
	var repo := ProfileRepository.new(_dir + "profiles/")
	var store := MemorySecureStore.new()
	store.attach_to_profiles(repo)
	store.attach_to_profiles(repo)
	assert_eq(repo.profile_deleted.get_connections().size(), 1, "повторная подписка — no-op")
	var a := repo.create("A")
	repo.create("B")
	store.set_secret(SecureStore.key_for(a.id, SecureStore.SERVICE_STRAVA, SecureStore.ITEM_ACCESS_TOKEN), "t")
	assert_eq(repo.delete(a.id), "")
	assert_eq(store.list_keys(a.id + "/"), [] as Array[String], "каскад работает")
	store.detach_from_profiles(repo)
	assert_eq(repo.profile_deleted.get_connections().size(), 0)
	store.attach_to_profiles(repo)
	var ref: WeakRef = weakref(store)
	store = null
	assert_null(ref.get_ref(), "подписка не удерживает хранилище (нет лямбды с self)")


# ---------------------------------------------------------------------------
# Периодический сброс без rename (REQ-LOC-07 крит. 1, 4)
# ---------------------------------------------------------------------------

func _ride_dir_abs(ride: Ride) -> String:
	return ProjectSettings.globalize_path(_dir).path_join(PROFILE).path_join(ride.id)


func _in_progress_ride(n: int) -> Ride:
	var r := _ride(n)
	r.metadata = {"in_progress": true, "elapsed_sec": n, "event_count": 0}
	r.events = [{"type": WorkoutSession.EVENT_START, "at_sec": 0.0, "value": 0}] as Array[Dictionary]
	return r


func test_save_progress_writes_in_place_without_touching_meta_and_index() -> void:
	var repo := FileRideRepository.new(_dir)
	var ride := _in_progress_ride(3)
	assert_ne(repo.save(ride), "")
	var dir := _ride_dir_abs(ride)
	var meta_before := FileAccess.get_file_as_string(dir.path_join(FileRideRepository.META_FILE))
	var index_path := ProjectSettings.globalize_path(_dir).path_join(PROFILE).path_join(FileRideRepository.INDEX_FILE)
	var index_before := FileAccess.get_file_as_string(index_path)
	ride.events.append({"type": WorkoutSession.EVENT_SKIP, "at_sec": 2.0, "value": 0})
	ride.metadata["elapsed_sec"] = 20
	assert_true(repo.save_progress(ride))
	assert_eq(FileAccess.get_file_as_string(dir.path_join(FileRideRepository.META_FILE)), meta_before, "meta.json не переписывается")
	assert_eq(FileAccess.get_file_as_string(index_path), index_before, "index.json не переписывается")
	assert_true(FileAccess.file_exists(dir.path_join(FileRideRepository.PROGRESS_FILE)))
	assert_false(FileAccess.file_exists(AtomicFile.tmp_path(dir.path_join(FileRideRepository.PROGRESS_FILE))), "без временного файла")
	var fresh := FileRideRepository.new(_dir).get_ride(ride.id)
	assert_eq(fresh.events.size(), 2, "читатель видит промежуточную копию")
	assert_eq(int(fresh.metadata["elapsed_sec"]), 20)
	assert_eq(repo.list(PROFILE)[0].ride_id, ride.id, "индекс в памяти обновлён")


func test_save_progress_shorter_content_is_padded_and_readable() -> void:
	var repo := FileRideRepository.new(_dir)
	var ride := _in_progress_ride(3)
	repo.save(ride)
	ride.metadata["note"] = "x".repeat(2000)
	ride.metadata["elapsed_sec"] = 10
	assert_true(repo.save_progress(ride))
	ride.metadata.erase("note")
	ride.metadata["elapsed_sec"] = 20
	assert_true(repo.save_progress(ride))
	var progress := _ride_dir_abs(ride).path_join(FileRideRepository.PROGRESS_FILE)
	assert_gt(FileAccess.get_file_as_bytes(progress).size(), 2000, "файл не укорачивается")
	var fresh := FileRideRepository.new(_dir).get_ride(ride.id)
	assert_eq(int(fresh.metadata["elapsed_sec"]), 20)
	assert_false(fresh.metadata.has("note"))


func test_torn_progress_file_falls_back_to_meta_json() -> void:
	var repo := FileRideRepository.new(_dir)
	var ride := _in_progress_ride(3)
	repo.save(ride)
	ride.metadata["elapsed_sec"] = 30
	repo.save_progress(ride)
	var progress := _ride_dir_abs(ride).path_join(FileRideRepository.PROGRESS_FILE)
	var f := FileAccess.open(progress, FileAccess.READ_WRITE)
	f.seek(5)
	f.store_string("\u0000\u0000обрыв")
	f.close()
	var fresh := FileRideRepository.new(_dir).get_ride(ride.id)
	assert_not_null(fresh, "заезд не теряется")
	assert_eq(int(fresh.metadata["elapsed_sec"]), 3, "используется meta.json")
	var recovered := FileRideRepository.new(_dir).recover_in_progress(PROFILE)
	assert_eq(recovered.size(), 1)


func test_newer_meta_json_wins_and_finish_removes_progress_copy() -> void:
	var repo := FileRideRepository.new(_dir)
	var ride := _in_progress_ride(3)
	repo.save(ride)
	ride.metadata["elapsed_sec"] = 10
	repo.save_progress(ride)
	ride.events.append({"type": WorkoutSession.EVENT_PAUSE, "at_sec": 10.0, "value": 0})
	ride.metadata["elapsed_sec"] = 10
	assert_true(repo.save_meta(ride), "пауза — атомарная запись meta.json")
	var dir := _ride_dir_abs(ride)
	assert_false(FileAccess.file_exists(dir.path_join(FileRideRepository.PROGRESS_FILE)), "копия удалена после полной записи")
	assert_eq(FileRideRepository.new(_dir).get_ride(ride.id).events.size(), 2)
	ride.metadata["elapsed_sec"] = 20
	repo.save_progress(ride)
	ride.metadata["in_progress"] = false
	assert_ne(repo.save(ride), "")
	assert_false(FileAccess.file_exists(dir.path_join(FileRideRepository.PROGRESS_FILE)))
	var fresh := FileRideRepository.new(_dir)
	assert_false(fresh.get_ride(ride.id).is_in_progress(), "завершённый заезд не перекрывается копией")
	assert_false(fresh.list(PROFILE)[0].in_progress)


func test_recorder_periodic_flush_does_not_rewrite_meta_or_index() -> void:
	var repo := FileRideRepository.new(_dir)
	var p := Profile.create("Rec")
	p.id = PROFILE
	var t := FakeTrainer.new(7)
	t.connect_delay_sec = 0.0
	t.connect_device("fake-hardening")
	var s := WorkoutSession.new(Workout.make("P", [WorkoutStep.watts(120, 150.0)] as Array[WorkoutStep], "zwo"), t, 200, 1.0, 70.0)
	var rec := RideRecorder.new(repo, p, s)
	s.start()
	var dir := ProjectSettings.globalize_path(_dir).path_join(PROFILE).path_join(rec.ride_id())
	var meta_before := FileAccess.get_file_as_string(dir.path_join(FileRideRepository.META_FILE))
	for i in 30:
		s.tick(1.0)
	assert_eq(rec.flush_count, 3)
	assert_eq(FileAccess.get_file_as_string(dir.path_join(FileRideRepository.META_FILE)), meta_before, "периодический сброс не переписывает meta.json")
	var on_disk := FileRideRepository.new(_dir).get_ride(rec.ride_id())
	assert_eq(on_disk.samples.size(), 30, "поток дописан")
	assert_eq(int(on_disk.metadata["elapsed_sec"]), 30, "метаданные не старше 10 с")
	rec.dispose()
