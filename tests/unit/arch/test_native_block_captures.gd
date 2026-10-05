extends GutTest
## Нативный мост CoreBluetooth не передаёт в блоки dispatch_async ссылки на строки (REQ-DEV-02, REQ-DEV-03).
## Блок Objective-C++ захватывает параметр `const std::string &` как ссылку; к моменту выполнения
## блока строка вызывающей стороны уже разрушена. Так id в discover_services/subscribe/read/write
## приходил пустым: «CoreBluetooth: peripheral not found: » сразу после connected, ни станок, ни датчики
## не подключались (журнал владельца 2026-10-05). Правило: в методе с dispatch_async строковые
## параметры называются `*_arg` и копируются в локальные `const std::string` до блока.

const BACKEND: String = "res://native/ble/src/platform/apple/apple_backend.mm"


## Методы AppleBackend с dispatch_async, у которых в блок может попасть ссылка на строку.
static func offenders(text: String) -> Array[String]:
	var fn_re := RegEx.create_from_string(r'(?m)^void AppleBackend::(\w+)\(([^)]*)\) \{')
	var out: Array[String] = []
	var matches := fn_re.search_all(text)
	for i in matches.size():
		var m: RegExMatch = matches[i]
		var end: int = matches[i + 1].get_start() if i + 1 < matches.size() else text.length()
		var body: String = text.substr(m.get_end(), end - m.get_end())
		if not body.contains("dispatch_async"):
			continue
		var param_re := RegEx.create_from_string(r'const std::string &(\w+)')
		for p in param_re.search_all(m.get_string(2)):
			var name: String = p.get_string(1)
			if not name.ends_with("_arg"):
				out.append("%s(%s)" % [m.get_string(1), name])
			elif not body.contains("const std::string %s = %s;" % [name.trim_suffix("_arg"), name]):
				out.append("%s(%s): нет локальной копии" % [m.get_string(1), name])
	return out


func test_no_string_references_captured_by_dispatch_async_blocks() -> void:
	var text := FileAccess.get_file_as_string(BACKEND)
	assert_true(text.contains("dispatch_async"), "бэкенд прочитан")
	assert_eq(offenders(text), [] as Array[String], "строковый параметр по ссылке попадает в блок dispatch_async")


func test_detector_catches_reference_capture() -> void:
	var bad := "void AppleBackend::discover_services(const std::string &id) {\n\tdispatch_async(q, ^{ use(id); });\n}\n"
	var good := "void AppleBackend::discover_services(const std::string &id_arg) {\n\tconst std::string id = id_arg;\n\tdispatch_async(q, ^{ use(id); });\n}\n"
	assert_eq(offenders(bad).size(), 1)
	assert_eq(offenders(good).size(), 0)
