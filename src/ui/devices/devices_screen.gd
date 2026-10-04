class_name DevicesScreen
extends Control
## Экран устройств (`AppState.Screen.DEVICES`; `docs/game/ui.md` п. 8.7; REQ-UIX-04 крит. 1, 3–5).
##
## Раскладка. `AppBar` «Устройства» с «назад» (`AppState.go_back()`, ручное сканирование при
## этом останавливается), справа индикатор поиска, переключатель «Автоподключение» и основная
## кнопка «Сканировать» / «Остановить поиск». Ниже:
## - баннер-предупреждение «Bluetooth недоступен» с действием «Как включить» (REQ-DEV-01 крит. 7);
## - строка статуса (поиск, ожидание запомненных, «устройство не найдено», REQ-DEV-06 крит. 3);
## - три слота `DeviceSlot` — «Станок», «Пульсометр», «Каденс» (UIX-04 крит. 5): в ряд на
##   regular, столбиком на compact;
## - раздел «Найденные устройства» — строки списка (`ListRow`, вариация `ListRowButton`, UIX-04
##   крит. 3): иконка типа, имя, тип, колонки сигнала, состояния и заряда, кнопка «Подключить» /
##   «Отключить»; пусто — пустое состояние с действием «Искать» (UIX-04 крит. 4);
## - раздел «Запомненные устройства» — такие же строки с «Забыть».
##
## Функции — как до T-086 (REQ-DEV-01 крит. 2–4, 7; REQ-DEV-06 крит. 2–4; REQ-DEV-07 крит. 1–3;
## REQ-PRF-04 крит. 2, 3): экран работает только через `ConnectionManager` и не знает, какая
## реализация станка подключена. Строки обновляются на месте по сигналам менеджера (без
## пересборки), переезжают между списками и освобождаются сразу, когда устройство исчезло.

const COMPACT_MAX_WIDTH: float = AppBar.COMPACT_MAX_WIDTH
## Содержимое экрана не шире 1216 lp (`ui.md` п. 3).
const CONTENT_MAX_WIDTH: float = 1216.0
## Ширины колонок строки, lp: сигнал, состояние, заряд (regular). На compact колонка одна —
## заряд, а сигнал и состояние уходят в подзаголовок: имени устройства нужна ширина.
const COLUMN_WIDTHS: Array[float] = [96.0, 168.0, 128.0]
const COLUMN_WIDTHS_COMPACT: Array[float] = [112.0]
const ROW_SCENE: PackedScene = preload("res://src/ui/common/list_row.tscn")
## Скорость вращения индикатора поиска, рад/с.
const INDICATOR_SPEED: float = TAU * 0.75
const SUBTITLE_SEPARATOR: String = " · "
const ROW_TEXT_SEPARATOR: String = " · "

## Слоты: тип устройства, иконка Lucide, ключ заголовка.
const SLOT_KINDS: Array[String] = [RememberedDevices.KIND_TRAINER, RememberedDevices.KIND_HR, RememberedDevices.KIND_CADENCE]
const SLOT_ICONS: Dictionary = {
	RememberedDevices.KIND_TRAINER: "bike",
	RememberedDevices.KIND_HR: "heart",
	RememberedDevices.KIND_CADENCE: "gauge",
}
const SLOT_TITLE_KEYS: Dictionary = {
	RememberedDevices.KIND_TRAINER: "ui.devices.slot.trainer",
	RememberedDevices.KIND_HR: "ui.devices.slot.hr",
	RememberedDevices.KIND_CADENCE: "ui.devices.slot.cadence",
}
## Иконка строки по типу устройства.
const KIND_ICONS: Dictionary = {
	RememberedDevices.KIND_TRAINER: "bike",
	RememberedDevices.KIND_HR: "heart",
	RememberedDevices.KIND_CADENCE: "gauge",
	RememberedDevices.KIND_POWER: "zap",
}
const UNKNOWN_ICON: String = "bluetooth"

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
var _compact: bool = false
var _slots: Dictionary = {}

@onready var _root: VBoxContainer = %Root
@onready var _app_bar: AppBar = %AppBar
@onready var _margin: MarginContainer = %Margin
@onready var _body: VBoxContainer = %Body
@onready var _status_label: Label = %StatusLabel
@onready var _scan_button: Button = %ScanButton
@onready var _scan_indicator: TextureRect = %ScanIndicator
@onready var _auto_connect_check: CheckButton = %AutoConnectCheck
@onready var _ble_banner: Banner = %BleBanner
@onready var _ble_help_dialog: AcceptDialog = %BleHelpDialog
@onready var _slots_box: BoxContainer = %Slots
@onready var _remembered_section: VBoxContainer = %RememberedSection
@onready var _remembered_list: VBoxContainer = %RememberedList
@onready var _found_list: VBoxContainer = %FoundList
@onready var _found_empty: EmptyState = %FoundEmpty
var _back_button: Button


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
	_app_bar.set_title("ui.devices.title")
	_app_bar.back_pressed.connect(_on_app_bar_back)
	_back_button = _app_bar.back_button()
	_back_button.name = "BackButton"
	_back_button.owner = self
	_back_button.unique_name_in_owner = true
	_scan_indicator.texture = UiIcons.icon("refresh-cw")
	_scan_indicator.self_modulate = UiTokens.ACCENT
	_scan_button.pressed.connect(toggle_scan)
	_auto_connect_check.toggled.connect(set_auto_connect)
	_ble_banner.action_pressed.connect(show_ble_help)
	_found_empty.action_pressed.connect(_on_empty_action)
	for kind in SLOT_KINDS:
		var slot: DeviceSlot = get_node("%" + _slot_node_name(kind))
		slot.find_requested.connect(_on_slot_find)
		slot.disconnect_requested.connect(_on_slot_disconnect)
		_slots[kind] = slot
	TouchTarget.attach(_scan_button, TouchTarget.Kind.BUTTON)
	TouchTarget.attach(_auto_connect_check, TouchTarget.Kind.UI)
	DialogLayout.attach_all(self)
	set_process(false)
	var scale_source := TouchTarget.default_runtime()
	if scale_source != null:
		scale_source.scale_changed.connect(_on_scale_changed)
	get_viewport().size_changed.connect(_update_layout)
	_update_layout()
	if _manager != null:
		refresh()
	else:
		_render_static()


func _exit_tree() -> void:
	var scale_source := TouchTarget.default_runtime()
	if scale_source != null and scale_source.scale_changed.is_connected(_on_scale_changed):
		scale_source.scale_changed.disconnect(_on_scale_changed)
	var viewport := get_viewport()
	if viewport != null and viewport.size_changed.is_connected(_update_layout):
		viewport.size_changed.disconnect(_update_layout)


func _enter_tree() -> void:
	if not is_node_ready():
		return
	var scale_source := TouchTarget.default_runtime()
	if scale_source != null and not scale_source.scale_changed.is_connected(_on_scale_changed):
		scale_source.scale_changed.connect(_on_scale_changed)
	if not get_viewport().size_changed.is_connected(_update_layout):
		get_viewport().size_changed.connect(_update_layout)


func _process(delta: float) -> void:
	_scan_indicator.pivot_offset = _scan_indicator.size * 0.5
	_scan_indicator.rotation = fmod(_scan_indicator.rotation + INDICATOR_SPEED * delta, TAU)


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


## «Назад»: на экран, с которого пришли (REQ-UIX-04 крит. 1); ручное сканирование при уходе
## с экрана останавливается (REQ-DEV-01 крит. 4), автоподключение держит своё.
func back() -> void:
	_stop_user_scan()
	if _app_state != null:
		_app_state.go_back()


## Подсказка «Как включить Bluetooth» (действие баннера).
func show_ble_help() -> void:
	_ble_help_dialog.title = tr("ui.devices.ble_help_title")
	_ble_help_dialog.dialog_text = tr("ui.devices.ble_help_text")
	_ble_help_dialog.ok_button_text = tr("ui.common.ok")
	_ble_help_dialog.popup_centered()


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
	if _manager == null or not is_node_ready() or not is_inside_tree():
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
	_update_dividers(_found_list)
	_update_dividers(_remembered_list)
	_render_static()
	_status_label.text = _status_text()
	_render_slots()


## Row for a device id: `{id, record, hbox, list_row, connect_button, forget_button}` or {};
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


## Текст строки: имя, подзаголовок (тип, недоступность) и колонки (сигнал, состояние, заряд)
## через « · ».
func row_text(id: String) -> String:
	var r := row(id)
	if r.is_empty():
		return ""
	var list_row: ListRow = r["list_row"]
	var parts: PackedStringArray = [list_row.title]
	if not list_row.subtitle.is_empty():
		parts.append(list_row.subtitle)
	for text in list_row.column_texts():
		if not text.is_empty():
			parts.append(text)
	return ROW_TEXT_SEPARATOR.join(parts)


## Слот устройства по типу (`trainer`, `hr`, `cadence`).
func slot(kind: String) -> DeviceSlot:
	return _slots.get(kind, null)


func is_ble_banner_visible() -> bool:
	return _ble_banner.visible


func ble_banner() -> Banner:
	return _ble_banner


func found_empty_state() -> EmptyState:
	return _found_empty


func app_bar() -> AppBar:
	return _app_bar


func is_compact() -> bool:
	return _compact


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


## Шапка, баннер, пустое состояние и разделы — по состоянию менеджера.
func _render_static() -> void:
	var available: bool = _manager != null and _manager.is_ble_available()
	var scanning: bool = _manager != null and _manager.scanner.is_scanning()
	_scan_button.text = tr("ui.devices.stop_scan") if scanning else tr("ui.devices.scan")
	_scan_button.disabled = not available
	_scan_indicator.visible = scanning
	set_process(scanning)
	if not scanning:
		_scan_indicator.rotation = 0.0
	if _manager != null:
		_auto_connect_check.set_pressed_no_signal(_manager.auto_connect_enabled)
	_auto_connect_check.text = tr("ui.devices.auto_connect")
	_ble_banner.show_banner(Banner.Kind.WARN, "ui.devices.ble_unavailable", "ui.devices.ble_help", "bluetooth-off")
	_ble_banner.visible = _manager != null and not available
	# Статус «Bluetooth недоступен» уже в баннере — строка статуса скрыта.
	_status_label.visible = available
	var found_empty := _found_list.get_child_count() == 0
	_found_empty.visible = found_empty
	_found_empty.setup("bluetooth", "ui.devices.empty_title", "ui.devices.empty_text",
		"ui.devices.empty_action" if available and not scanning else "")
	_remembered_section.visible = _remembered_list.get_child_count() > 0


## Слоты «Станок», «Пульсометр», «Каденс»: текущее устройство типа и его состояние.
func _render_slots() -> void:
	var available: bool = _manager.is_ble_available()
	var scanning: bool = _manager.scanner.is_scanning()
	for kind in SLOT_KINDS:
		var device_slot: DeviceSlot = _slots[kind]
		device_slot.setup(kind, SLOT_ICONS[kind], tr(SLOT_TITLE_KEYS[kind]))
		var record := _slot_record(kind)
		var id: String = str(record.get("id", ""))
		var state: int = _manager.state_of(id) if not id.is_empty() else TrainerDevice.ConnectionState.DISCONNECTED
		var device_name := str(record.get("name", ""))
		if state != TrainerDevice.ConnectionState.DISCONNECTED:
			var found := _manager.scanner.find(id)
			var signal_text := tr("ui.devices.rssi").format({"rssi": found["rssi"]}) if found.has("rssi") else "—"
			var battery: int = _manager.battery_of(id)
			var battery_text := "%d %s" % [battery, tr("ui.menu.unit.pct")] if battery >= 0 else "—"
			device_slot.show_device(id, state, tr(state_key(state)),
				device_name if not device_name.is_empty() else tr("ui.devices.unnamed"),
				signal_text, battery_text, tr("ui.devices.disconnect"))
		else:
			device_slot.show_empty(tr(state_key(state)), tr("ui.devices.slot.not_connected"), device_name,
				tr("ui.devices.slot.find"), available and not scanning)


## Запись устройства слота: подключаемое сейчас (`trainer_id` / `sensor_ids`), иначе
## запомненное этого типа ({} — нет).
func _slot_record(kind: String) -> Dictionary:
	var id := ""
	if kind == RememberedDevices.KIND_TRAINER:
		id = _manager.trainer_id
	else:
		id = str(_manager.sensor_ids.get(kind, ""))
	var records: Array[Dictionary] = _manager.remembered.list(profile_id())
	if not id.is_empty():
		for record in records:
			if str(record.get("id", "")) == id:
				return record
		var found := _manager.scanner.find(id)
		return {"id": id, "name": str(found.get("name", "")), "kind": kind}
	for record in records:
		if str(record.get("kind", "")) == kind:
			return record
	return {}


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


## Строка: `HBoxContainer` `Row_<id>` со строкой списка `ListRow` (вариация `ListRowButton`).
## Сама строка не нажимается (действия — кнопки в хвосте), поэтому без фокуса и наведения.
func _create_row(id: String) -> Dictionary:
	var hbox := HBoxContainer.new()
	hbox.name = "Row_" + id.validate_node_name()
	hbox.theme_type_variation = &"Row0"
	var list_row: ListRow = ROW_SCENE.instantiate()
	list_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_row.focus_mode = Control.FOCUS_NONE
	list_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	list_row.show_chevron = false
	hbox.add_child(list_row)
	var connect_button := Button.new()
	connect_button.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	connect_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	connect_button.pressed.connect(_on_row_button.bind(id, false))
	var forget_button := Button.new()
	forget_button.theme_type_variation = &"GhostButton"
	forget_button.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	forget_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	forget_button.pressed.connect(_on_row_button.bind(id, true))
	TouchTarget.attach(connect_button, TouchTarget.Kind.BUTTON)
	TouchTarget.attach(forget_button, TouchTarget.Kind.UI)
	return {"id": id, "record": {}, "hbox": hbox, "list_row": list_row, "icon_kind": null,
		"connect_button": connect_button, "forget_button": forget_button}


func _update_row(r: Dictionary, record: Dictionary, is_remembered: bool) -> void:
	var id: String = str(record["id"])
	var name: String = str(record.get("name", ""))
	if name.is_empty():
		name = tr("ui.devices.unnamed")
	var kind: String = str(record.get("kind", ""))
	var state: int = _manager.state_of(id)
	var battery: int = _manager.battery_of(id)
	var rssi_text := tr("ui.devices.rssi").format({"rssi": record["rssi"]}) if record.has("rssi") else ""
	var state_text := tr(state_key(state))
	var subtitle: PackedStringArray = [tr(kind_key(kind))]
	if _compact:
		subtitle.append(state_text)
		if not rssi_text.is_empty():
			subtitle.append(rssi_text)
	if record.has("rssi") and not record.get("available", true):
		subtitle.append(tr("ui.devices.unavailable"))
	var battery_text := tr("ui.devices.battery").format({"percent": battery}) if battery >= 0 else tr("ui.devices.battery_unknown")
	var list_row: ListRow = r["list_row"]
	var connect_button: Button = r["connect_button"]
	var forget_button: Button = r["forget_button"]
	# Слоты строки готовы только после входа в дерево: кнопки добавляются при первом обновлении.
	if connect_button.get_parent() == null:
		list_row.add_trailing(connect_button)
		list_row.add_trailing(forget_button)
	# Иконка пересоздаётся только при смене типа (без лишних узлов на каждом сигнале).
	if r["icon_kind"] != kind:
		r["icon_kind"] = kind
		list_row.set_icon(str(KIND_ICONS.get(kind, UNKNOWN_ICON)))
	list_row.set_texts(name, SUBTITLE_SEPARATOR.join(subtitle))
	if _compact:
		list_row.set_columns([battery_text], COLUMN_WIDTHS_COMPACT, &"NumLabel")
	else:
		list_row.set_columns([rssi_text, state_text, battery_text], COLUMN_WIDTHS, &"NumLabel")
	connect_button.text = tr("ui.devices.disconnect") if state == TrainerDevice.ConnectionState.CONNECTED else tr("ui.devices.connect")
	connect_button.disabled = kind == BleScanner.KIND_UNKNOWN or not _manager.is_ble_available()
	forget_button.text = tr("ui.devices.forget")
	forget_button.visible = is_remembered


## Разделитель 1 lp между строками; у последней строки списка его нет (`ui.md` п. 6).
static func _update_dividers(list: VBoxContainer) -> void:
	var count := list.get_child_count()
	for i in count:
		var list_row := (list.get_child(i) as Node).get_child(0) as ListRow
		if list_row != null:
			list_row.divider = i < count - 1


func _on_row_button(id: String, forget: bool) -> void:
	_row_in_signal = id
	if forget:
		forget_device(id)
	elif _rows.has(id):
		connect_device(_rows[id]["record"])
	_row_in_signal = ""


func _on_slot_find() -> void:
	if _manager != null and not _manager.scanner.is_scanning():
		toggle_scan()


func _on_slot_disconnect(id: String) -> void:
	if _manager != null and not id.is_empty():
		_manager.disconnect_device(id)
		refresh()


func _on_empty_action() -> void:
	_on_slot_find()


func _on_app_bar_back(_handled: bool) -> void:
	back()


func _on_state_changed(id: String) -> void:
	# Успешное подключение: устройство найдено — убрать его из «не найдено».
	if _manager != null and _manager.state_of(id) == TrainerDevice.ConnectionState.CONNECTED:
		_not_found_ids.erase(id)
	refresh()


func _on_auto_connect_timed_out(ids: Array[String]) -> void:
	_not_found_ids = ids.duplicate()
	_not_found_profile_id = profile_id()
	refresh()


func _on_scale_changed(_scale: float) -> void:
	_update_layout()


static func _slot_node_name(kind: String) -> String:
	match kind:
		RememberedDevices.KIND_TRAINER:
			return "TrainerSlot"
		RememberedDevices.KIND_HR:
			return "HrSlot"
	return "CadenceSlot"


## Раскладка: безопасная зона, поля, ширина содержимого ≤ 1216 lp; слоты в ряд (regular) или
## столбиком (compact).
func _update_layout() -> void:
	if not is_node_ready() or not is_inside_tree():
		return
	var safe := Vector4.ZERO
	var scale_source := TouchTarget.default_runtime()
	if scale_source != null:
		safe = scale_source.safe_margins()
	_root.offset_left = safe.x
	_root.offset_top = safe.y
	_root.offset_right = -safe.z
	_root.offset_bottom = -safe.w
	var canvas := get_viewport_rect().size
	var compact := canvas.x < COMPACT_MAX_WIDTH
	var changed := compact != _compact
	_compact = compact
	_margin.theme_type_variation = &"ScreenMarginCompact" if compact else &"ScreenMargin"
	var available := canvas.x - safe.x - safe.z \
		- float(_margin.get_theme_constant("margin_left")) - float(_margin.get_theme_constant("margin_right"))
	_body.custom_minimum_size.x = clampf(available, 0.0, CONTENT_MAX_WIDTH)
	_slots_box.vertical = compact
	_slots_box.theme_type_variation = &"Stack12" if compact else &"Row16"
	if changed and _manager != null:
		refresh()
