extends GutTest
## Приёмка T-107 (tester): хвойные по спеке — REQ-D3D-10 п.1–4, REQ-D3D-07 п.1, REQ-D3D-08 п.6,
## REQ-D3D-05 п.4. Числа спеки (`docs/game/art-bible.md`, «Растительность: хвойные», ред. 4)
## записаны здесь независимо от констант `ConiferKit`: формы и доли по трассам, диапазоны
## вариаций, бюджет треугольников по уровням, дистанции уровней, размеры форм.
## Параметры экземпляров восстанавливаются из того, что уходит в MultiMesh (трансформ и цвет
## экземпляра расстановки), треугольники — из массивов меша слоя по слоту UV2.x, удаление от оси
## трассы — своим перебором оси с шагом 1 м. Расстановка повторяется теми же бюджетами, что у
## `RideScene` (совпадение с узлами сцены проверяется), — позиции экземпляров готового MultiMesh на
## headless-сервере недоступны.

const SCENE: String = "res://src/scene3d/ride_scene.tscn"
const IDS: Array[String] = ["flat", "hills", "mountains", "seaside"]
const SCENERY_LAYERS: Array[String] = ["Trees", "Conifers", "ConifersLod1", "ConifersLod2", "Bushes", "Tufts",
	"Poplars", "StoneWalls", "Boulders"]
const LOD_LAYERS: Array[String] = ["Conifers", "ConifersLod1", "ConifersLod2"]

## Распределение по трассам (спека, «Распределение по трассам»), допуск ±10 п.п.
const SPEC_MIX: Dictionary = {
	"flat": {"spruce": 0.50, "spruce_young": 0.35, "fir": 0.15},
	"hills": {"spruce": 0.50, "spruce_young": 0.30, "fir": 0.20},
	"mountains": {"spruce": 0.35, "fir": 0.35, "spruce_young": 0.15, "spruce_wind": 0.15},
	"seaside": {"stone_pine": 0.55, "stone_pine_young": 0.30, "stone_pine_lean": 0.15},
}
const SHARE_TOL: float = 0.10
## Масштаб (равномерный) по форме — таблица «Вариации» и таблица форм (молодые).
const SPEC_SCALE: Dictionary = {
	"spruce": Vector2(0.80, 1.25), "spruce_young": Vector2(0.40, 0.55), "fir": Vector2(0.85, 1.30),
	"spruce_wind": Vector2(0.85, 1.15), "stone_pine": Vector2(0.85, 1.20), "stone_pine_young": Vector2(0.55, 0.70),
	"stone_pine_lean": Vector2(0.85, 1.20),
}
const SPEC_STRETCH_SPRUCE := Vector2(0.92, 1.12)
const SPEC_STRETCH_PINE := Vector2(0.95, 1.05)
const SPEC_BRIGHT_SPRUCE := Vector2(0.88, 1.10)
const SPEC_BRIGHT_PINE := Vector2(0.90, 1.10)
const SPEC_R_SPRUCE := Vector2(0.94, 1.08)
const SPEC_B_SPRUCE := Vector2(0.94, 1.06)
const SPEC_R_PINE := Vector2(0.95, 1.08)
const SPEC_B_PINE := Vector2(0.95, 1.04)
const SPEC_TILT_SPRUCE_DEG: float = 3.0
const SPEC_TILT_SPRUCE_SLOPE_DEG: float = 5.0
const SPEC_TILT_PINE_DEG: float = 4.0
const SPEC_LEAN_DEG := Vector2(10.0, 20.0)
const SPEC_LEAN_YAW_DEG: float = 35.0
const SPEC_LEAN_SHORE_M: float = 150.0
## Именованные вариации: молодая ель W ×1.15, тон +6 %; молодая пиния Y ×0.85, тон +5 %.
const SPEC_YOUNG_SPRUCE_W: float = 1.15
const SPEC_YOUNG_SPRUCE_TONE: float = 1.06
const SPEC_YOUNG_PINE_Y: float = 0.85
const SPEC_YOUNG_PINE_TONE: float = 1.05
## Уровни детализации по удалению от оси трассы, м.
const SPEC_LOD0_M: float = 60.0
const SPEC_LOD1_M: float = 220.0
## Допуск точного удаления (своя ось с шагом 1 м против `RoadIndex`), м.
const LOD_EPS_M: float = 0.5
## Бюджет треугольников экземпляра: семейство меша → [LOD0, LOD1, LOD2] (таблица LOD).
const SPEC_TRIS: Dictionary = {"spruce": [480, 120, 40], "fir": [520, 130, 40], "pine": [640, 160, 40]}
## Семейство меша формы на уровне: ветровал на LOD1/LOD2 — меш ели (спека), молодые — меш своего
## семейства; на LOD0 у ветровала свой меш (бюджет 480 — как у ели).
const FORM_FAMILY: Dictionary = {
	"spruce": "spruce", "spruce_young": "spruce", "fir": "fir", "spruce_wind": "spruce",
	"stone_pine": "pine", "stone_pine_young": "pine", "stone_pine_lean": "pine",
}
## Бюджеты спеки: кадр и слои.
const SPEC_FRAME_TRIS: int = 260000
const SPEC_MAX_LAYERS: int = 6
const SPEC_TREE_LINE_BAND_M: float = 60.0
const SPEC_TREE_LINE_SHARE: float = 0.60
const SPEC_WIND_MAX_SHARE: float = 0.15
const SPEC_MOUNTAINS_SHADE_MIN: float = 0.92
## Материалов и шейдеров до T-107 — замер tester на 8489dc2 (рабочая ветка без T-107):
## `PerfBudget.count` и полный обход (next_pass, override, overlay).
const MATERIALS_BEFORE: Dictionary = {"flat": 5, "hills": 5, "mountains": 5, "seaside": 6}
const FULL_MATERIALS_BEFORE: Dictionary = {"flat": 8, "hills": 8, "mountains": 8, "seaside": 9}
const SHADERS_BEFORE: Dictionary = {"flat": 6, "hills": 6, "mountains": 6, "seaside": 7}
## T-106a3: the rider got its own shaders (`rider_toon.gdshader`, `rider_outline.gdshader`, region
## palette) instead of the shared toon/outline ones; materials stay the same, conifers add none.
const RIDER_SHADERS_T106A3: int = 2
## Размеры форм на масштабе 1 (таблица форм): H, м, и W / H.
const SPEC_H: Dictionary = {"spruce": 9.0, "fir": 11.0, "spruce_wind": 8.0, "stone_pine": 10.0, "stone_pine_lean": 9.0}
const SPEC_WH: Dictionary = {"spruce": Vector2(0.40, 0.45), "fir": Vector2(0.24, 0.28), "spruce_wind": Vector2(0.35, 0.35),
	"stone_pine": Vector2(0.85, 0.95), "stone_pine_lean": Vector2(0.9, 0.9)}

var _scenes: Dictionary = {}
var _layers: Dictionary = {}


func before_all() -> void:
	for id in IDS:
		var s: RideScene = load(SCENE).instantiate()
		s.route_id = id
		add_child(s)
		_scenes[id] = s


func after_all() -> void:
	for id in _scenes:
		var s: RideScene = _scenes[id]
		if is_instance_valid(s):
			s.free()
	_scenes.clear()
	_layers.clear()


# ---------------------------------------------------------------------------
# Расстановка как в `RideScene` и разбор экземпляров
# ---------------------------------------------------------------------------

## Слои расстановки трассы с бюджетами `RideScene._build_world` (ориентиры, мосты и столбики —
## «неподвижная» часть бюджета).
func _place(id: String) -> Array[SceneryBuilder.Layer]:
	if _layers.has(id):
		return _layers[id]
	var s: RideScene = _scenes[id]
	var fixed: Array = []
	if s.props() != null:
		fixed.append(s.props())
	fixed.append_array(s.landmark_nodes())
	fixed.append_array(s.bridge_nodes())
	var fixed_visible: int = PerfBudget.max_visible_along(fixed, s.track)
	var fixed_total: int = 0
	for n in fixed:
		fixed_total += int(PerfBudget.count(n)["multimesh_instances"])
	var spots: Array[LandmarkBuilder.Placed] = []
	spots.append_array(s.landmarks_placed())
	spots.append_array(s.bridges_placed())
	var e: EnvironmentSet = s.environment_set
	var reserve: int = 0 if PerfBudget.is_compact(s.track) else maxi(e.visible_reserve, 0)
	var layers: Array[SceneryBuilder.Layer] = SceneryBuilder.place(s.track, e, s.terrain(), null,
		PerfBudget.MAX_VISIBLE_MULTIMESH_INSTANCES - fixed_visible - reserve,
		PerfBudget.MAX_MULTIMESH_INSTANCES - fixed_total, LandmarkBuilder.keep_out(spots))
	_layers[id] = layers
	return layers


func _layer(id: String, layer_name: String) -> SceneryBuilder.Layer:
	for l in _place(id):
		if l.name == layer_name:
			return l
	return null


## Узел слоя в мире сцены (null — нет).
func _node(id: String, layer_name: String) -> MultiMeshInstance3D:
	for n in (_scenes[id] as RideScene).world_nodes():
		if String(n.name) == layer_name:
			return n as MultiMeshInstance3D
	return null


func _node_instances(n: MultiMeshInstance3D) -> int:
	return int(PerfBudget.count(n)["multimesh_instances"]) if n != null else 0


## Экземпляр хвойного, который уходит в MultiMesh сцены.
class Inst:
	var form: String
	var lod: int
	var layer: String
	var xf: Transform3D
	var col: Color
	var slot: int = 0
	var s: float


## Экземпляры хвойных сцены (после прореживания `keep`, как в узлах).
func _instances(id: String) -> Array[Inst]:
	var out: Array[Inst] = []
	for lod in LOD_LAYERS.size():
		var l: SceneryBuilder.Layer = _layer(id, LOD_LAYERS[lod])
		if l == null:
			continue
		for i in l.kept():
			var it := Inst.new()
			it.form = ConiferKit.FORM_KEYS[l.plants[i].form]
			it.lod = l.plants[i].lod
			it.layer = l.name
			it.xf = l.xf[i]
			it.col = l.col[i]
			it.slot = int(round(l.custom[i].r)) if not l.custom.is_empty() else 0
			it.s = l.plants[i].s
			out.append(it)
	return out


## Своя ли модель у формы на уровне (иначе — поправка масштаба и цвета чужого меша).
func _own_mesh(form: String, lod: int) -> bool:
	match form:
		"spruce", "spruce_young", "stone_pine", "stone_pine_young":
			return true
		"fir":
			return lod < 2
	return lod == 0


func _is_pine(form: String) -> bool:
	return form.begins_with("stone_pine")


## Треугольники меша слоя по слоту UV2.x (0 — меш одной формы) и габариты слота.
func _slots(mesh: Mesh) -> Dictionary:
	var arrays: Array = mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uv2: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2] if arrays[Mesh.ARRAY_TEX_UV2] != null else PackedVector2Array()
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var out: Dictionary = {}
	for t in range(0, idx.size(), 3):
		var slot: int = maxi(int(round(uv2[idx[t]].x)) - 1, 0) if not uv2.is_empty() else 0
		if not out.has(slot):
			out[slot] = {"tris": 0, "lo": Vector3(INF, INF, INF), "hi": Vector3(-INF, -INF, -INF), "radial": 0.0}
		var d: Dictionary = out[slot]
		d["tris"] = int(d["tris"]) + 1
		for k in 3:
			var v: Vector3 = verts[idx[t + k]]
			d["lo"] = (d["lo"] as Vector3).min(v)
			d["hi"] = (d["hi"] as Vector3).max(v)
			d["radial"] = maxf(float(d["radial"]), Vector2(v.x, v.z).length())
	return out


## Семейство геометрии слота по пропорции кроны — диаметр описанного круга кончиков (2 × наибольшее
## удаление от оси ствола) к высоте; независимо от констант `ConiferKit`.
func _family_of(slot: Dictionary) -> String:
	var wh: float = 2.0 * float(slot["radial"]) / maxf((slot["hi"] as Vector3).y, 1e-3)
	if wh < 0.32:
		return "fir"
	if wh < 0.65:
		return "spruce"
	return "pine"


# ---------------------------------------------------------------------------
# Ось трассы: точное удаление (свой перебор, шаг 1 м, сетка 50 м)
# ---------------------------------------------------------------------------

class Axis:
	const CELL: float = 50.0
	var pts := PackedVector2Array()
	var cells: Dictionary = {}

	func _init(track: Track, step: float) -> void:
		var sample := TrackSample.new()
		var n: int = int(ceil(track.length_m() / step))
		for i in n + 1:
			track.sample_into(minf(float(i) * step, track.length_m() - 0.001), sample)
			pts.append(Vector2(sample.position.x, sample.position.z))
		for i in pts.size():
			var key := Vector2i(floori(pts[i].x / CELL), floori(pts[i].y / CELL))
			if not cells.has(key):
				cells[key] = PackedInt32Array()
			var list: PackedInt32Array = cells[key]
			list.append(i)
			cells[key] = list

	## Расстояние в плане до ближайшего отрезка оси в пределах `reach` (дальше — INF).
	func distance(p: Vector3, reach: float) -> float:
		var q := Vector2(p.x, p.z)
		var r: int = int(ceil(reach / CELL)) + 1
		var c := Vector2i(floori(q.x / CELL), floori(q.y / CELL))
		var best: float = INF
		for cx in range(c.x - r, c.x + r + 1):
			for cz in range(c.y - r, c.y + r + 1):
				var key := Vector2i(cx, cz)
				if not cells.has(key):
					continue
				for i in cells[key]:
					for j in [i - 1, i]:
						if j < 0 or j + 1 >= pts.size():
							continue
						var a: Vector2 = pts[j]
						var ab: Vector2 = pts[j + 1] - a
						var len2: float = ab.length_squared()
						var t: float = clampf((q - a).dot(ab) / len2, 0.0, 1.0) if len2 > 1e-9 else 0.0
						best = minf(best, q.distance_to(a + ab * t))
		return best if best <= reach else INF

	## Индекс ближайшей точки оси (для s ближайшего витка).
	func nearest_index(p: Vector3, reach: float) -> int:
		var q := Vector2(p.x, p.z)
		var r: int = int(ceil(reach / CELL)) + 1
		var c := Vector2i(floori(q.x / CELL), floori(q.y / CELL))
		var best: float = INF
		var bi: int = -1
		for cx in range(c.x - r, c.x + r + 1):
			for cz in range(c.y - r, c.y + r + 1):
				var key := Vector2i(cx, cz)
				if not cells.has(key):
					continue
				for i in cells[key]:
					var d: float = q.distance_squared_to(pts[i])
					if d < best:
						best = d
						bi = i
		return bi


# ---------------------------------------------------------------------------
# Тесты
# ---------------------------------------------------------------------------

## Расстановка теста совпадает со сценой: число экземпляров каждого слоя хвойных и лиственных и
## формы в узлах сцены (метаданные `conifer_forms`) — те же, что у повторённой расстановки.
func test_t107_placement_matches_scene_nodes() -> void:
	for id in IDS:
		for layer_name in ["Trees"] + LOD_LAYERS:
			var l: SceneryBuilder.Layer = _layer(id, layer_name)
			var want: int = l.kept().size() if l != null else 0
			assert_eq(_node_instances(_node(id, layer_name)), want, "%s %s: экземпляров в узле = расстановка" % [id, layer_name])
		var meta: Dictionary = {}
		for layer_name in LOD_LAYERS:
			var n := _node(id, layer_name)
			if n == null:
				continue
			var forms: Dictionary = n.get_meta(&"conifer_forms", {})
			var sum: int = 0
			for k in forms:
				meta[k] = int(meta.get(k, 0)) + int(forms[k])
				sum += int(forms[k])
			assert_eq(sum, _node_instances(n), "%s %s: метаданные форм = экземпляры узла" % [id, layer_name])
		var mine: Dictionary = {}
		for it in _instances(id):
			mine[it.form] = int(mine.get(it.form, 0)) + 1
		assert_eq(mine, meta, "%s: формы в сцене = формы расстановки" % id)


## REQ-D3D-10 п.1, «Распределение по трассам»: в сцене каждой трассы — ровно набор форм спеки
## (≥ 3), доли ±10 п.п. от числа хвойных в сцене; ветровал — не выше 15 %; приморье — пинии.
func test_req_d3d_10_c1_forms_and_shares_by_spec_table() -> void:
	for id in IDS:
		var counts: Dictionary = {}
		var insts := _instances(id)
		for it in insts:
			counts[it.form] = int(counts.get(it.form, 0)) + 1
		var spec: Dictionary = SPEC_MIX[id]
		var got: Array = counts.keys()
		got.sort()
		var want: Array = spec.keys()
		want.sort()
		var placed: int = 0
		for layer_name in LOD_LAYERS:
			var l: SceneryBuilder.Layer = _layer(id, layer_name)
			placed += l.xf.size() if l != null else 0
		gut.p("%s: хвойных в сцене %d (расставлено до прореживания %d), формы %s" % [id, insts.size(), placed, str(counts)])
		assert_eq(got, want, "%s: набор форм — по спеке" % id)
		assert_gte(got.size(), 3, "%s: не меньше трёх форм" % id)
		for key in spec:
			var share: float = float(counts.get(key, 0)) / float(maxi(insts.size(), 1))
			assert_almost_eq(share, float(spec[key]), SHARE_TOL, "%s: доля %s %.3f" % [id, key, share])
		if counts.has("spruce_wind"):
			var w: float = float(counts["spruce_wind"]) / float(insts.size())
			assert_lte(w, SPEC_WIND_MAX_SHARE + 1e-9, "%s: ветровал не выше 15 %% (%d из %d = %.4f)" % [id, counts["spruce_wind"], insts.size(), w])
	for key in SPEC_MIX["seaside"]:
		assert_true(_is_pine(String(key)), "приморье — только пинии")


## «Распределение»: горы — в полосе 60 м ниже границы леса пихта и ветровал вместе ≥ 60 %; выше
## границы леса хвойных нет.
func test_mountains_tree_line_band_fir_and_wind_share() -> void:
	var s: RideScene = _scenes["mountains"]
	var line: float = s.environment_set.tree_line_m
	var band: int = 0
	var high: int = 0
	var above: int = 0
	for it in _instances("mountains"):
		var y: float = it.xf.origin.y
		if y > line + 0.5:
			above += 1
		elif y > line - SPEC_TREE_LINE_BAND_M:
			band += 1
			if it.form == "fir" or it.form == "spruce_wind":
				high += 1
	gut.p("горы: граница леса %.0f м, в полосе %d хвойных, пихта+ветровал %d" % [line, band, high])
	assert_gt(band, 10, "у границы леса есть хвойные")
	assert_gte(float(high) / float(maxi(band, 1)), SPEC_TREE_LINE_SHARE, "пихта и ветровал у границы леса ≥ 60 %%")
	assert_eq(above, 0, "выше границы леса хвойных нет")


## REQ-D3D-10 п.2: масштаб, растяжение по Y, наклон, поворот, яркость и множители R/B — из
## трансформа и цвета экземпляра MultiMesh — в диапазонах спеки; масштаб, поворот и оттенок
## различаются внутри каждой формы.
func test_req_d3d_10_c2_instance_variations_from_multimesh_data() -> void:
	for id in IDS:
		var s: RideScene = _scenes[id]
		var cs: float = s.environment_set.conifer_scale
		var shade: float = s.environment_set.conifer_shade
		var bad: Array[String] = []
		var spread: Dictionary = {}
		var checked: int = 0
		for it in _instances(id):
			var pine: bool = _is_pine(it.form)
			var b: Basis = it.xf.basis
			var tilt_deg: float = rad_to_deg(b.y.normalized().angle_to(Vector3.UP))
			var yaw: float = fposmod(atan2(-b.x.z, b.x.x), TAU)
			if not spread.has(it.form):
				spread[it.form] = {"scale": [], "yaw": [], "col": []}
			(spread[it.form]["yaw"] as Array).append(yaw)
			(spread[it.form]["col"] as Array).append(it.col)
			if it.form == "stone_pine_lean":
				var lean: float = tilt_deg if it.lod > 0 else 15.0
				if it.lod > 0 and (lean < SPEC_LEAN_DEG.x - 0.01 or lean > SPEC_LEAN_DEG.y + 0.01):
					bad.append("%s lean LOD%d s=%.0f: наклон %.1f°" % [id, it.lod, it.s, lean])
			else:
				var tmax: float = SPEC_TILT_PINE_DEG if pine else SPEC_TILT_SPRUCE_SLOPE_DEG
				if tilt_deg > tmax + 0.01:
					bad.append("%s %s s=%.0f: наклон оси %.2f°" % [id, it.form, it.s, tilt_deg])
			if not _own_mesh(it.form, it.lod):
				continue
			checked += 1
			var wmul: float = SPEC_YOUNG_SPRUCE_W if it.form == "spruce_young" else 1.0
			var hmul: float = SPEC_YOUNG_PINE_Y if it.form == "stone_pine_young" else 1.0
			var scale: float = b.x.length() / (cs * wmul)
			var stretch: float = b.y.length() / (scale * cs * hmul)
			(spread[it.form]["scale"] as Array).append(scale)
			var sr: Vector2 = SPEC_SCALE[it.form]
			if scale < sr.x - 1e-4 or scale > sr.y + 1e-4:
				bad.append("%s %s s=%.0f: масштаб %.3f" % [id, it.form, it.s, scale])
			var st: Vector2 = SPEC_STRETCH_PINE if pine else SPEC_STRETCH_SPRUCE
			if stretch < st.x - 1e-4 or stretch > st.y + 1e-4:
				bad.append("%s %s s=%.0f: растяжение %.3f" % [id, it.form, it.s, stretch])
			var tone: float = SPEC_YOUNG_SPRUCE_TONE if it.form == "spruce_young" else (SPEC_YOUNG_PINE_TONE if it.form == "stone_pine_young" else 1.0)
			var bright: float = it.col.g / (tone * shade)
			var red: float = it.col.r / it.col.g
			var blue: float = it.col.b / it.col.g
			var br: Vector2 = SPEC_BRIGHT_PINE if pine else SPEC_BRIGHT_SPRUCE
			var rr: Vector2 = SPEC_R_PINE if pine else SPEC_R_SPRUCE
			var bb: Vector2 = SPEC_B_PINE if pine else SPEC_B_SPRUCE
			if bright < br.x - 1e-4 or bright > br.y + 1e-4:
				bad.append("%s %s s=%.0f: яркость %.3f" % [id, it.form, it.s, bright])
			if red < rr.x - 1e-4 or red > rr.y + 1e-4 or blue < bb.x - 1e-4 or blue > bb.y + 1e-4:
				bad.append("%s %s s=%.0f: R %.3f B %.3f" % [id, it.form, it.s, red, blue])
		assert_gt(checked, 0, "%s: экземпляры проверены" % id)
		assert_eq(bad, [] as Array[String], "%s: вариации в диапазонах спеки: %s" % [id, str(bad.slice(0, 6))])
		for form in spread:
			var d: Dictionary = spread[form]
			var n: int = (d["yaw"] as Array).size()
			if n < 2:
				continue
			var yaws: Array = d["yaw"]
			assert_gt(float(yaws.max()) - float(yaws.min()), 1e-3, "%s %s: поворот различается" % [id, form])
			var cols: Array = d["col"]
			var differ: bool = false
			for c in cols:
				if not (c as Color).is_equal_approx(cols[0]):
					differ = true
					break
			assert_true(differ, "%s %s: оттенок различается" % [id, form])
			var scales: Array = d["scale"]
			if scales.size() >= 2:
				assert_gt(float(scales.max()) - float(scales.min()), 1e-3, "%s %s: масштаб различается" % [id, form])
			if n >= 40:
				# Поворот 0–360° равномерно: каждая четверть круга занята.
				var q := [0, 0, 0, 0]
				for y in yaws:
					q[mini(int(float(y) / (TAU / 4.0)), 3)] += 1
				assert_false(q.has(0), "%s %s: поворот по всему кругу %s" % [id, form, str(q)])


## REQ-D3D-10 п.3: треугольников в экземпляре каждой формы на каждом уровне ≤ спеки — по слоту
## меша слоя сцены; слот экземпляра указывает на геометрию своего семейства (ель / пихта / пиния).
func test_req_d3d_10_c3_triangles_per_form_and_lod_in_scene_meshes() -> void:
	for id in IDS:
		var bad: Array[String] = []
		for lod in LOD_LAYERS.size():
			var node := _node(id, LOD_LAYERS[lod])
			var l: SceneryBuilder.Layer = _layer(id, LOD_LAYERS[lod])
			if node == null:
				assert_true(l == null or l.kept().is_empty(), "%s %s: узла нет — экземпляров нет" % [id, LOD_LAYERS[lod]])
				continue
			var slots: Dictionary = _slots(node.multimesh.mesh)
			var line: Array[String] = []
			for k in slots:
				line.append("слот %d %s %d" % [k, _family_of(slots[k]), int(slots[k]["tris"])])
			gut.p("%s %s: %s; всего в меше %d" % [id, LOD_LAYERS[lod], ", ".join(line), node.multimesh.mesh.surface_get_array_index_len(0) / 3])
			if slots.size() > 1:
				assert_true(node.multimesh.use_custom_data, "%s %s: меш нескольких форм — у экземпляров есть слот формы" % [id, LOD_LAYERS[lod]])
			var seen: Dictionary = {}
			for it in _instances(id):
				if it.lod != lod:
					continue
				if seen.has([it.form, it.slot]):
					continue
				seen[[it.form, it.slot]] = true
				if not slots.has(it.slot):
					bad.append("%s LOD%d: слот %d вне меша" % [it.form, lod, it.slot])
					continue
				var fam: String = FORM_FAMILY[it.form]
				if it.form == "fir" and lod == 2:
					fam = _family_of(slots[it.slot])
					if fam != "spruce" and fam != "fir":
						bad.append("fir LOD2: геометрия %s" % fam)
				if _family_of(slots[it.slot]) != fam:
					bad.append("%s LOD%d: слот %d — геометрия %s, ждали %s" % [it.form, lod, it.slot, _family_of(slots[it.slot]), fam])
				var budget: int = int((SPEC_TRIS["fir" if it.form == "fir" else fam] as Array)[lod])
				var tris: int = int(slots[it.slot]["tris"])
				if tris > budget:
					bad.append("%s LOD%d: %d треугольников > %d" % [it.form, lod, tris, budget])
		assert_eq(bad, [] as Array[String], "%s: %s" % [id, str(bad)])


## REQ-D3D-10 п.3, «Уровни детализации»: у каждого хвойного сцены уровень — по точному удалению
## от оси трассы (своя ось, шаг 1 м, все витки): LOD0 w ≤ 60, LOD1 60 < w ≤ 220, LOD2 w > 220;
## экземпляр в слое своего уровня; «Перевал»: деревья у соседнего витка серпантина тоже.
func test_req_d3d_10_c3_lod_by_exact_axis_distance_all_instances() -> void:
	for id in IDS:
		var s: RideScene = _scenes[id]
		var axis := Axis.new(s.track, 1.0)
		var bad: Array[String] = []
		var per_lod := [0, 0, 0]
		var other_turn: int = 0
		var max_err: float = 0.0
		for it in _instances(id):
			per_lod[it.lod] += 1
			if it.layer != LOD_LAYERS[it.lod]:
				bad.append("s=%.0f: LOD%d в слое %s" % [it.s, it.lod, it.layer])
			var w: float = axis.distance(it.xf.origin, SPEC_LOD1_M + 30.0)
			var ok: bool
			match it.lod:
				0:
					ok = w <= SPEC_LOD0_M + LOD_EPS_M
				1:
					ok = w > SPEC_LOD0_M - LOD_EPS_M and w <= SPEC_LOD1_M + LOD_EPS_M
				_:
					ok = w > SPEC_LOD1_M - LOD_EPS_M
			if not ok:
				bad.append("s=%.0f: LOD%d, до оси %.2f м" % [it.s, it.lod, w])
			if w < INF:
				var lod_true: int = 0 if w <= SPEC_LOD0_M else (1 if w <= SPEC_LOD1_M else 2)
				if lod_true != it.lod:
					max_err = maxf(max_err, minf(absf(w - SPEC_LOD0_M), absf(w - SPEC_LOD1_M)))
			# Ближайший виток — не свой участок s (серпантин, соседняя петля).
			var k: int = axis.nearest_index(it.xf.origin, SPEC_LOD1_M + 30.0)
			if k >= 0:
				var ds: float = absf(float(k) - it.s)
				ds = minf(ds, s.track.length_m() - ds)
				if ds > 400.0:
					other_turn += 1
		gut.p("%s: LOD0/1/2 = %s; ближе к чужому витку (> 400 м по s): %d; макс. промах у границы %.2f м" % [id, str(per_lod), other_turn, max_err])
		assert_eq(bad, [] as Array[String], "%s: уровни по точному удалению: %s" % [id, str(bad.slice(0, 6))])
		if id == "mountains":
			assert_gt(other_turn, 0, "горы: проверены деревья у соседнего витка серпантина")
		# Уровни переключаются в пределах дальности видимости кусков растительности — как у деревьев.
		# Спека: `visibility_range_end` деревьев 1500 м не меняется.
		var trees_range: float = 1500.0
		for layer_name in LOD_LAYERS:
			var n := _node(id, layer_name)
			if n == null:
				continue
			for part: GeometryInstance3D in [n] + n.get_children():
				assert_eq(part.visibility_range_begin, 0.0, "%s %s: без переключения в кадре" % [id, layer_name])
				if part.visibility_range_end > 0.0:
					assert_almost_eq(part.visibility_range_end, trees_range, 1e-3, "%s %s: дальность — как у лиственных" % [id, layer_name])


## «Распределение» (приморье): наклонные пинии — в 150 м от кромки воды и наклонены к воде ±35°.
## Кромка — точки с глубиной > 0 (перебор 72 направлений с шагом 2 м). Наклон засчитывается, если
## он в пределах 35° + 5° (допуск замера) от направления хоть на одну точку воды не дальше
## ближайшей + 10 м (вода с двух сторон, бухты — не штрафуются).
func test_seaside_lean_pines_near_water_and_lean_toward_it() -> void:
	var s: RideScene = _scenes["seaside"]
	var tf: TerrainField = s.terrain()
	var far: Array[String] = []
	var off: Array[String] = []
	var n: int = 0
	var to_river: int = 0
	var angles: Array = []
	for it in _instances("seaside"):
		if it.form != "stone_pine_lean":
			continue
		n += 1
		var p: Vector3 = it.xf.origin
		var dist: float = INF
		var dirs: Array[Vector3] = []
		var d: float = 2.0
		while d <= 200.0 and d <= dist + 10.0:
			for k in 72:
				var a: float = TAU * float(k) / 72.0
				if tf.water_depth_at(p.x + cos(a) * d, p.z + sin(a) * d) > 0.0:
					dirs.append(Vector3(cos(a), 0.0, sin(a)))
					dist = minf(dist, d)
			d += 2.0
		if dist > SPEC_LEAN_SHORE_M:
			far.append("s=%.0f: до воды %.0f м" % [it.s, dist])
			continue
		var wq: Vector3 = p + dirs[0] * (dist + 2.0)
		var river: bool = tf.sea_mask_at(wq.x, wq.z) < 0.5
		if river:
			to_river += 1
		var lean_dir: Vector3 = it.xf.basis.x if it.lod == 0 else it.xf.basis.y
		lean_dir.y = 0.0
		lean_dir = lean_dir.normalized()
		var best: float = 180.0
		for w in dirs:
			best = minf(best, rad_to_deg(lean_dir.angle_to(w)))
		angles.append(best)
		if best > SPEC_LEAN_YAW_DEG + 5.0:
			off.append("s=%.0f LOD%d: до воды %.0f м%s, наклон от воды на %.0f°" % [it.s, it.lod, dist, " (река)" if river else "", best])
	angles.sort()
	if not angles.is_empty():
		gut.p("приморье: наклонных %d, ближайшая вода — река %d; угол к воде медиана %.0f°, p90 %.0f°, макс %.0f°; > 40°: %d" % [n, to_river,
			float(angles[angles.size() / 2]), float(angles[int(angles.size() * 0.9)]), float(angles[-1]), off.size()])
	assert_gt(n, 10, "наклонные пинии есть")
	assert_eq(far, [] as Array[String], "наклонные — в 150 м от воды: %s" % str(far.slice(0, 6)))
	assert_eq(off, [] as Array[String], "наклон к воде ±35° (допуск замера 5°): %d из %d: %s" % [off.size(), n, str(off.slice(0, 8))])


## Детерминизм: повторная расстановка (и после расстановки другой трассы) даёт те же формы,
## уровни, трансформы, цвета и слоты; меш слоя сцены — тот же объект кэша.
func test_conifer_placement_deterministic() -> void:
	for id in ["mountains", "seaside"]:
		var first: Array[Inst] = _instances(id)
		_layers.erase(id)
		_place("flat")
		_layers.erase("flat")
		var second: Array[Inst] = _instances(id)
		assert_eq(second.size(), first.size(), "%s: то же число хвойных" % id)
		var diff: int = 0
		for i in mini(first.size(), second.size()):
			var a: Inst = first[i]
			var b: Inst = second[i]
			if a.form != b.form or a.lod != b.lod or a.slot != b.slot or not a.xf.is_equal_approx(b.xf) or not a.col.is_equal_approx(b.col):
				diff += 1
		assert_eq(diff, 0, "%s: расстановка хвойных повторяется" % id)


## Отдельная сцена той же трассы строит тот же лес (узлы, экземпляры, формы).
func test_conifer_scene_rebuild_same_forest() -> void:
	var s2: RideScene = load(SCENE).instantiate()
	s2.route_id = "mountains"
	add_child(s2)
	for layer_name in LOD_LAYERS:
		var a := _node("mountains", layer_name)
		var b: MultiMeshInstance3D = null
		for n in s2.world_nodes():
			if String(n.name) == layer_name:
				b = n as MultiMeshInstance3D
		assert_eq(b != null, a != null, "%s: узел есть в обеих сценах" % layer_name)
		if a != null and b != null:
			assert_eq(_node_instances(b), _node_instances(a), "%s: экземпляров столько же" % layer_name)
			assert_eq(b.get_meta(&"conifer_forms", {}), a.get_meta(&"conifer_forms", {}), "%s: формы те же" % layer_name)
			assert_eq(b.multimesh.mesh, a.multimesh.mesh, "%s: тот же меш слоя" % layer_name)
	s2.free()


## REQ-D3D-10 п.4, REQ-D3D-05 п.4, REQ-D3D-08 п.6: слоёв хвойных ≤ 6; материалов и шейдеров —
## столько же, сколько до T-107 (замер на 8489dc2), материалов ≤ 12; MultiMesh всего ≤ 40000,
## видимых с любой точки (шаг 50 м) ≤ 2000.
func test_req_d3d_10_c4_layers_materials_instances() -> void:
	for id in IDS:
		var s: RideScene = _scenes[id]
		var layers: int = 0
		for n in s.world_nodes():
			if String(n.name).begins_with("Conifer"):
				layers += 1
		assert_between(layers, 1, SPEC_MAX_LAYERS, "%s: слоёв MultiMesh хвойных" % id)
		var c: Dictionary = PerfBudget.count(s)
		var mats: Dictionary = {}
		var shaders: Dictionary = {}
		_walk_materials(s, mats, shaders)
		gut.p("%s: слоёв хвойных %d; материалов %d (полный обход %d), шейдеров %d; MultiMesh %d" % [id, layers,
			int(c["materials"]), mats.size(), shaders.size(), int(c["multimesh_instances"])])
		assert_lte(int(c["materials"]), int(MATERIALS_BEFORE[id]), "%s: материалов не больше, чем до T-107" % id)
		assert_lte(mats.size(), int(FULL_MATERIALS_BEFORE[id]), "%s: материалов (с проходом контура) не больше, чем до T-107" % id)
		assert_lte(shaders.size(), int(SHADERS_BEFORE[id]) + RIDER_SHADERS_T106A3, "%s: шейдеров не больше, чем до T-107 (+2 rider shaders of T-106a3)" % id)
		assert_lte(int(c["materials"]), 12, "%s: материалов ≤ 12" % id)
		assert_lte(int(c["multimesh_instances"]), 40000, "%s: MultiMesh всего ≤ 40000" % id)
		var visible: int = PerfBudget.max_visible_along([s], s.track, 50.0)
		gut.p("%s: видимых MultiMesh ≤ %d" % [id, visible])
		assert_lte(visible, 2000, "%s: видимых с любой точки ≤ 2000" % id)


func _walk_materials(n: Node, mats: Dictionary, shaders: Dictionary) -> void:
	if n is GeometryInstance3D:
		var g := n as GeometryInstance3D
		for m in _chain(g.material_override) + _chain(g.material_overlay):
			_note(m, mats, shaders)
		var mesh: Mesh = _mesh_of(n)
		if mesh != null:
			for i in mesh.get_surface_count():
				for m in _chain(mesh.surface_get_material(i)):
					_note(m, mats, shaders)
				if n is MeshInstance3D:
					for m in _chain((n as MeshInstance3D).get_surface_override_material(i)):
						_note(m, mats, shaders)
	for ch in n.get_children():
		_walk_materials(ch, mats, shaders)


func _note(m: Material, mats: Dictionary, shaders: Dictionary) -> void:
	mats[m.get_instance_id()] = true
	if m is ShaderMaterial and (m as ShaderMaterial).shader != null:
		shaders[(m as ShaderMaterial).shader.resource_path] = true


func _chain(m: Material) -> Array[Material]:
	var out: Array[Material] = []
	while m != null:
		out.append(m)
		m = m.next_pass
	return out


func _mesh_of(n: Node) -> Mesh:
	if n is MeshInstance3D:
		return (n as MeshInstance3D).mesh
	if n is MultiMeshInstance3D and (n as MultiMeshInstance3D).multimesh != null:
		return (n as MultiMeshInstance3D).multimesh.mesh
	return null


## «Бюджет»: треугольников хвойных в кадре ≤ 260 тыс. на любой точке — верхняя оценка без
## пирамиды камеры: все хвойные в кусках, чей центр в дальности видимости от точки трассы (шаг
## 50 м); треугольники экземпляра — по слоту своей формы. Отдельно (справка) — сколько
## треугольников уходит в GPU с вершинами чужих форм меша слоя.
func test_conifer_frame_triangles_upper_bound_all_tracks() -> void:
	for id in IDS:
		var s: RideScene = _scenes[id]
		var slot_tris: Dictionary = {}
		var mesh_tris: Dictionary = {}
		for lod in LOD_LAYERS.size():
			var node := _node(id, LOD_LAYERS[lod])
			if node == null:
				continue
			var slots: Dictionary = _slots(node.multimesh.mesh)
			for k in slots:
				slot_tris[[lod, k]] = int(slots[k]["tris"])
			mesh_tris[lod] = node.multimesh.mesh.surface_get_array_index_len(0) / 3
		# Куски: центр по экземплярам, как `chunked_multimesh` (номер куска — расстановка).
		var chunk_m: float = PerfBudget.chunk_length_m(s.track)
		var chunks: Dictionary = {}
		for lod in LOD_LAYERS.size():
			var l: SceneryBuilder.Layer = _layer(id, LOD_LAYERS[lod])
			if l == null:
				continue
			for i in l.kept():
				var key: Array = [lod, l.chunk[i] if l.chunks > 1 else 0]
				if not chunks.has(key):
					chunks[key] = {"lo": Vector3(INF, INF, INF), "hi": Vector3(-INF, -INF, -INF), "tris": 0, "gpu": 0}
				var c: Dictionary = chunks[key]
				c["lo"] = (c["lo"] as Vector3).min(l.xf[i].origin)
				c["hi"] = (c["hi"] as Vector3).max(l.xf[i].origin)
				var slot: int = int(round(l.custom[i].r)) if not l.custom.is_empty() else 0
				c["tris"] = int(c["tris"]) + int(slot_tris.get([lod, slot], 0))
				c["gpu"] = int(c["gpu"]) + int(mesh_tris.get(lod, 0))
		var best: int = 0
		var best_gpu: int = 0
		var best_at: float = 0.0
		var sample := TrackSample.new()
		var at: float = 0.0
		while at < s.track.length_m():
			s.track.sample_into(at, sample)
			var eye: Vector3 = sample.position + Vector3.UP * 2.0
			var t: int = 0
			var g: int = 0
			for key in chunks:
				var c: Dictionary = chunks[key]
				var center: Vector3 = ((c["lo"] as Vector3) + (c["hi"] as Vector3)) * 0.5
				if chunk_m <= 0.0 or eye.distance_to(center) <= PerfBudget.RANGE_TREES_M + PerfBudget.EYE_SLACK_M + 20.0:
					t += int(c["tris"])
					g += int(c["gpu"])
			if t > best:
				best = t
				best_at = at
			best_gpu = maxi(best_gpu, g)
			at += 50.0
		gut.p("%s: треугольников хвойных в дальности видимости (без пирамиды камеры) до %d (s=%.0f); в GPU с чужими формами до %d" % [id, best, best_at, best_gpu])
		# Спека: «на любой точке «Перевала»» — там оценка без пирамиды камеры уже строгая.
		if id == "mountains":
			assert_lte(best, SPEC_FRAME_TRIS, "%s: треугольников хвойных в кадре ≤ 260 тыс. (верхняя оценка без пирамиды)" % id)


## Бюджет кадра с пирамидой рабочей камеры (`docs/perf_budget.md`: «в кадре рабочей камеры»,
## ≤ 260 тыс.) на всех трассах, шаг 100 м: свой отбор кусков — дальность видимости до центра
## габарита куска и габарит не целиком за плоскостью пирамиды; габарит — позиции экземпляров
## расстановки ± диагональ меша слоя.
func test_conifer_frame_triangles_in_camera_frustum_all_tracks() -> void:
	for id in IDS:
		var s: RideScene = _scenes[id]
		var boxes: Array = []
		for lod in LOD_LAYERS.size():
			var node := _node(id, LOD_LAYERS[lod])
			var l: SceneryBuilder.Layer = _layer(id, LOD_LAYERS[lod])
			if node == null or l == null:
				continue
			var slots: Dictionary = _slots(node.multimesh.mesh)
			var pad: float = node.multimesh.mesh.get_aabb().size.length()
			var range_m: float = 0.0
			for part: GeometryInstance3D in [node] + node.get_children():
				range_m = maxf(range_m, part.visibility_range_end + part.visibility_range_end_margin)
			var per: Dictionary = {}
			for i in l.kept():
				var k: int = l.chunk[i] if l.chunks > 1 else 0
				if not per.has(k):
					per[k] = {"lo": Vector3(INF, INF, INF), "hi": Vector3(-INF, -INF, -INF), "tris": 0, "range": range_m}
				var c: Dictionary = per[k]
				c["lo"] = (c["lo"] as Vector3).min(l.xf[i].origin)
				c["hi"] = (c["hi"] as Vector3).max(l.xf[i].origin)
				var slot: int = int(round(l.custom[i].r)) if not l.custom.is_empty() else 0
				c["tris"] = int(c["tris"]) + int(slots[slot]["tris"])
			for k in per:
				var c: Dictionary = per[k]
				var lo: Vector3 = (c["lo"] as Vector3) - Vector3.ONE * pad
				var hi: Vector3 = (c["hi"] as Vector3) + Vector3.ONE * pad
				boxes.append([AABB(lo, hi - lo), int(c["tris"]), float(c["range"])])
		var best: int = 0
		var best_at: float = 0.0
		var at: float = 0.0
		while at < s.track.length_m():
			s.distance_m = fposmod(at - 32.0 / 3.6 / 60.0 * 30.0, s.track.length_m())
			s.apply_telemetry(0, false, 90, true, 32.0, true)
			for f in 30:
				s.advance(1.0 / 60.0)
			var cam: Camera3D = s.camera()
			var eye: Vector3 = cam.global_position
			var planes: Array = cam.get_frustum()
			var t: int = 0
			for b in boxes:
				var box: AABB = b[0]
				if float(b[2]) > 0.0 and eye.distance_to(box.get_center()) > float(b[2]):
					continue
				var inside: bool = true
				for pl: Plane in planes:
					var all_over: bool = true
					for e in 8:
						if not pl.is_point_over(box.get_endpoint(e)):
							all_over = false
							break
					if all_over:
						inside = false
						break
				if inside:
					t += int(b[1])
			if t > best:
				best = t
				best_at = at
			at += 100.0
		gut.p("%s: треугольников хвойных в кадре (пирамида камеры) до %d (s=%.0f)" % [id, best, best_at])
		assert_lte(best, SPEC_FRAME_TRIS, "%s: треугольников хвойных в кадре ≤ 260 тыс." % id)


## Маска UV2 в `toon.gdshader` / `outline.gdshader` (схлопывание чужих форм, крона без тени):
## ни один меш мира и гонщика, кроме мешей `ConiferKit`, не несёт UV2 при тун-материале или
## контуре — иначе его вершины схлопнутся или он перестанет принимать тень.
func test_toon_uv2_mask_touches_only_conifer_meshes() -> void:
	var conifer_meshes: Array = ConiferKit._meshes.values()
	for id in IDS:
		var s: RideScene = _scenes[id]
		var offenders: Array[String] = []
		var conifer_uv2: int = 0
		var checked: int = 0
		for g in _geometry(s):
			var mesh: Mesh = _mesh_of(g)
			if mesh == null:
				continue
			for i in mesh.get_surface_count():
				checked += 1
				if (mesh.surface_get_format(i) & Mesh.ARRAY_FORMAT_TEX_UV2) == 0:
					continue
				var toon: bool = false
				var mats: Array[Material] = _chain(mesh.surface_get_material(i)) + _chain(g.material_override)
				if g is MeshInstance3D:
					mats += _chain((g as MeshInstance3D).get_surface_override_material(i))
				for m in mats:
					if m is ShaderMaterial and (m as ShaderMaterial).shader != null:
						var path: String = (m as ShaderMaterial).shader.resource_path
						if path.ends_with("toon.gdshader") or path.ends_with("outline.gdshader"):
							toon = true
				if not toon:
					continue
				if conifer_meshes.has(mesh):
					conifer_uv2 += 1
				else:
					offenders.append("%s (%s)" % [g.get_path(), g.get_class()])
		gut.p("%s: поверхностей %d, хвойных с UV2 %d" % [id, checked, conifer_uv2])
		assert_gt(conifer_uv2, 0, "%s: меши хвойных несут UV2 (проверка работает)" % id)
		assert_eq(offenders, [] as Array[String], "%s: UV2 при тун-материале — только у хвойных: %s" % [id, str(offenders.slice(0, 6))])
	# Справка для T-106a4 (импорт `rider.glb`): есть ли UV2 в эталонных GLB пакета художнику.
	for path in ["res://assets/rider/reference/rider_rig_reference.glb", "res://assets/rider/reference/bike_reference.glb"]:
		if not ResourceLoader.exists(path):
			continue
		var scene: PackedScene = load(path)
		var root: Node = scene.instantiate()
		var with_uv2: int = 0
		for g in _geometry(root):
			var mesh: Mesh = _mesh_of(g)
			for i in (mesh.get_surface_count() if mesh != null else 0):
				if (mesh.surface_get_format(i) & Mesh.ARRAY_FORMAT_TEX_UV2) != 0:
					with_uv2 += 1
		gut.p("%s: поверхностей с UV2 — %d (риск для тун-материала при импорте T-106a4)" % [path, with_uv2])
		root.free()


func _geometry(root: Node) -> Array[GeometryInstance3D]:
	var out: Array[GeometryInstance3D] = []
	if root is GeometryInstance3D:
		out.append(root as GeometryInstance3D)
	for ch in root.get_children():
		out.append_array(_geometry(ch))
	return out


## Слой из одной формы — без слота (UV2.x = 0 у всех вершин): иначе без данных экземпляра шейдер
## схлопнет всё, кроме первой формы.
func test_single_form_layers_have_no_form_slot() -> void:
	for id in IDS:
		for layer_name in LOD_LAYERS:
			var n := _node(id, layer_name)
			if n == null:
				continue
			var slots: Dictionary = _slots(n.multimesh.mesh)
			if not n.multimesh.use_custom_data:
				assert_eq(slots.keys(), [0], "%s %s: без данных экземпляра — одна форма без слота" % [id, layer_name])


## Таблица форм: высота H и пропорция кроны W / H меша LOD0 каждой своей формы (масштаб 1), ствол
## виден у основания ели и пихты (0.10–0.14 H у ели, 0.08–0.10 H у пихты — низ кроны над землёй).
func test_form_table_heights_and_proportions_lod0() -> void:
	var models: Dictionary = {"spruce": ConiferKit.M_SPRUCE, "fir": ConiferKit.M_FIR, "spruce_wind": ConiferKit.M_WIND,
		"stone_pine": ConiferKit.M_PINE, "stone_pine_lean": ConiferKit.M_PINE_LEAN}
	for key in models:
		var mesh: ArrayMesh = ConiferKit.single_mesh(int(models[key]), 0, null)
		var arrays: Array = mesh.surface_get_arrays(0)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var uv2: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2]
		var lo := Vector3(INF, INF, INF)
		var hi := Vector3(-INF, -INF, -INF)
		var crown_lo: float = INF
		var radial: float = 0.0
		for i in verts.size():
			lo = lo.min(verts[i])
			hi = hi.max(verts[i])
			radial = maxf(radial, Vector2(verts[i].x, verts[i].z).length())
			if uv2[i].y > 0.99:
				crown_lo = minf(crown_lo, verts[i].y)
		var H: float = hi.y
		# Ели — диаметр описанного круга кончиков (у ветровала подветренная сторона короче, у
		# нижнего яруса 5 лап — габарит по осям меньше круга); пинии — габарит кроны.
		var W: float = maxf(hi.x - lo.x, hi.z - lo.z) if key.begins_with("stone_pine") else 2.0 * radial
		gut.p("%s LOD0: H %.2f м (спека %.1f), W/H %.3f (спека %s), низ кроны %.3f H" % [key, H, SPEC_H[key], W / H, str(SPEC_WH[key]), crown_lo / H])
		assert_almost_eq(H, float(SPEC_H[key]), float(SPEC_H[key]) * 0.05, "%s: высота H ±5 %%" % key)
		var wh: Vector2 = SPEC_WH[key]
		# Габарит по кончикам лап: кончики — ±12 % радиуса (спека), допуск на это.
		assert_between(W / H, wh.x * 0.88, wh.y * 1.12, "%s: W / H по габариту" % key)
		if key == "spruce":
			assert_between(crown_lo / H, 0.10 - 0.02, 0.14, "ель: ствол виден у основания ~0.10–0.14 H")
		elif key == "fir":
			assert_between(crown_lo / H, 0.08 - 0.02, 0.10, "пихта: ствол виден у основания ~0.08–0.10 H")


## «Не чёрные»: `conifer_shade` гор не ниже 0.92; строка бюджета хвойных в `docs/perf_budget.md`
## (треугольники по LOD — по арт-библии, в кадре ≤ 260 тыс., слоёв ≤ 6, эталон — MacBook на
## базовом M1).
func test_mountains_shade_and_perf_budget_row() -> void:
	var env: EnvironmentSet = (_scenes["mountains"] as RideScene).environment_set
	assert_gte(env.conifer_shade, SPEC_MOUNTAINS_SHADE_MIN, "горы: conifer_shade ≥ 0.92")
	var text: String = FileAccess.get_file_as_string("res://docs/perf_budget.md")
	var row := RegEx.create_from_string("\\|\\s*Хвойные[^|]*\\|\\s*260000\\s*\\|").search(text)
	assert_not_null(row, "строка бюджета: хвойные в кадре 260000")
	if row != null:
		assert_string_contains(row.get_string(), "MacBook на базовом M1", "эталон в строке бюджета")
	assert_not_null(RegEx.create_from_string("\\|[^|\\n]*хвойных[^|\\n]*\\|\\s*6\\s*\\|").search(text), "строка бюджета: слоёв хвойных ≤ 6")
	var sec: int = text.find("## Хвойные")
	assert_gt(sec, -1, "раздел «Хвойные» в perf_budget.md")
	if sec >= 0:
		var body: String = text.substr(sec, 1200)
		assert_string_contains(body, "LOD0/LOD1/LOD2", "треугольники на экземпляр по уровням")
		assert_string_contains(body, "art-bible.md", "ссылка на арт-библию")
		assert_string_contains(body, "≤ 260 тыс.", "в кадре ≤ 260 тыс.")
		assert_string_contains(body, "≤ 6", "слоёв ≤ 6")
		assert_string_contains(body, "MacBook на базовом M1", "эталон — MacBook на базовом M1")
