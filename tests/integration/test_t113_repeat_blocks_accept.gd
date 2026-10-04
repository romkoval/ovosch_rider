extends GutTest
## Приёмка T-113 (tester): REQ-HUD-13 п.8 для ZWO — путь пользователя целиком: файл `.zwo`
## импортируется в библиотеку (экран плана), приложение перезапускается, план читается из
## библиотеки, тренировка стартует на эмуляторе — список интервалов HUD до начала блока
## `IntervalsT` показывает его одной строкой цвета зоны рабочего отрезка (блок начинается с
## отдыха: OnPower ниже OffPower), с начала блока — строка на шаг. Два соседних `IntervalsT`
## с одинаковыми параметрами — две отдельные строки, не одна.

const MAIN_SCENE: String = "res://src/app/main.tscn"
const FTP: int = 200
## Разминка 2 × 1:00, затем блок 4 × (1:00 62.5 % = 125 Вт / 2:00 150 % = 300 Вт), затем два
## одинаковых IntervalsT 2 × (0:30 320 Вт / 0:30 100 Вт) подряд.
const ZWO: String = """<workout_file><name>T113 accept</name><workout>
<SteadyState Duration="60" Power="0.5"/>
<SteadyState Duration="60" Power="0.6"/>
<IntervalsT Repeat="4" OnDuration="60" OnPower="0.625" OffDuration="120" OffPower="1.5"/>
<IntervalsT Repeat="2" OnDuration="30" OnPower="1.6" OffDuration="30" OffPower="0.5"/>
<IntervalsT Repeat="2" OnDuration="30" OnPower="1.6" OffDuration="30" OffPower="0.5"/>
</workout></workout_file>"""

var _dir: String
var _now_usec: int = 1_000_000


func before_each() -> void:
	_dir = "user://test_t113_accept_%d_%d/" % [Time.get_ticks_usec(), randi() % 1000000]


func after_each() -> void:
	DiagLog.uninstall()
	_remove_tree(ProjectSettings.globalize_path(_dir))


static func _remove_tree(abs_path: String) -> void:
	if not DirAccess.dir_exists_absolute(abs_path):
		return
	var d := DirAccess.open(abs_path)
	if d == null:
		return
	for f in d.get_files():
		DirAccess.remove_absolute(abs_path.path_join(f))
	for sub in d.get_directories():
		_remove_tree(abs_path.path_join(sub))
	DirAccess.remove_absolute(abs_path)


func _main() -> AppMain:
	var main: AppMain = load(MAIN_SCENE).instantiate()
	main.data_dir = _dir
	main.trainer_kind = TrainerFactory.KIND_FAKE
	main.transport = MockHttpTransport.new()
	main.env_reader = Callable()
	add_child(main)
	return main


func _clock() -> int:
	return _now_usec


## Токен цвета зоны для шага с целью `watts` (та же модель, без знания границ зон).
static func _token_of_watts(watts: int) -> String:
	var w := Workout.make("one", [WorkoutStep.watts(60, float(watts))] as Array[WorkoutStep])
	return str(IntervalListModel.new(w, FTP).rows()[0]["color_token"])


func test_zwo_imported_to_library_survives_restart_and_hud_collapses_blocks() -> void:
	var repo := ProfileRepository.new(_dir + "profiles/")
	var p := repo.create("Solo")
	p.ftp_w = FTP
	repo.save(p)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_dir))
	var file := ProjectSettings.globalize_path(_dir + "t113.zwo")
	var f := FileAccess.open(file, FileAccess.WRITE)
	f.store_string(ZWO)
	f.close()
	# Запуск 1: импорт файла в библиотеку через экран плана.
	var first := _main()
	first.app_state.navigate(AppState.Screen.PLAN)
	var imported := first.plan_screen().import_path(file)
	assert_true(imported != null and imported.ok(), "импорт .zwo")
	var entry_id := str(imported.metadata.get("entry_id", "")) if imported != null else ""
	assert_false(entry_id.is_empty(), "запись библиотеки")
	first.free()
	# Запуск 2: план из библиотеки.
	var main := _main()
	var plan := main.workout_library.get_workout(main.repo.get_active().id, entry_id)
	assert_not_null(plan, "план прочитан из библиотеки после перезапуска")
	if plan == null:
		main.free()
		return
	assert_eq(plan.valid_repeat_blocks().size(), 3, "три блока IntervalsT сохранены в библиотеке: %s" % str(plan.repeat_blocks))
	assert_true(main.start_workout_on_emulator(plan), "тренировка на эмуляторе")
	var ws := main.workout_screen()
	ws.clock_usec = _clock
	await wait_process_frames(2)
	var model: IntervalListModel = ws.interval_list().model
	assert_not_null(model, "модель списка интервалов HUD")
	if model == null:
		main.free()
		return
	# До начала блоков: 2 строки разминки + 3 свёрнутых блока (соседние IntervalsT не слиты).
	assert_eq(model.row_count(), 5, "до начала блоков — 2 + 3 строки")
	if model.row_count() == 5:
		var row: Dictionary = model.rows()[2]
		assert_eq(str(row["kind"]), IntervalListModel.KIND_REPEAT, "блок свёрнут")
		assert_eq(str(row["color_token"]), _token_of_watts(300), "цвет — зона рабочего отрезка 300 Вт, а не отдыха 125 Вт")
		assert_eq(str(model.rows()[3]["kind"]), IntervalListModel.KIND_REPEAT)
		assert_eq(str(model.rows()[4]["kind"]), IntervalListModel.KIND_REPEAT, "второй одинаковый IntervalsT — своя строка")
	# Довести сессию до начала первого блока (120 с разминки) — блок раскрыт по шагам.
	var session := ws.session()
	for i in 121:
		session.tick(1.0)
	model.sync(session)
	assert_eq(model.row_count(), 2 + 8 + 2, "с начала блока — строка на шаг, следующие блоки свёрнуты")
	session.stop()
	main.free()
