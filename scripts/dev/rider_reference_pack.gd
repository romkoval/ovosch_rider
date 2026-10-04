extends RefCounted
## Эталонный пакет для подготовки `rider.glb` (T-106a1; бриф `docs/game/rider-artist-brief.md`
## разделы 4–6, 10, 18; арт-библия «Гонщик», «Вариант Г»): содержимое файлов
## `assets/rider/reference/` в памяти, из кода проекта, воспроизводимо побайтно.
## - `bike_reference.glb` — велосипед после подгонки под скелет (`RiderModel.reference_kits`),
##   шатуны в rest (φ = 90°, правая педаль впереди), педали под углом стопы; точки посадки —
##   пустые объекты `pt_*`;
## - `rider_rig_reference.glb` — арматура `rider_rig` (25 костей `RiderRig.BONES`, rest) и
##   сетка `rig_joints` — метки суставов (октаэдры, вес 1 на свою кость);
## - `rider_atlas_preview.png`, `rider_atlas_id.png` — атласы регионов (`RiderRegions`);
## - `rider_contract.json` — машиночитаемый контракт для конвейера доводки в Blender (T-143):
##   кости (начало, окончание, оси, Deform), контрольные позы ног φ 0…345° шаг 15° (бриф 5.4),
##   покачивание, точки и размеры велосипеда, ракурсы, регионы — в координатах Blender.
## Оси: glTF как у экспорта Blender «+Y Up» из координат брифа — модель смотрит в +Z
## (`RiderRig.to_gltf`, поворот на 180° вокруг Y); при импорте в Blender (+Y Up → Z вверх)
## гонщик смотрит в −Y, левая сторона +X, начало — на земле под кареткой.
## Пишет файлы `scripts/dev/rider_artist_kit.gd`; сверяет с ними тест
## `tests/integration/test_rider_artist_kit.gd`. Не для кадра.

const FILES: Array[String] = ["bike_reference.glb", "rider_rig_reference.glb", "rider_atlas_preview.png",
	"rider_atlas_id.png", "rider_contract.json"]
## Формат `rider_contract.json`: меняется при несовместимой правке структуры.
const CONTRACT_FORMAT: String = "ovosch-rider rider_contract 1"
## Шаг контрольных поз ног, градусы шатуна (арт-библия «Допуски для [авто]» — шаг реестра).
const POSE_STEP_DEG: int = 15
## Покачивание, которое выдерживают веса (бриф 5.4, таблица «Покачивание»): кость(и) →
## крен, рыскание (± градусы) или смещение вбок (± м). Движение программное, здесь — числа для
## проверки весов в конвейере.
const SWAY: Array = [
	{"bones": ["pelvis"], "roll_deg": 1.0, "yaw_deg": 0.0, "side_m": 0.0, "check": "ягодицы не глубже 0.5 см в седло"},
	{"bones": ["spine", "chest"], "roll_deg": 1.5, "yaw_deg": 1.2, "side_m": 0.0, "check": "низ джерси и пояс шорт не расходятся"},
	{"bones": ["head"], "roll_deg": 1.5, "yaw_deg": 1.0, "side_m": 0.0, "check": "воротник не входит в шею, шлем — в плечи"},
	{"bones": ["shin.L", "shin.R"], "roll_deg": 0.0, "yaw_deg": 0.0, "side_m": 0.01, "check": "колено вбок: бедро и голень не скручиваются"},
]
## Седло в `bike_reference.glb` — отдельный узел (поверхность для шага 5 конвейера): связные
## куски рамы, верх которых не ниже S.y − SADDLE_PICK_BELOW_M.
const SADDLE_NODE: String = "saddle"
const SADDLE_PICK_BELOW_M: float = 0.012
## `asset.generator` в glTF: без номера сборки Godot, иначе файл меняется от патч-версии
## движка (4.7 → 4.7.2), хотя данные те же.
const GENERATOR: String = "ovosch-rider scripts/dev/rider_reference_pack.gd (Godot 4.7 GLTFDocument)"
## Имя объекта арматуры в glTF (бриф раздел 12): корень сцены — узел, к которому экспорт
## Godot крепит кости `Skeleton3D`; Blender делает из него объект арматуры.
const RIG_NAME: String = "rider_rig"
const JOINT_RADIUS_M: float = 0.012
const SOCKET_RADIUS_M: float = 0.008

## Имена материалов велосипеда по цвету вершин (sRGB констант `RiderModel`).
var _color_names: Dictionary = {}
## Один материал на цвет на весь файл.
var _materials: Dictionary = {}


## Файл пакета → содержимое. Пустой массив байт — ошибка сборки этого файла.
func build() -> Dictionary:
	_init_color_names()
	_materials.clear()
	return {
		"bike_reference.glb": _glb_bytes(bike_scene()),
		"rider_rig_reference.glb": _glb_bytes(rig_scene()),
		"rider_atlas_preview.png": RiderRegions.preview_atlas().save_png_to_buffer(),
		"rider_atlas_id.png": RiderRegions.id_atlas().save_png_to_buffer(),
		"rider_contract.json": contract_json(),
	}


func _glb_bytes(scene: Node3D) -> PackedByteArray:
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var out := PackedByteArray()
	if doc.append_from_scene(scene, state) == OK:
		_restore_names(state)
		out = with_generator(doc.generate_buffer(state), GENERATOR)
	scene.free()
	return out


## GLB с подменённым `asset.generator` (JSON-чанк выравнивается пробелами до 4 байт, длины в
## заголовках пересчитываются; BIN-чанк — без изменений). Не GLB — пустой массив.
static func with_generator(glb: PackedByteArray, generator: String) -> PackedByteArray:
	if glb.size() < 20 or glb.decode_u32(0) != 0x46546C67:
		return PackedByteArray()
	var json_len: int = glb.decode_u32(12)
	var text: String = glb.slice(20, 20 + json_len).get_string_from_utf8()
	var re := RegEx.create_from_string("\"generator\"\\s*:\\s*\"[^\"]*\"")
	text = re.sub(text, "\"generator\":\"%s\"" % generator)
	var json: PackedByteArray = text.strip_edges(false, true).to_utf8_buffer()
	while json.size() % 4 != 0:
		json.append(0x20)
	var rest: PackedByteArray = glb.slice(20 + json_len)
	var out := PackedByteArray()
	out.resize(20)
	out.encode_u32(0, 0x46546C67)
	out.encode_u32(4, 2)
	out.encode_u32(8, 20 + json.size() + rest.size())
	out.encode_u32(12, json.size())
	out.encode_u32(16, 0x4E4F534A)
	out.append_array(json)
	out.append_array(rest)
	return out


## Экспорт Godot делает имена узлов glTF уникальными и годными для узлов сцены: «.» в именах
## костей становится «_», у сеток и материалов появляются цифры. Нужны имена брифа: кости —
## как в `RiderRig.BONES` (`thigh.L`), сетка — как её объект, материал — как задан.
func _restore_names(state: GLTFState) -> void:
	var bones: Dictionary = {}
	for b in RiderRig.bone_names():
		bones[b.replace(".", "_")] = b
	var meshes: Array[GLTFMesh] = state.get_meshes()
	for node in state.get_nodes():
		if bones.has(node.resource_name):
			node.resource_name = bones[node.resource_name]
		if node.mesh >= 0:
			meshes[node.mesh].resource_name = node.resource_name


func _init_color_names() -> void:
	var named := {
		"frame": RiderModel.C_FRAME, "frame_accent": RiderModel.C_ACCENT, "component": RiderModel.C_BLACK,
		"metal": RiderModel.C_SILVER, "bottle": RiderModel.C_JERSEY_BLUE, "tire": RiderModel.C_TIRE,
		"rim_carbon": RiderModel.C_RIM, "rim_decal": RiderModel.C_RIM_STRIPE, "chain": Color(0.3, 0.3, 0.32),
		"chainring": Color(0.15, 0.15, 0.17), "spokes": Color(0.2, 0.2, 0.22),
	}
	_color_names.clear()
	for n in named:
		_color_names[_color_key(MeshKit.lin(named[n]))] = "bike_" + n


func _color_key(linear: Color) -> String:
	return "%.3f_%.3f_%.3f" % [linear.r, linear.g, linear.b]


## Точки посадки велосипеда (система гонщика, Godot): имя пустого объекта → позиция.
static func bike_points() -> Dictionary:
	return {
		"pt_bb": RiderRig.BB,
		"pt_saddle_S": RiderRig.head("pelvis"),
		"pt_grip_L": RiderRig.head("grip.L"),
		"pt_grip_R": RiderRig.head("grip.R"),
		"pt_cleat_R_pedal_axis": RiderRig.head("cleat.R"),
		"pt_axle_rear": RiderRig.REAR_AXLE,
		"pt_axle_front": RiderRig.FRONT_AXLE,
	}


## Велосипед: части `RiderModel.reference_kits` в осях glTF, по поверхности на цвет (имена
## материалов — по региону: рама, акцент, обод…), точки посадки — пустые узлы.
func bike_scene() -> Node3D:
	var root := Node3D.new()
	root.name = "bike_reference"
	var kits: Dictionary = split_saddle(RiderModel.reference_kits(RiderRig.REST_CRANK_RAD))
	for part in kits:
		var mi := MeshInstance3D.new()
		mi.name = part
		mi.mesh = _surfaces_by_color(kits[part], part)
		root.add_child(mi)
	var points: Dictionary = bike_points()
	for n in points:
		var p := Node3D.new()
		p.name = n
		p.position = RiderRig.to_gltf(points[n])
		root.add_child(p)
	return root


## Части велосипеда с седлом отдельным набором `saddle` (после `bike_frame`): связные куски
## `bike_frame` (по общим вершинам), верх которых не ниже S.y − `SADDLE_PICK_BELOW_M` и которые
## лежат в длине седла. Геометрия та же, вершины и грани только перераспределены.
static func split_saddle(kits: Dictionary) -> Dictionary:
	var frame: MeshKit = kits["bike_frame"]
	var n: int = frame.vertices.size()
	var root := PackedInt32Array()
	root.resize(n)
	for i in n:
		root[i] = i
	for t in range(0, frame.indices.size(), 3):
		var a: int = _find(root, frame.indices[t])
		for j in [1, 2]:
			var b: int = _find(root, frame.indices[t + j])
			if a != b:
				root[maxi(a, b)] = mini(a, b)
				a = mini(a, b)
	var top: Dictionary = {}
	var zmin: Dictionary = {}
	var zmax: Dictionary = {}
	for i in n:
		var r: int = _find(root, i)
		var p: Vector3 = frame.vertices[i]
		top[r] = maxf(top.get(r, -INF), p.y)
		zmin[r] = minf(zmin.get(r, INF), p.z)
		zmax[r] = maxf(zmax.get(r, -INF), p.z)
	var s: Vector3 = RiderRig.head("pelvis")
	var rear_z: float = s.z + RiderRig.SADDLE_REAR_BEHIND_S_M + 0.001
	var nose_z: float = rear_z - RiderRig.SADDLE_LENGTH_M - 0.002
	var picked: Dictionary = {}
	for r in top:
		if top[r] >= s.y - SADDLE_PICK_BELOW_M and zmin[r] >= nose_z and zmax[r] <= rear_z:
			picked[r] = true
	var parts: Array[MeshKit] = [MeshKit.new(), MeshKit.new()]
	var remap: Array[Dictionary] = [{}, {}]
	for t in range(0, frame.indices.size(), 3):
		var side: int = 1 if picked.has(_find(root, frame.indices[t])) else 0
		var k: MeshKit = parts[side]
		for j in 3:
			var i: int = frame.indices[t + j]
			if not remap[side].has(i):
				remap[side][i] = k.vertices.size()
				k.vertices.append(frame.vertices[i])
				k.normals.append(frame.normals[i])
				k.colors.append(frame.colors[i])
			k.indices.append(remap[side][i])
	var out: Dictionary = {}
	for part in kits:
		out[part] = parts[0] if part == "bike_frame" else kits[part]
		if part == "bike_frame":
			out[SADDLE_NODE] = parts[1]
	return out


static func _find(root: PackedInt32Array, i: int) -> int:
	while root[i] != i:
		root[i] = root[root[i]]
		i = root[i]
	return i


func _surfaces_by_color(k: MeshKit, mesh_name: String) -> ArrayMesh:
	k.fix_winding()
	var groups: Dictionary = {}
	var order: Array[String] = []
	for t in range(0, k.indices.size(), 3):
		var key: String = _color_key(k.colors[k.indices[t]])
		if not groups.has(key):
			groups[key] = PackedInt32Array()
			order.append(key)
		var tri: PackedInt32Array = groups[key]
		tri.append_array(PackedInt32Array([k.indices[t], k.indices[t + 1], k.indices[t + 2]]))
		groups[key] = tri
	var mesh := ArrayMesh.new()
	mesh.resource_name = mesh_name
	for key in order:
		var tri: PackedInt32Array = groups[key]
		var remap: Dictionary = {}
		var verts := PackedVector3Array()
		var norms := PackedVector3Array()
		var idx := PackedInt32Array()
		for i in tri:
			if not remap.has(i):
				remap[i] = verts.size()
				verts.append(RiderRig.to_gltf(k.vertices[i]))
				norms.append(RiderRig.to_gltf(k.normals[i]))
			idx.append(remap[i])
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_NORMAL] = norms
		arrays[Mesh.ARRAY_INDEX] = idx
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		if not _materials.has(key):
			var mat := StandardMaterial3D.new()
			var lin: Color = k.colors[tri[0]]
			mat.albedo_color = Color(lin.r, lin.g, lin.b).linear_to_srgb()
			mat.roughness = 1.0
			mat.resource_name = "M_" + _color_names.get(key, "bike_color_" + key)
			_materials[key] = mat
		mesh.surface_set_material(mesh.get_surface_count() - 1, _materials[key])
	return mesh


## Арматура (rest по таблице, оси glTF) и метки суставов `rig_joints`. Корень сцены называется
## `rider_rig`: экспорт крепит кости к нему, и в Blender объект арматуры — `rider_rig`.
func rig_scene() -> Node3D:
	var root := Node3D.new()
	root.name = RIG_NAME
	var skel := Skeleton3D.new()
	skel.name = "Skeleton3D"
	root.add_child(skel)
	for b in RiderRig.BONES:
		skel.add_bone(b[0])
	var skin := Skin.new()
	for b in RiderRig.BONES:
		var i: int = skel.find_bone(b[0])
		var global: Transform3D = rest_gltf(b[0])
		var local: Transform3D = global
		if not (b[1] as String).is_empty():
			skel.set_bone_parent(i, skel.find_bone(b[1]))
			local = rest_gltf(b[1]).affine_inverse() * global
		skel.set_bone_rest(i, local)
		skin.add_named_bind(b[0], global.affine_inverse())
	skel.reset_bone_poses()
	var mi := MeshInstance3D.new()
	mi.name = "rig_joints"
	mi.mesh = _joint_markers()
	skel.add_child(mi)
	mi.skin = skin
	mi.skeleton = NodePath("..")
	return root


## Глобальный rest кости в осях glTF: начало — сустав таблицы, оси — `RiderRig.rest_basis`
## (Y вдоль кости, X — мировая X Blender). Импорт Blender (эвристика костей по умолчанию,
## «Blender») ставит кость по локальной +Y узла: направление и крен приходят как в брифе 5.3.
static func rest_gltf(bone: String) -> Transform3D:
	return Transform3D(RiderRig.gltf_flip().basis * RiderRig.rest_basis(bone), RiderRig.to_gltf(RiderRig.head(bone)))


## Октаэдр на начале каждой кости (сокеты — меньше и своим материалом), вес 1 на кость.
func _joint_markers() -> ArrayMesh:
	var mesh := ArrayMesh.new()
	mesh.resource_name = "rig_joints"
	for socket in [false, true]:
		var verts := PackedVector3Array()
		var norms := PackedVector3Array()
		var bones := PackedInt32Array()
		var weights := PackedFloat32Array()
		for bi in RiderRig.BONES.size():
			var b: Array = RiderRig.BONES[bi]
			if RiderRig.is_socket(b[0]) != socket:
				continue
			var c: Vector3 = RiderRig.to_gltf(b[2])
			var r: float = SOCKET_RADIUS_M if socket else JOINT_RADIUS_M
			var axes: Array[Vector3] = [Vector3.RIGHT, Vector3.UP, Vector3.BACK]
			for sx in [-1.0, 1.0]:
				for sy in [-1.0, 1.0]:
					for sz in [-1.0, 1.0]:
						var tri: Array[Vector3] = [axes[0] * sx, axes[1] * sy, axes[2] * sz]
						var n: Vector3 = Vector3(sx, sy, sz).normalized()
						# Обход по часовой при взгляде снаружи (лицевая грань Godot).
						var flip: bool = sx * sy * sz > 0.0
						var order: Array = [0, 2, 1] if flip else [0, 1, 2]
						for o in order:
							verts.append(c + tri[o] * r)
							norms.append(n)
							bones.append_array(PackedInt32Array([bi, 0, 0, 0]))
							weights.append_array(PackedFloat32Array([1.0, 0.0, 0.0, 0.0]))
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_NORMAL] = norms
		arrays[Mesh.ARRAY_BONES] = bones
		arrays[Mesh.ARRAY_WEIGHTS] = weights
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.2, 0.75, 0.95) if socket else Color(0.98, 0.55, 0.15)
		mat.roughness = 1.0
		mat.resource_name = "M_socket" if socket else "M_joint"
		mesh.surface_set_material(mesh.get_surface_count() - 1, mat)
	return mesh


# --- rider_contract.json (T-143) ---

## Контракт для конвейера доводки в Blender: всё в координатах Blender (бриф 4: Z вверх,
## гонщик смотрит в −Y, левая сторона +X, метры; `RiderRig.to_blender`). Числа округлены до
## 1e-6 м, порядок ключей фиксирован — файл побайтно воспроизводим.
static func contract_json() -> PackedByteArray:
	var bones: Array = []
	for b in RiderRig.BONES:
		var name: String = b[0]
		var basis: Basis = RiderRig.rest_basis(name)
		bones.append({
			"name": name, "parent": b[1], "deform": RiderRig.deforms(name), "socket": RiderRig.is_socket(name),
			"head": _bl(RiderRig.head(name)), "tail": _bl(RiderRig.tail(name)),
			"axis_x": _bl(basis.x), "axis_y": _bl(basis.y), "axis_z": _bl(basis.z),
		})
	var table: Array = []
	for row in RiderRig.CONTROL_POSES:
		table.append({"phi_deg": row[0], "cleat": _bl(row[1]), "ankle": _bl(row[2]), "knee": _bl(row[3]),
			"knee_deg": row[4], "foot_deg": row[5]})
	var poses: Array = []
	for phi in range(0, 360, POSE_STEP_DEG):
		poses.append({"phi_deg": phi, "R": leg_pose(float(phi), false), "L": leg_pose(float(phi), true)})
	var points: Dictionary = {}
	var pts: Dictionary = bike_points()
	for n in pts:
		points[n] = _bl(pts[n])
	var views: Array = []
	for v in RiderRig.VIEWS:
		views.append({"name": v[0], "camera": _bl(v[1]), "target": _bl(v[2]), "fov_deg": v[3], "crank_deg": v[4],
			"artist": RiderRig.ARTIST_VIEWS.has(v[0])})
	var regions: Array = []
	for code in RiderRegions.COUNT:
		regions.append({"code": code, "name": RiderRegions.region_name(code), "outline": RiderRegions.outline_weight(code)})
	var data: Dictionary = {
		"format": CONTRACT_FORMAT,
		"generator": "scripts/dev/rider_reference_pack.gd из src/scene3d/rider_rig.gd, rider_model.gd, rider_regions.gd",
		"coords": "Blender: Z вверх, гонщик смотрит в -Y, левая сторона +X, метры; Godot = (-x, z, y)",
		"bone_count": RiderRig.BONE_COUNT, "max_bones": RiderRig.MAX_BONES,
		"artist_tolerance_m": RiderRig.ARTIST_TOLERANCE_M, "socket_tail_m": RiderRig.SOCKET_TAIL_M,
		"hair_tail_m": [RiderRig.HAIR_TAIL_MIN_M, RiderRig.HAIR_TAIL_MAX_M],
		"bones": bones,
		"bike": {
			"bb": _bl(RiderRig.BB), "crank_m": RiderRig.CRANK_LENGTH_M, "pedal_x_m": RiderRig.PEDAL_X_M,
			"rear_axle": _bl(RiderRig.REAR_AXLE), "front_axle": _bl(RiderRig.FRONT_AXLE),
			"wheel_radius_m": RiderRig.WHEEL_RADIUS_M, "saddle_node": SADDLE_NODE,
			"saddle_top_m": _r(RiderRig.head("pelvis").y), "saddle_length_m": RiderRig.SADDLE_LENGTH_M,
			"saddle_rear_width_m": RiderRig.SADDLE_REAR_WIDTH_M, "saddle_rear_behind_s_m": RiderRig.SADDLE_REAR_BEHIND_S_M,
			"hood_palm_clearance_m": RiderModel.HOOD_PALM_CLEARANCE_M, "rest_crank_deg": _r(rad_to_deg(RiderRig.REST_CRANK_RAD)),
			"points": points,
		},
		"rest_sole_pitch_deg": _r(rad_to_deg(RiderRig.rest_sole_pitch_rad())),
		"foot_pitch_curve": "theta = -14 + 12 * cos(phi - 100) градусов, + носок вверх",
		"control_poses_table": table,
		"control_poses_step_deg": POSE_STEP_DEG,
		"control_poses": poses,
		"sway": SWAY,
		"views": views,
		"regions": {
			"count": RiderRegions.COUNT, "atlas_px": [RiderRegions.ATLAS_SIZE.x, RiderRegions.ATLAS_SIZE.y],
			"column_px": RiderRegions.COLUMN_PX, "margin": RiderRegions.MARGIN, "tone_min": RiderRegions.TONE_MIN,
			"tone_span": RiderRegions.TONE_SPAN, "tone_space": "linear", "lens": RiderRegions.LENS,
			"lens_highlight_v": RiderRegions.LENS_HIGHLIGHT_V, "first_bike": RiderRegions.FIRST_BIKE, "list": regions,
		},
	}
	return (JSON.stringify(data, "  ", false) + "\n").to_utf8_buffer()


## Положение ноги при угле шатуна правой ноги `phi_deg` (левая — φ + 180°), система гонщика:
## шип на оси педали, стопа под углом θ(φ) (`RiderRig.foot_pitch_rad`) — голеностоп и пятка
## поворачиваются вокруг шипа от rest; колено — двухзвенная цепь в продольной плоскости с
## длинами бедра и голени rest, впереди линии «таз — голеностоп»; x суставов — как в rest.
## Итог — в координатах Blender.
static func leg_pose(phi_deg: float, left: bool) -> Dictionary:
	var side: String = ".L" if left else ".R"
	var leg_rad: float = deg_to_rad(phi_deg + (180.0 if left else 0.0))
	var hip: Vector3 = RiderRig.head("thigh" + side)
	var knee_rest: Vector3 = RiderRig.head("shin" + side)
	var ankle_rest: Vector3 = RiderRig.head("foot" + side)
	var cleat_rest: Vector3 = RiderRig.head("cleat" + side)
	var heel_rest: Vector3 = RiderRig.head("heel" + side)
	var cleat := Vector3(cleat_rest.x, RiderRig.BB.y + RiderRig.CRANK_LENGTH_M * cos(leg_rad),
		RiderRig.BB.z - RiderRig.CRANK_LENGTH_M * sin(leg_rad))
	var theta: float = RiderRig.foot_pitch_rad(leg_rad)
	var a: float = theta - RiderRig.rest_sole_pitch_rad()
	var ankle: Vector3 = cleat + _pitch(ankle_rest - cleat_rest, a)
	var heel: Vector3 = cleat + _pitch(heel_rest - cleat_rest, a)
	var l1: float = Vector2(knee_rest.y - hip.y, knee_rest.z - hip.z).length()
	var l2: float = Vector2(ankle_rest.y - knee_rest.y, ankle_rest.z - knee_rest.z).length()
	var k2: Vector3 = RiderModel.two_bone_joint(Vector3(0.0, hip.y, hip.z), Vector3(0.0, ankle.y, ankle.z), l1, l2, Vector3.FORWARD)
	var knee := Vector3(knee_rest.x, k2.y, k2.z)
	var knee_deg: float = rad_to_deg((hip - knee).angle_to(ankle - knee))
	return {"hip": _bl(hip), "knee": _bl(knee), "ankle": _bl(ankle), "cleat": _bl(cleat), "heel": _bl(heel),
		"knee_deg": _r(knee_deg), "foot_deg": _r(rad_to_deg(theta))}


## Поворот смещения от шипа в продольной плоскости на `a` (+ — носок вверх).
static func _pitch(d: Vector3, a: float) -> Vector3:
	return Vector3(d.x, d.y * cos(a) - d.z * sin(a), d.z * cos(a) + d.y * sin(a))


static func _r(x: float) -> float:
	return 0.0 if absf(x) < 5e-7 else snappedf(x, 1e-6)


static func _bl(p: Vector3) -> Array:
	var b: Vector3 = RiderRig.to_blender(p)
	return [_r(b.x), _r(b.y), _r(b.z)]
