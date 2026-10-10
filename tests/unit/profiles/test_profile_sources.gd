extends GutTest
## Старое поле источника мощности профиля (REQ-WRK-09 п.14 (г)) и сброс источника FTP/зон
## в `local` при ручной правке (REQ-INT-06 крит. 4).


## WRK-09 п.14 (г), У-32 (T-170): выбора источника мощности в профиле нет; старые профили с полем
## «power_source» читаются без ошибок, поле больше не пишется.
func test_legacy_power_source_field_is_ignored() -> void:
	var p := Profile.create("A")
	assert_false("power_source" in p, "поля нет")
	assert_false(p.to_dict().has("power_source"))
	for value: Variant in ["power_meter", "trainer", "", "bananas", 5]:
		var legacy := Profile.from_dict({"id": "x", "name": "Old", "ftp_w": 200, "weight_kg": 70.0, "power_source": value})
		assert_not_null(legacy)
		assert_eq(legacy.validate(), [] as Array[String], "старый профиль с power_source=%s валиден" % str(value))
		assert_eq(legacy.ftp_w, 200)


func test_set_ftp_local_resets_source_after_sync() -> void:
	var p := Profile.create("A")
	p.ftp_w = 200
	var athlete := {"id": "i1", "ftp": 250, "power_zones_pct": [55.0, 75.0, 90.0, 105.0, 120.0, 150.0],
		"hr_zones_bpm": [120, 140, 160, 180], "max_hr": 190}
	var warnings := IntervalsSync.sync_profile(p, athlete, "2026-10-03")
	assert_eq(warnings.size(), 0)
	assert_eq(p.ftp_w, 250)
	assert_eq(p.ftp_source, "intervals:2026-10-03", "синхронизация пишет intervals:<дата>")
	assert_eq(p.zones_source, "intervals:2026-10-03")
	p.set_ftp_local(260)
	assert_eq(p.ftp_w, 260)
	assert_eq(p.ftp_source, Profile.SOURCE_LOCAL, "REQ-INT-06 крит. 4: ручная правка → local")
	assert_eq(p.zones_source, "intervals:2026-10-03", "зоны не трогались")
	IntervalsSync.sync_profile(p, athlete, "2026-10-04")
	assert_eq(p.ftp_source, "intervals:2026-10-04", "повторная синхронизация снова intervals")
	p.set_ftp_local(255)
	assert_eq(p.ftp_source, Profile.SOURCE_LOCAL, "и снова local после правки")
	assert_true(p.is_valid())


func test_set_zones_local_resets_zones_source() -> void:
	var p := Profile.create("A")
	p.zones_source = "intervals:2026-10-03"
	p.set_power_zones_local(PowerZones.custom(p.ftp_w, [50.0, 70.0, 90.0, 110.0, 130.0, 160.0] as Array[float]))
	assert_eq(p.zones_source, Profile.SOURCE_LOCAL)
	assert_eq(p.effective_power_zones().boundaries_pct[0], 50.0)
	p.zones_source = "intervals:2026-10-03"
	p.set_hr_zones_local(null)
	assert_eq(p.zones_source, Profile.SOURCE_LOCAL)
	assert_null(p.hr_zones, "null — зоны по умолчанию от max_hr")
	p.zones_source = "intervals:2026-10-03"
	p.set_power_zones_local(null)
	assert_eq(p.zones_source, Profile.SOURCE_LOCAL)
	assert_null(p.power_zones)
	assert_true(p.is_valid())
