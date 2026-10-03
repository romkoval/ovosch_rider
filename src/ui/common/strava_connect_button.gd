class_name StravaConnectButton
extends VBoxContainer
## Кнопка привязки Strava по брендбуку (REQ-STR-01 крит. 7/9, `StravaBranding`): без привязки —
## оранжевая (#FC5200) кнопка высотой 48 px с текстом «Connect with Strava» (не переводится);
## с привязкой — нейтральная «Отвязать Strava». Ниже — ссылка на страницу входа
## (`LinkButton.uri`, браузер открывает сам Godot) и подпись «Powered by Strava».
## Компонент только отражает состояние и испускает сигналы; логика — в `StravaService`.

signal connect_requested()
signal disconnect_requested()

var _authorized: bool = false
var _busy: bool = false

@onready var _button: Button = %Button
@onready var _open_link: LinkButton = %OpenLink
@onready var _powered_by: Label = %PoweredBy


func _ready() -> void:
	_button.custom_minimum_size.y = StravaBranding.CONNECT_BUTTON_HEIGHT_PX
	_button.custom_minimum_size.x = StravaBranding.CONNECT_BUTTON_MIN_WIDTH_PX
	_button.pressed.connect(_on_pressed)
	_open_link.visible = false
	# Ключи `ui.strava.connect` / `ui.strava.powered_by` в обеих локалях содержат один и тот же
	# английский текст: брендбук Strava требует именно «Connect with Strava» и «Powered by Strava»
	# (`StravaBranding.TEXT_*`); ключ нужен лишь для проверки «в сценах нет литералов».
	_powered_by.text = tr("ui.strava.powered_by")
	_render()


func set_authorized(authorized: bool) -> void:
	_authorized = authorized
	if authorized:
		_open_link.visible = false
	_render()


func is_authorized() -> bool:
	return _authorized


## Ожидание входа/отзыва: кнопка недоступна.
func set_busy(busy: bool) -> void:
	_busy = busy
	_render()


## Привязка недоступна (нет client_id/client_secret): кнопка выключена.
func set_available(available: bool) -> void:
	_button.disabled = not available or _busy
	_button.visible = true


## URL авторизации: показать ссылку «Открыть страницу входа Strava» (пусто — скрыть).
func set_authorize_url(url: String) -> void:
	_open_link.uri = url
	_open_link.visible = not url.is_empty()


func authorize_url() -> String:
	return _open_link.uri if _open_link.visible else ""


func button_text() -> String:
	return _button.text


func is_button_disabled() -> bool:
	return _button.disabled


func _on_pressed() -> void:
	if _authorized:
		disconnect_requested.emit()
	else:
		connect_requested.emit()


func _render() -> void:
	if not is_node_ready():
		return
	_button.disabled = _busy
	if _authorized:
		_button.text = tr("ui.settings.strava_disconnect")
		_button.remove_theme_stylebox_override("normal")
		_button.remove_theme_stylebox_override("hover")
		_button.remove_theme_stylebox_override("pressed")
		_button.remove_theme_color_override("font_color")
	else:
		_button.text = tr("ui.strava.connect")
		var style := StyleBoxFlat.new()
		style.bg_color = StravaBranding.BRAND_COLOR
		style.set_corner_radius_all(4)
		style.content_margin_left = 16
		style.content_margin_right = 16
		_button.add_theme_stylebox_override("normal", style)
		var hover := style.duplicate() as StyleBoxFlat
		hover.bg_color = StravaBranding.BRAND_COLOR.lightened(0.1)
		_button.add_theme_stylebox_override("hover", hover)
		var pressed := style.duplicate() as StyleBoxFlat
		pressed.bg_color = StravaBranding.BRAND_COLOR.darkened(0.1)
		_button.add_theme_stylebox_override("pressed", pressed)
		_button.add_theme_color_override("font_color", Color.WHITE)
	_open_link.text = tr("ui.strava.open_browser")


## Цвет фона кнопки в состоянии «не привязано» (для тестов брендбука).
func brand_color() -> Color:
	var style := _button.get_theme_stylebox("normal")
	return (style as StyleBoxFlat).bg_color if style is StyleBoxFlat else Color.TRANSPARENT
