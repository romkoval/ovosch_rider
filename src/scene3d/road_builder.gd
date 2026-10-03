class_name RoadBuilder
extends RefCounted
## Строит меш дороги вдоль `Track` (REQ-D3D-03 крит. 2, REQ-D3D-05): один `MeshInstance3D`
## с одной поверхностью `ArrayMesh` — лента шириной `width_m` из ≤ `MAX_SEGMENTS`
## сегментов (число фиксировано при построении и не растёт со временем). UV: u поперёк
## дороги 0..1 (разметка — текстурой), v — дистанция / ширина (повтор вдоль).

const DEFAULT_WIDTH_M: float = 6.0
const MAX_SEGMENTS: int = 400
const TARGET_SEGMENT_LENGTH_M: float = 5.0


## Число сегментов для трассы: длина / 5 м, но не больше `MAX_SEGMENTS` и не меньше 8.
static func segment_count(track: Track, max_segments: int = MAX_SEGMENTS) -> int:
	var by_length: int = int(ceil(track.length_m() / TARGET_SEGMENT_LENGTH_M))
	return clampi(by_length, 8, max_segments)


## Построить узел дороги. `segments` ≤ `MAX_SEGMENTS`; для петли последний сегмент замыкается на первый.
static func build(track: Track, material: Material = null, width_m: float = DEFAULT_WIDTH_M,
		segments: int = -1, center_offset_m: float = 0.0) -> MeshInstance3D:
	var n: int = segment_count(track) if segments <= 0 else clampi(segments, 1, MAX_SEGMENTS)
	var length: float = track.length_m()
	var step: float = length / float(n)
	var half: float = width_m * 0.5
	var ring_count: int = n + 1
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var sample := TrackSample.new()
	for i in ring_count:
		var s: float = minf(float(i) * step, length)
		track.sample_into(s if not (track.is_loop() and i == n) else 0.0, sample)
		var right: Vector3 = sample.right()
		var center: Vector3 = sample.position + right * center_offset_m
		vertices.append(center - right * half)
		vertices.append(center + right * half)
		normals.append(sample.up)
		normals.append(sample.up)
		var v: float = s / width_m
		uvs.append(Vector2(0.0, v))
		uvs.append(Vector2(1.0, v))
	for i in n:
		var a: int = i * 2
		var b: int = a + 1
		var c: int = a + 2
		var d: int = a + 3
		indices.append_array(PackedInt32Array([a, c, b, b, c, d]))
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
	node.name = "Road"
	node.mesh = mesh
	node.set_meta("segments", n)
	return node
