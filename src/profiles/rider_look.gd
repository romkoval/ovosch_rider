class_name RiderLook
extends RefCounted
## Внешность гонщика профиля (REQ-AVT-01; спека — `docs/game/art-bible.md`, «Гонщик» ред. 2,
## «Слоты внешности»): значения 28 слотов отдельно от геометрии. Модель и материалы применяет
## к этим данным 3D-слой (T-109, `RiderModel.apply_look`); здесь — только данные, проверка,
## пресеты и сериализация. Без узлов, без ссылок на 3D и интерфейс (NFR-06 п.3, AVT-01 п.6).
##
## Слот — строковый ключ (`jersey.main`), значение — строка: ключ палитры формы
## (`FORM_COLORS`) для слотов цвета или одно из перечисленных значений (`ENUMS`) для прочих.
## Формат хранения (`to_dict`): плоский словарь «слот → строка» и поле `version` = 1.
## Чтение (`from_dict`) не падает ни на каких данных: неверное значение слота (неизвестный ключ,
## не строка) получает значение по умолчанию только в этом слоте (AVT-01 п.3), отсутствующие
## слоты — тоже по умолчанию (данные, записанные до появления слота), неизвестные поля
## игнорируются. Сброшенные при чтении слоты — `reset_slots()`.
##
## Внешность по умолчанию — пресет `classic` (совпадает со столбцом «По умолчанию» таблицы
## слотов). Пресетов шесть: `classic`, `sunrise`, `alpine`, `sprint`, `stealth` и клубная форма
## владельца `volga_union` (список расширяемый: `PRESET_IDS` + `PRESETS` + ключ перевода); названия —
## ключи переводов `ui.menu.rider_look.preset.<id>` (`strings_menu.csv`). Прочерк в таблице
## пресетов (очков или перчаток нет) — значение по умолчанию.
##
## Секретов во внешности нет: только ключи палитры и перечислений (AVT-01 п.7).

const FORMAT_VERSION: int = 1
const VERSION_KEY: String = "version"

# --- Слоты (порядок — таблица слотов спеки) ---
const BODY_FIGURE: String = "body.figure"
const HAIR_STYLE: String = "hair.style"
const JERSEY_PATTERN: String = "jersey.pattern"
const JERSEY_MAIN: String = "jersey.main"
const JERSEY_ACCENT1: String = "jersey.accent1"
const JERSEY_ACCENT2: String = "jersey.accent2"
const SHORTS_MAIN: String = "shorts.main"
const SHORTS_GRIPPER: String = "shorts.gripper"
const SOCKS_MAIN: String = "socks.main"
const SOCKS_CUFF: String = "socks.cuff"
const HELMET_MODEL: String = "helmet.model"
const HELMET_MAIN: String = "helmet.main"
const HELMET_ACCENT: String = "helmet.accent"
const GLASSES_MODEL: String = "glasses.model"
const GLASSES_LENS: String = "glasses.lens"
const GLASSES_FRAME: String = "glasses.frame"
const SHOES_MODEL: String = "shoes.model"
const SHOES_MAIN: String = "shoes.main"
const SHOES_ACCENT: String = "shoes.accent"
const GLOVES_MODEL: String = "gloves.model"
const GLOVES_COLOR: String = "gloves.color"
const SKIN_TONE: String = "skin.tone"
const HAIR_COLOR: String = "hair.color"
const BIKE_FRAME: String = "bike.frame"
const BIKE_ACCENT: String = "bike.accent"
const BIKE_RIMS: String = "bike.rims"
const BIKE_RIM_DECAL: String = "bike.rim_decal"
const BIKE_BAR_TAPE: String = "bike.bar_tape"

const SLOTS: Array[String] = [
	BODY_FIGURE, HAIR_STYLE, JERSEY_PATTERN, JERSEY_MAIN, JERSEY_ACCENT1, JERSEY_ACCENT2,
	SHORTS_MAIN, SHORTS_GRIPPER, SOCKS_MAIN, SOCKS_CUFF, HELMET_MODEL, HELMET_MAIN, HELMET_ACCENT,
	GLASSES_MODEL, GLASSES_LENS, GLASSES_FRAME, SHOES_MODEL, SHOES_MAIN, SHOES_ACCENT,
	GLOVES_MODEL, GLOVES_COLOR, SKIN_TONE, HAIR_COLOR, BIKE_FRAME, BIKE_ACCENT, BIKE_RIMS,
	BIKE_RIM_DECAL, BIKE_BAR_TAPE,
]

## Палитра формы, sRGB (тёмные цвета разрешены и для `jersey.main` — ред. 2).
const FORM_COLORS: Dictionary = {
	"white": Color(0.95, 0.95, 0.96), "cream": Color(0.93, 0.89, 0.78),
	"red": Color(0.86, 0.14, 0.16), "orange": Color(0.96, 0.50, 0.12),
	"yellow": Color(0.98, 0.82, 0.18), "lime": Color(0.62, 0.82, 0.20),
	"green": Color(0.12, 0.55, 0.32), "graphite": Color(0.20, 0.21, 0.24),
	"teal": Color(0.10, 0.62, 0.66), "sky": Color(0.36, 0.68, 0.92),
	"blue": Color(0.18, 0.28, 0.72), "navy": Color(0.16, 0.18, 0.44),
	"purple": Color(0.48, 0.26, 0.66), "pink": Color(0.94, 0.46, 0.66),
	"grey": Color(0.62, 0.64, 0.68), "black": Color(0.09, 0.09, 0.10),
}
## Тон кожи (`skin.tone`), sRGB.
const SKIN_TONES: Dictionary = {
	"s1": Color(0.96, 0.80, 0.69), "s2": Color(0.92, 0.72, 0.58), "s3": Color(0.87, 0.64, 0.50),
	"s4": Color(0.74, 0.52, 0.38), "s5": Color(0.55, 0.37, 0.26), "s6": Color(0.38, 0.25, 0.18),
}
## Цвет волос (`hair.color`), sRGB.
const HAIR_COLORS: Dictionary = {
	"black": Color(0.10, 0.09, 0.09), "dark_brown": Color(0.24, 0.16, 0.11),
	"brown": Color(0.42, 0.28, 0.17), "blonde": Color(0.80, 0.66, 0.40),
	"red": Color(0.62, 0.27, 0.13), "grey": Color(0.66, 0.66, 0.66),
}
## Линзы (`glasses.lens`): [основной тон, блик], sRGB.
const LENSES: Dictionary = {
	"smoke": [Color(0.18, 0.19, 0.22), Color(0.42, 0.44, 0.50)],
	"blue_mirror": [Color(0.20, 0.42, 0.80), Color(0.62, 0.80, 0.98)],
	"orange_mirror": [Color(0.95, 0.50, 0.15), Color(1.0, 0.78, 0.45)],
}

## Слоты-перечисления и допустимые значения.
const ENUMS: Dictionary = {
	BODY_FIGURE: ["m", "f"],
	HAIR_STYLE: ["short", "tail"],
	JERSEY_PATTERN: ["solid", "side_panels", "chest_band", "shoulder_yoke"],
	HELMET_MODEL: ["aero", "vented"],
	GLASSES_MODEL: ["none", "shield", "half_frame"],
	GLASSES_LENS: ["smoke", "blue_mirror", "orange_mirror"],
	SHOES_MODEL: ["boa", "strap"],
	GLOVES_MODEL: ["none", "short"],
	SKIN_TONE: ["s1", "s2", "s3", "s4", "s5", "s6"],
	HAIR_COLOR: ["black", "dark_brown", "brown", "blonde", "red", "grey"],
	BIKE_RIMS: ["deep", "shallow"],
}

## Узор джерси → откуда берут цвет регионы 3–7 (бока, полоса, плечи, манжеты, воротник):
## `main`, `a1` (accent1), `a2` (accent2).
const PATTERN_SOURCES: Dictionary = {
	"solid": ["main", "main", "main", "a1", "a1"],
	"side_panels": ["a1", "main", "main", "a2", "a2"],
	"chest_band": ["main", "a1", "main", "a1", "a2"],
	"shoulder_yoke": ["a2", "main", "a1", "a1", "a1"],
}

const PRESET_CLASSIC: String = "classic"
const PRESET_SUNRISE: String = "sunrise"
const PRESET_ALPINE: String = "alpine"
const PRESET_SPRINT: String = "sprint"
const PRESET_STEALTH: String = "stealth"
## Клубная форма владельца «Волга Юнион» (решение владельца 2026-10-04; спека ред. 4): чёрные
## джерси и шорты, белые высокие носки, красный шлем, без логотипов.
const PRESET_VOLGA_UNION: String = "volga_union"
const PRESET_IDS: Array[String] = [PRESET_CLASSIC, PRESET_SUNRISE, PRESET_ALPINE, PRESET_SPRINT,
	PRESET_STEALTH, PRESET_VOLGA_UNION]
const DEFAULT_PRESET: String = PRESET_CLASSIC
## Названия пресетов — ключи переводов (полными литералами: инвентаризация ключей ищет их в коде).
const PRESET_NAME_KEYS: Dictionary = {
	PRESET_CLASSIC: "ui.menu.rider_look.preset.classic",
	PRESET_SUNRISE: "ui.menu.rider_look.preset.sunrise",
	PRESET_ALPINE: "ui.menu.rider_look.preset.alpine",
	PRESET_SPRINT: "ui.menu.rider_look.preset.sprint",
	PRESET_STEALTH: "ui.menu.rider_look.preset.stealth",
	PRESET_VOLGA_UNION: "ui.menu.rider_look.preset.volga_union",
}

## Значения пресетов (таблица «Пресеты» спеки); слоты с прочерком не указаны — по умолчанию.
const PRESETS: Dictionary = {
	PRESET_CLASSIC: {
		BODY_FIGURE: "m", HAIR_STYLE: "short", JERSEY_PATTERN: "side_panels",
		JERSEY_MAIN: "white", JERSEY_ACCENT1: "red", JERSEY_ACCENT2: "blue",
		SHORTS_MAIN: "navy", SHORTS_GRIPPER: "black", SOCKS_MAIN: "white", SOCKS_CUFF: "white",
		HELMET_MODEL: "aero", HELMET_MAIN: "white", HELMET_ACCENT: "black",
		GLASSES_MODEL: "shield", GLASSES_LENS: "smoke", GLASSES_FRAME: "black",
		SHOES_MODEL: "boa", SHOES_MAIN: "white", SHOES_ACCENT: "black",
		GLOVES_MODEL: "short", GLOVES_COLOR: "black", SKIN_TONE: "s3", HAIR_COLOR: "dark_brown",
		BIKE_FRAME: "red", BIKE_ACCENT: "yellow", BIKE_RIMS: "deep", BIKE_RIM_DECAL: "yellow",
		BIKE_BAR_TAPE: "black",
	},
	PRESET_SUNRISE: {
		BODY_FIGURE: "f", HAIR_STYLE: "tail", JERSEY_PATTERN: "chest_band",
		JERSEY_MAIN: "orange", JERSEY_ACCENT1: "navy", JERSEY_ACCENT2: "white",
		SHORTS_MAIN: "black", SHORTS_GRIPPER: "orange", SOCKS_MAIN: "white", SOCKS_CUFF: "orange",
		HELMET_MODEL: "vented", HELMET_MAIN: "white", HELMET_ACCENT: "orange",
		GLASSES_MODEL: "half_frame", GLASSES_LENS: "orange_mirror", GLASSES_FRAME: "white",
		SHOES_MODEL: "strap", SHOES_MAIN: "black", SHOES_ACCENT: "orange",
		GLOVES_MODEL: "short", GLOVES_COLOR: "black", SKIN_TONE: "s2", HAIR_COLOR: "blonde",
		BIKE_FRAME: "graphite", BIKE_ACCENT: "orange", BIKE_RIMS: "shallow", BIKE_RIM_DECAL: "white",
		BIKE_BAR_TAPE: "white",
	},
	PRESET_ALPINE: {
		BODY_FIGURE: "f", HAIR_STYLE: "short", JERSEY_PATTERN: "shoulder_yoke",
		JERSEY_MAIN: "teal", JERSEY_ACCENT1: "white", JERSEY_ACCENT2: "navy",
		SHORTS_MAIN: "navy", SHORTS_GRIPPER: "teal", SOCKS_MAIN: "teal", SOCKS_CUFF: "white",
		HELMET_MODEL: "aero", HELMET_MAIN: "black", HELMET_ACCENT: "teal",
		GLASSES_MODEL: "shield", GLASSES_LENS: "blue_mirror", GLASSES_FRAME: "white",
		SHOES_MODEL: "boa", SHOES_MAIN: "black", SHOES_ACCENT: "teal",
		GLOVES_MODEL: "none", SKIN_TONE: "s5", HAIR_COLOR: "black",
		BIKE_FRAME: "white", BIKE_ACCENT: "teal", BIKE_RIMS: "deep", BIKE_RIM_DECAL: "teal",
		BIKE_BAR_TAPE: "white",
	},
	PRESET_SPRINT: {
		BODY_FIGURE: "m", HAIR_STYLE: "short", JERSEY_PATTERN: "solid",
		JERSEY_MAIN: "yellow", JERSEY_ACCENT1: "black", JERSEY_ACCENT2: "black",
		SHORTS_MAIN: "black", SHORTS_GRIPPER: "yellow", SOCKS_MAIN: "black", SOCKS_CUFF: "yellow",
		HELMET_MODEL: "aero", HELMET_MAIN: "yellow", HELMET_ACCENT: "black",
		GLASSES_MODEL: "none",
		SHOES_MODEL: "boa", SHOES_MAIN: "white", SHOES_ACCENT: "yellow",
		GLOVES_MODEL: "short", GLOVES_COLOR: "yellow", SKIN_TONE: "s4", HAIR_COLOR: "red",
		BIKE_FRAME: "black", BIKE_ACCENT: "yellow", BIKE_RIMS: "deep", BIKE_RIM_DECAL: "white",
		BIKE_BAR_TAPE: "yellow",
	},
	PRESET_STEALTH: {
		BODY_FIGURE: "m", HAIR_STYLE: "tail", JERSEY_PATTERN: "side_panels",
		JERSEY_MAIN: "black", JERSEY_ACCENT1: "graphite", JERSEY_ACCENT2: "lime",
		SHORTS_MAIN: "black", SHORTS_GRIPPER: "lime", SOCKS_MAIN: "white", SOCKS_CUFF: "lime",
		HELMET_MODEL: "vented", HELMET_MAIN: "white", HELMET_ACCENT: "lime",
		GLASSES_MODEL: "shield", GLASSES_LENS: "blue_mirror", GLASSES_FRAME: "white",
		SHOES_MODEL: "boa", SHOES_MAIN: "white", SHOES_ACCENT: "black",
		GLOVES_MODEL: "short", GLOVES_COLOR: "black", SKIN_TONE: "s1", HAIR_COLOR: "blonde",
		BIKE_FRAME: "black", BIKE_ACCENT: "lime", BIKE_RIMS: "deep", BIKE_RIM_DECAL: "lime",
		BIKE_BAR_TAPE: "black",
	},
	# Значения — art-bible «Гонщик» ред. 4, таблица «Пресеты» (цвета с видео-референса владельца).
	PRESET_VOLGA_UNION: {
		BODY_FIGURE: "m", HAIR_STYLE: "short", JERSEY_PATTERN: "solid",
		JERSEY_MAIN: "black", JERSEY_ACCENT1: "graphite", JERSEY_ACCENT2: "red",
		SHORTS_MAIN: "black", SHORTS_GRIPPER: "black", SOCKS_MAIN: "white", SOCKS_CUFF: "white",
		HELMET_MODEL: "vented", HELMET_MAIN: "red", HELMET_ACCENT: "black",
		GLASSES_MODEL: "shield", GLASSES_LENS: "smoke", GLASSES_FRAME: "black",
		SHOES_MODEL: "boa", SHOES_MAIN: "black", SHOES_ACCENT: "graphite",
		GLOVES_MODEL: "short", GLOVES_COLOR: "black", SKIN_TONE: "s3", HAIR_COLOR: "dark_brown",
		BIKE_FRAME: "grey", BIKE_ACCENT: "red", BIKE_RIMS: "deep", BIKE_RIM_DECAL: "grey",
		BIKE_BAR_TAPE: "black",
	},
}

var _values: Dictionary = {}
var _reset_slots: Array[String] = []


func _init() -> void:
	_values = (PRESETS[DEFAULT_PRESET] as Dictionary).duplicate()


# ---------------------------------------------------------------------------
# Создание
# ---------------------------------------------------------------------------

## Внешность по умолчанию (`classic`).
static func default_look() -> RiderLook:
	return RiderLook.new()


## Внешность пресета; неизвестный id — null.
static func preset(preset_id: String) -> RiderLook:
	if not PRESETS.has(preset_id):
		return null
	var look := RiderLook.new()
	var values: Dictionary = PRESETS[preset_id]
	for slot in SLOTS:
		look._values[slot] = values.get(slot, default_value(slot))
	return look


## Ключ перевода названия пресета ("" — нет такого).
static func preset_name_key(preset_id: String) -> String:
	return str(PRESET_NAME_KEYS.get(preset_id, ""))


## Пресет, с которым внешность совпадает по всем слотам ("" — ни с одним).
func matching_preset() -> String:
	for id in PRESET_IDS:
		if equals(preset(id)):
			return id
	return ""


# ---------------------------------------------------------------------------
# Слоты
# ---------------------------------------------------------------------------

static func is_slot(slot: String) -> bool:
	return SLOTS.has(slot)


## Слот цвета формы (значение — ключ `FORM_COLORS`).
static func is_color_slot(slot: String) -> bool:
	return is_slot(slot) and not ENUMS.has(slot)


## Значение слота по умолчанию ("" — нет такого слота).
static func default_value(slot: String) -> String:
	return str((PRESETS[DEFAULT_PRESET] as Dictionary).get(slot, ""))


## Допустимые значения слота (цвет формы — все ключи палитры).
static func allowed_values(slot: String) -> Array[String]:
	var out: Array[String] = []
	if ENUMS.has(slot):
		for v: String in ENUMS[slot]:
			out.append(v)
	elif is_slot(slot):
		for k: String in FORM_COLORS.keys():
			out.append(k)
	return out


## Значение допустимо для слота: строка из `allowed_values(slot)`.
static func is_valid_value(slot: String, value: Variant) -> bool:
	if not (value is String) or not is_slot(slot):
		return false
	if ENUMS.has(slot):
		return (ENUMS[slot] as Array).has(value)
	return FORM_COLORS.has(value)


func get_value(slot: String) -> String:
	return str(_values.get(slot, ""))


## Задать значение слота. false — слот неизвестен или значение недопустимо (не меняется).
func set_value(slot: String, value: Variant) -> bool:
	if not is_valid_value(slot, value):
		return false
	_values[slot] = value
	return true


## Все значения: слот → строка.
func values() -> Dictionary:
	return _values.duplicate()


## Слоты, сброшенные к умолчанию при последнем `from_dict` (неверное значение).
func reset_slots() -> Array[String]:
	return _reset_slots.duplicate()


func equals(other: RiderLook) -> bool:
	if other == null:
		return false
	for slot in SLOTS:
		if get_value(slot) != other.get_value(slot):
			return false
	return true


func duplicate_look() -> RiderLook:
	return RiderLook.from_dict(to_dict())


# ---------------------------------------------------------------------------
# Цвета (для применения к модели, T-109)
# ---------------------------------------------------------------------------

## sRGB цвета формы по ключу (неизвестный — цвет по умолчанию `white`).
static func form_color(key: String) -> Color:
	return FORM_COLORS.get(key, FORM_COLORS["white"])


## Ключ цвета для региона узора джерси 3–7 (`index` 0..4: бока, полоса, плечи, манжеты, воротник).
func jersey_region_color_key(index: int) -> String:
	var sources: Array = PATTERN_SOURCES.get(get_value(JERSEY_PATTERN), PATTERN_SOURCES["side_panels"])
	match str(sources[clampi(index, 0, sources.size() - 1)]):
		"a1":
			return get_value(JERSEY_ACCENT1)
		"a2":
			return get_value(JERSEY_ACCENT2)
	return get_value(JERSEY_MAIN)


# ---------------------------------------------------------------------------
# Сериализация
# ---------------------------------------------------------------------------

## Словарь «слот → строка» и `version` = 1.
func to_dict() -> Dictionary:
	var out: Dictionary = {VERSION_KEY: FORMAT_VERSION}
	for slot in SLOTS:
		out[slot] = get_value(slot)
	return out


## Чтение из словаря (в т.ч. из JSON). Не словарь или null — внешность по умолчанию;
## неверный слот — по умолчанию только он (`reset_slots`); отсутствующий — по умолчанию.
static func from_dict(data: Variant) -> RiderLook:
	var look := RiderLook.new()
	if not (data is Dictionary):
		return look
	var source: Dictionary = data
	for slot in SLOTS:
		if not source.has(slot):
			continue
		var value: Variant = source[slot]
		if is_valid_value(slot, value):
			look._values[slot] = value
		else:
			look._reset_slots.append(slot)
	return look
