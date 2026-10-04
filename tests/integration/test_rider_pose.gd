extends GutTest
## Посадка и движение гонщика на скелете контракта (T-106a2): REQ-D3D-09 п.1–5 (допуски спеки
## «Допуски для `[авто]`» при φ 0…345° шагом 15° и наклоне −0.45…+0.45 рад), п.7 (кости,
## узлы, вес 1 на кость, бюджеты сеток), п.14, 15, 16 (в) и (д), 17 (а)–(в), 18 — для каждой
## фигуры. Источник модели — параметр (`RiderContract.POSE_SOURCES`): манекен `m`/`short` и
## `f`/`tail`, с T-106a4 — `rider.glb`. Числа — из арт-библии «Гонщик» (спека), не из кода.
## П.16 (а), (б), (г) — `test_rider_effort.gd` (сессии на `FakeTrainer`), п.17 (г) и п.7
## «без аллокаций» — статическая проверка `test_scene3d_world_acceptance`.

const RiderContract := preload("res://tests/fixtures/scene3d/rider_contract.gd")
const FRAME: float = 1.0 / 60.0
const LEANS: Array[float] = [-0.45, 0.0, 0.45]
## Спека: верх седла 0.965 м под S, задний край 0.065 м позади S (бриф раздел 6).
const SADDLE_REAR_Z: float = 0.23 + 0.065
const GRIP_R := Vector3(0.21, 0.885, -0.62)
## Таблица параметров движения спеки (A при k = 1, фаза пика «+», °).
const THETA_MEAN: float = -14.0
const THETA_AMP: float = 12.0
const THETA_PHASE: float = 100.0
const KNEE_X_MEAN: float = 0.100
const KNEE_X_AMP: float = 0.008
const PELVIS_ROLL_AMP: float = 0.6
const PELVIS_ROLL_PHASE: float = 180.0
const CHEST_ROLL_AMP: float = 1.5
const CHEST_YAW_AMP: float = 0.8
const CHEST_YAW_PHASE: float = 90.0
const K_LOW: float = 0.35
const K_HIGH: float = 1.3
## Запястье — от линии предплечья (вердикт game-designer по T-106a2, R3).
const WRIST_MAX_DEG: float = 5.0
## Хвост в rest (спека «Гонщик» ред. 4.4, «Причёски»): длина 0.16–0.20 м; вторая кость
## 0.096 ± 0.005 м назад-вниз 28° ± 3° к горизонту. Зазор до джерси — сетка к сетке: у кончика
## 1.3–2.4 см (номинал ≈ 1.85), контур к контуру ≤ 0.3 см (касание контуров допустимо, просвет
## фона — дефект); вся сетка хвоста ≥ 1.0 см; отклонение вниз на предел пружины (4° вокруг корня)
## не заводит хвост в спину.
const TAIL_LEN_MIN_M: float = 0.16
const TAIL_LEN_MAX_M: float = 0.20
const TAIL2_LEN_M: float = 0.096
const TAIL2_DOWN_DEG: float = 28.0
const TAIL_TIP_GAP_MIN_M: float = 0.013
const TAIL_TIP_GAP_MAX_M: float = 0.024
const TAIL_TIP_OUTLINE_GAP_MAX_M: float = 0.003
const TAIL_GAP_MIN_M: float = 0.010
## Корень хвоста с резинкой — вершины `hair_tail.1/2` ближе этого к началу `hair_tail.1`, м: под
## задним краем шлема у воротника, зазор ≥ 1.0 см к ним не применяется (только «не входит»).
const TAIL_ROOT_ZONE_M: float = 0.025
## Пружина хвоста устанавливается за это время от старта каденса; амплитуды сравниваются после, с.
const TAIL_SETTLE_S: float = 3.0
## Кончик хвоста — вершины `hair_tail.2` ближе этого к окончанию кости, м.
const TAIL_TIP_ZONE_M: float = 0.02
## Бюджет треугольников узлов (спека «Состав и бюджет»).
const NODE_TRIS: Dictionary = {"Body": 8000, "Hair": 800, "Helmet": 1600, "Eyewear": 400, "ShoeL": 600,
	"ShoeR": 600, "Bike": 2600, "FrontWheel": 1600, "RearWheel": 1600, "CrankArm": 600}
const TOTAL_TRIS: int = 18500

var _saddle_mesh: Mesh


func _rider(src: Dictionary) -> Rider:
	var holder := Node3D.new()
	add_child_autofree(holder)
	var r := RiderContract.load_rider(src, holder)
	_saddle_mesh = (r.get_node("%Bike") as MeshInstance3D).mesh
	return r


func _tris(mesh: Mesh) -> int:
	var n: int = 0
	for si in mesh.get_surface_count():
		n += (mesh.surface_get_arrays(si)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
	return n


func _p(r: Rider, bone: String) -> Vector3:
	return r.bone_pose(bone).origin


func _saddle_top(x: float, z: float) -> float:
	return RiderContract.top_at(_saddle_mesh, x, z)


## Ось педали стороны (+1 — правая) при φ этой стороны, система `Lean`.
func _pedal(side_phi: float, sx: float) -> Vector3:
	return Vector3(0.115 * sx, 0.27 + 0.17 * cos(side_phi), -0.17 * sin(side_phi))


## Угол стопы θ, °: линия «пятка → шип» к горизонтали в продольной плоскости, «+» — носок вверх.
func _theta(r: Rider, side: String) -> float:
	var c := _p(r, "cleat" + side)
	var h := _p(r, "heel" + side)
	return rad_to_deg(atan2(c.y - h.y, h.z - c.z))


## Внутренний угол колена, °.
func _knee_angle(r: Rider, side: String) -> float:
	var k := _p(r, "shin" + side)
	return rad_to_deg((_p(r, "thigh" + side) - k).angle_to(_p(r, "foot" + side) - k))


## Крен и рыскание кости относительно rest (велосипеда), °: крен > 0 — правая сторона вниз
## (поворот вокруг −Z), рыскание > 0 — правая сторона вперёд (вокруг +Y).
func _roll_yaw(r: Rider, bone: String) -> Vector2:
	var skel := r.skeleton()
	var i := skel.find_bone(bone)
	var d: Basis = skel.get_bone_global_pose(i).basis * skel.get_bone_global_rest(i).basis.inverse()
	var x: Vector3 = d * Vector3.RIGHT
	return Vector2(rad_to_deg(asin(clampf(-x.y, -1.0, 1.0))), rad_to_deg(atan2(-x.z, x.x)))


## Обход φ = 0…345° шагом 15°: `fn(φ°)` при заданных наклоне и k.
func _sweep(r: Rider, lean: float, k: float, fn: Callable) -> void:
	r.set_lean(lean)
	r.set_effort_k(k)
	for i in 24:
		r.set_crank_angle(deg_to_rad(15.0 * i))
		fn.call(15.0 * i)


# ---------------------------------------------------------------------------
# П.1–5 — посадка
# ---------------------------------------------------------------------------

## П.1: S над седлом на 0…15 мм, 0.03–0.10 м впереди заднего края, |S.x| ≤ 0.01; S от φ не
## двигается (±1 мм); крен таза — поворот вокруг S, крен корпуса ≤ 2°.
func test_p1_pelvis_on_saddle(src = use_parameters(RiderContract.POSE_SOURCES)) -> void:
	var r := _rider(src)
	var bad: Array[String] = []
	var s0: Vector3 = RiderRig.head("pelvis")
	for lean in LEANS:
		for k in [1.0, K_HIGH]:
			_sweep(r, lean, k, func(deg: float) -> void:
				var s := _p(r, "pelvis")
				var dy: float = s.y - _saddle_top(s.x, s.z)
				var ahead: float = SADDLE_REAR_Z - s.z
				var roll: float = absf(_roll_yaw(r, "chest").x)
				if dy < -1e-4 or dy > 0.015 or ahead < 0.03 or ahead > 0.10 or absf(s.x) > 0.01 \
						or s.distance_to(s0) > 0.001 or roll > 2.0:
					bad.append("%s φ=%d k=%.2f lean=%.2f: dy=%.4f впереди=%.3f x=%.4f сдвиг=%.4f крен=%.2f°" % [
						src["name"], deg, k, lean, dy, ahead, s.x, s.distance_to(s0), roll]))
	assert_eq(bad, [] as Array[String], "п.1: %s" % str(bad.slice(0, 4)))


## П.2: HIP над седлом на 75–95 мм, впереди S на 0.02–0.06, |HIP.x| 0.085–0.095; начало кости
## бедра — в HIP контракта ±0.01 м.
func test_p2_thighs_from_pelvis(src = use_parameters(RiderContract.POSE_SOURCES)) -> void:
	var r := _rider(src)
	var bad: Array[String] = []
	for lean in LEANS:
		_sweep(r, lean, K_HIGH, func(deg: float) -> void:
			var s := _p(r, "pelvis")
			for side in [".L", ".R"]:
				var hip := _p(r, "thigh" + side)
				var dy: float = hip.y - _saddle_top(0.0, hip.z)
				var dz: float = hip.z - s.z
				var off: float = hip.distance_to(RiderRig.head("thigh" + side))
				if dy < 0.075 or dy > 0.095 or dz < -0.06 or dz > -0.02 or absf(hip.x) < 0.085 or absf(hip.x) > 0.095 or off > 0.01:
					bad.append("%s φ=%d%s: dy=%.4f dz=%.4f x=%.4f от HIP %.4f" % [src["name"], deg, side, dy, dz, hip.x, off]))
	assert_eq(bad, [] as Array[String], "п.2: %s" % str(bad.slice(0, 4)))


## П.3: колено впереди и выше прямой HIP — ось педали на ≥ 0.03 м, |колено.x| 0.07–0.13; угол
## колена в нижней точке 140–155°, наименьший за оборот 65–80°; длины бедра и голени ±1 мм; шип
## на оси педали ±0.01 м.
func test_p3_knee_lengths_and_cleat_on_pedal(src = use_parameters(RiderContract.POSE_SOURCES)) -> void:
	var r := _rider(src)
	var thigh_rest: float = RiderRig.span("thigh.R", "shin.R")
	var shin_rest: float = RiderRig.span("shin.R", "foot.R")
	var bad: Array[String] = []
	var min_angle := {".L": 999.0, ".R": 999.0}
	var bottom := {}
	for lean in LEANS:
		for k in [K_LOW, K_HIGH]:
			_sweep(r, lean, k, func(deg: float) -> void:
				for side in [".L", ".R"]:
					var sx: float = -1.0 if side == ".L" else 1.0
					var side_phi: float = deg_to_rad(deg if side == ".R" else deg + 180.0)
					var hip := _p(r, "thigh" + side)
					var knee := _p(r, "shin" + side)
					var ankle := _p(r, "foot" + side)
					var pedal := _pedal(side_phi, sx)
					var d := Vector2(pedal.y - hip.y, pedal.z - hip.z).normalized()
					var n := Vector2(-d.y, d.x)
					if n.y > 0.0:
						n = -n
					var dist: float = Vector2(knee.y - hip.y, knee.z - hip.z).dot(n)
					var ang := _knee_angle(r, side)
					min_angle[side] = minf(min_angle[side], ang)
					if is_equal_approx(fposmod(rad_to_deg(side_phi), 360.0), 180.0):
						bottom[side + str(lean) + str(k)] = ang
					var dl: float = maxf(absf(hip.distance_to(knee) - thigh_rest), absf(knee.distance_to(ankle) - shin_rest))
					var cleat_err: float = _p(r, "cleat" + side).distance_to(pedal)
					if dist < 0.03 or knee.y < minf(hip.y, pedal.y) or absf(knee.x) < 0.07 or absf(knee.x) > 0.13 \
							or dl > 0.001 or cleat_err > 0.01:
						bad.append("%s φ=%d%s: до прямой %.3f x=%.3f Δдлины=%.5f шип %.4f" % [src["name"], deg, side, dist,
							knee.x, dl, cleat_err]))
	assert_eq(bad, [] as Array[String], "п.3: %s" % str(bad.slice(0, 4)))
	for side in min_angle:
		assert_between(float(min_angle[side]), 65.0, 80.0, "%s%s: наименьший угол колена %.1f°" % [src["name"], side, min_angle[side]])
	assert_gt(bottom.size(), 0, "нижняя точка проверена")
	for key in bottom:
		assert_between(float(bottom[key]), 140.0, 155.0, "%s %s: угол колена в нижней точке %.1f°" % [src["name"], key, bottom[key]])


## П.4: θ ∈ [−35°; +10°] за оборот, окна при φ = 0/90/180/270°, носок впереди пятки.
func test_p4_foot_angle(src = use_parameters(RiderContract.POSE_SOURCES)) -> void:
	var r := _rider(src)
	var windows := {0: [-25.0, 0.0], 90: [-12.0, 8.0], 180: [-35.0, -10.0], 270: [-28.0, -5.0]}
	var bad: Array[String] = []
	for lean in LEANS:
		_sweep(r, lean, 1.0, func(deg: float) -> void:
			for side in [".L", ".R"]:
				var side_deg: int = int(deg) if side == ".R" else int(fposmod(deg + 180.0, 360.0))
				var th := _theta(r, side)
				var lo: float = -35.0
				var hi: float = 10.0
				if windows.has(side_deg):
					lo = windows[side_deg][0]
					hi = windows[side_deg][1]
				if th < lo or th > hi or _p(r, "cleat" + side).z >= _p(r, "heel" + side).z:
					bad.append("%s φ=%d%s: θ=%.1f° (окно %.0f…%.0f)" % [src["name"], deg, side, th, lo, hi]))
	assert_eq(bad, [] as Array[String], "п.4: %s" % str(bad.slice(0, 4)))


## П.5: хват каждой кисти ≤ 0.015 м от точки хвата ручки, запястье ≤ 20°, локти 140–165°
## (спека п.8 списка «Что закодировать»); при любом φ и наклоне.
func test_p5_hands_on_hoods(src = use_parameters(RiderContract.POSE_SOURCES)) -> void:
	var r := _rider(src)
	var bad: Array[String] = []
	for lean in LEANS:
		_sweep(r, lean, K_HIGH, func(deg: float) -> void:
			for side in [".L", ".R"]:
				var sx: float = -1.0 if side == ".L" else 1.0
				var grip := _p(r, "grip" + side)
				var hood := Vector3(GRIP_R.x * sx, GRIP_R.y, GRIP_R.z)
				var fore := _p(r, "forearm" + side)
				var hand := _p(r, "hand" + side)
				var wrist: float = rad_to_deg((hand - fore).angle_to(grip - hand))
				var elbow: float = rad_to_deg((_p(r, "upperarm" + side) - fore).angle_to(hand - fore))
				if grip.distance_to(hood) > 0.015 or wrist > 20.0 or elbow < 140.0 or elbow > 165.0:
					bad.append("%s φ=%d%s: хват %.4f запястье %.1f° локоть %.1f°" % [src["name"], deg, side,
						grip.distance_to(hood), wrist, elbow]))
	assert_eq(bad, [] as Array[String], "п.5: %s" % str(bad.slice(0, 4)))


## П.5, запястье (вердикт game-designer по T-106a2, R3): кисть ≤ 5° от линии предплечья
## (угол «локоть → запястье» к «запястье → точка хвата») при k = 1.3 во всём диапазоне наклона
## −0.45…+0.45 рад и при φ 0…345° шагом 15°.
func test_p5_wrist_in_line_with_forearm(src = use_parameters(RiderContract.POSE_SOURCES)) -> void:
	var r := _rider(src)
	var bad: Array[String] = []
	var worst: Array[float] = [0.0]
	var elbow: Array[float] = [180.0, 0.0]
	var slide: Array[float] = [0.0]
	for i in 9:
		var lean: float = lerpf(-0.45, 0.45, float(i) / 8.0)
		_sweep(r, lean, K_HIGH, func(deg: float) -> void:
			for side in [".L", ".R"]:
				var fore := _p(r, "forearm" + side)
				var hand := _p(r, "hand" + side)
				var wrist: float = rad_to_deg((hand - fore).angle_to(_p(r, "grip" + side) - hand))
				worst[0] = maxf(worst[0], wrist)
				var el: float = rad_to_deg((_p(r, "upperarm" + side) - fore).angle_to(hand - fore))
				elbow[0] = minf(elbow[0], el)
				elbow[1] = maxf(elbow[1], el)
				slide[0] = maxf(slide[0], _p(r, "grip" + side).distance_to(Vector3(GRIP_R.x * (-1.0 if side == ".L" else 1.0), GRIP_R.y, GRIP_R.z)))
				if wrist > WRIST_MAX_DEG:
					bad.append("%s наклон %.2f φ=%d%s: запястье %.2f°" % [src["name"], lean, deg, side, wrist]))
	assert_eq(bad, [] as Array[String], "запястье ≤ 5° (худшее %.2f°): %s" % [worst[0], str(bad.slice(0, 4))])
	gut.p("%s: запястье худшее %.2f°, локоть %.1f…%.1f°, ладонь от точки хвата ≤ %.4f м" % [src["name"],
		worst[0], elbow[0], elbow[1], slide[0]])


# ---------------------------------------------------------------------------
# П.7 — состав и бюджет
# ---------------------------------------------------------------------------

## Кости ≤ 28 (25 по контракту), узлов с сетками ≤ 10 (состав спеки), один материал, без
## источников света; треугольники узлов и итог — в бюджете спеки (самые тяжёлые варианты).
func test_p7_bones_nodes_material_budget(src = use_parameters(RiderContract.POSE_SOURCES)) -> void:
	var r := _rider(src)
	assert_eq(r.skeleton().get_bone_count(), RiderRig.BONE_COUNT, "25 костей контракта")
	assert_lte(r.skeleton().get_bone_count(), 28, "костей ≤ 28")
	var meshes := r.find_children("*", "MeshInstance3D", true, false)
	assert_lte(meshes.size(), 10, "%s: MeshInstance3D ≤ 10" % src["name"])
	var names: Array[String] = []
	for m in meshes:
		names.append(String(m.name))
	for n in NODE_TRIS:
		assert_true(names.has(n), "%s: узел %s" % [src["name"], n])
	assert_eq(r.find_children("*", "Light3D", true, false).size(), 0, "гонщик не добавляет света")
	var materials := {}
	var total: int = 0
	var all_meshes: Dictionary = RiderModel.meshes(Rider.RIDER_MATERIAL)
	var heaviest := {"Body": ["body_m", "body_f"], "Hair": ["hair_short", "hair_tail"]}
	for m in meshes:
		var mi := m as MeshInstance3D
		materials[mi.get_active_material(0)] = true
		var variants: Array = heaviest.get(String(mi.name), [])
		var tris: int = _tris(mi.mesh)
		for v in variants:
			tris = maxi(tris, _tris(all_meshes[v]))
		assert_lte(tris, int(NODE_TRIS[String(mi.name)]), "%s: треугольников %d" % [mi.name, tris])
		total += tris
	assert_lte(total, TOTAL_TRIS, "итого треугольников %d ≤ 18 500" % total)
	assert_eq(materials.size(), 1, "один материал на гонщика с велосипедом")


## Вес 1 на одну деформирующую кость у каждой вершины сеток гонщика (манекен, спека «Порядок
## работ»); сетки привязаны к скелету контракта общим `Skin`.
func test_p7_dummy_rigid_weights_on_contract_bones(src = use_parameters(RiderContract.POSE_SOURCES)) -> void:
	var r := _rider(src)
	var skel := r.skeleton()
	for part in ["Body", "Hair", "Helmet", "Eyewear", "ShoeL", "ShoeR"]:
		var mi := r.get_node("%" + part) as MeshInstance3D
		assert_not_null(mi.skin, "%s: скиннинг" % part)
		assert_eq(mi.get_node(mi.skeleton), skel, "%s: скелет гонщика" % part)
		var arr: Array = mi.mesh.surface_get_arrays(0)
		var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
		var bad: int = 0
		var used := {}
		for v in bones.size() / 4:
			var bone_name: String = mi.skin.get_bind_name(bones[v * 4])
			used[bone_name] = true
			if not is_equal_approx(weights[v * 4], 1.0) or weights[v * 4 + 1] != 0.0 or RiderRig.is_socket(bone_name):
				bad += 1
		assert_eq(bad, 0, "%s/%s: вес 1 на одну кость, не сокет" % [src["name"], part])
		if part in ["Helmet", "Eyewear"]:
			assert_eq(used.keys(), ["head"], "%s — жёстко на head" % part)
		if part == "ShoeR":
			assert_eq(used.keys(), ["foot.R"], "туфля — на foot.R")
		if part == "Hair" and src["hair"] == "tail":
			assert_true(used.has("hair_tail.1") and used.has("hair_tail.2"), "хвост на hair_tail.1/2")


## Смена фигуры и причёски — подмена `mesh` тех же узлов (instance_id), узлов не больше.
func test_p7_figure_and_hair_swap_same_nodes(src = use_parameters(RiderContract.POSE_SOURCES)) -> void:
	var r := _rider(src)
	var ids := {}
	for m in r.find_children("*", "MeshInstance3D", true, false):
		ids[String(m.name)] = m.get_instance_id()
	var meshes: Dictionary = RiderModel.meshes(Rider.RIDER_MATERIAL)
	for fig in Rider.FIGURES:
		for hair in Rider.HAIR_STYLES:
			r.set_figure(fig)
			r.set_hair_style(hair)
			var now := r.find_children("*", "MeshInstance3D", true, false)
			assert_eq(now.size(), ids.size(), "%s/%s: узлов столько же" % [fig, hair])
			for m in now:
				assert_eq(m.get_instance_id(), ids[String(m.name)], "%s/%s: %s — тот же узел" % [fig, hair, m.name])
			assert_eq((r.get_node("%Body") as MeshInstance3D).mesh, meshes["body_" + fig], "Body = body_%s" % fig)
			assert_eq((r.get_node("%Hair") as MeshInstance3D).mesh, meshes["hair_" + hair], "Hair = hair_%s" % hair)


## Фигуры отличаются объёмом (таблица фигур спеки): плечи снаружи по дельтам `m` 0.44–0.46,
## `f` 0.40–0.42; таз по шортам `m` 0.34–0.36, `f` 0.35–0.37; суставы общие.
func test_figures_shoulder_and_hip_width() -> void:
	var meshes: Dictionary = RiderModel.meshes(Rider.RIDER_MATERIAL)
	var skin: Skin = RiderModel.rider_skin()
	var bands := {"m": [Vector2(0.44, 0.46), Vector2(0.34, 0.36)], "f": [Vector2(0.40, 0.42), Vector2(0.35, 0.37)]}
	var sh_y: float = RiderRig.head("upperarm.R").y
	for fig in bands:
		var arr: Array = (meshes["body_" + fig] as ArrayMesh).surface_get_arrays(0)
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES]
		var shoulders: float = 0.0
		var hips: float = 0.0
		for v in verts.size():
			var b: String = skin.get_bind_name(bones[v * 4])
			var p: Vector3 = verts[v]
			if (b == "chest" or b.begins_with("upperarm")) and p.y >= sh_y - 0.02:
				shoulders = maxf(shoulders, absf(p.x) * 2.0)
			if b == "pelvis" or b.begins_with("thigh"):
				hips = maxf(hips, absf(p.x) * 2.0)
		var sh: Vector2 = bands[fig][0]
		var hp: Vector2 = bands[fig][1]
		assert_between(shoulders, sh.x, sh.y, "%s: плечи по дельтам %.3f м" % [fig, shoulders])
		assert_between(hips, hp.x, hp.y, "%s: таз по шортам %.3f м" % [fig, hips])


# ---------------------------------------------------------------------------
# П.14–17 — движение по видео-референсу
# ---------------------------------------------------------------------------

## П.14: θ по кривой спеки ±2° при каждом φ, от k не зависит (±0.1°); контрольные позы правой
## ноги (φ = 0/90/180/270°): шип, голеностоп, колено ±0.01 м, угол колена ±2°.
func test_p14_foot_curve_and_control_poses(src = use_parameters(RiderContract.POSE_SOURCES)) -> void:
	var r := _rider(src)
	var at_low := {}
	var bad: Array[String] = []
	_sweep(r, 0.0, K_LOW, func(deg: float) -> void:
		at_low[deg] = [_theta(r, ".R"), _theta(r, ".L")])
	_sweep(r, 0.0, K_HIGH, func(deg: float) -> void:
		for i in 2:
			var side_deg: float = deg if i == 0 else deg + 180.0
			var th: float = _theta(r, ".R" if i == 0 else ".L")
			var want: float = THETA_MEAN + THETA_AMP * cos(deg_to_rad(side_deg - THETA_PHASE))
			if absf(th - want) > 2.0 or absf(th - float(at_low[deg][i])) > 0.1:
				bad.append("φ=%d сторона %d: θ=%.2f кривая %.2f при k_min %.2f" % [deg, i, th, want, at_low[deg][i]]))
	assert_eq(bad, [] as Array[String], "%s п.14 θ: %s" % [src["name"], str(bad.slice(0, 4))])
	# Таблица «Контрольные позы правой ноги» спеки: φ → шип (y, z), голеностоп, колено, угол колена.
	var table := {0: [Vector2(0.440, 0.000), Vector2(0.555, 0.092), Vector2(0.873, -0.213), 70.0],
		90: [Vector2(0.270, -0.170), Vector2(0.360, -0.053), Vector2(0.786, -0.162), 113.0],
		180: [Vector2(0.100, 0.000), Vector2(0.208, 0.100), Vector2(0.642, 0.026), 148.0],
		270: [Vector2(0.270, 0.170), Vector2(0.399, 0.241), Vector2(0.701, -0.078), 96.0]}
	r.set_effort_k(1.0)
	for deg in table:
		r.set_crank_angle(deg_to_rad(float(deg)))
		var row: Array = table[deg]
		var pts := [_p(r, "cleat.R"), _p(r, "foot.R"), _p(r, "shin.R")]
		var xs := [0.115, 0.110, 0.100]
		for j in 3:
			var want := Vector3(xs[j], (row[j] as Vector2).x, (row[j] as Vector2).y)
			assert_lt((pts[j] as Vector3).distance_to(want), 0.01, "%s φ=%d: точка %d %s (таблица %s)" % [src["name"], deg, j, pts[j], want])
		assert_almost_eq(_knee_angle(r, ".R"), float(row[3]), 2.0, "%s φ=%d: угол колена" % [src["name"], deg])


## Ряд значений параметра за оборот при k: [φ°] → значение.
func _series(r: Rider, k: float, fn: Callable) -> Dictionary:
	var out := {}
	r.set_lean(0.0)
	r.set_effort_k(k)
	for i in 72:
		r.set_crank_angle(deg_to_rad(5.0 * i))
		out[5.0 * i] = fn.call()
	return out


## Амплитуда (половина размаха) и φ пика ряда.
func _amp_peak(series: Dictionary) -> Vector2:
	var lo: float = INF
	var hi: float = -INF
	var peak: float = 0.0
	for deg in series:
		var v: float = series[deg]
		lo = minf(lo, v)
		if v > hi:
			hi = v
			peak = deg
	return Vector2((hi - lo) * 0.5, peak)


func _phase_err(a: float, b: float) -> float:
	return absf(wrapf(a - b, -180.0, 180.0))


## П.15 при k = 1: (а) крен груди 1.2–1.95°, пик «правая сторона вниз» при φ 120–180°;
## (б) крен таза ≤ 1°; (в) фаза пика крена таза и рыскания ±15°, амплитуда ±10 %; (г) |колено.x|
## — среднее и амплитуда ±2 мм; (д) начало `head` вбок ≤ 0.02 м, крен головы в мире ≤ 0.6°;
## (е) крен и рыскание при φ и φ + 180° — равны по модулю, противоположны по знаку (±0.1°).
func test_p15_sway_at_k1(src = use_parameters(RiderContract.POSE_SOURCES)) -> void:
	var r := _rider(src)
	var chest_roll := _series(r, 1.0, func() -> float: return _roll_yaw(r, "chest").x)
	var chest_yaw := _series(r, 1.0, func() -> float: return _roll_yaw(r, "chest").y)
	var pelvis_roll := _series(r, 1.0, func() -> float: return _roll_yaw(r, "pelvis").x)
	var knee_x := _series(r, 1.0, func() -> float: return absf(_p(r, "shin.R").x))
	var head_x := _series(r, 1.0, func() -> float: return absf(_p(r, "head").x))
	var head_roll := _series(r, 1.0, func() -> float: return absf(_roll_yaw(r, "head").x))
	var cr := _amp_peak(chest_roll)
	assert_between(cr.x, 1.2, 1.95, "%s (а) амплитуда крена груди %.2f°" % [src["name"], cr.x])
	assert_between(cr.y, 120.0, 180.0, "%s (а) пик «правая вниз» при φ=%.0f°" % [src["name"], cr.y])
	var pr := _amp_peak(pelvis_roll)
	assert_lte(pr.x, 1.0, "%s (б) крен таза %.2f°" % [src["name"], pr.x])
	assert_lte(_phase_err(pr.y, PELVIS_ROLL_PHASE), 15.0, "%s (в) фаза крена таза %.0f°" % [src["name"], pr.y])
	assert_almost_eq(pr.x, PELVIS_ROLL_AMP, PELVIS_ROLL_AMP * 0.1, "%s (в) амплитуда крена таза" % src["name"])
	var yw := _amp_peak(chest_yaw)
	assert_lte(_phase_err(yw.y, CHEST_YAW_PHASE), 15.0, "%s (в) фаза рыскания %.0f°" % [src["name"], yw.y])
	assert_almost_eq(yw.x, CHEST_YAW_AMP, CHEST_YAW_AMP * 0.1, "%s (в) амплитуда рыскания %.3f°" % [src["name"], yw.x])
	var kx := _amp_peak(knee_x)
	var lo: float = INF
	var hi: float = -INF
	for deg in knee_x:
		lo = minf(lo, knee_x[deg])
		hi = maxf(hi, knee_x[deg])
	assert_almost_eq((lo + hi) * 0.5, KNEE_X_MEAN, 0.002, "%s (г) среднее |колено.x|" % src["name"])
	assert_almost_eq(kx.x, KNEE_X_AMP, 0.002, "%s (г) амплитуда |колено.x| %.4f" % [src["name"], kx.x])
	var hx: float = 0.0
	var hr: float = 0.0
	for deg in head_x:
		hx = maxf(hx, head_x[deg])
		hr = maxf(hr, head_roll[deg])
	assert_lte(hx, 0.02, "%s (д) голова вбок %.4f м" % [src["name"], hx])
	assert_lte(hr, 0.6, "%s (д) крен головы в мире %.3f°" % [src["name"], hr])
	var bad: Array[String] = []
	for deg in chest_roll:
		if deg >= 180.0:
			continue
		for pair in [[chest_roll, "крен груди"], [chest_yaw, "рыскание"], [pelvis_roll, "крен таза"]]:
			var s: Dictionary = pair[0]
			if absf(float(s[deg]) + float(s[deg + 180.0])) > 0.1:
				bad.append("%s φ=%d: %.3f / %.3f" % [pair[1], deg, s[deg], s[deg + 180.0]])
	assert_eq(bad, [] as Array[String], "%s (е) левая = правая через 180°: %s" % [src["name"], str(bad.slice(0, 4))])


## П.15, предел: крен груди от педалирования ≤ 2° при k до верхней границы и наклоне −0.45…0.45.
func test_p15_chest_roll_limit_with_lean(src = use_parameters(RiderContract.POSE_SOURCES)) -> void:
	var r := _rider(src)
	var worst := [0.0]
	for lean in LEANS:
		_sweep(r, lean, K_HIGH, func(_deg: float) -> void:
			worst[0] = maxf(worst[0], absf(_roll_yaw(r, "chest").x)))
	assert_lte(float(worst[0]), 2.0, "%s: крен груди ≤ 2° (%.2f°)" % [src["name"], worst[0]])


## П.16 (в): амплитуды крена груди, крена таза, рыскания и колена вбок = A · k ±5 % при
## k = 0.35, 1, 1.3; θ от k не зависит (п.14).
func test_p16c_amplitudes_proportional_to_k(src = use_parameters(RiderContract.POSE_SOURCES)) -> void:
	var r := _rider(src)
	for k in [K_LOW, 1.0, K_HIGH]:
		var checks := [
			[func() -> float: return _roll_yaw(r, "chest").x, CHEST_ROLL_AMP, "крен груди"],
			[func() -> float: return _roll_yaw(r, "pelvis").x, PELVIS_ROLL_AMP, "крен таза"],
			[func() -> float: return _roll_yaw(r, "chest").y, CHEST_YAW_AMP, "рыскание"],
			[func() -> float: return absf(_p(r, "shin.R").x), KNEE_X_AMP, "колено вбок"],
		]
		for c in checks:
			var amp: float = _amp_peak(_series(r, k, c[0])).x
			var want: float = float(c[1]) * k
			assert_almost_eq(amp, want, want * 0.05, "%s k=%.2f %s: %.4f (A·k = %.4f)" % [src["name"], k, c[2], amp, want])


## Все кости: начала и оси в системе `Lean`.
func _snapshot(r: Rider) -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	for i in r.skeleton().get_bone_count():
		out.append(r.skeleton().get_bone_global_pose(i))
	return out


func _max_diff(a: Array[Transform3D], b: Array[Transform3D]) -> Vector2:
	var d := Vector2.ZERO
	for i in a.size():
		d.x = maxf(d.x, a[i].origin.distance_to(b[i].origin))
		d.y = maxf(d.y, rad_to_deg(a[i].basis.get_rotation_quaternion().angle_to(b[i].basis.get_rotation_quaternion())))
	return d


## П.16 (д), D3D-04 п.2: при каденсе 0 k не обновляется — смена P за 5 с не меняет позу
## (±1 мм, ±0.1°).
func test_p16e_zero_cadence_freezes_pose(src = use_parameters(RiderContract.POSE_SOURCES)) -> void:
	var r := _rider(src)
	r.set_power(100, true, 200)
	r.set_cadence(90)
	for i in 180:
		r.advance(FRAME)
	r.set_cadence(0)
	for i in 600:
		r.advance(FRAME)
	var k0: float = r.effort_k
	var before := _snapshot(r)
	r.set_power(400, true, 200)
	for i in 300:
		r.advance(FRAME)
	var d := _max_diff(before, _snapshot(r))
	assert_eq(r.effort_k, k0, "k заморожен при каденсе 0")
	assert_lte(d.x, 0.001, "%s: кости не сдвинулись (%.5f м)" % [src["name"], d.x])
	assert_lte(d.y, 0.1, "%s: кости не повернулись (%.3f°)" % [src["name"], d.y])


## П.17 (а): при k на верхней границе велосипед относительно `Lean` от φ не зависит, S
## относительно седла — тоже (±1 мм, ±0.1°).
func test_p17a_bike_and_pelvis_still(src = use_parameters(RiderContract.POSE_SOURCES)) -> void:
	var r := _rider(src)
	var bike := r.get_node("%Bike") as Node3D
	var wheels := [r.get_node("%FrontWheel") as Node3D, r.get_node("%RearWheel") as Node3D]
	var bike0: Transform3D = bike.transform
	var s0 := RiderRig.head("pelvis")
	var bad: Array[String] = []
	_sweep(r, 0.0, K_HIGH, func(deg: float) -> void:
		if not bike.transform.is_equal_approx(bike0) or _p(r, "pelvis").distance_to(s0) > 0.001:
			bad.append("φ=%d" % deg)
		for w in wheels:
			if (w as Node3D).position.distance_to(RiderRig.FRONT_AXLE if w == wheels[0] else RiderRig.REAR_AXLE) > 0.001:
				bad.append("φ=%d колесо" % deg))
	assert_eq(bad, [] as Array[String], "%s: велосипед и S стоят: %s" % [src["name"], str(bad.slice(0, 4))])


## Параметры п.14–15 кадра: θ, |колено.x|, крен таза, крен и рыскание груди.
func _params(r: Rider) -> PackedFloat32Array:
	var c := _roll_yaw(r, "chest")
	return PackedFloat32Array([_theta(r, ".R"), absf(_p(r, "shin.R").x) * 1000.0, _roll_yaw(r, "pelvis").x, c.x, c.y])


## П.17 (б): при постоянных каденсе (60, 90, 100, 120) и P амплитуда каждого параметра за
## обороты 11–20 не больше, чем за 1–10 (+2 %); (в) при 120 об/мин переход φ через 0° без скачка.
func test_p17bc_stable_amplitude_and_no_jump_at_zero(src = use_parameters(RiderContract.POSE_SOURCES)) -> void:
	for rpm in [60, 90, 100, 120]:
		var r := _rider(src)
		r.set_power(200, true, 200)
		r.set_cadence(rpm)
		var lo := [[], []]
		var hi := [[], []]
		for w in 2:
			for j in 5:
				lo[w].append(INF)
				hi[w].append(-INF)
		var turns: float = 0.0
		var prev_phi: float = r.crank_rotation_rad()
		var prev := _params(r)
		var wrap_jump := PackedFloat32Array([0, 0, 0, 0, 0])
		var other_jump := PackedFloat32Array([0, 0, 0, 0, 0])
		while turns < 20.0:
			r.advance(FRAME)
			var phi: float = r.crank_rotation_rad()
			var dphi: float = fposmod(phi - prev_phi, TAU)
			turns += dphi / TAU
			var wrapped: bool = phi < prev_phi
			prev_phi = phi
			var cur := _params(r)
			var win: int = 0 if turns <= 10.0 else 1
			for j in 5:
				lo[win][j] = minf(lo[win][j], cur[j])
				hi[win][j] = maxf(hi[win][j], cur[j])
				if turns > 18.0 and turns <= 19.0 or wrapped and turns > 18.0 and turns < 19.5:
					var jump: float = absf(cur[j] - prev[j])
					if wrapped:
						wrap_jump[j] = maxf(wrap_jump[j], jump)
					else:
						other_jump[j] = maxf(other_jump[j], jump)
			prev = cur
		for j in 5:
			var a1: float = hi[0][j] - lo[0][j]
			var a2: float = hi[1][j] - lo[1][j]
			assert_lte(a2, a1 * 1.02 + 1e-6, "%s %d об/мин: параметр %d — обороты 11–20 (%.4f) ≤ 1–10 (%.4f)" % [src["name"], rpm, j, a2, a1])
			if rpm == 120:
				assert_lte(wrap_jump[j], other_jump[j] * 1.02 + 1e-6, "%s: параметр %d через 0° без скачка (%.5f / %.5f)" % [
					src["name"], j, wrap_jump[j], other_jump[j]])


# ---------------------------------------------------------------------------
# П.18 — хвост
# ---------------------------------------------------------------------------

## Отклонение кончика хвоста от rest в системе головы, °: x — вбок, y — вверх-вниз, z — от
## направления rest (конус).
func _tail_dev(r: Rider) -> Vector3:
	var head: Transform3D = r.bone_pose("head")
	var t1: Transform3D = r.bone_pose("hair_tail.1")
	var t2: Transform3D = r.bone_pose("hair_tail.2")
	var len2: float = RiderRig.tail("hair_tail.2").distance_to(RiderRig.head("hair_tail.2"))
	var tip: Vector3 = t2.origin + t2.basis.y.normalized() * len2
	var skel := r.skeleton()
	var head_rest: Transform3D = skel.get_bone_global_rest(skel.find_bone("head"))
	var now: Vector3 = (head.basis.inverse() * (tip - t1.origin)).normalized()
	var rest: Vector3 = (head_rest.basis.inverse() * (RiderRig.tail("hair_tail.2") - RiderRig.head("hair_tail.1"))).normalized()
	var side: float = rad_to_deg(asin(clampf(now.x, -1.0, 1.0)) - asin(clampf(rest.x, -1.0, 1.0)))
	var vert: float = rad_to_deg(wrapf(atan2(now.y, now.z) - atan2(rest.y, rest.z), -PI, PI))
	return Vector3(side, vert, rad_to_deg(now.angle_to(rest)))


func test_p18_tail_spring_parameters_in_spec() -> void:
	assert_between(RiderMotion.TAIL_FREQ_HZ, 1.5, 2.0, "собственная частота 1.5–2 Гц")
	assert_between(RiderMotion.TAIL_DAMPING, 0.3, 0.5, "затухание 0.3–0.5 от критического")
	assert_lte(RiderMotion.TAIL_SIDE_MAX_DEG, 8.0, "вбок до ±8°")
	assert_lte(RiderMotion.TAIL_VERT_MAX_DEG, 4.0, "вверх-вниз до ±4°")
	assert_lte(RiderMotion.TAIL_CONE_DEG, 20.0, "конус 20°")


## П.18: при 90, 100, 120 об/мин и k = 1.3 за 60 с хвост в пределах (вбок ±8°, вверх-вниз ±4°,
## конус 20°), амплитуда за последние 10 оборотов ≤ первых 10 после установления (от 3 с со
## старта каденса, ред. 4.4) (+2 %); через 3 с после остановки
## — ≤ 10 % амплитуды до остановки. Плюс синтетический наклон в повороте ±0.45 рад.
func test_p18_tail_bounded_stable_and_settles() -> void:
	var src: Dictionary = RiderContract.POSE_SOURCES[1]
	assert_eq(src["hair"], "tail")
	for rpm in [90, 100, 120]:
		var r := _rider(src)
		r.set_power(400, true, 200)
		r.set_effort_k(K_HIGH)
		r.set_cadence(rpm)
		var frames: int = 60 * 60
		var rev_frames: int = int(round(60.0 / float(rpm) * 60.0))
		var settle: int = int(round(TAIL_SETTLE_S / FRAME))
		var first: float = 0.0
		var last: float = 0.0
		var worst := Vector3.ZERO
		var moved: float = 0.0
		for i in frames:
			r.advance(FRAME)
			var d := _tail_dev(r)
			worst = Vector3(maxf(worst.x, absf(d.x)), maxf(worst.y, absf(d.y)), maxf(worst.z, d.z))
			if i >= settle and i < settle + rev_frames * 10:
				first = maxf(first, d.z)
			if i >= frames - rev_frames * 10:
				last = maxf(last, d.z)
				moved = maxf(moved, d.z)
		assert_lte(worst.x, 8.0 + 0.3, "%d об/мин: вбок %.2f°" % [rpm, worst.x])
		assert_lte(worst.y, 4.0 + 0.3, "%d об/мин: вверх-вниз %.2f°" % [rpm, worst.y])
		assert_lte(worst.z, 20.0, "%d об/мин: конус %.2f°" % [rpm, worst.z])
		assert_gt(moved, 0.2, "%d об/мин: хвост движется (%.2f°)" % [rpm, moved])
		assert_lte(last, first * 1.02 + 1e-4, "%d об/мин: амплитуда не растёт (%.3f° ≤ %.3f°)" % [rpm, last, first])
		r.set_cadence(0)
		for i in 180:
			r.advance(FRAME)
		var after: float = 0.0
		for i in 60:
			r.advance(FRAME)
			after = maxf(after, _tail_dev(r).z)
		assert_lte(after, last * 0.1, "%d об/мин: через 3 с после остановки %.3f° ≤ 10 %% от %.3f°" % [rpm, after, last])
	# Синтетический наклон в повороте и покачивание: пределы держатся.
	var r2 := _rider(src)
	r2.set_power(400, true, 200)
	r2.set_cadence(100)
	var worst2 := Vector3.ZERO
	for i in 1200:
		r2.set_lean(0.45 * sin(TAU * 0.7 * float(i) * FRAME))
		r2.advance(FRAME)
		var d := _tail_dev(r2)
		worst2 = Vector3(maxf(worst2.x, absf(d.x)), maxf(worst2.y, absf(d.y)), maxf(worst2.z, d.z))
	assert_gt(worst2.x, 0.5, "наклон раскачивает хвост вбок (%.2f°)" % worst2.x)
	assert_lte(worst2.x, 8.3, "наклон: вбок %.2f°" % worst2.x)
	assert_lte(worst2.y, 4.3, "наклон: вверх-вниз %.2f°" % worst2.y)
	assert_lte(worst2.z, 20.0, "наклон: конус %.2f°" % worst2.z)


## Окончание хвоста по контракту (оракул `BRIEF_HAIR_TAIL_END`, ±5 мм): `RiderRig`, rest скелета
## игры (ось Y `hair_tail.2` — на кончик) и сетка — строго по костям (без своего изгиба кончика).
func test_p18_tail_rest_geometry() -> void:
	var src: Dictionary = RiderContract.POSE_SOURCES[1]
	assert_eq(src["hair"], "tail")
	var r := _rider(src)
	var h1: Vector3 = RiderRig.head("hair_tail.1")
	var h2: Vector3 = RiderRig.head("hair_tail.2")
	var end: Vector3 = RiderRig.tail("hair_tail.2")
	var oracle: Vector3 = RiderRig.from_blender(RiderContract.BRIEF_HAIR_TAIL_END)
	assert_lte(end.distance_to(oracle), RiderContract.HAIR_TAIL_END_TOL_M,
		"окончание hair_tail.2 %s — по контракту %s ± 5 мм" % [end, oracle])
	var len2: float = h2.distance_to(end)
	assert_almost_eq(len2, TAIL2_LEN_M, 0.005, "вторая кость %.4f м" % len2)
	var down: float = rad_to_deg(atan2(h2.y - end.y, end.z - h2.z))
	assert_almost_eq(down, TAIL2_DOWN_DEG, 3.0, "кончик назад-вниз %.1f° к горизонту" % down)
	var total: float = h1.distance_to(h2) + len2
	assert_between(total, TAIL_LEN_MIN_M, TAIL_LEN_MAX_M, "весь хвост %.3f м" % total)
	var skel := r.skeleton()
	for b in ["hair_tail.1", "hair_tail.2"]:
		var rest: Transform3D = skel.get_bone_global_rest(skel.find_bone(b))
		var want: Vector3 = RiderRig.tail(b) - RiderRig.head(b)
		assert_lt(rad_to_deg(rest.basis.y.angle_to(want)), 0.1, "%s: ось Y rest — на окончание" % b)
	# Сетка по костям: вершины каждой кости хвоста — у отрезка «начало → окончание» (в пределах
	# радиуса хвоста), кончик сетки — у окончания `hair_tail.2`.
	var hair: Mesh = RiderModel.meshes(Rider.RIDER_MATERIAL)["hair_tail"]
	var segs := {RiderRig.index_of("hair_tail.1"): [h1, h2], RiderRig.index_of("hair_tail.2"): [h2, end]}
	var off := {}
	var reach: float = 0.0
	for p in _bone_points(hair, -1, 0.0):
		var bone: int = p[0]
		if not segs.has(bone):
			continue
		var a: Vector3 = segs[bone][0]
		var b: Vector3 = segs[bone][1]
		var v: Vector3 = p[1]
		off[bone] = maxf(off.get(bone, 0.0), v.distance_to(Geometry3D.get_closest_point_to_segment(v, a, b)))
		if bone == RiderRig.index_of("hair_tail.2"):
			reach = maxf(reach, (v - a).dot((b - a).normalized()))
	for bone in segs:
		assert_lte(off[bone], 0.02, "%s: сетка у кости (%.4f м)" % [RiderRig.BONES[bone][0], off[bone]])
	assert_almost_eq(reach, len2, 0.01, "кончик сетки у окончания hair_tail.2 (%.4f из %.4f м)" % [reach, len2])


## Зазор хвоста до джерси в rest для каждой фигуры (ред. 4.4, сетка к сетке): у кончика (вершины
## `hair_tail.2` ближе `TAIL_TIP_ZONE_M` к окончанию) сетка к сетке 1.3–2.4 см, контур к контуру
## (оболочки `outline_width` × вес, как в кадре) ≤ 0.3 см — касание контуров допустимо; сетка хвоста
## (`hair_tail.1/2`) за корнем — сетка к сетке ≥ 1.0 см, корень с резинкой (`TAIL_ROOT_ZONE_M`, под
## краем шлема у воротника) — в джерси не входит; хвост, повёрнутый вокруг корня `hair_tail.1` к
## спине на предел пружины (`TAIL_VERT_MAX_DEG`), в спину не входит. Джерси — треугольники тела
## не на костях `head`/`neck` (кожа головы и шеи — не джерси).
func test_p18_tail_tip_clearance_to_jersey() -> void:
	var meshes: Dictionary = RiderModel.meshes(Rider.RIDER_MATERIAL)
	var outline: float = ((Rider.RIDER_MATERIAL as ShaderMaterial).next_pass as ShaderMaterial).get_shader_parameter("outline_width")
	assert_gt(outline, 0.0, "контур гонщика")
	var t1: int = RiderRig.index_of("hair_tail.1")
	var t2: int = RiderRig.index_of("hair_tail.2")
	var end: Vector3 = RiderRig.tail("hair_tail.2")
	var root: Vector3 = RiderRig.head("hair_tail.1")
	var down := Transform3D(Basis.IDENTITY, root) * Transform3D(Basis(Vector3.RIGHT,
		deg_to_rad(RiderMotion.TAIL_VERT_MAX_DEG)), Vector3.ZERO) * Transform3D(Basis.IDENTITY, -root)
	var skin_bones: Array[int] = [RiderRig.index_of("head"), RiderRig.index_of("neck")]
	var root_zone := PackedVector3Array()
	var tail_rest := PackedVector3Array()
	var tail_down := PackedVector3Array()
	for p in _bone_points(meshes["hair_tail"], -1, 0.0):
		if p[0] != t1 and p[0] != t2:
			continue
		var v: Vector3 = p[1]
		if v.distance_to(root) <= TAIL_ROOT_ZONE_M:
			root_zone.append(v)
		else:
			tail_rest.append(v)
		tail_down.append(down * v)
	for fig in Rider.FIGURES:
		var body: Mesh = meshes["body_" + fig]
		var gaps := PackedFloat32Array()
		for w in [0.0, outline]:
			var tip := PackedVector3Array()
			for p in _bone_points(meshes["hair_tail"], t2, w):
				if (p[1] as Vector3).distance_to(end) <= TAIL_TIP_ZONE_M + w:
					tip.append(p[1])
			gaps.append(_mesh_gap(tip, _tris_near(body, end, 0.15, w, skin_bones)))
		assert_between(gaps[0], TAIL_TIP_GAP_MIN_M, TAIL_TIP_GAP_MAX_M,
			"%s: зазор кончика до джерси сетка к сетке %.4f м" % [fig, gaps[0]])
		assert_lte(gaps[1], TAIL_TIP_OUTLINE_GAP_MAX_M,
			"%s: контур к контуру у кончика %.4f м — без просвета фона" % [fig, gaps[1]])
		var jersey: PackedVector3Array = _tris_near(body, RiderRig.head("hair_tail.2"), 0.3, 0.0, skin_bones)
		var along: float = _mesh_gap(tail_rest, jersey)
		assert_gte(along, TAIL_GAP_MIN_M, "%s: хвост за корнем до джерси сетка к сетке %.4f м" % [fig, along])
		var at_root: float = _mesh_gap(root_zone, jersey)
		assert_gt(at_root, 0.0, "%s: корень хвоста с резинкой не входит в джерси (%.4f м)" % [fig, at_root])
		var low: float = _mesh_gap(tail_down, jersey)
		assert_gt(low, 0.0, "%s: хвост вниз на %.0f° не входит в спину (%.4f м)" % [fig, RiderMotion.TAIL_VERT_MAX_DEG, low])
		gut.p("%s: зазор кончика — сетка %.4f м, контур к контуру %.4f м; хвост за корнем %.4f м, корень %.4f м; вниз на предел %.4f м" % [
			fig, gaps[0], gaps[1], along, at_root, low])


## Вершины сетки rest `[кость, точка]` (кость −1 — все), сдвинутые по нормали на `outline` × вес
## контура (альфа цвета вершины, как в шейдере контура).
func _bone_points(mesh: Mesh, bone: int, outline: float) -> Array:
	var arr: Array = mesh.surface_get_arrays(0)
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var n: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var c: PackedColorArray = arr[Mesh.ARRAY_COLOR]
	var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES]
	var out: Array = []
	for i in v.size():
		if bone < 0 or bones[i * 4] == bone:
			out.append([bones[i * 4], v[i] + n[i] * outline * c[i].a])
	return out


## Треугольники сетки rest (тройки точек) с вершиной ближе `radius` к `near`, вершины сдвинуты
## по нормали на `outline` × вес контура; треугольники на костях `skip_bones` пропускаются.
func _tris_near(mesh: Mesh, near: Vector3, radius: float, outline: float, skip_bones: Array[int] = []) -> PackedVector3Array:
	var arr: Array = mesh.surface_get_arrays(0)
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var n: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var c: PackedColorArray = arr[Mesh.ARRAY_COLOR]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES]
	var out := PackedVector3Array()
	for t in range(0, idx.size(), 3):
		if skip_bones.has(bones[idx[t] * 4]):
			continue
		var close: bool = false
		for j in 3:
			close = close or v[idx[t + j]].distance_to(near) < radius
		if close:
			for j in 3:
				var k: int = idx[t + j]
				out.append(v[k] + n[k] * outline * c[k].a)
	return out


## Наименьшее расстояние от точек до треугольников (тройки точек), м.
func _mesh_gap(pts: PackedVector3Array, tris: PackedVector3Array) -> float:
	var best: float = INF
	for t in range(0, tris.size(), 3):
		for p in pts:
			best = minf(best, p.distance_to(_closest_on_triangle(p, tris[t], tris[t + 1], tris[t + 2])))
	return best


func _closest_on_triangle(p: Vector3, a: Vector3, b: Vector3, c: Vector3) -> Vector3:
	var n: Vector3 = (b - a).cross(c - a)
	if n.length_squared() > 1e-14:
		n = n.normalized()
		var q: Vector3 = p - n * n.dot(p - a)
		var bc: Vector3 = Geometry3D.get_triangle_barycentric_coords(q, a, b, c)
		if bc.x >= 0.0 and bc.y >= 0.0 and bc.z >= 0.0:
			return q
	var best: Vector3 = Geometry3D.get_closest_point_to_segment(p, a, b)
	for e in [[b, c], [c, a]]:
		var q: Vector3 = Geometry3D.get_closest_point_to_segment(p, e[0], e[1])
		if p.distance_to(q) < p.distance_to(best):
			best = q
	return best
