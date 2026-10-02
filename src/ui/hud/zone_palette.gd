class_name ZonePalette
extends RefCounted
## Палитра зон для HUD (REQ-HUD-03 крит. 2, REQ-HUD-04, REQ-INT-05 крит. 3; «Открытые решения» п. 7).
##
## Модель HUD оперирует ТОКЕНАМИ (`"z1".."z7"`, `"hr1".."hr5"`, `""` — нет зоны);
## сами цвета живут только здесь, чтобы тема/оформление менялись в одном месте.
## Мощность: Z1 серый, Z2 синий, Z3 зелёный, Z4 жёлтый, Z5 оранжевый, Z6 красный, Z7 фиолетовый.
## Пульс: 5 зон серый/синий/зелёный/оранжевый/красный.

const POWER_TOKENS: Array[String] = ["z1", "z2", "z3", "z4", "z5", "z6", "z7"]
const HR_TOKENS: Array[String] = ["hr1", "hr2", "hr3", "hr4", "hr5"]
const NO_ZONE_TOKEN: String = ""

const COLOR_NAMES: Dictionary = {
	"z1": "gray", "z2": "blue", "z3": "green", "z4": "yellow", "z5": "orange", "z6": "red", "z7": "purple",
	"hr1": "gray", "hr2": "blue", "hr3": "green", "hr4": "orange", "hr5": "red",
}

const COLORS: Dictionary = {
	"gray": Color(0.55, 0.55, 0.58),
	"blue": Color(0.25, 0.55, 0.95),
	"green": Color(0.30, 0.75, 0.40),
	"yellow": Color(0.95, 0.85, 0.25),
	"orange": Color(0.95, 0.55, 0.20),
	"red": Color(0.90, 0.25, 0.25),
	"purple": Color(0.65, 0.35, 0.85),
}
## Цвет «нет зоны» — нейтральный, без акцента.
const NO_ZONE_COLOR: Color = Color(0.35, 0.35, 0.38)


## Токен зоны мощности 1..7 (0 или вне диапазона → "").
static func power_token(zone: int) -> String:
	return POWER_TOKENS[zone - 1] if zone >= 1 and zone <= POWER_TOKENS.size() else NO_ZONE_TOKEN


## Токен зоны пульса 1..5 (0 или вне диапазона → "").
static func hr_token(zone: int) -> String:
	return HR_TOKENS[zone - 1] if zone >= 1 and zone <= HR_TOKENS.size() else NO_ZONE_TOKEN


## Имя цвета токена ("gray", "blue", …); "" для отсутствия зоны.
static func color_name(token: String) -> String:
	return str(COLOR_NAMES.get(token, ""))


## Цвет токена; неизвестный/пустой токен → `NO_ZONE_COLOR`.
static func color(token: String) -> Color:
	var name := color_name(token)
	return COLORS[name] if COLORS.has(name) else NO_ZONE_COLOR


static func is_valid_token(token: String) -> bool:
	return COLOR_NAMES.has(token)
