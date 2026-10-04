class_name SecureStoreFilter
extends RefCounted
## Фильтр секретов диагностического журнала (T-116a; REQ-NFR-05 п.1, 2): ни токен, ни ключ
## API, ни код OAuth не попадают в файл журнала, даже если вызывающий передал их по ошибке.
## Часть модуля защищённого хранилища (`src/storage/secure_store*`): только он знает имена и
## значения секретов (NFR-05 п.1); журнал получает от него лишь маскирование.
##
## Три линии защиты, все применяются к каждой записи:
## 1. Известные значения: всё, что лежит в подключённом `SecureStore` (`set_store`), и значения,
##    добавленные явно (`add_secret`, например код OAuth до обмена на токен), заменяются на
##    `MASK`, где бы ни встретились — в тексте, в значении поля, внутри URL. Значения короче
##    `MIN_SECRET_LENGTH` не считаются секретами (иначе маскировались бы числа и слова),
##    срок действия токена (`expires_at`) — тоже.
## 2. Шаблоны: заголовок `Authorization: …` (любая схема), `Bearer …`, параметры
##    `code=`, `access_token=`, `refresh_token=`, `client_secret=`, `api_key=` в URL и тексте.
## 3. Имена полей: значение поля словаря с «секретным» именем (`SENSITIVE_KEYS`, без учёта
##    регистра) заменяется целиком, какого бы типа оно ни было.
##
## Хранилище читается при каждой фильтрации (значений несколько, они в памяти), поэтому ключ,
## привязанный после открытия журнала, маскируется сразу.

const MASK: String = "***"
const MIN_SECRET_LENGTH: int = 6
## Имена полей, значения которых не пишутся никогда (сравнение без учёта регистра).
const SENSITIVE_KEYS: Array[String] = [
	"authorization", "access_token", "refresh_token", "client_secret", "api_key", "apikey",
	"password", "secret", "token", "oauth_code", "auth_code", "bearer",
]
## Пункты хранилища, которые секретом не являются (срок действия токена — число).
const NON_SECRET_ITEMS: Array[String] = [SecureStore.ITEM_EXPIRES_AT]

var _store: SecureStore = null
var _extra: Dictionary = {}
var _patterns: Array[RegEx] = []


func _init() -> void:
	# Порядок важен: сначала заголовок целиком, затем схемы и параметры.
	for source: String in [
		"(?i)(authorization\\s*[:=]\\s*)[^\\r\\n,;\"'}]+",
		"(?i)(\\bbearer\\s+)[A-Za-z0-9._~+/=-]+",
		"(?i)((?:^|[?&\\s\"'])code=)[^&\\s\"'#]+",
		"(?i)((?:access_token|refresh_token|client_secret|api_key|apikey|password)\"?\\s*[:=]\\s*\"?)[^&\\s\"',}]+",
	]:
		var re := RegEx.new()
		re.compile(source)
		_patterns.append(re)


## Подключить хранилище секретов: его значения маскируются (null — отключить).
func set_store(store: SecureStore) -> void:
	_store = store


## Явно добавить секрет (например, код OAuth до обмена): маскируется до `forget_secret`.
func add_secret(value: String) -> void:
	if value.length() >= MIN_SECRET_LENGTH:
		_extra[value] = true


func forget_secret(value: String) -> void:
	_extra.erase(value)


## Известные значения секретов (хранилище + явно добавленные), длинные первыми — чтобы
## секрет, содержащий другой секрет, маскировался целиком.
func known_secrets() -> Array[String]:
	var out: Array[String] = []
	for value: String in _extra.keys():
		out.append(value)
	if _store != null:
		for key in _store.list_keys():
			if NON_SECRET_ITEMS.has(key.get_file()):
				continue
			var value := _store.get_secret(key)
			if value.length() >= MIN_SECRET_LENGTH and not out.has(value):
				out.append(value)
	out.sort_custom(func(a: String, b: String) -> bool: return a.length() > b.length())
	return out


## Текст без секретов.
func redact(text: String) -> String:
	return _redact_text(text, known_secrets())


## Значение без секретов: строки фильтруются, словари и массивы — рекурсивно, значения
## полей с секретными именами заменяются на `MASK`. Исходное значение не меняется.
func redact_value(value: Variant) -> Variant:
	return _redact_value(value, known_secrets())


static func is_sensitive_key(key: String) -> bool:
	var lower := key.to_lower()
	for name in SENSITIVE_KEYS:
		if lower == name or lower.ends_with("_" + name) or lower.ends_with("." + name):
			return true
	return false


func _redact_value(value: Variant, secrets: Array[String]) -> Variant:
	match typeof(value):
		TYPE_STRING, TYPE_STRING_NAME:
			return _redact_text(str(value), secrets)
		TYPE_DICTIONARY:
			var out: Dictionary = {}
			var source: Dictionary = value
			for k: Variant in source.keys():
				var key := _redact_text(str(k), secrets)
				out[key] = MASK if is_sensitive_key(str(k)) else _redact_value(source[k], secrets)
			return out
		TYPE_ARRAY:
			var out_arr: Array = []
			for item: Variant in value:
				out_arr.append(_redact_value(item, secrets))
			return out_arr
		TYPE_PACKED_STRING_ARRAY:
			var out_psa := PackedStringArray()
			for item: String in value:
				out_psa.append(_redact_text(item, secrets))
			return out_psa
	return value


func _redact_text(text: String, secrets: Array[String]) -> String:
	if text.is_empty():
		return text
	var out := text
	for secret in secrets:
		out = out.replace(secret, MASK)
	for re in _patterns:
		out = re.sub(out, "$1" + MASK, true)
	return out
