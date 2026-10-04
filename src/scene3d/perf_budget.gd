class_name PerfBudget
extends RefCounted
## Бюджет производительности 3D-сцены (REQ-D3D-05 крит. 2–4, решение В-7; REQ-D3D-08 п.6).
## Числа продублированы в `docs/perf_budget.md`; тест сверяет документ с константами.
##
## Экземпляры MultiMesh считаются «видимыми с любой точки трассы» (T-066): на длинной
## трассе объекты окружения разбиты на куски вдоль трассы (`chunk_length_m`), у каждого
## куска — `visibility_range_end`; движок прячет кусок, если расстояние от камеры до
## центра его AABB больше `visibility_range_end` (+ `visibility_range_end_margin`).
## Компактный мир (габарит трассы ≤ `COMPACT_EXTENT_M`) целиком в зоне видимости —
## там кусков нет, «видимо» = «всего».

const MAX_MESH_INSTANCES: int = 60
const MAX_MATERIALS: int = 12
const MAX_LIGHTS: int = 3
## Ручной замер на устройстве (`RenderingServer.get_rendering_info`).
const MAX_DRAW_CALLS: int = 150
## Экземпляров MultiMesh, видимых из любой точки трассы (с учётом `visibility_range`).
const MAX_VISIBLE_MULTIMESH_INSTANCES: int = 2000
## Экземпляров MultiMesh всего на трассе (память и время построения; на длинном маршруте
## плотность объектов урезается под этот потолок).
const MAX_MULTIMESH_INSTANCES: int = 40000
const MIN_PHYSICS_TICKS_PER_SECOND: int = 60
## Узлов геометрии с параметрами экземпляра тун-света (`RenderLook`, T-112) на сцену. Буфер
## параметров экземпляра Forward+/Mobile (`rendering/limits/global_shader_variables/buffer_size`
## = 65536 слотов, 16 на узел) — 4096 узлов на процесс: два экрана заезда по 1024 и пересборка
## одного из них (старые узлы живут до конца кадра) — 3072, запас 1024.
const MAX_LOOK_INSTANCES: int = 1024

## Длина куска MultiMesh вдоль трассы, м, и потолок числа кусков на тип объекта (на очень
## длинном маршруте кусок удлиняется).
const CHUNK_LENGTH_M: float = 500.0
const MAX_CHUNKS_PER_TYPE: int = 60
## Трасса, у которой большая сторона габарита не длиннее этого, — компактная: весь мир
## ближе дальности видимости деревьев, куски не нужны.
const COMPACT_EXTENT_M: float = 1000.0
## Дальность видимости куска (до центра его AABB), м: деревья, кусты, трава, столбики.
const RANGE_TREES_M: float = 1500.0
const RANGE_BUSHES_M: float = 1000.0
const RANGE_TUFTS_M: float = 450.0
const RANGE_POSTS_M: float = 700.0
## Гистерезис скрытия куска (`visibility_range_end_margin`), м.
const RANGE_MARGIN_M: float = 50.0
## Шаг точек трассы, по которым строители проверяют видимый бюджет, м — тот же, что в
## критерии D3D-08 п.6 (на серпантине «Перевала» между точками через 250 м видно больше).
const CHECK_STEP_M: float = 50.0
## Камера стоит позади велосипедиста: запас к дальности при подсчёте по точкам трассы, м.
const EYE_SLACK_M: float = 10.0


## Подсчёт узлов сцены: `{mesh_instances, materials, lights, multimesh_instances}`
## (экземпляры MultiMesh — всего в сцене).
static func count(root: Node) -> Dictionary:
	var materials: Dictionary = {}
	var result := {"mesh_instances": 0, "lights": 0, "multimesh_instances": 0}
	_walk(root, result, materials)
	result["materials"] = materials.size()
	return result


static func _walk(node: Node, result: Dictionary, materials: Dictionary) -> void:
	if node is MeshInstance3D:
		result["mesh_instances"] += 1
		var mi := node as MeshInstance3D
		if mi.mesh != null:
			for i in mi.mesh.get_surface_count():
				var mat: Material = mi.get_active_material(i)
				if mat != null:
					materials[mat.get_instance_id()] = true
	elif node is MultiMeshInstance3D:
		var mm := (node as MultiMeshInstance3D).multimesh
		if mm != null:
			result["multimesh_instances"] += mm.instance_count
			if mm.mesh != null:
				for i in mm.mesh.get_surface_count():
					var mat: Material = mm.mesh.surface_get_material(i)
					if mat != null:
						materials[mat.get_instance_id()] = true
	elif node is Light3D:
		result["lights"] += 1
	for child in node.get_children():
		_walk(child, result, materials)


# ---------------------------------------------------------------------------
# Куски и видимость (REQ-D3D-08 п.6)
# ---------------------------------------------------------------------------

## Компактна ли трасса (большая сторона горизонтального габарита ≤ `COMPACT_EXTENT_M`).
static func is_compact(track: Track) -> bool:
	var length: float = track.length_m()
	var n: int = clampi(int(ceil(length / 25.0)), 2, 4000)
	var sample := TrackSample.new()
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for i in n + 1:
		track.sample_into(length * float(i) / float(n), sample)
		lo = Vector2(minf(lo.x, sample.position.x), minf(lo.y, sample.position.z))
		hi = Vector2(maxf(hi.x, sample.position.x), maxf(hi.y, sample.position.z))
	return maxf(hi.x - lo.x, hi.y - lo.y) <= COMPACT_EXTENT_M


## Длина куска вдоль трассы, м (0 — без кусков: компактный мир).
static func chunk_length_m(track: Track) -> float:
	if is_compact(track):
		return 0.0
	return maxf(CHUNK_LENGTH_M, track.length_m() / float(MAX_CHUNKS_PER_TYPE))


## Число кусков на тип объекта для трассы (1 — компактный мир).
static func chunk_count(track: Track, chunk_m: float) -> int:
	if chunk_m <= 0.0:
		return 1
	return maxi(int(ceil(track.length_m() / chunk_m)), 1)


## Индекс куска для дистанции `s`.
static func chunk_of(s: float, chunk_m: float, chunks: int) -> int:
	if chunk_m <= 0.0:
		return 0
	return clampi(int(s / chunk_m), 0, chunks - 1)


## Экземпляры MultiMesh под `root`, видимые из точки `eye`: кусок без `visibility_range_end`
## виден всегда, иначе — если расстояние до центра его AABB ≤ end + margin + `slack_m`.
static func visible_multimesh_instances(root: Node, eye: Vector3, slack_m: float = 0.0) -> int:
	var total: int = 0
	if root is MultiMeshInstance3D:
		var mmi := root as MultiMeshInstance3D
		if mmi.multimesh != null and mmi.multimesh.instance_count > 0:
			if mmi.visibility_range_end <= 0.0:
				total += mmi.multimesh.instance_count
			else:
				var xf: Transform3D = mmi.global_transform if mmi.is_inside_tree() else mmi.transform
				var center: Vector3 = xf * multimesh_aabb(mmi.multimesh).get_center()
				if eye.distance_to(center) <= mmi.visibility_range_end + mmi.visibility_range_end_margin + slack_m:
					total += mmi.multimesh.instance_count
	for child in root.get_children():
		total += visible_multimesh_instances(child, eye, slack_m)
	return total


## Максимум видимых экземпляров по точкам трассы с шагом `step_m` (камера — у велосипедиста,
## с запасом `EYE_SLACK_M`). `nodes` — корни поддеревьев (могут быть вне дерева сцены).
static func max_visible_along(nodes: Array, track: Track, step_m: float = CHECK_STEP_M) -> int:
	var length: float = track.length_m()
	var n: int = maxi(int(ceil(length / step_m)), 1)
	var sample := TrackSample.new()
	var best: int = 0
	for i in n:
		track.sample_into(minf(float(i) * step_m, length), sample)
		var seen: int = 0
		for node in nodes:
			if node != null:
				seen += visible_multimesh_instances(node as Node, sample.position, EYE_SLACK_M)
		best = maxi(best, seen)
	return best


## AABB мультимеша: заданный при построении `custom_aabb` (позиции экземпляров на
## headless-сервере недоступны), иначе — расчётный.
static func multimesh_aabb(mm: MultiMesh) -> AABB:
	if mm.custom_aabb.size != Vector3.ZERO:
		return mm.custom_aabb
	return mm.get_aabb()

