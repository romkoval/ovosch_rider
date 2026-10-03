class_name UiTokens
extends RefCounted
## Цветовые токены и размеры дизайн-системы (REQ-UIX-01 крит. 4, REQ-HUD-14 крит. 4).
##
## Источник значений — `docs/game/ui.md` п. 4 (палитра меню, только тёмная тема, акцент
## #2CC9B4 — решение владельца 2026-10-03) и `docs/game/hud.md` п. 5, 11 (токены HUD).
## Цвета стилей `app_theme.tres` берутся отсюда (`AppThemeBuilder`), тест сверяет их.
## Цвета зон мощности и пульса здесь не дублируются — они в `ZonePalette`.

# --- Меню (`ui.md` п. 4) ---------------------------------------------------------------
const BG: Color = Color("#0E1116")
const SURFACE1: Color = Color("#171B22")
const SURFACE2: Color = Color("#1F2530")
const SURFACE3: Color = Color("#29303D")
const INSET: Color = Color("#0B0E13")
const LINE: Color = Color("#2E3542")
const LINE_STRONG: Color = Color("#3A4352")
const TEXT: Color = Color("#F2F4F7")
const TEXT2: Color = Color("#A3ACBA")
const TEXT_DISABLED: Color = Color("#687180")
const ACCENT: Color = Color("#2CC9B4")
const ACCENT_PRESSED: Color = Color("#22A896")
const ON_ACCENT: Color = Color("#0B0E13")
const SIM: Color = Color("#F0B45A")
const WARN: Color = Color("#FFC24D")
const DANGER: Color = Color("#C23A36")
## Наведение и нажатие опасной кнопки (`ui.md` п. 4, 13): `danger` темнее на 8 % и 16 % —
## светлый текст на светлеющем красном терял бы контраст (≥ 4.5:1 с `text`).
const DANGER_HOVER: Color = Color("#B23532")
const DANGER_PRESSED: Color = Color("#A3312D")
const DANGER_TEXT: Color = Color("#FF6B6B")
const SCRIM: Color = Color(0.0, 0.0, 0.0, 0.55)
## Тень диалогов и всплывающих меню (`ui.md` п. 3): 24 lp, альфа 0.5, смещение (0, 8).
const SHADOW: Color = Color(0.0, 0.0, 0.0, 0.5)
const SHADOW_SIZE: int = 24
const SHADOW_OFFSET: Vector2 = Vector2(0, 8)
## Аватары профилей (`ui.md` п. 4): цвет выбирается по хэшу `id`.
const AVATAR_COLORS: Array[Color] = [
	Color("#6B8CD9"), Color("#C7779B"), Color("#5FAF9A"),
	Color("#C9A15A"), Color("#8C7BD1"), Color("#D98A6B"),
]
## Наведение основной кнопки: светлее акцента на 6 % (`ui.md` п. 9.2).
const ACCENT_HOVER_LIGHTEN: float = 0.06
## Альфа фона баннеров (`ui.md` п. 6).
const BANNER_ALPHA: float = 0.12
## Альфа рамки карточки при наведении (`ui.md` п. 9.2).
const CARD_HOVER_BORDER_ALPHA: float = 0.6
## Альфа выделения текста в полях (`ui.md` п. 9.1).
const SELECTION_ALPHA: float = 0.35
## Разрядка надзаголовка Overline (`ui.md` п. 5): +6 % кегля.
const OVERLINE_TRACKING: float = 0.06

# --- HUD (`hud.md` п. 11) ---------------------------------------------------------------
const HUD_INK: Color = Color("#0B0E13")
const HUD_PLATE_ALPHA: float = 0.78
const HUD_PLATE: Color = Color(HUD_INK, HUD_PLATE_ALPHA)
## Подложка карточки цели (`hud.md` п. 5, 11).
const HUD_CARD: Color = Color(HUD_INK, 0.55)
## Вуаль паузы (`hud.md` п. 10.2, 11).
const HUD_PAUSE_VEIL: Color = Color(HUD_INK, 0.35)
## Карточка паузы (`hud.md` п. 10.2): `surface1` (#171B22) с альфой 0.94, радиус 18·s.
const HUD_PAUSE_CARD_ALPHA: float = 0.94
const HUD_PAUSE_CARD: Color = Color(SURFACE1, HUD_PAUSE_CARD_ALPHA)
const HUD_PAUSE_CARD_RADIUS: int = 18
const HUD_TEXT: Color = Color("#F5F7FA")
const HUD_TEXT2: Color = Color("#B9C1CD")
const HUD_POWER_LINE: Color = Color("#F5F7FA")
const HUD_HR_LINE: Color = Color("#FF4757")
const HUD_HR_LABEL: Color = Color("#FF9AA2")
const HUD_WARN: Color = Color("#FFC24D")
const HUD_DEV_ON: Color = Color("#2CC9B4")
const HUD_DEV_BELOW: Color = Color("#8FC2FF")
const HUD_OK: Color = Color("#2CC9B4")
const HUD_ERR: Color = Color("#FF6B6B")
const HUD_FREE: Color = Color(0.62, 0.65, 0.72)
const HUD_FREE_HATCH: Color = Color(1.0, 1.0, 1.0, 0.18)

## Фишка зоны (`hud.md` п. 11): 32·s × 18·s, радиус 5·s, текст 12·s / 750 цветом `hud.ink`;
## «нет зоны» — без заливки, рамка 1·s и текст `hud.text2`. Размеры — в lp HUD (до `s`).
const HUD_ZONE_CHIP_SIZE: Vector2 = Vector2(32, 18)
const HUD_ZONE_CHIP_RADIUS: int = 5
const HUD_ZONE_CHIP_FONT_SIZE: int = 12
const HUD_ZONE_CHIP_TEXT: Color = HUD_INK
const HUD_ZONE_CHIP_EMPTY_BORDER: int = 1
const HUD_ZONE_CHIP_EMPTY_TEXT: Color = HUD_TEXT2

## Палитра уклона (`hud.md` п. 11): «труднее = теплее». Порог — нижняя граница диапазона
## в процентах; цвет действует от порога (включительно) до следующего порога.
const GRADE_THRESHOLDS: Array[float] = [-INF, -2.0, 2.0, 4.0, 7.0, 10.0]
const GRADE_COLORS: Array[Color] = [
	Color(0.52, 0.62, 0.74), # < -2 %: холодный сланец
	Color(0.60, 0.74, 0.52), # -2…2 %: шалфей
	Color(0.93, 0.80, 0.42), # 2…4 %: песок
	Color(0.93, 0.58, 0.30), # 4…7 %: терракота
	Color(0.84, 0.33, 0.28), # 7…10 %: кирпич
	Color(0.58, 0.20, 0.28), # ≥ 10 %: вино
]


## Цвет палитры уклона для уклона в процентах.
static func grade_color(grade_pct: float) -> Color:
	var idx := 0
	for i in GRADE_THRESHOLDS.size():
		if grade_pct >= GRADE_THRESHOLDS[i]:
			idx = i
	return GRADE_COLORS[idx]


## Цвет аватара профиля по его идентификатору (стабильный хэш строки).
static func avatar_color(profile_id: String) -> Color:
	return AVATAR_COLORS[absi(profile_id.hash()) % AVATAR_COLORS.size()]


## Относительная яркость sRGB-цвета по WCAG 2.x (альфа не учитывается).
static func relative_luminance(c: Color) -> float:
	return 0.2126 * _linear(c.r) + 0.7152 * _linear(c.g) + 0.0722 * _linear(c.b)


## Контраст двух непрозрачных цветов по WCAG 2.x (1…21).
static func contrast_ratio(a: Color, b: Color) -> float:
	var la := relative_luminance(a)
	var lb := relative_luminance(b)
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)


## Цвет `top` с его альфой поверх непрозрачного `bottom` (смешивание в sRGB).
static func blend_over(top: Color, bottom: Color) -> Color:
	return Color(bottom.lerp(Color(top, 1.0), top.a), 1.0)


static func _linear(v: float) -> float:
	return v / 12.92 if v <= 0.04045 else pow((v + 0.055) / 1.055, 2.4)
