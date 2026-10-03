class_name RoadBuilder
extends RefCounted
## Строит меш дороги вдоль `Track` (REQ-D3D-03 крит. 2, REQ-D3D-05, REQ-D3D-08 п.4): лента
## шириной `width_m` с шагом ~`TARGET_SEGMENT_LENGTH_M` на любой длине трассы, кусками
## (`rings`): кусок — `MeshInstance3D` с одной поверхностью `ArrayMesh` и не больше
## `MAX_SEGMENTS` сегментов; кусков не больше `MAX_CHUNKS` (на трассе длиннее 20 км шаг
## растёт). Число сегментов фиксировано при построении и не растёт со временем. Кусок 0 —
## сам узел «Road», остальные — его дети `Road_<k>` с дальностью видимости. Обочина
## (`RoadsideBuilder`) строится на тех же кольцах — край асфальта и кромка совпадают.
## UV: u поперёк дороги 0..1 (разметка — текстурой), v — дистанция / ширина (повтор вдоль).

const DEFAULT_WIDTH_M: float = 6.0
## Сегментов в одном куске (меше).
const MAX_SEGMENTS: int = 800
## Кусков на трассу (бюджет `MeshInstance3D`).
const MAX_CHUNKS: int = 5
const TARGET_SEGMENT_LENGTH_M: float = 5.0
## Дальность видимости куска сверх его полудиагонали, м (как у рельефа).
const RANGE_M: float = 3000.0


## Всего сегментов на трассе: длина / 5 м, не меньше 8 и не больше `MAX_SEGMENTS` · `MAX_CHUNKS`.
static func total_segments(track: Track) -> int:
	var by_length: int = int(ceil(track.length_m() / TARGET_SEGMENT_LENGTH_M))
	return clampi(by_length, 8, MAX_SEGMENTS * MAX_CHUNKS)


## Число кусков дороги (и обочины) на трассе.
static func chunk_count(track: Track) -> int:
	return int(ceil(float(total_segments(track)) / float(MAX_SEGMENTS)))


## Сегментов в куске 0 (узел «Road», мета `segments`): все, если трасса в один кусок, иначе
## `MAX_SEGMENTS`. `max_segments` — потолок для короткой трассы (совместимость).
static func segment_count(track: Track, max_segments: int = MAX_SEGMENTS) -> int:
	return mini(total_segments(track), clampi(max_segments, 8, MAX_SEGMENTS))


## Дистанции колец: `total_segments + 1` штук с равным шагом; для петли последнее
## кольцо — на s = длина (выборка трассы даёт ту же точку, что s = 0).
static func ring_distances(track: Track) -> PackedFloat64Array:
	var n: int = total_segments(track)
	var length: float = track.length_m()
	var out := PackedFloat64Array()
	out.resize(n + 1)
	for i in n + 1:
		out[i] = length * float(i) / float(n)
	return out


## Кольца куска `k`: [первое; последнее] включительно (соседние куски делят кольцо); полные
## куски — по `MAX_SEGMENTS` сегментов, последний — остаток.
static func chunk_rings(track: Track, k: int) -> Vector2i:
	var n: int = total_segments(track)
	var chunks: int = chunk_count(track)
	var per: int = n if chunks == 1 else MAX_SEGMENTS
	return Vector2i(mini(k * per, n), mini((k + 1) * per, n))


## Построить узел дороги. `segments` > 0 — явное число сегментов в один кусок (≤ `MAX_SEGMENTS`).
static func build(track: Track, material: Material = null, width_m: float = DEFAULT_WIDTH_M,
		segments: int = -1, center_offset_m: float = 0.0) -> MeshInstance3D:
	var dist: PackedFloat64Array
	var chunks: int = 1
	if segments > 0:
		var n: int = clampi(segments, 1, MAX_SEGMENTS)
		dist = PackedFloat64Array()
		dist.resize(n + 1)
		for i in n + 1:
			dist[i] = track.length_m() * float(i) / float(n)
	else:
		dist = ring_distances(track)
		chunks = chunk_count(track)
	var root: MeshInstance3D = null
	for k in chunks:
		var span: Vector2i = Vector2i(0, dist.size() - 1) if chunks == 1 else chunk_rings(track, k)
		var node := _chunk(track, dist, span, material, width_m, center_offset_m)
		if chunks > 1:
			node.visibility_range_end = RANGE_M + node.get_aabb().size.length() * 0.5
		if root == null:
			node.name = "Road"
			node.set_meta("segments", span.y - span.x)
			node.set_meta("chunks", chunks)
			root = node
		else:
			node.name = "Road_%02d" % k
			root.add_child(node)
	return root


static func _chunk(track: Track, dist: PackedFloat64Array, span: Vector2i, material: Material, width_m: float,
		center_offset_m: float) -> MeshInstance3D:
	var half: float = width_m * 0.5
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var sample := TrackSample.new()
	var last: int = dist.size() - 1
	for i in range(span.x, span.y + 1):
		var s: float = dist[i]
		track.sample_into(0.0 if (track.is_loop() and i == last) else s, sample)
		var right: Vector3 = sample.right()
		var center: Vector3 = sample.position + right * center_offset_m
		vertices.append(center - right * half)
		vertices.append(center + right * half)
		normals.append(sample.up)
		normals.append(sample.up)
		var v: float = s / width_m
		uvs.append(Vector2(0.0, v))
		uvs.append(Vector2(1.0, v))
	for i in span.y - span.x:
		var a: int = i * 2
		indices.append_array(PackedInt32Array([a, a + 2, a + 1, a + 1, a + 2, a + 3]))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	if material != null:
		mesh.surface_set_material(0, material)
	var node := MeshInstance3D.new()
	node.mesh = mesh
	return node
