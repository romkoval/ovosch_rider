class_name SettingsSections
extends RefCounted
## Разделы экрана настроек и их тексты (`docs/game/ui.md` п. 8.6; REQ-UIX-04 крит. 3).
##
## Порядок разделов задан требованием: «Профиль», «Тренировка», «Зоны», «Интеграции»,
## «Интерфейс», «О программе». У каждого раздела — id, ключ заголовка, иконка Lucide для
## навигации (regular) и путь узла раздела в сцене экрана.
##
## Здесь же — тексты экрана, которые появились в T-086 (ключи в `strings_menu.csv`): путь
## узла → ключ. Прежние тексты экрана (ключи `strings.csv`) остаются в
## `SettingsScreen.STATIC_TEXTS`. Оба словаря применяются экраном одинаково — `tr()` при
## каждой перерисовке, поэтому язык меняется без перезапуска (REQ-NFR-08 крит. 4).

const PROFILE: String = "profile"
const TRAINING: String = "training"
const ZONES: String = "zones"
const INTEGRATIONS: String = "integrations"
const INTERFACE: String = "interface"
const ABOUT: String = "about"

## Корень содержимого прокрутки в сцене экрана.
const CONTENT: String = "Root/Margin/Body/Scroll/Content/"

## Разделы по порядку: id, ключ заголовка, иконка навигации, узел раздела.
const ORDER: Array[Dictionary] = [
	{"id": PROFILE, "title": "ui.settings.section.profile", "icon": "user", "node": CONTENT + "ProfileSection"},
	{"id": TRAINING, "title": "ui.settings.section.training", "icon": "bike", "node": CONTENT + "TrainingSection"},
	{"id": ZONES, "title": "ui.settings.section.zones", "icon": "gauge", "node": CONTENT + "ZonesSection"},
	{"id": INTEGRATIONS, "title": "ui.settings.section.integrations", "icon": "refresh-cw", "node": CONTENT + "IntegrationsSection"},
	{"id": INTERFACE, "title": "ui.settings.section.interface", "icon": "settings", "node": CONTENT + "InterfaceSection"},
	{"id": ABOUT, "title": "ui.settings.about_title", "icon": "info", "node": CONTENT + "AboutSection"},
]

## Тексты T-086: путь узла относительно экрана → ключ перевода.
const TEXTS: Dictionary = {
	CONTENT + "ProfileSection/Title": "ui.settings.section.profile",
	CONTENT + "TrainingSection/Title": "ui.settings.section.training",
	CONTENT + "ZonesSection/Title": "ui.settings.section.zones",
	CONTENT + "IntegrationsSection/Title": "ui.settings.section.integrations",
	CONTENT + "InterfaceSection/Title": "ui.settings.section.interface",
	CONTENT + "TrainingSection/Card/Rows/ResistanceRow/Texts/Hint": "ui.settings.resistance_hint",
	CONTENT + "TrainingSection/Card/Rows/IntensityRow/Texts/Label": "ui.settings.intensity",
	CONTENT + "TrainingSection/Card/Rows/IntensityRow/Texts/Hint": "ui.settings.intensity_hint",
	CONTENT + "TrainingSection/Card/Rows/SteepnessRow/Texts/Label": "ui.settings.steepness",
	CONTENT + "TrainingSection/Card/Rows/SteepnessRow/Texts/Hint": "ui.settings.steepness_hint",
	CONTENT + "ZonesSection/Card/Rows/SourcesRow/Label": "ui.settings.sources_title",
	CONTENT + "AboutSection/Card/Rows/VersionRow/Label": "ui.settings.version_title",
	CONTENT + "AboutSection/Card/Rows/LicensesRow/Texts/Label": "ui.settings.licenses_row",
	CONTENT + "AboutSection/Card/Rows/LicensesRow/Texts/Hint": "ui.settings.licenses_hint",
	CONTENT + "AboutSection/Card/Rows/LicensesRow/LicensesButton": "ui.settings.licenses_open",
	CONTENT + "AboutSection/Card/Rows/PrivacyRow/Texts/Label": "ui.settings.privacy_title",
}

## Строки «О программе» о шрифте и иконках (лицензии файлов `assets/fonts/inter/OFL.txt`
## и `assets/icons/lucide/LICENSE`).
const LICENSE_INTER: String = "ui.settings.license_inter"
const LICENSE_LUCIDE: String = "ui.settings.license_lucide"
## Подпись под строкой политики конфиденциальности: «Документ: {path}».
const PRIVACY_DOC: String = "ui.settings.privacy_doc"
## Единицы (общие ключи меню).
const UNIT_PCT: String = "ui.menu.unit.pct"
const UNIT_W: String = "ui.menu.unit.w"
## Заголовок листа лицензий.
const LICENSES_TITLE: String = "ui.settings.licenses_row"


## id разделов по порядку.
static func ids() -> Array[String]:
	var out: Array[String] = []
	for section in ORDER:
		out.append(str(section["id"]))
	return out


## Описание раздела по id ({} — нет такого).
static func find(id: String) -> Dictionary:
	for section in ORDER:
		if section["id"] == id:
			return section
	return {}
