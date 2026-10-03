class_name UiIcons
extends RefCounted
## Иконки Lucide по имени (`docs/game/ui.md` п. 7; файлы — `assets/icons/lucide/*.svg`,
## импорт `DPITexture` 24×24 lp, белый штрих: цвет задаётся модуляцией).
##
## `UiIcons.icon("bluetooth-off")` возвращает импортированную текстуру; загруженные
## текстуры кэшируются на время работы процесса (одна текстура на имя). Размер иконки
## задаёт узел (`TextureRect.expand_mode`, `Button.icon_max_width`), а не помощник.
## Метод называется `icon`, а не `get`: `Object.get` переопределить нельзя.

const DIR: String = "res://assets/icons/lucide/"
## Иконки баннера (`ui.md` п. 6) по виду: сведения, предупреждение, ошибка.
const BANNER_INFO: String = "info"
const BANNER_WARN: String = "triangle-alert"
const BANNER_ERROR: String = "circle-alert"

static var _cache: Dictionary[String, Texture2D] = {}


## Путь к файлу иконки `name` (имя файла без `.svg`).
static func path(name: String) -> String:
	return DIR + name + ".svg"


## Есть ли иконка `name` в наборе.
static func has(name: String) -> bool:
	return not name.is_empty() and ResourceLoader.exists(path(name))


## Текстура иконки `name`; пустое имя — `null`; нет файла — `null` и ошибка в журнал.
static func icon(name: String) -> Texture2D:
	if name.is_empty():
		return null
	var cached: Texture2D = _cache.get(name)
	if cached != null:
		return cached
	if not ResourceLoader.exists(path(name)):
		push_error("UiIcons: icon '%s' not found in %s" % [name, DIR])
		return null
	var tex := load(path(name)) as Texture2D
	if tex != null:
		_cache[name] = tex
	return tex


## Сбрасывает кэш (для тестов и горячей перезагрузки набора).
static func clear_cache() -> void:
	_cache.clear()
