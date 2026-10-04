extends RefCounted
## Оракул контракта модели гонщика для тестов T-106a1..T-106c: числа ТЗ
## `docs/game/rider-artist-brief.md` (разделы 5.1, 6, 14) как есть, в координатах Blender, —
## независимо от таблиц кода (`RiderRig`), и источники модели для параметризованных тестов.
##
## Источник модели — параметр (карточка «Общее для T-106a1..T-106c»): тот же набор проверок
## прогоняется на скелете из кода, на эталонной арматуре пакета и, с T-106b, на `rider.glb` —
## строкой в `RIG_SOURCES`, без переписывания тестов.

## Кость → [родитель, начало (Blender: x, y, z)]; для `.L` — как в брифе, `.R` — зеркально
## (`brief_bones()`); `hair_tail.2` — без позиции (бриф задаёт длину 0.09–0.10 м), его окончание
## (кончик хвоста) — `BRIEF_HAIR_TAIL_END`.
const BRIEF_BONES: Dictionary = {
	"pelvis": ["", Vector3(0.0, 0.230, 0.965)],
	"spine": ["pelvis", Vector3(0.0, 0.105, 1.147)],
	"chest": ["spine", Vector3(0.0, -0.018, 1.234)],
	"neck": ["chest", Vector3(0.0, -0.190, 1.380)],
	"head": ["neck", Vector3(0.0, -0.310, 1.420)],
	"upperarm.L": ["chest", Vector3(0.180, -0.220, 1.340)],
	"forearm.L": ["upperarm.L", Vector3(0.240, -0.345, 1.060)],
	"hand.L": ["forearm.L", Vector3(0.215, -0.560, 0.925)],
	"grip.L": ["hand.L", Vector3(0.210, -0.620, 0.885)],
	"thigh.L": ["pelvis", Vector3(0.090, 0.190, 1.050)],
	"shin.L": ["thigh.L", Vector3(0.100, -0.170, 0.797)],
	"foot.L": ["shin.L", Vector3(0.110, -0.063, 0.371)],
	"cleat.L": ["foot.L", Vector3(0.115, -0.170, 0.270)],
	"heel.L": ["foot.L", Vector3(0.115, 0.018, 0.296)],
	"hair_tail.1": ["head", Vector3(0.0, -0.250, 1.390)],
	"hair_tail.2": ["hair_tail.1", null],
}
## Окончание `hair_tail.2` — кончик хвоста в rest (Blender; вердикт game-designer по T-106a2, Г15):
## хвост от вершины дуги над воротником ложится назад-вниз ≈ 22° к горизонту, вторая кость
## ≈ 0.092 м, весь хвост ≈ 0.186 м (спека «Причёски»: 0.16–0.20 м). Допуск `HAIR_TAIL_END_TOL_M`.
const BRIEF_HAIR_TAIL_END := Vector3(0.0, -0.080, 1.395)
const HAIR_TAIL_END_TOL_M: float = 0.005
## Сокеты (бриф 5.1): без весов, по ним IK ставит кисти и стопы.
const BRIEF_SOCKETS: Array[String] = ["grip.L", "grip.R", "cleat.L", "cleat.R", "heel.L", "heel.R"]
## Велосипед (бриф раздел 6, Blender, м).
const BRIEF_BB := Vector3(0.0, 0.0, 0.27)
const BRIEF_REAR_AXLE := Vector3(0.0, 0.405, 0.335)
const BRIEF_FRONT_AXLE := Vector3(0.0, -0.585, 0.335)
const BRIEF_SADDLE_TOP_M: float = 0.965
const BRIEF_SADDLE_S_Y: float = 0.230
const BRIEF_GRIP_L := Vector3(0.21, -0.62, 0.885)
const BRIEF_CLEAT_R := Vector3(-0.115, -0.170, 0.270)
const BRIEF_CRANK_M: float = 0.17
const BRIEF_PEDAL_X_M: float = 0.115
## Ракурсы брифа раздел 14 (Blender): камера, цель, FOV, углы шатуна.
const BRIEF_VIEWS: Dictionary = {
	"work": [Vector3(0.49, 3.77, 2.10), Vector3(0.0, -6.0, 0.60), 55.0, [0, 90, 180, 270]],
	"side_r": [Vector3(-2.8, -0.1, 0.95), Vector3(0.0, -0.1, 0.85), 40.0, [0, 90, 180, 270]],
	"hips_r": [Vector3(-1.3, 0.15, 0.97), Vector3(0.0, 0.05, 0.87), 35.0, [0, 90, 180, 270]],
	"rear34_l": [Vector3(1.5, 2.0, 1.55), Vector3(0.0, 0.05, 0.95), 40.0, [90]],
	"front34_r": [Vector3(-1.6, -2.2, 1.35), Vector3(0.0, -0.25, 1.05), 40.0, [90]],
	"head_34": [Vector3(-0.7, -1.1, 1.55), Vector3(0.0, -0.38, 1.42), 30.0, [90]],
}

const REFERENCE_DIR: String = "res://assets/rider/reference"
const BIKE_REFERENCE: String = "res://assets/rider/reference/bike_reference.glb"

## Источники скелета модели: `name` — для сообщений; `path` — "" (скелет из кода,
## `RiderRig.build_skeleton`), `.glb` (импорт `GLTFDocument`, оси glTF как у экспорта Blender
## «+Y Up» — перевод `RiderRig.from_gltf`) или сцена Godot (уже в осях игры); `tol_m` — допуск
## начал костей; `roll_deg` — допуск осей кости (бриф 5.3); `marker_meshes` — сетки-метки, на
## которые правило «на сокетах весов нет» не распространяется.
const RIG_SOURCES: Array = [
	{"name": "code", "path": "", "tol_m": 1e-5, "roll_deg": 0.01, "marker_meshes": []},
	{"name": "rider_rig_reference.glb", "path": "res://assets/rider/reference/rider_rig_reference.glb",
		"tol_m": 0.001, "roll_deg": 0.05, "marker_meshes": ["rig_joints"]},
	# T-106a2: манекен в игре — `Skeleton3D` узла `Rider` (вторая арматура сцены — шатуны, `skeleton`
	# выбирает нужную по имени).
	{"name": "rider.tscn (манекен)", "path": "res://src/scene3d/rider.tscn", "skeleton": "Skeleton",
		"tol_m": 1e-5, "roll_deg": 0.01, "marker_meshes": []},
	# T-106b/T-106c: {"name": "rider.glb", "path": "res://assets/rider/rider.glb",
	#	"tol_m": RiderRig.ARTIST_TOLERANCE_M, "roll_deg": 5.0, "marker_meshes": []},
]


static func mirror(bone: String) -> String:
	return bone.replace(".L", ".R")


## Все кости брифа: кость → [родитель, начало Blender или null].
static func brief_bones() -> Dictionary:
	var out: Dictionary = {}
	for name in BRIEF_BONES:
		out[name] = BRIEF_BONES[name]
		if (name as String).ends_with(".L"):
			var p: Vector3 = BRIEF_BONES[name][1]
			out[mirror(name)] = [mirror(BRIEF_BONES[name][0]), Vector3(-p.x, p.y, p.z)]
	return out


## Импорт glTF/GLB так же, как его читает редактор (`GLTFDocument`); сцена — ребёнком `holder`
## (освобождается вместе с ним). Ошибка — null.
static func import_glb(path: String, holder: Node) -> Node:
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(ProjectSettings.globalize_path(path), state) != OK:
		return null
	var scene: Node = doc.generate_scene(state)
	if scene != null:
		holder.add_child(scene)
	return scene


## Загрузить источник скелета. Итог: `root` — корень модели (в дереве под `holder`),
## `skeleton`, `to_godot` — перевод из системы сцены источника в систему гонщика (Godot);
## `error` — непустой при ошибке.
static func load_rig(src: Dictionary, holder: Node) -> Dictionary:
	var path: String = src["path"]
	var out := {"root": null, "skeleton": null, "to_godot": Transform3D.IDENTITY, "error": ""}
	var root: Node = null
	if path.is_empty():
		var skel := Skeleton3D.new()
		skel.name = "rider_rig"
		RiderRig.build_skeleton(skel)
		holder.add_child(skel)
		root = skel
	elif path.get_extension() == "glb" or path.get_extension() == "gltf":
		root = import_glb(path, holder)
		out["to_godot"] = RiderRig.gltf_flip()
	else:
		var packed: PackedScene = load(path)
		if packed != null:
			root = packed.instantiate()
			holder.add_child(root)
	if root == null:
		out["error"] = "%s: не загружается" % src["name"]
		return out
	out["root"] = root
	var skels: Array[Node] = root.find_children(str(src.get("skeleton", "*")), "Skeleton3D", true, false)
	if root is Skeleton3D:
		skels.push_front(root)
	if skels.size() != 1:
		out["error"] = "%s: арматур %d, нужна одна" % [src["name"], skels.size()]
		return out
	out["skeleton"] = skels[0]
	return out


## Глобальный rest кости в системе гонщика (Godot).
static func bone_rest_godot(rig: Dictionary, bone: int) -> Transform3D:
	var skel: Skeleton3D = rig["skeleton"]
	return (rig["to_godot"] as Transform3D) * skel.global_transform * skel.get_bone_global_rest(bone)


## Наивысшая точка меша на вертикали (x, z) после `xf` — по треугольникам
## `ARRAY_VERTEX`/`ARRAY_INDEX` (обе стороны грани).
static func top_at(mesh: Mesh, x: float, z: float, xf: Transform3D = Transform3D.IDENTITY) -> float:
	var best: float = -INF
	for s in mesh.get_surface_count():
		var arr: Array = mesh.surface_get_arrays(s)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		for t in range(0, idx.size(), 3):
			var hit: Variant = Geometry3D.ray_intersects_triangle(Vector3(x, 5.0, z), Vector3.DOWN,
				xf * v[idx[t]], xf * v[idx[t + 1]], xf * v[idx[t + 2]])
			if hit == null:
				hit = Geometry3D.ray_intersects_triangle(Vector3(x, 5.0, z), Vector3.DOWN,
					xf * v[idx[t]], xf * v[idx[t + 2]], xf * v[idx[t + 1]])
			if hit != null:
				best = maxf(best, (hit as Vector3).y)
	return best


## Источники модели для поз гонщика в игре (REQ-D3D-09 п.1–5, 14–18; T-106a2): сцена `Rider` и
## вариант внешности — фигура (`body.figure`) и причёска (`hair.style`). Каждая фигура
## проверяется отдельно (критерии «для каждой фигуры»). С T-106a4 — строки с `rider.glb`.
const POSE_SOURCES: Array = [
	{"name": "манекен m/short", "scene": "res://src/scene3d/rider.tscn", "figure": "m", "hair": "short"},
	{"name": "манекен f/tail", "scene": "res://src/scene3d/rider.tscn", "figure": "f", "hair": "tail"},
]


## Гонщик источника `src` под `holder` (в дереве), без своего `_process` (кадры — `advance`).
static func load_rider(src: Dictionary, holder: Node) -> Rider:
	var r: Rider = (load(src["scene"]) as PackedScene).instantiate()
	holder.add_child(r)
	r.set_process(false)
	r.set_figure(src["figure"])
	r.set_hair_style(src["hair"])
	return r
