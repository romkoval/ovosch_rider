class_name TrainerFactory
extends RefCounted
## Фабрика реализаций `TrainerDevice`. Единственное место, где известно,
## какая реализация станка подключена (REQ-DEV-09 крит. 1).

## Идентификаторы реализаций.
const KIND_FAKE: String = "fake"
const KIND_BLE: String = "ble"

## Последовательность синтетического пульса: считается один раз, `FakeTrainer` копирует её себе.
static var _heart_rate_sequence: Array[int] = []


## Создать устройство по имени реализации: `"fake"` — эмулятор `FakeTrainer` с синтетическим
## пульсом `FakeHeartRateCurve` (95 → 165 уд/мин за 20 мин, затем плато; REQ-DEV-09 п.5 —
## пульс в dev-режиме), `"ble"` — `BleTrainer` поверх `BleBridge.create_default()`, но только
## если загружен нативный BLE-модуль (иначе `BleTrainer` сел бы на заглушку и
## «подключался» к несуществующему станку) — без модуля возвращает null
## с предупреждением. Неизвестный `kind` → null с ошибкой.
static func create(kind: String) -> TrainerDevice:
	match kind:
		KIND_FAKE:
			return _create_fake()
		KIND_BLE:
			if not NativeBleBridge.is_native_available():
				push_warning("TrainerFactory: нативный BLE-модуль не загружен, BleTrainer недоступен, возвращён null")
				return null
			return BleTrainer.new(BleBridge.create_default())
	push_error("TrainerFactory: неизвестная реализация станка '%s'" % kind)
	return null


## Эмулятор для приложения (dev-режим, «тренировка на эмуляторе», снимки UI): `FakeTrainer`
## с синтетическим пульсом. Тестам, которым пульс не нужен, — `FakeTrainer.new()` напрямую.
static func _create_fake() -> TrainerDevice:
	if _heart_rate_sequence.is_empty():
		_heart_rate_sequence = FakeHeartRateCurve.new().sequence()
	var trainer := FakeTrainer.new()
	trainer.set_heart_rate_sequence(_heart_rate_sequence)
	return trainer


## `BleTrainer` поверх явно переданного моста (тесты на `StubBleBridge`, инъекция).
static func create_ble(bridge: BleBridge) -> TrainerDevice:
	return BleTrainer.new(bridge)
