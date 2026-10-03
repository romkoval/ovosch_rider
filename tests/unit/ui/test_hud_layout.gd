extends GutTest
## Геометрия HUD заезда (T-073): `HudLayout` на разрешениях вводного абзаца HUD
## (REQ-HUD-13 крит. 1, 4, 5, 6, 9), 3D в физическом разрешении окна (крит. 10),
## расстановка слотов экрана тренировки по `HudLayout`. Дизайн — `docs/game/hud.md` п. 3, 4.1.

const SCREEN_SCENE: String = "res://src/ui/workout/workout_screen.tscn"
## Разрешения (пиксели), признак телефона и безопасная зона в lp базового холста.
const CASES: Array[Dictionary] = [
	{"name": "1280x720", "px": Vector2(1280, 720), "phone": false, "safe": Vector4.ZERO},
	{"name": "1920x1080", "px": Vector2(1920, 1080), "phone": false, "safe": Vector4.ZERO},
	{"name": "2732x2048", "px": Vector2(2732, 2048), "phone": false, "safe": Vector4.ZERO},
	{"name": "1024x768", "px": Vector2(1024, 768), "phone": false, "safe": Vector4.ZERO},
	{"name": "2556x1179", "px": Vector2(2556, 1179), "phone": true, "safe": Vector4(100, 0, 100, 13)},
	{"name": "1280x590", "px": Vector2(1280, 590), "phone": true, "safe": Vector4(100, 0, 100, 13)},
]
const EPS: float = 0.5


## Холст `canvas_items` + `expand` с базой 1280×720: высота 720 при аспекте ≥ 16:9, иначе ширина 1280.
static func _base_canvas(px: Vector2) -> Vector2:
	var aspect := px.x / px.y
	var base := Vector2(UiScale.BASE_SIZE)
	if aspect >= base.x / base.y:
		return Vector2(base.y * aspect, base.y)
	return Vector2(base.x, base.x / aspect)


func _layout(c: Dictionary) -> HudLayout:
	var phone: bool = c["phone"]
	var s := UiScale.HUD_SCALE_PHONE if phone else UiScale.HUD_SCALE_DESKTOP
	var touch := UiScale.TOUCH_HUD_PHONE if phone else UiScale.TOUCH_HUD_DESKTOP
	var canvas := _base_canvas(c["px"]) / s
	var safe: Vector4 = c["safe"] / s
	return HudLayout.compute(canvas, safe, s, touch, phone)


func _assert_inside(inner: Rect2, outer: Rect2, msg: String) -> void:
	assert_true(inner.position.x >= outer.position.x - EPS and inner.position.y >= outer.position.y - EPS
		and inner.end.x <= outer.end.x + EPS and inner.end.y <= outer.end.y + EPS,
		"%s: %s внутри %s" % [msg, inner, outer])


# --- Числа `hud.md` п. 4.1 на 16:9 ----------------------------------------------------------

func test_reference_geometry_1280x720() -> void:
	var l := HudLayout.compute(Vector2(1280, 720))
	assert_eq(l.panel, Rect2(320, 16, 640, 166), "панель 640×166, верх-центр, y = M")
	assert_almost_eq(l.list_slot.size.x, 281.6, 0.01, "w_l = 0.22·W")
	assert_eq(l.list_slot.position, Vector2(16, 16))
	assert_almost_eq(l.chart.size.y, 122.4, 0.01, "h_c = 0.17·H")
	assert_almost_eq(l.chart.position.y, 597.6, 0.01)
	assert_eq(l.chart.size.x, 1280.0, "график во всю ширину")
	assert_almost_eq(l.chart_gradient.position.y, 569.6, 0.01, "градиент 28 над графиком")
	assert_eq(l.hint_slot.position.y, 190.0, "слот подсказки под панелью +8")
	assert_eq(l.pause_button, Rect2(1216, 16, 48, 48), "кнопка touch_hud в правом верхнем углу")
	assert_false(l.status_vertical, "справа от панели 304 ≥ 260 — фишки строкой")


func test_chart_height_clamp_and_wide_screen_limit() -> void:
	assert_almost_eq(HudLayout.chart_height(500.0), 112.0, 0.01, "нижняя граница 112")
	assert_almost_eq(HudLayout.chart_height(500.0, 1.2), 93.33, 0.01, "на телефоне 112 lp базы = 93.3 lp HUD")
	var wide := HudLayout.compute(Vector2(1680, 720))
	assert_eq(wide.chart.size.x, HudLayout.CHART_MAX_WIDTH, "21:9 — не шире 1600")
	assert_almost_eq(wide.chart.get_center().x, 840.0, 0.01, "по центру")


func test_status_chips_fall_back_to_column_when_row_does_not_fit() -> void:
	var l := HudLayout.compute(Vector2(1280, 720), Vector4.ZERO, 1.0, 48.0, false, Vector2(97, 56), 260.0)
	assert_true(l.status_vertical, "строка фишек шире места до кнопки — столбиком")
	assert_eq(l.pause_button.size, Vector2(97, 56), "фактический размер кнопки")
	assert_almost_eq(l.status_slot.position.y, l.pause_button.end.y + HudLayout.STATUS_GAP, 0.01)


# --- REQ-HUD-13 на разрешениях вводного абзаца ------------------------------------------------

func test_req_hud_13_c1_panel_in_top_30_percent_and_centered() -> void:
	for c in CASES:
		var l := _layout(c)
		var size := l.canvas_size
		assert_true(l.panel.end.y <= HudLayout.PANEL_MAX_BOTTOM_FRACTION * size.y + EPS,
			"%s: низ панели %.1f ≤ 30 %% H (%.1f)" % [c["name"], l.panel.end.y, 0.3 * size.y])
		assert_true(absf(l.panel.get_center().x - size.x * 0.5) <= 0.05 * size.x,
			"%s: центр панели в ±5 %% ширины" % c["name"])


func test_req_hud_13_c4_chart_at_bottom_full_width_12_to_22_percent() -> void:
	for c in CASES:
		var l := _layout(c)
		var size := l.canvas_size
		var safe := l.safe_rect()
		assert_almost_eq(l.chart.end.y, safe.end.y, 0.01, "%s: прижат к низу" % c["name"])
		if size.x - l.safe_margins.x - l.safe_margins.z <= HudLayout.CHART_MAX_WIDTH:
			assert_almost_eq(l.chart.position.x, safe.position.x, 0.01, "%s: от левого отступа" % c["name"])
			assert_almost_eq(l.chart.end.x, safe.end.x, 0.01, "%s: до правого отступа" % c["name"])
		var frac := l.chart.size.y / size.y
		assert_true(frac >= 0.12 - 1e-6 and frac <= 0.22 + 1e-6, "%s: высота %.3f H" % [c["name"], frac])


func test_req_hud_13_c5_center_zone_free_of_opaque_slots() -> void:
	for c in CASES:
		var l := _layout(c)
		var center := HudLayout.center_zone(l.canvas_size)
		var slots := l.opaque_slots()
		for name: String in slots:
			var r: Rect2 = slots[name]
			assert_false(r.intersects(center), "%s: %s %s не заходит в центр %s" % [c["name"], name, r, center])


func test_req_hud_13_c6_no_overlaps_list_gap_and_safe_area() -> void:
	for c in CASES:
		var l := _layout(c)
		var slots := l.opaque_slots()
		var names: Array = slots.keys()
		for i in names.size():
			for j in range(i + 1, names.size()):
				var a: Rect2 = slots[names[i]]
				var b: Rect2 = slots[names[j]]
				assert_false(a.intersects(b), "%s: %s и %s не пересекаются (%s, %s)" % [c["name"], names[i], names[j], a, b])
			_assert_inside(slots[names[i]], l.safe_rect(), "%s: %s в безопасной зоне" % [c["name"], names[i]])
		assert_true(l.panel.position.x - l.list_slot.end.x >= HudLayout.LIST_PANEL_GAP - 1e-3,
			"%s: зазор список — панель ≥ 16·s" % c["name"])
		assert_true(l.list_slot.end.x <= 0.25 * l.canvas_size.x + EPS, "%s: левый слот в левых 25 %%" % c["name"])


func test_req_hud_13_c9_hint_slot_under_panel_on_desktop_and_above_chart_on_phone() -> void:
	for c in CASES:
		var l := _layout(c)
		assert_false(l.hint_slot.intersects(HudLayout.center_zone(l.canvas_size)), "%s: подсказка вне центра" % c["name"])
		assert_false(l.hint_slot.intersects(l.chart), "%s: подсказка не на графике" % c["name"])
		if c["phone"]:
			assert_almost_eq(l.hint_slot.end.y, l.chart.position.y - HudLayout.HINT_CHART_GAP_PHONE, 0.01, "%s: у низа кадра" % c["name"])
			assert_true(l.status_vertical, "%s: на телефоне фишки столбиком" % c["name"])
		else:
			assert_almost_eq(l.hint_slot.position.y, l.panel.end.y + HudLayout.HINT_PANEL_GAP, 0.01, "%s: под панелью" % c["name"])


# --- Экран тренировки: 3D в физическом разрешении, слоты по раскладке ----------------------------

func _screen() -> WorkoutScreen:
	var s: WorkoutScreen = load(SCREEN_SCENE).instantiate()
	s.keep_awake_setter = func(_on: bool) -> void: pass
	add_child_autofree(s)
	return s


func test_req_hud_13_c10_viewport_texture_matches_window_pixels() -> void:
	var s := _screen()
	var window := s.get_window()
	var visible_lp := s.get_viewport_rect().size
	assert_eq(s.size, visible_lp, "предусловие: экран на весь холст")
	var vp := s.ride_viewport_size()
	assert_true(absi(vp.x - window.size.x) <= 1 and absi(vp.y - window.size.y) <= 1,
		"размер изображения 3D %s = размер окна %s ±1 px" % [vp, window.size])
	var container := s.get_child(0) as SubViewportContainer
	assert_not_null(container, "3D-фон — первый ребёнок")
	assert_true(container.get_global_rect().size.is_equal_approx(Vector2(vp) * container.scale), "контейнер — растр вьюпорта")
	assert_true((Vector2(vp) * container.scale).is_equal_approx(s.size), "уменьшен до размера экрана в lp")


func test_viewport_follows_screen_size_change() -> void:
	var s := _screen()
	var px_per_lp := Vector2(s.get_window().size) / s.get_viewport_rect().size
	s.set_anchors_preset(Control.PRESET_TOP_LEFT)
	s.size = Vector2(640, 360)
	var vp := s.ride_viewport_size()
	assert_eq(vp, Vector2i((Vector2(640, 360) * px_per_lp).round()), "вьюпорт пересчитан при смене размера")


func test_screen_slots_follow_layout() -> void:
	var s := _screen()
	var l := s.hud_layout()
	assert_eq(s.metric_panel().position, l.panel.position, "панель цифр на месте слота")
	assert_eq(s.metric_panel().size, l.panel.size, "панель 640×166")
	assert_eq(s.list_slot().get_rect(), l.list_slot)
	assert_eq(s.hint_slot().get_rect(), l.hint_slot)
	assert_eq(s.toolbar_slot().get_rect(), l.toolbar_slot)
	assert_eq(s.chart_slot().get_rect(), l.chart_gradient.merge(l.chart), "слот графика — градиент и график")
	assert_eq((s.get_node("%PauseButton") as Control).get_rect(), l.pause_button)
