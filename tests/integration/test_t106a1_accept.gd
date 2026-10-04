extends GutTest
## Приёмка T-106a1 (tester): `[авто]`-часть карточки T-106a1 и подготовка REQ-D3D-09 п.1, 2, 5,
## п.11 — независимо от оракула исполнителя (`tests/fixtures/scene3d/rider_contract.gd`):
## числа читаются прямо из ТЗ художнику `docs/game/rider-artist-brief.md` (§5.1 таблица костей,
## §5.4 контрольные позы, §6 точки посадки), файлы пакета `assets/rider/reference/` импортируются
## `GLTFDocument` и переводятся в оси Blender по правилу импорта Blender «+Y Up»
## ((x, y, z)_glTF → (x, −z, y)), без функций перевода `RiderRig`.
## - `rider_rig_reference.glb`: 25 костей, имена и родители §5.1, начала ±1 мм, хвост 0.09–0.10 м;
## - `bike_reference.glb`: точки `pt_*` = §6 ±1 мм; по геометрии — верх седла под S
##   0.965 ± 0.002, длина 0.27, ширина сзади 0.13, задний край 3–10 см позади S; ручки под
##   центром хвата; корпуса педалей на осях ±0.115 при φ = 90° (правая впереди), шатун 0.17;
## - `RiderRig.CONTROL_POSES` = таблица §5.4;
## - кадры `head_34` не лежат в `docs/` (REQ-D3D-09 п.11, до ответа Н-47).

const BRIEF: String = "res://docs/game/rider-artist-brief.md"
const DIR: String = "res://assets/rider/reference/"
const MM: float = 0.001

var _brief: PackedStringArray


func before_all() -> void:
	_brief = FileAccess.get_file_as_string(BRIEF).split("\n")


# ---------------------------------------------------------------------------
# Разбор брифа
# ---------------------------------------------------------------------------

## Строки первой таблицы после строки, начинающейся с `heading`.
func _table(heading: String) -> Array[PackedStringArray]:
	var rows: Array[PackedStringArray] = []
	var start := -1
	for i in _brief.size():
		if _brief[i].begins_with(heading):
			start = i
			break
	assert_true(start >= 0, "в брифе есть «%s»" % heading)
	if start < 0:
		return rows
	var in_table := false
	for i in range(start + 1, _brief.size()):
		var line := _brief[i].strip_edges()
		if line.begins_with("|"):
			in_table = true
			var cells := PackedStringArray()
			var parts := line.split("|")
			for j in range(1, parts.size() - 1):
				cells.append(parts[j].strip_edges())
			rows.append(cells)
		elif in_table:
			break
	return rows.slice(2)


static func _ticks(cell: String) -> PackedStringArray:
	var out := PackedStringArray()
	var re := RegEx.new()
	re.compile("`([^`]+)`")
	for m in re.search_all(cell):
		out.append(m.get_string(1))
	return out


## Числа в скобках «(a, b[, c])» по порядку.
static func _tuples(cell: String) -> Array[PackedFloat64Array]:
	var out: Array[PackedFloat64Array] = []
	var re := RegEx.new()
	re.compile("\\(([±−\\-0-9., ]+)\\)")
	for m in re.search_all(cell):
		var nums := PackedFloat64Array()
		for part in m.get_string(1).split(","):
			var t := part.strip_edges().replace("−", "-").replace("±", "")
			if t.is_valid_float():
				nums.append(t.to_float())
		if nums.size() >= 2:
			out.append(nums)
	return out


static func _num(text: String) -> float:
	return text.strip_edges().replace("−", "-").replace("°", "").to_float()


## Кости брифа §5.1: имя → [родитель, начало в Blender или null]. Правая сторона — зеркало левой.
func _brief_bones() -> Dictionary:
	var out := {}
	for r: PackedStringArray in _table("### 5.1."):
		var name := _ticks(r[0])
		if name.is_empty():
			continue
		var parent_t := _ticks(r[1])
		var parent: String = parent_t[0] if not parent_t.is_empty() else ""
		var t := _tuples(r[2])
		var head: Variant = Vector3(t[0][0], t[0][1], t[0][2]) if not t.is_empty() and t[0].size() == 3 else null
		out[name[0]] = [parent, head]
		if name[0].ends_with(".L"):
			var mirror_head: Variant = Vector3(-head.x, head.y, head.z) if head != null else null
			out[name[0].replace(".L", ".R")] = [parent.replace(".L", ".R"), mirror_head]
	return out


## Строка таблицы §6 по началу первой ячейки.
func _fit_row(label: String) -> String:
	for r: PackedStringArray in _table("## 6. Посадка"):
		if r[0].begins_with(label):
			return r[1]
	assert_true(false, "в §6 есть строка «%s»" % label)
	return ""


# ---------------------------------------------------------------------------
# glTF
# ---------------------------------------------------------------------------

func _import(file: String) -> Node:
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err := doc.append_from_file(ProjectSettings.globalize_path(DIR + file), state)
	assert_eq(err, OK, "%s: GLTFDocument без ошибок" % file)
	if err != OK:
		return null
	var scene := doc.generate_scene(state)
	assert_not_null(scene, "%s: сцена построена" % file)
	if scene != null:
		autofree(scene)
	return scene


static func _blender(g: Vector3) -> Vector3:
	return Vector3(g.x, -g.z, g.y)


## Трансформ узла относительно корня сцены (сцена вне дерева).
static func _to_root(node: Node) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var n: Node = node
	while n != null:
		if n is Node3D:
			xf = (n as Node3D).transform * xf
		n = n.get_parent()
	return xf


## Вершины и треугольники меша в осях Blender.
static func _mesh_tris(mi: MeshInstance3D) -> PackedVector3Array:
	var out := PackedVector3Array()
	var xf := _to_root(mi)
	for s in mi.mesh.get_surface_count():
		var arr: Array = mi.mesh.surface_get_arrays(s)
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		if idx.is_empty():
			for i in verts.size():
				idx.append(i)
		for i in idx:
			out.append(_blender(xf * verts[i]))
	return out


## Наивысшая точка поверхности на вертикали (x, y) в осях Blender.
static func _top_at(tris: PackedVector3Array, x: float, y: float) -> float:
	var best := -INF
	var p := Vector2(x, y)
	for i in range(0, tris.size(), 3):
		var a := tris[i]
		var b := tris[i + 1]
		var c := tris[i + 2]
		var a2 := Vector2(a.x, a.y)
		var v0 := Vector2(b.x, b.y) - a2
		var v1 := Vector2(c.x, c.y) - a2
		var v2 := p - a2
		var den := v0.x * v1.y - v1.x * v0.y
		if absf(den) < 1e-12:
			continue
		var u := (v2.x * v1.y - v1.x * v2.y) / den
		var v := (v0.x * v2.y - v2.x * v0.y) / den
		if u < -1e-6 or v < -1e-6 or u + v > 1.0 + 1e-6:
			continue
		best = maxf(best, a.z + u * (b.z - a.z) + v * (c.z - a.z))
	return best


# ---------------------------------------------------------------------------
# Скелет
# ---------------------------------------------------------------------------

func test_rig_reference_bones_match_brief_5_1() -> void:
	var want := _brief_bones()
	assert_eq(want.size(), 25, "в §5.1 с зеркалом — 25 костей")
	var scene := _import("rider_rig_reference.glb")
	if scene == null:
		return
	var skels := scene.find_children("*", "Skeleton3D", true, false)
	assert_eq(skels.size(), 1, "одна арматура")
	if skels.is_empty():
		return
	var sk := skels[0] as Skeleton3D
	assert_eq(sk.get_bone_count(), 25, "25 костей в файле")
	var xf := _to_root(sk)
	for name: String in want:
		var i := sk.find_bone(name)
		assert_true(i >= 0, "кость %s в файле" % name)
		if i < 0:
			continue
		var parent_i := sk.get_bone_parent(i)
		var parent: String = sk.get_bone_name(parent_i) if parent_i >= 0 else ""
		assert_eq(parent, want[name][0], "%s: родитель" % name)
		var head: Vector3 = _blender(xf * sk.get_bone_global_rest(i).origin)
		if want[name][1] != null:
			assert_lt(head.distance_to(want[name][1]), MM, "%s: начало %s, бриф %s" % [name, head, want[name][1]])
		else:
			var root_head: Vector3 = _blender(xf * sk.get_bone_global_rest(parent_i).origin)
			assert_between(head.distance_to(root_head), 0.09, 0.10, "%s: 0.09–0.10 м от %s" % [name, parent])
	# Длины §5.1 (проверка, что числа не сбились): бедро и голень 0.44, между HIP 0.18.
	var hip: Vector3 = want["thigh.L"][1]
	assert_almost_eq(hip.distance_to(want["shin.L"][1]), 0.44, 0.002, "бедро 0.44")
	assert_almost_eq((want["shin.L"][1] as Vector3).distance_to(want["foot.L"][1]), 0.44, 0.002, "голень 0.44")


func test_code_table_matches_brief_5_1_in_blender_axes() -> void:
	var want := _brief_bones()
	for name: String in want:
		var i := RiderRig.index_of(name)
		assert_true(i >= 0, "%s в RiderRig" % name)
		if i < 0:
			continue
		assert_eq(RiderRig.parent_of(name), want[name][0], "%s: родитель" % name)
		var g: Vector3 = RiderRig.head(name)
		# Godot гонщика: Y вверх, вперёд −Z, правая сторона +X → Blender: Z вверх, вперёд −Y, левая +X.
		var b := Vector3(-g.x, g.z, g.y)
		if want[name][1] != null:
			assert_lt(b.distance_to(want[name][1]), MM, "%s: код %s, бриф %s" % [name, b, want[name][1]])
	for socket in ["grip.L", "grip.R", "cleat.L", "cleat.R", "heel.L", "heel.R"]:
		assert_false(RiderRig.deforms(socket), "%s — Deform off (§5.1)" % socket)


func test_control_poses_match_brief_5_4() -> void:
	var rows := _table("### 5.4.")
	var by_phi := {}
	for r: PackedStringArray in rows:
		var phi_text := r[0].get_slice("°", 0).strip_edges()
		if phi_text.is_valid_int():
			by_phi[phi_text.to_int()] = r
	assert_eq(by_phi.size(), 4, "в §5.4 четыре угла φ")
	assert_eq(RiderRig.CONTROL_POSES.size(), 4)
	for pose: Array in RiderRig.CONTROL_POSES:
		var phi: int = pose[0]
		assert_true(by_phi.has(phi), "φ = %d в брифе" % phi)
		if not by_phi.has(phi):
			continue
		var r: PackedStringArray = by_phi[phi]
		var names := ["шип", "голеностоп", "колено"]
		for k in 3:
			var t := _tuples(r[k + 1])
			var g: Vector3 = pose[k + 1]
			# Blender (y, z) = Godot (z, y).
			assert_almost_eq(g.z, t[0][0], MM, "φ %d %s: y" % [phi, names[k]])
			assert_almost_eq(g.y, t[0][1], MM, "φ %d %s: z" % [phi, names[k]])
		assert_almost_eq(float(pose[4]), _num(r[4]), 0.01, "φ %d: угол в колене" % phi)
		assert_almost_eq(float(pose[5]), _num(r[5]), 0.01, "φ %d: наклон стопы" % phi)


# ---------------------------------------------------------------------------
# Велосипед
# ---------------------------------------------------------------------------

func test_bike_points_match_brief_6() -> void:
	var scene := _import("bike_reference.glb")
	if scene == null:
		return
	var bb := _tuples(_fit_row("Каретка"))[0]
	var axles := _tuples(_fit_row("Оси колёс"))
	var grip := _tuples(_fit_row("Центр ладони"))[0]
	var cleat := _tuples(_fit_row("Ось педали под шипом"))[0]
	var saddle_row := _fit_row("Верх седла")
	var want := {
		"pt_bb": Vector3(bb[0], bb[1], bb[2]),
		"pt_axle_rear": Vector3(axles[0][0], axles[0][1], axles[0][2]),
		"pt_axle_front": Vector3(axles[1][0], axles[1][1], axles[1][2]),
		"pt_grip_L": Vector3(absf(grip[0]), grip[1], grip[2]),
		"pt_grip_R": Vector3(-absf(grip[0]), grip[1], grip[2]),
		"pt_cleat_R_pedal_axis": Vector3(cleat[0], cleat[1], cleat[2]),
	}
	var re := RegEx.new()
	re.compile("высота ([0-9.]+) у точки опоры таза \\(y = ([0-9.]+)\\)")
	var m := re.search(saddle_row)
	assert_not_null(m, "§6: высота седла и y точки опоры")
	if m != null:
		want["pt_saddle_S"] = Vector3(0.0, m.get_string(2).to_float(), m.get_string(1).to_float())
	for n: String in want:
		var node := scene.find_child(n, true, false) as Node3D
		assert_not_null(node, "%s в файле" % n)
		if node != null:
			var b := _blender(_to_root(node).origin)
			assert_lt(b.distance_to(want[n]), MM, "%s: %s, бриф %s" % [n, b, want[n]])


func test_saddle_geometry_from_file_matches_brief_6() -> void:
	var scene := _import("bike_reference.glb")
	if scene == null:
		return
	var frame := scene.find_child("bike_frame", true, false) as MeshInstance3D
	assert_not_null(frame)
	if frame == null:
		return
	# art-bible ред. 4.1 «Вход конвейера из пакета» (T-143): седло — отдельный узел `saddle`.
	# Геометрия велосипеда по брифу §6 — рама и седло вместе, как в файле до разделения.
	var saddle := scene.find_child("saddle", true, false) as MeshInstance3D
	assert_not_null(saddle, "узел saddle (ред. 4.1)")
	var tris := _mesh_tris(frame)
	if saddle != null:
		tris.append_array(_mesh_tris(saddle))
	# Верх седла под S (бриф §6: 0.965 у y = 0.230).
	var top := _top_at(tris, 0.0, 0.230)
	assert_almost_eq(top, 0.965, 0.002, "верх седла под S по геометрии: %.4f" % top)
	# Седло — всё выше 0.93 м и позади руля (y > −0.3).
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	for p in tris:
		if p.z > 0.93 and p.y > -0.3:
			lo = lo.min(p)
			hi = hi.max(p)
	assert_almost_eq(hi.y - lo.y, 0.27, 0.005, "длина седла 0.27 (%.3f)" % (hi.y - lo.y))
	assert_almost_eq(hi.x - lo.x, 0.13, 0.005, "ширина сзади 0.13 (%.3f)" % (hi.x - lo.x))
	assert_between(hi.y - 0.230, 0.03, 0.10, "задний край на 3–10 см позади S (%.3f)" % (hi.y - 0.230))
	# Ручки: под центром ладони (±0.21, −0.62, 0.885) — корпус ручки на 0–3 см ниже.
	for x in [0.21, -0.21]:
		var hood := _top_at(tris, x, -0.62)
		assert_between(0.885 - hood, 0.0, 0.03, "ручка x=%.2f: верх %.4f под центром ладони 0.885" % [x, hood])


func test_crank_and_contact_pedals_from_file_geometry() -> void:
	var scene := _import("bike_reference.glb")
	if scene == null:
		return
	var crank := scene.find_child("crankset", true, false) as MeshInstance3D
	assert_not_null(crank)
	if crank == null:
		return
	var tris := _mesh_tris(crank)
	# φ = 90°: правая педаль впереди (−Y), левая сзади; x правой −0.115, левой +0.115 (Blender).
	for side in [[-1.0, -1.0, "правая"], [1.0, 1.0, "левая"]]:
		var axis := Vector3(0.115 * side[0], 0.17 * side[1], 0.27)
		var lo := Vector3(INF, INF, INF)
		var hi := Vector3(-INF, -INF, -INF)
		var n := 0
		for p in tris:
			if absf(p.x - axis.x) < 0.03 and absf(p.y - axis.y) < 0.06 and absf(p.z - axis.z) < 0.03:
				lo = lo.min(p)
				hi = hi.max(p)
				n += 1
		assert_gt(n, 0, "%s педаль у оси %s" % [side[2], axis])
		if n == 0:
			continue
		var c := (lo + hi) * 0.5
		assert_almost_eq(c.x, axis.x, 0.004, "%s: корпус педали по x на ±0.115 (%.4f)" % [side[2], c.x])
		assert_almost_eq(Vector2(c.y, c.z - 0.27).length(), 0.17, 0.01, "%s: шатун 0.17 (центр педали %.3f от каретки)" % [side[2], Vector2(c.y, c.z - 0.27).length()])
		assert_gt(hi.y - lo.y, 0.06, "%s: контактная педаль — платформа вдоль хода (%.3f)" % [side[2], hi.y - lo.y])


# ---------------------------------------------------------------------------
# REQ-D3D-09 п.11: кадры head_34 не в docs/ до ответа Н-47
# ---------------------------------------------------------------------------

func test_no_head_34_frames_in_docs() -> void:
	var found: Array[String] = []
	_scan("res://docs/", found)
	assert_eq(found, [] as Array[String], "кадры ракурса head_34 в docs/ (REQ-D3D-09 п.11, Н-47): %s" % ", ".join(found))


func _scan(dir: String, found: Array[String]) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	for f in d.get_files():
		if f.contains("head_34") and (f.ends_with(".png") or f.ends_with(".jpg")):
			found.append(dir + f)
	for sub in d.get_directories():
		_scan(dir + sub + "/", found)
