extends GutTest
## Тесты нормализации UUID и констант (REQ-DEV-01 крит. 1).


func test_constants_match_sig_assigned_numbers() -> void:
	assert_eq(BleUuids.FTMS_SERVICE, "1826")
	assert_eq(BleUuids.INDOOR_BIKE_DATA, "2AD2")
	assert_eq(BleUuids.FTMS_CONTROL_POINT, "2AD9")
	assert_eq(BleUuids.FTMS_STATUS, "2ADA")
	assert_eq(BleUuids.SUPPORTED_RESISTANCE_RANGE, "2AD6")
	assert_eq(BleUuids.HEART_RATE_MEASUREMENT, "2A37")
	assert_eq(BleUuids.CSC_MEASUREMENT, "2A5B")
	assert_eq(BleUuids.CYCLING_POWER_MEASUREMENT, "2A63")
	assert_eq(BleUuids.BATTERY_SERVICE, "180F")
	assert_eq(BleUuids.BATTERY_LEVEL, "2A19")


func test_scan_services_are_ftms_hrs_csc_cps() -> void:
	assert_eq(BleUuids.SCAN_SERVICES, PackedStringArray(["1826", "6E40FEC1-B5A3-F393-E0A9-E50E24DCCA9E", "180D", "1816", "1818"]),
		"REQ-DEV-01 крит. 1 (с FE-C, DEV-11)")


func test_normalize_short_full_and_prefixed_forms() -> void:
	assert_eq(BleUuids.normalize("2ad2"), "2AD2")
	assert_eq(BleUuids.normalize(" 0x2AD2 "), "2AD2")
	assert_eq(BleUuids.normalize("00002ad2-0000-1000-8000-00805f9b34fb"), "2AD2")
	assert_eq(BleUuids.normalize("00002AD2"), "2AD2")
	assert_eq(BleUuids.normalize("6E400001-B5A3-F393-E0A9-E50E24DCCA9E"), "6E400001-B5A3-F393-E0A9-E50E24DCCA9E",
		"128-битный не на базе SIG — без изменений")
	assert_true(BleUuids.equals("2ad2", "00002AD2-0000-1000-8000-00805F9B34FB"))


func test_to_full_expands_short_uuid() -> void:
	assert_eq(BleUuids.to_full("180d"), "0000180D-0000-1000-8000-00805F9B34FB")
	assert_eq(BleUuids.to_full("0000180D-0000-1000-8000-00805F9B34FB"), "0000180D-0000-1000-8000-00805F9B34FB")


func test_device_kind_by_services() -> void:
	assert_eq(BleUuids.device_kind(PackedStringArray(["180f", "1826"])), "trainer")
	assert_eq(BleUuids.device_kind(PackedStringArray(["180D"])), "heart_rate")
	assert_eq(BleUuids.device_kind(PackedStringArray(["1816"])), "cadence")
	assert_eq(BleUuids.device_kind(PackedStringArray(["1818", "1816"])), "cadence", "CSC приоритетнее CPS")
	assert_eq(BleUuids.device_kind(PackedStringArray(["1818"])), "power")
	assert_eq(BleUuids.device_kind(PackedStringArray()), "unknown")
