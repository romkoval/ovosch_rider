class_name MockHttpTransport
extends HttpTransport
## Мок HTTP-транспорта для тестов (T-032; REQ-INT-01 крит. 1, REQ-INT-02 крит. 4, 5,
## REQ-INT-07 крит. 4, REQ-NFR-03 крит. 1, 2).
##
## - `enqueue(method, url_pattern, response, repeat)` — очередь ответов для запросов,
##   чей URL содержит `url_pattern` (или совпадает с ним как glob `*`/`?`); `method`
##   `"*"` — любой. Ответы выдаются по одному; `repeat = -1` — бесконечно.
## - `offline = true` — каждый запрос получает транспортную ошибку `offline`
##   (запрос при этом записывается в журнал — так считаются «попытки»).
## - `requests` — журнал `{method, url, headers, body, timeout_sec, seq}`.
## - Без совпадений — `default_response` (по умолчанию 404).
## Задержек нет: мок отвечает синхронно, `await` на нём возвращается сразу.

var offline: bool = false
var requests: Array[Dictionary] = []
var default_response: HttpResponse = HttpResponse.make(404, "")

var _rules: Array[Dictionary] = []


func enqueue(method: String, url_pattern: String, response: HttpResponse, repeat: int = 1) -> MockHttpTransport:
	_rules.append({"method": method.to_upper(), "pattern": url_pattern, "response": response, "left": repeat})
	return self


func enqueue_json(method: String, url_pattern: String, status: int, data: Variant,
		headers: Dictionary = {}, repeat: int = 1) -> MockHttpTransport:
	return enqueue(method, url_pattern, HttpResponse.json_response(status, data, headers), repeat)


func enqueue_failure(method: String, url_pattern: String, error_code: String, repeat: int = 1) -> MockHttpTransport:
	return enqueue(method, url_pattern, HttpResponse.failure(error_code), repeat)


func request(method: String, url: String, headers: Dictionary,
		body: PackedByteArray = PackedByteArray(), timeout_sec: float = DEFAULT_TIMEOUT_SEC) -> HttpResponse:
	requests.append({
		"method": method.to_upper(),
		"url": url,
		"headers": headers.duplicate(),
		"body": body,
		"timeout_sec": timeout_sec,
		"seq": requests.size(),
	})
	if offline:
		return HttpResponse.failure(HttpResponse.ERR_OFFLINE)
	for i in _rules.size():
		var rule: Dictionary = _rules[i]
		if rule["method"] != "*" and rule["method"] != method.to_upper():
			continue
		if not _matches(url, str(rule["pattern"])):
			continue
		var left := int(rule["left"])
		if left == 1:
			_rules.remove_at(i)
		elif left > 1:
			rule["left"] = left - 1
		return rule["response"]
	return default_response


func request_count(method: String = "", url_pattern: String = "") -> int:
	var n := 0
	for r in requests:
		if not method.is_empty() and r["method"] != method.to_upper():
			continue
		if not url_pattern.is_empty() and not _matches(str(r["url"]), url_pattern):
			continue
		n += 1
	return n


func last_request() -> Dictionary:
	return requests[requests.size() - 1] if not requests.is_empty() else {}


## Сбросить журнал и очередь.
func clear() -> void:
	requests = []
	_rules = []


## Остались ли невыданные заготовленные ответы.
func pending_count() -> int:
	return _rules.size()


static func _matches(url: String, pattern: String) -> bool:
	return pattern.is_empty() or url.contains(pattern) or url.match(pattern)
