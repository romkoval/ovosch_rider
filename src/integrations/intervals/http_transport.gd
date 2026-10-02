class_name HttpTransport
extends RefCounted
## Интерфейс HTTP-транспорта (T-032, основа REQ-NFR-03 крит. 1, 2).
##
## Все сетевые вызовы приложения идут через `request()`; реализации:
## - `GodotHttpTransport` — реальная, на `HTTPRequest` (единственное место
##   сетевого ввода-вывода в `src/`);
## - `MockHttpTransport` — для тестов: заготовленные ответы, журнал запросов,
##   режим «нет сети».
##
## `request()` асинхронный: вызывать через `await`. Реализация никогда не
## бросает — любая проблема возвращается как `HttpResponse` с `error`.

const DEFAULT_TIMEOUT_SEC: float = 15.0


## Выполнить запрос. `headers` — словарь имя → значение; `body` — байты (пустой для GET).
func request(_method: String, _url: String, _headers: Dictionary,
		_body: PackedByteArray = PackedByteArray(), _timeout_sec: float = DEFAULT_TIMEOUT_SEC) -> HttpResponse:
	push_error("HttpTransport.request: not implemented")
	return HttpResponse.failure(HttpResponse.ERR_NETWORK)


## Собрать URL: `base` + `path` + закодированные параметры запроса (ключи в порядке словаря).
static func build_url(base: String, path: String, query: Dictionary = {}) -> String:
	var url := base.rstrip("/") + "/" + path.lstrip("/")
	if query.is_empty():
		return url
	var parts: Array[String] = []
	for k in query.keys():
		parts.append("%s=%s" % [str(k).uri_encode(), str(query[k]).uri_encode()])
	return url + "?" + "&".join(parts)
