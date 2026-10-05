class_name AboutDiagnostics
extends VBoxContainer
## Строки диагностики в «О программе» (T-116a, п.4–6).
##
## - «Журнал диагностики» → «Сохранить журнал»: системный диалог сохранения (`FileDialog`,
##   `use_native_dialog`), в выбранный файл уходит весь журнал (`DiagLog.export_to`); итог —
##   в подписи строки. Видна всегда.
## - Скрытые строки разработчика (доступны и в release-сборке): открываются пятью нажатиями
##   на строку «Версия» (`register_unlock_tap`, как «номер сборки» в системных настройках) и
##   остаются видны до перезапуска:
##   - «Замер FPS»: трасса (по умолчанию «Перевал») и длительность (по умолчанию 3 мин),
##     «Запустить» → сигнал `benchmark_requested` (экран замера — `FpsBenchmark`, открывает
##     экран настроек);
##   - «Ограничить FPS до 15» (`FrameRateLimit`, NFR-02 п.3);
##   - «Эмулятор станка» (REQ-DEV-09 крит. 6, FRD-01 крит. 4): переключатель → сигнал
##     `emulator_toggled`, решает оболочка (`AppMain.set_emulator_unlocked`), состояние она же
##     возвращает в `show_emulator_state`; в отладочной сборке эмулятор включён всегда;
##   - «BLE-отладка» (T-165): «Открыть» → сигнал `ble_debug_requested`, экран `BleDebugScreen`
##     открывает экран настроек.
##
## Оформление строк — как у остальных строк «О программе» (`Row16`, высота 56, подпись и
## пояснение `CaptionLabel` слева, контрол справа); решения `ui.md` для раздела разработчика
## нет (вопрос game-designer в отчёте T-116a).

## «Запустить» замер FPS.
signal benchmark_requested(route_id: String, duration_sec: float)
## Переключатель «Эмулятор станка» (до перезапуска приложения).
signal emulator_toggled(enabled: bool)
## «Открыть» экран «BLE-отладка».
signal ble_debug_requested

const UNLOCK_TAPS: int = 5
const ROW_HEIGHT: float = 56.0
const DEFAULT_ROUTE: String = FpsBenchmark.DEFAULT_ROUTE
const DEFAULT_DURATION_SEC: int = 180
const EXPORT_FILTER: String = "*.log"

var _taps: int = 0
var _dev_visible: bool = false
## Итог последнего экспорта: "" — не было, иначе ключ перевода.
var _export_status_key: String = ""
var _export_path: String = ""

var _log_label: Label
var _log_hint: Label
var _save_log_button: Button
var _bench_row: HBoxContainer
var _bench_label: Label
var _bench_hint: Label
var _bench_button: Button
var _bench_params_row: HBoxContainer
var _route_option: OptionButton
var _duration_option: OptionButton
var _limit_row: HBoxContainer
var _limit_label: Label
var _limit_hint: Label
var _limit_check: CheckButton
var _emulator_row: HBoxContainer
var _emulator_label: Label
var _emulator_hint: Label
var _emulator_check: CheckButton
var _ble_debug_row: HBoxContainer
var _ble_debug_label: Label
var _ble_debug_hint: Label
var _ble_debug_button: Button
var _file_dialog: FileDialog = null


func _init() -> void:
	name = "DiagnosticsRows"
	theme_type_variation = &"Stack8"
	_build()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED:
		render_texts()


# ---------------------------------------------------------------------------
# Скрытые строки
# ---------------------------------------------------------------------------

## Нажатие на строку «Версия»: пятое открывает строки разработчика. true — открыты.
func register_unlock_tap() -> bool:
	if _dev_visible:
		return true
	_taps += 1
	if _taps >= UNLOCK_TAPS:
		unlock_dev_tools()
	return _dev_visible


func unlock_dev_tools() -> void:
	_dev_visible = true
	_bench_row.visible = true
	_bench_params_row.visible = true
	_limit_row.visible = true
	_limit_check.set_pressed_no_signal(FrameRateLimit.is_limited())
	_emulator_row.visible = true
	_ble_debug_row.visible = true
	DiagLog.event(DiagLog.CAT_SETTINGS, "dev_tools_unlocked")


func are_dev_tools_visible() -> bool:
	return _dev_visible


func selected_route() -> String:
	var ids := RouteCatalog.ids()
	var i := _route_option.selected
	return ids[i] if i >= 0 and i < ids.size() else DEFAULT_ROUTE


func selected_duration_sec() -> float:
	var i := _duration_option.selected
	return float(FpsBenchmark.DURATIONS_SEC[i]) if i >= 0 and i < FpsBenchmark.DURATIONS_SEC.size() else float(DEFAULT_DURATION_SEC)


func request_benchmark() -> void:
	benchmark_requested.emit(selected_route(), selected_duration_sec())


func set_fps_limited(limited: bool) -> void:
	FrameRateLimit.set_limited(limited)
	_limit_check.set_pressed_no_signal(FrameRateLimit.is_limited())


## Состояние «Эмулятора станка» от оболочки: `enabled` — эмулятор доступен, `forced` — включён
## сборкой (отладка) и выключить его нельзя.
func show_emulator_state(enabled: bool, forced: bool) -> void:
	_emulator_check.set_pressed_no_signal(enabled)
	_emulator_check.disabled = forced


func emulator_check() -> CheckButton:
	return _emulator_check


func _on_emulator_check_toggled(enabled: bool) -> void:
	emulator_toggled.emit(enabled)


func ble_debug_button() -> Button:
	return _ble_debug_button


func request_ble_debug() -> void:
	ble_debug_requested.emit()


# ---------------------------------------------------------------------------
# Экспорт журнала
# ---------------------------------------------------------------------------

## «Сохранить журнал»: системный диалог сохранения файла.
func request_export() -> void:
	if _file_dialog == null:
		_file_dialog = FileDialog.new()
		_file_dialog.name = "SaveLogDialog"
		_file_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
		_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
		_file_dialog.use_native_dialog = true
		_file_dialog.filters = PackedStringArray([EXPORT_FILTER])
		_file_dialog.file_selected.connect(_on_export_path_selected)
		add_child(_file_dialog)
	_file_dialog.title = tr("ui.settings.diag_log_save")
	_file_dialog.current_file = DiagLog.export_file_name()
	_file_dialog.popup_centered_ratio(0.6)


## Сохранить журнал в `path` (выбран в диалоге). `OK` или код ошибки; итог — в подписи строки.
func export_log_to(path: String) -> Error:
	var journal := DiagLog.shared()
	var err: Error = journal.export_to(path) if journal != null else ERR_UNCONFIGURED
	_export_path = path
	_export_status_key = "ui.settings.diag_log_saved" if err == OK else "ui.settings.diag_log_failed"
	DiagLog.event(DiagLog.CAT_APP, "log_exported", {"ok": err == OK, "error": error_string(err)})
	render_texts()
	return err


func export_dialog() -> FileDialog:
	return _file_dialog


func save_log_button() -> Button:
	return _save_log_button


func benchmark_button() -> Button:
	return _bench_button


func route_option() -> OptionButton:
	return _route_option


func duration_option() -> OptionButton:
	return _duration_option


func fps_limit_check() -> CheckButton:
	return _limit_check


func log_hint_text() -> String:
	return _log_hint.text


# ---------------------------------------------------------------------------
# Тексты и построение
# ---------------------------------------------------------------------------

func render_texts() -> void:
	_log_label.text = tr("ui.settings.diag_log_title")
	if _export_status_key.is_empty():
		_log_hint.text = tr("ui.settings.diag_log_hint")
	else:
		_log_hint.text = tr(_export_status_key).format({"path": _export_path})
	_save_log_button.text = tr("ui.settings.diag_log_save")
	_bench_label.text = tr("ui.settings.fps_bench_title")
	_bench_hint.text = tr("ui.settings.fps_bench_hint")
	_bench_button.text = tr("ui.settings.fps_bench_run")
	_limit_label.text = tr("ui.settings.fps_limit_title").format({"fps": FrameRateLimit.DEBUG_FPS})
	_limit_hint.text = tr("ui.settings.fps_limit_hint")
	_emulator_label.text = tr("ui.settings.emulator_title")
	_emulator_hint.text = tr("ui.settings.emulator_hint")
	_ble_debug_label.text = tr("ui.settings.ble_debug_title")
	_ble_debug_hint.text = tr("ui.settings.ble_debug_hint")
	_ble_debug_button.text = tr("ui.settings.ble_debug_open")
	var ids := RouteCatalog.ids()
	for i in ids.size():
		_route_option.set_item_text(i, tr(RouteCatalog.get_route(ids[i]).name_key))
	for i in FpsBenchmark.DURATIONS_SEC.size():
		_duration_option.set_item_text(i, tr("ui.settings.fps_bench_minutes").format({"min": FpsBenchmark.DURATIONS_SEC[i] / 60}))


func _build() -> void:
	var log_row := _row("LogRow")
	var log_texts := _texts(log_row)
	_log_label = log_texts[0]
	_log_hint = log_texts[1]
	_save_log_button = _button(log_row, "SaveLogButton")
	_save_log_button.pressed.connect(request_export)

	_bench_row = _row("FpsBenchRow")
	var bench_texts := _texts(_bench_row)
	_bench_label = bench_texts[0]
	_bench_hint = bench_texts[1]
	_bench_button = _button(_bench_row, "FpsBenchButton")
	_bench_button.pressed.connect(request_benchmark)

	_bench_params_row = _row("FpsBenchParamsRow")
	_route_option = OptionButton.new()
	_route_option.name = "FpsBenchRouteOption"
	_route_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_route_option.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var ids := RouteCatalog.ids()
	for i in ids.size():
		_route_option.add_item(ids[i], i)
	_route_option.select(maxi(ids.find(DEFAULT_ROUTE), 0))
	_bench_params_row.add_child(_route_option)
	_duration_option = OptionButton.new()
	_duration_option.name = "FpsBenchDurationOption"
	_duration_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_duration_option.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	for i in FpsBenchmark.DURATIONS_SEC.size():
		_duration_option.add_item(str(FpsBenchmark.DURATIONS_SEC[i]), i)
	_duration_option.select(maxi(FpsBenchmark.DURATIONS_SEC.find(DEFAULT_DURATION_SEC), 0))
	_bench_params_row.add_child(_duration_option)

	_limit_row = _row("FpsLimitRow")
	var limit_texts := _texts(_limit_row)
	_limit_label = limit_texts[0]
	_limit_hint = limit_texts[1]
	_limit_check = CheckButton.new()
	_limit_check.name = "FpsLimitCheck"
	_limit_check.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_limit_check.toggled.connect(set_fps_limited)
	_limit_row.add_child(_limit_check)

	_emulator_row = _row("EmulatorRow")
	var emulator_texts := _texts(_emulator_row)
	_emulator_label = emulator_texts[0]
	_emulator_hint = emulator_texts[1]
	_emulator_check = CheckButton.new()
	_emulator_check.name = "EmulatorCheck"
	_emulator_check.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_emulator_check.toggled.connect(_on_emulator_check_toggled)
	_emulator_row.add_child(_emulator_check)

	_ble_debug_row = _row("BleDebugRow")
	var ble_debug_texts := _texts(_ble_debug_row)
	_ble_debug_label = ble_debug_texts[0]
	_ble_debug_hint = ble_debug_texts[1]
	_ble_debug_button = _button(_ble_debug_row, "BleDebugButton")
	_ble_debug_button.pressed.connect(request_ble_debug)

	for b: Button in [_save_log_button, _bench_button, _ble_debug_button]:
		TouchTarget.attach(b, TouchTarget.Kind.BUTTON)
	for c: Control in [_route_option, _duration_option, _limit_check, _emulator_check]:
		TouchTarget.attach(c, TouchTarget.Kind.UI)
	for hidden: Control in [_bench_row, _bench_params_row, _limit_row, _emulator_row, _ble_debug_row]:
		hidden.visible = false
	render_texts()


func _row(row_name: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = row_name
	row.custom_minimum_size = Vector2(0, ROW_HEIGHT)
	row.theme_type_variation = &"Row16"
	add_child(row)
	return row


## Подпись и пояснение слева в строке: [Label, Hint].
func _texts(row: HBoxContainer) -> Array[Label]:
	var box := VBoxContainer.new()
	box.name = "Texts"
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.theme_type_variation = &"Stack0"
	row.add_child(box)
	var label := Label.new()
	label.name = "Label"
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(label)
	var hint := Label.new()
	hint.name = "Hint"
	hint.theme_type_variation = &"CaptionLabel"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(hint)
	return [label, hint]


func _button(row: HBoxContainer, button_name: String) -> Button:
	var b := Button.new()
	b.name = button_name
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(b)
	return b


func _on_export_path_selected(path: String) -> void:
	export_log_to(path)
