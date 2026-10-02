class_name GodotHttpTransport
extends HttpTransport
## Реальный транспорт на `HTTPRequest` (T-032). Единственное место сетевого
## ввода-вывода в `src/`.
##
## `HTTPRequest` — узел, поэтому транспорту нужен `host` в дереве сцены (его даёт
## владелец — оболочка приложения). На каждый запрос создаётся свой узел, после
## ответа он освобождается; параллельные запросы допустимы.

const METHODS: Dictionary = {
	"GET": HTTPClient.METHOD_GET,
	"POST": HTTPClient.METHOD_POST,
	"PUT": HTTPClient.METHOD_PUT,
	"DELETE": HTTPClient.METHOD_DELETE,
	"PATCH": HTTPClient.METHOD_PATCH,
	"HEAD": HTTPClient.METHOD_HEAD,
}

var _host: Node


func _init(host: Node) -> void:
	_host = host


func request(method: String, url: String, headers: Dictionary,
		body: PackedByteArray = PackedByteArray(), timeout_sec: float = DEFAULT_TIMEOUT_SEC) -> HttpResponse:
	if _host == null or not is_instance_valid(_host) or not _host.is_inside_tree():
		return HttpResponse.failure(HttpResponse.ERR_NETWORK)
	var m := method.to_upper()
	if not METHODS.has(m):
		return HttpResponse.failure(HttpResponse.ERR_NETWORK)
	var http := HTTPRequest.new()
	http.timeout = timeout_sec
	http.accept_gzip = true
	_host.add_child(http)
	var header_lines := PackedStringArray()
	for k in headers.keys():
		header_lines.append("%s: %s" % [str(k), str(headers[k])])
	var err := http.request_raw(url, header_lines, METHODS[m] as HTTPClient.Method, body)
	if err != OK:
		http.queue_free()
		return HttpResponse.failure(HttpResponse.ERR_NETWORK)
	var completed: Array = await http.request_completed
	http.queue_free()
	var result: int = completed[0]
	var code: int = completed[1]
	var raw_headers: PackedStringArray = completed[2]
	var bytes: PackedByteArray = completed[3]
	if result == HTTPRequest.RESULT_TIMEOUT:
		return HttpResponse.failure(HttpResponse.ERR_TIMEOUT)
	if result != HTTPRequest.RESULT_SUCCESS:
		return HttpResponse.failure(HttpResponse.ERR_NETWORK)
	var response := HttpResponse.new()
	response.status = code
	response.body = bytes
	response.headers = HttpResponse.normalize_headers(raw_headers)
	return response
