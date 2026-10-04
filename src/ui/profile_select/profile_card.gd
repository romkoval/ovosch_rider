class_name ProfileCard
extends Button
## Карточка профиля на экране выбора (`docs/game/ui.md` п. 8.1): кнопка с вариацией
## `CardButton` (фокус, Enter и клавиатура работают сразу), содержимое — дочерние узлы с
## `mouse_filter = PASS`: аватар с инициалом, имя (`TitleLabel`, длинное сокращается «…»),
## «FTP 250 Вт · 75 кг» (`CaptionNumLabel`). В правом верхнем углу — кнопка «⋯» (`IconButton`)
## с действиями профиля (удаление).
##
## Нажатие на карточку — выбор профиля (`chosen`), «⋯» — `menu_requested`. Выделение
## (`toggle_mode`, стиль «нажата» темы — рамка `accent`) — активный профиль.

signal chosen(profile_id: String)
signal menu_requested(profile_id: String, anchor: Control)

const SIZE_REGULAR: Vector2 = Vector2(240, 200)
const SIZE_COMPACT: Vector2 = Vector2(240, 150)
const AVATAR_REGULAR: float = 64.0
const AVATAR_COMPACT: float = 48.0
## Отступ кнопки «⋯» от угла карточки, lp.
const MENU_INSET: float = 8.0
const MENU_ICON: String = "ellipsis"

var profile_id: String = ""
var _compact: bool = false

var _content: VBoxContainer
var _avatar: ProfileAvatar
var _name: Label
var _stats: Label
var _menu: Button


func _init() -> void:
	theme_type_variation = &"CardButton"
	toggle_mode = true
	text = ""
	auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	custom_minimum_size = SIZE_REGULAR
	_content = VBoxContainer.new()
	_content.name = "Content"
	_content.theme_type_variation = &"Stack8"
	_content.alignment = BoxContainer.ALIGNMENT_CENTER
	_content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 16)
	_content.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_content)
	_avatar = ProfileAvatar.new()
	_avatar.name = "Avatar"
	_avatar.custom_minimum_size = Vector2(AVATAR_REGULAR, AVATAR_REGULAR)
	_avatar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_content.add_child(_avatar)
	_name = _make_label("Name", &"TitleLabel")
	_stats = _make_label("Stats", &"CaptionNumLabel")
	_menu = Button.new()
	_menu.name = "Menu"
	_menu.theme_type_variation = &"IconButton"
	_menu.icon = UiIcons.icon(MENU_ICON)
	_menu.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_menu.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_menu.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_menu.pressed.connect(_on_menu_pressed)
	add_child(_menu)
	pressed.connect(_on_pressed)


func _ready() -> void:
	TouchTarget.attach(self, TouchTarget.Kind.UI)
	TouchTarget.attach(_menu, TouchTarget.Kind.UI)
	_menu.minimum_size_changed.connect(_place_menu)
	resized.connect(_place_menu)
	_place_menu()


## Данные карточки: id, имя (пользовательские данные), строка «FTP · вес» (готовый текст).
func set_profile(id: String, name_text: String, stats_text: String) -> void:
	profile_id = id
	_avatar.set_profile(id, name_text)
	_name.text = name_text
	_stats.text = stats_text


## Размер карточки и аватара: regular 240×200 (аватар 64), compact 240×150 (аватар 48).
func set_compact(compact: bool) -> void:
	_compact = compact
	var floor_size := SIZE_COMPACT if compact else SIZE_REGULAR
	var touch := TouchTarget.of(self)
	if touch != null:
		touch.set_floor(floor_size)
	else:
		custom_minimum_size = floor_size
	var avatar := AVATAR_COMPACT if compact else AVATAR_REGULAR
	_avatar.custom_minimum_size = Vector2(avatar, avatar)


## Показать «⋯» (нет смысла, когда удалить профиль нельзя — он единственный).
func set_menu_visible(shown: bool) -> void:
	_menu.visible = shown


## Выделить карточку (активный профиль) без сигналов.
func set_selected(selected: bool) -> void:
	set_pressed_no_signal(selected)


func is_selected() -> bool:
	return button_pressed


func name_text() -> String:
	return _name.text


func stats_text() -> String:
	return _stats.text


func menu_button() -> Button:
	return _menu


func avatar() -> ProfileAvatar:
	return _avatar


func _make_label(node_name: String, variation: StringName) -> Label:
	var label := Label.new()
	label.name = node_name
	label.theme_type_variation = variation
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.clip_text = true
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.mouse_filter = Control.MOUSE_FILTER_PASS
	_content.add_child(label)
	return label


func _place_menu() -> void:
	var menu_size := _menu.get_combined_minimum_size()
	_menu.size = menu_size
	_menu.position = Vector2(size.x - menu_size.x - MENU_INSET, MENU_INSET)


func _on_pressed() -> void:
	chosen.emit(profile_id)


func _on_menu_pressed() -> void:
	menu_requested.emit(profile_id, _menu)
