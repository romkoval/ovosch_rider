extends GutTest
## T-103: итог заезда — одна карточка для тренировки по плану и свободной езды (`ui.md` п. 8.8;
## REQ-HUD-14 крит. 7): вуаль `scrim`, фон `surface1` с альфой ≥ 0.96, подписи и кнопки внутри
## карточки; плитки плана — время, дистанция, ср. мощность, NP, ср. пульс, работа (кДж) и совпадают
## со сводкой LOC-04; числа сэмплов нет; паузы — только при `paused_total_sec` > 0 (75 с → «01:15»);
## кнопки — цель не меньше `touch_hud`; «Открыть в истории» ведёт к сохранённому заезду.

const WORKOUT_SCENE: String = "res://src/ui/workout/workout_screen.tscn"
const FREE_RIDE_SCENE: String = "res://src/ui/free_ride/free_ride_screen.tscn"

var _now_usec: int = 0
var _trainer: FakeTrainer
var _profile: Profile
var _state: AppState
var _repo: ProfileRepository
var _dir: String
var _locale: String


func before_each() -> void:
	_locale = TranslationServer.get_locale()
	_now_usec = 7_000_000
	_dir = "user://test_summary_card_%d_%d/" % [Time.get_ticks_usec(), randi() % 100000]
	_repo = ProfileRepository.new(_dir + "profiles/")
	_state = AppState.new(_repo)
	_trainer = FakeTrainer.new(21)
	_trainer.connect_delay_sec = 0.0
	_trainer.power_noise_w = 0.0
	_trainer.power_tau_sec = 0.01
	_trainer.cadence_noise_rpm = 0.0
	_trainer.connect_device("summary")
	_profile = Profile.create("Rider")
	_profile.ftp_w = 200
	_profile.max_hr = 180
	TranslationServer.set_locale("en")


func after_each() -> void:
	TranslationServer.set_locale(_locale)
	_remove_tree(ProjectSettings.globalize_path(_dir))


static func _remove_tree(abs_path: String) -> void:
	if not DirAccess.dir_exists_absolute(abs_path):
		return
	var d := DirAccess.open(abs_path)
	for f in d.get_files():
		DirAccess.remove_absolute(abs_path.path_join(f))
	for sub in d.get_directories():
		_remove_tree(abs_path.path_join(sub))
	DirAccess.remove_absolute(abs_path)


func _clock() -> int:
	return _now_usec


func _keep(_on: bool) -> void:
	pass


func _workout_screen() -> WorkoutScreen:
	var s: WorkoutScreen = load(WORKOUT_SCENE).instantiate()
	s.clock_usec = _clock
	s.keep_awake_setter = _keep
	add_child_autofree(s)
	s.setup(DevScreen.test_workout(), _profile, _trainer, _state)
	assert_true(s.start())
	return s


func _advance(s: WorkoutScreen, sec: float) -> void:
	_now_usec += int(round(sec * 1_000_000.0))
	s.ticker().poll()


func _labels(root: Node) -> Array[Label]:
	var out: Array[Label] = []
	for n in root.find_children("*", "Label", true, false):
		if (n as Label).is_visible_in_tree():
			out.append(n)
	return out


## Общие проверки карточки: вуаль, фон, всё внутри карточки, нет сэмплов, цели кнопок.
func _check_card(card: RideSummaryCard, where: String) -> void:
	assert_true(card.is_visible_in_tree(), "%s: итог показан" % where)
	assert_true(card.scrim().is_visible_in_tree(), "%s: вуаль" % where)
	assert_eq(card.scrim().color, UiTokens.SCRIM, "%s: цвет вуали scrim" % where)
	var box := card.card().get_theme_stylebox("panel") as StyleBoxFlat
	assert_not_null(box, "%s: у карточки есть фон" % where)
	if box != null:
		assert_gte(box.bg_color.a, 0.96, "%s: непрозрачность фона ≥ 0.96" % where)
		assert_eq(Color(box.bg_color, 1.0), Color(UiTokens.SURFACE1, 1.0), "%s: фон surface1" % where)
	var rect := card.card().get_global_rect()
	for l in _labels(card):
		if l.get_parent() == card or not card.card().is_ancestor_of(l):
			fail_test("%s: подпись «%s» вне карточки" % [where, l.text])
			continue
		assert_true(rect.encloses(l.get_global_rect()), "%s: «%s» внутри карточки" % [where, l.text])
		assert_false(l.text.to_lower().contains("sample") or l.text.to_lower().contains("сэмпл"),
				"%s: нет числа сэмплов: «%s»" % [where, l.text])
	var touch := UiScale.TOUCH_HUD_DESKTOP
	for b: Button in [card.home_button(), card.history_button()]:
		assert_true(rect.encloses(b.get_global_rect()), "%s: кнопка «%s» внутри карточки" % [where, b.text])
		assert_gte(b.get_combined_minimum_size().y, touch, "%s: высота «%s» ≥ touch_hud" % [where, b.text])
		assert_gte(b.get_combined_minimum_size().x, touch, "%s: ширина «%s» ≥ touch_hud" % [where, b.text])
	assert_lt(card.history_button().get_global_rect().position.x, card.home_button().get_global_rect().position.x,
			"%s: «Открыть в истории» слева от «На главный»" % where)
	assert_false(card.history_button().get_global_rect().intersects(card.home_button().get_global_rect()),
			"%s: кнопки не перекрываются" % where)


func test_plan_summary_is_card_with_loc_04_values_and_no_pauses() -> void:
	var s := _workout_screen()
	_advance(s, 200.0)
	await wait_process_frames(2)
	assert_true(s.is_summary_visible())
	var card := s.summary_card()
	_check_card(card, "план")
	assert_eq(card.title_text(), "ui.workout.finished", "заголовок — ключ «Тренировка завершена»")
	assert_eq(card.title_text().is_empty(), false)
	assert_eq(card.subtitle_text(), "dev-3-steps", "подзаголовок — название тренировки")
	assert_eq(card.stat_keys(), ["time", "distance", "avg_power", "np", "avg_hr", "work"] as Array[String],
			"плитки плана по порядку, шестая — работа")
	var sm := RideSummary.compute(s.session().samples, 200, _profile.effective_power_zones(), _profile.effective_hr_zones())
	assert_eq(s.summary_value_text("time"), HudModel.format_elapsed(sm.duration_sec))
	assert_eq(s.summary_value_text("distance"), "%.1f km" % (sm.distance_m / 1000.0))
	assert_eq(s.summary_value_text("avg_power"), "%d W" % sm.avg_power_w, "ср. мощность = LOC-04")
	assert_eq(s.summary_value_text("np"), "%d W" % sm.normalized_power_w, "NP = LOC-04")
	assert_eq(s.summary_value_text("work"), "%d kJ" % roundi(sm.work_kj), "работа = LOC-04")
	assert_eq(card.paused_text(), "", "пауз не было — строки пауз нет")


func test_plan_summary_shows_pauses_75_sec() -> void:
	var s := _workout_screen()
	_advance(s, 10.0)
	s.toggle_pause()
	_advance(s, 75.0)
	s.toggle_pause()
	_advance(s, 200.0)
	await wait_process_frames(2)
	assert_true(s.is_summary_visible())
	assert_eq(s.summary_card().paused_text(), "Paused: 01:15", "пауза 75 с — «01:15»")
	_check_card(s.summary_card(), "план с паузой")


func test_plan_summary_stopped_early_in_subtitle_and_ru_title() -> void:
	TranslationServer.set_locale("ru")
	var s := _workout_screen()
	_advance(s, 20.0)
	s.request_stop()
	s.confirm_stop()
	await wait_process_frames(2)
	var card := s.summary_card()
	assert_eq(card.subtitle_text(), "dev-3-steps · завершена досрочно")
	var title := card.card().find_child("SummaryTitle", true, false) as Label
	assert_eq(tr(title.text), "Тренировка завершена")
	assert_eq(card.history_button().disabled, true, "без сохранённого заезда «Открыть в истории» недоступна")
	s.set_saved_ride_id("ride-1")
	assert_false(card.history_button().disabled)
	watch_signals(s)
	(s.get_node("%HistoryButton") as Button).pressed.emit()
	assert_signal_emitted_with_parameters(s, "history_requested", ["ride-1"])


func test_free_ride_summary_uses_same_component_with_ascent() -> void:
	var s: FreeRideScreen = load(FREE_RIDE_SCENE).instantiate()
	s.clock_usec = _clock
	s.keep_awake_setter = _keep
	add_child_autofree(s)
	s.setup(_state, _profile, _trainer)
	assert_true(s.start())
	for i in 30:
		_now_usec += 1_000_000
		s.ticker().poll()
	s.request_finish()
	s.confirm_finish()
	await wait_process_frames(2)
	assert_true(s.is_summary_visible())
	var card := s.summary_card()
	assert_true(card is RideSummaryCard, "тот же компонент итога")
	_check_card(card, "свободная езда")
	assert_eq(card.stat_keys()[5], "ascent", "у свободной езды шестая плитка — набор")
	assert_eq(card.paused_text(), "", "пауз не было")
