extends GutTest
## Приёмка T-092 (tester): ориентиры трасс `RouteCatalog.landmarks` по `docs/game/tracks.md`
## п. 4.5 (s, тип, сторона, план) и разрыв между соседними ориентирами по кругу (включая стык)
## ≤ 1.5 км — REQ-D3D-08 крит. 12.
##
## Отличия от тестов разработчика: эталон — не таблица, переписанная в тест, а сам
## `docs/game/tracks.md` п. 4.5, разобранный тестом (столбцы s_m, type, Сторона, План);
## разрыв считается тестом по данным каталога, включая стык `L − s_last + s_first`, и
## сверяется со столбцом «Разрыв» документа; длина L — по профилю каталога.

const TRACKS_MD: String = "res://docs/game/tracks.md"
const MAX_GAP_M: float = 1500.0
const PLANES: Dictionary = {"у дороги": "near", "средний": "mid", "дальний": "far"}


## Таблицы п. 4.5: id трассы → массив строк `{s, type, side, plane, gap}`.
func _doc_landmarks() -> Dictionary:
	var text := FileAccess.get_file_as_string(TRACKS_MD)
	var start: int = text.find("### 4.5.")
	var end: int = text.find("\n## 5.", start)
	assert_gt(start, 0, "в tracks.md есть п. 4.5")
	var section: String = text.substr(start, end - start)
	var out: Dictionary = {}
	var current: String = ""
	var head := RegEx.create_from_string("^\\*\\*`([a-z]+)`, L = ([0-9 ]+) м\\*\\*")
	var row := RegEx.create_from_string("^\\|\\s*(\\d+)\\s*\\|\\s*`([a-z_]+)`\\s*\\|\\s*([a-z]+)\\s*\\|\\s*([^|]+?)\\s*\\|[^|]*\\|\\s*(\\d+)")
	for line in section.split("\n"):
		var h := head.search(line)
		if h != null:
			current = h.get_string(1)
			out[current] = []
			continue
		var m := row.search(line)
		if m != null and not current.is_empty():
			(out[current] as Array).append({
				"s": float(m.get_string(1)), "type": m.get_string(2), "side": m.get_string(3),
				"plane": PLANES.get(m.get_string(4), "?" + m.get_string(4)), "gap": float(m.get_string(5)),
			})
	return out


func test_req_d3d_08_c12_catalog_landmarks_equal_tracks_md_4_5_with_side_and_plane() -> void:
	var doc := _doc_landmarks()
	assert_eq(doc.keys().size(), 4, "в п. 4.5 — таблицы четырёх трасс: %s" % str(doc.keys()))
	for id in RouteCatalog.IDS:
		assert_true(doc.has(id), "%s: таблица в tracks.md" % id)
		if not doc.has(id):
			continue
		var want: Array = doc[id]
		var got: Array = RouteCatalog.get_route(id).landmarks
		assert_eq(got.size(), want.size(), "%s: ориентиров в каталоге столько же, сколько в таблице" % id)
		var diff: Array[String] = []
		for i in mini(got.size(), want.size()):
			var g: RouteCatalog.Landmark = got[i]
			var w: Dictionary = want[i]
			if absf(g.s_m - float(w["s"])) > 0.5 or g.type != w["type"] or g.side != w["side"] or g.plane != w["plane"]:
				diff.append("#%d: каталог (%.0f, %s, %s, %s) ≠ документ (%.0f, %s, %s, %s)" % [i, g.s_m, g.type, g.side,
					g.plane, w["s"], w["type"], w["side"], w["plane"]])
		assert_eq(diff, [] as Array[String], "%s: s, тип, сторона и план — как в tracks.md" % id)


func test_req_d3d_08_c12_max_gap_including_seam_within_1500m_and_matches_doc_gaps() -> void:
	var doc := _doc_landmarks()
	for id in RouteCatalog.IDS:
		var route: RouteCatalog.RouteDef = RouteCatalog.get_route(id)
		var L: float = route.profile.length_m()
		var lm: Array = route.landmarks
		assert_gte(lm.size(), 2, "%s: ориентиров больше одного" % id)
		if lm.size() < 2:
			continue
		var gaps: Array[float] = []
		for i in lm.size():
			var s0: float = (lm[i] as RouteCatalog.Landmark).s_m
			var s1: float = (lm[(i + 1) % lm.size()] as RouteCatalog.Landmark).s_m
			var gap: float = s1 - s0 if i < lm.size() - 1 else L - s0 + s1
			gaps.append(gap)
			assert_true(s0 >= 0.0 and s0 < L, "%s: s = %.0f в круге [0; %.0f)" % [id, s0, L])
			if i < lm.size() - 1:
				assert_gt(s1, s0, "%s: ориентиры по возрастанию s, по одному на s" % id)
		var worst: float = 0.0
		for g in gaps:
			worst = maxf(worst, g)
		assert_lte(worst, MAX_GAP_M, "%s: макс. разрыв %.0f м (стык %.0f м)" % [id, worst, gaps.back()])
		var total: float = 0.0
		for g in gaps:
			total += g
		assert_almost_eq(total, L, 0.5, "%s: разрывы по кругу в сумме дают L" % id)
		if doc.has(id) and (doc[id] as Array).size() == gaps.size():
			for i in gaps.size():
				assert_almost_eq(gaps[i], float(doc[id][i]["gap"]), 0.5, "%s: разрыв #%d как в столбце «Разрыв»" % [id, i])

