class_name MeshKit
extends RefCounted
## Сборщик процедурных мешей с цветами вершин (REQ-D3D-07): трубки, эллипсоиды, конусы,
## коробки, кольца. Всё, что строится этим классом, красится одним тун-материалом по цвету
## вершины — поэтому велосипедист и объекты мира укладываются в бюджет материалов
## (`PerfBudget.MAX_MATERIALS`). Альфа цвета вершины — вес контура (0 — без контура),
## её читает шейдер обводки `outline.gdshader`.
##
## Цвета передаются в sRGB (как в палитре арт-библии) и переводятся в линейное
## пространство при добавлении: шейдер получает COLOR без преобразования.
## Используется только при построении сцены, не в кадре.
##
## Color regions (T-106a3, REQ-D3D-09 p.6; art bible "Rider" -> "Appearance slots", "Color
## regions in glTF"): the rider and bike set `region` (and `accent_region` for the accent part
## of a primitive: tube side panels, ellipsoid band) before adding primitives. Every vertex then
## also gets a region code in UV0 (U = column of the 32-column atlas, V = tone, Blender
## convention flipped like glTF). `to_mesh` writes UV0 instead of COLOR for such a kit,
## resolves regions per face (each face entirely inside one column: a face touching an accent
## vertex — side panel, band, lens highlight — takes the accent region, so borders run along
## quad edges; vertices on region borders are duplicated) and stores smoothed
## outline normals (average over all vertices at the same position) in TANGENT: the rider
## outline pass moves vertices along them, so hard edges and region seams do not tear it.
## Vertex colors of such a kit stay filled (the artist pack `bike_reference.glb` reads them),
## the game does not use them.

var vertices := PackedVector3Array()
var normals := PackedVector3Array()
var colors := PackedColorArray()
var indices := PackedInt32Array()
## UV0 region codes, one per vertex while `region` >= 0 (empty for world kits).
var uvs := PackedVector2Array()
## 1 — the vertex is in the accent part of its primitive (accent region or highlight tone).
var accents := PackedByteArray()
## Smoothed outline normals (filled by `finalize_regions`).
var outline_normals := PackedVector3Array()
## Region of new vertices (0-31); -1 — no region coding (world kits).
var region: int = -1
## Region of the accent part of a primitive (tube side panels, ellipsoid band); -1 — `region`.
var accent_region: int = -1
## Tone V of new vertices (Blender convention: tone = 0.6 + 0.8 * V, 0.5 -> 1.0).
var tone_v: float = 0.5
## Ellipsoid vertices with local unit Y at or above this get `highlight_v` instead of `tone_v`
## (lens highlight strip, region 19); > 1 — off.
var highlight_from_y: float = 2.0
var highlight_v: float = 0.9

const REGION_COLUMNS: int = 32


func vertex_count() -> int:
	return vertices.size()


## Цвет вершины: sRGB → линейный, альфа (вес контура) — без преобразования.
static func lin(c: Color) -> Color:
	var l := c.srgb_to_linear()
	l.a = c.a
	return l


## UV0 of region `code` with tone `v` (Blender V, 0 — atlas bottom): column centre, V flipped
## as glTF does.
static func region_uv(code: int, v: float = 0.5) -> Vector2:
	return Vector2((float(code) + 0.5) / float(REGION_COLUMNS), 1.0 - v)


## Region code of a UV0 (`floor(U * 32)`).
static func uv_region(uv: Vector2) -> int:
	return clampi(int(floor(uv.x * float(REGION_COLUMNS))), 0, REGION_COLUMNS - 1)


func uses_regions() -> bool:
	return not uvs.is_empty()


## Raw vertex (for lofts built outside the primitives below); `accent` — the accent region.
func add_vertex(p: Vector3, n: Vector3, c: Color, accent: bool = false, v: float = -1.0) -> int:
	return _add_vertex(p, n, c, accent, v)


func _add_vertex(p: Vector3, n: Vector3, c: Color, accent: bool = false, v: float = -1.0) -> int:
	vertices.append(p)
	normals.append(n)
	colors.append(c)
	if region >= 0:
		var code: int = accent_region if accent and accent_region >= 0 else region
		uvs.append(region_uv(code, tone_v if v < 0.0 else v))
		accents.append(1 if (accent and accent_region >= 0) or v >= 0.0 else 0)
	return vertices.size() - 1


## Трубка от `a` до `b` с эллиптическим сечением: `ra`/`rb` — радиусы (x — вдоль `side`,
## y — поперёк). `side` — опорная ось «вбок» (по умолчанию X). `side_color` красит
## боковые грани (|cos| > `side_threshold`) — лампасы на форме. Торцы — плоские крышки.
func add_tube(a: Vector3, b: Vector3, ra: Vector2, rb: Vector2, color: Color, sides: int = 10,
		caps: bool = true, side: Vector3 = Vector3.RIGHT, side_color: Color = Color(0, 0, 0, -1.0),
		side_threshold: float = 0.8) -> void:
	var axis: Vector3 = b - a
	var length: float = axis.length()
	if length < 1e-6:
		return
	var dir: Vector3 = axis / length
	var u: Vector3 = side - dir * side.dot(dir)
	if u.length_squared() < 1e-8:
		u = Vector3.UP - dir * dir.y
	u = u.normalized()
	var v: Vector3 = dir.cross(u).normalized()
	var base_col := lin(color)
	var accent := lin(side_color) if side_color.a >= 0.0 else base_col
	var start: int = vertices.size()
	for i in sides + 1:
		var ang: float = TAU * float(i) / float(sides)
		var c: float = cos(ang)
		var s: float = sin(ang)
		var is_side: bool = side_color.a >= 0.0 and absf(c) > side_threshold
		var col: Color = accent if is_side else base_col
		# Нормаль эллипса: градиент (c/rx, s/ry) с поправкой на конусность.
		var na: Vector3 = (u * (c / maxf(ra.x, 1e-4)) + v * (s / maxf(ra.y, 1e-4))).normalized()
		var slope: float = (ra.x - rb.x) / length
		var n: Vector3 = (na + dir * slope).normalized()
		_add_vertex(a + u * c * ra.x + v * s * ra.y, n, col, is_side)
		_add_vertex(b + u * c * rb.x + v * s * rb.y, n, col, is_side)
	for i in sides:
		var i0: int = start + i * 2
		indices.append_array(PackedInt32Array([i0, i0 + 2, i0 + 1, i0 + 1, i0 + 2, i0 + 3]))
	if caps:
		_add_cap(a, -dir, u, v, ra, base_col, sides)
		_add_cap(b, dir, u, v, rb, base_col, sides)


func _add_cap(center: Vector3, n: Vector3, u: Vector3, v: Vector3, r: Vector2, col: Color, sides: int) -> void:
	var c0: int = _add_vertex(center, n, col)
	for i in sides + 1:
		var ang: float = TAU * float(i) / float(sides)
		_add_vertex(center + u * cos(ang) * r.x + v * sin(ang) * r.y, n, col)
	for i in sides:
		if n.dot(u.cross(v)) > 0.0:
			indices.append_array(PackedInt32Array([c0, c0 + 1 + i, c0 + 2 + i]))
		else:
			indices.append_array(PackedInt32Array([c0, c0 + 2 + i, c0 + 1 + i]))


## Ломаная трубка через точки `pts` с радиусами `radii` (сочленения — сферы того же радиуса).
func add_limb(pts: PackedVector3Array, radii: PackedFloat32Array, color: Color, sides: int = 10,
		side: Vector3 = Vector3.RIGHT) -> void:
	for i in pts.size() - 1:
		add_tube(pts[i], pts[i + 1], Vector2(radii[i], radii[i]), Vector2(radii[i + 1], radii[i + 1]), color, sides, false, side)
	for i in pts.size():
		add_ellipsoid(pts[i], Vector3.ONE * radii[i], color, Basis.IDENTITY, 5, sides)


## Эллипсоид с полуосями `radii` в базисе `basis`. `band_axis`/`band_*` — цветная полоса
## (например, вентиляционные прорези шлема): вершины, у которых координата вдоль
## `band_axis` в долях радиуса попадает в [band_from; band_to], красятся `band_color`
## (region kits: `accent_region`). `band_min_y` — the band only where local unit Y >= it
## (helmet: the stripe stops above the lower rim).
func add_ellipsoid(center: Vector3, radii: Vector3, color: Color, basis: Basis = Basis.IDENTITY,
		rings: int = 6, segments: int = 12, band_axis: int = -1, band_from: float = 0.0,
		band_to: float = 0.0, band_color: Color = Color.BLACK, band_min_y: float = -2.0) -> void:
	var base_col := lin(color)
	var accent := lin(band_color)
	var start: int = vertices.size()
	for r in rings + 1:
		var phi: float = PI * float(r) / float(rings)
		for s in segments + 1:
			var theta: float = TAU * float(s) / float(segments)
			var unit := Vector3(sin(phi) * cos(theta), cos(phi), sin(phi) * sin(theta))
			var local := unit * radii
			var n_local := Vector3(unit.x / radii.x, unit.y / radii.y, unit.z / radii.z).normalized()
			var col: Color = base_col
			var in_band: bool = band_axis >= 0 and unit[band_axis] >= band_from and unit[band_axis] <= band_to \
				and unit.y >= band_min_y
			if in_band:
				col = accent
			var v: float = highlight_v if unit.y >= highlight_from_y else -1.0
			_add_vertex(center + basis * local, (basis * n_local).normalized(), col, in_band, v)
	for r in rings:
		for s in segments:
			var i0: int = start + r * (segments + 1) + s
			var i1: int = i0 + segments + 1
			indices.append_array(PackedInt32Array([i0, i0 + 1, i1, i0 + 1, i1 + 1, i1]))


## Конус (или усечённый конус) по оси Y от `base` вверх на `height`.
func add_cone(base: Vector3, height: float, radius: float, color: Color, sides: int = 8,
		top_radius: float = 0.0) -> void:
	add_tube(base, base + Vector3.UP * height, Vector2(radius, radius), Vector2(top_radius, top_radius), color,
		sides, true, Vector3.RIGHT)


## Коробка `size` с плоскими нормалями, трансформ `xform` (центр коробки — origin).
func add_box(xform: Transform3D, size: Vector3, color: Color) -> void:
	var col := lin(color)
	var h := size * 0.5
	var faces := [
		[Vector3.RIGHT, Vector3.BACK, Vector3.UP],
		[Vector3.LEFT, Vector3.FORWARD, Vector3.UP],
		[Vector3.UP, Vector3.RIGHT, Vector3.BACK],
		[Vector3.DOWN, Vector3.RIGHT, Vector3.FORWARD],
		[Vector3.BACK, Vector3.LEFT, Vector3.UP],
		[Vector3.FORWARD, Vector3.RIGHT, Vector3.UP],
	]
	for f in faces:
		var n: Vector3 = f[0]
		var t: Vector3 = f[1]
		var bt: Vector3 = f[2]
		var c: Vector3 = n * h
		var tt: Vector3 = t * h
		var bb: Vector3 = bt * h
		var wn: Vector3 = (xform.basis * n).normalized()
		var i0: int = _add_vertex(xform * (c - tt - bb), wn, col)
		_add_vertex(xform * (c + tt - bb), wn, col)
		_add_vertex(xform * (c + tt + bb), wn, col)
		_add_vertex(xform * (c - tt + bb), wn, col)
		# Обход против часовой при взгляде снаружи (Godot: передняя грань — по часовой в экране).
		if t.cross(bt).dot(n) > 0.0:
			indices.append_array(PackedInt32Array([i0, i0 + 2, i0 + 1, i0, i0 + 3, i0 + 2]))
		else:
			indices.append_array(PackedInt32Array([i0, i0 + 1, i0 + 2, i0, i0 + 2, i0 + 3]))


## Плоское кольцо в плоскости YZ (ось — X) на смещении `x`, радиусы `r_in`..`r_out`,
## нормаль `±X`. Для обода колеса и звезды.
func add_annulus_x(x: float, r_in: float, r_out: float, color: Color, normal_sign: float, sides: int = 32) -> void:
	var col := lin(color)
	var n := Vector3(normal_sign, 0.0, 0.0)
	var start: int = vertices.size()
	for i in sides + 1:
		var ang: float = TAU * float(i) / float(sides)
		var dy: float = cos(ang)
		var dz: float = sin(ang)
		_add_vertex(Vector3(x, dy * r_in, dz * r_in), n, col)
		_add_vertex(Vector3(x, dy * r_out, dz * r_out), n, col)
	for i in sides:
		var i0: int = start + i * 2
		if normal_sign > 0.0:
			indices.append_array(PackedInt32Array([i0, i0 + 1, i0 + 2, i0 + 1, i0 + 3, i0 + 2]))
		else:
			indices.append_array(PackedInt32Array([i0, i0 + 2, i0 + 1, i0 + 1, i0 + 2, i0 + 3]))


## Цилиндрическая лента вокруг оси X: радиус `r`, от `x0` до `x1`, нормаль наружу (`outward`)
## или внутрь.
func add_band_x(x0: float, x1: float, r: float, color: Color, outward: bool, sides: int = 32) -> void:
	var col := lin(color)
	var start: int = vertices.size()
	for i in sides + 1:
		var ang: float = TAU * float(i) / float(sides)
		var n := Vector3(0.0, cos(ang), sin(ang))
		var nn: Vector3 = n if outward else -n
		_add_vertex(Vector3(x0, n.y * r, n.z * r), nn, col)
		_add_vertex(Vector3(x1, n.y * r, n.z * r), nn, col)
	for i in sides:
		var i0: int = start + i * 2
		if outward:
			indices.append_array(PackedInt32Array([i0, i0 + 2, i0 + 1, i0 + 1, i0 + 2, i0 + 3]))
		else:
			indices.append_array(PackedInt32Array([i0, i0 + 1, i0 + 2, i0 + 1, i0 + 3, i0 + 2]))


## Тор вокруг оси X (покрышка): большой радиус `big_r`, малый `small_r`.
func add_torus_x(big_r: float, small_r: float, color: Color, sides: int = 36, ring_sides: int = 8) -> void:
	var col := lin(color)
	var start: int = vertices.size()
	for i in sides + 1:
		var a: float = TAU * float(i) / float(sides)
		var radial := Vector3(0.0, cos(a), sin(a))
		for j in ring_sides + 1:
			var b: float = TAU * float(j) / float(ring_sides)
			var n: Vector3 = radial * cos(b) + Vector3.RIGHT * sin(b)
			_add_vertex(radial * big_r + n * small_r, n, col)
	for i in sides:
		for j in ring_sides:
			var i0: int = start + i * (ring_sides + 1) + j
			var i1: int = i0 + ring_sides + 1
			indices.append_array(PackedInt32Array([i0, i1, i0 + 1, i0 + 1, i1, i1 + 1]))


## Добавить произвольный четырёхугольник (a, b, c, d по кругу) с нормалью `n`.
func add_quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3, color: Color) -> void:
	var col := lin(color)
	var i0: int = _add_vertex(a, n, col)
	_add_vertex(b, n, col)
	_add_vertex(c, n, col)
	_add_vertex(d, n, col)
	var face_n: Vector3 = (b - a).cross(c - a)
	if face_n.dot(n) < 0.0:
		indices.append_array(PackedInt32Array([i0, i0 + 1, i0 + 2, i0, i0 + 2, i0 + 3]))
	else:
		indices.append_array(PackedInt32Array([i0, i0 + 2, i0 + 1, i0, i0 + 3, i0 + 2]))


## Треугольник (a, b, c) с нормалью `n` (обход приводится к нормали в `fix_winding`).
func add_triangle(a: Vector3, b: Vector3, c: Vector3, n: Vector3, color: Color) -> void:
	var col := lin(color)
	var i0: int = _add_vertex(a, n, col)
	_add_vertex(b, n, col)
	_add_vertex(c, n, col)
	indices.append_array(PackedInt32Array([i0, i0 + 1, i0 + 2]))


## Двускатная крыша (T-083, постройки ориентиров): основание — прямоугольник `size.x` × `size.z`
## на высоте 0 в осях `xform`, конёк вдоль X на высоте `size.y`, свес `overhang` со всех сторон.
## Скаты — `color`, фронтоны (треугольники на торцах) — `gable_color`.
func add_gable_roof(xform: Transform3D, size: Vector3, overhang: float, color: Color, gable_color: Color) -> void:
	var hx: float = size.x * 0.5 + overhang
	var hz: float = size.z * 0.5 + overhang
	var drop: float = size.y * overhang / maxf(size.z * 0.5, 1e-3)
	var ridge_a: Vector3 = xform * Vector3(-hx, size.y, 0.0)
	var ridge_b: Vector3 = xform * Vector3(hx, size.y, 0.0)
	for sgn in [-1.0, 1.0]:
		var eave_a: Vector3 = xform * Vector3(-hx, -drop, sgn * hz)
		var eave_b: Vector3 = xform * Vector3(hx, -drop, sgn * hz)
		var n: Vector3 = (xform.basis * Vector3(0.0, hz, sgn * (size.y + drop))).normalized()
		add_quad(eave_a, eave_b, ridge_b, ridge_a, n, color)
	for sgn in [-1.0, 1.0]:
		var x: float = sgn * size.x * 0.5
		var n: Vector3 = (xform.basis * Vector3(sgn, 0.0, 0.0)).normalized()
		add_triangle(xform * Vector3(x, 0.0, -size.z * 0.5), xform * Vector3(x, 0.0, size.z * 0.5),
			xform * Vector3(x, size.y, 0.0), n, gable_color)


## Четырёхскатная пирамида (крыша башни): основание `half.x` × `half.y` (полуразмеры по X и Z)
## с центром `base`, вершина на `height` выше, грани вдоль осей X/Z.
func add_pyramid(base: Vector3, half: Vector2, height: float, color: Color) -> void:
	var apex: Vector3 = base + Vector3(0.0, height, 0.0)
	var c: Array[Vector3] = [
		base + Vector3(-half.x, 0.0, -half.y), base + Vector3(half.x, 0.0, -half.y),
		base + Vector3(half.x, 0.0, half.y), base + Vector3(-half.x, 0.0, half.y),
	]
	for i in 4:
		var a: Vector3 = c[i]
		var b: Vector3 = c[(i + 1) % 4]
		var mid: Vector3 = (a + b) * 0.5 - base
		var n: Vector3 = (mid.normalized() * height + Vector3.UP * mid.length()).normalized()
		add_triangle(a, b, apex, n, color)


## Привести обход треугольников к нормалям вершин (в Godot лицевая грань — обход по часовой
## при взгляде на неё): примитивам выше не нужно заботиться о порядке индексов.
func fix_winding() -> void:
	for t in range(0, indices.size(), 3):
		var i0: int = indices[t]
		var i1: int = indices[t + 1]
		var i2: int = indices[t + 2]
		var fn: Vector3 = (vertices[i2] - vertices[i0]).cross(vertices[i1] - vertices[i0])
		if fn.dot(normals[i0] + normals[i1] + normals[i2]) < 0.0:
			indices[t + 1] = i2
			indices[t + 2] = i1


## Region kits: one region per face and smoothed outline normals (see the class comment).
## Idempotent; call after all primitives are added (winding is fixed first).
func finalize_regions() -> void:
	if not uses_regions():
		return
	assert(uvs.size() == vertices.size() and accents.size() == vertices.size(),
		"MeshKit: every vertex of a region kit needs a region")
	fix_winding()
	# Region (UV) of each face: an accent vertex wins (the accent covers whole quads, borders run
	# along quad edges); border vertices are duplicated.
	var copies: Dictionary = {}
	for t in range(0, indices.size(), 3):
		var face: Vector2 = uvs[indices[t]]
		for j in 3:
			if accents[indices[t + j]] == 1:
				face = uvs[indices[t + j]]
				break
		for j in 3:
			var i: int = indices[t + j]
			if uvs[i] == face:
				continue
			var key: String = "%d:%f:%f" % [i, face.x, face.y]
			if not copies.has(key):
				copies[key] = vertices.size()
				vertices.append(vertices[i])
				normals.append(normals[i])
				colors.append(colors[i])
				uvs.append(face)
				accents.append(accents[i])
			indices[t + j] = copies[key]
	outline_normals = smoothed_normals(vertices, normals)


## Average of the normals of all vertices at the same position (to 0.1 mm), normalized.
static func smoothed_normals(pts: PackedVector3Array, ns: PackedVector3Array) -> PackedVector3Array:
	var sums: Dictionary = {}
	var keys: Array[Vector3i] = []
	keys.resize(pts.size())
	for i in pts.size():
		var key := Vector3i((pts[i] * 10000.0).round())
		keys[i] = key
		sums[key] = sums.get(key, Vector3.ZERO) + ns[i]
	var out := PackedVector3Array()
	out.resize(pts.size())
	for i in pts.size():
		var sum: Vector3 = sums[keys[i]]
		out[i] = sum.normalized() if sum.length_squared() > 1e-12 else ns[i]
	return out


## Outline normals as the TANGENT array (w = 1): skinning moves them with the bone.
func outline_tangents() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(outline_normals.size() * 4)
	for i in outline_normals.size():
		var n: Vector3 = outline_normals[i]
		out[i * 4] = n.x
		out[i * 4 + 1] = n.y
		out[i * 4 + 2] = n.z
		out[i * 4 + 3] = 1.0
	return out


## Surface arrays: world kits — COLOR; region kits — UV0 and TANGENT (outline normals),
## without COLOR (the rider shaders read only the region).
func surface_arrays() -> Array:
	fix_winding()
	finalize_regions()
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	if uses_regions():
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		arrays[Mesh.ARRAY_TANGENT] = outline_tangents()
	else:
		arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	return arrays


## Собрать `ArrayMesh` с одной поверхностью.
func to_mesh(material: Material = null) -> ArrayMesh:
	var arrays: Array = surface_arrays()
	var mesh := ArrayMesh.new()
	if vertices.is_empty():
		return mesh
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	if material != null:
		mesh.surface_set_material(0, material)
	return mesh
