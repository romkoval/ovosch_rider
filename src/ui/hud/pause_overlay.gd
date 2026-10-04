class_name PauseOverlay
extends Control
## Вуаль и карточка паузы (`docs/game/hud.md` п. 10.2; REQ-WRK-05 — UI паузы, возобновления
## и досрочного завершения с подтверждением крит. 4).
##
## Самостоятельный компонент: не знает о сессии и экране, только отдаёт сигналы. Экран
## (T-078, T-084) кладёт его на весь кадр между 3D-сценой и HUD и вызывает:
## - `show_pause()` — сессия на паузе: вуаль `hud.ink` 0.35 (200 мс) и карточка «Пауза»
##   с «Продолжить», «Пропустить шаг» (только режим плана) и «Завершить»;
## - `show_finish_confirmation()` — подтверждение досрочного завершения (WRK-05.4); то же
##   открывает «Завершить» на карточке. Если подтверждение открыто не с паузы (кнопка
##   «Завершить» панели инструментов), «Отмена» убирает вуаль целиком;
## - `hide_overlay()` — сессия возобновлена.
##
## Клавиши (когда вуаль на экране; событие поглощается раньше остального интерфейса):
## Пробел и Enter на карточке паузы — «Продолжить»; Esc в подтверждении — назад, на
## карточке паузы — ничего (не уходит дальше к панели инструментов).
##
## Подтверждение завершения — диалог по `ui.md` п. 6 (REQ-UIX-01 крит. 8): карточка 480 lp, текст с
## переносом, кнопки у правого края по ширине текста — «Отмена» (вторичная) слева, «Завершить»
## (опасная) справа, фокус при открытии — «Отмена».
##
## Карточка паузы: 360 lp, фон `surface1` с альфой 0.94, радиус 18 (`hud.md` п. 10.2) — вариация темы
## `HudPauseCard`; «Пауза» — 30 lp / 750, `HudPauseTitle`; «Продолжить» — высота
## `max(52, touch_hud)`; текстовые кнопки — `touch_hud`.
## `touch_hud` берётся из автозагрузки `UiScaleRuntime` (48 / 52 / 72 lp HUD).

## «Продолжить» на карточке паузы (кнопка, Пробел или Enter).
signal resume_requested
## «Пропустить шаг» на карточке паузы (только режим плана).
signal skip_requested
## Досрочное завершение подтверждено.
signal finish_confirmed
## Подтверждение завершения отменено («Отмена» или Esc).
signal finish_cancelled

enum View { HIDDEN, PAUSE, CONFIRM }

const FADE_SEC: float = 0.2
## Префикс ключей перевода компонента (`assets/i18n/strings_hud_controls.csv`); тексты
## узлов задаются в `_ready` и переводятся автоматически (`auto_translate_mode`).
const KEY: String = "ui.hud_controls."
const CARD_WIDTH_LP: float = 360.0
## Ширина карточки подтверждения — ширина диалога (`DialogLayout.WIDTH`, `ui.md` п. 6).
const CONFIRM_WIDTH_LP: float = 480.0
const CARD_RADIUS_LP: int = 18
const CARD_ALPHA: float = 0.94
const CARD_MARGIN: Vector2 = Vector2(24, 20)
## Минимальная высота основной кнопки, lp HUD (`hud.md` п. 10.2).
const PRIMARY_MIN_LP: float = 52.0

var _mode: HudToolbar.Mode = HudToolbar.Mode.PLAN
var _view: View = View.HIDDEN
var _confirm_from_pause: bool = false
var _touch: float = UiScale.TOUCH_HUD_DESKTOP
var _tween: Tween

@onready var _veil: ColorRect = %Veil
@onready var _card: PanelContainer = %Card
@onready var _pause_view: VBoxContainer = %PauseView
@onready var _confirm_view: VBoxContainer = %ConfirmView
@onready var _title: Label = %Title
@onready var _subtitle: Label = %Subtitle
@onready var _confirm_title: Label = %ConfirmTitle
@onready var _confirm_body: Label = %ConfirmBody
@onready var _resume_button: Button = %ResumeButton
@onready var _skip_button: Button = %SkipButton
@onready var _finish_button: Button = %FinishButton
@onready var _cancel_button: Button = %CancelButton
@onready var _confirm_button: Button = %ConfirmButton


func _ready() -> void:
	_veil.color = UiTokens.HUD_PAUSE_VEIL
	_title.text = KEY + "pause.title"
	_subtitle.text = KEY + "pause.subtitle"
	_resume_button.text = KEY + "pause.resume"
	_skip_button.text = KEY + "pause.skip"
	_finish_button.text = KEY + "pause.finish"
	_confirm_title.text = KEY + "finish.title"
	_cancel_button.text = KEY + "finish.cancel"
	_confirm_button.text = KEY + "finish.confirm"
	_resume_button.pressed.connect(_on_resume_pressed)
	_skip_button.pressed.connect(_on_skip_pressed)
	_finish_button.pressed.connect(show_finish_confirmation)
	_cancel_button.pressed.connect(cancel_finish)
	_confirm_button.pressed.connect(_on_confirm_pressed)
	var ui := get_node_or_null(^"/root/UiScaleRuntime") as UiScale
	set_touch_target(ui.touch_hud() if ui != null else UiScale.TOUCH_HUD_DESKTOP)
	_apply_view()


## Режим экрана: в свободной езде нет «Пропустить шаг», текст подтверждения — про заезд.
func set_mode(mode: HudToolbar.Mode) -> void:
	_mode = mode
	if is_node_ready():
		_apply_view()


func get_mode() -> HudToolbar.Mode:
	return _mode


## Сторона цели нажатия кнопок карточки, lp HUD (`touch_hud`).
func set_touch_target(lp: float) -> void:
	_touch = lp
	if not is_node_ready():
		return
	_resume_button.custom_minimum_size.y = maxf(PRIMARY_MIN_LP, lp)
	for b: Button in [_skip_button, _finish_button, _cancel_button, _confirm_button]:
		b.custom_minimum_size = Vector2(lp, lp)


## Показать карточку паузы.
func show_pause() -> void:
	_set_view(View.PAUSE)


## Показать подтверждение досрочного завершения (WRK-05.4).
func show_finish_confirmation() -> void:
	if _view == View.CONFIRM:
		return
	_confirm_from_pause = _view == View.PAUSE
	_set_view(View.CONFIRM)
	# Enter в подтверждении нажимает «Отмена», а не «Завершить» (сразу и после кадра).
	if _cancel_button.is_visible_in_tree():
		_cancel_button.grab_focus()
	_cancel_button.grab_focus.call_deferred()


## Отменить подтверждение: назад к карточке паузы или убрать вуаль.
func cancel_finish() -> void:
	if _view != View.CONFIRM:
		return
	if _confirm_from_pause:
		show_pause()
	else:
		hide_overlay()
	finish_cancelled.emit()


## Убрать вуаль и карточку.
func hide_overlay() -> void:
	_set_view(View.HIDDEN)


func is_shown() -> bool:
	return _view != View.HIDDEN


func view() -> View:
	return _view


## Видимые кнопки текущей карточки (для проверок целей нажатия и состава).
func visible_buttons() -> Array[Button]:
	var out: Array[Button] = []
	if _view == View.HIDDEN:
		return out
	var root: Control = _pause_view if _view == View.PAUSE else _confirm_view
	for b: Button in [_resume_button, _skip_button, _finish_button, _cancel_button, _confirm_button]:
		if b.is_visible_in_tree() and root.is_ancestor_of(b):
			out.append(b)
	return out


func resume_button() -> Button:
	return _resume_button


func skip_button() -> Button:
	return _skip_button


func finish_button() -> Button:
	return _finish_button


func cancel_button() -> Button:
	return _cancel_button


func confirm_button() -> Button:
	return _confirm_button


## Стиль карточки из токенов: `surface1` с альфой 0.94, радиус 18 (`hud.md` п. 10.2) — тот же,
## что у вариации `HudPauseCard` темы; на узле применяется вариация, функция — для сверки.
static func card_style() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(UiTokens.SURFACE1, CARD_ALPHA)
	box.set_corner_radius_all(CARD_RADIUS_LP)
	box.content_margin_left = CARD_MARGIN.x
	box.content_margin_right = CARD_MARGIN.x
	box.content_margin_top = CARD_MARGIN.y
	box.content_margin_bottom = CARD_MARGIN.y
	box.corner_detail = 8
	box.anti_aliasing = true
	return box


func _input(event: InputEvent) -> void:
	if _view == View.HIDDEN:
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	var code := key.keycode if key.keycode != KEY_NONE else key.physical_keycode
	match code:
		KEY_SPACE, KEY_ENTER, KEY_KP_ENTER:
			if _view != View.PAUSE:
				return
			_on_resume_pressed()
		KEY_ESCAPE:
			if _view == View.CONFIRM:
				cancel_finish()
		_:
			return
	get_viewport().set_input_as_handled()


func _set_view(v: View) -> void:
	var was_shown := is_shown()
	_view = v
	_apply_view()
	if is_shown() != was_shown:
		_fade(is_shown())


func _apply_view() -> void:
	if not is_node_ready():
		return
	_pause_view.visible = _view != View.CONFIRM
	_confirm_view.visible = _view == View.CONFIRM
	_skip_button.visible = _mode == HudToolbar.Mode.PLAN
	_confirm_body.text = KEY + "finish.body_plan" if _mode == HudToolbar.Mode.PLAN else KEY + "finish.body_free_ride"
	_card.custom_minimum_size.x = CONFIRM_WIDTH_LP if _view == View.CONFIRM else CARD_WIDTH_LP
	_card.mouse_filter = Control.MOUSE_FILTER_STOP if is_shown() else Control.MOUSE_FILTER_IGNORE


func _fade(appear: bool) -> void:
	if _tween != null:
		_tween.kill()
	if appear:
		visible = true
	if not is_inside_tree():
		modulate.a = 1.0 if appear else 0.0
		visible = appear
		return
	_tween = create_tween()
	_tween.tween_property(self, "modulate:a", 1.0 if appear else 0.0, FADE_SEC)
	if not appear:
		_tween.tween_callback(_after_hide)


func _after_hide() -> void:
	if _view == View.HIDDEN:
		visible = false


func _on_resume_pressed() -> void:
	if _view == View.PAUSE:
		resume_requested.emit()


func _on_skip_pressed() -> void:
	if _view == View.PAUSE and _mode == HudToolbar.Mode.PLAN:
		skip_requested.emit()


func _on_confirm_pressed() -> void:
	if _view != View.CONFIRM:
		return
	hide_overlay()
	finish_confirmed.emit()
