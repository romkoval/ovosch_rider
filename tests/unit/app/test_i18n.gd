extends GutTest
## Инвентаризация переводов (REQ-NFR-08 крит. 1, 2): все ключи из сцен и скриптов
## UI есть в strings.csv с непустыми ru и en; в литералах `src/ui/` нет кириллицы.

const CSV_PATH: String = "res://assets/i18n/strings.csv"
const SCAN_DIRS: Array[String] = ["res://src/ui", "res://src/app", "res://src/scene3d"]

var _table: Dictionary = {}
var _locales: Array[String] = []


func before_all() -> void:
	var f := FileAccess.open(CSV_PATH, FileAccess.READ)
	assert_not_null(f, "strings.csv открывается")
	var header := f.get_csv_line()
	for i in range(1, header.size()):
		_locales.append(header[i])
	while not f.eof_reached():
		var line := f.get_csv_line()
		if line.size() < 2 or line[0].is_empty():
			continue
		var row: Dictionary = {}
		for i in range(1, mini(line.size(), header.size())):
			row[header[i]] = line[i]
		_table[line[0]] = row
	f.close()


func _files_recursive(dir_path: String, exts: Array[String]) -> Array[String]:
	var out: Array[String] = []
	var d := DirAccess.open(dir_path)
	if d == null:
		return out
	for f in d.get_files():
		for ext in exts:
			if f.ends_with(ext):
				out.append(dir_path.path_join(f))
	for sub in d.get_directories():
		out.append_array(_files_recursive(dir_path.path_join(sub), exts))
	return out


func _strip_comments(source: String) -> String:
	var kept: Array[String] = []
	for line in source.split("\n"):
		var idx := line.find("#")
		kept.append(line.substr(0, idx) if idx != -1 else line)
	return "\n".join(kept)


func _keys_in_sources() -> Dictionary:
	var re := RegEx.create_from_string('"((?:ui|error)\\.[a-z0-9_]+(?:\\.[a-z0-9_]+)+)"')
	var found: Dictionary = {}
	for dir in SCAN_DIRS:
		for path in _files_recursive(dir, [".gd", ".tscn"]):
			var text := FileAccess.get_file_as_string(path)
			for m in re.search_all(text):
				found[m.get_string(1)] = path
	return found


func test_csv_has_ru_and_en_columns() -> void:
	assert_eq(_locales, ["ru", "en"])
	assert_gt(_table.size(), 20)


func test_every_key_has_non_empty_ru_and_en() -> void:
	for key in _table:
		for locale in _locales:
			assert_false(str(_table[key].get(locale, "")).strip_edges().is_empty(), "REQ-NFR-08 крит. 2: %s [%s]" % [key, locale])


## REQ-NFR-08 крит. 2 по сырому CSV (словарь `_table` схлопывает дубликаты и короткие строки):
## каждый ключ встречается один раз, у каждой строки ровно столько колонок, сколько в заголовке,
## и непустые ru и en.
func test_csv_keys_unique_and_rows_complete() -> void:
	var f := FileAccess.open(CSV_PATH, FileAccess.READ)
	assert_not_null(f, "strings.csv открывается")
	var header := f.get_csv_line()
	var ru_col := header.find("ru")
	var en_col := header.find("en")
	assert_true(ru_col > 0 and en_col > 0, "в заголовке есть колонки ru и en")
	var seen: Dictionary = {}
	var duplicates: Array[String] = []
	var row_no := 1
	while not f.eof_reached():
		var line := f.get_csv_line()
		row_no += 1
		if line.size() == 1 and line[0].strip_edges().is_empty():
			continue
		var key := line[0].strip_edges()
		assert_false(key.is_empty(), "строка %d: пустой ключ" % row_no)
		if seen.has(key):
			duplicates.append("%s (строки %d и %d)" % [key, seen[key], row_no])
		else:
			seen[key] = row_no
		assert_eq(line.size(), header.size(), "строка %d (%s): число колонок" % [row_no, key])
		for col in [ru_col, en_col]:
			var value := line[col] if col < line.size() else ""
			assert_false(value.strip_edges().is_empty(), "REQ-NFR-08 крит. 2: %s [%s] пустой" % [key, header[col]])
	f.close()
	assert_eq(duplicates, [] as Array[String], "REQ-NFR-08 крит. 2: ключи в strings.csv не повторяются")
	assert_gt(seen.size(), 20)


func test_every_key_used_in_ui_sources_exists_in_csv() -> void:
	var used := _keys_in_sources()
	assert_gt(used.size(), 15, "ключи в сценах/скриптах найдены")
	for key in used:
		assert_true(_table.has(key), "ключ %s из %s отсутствует в strings.csv" % [key, used[key]])


func test_every_profile_error_code_has_translation() -> void:
	var codes: Array[String] = [
		Profile.ERR_ID_EMPTY, Profile.ERR_NAME_EMPTY, Profile.ERR_NAME_TOO_LONG,
		Profile.ERR_FTP_OUT_OF_RANGE, Profile.ERR_WEIGHT_OUT_OF_RANGE, Profile.ERR_MAX_HR_OUT_OF_RANGE,
		Profile.ERR_INTENSITY_OUT_OF_RANGE, Profile.ERR_RESISTANCE_OUT_OF_RANGE,
		Profile.ERR_POWER_ZONES_INVALID, Profile.ERR_HR_ZONES_INVALID,
		ProfileRepository.ERR_NAME_NOT_UNIQUE, ProfileRepository.ERR_PROFILE_NOT_FOUND,
		ProfileRepository.ERR_LAST_PROFILE, ProfileRepository.ERR_STORAGE_WRITE_FAILED,
	]
	for code in codes:
		assert_true(_table.has(ProfileSelectScreen.ERROR_KEY_PREFIX + code), "нет перевода для кода %s" % code)


func test_translations_are_loaded_in_project() -> void:
	var previous := TranslationServer.get_locale()
	TranslationServer.set_locale("ru")
	assert_eq(TranslationServer.translate("ui.profile_select.title"), "Выбор профиля")
	TranslationServer.set_locale("en")
	assert_eq(TranslationServer.translate("ui.profile_select.title"), "Choose a profile")
	assert_eq(ProfileSelectScreen.error_message(Profile.ERR_FTP_OUT_OF_RANGE), "FTP must be between 50 and 600 W")
	TranslationServer.set_locale(previous)


func test_no_cyrillic_literals_in_ui_sources() -> void:
	var cyr := RegEx.create_from_string("[\\p{Cyrillic}]")
	for dir in SCAN_DIRS:
		for path in _files_recursive(dir, [".gd", ".tscn"]):
			var text := _strip_comments(FileAccess.get_file_as_string(path))
			assert_null(cyr.search(text), "REQ-NFR-08 крит. 1: кириллица в литералах %s" % path)
