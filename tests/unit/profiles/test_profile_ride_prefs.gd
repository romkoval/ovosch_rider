extends GutTest
## Поля профиля свободной езды (T-061): последняя трасса (REQ-FRD-02 крит. 3 — хранение,
## по умолчанию `flat`) и крутизна SIM (REQ-FRD-05 крит. 1 — хранение: 0–100 % с шагом 5,
## по умолчанию 50, сохраняется между сессиями).

var _dir: String


func before_each() -> void:
	_dir = "user://test_profile_prefs_%d_%d/" % [Time.get_ticks_usec(), randi() % 100000]


func after_each() -> void:
	AtomicFile.simulate_write_error_prefix = ""
	_remove_tree(ProjectSettings.globalize_path(_dir))


static func _remove_tree(abs_path: String) -> void:
	if not DirAccess.dir_exists_absolute(abs_path):
		return
	var d := DirAccess.open(abs_path)
	for f in d.get_files():
		DirAccess.remove_absolute(abs_path.path_join(f))
	for sub in d.get_directories():
		_remove_tree(abs_path.path_join(sub))
	DirAccess.remove_absolute(abs_path)


func test_defaults() -> void:
	var p := Profile.create("Роман")
	assert_eq(p.last_route_id, "", "трасса ещё не выбиралась")
	assert_eq(p.effective_route_id(), "flat", "FRD-02 крит. 3: первый запуск — равнина")
	assert_eq(p.sim_steepness_pct, 50, "FRD-05 крит. 1: по умолчанию 50 %")
	assert_true(p.is_valid())


func test_effective_route_uses_last_choice() -> void:
	var p := Profile.create("Роман")
	p.last_route_id = "mountains"
	assert_eq(p.effective_route_id(), "mountains")


func test_steepness_range_and_step() -> void:
	for ok_value in [0, 5, 50, 95, 100]:
		assert_true(Profile.is_valid_sim_steepness(ok_value), "%d %% допустимо" % ok_value)
	for bad_value in [-5, 105, 52, 1]:
		assert_false(Profile.is_valid_sim_steepness(bad_value), "%d %% недопустимо" % bad_value)


func test_normalize_snaps_steepness_and_drops_bad_route() -> void:
	var p := Profile.create("Роман")
	p.sim_steepness_pct = 52
	p.last_route_id = "../x"
	p.normalize()
	assert_eq(p.sim_steepness_pct, 50)
	assert_eq(p.last_route_id, "")
	assert_true(p.is_valid())
	p.sim_steepness_pct = 130
	p.last_route_id = "seaside"
	p.normalize()
	assert_eq(p.sim_steepness_pct, 100)
	assert_eq(p.last_route_id, "seaside")


func test_snap_steepness() -> void:
	assert_eq(Profile.snap_sim_steepness(52.0), 50)
	assert_eq(Profile.snap_sim_steepness(53.0), 55)
	assert_eq(Profile.snap_sim_steepness(-10.0), 0)
	assert_eq(Profile.snap_sim_steepness(140.0), 100)


func test_route_id_format() -> void:
	assert_true(Profile.is_valid_route_id(""))
	assert_true(Profile.is_valid_route_id("flat"))
	assert_true(Profile.is_valid_route_id("sea_side-2"))
	assert_false(Profile.is_valid_route_id("Flat"))
	assert_false(Profile.is_valid_route_id("../x"))
	assert_false(Profile.is_valid_route_id("горы"))
	assert_false(Profile.is_valid_route_id("a".repeat(65)))


func test_dict_round_trip() -> void:
	var p := Profile.create("Роман")
	p.last_route_id = "hills"
	p.sim_steepness_pct = 75
	var d := p.to_dict()
	assert_eq(d["last_route_id"], "hills")
	assert_eq(d["sim_steepness_pct"], 75)
	var back := Profile.from_dict(JSON.parse_string(JSON.stringify(d)))
	assert_eq(back.last_route_id, "hills")
	assert_eq(back.sim_steepness_pct, 75)


func test_old_profile_without_fields_gets_defaults() -> void:
	var d := Profile.create("Роман").to_dict()
	d.erase("last_route_id")
	d.erase("sim_steepness_pct")
	var p := Profile.from_dict(d)
	assert_eq(p.last_route_id, "")
	assert_eq(p.effective_route_id(), "flat")
	assert_eq(p.sim_steepness_pct, 50)
	assert_true(p.is_valid())


func test_corrupted_values_on_disk_are_normalized_not_blocking() -> void:
	var d := Profile.create("Роман").to_dict()
	d["last_route_id"] = "../../etc"
	d["sim_steepness_pct"] = 237.0
	var p := Profile.from_dict(d)
	assert_eq(p.last_route_id, "", "неверный идентификатор → трасса по умолчанию")
	assert_eq(p.sim_steepness_pct, 100, "крутизна ограничена 100 %")
	assert_true(p.is_valid(), "профиль остаётся сохраняемым")
	d["last_route_id"] = 42
	d["sim_steepness_pct"] = "abc"
	p = Profile.from_dict(d)
	assert_eq(p.last_route_id, "")
	assert_eq(p.sim_steepness_pct, 50)


func test_repository_persists_route_and_steepness_between_sessions() -> void:
	var repo := ProfileRepository.new(_dir)
	var p := repo.create("Роман")
	p.ftp_w = 280
	assert_eq(repo.save(p), [])
	assert_eq(repo.set_last_route_id(p.id, "mountains"), [])
	assert_eq(repo.set_sim_steepness_pct(p.id, 30), [])
	var reopened := ProfileRepository.new(_dir)
	var loaded := reopened.get_by_id(p.id)
	assert_eq(loaded.last_route_id, "mountains", "FRD-02 крит. 3: трасса в профиле")
	assert_eq(loaded.effective_route_id(), "mountains")
	assert_eq(loaded.sim_steepness_pct, 30, "FRD-05 крит. 1: крутизна между сессиями")
	assert_eq(loaded.ftp_w, 280, "остальные поля не тронуты")


func test_repository_normalizes_bad_values_and_rejects_unknown_profile() -> void:
	var repo := ProfileRepository.new(_dir)
	var p := repo.create("Роман")
	assert_eq(repo.set_last_route_id(p.id, "hills"), [])
	assert_eq(repo.set_sim_steepness_pct(p.id, 52), [])
	assert_eq(repo.set_last_route_id(p.id, "Bad Id"), [])
	var reopened := ProfileRepository.new(_dir).get_by_id(p.id)
	assert_eq(reopened.sim_steepness_pct, 50, "крутизна на шаге 5 %")
	assert_eq(reopened.last_route_id, "", "неверный формат → трасса по умолчанию")
	assert_eq(repo.set_last_route_id("ghost", "flat"), [ProfileRepository.ERR_PROFILE_NOT_FOUND])
	assert_eq(repo.set_sim_steepness_pct("ghost", 50), [ProfileRepository.ERR_PROFILE_NOT_FOUND])


func test_repository_write_failure_keeps_previous_value() -> void:
	var repo := ProfileRepository.new(_dir)
	var p := repo.create("Роман")
	AtomicFile.simulate_write_error_prefix = repo.file_path()
	assert_has(repo.set_sim_steepness_pct(p.id, 80), ProfileRepository.ERR_STORAGE_WRITE_FAILED)
	AtomicFile.simulate_write_error_prefix = ""
	assert_push_error("AtomicFile")
	assert_push_error("ProfileRepository")
	assert_eq(repo.get_by_id(p.id).sim_steepness_pct, 50)
