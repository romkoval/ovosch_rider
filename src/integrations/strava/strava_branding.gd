class_name StravaBranding
extends RefCounted
## Константы брендбука Strava для UI (REQ-STR-01 крит. 9 — вне контейнера; ТЗ:
## кнопка «Connect with Strava» и логотип «Powered by Strava»). Сами изображения
## добавляются в `assets/strava/` из официального набора Strava Brand Guidelines
## без изменений (T-049/T-053); здесь — пути, размеры и ключи переводов.

## Фирменный оранжевый Strava.
const BRAND_COLOR: Color = Color("#FC5200")
## Кнопка «Connect with Strava»: официальный ассет, высота 48 px, без перекраски и растяжения.
const CONNECT_BUTTON_ASSET: String = "res://assets/strava/btn_strava_connectwith_orange.svg"
const CONNECT_BUTTON_HEIGHT_PX: int = 48
const CONNECT_BUTTON_MIN_WIDTH_PX: int = 193
## Логотип «Powered by Strava» (горизонтальный, оранжевый) — обязателен на экранах с данными Strava.
const POWERED_BY_ASSET: String = "res://assets/strava/api_logo_pwrdBy_strava_horiz_orange.svg"
const POWERED_BY_HEIGHT_PX: int = 24
## Ключи переводов (таблица `assets/i18n/strings.csv`, T-054); в обеих локалях — текст брендбука.
const KEY_CONNECT_BUTTON: String = "ui.strava.connect"
const KEY_POWERED_BY: String = "ui.strava.powered_by"
## Английские тексты по брендбуку (переводить нельзя — названия продукта).
const TEXT_CONNECT_BUTTON: String = "Connect with Strava"
const TEXT_POWERED_BY: String = "Powered by Strava"
const TEXT_VIEW_ON_STRAVA: String = "View on Strava"
const GUIDELINES_URL: String = "https://developers.strava.com/guidelines/"
const ACTIVITY_URL_PREFIX: String = "https://www.strava.com/activities/"


## Ссылка на активность (REQ-STR-05 крит. 3).
static func activity_url(activity_id: String) -> String:
	return ACTIVITY_URL_PREFIX + activity_id.strip_edges()
