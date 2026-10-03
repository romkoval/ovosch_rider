class_name WorkoutScreen
extends Control
## Экран тренировки (`AppState.Screen.WORKOUT`): собирает `WorkoutSession`, один
## `SessionTicker`, `HudModel`, `KeepAwake` и отрисовывает HUD (REQ-HUD-01..09, 13, 14,
## REQ-WRK-03..07, REQ-NFR-04). Зависимости приходят через `setup()`; станок — любой
## `TrainerDevice` (в приложении — `SensorHub` из `ConnectionManager`, в режиме
## разработки — эмулятор из `TrainerFactory`). При переданном `ConnectionManager`
## экран ставит `ticks_devices = false` на время сессии, чтобы устройства не
## получали время дважды, и возвращает `true` по завершении.
##
## Раскладка HUD — `HudLayout` (`docs/game/hud.md` п. 4.1): панель цифр `HudMetricPanel`
## сверху по центру, левый слот (список интервалов — T-078; пока номер шага), слот графика
## снизу (график — T-078; пока полоса прогресса HUD-07), слот подсказки, фишки статусов и
## кнопка паузы справа сверху, колонка органов управления у правого края (панель
## инструментов — T-074/T-078; пока прежние кнопки). Слоты отдаются наружу (`list_slot()`,
## `chart_slot()`, `hint_slot()`, `toolbar_slot()`), чтобы T-078 наполнил их компонентами.
##
## 3D-фон — `RideScene` в `SubViewport` (REQ-D3D-01) в физическом разрешении окна
## (REQ-HUD-13 крит. 10, `hud.md` п. 3): размер вьюпорта = размер экрана в пикселях окна,
## контейнер уменьшен `scale` обратно в lp холста, поэтому при растяжении `canvas_items`
## сцена не растягивается из меньшего растра. Вьюпорт рисуется, только пока экран виден.
## На время экрана включается масштаб HUD (`UiScaleRuntime.set_mode(UiScale.Mode.HUD)`).
##
## Строки — через ключи `ui.workout.*` и `ui.hud.*`; значения HUD берутся из `HudModel.state()`.
## После FINISHED показывается сводка-заглушка с кнопкой «На главный»; сохранение
## заезда — этап 5, для него есть сигнал `session_finished(session)`.

const UNIT_KEY: String = "ui.workout.unit_w"
const RESISTANCE_STEP: int = 5
const INTENSITY_STEP: float = 0.05
const ICON_PAUSE: Texture2D = preload("res://assets/icons/lucide/pause.svg")
const ICON_PLAY: Texture2D = preload("res://assets/icons/lucide/play.svg")
## Фишка статуса (`hud.md` п. 10.3): высота 24, радиус 12, точка 8, текст 12 / 650.
const CHIP_HEIGHT: float = HudLayout.STATUS_CHIP_HEIGHT
const CHIP_RADIUS: int = 12
const CHIP_DOT_RADIUS: float = 4.0
const CHIP_PAD_LEFT: float = 22.0
const CHIP_PAD_RIGHT: float = 10.0
const CHIP_GAP: float = 6.0
## Поля временной полосы прогресса внутри слота графика.
const CHART_PADDING: Vector2 = Vector2(16, 12)

## Сессия создана и сейчас стартует — владелец подключает запись заезда (`RideRecorder`, REQ-LOC-07).
signal session_created(session: WorkoutSession)
## Сессия завершена (по плану или досрочно) — хук для сохранения заезда (этап 5).
signal session_finished(session: WorkoutSession)
## Профиль изменён экраном (уровень сопротивления) — владелец сохраняет.
signal profile_updated(profile: Profile)

## Подставляемые часы тикера (пусто — системные).
var clock_usec: Callable = Callable()
## Подставляемый сеттер KeepAwake (пусто — DisplayServer).
var keep_awake_setter: Callable = Callable()

var _workout: Workout
var _profile: Profile
var _trainer: TrainerDevice
var _app_state: AppState
var _connections: ConnectionManager
var _session: WorkoutSession
var _ticker: SessionTicker
var _hud: HudModel
var _keep_awake: KeepAwake
var _stop_pending: bool = false
var _layout: HudLayout
## Цвета точек фишек статусов: фишка → цвет.
var _chip_dots: Dictionary = {}
var _chart_plate: StyleBoxFlat
var _status_chip_box: StyleBoxFlat

@onready var _ride_scene: RideScene = %RideScene
@onready var _viewport_container: SubViewportContainer = %ViewportContainer
@onready var _viewport: SubViewport = %Viewport
@onready var _hud_root: Control = %HudRoot
@onready var _summary_root: Control = %SummaryRoot
@onready var _no_session_label: Label = %NoSessionLabel
@onready var _metric_panel: HudMetricPanel = %MetricPanel
@onready var _list_slot: Control = %ListSlot
@onready var _step_plate: Control = %StepPlate
@onready var _step_label: Label = %StepLabel
@onready var _chart_slot: Control = %ChartSlot
@onready var _progress_bar: WorkoutProgressBar = %ProgressBar
@onready var _hint_slot: Control = %HintSlot
@onready var _cue_plate: PanelContainer = %CuePlate
@onready var _cue_label: Label = %CueLabel
@onready var _status_slot: Control = %StatusSlot
@onready var _trainer_chip: Control = %TrainerChip
@onready var _connection_label: Label = %ConnectionLabel
@onready var _hr_chip: Control = %HrChip
@onready var _mode_chip: Control = %ModeChip
@onready var _intensity_chip: Control = %IntensityChip
@onready var _intensity_status_label: Label = %IntensityStatusLabel
@onready var _pause_button: Button = %PauseButton
@onready var _toolbar_slot: Control = %ToolbarSlot
@onready var _toolbar: PanelContainer = %Toolbar
@onready var _skip_button: Button = %SkipButton
@onready var _stop_button: Button = %StopButton
@onready var _erg_button: Button = %ErgButton
@onready var _resistance_row: Control = %ResistanceRow
@onready var _resistance_label: Label = %ResistanceLabel
@onready var _resistance_minus: Button = %ResistanceMinus
@onready var _resistance_plus: Button = %ResistancePlus
@onready var _intensity_label: Label = %IntensityLabel
@onready var _intensity_minus: Button = %IntensityMinus
@onready var _intensity_plus: Button = %IntensityPlus
@onready var _stop_dialog: ConfirmationDialog = %StopDialog
@onready var _summary_label: Label = %SummaryLabel
@onready var _home_button: Button = %HomeButton


## Подготовить тренировку. `connections` — опционально, для `ticks_devices`.
func setup(workout: Workout, profile: Profile, trainer: TrainerDevice, app_state: AppState,
		connections: ConnectionManager = null) -> void:
	_teardown()
	_workout = workout
	_profile = profile
	_trainer = trainer
	_app_state = app_state
	_connections = connections
	if is_node_ready():
		refresh()


func _ready() -> void:
	# Узлы-значения панели доступны по уникальным именам и от экрана (`%TargetLabel` и др.).
	_metric_panel.share_unique_names(self)
	_chart_plate = StyleBoxFlat.new()
	_chart_plate.bg_color = UiTokens.HUD_PLATE
	_status_chip_box = StyleBoxFlat.new()
	_status_chip_box.bg_color = UiTokens.HUD_PLATE
	_status_chip_box.set_corner_radius_all(CHIP_RADIUS)
	_chart_slot.draw.connect(_draw_chart_backdrop)
	for chip: Control in [_trainer_chip, _hr_chip, _mode_chip, _intensity_chip]:
		chip.draw.connect(_draw_status_chip.bind(chip))
	resized.connect(_on_resized)
	get_viewport().size_changed.connect(_on_resized)
	_pause_button.pressed.connect(toggle_pause)
	_skip_button.pressed.connect(skip_step)
	_stop_button.pressed.connect(func() -> void: request_stop())
	_erg_button.pressed.connect(toggle_erg)
	_resistance_minus.pressed.connect(func() -> void: adjust_resistance(-RESISTANCE_STEP))
	_resistance_plus.pressed.connect(func() -> void: adjust_resistance(RESISTANCE_STEP))
	_intensity_minus.pressed.connect(func() -> void: adjust_intensity(-INTENSITY_STEP))
	_intensity_plus.pressed.connect(func() -> void: adjust_intensity(INTENSITY_STEP))
	_stop_dialog.confirmed.connect(func() -> void: confirm_stop())
	_stop_dialog.canceled.connect(func() -> void: _stop_pending = false)
	_home_button.pressed.connect(go_home)
	_fit_viewport()
	refresh()


# ---------------------------------------------------------------------------
# Жизненный цикл сессии
# ---------------------------------------------------------------------------

## Создать сессию, HUD, KeepAwake и тикер; запустить. false — не настроен.
func start() -> bool:
	if _workout == null or _trainer == null or not is_node_ready():
		return false
	_teardown_session()
	var ftp: int = _profile.ftp_w if _profile != null else 200
	var intensity: float = float(_profile.intensity_default) / 100.0 if _profile != null else 1.0
	var weight: float = _profile.weight_kg if _profile != null else WorkoutSession.DEFAULT_WEIGHT_KG
	_session = WorkoutSession.new(_workout, _trainer, ftp, intensity, weight)
	if _profile != null:
		_session.resistance_level = WorkoutSession.snap_resistance(_profile.resistance_level_default)
	_session.resistance_level_changed.connect(_on_resistance_level_changed)
	_session.state_changed.connect(_on_session_state)
	_hud = HudModel.new(_session, _profile)
	_hud.changed.connect(func(_s: Dictionary) -> void: _render())
	_keep_awake = KeepAwake.new(keep_awake_setter)
	_keep_awake.attach(_session)
	_ticker = SessionTicker.new(clock_usec)
	_ticker.name = "SessionTicker"
	_ticker.attach(_session)
	add_child(_ticker)
	if _connections != null:
		_connections.ticks_devices = false
	_stop_pending = false
	_ride_scene.bind(_session, _profile)
	session_created.emit(_session)
	_session.start()
	_ticker.start()
	refresh()
	return true


func session() -> WorkoutSession:
	return _session


func ticker() -> SessionTicker:
	return _ticker


func hud() -> HudModel:
	return _hud


func keep_awake() -> KeepAwake:
	return _keep_awake


func progress_bar() -> WorkoutProgressBar:
	return _progress_bar


## 3D-фон под HUD.
func ride_scene() -> RideScene:
	return _ride_scene


## Размер изображения 3D-сцены в пикселях (REQ-HUD-13 крит. 10).
func ride_viewport_size() -> Vector2i:
	return _viewport.size


## Панель цифр HUD (`HudMetricPanel`).
func metric_panel() -> HudMetricPanel:
	return _metric_panel


## Текущая геометрия HUD (пересчитывается при смене размера и на каждой отрисовке).
func hud_layout() -> HudLayout:
	if _layout == null:
		_layout_hud()
	return _layout


## Левый слот (список интервалов — T-078). Содержимое ставится от его левого верхнего угла.
func list_slot() -> Control:
	return _list_slot


## Слот графика: прямоугольник градиента и графика (`hud_layout().chart_gradient` ∪ `chart`).
func chart_slot() -> Control:
	return _chart_slot


## Слот подсказки и фишки «ДАЛЕЕ».
func hint_slot() -> Control:
	return _hint_slot


## Колонка панели инструментов у правого края.
func toolbar_slot() -> Control:
	return _toolbar_slot


## Уход с экрана тренировки: снимаем запрет гашения (REQ-NFR-04 крит. 1) и возвращаем
## масштаб меню.
func on_screen_exited() -> void:
	if _keep_awake != null:
		_keep_awake.on_screen_exited()
	var ui := _ui_scale()
	if ui != null and ui.mode == UiScale.Mode.HUD:
		ui.set_mode(UiScale.Mode.MENU)


## Вход на экран: запрет гашения и масштаб HUD (`hud.md` п. 3).
func on_screen_entered() -> void:
	if _keep_awake != null:
		_keep_awake.on_screen_entered()
	var ui := _ui_scale()
	if ui != null and ui.mode != UiScale.Mode.HUD:
		ui.set_mode(UiScale.Mode.HUD)
	refresh()


# ---------------------------------------------------------------------------
# Управление
# ---------------------------------------------------------------------------

func toggle_pause() -> void:
	if _session == null:
		return
	match _session.get_state():
		WorkoutSession.State.RUNNING:
			_session.pause()
		WorkoutSession.State.PAUSED:
			_session.resume()
	refresh()


func skip_step() -> void:
	if _session != null:
		_session.skip_step()
		refresh()


## Стоп требует подтверждения (REQ-WRK-05 крит. 4): показывает диалог.
func request_stop() -> bool:
	if _session == null or _session.get_state() == WorkoutSession.State.FINISHED:
		return false
	_stop_pending = true
	_stop_dialog.popup_centered()
	return true


func confirm_stop() -> void:
	_stop_pending = false
	if _session != null:
		_session.stop()
	refresh()


func cancel_stop() -> void:
	_stop_pending = false
	_stop_dialog.hide()


func is_stop_confirmation_pending() -> bool:
	return _stop_pending


## ERG вкл/выкл одним нажатием (REQ-WRK-03 крит. 1).
func toggle_erg() -> void:
	if _session != null:
		_session.toggle_erg()
		refresh()


## Уровень сопротивления ±5 % (REQ-WRK-04 крит. 1).
func adjust_resistance(delta_pct: int) -> void:
	if _session != null:
		_session.set_resistance_level(_session.resistance_level + delta_pct)
		refresh()


## Множитель интенсивности ±5 % (REQ-WRK-07 крит. 1).
func adjust_intensity(delta: float) -> void:
	if _session != null:
		_session.set_intensity(_session.intensity() + delta)
		refresh()


func go_home() -> void:
	on_screen_exited()
	if _app_state != null:
		_app_state.navigate(AppState.Screen.HOME)


# ---------------------------------------------------------------------------
# Тексты (для тестов и отрисовки)
# ---------------------------------------------------------------------------

func target_text() -> String:
	return _metric_panel.target_text()


func power_text() -> String:
	return _metric_panel.power_text()


func deviation_text() -> String:
	return _metric_panel.deviation_text()


func power_zone_text() -> String:
	return _metric_panel.power_zone_text()


func hr_text() -> String:
	return _metric_panel.hr_text()


func cadence_text() -> String:
	return _metric_panel.cadence_text()


func speed_text() -> String:
	return _metric_panel.speed_text()


func elapsed_text() -> String:
	return _metric_panel.elapsed_text()


func countdown_text() -> String:
	return _metric_panel.countdown_text()


func step_text() -> String:
	return _step_label.text


## Полный текст состояния станка (подсказка фишки «СТАНОК»).
func connection_text() -> String:
	return _trainer_chip.tooltip_text


func cue_text() -> String:
	return _cue_label.text


func summary_text() -> String:
	return _summary_label.text


func is_resistance_row_visible() -> bool:
	return _resistance_row.visible


func is_summary_visible() -> bool:
	return _summary_root.visible


func is_countdown_accented() -> bool:
	return _metric_panel.is_countdown_accented()


# ---------------------------------------------------------------------------
# Отрисовка
# ---------------------------------------------------------------------------

## Перечитать модель и обновить все узлы.
func refresh() -> void:
	if not is_node_ready():
		return
	if _session == null:
		_hud_root.visible = false
		_summary_root.visible = false
		_no_session_label.visible = true
		return
	_no_session_label.visible = false
	var finished: bool = _session.get_state() == WorkoutSession.State.FINISHED
	_hud_root.visible = not finished
	_summary_root.visible = finished
	if finished:
		_render_summary()
	else:
		_render()


func _render() -> void:
	if _hud == null or _session == null or _session.get_state() == WorkoutSession.State.FINISHED:
		return
	var s := _hud.state()
	_metric_panel.set_state(_panel_state(s))
	_step_label.text = tr("ui.workout.step").format({"step": s["step_text"]})
	_render_status(s)
	_cue_label.text = s["cue_text"]
	var has_cue := not str(s["cue_text"]).is_empty()
	_cue_label.visible = has_cue
	_cue_plate.visible = has_cue
	var paused: bool = s["session_state"] == WorkoutSession.State.PAUSED
	_pause_button.text = tr("ui.workout.resume") if paused else tr("ui.workout.pause")
	_pause_button.icon = ICON_PLAY if paused else ICON_PAUSE
	_erg_button.text = tr("ui.workout.erg_on") if s["erg_enabled"] else tr("ui.workout.erg_off")
	_resistance_row.visible = not s["erg_enabled"]
	_resistance_label.text = tr("ui.workout.resistance").format({"value": _session.resistance_level})
	_intensity_label.text = tr("ui.workout.intensity").format({"value": s["intensity_pct"]})
	_progress_bar.set_segments(_hud.progress_segments(), _hud.cursor())
	_layout_hud()


## Состояние для панели цифр: `HudModel.state()` + доля шага, зона цели, каденс шага.
func _panel_state(s: Dictionary) -> Dictionary:
	var ex := _session.executor
	var step := ex.current_step()
	var duration: int = step.duration_sec if step != null else 0
	var target: int = int(s["target_w"])
	var zone: int = 0
	if target > 0:
		zone = _profile.power_zone_of(target) if _profile != null else Zones.power_zone(target, ex.ftp_w)
	s["step_fraction"] = 1.0 - float(ex.step_remaining_sec()) / float(duration) if duration > 0 else 0.0
	s["step_free"] = step != null and step.is_free_ride()
	s["target_zone_token"] = ZonePalette.power_token(zone)
	s["target_cadence_rpm"] = step.cadence_rpm if step != null else 0
	s["resistance_pct"] = _session.resistance_level
	return s


## Фишки статусов (`hud.md` п. 10.3): станок, пульс, ERG, интенсивность ≠ 100 %.
func _render_status(s: Dictionary) -> void:
	_trainer_chip.tooltip_text = tr(s["connection_key"])
	_chip_dots[_trainer_chip] = _connection_dot(int(s["connection_state"]))
	var has_hr: bool = int(s["hr_bpm"]) >= 0
	_hr_chip.tooltip_text = tr("ui.hud.status.hr_ok") if has_hr else tr("ui.hud.status.hr_missing")
	_chip_dots[_hr_chip] = UiTokens.HUD_OK if has_hr else UiTokens.HUD_ERR
	var erg_on: bool = s["erg_enabled"]
	_mode_chip.tooltip_text = tr("ui.workout.erg_on") if erg_on else tr("ui.workout.erg_off")
	if not erg_on:
		_chip_dots[_mode_chip] = UiTokens.HUD_TEXT2
	else:
		_chip_dots[_mode_chip] = UiTokens.HUD_OK if s["erg_active_on_trainer"] else UiTokens.HUD_WARN
	var pct: int = int(s["intensity_pct"])
	_intensity_chip.visible = pct != 100
	_intensity_status_label.text = tr("ui.hud.status.intensity").format({"value": pct})
	_intensity_chip.tooltip_text = tr("ui.hud.status.intensity_hint").format({"value": pct})
	_chip_dots[_intensity_chip] = UiTokens.HUD_WARN
	for chip: Control in [_trainer_chip, _hr_chip, _mode_chip, _intensity_chip]:
		chip.queue_redraw()


static func _connection_dot(state: int) -> Color:
	match state:
		TrainerDevice.ConnectionState.CONNECTED:
			return UiTokens.HUD_OK
		TrainerDevice.ConnectionState.SCANNING, TrainerDevice.ConnectionState.CONNECTING, TrainerDevice.ConnectionState.RECONNECTING:
			return UiTokens.HUD_WARN
		_:
			return UiTokens.HUD_ERR


# ---------------------------------------------------------------------------
# Раскладка и 3D в физическом разрешении
# ---------------------------------------------------------------------------

func _on_resized() -> void:
	_fit_viewport()
	_layout_hud()


## Вьюпорт 3D — в пикселях окна: размер экрана в lp × пикселей на lp; контейнер уменьшен
## `scale` обратно до размера экрана (REQ-HUD-13 крит. 10).
func _fit_viewport() -> void:
	var lp := size
	if lp.x <= 0.0 or lp.y <= 0.0:
		return
	var px_per_lp := _px_per_lp()
	var px := Vector2i(maxi(roundi(lp.x * px_per_lp.x), 1), maxi(roundi(lp.y * px_per_lp.y), 1))
	_viewport_container.position = Vector2.ZERO
	_viewport_container.scale = lp / Vector2(px)
	_viewport_container.size = Vector2(px)
	if _viewport.size != px:
		_viewport.size = px


## Пикселей окна в одном lp холста этого экрана (по осям).
func _px_per_lp() -> Vector2:
	var visible_lp := get_viewport_rect().size
	var window := get_window()
	if window == null or visible_lp.x <= 0.0 or visible_lp.y <= 0.0:
		return Vector2.ONE
	return Vector2(window.size) / visible_lp


## Расставить слоты HUD по `HudLayout`.
func _layout_hud() -> void:
	if not is_node_ready() or size.x <= 0.0 or size.y <= 0.0:
		return
	var ui := _ui_scale()
	var s := ui.current_scale() if ui != null and ui.mode == UiScale.Mode.HUD else 1.0
	var touch := ui.touch_hud() if ui != null else UiScale.TOUCH_HUD_DESKTOP
	var phone := ui != null and ui.device == UiScale.Device.PHONE
	var safe := ui.safe_margins() if ui != null else Vector4.ZERO
	var chips := _visible_chips()
	_size_chips(chips)
	var row_w := CHIP_GAP * maxf(chips.size() - 1, 0)
	for chip in chips:
		row_w += chip.size.x
	_layout = HudLayout.compute(size, safe, s, touch, phone, _pause_button.get_combined_minimum_size(), row_w)
	_set_rect(_metric_panel, _layout.panel)
	_set_rect(_pause_button, _layout.pause_button)
	_set_rect(_list_slot, _layout.list_slot)
	_step_plate.position = Vector2.ZERO
	_step_plate.size = _step_plate.get_combined_minimum_size()
	var chart_rect := _layout.chart_gradient.merge(_layout.chart)
	_set_rect(_chart_slot, chart_rect)
	_progress_bar.position = Vector2(CHART_PADDING.x, _layout.chart_gradient.size.y + CHART_PADDING.y)
	_progress_bar.size = Vector2(chart_rect.size.x - 2.0 * CHART_PADDING.x, _layout.chart.size.y - 2.0 * CHART_PADDING.y)
	_chart_slot.queue_redraw()
	_set_rect(_hint_slot, _layout.hint_slot)
	_layout_cue()
	_set_rect(_status_slot, _layout.status_slot)
	_layout_chips(chips)
	_set_rect(_toolbar_slot, _layout.toolbar_slot)
	var tools := _toolbar.get_combined_minimum_size()
	_toolbar.size = tools
	_toolbar.position = Vector2(_layout.toolbar_slot.size.x - tools.x, maxf((_layout.toolbar_slot.size.y - tools.y) * 0.5, 0.0))


## Плашка подсказки: по ширине текста (не шире слота); вверху слота на компьютере и
## планшете, внизу — на телефоне (слот у низа кадра).
func _layout_cue() -> void:
	if not _cue_plate.visible:
		return
	var slot := _layout.hint_slot.size
	var box := _cue_plate.get_theme_stylebox(&"panel")
	var pad := box.get_minimum_size() if box != null else Vector2.ZERO
	var font := _cue_label.get_theme_font(&"font")
	var text_w := font.get_string_size(_cue_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, _cue_label.get_theme_font_size(&"font_size")).x
	var width := minf(ceilf(text_w) + pad.x + 1.0, slot.x)
	_cue_label.custom_minimum_size = Vector2(width - pad.x, 0)
	_cue_plate.size = Vector2(width, 0)
	_cue_plate.size = _cue_plate.get_combined_minimum_size()
	var y := slot.y - _cue_plate.size.y if _layout.phone else 0.0
	_cue_plate.position = Vector2((slot.x - _cue_plate.size.x) * 0.5, y)


func _visible_chips() -> Array[Control]:
	var out: Array[Control] = []
	for chip: Control in [_trainer_chip, _hr_chip, _mode_chip, _intensity_chip]:
		if chip.visible:
			out.append(chip)
	return out


func _size_chips(chips: Array[Control]) -> void:
	for chip in chips:
		var label := chip.get_child(0) as Label
		var label_size := label.get_combined_minimum_size()
		label.position = Vector2(CHIP_PAD_LEFT, (CHIP_HEIGHT - label_size.y) * 0.5)
		label.size = label_size
		chip.size = Vector2(CHIP_PAD_LEFT + label_size.x + CHIP_PAD_RIGHT, CHIP_HEIGHT)


## Строкой — вправо к кнопке паузы; столбиком — под кнопкой, по правому краю.
func _layout_chips(chips: Array[Control]) -> void:
	var slot := _layout.status_slot.size
	if _layout.status_vertical:
		var y := 0.0
		for chip in chips:
			chip.position = Vector2(slot.x - chip.size.x, y)
			y += CHIP_HEIGHT + HudLayout.STATUS_GAP
	else:
		var x := slot.x
		for i in range(chips.size() - 1, -1, -1):
			x -= chips[i].size.x
			chips[i].position = Vector2(x, 0)
			x -= CHIP_GAP


static func _set_rect(node: Control, rect: Rect2) -> void:
	node.position = rect.position
	node.size = rect.size


func _ui_scale() -> UiScale:
	return get_node_or_null(^"/root/UiScaleRuntime") as UiScale


## Градиент 28 lp (прозрачность 0 → подложка) и подложка графика.
func _draw_chart_backdrop() -> void:
	if _layout == null:
		return
	var w := _chart_slot.size.x
	var g := _layout.chart_gradient.size.y
	var clear := Color(UiTokens.HUD_PLATE, 0.0)
	_chart_slot.draw_polygon(
		PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w, g), Vector2(0, g)]),
		PackedColorArray([clear, clear, UiTokens.HUD_PLATE, UiTokens.HUD_PLATE]))
	_chart_slot.draw_style_box(_chart_plate, Rect2(0, g, w, _layout.chart.size.y))


## Фишка статуса: подложка `hud.plate` (r 12) и точка состояния.
func _draw_status_chip(chip: Control) -> void:
	chip.draw_style_box(_status_chip_box, Rect2(Vector2.ZERO, chip.size))
	chip.draw_circle(Vector2(CHIP_PAD_LEFT * 0.5 + 1.0, CHIP_HEIGHT * 0.5), CHIP_DOT_RADIUS, _chip_dots.get(chip, UiTokens.HUD_TEXT2))


func _render_summary() -> void:
	var m := _session.metadata()
	_summary_label.text = tr("ui.workout.summary").format({
		"name": m["workout_name"],
		"time": HudModel.format_elapsed(int(m["elapsed_sec"])),
		"distance": "%.1f" % (float(m["distance_m"]) / 1000.0),
		"samples": m["sample_count"],
		"early": tr("ui.workout.stopped_early") if m["stopped_early"] else "",
	}) + "\n" + tr("ui.workout.summary_paused").format({
		"paused": HudModel.format_elapsed(int(round(float(m["paused_total_sec"])))),
	})


# ---------------------------------------------------------------------------
# Внутреннее
# ---------------------------------------------------------------------------

func _on_session_state(state: int) -> void:
	if state == WorkoutSession.State.FINISHED:
		if _ticker != null:
			_ticker.stop()
		if _connections != null:
			_connections.ticks_devices = true
		if _ride_scene != null:
			_ride_scene.unbind()
		session_finished.emit(_session)
	refresh()


func _on_resistance_level_changed(percent: int) -> void:
	if _profile != null:
		_profile.resistance_level_default = percent
		profile_updated.emit(_profile)


func _teardown_session() -> void:
	if _ticker != null:
		_ticker.stop()
		_ticker.queue_free()
		_ticker = null
	if _keep_awake != null:
		_keep_awake.detach()
		_keep_awake = null
	if _session != null and _session.get_state() in [WorkoutSession.State.RUNNING, WorkoutSession.State.PAUSED]:
		_session.stop()
	if _connections != null:
		_connections.ticks_devices = true
	if _ride_scene != null:
		_ride_scene.unbind()
	_session = null
	_hud = null


func _teardown() -> void:
	_teardown_session()
	_workout = null
	_trainer = null


func _exit_tree() -> void:
	on_screen_exited()
