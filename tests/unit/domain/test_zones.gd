extends GutTest
## Тесты зон мощности и пульса (REQ-PRF-02, REQ-HUD-03, REQ-HUD-04).


func test_power_zone_req_prf_02_table_at_ftp_200() -> void:
	var expected := {110: 1, 111: 2, 150: 2, 151: 3, 180: 3, 181: 4,
		210: 4, 211: 5, 240: 5, 241: 6, 300: 6, 301: 7}
	for p in expected:
		assert_eq(Zones.power_zone(p, 200), expected[p], "%d Вт при FTP 200" % p)


func test_power_zone_boundary_belongs_to_lower_zone() -> void:
	# Ровно на границе (55 % от 200 = 110) → нижняя зона.
	assert_eq(Zones.power_zone(110, 200), 1)
	assert_eq(Zones.power_zone(300, 200), 6)
	# Нечётное FTP: 55 % от 250 = 137.5 → 137 Z1, 138 Z2.
	assert_eq(Zones.power_zone(137, 250), 1)
	assert_eq(Zones.power_zone(138, 250), 2)


func test_power_zone_zero_power_is_z1_and_bad_ftp_is_zero() -> void:
	assert_eq(Zones.power_zone(0, 200), 1, "REQ-HUD-03 крит. 3")
	assert_eq(Zones.power_zone(200, 0), 0)
	assert_eq(Zones.power_zone(200, -5), 0)
	assert_eq(Zones.power_zone(5000, 200), 7)


func test_power_zones_custom_boundaries() -> void:
	var z := PowerZones.custom(100, [50.0, 100.0] as Array[float])
	assert_eq(z.zone_count(), 3)
	assert_eq(z.zone_of(50), 1)
	assert_eq(z.zone_of(51), 2)
	assert_eq(z.zone_of(100), 2)
	assert_eq(z.zone_of(101), 3)
	assert_eq(z.validate().size(), 0)


func test_power_zones_lower_watts() -> void:
	var z := PowerZones.coggan(200)
	assert_eq(z.zone_lower_watts(1), 0)
	assert_eq(z.zone_lower_watts(2), 111)
	assert_eq(z.zone_lower_watts(7), 301)
	assert_eq(z.zone_lower_watts(8), 0)


func test_power_zones_validate_rejects_bad_boundaries() -> void:
	assert_eq(PowerZones.coggan(0).validate().size(), 1)
	assert_eq(PowerZones.custom(200, [75.0, 55.0] as Array[float]).validate().size(), 1)
	assert_eq(PowerZones.custom(200, [] as Array[float]).validate().size(), 1)
	assert_eq(PowerZones.custom(200, [-1.0, 50.0] as Array[float]).validate().size(), 1)


func test_coggan_default_boundaries_not_shared_between_instances() -> void:
	var a := PowerZones.coggan(200)
	var b := PowerZones.coggan(200)
	a.boundaries_pct[0] = 10.0
	assert_eq(b.boundaries_pct[0], 55.0)
	assert_eq(PowerZones.COGGAN_BOUNDARIES_PCT[0], 55.0)


func test_hr_zone_req_hud_04_at_max_180() -> void:
	assert_eq(Zones.hr_zone(107, 180), 1)
	assert_eq(Zones.hr_zone(108, 180), 2)
	assert_eq(Zones.hr_zone(126, 180), 3)
	assert_eq(Zones.hr_zone(144, 180), 4)
	assert_eq(Zones.hr_zone(162, 180), 5)
	assert_eq(Zones.hr_zone(200, 180), 5)


func test_hr_zone_boundary_belongs_to_upper_zone() -> void:
	# 60 % от 180 = 108 → уже Z2 (в отличие от зон мощности).
	assert_eq(Zones.hr_zone(108, 180), 2)
	assert_eq(Zones.hr_zone(125, 180), 2)
	assert_eq(Zones.hr_zone(126, 180), 3)
	assert_eq(Zones.hr_zone(161, 180), 4)


func test_hr_zone_no_data_is_zero() -> void:
	assert_eq(Zones.hr_zone(0, 180), 0, "REQ-HUD-04 крит. 2")
	assert_eq(Zones.hr_zone(120, 0), 0)
	assert_eq(Zones.hr_zone(-3, 180), 0)


func test_hr_zones_custom_boundaries_and_validate() -> void:
	var z := HrZones.custom(200, [50.0, 75.0] as Array[float])
	assert_eq(z.zone_count(), 3)
	assert_eq(z.zone_of(99), 1)
	assert_eq(z.zone_of(100), 2)
	assert_eq(z.zone_of(150), 3)
	assert_eq(z.validate().size(), 0)
	assert_eq(HrZones.custom(200, [75.0, 50.0] as Array[float]).validate().size(), 1)
	assert_eq(HrZones.five_zone(0).validate().size(), 1)


func test_hr_zones_custom_bpm_matches_five_zone_180_without_max_hr() -> void:
	var abs_z := HrZones.custom_bpm([108, 126, 144, 162] as Array[int])
	var rel_z := HrZones.five_zone(180)
	assert_true(abs_z.is_absolute())
	assert_eq(abs_z.max_hr, 0, "max_hr не нужен")
	assert_eq(abs_z.zone_count(), 5)
	for bpm in range(0, 221):
		assert_eq(abs_z.zone_of(bpm), rel_z.zone_of(bpm), "bpm=%d" % bpm)
	assert_eq(abs_z.zone_of(107), 1)
	assert_eq(abs_z.zone_of(108), 2, "граница → верхняя зона, как и у относительных")
	assert_eq(abs_z.zone_of(0), 0)
	assert_eq(abs_z.validate().size(), 0)


func test_hr_zones_custom_bpm_validate_monotonic() -> void:
	assert_eq(HrZones.custom_bpm([126, 108] as Array[int]).validate().size(), 1)
	assert_eq(HrZones.custom_bpm([108, 108] as Array[int]).validate().size(), 1)
	assert_eq(HrZones.custom_bpm([0, 120] as Array[int]).validate().size(), 1)
	assert_eq(HrZones.custom_bpm([120, 140, 160] as Array[int]).zone_count(), 4)
