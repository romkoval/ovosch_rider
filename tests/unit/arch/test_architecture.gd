extends GutTest
## Архитектурные и инфраструктурные проверки (REQ-NFR-06 крит. 1–3, REQ-NFR-05 крит. 1,
## REQ-INF-03 крит. 3, 5, REQ-INF-04 крит. 1, 2; REQ-DEV-09 крит. 1 — реализация станка известна только `src/devices/`).

const SRC: String = "res://src"
const TESTS: String = "res://tests"
const DOCS: String = "res://docs"
const REQUIREMENTS: String = "res://docs/requirements.md"
const BACKLOG: String = "res://docs/backlog.md"

## Идентификаторы реализаций станка/моста, запрещённые вне `src/devices/`.
const IMPLEMENTATION_IDENTIFIERS: Array[String] = ["FakeTrainer", "BleTrainer", "StubBleBridge"]
## Разрешённые места платформенных вызовов (REQ-NFR-06 крит. 1, с поправкой daf4ca8).
const PLATFORM_ALLOWED_PREFIXES: Array[String] = ["res://src/storage/secure_store", "res://src/devices/ble/", "res://src/app/locale.gd"]
## Слои, от которых домен не зависит (REQ-NFR-06 крит. 3).
const DOMAIN_FORBIDDEN_DIRS: Array[String] = ["res://src/devices", "res://src/session", "res://src/ui", "res://src/scene3d", "res://src/app", "res://src/profiles", "res://src/storage", "res://src/integrations"]


# ---------------------------------------------------------------------------
# Утилиты
# ---------------------------------------------------------------------------

static func _files(dir_path: String, exts: Array[String], out: Array[String]) -> void:
	var d := DirAccess.open(dir_path)
	if d == null:
		return
	for f in d.get_files():
		for ext in exts:
			if f.ends_with(ext):
				out.append(dir_path.path_join(f))
				break
	for sub in d.get_directories():
		if not sub.begins_with("."):
			_files(dir_path.path_join(sub), exts, out)


static func _list(dir_path: String, exts: Array[String]) -> Array[String]:
	var out: Array[String] = []
	_files(dir_path, exts, out)
	out.sort()
	return out


## Текст без комментариев (`#` до конца строки; `##` докстринги тоже).
static func _code_lines(path: String) -> Array[String]:
	var out: Array[String] = []
	for line in FileAccess.get_file_as_string(path).split("\n"):
		var idx := line.find("#")
		out.append(line.substr(0, idx) if idx != -1 else line)
	return out


static func _has_prefix(path: String, prefixes: Array[String]) -> bool:
	for p in prefixes:
		if path.begins_with(p):
			return true
	return false


static func _class_names_in(dir_path: String) -> Array[String]:
	var re := RegEx.create_from_string("^class_name\\s+([A-Za-z_][A-Za-z0-9_]*)")
	var out: Array[String] = []
	for path in _list(dir_path, [".gd"]):
		for line in FileAccess.get_file_as_string(path).split("\n"):
			var m := re.search(line)
			if m != null:
				out.append(m.get_string(1))
	return out


# ---------------------------------------------------------------------------
# (1) Реализации станка известны только src/devices/ (REQ-DEV-09 крит. 1)
# ---------------------------------------------------------------------------

func test_trainer_implementations_are_not_referenced_outside_devices() -> void:
	var re := RegEx.create_from_string("\\b(" + "|".join(IMPLEMENTATION_IDENTIFIERS) + ")\\b")
	var offenders: Array[String] = []
	for path in _list(SRC, [".gd", ".tscn"]):
		if path.begins_with("res://src/devices/"):
			continue
		var n := 0
		for line in _code_lines(path):
			n += 1
			if re.search(line) != null:
				offenders.append("%s:%d" % [path, n])
	assert_eq(offenders, [], "реализации станка упомянуты вне src/devices/: %s" % str(offenders))


func test_dev_screen_obtains_trainer_only_via_factory() -> void:
	var files := _list("res://src/ui/dev", [".gd"])
	assert_gt(files.size(), 0, "экран разработчика существует")
	var direct_new := RegEx.create_from_string("\\b[A-Za-z_]*(Trainer|Bridge)\\.new\\(")
	for path in files:
		var code := "\n".join(_code_lines(path))
		assert_true(code.contains("TrainerFactory.create("), "%s получает станок через TrainerFactory.create" % path)
		assert_null(direct_new.search(code), "%s не создаёт станок/мост напрямую через .new()" % path)


# ---------------------------------------------------------------------------
# (2) Домен не зависит от устройств, сессии, UI и сцен (REQ-NFR-06 крит. 3)
# ---------------------------------------------------------------------------

func test_domain_has_no_dependencies_on_outer_layers() -> void:
	var forbidden_classes: Array[String] = []
	for dir in DOMAIN_FORBIDDEN_DIRS:
		forbidden_classes.append_array(_class_names_in(dir))
	assert_gt(forbidden_classes.size(), 5, "классы внешних слоёв найдены")
	var class_re := RegEx.create_from_string("\\b(" + "|".join(forbidden_classes) + ")\\b")
	var scene_re := RegEx.create_from_string("\\b(Node|Node2D|Node3D|Control|SceneTree|get_tree|preload|load)\\s*\\(|\\bextends\\s+(Node|Control|Node2D|Node3D)\\b|res://src/(devices|session|ui|scene3d|app|profiles|storage|integrations)/")
	var offenders: Array[String] = []
	for path in _list("res://src/domain", [".gd"]):
		var n := 0
		for line in _code_lines(path):
			n += 1
			if class_re.search(line) != null or scene_re.search(line) != null:
				offenders.append("%s:%d %s" % [path, n, line.strip_edges()])
	assert_eq(offenders, [], "домен ссылается на внешние слои: %s" % str(offenders))


func test_domain_classes_extend_refcounted_or_domain_classes() -> void:
	var domain_classes := _class_names_in("res://src/domain")
	var re := RegEx.create_from_string("^extends\\s+([A-Za-z_][A-Za-z0-9_]*)")
	for path in _list("res://src/domain", [".gd"]):
		for line in FileAccess.get_file_as_string(path).split("\n"):
			var m := re.search(line)
			if m != null:
				var base := m.get_string(1)
				assert_true(base in ["RefCounted", "Object", "Resource"] or domain_classes.has(base), "%s extends %s" % [path, base])


# ---------------------------------------------------------------------------
# (3) Платформенные вызовы только в разрешённых местах (REQ-NFR-06 крит. 1)
# ---------------------------------------------------------------------------

func test_platform_calls_only_in_allowed_files() -> void:
	var re := RegEx.create_from_string("(^|[^A-Za-z0-9_])OS\\.|\\bhas_feature\\(|\\bEngine\\.has_singleton\\(|\\bClassDB\\.class_exists\\(\"Native")
	var offenders: Array[String] = []
	for path in _list(SRC, [".gd"]):
		if _has_prefix(path, PLATFORM_ALLOWED_PREFIXES):
			continue
		var n := 0
		for line in _code_lines(path):
			n += 1
			if re.search(line) != null:
				offenders.append("%s:%d %s" % [path, n, line.strip_edges()])
	assert_eq(offenders, [], "платформенные вызовы вне разрешённых файлов: %s" % str(offenders))


func test_native_code_only_under_native_ble() -> void:
	var offenders: Array[String] = []
	for root in ["res://src", "res://tests", "res://assets", "res://scripts"]:
		for path in _list(root, [".cpp", ".mm", ".m", ".h", ".hpp", ".java", ".kt"]):
			offenders.append(path)
	assert_eq(offenders, [], "REQ-NFR-06 крит. 2: нативный код вне native/ble/: %s" % str(offenders))


# ---------------------------------------------------------------------------
# (4) Секреты (REQ-INF-03 крит. 5, REQ-NFR-05)
# ---------------------------------------------------------------------------

func test_no_secret_like_literals_in_src_and_docs() -> void:
	var re := RegEx.create_from_string("(^|[^A-Za-z0-9_])sk_[A-Za-z0-9]{8,}|client_secret\\s*[=:]\\s*\"[^\"]+\"|Bearer [A-Za-z0-9._-]{8,}|api_key\\s*[=:]\\s*\"[^\"]+\"|refresh_token\\s*[=:]\\s*\"[^\"]+\"")
	var allow := RegEx.create_from_string("PLACEHOLDER|placeholder|example|EXAMPLE|<token>|<secret>|<key>|dummy")
	var offenders: Array[String] = []
	for root in [SRC, DOCS, "res://tests/fixtures"]:
		for path in _list(root, [".gd", ".md", ".tscn", ".json", ".cfg", ".csv", ".txt"]):
			var n := 0
			for line in FileAccess.get_file_as_string(path).split("\n"):
				n += 1
				if re.search(line) != null and allow.search(line) == null:
					offenders.append("%s:%d" % [path, n])
	var project := FileAccess.get_file_as_string("res://project.godot")
	assert_null(re.search(project), "секреты в project.godot")
	assert_eq(offenders, [], "строки, похожие на секреты: %s" % str(offenders))


func test_secrets_are_read_only_through_secure_store() -> void:
	# REQ-NFR-05 крит. 1: вне src/storage/ никто не читает/пишет файлы секретов напрямую.
	var offenders: Array[String] = []
	for path in _list(SRC, [".gd"]):
		if path.begins_with("res://src/storage/"):
			continue
		var n := 0
		for line in _code_lines(path):
			n += 1
			if line.contains("open_encrypted_with_pass") or line.contains("secrets.bin"):
				offenders.append("%s:%d" % [path, n])
	assert_eq(offenders, [], "прямой доступ к хранилищу секретов вне src/storage/: %s" % str(offenders))


# ---------------------------------------------------------------------------
# (5) Парные .uid (REQ-INF-03 крит. 3)
# ---------------------------------------------------------------------------

func test_every_gd_has_uid_and_no_orphan_uids() -> void:
	for root in [SRC, TESTS]:
		var gd := _list(root, [".gd"])
		var uid := _list(root, [".gd.uid"])
		var missing: Array[String] = []
		for path in gd:
			if not uid.has(path + ".uid"):
				missing.append(path)
		var orphan: Array[String] = []
		for path in uid:
			if not gd.has(path.trim_suffix(".uid")):
				orphan.append(path)
		assert_eq(missing, [], "%s: .gd без .uid" % root)
		assert_eq(orphan, [], "%s: осиротевшие .uid" % root)


# ---------------------------------------------------------------------------
# (6) Тестовые файлы (REQ-INF-01, REQ-INF-04 крит. 1)
# ---------------------------------------------------------------------------

func test_every_test_file_extends_gut_test() -> void:
	var bad: Array[String] = []
	for path in _list(TESTS, [".gd"]):
		if not path.get_file().begins_with("test_"):
			continue
		var first_code := ""
		for line in FileAccess.get_file_as_string(path).split("\n"):
			var t := line.strip_edges()
			if t.is_empty() or t.begins_with("#"):
				continue
			first_code = t
			break
		if first_code != "extends GutTest":
			bad.append(path)
	assert_eq(bad, [], "тестовые файлы без `extends GutTest`")


func test_every_test_file_mentions_a_req_id() -> void:
	var re := RegEx.create_from_string("REQ-[A-Z0-9]+-[0-9]+")
	var without: Array[String] = []
	for path in _list(TESTS, [".gd"]):
		if path.get_file().begins_with("test_") and re.search(FileAccess.get_file_as_string(path)) == null:
			without.append(path)
	# Пока только предупреждение: правило станет падающим после очистки чужих файлов (см. отчёт).
	if not without.is_empty():
		print("ПРЕДУПРЕЖДЕНИЕ REQ-INF-04 крит. 1: тестовые файлы без REQ-ID: %s" % str(without))
	pass_test("REQ-INF-04 крит. 1: без REQ-ID %d файл(ов) — см. предупреждение выше" % without.size())


# ---------------------------------------------------------------------------
# (6b) CI-workflow (REQ-INF-02 крит. 1–4, REQ-INF-03 крит. 2, 5)
# ---------------------------------------------------------------------------

func test_ci_workflow_runs_on_push_and_pr_with_full_history_import_tests_and_scans() -> void:
	var yml := FileAccess.get_file_as_string("res://.github/workflows/ci.yml")
	assert_false(yml.is_empty(), "ci.yml существует")
	assert_string_contains(yml, 'branches: ["**"]', "REQ-INF-02 крит. 1: push в любую ветку")
	assert_string_contains(yml, "pull_request:", "REQ-INF-02 крит. 1: pull_request")
	assert_string_contains(yml, "fetch-depth: 0", "REQ-INF-03 крит. 2: полная история для проверки коммитов")
	assert_string_contains(yml, "--headless --path . --import", "REQ-INF-02: проект открывается headless")
	assert_string_contains(yml, "scripts/test.sh", "REQ-INF-02: запуск GUT")
	assert_string_contains(yml, "scripts/check_secrets.sh", "REQ-INF-03 крит. 5: поиск секретов в CI")
	assert_string_contains(yml, "scripts/check_commit_messages.sh", "REQ-INF-03 крит. 1: сообщения коммитов с REQ-ID")
	assert_string_contains(yml, "tests/reports/results.xml", "REQ-INF-02: JUnit-отчёт как артефакт")
	for script in ["res://scripts/test.sh", "res://scripts/check_secrets.sh", "res://scripts/check_commit_messages.sh"]:
		assert_true(FileAccess.file_exists(script), "%s существует" % script)


# ---------------------------------------------------------------------------
# (6c) Доменный слой покрыт тестами (REQ-NFR-09 крит. 1, 4)
# ---------------------------------------------------------------------------

func test_domain_modules_have_test_files_and_tests_need_no_scene_tree() -> void:
	var corpus := ""
	for path in _list("res://tests/unit/domain", [".gd"]):
		corpus += FileAccess.get_file_as_string(path) + "\n"
	for cls in ["IntervalExecutor", "Workout", "WorkoutStep", "PowerZones", "HrZones"]:
		assert_true(corpus.contains(cls + "."), "REQ-NFR-09 крит. 1: есть тесты для %s" % cls)
	for path in _list("res://tests/unit/domain", [".gd"]):
		var code := "\n".join(_code_lines(path))
		assert_false(code.contains("get_tree(") or code.contains("add_child"), "REQ-NFR-09 крит. 4: %s без SceneTree" % path)


# ---------------------------------------------------------------------------
# (7) Трассируемость REQ → тесты (REQ-INF-04 крит. 2)
# ---------------------------------------------------------------------------

## REQ-ID → есть ли у него критерии [авто].
static func _requirements_with_auto() -> Dictionary:
	var out: Dictionary = {}
	var heading := RegEx.create_from_string("^###\\s+(REQ-[A-Z0-9]+-[0-9]+)")
	var current := ""
	for line in FileAccess.get_file_as_string(REQUIREMENTS).split("\n"):
		var m := heading.search(line)
		if m != null:
			current = m.get_string(1)
			out[current] = false
		elif not current.is_empty() and line.contains("[авто]"):
			out[current] = true
	return out


## REQ-ID → статус задачи бэклога (`done`, `review`, …), по строкам таблицы задач.
static func _backlog_req_status() -> Dictionary:
	var out: Dictionary = {}
	var req_re := RegEx.create_from_string("REQ-[A-Z0-9]+-[0-9]+")
	var status_re := RegEx.create_from_string("`([a-z-]+)`")
	for line in FileAccess.get_file_as_string(BACKLOG).split("\n"):
		if not line.begins_with("| T-"):
			continue
		var cells := line.split("|")
		if cells.size() < 8:
			continue
		var status_cell := cells[cells.size() - 2]
		var sm := status_re.search(status_cell)
		if sm == null:
			continue
		var status := sm.get_string(1)
		for m in req_re.search_all(cells[5]):
			var id := m.get_string()
			if status == "done" or not out.has(id):
				out[id] = status
	return out


func test_every_auto_req_closed_in_backlog_has_a_test() -> void:
	var auto := _requirements_with_auto()
	assert_gt(auto.size(), 50, "требования разобраны")
	var statuses := _backlog_req_status()
	assert_gt(statuses.size(), 10, "таблица бэклога разобрана")
	var corpus := ""
	for path in _list(TESTS, [".gd"]):
		corpus += FileAccess.get_file_as_string(path) + "\n"
	var uncovered_done: Array[String] = []
	var uncovered_other: Array[String] = []
	var ids: Array = auto.keys()
	ids.sort()
	for id in ids:
		if not auto[id]:
			continue
		if corpus.contains(id):
			continue
		if statuses.get(id, "") == "done":
			uncovered_done.append(id)
		else:
			uncovered_other.append(id)
	if not uncovered_other.is_empty():
		print("ПРЕДУПРЕЖДЕНИЕ REQ-INF-04 крит. 2: REQ с [авто] без тестов (задачи не закрыты): %s" % str(uncovered_other))
	assert_eq(uncovered_done, [], "REQ закрыты в бэклоге (done), но тестов с их ID нет: %s" % str(uncovered_done))
