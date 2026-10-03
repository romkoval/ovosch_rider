class_name FitDefinitions
extends RefCounted
## Константы протокола и профиля FIT (Garmin FIT SDK), используемые кодировщиком
## и тестовым декодером (REQ-LOC-05, REQ-STR-02 крит. 2).

## Начало эпохи FIT: 1989-12-31T00:00:00Z в unix-секундах.
const FIT_EPOCH_UNIX: int = 631065600

const HEADER_SIZE: int = 14
## Protocol 2.0: старшие 4 бита — major, младшие — minor.
const PROTOCOL_VERSION: int = 0x20
## Profile 21.60 → 2160 (major × 100 + minor).
const PROFILE_VERSION: int = 2160
const SIGNATURE: String = ".FIT"

# --- Заголовок записи ---
const HDR_DEFINITION: int = 0x40
const HDR_DEVELOPER_DATA: int = 0x20
const HDR_COMPRESSED_TIMESTAMP: int = 0x80
const HDR_LOCAL_MASK: int = 0x0F

# --- Базовые типы ---
const T_ENUM: int = 0x00
const T_SINT8: int = 0x01
const T_UINT8: int = 0x02
const T_SINT16: int = 0x83
const T_UINT16: int = 0x84
const T_SINT32: int = 0x85
const T_UINT32: int = 0x86
const T_STRING: int = 0x07
const T_FLOAT32: int = 0x88
const T_FLOAT64: int = 0x89
const T_UINT8Z: int = 0x0A
const T_UINT16Z: int = 0x8B
const T_UINT32Z: int = 0x8C
const T_BYTE: int = 0x0D
const T_SINT64: int = 0x8E
const T_UINT64: int = 0x8F
const T_UINT64Z: int = 0x90

## Размер одного значения базового типа, байт.
const BASE_SIZE: Dictionary = {
	T_ENUM: 1, T_SINT8: 1, T_UINT8: 1, T_SINT16: 2, T_UINT16: 2, T_SINT32: 4, T_UINT32: 4,
	T_STRING: 1, T_FLOAT32: 4, T_FLOAT64: 8, T_UINT8Z: 1, T_UINT16Z: 2, T_UINT32Z: 4,
	T_BYTE: 1, T_SINT64: 8, T_UINT64: 8, T_UINT64Z: 8,
}

## Invalid-значение базового типа (REQ-LOC-05 крит. 3).
const INVALID: Dictionary = {
	T_ENUM: 0xFF, T_SINT8: 0x7F, T_UINT8: 0xFF, T_SINT16: 0x7FFF, T_UINT16: 0xFFFF,
	T_SINT32: 0x7FFFFFFF, T_UINT32: 0xFFFFFFFF, T_STRING: 0x00, T_FLOAT32: 0xFFFFFFFF,
	T_FLOAT64: -1, T_UINT8Z: 0x00, T_UINT16Z: 0x0000, T_UINT32Z: 0x00000000, T_BYTE: 0xFF,
	T_SINT64: 0x7FFFFFFFFFFFFFFF, T_UINT64: -1, T_UINT64Z: 0,
}

# --- Глобальные номера сообщений ---
const MSG_FILE_ID: int = 0
const MSG_SESSION: int = 18
const MSG_LAP: int = 19
const MSG_RECORD: int = 20
const MSG_EVENT: int = 21
const MSG_DEVICE_INFO: int = 23
const MSG_ACTIVITY: int = 34
const MSG_FILE_CREATOR: int = 49

## Общие поля.
const F_TIMESTAMP: int = 253
const F_MESSAGE_INDEX: int = 254

# file_id
const FILE_ID_TYPE: int = 0
const FILE_ID_MANUFACTURER: int = 1
const FILE_ID_PRODUCT: int = 2
const FILE_ID_SERIAL_NUMBER: int = 3
const FILE_ID_TIME_CREATED: int = 4
const FILE_ID_PRODUCT_NAME: int = 8
const FILE_TYPE_ACTIVITY: int = 4
const MANUFACTURER_DEVELOPMENT: int = 255

# file_creator
const FILE_CREATOR_SOFTWARE_VERSION: int = 0
const FILE_CREATOR_HARDWARE_VERSION: int = 1

# device_info
const DEVICE_INFO_DEVICE_INDEX: int = 0
const DEVICE_INFO_MANUFACTURER: int = 2
const DEVICE_INFO_PRODUCT: int = 4
const DEVICE_INFO_SOFTWARE_VERSION: int = 5
const DEVICE_INFO_PRODUCT_NAME: int = 27
const DEVICE_INDEX_CREATOR: int = 0

# event
const EVENT_EVENT: int = 0
const EVENT_EVENT_TYPE: int = 1
const EVENT_DATA: int = 3
const EVENT_EVENT_GROUP: int = 4
const EVENT_TIMER: int = 0
const EVENT_SESSION: int = 8
const EVENT_LAP: int = 9
const EVENT_ACTIVITY: int = 26
const EVENT_TYPE_START: int = 0
const EVENT_TYPE_STOP: int = 1
const EVENT_TYPE_STOP_ALL: int = 4

# record
const RECORD_HEART_RATE: int = 3
const RECORD_CADENCE: int = 4
const RECORD_DISTANCE: int = 5
const RECORD_SPEED: int = 6
const RECORD_POWER: int = 7

# lap
const LAP_EVENT: int = 0
const LAP_EVENT_TYPE: int = 1
const LAP_START_TIME: int = 2
const LAP_TOTAL_ELAPSED_TIME: int = 7
const LAP_TOTAL_TIMER_TIME: int = 8
const LAP_TOTAL_DISTANCE: int = 9
const LAP_AVG_HEART_RATE: int = 15
const LAP_MAX_HEART_RATE: int = 16
const LAP_AVG_CADENCE: int = 17
const LAP_AVG_POWER: int = 19
const LAP_MAX_POWER: int = 20
const LAP_LAP_TRIGGER: int = 24
const LAP_SPORT: int = 25
const LAP_TRIGGER_MANUAL: int = 0

# session
const SESSION_EVENT: int = 0
const SESSION_EVENT_TYPE: int = 1
const SESSION_START_TIME: int = 2
const SESSION_SPORT: int = 5
const SESSION_SUB_SPORT: int = 6
const SESSION_TOTAL_ELAPSED_TIME: int = 7
const SESSION_TOTAL_TIMER_TIME: int = 8
const SESSION_TOTAL_DISTANCE: int = 9
const SESSION_AVG_SPEED: int = 14
const SESSION_AVG_HEART_RATE: int = 16
const SESSION_MAX_HEART_RATE: int = 17
const SESSION_AVG_CADENCE: int = 18
const SESSION_MAX_CADENCE: int = 19
const SESSION_AVG_POWER: int = 20
const SESSION_MAX_POWER: int = 21
const SESSION_FIRST_LAP_INDEX: int = 25
const SESSION_NUM_LAPS: int = 26
const SESSION_TRIGGER: int = 28
const SESSION_NORMALIZED_POWER: int = 34
const SESSION_TOTAL_WORK: int = 48
const SESSION_THRESHOLD_POWER: int = 62
const SPORT_CYCLING: int = 2
const SUB_SPORT_VIRTUAL_ACTIVITY: int = 58
const SESSION_TRIGGER_ACTIVITY_END: int = 0

# activity
const ACTIVITY_TOTAL_TIMER_TIME: int = 0
const ACTIVITY_NUM_SESSIONS: int = 1
const ACTIVITY_TYPE: int = 2
const ACTIVITY_EVENT: int = 3
const ACTIVITY_EVENT_TYPE: int = 4
const ACTIVITY_LOCAL_TIMESTAMP: int = 5
const ACTIVITY_TYPE_MANUAL: int = 0


## unix-секунды → метка времени FIT.
static func to_fit_time(unix_sec: int) -> int:
	return maxi(unix_sec - FIT_EPOCH_UNIX, 0)


## Метка времени FIT → unix-секунды.
static func from_fit_time(fit_sec: int) -> int:
	return fit_sec + FIT_EPOCH_UNIX
