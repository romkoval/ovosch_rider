class_name HttpResponse
extends RefCounted
## Ответ HTTP-транспорта (REQ-NFR-03 — основа, T-032).
##
## `error` пуст при полученном ответе (любой статус, включая 4xx/5xx) и содержит
## код транспортной ошибки, когда ответа нет: `network` (нет соединения, DNS,
## TLS), `timeout`, `offline` (мок в режиме «нет сети»). Имена заголовков — в
## нижнем регистре.

const ERR_NONE: String = ""
const ERR_NETWORK: String = "network"
const ERR_TIMEOUT: String = "timeout"
const ERR_OFFLINE: String = "offline"

var status: int = 0
var headers: Dictionary = {}
var body: PackedByteArray = PackedByteArray()
var error: String = ERR_NONE


static func make(status_code: int, body_text: String = "", response_headers: Dictionary = {}) -> HttpResponse:
	var r := HttpResponse.new()
	r.status = status_code
	r.body = body_text.to_utf8_buffer()
	for k in response_headers.keys():
		r.headers[str(k).to_lower()] = str(response_headers[k])
	return r


## Ответ с JSON-телом (заголовок `content-type` выставляется).
static func json_response(status_code: int, data: Variant, response_headers: Dictionary = {}) -> HttpResponse:
	var r := make(status_code, JSON.stringify(data), response_headers)
	if not r.headers.has("content-type"):
		r.headers["content-type"] = "application/json"
	return r


## Транспортная ошибка без ответа сервера.
static func failure(error_code: String, status_code: int = 0) -> HttpResponse:
	var r := HttpResponse.new()
	r.error = error_code if not error_code.is_empty() else ERR_NETWORK
	r.status = status_code
	return r


## Заголовки вида `"Name: value"` → словарь с именами в нижнем регистре.
static func normalize_headers(raw: PackedStringArray) -> Dictionary:
	var out := {}
	for line in raw:
		var idx := line.find(":")
		if idx <= 0:
			continue
		out[line.substr(0, idx).strip_edges().to_lower()] = line.substr(idx + 1).strip_edges()
	return out


## Ответ получен и статус 2xx.
func ok() -> bool:
	return error.is_empty() and status >= 200 and status < 300


## Ответа нет (сеть, таймаут, offline).
func is_transport_error() -> bool:
	return not error.is_empty()


func body_text() -> String:
	return body.get_string_from_utf8()


## Разобранный JSON тела или null, если тело не JSON.
func json() -> Variant:
	var text := body_text()
	if text.strip_edges().is_empty():
		return null
	var parser := JSON.new()
	if parser.parse(text) != OK:
		return null
	return parser.data


func header(name: String, default: String = "") -> String:
	return str(headers.get(name.to_lower(), default))


func _to_string() -> String:
	if is_transport_error():
		return "HttpResponse(error=%s)" % error
	return "HttpResponse(%d, %d bytes)" % [status, body.size()]
