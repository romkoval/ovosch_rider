extends GutTest
## Тесты StravaConfig (REQ-STR-01 крит. 5, 6; решение В-6).

var _dir: String


func before_each() -> void:
	_dir = "user://test_strava_cfg_%d_%d/" % [Time.get_ticks_usec(), randi() % 100000]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_dir))


func after_each() -> void:
	var abs := ProjectSettings.globalize_path(_dir)
	var d := DirAccess.open(abs)
	if d != null:
		for f in d.get_files():
			DirAccess.remove_absolute(abs.path_join(f))
	DirAccess.remove_absolute(abs)


func _write_cfg(id: String, secret: String) -> String:
	var cfg := ConfigFile.new()
	cfg.set_value("strava", "client_id", id)
	cfg.set_value("strava", "client_secret", secret)
	var path := _dir + "secrets.cfg"
	cfg.save(path)
	return path


func _env(values: Dictionary) -> Callable:
	return func(name: String) -> String: return str(values.get(name, ""))


func test_loads_from_config_file() -> void:
	var c := StravaConfig.load(_write_cfg("12345", "fixture-secret-value"))
	assert_true(c.is_configured(), "REQ-STR-01 крит. 6: user://secrets.cfg")
	assert_eq(c.client_id, "12345")
	assert_eq(c.client_secret(), "fixture-secret-value")
	assert_eq(c.source, StravaConfig.SOURCE_CONFIG_FILE)


func test_loads_from_environment_when_no_file() -> void:
	var env := _env({StravaConfig.ENV_CLIENT_ID: "777", StravaConfig.ENV_CLIENT_SECRET: "env-fixture-secret"})
	var c := StravaConfig.load(_dir + "missing.cfg", env)
	assert_true(c.is_configured(), "REQ-STR-01 крит. 6: переменные окружения")
	assert_eq(c.client_id, "777")
	assert_eq(c.source, StravaConfig.SOURCE_ENVIRONMENT)


func test_config_file_has_priority_over_environment() -> void:
	var env := _env({StravaConfig.ENV_CLIENT_ID: "777", StravaConfig.ENV_CLIENT_SECRET: "env-fixture-secret"})
	var c := StravaConfig.load(_write_cfg("12345", "file-fixture-secret"), env)
	assert_eq(c.client_id, "12345")
	assert_eq(c.source, StravaConfig.SOURCE_CONFIG_FILE)


func test_without_any_source_not_configured_with_message_and_no_crash() -> void:
	var c := StravaConfig.load(_dir + "missing.cfg")
	assert_false(c.is_configured(), "REQ-STR-01 крит. 6")
	assert_eq(c.source, StravaConfig.SOURCE_NONE)
	assert_string_contains(c.unavailable_message(), "недоступна")
	assert_string_contains(c.unavailable_message(), "secrets.cfg")
	var invalid_env := _env({StravaConfig.ENV_CLIENT_ID: "1"})
	assert_false(StravaConfig.load(_dir + "missing.cfg", invalid_env).is_configured(), "один параметр из двух — не настроено")


func test_placeholders_from_example_are_not_accepted() -> void:
	var c := StravaConfig.load(_write_cfg("YOUR_CLIENT_ID_PLACEHOLDER", "YOUR_CLIENT_SECRET_PLACEHOLDER"))
	assert_false(c.is_configured(), "плейсхолдеры примера не считаются настройкой")
	assert_true(FileAccess.file_exists("res://secrets.example.cfg.txt"), "в репозитории есть пример с плейсхолдерами")
	var example := FileAccess.get_file_as_string("res://secrets.example.cfg.txt")
	assert_string_contains(example, "PLACEHOLDER")
	assert_string_contains(example, "[strava]")


func test_secret_not_in_to_string() -> void:
	var c := StravaConfig.from_values("12345", "very-secret-fixture")
	assert_false(str(c).contains("very-secret-fixture"), "REQ-STR-01 крит. 5: секрет не логируется: %s" % str(c))
	assert_string_contains(str(c), "***")
	assert_eq(c.source, StravaConfig.SOURCE_BUILD)
	assert_false(StravaConfig.from_values("", "x").is_configured())
