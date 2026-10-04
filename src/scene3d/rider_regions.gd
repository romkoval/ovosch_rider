class_name RiderRegions
extends RefCounted
## Регионы цвета гонщика с велосипедом (REQ-D3D-09 п.6, REQ-AVT-02; арт-библия «Гонщик» →
## «Слоты внешности», бриф художнику раздел 10): код региона в UV0 — U = колонка атласа
## 0–31, V — тон. Таблица регионов, веса контура, фиксированные цвета и связь «регион → слот
## `RiderLook`» — источник для атласов эталонного пакета (`scripts/dev/rider_reference_pack.gd`),
## тун-материала гонщика (T-106a3), применения внешности (T-109) и тестов. Цвета слотов —
## только в `RiderLook` (палитра формы, кожа, волосы, линзы).

const COUNT: int = 32
## Атлас для художника: 1024 × 256 px, 32 колонки по 32 px.
const ATLAS_SIZE := Vector2i(1024, 256)
const COLUMN_PX: int = 32
## Отступ острова UV от края колонки — доля её ширины (бриф 10, правило 1).
const MARGIN: float = 0.1
## Тон = TONE_MIN + TONE_SPAN · V (V — как в Blender: 0 внизу атласа, 1 вверху).
const TONE_MIN: float = 0.6
const TONE_SPAN: float = 0.8
## Регион линзы: V ≥ LENS_HIGHLIGHT_V — цвет блика (правило шейдера для региона 19).
const LENS: int = 19
const LENS_HIGHLIGHT_V: float = 0.75
## Первый регион велосипеда: 23–31 художник не использует.
const FIRST_BIKE: int = 23

## [имя, вес контура] по кодам 0–31.
const REGIONS: Array = [
	["skin", 1.0], ["hair", 1.0], ["jersey_main", 1.0], ["jersey_side", 1.0],
	["jersey_band", 1.0], ["jersey_yoke", 1.0], ["jersey_cuff", 1.0], ["jersey_collar", 1.0],
	["shorts_main", 1.0], ["shorts_gripper", 1.0], ["socks_main", 1.0], ["socks_cuff", 1.0],
	["shoe_main", 1.0], ["shoe_accent", 1.0], ["shoe_sole", 1.0], ["cleat", 1.0],
	["helmet_main", 1.0], ["helmet_accent", 1.0], ["helmet_inner", 0.0], ["lens", 0.0],
	["glasses_frame", 0.0], ["glove", 1.0], ["glove_palm", 1.0], ["frame_main", 1.0],
	["frame_accent", 1.0], ["rim_decal", 0.0], ["bar_tape", 1.0], ["tire", 1.0],
	["rim_carbon", 0.0], ["metal", 0.0], ["component", 1.0], ["bottle", 1.0],
]

## Фиксированные цвета регионов (sRGB), таблица регионов спеки: слотом не меняются.
## Ладонь перчатки (22) при `gloves.model` = `none` — цвет кожи.
const FIXED: Dictionary = {
	14: Color(0.14, 0.14, 0.16), 15: Color(0.82, 0.18, 0.16), 18: Color(0.12, 0.12, 0.14),
	22: Color(0.22, 0.22, 0.24), 27: Color(0.10, 0.10, 0.11), 28: Color(0.13, 0.13, 0.15),
	29: Color(0.70, 0.71, 0.74), 30: Color(0.09, 0.09, 0.10),
}
## Регион → слот цвета формы `RiderLook` (столбец «Слот» таблицы регионов). Узор джерси
## (3–7), кожа, волосы, линза и перчатки — отдельно в `palette()`.
const FORM_SLOTS: Dictionary = {
	2: RiderLook.JERSEY_MAIN, 8: RiderLook.SHORTS_MAIN, 9: RiderLook.SHORTS_GRIPPER,
	10: RiderLook.SOCKS_MAIN, 11: RiderLook.SOCKS_CUFF, 12: RiderLook.SHOES_MAIN,
	13: RiderLook.SHOES_ACCENT, 16: RiderLook.HELMET_MAIN, 17: RiderLook.HELMET_ACCENT,
	20: RiderLook.GLASSES_FRAME, 23: RiderLook.BIKE_FRAME, 24: RiderLook.BIKE_ACCENT,
	25: RiderLook.BIKE_RIM_DECAL, 26: RiderLook.BIKE_BAR_TAPE, 31: RiderLook.JERSEY_ACCENT2,
}
## id-атлас: шаг тона между соседними колонками (17/32 оборота — все 32 тона разные, соседи
## далеко по кругу), насыщенность и яркость чередуются. Подобрано на максимум наименьшего
## ΔE76 между любыми двумя колонками (≈ 20) при ΔE соседей ≥ 60.
const ID_HUE_STEP: float = 17.0 / 32.0


## Цвета 32 регионов внешности `look` (sRGB): слоты по таблице регионов, узор джерси — по
## схеме `RiderLook.PATTERN_SOURCES`, фиксированные — `FIXED`. Линза — основной тон (блик —
## `lens_highlight`). Источник атласа-превью; T-109 пишет те же цвета в палитру материала.
static func palette(look: RiderLook) -> Array[Color]:
	var out: Array[Color] = []
	out.resize(COUNT)
	var skin: Color = RiderLook.SKIN_TONES[look.get_value(RiderLook.SKIN_TONE)]
	var no_gloves: bool = look.get_value(RiderLook.GLOVES_MODEL) == "none"
	for code in COUNT:
		if FIXED.has(code):
			out[code] = FIXED[code]
		elif FORM_SLOTS.has(code):
			out[code] = RiderLook.form_color(look.get_value(FORM_SLOTS[code]))
	out[0] = skin
	out[1] = RiderLook.HAIR_COLORS[look.get_value(RiderLook.HAIR_COLOR)]
	for i in 5:
		out[3 + i] = RiderLook.form_color(look.jersey_region_color_key(i))
	out[LENS] = (RiderLook.LENSES[look.get_value(RiderLook.GLASSES_LENS)] as Array)[0]
	out[21] = skin if no_gloves else RiderLook.form_color(look.get_value(RiderLook.GLOVES_COLOR))
	if no_gloves:
		out[22] = skin
	return out


## Цвет блика линзы внешности `look` (V ≥ `LENS_HIGHLIGHT_V` в регионе 19), sRGB.
static func lens_highlight(look: RiderLook) -> Color:
	return (RiderLook.LENSES[look.get_value(RiderLook.GLASSES_LENS)] as Array)[1]


## Внешность атласа-превью — пресет `classic` (внешность по умолчанию).
static func preview_look() -> RiderLook:
	return RiderLook.preset(RiderLook.PRESET_CLASSIC)


static func region_name(code: int) -> String:
	return REGIONS[code][0]


static func outline_weight(code: int) -> float:
	return REGIONS[code][1]


## Тон по V (Blender: 0 — низ атласа).
static func tone(v: float) -> float:
	return TONE_MIN + TONE_SPAN * v


## Допустимый диапазон U острова региона `code` (с отступом 10 %).
static func u_range(code: int) -> Vector2:
	return Vector2((float(code) + MARGIN) / float(COUNT), (float(code) + 1.0 - MARGIN) / float(COUNT))


## Цвет пикселя атласа-превью: цвет региона из `colors` × тон (в линейном пространстве, как
## множитель в шейдере), обратно в sRGB; у линзы при V ≥ 0.75 — цвет блика `highlight`.
static func preview_color(colors: Array[Color], highlight: Color, code: int, v: float) -> Color:
	var base: Color = colors[code]
	if code == LENS and v >= LENS_HIGHLIGHT_V:
		base = highlight
	var lin: Color = base.srgb_to_linear() * tone(v)
	return Color(minf(lin.r, 1.0), minf(lin.g, 1.0), minf(lin.b, 1.0)).linear_to_srgb()


## 32 различимых оттенка атласа-проверки: тон k · 17/32 оборота, у нечётных колонок яркость
## ниже, у пар 2–3, 6–7, … — насыщенность ниже (`ID_HUE_STEP`).
static func id_color(code: int) -> Color:
	var h: float = fposmod(float(code) * ID_HUE_STEP, 1.0)
	var s: float = 0.95 if (code >> 1) % 2 == 0 else 0.45
	var v: float = 1.0 if code % 2 == 0 else 0.7
	return Color.from_hsv(h, s, v)


## Атлас-превью 1024 × 256: колонка k — цвет региона k внешности `look` (по умолчанию —
## `classic`), по вертикали — тон от 0.6 (низ) до 1.4 (верх). Строка y (0 — верх
## изображения) ↔ V = 1 − (y + 0.5) / 256.
static func preview_atlas(look: RiderLook = null) -> Image:
	if look == null:
		look = preview_look()
	var colors: Array[Color] = palette(look)
	var highlight: Color = lens_highlight(look)
	var img := Image.create_empty(ATLAS_SIZE.x, ATLAS_SIZE.y, false, Image.FORMAT_RGB8)
	for y in ATLAS_SIZE.y:
		var v: float = 1.0 - (float(y) + 0.5) / float(ATLAS_SIZE.y)
		for code in COUNT:
			var c: Color = preview_color(colors, highlight, code, v)
			img.fill_rect(Rect2i(code * COLUMN_PX, y, COLUMN_PX, 1), c)
	return img


## Атлас-проверка 1024 × 256: колонка k — свой оттенок `id_color(k)`, тёмная линия по
## границам колонок, номер колонки цифрами 3 раза по высоте; у 23–31 (велосипед) — ещё
## тёмный крест в середине.
static func id_atlas() -> Image:
	var img := Image.create_empty(ATLAS_SIZE.x, ATLAS_SIZE.y, false, Image.FORMAT_RGB8)
	for code in COUNT:
		var x0: int = code * COLUMN_PX
		var c: Color = id_color(code)
		img.fill_rect(Rect2i(x0, 0, COLUMN_PX, ATLAS_SIZE.y), c)
		img.fill_rect(Rect2i(x0, 0, 1, ATLAS_SIZE.y), Color(0.05, 0.05, 0.05))
		var ink: Color = Color.BLACK if c.get_luminance() > 0.5 else Color.WHITE
		for row in [16, 112, 208]:
			_draw_number(img, code, x0 + (COLUMN_PX >> 1), row, ink)
		if code >= FIRST_BIKE:
			for i in 20:
				img.set_pixel(x0 + 6 + i, 70 + i, ink)
				img.set_pixel(x0 + 25 - i, 70 + i, ink)
				img.set_pixel(x0 + 6 + i, 166 + i, ink)
				img.set_pixel(x0 + 25 - i, 166 + i, ink)
	return img


## Цифры 3 × 5, масштаб 3 (9 × 15 px), по центру `cx`, верх — `top`.
const _DIGITS: Array = [
	["111", "101", "101", "101", "111"], ["010", "110", "010", "010", "111"],
	["111", "001", "111", "100", "111"], ["111", "001", "111", "001", "111"],
	["101", "101", "111", "001", "001"], ["111", "100", "111", "001", "111"],
	["111", "100", "111", "101", "111"], ["111", "001", "010", "010", "010"],
	["111", "101", "111", "101", "111"], ["111", "101", "111", "001", "111"],
]


static func _draw_number(img: Image, n: int, cx: int, top: int, ink: Color) -> void:
	var text: String = str(n)
	var scale: int = 3
	var w: int = text.length() * 3 * scale + (text.length() - 1) * scale
	var x: int = cx - (w >> 1)
	for ch in text:
		var glyph: Array = _DIGITS[int(ch)]
		for gy in 5:
			for gx in 3:
				if (glyph[gy] as String)[gx] == "1":
					img.fill_rect(Rect2i(x + gx * scale, top + gy * scale, scale, scale), ink)
		x += 4 * scale
