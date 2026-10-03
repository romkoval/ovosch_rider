class_name ProfileAvatar
extends Control
## Аватар профиля (`docs/game/ui.md` п. 4, 8.1): круг цвета `UiTokens.avatar_color(id)` с
## инициалом имени цветом `text`. Размер — `custom_minimum_size` узла (карточка выбора
## профиля — 64 lp). Рисовать аватар на чужом узле (фишка профиля в AppBar) — `draw_on()`.
##
## Цвет аватара — данные профиля (хэш id), а не переопределение темы.

## Доля диаметра, которую занимает кегль инициала.
const INITIAL_SIZE_RATIO: float = 0.42

var profile_id: String = "":
	set(value):
		profile_id = value
		queue_redraw()
var profile_name: String = "":
	set(value):
		profile_name = value
		queue_redraw()


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var diameter := minf(size.x, size.y)
	draw_on(self, size * 0.5, diameter, profile_id, profile_name)


## Задать профиль одним вызовом.
func set_profile(id: String, name_text: String) -> void:
	profile_id = id
	profile_name = name_text


## Нарисовать аватар на `canvas` с центром `center` и диаметром `diameter`.
static func draw_on(canvas: Control, center: Vector2, diameter: float, id: String, name_text: String) -> void:
	if diameter <= 0.0:
		return
	canvas.draw_circle(center, diameter * 0.5, UiTokens.avatar_color(id), true, -1.0, true)
	var letter := initial(name_text)
	if letter.is_empty():
		return
	var font := canvas.get_theme_font("font", "Label")
	var font_size := maxi(int(roundf(diameter * INITIAL_SIZE_RATIO)), 8)
	var text_size := font.get_string_size(letter, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var baseline := center + Vector2(-text_size.x * 0.5, (font.get_ascent(font_size) - font.get_descent(font_size)) * 0.5)
	canvas.draw_string(font, baseline, letter, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, UiTokens.TEXT)


## Инициал имени (первая буква, заглавная); пустое имя — "".
static func initial(name_text: String) -> String:
	return name_text.strip_edges().left(1).to_upper()
