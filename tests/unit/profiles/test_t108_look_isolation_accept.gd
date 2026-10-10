extends GutTest
## Tester acceptance of T-108 — rider look in the profile: aliasing and persistence paths the
## spec-table acceptance (`test_t108_rider_look_spec_accept.gd`) does not walk (REQ-AVT-01 p.2,
## p.4; regression REQ-PRF-01, REQ-PRF-04). A look handed to or taken from the repository is a
## value: changing it without `save` / `set_rider_look` changes nothing on disk or in another
## profile; saving another field keeps the look; deleting a profile keeps the others' looks.

var _dir: String


func before_each() -> void:
	_dir = "user://test_t108_look_isolation_%d_%d/" % [Time.get_ticks_usec(), randi() % 100000]


func after_each() -> void:
	var abs_path := ProjectSettings.globalize_path(_dir)
	if DirAccess.dir_exists_absolute(abs_path):
		for f in DirAccess.get_files_at(abs_path):
			DirAccess.remove_absolute(abs_path.path_join(f))
		DirAccess.remove_absolute(abs_path)


func _look(figure: String, hair: String, jersey: String) -> RiderLook:
	var l := RiderLook.default_look()
	assert_true(l.set_value("body.figure", figure))
	assert_true(l.set_value("hair.style", hair))
	assert_true(l.set_value("jersey.main", jersey), "precondition: %s is a form colour" % jersey)
	return l


func _jersey_colours() -> Array[String]:
	var out: Array[String] = []
	for v in RiderLook.allowed_values("jersey.main"):
		if v != RiderLook.default_value("jersey.main"):
			out.append(v)
	return out


func test_look_from_repository_is_a_copy_until_saved() -> void:
	var repo := ProfileRepository.new(_dir)
	var a := repo.create("Anna")
	var b := repo.create("Boris")
	var colours := _jersey_colours()
	assert_eq(repo.set_rider_look(a.id, _look("f", "tail", colours[0])), [] as Array[String])
	# Taken look changed without saving.
	var got := repo.get_by_id(a.id)
	got.rider_look.set_value("jersey.main", colours[1])
	got.rider_look.set_value("hair.style", "short")
	assert_eq(repo.get_by_id(a.id).rider_look.get_value("jersey.main"), colours[0], "unsaved change does not leak into the store")
	assert_eq(repo.get_by_id(a.id).rider_look.get_value("hair.style"), "tail")
	# Look handed to set_rider_look changed afterwards.
	var handed := _look("m", "short", colours[2])
	repo.set_rider_look(b.id, handed)
	handed.set_value("jersey.main", colours[3])
	handed.set_value("body.figure", "f")
	assert_eq(repo.get_by_id(b.id).rider_look.get_value("jersey.main"), colours[2], "argument changed after save does not leak")
	assert_eq(repo.get_by_id(b.id).rider_look.get_value("body.figure"), "m")
	# values() of a stored look is not a live view.
	var vals := repo.get_by_id(a.id).rider_look.values()
	vals["jersey.main"] = colours[4]
	assert_eq(repo.get_by_id(a.id).rider_look.get_value("jersey.main"), colours[0], "values() is a copy")
	# Profile object saved, then mutated without a second save.
	var p := repo.get_by_id(a.id)
	repo.save(p)
	p.rider_look.set_value("jersey.main", colours[5])
	assert_eq(repo.get_by_id(a.id).rider_look.get_value("jersey.main"), colours[0], "saved snapshot does not follow the caller's object")
	# Presets and the default look are fresh values.
	var stealth_jersey := RiderLook.preset("stealth").get_value("jersey.main")
	var pr := RiderLook.preset("stealth")
	pr.set_value("jersey.main", colours[0] if colours[0] != stealth_jersey else colours[1])
	assert_eq(RiderLook.preset("stealth").get_value("jersey.main"), stealth_jersey, "preset table not mutated through a returned look")
	var d1 := RiderLook.default_look()
	d1.set_value("hair.style", "tail")
	assert_eq(RiderLook.default_look().get_value("hair.style"), "short", "default look not mutated")
	# Everything survives a new repository on the same directory.
	var again := ProfileRepository.new(_dir)
	assert_eq(again.get_by_id(a.id).rider_look.get_value("jersey.main"), colours[0])
	assert_eq(again.get_by_id(a.id).rider_look.get_value("body.figure"), "f")
	assert_eq(again.get_by_id(b.id).rider_look.get_value("jersey.main"), colours[2])


func test_other_field_setters_keep_the_look() -> void:
	var repo := ProfileRepository.new(_dir)
	var a := repo.create("Anna")
	var look := RiderLook.preset("volga_union")
	assert_not_null(look, "precondition: volga_union preset")
	repo.set_rider_look(a.id, look)
	repo.set_last_route_id(a.id, RouteCatalog.DEFAULT_ID)
	repo.set_last_workout_id(a.id, "")
	repo.set_sim_steepness_pct(a.id, 35)
	var p := repo.get_by_id(a.id)
	p.ftp_w = 250
	repo.save(p)
	assert_true(ProfileRepository.new(_dir).get_by_id(a.id).rider_look.equals(look), "look intact after other fields were saved")


## PRF-04 / AVT-01 p.4: deleting a profile keeps the other profiles' looks; a new profile with the
## same name starts from the default look (no leftovers of the deleted one).
func test_delete_profile_keeps_others_and_new_namesake_starts_default() -> void:
	var repo := ProfileRepository.new(_dir)
	var a := repo.create("Anna")
	var b := repo.create("Boris")
	var colours := _jersey_colours()
	repo.set_rider_look(a.id, _look("f", "tail", colours[0]))
	repo.set_rider_look(b.id, _look("m", "tail", colours[1]))
	assert_eq(repo.delete(a.id), "")
	var again := ProfileRepository.new(_dir)
	assert_eq(again.get_by_id(b.id).rider_look.get_value("jersey.main"), colours[1], "other profile's look kept")
	var a2 := again.create("Anna")
	assert_not_null(a2)
	assert_true(again.get_by_id(a2.id).rider_look.equals(RiderLook.default_look()), "new namesake has the default look")
	assert_true(again.set_active(a2.id).is_empty())
	assert_true(again.get_active().rider_look.equals(RiderLook.default_look()), "active profile look = its own")
	assert_true(again.set_active(b.id).is_empty())
	assert_eq(again.get_active().rider_look.get_value("jersey.main"), colours[1], "switching back gives B's look")
