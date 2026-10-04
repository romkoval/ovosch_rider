extends SceneTree
## Пакет художнику (T-106a1; бриф `docs/game/rider-artist-brief.md` разделы 4–6, 10, 18):
## собирает из кода проекта, воспроизводимо, в `assets/rider/reference/`:
## - `bike_reference.glb` — велосипед после подгонки под скелет (`RiderModel.reference_kits`),
##   шатуны в rest (φ = 90°, правая педаль впереди), педали под углом стопы; точки посадки —
##   пустые объекты `pt_*`;
## - `rider_rig_reference.glb` — арматура `rider_rig` (25 костей `RiderRig.BONES`, rest) и
##   сетка `rig_joints` — метки суставов (октаэдры, вес 1 на свою кость);
## - `rider_atlas_preview.png`, `rider_atlas_id.png` — атласы регионов (`RiderRegions`).
## Оси: glTF как у экспорта Blender «+Y Up» из координат брифа — модель смотрит в +Z
## (`RiderRig.to_gltf`, поворот на 180° вокруг Y); при импорте в Blender (+Y Up → Z вверх)
## гонщик смотрит в −Y, левая сторона +X, начало — на земле под кареткой.
## Запуск: ./scripts/rider_artist_kit.sh [каталог=assets/rider/reference]

const DEFAULT_OUT: String = "res://assets/rider/reference"
const JOINT_RADIUS_M: float = 0.012
const SOCKET_RADIUS_M: float = 0.008

## Имена материалов велосипеда по цвету вершин (sRGB констант `RiderModel`).
var _color_names: Dictionary = {}
## Один материал на цвет на весь файл.
var _materials: Dictionary = {}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else DEFAULT_OUT
	var dir: String = ProjectSettings.globalize_path(out)
	DirAccess.make_dir_recursive_absolute(dir)
	_init_color_names()
	var errors: Array[String] = []
	_check(_write_glb(_bike_scene(), dir.path_join("bike_reference.glb")), "bike_reference.glb", errors)
	_check(_write_glb(_rig_scene(), dir.path_join("rider_rig_reference.glb")), "rider_rig_reference.glb", errors)
	_check(RiderRegions.preview_atlas().save_png(dir.path_join("rider_atlas_preview.png")), "rider_atlas_preview.png", errors)
	_check(RiderRegions.id_atlas().save_png(dir.path_join("rider_atlas_id.png")), "rider_atlas_id.png", errors)
	if not errors.is_empty():
		push_error("rider_artist_kit: %s" % ", ".join(errors))
		quit(1)
		return
	print("rider_artist_kit: %s" % dir)
	quit(0)


func _check(err: Error, what: String, errors: Array[String]) -> void:
	print("rider_artist_kit: %s — %s" % [what, error_string(err)])
	if err != OK:
		errors.append(what)


func _write_glb(scene: Node3D, path: String) -> Error:
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err: Error = doc.append_from_scene(scene, state)
	if err == OK:
		_restore_names(state)
		err = doc.write_to_filesystem(state, path)
	scene.free()
	return err


## Экспорт Godot делает имена узлов glTF уникальными и годными для узлов сцены: «.» в именах
## костей становится «_», у сеток и материалов появляются цифры. Художнику нужны имена брифа:
## кости — как в `RiderRig.BONES` (`thigh.L`), сетка — как её объект, материал — как задан.
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
	for n in named:
		_color_names[_color_key(MeshKit.lin(named[n]))] = "bike_" + n


func _color_key(linear: Color) -> String:
	return "%.3f_%.3f_%.3f" % [linear.r, linear.g, linear.b]


## Велосипед: части `RiderModel.reference_kits` в осях glTF, по поверхности на цвет (имена
## материалов — по региону: рама, акцент, обод…), точки посадки — пустые узлы.
func _bike_scene() -> Node3D:
	var root := Node3D.new()
	root.name = "bike_reference"
	var kits: Dictionary = RiderModel.reference_kits(RiderRig.REST_CRANK_RAD)
	for part in kits:
		var mi := MeshInstance3D.new()
		mi.name = part
		mi.mesh = _surfaces_by_color(kits[part], part)
		root.add_child(mi)
	var points := {
		"pt_bb": RiderRig.BB,
		"pt_saddle_S": RiderRig.head("pelvis"),
		"pt_grip_L": RiderRig.head("grip.L"),
		"pt_grip_R": RiderRig.head("grip.R"),
		"pt_cleat_R_pedal_axis": RiderRig.head("cleat.R"),
		"pt_axle_rear": RiderRig.REAR_AXLE,
		"pt_axle_front": RiderRig.FRONT_AXLE,
	}
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


## Арматура `rider_rig` (rest по таблице, оси glTF) и метки суставов `rig_joints`.
func _rig_scene() -> Node3D:
	var root := Node3D.new()
	root.name = "rider_rig_reference"
	var skel := Skeleton3D.new()
	skel.name = "rider_rig"
	root.add_child(skel)
	for b in RiderRig.BONES:
		skel.add_bone(b[0])
	var skin := Skin.new()
	for b in RiderRig.BONES:
		var i: int = skel.find_bone(b[0])
		var head: Vector3 = RiderRig.to_gltf(b[2])
		var origin: Vector3 = head
		if not (b[1] as String).is_empty():
			skel.set_bone_parent(i, skel.find_bone(b[1]))
			origin -= RiderRig.to_gltf(RiderRig.head(b[1]))
		skel.set_bone_rest(i, Transform3D(Basis.IDENTITY, origin))
		skin.add_named_bind(b[0], Transform3D(Basis.IDENTITY, -head))
	skel.reset_bone_poses()
	var mi := MeshInstance3D.new()
	mi.name = "rig_joints"
	mi.mesh = _joint_markers()
	skel.add_child(mi)
	mi.skin = skin
	mi.skeleton = NodePath("..")
	return root


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
