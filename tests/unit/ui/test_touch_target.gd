extends GutTest
## `TouchTarget` (T-076; `docs/game/ui.md` п. 3, 6; REQ-UIX-05 крит. 1): минимальный размер
## цели нажатия по типу устройства `UiScale` — `touch_ui` 52 lp на сенсорных, 40 lp на
## компьютере, кнопки не ниже 44 lp, кнопки HUD — `touch_hud`; пересчёт по `scale_changed`.


func _runtime(device: UiScale.Device) -> UiScale:
	# Узел не добавляется в дерево: `_ready` автозагрузки трогает окно, здесь нужен только источник.
	var ui: UiScale = autofree(UiScale.new())
	ui.device = device
	return ui


func test_min_size_for_kinds() -> void:
	assert_eq(TouchTarget.min_size_for(TouchTarget.Kind.UI, 40.0, 48.0), Vector2(40, 40), "компьютер: touch_ui 40")
	assert_eq(TouchTarget.min_size_for(TouchTarget.Kind.UI, 52.0, 72.0), Vector2(52, 52), "сенсорные: touch_ui 52")
	assert_eq(TouchTarget.min_size_for(TouchTarget.Kind.BUTTON, 40.0, 48.0), Vector2(40, 44), "кнопка на компьютере — высота 44 (ui.md п. 6)")
	assert_eq(TouchTarget.min_size_for(TouchTarget.Kind.BUTTON, 52.0, 72.0), Vector2(52, 52), "кнопка на сенсорных — 52")
	assert_eq(TouchTarget.min_size_for(TouchTarget.Kind.HUD, 52.0, 72.0), Vector2(72, 72), "кнопка HUD — touch_hud")
	assert_eq(TouchTarget.min_size_for(TouchTarget.Kind.UI, 40.0, 48.0, Vector2(48, 48)), Vector2(48, 48), "нижняя граница поднимает размер")
	assert_eq(TouchTarget.min_size_for(TouchTarget.Kind.UI, 52.0, 72.0, Vector2(0, 64)), Vector2(52, 64))


func test_attach_applies_size_by_device_and_keeps_own_minimum() -> void:
	var phone := _runtime(UiScale.Device.PHONE)
	var button: Button = add_child_autofree(Button.new())
	button.custom_minimum_size = Vector2(120, 0)
	var helper := TouchTarget.attach(button, TouchTarget.Kind.UI, Vector2.ZERO, phone)
	assert_eq(button.custom_minimum_size, Vector2(120, 52), "своя ширина 120 сохраняется, высота — touch_ui телефона")
	assert_eq(TouchTarget.of(button), helper)
	assert_eq(button.get_children().size(), 0, "помощник — внутренний узел, в get_children() его нет")
	assert_eq(TouchTarget.attach(button, TouchTarget.Kind.UI, Vector2.ZERO, phone), helper, "повторный attach — тот же узел")
	assert_eq(button.get_children(true).size(), 1)


func test_recomputes_on_scale_changed() -> void:
	var ui := _runtime(UiScale.Device.DESKTOP)
	var button: Button = add_child_autofree(Button.new())
	TouchTarget.attach(button, TouchTarget.Kind.UI, Vector2.ZERO, ui)
	assert_eq(button.custom_minimum_size, Vector2(40, 40), "компьютер — 40 lp")
	ui.device = UiScale.Device.TABLET
	ui.scale_changed.emit(1.0)
	assert_eq(button.custom_minimum_size, Vector2(52, 52), "после scale_changed — 52 lp (планшет)")
	var hud_button: Button = add_child_autofree(Button.new())
	TouchTarget.attach(hud_button, TouchTarget.Kind.HUD, Vector2.ZERO, ui)
	ui.device = UiScale.Device.PHONE
	ui.scale_changed.emit(1.2)
	assert_eq(hud_button.custom_minimum_size, Vector2(72, 72), "кнопка HUD телефона — touch_hud 72")


func test_disconnects_when_target_leaves_tree() -> void:
	var ui := _runtime(UiScale.Device.DESKTOP)
	var button: Button = add_child_autofree(Button.new())
	var helper := TouchTarget.attach(button, TouchTarget.Kind.UI, Vector2.ZERO, ui)
	assert_true(ui.scale_changed.is_connected(helper._on_scale_changed))
	remove_child(button)
	assert_false(ui.scale_changed.is_connected(helper._on_scale_changed), "вне дерева сигнал отключён")
	add_child(button)
	assert_true(ui.scale_changed.is_connected(helper._on_scale_changed), "снова в дереве — подключён")


func test_attach_all_covers_interactive_nodes_only() -> void:
	var ui := _runtime(UiScale.Device.PHONE)
	var root: VBoxContainer = add_child_autofree(VBoxContainer.new())
	var button := Button.new()
	var field := LineEdit.new()
	var label := Label.new()
	root.add_child(button)
	root.add_child(field)
	root.add_child(label)
	assert_eq(TouchTarget.attach_all(root, TouchTarget.Kind.UI, ui), 2, "кнопка и поле; надпись не интерактивна")
	assert_not_null(TouchTarget.of(button))
	assert_not_null(TouchTarget.of(field))
	assert_null(TouchTarget.of(label))
	assert_eq(field.custom_minimum_size, Vector2(52, 52))


func test_default_runtime_is_autoload() -> void:
	var runtime := TouchTarget.default_runtime()
	assert_not_null(runtime, "автозагрузка UiScaleRuntime")
	var button: Button = add_child_autofree(Button.new())
	TouchTarget.attach(button)
	var expected := runtime.touch_ui()
	assert_eq(button.custom_minimum_size, Vector2(expected, expected), "без подмены — touch_ui текущего устройства")
