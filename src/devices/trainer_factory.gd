class_name TrainerFactory
extends RefCounted
## Фабрика реализаций `TrainerDevice`. Единственное место, где известно,
## какая реализация станка подключена (REQ-DEV-09 крит. 1).

## Идентификаторы реализаций.
const KIND_FAKE: String = "fake"
const KIND_BLE: String = "ble"


## Создать устройство по имени реализации: `"fake"` — эмулятор `FakeTrainer`,
## `"ble"` — `BleTrainer` поверх `BleBridge.create_default()`, но только если
## загружен нативный BLE-модуль (иначе `BleTrainer` сел бы на заглушку и
## «подключался» к несуществующему станку) — без модуля возвращает null
## с предупреждением. Неизвестный `kind` → null с ошибкой.
static func create(kind: String) -> TrainerDevice:
	match kind:
		KIND_FAKE:
			return FakeTrainer.new()
		KIND_BLE:
			if not NativeBleBridge.is_native_available():
				push_warning("TrainerFactory: нативный BLE-модуль не загружен, BleTrainer недоступен, возвращён null")
				return null
			return BleTrainer.new(BleBridge.create_default())
	push_error("TrainerFactory: неизвестная реализация станка '%s'" % kind)
	return null


## `BleTrainer` поверх явно переданного моста (тесты на `StubBleBridge`, инъекция).
static func create_ble(bridge: BleBridge) -> TrainerDevice:
	return BleTrainer.new(bridge)
