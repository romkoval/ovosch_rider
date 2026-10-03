class_name ProfileSelectScreen
extends Control
## Экран выбора и создания профиля (REQ-PRF-01 крит. 1, 2, 4, 5; REQ-PRF-05).
## Все строки — через ключи переводов (REQ-NFR-08 крит. 1); ошибки валидации
## показываются по кодам `Profile.ERR_*` / `ProfileRepository.ERR_*` как
## `tr("error.profile.<code>")`.
##
## Экран не знает, какой экран следующий: по выбору вызывает `AppState.select_profile`
## и испускает `profile_chosen`. Зависимости передаются через `setup()`.

const ERROR_KEY_PREFIX: String = "error.profile."

signal profile_chosen(id: String)
signal profile_created(id: String)
signal profile_deleted(id: String)

var _repo: ProfileRepository
var _app_state: AppState
var _ids: Array[String] = []
var _pending_delete_id: String = ""

@onready var _list: ItemList = %ProfileList
@onready var _select_button: Button = %SelectButton
@onready var _create_button: Button = %CreateButton
@onready var _delete_button: Button = %DeleteButton
@onready var _empty_hint: Label = %EmptyHint
@onready var _create_form: PanelContainer = %CreateForm
@onready var _name_edit: LineEdit = %NameEdit
@onready var _ftp_spin: SpinBox = %FtpSpin
@onready var _weight_spin: SpinBox = %WeightSpin
@onready var _max_hr_spin: SpinBox = %MaxHrSpin
@onready var _save_button: Button = %SaveButton
@onready var _cancel_button: Button = %CancelButton
@onready var _error_label: Label = %ErrorLabel
@onready var _delete_dialog: ConfirmationDialog = %DeleteDialog


## Внедрить зависимости (до или после добавления в дерево).
func setup(repo: ProfileRepository, app_state: AppState = null) -> void:
	_repo = repo
	_app_state = app_state
	if is_node_ready():
		refresh()


func _ready() -> void:
	_select_button.pressed.connect(select_current)
	_create_button.pressed.connect(open_create_form)
	_delete_button.pressed.connect(request_delete)
	_save_button.pressed.connect(func() -> void: submit_create())
	_cancel_button.pressed.connect(close_create_form)
	_list.item_selected.connect(func(_index: int) -> void: _update_buttons())
	_list.item_activated.connect(func(_index: int) -> void: select_current())
	_delete_dialog.confirmed.connect(func() -> void: confirm_delete())
	_delete_dialog.canceled.connect(func() -> void: _pending_delete_id = "")
	_create_form.visible = false
	if _repo != null:
		refresh()


## Перечитать список профилей из репозитория.
func refresh() -> void:
	_list.clear()
	_ids = []
	var active_id: String = _repo.active_profile_id
	for p in _repo.list():
		_ids.append(p.id)
		var index: int = _list.add_item("%s — %s" % [p.name, tr("ui.profile_select.item_ftp").format({"ftp": p.ftp_w})])
		if p.id == active_id:
			_list.select(index)
	var empty: bool = _ids.is_empty()
	_empty_hint.visible = empty
	if empty:
		open_create_form()
	# Автовыбор единственного профиля при старте не удался (например, сбой записи) — показать причину.
	if _app_state != null and not _app_state.last_select_error().is_empty():
		_show_error([_app_state.last_select_error()])
	_update_buttons()


func profile_count() -> int:
	return _ids.size()


## Выбрать строку списка по индексу (для тестов и клавиатуры).
func select_index(index: int) -> void:
	if index >= 0 and index < _ids.size():
		_list.select(index)
	_update_buttons()


## id выделенного профиля или "".
func selected_profile_id() -> String:
	var selected := _list.get_selected_items()
	if selected.is_empty():
		return ""
	return _ids[selected[0]]


## Подтвердить выбор выделенного профиля. false — ничего не выделено или выбор не удался
## (например, не записан активный профиль) — причина показана в `error_text()`.
func select_current() -> bool:
	var id := selected_profile_id()
	if id.is_empty():
		return false
	var err := ""
	if _app_state != null:
		if not _app_state.select_profile(id):
			err = _app_state.last_select_error()
			if err.is_empty():
				err = ProfileRepository.ERR_PROFILE_NOT_FOUND
	else:
		err = _repo.set_active(id)
	if not err.is_empty():
		_show_error([err])
		return false
	_show_error([])
	profile_chosen.emit(id)
	return true


func open_create_form() -> void:
	_name_edit.text = ""
	_ftp_spin.value = 200
	_weight_spin.value = 75.0
	_max_hr_spin.value = 0
	_show_error([])
	_create_form.visible = true
	_name_edit.grab_focus()


func close_create_form() -> void:
	_create_form.visible = false
	_show_error([])


func is_create_form_open() -> bool:
	return _create_form.visible


## Заполнить форму (для тестов).
func fill_create_form(profile_name: String, ftp_w: int, weight_kg: float, max_hr: int = 0) -> void:
	_name_edit.text = profile_name
	_ftp_spin.value = ftp_w
	_weight_spin.value = weight_kg
	_max_hr_spin.value = max_hr


## Создать профиль из формы. Возвращает профиль или null (ошибки показаны в `error_text()`).
func submit_create() -> Profile:
	var p := Profile.create(_name_edit.text)
	p.ftp_w = int(_ftp_spin.value)
	p.weight_kg = _weight_spin.value
	p.max_hr = int(_max_hr_spin.value)
	var errors := _repo.save(p)
	if not errors.is_empty():
		_show_error(errors)
		return null
	close_create_form()
	refresh()
	select_index(_ids.find(p.id))
	profile_created.emit(p.id)
	return p


## Запросить удаление выделенного профиля (показывает подтверждение, REQ-PRF-01 крит. 4).
func request_delete() -> bool:
	var id := selected_profile_id()
	if id.is_empty():
		return false
	_pending_delete_id = id
	var p := _repo.get_by_id(id)
	_delete_dialog.dialog_text = tr("ui.profile_select.delete_confirm").format({"name": p.name if p != null else id})
	_delete_dialog.popup_centered()
	return true


## Подтверждённое удаление. Возвращает "" или код ошибки (например, `last_profile`).
func confirm_delete() -> String:
	var id := _pending_delete_id
	_pending_delete_id = ""
	if id.is_empty():
		return ProfileRepository.ERR_PROFILE_NOT_FOUND
	var err := _repo.delete(id)
	if err.is_empty():
		profile_deleted.emit(id)
	else:
		_show_error([err])
	refresh()
	return err


func pending_delete_id() -> String:
	return _pending_delete_id


## Текущий текст ошибки ("" если нет).
func error_text() -> String:
	return _error_label.text if _error_label.visible else ""


## Перевод кода ошибки.
static func error_message(code: String) -> String:
	return TranslationServer.translate(ERROR_KEY_PREFIX + code)


func _show_error(codes: Array[String]) -> void:
	var lines: Array[String] = []
	for code in codes:
		lines.append(tr(ERROR_KEY_PREFIX + code))
	_error_label.text = "\n".join(lines)
	_error_label.visible = not lines.is_empty()


func _update_buttons() -> void:
	var has_selection: bool = not selected_profile_id().is_empty()
	_select_button.disabled = not has_selection
	_delete_button.disabled = not has_selection or _ids.size() <= 1
