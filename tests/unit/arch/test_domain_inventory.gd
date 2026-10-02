extends GutTest
## Инвентаризация публичных методов доменного слоя (тестировщик, T-056).
## REQ-NFR-09 крит. 2 (способ «предложен, подтвердить» — реализован предложенный):
## для каждого `.gd` в `src/domain/` собираются публичные (`func name(`, имя без `_`
## в начале) и статические (`static func name(`) методы; каждый должен вызываться хотя
## бы в одном файле `tests/unit/domain/**` или `tests/unit/session/**` — по регэкспу
## `\.name\(` (вызов на экземпляре или классе) либо `ClassName.name(`. Непокрытые —
## падение с перечнем по файлам.
##
## Известное ограничение способа (зафиксировано, владельцу на подтверждение): регэксп
## `\.name\(` не различает класс получателя — для распространённых имён (`start`, `make`,
## `validate`, `tick`, `reset`, `step`, `zone_of`, …) вызов на объекте другого класса
## засчитывается как покрытие. Проверка даёт нижнюю оценку непокрытости (ложных
## «непокрыт» нет; ложные «покрыт» возможны). Строгий вариант на будущее: учитывать тип
## переменной-получателя по объявлению в тесте (`var x := ClassName.…` / `x: ClassName`)
## или требовать для «общих» имён вызов вида `ClassName.name(` / на переменной этого типа.
##
## REQ-INF-04 крит. 2 (каждый REQ закрытой `done`-задачи бэклога имеет тест) закрыт
## тестом `test_req_inf_04_c2_every_req_of_done_backlog_task_has_a_test_mentioning_it`
## в `tests/unit/arch/test_infra_acceptance.gd` — здесь не дублируется.

const DOMAIN_DIR: String = "res://src/domain"
const TEST_DIRS: Array[String] = ["res://tests/unit/domain", "res://tests/unit/session"]


static func _files(dir_path: String, ext: String, out: Array[String]) -> void:
	var d := DirAccess.open(dir_path)
	if d == null:
		return
	for f in d.get_files():
		if f.ends_with(ext):
			out.append(dir_path.path_join(f))
	for sub in d.get_directories():
		if not sub.begins_with("."):
			_files(dir_path.path_join(sub), ext, out)


static func _list(dir_path: String, ext: String) -> Array[String]:
	var out: Array[String] = []
	_files(dir_path, ext, out)
	out.sort()
	return out


## Код без комментариев (`#` до конца строки).
static func _code(path: String) -> String:
	var kept: Array[String] = []
	for line in FileAccess.get_file_as_string(path).split("\n"):
		var idx := line.find("#")
		kept.append(line.substr(0, idx) if idx != -1 else line)
	return "\n".join(kept)


## {class_name, methods: [{name, is_static, line}]} для файла домена.
static func _inventory_of(path: String) -> Dictionary:
	var cls := ""
	var methods: Array[Dictionary] = []
	var class_re := RegEx.create_from_string("^class_name\\s+([A-Za-z_][A-Za-z0-9_]*)")
	var func_re := RegEx.create_from_string("^(static\\s+)?func\\s+([A-Za-z][A-Za-z0-9_]*)\\s*\\(")
	var n := 0
	for line in FileAccess.get_file_as_string(path).split("\n"):
		n += 1
		var cm := class_re.search(line)
		if cm != null:
			cls = cm.get_string(1)
			continue
		var fm := func_re.search(line)
		if fm != null:
			methods.append({"name": fm.get_string(2), "is_static": not fm.get_string(1).is_empty(), "line": n})
	return {"class_name": cls, "methods": methods, "path": path}


## Весь код тестов домена и сессии одной строкой (без комментариев).
static func _test_corpus() -> String:
	var corpus := ""
	for dir in TEST_DIRS:
		for path in _list(dir, ".gd"):
			corpus += _code(path) + "\n"
	return corpus


static func _is_called(corpus: String, cls: String, method: String) -> bool:
	var dot_call := RegEx.create_from_string("\\." + method + "\\s*\\(")
	if dot_call.search(corpus) != null:
		return true
	if not cls.is_empty():
		var static_call := RegEx.create_from_string("\\b" + cls + "\\." + method + "\\s*\\(")
		if static_call.search(corpus) != null:
			return true
	return false


func test_req_nfr_09_c2_inventory_finds_domain_files_and_public_methods() -> void:
	var files := _list(DOMAIN_DIR, ".gd")
	assert_gte(files.size(), 9, "в src/domain/ ожидается не меньше 9 файлов: %s" % str(files))
	var total := 0
	for path in files:
		var inv := _inventory_of(path)
		assert_false(str(inv["class_name"]).is_empty(), "%s без class_name" % path)
		assert_gt((inv["methods"] as Array).size(), 0, "%s без публичных методов" % path)
		total += (inv["methods"] as Array).size()
	assert_gte(total, 60, "инвентарь публичных методов домена: %d" % total)


func test_req_nfr_09_c2_private_methods_and_init_are_excluded_from_inventory() -> void:
	for path in _list(DOMAIN_DIR, ".gd"):
		for m in _inventory_of(path)["methods"]:
			assert_false(str(m["name"]).begins_with("_"), "%s: %s не публичный" % [path, m["name"]])


func test_req_nfr_09_c2_every_public_domain_method_is_called_by_domain_or_session_tests() -> void:
	var corpus := _test_corpus()
	assert_gt(corpus.length(), 10000, "корпус тестов домена и сессии прочитан")
	var uncovered: Array[String] = []
	var covered := 0
	for path in _list(DOMAIN_DIR, ".gd"):
		var inv := _inventory_of(path)
		var missing: Array[String] = []
		for m in inv["methods"]:
			if _is_called(corpus, inv["class_name"], m["name"]):
				covered += 1
			else:
				missing.append("%s%s (строка %d)" % ["static " if m["is_static"] else "", m["name"], m["line"]])
		if not missing.is_empty():
			uncovered.append("%s [%s]: %s" % [path.get_file(), inv["class_name"], ", ".join(missing)])
	assert_gt(covered, 0)
	assert_eq(uncovered, [], "REQ-NFR-09 крит. 2 — публичные методы домена без единого вызова в тестах:\n  " + "\n  ".join(uncovered))


func test_req_nfr_09_c2_detection_sanity_known_called_and_known_absent() -> void:
	# Контроль метода: заведомо вызываемые и заведомо отсутствующие имена.
	var corpus := _test_corpus()
	assert_true(_is_called(corpus, "IntervalExecutor", "tick"), "IntervalExecutor.tick вызывается в тестах")
	assert_true(_is_called(corpus, "WorkoutStep", "percent"), "статический WorkoutStep.percent вызывается")
	assert_false(_is_called(corpus, "Nothing", "definitely_not_a_method_xyz"))
	assert_false(_is_called("var a := foo.barbaz(1)", "", "bar"), "совпадение по префиксу имени не считается вызовом")
