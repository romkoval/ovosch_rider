extends GutTest
## Повторная приёмка T-100 (tester): REQ-INF-01 крит. 2, 5 — одиночный прогон файла сцены
## (`-gselect=test_route_environments`, критерий карточки T-100) и отдельный процесс, который
## заполняет статический кэш `RouteWorld` и выходит без явной очистки, завершаются без
## «resources still in use at exit» и «leaked at exit». Кэш очищается сам при выходе корня
## дерева сцен; `clear_cache()` не ломает уже построенные трассы, повторный `track()` строит
## план заново.

const PROBE: String = "res://tests/fixtures/scene3d/route_cache_exit_probe.gd"
const LEAK_PATTERNS: Array[String] = ["resources still in use at exit", "leaked at exit"]


static func _godot() -> String:
	return OS.get_executable_path()


static func _project_dir() -> String:
	return ProjectSettings.globalize_path("res://")


static func _leaks(output: String) -> Array[String]:
	var out: Array[String] = []
	for line in output.split("\n"):
		for p in LEAK_PATTERNS:
			if line.to_lower().contains(p):
				out.append(line.strip_edges())
	return out


func test_req_inf_01_c5_probe_process_fills_cache_and_exits_without_leaks() -> void:
	var output: Array = []
	var code := OS.execute(_godot(), ["--headless", "--path", _project_dir(), "-s", PROBE], output, true)
	var text := "\n".join(output)
	assert_eq(code, 0, "проба завершилась кодом 0")
	assert_string_contains(text, "PROBE cached=2 hooked=true", "предусловие: кэш заполнен и подписан на выход")
	assert_eq(_leaks(text), [] as Array[String], "при выходе нет ресурсов в использовании и утечек")


func test_req_inf_01_c2_c5_single_file_run_route_environments_is_clean() -> void:
	var junit := ProjectSettings.globalize_path("user://t100_reaccept_results_%d.xml" % Time.get_ticks_usec())
	var output: Array = []
	var code := OS.execute(_godot(), ["--headless", "--path", _project_dir(), "-s", "addons/gut/gut_cmdln.gd",
		"-gconfig=res://.gutconfig.json", "-gselect=test_route_environments", "-gjunit_xml_file=" + junit],
		output, true)
	var text := "\n".join(output)
	DirAccess.remove_absolute(junit)
	assert_eq(code, 0, "одиночный прогон зелёный")
	assert_string_contains(text, "test_route_environments", "запущен именно этот файл")
	var scripts := RegEx.create_from_string("Scripts\\s+1\\s").search(text.replace("\u001b", ""))
	assert_not_null(scripts, "запущен ровно один скрипт")
	assert_eq(_leaks(text), [] as Array[String], "одиночный прогон без «resources still in use at exit»")


func test_clear_cache_keeps_built_tracks_and_rebuilds_on_demand() -> void:
	var a := RouteWorld.track("flat")
	assert_gt(RouteWorld.cached_count(), 0)
	assert_true(RouteWorld.is_exit_hooked(), "кэш подписан на выход корня дерева сцен")
	RouteWorld.clear_cache()
	assert_eq(RouteWorld.cached_count(), 0, "кэш пуст")
	assert_not_null(a.route, "уже построенная трасса цела")
	var b := RouteWorld.track("flat")
	assert_ne(a, b, "после очистки план строится заново")
	assert_eq(RouteWorld.track("flat"), b, "и снова берётся из кэша")
	RouteWorld.clear_cache()
