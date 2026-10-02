extends GutTest
## Тесты HttpResponse, HttpTransport, MockHttpTransport, GodotHttpTransport
## (T-032; основа REQ-NFR-03 крит. 1, 2; REQ-INT-07 крит. 4 — мок считает запросы).


func test_response_make_lowercases_headers_and_ok() -> void:
	var r := HttpResponse.make(200, "hello", {"Content-Type": "text/plain", "Retry-After": "5"})
	assert_true(r.ok())
	assert_false(r.is_transport_error())
	assert_eq(r.body_text(), "hello")
	assert_eq(r.header("content-type"), "text/plain")
	assert_eq(r.header("RETRY-AFTER"), "5", "имена заголовков без учёта регистра")
	assert_eq(r.header("missing", "d"), "d")
	assert_false(HttpResponse.make(404).ok())
	assert_false(HttpResponse.make(500).ok())


func test_json_response_and_json_parsing() -> void:
	var r := HttpResponse.json_response(200, {"a": 1, "b": [1, 2]})
	assert_eq(r.header("content-type"), "application/json")
	var data: Variant = r.json()
	assert_true(data is Dictionary)
	assert_eq(int(data["a"]), 1)
	assert_null(HttpResponse.make(200, "not json").json())
	assert_null(HttpResponse.make(204, "").json())


func test_failure_response_flags() -> void:
	var r := HttpResponse.failure(HttpResponse.ERR_TIMEOUT)
	assert_true(r.is_transport_error())
	assert_false(r.ok())
	assert_eq(r.error, "timeout")
	assert_eq(HttpResponse.failure("").error, HttpResponse.ERR_NETWORK, "пустой код → network")


func test_normalize_headers_from_lines() -> void:
	var h := HttpResponse.normalize_headers(PackedStringArray(["Content-Type: application/json", "X-Rate: 10", "garbage"]))
	assert_eq(h.size(), 2)
	assert_eq(str(h["content-type"]), "application/json")
	assert_eq(str(h["x-rate"]), "10")


func test_build_url_encodes_query() -> void:
	var url := HttpTransport.build_url("https://intervals.icu/", "/api/v1/athlete/i1/events", {"oldest": "2026-10-02", "category": "WORKOUT,NOTE"})
	assert_eq(url, "https://intervals.icu/api/v1/athlete/i1/events?oldest=2026-10-02&category=WORKOUT%2CNOTE")
	assert_eq(HttpTransport.build_url("https://x.test", "api/a"), "https://x.test/api/a")


func test_mock_offline_records_request_and_returns_offline_error() -> void:
	var m := MockHttpTransport.new()
	m.offline = true
	var r: HttpResponse = await m.request("GET", "https://x.test/a", {"A": "1"})
	assert_true(r.is_transport_error())
	assert_eq(r.error, HttpResponse.ERR_OFFLINE)
	assert_eq(m.request_count(), 1, "REQ-NFR-03 крит. 2: попытка учтена")
	assert_eq(str(m.last_request()["url"]), "https://x.test/a")
	assert_eq(str(m.last_request()["headers"]["A"]), "1")


func test_mock_queue_is_fifo_and_default_404() -> void:
	var m := MockHttpTransport.new()
	m.enqueue_json("GET", "/athlete/", 200, {"n": 1}).enqueue_json("GET", "/athlete/", 500, {})
	var a: HttpResponse = await m.request("GET", "https://x.test/api/athlete/i1", {})
	var b: HttpResponse = await m.request("GET", "https://x.test/api/athlete/i1", {})
	var c: HttpResponse = await m.request("GET", "https://x.test/api/athlete/i1", {})
	assert_eq(a.status, 200)
	assert_eq(b.status, 500)
	assert_eq(c.status, 404, "очередь пуста → ответ по умолчанию")
	assert_eq(m.pending_count(), 0)
	assert_eq(m.request_count("GET", "/athlete/"), 3)


func test_mock_sticky_rule_pattern_and_method_filter() -> void:
	var m := MockHttpTransport.new()
	m.enqueue("GET", "*events*", HttpResponse.make(503), -1)
	m.enqueue_failure("POST", "/upload", HttpResponse.ERR_NETWORK)
	for i in 3:
		var r: HttpResponse = await m.request("GET", "https://x.test/events?oldest=1", {})
		assert_eq(r.status, 503, "правило с repeat=-1 действует всегда")
	var post: HttpResponse = await m.request("POST", "https://x.test/upload", {}, "x".to_utf8_buffer())
	assert_eq(post.error, HttpResponse.ERR_NETWORK)
	var get_upload: HttpResponse = await m.request("GET", "https://x.test/upload", {})
	assert_eq(get_upload.status, 404, "метод не совпал — правило не применяется")
	assert_eq(m.request_count("POST"), 1)
	m.clear()
	assert_eq(m.request_count(), 0)
	assert_eq(m.pending_count(), 0)


func test_godot_transport_without_host_returns_network_error() -> void:
	var t := GodotHttpTransport.new(null)
	var r: HttpResponse = await t.request("GET", "http://127.0.0.1:9/", {})
	assert_true(r.is_transport_error())
	var detached := Node.new()
	var t2 := GodotHttpTransport.new(detached)
	var r2: HttpResponse = await t2.request("GET", "http://127.0.0.1:9/", {})
	assert_true(r2.is_transport_error(), "хост вне дерева — ошибка транспорта, не падение")
	detached.free()


func test_godot_transport_unreachable_host_is_transport_error() -> void:
	var host := Node.new()
	add_child_autofree(host)
	var t := GodotHttpTransport.new(host)
	var r: HttpResponse = await t.request("GET", "http://127.0.0.1:9/nothing", {"Accept": "application/json"}, PackedByteArray(), 3.0)
	assert_true(r.is_transport_error(), "недоступный хост → транспортная ошибка: %s" % str(r))
	assert_false(r.ok())
	await get_tree().process_frame
	assert_eq(host.get_child_count(), 0, "узел HTTPRequest освобождён после ответа")
