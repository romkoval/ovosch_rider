extends GutTest
## Статическая проверка UI (T-089): REQ-UIX-01 крит. 2 — в сценах и коде `src/ui/` нет локальных
## переопределений темы; REQ-NFR-08 крит. 1, 2 — итоговый набор переводов: каждый ключ всех
## `strings*.csv` используется кодом, ru и en непустые.
##
## Переопределения ищутся по всему `src/ui/**` и шире формулировки UIX-01 крит. 2: не только цвет,
## шрифт и размер, но и стили и константы (`theme_override_*`, `add_theme_*_override`). Исключение —
## кнопка «Connect with Strava» по брендбуку Strava (`strava_connect_button.gd`, решение У-8).
## Цвета данных (зона, уклон, статус) задаются `self_modulate`/рисованием и сюда не попадают.

const UI_DIR: String = "res://src/ui/"
const I18N_DIR: String = "res://assets/i18n/"
## Где ищутся ключи переводов.
const CODE_DIRS: Array[String] = ["res://src/", "res://scripts/"]
## Файлы с разрешёнными переопределениями (брендбук Strava, У-8).
const OVERRIDE_ALLOWED: Array[String] = ["res://src/ui/common/strava_connect_button.gd"]
## Префиксы ключей, которые код собирает из частей (`prefix + code`): ключ с таким префиксом
## считается используемым, если префикс встречается в коде.
const DYNAMIC_PREFIXES: Array[String] = [
	"error.profile.", "ui.dev.state.", "ui.dev.connection.", "ui.hud.connection.",
	"ui.plan.import.error.", "ui.history.strava.", "ui.free_ride.summary.", "ui.hud_controls.",
	"ui.history.month.", "ui.history.mon.", "ui.history.stat.", "track.",
]
## Ключи-метаданные файлов по областям (`meta.area.<область>`, проверяет `test_i18n.gd`) и
## образец перевода из `test_i18n.gd` — в коде не встречаются, но нужны.
const KEYS_WITHOUT_CODE: Array[String] = ["ui.profile_select.title"]
const META_PREFIX: String = "meta.area."

var _override_re := RegEx.create_from_string("theme_override_[a-z_]+/|add_theme_[a-z_]+_override\\s*\\(")


static func _files(dir_path: String, exts: Array[String], out: Array[String]) -> void:
	var d := DirAccess.open(dir_path)
	if d == null:
		return
	for f in d.get_files():
		if exts.has(f.get_extension()):
			out.append(dir_path.path_join(f))
	for sub in d.get_directories():
		if not sub.begins_with("."):
			_files(dir_path.path_join(sub), exts, out)


## Текст файла без комментариев (`#` до конца строки вне строковых литералов не разбирается:
## для поиска имён API этого достаточно — в литералах `#` в UI-коде нет перед вызовами).
static func _code(path: String) -> String:
	var kept: PackedStringArray = []
	for line in FileAccess.get_file_as_string(path).split("\n"):
		var stripped := line.strip_edges()
		if stripped.begins_with("#"):
			continue
		var idx := line.find(" ## ")
		kept.append(line.substr(0, idx) if idx != -1 else line)
	return "\n".join(kept)


func test_req_uix_01_c2_no_theme_overrides_in_src_ui() -> void:
	var files: Array[String] = []
	_files(UI_DIR, ["gd", "tscn", "tres"] as Array[String], files)
	assert_gt(files.size(), 50, "предусловие: файлы src/ui найдены")
	var found: Array[String] = []
	for path in files:
		if OVERRIDE_ALLOWED.has(path):
			continue
		var lines := _code(path).split("\n")
		for i in lines.size():
			if _override_re.search(lines[i]) != null:
				found.append("%s: %s" % [path.trim_prefix(UI_DIR), lines[i].strip_edges()])
	assert_eq(found, [] as Array[String], "переопределения темы в src/ui (только тема и вариации)")


func test_req_uix_01_c2_strava_exception_is_the_only_one() -> void:
	# Исключение У-8 — действительно кнопка Strava (иначе исключение надо пересмотреть).
	var code := _code(OVERRIDE_ALLOWED[0])
	assert_true(_override_re.search(code) != null, "в кнопке Strava стили по брендбуку")
	assert_string_contains(code, "class_name StravaConnectButton")


## Ключи всех `strings*.csv`: ключ → {ru, en}.
static func _keys() -> Dictionary:
	var out := {}
	for name in DirAccess.get_files_at(I18N_DIR):
		if not (name.begins_with("strings") and name.ends_with(".csv")):
			continue
		var f := FileAccess.open(I18N_DIR + name, FileAccess.READ)
		var header := f.get_csv_line()
		var ru := header.find("ru")
		var en := header.find("en")
		while not f.eof_reached():
			var row := f.get_csv_line()
			if row.size() < 2 or row[0].is_empty():
				continue
			out[row[0]] = {"ru": row[ru] if ru < row.size() else "", "en": row[en] if en < row.size() else "", "file": name}
	return out


func test_req_nfr_08_c1_c2_every_key_is_used_and_translated() -> void:
	var keys := _keys()
	assert_gt(keys.size(), 300, "предусловие: ключи прочитаны")
	var files: Array[String] = []
	for dir_path in CODE_DIRS:
		_files(dir_path, ["gd", "tscn"] as Array[String], files)
	var code := ""
	for path in files:
		code += _code(path) + "\n"
	var unused: Array[String] = []
	var empty: Array[String] = []
	for key: String in keys:
		var entry: Dictionary = keys[key]
		if str(entry["ru"]).strip_edges().is_empty() or str(entry["en"]).strip_edges().is_empty():
			empty.append(key)
		if key.begins_with(META_PREFIX) or KEYS_WITHOUT_CODE.has(key) or _used(code, key):
			continue
		unused.append("%s (%s)" % [key, entry["file"]])
	assert_eq(empty, [] as Array[String], "ключи без перевода ru/en")
	assert_eq(unused, [] as Array[String], "ключи, которых нет в коде")


static func _used(code: String, key: String) -> bool:
	if RegEx.create_from_string(_escape(key) + "(?![a-z_0-9.])").search(code) != null:
		return true
	for prefix in DYNAMIC_PREFIXES:
		if key.begins_with(prefix) and RegEx.create_from_string("\"" + _escape(prefix) + "[\"%]").search(code) != null:
			return true
	return false


static func _escape(text: String) -> String:
	return text.replace(".", "\\.")
