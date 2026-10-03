class_name DevicesScreen
extends Control
## Devices screen (`AppState.Screen.DEVICES`): remembered and discovered devices with
## kind, RSSI, connection state and battery; scan / connect / forget / auto-connect
## (REQ-DEV-01 crit. 2-4, REQ-DEV-06 crit. 2-4, REQ-DEV-07 crit. 1-3).
## Works only through `ConnectionManager`; all strings are translation keys.

var _manager: ConnectionManager
var _repo: ProfileRepository
var _app_state: AppState
var _rows: Dictionary = {}
## Не найденные при автоподключении (REQ-DEV-06 крит. 3). Сбрасывается при новом поиске
## (сканирование, новое автоподключение) и при смене профиля; подключившееся устройство
## убирается из списка. Вход на экран список не сбрасывает.
var _not_found_ids: Array[String] = []
## Профиль, для которого получен `_not_found_ids`.
var _not_found_profile_id: String = ""
## id строки, кнопка которой сейчас обрабатывает нажатие (см. `refresh`).
var _row_in_signal: String = ""

@onready var _status_label: Label = %StatusLabel
@onready var _scan_button: Button = %ScanButton
@onready var _auto_connect_check: CheckButton = %AutoConnectCheck
@onready var _back_button: Button = %BackButton
@onready var _remembered_list: VBoxContainer = %RememberedList
@onready var _found_list: VBoxContainer = %FoundList


func setup(manager: ConnectionManager, repo: ProfileRepository, app_state: AppState) -> void:
	if _manager != null and _manager != manager:
		_manager.devices_changed.disconnect(refresh)
		_manager.state_changed.disconnect(_on_state_changed)
		_manager.auto_connect_timed_out.disconnect(_on_auto_connect_timed_out)
	_manager = manager
	_repo = repo
	_app_state = app_state
	if not _manager.devices_changed.is_connected(refresh):
		_manager.devices_changed.connect(refresh)
		_manager.state_changed.connect(_on_state_changed)
		_manager.auto_connect_timed_out.connect(_on_auto_connect_timed_out)
	if is_node_ready():
		refresh()


func _ready() -> void:
	_scan_button.pressed.connect(toggle_scan)
	_auto_connect_check.toggled.connect(set_auto_connect)
	_back_button.pressed.connect(back)
	if _manager != null:
		refresh()


func profile_id() -> String:
	return _repo.active_profile_id if _repo != null else ""


func toggle_scan() -> void:
	if _manager == null:
		return
	if _manager.scanner.is_scanning():
		_manager.stop_scan()
	else:
		_not_found_ids.clear()
		_manager.start_scan()
	refresh()


func set_auto_connect(enabled: bool) -> void:
	if _manager == null:
		return
	_manager.auto_connect_enabled = enabled
	if enabled:
		_not_found_ids.clear()
		_manager.auto_connect(profile_id())
	else:
		_manager.cancel_auto_connect()
	refresh()


func connect_device(record: Dictionary) -> void:
	if _manager == null:
		return
	if _manager.is_device_connected(str(record.get("id", ""))):
		_manager.disconnect_device(str(record.get("id", "")))
	else:
		_manager.connect_record(record)
	refresh()


func forget_device(id: String) -> void:
	if _manager == null:
		return
	_manager.forget(profile_id(), id)
	refresh()


## Leaving the screen stops scanning (REQ-DEV-01 crit. 4); auto-connect keeps its own scan.
func back() -> void:
	_stop_user_scan()
	if _app_state != null:
		_app_state.navigate(AppState.Screen.HOME)


func _notification(what: int) -> void:
	# Вход на экран список «не найдено» не сбрасывает: таймаут автоподключения, истёкший
	# на другом экране, должен быть виден (REQ-DEV-06 крит. 3).
	if what == NOTIFICATION_VISIBILITY_CHANGED and is_node_ready() and not visible:
		_stop_user_scan()


func _stop_user_scan() -> void:
	if _manager != null and not _manager.is_auto_connecting():
		_manager.stop_scan()


## Incremental refresh: rows are kept and updated in place, moved between the lists
## when a device becomes remembered/forgotten, and freed only when the device vanishes
## (no rebuild on every signal, no orphan nodes from queued frees).
func refresh() -> void:
	if _manager == null or not is_node_ready():
		return
	# Смена профиля или новое автоподключение (в т.ч. запущенное при выборе профиля):
	# список «не найдено» относится к прежнему поиску.
	if profile_id() != _not_found_profile_id or _manager.is_auto_connecting():
		_not_found_ids.clear()
	_not_found_profile_id = profile_id()
	var seen: Dictionary = {}
	var remembered_ids: Array[String] = []
	var index_remembered: int = 0
	for record in _manager.remembered.list(profile_id()):
		var id: String = str(record["id"])
		remembered_ids.append(id)
		_place_row(record, true, _remembered_list, index_remembered)
		index_remembered += 1
		seen[id] = true
	var index_found: int = 0
	for found in _manager.scanner.devices:
		var id: String = str(found["id"])
		if remembered_ids.has(id):
			continue
		_place_row(found, false, _found_list, index_found)
		index_found += 1
		seen[id] = true
	for id in _rows.keys():
		if not seen.has(id):
			var hbox: HBoxContainer = _rows[id]["hbox"]
			if hbox.get_parent() != null:
				hbox.get_parent().remove_child(hbox)
			# Отсоединённая строка освобождается сразу (без «сирот» до следующего кадра).
			# Строку, чья кнопка сейчас испускает `pressed`, освобождать синхронно нельзя:
			# кнопка обращается к себе после сигнала — для неё отложенное освобождение.
			if str(id) == _row_in_signal:
				hbox.queue_free()
			else:
				hbox.free()
			_rows.erase(id)
	var available: bool = _manager.is_ble_available()
	_scan_button.text = tr("ui.devices.stop_scan") if _manager.scanner.is_scanning() else tr("ui.devices.scan")
	_scan_button.disabled = not available
	_auto_connect_check.set_pressed_no_signal(_manager.auto_connect_enabled)
	_status_label.text = _status_text()


## Row for a device id: `{id, record, label, connect_button, forget_button}` or {};
## `forget_button` is null for discovered (not remembered) devices.
func row(id: String) -> Dictionary:
	if not _rows.has(id):
		return {}
	var r: Dictionary = (_rows[id] as Dictionary).duplicate()
	var forget: Button = r["forget_button"]
	if not forget.visible:
		r["forget_button"] = null
	return r


func row_ids() -> Array[String]:
	var out: Array[String] = []
	for id in _rows:
		out.append(str(id))
	return out


func status_text() -> String:
	return _status_label.text


func row_text(id: String) -> String:
	var r := row(id)
	return (r["label"] as Label).text if not r.is_empty() else ""


static func kind_key(kind: String) -> String:
	match kind:
		RememberedDevices.KIND_TRAINER:
			return "ui.devices.kind.trainer"
		RememberedDevices.KIND_HR:
			return "ui.devices.kind.hr"
		RememberedDevices.KIND_CADENCE:
			return "ui.devices.kind.cadence"
		RememberedDevices.KIND_POWER:
			return "ui.devices.kind.power"
	return "ui.devices.kind.unknown"


static func state_key(state: int) -> String:
	match state:
		TrainerDevice.ConnectionState.CONNECTING, TrainerDevice.ConnectionState.SCANNING:
			return "ui.devices.state.connecting"
		TrainerDevice.ConnectionState.CONNECTED:
			return "ui.devices.state.connected"
		TrainerDevice.ConnectionState.RECONNECTING:
			return "ui.devices.state.reconnecting"
	return "ui.devices.state.disconnected"


func _status_text() -> String:
	if not _manager.is_ble_available():
		return tr("ui.devices.ble_unavailable")
	if _manager.is_auto_connecting():
		return tr("ui.devices.status.auto_connecting").format({"count": _manager.pending_auto_connect_ids().size()})
	if not _not_found_ids.is_empty():
		return tr("ui.devices.status.not_found").format({"names": ", ".join(_names_of(_not_found_ids))})
	if _manager.scanner.is_scanning():
		return tr("ui.devices.status.scanning")
	return tr("ui.devices.status.idle")


func _names_of(ids: Array[String]) -> PackedStringArray:
	var out := PackedStringArray()
	for id in ids:
		var rec := _manager.remembered.find(profile_id(), id)
		var name := str(rec.get("name", ""))
		out.append(name if not name.is_empty() else id)
	return out


func _place_row(record: Dictionary, is_remembered: bool, parent: VBoxContainer, index: int) -> void:
	var id: String = str(record["id"])
	if not _rows.has(id):
		_rows[id] = _create_row(id)
	var r: Dictionary = _rows[id]
	r["record"] = record.duplicate()
	var hbox: HBoxContainer = r["hbox"]
	if hbox.get_parent() != parent:
		if hbox.get_parent() != null:
			hbox.get_parent().remove_child(hbox)
		parent.add_child(hbox)
	if hbox.get_index() != index:
		parent.move_child(hbox, index)
	_update_row(r, record, is_remembered)


func _create_row(id: String) -> Dictionary:
	var hbox := HBoxContainer.new()
	hbox.name = "Row_" + id.validate_node_name()
	var label := Label.new()
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(label)
	var connect_button := Button.new()
	connect_button.pressed.connect(func() -> void: _on_row_button(id, false))
	hbox.add_child(connect_button)
	var forget_button := Button.new()
	forget_button.pressed.connect(func() -> void: _on_row_button(id, true))
	hbox.add_child(forget_button)
	return {"id": id, "record": {}, "hbox": hbox, "label": label, "connect_button": connect_button, "forget_button": forget_button}


func _update_row(r: Dictionary, record: Dictionary, is_remembered: bool) -> void:
	var id: String = str(record["id"])
	var name: String = str(record.get("name", ""))
	if name.is_empty():
		name = tr("ui.devices.unnamed")
	var state: int = _manager.state_of(id)
	var battery: int = _manager.battery_of(id)
	var parts: PackedStringArray = [name, tr(kind_key(str(record.get("kind", ""))))]
	if record.has("rssi"):
		parts.append(tr("ui.devices.rssi").format({"rssi": record["rssi"]}))
		if not record.get("available", true):
			parts.append(tr("ui.devices.unavailable"))
	parts.append(tr(state_key(state)))
	parts.append(tr("ui.devices.battery").format({"percent": battery}) if battery >= 0 else tr("ui.devices.battery_unknown"))
	(r["label"] as Label).text = " · ".join(parts)
	var connect_button: Button = r["connect_button"]
	connect_button.text = tr("ui.devices.disconnect") if state == TrainerDevice.ConnectionState.CONNECTED else tr("ui.devices.connect")
	connect_button.disabled = str(record.get("kind", "")) == BleScanner.KIND_UNKNOWN or not _manager.is_ble_available()
	var forget_button: Button = r["forget_button"]
	forget_button.text = tr("ui.devices.forget")
	forget_button.visible = is_remembered


func _on_row_button(id: String, forget: bool) -> void:
	_row_in_signal = id
	if forget:
		forget_device(id)
	elif _rows.has(id):
		connect_device(_rows[id]["record"])
	_row_in_signal = ""


func _on_state_changed(id: String) -> void:
	# Успешное подключение: устройство найдено — убрать его из «не найдено».
	if _manager != null and _manager.state_of(id) == TrainerDevice.ConnectionState.CONNECTED:
		_not_found_ids.erase(id)
	refresh()


func _on_auto_connect_timed_out(ids: Array[String]) -> void:
	_not_found_ids = ids.duplicate()
	_not_found_profile_id = profile_id()
	refresh()
