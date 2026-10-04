extends GutTest
## Тесты превью трассы (T-075): REQ-FRD-03 крит. 1–3 (цифры, форматы, серия и шкалы),
## модельная часть крит. 5, 6 (палитра уклона, подписи), REQ-UIX-03 крит. 2, 4 — трасса
## (одна модель для карточки и HUD); `docs/game/tracks.md` п. 7.

const FIELD := Rect2(12, 12, 320, 120)
const WIDTHS: Array[int] = [40, 100, 213, 320, 431, 1000]

var _locale: String = ""


func before_each() -> void:
	_locale = TranslationServer.get_locale()


func after_each() -> void:
	TranslationServer.set_locale(_locale)


## Тестовый профиль FRD-03 крит. 1: 1000 м ровно, 1000 м подъём на 50 м, 1000 м спуск на 50 м;
## опорные точки с шагом 10 м (между ними — периодическая PCHIP, поэтому ломаная задаётся часто).
func _frd03_profile() -> RouteProfile:
	var pts := PackedVector2Array()
	var s := 0
	while s <= 3000:
		var h: float = 0.0
		if s > 1000 and s <= 2000:
			h = 50.0 * float(s - 1000) / 1000.0
		elif s > 2000:
			h = 50.0 * float(3000 - s) / 1000.0
		pts.append(Vector2(s, h))
		s += 10
	return RouteProfile.from_points(pts)


func _model(route_id: String) -> RoutePreviewModel:
	return RoutePreviewModel.for_route(RouteCatalog.get_route(route_id))


func _stat_texts(model: RoutePreviewModel) -> Array[String]:
	var out: Array[String] = []
	for st in model.stats():
		out.append(str(st["text"]))
	return out


# --- FRD-03 крит. 1, 2: цифры по функциям профиля и форматы ---------------------------

func test_frd03_c1_test_profile_ru() -> void:
	TranslationServer.set_locale("ru")
	var model := RoutePreviewModel.for_profile(_frd03_profile())
	assert_true(model.is_valid())
	assert_eq(model.length_text(), "3.0 км")
	assert_eq(model.ascent_text(), "50 м")
	assert_eq(model.max_grade_text(), "5.0 %")
	assert_eq(_stat_texts(model), ["3.0 км", "50 м", "5.0 %"] as Array[String])


func test_frd03_c1_test_profile_en() -> void:
	TranslationServer.set_locale("en")
	var model := RoutePreviewModel.for_profile(_frd03_profile())
	assert_eq(_stat_texts(model), ["3.0 km", "50 m", "5.0 %"] as Array[String])


func test_frd03_c1_numbers_come_from_profile_functions() -> void:
	var profile := _frd03_profile()
	assert_almost_eq(profile.max_grade_pct(), 5.0, 0.1)
	var model := RoutePreviewModel.for_profile(profile)
	var st := model.stats()
	assert_eq(st[0]["value"], RoutePreviewModel.length_value(profile.length_m()))
	assert_eq(st[1]["value"], RoutePreviewModel.ascent_value(profile.ascent_m()))
	assert_eq(st[2]["value"], RoutePreviewModel.grade_value(profile.max_grade_pct()))
	assert_eq([st[0]["id"], st[1]["id"], st[2]["id"]], [RoutePreviewModel.STAT_LENGTH, RoutePreviewModel.STAT_ASCENT, RoutePreviewModel.STAT_MAX_GRADE])


func test_frd03_c2_stat_parts_and_captions() -> void:
	TranslationServer.set_locale("ru")
	var st := _model(RouteCatalog.MOUNTAINS).stats()
	assert_eq(st[0]["value"], "20.0")
	assert_eq(st[0]["unit"], "км")
	assert_eq(st[0]["caption"], "круг")
	assert_eq(st[1]["caption"], "набор")
	assert_eq(st[2]["caption"], "макс. уклон")
	TranslationServer.set_locale("en")
	st = _model(RouteCatalog.MOUNTAINS).stats()
	assert_eq(st[0]["unit"], "km")
	assert_eq(st[1]["unit"], "m")
	assert_eq(st[0]["caption"], "lap")


## Ключи превью (`track.*`, `strings_tracks.csv`) переведены на ru и en (NFR-08 крит. 2):
## сканеры ключей в исходниках ищут только `ui.*`/`error.*`, поэтому проверка — здесь.
func test_preview_keys_translated_ru_en() -> void:
	var keys: Array[String] = [
		RoutePreviewModel.KEY_UNIT_KM, RoutePreviewModel.KEY_UNIT_M, RoutePreviewModel.KEY_UNIT_PCT,
		RoutePreviewModel.KEY_STAT_LAP, RoutePreviewModel.KEY_STAT_ASCENT, RoutePreviewModel.KEY_STAT_MAX_GRADE,
		RoutePreviewModel.KEY_CLIMB, RoutePreviewModel.KEY_BRIDGE,
	]
	var csv := FileAccess.get_file_as_string("res://assets/i18n/strings_tracks.csv")
	for key in keys:
		assert_true(csv.contains("\n" + key + ","), "%s в strings_tracks.csv" % key)
		for locale in ["ru", "en"]:
			TranslationServer.set_locale(locale)
			var text := String(TranslationServer.translate(key))
			assert_true(text != key and not text.strip_edges().is_empty(), "%s [%s]" % [key, locale])


func test_frd03_c2_formats() -> void:
	TranslationServer.set_locale("ru")
	assert_eq(RoutePreviewModel.format_length_km(9960.0), "10.0 км")
	assert_eq(RoutePreviewModel.format_length_km(12345.0), "12.3 км")
	assert_eq(RoutePreviewModel.format_ascent_m(440.6), "441 м")
	assert_eq(RoutePreviewModel.format_ascent_m(19.4), "19 м")
	assert_eq(RoutePreviewModel.format_grade_pct(9.447), "9.4 %")
	assert_eq(RoutePreviewModel.format_grade_pct(4.96), "5.0 %")
	assert_eq(RoutePreviewModel.format_grade_pct(-0.04), "0.0 %", "без «−0.0»")
	assert_eq(RoutePreviewModel.format_height_m(737.6), "738 м")


## FRD-03 крит. 5 (цифры): совпадают с D3D-08.3 (`tracks.md` п. 3).
func test_frd03_c5_catalog_numbers() -> void:
	TranslationServer.set_locale("ru")
	var expected := {
		RouteCatalog.FLAT: ["10.0 км", "19 м", "1.0 %"],
		RouteCatalog.HILLS: ["15.0 км", "220 м", "7.5 %"],
		RouteCatalog.MOUNTAINS: ["20.0 км", "441 м", "9.4 %"],
		RouteCatalog.SEASIDE: ["12.0 км", "56 м", "4.9 %"],
	}
	for route_id: String in expected:
		assert_eq(Array(_stat_texts(_model(route_id))), expected[route_id], route_id)


# --- FRD-03 крит. 3: шкалы ------------------------------------------------------------

func test_frd03_c3_thumb_fill_fraction_per_route() -> void:
	var expected := {RouteCatalog.FLAT: 0.08, RouteCatalog.SEASIDE: 0.30, RouteCatalog.HILLS: 0.65}
	for route_id: String in expected:
		assert_almost_eq(_model(route_id).fill_fraction(RoutePreviewModel.Mode.THUMB), float(expected[route_id]), 0.02, route_id)
	var mountains := _model(RouteCatalog.MOUNTAINS).fill_fraction(RoutePreviewModel.Mode.THUMB)
	assert_between(mountains, 0.98, 1.0 + 1e-9)


func test_frd03_c3_thumb_scale_bottom_is_route_min_span_max_of_drop_and_150() -> void:
	for route_id in RouteCatalog.ids():
		var model := _model(route_id)
		var profile := model.profile
		var p := model.plot(RoutePreviewModel.Mode.THUMB, FIELD)
		assert_almost_eq(p.y(profile.min_height_m()), FIELD.end.y, 1e-6, "%s: минимум — нижний край поля" % route_id)
		var span: float = maxf(profile.max_height_m() - profile.min_height_m(), 150.0)
		assert_almost_eq(p.h_top - p.h_bottom, span, 1e-6, route_id)
		assert_almost_eq(p.x(0.0), FIELD.position.x, 1e-6)
		assert_almost_eq(p.x(profile.length_m()), FIELD.end.x, 1e-6, "%s: круг — во всю ширину" % route_id)
	var mountains := _model(RouteCatalog.MOUNTAINS)
	var mp := mountains.plot(RoutePreviewModel.Mode.THUMB, FIELD)
	assert_almost_eq(mp.y(mountains.profile.max_height_m()), FIELD.position.y, 1e-6, "горы — во всю высоту")


func test_large_profile_has_10_percent_margins() -> void:
	for route_id in RouteCatalog.ids():
		var model := _model(route_id)
		var p := model.plot(RoutePreviewModel.Mode.LARGE, FIELD)
		var y_min: float = p.y(model.profile.min_height_m())
		var y_max: float = p.y(model.profile.max_height_m())
		assert_almost_eq(FIELD.end.y - y_min, FIELD.size.y * 0.10, 1e-6, "%s: поле снизу 10 %%" % route_id)
		assert_true(y_max - FIELD.position.y >= FIELD.size.y * 0.10 - 1e-6, "%s: поле сверху ≥ 10 %%" % route_id)
		# Решение ред. 2 (`tracks.md` п. 7.2): размах max(перепад, 40 м) — как у профиля круга
		# и «впереди 2 км» в HUD (`hud.md` п. 8), а не 150 м миниатюры.
		var drop: float = model.profile.max_height_m() - model.profile.min_height_m()
		var span: float = maxf(drop, 40.0)
		gut.p("%s: перепад %.1f м → размах крупного профиля %.1f м" % [route_id, drop, span])
		assert_almost_eq((p.h_top - p.h_bottom) * 0.8, span, 1e-6, "%s: размах max(перепад %.1f, 40 м)" % [route_id, drop])
		if drop >= 40.0:
			assert_almost_eq(y_max - FIELD.position.y, FIELD.size.y * 0.10, 1e-6, "%s: перепад ≥ 40 м — вершина у верхнего поля" % route_id)
			assert_almost_eq(model.fill_fraction(RoutePreviewModel.Mode.LARGE), 0.8, 1e-6, "%s: профиль занимает 80 %% поля" % route_id)
		else:
			assert_almost_eq(model.fill_fraction(RoutePreviewModel.Mode.LARGE), drop / 40.0 * 0.8, 1e-6, "%s: перепад < 40 м — доля от размаха 40 м" % route_id)
	# Равнина: перепад меньше 40 м — шкала 40 м, а не 150 м (иначе полоска у дна, T-080).
	var flat := _model(RouteCatalog.FLAT)
	var flat_drop: float = flat.profile.max_height_m() - flat.profile.min_height_m()
	assert_lt(flat_drop, 40.0, "предусловие: перепад равнины < 40 м")
	var fp := flat.plot(RoutePreviewModel.Mode.LARGE, FIELD)
	assert_almost_eq(fp.h_top - fp.h_bottom, 40.0 / 0.8, 1e-6, "равнина: размах 40 м + поля 10 %")
	assert_gt(flat.fill_fraction(RoutePreviewModel.Mode.LARGE), 0.2, "равнина видна, а не полоской у дна")
	var mountains := _model(RouteCatalog.MOUNTAINS)
	var mp := mountains.plot(RoutePreviewModel.Mode.LARGE, FIELD)
	assert_almost_eq(mp.y(mountains.profile.max_height_m()) - FIELD.position.y, FIELD.size.y * 0.10, 1e-6, "горы: вершина у верхнего поля")


func test_y_range_for_min_span_and_margins() -> void:
	assert_eq(RoutePreviewModel.y_range_for(36.0, 48.0, 150.0), Vector2(36.0, 186.0))
	assert_eq(RoutePreviewModel.y_range_for(300.0, 738.0, 150.0), Vector2(300.0, 738.0))
	var r := RoutePreviewModel.y_range_for(0.0, 80.0, 40.0, 0.1)
	assert_almost_eq(r.x, -10.0, 1e-9)
	assert_almost_eq(r.y, 90.0, 1e-9)


# --- FRD-03 крит. 3: серия ------------------------------------------------------------

func test_frd03_c3_series_spans_whole_lap() -> void:
	for route_id in RouteCatalog.ids():
		var model := _model(route_id)
		var pts := model.lap_series(320)
		assert_almost_eq(pts[0].x, 0.0, 1e-9, route_id)
		assert_almost_eq(pts[-1].x, model.length_m(), 1e-9, route_id)
		assert_almost_eq(pts[-1].y, pts[0].y, 1e-6, "%s: круг замкнут" % route_id)
		for i in range(1, pts.size()):
			assert_true(pts[i].x > pts[i - 1].x, "%s: s возрастает" % route_id)
			if pts[i].x <= pts[i - 1].x:
				break


func test_frd03_c3_point_count_at_most_twice_width() -> void:
	for route_id in RouteCatalog.ids():
		var model := _model(route_id)
		for w in WIDTHS:
			var p := model.plot(RoutePreviewModel.Mode.THUMB, Rect2(0, 0, w, 60))
			assert_true(model.series(p).size() <= 2 * w, "%s, ширина %d: %d точек" % [route_id, w, model.series(p).size()])
			assert_true(model.outline(p).size() <= 2 * w)
	# Короткий профиль без прореживания — все точки выборки (+ точка s = L).
	var small := RoutePreviewModel.for_profile(_frd03_profile())
	assert_eq(small.lap_series(1000).size(), small.profile.sample_count() + 1)


func test_frd03_c3_local_extrema_kept() -> void:
	for route_id in RouteCatalog.ids():
		var model := _model(route_id)
		var heights := model.profile.sample_heights()
		var step := model.profile.sample_step_m()
		var n := heights.size()
		var extrema: Array[float] = []
		for i in n:
			var prev: float = heights[(i - 1 + n) % n]
			var next: float = heights[(i + 1) % n]
			# Строгий экстремум с допуском: шум округления на ровной полке (1e-15 м) — не экстремум.
			var eps := 1e-6
			if (heights[i] > prev + eps and heights[i] > next + eps) or (heights[i] < prev - eps and heights[i] < next - eps):
				extrema.append(float(i) * step)
		assert_gt(extrema.size(), 0, route_id)
		for w in [100, 320]:
			var pts := model.lap_series(w)
			var xs: Dictionary = {}
			for pt in pts:
				xs[snappedf(pt.x, 0.001)] = true
			var missing: Array[float] = []
			for s in extrema:
				if s > 0.0 and not xs.has(snappedf(s, 0.001)):
					missing.append(s)
			assert_eq(missing, [] as Array[float], "%s, ширина %d: локальные экстремумы среди точек" % [route_id, w])
			var hs := PackedFloat64Array()
			for pt in pts:
				hs.append(pt.y)
			var lo: float = INF
			var hi: float = -INF
			for h in hs:
				lo = minf(lo, h)
				hi = maxf(hi, h)
			assert_almost_eq(lo, model.profile.min_height_m(), 1e-6, "%s: минимум трассы в серии" % route_id)
			assert_almost_eq(hi, model.profile.max_height_m(), 1e-6, "%s: максимум трассы в серии" % route_id)


func test_decimate_keeps_bucket_extrema_and_ends() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 75
	var pts := PackedVector2Array()
	for i in 5000:
		pts.append(Vector2(i, rng.randf_range(-100.0, 100.0)))
	pts[1234].y = 500.0
	pts[4321].y = -500.0
	var out := RoutePreviewModel.decimate(pts, 200)
	assert_true(out.size() <= 200)
	assert_eq(out[0], pts[0])
	assert_eq(out[-1], pts[-1])
	assert_has(Array(out), pts[1234])
	assert_has(Array(out), pts[4321])
	for i in range(1, out.size()):
		assert_true(out[i].x > out[i - 1].x)
		if out[i].x <= out[i - 1].x:
			break
	var short := PackedVector2Array([Vector2(0, 0), Vector2(1, 2), Vector2(2, 0)])
	assert_eq(RoutePreviewModel.decimate(short, 4), short)


# --- FRD-03 крит. 5 (модель): заливка по палитре уклона ------------------------------

func test_grade_palette_boundaries() -> void:
	var slate := UiTokens.GRADE_COLORS[0]
	var sage := UiTokens.GRADE_COLORS[1]
	assert_eq(UiTokens.grade_color(-2.01), slate)
	assert_eq(UiTokens.grade_color(-2.0), sage)
	assert_eq(UiTokens.grade_color(1.99), sage)
	assert_eq(UiTokens.grade_color(2.0), UiTokens.GRADE_COLORS[2])
	assert_eq(UiTokens.grade_color(4.0), UiTokens.GRADE_COLORS[3])
	assert_eq(UiTokens.grade_color(7.0), UiTokens.GRADE_COLORS[4])
	assert_eq(UiTokens.grade_color(10.0), UiTokens.GRADE_COLORS[5])


func _piece_color_at(pieces: Array[Dictionary], s: float) -> Color:
	for piece in pieces:
		if s >= float(piece["s0"]) and s < float(piece["s1"]):
			return piece["color"]
	return Color.TRANSPARENT


func test_grade_pieces_follow_profile_grade() -> void:
	var model := RoutePreviewModel.for_profile(_frd03_profile())
	var p := model.plot(RoutePreviewModel.Mode.LARGE, Rect2(0, 0, 3000, 100))
	var pieces := model.grade_pieces(p)
	assert_eq(_piece_color_at(pieces, 500.0), UiTokens.grade_color(0.0), "ровно — шалфей")
	assert_eq(_piece_color_at(pieces, 1500.0), UiTokens.grade_color(5.0), "+5 % — терракота")
	assert_eq(_piece_color_at(pieces, 2500.0), UiTokens.grade_color(-5.0), "−5 % — сланец")


func test_grade_pieces_cover_lap_without_gaps_and_min_width() -> void:
	for route_id in RouteCatalog.ids():
		var model := _model(route_id)
		for w in [213, 320, 431]:
			var p := model.plot(RoutePreviewModel.Mode.THUMB, Rect2(0, 0, w, 60))
			var pieces := model.grade_pieces(p)
			assert_gt(pieces.size(), 0)
			assert_almost_eq(float(pieces[0]["s0"]), 0.0, 1e-9)
			assert_almost_eq(float(pieces[-1]["s1"]), model.length_m(), 1e-6)
			var bad: Array[String] = []
			for i in pieces.size():
				var px: float = (float(pieces[i]["s1"]) - float(pieces[i]["s0"])) * p.px_per_m()
				if px < RoutePreviewModel.MIN_PIECE_PX - 1e-6:
					bad.append("кусок %d: %.2f px" % [i, px])
				if i > 0:
					if absf(float(pieces[i]["s0"]) - float(pieces[i - 1]["s1"])) > 1e-6:
						bad.append("зазор перед куском %d" % i)
					if pieces[i]["color"] == pieces[i - 1]["color"]:
						bad.append("соседи %d одного цвета" % i)
				if not UiTokens.GRADE_COLORS.has(pieces[i]["color"]):
					bad.append("цвет %d не из палитры уклона" % i)
			assert_eq(bad, [] as Array[String], "%s, ширина %d" % [route_id, w])


func test_grade_colors_differ_from_power_zone_colors() -> void:
	for token in ZonePalette.POWER_TOKENS:
		assert_false(UiTokens.GRADE_COLORS.has(ZonePalette.color(token)), token)


func test_mountains_profile_shows_steep_colors_flat_does_not() -> void:
	var colors_of := func(route_id: String) -> Dictionary:
		var model := _model(route_id)
		var found: Dictionary = {}
		for piece in model.grade_pieces(model.plot(RoutePreviewModel.Mode.THUMB, Rect2(0, 0, 320, 60))):
			found[piece["color"]] = true
		return found
	var mountains: Dictionary = colors_of.call(RouteCatalog.MOUNTAINS)
	assert_true(mountains.has(UiTokens.GRADE_COLORS[4]), "горы: кирпич (7…10 %)")
	assert_true(mountains.has(UiTokens.GRADE_COLORS[0]), "горы: спуск сланцем")
	var flat: Dictionary = colors_of.call(RouteCatalog.FLAT)
	assert_eq(flat.keys(), [UiTokens.GRADE_COLORS[1]], "равнина — только шалфей")


func test_fill_matches_outline() -> void:
	var model := _model(RouteCatalog.HILLS)
	var p := model.plot(RoutePreviewModel.Mode.THUMB, FIELD)
	var fill := model.fill(p)
	assert_eq(fill.size(), model.grade_pieces(p).size())
	var outline := model.outline(p)
	assert_almost_eq(fill[0]["top"][0].x, FIELD.position.x, 1e-4)
	assert_almost_eq(fill[-1]["top"][-1].x, FIELD.end.x, 1e-4)
	assert_almost_eq(fill[0]["top"][0].y, outline[0].y, 1e-4)
	for piece in fill:
		var top: PackedVector2Array = piece["top"]
		assert_true(top.size() >= 2)
		for pt in top:
			assert_true(pt.y >= FIELD.position.y - 1e-4 and pt.y <= FIELD.end.y + 1e-4, "заливка в поле")


# --- FRD-03 крит. 6 (модель): подписи --------------------------------------------------

func test_km_step_rule() -> void:
	assert_eq(RoutePreviewModel.km_step(3000.0), 1)
	assert_eq(RoutePreviewModel.km_step(9000.0), 1)  # 10 подписей
	assert_eq(RoutePreviewModel.km_step(10000.0), 2)  # при шаге 1 — 11 подписей
	assert_eq(RoutePreviewModel.km_step(12000.0), 2)
	assert_eq(RoutePreviewModel.km_step(15000.0), 2)
	assert_eq(RoutePreviewModel.km_step(20000.0), 5)  # при шаге 2 — 11 подписей
	assert_eq(RoutePreviewModel.km_step(100000.0), 20)
	var labels := _model(RouteCatalog.FLAT).km_labels()
	var texts: Array[String] = []
	for l in labels:
		texts.append(str(l["text"]))
	assert_eq(texts, ["0", "2", "4", "6", "8", "10"] as Array[String])
	assert_almost_eq(float(labels[-1]["fraction"]), 1.0, 1e-9)
	for route_id in RouteCatalog.ids():
		assert_true(_model(route_id).km_labels().size() <= RoutePreviewModel.MAX_KM_LABELS, route_id)


func test_climb_labels() -> void:
	TranslationServer.set_locale("ru")
	var mountains := _model(RouteCatalog.MOUNTAINS).climb_labels()
	assert_eq(mountains.size(), 1)
	assert_false(mountains[0]["short"])
	assert_eq(mountains[0]["text"], "подъём 7.0 км · 6.0 %")
	var hills := _model(RouteCatalog.HILLS).climb_labels()
	assert_eq(hills.size(), 4, "холмы — все четыре")
	for label in hills:
		assert_true(label["short"])
		assert_false(str(label["text"]).contains("подъём"))
	assert_eq(hills[1]["text"], "1.2 км · 5.7 %")
	for i in range(1, hills.size()):
		assert_true(float(hills[i]["start_m"]) > float(hills[i - 1]["start_m"]), "по порядку s")
	assert_eq(_model(RouteCatalog.FLAT).climb_labels().size(), 0)
	TranslationServer.set_locale("en")
	assert_eq(_model(RouteCatalog.MOUNTAINS).climb_labels()[0]["text"], "climb 7.0 km · 6.0 %")


func test_height_labels_and_peak() -> void:
	TranslationServer.set_locale("ru")
	var model := _model(RouteCatalog.MOUNTAINS)
	var labels := model.height_labels()
	assert_eq(labels[0]["text"], "738 м")
	assert_eq(labels[1]["text"], "300 м")
	assert_true(model.marks_peak)
	assert_almost_eq(model.profile.height_at(model.peak_s_m()), model.profile.max_height_m(), 1e-6)
	assert_false(_model(RouteCatalog.HILLS).marks_peak)


func test_bridge_only_on_seaside() -> void:
	TranslationServer.set_locale("ru")
	var seaside := _model(RouteCatalog.SEASIDE)
	assert_true(seaside.has_bridge())
	assert_eq(seaside.bridges, RouteCatalog.get_route(RouteCatalog.SEASIDE).bridges)
	assert_eq(RoutePreviewModel.bridge_text(), "мост")
	for route_id in [RouteCatalog.FLAT, RouteCatalog.HILLS, RouteCatalog.MOUNTAINS]:
		assert_false(_model(route_id).has_bridge(), route_id)


# --- UIX-03 крит. 4 (трасса): одна модель для превью и HUD -----------------------------

func test_window_plot_for_hud_uses_same_series() -> void:
	var model := _model(RouteCatalog.FLAT)
	var length := model.length_m()
	# «Впереди 2 км» через стык круга: s − 200 … s + 2000 при s = L − 500.
	var s := length - 500.0
	var p := model.window_plot(s - 200.0, s + 2000.0, Rect2(0, 0, 200, 44), 40.0)
	assert_true(p.h_top - p.h_bottom >= 40.0 - 1e-9, "минимальный размах 40 м")
	var pts := model.series(p)
	assert_almost_eq(pts[0].x, s - 200.0, 1e-6)
	assert_almost_eq(pts[-1].x, s + 2000.0, 1e-6)
	assert_true(pts.size() <= 400)
	for pt in pts:
		assert_almost_eq(pt.y, model.profile.height_at(pt.x), 1e-3)
	var pieces := model.grade_pieces(p)
	assert_almost_eq(float(pieces[0]["s0"]), s - 200.0, 1e-6)
	assert_almost_eq(float(pieces[-1]["s1"]), s + 2000.0, 1e-6)
	# Точки серии круга — те же значения профиля, что и у окна.
	var lap := model.lap_series(100000)
	assert_almost_eq(lap[150].y, model.profile.height_at(lap[150].x), 1e-3)


func test_invalid_profile_is_safe() -> void:
	var model := RoutePreviewModel.for_profile(RouteProfile.from_points(PackedVector2Array([Vector2(0, 0)])))
	assert_false(model.is_valid())
	var p := model.plot(RoutePreviewModel.Mode.THUMB, FIELD)
	assert_eq(model.series(p).size(), 0)
	assert_eq(model.grade_pieces(p).size(), 0)
	assert_eq(model.fill(p).size(), 0)
	assert_eq(model.climb_labels().size(), 0)
	assert_eq(model.height_labels().size(), 0)
	assert_eq(model.stats().size(), 3)


# --- RoutePreview (узел) ----------------------------------------------------------------

func test_route_preview_node_thumb_and_large() -> void:
	var preview := RoutePreview.new()
	preview.size = Vector2(320, 140)
	add_child_autofree(preview)
	preview.set_route(RouteCatalog.get_route(RouteCatalog.SEASIDE))
	assert_eq(preview.mouse_filter, Control.MOUSE_FILTER_PASS, "без интерактива: нажатие уходит карточке")
	assert_eq(preview.mode, RoutePreviewModel.Mode.THUMB)
	assert_eq(preview.field_rect(), Rect2(12, 12, 296, 116), "поля 12 фона InsetPanel")
	assert_eq(preview.get_combined_minimum_size().y, RoutePreview.THUMB_MIN_HEIGHT)
	await wait_process_frames(2)
	preview.mode = RoutePreviewModel.Mode.LARGE
	var gutter := preview.height_gutter_width()
	assert_gt(gutter, 0.0, "колонка подписей высот слева")
	assert_eq(preview.field_rect(), Rect2(gutter, 0, 320 - gutter, 140 - RoutePreview.AXIS_HEIGHT))
	assert_eq(preview.current_plot().rect, preview.field_rect())
	assert_eq(preview.get_combined_minimum_size().y, RoutePreview.LARGE_MIN_HEIGHT)
	await wait_process_frames(2)
	preview.model = null
	assert_null(preview.current_plot())
	await wait_process_frames(1)


func test_route_preview_has_no_theme_overrides() -> void:
	var source := FileAccess.get_file_as_string("res://src/ui/tracks/route_preview.gd")
	assert_false(source.contains("add_theme_"), "без локальных переопределений темы")
	assert_false(source.contains("theme_override"), "без theme_override_*")
