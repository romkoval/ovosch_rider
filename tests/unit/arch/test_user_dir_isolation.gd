extends GutTest
## T-115 (REQ-INF-01 п.1, 2): прогон GUT через scripts/test.sh пишет user:// в свой
## каталог, а не в общий app_userdata — параллельные прогоны из разных worktree не
## видят файлов друг друга.

const RUN_HOME_ENV := "OVOSCH_TEST_RUN_HOME"


func test_user_dir_is_inside_run_home_when_started_by_test_sh() -> void:
	var run_home: String = OS.get_environment(RUN_HOME_ENV)
	if run_home.is_empty():
		pending("прогон не через scripts/test.sh — изоляция user:// не включена")
		return
	var user_dir: String = OS.get_user_data_dir().simplify_path()
	var root: String = run_home.simplify_path()
	assert_true(user_dir.begins_with(root + "/"),
		"user:// (%s) — внутри каталога прогона (%s)" % [user_dir, root])
	# «//» в пути (TMPDIR с завершающим «/») ломает обход каталогов DirAccess.
	assert_false(OS.get_user_data_dir().contains("//"), "в пути user:// нет «//»: %s" % OS.get_user_data_dir())


func test_files_written_to_user_land_in_run_home() -> void:
	var run_home: String = OS.get_environment(RUN_HOME_ENV)
	if run_home.is_empty():
		pending("прогон не через scripts/test.sh — изоляция user:// не включена")
		return
	var path := "user://t115_isolation_probe.txt"
	var f := FileAccess.open(path, FileAccess.WRITE)
	assert_not_null(f, "user:// доступен на запись")
	if f == null:
		return
	f.store_string("probe")
	f.close()
	var abs_path: String = ProjectSettings.globalize_path(path).simplify_path()
	assert_true(abs_path.begins_with(run_home.simplify_path() + "/"), "файл лёг в каталог прогона: %s" % abs_path)
	# Обход каталога user:// видит ровно записанный файл (а не чужой каталог).
	var dir_path := "user://t115_isolation_dir/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir_path))
	var g := FileAccess.open(dir_path + "only.txt", FileAccess.WRITE)
	if g != null:
		g.store_string("x")
		g.close()
	var d := DirAccess.open(dir_path)
	assert_not_null(d)
	if d != null:
		assert_eq(Array(d.get_files()), ["only.txt"], "DirAccess перечисляет каталог прогона")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(dir_path + "only.txt"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(dir_path))
	DirAccess.remove_absolute(abs_path)


func test_test_sh_isolates_user_dir_and_cleans_up() -> void:
	var text := FileAccess.get_file_as_string("res://scripts/test.sh")
	assert_string_contains(text, "mktemp -d", "каталог данных — свой на прогон")
	assert_string_contains(text, "HOME=\"$run_home\"", "macOS: user:// строится от HOME")
	assert_string_contains(text, "XDG_DATA_HOME=\"$run_home", "Linux: user:// строится от XDG_DATA_HOME")
	assert_string_contains(text, "rm -rf \"$run_home\"", "после прогона каталог удаляется")
