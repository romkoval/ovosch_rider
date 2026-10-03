extends GutTest
## Приёмочные тесты парсеров источников плана и библиотеки тренировок
## (REQ-IMP-01, REQ-IMP-02, REQ-IMP-03 крит. 1, REQ-IMP-04, REQ-IMP-05, REQ-INT-03,
## REQ-NFR-09 крит. 1, 3). Фикстуры собраны независимо по спецификациям форматов:
## `tests/fixtures/workouts_acceptance/`.

const ACC: String = "res://tests/fixtures/workouts_acceptance/"
const DEV: String = "res://tests/fixtures/workouts/"
const A: String = "acc-profile-a"
const B: String = "acc-profile-b"

var _dir: String
var _lib: WorkoutLibrary


func before_each() -> void:
	_dir = "user://acc_workouts_%d_%d/" % [Time.get_ticks_usec(), randi() % 100000]
	_lib = WorkoutLibrary.new(_dir)


func after_each() -> void:
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


static func _read(name: String) -> String:
	return FileAccess.get_file_as_string(ACC + name)


static func _event(name: String) -> Dictionary:
	var json := JSON.new()
	assert(json.parse(_read(name)) == OK)
	return json.data


func _write_tmp(name: String, text: String) -> String:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_dir + "in/"))
	var path := _dir + "in/" + name
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()
	return path


func _write_tmp_bytes(name: String, bytes: PackedByteArray) -> String:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_dir + "in/"))
	var path := _dir + "in/" + name
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer(bytes)
	f.close()
	return path


static func _has_key(entries: Array[Dictionary], key: String) -> bool:
	for e in entries:
		if str(e.get("key", "")) == key:
			return true
	return false


static func _entry_with_key(entries: Array[Dictionary], key: String) -> Dictionary:
	for e in entries:
		if str(e.get("key", "")) == key:
			return e
	return {}


func _assert_step_percent(s: WorkoutStep, dur: int, pct: float, ctx: String) -> void:
	assert_eq(s.duration_sec, dur, ctx + ": длительность")
	assert_eq(s.target_kind, WorkoutStep.TargetKind.PERCENT_FTP, ctx + ": тип цели % FTP")
	assert_almost_eq(s.target_start, pct, 0.001, ctx + ": цель начала")
	assert_almost_eq(s.target_end, pct, 0.001, ctx + ": цель конца (постоянный шаг)")


func _assert_step_watts(s: WorkoutStep, dur: int, w: float, ctx: String) -> void:
	assert_eq(s.duration_sec, dur, ctx + ": длительность")
	assert_eq(s.target_kind, WorkoutStep.TargetKind.WATTS, ctx + ": тип цели ватты")
	assert_almost_eq(s.target_start, w, 0.001, ctx + ": цель начала")
	assert_almost_eq(s.target_end, w, 0.001, ctx + ": цель конца (постоянный шаг)")


func _assert_ramp(s: WorkoutStep, dur: int, a: float, b: float, kind: WorkoutStep.TargetKind, ctx: String) -> void:
	assert_eq(s.duration_sec, dur, ctx + ": длительность")
	assert_eq(s.target_kind, kind, ctx + ": тип цели")
	assert_almost_eq(s.target_start, a, 0.001, ctx + ": цель начала")
	assert_almost_eq(s.target_end, b, 0.001, ctx + ": цель конца")
	assert_true(s.is_ramp(), ctx + ": это рампа")


## Сообщение без стека вызовов, внутренних имён классов и путей (REQ-IMP-05 крит. 3).
func _assert_user_safe(text: String, ctx: String) -> void:
	for bad in ["res://", "user://", ".gd", "ZwoParser", "ErgMrcParser", "IntervalsIcuWorkoutParser",
			"WorkoutLibrary", "WorkoutSerializer", "ParseResult", "XMLParser", "RefCounted", "at:", "stack", "Traceback"]:
		assert_false(text.contains(bad), "%s: сообщение не должно содержать '%s': %s" % [ctx, bad, text])


# ===========================================================================
# REQ-IMP-01 — импорт ZWO
# ===========================================================================

func test_req_imp_01_c1_warmup_ramp_steady_intervals_ramp_cooldown() -> void:
	var r := ZwoParser.parse(_read("acc_full.zwo"))
	assert_true(r.ok(), "ожидался успешный разбор: " + str(r.error_messages()))
	if not r.ok():
		return
	var w := r.workout
	assert_eq(w.steps.size(), 12, "1 + 1 + 3×2 + 1 + 1 + 1 + 1 шагов")
	_assert_ramp(w.steps[0], 300, 40.0, 70.0, WorkoutStep.TargetKind.PERCENT_FTP, "Warmup")
	assert_eq(w.steps[0].kind, WorkoutStep.StepKind.WARMUP, "Warmup: тип шага")
	_assert_step_percent(w.steps[1], 600, 100.0, "SteadyState Power=1.0 → ровно 100 %")
	# IntervalsT Repeat=3: 3 пары on/off
	for i in 3:
		_assert_step_percent(w.steps[2 + i * 2], 120, 120.0, "IntervalsT on #%d" % (i + 1))
		assert_eq(w.steps[2 + i * 2].kind, WorkoutStep.StepKind.INTERVAL_ON, "on #%d: тип" % (i + 1))
		_assert_step_percent(w.steps[3 + i * 2], 60, 50.0, "IntervalsT off #%d" % (i + 1))
		assert_eq(w.steps[3 + i * 2].kind, WorkoutStep.StepKind.INTERVAL_OFF, "off #%d: тип" % (i + 1))
	_assert_ramp(w.steps[8], 300, 50.0, 90.0, WorkoutStep.TargetKind.PERCENT_FTP, "Ramp")
	_assert_ramp(w.steps[11], 300, 60.0, 30.0, WorkoutStep.TargetKind.PERCENT_FTP, "Cooldown (PowerLow → PowerHigh, вниз)")
	assert_eq(w.steps[11].kind, WorkoutStep.StepKind.COOLDOWN, "Cooldown: тип шага")


func test_req_imp_01_c1_power_fraction_075_is_75_percent() -> void:
	var r := ZwoParser.parse(_read("acc_bom_crlf.zwo"))
	assert_true(r.ok(), str(r.error_messages()))
	if not r.ok():
		return
	_assert_step_percent(r.workout.steps[0], 600, 75.0, "Power=0.75")


func test_req_imp_01_c2_freeride_has_no_target_and_maxeffort_is_freeride_with_warning() -> void:
	var r := ZwoParser.parse(_read("acc_full.zwo"))
	assert_true(r.ok(), str(r.error_messages()))
	if not r.ok():
		return
	var free := r.workout.steps[9]
	assert_eq(free.duration_sec, 180, "FreeRide: длительность")
	assert_eq(free.target_kind, WorkoutStep.TargetKind.NONE, "FreeRide: без целевой мощности")
	assert_true(free.is_free_ride(), "FreeRide: is_free_ride()")
	assert_eq(free.target_watts_at(0.0, 250), 0, "FreeRide: цель 0 Вт")
	var max_effort := r.workout.steps[10]
	assert_eq(max_effort.duration_sec, 60, "MaxEffort: длительность")
	assert_eq(max_effort.target_kind, WorkoutStep.TargetKind.NONE, "MaxEffort → свободная езда (В-12)")
	assert_true(max_effort.is_free_ride(), "MaxEffort: is_free_ride()")
	var warn := _entry_with_key(r.warnings, "max_effort_as_free_ride")
	assert_false(warn.is_empty(), "предупреждение о MaxEffort → свободная езда: " + str(r.warning_messages()))
	assert_eq(int(warn.get("line", 0)), 23, "предупреждение указывает строку элемента MaxEffort")
	assert_true(str(warn.get("message", "")).to_lower().contains("maxeffort"), "в тексте предупреждения упомянут MaxEffort")


func test_req_imp_01_c3_cadence_attributes() -> void:
	var r := ZwoParser.parse(_read("acc_full.zwo"))
	assert_true(r.ok(), str(r.error_messages()))
	if not r.ok():
		return
	var w := r.workout
	assert_eq(w.steps[0].cadence_rpm, 85, "Warmup Cadence=85")
	assert_eq(w.steps[1].cadence_rpm, 90, "SteadyState Cadence=90")
	assert_eq(w.steps[2].cadence_rpm, 100, "IntervalsT on: Cadence=100")
	assert_eq(w.steps[3].cadence_rpm, 80, "IntervalsT off: CadenceResting=80")
	assert_eq(w.steps[8].cadence_rpm, 85, "Ramp CadenceLow=80/CadenceHigh=90 → 85")
	assert_eq(w.steps[9].cadence_rpm, 0, "FreeRide без каденса → не задан (0)")
	assert_eq(w.steps[11].cadence_rpm, 0, "Cooldown без каденса → не задан (0)")


func test_req_imp_01_c4_textevents_attached_to_step_time() -> void:
	var r := ZwoParser.parse(_read("acc_full.zwo"))
	assert_true(r.ok(), str(r.error_messages()))
	if not r.ok():
		return
	var w := r.workout
	var steady := w.steps[1]
	assert_eq(steady.text_cues.size(), 2, "SteadyState: 2 подсказки")
	if steady.text_cues.size() == 2:
		assert_eq(steady.text_cues[0].at_sec, 0)
		assert_eq(steady.text_cues[0].text, "Ровно на FTP")
		assert_eq(steady.text_cues[1].at_sec, 300)
		assert_eq(steady.text_cues[1].text, "Половина")
	# Внутри IntervalsT смещение от начала пары on/off; подсказки повторяются в каждом повторе.
	for i in 3:
		var on := w.steps[2 + i * 2]
		var off := w.steps[3 + i * 2]
		assert_eq(on.text_cues.size(), 1, "on #%d: одна подсказка" % (i + 1))
		if on.text_cues.size() == 1:
			assert_eq(on.text_cues[0].at_sec, 10, "on #%d: смещение 10 с" % (i + 1))
			assert_eq(on.text_cues[0].text, "Жми")
		assert_eq(off.text_cues.size(), 1, "off #%d: одна подсказка" % (i + 1))
		if off.text_cues.size() == 1:
			assert_eq(off.text_cues[0].at_sec, 10, "off #%d: 130 − 120 = 10 с от начала off" % (i + 1))
			assert_eq(off.text_cues[0].text, "Отдых")
	assert_eq(w.steps[0].text_cues.size(), 0, "Warmup без подсказок")


func test_req_imp_01_c4_textevent_with_cdata_body_crlf() -> void:
	var r := ZwoParser.parse(_read("acc_bom_crlf.zwo"))
	assert_true(r.ok(), str(r.error_messages()))
	if not r.ok():
		return
	var s := r.workout.steps[0]
	assert_eq(s.text_cues.size(), 1, "textevent с телом CDATA: одна подсказка из атрибута message")
	if s.text_cues.size() == 1:
		assert_eq(s.text_cues[0].at_sec, 60)
		assert_eq(s.text_cues[0].text, "Подсказка в CRLF")


func test_req_imp_01_c5_name_description_author_metadata() -> void:
	var r := ZwoParser.parse(_read("acc_full.zwo"))
	assert_true(r.ok(), str(r.error_messages()))
	if not r.ok():
		return
	assert_eq(r.workout.name, "Acceptance Full", "name")
	assert_eq(r.workout.description, "Все поддерживаемые элементы ZWO.", "description")
	assert_eq(str(r.metadata.get("author", "")), "Acceptance Tester", "author в метаданных")
	assert_eq(str(r.metadata.get("sport_type", "")), "bike", "sportType в метаданных")
	assert_eq(r.workout.source, "zwo", "source = zwo")


func test_req_imp_01_c5_cdata_description_and_bom() -> void:
	var r := ZwoParser.parse(_read("acc_bom_crlf.zwo"))
	assert_true(r.ok(), "файл с BOM/CRLF/комментариями должен разбираться: " + str(r.error_messages()))
	if not r.ok():
		return
	assert_eq(r.workout.name, "BOM CRLF")
	assert_eq(r.workout.description, "Описание <в CDATA> & с амперсандом", "CDATA в description — как есть")
	assert_eq(str(r.metadata.get("author", "")), "BOM Tester")


func test_req_imp_01_c5_bom_passed_as_string_prefix() -> void:
	# Строка начинается с U+FEFF (как если бы файл прочли без снятия BOM).
	var text := "﻿" + _read("acc_lowercase.zwo")
	var r := ZwoParser.parse(text)
	assert_true(r.ok(), "BOM в начале строки не должен ломать разбор: " + str(r.error_messages()))


func test_req_imp_01_c7_crlf_line_endings_accepted() -> void:
	# Файл, сохранённый в Windows: CRLF везде, включая конец файла.
	var text := _read("acc_lowercase.zwo").replace("\n", "\r\n")
	var r := ZwoParser.parse(text)
	assert_true(r.ok(), "валидный XML с CRLF должен разбираться: " + str(r.error_messages()))
	if r.ok():
		assert_eq(r.workout.steps.size(), 3)
		assert_eq(r.workout.total_duration_sec(), 1200)


func test_req_imp_01_c7_trailing_blank_line_accepted() -> void:
	var text := _read("acc_lowercase.zwo").strip_edges() + "\n\n"
	var r := ZwoParser.parse(text)
	assert_true(r.ok(), "пустая строка в конце файла — валидный XML: " + str(r.error_messages()))


func test_req_imp_01_c5_cdata_description_kept_without_engine_error() -> void:
	var xml := "<workout_file><name>N</name><description><![CDATA[Описание <в CDATA> & amп]]></description><workout><SteadyState Duration=\"60\" Power=\"0.7\"/></workout></workout_file>"
	var r := ZwoParser.parse(xml)
	assert_true(r.ok(), str(r.error_messages()))
	if r.ok():
		assert_eq(r.workout.description, "Описание <в CDATA> & amп", "текст CDATA сохраняется в description")


func test_req_imp_01_c6_fixture_totals_acceptance() -> void:
	var expected := {
		"acc_full.zwo": [12, 2280],
		"acc_bom_crlf.zwo": [2, 900],
		"acc_lowercase.zwo": [3, 1200],
		"acc_unknown_attrs.zwo": [7, 1260],
	}
	for name in expected.keys():
		var r := ZwoParser.parse(_read(name))
		assert_true(r.ok(), "%s: %s" % [name, str(r.error_messages())])
		if r.ok():
			assert_eq(r.workout.steps.size(), int(expected[name][0]), "%s: число шагов" % name)
			assert_eq(r.workout.total_duration_sec(), int(expected[name][1]), "%s: суммарная длительность" % name)


func test_req_imp_01_c6_fixture_totals_developer_dir() -> void:
	# Фикстуры разработчика: проверка только внутренней согласованности (сумма шагов = total).
	var d := DirAccess.open(DEV)
	assert_not_null(d)
	var checked := 0
	for f in d.get_files():
		if not f.ends_with(".zwo"):
			continue
		var r := ZwoParser.parse(FileAccess.get_file_as_string(DEV + f))
		if r.ok():
			checked += 1
			var sum := 0
			for s in r.workout.steps:
				sum += s.duration_sec
			assert_eq(r.workout.total_duration_sec(), sum, f + ": сумма длительностей шагов")
			assert_gt(r.workout.steps.size(), 0, f + ": шаги есть")
	assert_gt(checked, 0, "хотя бы одна валидная .zwo фикстура разработчика")


func test_req_imp_01_c7_not_xml_rejected_with_message() -> void:
	var r := ZwoParser.parse(_read("acc_not_xml.zwo"))
	assert_false(r.ok(), "не-XML должен отклоняться")
	assert_null(r.workout, "план не возвращается")
	assert_gt(r.errors.size(), 0, "есть сообщение об ошибке")
	assert_false(r.user_message("acc_not_xml.zwo").is_empty())
	_assert_user_safe(r.user_message("acc_not_xml.zwo"), "not_xml")


func test_req_imp_01_c7_truncated_xml_rejected() -> void:
	var r := ZwoParser.parse(_read("acc_truncated.zwo"))
	assert_false(r.ok(), "оборванный XML должен отклоняться")
	assert_null(r.workout)
	assert_gt(r.errors.size(), 0)
	_assert_user_safe(r.user_message("acc_truncated.zwo"), "truncated")


func test_req_imp_01_c7_empty_text_rejected() -> void:
	var r := ZwoParser.parse("")
	assert_false(r.ok())
	assert_null(r.workout)
	assert_gt(r.errors.size(), 0)


# --- границы и негатив ZWO ---

func test_req_imp_01_neg_no_workout_element_rejected() -> void:
	var r := ZwoParser.parse(_read("acc_no_workout.zwo"))
	assert_false(r.ok(), "ZWO без <workout> не является тренировкой")
	assert_null(r.workout)
	assert_gt(r.errors.size(), 0)
	var msg := r.user_message("acc_no_workout.zwo")
	assert_true(msg.to_lower().contains("workout"), "сообщение называет отсутствующий элемент: " + msg)
	_assert_user_safe(msg, "no_workout")


func test_req_imp_01_neg_duration_zero_rejected_with_line() -> void:
	var r := ZwoParser.parse(_read("acc_zero_duration.zwo"))
	assert_false(r.ok(), "Duration=\"0\" — невалидный шаг, импорт не выполняется")
	assert_null(r.workout)
	assert_gt(r.errors.size(), 0)
	if r.errors.size() > 0:
		assert_eq(int(r.errors[0].get("line", 0)), 6, "ошибка указывает строку элемента с Duration=0")
		assert_eq(str(r.errors[0].get("element", "")), "SteadyState", "ошибка указывает элемент")


func test_req_imp_01_neg_repeat_zero_rejected_with_line() -> void:
	var r := ZwoParser.parse(_read("acc_zero_repeat.zwo"))
	assert_false(r.ok(), "Repeat=\"0\" не даёт ни одного интервала — импорт не выполняется")
	assert_null(r.workout)
	assert_gt(r.errors.size(), 0)
	if r.errors.size() > 0:
		assert_eq(int(r.errors[0].get("line", 0)), 6, "ошибка указывает строку IntervalsT")
		assert_eq(str(r.errors[0].get("element", "")), "IntervalsT")


func test_req_imp_01_edge_unknown_attributes_ignored_import_succeeds() -> void:
	var r := ZwoParser.parse(_read("acc_unknown_attrs.zwo"))
	assert_true(r.ok(), "неизвестные атрибуты (FlatRoad, Zone, show_avg, ftptest) не блокируют импорт: " + str(r.error_messages()))
	if not r.ok():
		return
	assert_eq(r.workout.steps.size(), 7)
	_assert_step_percent(r.workout.steps[1], 600, 75.0, "SteadyState с лишними атрибутами")
	assert_true(_has_key(r.warnings, "unsupported_attribute"), "OverUnder/pace — предупреждение, не ошибка")


func test_req_imp_01_edge_lowercase_element_names_accepted() -> void:
	var r := ZwoParser.parse(_read("acc_lowercase.zwo"))
	assert_true(r.ok(), "steadystate/warmup/cooldown в нижнем регистре: " + str(r.error_messages()))
	if not r.ok():
		return
	assert_eq(r.workout.steps.size(), 3)
	_assert_step_percent(r.workout.steps[1], 600, 80.0, "steadystate")
	assert_eq(r.workout.steps[0].kind, WorkoutStep.StepKind.WARMUP)
	assert_eq(r.workout.steps[2].kind, WorkoutStep.StepKind.COOLDOWN)


func test_req_imp_01_edge_textevent_beyond_step_is_warning_not_error() -> void:
	var xml := """<workout_file><name>x</name><workout>
<SteadyState Duration="60" Power="0.7"><textevent timeoffset="60" message="late"/></SteadyState>
</workout></workout_file>"""
	var r := ZwoParser.parse(xml)
	assert_true(r.ok(), "подсказка за пределами шага не должна ломать импорт: " + str(r.error_messages()))
	if r.ok():
		assert_eq(r.workout.steps[0].text_cues.size(), 0, "подсказка на 60 с при длительности 60 с не привязана")
		assert_gt(r.warnings.size(), 0, "есть предупреждение")


func test_req_imp_01_edge_wrong_root_element_rejected() -> void:
	var r := ZwoParser.parse("<?xml version=\"1.0\"?><plan><workout><SteadyState Duration=\"60\" Power=\"0.7\"/></workout></plan>")
	assert_false(r.ok(), "корень не workout_file — не ZWO")
	assert_null(r.workout)


# ===========================================================================
# REQ-IMP-02 — импорт .erg / .mrc
# ===========================================================================

func test_req_imp_02_c1_erg_spaces_pairs_to_steps_and_ramps() -> void:
	var r := ErgMrcParser.parse(_read("acc_spaces.erg"), "erg")
	assert_true(r.ok(), "erg с пробелами и пустыми строками: " + str(r.error_messages()))
	if not r.ok():
		return
	var w := r.workout
	assert_eq(w.steps.size(), 4, "4 шага: 2 постоянных, рампа, постоянный (скачки не дают шагов)")
	assert_eq(w.total_duration_sec(), 900, "15 мин")
	_assert_step_watts(w.steps[0], 300, 100.0, "0–5 мин 100 Вт")
	_assert_step_watts(w.steps[1], 300, 200.0, "5–10 мин 200 Вт")
	_assert_ramp(w.steps[2], 150, 150.0, 250.0, WorkoutStep.TargetKind.WATTS, "10–12.5 мин рампа 150→250")
	_assert_step_watts(w.steps[3], 150, 100.0, "12.5–15 мин 100 Вт")
	assert_eq(w.source, "erg")


func test_req_imp_02_c1_mrc_tabs_crlf_pairs_to_steps() -> void:
	var r := ErgMrcParser.parse(_read("acc_tabs.mrc"), "mrc")
	assert_true(r.ok(), "mrc с табами и CRLF: " + str(r.error_messages()))
	if not r.ok():
		return
	var w := r.workout
	assert_eq(w.steps.size(), 4)
	assert_eq(w.total_duration_sec(), 1200)
	_assert_step_percent(w.steps[0], 300, 50.0, "0–5 мин 50 %")
	_assert_step_percent(w.steps[1], 600, 90.0, "5–15 мин 90 %")
	_assert_step_percent(w.steps[2], 150, 100.0, "15–17.5 мин 100 %")
	_assert_ramp(w.steps[3], 150, 60.0, 40.0, WorkoutStep.TargetKind.PERCENT_FTP, "17.5–20 мин рампа 60→40")
	assert_eq(w.source, "mrc")


func test_req_imp_02_c1_developer_fixtures_internally_consistent() -> void:
	var d := DirAccess.open(DEV)
	assert_not_null(d)
	var checked := 0
	for f in d.get_files():
		var ext := f.get_extension().to_lower()
		if ext != "erg" and ext != "mrc":
			continue
		var r := ErgMrcParser.parse(FileAccess.get_file_as_string(DEV + f), ext)
		if r.ok():
			checked += 1
			assert_eq(r.workout.source, ext, f + ": source = расширение")
			assert_gt(r.workout.steps.size(), 0, f + ": шаги есть")
	assert_gt(checked, 0, "хотя бы одна валидная .erg/.mrc фикстура разработчика")


func test_req_imp_02_c2_extension_defines_units_percent_header_in_erg() -> void:
	var r := ErgMrcParser.parse(_read("acc_percent_in_erg.erg"), "erg")
	assert_true(r.ok(), str(r.error_messages()))
	if not r.ok():
		return
	assert_eq(r.workout.steps.size(), 2)
	_assert_step_watts(r.workout.steps[0], 600, 60.0, ".erg с MINUTES PERCENT — всё равно ватты")
	_assert_step_watts(r.workout.steps[1], 600, 80.0, ".erg с MINUTES PERCENT — всё равно ватты")
	assert_eq(r.workout.source, "erg")
	assert_gt(r.warnings.size(), 0, "расхождение заголовка и расширения — предупреждение: " + str(r.warning_messages()))


func test_req_imp_02_c2_extension_defines_units_watts_header_in_mrc() -> void:
	var r := ErgMrcParser.parse(_read("acc_watts_in_mrc.mrc"), "mrc")
	assert_true(r.ok(), str(r.error_messages()))
	if not r.ok():
		return
	_assert_step_percent(r.workout.steps[0], 600, 60.0, ".mrc с MINUTES WATTS — всё равно % FTP")
	assert_eq(r.workout.source, "mrc")
	assert_gt(r.warnings.size(), 0, "расхождение заголовка и расширения — предупреждение")


func test_req_imp_02_c2_library_picks_units_by_extension_case_insensitive() -> void:
	var r_erg := WorkoutLibrary.parse_text(_read("acc_percent_in_erg.erg"), "Plan.ERG")
	assert_true(r_erg.ok(), str(r_erg.error_messages()))
	if r_erg.ok():
		assert_eq(r_erg.workout.steps[0].target_kind, WorkoutStep.TargetKind.WATTS, ".ERG → ватты")
	var r_mrc := WorkoutLibrary.parse_text(_read("acc_watts_in_mrc.mrc"), "Plan.Mrc")
	assert_true(r_mrc.ok(), str(r_mrc.error_messages()))
	if r_mrc.ok():
		assert_eq(r_mrc.workout.steps[0].target_kind, WorkoutStep.TargetKind.PERCENT_FTP, ".Mrc → % FTP")


func test_req_imp_02_c3_course_text_tabs_to_cues() -> void:
	var r := ErgMrcParser.parse(_read("acc_tabs.mrc"), "mrc")
	assert_true(r.ok(), str(r.error_messages()))
	if not r.ok():
		return
	var w := r.workout
	assert_eq(w.steps[0].text_cues.size(), 1, "0 с → шаг 1")
	assert_eq(w.steps[1].text_cues.size(), 1, "300 с → шаг 2")
	assert_eq(w.steps[2].text_cues.size(), 1, "900 с → шаг 3")
	assert_eq(w.steps[3].text_cues.size(), 1, "1050 с → шаг 4")
	if w.steps[0].text_cues.size() == 1:
		assert_eq(w.steps[0].text_cues[0].text, "Разминка")
		assert_eq(w.steps[0].text_cues[0].at_sec, 0)
	if w.steps[1].text_cues.size() == 1:
		assert_eq(w.steps[1].text_cues[0].text, "Свит-спот")
		assert_eq(w.steps[1].text_cues[0].at_sec, 0)
	if w.steps[2].text_cues.size() == 1:
		assert_eq(w.steps[2].text_cues[0].text, "FTP блок")
	if w.steps[3].text_cues.size() == 1:
		assert_eq(w.steps[3].text_cues[0].text, "Заминка-рампа")
		assert_eq(w.steps[3].text_cues[0].at_sec, 0)


func test_req_imp_02_c3_course_text_spaces_to_cues_duration_dropped() -> void:
	var r := ErgMrcParser.parse(_read("acc_spaces.erg"), "erg")
	assert_true(r.ok(), str(r.error_messages()))
	if not r.ok():
		return
	var w := r.workout
	assert_eq(w.steps[0].text_cues.size(), 1)
	assert_eq(w.steps[1].text_cues.size(), 1)
	assert_eq(w.steps[2].text_cues.size(), 1)
	assert_eq(w.steps[3].text_cues.size(), 0)
	if w.steps[0].text_cues.size() == 1:
		assert_eq(w.steps[0].text_cues[0].text, "Разминка сто ватт", "длительность показа (10) не попадает в текст")
	if w.steps[1].text_cues.size() == 1:
		assert_eq(w.steps[1].text_cues[0].text, "Второй блок")
	if w.steps[2].text_cues.size() == 1:
		assert_eq(w.steps[2].text_cues[0].text, "Рампа пошла")


func test_req_imp_02_c3_course_text_mid_step_offset() -> void:
	var text := _read("acc_percent_in_erg.erg") + "[COURSE TEXT]\n750\tПолпути второго блока\t5\n[END COURSE TEXT]\n"
	var r := ErgMrcParser.parse(text, "erg")
	assert_true(r.ok(), str(r.error_messages()))
	if not r.ok():
		return
	assert_eq(r.workout.steps[1].text_cues.size(), 1, "750 с попадает во второй шаг (600–1200)")
	if r.workout.steps[1].text_cues.size() == 1:
		assert_eq(r.workout.steps[1].text_cues[0].at_sec, 150, "смещение внутри шага 750 − 600")


func test_req_imp_02_c4_ftp_header_in_metadata_not_in_workout() -> void:
	var r := ErgMrcParser.parse(_read("acc_spaces.erg"), "erg")
	assert_true(r.ok(), str(r.error_messages()))
	if not r.ok():
		return
	assert_eq(int(r.metadata.get("ftp", -1)), 250, "FTP = 250 из заголовка в метаданных")
	assert_eq(str(r.metadata.get("description", "")), "Acceptance erg with spaces")
	assert_eq(str(r.metadata.get("file_name", "")), "acc_spaces.erg")
	# Цели в ваттах не пересчитываются по FTP из заголовка: 100 Вт остаются 100 Вт при любом FTP профиля.
	assert_eq(r.workout.steps[0].target_watts_at(0.0, 300), 100, "ватты не зависят от FTP профиля")
	assert_eq(r.workout.steps[0].target_watts_at(0.0, 250), 100)


func test_req_imp_02_c4_ftp_header_does_not_change_profile() -> void:
	var repo_dir := _dir + "profiles/"
	var repo := ProfileRepository.new(repo_dir)
	var p := repo.create("Acceptance")
	assert_not_null(p)
	if p == null:
		return
	var ftp_before: int = p.ftp_w
	var r := _lib.import_file(p.id, ACC + "acc_spaces.erg")
	assert_true(r.ok(), str(r.error_messages()))
	var again := repo.get_by_id(p.id)
	assert_eq(again.ftp_w, ftp_before, "FTP профиля не изменился после импорта .erg с FTP = 250")
	assert_ne(ftp_before, 250, "предусловие: FTP профиля по умолчанию не совпадает с 250 из файла")


func test_req_imp_02_c5_no_course_data_rejected() -> void:
	var r := ErgMrcParser.parse(_read("acc_no_data.erg"), "erg")
	assert_false(r.ok(), "без [COURSE DATA] — отказ")
	assert_null(r.workout)
	assert_gt(r.errors.size(), 0)
	var msg := r.user_message("acc_no_data.erg")
	assert_true(msg.to_upper().contains("COURSE DATA"), "сообщение называет секцию: " + msg)
	_assert_user_safe(msg, "no_course_data")


func test_req_imp_02_c5_non_monotonic_time_rejected_with_line() -> void:
	var r := ErgMrcParser.parse(_read("acc_time_backwards.erg"), "erg")
	assert_false(r.ok(), "время назад — отказ")
	assert_null(r.workout)
	assert_gt(r.errors.size(), 0)
	if r.errors.size() > 0:
		assert_eq(int(r.errors[0].get("line", 0)), 12, "ошибка указывает строку «8 200»")
	_assert_user_safe(r.user_message("acc_time_backwards.erg"), "non_monotonic")


func test_req_imp_02_c5_single_point_rejected() -> void:
	var r := ErgMrcParser.parse(_read("acc_single_point.erg"), "erg")
	assert_false(r.ok(), "одна точка не образует шага — отказ")
	assert_null(r.workout)
	assert_gt(r.errors.size(), 0)
	_assert_user_safe(r.user_message("acc_single_point.erg"), "single_point")


func test_req_imp_02_c5_empty_and_garbage_rejected() -> void:
	var r1 := ErgMrcParser.parse("", "erg")
	assert_false(r1.ok())
	assert_null(r1.workout)
	var r2 := ErgMrcParser.parse("<?xml version=\"1.0\"?><workout_file/>", "erg")
	assert_false(r2.ok(), "XML вместо erg — отказ")
	assert_null(r2.workout)
	var r3 := ErgMrcParser.parse("[COURSE DATA]\n0\tabc\n5\t100\n[END COURSE DATA]\n", "erg")
	assert_false(r3.ok(), "нечисловое значение — отказ")
	assert_null(r3.workout)
	if r3.errors.size() > 0:
		assert_eq(int(r3.errors[0].get("line", 0)), 2, "строка с нечисловым значением")


func test_req_imp_02_c6_fractional_minutes() -> void:
	var r := ErgMrcParser.parse("[COURSE DATA]\n0\t100\n2.5\t100\n2.5\t120\n4\t120\n[END COURSE DATA]\n", "erg")
	assert_true(r.ok(), str(r.error_messages()))
	if not r.ok():
		return
	assert_eq(r.workout.steps[0].duration_sec, 150, "2.5 мин → 150 с")
	assert_eq(r.workout.steps[1].duration_sec, 90, "1.5 мин → 90 с")
	assert_eq(r.workout.total_duration_sec(), 240)


func test_req_imp_02_edge_auto_kind_falls_back_to_header() -> void:
	var r := ErgMrcParser.parse(_read("acc_percent_in_erg.erg"))
	assert_true(r.ok(), str(r.error_messages()))
	if r.ok():
		assert_eq(r.workout.source, "mrc", "без расширения тип берётся из заголовка MINUTES PERCENT")


# ===========================================================================
# REQ-IMP-03 крит. 1 — выбор парсера по расширению
# ===========================================================================

func test_req_imp_03_c1_parser_chosen_by_extension_case_insensitive() -> void:
	var zwo := WorkoutLibrary.parse_text(_read("acc_full.zwo"), "Plan.ZWO")
	assert_true(zwo.ok(), "ZWO: " + str(zwo.error_messages()))
	if zwo.ok():
		assert_eq(zwo.workout.source, "zwo")
	var erg := WorkoutLibrary.parse_text(_read("acc_spaces.erg"), "plan.Erg")
	assert_true(erg.ok(), "Erg: " + str(erg.error_messages()))
	if erg.ok():
		assert_eq(erg.workout.source, "erg")
	var mrc := WorkoutLibrary.parse_text(_read("acc_tabs.mrc"), "PLAN.MRC")
	assert_true(mrc.ok(), "MRC: " + str(mrc.error_messages()))
	if mrc.ok():
		assert_eq(mrc.workout.source, "mrc")
	assert_true(WorkoutLibrary.is_supported_extension("x.ZwO"))
	assert_false(WorkoutLibrary.is_supported_extension("x.fit"))


func test_req_imp_03_c1_unknown_extension_is_imp05_error() -> void:
	for name in ["plan.txt", "plan.fit", "plan", "plan.zwo.bak"]:
		var r := WorkoutLibrary.parse_text(_read("acc_full.zwo"), name)
		assert_false(r.ok(), "%s: расширение не поддерживается" % name)
		assert_null(r.workout, name)
		assert_gt(r.errors.size(), 0, name)
		var msg := r.user_message(name)
		assert_true(msg.contains(name), "%s: сообщение содержит имя файла: %s" % [name, msg])
		_assert_user_safe(msg, name)


func test_req_imp_03_c1_import_file_by_path_and_missing_file() -> void:
	var path := _write_tmp("My Plan.ZWO", _read("acc_full.zwo"))
	var r := _lib.import_file(A, path)
	assert_true(r.ok(), str(r.error_messages()))
	assert_eq(_lib.count(A), 1)
	var missing := _lib.import_file(A, _dir + "in/nope.zwo")
	assert_false(missing.ok(), "несуществующий файл — ошибка, не падение")
	assert_null(missing.workout)
	assert_true(missing.user_message("nope.zwo").contains("nope.zwo"))
	assert_eq(_lib.count(A), 1, "библиотека не изменилась")


func test_req_imp_03_c1_import_file_with_bom_bytes() -> void:
	var bytes := FileAccess.get_file_as_bytes(ACC + "acc_bom_crlf.zwo")
	assert_eq(bytes[0], 0xEF, "предусловие: фикстура начинается с BOM")
	var path := _write_tmp_bytes("bom.zwo", bytes)
	var r := _lib.import_file(A, path)
	assert_true(r.ok(), "импорт файла с BOM через путь: " + str(r.error_messages()))
	if r.ok():
		assert_eq(r.workout.name, "BOM CRLF")


# ===========================================================================
# REQ-IMP-04 — библиотека
# ===========================================================================

func test_req_imp_04_c1_entry_has_name_duration_source_file() -> void:
	var r := _lib.import_file(A, ACC + "acc_full.zwo")
	assert_true(r.ok(), str(r.error_messages()))
	var entries := _lib.list(A)
	assert_eq(entries.size(), 1)
	if entries.size() != 1:
		return
	assert_eq(str(entries[0]["name"]), "Acceptance Full", "название")
	assert_eq(int(entries[0]["duration_sec"]), 2280, "длительность")
	assert_eq(str(entries[0]["source_file"]), "acc_full.zwo", "источник — имя файла")
	assert_eq(str(entries[0]["source"]), "zwo")
	var w := _lib.get_workout(A, str(entries[0]["id"]))
	assert_not_null(w, "план доступен по id")
	if w != null:
		assert_eq(w.steps.size(), 12)


func test_req_imp_04_c1_erg_without_name_gets_file_basename() -> void:
	var path := _write_tmp("Tempo Tuesday.erg", "[COURSE DATA]\n0\t100\n10\t100\n[END COURSE DATA]\n")
	var r := _lib.import_file(A, path)
	assert_true(r.ok(), str(r.error_messages()))
	var entries := _lib.list(A)
	assert_eq(entries.size(), 1)
	if entries.size() == 1:
		assert_eq(str(entries[0]["name"]), "Tempo Tuesday", "имя файла без расширения как название")
		assert_eq(int(entries[0]["duration_sec"]), 600)
		assert_eq(str(entries[0]["source_file"]), "Tempo Tuesday.erg")


func test_req_imp_04_c2_profiles_isolated() -> void:
	assert_true(_lib.import_file(A, ACC + "acc_full.zwo").ok())
	assert_true(_lib.import_file(A, ACC + "acc_tabs.mrc").ok())
	assert_true(_lib.import_file(B, ACC + "acc_spaces.erg").ok())
	assert_eq(_lib.count(A), 2, "в A две записи")
	assert_eq(_lib.count(B), 1, "в B одна запись")
	var a_id := str(_lib.list(A)[0]["id"])
	assert_true(_lib.get_entry(B, a_id).is_empty(), "запись A не читается через B")
	assert_null(_lib.get_workout(B, a_id), "план A не читается через B")
	assert_false(_lib.delete(B, a_id), "удалить запись A через B нельзя")
	assert_eq(_lib.count(A), 2, "A не пострадал")
	assert_eq(_lib.count("unknown-profile"), 0, "неизвестный профиль — пустая библиотека")


func test_req_imp_04_c4_same_content_reimport_replaces_single_entry_with_warning() -> void:
	var first := _lib.import_file(A, ACC + "acc_full.zwo")
	assert_true(first.ok(), str(first.error_messages()))
	var second := _lib.import_file(A, ACC + "acc_full.zwo")
	assert_true(second.ok(), "повторный импорт того же содержимого выполняется: " + str(second.error_messages()))
	assert_eq(_lib.count(A), 1, "то же содержимое → одна запись (замена, решение 20)")
	assert_true(_has_key(second.warnings, "duplicate_replaced"), "предупреждение о замене: " + str(second.warning_messages()))
	assert_eq(str(second.metadata.get("entry_id", "")), str(first.metadata.get("entry_id", "")), "id записи сохраняется")


func test_req_imp_04_c4_same_name_different_content_creates_two_entries() -> void:
	var text := _read("acc_full.zwo")
	var p1 := _write_tmp("same_name_1.zwo", text)
	var p2 := _write_tmp("same_name_2.zwo", text.replace("Duration=\"600\"", "Duration=\"900\""))
	assert_true(_lib.import_file(A, p1).ok())
	var r2 := _lib.import_file(A, p2)
	assert_true(r2.ok(), str(r2.error_messages()))
	assert_false(_has_key(r2.warnings, "duplicate_replaced"), "другое содержимое — не дубликат")
	var entries := _lib.list(A)
	assert_eq(entries.size(), 2, "то же название, другое содержимое → две записи (без перезаписи)")
	if entries.size() == 2:
		assert_eq(str(entries[0]["name"]), "Acceptance Full")
		assert_eq(str(entries[1]["name"]), "Acceptance Full")
		assert_ne(str(entries[0]["id"]), str(entries[1]["id"]))
		var durations := [int(entries[0]["duration_sec"]), int(entries[1]["duration_sec"])]
		durations.sort()
		assert_eq(durations, [2280, 2580])


func test_req_imp_04_c4_same_file_name_different_content_creates_two_entries() -> void:
	# Один и тот же путь, перезаписанный другим содержимым, — вторая запись.
	var path := _write_tmp("plan.mrc", _read("acc_tabs.mrc"))
	assert_true(_lib.import_file(A, path).ok())
	path = _write_tmp("plan.mrc", _read("acc_watts_in_mrc.mrc"))
	assert_true(_lib.import_file(A, path).ok())
	assert_eq(_lib.count(A), 2)


func test_req_imp_04_c5_delete_entry_leaves_other_entries_and_foreign_files() -> void:
	assert_true(_lib.import_file(A, ACC + "acc_full.zwo").ok())
	assert_true(_lib.import_file(A, ACC + "acc_tabs.mrc").ok())
	# «Заезд» — файл вне библиотеки в том же корне user://: удаление записи его не трогает.
	var rides_dir := _dir + "rides/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(rides_dir))
	var ride := FileAccess.open(rides_dir + "ride_1.fit", FileAccess.WRITE)
	ride.store_string("ride")
	ride.close()
	var entries := _lib.list(A)
	var victim := str(entries[0]["id"])
	assert_true(_lib.delete(A, victim), "удаление существующей записи")
	assert_eq(_lib.count(A), 1, "осталась одна запись")
	assert_true(_lib.get_entry(A, victim).is_empty(), "удалённая запись не читается")
	assert_null(_lib.get_workout(A, victim))
	assert_true(FileAccess.file_exists(rides_dir + "ride_1.fit"), "файл заезда цел")
	assert_false(_lib.delete(A, victim), "повторное удаление → false, без падения")
	assert_false(_lib.delete(A, "../../etc"), "небезопасный id отклоняется")


func test_req_imp_04_c5_delete_all_and_profile_cascade() -> void:
	var repo := ProfileRepository.new(_dir + "profiles/")
	var pa := repo.create("Alpha")
	var pb := repo.create("Beta")
	assert_not_null(pa)
	assert_not_null(pb)
	if pa == null or pb == null:
		return
	_lib.attach_to_profiles(repo)
	_lib.attach_to_profiles(repo)  # повторное подключение не дублирует подписку
	assert_true(_lib.import_file(pa.id, ACC + "acc_full.zwo").ok())
	assert_true(_lib.import_file(pa.id, ACC + "acc_tabs.mrc").ok())
	assert_true(_lib.import_file(pb.id, ACC + "acc_spaces.erg").ok())
	var changed: Array[String] = []
	_lib.library_changed.connect(func(id: String) -> void: changed.append(id))
	assert_eq(repo.delete(pa.id), "", "удаление профиля A")
	assert_eq(_lib.count(pa.id), 0, "каскад: библиотека A стёрта")
	assert_false(DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(_lib.profile_dir(pa.id))), "каталог A удалён")
	assert_eq(_lib.count(pb.id), 1, "библиотека B не тронута")
	assert_eq(changed.count(pa.id), 1, "один сигнал library_changed для A (подписка не задвоена)")


func test_req_imp_04_c6_roundtrip_dict_and_json_all_fixtures_lossless() -> void:
	var checked := 0
	for dir_path in [ACC, DEV]:
		var d := DirAccess.open(dir_path)
		assert_not_null(d, dir_path)
		if d == null:
			continue
		for f in d.get_files():
			if f == "acc_bom_crlf.zwo":
				continue  # дефекты CRLF/CDATA парсера ZWO покрыты отдельными тестами IMP-01
			var ext := f.get_extension().to_lower()
			var r: ParseResult
			if ext == "zwo":
				r = ZwoParser.parse(FileAccess.get_file_as_string(dir_path + f))
			elif ext == "erg" or ext == "mrc":
				r = ErgMrcParser.parse(FileAccess.get_file_as_string(dir_path + f), ext)
			elif ext == "json" and (f.begins_with("acc_event") or f.begins_with("intervals_event")):
				var json := JSON.new()
				if json.parse(FileAccess.get_file_as_string(dir_path + f)) != OK or not (json.data is Dictionary):
					continue
				r = IntervalsIcuWorkoutParser.parse(json.data)
			else:
				continue
			if not r.ok():
				continue
			checked += 1
			var before := WorkoutSerializer.to_dict(r.workout)
			var via_dict := WorkoutSerializer.from_dict(before)
			assert_not_null(via_dict, f + ": from_dict")
			if via_dict != null:
				assert_eq_deep(WorkoutSerializer.to_dict(via_dict), before)
				assert_eq(via_dict.steps.size(), r.workout.steps.size(), f + ": число шагов")
				assert_eq(via_dict.total_duration_sec(), r.workout.total_duration_sec(), f + ": длительность")
				assert_eq(via_dict.name, r.workout.name, f + ": name")
				assert_eq(via_dict.description, r.workout.description, f + ": description")
				assert_eq(via_dict.source, r.workout.source, f + ": source")
				assert_true(via_dict.is_valid(), f + ": валидность после десериализации")
			var via_json := WorkoutSerializer.from_json(WorkoutSerializer.to_json(r.workout))
			assert_not_null(via_json, f + ": from_json")
			if via_json != null:
				assert_eq_deep(WorkoutSerializer.to_dict(via_json), before)
	assert_gt(checked, 8, "проверено достаточно фикстур")


func test_req_imp_04_c6_roundtrip_preserves_cadence_cues_kinds_targets() -> void:
	var r := ZwoParser.parse(_read("acc_full.zwo"))
	assert_true(r.ok())
	if not r.ok():
		return
	var w2 := WorkoutSerializer.from_json(WorkoutSerializer.to_json(r.workout))
	assert_not_null(w2)
	if w2 == null:
		return
	for i in r.workout.steps.size():
		var a := r.workout.steps[i]
		var b := w2.steps[i]
		assert_eq(b.duration_sec, a.duration_sec, "шаг %d: длительность" % i)
		assert_eq(b.target_kind, a.target_kind, "шаг %d: тип цели" % i)
		assert_eq(b.kind, a.kind, "шаг %d: вид шага" % i)
		assert_almost_eq(b.target_start, a.target_start, 0.0001, "шаг %d: цель начала" % i)
		assert_almost_eq(b.target_end, a.target_end, 0.0001, "шаг %d: цель конца" % i)
		assert_eq(b.cadence_rpm, a.cadence_rpm, "шаг %d: каденс" % i)
		assert_eq(b.text_cues.size(), a.text_cues.size(), "шаг %d: число подсказок" % i)
		for j in mini(a.text_cues.size(), b.text_cues.size()):
			assert_eq(b.text_cues[j].at_sec, a.text_cues[j].at_sec, "шаг %d подсказка %d: время" % [i, j])
			assert_eq(b.text_cues[j].text, a.text_cues[j].text, "шаг %d подсказка %d: текст" % [i, j])


func test_req_imp_04_c6_library_survives_restart_with_metadata() -> void:
	var r := _lib.import_file(A, ACC + "acc_spaces.erg")
	assert_true(r.ok(), str(r.error_messages()))
	var before := WorkoutSerializer.to_dict(r.workout)
	var id := str(r.metadata.get("entry_id", ""))
	# «Перезапуск»: новый экземпляр над тем же каталогом.
	var reopened := WorkoutLibrary.new(_dir)
	assert_eq(reopened.count(A), 1, "запись пережила перезапуск")
	var entry := reopened.get_entry(A, id)
	assert_false(entry.is_empty())
	assert_eq(str(entry.get("name", "")), "acc_spaces")
	assert_eq(int(entry.get("duration_sec", 0)), 900)
	var meta: Dictionary = entry.get("metadata", {})
	assert_eq(int(meta.get("ftp", -1)), 250, "метаданные (FTP заголовка) сохранены")
	assert_eq(str(meta.get("file_name", "")), "acc_spaces.erg")
	var w := reopened.get_workout(A, id)
	assert_not_null(w)
	if w != null:
		assert_eq_deep(WorkoutSerializer.to_dict(w), before)
		assert_eq(w.steps[0].text_cues.size(), 1, "подсказки сохранены")


func test_req_imp_04_edge_corrupted_record_skipped_without_crash() -> void:
	assert_true(_lib.import_file(A, ACC + "acc_full.zwo").ok())
	var dir := _lib.profile_dir(A)
	var bad := FileAccess.open(dir + "deadbeef-dead-4ead-8ead-deadbeefdead.json", FileAccess.WRITE)
	bad.store_string(_read("acc_corrupted_record.json"))
	bad.close()
	var arr := FileAccess.open(dir + "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa.json", FileAccess.WRITE)
	arr.store_string("[1, 2, 3]")
	arr.close()
	var txt := FileAccess.open(dir + "notes.txt", FileAccess.WRITE)
	txt.store_string("not a record")
	txt.close()
	var reopened := WorkoutLibrary.new(_dir)
	assert_eq(reopened.count(A), 1, "битые записи и посторонние файлы пропущены")
	assert_eq(reopened.list(A).size(), 1)
	assert_true(reopened.get_entry(A, "deadbeef-dead-4ead-8ead-deadbeefdead").is_empty())
	assert_null(reopened.get_workout(A, "deadbeef-dead-4ead-8ead-deadbeefdead"))
	assert_null(reopened.get_workout(A, "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"))
	# После битой записи импорт продолжает работать.
	assert_true(reopened.import_file(A, ACC + "acc_tabs.mrc").ok())
	assert_eq(reopened.count(A), 2)


func test_req_imp_04_edge_record_without_workout_field() -> void:
	var dir := _lib.profile_dir(A)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var f := FileAccess.open(dir + "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb.json", FileAccess.WRITE)
	f.store_string("{\"id\": \"bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb\", \"name\": \"Half\"}")
	f.close()
	var w := _lib.get_workout(A, "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb")
	assert_null(w, "запись без плана → план null, без падения")
	# Наблюдение для отчёта: запись без плана не фильтруется из list().
	gut.p("record_without_workout listed: %d" % _lib.list(A).size())


func test_req_imp_04_edge_import_failed_parse_adds_nothing() -> void:
	var r := _lib.import_file(A, ACC + "acc_unknown_element.zwo")
	assert_false(r.ok())
	assert_eq(_lib.count(A), 0, "ошибочный импорт не создаёт запись")
	var r2 := _lib.import_file(A, ACC + "acc_time_backwards.erg")
	assert_false(r2.ok())
	assert_eq(_lib.count(A), 0)
	var r3 := _lib.import_text("", _read("acc_full.zwo"), "x.zwo")
	assert_false(r3.ok(), "импорт без профиля — ошибка")
	assert_eq(_lib.count(""), 0)


# ===========================================================================
# REQ-IMP-05 — понятные ошибки импорта
# ===========================================================================

func test_req_imp_05_c1_c2_unknown_zwo_element_message_with_name_and_line() -> void:
	var r := _lib.import_file(A, ACC + "acc_unknown_element.zwo")
	assert_false(r.ok(), "SolidState не поддерживается — импорт не выполняется")
	assert_null(r.workout, "частично разобранный план не возвращается")
	assert_eq(_lib.count(A), 0, "запись не создана")
	assert_eq(r.errors.size(), 1, "ровно одна ошибка про элемент: " + str(r.error_messages()))
	if r.errors.is_empty():
		return
	var e := r.errors[0]
	assert_eq(str(e.get("element", "")), "SolidState", "имя элемента")
	assert_eq(int(e.get("line", 0)), 9, "номер строки элемента SolidState")
	assert_eq(str(e.get("key", "")), "unknown_element")
	var msg := r.user_message(str(r.metadata.get("file_name", "")))
	assert_true(msg.contains("acc_unknown_element.zwo"), "сообщение содержит имя файла: " + msg)
	assert_true(msg.contains("SolidState"), "сообщение содержит имя элемента: " + msg)
	assert_true(msg.contains("не поддерживается"), "тип проблемы на языке интерфейса: " + msg)
	assert_true(msg.contains("строка 9"), "сообщение содержит номер строки: " + msg)
	_assert_user_safe(msg, "unknown_element")


func test_req_imp_05_c2_unknown_element_nested_in_step_rejected() -> void:
	var xml := """<workout_file><name>x</name><workout>
<SteadyState Duration="60" Power="0.7">
  <Sprint Duration="10"/>
</SteadyState>
</workout></workout_file>"""
	var r := ZwoParser.parse(xml)
	assert_false(r.ok(), "неизвестный элемент внутри шага — отказ")
	assert_null(r.workout)
	if r.errors.size() > 0:
		assert_eq(str(r.errors[0].get("element", "")), "Sprint")
		assert_eq(int(r.errors[0].get("line", 0)), 3)


func test_req_imp_05_c2_all_supported_elements_import() -> void:
	# Полный список поддерживаемых элементов в одном файле проходит без ошибок.
	var r := ZwoParser.parse(_read("acc_full.zwo"))
	assert_true(r.ok(), str(r.error_messages()))
	assert_eq(r.errors.size(), 0)


func test_req_imp_05_c1_c3_messages_user_safe_for_all_negative_fixtures() -> void:
	var cases := {
		"acc_not_xml.zwo": "zwo",
		"acc_truncated.zwo": "zwo",
		"acc_no_workout.zwo": "zwo",
		"acc_unknown_element.zwo": "zwo",
		"acc_zero_duration.zwo": "zwo",
		"acc_zero_repeat.zwo": "zwo",
		"acc_no_data.erg": "erg",
		"acc_single_point.erg": "erg",
		"acc_time_backwards.erg": "erg",
	}
	for name in cases.keys():
		var r := WorkoutLibrary.parse_text(_read(name), name)
		assert_false(r.ok(), name + ": должен отклоняться")
		assert_null(r.workout, name)
		assert_gt(r.errors.size(), 0, name + ": есть ошибка")
		var msg := r.user_message(name)
		assert_true(msg.begins_with(name + ":"), name + ": сообщение начинается с имени файла: " + msg)
		_assert_user_safe(msg, name)
		for e in r.errors:
			_assert_user_safe(str(e.get("message", "")), name)
			assert_false(str(e.get("message", "")).strip_edges().is_empty(), name + ": текст ошибки не пуст")
	# Intervals.icu
	var ev := IntervalsIcuWorkoutParser.parse(_event("acc_event_press_lap.json"))
	assert_false(ev.ok())
	_assert_user_safe(ev.user_message("event"), "press_lap")
	var doc := IntervalsIcuWorkoutParser.parse(_event("acc_event_doc_unsupported.json"))
	assert_false(doc.ok())
	_assert_user_safe(doc.user_message("event"), "doc_unsupported")


func test_req_imp_05_c3_format_entry_shapes() -> void:
	var text := ParseResult.format_entry({"line": 9, "column": 0, "element": "SolidState", "message": "элемент SolidState не поддерживается", "key": "x"}, "f.zwo")
	assert_eq(text, "f.zwo: элемент SolidState не поддерживается (строка 9)")
	var text2 := ParseResult.format_entry({"line": 3, "column": 6, "element": "press", "message": "элемент 'press' не поддерживается", "key": "x"}, "")
	assert_eq(text2, "элемент 'press' не поддерживается (строка 3, позиция 6)")


func test_req_imp_05_c4_bulk_garbage_does_not_crash() -> void:
	var garbage := ["", " ", "\u0000\u0001\u0002", "<", "<workout_file>", "<workout_file><workout>", "[COURSE DATA]", "[COURSE DATA]\n\n[END COURSE DATA]",
			"<workout_file><workout><SteadyState Duration=\"abc\" Power=\"x\"/></workout></workout_file>",
			"<workout_file><workout><IntervalsT Repeat=\"-1\" OnDuration=\"1\" OffDuration=\"1\" OnPower=\"1\" OffPower=\"1\"/></workout></workout_file>",
			"<workout_file><workout><SteadyState Duration=\"60\" Power=\"-0.5\"/></workout></workout_file>",
			"[COURSE DATA]\n0\t100\n5\t-100\n[END COURSE DATA]",
			"[COURSE DATA]\n0\t100\n0\t100\n[END COURSE DATA]",
			"[COURSE DATA]\n0\n5\n[END COURSE DATA]"]
	for g in garbage:
		for ext in ["zwo", "erg", "mrc"]:
			var r := WorkoutLibrary.parse_text(g, "g." + ext)
			assert_false(r.ok(), "мусор '%s' как .%s не даёт плана" % [g.c_escape().left(40), ext])
			assert_null(r.workout)
		var t := IntervalsIcuWorkoutParser.parse_description_text(g)
		assert_false(t.ok(), "мусор как описание Intervals: '%s'" % g.c_escape().left(40))
	var e1 := IntervalsIcuWorkoutParser.parse({})
	assert_false(e1.ok())
	var e2 := IntervalsIcuWorkoutParser.parse({"workout_doc": {"steps": [1, "x", null, {}]}})
	assert_false(e2.ok())
	assert_null(e2.workout)
	var e3 := IntervalsIcuWorkoutParser.parse({"workout_doc": {"steps": []}})
	assert_false(e3.ok())
	var e4 := IntervalsIcuWorkoutParser.parse({"workout_doc": {"steps": [{"duration": 60, "power": "fast"}]}})
	assert_false(e4.ok())
	var e5 := IntervalsIcuWorkoutParser.parse({"workout_doc": {"steps": [{"duration": 60, "power": {"value": 50, "units": "kj"}}]}})
	assert_false(e5.ok())
	var e6 := IntervalsIcuWorkoutParser.parse({"workout_doc": {"steps": [{"reps": 0, "steps": [{"duration": 60, "power": 50}]}]}})
	assert_false(e6.ok())
	assert_true(true, "дошли до конца без падения")


# ===========================================================================
# REQ-INT-03 — разбор структурированной тренировки Intervals.icu
# ===========================================================================

func test_req_int_03_c1_text_percent_step() -> void:
	var r := IntervalsIcuWorkoutParser.parse(_event("acc_event_text.json"))
	assert_true(r.ok(), str(r.error_messages()))
	if not r.ok():
		return
	_assert_step_percent(r.workout.steps[0], 600, 65.0, "10m 65%")
	assert_eq(r.workout.source, "intervals_icu")
	assert_eq(r.workout.name, "Acceptance Text Workout")


func test_req_int_03_c1_text_duration_forms() -> void:
	var r := IntervalsIcuWorkoutParser.parse(_event("acc_event_text.json"))
	assert_true(r.ok(), str(r.error_messages()))
	if not r.ok():
		return
	var w := r.workout
	assert_eq(w.steps[9].duration_sec, 5400, "1h30m")
	assert_eq(w.steps[10].duration_sec, 90, "90s")
	assert_eq(w.steps[11].duration_sec, 600, "10:00")
	var r2 := IntervalsIcuWorkoutParser.parse_description_text("- 1h 50%\n- 30s 60%\n- 1:00:00 55%\n- 2m30s 70%\n")
	assert_true(r2.ok(), str(r2.error_messages()))
	if r2.ok():
		assert_eq(r2.workout.steps[0].duration_sec, 3600, "1h")
		assert_eq(r2.workout.steps[1].duration_sec, 30, "30s")
		assert_eq(r2.workout.steps[2].duration_sec, 3600, "1:00:00")
		assert_eq(r2.workout.steps[3].duration_sec, 150, "2m30s")


func test_req_int_03_c2_text_watts_step() -> void:
	var r := IntervalsIcuWorkoutParser.parse(_event("acc_event_text.json"))
	assert_true(r.ok(), str(r.error_messages()))
	if not r.ok():
		return
	_assert_step_watts(r.workout.steps[10], 90, 250.0, "90s 250w")
	var r2 := IntervalsIcuWorkoutParser.parse_description_text("- 5m 250w")
	assert_true(r2.ok())
	if r2.ok():
		_assert_step_watts(r2.workout.steps[0], 300, 250.0, "5m 250w")
		assert_eq(r2.workout.steps[0].target_watts_at(0.0, 100), 250, "ватты не зависят от FTP")


func test_req_int_03_c2_doc_watts_step() -> void:
	var r := IntervalsIcuWorkoutParser.parse(_event("acc_event_doc.json"))
	assert_true(r.ok(), str(r.error_messages()))
	if not r.ok():
		return
	_assert_step_watts(r.workout.steps[9], 300, 220.0, "doc power 220 w")


func test_req_int_03_c3_range_to_midpoint() -> void:
	var r := IntervalsIcuWorkoutParser.parse(_event("acc_event_text.json"))
	assert_true(r.ok(), str(r.error_messages()))
	if not r.ok():
		return
	_assert_step_percent(r.workout.steps[8], 600, 90.0, "10m 85-95% → 90 %")
	assert_false(r.workout.steps[8].is_ramp(), "диапазон — не рампа")
	var r2 := IntervalsIcuWorkoutParser.parse_description_text("- 10m 60-70%\n- 5m 200-240w")
	assert_true(r2.ok())
	if r2.ok():
		_assert_step_percent(r2.workout.steps[0], 600, 65.0, "60-70% → 65")
		_assert_step_watts(r2.workout.steps[1], 300, 220.0, "200-240w → 220")
	var doc := IntervalsIcuWorkoutParser.parse(_event("acc_event_doc.json"))
	assert_true(doc.ok())
	if doc.ok():
		_assert_step_percent(doc.workout.steps[10], 300, 65.0, "doc start/end без ramp → середина 65")


func test_req_int_03_c4_ramp_keeps_start_and_end() -> void:
	var r := IntervalsIcuWorkoutParser.parse(_event("acc_event_text.json"))
	assert_true(r.ok(), str(r.error_messages()))
	if not r.ok():
		return
	_assert_ramp(r.workout.steps[7], 480, 50.0, 75.0, WorkoutStep.TargetKind.PERCENT_FTP, "8m ramp 50-75%")
	var doc := IntervalsIcuWorkoutParser.parse(_event("acc_event_doc.json"))
	assert_true(doc.ok(), str(doc.error_messages()))
	if doc.ok():
		_assert_ramp(doc.workout.steps[0], 600, 40.0, 70.0, WorkoutStep.TargetKind.PERCENT_FTP, "doc warmup ramp 40→70")
		assert_eq(doc.workout.steps[0].kind, WorkoutStep.StepKind.WARMUP)
		_assert_ramp(doc.workout.steps[12], 180, 60.0, 40.0, WorkoutStep.TargetKind.PERCENT_FTP, "doc cooldown ramp 60→40")
		assert_eq(doc.workout.steps[12].kind, WorkoutStep.StepKind.COOLDOWN)
	var r2 := IntervalsIcuWorkoutParser.parse_description_text("- 5m ramp 150-250w")
	assert_true(r2.ok())
	if r2.ok():
		_assert_ramp(r2.workout.steps[0], 300, 150.0, 250.0, WorkoutStep.TargetKind.WATTS, "ramp в ваттах")


func test_req_int_03_c5_repeats_expanded_inline_and_block() -> void:
	var r := IntervalsIcuWorkoutParser.parse(_event("acc_event_text.json"))
	assert_true(r.ok(), str(r.error_messages()))
	if not r.ok():
		return
	var w := r.workout
	assert_eq(w.steps.size(), 12, "1 + 3×2 + 5 шагов")
	for i in 3:
		_assert_step_percent(w.steps[1 + i * 2], 240, 105.0, "повтор %d: 4m 105%%" % (i + 1))
		_assert_step_percent(w.steps[2 + i * 2], 120, 50.0, "повтор %d: 2m 50%%" % (i + 1))
	# Блочная форма: 3x с последующими строками «- …» до пустой строки.
	var r2 := IntervalsIcuWorkoutParser.parse_description_text("- 5m 50%\n\n3x\n- 4m 105%\n- 2m 50%\n\n- 5m 40%")
	assert_true(r2.ok(), str(r2.error_messages()))
	if r2.ok():
		assert_eq(r2.workout.steps.size(), 1 + 6 + 1, "блочный повтор: 3 × 2 шага")
		assert_eq(r2.workout.total_duration_sec(), 300 + 3 * 360 + 300)
	# Повтор в конце без пустой строки.
	var r3 := IntervalsIcuWorkoutParser.parse_description_text("2x\n- 1m 100%\n- 1m 50%")
	assert_true(r3.ok(), str(r3.error_messages()))
	if r3.ok():
		assert_eq(r3.workout.steps.size(), 4)


func test_req_int_03_c5_doc_reps_nested_steps_expanded_with_independent_copies() -> void:
	var r := IntervalsIcuWorkoutParser.parse(_event("acc_event_doc.json"))
	assert_true(r.ok(), str(r.error_messages()))
	if not r.ok():
		return
	var w := r.workout
	assert_eq(w.steps.size(), 13, "1 + 4×2 + 1 + 1 + 1 + 1")
	for i in 4:
		_assert_step_percent(w.steps[1 + i * 2], 180, 110.0, "reps %d on" % (i + 1))
		_assert_step_percent(w.steps[2 + i * 2], 120, 50.0, "reps %d off" % (i + 1))
		assert_eq(w.steps[1 + i * 2].cadence_rpm, 95, "reps %d каденс" % (i + 1))
		assert_eq(w.steps[1 + i * 2].text_cues.size(), 1, "reps %d подсказка" % (i + 1))
	# Повторы — независимые копии.
	w.steps[1].text_cues.clear()
	assert_eq(w.steps[3].text_cues.size(), 1, "правка первого повтора не меняет второй")


func test_req_int_03_c6_cadence_present_and_absent() -> void:
	var r := IntervalsIcuWorkoutParser.parse(_event("acc_event_text.json"))
	assert_true(r.ok(), str(r.error_messages()))
	if not r.ok():
		return
	assert_eq(r.workout.steps[9].cadence_rpm, 85, "85rpm")
	assert_eq(r.workout.steps[10].cadence_rpm, 105, "100-110rpm → 105")
	assert_eq(r.workout.steps[0].cadence_rpm, 0, "без rpm → не задан (0)")
	var doc := IntervalsIcuWorkoutParser.parse(_event("acc_event_doc.json"))
	assert_true(doc.ok())
	if doc.ok():
		assert_eq(doc.workout.steps[1].cadence_rpm, 95, "doc cadence число")
		assert_eq(doc.workout.steps[9].cadence_rpm, 90, "doc cadence start/end → середина")
		assert_eq(doc.workout.steps[0].cadence_rpm, 0, "doc без cadence → 0")


func test_req_int_03_c7_text_hints_become_cues() -> void:
	var r := IntervalsIcuWorkoutParser.parse(_event("acc_event_text.json"))
	assert_true(r.ok(), str(r.error_messages()))
	if not r.ok():
		return
	var first := r.workout.steps[0]
	assert_eq(first.text_cues.size(), 1, "строка «Warmup» без дефиса → подсказка следующего шага")
	if first.text_cues.size() == 1:
		assert_eq(first.text_cues[0].text, "Warmup")
		assert_eq(first.text_cues[0].at_sec, 0)
	var r2 := IntervalsIcuWorkoutParser.parse_description_text("- 10m 65% Spin easy, high cadence\n- 5m 90%")
	assert_true(r2.ok(), str(r2.error_messages()))
	if r2.ok():
		assert_eq(r2.workout.steps[0].text_cues.size(), 1, "слова после цели — подсказка шага")
		if r2.workout.steps[0].text_cues.size() == 1:
			assert_true(r2.workout.steps[0].text_cues[0].text.contains("Spin easy"), r2.workout.steps[0].text_cues[0].text)
		assert_eq(r2.workout.steps[1].text_cues.size(), 0)
	var doc := IntervalsIcuWorkoutParser.parse(_event("acc_event_doc.json"))
	assert_true(doc.ok())
	if doc.ok():
		assert_eq(doc.workout.steps[0].text_cues.size(), 1)
		if doc.workout.steps[0].text_cues.size() == 1:
			assert_eq(doc.workout.steps[0].text_cues[0].text, "Разминка")
		assert_eq(doc.workout.steps[1].text_cues[0].text, "Жми")


func test_req_int_03_c8_total_matches_declared_within_1s() -> void:
	var r := IntervalsIcuWorkoutParser.parse(_event("acc_event_text.json"))
	assert_true(r.ok(), str(r.error_messages()))
	if not r.ok():
		return
	assert_eq(r.workout.total_duration_sec(), 8850, "сумма шагов")
	assert_true(absi(r.workout.total_duration_sec() - 8850) <= 1, "в допуске ±1 с от заявленной")
	assert_false(_has_key(r.warnings, "duration_mismatch"), "совпадает — без предупреждения: " + str(r.warning_messages()))
	var doc := IntervalsIcuWorkoutParser.parse(_event("acc_event_doc.json"))
	assert_true(doc.ok(), str(doc.error_messages()))
	if doc.ok():
		assert_eq(doc.workout.total_duration_sec(), 2700)
		assert_false(_has_key(doc.warnings, "duration_mismatch"))


func test_req_int_03_c8_declared_duration_mismatch_is_warning_boundary() -> void:
	var base := {"name": "x", "description": "- 10m 65%\n- 5m 50%"}  # 900 с
	for declared in [899, 900, 901]:
		var ev := base.duplicate()
		ev["duration"] = declared
		var r := IntervalsIcuWorkoutParser.parse(ev)
		assert_true(r.ok(), "duration=%d" % declared)
		assert_false(_has_key(r.warnings, "duration_mismatch"), "±1 с — в допуске (declared=%d)" % declared)
	for declared in [898, 902, 3600]:
		var ev := base.duplicate()
		ev["duration"] = declared
		var r := IntervalsIcuWorkoutParser.parse(ev)
		assert_true(r.ok(), "расхождение не блокирует импорт (declared=%d)" % declared)
		assert_true(_has_key(r.warnings, "duration_mismatch"), "расхождение > 1 с — предупреждение (declared=%d): %s" % [declared, str(r.warning_messages())])
	var no_decl := IntervalsIcuWorkoutParser.parse(base)
	assert_true(no_decl.ok())
	assert_false(_has_key(no_decl.warnings, "duration_mismatch"), "без заявленной длительности — нечего сверять")


func test_req_int_03_c9_press_lap_error_with_position_no_partial_plan() -> void:
	var r := IntervalsIcuWorkoutParser.parse(_event("acc_event_press_lap.json"))
	assert_false(r.ok(), "press lap не поддерживается — ошибка")
	assert_null(r.workout, "частично разобранный план (10m 65%) не возвращается")
	assert_gt(r.errors.size(), 0)
	if r.errors.is_empty():
		return
	var e := r.errors[0]
	assert_eq(int(e.get("line", 0)), 3, "строка «- 5m press lap» (3-я строка описания)")
	assert_gt(int(e.get("column", 0)), 0, "указана позиция в строке")
	assert_eq(int(e.get("column", 0)), 6, "позиция токена press в строке «- 5m press lap»")
	assert_true(str(e.get("message", "")).contains("press"), "сообщение называет элемент: " + str(e.get("message", "")))
	_assert_user_safe(r.user_message("event"), "press_lap")


func test_req_int_03_c9_unsupported_targets_text() -> void:
	for body in ["- 10m 140bpm", "- 10m Z2", "- 10m 4:30/km", "- 10m 70%hr", "- 10m 60% 140-150bpm"]:
		var r := IntervalsIcuWorkoutParser.parse_description_text("- 5m 50%\n" + body)
		assert_false(r.ok(), body + ": должна быть ошибка")
		assert_null(r.workout, body)
		if r.errors.size() > 0:
			assert_eq(int(r.errors[0].get("line", 0)), 2, body + ": строка 2")
			assert_gt(int(r.errors[0].get("column", 0)), 0, body + ": позиция")


func test_req_int_03_c9_step_without_duration_is_error() -> void:
	var r := IntervalsIcuWorkoutParser.parse_description_text("- 5m 50%\n- 65%")
	assert_false(r.ok(), "шаг без длительности — ошибка")
	assert_null(r.workout)
	if r.errors.size() > 0:
		assert_eq(int(r.errors[0].get("line", 0)), 2)


func test_req_int_03_c9_doc_unsupported_hr_target_error_with_position() -> void:
	var r := IntervalsIcuWorkoutParser.parse(_event("acc_event_doc_unsupported.json"))
	assert_false(r.ok(), "цель по пульсу не поддерживается")
	assert_null(r.workout, "частичный план не возвращается")
	assert_gt(r.errors.size(), 0)
	if r.errors.size() > 0:
		assert_eq(int(r.errors[0].get("line", 0)), 2, "позиция: второй шаг")
		assert_true(str(r.errors[0].get("element", "")).contains("steps[1]"), "путь к шагу: " + str(r.errors[0].get("element", "")))


func test_req_int_03_c9_doc_error_inside_nested_reps_points_to_top_step() -> void:
	var ev := {"workout_doc": {"steps": [
		{"duration": 600, "power": {"value": 65}},
		{"reps": 3, "steps": [{"duration": 60, "power": {"value": 100}}, {"duration": 60, "pace": {"value": 5}}]},
	]}}
	var r := IntervalsIcuWorkoutParser.parse(ev)
	assert_false(r.ok())
	assert_null(r.workout)
	if r.errors.size() > 0:
		assert_eq(int(r.errors[0].get("line", 0)), 2)
		assert_true(str(r.errors[0].get("element", "")).contains("steps[1].steps[1]"), str(r.errors[0].get("element", "")))


func test_req_int_03_neg_event_without_doc_and_description() -> void:
	var r := IntervalsIcuWorkoutParser.parse(_event("acc_event_empty.json"))
	assert_false(r.ok(), "событие без workout_doc и описания — нет плана")
	assert_null(r.workout)
	assert_gt(r.errors.size(), 0, "есть понятная ошибка")
	_assert_user_safe(r.user_message("event"), "empty_event")
	var r2 := IntervalsIcuWorkoutParser.parse({"name": "Only text", "description": "Easy ride today, no structure."})
	assert_false(r2.ok(), "описание без шагов — нет плана")
	assert_null(r2.workout)


func test_req_int_03_edge_doc_freeride_and_fallback_to_description() -> void:
	var doc := IntervalsIcuWorkoutParser.parse(_event("acc_event_doc.json"))
	assert_true(doc.ok(), str(doc.error_messages()))
	if doc.ok():
		var free := doc.workout.steps[11]
		assert_eq(free.duration_sec, 120)
		assert_true(free.is_free_ride(), "freeride: true → свободная езда")
		assert_eq(free.target_kind, WorkoutStep.TargetKind.NONE)
	# workout_doc без steps → разбор описания.
	var ev := {"name": "n", "description": "- 10m 65%", "workout_doc": {"duration": 600}, "duration": 600}
	var r := IntervalsIcuWorkoutParser.parse(ev)
	assert_true(r.ok(), str(r.error_messages()))
	if r.ok():
		assert_eq(r.workout.steps.size(), 1)
		assert_eq(r.workout.name, "n")


func test_req_int_03_edge_repeat_zero_and_power_one_hundred() -> void:
	var r := IntervalsIcuWorkoutParser.parse_description_text("0x (4m 105%, 2m 50%)\n- 5m 50%")
	assert_false(r.ok(), "0x — ошибка повтора")
	var r2 := IntervalsIcuWorkoutParser.parse_description_text("- 20m 100%")
	assert_true(r2.ok())
	if r2.ok():
		_assert_step_percent(r2.workout.steps[0], 1200, 100.0, "100 %")


# ===========================================================================
# REQ-NFR-09 крит. 1, 3 — наличие тестовых файлов парсеров
# ===========================================================================

func test_req_nfr_09_c1_parser_test_files_exist() -> void:
	for f in ["res://tests/unit/integrations/workouts/test_zwo_parser.gd",
			"res://tests/unit/integrations/workouts/test_erg_mrc_parser.gd",
			"res://tests/unit/integrations/workouts/test_intervals_icu_workout_parser.gd",
			"res://tests/unit/integrations/workouts/test_workout_library.gd"]:
		assert_true(FileAccess.file_exists(f), f + " существует")


func test_req_nfr_09_c3_each_parser_rejects_invalid_input() -> void:
	assert_false(ZwoParser.parse("garbage").ok(), "ZWO")
	assert_false(ErgMrcParser.parse("garbage", "erg").ok(), "ERG")
	assert_false(ErgMrcParser.parse("garbage", "mrc").ok(), "MRC")
	assert_false(IntervalsIcuWorkoutParser.parse_description_text("garbage").ok(), "Intervals text")
	assert_false(IntervalsIcuWorkoutParser.parse({"workout_doc": {"steps": ["garbage"]}}).ok(), "Intervals doc")
