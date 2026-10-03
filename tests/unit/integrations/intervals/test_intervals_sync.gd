extends GutTest
## Тесты IntervalsSync и расширения Profile (REQ-INT-06 крит. 1–5, 7; REQ-PRF-02 крит. 6).

const FIXTURES: String = "res://tests/fixtures/intervals/"
const DATE: String = "2026-10-02"


static func _athlete_json() -> Dictionary:
	var json := JSON.new()
	assert(json.parse(FileAccess.get_file_as_string(FIXTURES + "athlete.json")) == OK)
	return json.data


func _profile() -> Profile:
	var p := Profile.create("Даша")
	p.ftp_w = 200
	p.max_hr = 180
	return p


# ---------------------------------------------------------------------------
# parse_athlete
# ---------------------------------------------------------------------------

func test_parse_athlete_picks_bike_sport_settings() -> void:
	var a := IntervalsSync.parse_athlete(_athlete_json())
	assert_eq(str(a["id"]), "i12345")
	assert_eq(str(a["name"]), "Test Athlete")
	assert_eq(int(a["ftp"]), 250, "FTP из записи Ride, не из Run")
	assert_eq(int(a["indoor_ftp"]), 245)
	assert_eq(int(a["lthr"]), 168)
	assert_eq(int(a["max_hr"]), 192)
	assert_almost_eq(float(a["weight_kg"]), 68.5, 0.001)
	assert_eq(a["power_zones_pct"], [55.0, 75.0, 90.0, 105.0, 120.0, 150.0], "открытая 999 отброшена")
	assert_eq(int(a["power_zone_count"]), 7)
	assert_eq(a["hr_zones_bpm"], [116, 135, 154, 173, 183], "верхние границы → нижние границы зон 2..6")
	assert_eq(int(a["hr_zone_count"]), 6)
	assert_eq(a["warnings"], [])


func test_parse_athlete_without_bike_settings_warns_and_uses_first() -> void:
	var a := IntervalsSync.parse_athlete({"id": "i1", "sportSettings": [{"types": ["Run"], "ftp": 300, "max_hr": 190}]})
	assert_has(a["warnings"], IntervalsSync.WARN_NO_BIKE_SETTINGS)
	assert_eq(int(a["ftp"]), 300)
	assert_has(a["warnings"], IntervalsSync.WARN_POWER_ZONES_MISSING)
	var none := IntervalsSync.parse_athlete({"id": "i2"})
	assert_eq(int(none["ftp"]), 0)
	assert_has(none["warnings"], IntervalsSync.WARN_FTP_MISSING)


# ---------------------------------------------------------------------------
# Зоны мощности (REQ-INT-06 крит. 2)
# ---------------------------------------------------------------------------

func test_power_zones_in_watts_convert_to_rounded_percent() -> void:
	var pct := IntervalsSync.power_zones_to_pct([110, 150, 180, 210, 240, 300, 9999], 200)
	assert_eq(pct, [55.0, 75.0, 90.0, 105.0, 120.0, 150.0], "REQ-INT-06 крит. 2: ватты → % FTP, открытая граница отброшена")
	var rounded := IntervalsSync.power_zones_to_pct([137, 188, 400], 250, "watts")
	assert_eq(rounded, [55.0, 75.0, 160.0], "округление до целого процента (54.8 → 55, 75.2 → 75)")
	assert_eq(IntervalsSync.power_zones_to_pct([100, 150], 200, "watts"), [50.0, 75.0], "явные ватты при малых числах")
	assert_eq(IntervalsSync.power_zones_to_pct([100, 150], 0, "watts"), [], "без FTP ватты не перевести")


func test_power_zones_watts_with_999_sentinel_is_open_bound() -> void:
	assert_eq(IntervalsSync.power_zones_to_pct([110, 150, 180, 210, 240, 300, 999], 200), [55.0, 75.0, 90.0, 105.0, 120.0, 150.0], "D-7: 999 — открытая граница и в ваттах")
	assert_eq(IntervalsSync.power_zones_to_pct([110, 150, 999], 200, "watts"), [55.0, 75.0])


func test_more_than_nine_hr_zones_warns_and_keeps_profile_zones() -> void:
	var p := _profile()
	p.hr_zones = HrZones.custom_bpm([100, 120, 140, 160])
	var ten: Array[int] = [100, 110, 120, 130, 140, 150, 160, 170, 180]
	var w := IntervalsSync.apply_athlete_to_profile(p, {"ftp": 220, "power_zones_pct": [55.0, 75.0], "hr_zones_bpm": ten, "max_hr": 195}, false, DATE)
	assert_has(w, IntervalsSync.WARN_HR_ZONES_COUNT, "10 зон пульса → предупреждение")
	assert_eq(p.hr_zones.boundaries_bpm, [100, 120, 140, 160], "зоны пульса не тронуты")
	assert_eq(p.max_hr, 180, "max_hr тоже не тронут")


func test_power_zones_percent_and_names_rule() -> void:
	assert_eq(IntervalsSync.power_zones_to_pct([55, 75, 90], 200, "auto", ["Z1", "Z2", "Z3"]), [55.0, 75.0], "число имён = число значений → последняя граница открытая")
	assert_eq(IntervalsSync.power_zones_to_pct([55, 75, 90], 200), [55.0, 75.0, 90.0], "без имён и без открытой границы — все значения границы")
	assert_eq(IntervalsSync.power_zones_to_pct([60.4, 80.6], 200, "percent"), [60.0, 81.0])


func test_power_zones_invalid_lists_are_rejected() -> void:
	assert_eq(IntervalsSync.power_zones_to_pct([], 200), [])
	assert_eq(IntervalsSync.power_zones_to_pct([75, 55], 200), [], "не возрастают")
	assert_eq(IntervalsSync.power_zones_to_pct([55, 55], 200), [], "равные")
	assert_eq(IntervalsSync.power_zones_to_pct([55, "x"], 200), [], "не числа")
	assert_eq(IntervalsSync.power_zones_to_pct([0, 55], 200), [], "нулевая граница")


func test_apply_supports_up_to_nine_zones_and_rejects_more() -> void:
	var p := _profile()
	var nine: Array[float] = [20.0, 30.0, 40.0, 50.0, 60.0, 70.0, 80.0, 90.0]
	var w := IntervalsSync.apply_athlete_to_profile(p, {"ftp": 200, "power_zones_pct": nine}, false, DATE)
	assert_eq(p.effective_power_zones().zone_count(), 9, "REQ-INT-06 крит. 2: 9 зон принимаются")
	assert_eq(p.power_zone_of(200), 9, "REQ-PRF-02 крит. 6: функция зоны работает с 9 зонами")
	assert_eq(p.power_zone_of(40), 1)
	assert_does_not_have(w, IntervalsSync.WARN_POWER_ZONES_COUNT)
	assert_eq(p.validate(), [])
	var ten: Array[float] = [10.0, 20.0, 30.0, 40.0, 50.0, 60.0, 70.0, 80.0, 90.0]
	var w10 := IntervalsSync.apply_athlete_to_profile(p, {"ftp": 200, "power_zones_pct": ten}, false, DATE)
	assert_has(w10, IntervalsSync.WARN_POWER_ZONES_COUNT, "10 зон → предупреждение")
	assert_eq(p.power_zones.boundaries_pct, nine, "зоны профиля не изменились")


func test_zero_or_one_zone_gives_warning_and_keeps_profile_zones() -> void:
	var p := _profile()
	var zero := IntervalsSync.apply_athlete_to_profile(p, {"ftp": 200, "power_zones_pct": []}, false, DATE)
	assert_has(zero, IntervalsSync.WARN_POWER_ZONES_MISSING)
	assert_null(p.power_zones, "зоны остались Coggan")
	var one := IntervalsSync.parse_athlete({"sportSettings": [{"types": ["Ride"], "ftp": 200, "power_zones": [999], "power_zone_names": ["Z1"]}]})
	assert_eq(one["power_zones_pct"], [])
	assert_has(one["warnings"], IntervalsSync.WARN_POWER_ZONES_INVALID)
	var w1 := IntervalsSync.apply_athlete_to_profile(p, one, false, DATE)
	assert_has(w1, IntervalsSync.WARN_POWER_ZONES_COUNT)
	assert_null(p.power_zones)


# ---------------------------------------------------------------------------
# Зоны пульса (REQ-INT-06 крит. 3)
# ---------------------------------------------------------------------------

func test_hr_zones_upper_bounds_become_lower_bounds_plus_one() -> void:
	var bpm := IntervalsSync.hr_zones_to_bpm([115, 134, 153, 172, 182, 192], 192)
	assert_eq(bpm, [116, 135, 154, 173, 183])
	var zones := HrZones.custom_bpm(bpm)
	assert_eq(zones.zone_of(115), 1, "115 — ещё Z1 (верхняя граница Intervals включительно)")
	assert_eq(zones.zone_of(116), 2)
	assert_eq(zones.zone_of(192), 6)
	assert_eq(IntervalsSync.hr_zones_to_bpm([120, 140], 0), [121, 141], "без max_hr и имён — все значения границы")
	assert_eq(IntervalsSync.hr_zones_to_bpm([140, 120], 0), [], "не возрастают")
	assert_eq(IntervalsSync.hr_zones_to_bpm([], 190), [])


func test_apply_hr_zones_from_sport_settings() -> void:
	var p := _profile()
	var w := IntervalsSync.apply_athlete_to_profile(p, IntervalsSync.parse_athlete(_athlete_json()), false, DATE)
	assert_eq(w, [])
	assert_eq(p.max_hr, 192)
	assert_true(p.hr_zones.is_absolute(), "REQ-INT-06 крит. 3: границы в уд/мин")
	assert_eq(p.effective_hr_zones().zone_count(), 6)
	assert_eq(p.hr_zone_of(150), 3)
	assert_eq(p.hr_zone_of(183), 6)
	assert_eq(p.validate(), [])


func test_apply_without_hr_zones_uses_max_hr() -> void:
	var p := _profile()
	p.hr_zones = HrZones.custom_bpm([100, 120, 140, 160])
	var w := IntervalsSync.apply_athlete_to_profile(p, {"ftp": 220, "power_zones_pct": [55.0, 75.0], "max_hr": 195}, false, DATE)
	assert_has(w, IntervalsSync.WARN_HR_ZONES_MISSING)
	assert_eq(p.max_hr, 195, "REQ-INT-06 крит. 3: зоны от max_hr")
	assert_null(p.hr_zones)
	assert_eq(p.effective_hr_zones().zone_count(), 5)
	assert_eq(p.hr_zone_of(117), 2, "60 % от 195 = 117 → Z2")
	var no_hr := IntervalsSync.apply_athlete_to_profile(_profile(), {"ftp": 220}, false, DATE)
	assert_has(no_hr, IntervalsSync.WARN_MAX_HR_MISSING)


# ---------------------------------------------------------------------------
# FTP, источники, переопределение (REQ-INT-06 крит. 1, 4, 5, 7)
# ---------------------------------------------------------------------------

func test_apply_writes_ftp_zones_sources_and_athlete_id() -> void:
	var p := _profile()
	var w := IntervalsSync.apply_athlete_to_profile(p, IntervalsSync.parse_athlete(_athlete_json()), false, DATE)
	assert_eq(w, [])
	assert_eq(p.ftp_w, 250, "REQ-INT-06 крит. 1: FTP из фикстуры")
	assert_eq(p.power_zones.boundaries_pct, [55.0, 75.0, 90.0, 105.0, 120.0, 150.0], "REQ-INT-06 крит. 1: границы зон")
	assert_eq(p.effective_power_zones().ftp_w, 250)
	assert_eq(p.power_zone_of(250), 4)
	assert_eq(p.ftp_source, "intervals:2026-10-02", "REQ-INT-06 крит. 6: источник с датой")
	assert_eq(p.zones_source, "intervals:2026-10-02")
	assert_eq(p.intervals_athlete_id, "i12345")
	assert_eq(p.validate(), [])


func test_local_override_blocks_sync() -> void:
	var p := _profile()
	p.power_zones = PowerZones.custom(200, [50.0, 80.0])
	var w := IntervalsSync.apply_athlete_to_profile(p, IntervalsSync.parse_athlete(_athlete_json()), true, DATE)
	assert_eq(w, [IntervalsSync.WARN_LOCAL_OVERRIDE])
	assert_eq(p.ftp_w, 200, "REQ-INT-06 крит. 4: FTP не изменился")
	assert_eq(p.power_zones.boundaries_pct, [50.0, 80.0], "зоны мощности не изменились")
	assert_eq(p.max_hr, 180)
	assert_null(p.hr_zones, "зоны пульса не изменились")
	assert_eq(p.ftp_source, Profile.SOURCE_LOCAL)
	assert_eq(p.zones_source, Profile.SOURCE_LOCAL)
	p.intervals_override_local = true
	assert_eq(IntervalsSync.sync_profile(p, {"ftp": 300}, DATE), [IntervalsSync.WARN_LOCAL_OVERRIDE], "sync_profile читает флаг профиля")
	assert_eq(p.ftp_w, 200)


func test_resync_without_override_updates_values() -> void:
	var p := _profile()
	IntervalsSync.apply_athlete_to_profile(p, {"ftp": 230, "power_zones_pct": [55.0, 75.0, 90.0]}, false, "2026-09-01")
	assert_eq(p.ftp_w, 230)
	assert_eq(p.ftp_source, "intervals:2026-09-01")
	var w := IntervalsSync.apply_athlete_to_profile(p, {"ftp": 240, "power_zones_pct": [50.0, 70.0, 90.0, 110.0]}, false, DATE)
	assert_eq(w, [IntervalsSync.WARN_HR_ZONES_MISSING, IntervalsSync.WARN_MAX_HR_MISSING])
	assert_eq(p.ftp_w, 240, "REQ-INT-06 крит. 5: повторная синхронизация обновляет FTP")
	assert_eq(p.power_zones.boundaries_pct, [50.0, 70.0, 90.0, 110.0])
	assert_eq(p.ftp_source, "intervals:2026-10-02")
	assert_eq(IntervalsSync.sync_profile(p, {"ftp": 245}, DATE).size(), 3, "флаг профиля выключен → применяется")
	assert_eq(p.ftp_w, 245)


func test_missing_or_out_of_range_ftp_keeps_local_value_with_warning() -> void:
	var p := _profile()
	var w := IntervalsSync.apply_athlete_to_profile(p, {"ftp": 0, "power_zones_pct": [55.0, 75.0]}, false, DATE)
	assert_has(w, IntervalsSync.WARN_FTP_MISSING, "REQ-INT-06 крит. 7")
	assert_eq(p.ftp_w, 200, "локальное значение сохранено")
	assert_eq(p.ftp_source, Profile.SOURCE_LOCAL)
	assert_eq(p.power_zones.boundaries_pct, [55.0, 75.0], "зоны в % применяются и без FTP")
	var w2 := IntervalsSync.apply_athlete_to_profile(p, {"ftp": 700}, false, DATE)
	assert_has(w2, IntervalsSync.WARN_FTP_OUT_OF_RANGE)
	assert_eq(p.ftp_w, 200)
	assert_eq(p.validate(), [])


# ---------------------------------------------------------------------------
# Profile: новые поля
# ---------------------------------------------------------------------------

func test_profile_new_fields_round_trip_and_defaults() -> void:
	var p := _profile()
	assert_eq(p.ftp_source, "local")
	assert_eq(p.zones_source, "local")
	assert_eq(p.intervals_athlete_id, "")
	assert_false(p.intervals_override_local)
	p.ftp_source = "intervals:2026-10-02"
	p.zones_source = "intervals:2026-10-02"
	p.intervals_athlete_id = "i12345"
	p.intervals_override_local = true
	var copy := Profile.from_dict(p.to_dict())
	assert_eq(copy.ftp_source, "intervals:2026-10-02")
	assert_eq(copy.zones_source, "intervals:2026-10-02")
	assert_eq(copy.intervals_athlete_id, "i12345")
	assert_true(copy.intervals_override_local)
	assert_eq(copy.to_dict(), p.to_dict())
	var legacy := Profile.from_dict({"id": "x", "name": "Old", "ftp_w": 200})
	assert_eq(legacy.ftp_source, "local", "старые файлы без полей → local")
	assert_eq(legacy.validate(), [])


func test_profile_rejects_unknown_source() -> void:
	var p := _profile()
	p.ftp_source = "strava"
	assert_has(p.validate(), Profile.ERR_SOURCE_INVALID)
	p.ftp_source = "intervals"
	p.zones_source = "intervals:2026-01-01"
	assert_eq(p.validate(), [])
	assert_false(p.to_dict().has("api_key"), "REQ-PRF-03 крит. 3: секретов в данных профиля нет")
