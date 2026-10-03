extends Control
## Стенд общих компонентов меню для снимков и ручного осмотра (T-076; `docs/game/ui.md` п. 6).
##
## Не экран приложения: в навигацию `AppState` не входит. Открыть — запустить сцену
## `components_stand.tscn` (редактор: F6) или снять снимок отладочным скриптом. Показывает
## AppBar с действием, три баннера, статы (обычные и плитку итогов), строки списка (одна и две
## строки текста, колонки, хвост, выбранная) и пустое состояние. Данные — образцы.

const APP_BAR_SCENE: PackedScene = preload("res://src/ui/common/app_bar.tscn")
const BANNER_SCENE: PackedScene = preload("res://src/ui/common/banner.tscn")
const STAT_SCENE: PackedScene = preload("res://src/ui/common/stat_view.tscn")
const ROW_SCENE: PackedScene = preload("res://src/ui/common/list_row.tscn")
const EMPTY_SCENE: PackedScene = preload("res://src/ui/common/empty_state.tscn")

## Ширины колонок строки истории (время, км, ср. Вт, NP), lp.
const COLUMN_WIDTHS: Array = [72, 56, 56, 56]

@onready var _bar_slot: VBoxContainer = %BarSlot
@onready var _content: VBoxContainer = %Content


func _ready() -> void:
	var bar: AppBar = APP_BAR_SCENE.instantiate()
	bar.navigate_on_back = false
	_bar_slot.add_child(bar)
	bar.set_title("ui.menu.stand.title")
	var search := Button.new()
	search.theme_type_variation = &"PrimaryButton"
	search.text = "ui.menu.stand.action_search"
	bar.add_action(search)
	TouchTarget.attach(search, TouchTarget.Kind.BUTTON)

	_add_banner(Banner.Kind.WARN, "ui.menu.stand.banner_warn", "ui.menu.stand.banner_warn_action", "bluetooth-off")
	_add_banner(Banner.Kind.ERROR, "ui.menu.stand.banner_error", "ui.menu.stand.banner_error_action", "cloud-upload")
	_add_banner(Banner.Kind.INFO, "ui.menu.stand.banner_info", "ui.menu.stand.banner_info_action", "")

	var stats := HBoxContainer.new()
	stats.theme_type_variation = &"Stack24"
	_content.add_child(stats)
	_add_stat(stats, "38:00", "", "ui.menu.stand.stat_duration", false)
	_add_stat(stats, "300", "ui.menu.unit.w", "ui.menu.stand.stat_max_target", false)
	_add_stat(stats, "20.0", "ui.menu.unit.km", "ui.menu.stand.stat_distance", true)
	_add_stat(stats, "212", "ui.menu.unit.w", "ui.menu.stand.stat_avg_power", true)

	var rows := VBoxContainer.new()
	_content.add_child(rows)
	var group := ButtonGroup.new()
	var one := _add_row(rows, "Tacx Neo 2T", "", "")
	one.set_icon("bike")
	var connect_button := Button.new()
	connect_button.theme_type_variation = &"GhostButton"
	connect_button.text = "ui.menu.stand.row_connect"
	one.add_trailing(connect_button)
	TouchTarget.attach(connect_button, TouchTarget.Kind.UI)
	one.show_chevron = false
	var plan := _add_row(rows, "Sweet Spot 3×10", "", "3 Oct, 21:12")
	plan.set_columns(["1:02:15", "32.4", "212", "228"], COLUMN_WIDTHS)
	plan.add_trailing(_overline("ui.menu.stand.mode_plan"))
	plan.selectable = true
	plan.button_group = group
	plan.set_selected(true)
	var sim := _add_row(rows, "Mountain Pass", "+412 m", "2 Oct, 19:40")
	sim.set_columns(["0:48:02", "18.9", "176", "190"], COLUMN_WIDTHS)
	sim.add_trailing(_overline("ui.menu.stand.mode_sim"))
	sim.selectable = true
	sim.button_group = group

	var empty_panel := PanelContainer.new()
	empty_panel.custom_minimum_size.y = 260
	_content.add_child(empty_panel)
	var empty: EmptyState = EMPTY_SCENE.instantiate()
	empty_panel.add_child(empty)
	empty.setup("history", "ui.menu.stand.empty_title", "ui.menu.stand.empty_text", "ui.menu.stand.empty_action")


func _add_banner(kind: Banner.Kind, text_key: String, action_key: String, icon: String) -> void:
	var banner: Banner = BANNER_SCENE.instantiate()
	_content.add_child(banner)
	banner.show_banner(kind, text_key, action_key, icon)


func _add_stat(parent: Container, value: String, unit: String, caption: String, large: bool) -> void:
	var stat: StatView = STAT_SCENE.instantiate()
	parent.add_child(stat)
	stat.large = large
	stat.set_stat(value, unit, caption)


func _add_row(parent: Container, title: String, subtitle: String, overline: String) -> ListRow:
	var row: ListRow = ROW_SCENE.instantiate()
	parent.add_child(row)
	row.set_texts(title, subtitle, overline)
	return row


func _overline(key: String) -> Label:
	var label := Label.new()
	label.theme_type_variation = &"OverlineLabel"
	label.uppercase = true
	label.text = key
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return label
