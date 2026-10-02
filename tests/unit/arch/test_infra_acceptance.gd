extends GutTest
## Независимые приёмочные тесты инфраструктуры и архитектуры (тестировщик, T-014).
## Покрытие: REQ-INF-03 крит. 1, 2, 3, 5; REQ-INF-04 крит. 1, 2; REQ-NFR-06 крит. 1–3;
## REQ-NFR-05 крит. 1; REQ-NFR-09 крит. 1, 4.
##
## Скрипт `check_secrets.sh` проверяется на изолированной копии в собственном временном
## каталоге теста (скрипт делает `cd "$(dirname "$0")/.."`, поэтому сканирует только то,
## что мы туда положили) — репозиторий и параллельные прогоны не затрагиваются.
## Скрипт `check_commit_messages.sh` проверяется на реальной истории и на shallow-клоне
## во временном каталоге.

const SRC: String = "res://src"
const TESTS: String = "res://tests"
const REQUIREMENTS: String = "res://docs/requirements.md"
const BACKLOG: String = "res://docs/backlog.md"
const SECRETS_SCRIPT: String = "res://scripts/check_secrets.sh"
const COMMITS_SCRIPT: String = "res://scripts/check_commit_messages.sh"
## Коммиты из начала истории без REQ-ID и без префикса (для негативной проверки скрипта).
const EARLY_BAD_RANGE: String = "2851b8f~1..cfb072a"

var _dir: String


func before_each() -> void:
	_dir = "user://test_acc_infra_%d_%d/" % [Time.get_ticks_usec(), randi() % 1000000]


func after_each() -> void:
	var abs_dir := ProjectSettings.globalize_path(_dir)
	if DirAccess.dir_exists_absolute(abs_dir):
		OS.execute("rm", ["-rf", abs_dir])
	assert_false(DirAccess.dir_exists_absolute(abs_dir), "временный каталог удалён")


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


static func _code_lines(path: String) -> Array[String]:
	var out: Array[String] = []
	for line in FileAccess.get_file_as_string(path).split("\n"):
		var idx := line.find("#")
		out.append(line.substr(0, idx) if idx != -1 else line)
	return out


static func _class_names_in(dir_path: String) -> Array[String]:
	var re := RegEx.create_from_string("^class_name\\s+([A-Za-z_][A-Za-z0-9_]*)")
	var out: Array[String] = []
	for path in _list(dir_path, [".gd"]):
		for line in FileAccess.get_file_as_string(path).split("\n"):
			var m := re.search(line)
			if m != null:
				out.append(m.get_string(1))
	return out


func _write(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _has_tool(tool: String) -> bool:
	var out := []
	return OS.execute(tool, ["--version"], out) == 0


## Запустить bash-скрипт, вернуть {code, output}.
func _run(script_abs: String, args: Array[String]) -> Dictionary:
	var out := []
	var argv: Array = [script_abs]
	argv.append_array(args)
	var code := OS.execute("bash", argv, out, true)
	return {"code": code, "output": "\n".join(PackedStringArray(out))}


## Изолированная копия репозитория для check_secrets.sh: <root>/scripts/check_secrets.sh + файлы.
func _sandbox_with_secrets_script(files: Dictionary) -> String:
	var root := _dir + "sandbox/"
	_write(root + "scripts/check_secrets.sh", FileAccess.get_file_as_string(SECRETS_SCRIPT))
	_write(root + "project.godot", "[application]\nconfig/name=\"sandbox\"\n")
	_write(root + "src/clean.gd", "extends RefCounted\nvar ok := 1\n")
	for rel in files.keys():
		_write(root + rel, files[rel])
	return ProjectSettings.globalize_path(root + "scripts/check_secrets.sh")


# ===========================================================================
# REQ-INF-03 крит. 5 — поиск секретов (скрипт на изолированной копии)
# ===========================================================================

func test_req_inf_03_c5_secrets_script_passes_on_clean_tree_and_real_repo() -> void:
	if not _has_tool("bash"):
		pending("bash недоступен")
		return
	var clean := _run(_sandbox_with_secrets_script({}), [])
	assert_eq(clean["code"], 0, "чистое дерево → 0: %s" % clean["output"])
	assert_true(str(clean["output"]).contains("check_secrets: OK"))
	var real := _run(ProjectSettings.globalize_path(SECRETS_SCRIPT), [])
	assert_eq(real["code"], 0, "в репозитории секретов нет: %s" % real["output"])


func test_req_inf_03_c5_secrets_script_fails_on_client_secret_in_src() -> void:
	if not _has_tool("bash"):
		pending("bash недоступен")
		return
	var r := _run(_sandbox_with_secrets_script({"src/leak.gd": "extends RefCounted\nvar client_secret = \"abc12345\"\n"}), [])
	assert_eq(r["code"], 1, "client_secret в src/ → код 1: %s" % r["output"])
	assert_true(str(r["output"]).contains("SECRET?"))


func test_req_inf_03_c5_secrets_script_fails_on_each_pattern_from_requirement() -> void:
	if not _has_tool("bash"):
		pending("bash недоступен")
		return
	var samples := {
		"api_key": "var api_key = \"AKIA1234567890\"",
		"Bearer": "var h = \"Authorization: Bearer eyJhbGciOiJIUzI1NiJ9.abc.def\"",
		"refresh_token": "var refresh_token = \"rt-9f8e7d6c5b4a\"",
		"sk_": "const KEY := \"sk_1234567890abcdef\"",
	}
	for name in samples.keys():
		var r := _run(_sandbox_with_secrets_script({"src/leak_%s.gd" % name: "extends RefCounted\n%s\n" % samples[name]}), [])
		assert_eq(r["code"], 1, "шаблон %s должен ловиться: %s" % [name, r["output"]])
		OS.execute("rm", ["-rf", ProjectSettings.globalize_path(_dir + "sandbox/")])


func test_req_inf_03_c5_secrets_script_fails_on_secret_in_tests_fixtures() -> void:
	# Критерий прямо называет tests/fixtures/ целью поиска.
	if not _has_tool("bash"):
		pending("bash недоступен")
		return
	var r := _run(_sandbox_with_secrets_script({"tests/fixtures/tmp_secret_probe.gd": "extends RefCounted\nvar client_secret = \"abc12345\"\n"}), [])
	assert_eq(r["code"], 1, "client_secret в tests/fixtures/ должен давать код 1; факт: код %d, вывод: %s" % [r["code"], r["output"]])


func test_req_inf_03_c5_secrets_script_fails_on_secret_in_project_godot_and_docs() -> void:
	if not _has_tool("bash"):
		pending("bash недоступен")
		return
	var r := _run(_sandbox_with_secrets_script({"project.godot": "[strava]\nclient_secret=\"abc12345\"\n"}), [])
	assert_eq(r["code"], 1, "client_secret в project.godot → 1: %s" % r["output"])
	OS.execute("rm", ["-rf", ProjectSettings.globalize_path(_dir + "sandbox/")])
	r = _run(_sandbox_with_secrets_script({"docs/notes.md": "token: Bearer abcdefghijklmnop\n"}), [])
	assert_eq(r["code"], 1, "Bearer в docs/ → 1: %s" % r["output"])


func test_req_inf_03_c5_secrets_script_allows_placeholders() -> void:
	if not _has_tool("bash"):
		pending("bash недоступен")
		return
	var r := _run(_sandbox_with_secrets_script({"src/cfg.gd": "extends RefCounted\nvar client_secret = \"<secret>\"\nvar api_key = \"PLACEHOLDER\"\n"}), [])
	assert_eq(r["code"], 0, "плейсхолдеры не считаются секретами: %s" % r["output"])


func test_req_inf_03_c5_no_secret_like_literals_in_repo_by_gut_scan() -> void:
	var re := RegEx.create_from_string("client_secret\\s*[=:]\\s*\"[^\"]+\"|api_key\\s*[=:]\\s*\"[^\"]+\"|Bearer [A-Za-z0-9._-]{8,}|refresh_token\\s*[=:]\\s*\"[^\"]+\"")
	var allow := RegEx.create_from_string("PLACEHOLDER|placeholder|example|EXAMPLE|<token>|<secret>|<key>|dummy")
	var offenders: Array[String] = []
	for root in [SRC, "res://tests/fixtures", "res://docs"]:
		for path in _list(root, [".gd", ".md", ".tscn", ".json", ".cfg", ".csv", ".txt", ".sh"]):
			var n := 0
			for line in FileAccess.get_file_as_string(path).split("\n"):
				n += 1
				if re.search(line) != null and allow.search(line) == null:
					offenders.append("%s:%d" % [path, n])
	assert_null(re.search(FileAccess.get_file_as_string("res://project.godot")), "секреты в project.godot")
	assert_eq(offenders, [], "строки, похожие на секреты: %s" % str(offenders))


# ===========================================================================
# REQ-INF-03 крит. 1, 2 — сообщения коммитов и история в CI
# ===========================================================================

func test_req_inf_03_c1_commit_script_accepts_recent_history_and_rejects_early_commits() -> void:
	if not _has_tool("bash") or not _has_tool("git"):
		pending("bash/git недоступны")
		return
	var script := ProjectSettings.globalize_path(COMMITS_SCRIPT)
	var head := _run(script, ["HEAD~0..HEAD"])
	assert_eq(head["code"], 0, "HEAD соответствует правилу: %s" % head["output"])
	var bad := _run(script, [EARLY_BAD_RANGE])
	assert_eq(bad["code"], 1, "ранние коммиты без REQ-ID и префикса → код 1: %s" % bad["output"])
	assert_true(str(bad["output"]).contains("BAD COMMIT"))
	assert_true(str(bad["output"]).contains("REQ-ID"))


func test_req_inf_03_c1_commit_script_rule_matches_requirement_regex() -> void:
	# Проверено чтением скрипта: правило — REQ-[A-Z0-9]+-[0-9]+ в теле или префикс docs:/ci:/tests:/chore: в заголовке.
	var text := FileAccess.get_file_as_string(COMMITS_SCRIPT)
	assert_string_contains(text, "REQ-[A-Z0-9]+-[0-9]+", "регулярное выражение критерия 1 присутствует")
	assert_string_contains(text, "^(docs|ci|tests|chore):", "служебные префиксы")
	assert_string_contains(text, "is-shallow-repository", "крит. 2: распознавание shallow clone")
	assert_string_contains(text, "exit 0", "на shallow clone — выход 0")
	assert_string_contains(text, "--no-merges", "merge-коммиты не проверяются")


func test_req_inf_03_c2_commit_script_skips_with_warning_on_shallow_clone() -> void:
	if not _has_tool("bash") or not _has_tool("git"):
		pending("bash/git недоступны")
		return
	var repo_abs := ProjectSettings.globalize_path("res://")
	var clone_abs := ProjectSettings.globalize_path(_dir + "shallow")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_dir))
	var out := []
	var code := OS.execute("git", ["clone", "-q", "--depth", "1", "file://" + repo_abs.trim_suffix("/"), clone_abs], out, true)
	assert_eq(code, 0, "shallow-клон создан: %s" % "\n".join(PackedStringArray(out)))
	var r := _run(clone_abs.path_join("scripts/check_commit_messages.sh"), ["HEAD~5..HEAD"])
	assert_eq(r["code"], 0, "на shallow clone проверка пропускается с кодом 0: %s" % r["output"])
	assert_true(str(r["output"]).contains("shallow"), "есть предупреждение о shallow clone: %s" % r["output"])


func test_req_inf_03_c2_commit_script_falls_back_to_head_on_unknown_range() -> void:
	if not _has_tool("bash") or not _has_tool("git"):
		pending("bash/git недоступны")
		return
	var r := _run(ProjectSettings.globalize_path(COMMITS_SCRIPT), ["no-such-ref-xyz..HEAD"])
	assert_eq(r["code"], 0, "недоступный диапазон → только HEAD, код 0: %s" % r["output"])
	assert_true(str(r["output"]).contains("недоступен"))


func test_req_inf_03_c2_ci_checks_out_full_history_and_runs_both_scripts_before_tests() -> void:
	var yml := FileAccess.get_file_as_string("res://.github/workflows/ci.yml")
	assert_string_contains(yml, "fetch-depth: 0")
	assert_string_contains(yml, "./scripts/check_secrets.sh")
	assert_string_contains(yml, "./scripts/check_commit_messages.sh")
	assert_string_contains(yml, 'branches: ["**"]')
	assert_string_contains(yml, "pull_request:")
	assert_string_contains(yml, "if: always()")
	assert_lt(yml.find("check_secrets.sh"), yml.find("scripts/test.sh"), "сканирование секретов — до тестов")
	assert_lt(yml.find("check_commit_messages.sh"), yml.find("scripts/test.sh"))
	var steps := yml.count("- name:")
	assert_gte(steps, 6)


# ===========================================================================
# REQ-INF-03 крит. 3 — парные .uid
# ===========================================================================

func test_req_inf_03_c3_every_gd_has_uid_and_no_orphan_uid_in_src_and_tests() -> void:
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
		assert_gt(gd.size(), 5)


# ===========================================================================
# REQ-INF-04 крит. 1, 2 — трассируемость тестов к требованиям
# ===========================================================================

func test_req_inf_04_c1_every_test_file_mentions_a_req_id_strictly() -> void:
	var re := RegEx.create_from_string("REQ-[A-Z0-9]+-[0-9]+")
	var without: Array[String] = []
	var checked := 0
	for path in _list(TESTS, [".gd"]):
		if not path.get_file().begins_with("test_"):
			continue
		checked += 1
		if re.search(FileAccess.get_file_as_string(path)) == null:
			without.append(path)
	assert_gt(checked, 20)
	assert_eq(without, [], "REQ-INF-04 крит. 1: тестовые файлы без REQ-ID: %s" % str(without))


func test_req_inf_04_c1_every_req_id_mentioned_in_tests_exists_in_requirements() -> void:
	var known: Dictionary = {}
	var heading := RegEx.create_from_string("^###\\s+(REQ-[A-Z0-9]+-[0-9]+)")
	for line in FileAccess.get_file_as_string(REQUIREMENTS).split("\n"):
		var m := heading.search(line)
		if m != null:
			known[m.get_string(1)] = true
	assert_gt(known.size(), 50)
	var re := RegEx.create_from_string("REQ-[A-Z0-9]+-[0-9]+")
	var unknown: Array[String] = []
	for path in _list(TESTS, [".gd"]):
		for m in re.search_all(FileAccess.get_file_as_string(path)):
			var id := m.get_string()
			if not known.has(id) and not unknown.has(id + " (" + path + ")"):
				unknown.append(id + " (" + path + ")")
	assert_eq(unknown, [], "тесты ссылаются на несуществующие REQ: %s" % str(unknown))


static func _backlog_done_reqs() -> Array[String]:
	var out: Array[String] = []
	var req_re := RegEx.create_from_string("REQ-[A-Z0-9]+-[0-9]+")
	var header_idx_req := -1
	var header_idx_status := -1
	for line in FileAccess.get_file_as_string(BACKLOG).split("\n"):
		if not line.begins_with("|"):
			continue
		var cells := line.split("|")
		if header_idx_req == -1:
			for i in cells.size():
				var c := cells[i].strip_edges()
				if c == "REQ-ID":
					header_idx_req = i
				elif c == "Статус":
					header_idx_status = i
			continue
		if not line.begins_with("| T-") or cells.size() <= maxi(header_idx_req, header_idx_status):
			continue
		if not cells[header_idx_status].contains("`done`"):
			continue
		for m in req_re.search_all(cells[header_idx_req]):
			if not out.has(m.get_string()):
				out.append(m.get_string())
	out.sort()
	return out


func test_req_inf_04_c2_every_req_of_done_backlog_task_has_a_test_mentioning_it() -> void:
	var done := _backlog_done_reqs()
	assert_gt(done.size(), 10, "REQ закрытых задач найдены в бэклоге: %d" % done.size())
	var corpus := ""
	for path in _list(TESTS, [".gd"]):
		corpus += FileAccess.get_file_as_string(path) + "\n"
	var uncovered: Array[String] = []
	for id in done:
		if not corpus.contains(id):
			uncovered.append(id)
	assert_eq(uncovered, [], "REQ закрытых (`done`) задач без теста: %s" % str(uncovered))


func test_req_inf_04_c2_this_batch_reqs_are_covered_by_tests() -> void:
	var corpus := ""
	for path in _list(TESTS, [".gd"]):
		corpus += FileAccess.get_file_as_string(path) + "\n"
	for id in ["REQ-NFR-02", "REQ-DEV-09", "REQ-WRK-01", "REQ-INF-03", "REQ-INF-04", "REQ-NFR-05", "REQ-NFR-06", "REQ-NFR-09"]:
		assert_true(corpus.contains(id), "нет теста с %s" % id)


# ===========================================================================
# REQ-NFR-06 крит. 1–3 — изоляция платформенного кода и слои
# ===========================================================================

func test_req_nfr_06_c1_platform_calls_only_in_three_allowed_places() -> void:
	var allowed: Array[String] = ["res://src/storage/secure_store", "res://src/devices/ble/", "res://src/app/locale.gd"]
	var re := RegEx.create_from_string("(^|[^A-Za-z0-9_])OS\\.|\\bhas_feature\\(|\"(macOS|iOS|Android|Linux|Windows)\"")
	var offenders: Array[String] = []
	for path in _list(SRC, [".gd"]):
		var skip := false
		for p in allowed:
			if path.begins_with(p):
				skip = true
		if skip:
			continue
		var n := 0
		for line in _code_lines(path):
			n += 1
			if re.search(line) != null:
				offenders.append("%s:%d %s" % [path, n, line.strip_edges()])
	assert_eq(offenders, [], "платформенные вызовы вне разрешённых мест: %s" % str(offenders))


## Сторонние зависимости (SDK godot-cpp) — не код проекта; критерий относится к собственному коду.
const THIRD_PARTY_NATIVE_PREFIXES: Array[String] = ["res://native/godot-cpp/"]
const NATIVE_EXTS: Array[String] = [".cpp", ".cc", ".mm", ".m", ".h", ".hpp", ".java", ".kt", ".swift"]


func test_req_nfr_06_c2_no_native_sources_outside_native_ble() -> void:
	var offenders: Array[String] = []
	for root in ["res://src", "res://tests", "res://assets", "res://scripts", "res://addons", "res://docs"]:
		offenders.append_array(_list(root, NATIVE_EXTS))
	for path in _list("res://native", NATIVE_EXTS):
		var third_party := false
		for prefix in THIRD_PARTY_NATIVE_PREFIXES:
			if path.begins_with(prefix):
				third_party = true
		if not third_party and not path.begins_with("res://native/ble/"):
			offenders.append(path)
	assert_eq(offenders, [], "собственный нативный код вне native/ble/: %s" % str(offenders))


func test_req_nfr_06_c3_domain_depends_on_nothing_outside_domain() -> void:
	var outer: Array[String] = []
	for dir in ["res://src/devices", "res://src/session", "res://src/app", "res://src/ui", "res://src/scene3d", "res://src/profiles", "res://src/storage"]:
		outer.append_array(_class_names_in(dir))
	assert_gt(outer.size(), 5)
	var class_re := RegEx.create_from_string("\\b(" + "|".join(outer) + ")\\b")
	var scene_re := RegEx.create_from_string("\\bextends\\s+(Node|Control|Node2D|Node3D|CanvasItem)\\b|\\b(get_tree|preload|load)\\s*\\(|res://src/(devices|session|ui|scene3d|app|profiles|storage)/|\\bSceneTree\\b")
	var offenders: Array[String] = []
	for path in _list("res://src/domain", [".gd"]):
		var n := 0
		for line in _code_lines(path):
			n += 1
			if class_re.search(line) != null or scene_re.search(line) != null:
				offenders.append("%s:%d" % [path, n])
	assert_eq(offenders, [], "домен зависит от внешних слоёв: %s" % str(offenders))


func test_req_nfr_06_c3_session_depends_only_on_domain_and_trainer_interface() -> void:
	var forbidden: Array[String] = ["FakeTrainer", "BleTrainer", "StubBleBridge", "NativeBleBridge", "TrainerFactory"]
	forbidden.append_array(_class_names_in("res://src/app"))
	forbidden.append_array(_class_names_in("res://src/ui"))
	forbidden.append_array(_class_names_in("res://src/profiles"))
	forbidden.append_array(_class_names_in("res://src/storage"))
	var re := RegEx.create_from_string("\\b(" + "|".join(forbidden) + ")\\b")
	var offenders: Array[String] = []
	for path in _list("res://src/session", [".gd"]):
		var n := 0
		for line in _code_lines(path):
			n += 1
			if re.search(line) != null:
				offenders.append("%s:%d %s" % [path, n, line.strip_edges()])
	assert_eq(offenders, [], "src/session/ зависит от реализаций станка или верхних слоёв: %s" % str(offenders))


func test_req_nfr_06_c3_no_layer_depends_on_app_shell_and_lower_layers_ignore_app_state() -> void:
	# Решение Н-5 (REQ-NFR-06 крит. 3): src/app/ = модель навигации AppState (контракт, от
	# которого может зависеть только src/ui/) + оболочка main.gd/main.tscn/locale.gd, от
	# которой не зависит никто. Нижние слои не упоминают ничего из src/app/ вообще.
	var shell_re := RegEx.create_from_string("\\bAppMain\\b|\\bAppLocale\\b|src/app/main\\.gd|src/app/main\\.tscn|src/app/locale\\.gd")
	var app_classes := _class_names_in("res://src/app")
	assert_has(app_classes, "AppState")
	assert_has(app_classes, "AppMain")
	assert_has(app_classes, "AppLocale")
	var any_app_re := RegEx.create_from_string("\\b(" + "|".join(app_classes) + ")\\b|res://src/app/")
	var shell_offenders: Array[String] = []
	var lower_offenders: Array[String] = []
	var lower_dirs: Array[String] = ["res://src/domain/", "res://src/session/", "res://src/devices/", "res://src/profiles/", "res://src/storage/", "res://src/integrations/"]
	for path in _list(SRC, [".gd", ".tscn"]):
		if path.begins_with("res://src/app/"):
			continue
		var is_lower := false
		for d in lower_dirs:
			if path.begins_with(d):
				is_lower = true
		var n := 0
		for line in _code_lines(path):
			n += 1
			if shell_re.search(line) != null:
				shell_offenders.append("%s:%d %s" % [path, n, line.strip_edges()])
			if is_lower and any_app_re.search(line) != null:
				lower_offenders.append("%s:%d %s" % [path, n, line.strip_edges()])
	assert_eq(shell_offenders, [], "оболочка src/app/ (AppMain, main.gd/.tscn, AppLocale/locale.gd) упомянута вне src/app/: %s" % str(shell_offenders))
	assert_eq(lower_offenders, [], "нижние слои упоминают src/app/ (включая AppState): %s" % str(lower_offenders))


func test_req_nfr_06_c3_ui_may_depend_on_app_state_only() -> void:
	# UI навигирует через AppState — разрешено Н-5; но ничего другого из src/app/ UI не знает.
	var ui_uses_app_state := false
	var other: Array[String] = []
	var other_re := RegEx.create_from_string("\\bAppMain\\b|\\bAppLocale\\b|TranslationServer\\.set_locale")
	for path in _list("res://src/ui", [".gd"]):
		for line in _code_lines(path):
			if line.contains("AppState"):
				ui_uses_app_state = true
			if other_re.search(line) != null:
				other.append("%s: %s" % [path, line.strip_edges()])
	assert_true(ui_uses_app_state, "UI использует контракт AppState")
	assert_eq(other, [], "UI не трогает оболочку и не меняет локаль сам: %s" % str(other))


func test_req_nfr_06_c3_architecture_tests_exist_and_cover_negative_probe_by_design() -> void:
	# Негативная проба (src/domain/tmp_probe.gd: extends Node + OS.get_name()) выполнена вручную:
	# три теста разработчика упали (domain deps, extends, platform calls). Здесь — что они есть.
	var arch := FileAccess.get_file_as_string("res://tests/unit/arch/test_architecture.gd")
	for name in ["test_domain_has_no_dependencies_on_outer_layers", "test_domain_classes_extend_refcounted_or_domain_classes", "test_platform_calls_only_in_allowed_files", "test_native_code_only_under_native_ble"]:
		assert_string_contains(arch, name)


# ===========================================================================
# REQ-NFR-05 крит. 1 — единственная точка работы с секретами
# ===========================================================================

func test_req_nfr_05_c1_only_storage_touches_secret_files_and_tokens() -> void:
	var offenders: Array[String] = []
	var re := RegEx.create_from_string("open_encrypted_with_pass|secrets\\.bin|access_token|refresh_token|api_key|client_secret")
	for path in _list(SRC, [".gd"]):
		if path.begins_with("res://src/storage/"):
			continue
		var code := "\n".join(_code_lines(path))
		# Критерий разрешает интеграции, работающие через интерфейс SecureStore (а не напрямую с файлами/токенами).
		if path.begins_with("res://src/integrations/") and code.contains("SecureStore") \
				and not code.contains("open_encrypted_with_pass") and not code.contains("secrets.bin"):
			continue
		var n := 0
		for line in _code_lines(path):
			n += 1
			if re.search(line) != null:
				offenders.append("%s:%d" % [path, n])
	assert_eq(offenders, [], "работа с секретами вне src/storage/ и интеграций через SecureStore: %s" % str(offenders))


# ===========================================================================
# REQ-NFR-09 крит. 1, 4 — покрытие доменного слоя
# ===========================================================================

func test_req_nfr_09_c1_domain_test_files_exist_for_executor_workout_and_zones() -> void:
	var names: Array[String] = []
	for path in _list("res://tests/unit/domain", [".gd"]):
		names.append(path.get_file())
	var want := {"executor": false, "workout": false, "zones": false}
	for n in names:
		for key in want.keys():
			if n.contains(key):
				want[key] = true
	for key in want.keys():
		assert_true(want[key], "нет тестового файла для «%s» в tests/unit/domain: %s" % [key, str(names)])
	# Парсеры ZWO/.erg/Intervals, FIT, сводка, очередь Strava — этапы 4–6, пока n/a.


func test_req_nfr_09_c4_domain_tests_and_sources_have_no_scene_tree_dependencies() -> void:
	var offenders: Array[String] = []
	for path in _list("res://tests/unit/domain", [".gd"]):
		var n := 0
		for line in _code_lines(path):
			n += 1
			if line.contains("get_tree(") or line.contains("add_child") or line.contains("autofree") or line.contains("await "):
				offenders.append("%s:%d" % [path, n])
	assert_eq(offenders, [], "доменные тесты зависят от SceneTree: %s" % str(offenders))
	var re := RegEx.create_from_string("^extends\\s+([A-Za-z_][A-Za-z0-9_]*)")
	var domain := _class_names_in("res://src/domain")
	for path in _list("res://src/domain", [".gd"]):
		for line in FileAccess.get_file_as_string(path).split("\n"):
			var m := re.search(line)
			if m != null:
				assert_true(m.get_string(1) in ["RefCounted", "Object", "Resource"] or domain.has(m.get_string(1)), "%s extends %s" % [path, m.get_string(1)])
