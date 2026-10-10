class_name BleUuids
extends RefCounted
## UUID сервисов и характеристик BLE, используемых приложением (REQ-DEV-01..07).
##
## Все UUID — 16-битные из Bluetooth SIG Assigned Numbers, хранятся как строки
## в верхнем регистре без префикса ("1826"). `normalize()` приводит к этому виду
## любую запись: нижний регистр, "0x1826", полный 128-битный UUID на базе
## Bluetooth Base UUID (0000xxxx-0000-1000-8000-00805F9B34FB).

## Fitness Machine Service (FTMS) и его характеристики.
const FTMS_SERVICE: String = "1826"
const INDOOR_BIKE_DATA: String = "2AD2"
const FTMS_CONTROL_POINT: String = "2AD9"
const FTMS_STATUS: String = "2ADA"
## Fitness Machine Feature: поддержка SIM в Target Setting Features (REQ-FRD-04 крит. 6).
const FITNESS_MACHINE_FEATURE: String = "2ACC"
## Supported Inclination Range: ограничение уклона SIM (REQ-FRD-04 крит. 3).
const SUPPORTED_INCLINATION_RANGE: String = "2AD5"
const SUPPORTED_RESISTANCE_RANGE: String = "2AD6"
const SUPPORTED_POWER_RANGE: String = "2AD8"
## Heart Rate Service.
const HRS_SERVICE: String = "180D"
const HEART_RATE_MEASUREMENT: String = "2A37"
## Cycling Speed and Cadence.
const CSC_SERVICE: String = "1816"
const CSC_MEASUREMENT: String = "2A5B"
## Cycling Power Service.
const CPS_SERVICE: String = "1818"
const CYCLING_POWER_MEASUREMENT: String = "2A63"
## Battery Service.
const BATTERY_SERVICE: String = "180F"
const BATTERY_LEVEL: String = "2A19"
## FE-C over BLE (REQ-DEV-11): сервис FEC1, нотификации станка FEC2, запись на станок FEC3 —
## 128-битные UUID, хранятся полной формой в верхнем регистре.
const FEC_SERVICE: String = "6E40FEC1-B5A3-F393-E0A9-E50E24DCCA9E"
const FEC_NOTIFY: String = "6E40FEC2-B5A3-F393-E0A9-E50E24DCCA9E"
const FEC_WRITE: String = "6E40FEC3-B5A3-F393-E0A9-E50E24DCCA9E"

## Сервисы, по которым идёт сканирование (REQ-DEV-01 крит. 1): FTMS, FE-C, HRS, CSC, CPS.
const SCAN_SERVICES: PackedStringArray = ["1826", "6E40FEC1-B5A3-F393-E0A9-E50E24DCCA9E", "180D", "1816", "1818"]

const BASE_UUID_SUFFIX: String = "-0000-1000-8000-00805F9B34FB"


## Приводит UUID к короткой форме в верхнем регистре, если это 16-битный UUID
## на базе Bluetooth Base UUID; иначе возвращает полный UUID в верхнем регистре.
static func normalize(uuid: String) -> String:
	var u: String = uuid.strip_edges().to_upper()
	if u.begins_with("0X"):
		u = u.substr(2)
	if u.length() == 36 and u.begins_with("0000") and u.ends_with(BASE_UUID_SUFFIX):
		return u.substr(4, 4)
	if u.length() == 8 and u.begins_with("0000"):
		return u.substr(4, 4)
	return u


## Полная 128-битная форма 16-битного UUID.
static func to_full(uuid: String) -> String:
	var u: String = normalize(uuid)
	if u.length() == 4:
		return "0000" + u + BASE_UUID_SUFFIX
	return u


static func equals(a: String, b: String) -> bool:
	return normalize(a) == normalize(b)


## Тип устройства по списку сервисов рекламы: "trainer" | "heart_rate" |
## "cadence" | "power" | "unknown" (первый подходящий в этом порядке). «Станок» — FTMS или
## FE-C (REQ-DEV-10 п.1, DEV-11 п.1 (а)); CSC и CPS станка в тип не входят.
static func device_kind(service_uuids: PackedStringArray) -> String:
	var set: Dictionary = {}
	for s in service_uuids:
		set[normalize(s)] = true
	if is_trainer_service_set(set):
		return "trainer"
	if set.has(HRS_SERVICE):
		return "heart_rate"
	if set.has(CSC_SERVICE):
		return "cadence"
	if set.has(CPS_SERVICE):
		return "power"
	return "unknown"


## В наборе сервисов (ключи — нормализованные UUID) есть сервис станка: FTMS или FE-C.
static func is_trainer_service_set(normalized: Dictionary) -> bool:
	return normalized.has(FTMS_SERVICE) or normalized.has(FEC_SERVICE)
