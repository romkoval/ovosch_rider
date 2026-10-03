extends SceneTree
## CI (macOS): проверяет, что собранный GDExtension загружается движком и класс
## `OvoschBle` реализует контракт `BleBridge` 1:1 (REQ-DEV-01 крит. 6, REQ-NFR-06 крит. 2).
##
## Экземпляр `OvoschBle` не создаётся: бэкенд CoreBluetooth при инициализации обращается
## к Bluetooth, а у редактора Godot нет NSBluetoothAlwaysUsageDescription — macOS
## завершил бы процесс по TCC. Проверяются только регистрация класса, методы и сигналы.
##
## Запуск: Godot --headless --path . --script res://scripts/ci/check_native_ble.gd

const NATIVE_CLASS: StringName = &"OvoschBle"
const CONTRACT: String = "res://src/devices/ble/ble_bridge.gd"


func _init() -> void:
	var failures: Array[String] = []
	if not ClassDB.class_exists(NATIVE_CLASS):
		failures.append("класс %s не зарегистрирован (GDExtension не загружен)" % NATIVE_CLASS)
	else:
		var contract: Script = load(CONTRACT)
		var native_methods: Array[String] = []
		for m in ClassDB.class_get_method_list(NATIVE_CLASS, true):
			native_methods.append(str(m["name"]))
		for m in contract.get_script_method_list():
			var method_name := str(m["name"])
			# Статические помощники контракта (create_default, adapter_state_name) — не часть моста.
			if method_name.begins_with("_") or (int(m["flags"]) & METHOD_FLAG_STATIC) != 0:
				continue
			if not native_methods.has(method_name):
				failures.append("нет метода %s" % method_name)
		var native_signals: Array[String] = []
		for s in ClassDB.class_get_signal_list(NATIVE_CLASS, true):
			native_signals.append(str(s["name"]))
		for s in contract.get_script_signal_list():
			if not native_signals.has(str(s["name"])):
				failures.append("нет сигнала %s" % s["name"])
	if failures.is_empty():
		print("check_native_ble: OK — %s загружен, контракт BleBridge совпадает" % NATIVE_CLASS)
		quit(0)
	else:
		for f in failures:
			printerr("check_native_ble: " + f)
		quit(1)
