class_name TrainerFactory
extends RefCounted
## Фабрика реализаций `TrainerDevice`. Единственное место, где известно,
## какая реализация станка подключена (REQ-DEV-09 крит. 1).

## Идентификаторы реализаций.
const KIND_FAKE: String = "fake"
const KIND_BLE: String = "ble"


## Создать устройство по имени реализации: `"fake"` — эмулятор `FakeTrainer`,
## `"ble"` — нативный мост (появится на этапе 2; пока возвращает null с предупреждением).
## Неизвестный `kind` → null с ошибкой.
static func create(kind: String) -> TrainerDevice:
	match kind:
		KIND_FAKE:
			return FakeTrainer.new()
		KIND_BLE:
			push_warning("TrainerFactory: реализация BleTrainer ещё не доступна (этап 2), возвращён null")
			return null
	push_error("TrainerFactory: неизвестная реализация станка '%s'" % kind)
	return null
