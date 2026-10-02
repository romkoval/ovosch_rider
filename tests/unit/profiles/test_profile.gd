extends GutTest
## Тесты модели профиля Profile (REQ-PRF-02 крит. 1, 4, 6; REQ-PRF-01 крит. 1).


func _valid() -> Profile:
	var p := Profile.create("Даша")
	p.ftp_w = 200
	p.weight_kg = 60.0
	return p


func test_create_sets_uuid_trimmed_name_and_created_at() -> void:
	var p := Profile.create("  Даша  ")
	assert_eq(p.name, "Даша")
	assert_gt(p.created_at, 0)
	var re := RegEx.create_from_string("^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$")
	assert_not_null(re.search(p.id), "id — UUID v4: %s" % p.id)


func test_generate_id_is_unique() -> void:
	var seen := {}
	for i in 200:
		seen[Profile.generate_id()] = true
	assert_eq(seen.size(), 200)


func test_default_profile_is_valid() -> void:
	assert_eq(_valid().validate(), [])
	assert_true(_valid().is_valid())


func test_name_empty_or_whitespace_is_rejected() -> void:
	var p := _valid()
	p.name = ""
	assert_has(p.validate(), Profile.ERR_NAME_EMPTY)
	p.name = "   "
	assert_has(p.validate(), Profile.ERR_NAME_EMPTY, "REQ-PRF-01 крит. 1: пусто после обрезки")


func test_name_length_limit_40() -> void:
	var p := _valid()
	p.name = "a".repeat(40)
	assert_eq(p.validate(), [])
	p.name = "a".repeat(41)
	assert_has(p.validate(), Profile.ERR_NAME_TOO_LONG)
	p.name = " " + "a".repeat(40) + " "
	assert_eq(p.validate(), [], "пробелы по краям не считаются")


func test_ftp_range_50_600() -> void:
	var p := _valid()
	for ok in [50, 600, 250]:
		p.ftp_w = ok
		assert_does_not_have(p.validate(), Profile.ERR_FTP_OUT_OF_RANGE, "FTP %d допустим" % ok)
	for bad in [49, 601, 0, -10]:
		p.ftp_w = bad
		assert_has(p.validate(), Profile.ERR_FTP_OUT_OF_RANGE, "FTP %d отклоняется" % bad)


func test_weight_range_20_250() -> void:
	var p := _valid()
	for ok in [20.0, 250.0, 75.3]:
		p.weight_kg = ok
		assert_does_not_have(p.validate(), Profile.ERR_WEIGHT_OUT_OF_RANGE, "вес %.1f допустим" % ok)
	for bad in [19.9, 250.1, 0.0]:
		p.weight_kg = bad
		assert_has(p.validate(), Profile.ERR_WEIGHT_OUT_OF_RANGE, "вес %.1f отклоняется" % bad)


func test_max_hr_is_0_or_100_220() -> void:
	var p := _valid()
	for ok in [0, 100, 220, 185]:
		p.max_hr = ok
		assert_does_not_have(p.validate(), Profile.ERR_MAX_HR_OUT_OF_RANGE, "max_hr %d допустим" % ok)
	for bad in [99, 221, 50, -1]:
		p.max_hr = bad
		assert_has(p.validate(), Profile.ERR_MAX_HR_OUT_OF_RANGE, "max_hr %d отклоняется" % bad)


func test_intensity_and_resistance_defaults_ranges() -> void:
	var p := _valid()
	p.intensity_default = 49
	assert_has(p.validate(), Profile.ERR_INTENSITY_OUT_OF_RANGE)
	p.intensity_default = 150
	p.resistance_level_default = 101
	assert_has(p.validate(), Profile.ERR_RESISTANCE_OUT_OF_RANGE)
	p.resistance_level_default = 0
	assert_eq(p.validate(), [])


func test_hr_zones_unavailable_without_max_hr() -> void:
	var p := _valid()
	assert_false(p.has_hr_zones())
	assert_null(p.effective_hr_zones())
	assert_eq(p.hr_zone_of(150), 0, "REQ-PRF-02 крит. 4: «нет зоны»")
	p.max_hr = 180
	assert_true(p.has_hr_zones())
	assert_eq(p.hr_zone_of(107), 1)
	assert_eq(p.hr_zone_of(108), 2)
	assert_eq(p.hr_zone_of(162), 5)


func test_power_zone_table_at_ftp_200() -> void:
	var p := _valid()
	var expected := {110: 1, 111: 2, 150: 2, 151: 3, 180: 3, 181: 4, 210: 4, 211: 5, 240: 5, 241: 6, 300: 6, 301: 7}
	for w in expected:
		assert_eq(p.power_zone_of(w), expected[w], "REQ-PRF-02 крит. 6: %d Вт" % w)


func test_custom_power_zone_bounds_follow_profile_ftp() -> void:
	var p := _valid()
	p.power_zones = PowerZones.custom(999, [50.0, 100.0])
	assert_eq(p.effective_power_zones().ftp_w, 200, "FTP всегда из профиля, не из объекта зон")
	assert_eq(p.power_zone_of(100), 1)
	assert_eq(p.power_zone_of(101), 2)
	assert_eq(p.power_zone_of(201), 3)
	p.ftp_w = 300
	assert_eq(p.power_zone_of(150), 1, "смена FTP сдвинула границы")


func test_invalid_custom_bounds_are_rejected() -> void:
	var p := _valid()
	p.power_zones = PowerZones.custom(200, [75.0, 55.0])
	assert_has(p.validate(), Profile.ERR_POWER_ZONES_INVALID)
	p.power_zones = null
	p.max_hr = 180
	p.hr_zones = HrZones.custom(180, [])
	assert_has(p.validate(), Profile.ERR_HR_ZONES_INVALID)


func test_to_dict_from_dict_roundtrip_with_custom_zones() -> void:
	var p := _valid()
	p.max_hr = 190
	p.power_zones = PowerZones.custom(200, [60.0, 80.0, 100.0])
	p.hr_zones = HrZones.custom(190, [65.0, 75.0, 85.0, 92.0])
	p.intensity_default = 95
	p.resistance_level_default = 35
	var copy := Profile.from_dict(p.to_dict())
	assert_eq(copy.id, p.id)
	assert_eq(copy.name, p.name)
	assert_eq(copy.ftp_w, 200)
	assert_eq(copy.weight_kg, 60.0)
	assert_eq(copy.max_hr, 190)
	assert_eq(copy.intensity_default, 95)
	assert_eq(copy.resistance_level_default, 35)
	assert_eq(copy.created_at, p.created_at)
	assert_eq(copy.power_zones.boundaries_pct, [60.0, 80.0, 100.0])
	assert_eq(copy.hr_zones.boundaries_pct, [65.0, 75.0, 85.0, 92.0])
	assert_eq(copy.validate(), [])


func test_roundtrip_keeps_null_zones_as_defaults() -> void:
	var p := _valid()
	var d := p.to_dict()
	assert_null(d["power_zone_bounds_pct"])
	assert_null(d["hr_zone_bounds_pct"])
	var copy := Profile.from_dict(d)
	assert_null(copy.power_zones)
	assert_null(copy.hr_zones)
	assert_eq(copy.power_zone_of(111), 2, "Coggan по умолчанию")


func test_from_dict_accepts_json_floats_and_missing_fields() -> void:
	var json := '{"id":"abc","name":"Боб","ftp_w":250.0,"weight_kg":80.25,"max_hr":0.0}'
	var p := Profile.from_dict(JSON.parse_string(json))
	assert_eq(p.ftp_w, 250)
	assert_typeof(p.ftp_w, TYPE_INT)
	assert_almost_eq(p.weight_kg, 80.3, 1e-9, "вес округлён до 0.1")
	assert_eq(p.max_hr, 0)
	assert_eq(p.intensity_default, 100, "отсутствующее поле → умолчание")
	assert_eq(p.resistance_level_default, 50)
	assert_null(p.power_zones)


func test_weight_snapped_to_0_1_in_to_dict() -> void:
	var p := _valid()
	p.weight_kg = 72.46
	assert_almost_eq(float(p.to_dict()["weight_kg"]), 72.5, 1e-9)


func test_weight_is_validated_after_snapping_and_normalize_applies_it() -> void:
	var p := _valid()
	p.weight_kg = 19.96
	assert_eq(p.validate(), [], "19.96 → 20.0 принимается")
	p.weight_kg = 19.94
	assert_has(p.validate(), Profile.ERR_WEIGHT_OUT_OF_RANGE, "19.94 → 19.9 отклоняется")
	p.weight_kg = 19.96
	p.name = "  Даша "
	p.normalize()
	assert_almost_eq(p.weight_kg, 20.0, 1e-9)
	assert_eq(p.name, "Даша")


func test_absolute_hr_zones_work_without_max_hr_and_roundtrip() -> void:
	var p := _valid()
	p.hr_zones = HrZones.custom_bpm([108, 126, 144, 162])
	assert_true(p.has_hr_zones(), "REQ-PRF-02 крит. 4: переопределённые зоны доступны без max_hr")
	assert_eq(p.hr_zone_of(107), 1)
	assert_eq(p.hr_zone_of(150), 4)
	assert_eq(p.validate(), [])
	var copy := Profile.from_dict(p.to_dict())
	assert_true(copy.hr_zones.is_absolute())
	assert_eq(copy.hr_zones.boundaries_bpm, [108, 126, 144, 162])
	assert_eq(copy.hr_zone_of(150), 4)
	p.hr_zones = HrZones.custom_bpm([144, 108])
	assert_has(p.validate(), Profile.ERR_HR_ZONES_INVALID)


func test_from_dict_tolerates_garbage_and_null_types() -> void:
	var p := Profile.from_dict({"id": 7, "name": null, "ftp_w": "abc", "weight_kg": null, "max_hr": null,
		"power_zone_bounds_pct": "junk", "hr_zone_bounds_pct": {"a": 1}, "created_at": "yesterday"})
	assert_eq(p.id, "7")
	assert_eq(p.name, "")
	assert_eq(p.ftp_w, 0, "мусор → 0, чтобы validate() отклонил")
	assert_eq(p.weight_kg, 75.0, "null → умолчание")
	assert_eq(p.max_hr, 0)
	assert_null(p.power_zones)
	assert_null(p.hr_zones)
	assert_has(p.validate(), Profile.ERR_FTP_OUT_OF_RANGE)


func test_duplicate_profile_is_independent_copy() -> void:
	var p := _valid()
	var copy := p.duplicate_profile()
	copy.ftp_w = 300
	assert_eq(p.ftp_w, 200)
	assert_eq(copy.id, p.id)
