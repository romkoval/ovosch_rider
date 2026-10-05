extends GutTest
## Бэклог и файлы задач не расходятся (REQ-INF-03: задачи и коммиты трассируются по ID).
## С 2026-10-05 `docs/backlog.md` — индекс: строка задачи в таблице раздела 2, файл задачи —
## `docs/tasks/<ID>.md`; описание, критерии и история — в файле задачи.
## Статус — только в таблице. Тест ловит задачу без файла, файл без строки,
## повтор строки, неизвестный статус и карточку, вернувшуюся в бэклог.

const BACKLOG: String = "res://docs/backlog.md"
const TASKS: String = "res://docs/tasks"
const TEMPLATE: String = "_template.md"
const STATUSES: Array[String] = ["todo", "in-progress", "review", "done", "blocked", "split"]


## Строки таблицы: {"id": ID, "status": текст статуса}. Файл задачи — `docs/tasks/<ID>.md`.
static func table_rows(text: String) -> Array[Dictionary]:
	var row_re := RegEx.create_from_string(r'^\| (T-[0-9][^ |]*) \|.*\| `([^`]*)` \|$')
	var out: Array[Dictionary] = []
	for line in text.split("\n"):
		var m := row_re.search(line)
		if m != null:
			out.append({"id": m.get_string(1), "status": m.get_string(2)})
	return out


## Проблемы согласованности: пустой массив — всё сходится.
static func problems(backlog: String, files: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var ids: Dictionary = {}
	for row in table_rows(backlog):
		var id: String = row["id"]
		if ids.has(id):
			out.append("%s: строка в таблице повторяется" % id)
		ids[id] = true
		var word: String = String(row["status"]).split(":")[0].strip_edges()
		if not STATUSES.has(word):
			out.append("%s: неизвестный статус «%s»" % [id, row["status"]])
		if not files.has(id):
			out.append("%s: нет файла docs/tasks/%s.md" % [id, id])
		elif not String(files[id]).begins_with("# %s — " % id):
			out.append("%s: файл не начинается с «# %s — »" % [id, id])
	for id in files:
		if not ids.has(id):
			out.append("%s: файл docs/tasks/%s.md есть, строки в таблице нет" % [id, id])
	var card_re := RegEx.create_from_string(r'(?m)^#### T-[0-9]')
	if card_re.search(backlog) != null:
		out.append("карточка задачи (#### T-…) в backlog.md — её место в docs/tasks/")
	return out


static func task_files() -> Dictionary:
	var out: Dictionary = {}
	var d := DirAccess.open(TASKS)
	if d == null:
		return out
	for f in d.get_files():
		if f.ends_with(".md") and f != TEMPLATE:
			out[f.get_basename()] = FileAccess.get_file_as_string(TASKS.path_join(f))
	return out


func test_backlog_rows_and_task_files_match() -> void:
	var backlog := FileAccess.get_file_as_string(BACKLOG)
	var files := task_files()
	assert_gt(table_rows(backlog).size(), 100, "строки таблицы найдены")
	assert_gt(files.size(), 100, "файлы задач найдены")
	assert_eq(problems(backlog, files), [] as Array[String], "бэклог и docs/tasks/ расходятся")


func test_template_exists() -> void:
	assert_true(FileAccess.file_exists(TASKS.path_join(TEMPLATE)), "шаблон docs/tasks/_template.md")


func test_detector_catches_mismatches() -> void:
	var backlog := "\n".join([
		"| T-001 | `[game]` | 1 | А | REQ-INF-01 | — | — | `done` |",
		"| T-002 | `[game]` | 1 | Б | — | — | — | `готово` |",
		"| T-003 | `[game]` | 1 | В | — | — | — | `todo` |",
		"#### T-004 — карточка",
	])
	var files := {"T-001": "# T-001 — А", "T-002": "# T-002 — Б", "T-009": "# T-009 — лишний"}
	var p := problems(backlog, files)
	assert_eq(p.size(), 4, str(p))  # статус T-002, нет файла T-003, лишний T-009, карточка
	assert_eq(problems("| T-001 | x | 1 | А | — | — | — | `blocked: ждёт Н-1` |", {"T-001": "# T-001 — А"}).size(), 0)
