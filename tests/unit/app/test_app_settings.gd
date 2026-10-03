extends GutTest
## Тесты AppSettings (REQ-NFR-08 крит. 3): сохранение языка между запусками.

var _path: String


func before_each() -> void:
	_path = "user://test_settings_%d_%d/settings.json" % [Time.get_ticks_usec(), randi() % 100000]


func after_each() -> void:
	var dir := ProjectSettings.globalize_path(_path.get_base_dir())
	if DirAccess.dir_exists_absolute(dir):
		for f in DirAccess.open(dir).get_files():
			DirAccess.remove_absolute(dir.path_join(f))
		DirAccess.remove_absolute(dir)


func test_missing_file_gives_defaults_and_system_locale() -> void:
	var s := AppSettings.load_from(_path)
	assert_eq(s.locale, "")
	assert_false(s.has_locale())
	assert_eq(s.effective_locale(), AppLocale.detect(), "без сохранённого языка — системный")
	assert_eq(s.path(), _path)


func test_save_and_reload_locale() -> void:
	var s := AppSettings.new(_path)
	s.locale = "ru"
	assert_true(s.save())
	assert_true(FileAccess.file_exists(_path))
	var again := AppSettings.load_from(_path)
	assert_eq(again.locale, "ru", "язык сохраняется между запусками")
	assert_eq(again.effective_locale(), "ru")
	assert_true(again.has_locale())


func test_unsupported_or_corrupted_values_fall_back() -> void:
	var s := AppSettings.new(_path)
	s.locale = "de"
	s.save()
	assert_eq(AppSettings.load_from(_path).locale, "", "неподдерживаемый язык игнорируется")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_path.get_base_dir()))
	var f := FileAccess.open(_path, FileAccess.WRITE)
	f.store_string("{not json")
	f.close()
	var broken := AppSettings.load_from(_path)
	assert_eq(broken.locale, "", "повреждённый файл — значения по умолчанию")
	assert_eq(broken.effective_locale(), AppLocale.detect())
