extends RefCounted
## Эталонный пакет для подготовки `rider.glb` (T-106a1; бриф `docs/game/rider-artist-brief.md`
## разделы 4–6, 10, 18; арт-библия «Гонщик», «Вариант Г»): содержимое файлов
## `assets/rider/reference/` в памяти, из кода проекта, воспроизводимо побайтно.
## - `bike_reference.glb` — велосипед после подгонки под скелет (`RiderModel.reference_kits`),
##   шатуны в rest (φ = 90°, правая педаль впереди), педали под углом стопы; точки посадки —
##   пустые объекты `pt_*`;
## - `rider_rig_reference.glb` — арматура `rider_rig` (25 костей `RiderRig.BONES`, rest) и
##   сетка `rig_joints` — метки суставов (октаэдры, вес 1 на свою кость);
## - `rider_atlas_preview.png`, `rider_atlas_id.png` — атласы регионов (`RiderRegions`).
## Оси: glTF как у экспорта Blender «+Y Up» из координат брифа — модель смотрит в +Z
## (`RiderRig.to_gltf`, поворот на 180° вокруг Y); при импорте в Blender (+Y Up → Z вверх)
## гонщик смотрит в −Y, левая сторона +X, начало — на земле под кареткой.
## Пишет файлы `scripts/dev/rider_artist_kit.gd`; сверяет с ними тест
## `tests/integration/test_rider_artist_kit.gd`. Не для кадра.

const FILES: Array[String] = ["bike_reference.glb", "rider_rig_reference.glb", "rider_atlas_preview.png",
	"rider_atlas_id.png"]
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
	var kits: Dictionary = RiderModel.reference_kits(RiderRig.REST_CRANK_RAD)
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
