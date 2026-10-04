class_name RideSummaryCard
extends Control
## Итог заезда поверх 3D (`docs/game/ui.md` п. 8.8; REQ-HUD-14 крит. 7, 8) — общий для экрана
## тренировки по плану и свободной езды.
##
## Вуаль `scrim` на весь кадр, по центру карточка `HudSummaryCard` (`surface1` с альфой 0.97,
## радиус 18): заголовок Display («Тренировка завершена» / «Заезд завершён»), подзаголовок
## (название тренировки или трассы), сетка плиток Stat Large 3 × 2 (`Grid16`), строка пауз
## Caption — только если паузы были (`paused_total_sec` > 0), кнопки «Открыть в истории»
## (вторичная, слева) и «На главный» (основная, справа). Ширина карточки — min(720, W − 2·16) на
## всех устройствах, высота по содержимому, по центру области внутри безопасной зоны. Кнопки —
## цель `touch_hud` (экран заезда в масштабе HUD, UIX-05 крит. 1).
##
## Компонент не знает о сессии: экран задаёт плитки (`setup_stats`), значения (`set_value`),
## тексты и время пауз. Кнопки — сигналы `home_requested` и `history_requested`; их узлы
## доступны и по уникальным именам экрана (`share_unique_names`: `%HomeButton`, `%HistoryButton`).

signal home_requested
signal history_requested

## Ширина карточки (`ui.md` п. 8.8) и поля от края области.
const CARD_WIDTH: float = 720.0
const MARGIN: float = 16.0
const KEY_PAUSED: String = "ui.summary.paused"

## Безопасная зона, lp (слева, сверху, справа, снизу); null — из `UiScaleRuntime`.
var safe_margins_override: Variant = null

var _values: Dictionary = {}
var _keys: Array[String] = []
var _paused_sec: float = 0.0

@onready var _scrim: ColorRect = %Scrim
@onready var _center: CenterContainer = %Center
@onready var _card: PanelContainer = %SummaryCard
@onready var _title: Label = %SummaryTitle
@onready var _subtitle: Label = %SummarySubtitle
@onready var _grid: GridContainer = %StatsGrid
@onready var _paused_label: Label = %PausedLabel
@onready var _history_button: Button = %HistoryButton
@onready var _home_button: Button = %HomeButton


func _ready() -> void:
	_scrim.color = UiTokens.SCRIM
	_home_button.pressed.connect(_on_home_pressed)
	_history_button.pressed.connect(_on_history_pressed)
	for b: Button in [_history_button, _home_button]:
		TouchTarget.attach(b, TouchTarget.Kind.HUD)
	resized.connect(fit)
	visibility_changed.connect(fit)


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_render_paused()


## Плитки: `[{"key": "time", "caption": "<ключ подписи>"}, …]` по порядку сетки (3 в ряд).
func setup_stats(stats: Array[Dictionary]) -> void:
	for child in _grid.get_children():
		_grid.remove_child(child)
		child.queue_free()
	_values.clear()
	_keys.clear()
	for spec in stats:
		var key := str(spec["key"])
		var box := VBoxContainer.new()
		box.name = "Stat_" + key
		box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var value := Label.new()
		value.name = "Value"
		value.theme_type_variation = &"StatLargeLabel"
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		value.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		var caption := Label.new()
		caption.name = "Caption"
		caption.theme_type_variation = &"CaptionLabel"
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		caption.text = str(spec["caption"])
		box.add_child(value)
		box.add_child(caption)
		_grid.add_child(box)
		_values[key] = value
		_keys.append(key)


func set_title(text: String) -> void:
	_title.text = text


func set_subtitle(text: String) -> void:
	_subtitle.text = text
	_subtitle.visible = not text.is_empty()


func set_value(key: String, text: String) -> void:
	var label: Label = _values.get(key, null)
	if label != null:
		label.text = text


## Время пауз, с: строка «Паузы: 01:15» видна только при значении > 0 (HUD-14 крит. 7).
func set_paused_sec(sec: float) -> void:
	_paused_sec = maxf(sec, 0.0)
	_render_paused()


func set_history_enabled(enabled: bool) -> void:
	_history_button.disabled = not enabled


# ---------------------------------------------------------------------------
# Доступ (экраны, тесты)
# ---------------------------------------------------------------------------

func value_text(key: String) -> String:
	var label: Label = _values.get(key, null)
	return label.text if label != null else ""


func stat_keys() -> Array[String]:
	return _keys.duplicate()


func title_text() -> String:
	return _title.text


func subtitle_text() -> String:
	return _subtitle.text if _subtitle.visible else ""


## Строка пауз ("" — пауз не было).
func paused_text() -> String:
	return _paused_label.text if _paused_label.visible else ""


func card() -> PanelContainer:
	return _card


func scrim() -> ColorRect:
	return _scrim


func home_button() -> Button:
	return _home_button


func history_button() -> Button:
	return _history_button


## Узлы кнопок доступны по уникальным именам и от экрана-владельца (`%HomeButton`, `%HistoryButton`).
func share_unique_names(new_owner: Node) -> void:
	for node: Node in [_home_button, _history_button]:
		node.owner = new_owner
		node.unique_name_in_owner = true


## Разместить карточку: по центру области внутри безопасной зоны, ширина min(720, W − 2·16).
func fit() -> void:
	if not is_node_ready() or size.x <= 0.0 or size.y <= 0.0:
		return
	var safe := _safe_margins()
	_center.offset_left = safe.x
	_center.offset_top = safe.y
	_center.offset_right = -safe.z
	_center.offset_bottom = -safe.w
	var avail_w := size.x - safe.x - safe.z
	_card.custom_minimum_size = Vector2(minf(CARD_WIDTH, maxf(avail_w - 2.0 * MARGIN, 0.0)), 0.0)


func _safe_margins() -> Vector4:
	if safe_margins_override is Vector4:
		return safe_margins_override
	var ui := get_node_or_null(^"/root/UiScaleRuntime") as UiScale
	return ui.safe_margins() if ui != null else Vector4.ZERO


func _render_paused() -> void:
	_paused_label.visible = _paused_sec > 0.0
	_paused_label.text = tr(KEY_PAUSED).format({"paused": HudModel.format_elapsed(roundi(_paused_sec))}) \
			if _paused_label.visible else ""


func _on_home_pressed() -> void:
	home_requested.emit()


func _on_history_pressed() -> void:
	history_requested.emit()
