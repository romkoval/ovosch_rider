class_name NextChip
extends Control
## Фишка «ДАЛЕЕ · 1:00 · 125 Вт      5» в слоте подсказки за 5 с до смены шага
## (`docs/game/hud.md` п. 10.1; REQ-HUD-06 крит. 2 — отображение состояния «скоро смена»).
##
## Самостоятельный компонент: не знает о сессии и экране. Экран (T-078) на каждом тике
## вызывает `show_next(...)` и `set_seconds_left(...)`, пока модель HUD говорит
## `about_to_change`, и `hide_chip()` на смене шага. Появление — прозрачность 0 → 1 и сдвиг
## на 8 lp вниз за 200 мс, исчезание — прозрачность 1 → 0 за 200 мс.
##
## Вид: подложка `HudPlate`, слева полоса 6 lp цветом зоны следующего шага, подпись «ДАЛЕЕ»
## (`HudCaptionLabel`), строка «длительность · цель» и секунды справа — 18 lp, вес 750, `tnum`
## (`HudTargetLabel` с размером из `hud.md`), секунды цветом `hud.warn`. Размеры в lp HUD:
## множитель телефона `s` применяет окно (`UiScale`, `content_scale_factor`).

## Появление и исчезание, с.
const FADE_SEC: float = 0.2
## Сдвиг при появлении (сверху вниз), lp.
const SLIDE_LP: float = 8.0
## Ширина полосы цвета зоны, lp.
const STRIP_WIDTH_LP: float = 6.0
## Размер строки и секунд (`hud.md` п. 10.1: 18·s / 750 `tnum`), lp.
const TEXT_FONT_SIZE: int = 18
## Высота фишки (слот подсказки — не выше 40·s), lp.
const HEIGHT_LP: float = 40.0
## Минимальная ширина фишки (секунды прижаты вправо, как в макете `plan_next_1280.png`), lp.
const MIN_WIDTH_LP: float = 280.0
## Префикс ключей перевода компонента (`assets/i18n/strings_hud_controls.csv`).
const KEY: String = "ui.hud_controls."
## Секунды отсчёта показываются в диапазоне 1…5 (`hud.md` п. 10.1).
const MAX_SECONDS: int = 5

var _plate: PanelContainer
var _strip: ColorRect
var _caption: Label
var _line: Label
var _seconds: Label
var _shown: bool = false
var _slide: float = 0.0
var _tween: Tween
var _zone_color: Color = UiTokens.HUD_FREE


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	modulate.a = 0.0
	_build()


func _ready() -> void:
	resized.connect(_layout_plate)
	_layout_plate()


## Показать фишку следующего шага. `duration_sec` — длительность шага, `target_text` —
## готовая цель (`format_target`), `zone_color` — цвет зоны следующего шага. Если фишка
## уже на экране, меняется только содержимое (без повторной анимации).
func show_next(duration_sec: int, target_text: String, zone_color: Color) -> void:
	_zone_color = zone_color
	_strip.color = zone_color
	_line.text = tr(KEY + "next.line").format({"duration": format_duration(duration_sec), "target": target_text})
	if _shown:
		return
	_shown = true
	visible = true
	_animate(1.0, -SLIDE_LP)


## Секунды до смены шага, справа на фишке (ограничены 0…5).
func set_seconds_left(seconds: int) -> void:
	_seconds.text = "%d" % clampi(seconds, 0, MAX_SECONDS)


## Убрать фишку (прозрачность 1 → 0 за 200 мс).
func hide_chip() -> void:
	if not _shown:
		return
	_shown = false
	_animate(0.0, 0.0)


## Фишка на экране (или появляется).
func is_shown() -> bool:
	return _shown


## Текст строки «длительность · цель».
func line_text() -> String:
	return _line.text


## Текст секунд справа.
func seconds_text() -> String:
	return _seconds.text


## Цвет полосы зоны.
func zone_color() -> Color:
	return _zone_color


## Длительность шага: `м:сс`, от часа — `ч:мм:сс` (`hud.md` п. 13).
static func format_duration(total_sec: int) -> String:
	var t := maxi(total_sec, 0)
	if t >= 3600:
		return "%d:%02d:%02d" % [t / 3600, (t % 3600) / 60, t % 60]
	return "%d:%02d" % [t / 60, t % 60]


## Цель шага: `125 Вт`, рампа `125→225 Вт`, свободный шаг (`start_w` < 0) — `свободно`.
static func format_target(start_w: int, end_w: int = -1) -> String:
	if start_w < 0:
		return TranslationServer.translate(KEY + "next.free")
	if end_w >= 0 and end_w != start_w:
		return str(TranslationServer.translate(KEY + "next.ramp")).format({"from": start_w, "to": end_w})
	return str(TranslationServer.translate(KEY + "next.watts")).format({"value": start_w})


func _get_minimum_size() -> Vector2:
	return _plate.get_combined_minimum_size() if _plate != null else Vector2.ZERO


func _build() -> void:
	_plate = PanelContainer.new()
	_plate.name = "Plate"
	_plate.theme_type_variation = &"HudPlate"
	_plate.custom_minimum_size = Vector2(MIN_WIDTH_LP, HEIGHT_LP)
	_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_plate)
	var row := HBoxContainer.new()
	row.name = "Row"
	row.add_theme_constant_override("separation", 12)
	_plate.add_child(row)
	_strip = ColorRect.new()
	_strip.name = "ZoneStrip"
	_strip.custom_minimum_size = Vector2(STRIP_WIDTH_LP, 0.0)
	_strip.color = _zone_color
	row.add_child(_strip)
	_caption = _label("Caption", &"HudCaptionLabel")
	_caption.text = KEY + "next.caption"
	row.add_child(_caption)
	_line = _label("Line", &"HudTargetLabel")
	_line.add_theme_font_size_override("font_size", TEXT_FONT_SIZE)
	_line.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_line)
	_seconds = _label("Seconds", &"HudTargetLabel")
	_seconds.add_theme_font_size_override("font_size", TEXT_FONT_SIZE)
	_seconds.add_theme_color_override("font_color", UiTokens.HUD_WARN)
	_seconds.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_seconds.text = "%d" % MAX_SECONDS
	row.add_child(_seconds)
	_plate.minimum_size_changed.connect(update_minimum_size)


func _label(node_name: String, variation: StringName) -> Label:
	var l := Label.new()
	l.name = node_name
	l.theme_type_variation = variation
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _animate(alpha: float, slide_from: float) -> void:
	if _tween != null:
		_tween.kill()
	if alpha > 0.0:
		_set_slide(slide_from)
	if not is_inside_tree():
		modulate.a = alpha
		_set_slide(0.0)
		visible = alpha > 0.0
		return
	_tween = create_tween().set_parallel(true)
	_tween.tween_property(self, "modulate:a", alpha, FADE_SEC)
	if alpha > 0.0:
		_tween.tween_method(_set_slide, slide_from, 0.0, FADE_SEC).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	else:
		_tween.chain().tween_callback(_after_hide)


func _after_hide() -> void:
	if not _shown:
		visible = false


func _set_slide(value: float) -> void:
	_slide = value
	_layout_plate()


func _layout_plate() -> void:
	if _plate == null:
		return
	var plate_size := _plate.get_combined_minimum_size()
	_plate.size = plate_size
	_plate.position = Vector2(roundf((size.x - plate_size.x) * 0.5), _slide)
