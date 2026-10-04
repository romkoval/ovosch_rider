extends GutTest
## `RiderLook` — внешность гонщика в профиле (T-108; REQ-AVT-01 п.1–7; регрессия REQ-PRF-01,
## PRF-04). Спека — `docs/game/art-bible.md`, «Гонщик» ред. 2, «Слоты внешности»: 28 слотов,
## палитра формы, 6 пресетов (ред. 4: + клубная форма владельца `volga_union`), формат `version` 1.

const SECRET_KEY: String = "fixture-look-intervals-key-63"

var _dir: String


func before_each() -> void:
	_dir = "user://test_rider_look_%d_%d/" % [Time.get_ticks_usec(), randi() % 1000000]


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


## Внешность, отличная от умолчания в каждом слоте, где это возможно.
static func _custom_look() -> RiderLook:
	var look := RiderLook.preset(RiderLook.PRESET_SUNRISE)
	look.set_value(RiderLook.JERSEY_MAIN, "purple")
	look.set_value(RiderLook.BIKE_RIMS, "shallow")
	look.set_value(RiderLook.SKIN_TONE, "s6")
	return look


# ---------------------------------------------------------------------------
# Слоты и значения по спеке
# ---------------------------------------------------------------------------

func test_28_slots_with_spec_defaults_equal_to_classic() -> void:
	assert_eq(RiderLook.SLOTS.size(), 28, "28 слотов (ред. 2)")
	var look := RiderLook.default_look()
	var expected := {
		"body.figure": "m", "hair.style": "short", "jersey.pattern": "side_panels",
		"jersey.main": "white", "jersey.accent1": "red", "jersey.accent2": "blue",
		"shorts.main": "navy", "shorts.gripper": "black", "socks.main": "white", "socks.cuff": "white",
		"helmet.model": "aero", "helmet.main": "white", "helmet.accent": "black",
		"glasses.model": "shield", "glasses.lens": "smoke", "glasses.frame": "black",
		"shoes.model": "boa", "shoes.main": "white", "shoes.accent": "black",
		"gloves.model": "short", "gloves.color": "black", "skin.tone": "s3", "hair.color": "dark_brown",
		"bike.frame": "red", "bike.accent": "yellow", "bike.rims": "deep", "bike.rim_decal": "yellow",
		"bike.bar_tape": "black",
	}
	assert_eq(expected.size(), 28)
	for slot: String in expected:
		assert_true(RiderLook.is_slot(slot), "слот %s есть" % slot)
		assert_eq(look.get_value(slot), expected[slot], "по умолчанию %s" % slot)
	assert_eq(look.matching_preset(), RiderLook.PRESET_CLASSIC, "умолчание = classic")


func test_enum_slots_and_form_palette_match_spec() -> void:
	assert_eq(RiderLook.allowed_values(RiderLook.BODY_FIGURE), ["m", "f"])
	assert_eq(RiderLook.allowed_values(RiderLook.HAIR_STYLE), ["short", "tail"])
	assert_eq(RiderLook.allowed_values(RiderLook.GLASSES_MODEL), ["none", "shield", "half_frame"])
	assert_eq(RiderLook.allowed_values(RiderLook.BIKE_RIMS), ["deep", "shallow"])
	assert_eq(RiderLook.allowed_values(RiderLook.SKIN_TONE).size(), 6)
	assert_eq(RiderLook.FORM_COLORS.size(), 16, "палитра формы — 16 ключей")
	assert_true(RiderLook.is_color_slot(RiderLook.JERSEY_MAIN))
	assert_false(RiderLook.is_color_slot(RiderLook.HELMET_MODEL))
	assert_true(RiderLook.is_valid_value(RiderLook.JERSEY_MAIN, "black"), "тёмная джерси разрешена (ред. 2)")
	assert_eq(RiderLook.form_color("navy"), Color(0.16, 0.18, 0.44))


func test_set_value_rejects_invalid_and_keeps_previous() -> void:
	var look := RiderLook.default_look()
	assert_true(look.set_value(RiderLook.HELMET_MODEL, "vented"))
	assert_false(look.set_value(RiderLook.HELMET_MODEL, "tt"), "неизвестная модель")
	assert_false(look.set_value(RiderLook.JERSEY_MAIN, "#ff0000"), "цвет не ключом палитры")
	assert_false(look.set_value(RiderLook.JERSEY_MAIN, 3), "не строка")
	assert_false(look.set_value("cape.color", "red"), "неизвестный слот")
	assert_eq(look.get_value(RiderLook.HELMET_MODEL), "vented")
	assert_eq(look.get_value(RiderLook.JERSEY_MAIN), "white")


func test_jersey_pattern_scheme_maps_regions_3_to_7() -> void:
	var look := RiderLook.preset(RiderLook.PRESET_CLASSIC)
	# side_panels: бока a1, полоса main, плечи main, манжеты a2, воротник a2.
	var keys: Array[String] = []
	for i in 5:
		keys.append(look.jersey_region_color_key(i))
	assert_eq(keys, ["red", "white", "white", "blue", "blue"])
	look.set_value(RiderLook.JERSEY_PATTERN, "shoulder_yoke")
	keys.clear()
	for i in 5:
		keys.append(look.jersey_region_color_key(i))
	assert_eq(keys, ["blue", "white", "red", "red", "red"])


# ---------------------------------------------------------------------------
# Сериализация и неверные слоты (AVT-01 п.2, 3)
# ---------------------------------------------------------------------------

func test_to_dict_is_flat_slot_map_with_version_1_and_round_trips() -> void:
	var look := _custom_look()
	var d := look.to_dict()
	assert_eq(int(d[RiderLook.VERSION_KEY]), 1)
	assert_eq(d.size(), 29, "28 слотов + version")
	for slot in RiderLook.SLOTS:
		assert_true(d[slot] is String, "значение %s — строка" % slot)
	var back := RiderLook.from_dict(JSON.parse_string(JSON.stringify(d)))
	assert_true(back.equals(look), "round-trip через JSON")
	assert_eq(back.reset_slots(), [])


func test_one_invalid_slot_resets_only_that_slot() -> void:
	var cases: Array = [
		[RiderLook.HELMET_MODEL, "tt_helmet"],
		[RiderLook.JERSEY_MAIN, "#00ff00"],
		[RiderLook.SKIN_TONE, 4],
		[RiderLook.GLASSES_LENS, null],
		[RiderLook.BIKE_FRAME, {"r": 1}],
	]
	for c: Array in cases:
		var d := _custom_look().to_dict()
		d[c[0]] = c[1]
		var back := RiderLook.from_dict(d)
		assert_eq(back.get_value(c[0]), RiderLook.default_value(c[0]), "%s → по умолчанию" % c[0])
		assert_eq(back.reset_slots(), [c[0]], "сброшен только %s" % c[0])
		for slot in RiderLook.SLOTS:
			if slot != c[0]:
				assert_eq(back.get_value(slot), _custom_look().get_value(slot), "%s сохранён при порче %s" % [slot, c[0]])


func test_missing_slots_unknown_fields_and_garbage_read_as_default() -> void:
	var partial := RiderLook.from_dict({"version": 1, "jersey.main": "teal", "cape": "red"})
	assert_eq(partial.get_value(RiderLook.JERSEY_MAIN), "teal")
	assert_eq(partial.get_value(RiderLook.BODY_FIGURE), "m", "отсутствующий слот — по умолчанию")
	assert_eq(partial.reset_slots(), [], "отсутствие — не ошибка")
	for garbage: Variant in [null, 5, "look", [1, 2]]:
		assert_true(RiderLook.from_dict(garbage).equals(RiderLook.default_look()), "мусор %s → умолчание" % str(garbage))


# ---------------------------------------------------------------------------
# Пресеты (AVT-01 п.5)
# ---------------------------------------------------------------------------

func test_six_presets_valid_without_replacements_and_distinct() -> void:
	assert_eq(RiderLook.PRESET_IDS, ["classic", "sunrise", "alpine", "sprint", "stealth", "volga_union"])
	var jerseys: Array[String] = []
	for id in RiderLook.PRESET_IDS:
		var look := RiderLook.preset(id)
		assert_not_null(look, id)
		var back := RiderLook.from_dict(look.to_dict())
		assert_eq(back.reset_slots(), [], "пресет %s проходит проверку без замен" % id)
		for slot in RiderLook.SLOTS:
			var raw: Variant = (RiderLook.PRESETS[id] as Dictionary).get(slot, RiderLook.default_value(slot))
			assert_true(RiderLook.is_valid_value(slot, raw), "%s.%s = %s допустимо" % [id, slot, raw])
		assert_eq(look.matching_preset(), id)
		jerseys.append(look.get_value(RiderLook.JERSEY_MAIN))
	assert_eq(jerseys, ["white", "orange", "teal", "yellow", "black", "black"], "джерси пресетов")
	assert_ne(RiderLook.preset(RiderLook.PRESET_VOLGA_UNION).values(), RiderLook.preset(RiderLook.PRESET_STEALTH).values(),
			"два чёрных пресета различаются")
	assert_null(RiderLook.preset("rainbow"))


func test_presets_cover_both_figures_and_hair_styles_and_spec_specifics() -> void:
	var figures := {}
	var hair := {}
	for id in RiderLook.PRESET_IDS:
		figures[RiderLook.preset(id).get_value(RiderLook.BODY_FIGURE)] = true
		hair[RiderLook.preset(id).get_value(RiderLook.HAIR_STYLE)] = true
	assert_eq(figures.size(), 2)
	assert_eq(hair.size(), 2)
	assert_eq(RiderLook.preset(RiderLook.PRESET_SPRINT).get_value(RiderLook.GLASSES_MODEL), "none", "sprint без очков")
	assert_eq(RiderLook.preset(RiderLook.PRESET_ALPINE).get_value(RiderLook.GLOVES_MODEL), "none")
	assert_eq(RiderLook.preset(RiderLook.PRESET_SPRINT).get_value(RiderLook.GLASSES_LENS), "smoke", "прочерк — по умолчанию")
	assert_eq(RiderLook.preset(RiderLook.PRESET_STEALTH).get_value(RiderLook.HAIR_STYLE), "tail")
	assert_eq(RiderLook.preset(RiderLook.PRESET_SUNRISE).get_value(RiderLook.BIKE_RIMS), "shallow")
	var volga := RiderLook.preset(RiderLook.PRESET_VOLGA_UNION)
	assert_eq(volga.get_value(RiderLook.JERSEY_MAIN), "black", "Волга Юнион: чёрная джерси")
	assert_eq(volga.get_value(RiderLook.SHORTS_MAIN), "black", "чёрные шорты")
	assert_eq(volga.get_value(RiderLook.SOCKS_MAIN), "white", "белые носки")
	assert_eq(volga.get_value(RiderLook.HELMET_MAIN), "red", "красный шлем")
	var expected_volga := {
		"body.figure": "m", "hair.style": "short", "jersey.pattern": "solid",
		"jersey.main": "black", "jersey.accent1": "graphite", "jersey.accent2": "red",
		"shorts.main": "black", "shorts.gripper": "black", "socks.main": "white", "socks.cuff": "white",
		"helmet.model": "vented", "helmet.main": "red", "helmet.accent": "black",
		"glasses.model": "shield", "glasses.lens": "smoke", "glasses.frame": "black",
		"shoes.model": "boa", "shoes.main": "black", "shoes.accent": "graphite",
		"gloves.model": "short", "gloves.color": "black", "skin.tone": "s3", "hair.color": "dark_brown",
		"bike.frame": "grey", "bike.accent": "red", "bike.rims": "deep", "bike.rim_decal": "grey",
		"bike.bar_tape": "black",
	}
	for slot: String in expected_volga:
		assert_eq(volga.get_value(slot), expected_volga[slot], "volga_union.%s по спеке ред. 4" % slot)


func test_preset_names_are_translation_keys_with_ru_and_en() -> void:
	var previous := TranslationServer.get_locale()
	var expected := {
		"classic": ["Классика", "Classic"], "sunrise": ["Рассвет", "Sunrise"], "alpine": ["Альпы", "Alpine"],
		"sprint": ["Спринт", "Sprint"], "stealth": ["Стелс", "Stealth"],
		"volga_union": ["Волга Юнион", "Volga Union"],
	}
	for id in RiderLook.PRESET_IDS:
		var key := RiderLook.preset_name_key(id)
		assert_eq(key, "ui.menu.rider_look.preset." + id)
		TranslationServer.set_locale("ru")
		assert_eq(str(TranslationServer.translate(key)), expected[id][0], key + " [ru]")
		TranslationServer.set_locale("en")
		assert_eq(str(TranslationServer.translate(key)), expected[id][1], key + " [en]")
	TranslationServer.set_locale(previous)


# ---------------------------------------------------------------------------
# Профиль и хранилище (AVT-01 п.1, 2, 4, 6, 7)
# ---------------------------------------------------------------------------

func test_new_profile_has_default_look_and_dict_carries_it() -> void:
	var p := Profile.create("Rider")
	assert_true(p.rider_look.equals(RiderLook.default_look()))
	var d := p.to_dict()
	assert_true(d.has("rider_look"))
	assert_eq(int((d["rider_look"] as Dictionary)["version"]), 1)


func test_profile_saved_without_look_reads_with_default_and_other_fields_intact() -> void:
	var repo := ProfileRepository.new(_dir)
	var p := Profile.create("Old")
	p.ftp_w = 245
	p.weight_kg = 68.4
	p.sim_steepness_pct = 70
	assert_eq(repo.save(p), [])
	# Файл в формате до T-108: у профиля нет поля `rider_look`.
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(repo.file_path()))
	for item: Dictionary in data["profiles"]:
		item.erase("rider_look")
	var f := FileAccess.open(repo.file_path(), FileAccess.WRITE)
	f.store_string(JSON.stringify(data))
	f.close()
	var reread := ProfileRepository.new(_dir).get_by_id(p.id)
	assert_not_null(reread, "профиль прочитан без ошибки")
	assert_true(reread.rider_look.equals(RiderLook.default_look()), "внешность по умолчанию")
	assert_eq(reread.ftp_w, 245)
	assert_almost_eq(reread.weight_kg, 68.4, 1e-6)
	assert_eq(reread.sim_steepness_pct, 70)
	assert_eq(reread.name, "Old")


func test_look_round_trips_through_new_repository_on_same_dir() -> void:
	var repo := ProfileRepository.new(_dir)
	var p := repo.create("Rider")
	assert_eq(repo.set_rider_look(p.id, _custom_look()), [])
	var reread := ProfileRepository.new(_dir).get_by_id(p.id)
	for slot in RiderLook.SLOTS:
		assert_eq(reread.rider_look.get_value(slot), _custom_look().get_value(slot), "слот %s после чтения" % slot)
	var via_save := reread.duplicate_profile()
	via_save.rider_look.set_value(RiderLook.HELMET_MAIN, "pink")
	assert_eq(repo.save(via_save), [])
	assert_eq(ProfileRepository.new(_dir).get_by_id(p.id).rider_look.get_value(RiderLook.HELMET_MAIN), "pink", "и через save()")


func test_invalid_slot_on_disk_resets_only_it_and_profile_still_reads() -> void:
	var repo := ProfileRepository.new(_dir)
	var p := repo.create("Rider")
	repo.set_rider_look(p.id, _custom_look())
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(repo.file_path()))
	(data["profiles"][0]["rider_look"] as Dictionary)["shoes.model"] = "clogs"
	var f := FileAccess.open(repo.file_path(), FileAccess.WRITE)
	f.store_string(JSON.stringify(data))
	f.close()
	var reread := ProfileRepository.new(_dir).get_by_id(p.id)
	assert_not_null(reread)
	assert_eq(reread.rider_look.get_value(RiderLook.SHOES_MODEL), "boa", "сброшен только неверный слот")
	assert_eq(reread.rider_look.get_value(RiderLook.JERSEY_MAIN), "purple")
	assert_eq(reread.rider_look.get_value(RiderLook.SKIN_TONE), "s6")


func test_profiles_have_independent_looks_and_active_switch_follows() -> void:
	var repo := ProfileRepository.new(_dir)
	var a := repo.create("A")
	var b := repo.create("B")
	assert_eq(repo.set_rider_look(a.id, RiderLook.preset(RiderLook.PRESET_STEALTH)), [])
	assert_true(repo.get_by_id(b.id).rider_look.equals(RiderLook.default_look()), "B не изменился")
	assert_eq(repo.set_rider_look(b.id, RiderLook.preset(RiderLook.PRESET_ALPINE)), [])
	assert_eq(repo.get_by_id(a.id).rider_look.matching_preset(), RiderLook.PRESET_STEALTH, "A не изменился")
	# Копия профиля не делит внешность с хранилищем.
	var copy := repo.get_by_id(a.id)
	copy.rider_look.set_value(RiderLook.JERSEY_MAIN, "pink")
	assert_eq(repo.get_by_id(a.id).rider_look.get_value(RiderLook.JERSEY_MAIN), "black")
	var state := AppState.new(repo)
	assert_true(state.select_profile(b.id))
	assert_eq(repo.get_active().rider_look.matching_preset(), RiderLook.PRESET_ALPINE, "активный — B")
	assert_true(state.select_profile(a.id))
	assert_eq(repo.get_active().rider_look.matching_preset(), RiderLook.PRESET_STEALTH, "активный — A")


func test_set_rider_look_unknown_profile_and_null() -> void:
	var repo := ProfileRepository.new(_dir)
	var p := repo.create("Rider")
	assert_eq(repo.set_rider_look("missing", RiderLook.default_look()), [ProfileRepository.ERR_PROFILE_NOT_FOUND])
	assert_eq(repo.set_rider_look(p.id, null), [], "null — внешность по умолчанию")
	assert_true(repo.get_by_id(p.id).rider_look.equals(RiderLook.default_look()))


func test_no_secrets_in_profile_file_with_look() -> void:
	var repo := ProfileRepository.new(_dir + "profiles/")
	var store := EncryptedFileSecureStore.new(_dir + "secure/", "fixture-device-password-1")
	var p := repo.create("Rider")
	store.set_secret(SecureStore.key_for(p.id, SecureStore.SERVICE_INTERVALS, SecureStore.ITEM_API_KEY), SECRET_KEY)
	repo.set_rider_look(p.id, RiderLook.preset(RiderLook.PRESET_SPRINT))
	var text := FileAccess.get_file_as_string(repo.file_path())
	assert_true(text.contains("rider_look"))
	assert_false(text.contains(SECRET_KEY), "PRF-03 п.3: ключа нет в файле профилей")
	for value: String in RiderLook.preset(RiderLook.PRESET_SPRINT).values().values():
		assert_true(RiderLook.SLOTS.size() > 0 and (RiderLook.FORM_COLORS.has(value) or _is_enum_value(value)),
				"во внешности только ключи палитры и перечислений: %s" % value)


static func _is_enum_value(value: String) -> bool:
	for slot: String in RiderLook.ENUMS:
		if (RiderLook.ENUMS[slot] as Array).has(value):
			return true
	return false


func test_profiles_layer_does_not_depend_on_scene3d_ui_or_app() -> void:
	var forbidden_dirs: Array[String] = ["res://src/scene3d", "res://src/ui", "res://src/app"]
	var forbidden_classes: Array[String] = []
	var re := RegEx.create_from_string("^class_name\\s+([A-Za-z_][A-Za-z0-9_]*)")
	for dir in forbidden_dirs:
		for path in _gd_files(dir):
			for line in FileAccess.get_file_as_string(path).split("\n"):
				var m := re.search(line)
				if m != null:
					forbidden_classes.append(m.get_string(1))
	assert_gt(forbidden_classes.size(), 10, "классы запрещённых слоёв найдены")
	var offenders: Array[String] = []
	for path in _gd_files("res://src/profiles"):
		var n := 0
		for raw in FileAccess.get_file_as_string(path).split("\n"):
			n += 1
			var hash_at := raw.find("#")
			var line := raw.substr(0, hash_at) if hash_at != -1 else raw
			for dir in forbidden_dirs:
				if line.contains(dir + "/"):
					offenders.append("%s:%d %s" % [path, n, dir])
			for cls in forbidden_classes:
				if RegEx.create_from_string("\\b%s\\b" % cls).search(line) != null:
					offenders.append("%s:%d %s" % [path, n, cls])
	assert_eq(offenders, [], "AVT-01 п.6 / NFR-06 п.3: src/profiles/ не зависит от 3D, UI и оболочки")


func test_look_reads_and_saves_headless_without_scene_tree() -> void:
	# Ни узлов, ни сцен: только RefCounted и файл.
	var look := RiderLook.preset(RiderLook.PRESET_ALPINE)
	assert_true(look is RefCounted)
	var repo := ProfileRepository.new(_dir)
	var p := repo.create("Headless")
	assert_eq(repo.set_rider_look(p.id, look), [])
	assert_true(ProfileRepository.new(_dir).get_by_id(p.id).rider_look.equals(look))


static func _gd_files(dir_path: String) -> Array[String]:
	var out: Array[String] = []
	var d := DirAccess.open(dir_path)
	if d == null:
		return out
	for f in d.get_files():
		if f.ends_with(".gd"):
			out.append(dir_path.path_join(f))
	for sub in d.get_directories():
		out.append_array(_gd_files(dir_path.path_join(sub)))
	return out
