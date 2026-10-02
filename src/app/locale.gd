class_name AppLocale
extends RefCounted
## Определение языка интерфейса (REQ-NFR-08 крит. 3): язык системы, если он ru или en,
## иначе en. Единственное место в `src/app/`, где вызывается `OS.*`
## (`OS.get_locale_language()` — не ветвление по платформе; файл внесён в список
## исключений REQ-NFR-06 крит. 1). Чистая функция `pick()` тестируется отдельно.

const SUPPORTED_LOCALES: Array[String] = ["en", "ru"]
const FALLBACK_LOCALE: String = "en"


## Язык интерфейса для текущей системы.
static func detect() -> String:
	return pick(OS.get_locale_language())


## Язык интерфейса по коду языка системы (`"ru"`, `"ru_RU"`, `"en_US"`, `"de"` → `"en"`).
static func pick(system_language: String) -> String:
	var lang: String = system_language.to_lower().substr(0, 2)
	return lang if SUPPORTED_LOCALES.has(lang) else FALLBACK_LOCALE
