class_name RiderRegions
extends RefCounted
## Регионы цвета гонщика с велосипедом (REQ-D3D-09 п.6, REQ-AVT-02; арт-библия «Гонщик» →
## «Слоты внешности», бриф художнику раздел 10): код региона в UV0 — U = колонка атласа
## 0–31, V — тон. Таблица регионов, веса контура и палитра пресета `classic` (внешность по
## умолчанию) — источник для атласов пакета художнику (`scripts/dev/rider_artist_kit.gd`),
## тун-материала гонщика (T-106a3) и тестов.

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

## Палитра формы (sRGB), арт-библия «Палитра формы».
const FORM := {
	"white": Color(0.95, 0.95, 0.96), "cream": Color(0.93, 0.89, 0.78),
	"red": Color(0.86, 0.14, 0.16), "orange": Color(0.96, 0.50, 0.12),
	"yellow": Color(0.98, 0.82, 0.18), "lime": Color(0.62, 0.82, 0.20),
	"green": Color(0.12, 0.55, 0.32), "graphite": Color(0.20, 0.21, 0.24),
	"teal": Color(0.10, 0.62, 0.66), "sky": Color(0.36, 0.68, 0.92),
	"blue": Color(0.18, 0.28, 0.72), "navy": Color(0.16, 0.18, 0.44),
	"purple": Color(0.48, 0.26, 0.66), "pink": Color(0.94, 0.46, 0.66),
	"grey": Color(0.62, 0.64, 0.68), "black": Color(0.09, 0.09, 0.10),
}

## Пресет `classic` (внешность по умолчанию): цвет каждого региона, sRGB. Узор джерси
## `side_panels` (main white, accent1 red, accent2 blue): 3 — a1, 4, 5 — main, 6, 7 — a2.
## Фиксированные цвета — из таблицы регионов. Линза `smoke`: основной тон, блик — отдельно.
const CLASSIC: Array = [
	Color(0.87, 0.64, 0.50),  # 0 skin s3
	Color(0.24, 0.16, 0.11),  # 1 hair dark_brown
	Color(0.95, 0.95, 0.96),  # 2 jersey_main white
	Color(0.86, 0.14, 0.16),  # 3 jersey_side = accent1 red
	Color(0.95, 0.95, 0.96),  # 4 jersey_band = main
	Color(0.95, 0.95, 0.96),  # 5 jersey_yoke = main
	Color(0.18, 0.28, 0.72),  # 6 jersey_cuff = accent2 blue
	Color(0.18, 0.28, 0.72),  # 7 jersey_collar = accent2 blue
	Color(0.16, 0.18, 0.44),  # 8 shorts_main navy
	Color(0.09, 0.09, 0.10),  # 9 shorts_gripper black
	Color(0.95, 0.95, 0.96),  # 10 socks_main white
	Color(0.95, 0.95, 0.96),  # 11 socks_cuff white
	Color(0.95, 0.95, 0.96),  # 12 shoe_main white
	Color(0.09, 0.09, 0.10),  # 13 shoe_accent black
	Color(0.14, 0.14, 0.16),  # 14 shoe_sole (фикс.)
	Color(0.82, 0.18, 0.16),  # 15 cleat (фикс.)
	Color(0.95, 0.95, 0.96),  # 16 helmet_main white
	Color(0.09, 0.09, 0.10),  # 17 helmet_accent black
	Color(0.12, 0.12, 0.14),  # 18 helmet_inner (фикс.)
	Color(0.18, 0.19, 0.22),  # 19 lens smoke
	Color(0.09, 0.09, 0.10),  # 20 glasses_frame black
	Color(0.09, 0.09, 0.10),  # 21 glove black
	Color(0.22, 0.22, 0.24),  # 22 glove_palm (фикс.)
	Color(0.86, 0.14, 0.16),  # 23 frame_main red
	Color(0.98, 0.82, 0.18),  # 24 frame_accent yellow
	Color(0.98, 0.82, 0.18),  # 25 rim_decal yellow
	Color(0.09, 0.09, 0.10),  # 26 bar_tape black
	Color(0.10, 0.10, 0.11),  # 27 tire (фикс.)
	Color(0.13, 0.13, 0.15),  # 28 rim_carbon (фикс.)
	Color(0.70, 0.71, 0.74),  # 29 metal (фикс.)
	Color(0.09, 0.09, 0.10),  # 30 component (фикс.)
	Color(0.18, 0.28, 0.72),  # 31 bottle = jersey.accent2 blue
]
## Блик линзы `smoke` (V ≥ 0.75 в регионе 19).
const CLASSIC_LENS_HIGHLIGHT := Color(0.42, 0.44, 0.50)


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


## Цвет пикселя атласа-превью: цвет региона `classic` × тон (в линейном пространстве, как
## множитель в шейдере), обратно в sRGB; у линзы при V ≥ 0.75 — цвет блика.
static func preview_color(code: int, v: float) -> Color:
	var base: Color = CLASSIC[code]
	if code == LENS and v >= LENS_HIGHLIGHT_V:
		base = CLASSIC_LENS_HIGHLIGHT
	var lin: Color = base.srgb_to_linear() * tone(v)
	return Color(minf(lin.r, 1.0), minf(lin.g, 1.0), minf(lin.b, 1.0)).linear_to_srgb()


## 32 различимых оттенка атласа-проверки: шаг по тону — золотое сечение (соседние колонки
## далеко по кругу), яркость и насыщенность чередуются.
static func id_color(code: int) -> Color:
	var h: float = fposmod(float(code) * 0.618034, 1.0)
	var s: float = 0.85 if code % 2 == 0 else 0.6
	var v: float = 0.95 if (code >> 1) % 2 == 0 else 0.72
	return Color.from_hsv(h, s, v)


## Атлас-превью 1024 × 256: колонка k — цвет региона k внешности по умолчанию, по вертикали —
## тон от 0.6 (низ) до 1.4 (верх). Строка y (0 — верх изображения) ↔ V = 1 − (y + 0.5) / 256.
static func preview_atlas() -> Image:
	var img := Image.create_empty(ATLAS_SIZE.x, ATLAS_SIZE.y, false, Image.FORMAT_RGB8)
	for y in ATLAS_SIZE.y:
		var v: float = 1.0 - (float(y) + 0.5) / float(ATLAS_SIZE.y)
		for code in COUNT:
			var c: Color = preview_color(code, v)
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
