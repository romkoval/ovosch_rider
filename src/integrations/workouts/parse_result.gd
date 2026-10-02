class_name ParseResult
extends RefCounted
## Результат разбора источника плана: ZWO, .erg/.mrc, Intervals.icu
## (REQ-IMP-01, REQ-IMP-02, REQ-INT-03, REQ-IMP-05).
##
## Инвариант: `workout` не null только если `errors` пуст — частично разобранный
## план никогда не возвращается как валидный (REQ-INT-03 крит. 9, REQ-IMP-05 крит. 2).
## Предупреждения (`warnings`) не блокируют импорт.
##
## Элемент `errors`/`warnings` — словарь `{line, column, element, message, key}`:
## - `line`, `column` — позиция в исходнике (1-based; 0 — не применимо);
## - `element` — имя элемента/поля/токена, к которому относится сообщение ("" — нет);
## - `message` — текст на русском, без стека вызовов и внутренних имён классов
##   (REQ-IMP-05 крит. 3);
## - `key` — стабильный код для локализации в UI (например `unknown_element`).

var workout: Workout = null
var errors: Array[Dictionary] = []
var warnings: Array[Dictionary] = []
## Метаданные источника, которым нет места в `Workout`: `author`, `sport_type`,
## `ftp`, `file_name`, `description` и т. п. (REQ-IMP-01 крит. 5, REQ-IMP-02 крит. 4).
var metadata: Dictionary = {}


## Разбор успешен: есть план и нет ошибок.
func ok() -> bool:
	return workout != null and errors.is_empty()


func add_error(message: String, line: int = 0, column: int = 0, element: String = "",
		key: String = "parse_error") -> void:
	errors.append(_entry(message, line, column, element, key))
	workout = null


func add_warning(message: String, line: int = 0, column: int = 0, element: String = "",
		key: String = "warning") -> void:
	warnings.append(_entry(message, line, column, element, key))


## Присвоить план; игнорируется, если уже есть ошибки (инвариант).
func set_workout(w: Workout) -> void:
	workout = w if errors.is_empty() else null


## Перенести ошибки и предупреждения из другого результата (вложенный разбор).
func merge_from(other: ParseResult) -> void:
	for e in other.errors:
		errors.append(e)
	for w in other.warnings:
		warnings.append(w)
	if not errors.is_empty():
		workout = null


## Тексты ошибок (только `message`).
func error_messages() -> Array[String]:
	var out: Array[String] = []
	for e in errors:
		out.append(str(e.get("message", "")))
	return out


func warning_messages() -> Array[String]:
	var out: Array[String] = []
	for w in warnings:
		out.append(str(w.get("message", "")))
	return out


## Сообщение для пользователя по одной записи (REQ-IMP-05 крит. 1):
## `<файл>: <сообщение> (элемент <имя>, строка N)`. Части, которых нет, опускаются.
static func format_entry(entry: Dictionary, file_name: String = "") -> String:
	var parts: Array[String] = []
	var element: String = str(entry.get("element", ""))
	var line: int = int(entry.get("line", 0))
	var column: int = int(entry.get("column", 0))
	var text: String = str(entry.get("message", ""))
	if not element.is_empty() and not text.contains(element):
		parts.append("элемент %s" % element)
	if line > 0:
		parts.append("строка %d" % line if column <= 0 else "строка %d, позиция %d" % [line, column])
	if not parts.is_empty():
		text += " (" + ", ".join(parts) + ")"
	if not file_name.is_empty():
		text = "%s: %s" % [file_name, text]
	return text


## Все ошибки одной строкой на пользователя (по одной на строку).
func user_message(file_name: String = "") -> String:
	var lines: Array[String] = []
	for e in errors:
		lines.append(format_entry(e, file_name))
	return "\n".join(lines)


static func _entry(message: String, line: int, column: int, element: String, key: String) -> Dictionary:
	return {
		"line": line,
		"column": column,
		"element": element,
		"message": message,
		"key": key,
	}


func _to_string() -> String:
	return "ParseResult(ok=%s, errors=%d, warnings=%d)" % [str(ok()), errors.size(), warnings.size()]
