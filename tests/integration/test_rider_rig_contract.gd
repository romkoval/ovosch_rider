extends GutTest
## Контракт скелета модели гонщика (T-106a1; подготовка REQ-D3D-09 п.1, 2, 5; бриф художнику
## разделы 4, 5.1, 5.3, 6, 14 — проверки Т2, Т5 (сокеты), Т7; арт-библия «Гонщик»). Источник
## модели — параметр (`RiderContract.RIG_SOURCES`): скелет из кода, эталонная арматура
## `rider_rig_reference.glb`, с T-106b — `rider.glb`; набор проверок один.
## Числа — из брифа (`tests/fixtures/scene3d/rider_contract.gd`), не из таблицы кода.

const RiderContract := preload("res://tests/fixtures/scene3d/rider_contract.gd")
const EPS: float = 1e-4


func _load(src: Dictionary) -> Dictionary:
	var holder := Node3D.new()
	add_child_autofree(holder)
	var rig: Dictionary = RiderContract.load_rig(src, holder)
	assert_eq(rig["error"], "", "%s загружается" % src["name"])
	return rig


## Т2: 25 костей с именами и иерархией брифа 5.1, начала в rest — в допуске источника;
## хвост 0.09–0.10 м; не больше 28 костей (REQ-D3D-09 п.7).
func test_t2_bones_names_parents_heads(src = use_parameters(RiderContract.RIG_SOURCES)) -> void:
	var rig := _load(src)
	if not rig["error"].is_empty():
		return
	var skel: Skeleton3D = rig["skeleton"]
	var brief: Dictionary = RiderContract.brief_bones()
	assert_eq(skel.get_bone_count(), 25, "%s: 25 костей" % src["name"])
	assert_lte(skel.get_bone_count(), RiderRig.MAX_BONES)
	var tol: float = src["tol_m"]
	for name in brief:
		var i: int = skel.find_bone(name)
		assert_true(i >= 0, "%s: кость %s (с .L/.R, как в брифе)" % [src["name"], name])
		if i < 0:
			continue
		var parent: int = skel.get_bone_parent(i)
		assert_eq(skel.get_bone_name(parent) if parent >= 0 else "", brief[name][0], "%s: родитель %s" % [src["name"], name])
		if brief[name][1] == null:
			continue
		var b: Vector3 = RiderRig.to_blender(RiderContract.bone_rest_godot(rig, i).origin)
		assert_lt(b.distance_to(brief[name][1]), tol, "%s: начало %s %s (бриф %s)" % [src["name"], name, b, brief[name][1]])
	var t1: int = skel.find_bone("hair_tail.1")
	var t2: int = skel.find_bone("hair_tail.2")
	if t1 >= 0 and t2 >= 0:
		var tail: float = RiderContract.bone_rest_godot(rig, t1).origin.distance_to(RiderContract.bone_rest_godot(rig, t2).origin)
		assert_between(tail, RiderRig.HAIR_TAIL_MIN_M - tol, RiderRig.HAIR_TAIL_MAX_M + tol, "%s: хвост %.3f м" % [src["name"], tail])


## Т7 и бриф 4: арматура в начале координат, поворот 0, масштаб 1; сетки — без своего
## трансформа; гонщик смотрит вперёд (−Z Godot, −Y Blender), левая сторона — +X Blender.
func test_t7_armature_at_origin_axes_and_scale(src = use_parameters(RiderContract.RIG_SOURCES)) -> void:
	var rig := _load(src)
	if not rig["error"].is_empty():
		return
	var skel: Skeleton3D = rig["skeleton"]
	# Трансформ арматуры — в системе файла (glTF), до нашего перевода осей.
	var xf: Transform3D = skel.global_transform
	assert_lt(xf.origin.length(), EPS, "%s: арматура в начале координат" % src["name"])
	assert_true(xf.basis.is_equal_approx(Basis.IDENTITY), "%s: поворот 0 и масштаб 1 (%s)" % [src["name"], xf.basis])
	for mi in skel.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		assert_true(m.transform.is_equal_approx(Transform3D.IDENTITY), "%s/%s: трансформ применён" % [src["name"], m.name])
	var grip: Vector3 = RiderContract.bone_rest_godot(rig, skel.find_bone("grip.L")).origin
	var pelvis: Vector3 = RiderContract.bone_rest_godot(rig, skel.find_bone("pelvis")).origin
	assert_lt(grip.z, pelvis.z, "%s: руль впереди таза (−Z)" % src["name"])
	assert_gt(RiderRig.to_blender(grip).x, 0.0, "%s: grip.L — +X Blender" % src["name"])
	assert_almost_eq(pelvis.y, RiderContract.BRIEF_SADDLE_TOP_M, src["tol_m"] + EPS, "%s: метры, Z вверх" % src["name"])


## Бриф 5.3: локальная Y кости — к окончанию (начало дочерней кости цепочки), X — параллельно
## мировой X Blender (Recalculate Roll → Global +X).
func test_bone_axes_along_bone_roll_global_x(src = use_parameters(RiderContract.RIG_SOURCES)) -> void:
	var rig := _load(src)
	if not rig["error"].is_empty():
		return
	var skel: Skeleton3D = rig["skeleton"]
	var tol_rad: float = deg_to_rad(src["roll_deg"])
	for name in RiderRig.bone_names():
		var i: int = skel.find_bone(name)
		if i < 0:
			continue
		var rest: Transform3D = RiderContract.bone_rest_godot(rig, i)
		var y: Vector3 = rest.basis.y.normalized()
		var x: Vector3 = rest.basis.x.normalized()
		var child: String = _chain_child(name)
		if not child.is_empty():
			var dir: Vector3 = RiderContract.bone_rest_godot(rig, skel.find_bone(child)).origin - rest.origin
			assert_lt(y.angle_to(dir), tol_rad, "%s: %s — Y к %s" % [src["name"], name, child])
		var want_x: Vector3 = (Vector3.LEFT - y * Vector3.LEFT.dot(y)).normalized()
		assert_lt(x.angle_to(want_x), tol_rad, "%s: %s — крен (X ∥ X Blender)" % [src["name"], name])


## Бриф 5.1, Т5: шесть сокетов — листья иерархии, весов на них нет (кроме сеток-меток).
func test_sockets_leaf_and_without_weights(src = use_parameters(RiderContract.RIG_SOURCES)) -> void:
	var rig := _load(src)
	if not rig["error"].is_empty():
		return
	var skel: Skeleton3D = rig["skeleton"]
	var sockets: Array[int] = []
	for name in RiderContract.BRIEF_SOCKETS:
		var i: int = skel.find_bone(name)
		assert_true(i >= 0, "%s: сокет %s" % [src["name"], name])
		if i >= 0:
			assert_eq(skel.get_bone_children(i).size(), 0, "%s: %s — лист" % [src["name"], name])
			sockets.append(i)
	for node in skel.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if (src["marker_meshes"] as Array).has(String(mi.name)) or mi.skin == null:
			continue
		for s in mi.mesh.get_surface_count():
			var arr: Array = mi.mesh.surface_get_arrays(s)
			var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
			var heavy: int = 0
			for k in bones.size():
				var bind: int = bones[k]
				var bone: int = skel.find_bone(mi.skin.get_bind_name(bind)) if mi.skin.get_bind_name(bind) != &"" else mi.skin.get_bind_bone(bind)
				if weights[k] > 0.0 and sockets.has(bone):
					heavy += 1
			assert_eq(heavy, 0, "%s/%s: на сокетах весов нет" % [src["name"], mi.name])


## Бриф 5.2, 6 и REQ-D3D-09 п.1, 2, 5: поза привязки сидит на `bike_reference.glb` — таз S над
## верхом седла на 0…15 мм, тазобедренные суставы над седлом на 75–95 мм, сокеты `grip` — на
## центре хвата тормозных ручек, `cleat.R` — на оси правой педали (φ = 90°), подошва rest
## «пятка → шип» — носком вниз на 8°.
func test_rest_pose_sits_on_reference_bike(src = use_parameters(RiderContract.RIG_SOURCES)) -> void:
	var rig := _load(src)
	if not rig["error"].is_empty():
		return
	var holder := Node3D.new()
	add_child_autofree(holder)
	var bike: Node = RiderContract.import_glb(RiderContract.BIKE_REFERENCE, holder)
	assert_not_null(bike, "bike_reference.glb импортируется")
	if bike == null:
		return
	var frame := bike.find_child("bike_frame", true, false) as MeshInstance3D
	var to_godot: Transform3D = RiderRig.gltf_flip()
	var skel: Skeleton3D = rig["skeleton"]
	var tol: float = src["tol_m"]
	var at := func(bone: String) -> Vector3: return RiderContract.bone_rest_godot(rig, skel.find_bone(bone)).origin
	var s: Vector3 = at.call("pelvis")
	var top: float = RiderContract.top_at(frame.mesh, s.x, s.z, to_godot)
	assert_between(s.y - top, -tol, 0.015 + tol, "%s: S над седлом на 0…15 мм (%.4f)" % [src["name"], s.y - top])
	for side in [".L", ".R"]:
		var hip: Vector3 = at.call("thigh" + side)
		var hip_top: float = RiderContract.top_at(frame.mesh, 0.0, hip.z, to_godot)
		assert_between(hip.y - hip_top, 0.075 - tol, 0.095 + tol, "%s: thigh%s над седлом 75–95 мм" % [src["name"], side])
		var grip: Vector3 = at.call("grip" + side)
		var hood: float = RiderContract.top_at(frame.mesh, grip.x, grip.z, to_godot)
		assert_almost_eq(hood + RiderModel.HOOD_PALM_CLEARANCE_M, grip.y, 0.005 + tol, "%s: grip%s на ручке" % [src["name"], side])
		var brief_grip: Vector3 = RiderContract.BRIEF_GRIP_L * Vector3(1.0 if side == ".L" else -1.0, 1.0, 1.0)
		assert_lt(RiderRig.to_blender(grip).distance_to(brief_grip), 0.005 + tol, "%s: grip%s ±5 мм" % [src["name"], side])
	var cleat: Vector3 = at.call("cleat.R")
	var axis: Vector3 = (bike.find_child("pt_cleat_R_pedal_axis", true, false) as Node3D).global_position
	assert_lt(cleat.distance_to(RiderRig.from_gltf(axis)), tol + EPS, "%s: cleat.R на оси правой педали" % src["name"])
	var bb: Vector3 = RiderRig.from_blender(RiderContract.BRIEF_BB)
	var pedal: Vector3 = bb + Vector3(RiderContract.BRIEF_PEDAL_X_M, 0.0, -RiderContract.BRIEF_CRANK_M)
	assert_lt(cleat.distance_to(pedal), tol + EPS, "%s: ось педали при φ = 90° — по брифу" % src["name"])
	var heel: Vector3 = at.call("heel.R")
	var pitch: float = rad_to_deg(atan2(cleat.y - heel.y, heel.z - cleat.z))
	assert_almost_eq(pitch, -8.0, 1.0, "%s: подошва rest −8° (%.1f°)" % [src["name"], pitch])
	assert_almost_eq(heel.distance_to(cleat), 0.19, 0.002 + tol, "%s: пятка 0.19 м позади шипа" % src["name"])


## Начало «своего» ребёнка цепочки (бриф 5.1, «Окончание — начало …»); "" — лист или особое
## окончание (`head`, `foot`, сокеты, `hair_tail.2`).
func _chain_child(bone: String) -> String:
	var side: String = bone.right(2) if bone.ends_with(".L") or bone.ends_with(".R") else ""
	var chain := {"pelvis": "spine", "spine": "chest", "chest": "neck", "neck": "head", "upperarm": "forearm",
		"forearm": "hand", "hand": "grip", "thigh": "shin", "shin": "foot", "hair_tail.1": "hair_tail.2"}
	var base: String = bone.trim_suffix(side)
	return (chain[base] as String) + side if chain.has(base) else ""
