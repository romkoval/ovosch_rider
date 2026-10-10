class_name BleDebugScreen
extends Control
## Экран «BLE-отладка» (T-165): сырые данные BLE-устройств на реальном железе — реклама,
## сервисы, характеристики, значения, запись hex и пресеты, журнал событий моста. Вся логика —
## в `BleDebugModel` (`src/devices/ble/debug/`); экран только показывает её и передаёт нажатия.
##
## Вход — скрытая строка разработчика «BLE-отладка» в «О программе» (5 нажатий на «Версию»,
## доступно и в release); экран открывается поверх настроек (`SettingsScreen.open_ble_debug`)
## и работает с общим мостом приложения (`ConnectionManager.bridge`). Пока экран открыт,
## сканирование и автоподключение `ConnectionManager` приостановлены (публичными методами
## менеджера: `cancel_auto_connect`, `stop_scan`, `auto_connect_enabled`); при закрытии
## возвращаются, как были. Устройство, подключённое экраном, при закрытии отключается, если
## оно не подключено и самим приложением.
##
## Оформление: решения `ui.md` для инструментов разработчика нет — элементы темы как есть
## (как у «Замера FPS»).

## Экран закрыт («Назад», Esc).
signal closed

## Сколько последних строк журнала показывать на экране (копируется журнал целиком).
const LOG_LINES_SHOWN: int = 300
## Не чаще, чем раз в столько секунд экран перерисовывает список, дерево и журнал.
const RENDER_INTERVAL_SEC: float = 0.25
const PRESET_KEYS: Dictionary = {
	BleDebugModel.PRESET_FTMS_REQUEST_CONTROL: "ui.ble_debug.preset_ftms_request_control",
	BleDebugModel.PRESET_FTMS_START: "ui.ble_debug.preset_ftms_start",
	BleDebugModel.PRESET_FTMS_TARGET_POWER_150: "ui.ble_debug.preset_ftms_target_power",
	BleDebugModel.PRESET_FTMS_RESET: "ui.ble_debug.preset_ftms_reset",
	BleDebugModel.PRESET_FEC_TARGET_POWER_150: "ui.ble_debug.preset_fec_target_power",
}

var model: BleDebugModel = null

var _connections: ConnectionManager = null
var _manager_suspended: bool = false
var _manager_was_scanning: bool = false
var _manager_was_auto: bool = false
var _manager_auto_enabled: bool = true
var _selected_device: String = ""
var _selected_service: String = ""
var _selected_char: String = ""
var _status_key: String = ""
var _status_count: int = 0
var _dirty_devices: bool = true
var _dirty_tree: bool = true
var _dirty_log: bool = true
var _dirty_state: bool = true
var _since_render: float = 0.0
var _closed: bool = false
var _preset_buttons: Dictionary = {}

@onready var _backdrop: ColorRect = $Backdrop
@onready var _back_button: Button = %BackButton
@onready var _adapter_label: Label = %AdapterLabel
@onready var _scan_button: Button = %ScanButton
@onready var _stop_scan_button: Button = %StopScanButton
@onready var _filter_check: CheckButton = %FilterCheck
@onready var _devices_title: Label = %DevicesTitle
@onready var _device_list: ItemList = %DeviceList
@onready var _device_info_label: Label = %DeviceInfoLabel
@onready var _connect_button: Button = %ConnectButton
@onready var _disconnect_button: Button = %DisconnectButton
@onready var _link_label: Label = %LinkLabel
@onready var _service_tree: Tree = %ServiceTree
@onready var _char_label: Label = %CharLabel
@onready var _read_button: Button = %ReadButton
@onready var _subscribe_button: Button = %SubscribeButton
@onready var _device_info_button: Button = %DeviceInfoButton
@onready var _value_label: Label = %ValueLabel
@onready var _hex_edit: LineEdit = %HexEdit
@onready var _response_check: CheckButton = %ResponseCheck
@onready var _write_button: Button = %WriteButton
@onready var _presets: HFlowContainer = %Presets
@onready var _log_title: Label = %LogTitle
@onready var _log_view: TextEdit = %LogView
@onready var _copy_log_button: Button = %CopyLogButton
@onready var _clear_log_button: Button = %ClearLogButton
@onready var _status_label: Label = %StatusLabel


## Подключить экран к мосту приложения и приостановить сканирование менеджера.
func setup(connections: ConnectionManager) -> void:
	_connections = connections
	var bridge: BleBridge = connections.bridge if connections != null else null
	model = BleDebugModel.new(bridge)
	model.devices_changed.connect(_on_devices_changed)
	model.link_changed.connect(_on_link_changed)
	model.tree_changed.connect(_on_tree_changed)
	model.value_changed.connect(_on_value_changed)
	model.log_added.connect(_on_log_added)
	_suspend_manager()


func _ready() -> void:
	_backdrop.color = UiTokens.BG
	_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	_back_button.pressed.connect(close)
	_scan_button.pressed.connect(start_scan)
	_stop_scan_button.pressed.connect(stop_scan)
	_filter_check.toggled.connect(set_app_filter)
	_device_list.item_selected.connect(_on_device_selected)
	_connect_button.pressed.connect(connect_selected)
	_disconnect_button.pressed.connect(disconnect_device)
	_service_tree.item_selected.connect(_on_tree_item_selected)
	_read_button.pressed.connect(read_selected)
	_subscribe_button.pressed.connect(toggle_subscription)
	_device_info_button.pressed.connect(read_device_info)
	_write_button.pressed.connect(write_selected)
	_hex_edit.text_submitted.connect(func(_t: String) -> void: write_selected())
	_copy_log_button.pressed.connect(copy_log)
	_clear_log_button.pressed.connect(clear_log)
	for id: String in BleDebugModel.PRESET_IDS:
		var b := Button.new()
		b.name = "Preset_" + id
		b.pressed.connect(write_preset.bind(id))
		_presets.add_child(b)
		_preset_buttons[id] = b
	render_now()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		render_now()


func _process(delta: float) -> void:
	_since_render += delta
	if _since_render < RENDER_INTERVAL_SEC:
		return
	if _dirty_devices or _dirty_tree or _dirty_log or _dirty_state:
		render_now()


func _exit_tree() -> void:
	_teardown()


# ---------------------------------------------------------------------------
# Действия
# ---------------------------------------------------------------------------

func start_scan() -> bool:
	_status_key = ""
	var ok := model.start_scan()
	_mark_all()
	return ok


func stop_scan() -> void:
	model.stop_scan()
	_mark_all()


func set_app_filter(enabled: bool) -> void:
	model.set_use_app_filter(enabled)
	_mark_all()


func select_device(id: String) -> void:
	_selected_device = id
	_dirty_devices = true
	_dirty_state = true


func connect_selected() -> void:
	if _selected_device.is_empty():
		return
	if _connections != null and _connections.is_device_connected(_selected_device):
		model.note("device %s is also connected by the app; its link is shared" % BleDebugModel.device_tag(_selected_device))
	_selected_service = ""
	_selected_char = ""
	model.connect_device(_selected_device)
	_mark_all()


func disconnect_device() -> void:
	model.disconnect_device()
	_mark_all()


## Выбрать характеристику (как щелчок в дереве).
func select_characteristic(service_uuid: String, char_uuid: String) -> void:
	_selected_service = BleUuids.normalize(service_uuid)
	_selected_char = BleUuids.normalize(char_uuid)
	_dirty_state = true
	_dirty_tree = true


func read_selected() -> bool:
	if _selected_char.is_empty():
		return false
	return model.read(_selected_service, _selected_char)


func toggle_subscription() -> bool:
	if _selected_char.is_empty():
		return false
	var ok := model.set_subscribed(_selected_service, _selected_char,
			not model.is_subscribed(_selected_service, _selected_char))
	_mark_all()
	return ok


func read_device_info() -> int:
	return model.read_device_info()


## Записать hex из поля в выбранную характеристику. false — нет выбора, не подключено или hex неверен.
func write_selected() -> bool:
	if _selected_char.is_empty():
		return false
	var ok := model.write_hex(_selected_service, _selected_char, _hex_edit.text, _response_check.button_pressed)
	if not ok and not BleDebugModel.parse_hex(_hex_edit.text)["ok"]:
		_set_status("ui.ble_debug.hex_invalid")
	return ok


func write_preset(preset_id: String) -> bool:
	return model.write_preset(preset_id, _response_check.button_pressed)


func copy_log() -> void:
	DisplayServer.clipboard_set(model.log_text())
	_set_status("ui.ble_debug.copied", model.log_size())


func clear_log() -> void:
	model.clear_log()
	_dirty_log = true


## «Назад»/Esc. true — обработано.
func handle_back() -> bool:
	close()
	return true


func close() -> void:
	if _closed:
		return
	_teardown()
	closed.emit()


# ---------------------------------------------------------------------------
# Доступ для тестов
# ---------------------------------------------------------------------------

func preset_button(preset_id: String) -> Button:
	return _preset_buttons.get(preset_id, null)


func back_button() -> Button:
	return _back_button


func scan_button() -> Button:
	return _scan_button


func device_list() -> ItemList:
	return _device_list


func service_tree() -> Tree:
	return _service_tree


func log_view_text() -> String:
	return _log_view.text


func link_text() -> String:
	return _link_label.text


func value_text() -> String:
	return _value_label.text


func is_manager_suspended() -> bool:
	return _manager_suspended


# ---------------------------------------------------------------------------
# Отрисовка
# ---------------------------------------------------------------------------

func render_now() -> void:
	_since_render = 0.0
	if model == null:
		return
	_render_texts()
	if _dirty_devices:
		_render_devices()
	if _dirty_tree:
		_render_tree()
	if _dirty_log:
		_render_log()
	_render_state()
	_dirty_devices = false
	_dirty_tree = false
	_dirty_log = false
	_dirty_state = false


func _render_texts() -> void:
	if not model.is_available():
		_adapter_label.text = tr("ui.ble_debug.unavailable")
	else:
		_adapter_label.text = tr("ui.ble_debug.adapter").format({"state": BleBridge.adapter_state_name(model.adapter_state())})
	_devices_title.text = tr("ui.ble_debug.devices").format({"count": model.devices.size()})
	_log_title.text = tr("ui.ble_debug.log").format({"count": model.log_size()})
	for id: String in _preset_buttons:
		(_preset_buttons[id] as Button).text = tr(str(PRESET_KEYS.get(id, id)))
	_status_label.text = "" if _status_key.is_empty() else tr(_status_key).format({"count": _status_count})


func _render_devices() -> void:
	_device_list.clear()
	for id in model.device_ids():
		var d := model.device(id)
		var label := "%s  %d dBm  %s" % [_display_name(str(d["name"])), int(d["rssi"]), str(d["kind"])]
		var idx := _device_list.add_item(label)
		_device_list.set_item_metadata(idx, id)
		if id == _selected_device:
			_device_list.select(idx)
	var info: Array[String] = []
	var dev := model.device(_selected_device) if not _selected_device.is_empty() else {}
	if dev.is_empty():
		info.append(tr("ui.ble_debug.no_device"))
	else:
		info.append(tr("ui.ble_debug.info_name").format({"name": _display_name(str(dev["name"]))}))
		info.append(tr("ui.ble_debug.info_id").format({"id": dev["id"]}))
		info.append(tr("ui.ble_debug.info_rssi").format({"rssi": dev["rssi"]}))
		info.append(tr("ui.ble_debug.info_kind").format({"kind": dev["kind"]}))
		info.append(tr("ui.ble_debug.info_raw").format({"uuids": ", ".join(dev["raw"] as PackedStringArray)}))
		info.append(tr("ui.ble_debug.info_norm").format({"uuids": ", ".join(dev["norm"] as PackedStringArray)}))
		info.append(tr("ui.ble_debug.info_union").format({"uuids": ", ".join(dev["union"] as PackedStringArray)}))
		info.append(tr("ui.ble_debug.info_packets").format({"count": dev["packets"]}))
	_device_info_label.text = "\n".join(info)


func _render_tree() -> void:
	_service_tree.clear()
	var root := _service_tree.create_item()
	for s: Dictionary in model.service_tree():
		var s_item := _service_tree.create_item(root)
		s_item.set_text(0, _uuid_label(str(s["uuid"]), str(s["name"])))
		s_item.set_metadata(0, {"service": s["uuid"], "char": ""})
		s_item.set_selectable(0, false)
		for c: Dictionary in s["chars"]:
			var c_item := _service_tree.create_item(s_item)
			var text := _uuid_label(str(c["uuid"]), str(c["name"]))
			if model.is_subscribed(str(s["uuid"]), str(c["uuid"])):
				text += "  " + tr("ui.ble_debug.subscribed_mark")
			c_item.set_text(0, text)
			c_item.set_metadata(0, {"service": s["uuid"], "char": c["uuid"]})
			if str(s["uuid"]) == _selected_service and str(c["uuid"]) == _selected_char:
				c_item.select(0)


func _render_log() -> void:
	_log_view.text = "\n".join(model.log_lines(LOG_LINES_SHOWN))
	_log_view.set_caret_line(_log_view.get_line_count() - 1)
	_log_view.scroll_vertical = _log_view.get_line_count()


func _render_state() -> void:
	_scan_button.disabled = not model.is_available()
	_stop_scan_button.disabled = not model.scanning
	_filter_check.set_pressed_no_signal(model.use_app_filter)
	var name := _display_name(str(model.device(model.link_id).get("name", "")))
	match model.link_state:
		BleDebugModel.LinkState.CONNECTING:
			_link_label.text = tr("ui.ble_debug.link_connecting").format({"name": name})
		BleDebugModel.LinkState.DISCOVERING:
			_link_label.text = tr("ui.ble_debug.link_discovering").format({"name": name})
		BleDebugModel.LinkState.READY:
			_link_label.text = tr("ui.ble_debug.link_ready").format({"name": name})
		_:
			_link_label.text = tr("ui.ble_debug.link_idle")
	_connect_button.disabled = _selected_device.is_empty() or not model.is_available()
	_disconnect_button.disabled = model.link_id.is_empty()
	var ready := model.is_ready()
	var has_char := ready and not _selected_char.is_empty()
	_read_button.disabled = not has_char
	_subscribe_button.disabled = not has_char
	_write_button.disabled = not has_char
	_subscribe_button.text = tr("ui.ble_debug.unsubscribe") if has_char and model.is_subscribed(_selected_service, _selected_char) \
			else tr("ui.ble_debug.subscribe")
	_device_info_button.disabled = not (ready and model.has_service(BleDebugModel.DEVICE_INFO_SERVICE))
	for id: String in _preset_buttons:
		(_preset_buttons[id] as Button).disabled = not ready
	if _selected_char.is_empty():
		_char_label.text = tr("ui.ble_debug.no_char")
		_value_label.text = ""
		return
	_char_label.text = "%s / %s" % [_uuid_label(_selected_service, BleDebugModel.service_name(_selected_service)),
			_uuid_label(_selected_char, BleDebugModel.char_name(_selected_char))]
	var v := model.value_of(_selected_char)
	if v.is_empty():
		_value_label.text = tr("ui.ble_debug.value_none")
		return
	var lines: Array[String] = [tr("ui.ble_debug.value").format({"time": v["time"], "source": v["source"], "hex": v["hex"]})]
	if not str(v["decoded"]).is_empty():
		lines.append(tr("ui.ble_debug.decoded").format({"text": v["decoded"]}))
	_value_label.text = "\n".join(lines)


func _display_name(name: String) -> String:
	return name if not name.is_empty() else tr("ui.ble_debug.no_name")


static func _uuid_label(uuid: String, name: String) -> String:
	return uuid if name.is_empty() else "%s  %s" % [uuid, name]


# ---------------------------------------------------------------------------
# Внутреннее
# ---------------------------------------------------------------------------

func _mark_all() -> void:
	_dirty_devices = true
	_dirty_tree = true
	_dirty_log = true
	_dirty_state = true


func _set_status(key: String, count: int = 0) -> void:
	_status_key = key
	_status_count = count
	_dirty_state = true
	if is_node_ready():
		_render_texts()


func _on_devices_changed() -> void:
	_dirty_devices = true


func _on_link_changed() -> void:
	_dirty_state = true


func _on_tree_changed() -> void:
	_dirty_tree = true
	_dirty_state = true


func _on_value_changed(char_uuid: String) -> void:
	if char_uuid == _selected_char:
		_dirty_state = true


func _on_log_added(_entry: Dictionary) -> void:
	_dirty_log = true


func _on_device_selected(index: int) -> void:
	select_device(str(_device_list.get_item_metadata(index)))


func _on_tree_item_selected() -> void:
	var item := _service_tree.get_selected()
	if item == null:
		return
	var meta: Dictionary = item.get_metadata(0)
	if str(meta.get("char", "")).is_empty():
		return
	select_characteristic(str(meta["service"]), str(meta["char"]))
	_dirty_tree = false


## Остановить сканирование и автоподключение приложения на время отладки.
func _suspend_manager() -> void:
	if _connections == null or _manager_suspended:
		return
	_manager_suspended = true
	_manager_was_auto = _connections.is_auto_connecting() or _connections.is_auto_connect_deferred()
	_manager_was_scanning = _connections.scanner != null and _connections.scanner.is_scanning() and not _manager_was_auto
	_manager_auto_enabled = _connections.auto_connect_enabled
	_connections.cancel_auto_connect()
	_connections.stop_scan()
	_connections.auto_connect_enabled = false
	model.note("app scanning and auto-connect paused (was scanning: %s, auto-connect: %s)" % [_manager_was_scanning, _manager_was_auto])


func _resume_manager() -> void:
	if _connections == null or not _manager_suspended:
		return
	_manager_suspended = false
	_connections.auto_connect_enabled = _manager_auto_enabled
	if _manager_was_auto:
		_connections.auto_connect(_connections.profile_id)
	elif _manager_was_scanning:
		_connections.start_scan()


func _teardown() -> void:
	if _closed:
		return
	_closed = true
	if model != null:
		var keep_link := _connections != null and not model.link_id.is_empty() \
				and _connections.is_device_connected(model.link_id)
		for pair: Array in [[model.devices_changed, _on_devices_changed], [model.link_changed, _on_link_changed],
				[model.tree_changed, _on_tree_changed], [model.value_changed, _on_value_changed],
				[model.log_added, _on_log_added]]:
			var sig: Signal = pair[0]
			if sig.is_connected(pair[1]):
				sig.disconnect(pair[1])
		model.dispose(not keep_link)
	_resume_manager()
