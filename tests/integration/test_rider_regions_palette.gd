extends GutTest
## T-106a3: color regions in UV0, appearance palette and outline weight in one material,
## additive rim, jersey patterns, rider shadow, rider budget row (REQ-D3D-09 p.6, 7, 12 [auto];
## REQ-D3D-07 p.4, 6 regression; REQ-D3D-05 p.4; REQ-AVT-02 p.1, 2 mechanism). Spec: art bible
## "Rider" -> "Appearance slots" (regions, encoding, outline column, pattern table),
## "Composition and budget", "Rider shadow".

const RIDER_SCENE: String = "res://src/scene3d/rider.tscn"
const RIDE_SCENE: String = "res://src/scene3d/ride_scene.tscn"
const ATLAS: String = "res://assets/rider/reference/rider_atlas_preview.png"
const RIDER_TOON: String = "res://src/scene3d/shaders/rider_toon.gdshader"
const RIDER_OUTLINE: String = "res://src/scene3d/shaders/rider_outline.gdshader"
const TOON_LIGHT: String = "res://src/scene3d/shaders/toon_light.gdshaderinc"

## Regions without outline (table of regions, column "Outline").
const SPEC_NO_OUTLINE: Array[int] = [18, 19, 20, 25, 28, 29]
## Pattern table of the spec: regions 3 sides, 4 band, 5 shoulders, 6 cuffs, 7 collar.
const SPEC_PATTERNS: Dictionary = {
	"solid": ["main", "main", "main", "a1", "a1"],
	"side_panels": ["a1", "main", "main", "a2", "a2"],
	"chest_band": ["main", "a1", "main", "a1", "a2"],
	"shoulder_yoke": ["a2", "main", "a1", "a1", "a1"],
}
## Mesh variants of the rider nodes: node -> mesh keys of `RiderModel.meshes`.
const NODE_MESHES: Dictionary = {
	"Body": ["body_m", "body_f"], "Hair": ["hair_short", "hair_tail"], "Helmet": ["helmet"],
	"Eyewear": ["eyewear"], "ShoeL": ["shoe_l"], "ShoeR": ["shoe_r"], "Bike": ["bike"],
	"FrontWheel": ["wheel", "wheel_shallow"], "RearWheel": ["rear_wheel", "rear_wheel_shallow"],
	"CrankArm": ["crank"],
}
## Triangle limits of the composition table.
const TRI_LIMITS: Dictionary = {
	"Body": 8000, "Hair": 800, "Helmet": 1600, "Eyewear": 400, "ShoeL": 600, "ShoeR": 600,
	"Bike": 2600, "FrontWheel": 1600, "RearWheel": 1600, "CrankArm": 600,
}
const TOTAL_TRIS: int = 18500
const MAX_NODES: int = 10

var _meshes: Dictionary


func before_all() -> void:
	_meshes = RiderModel.meshes(Rider.RIDER_MATERIAL)


func _arrays(key: String) -> Array:
	return (_meshes[key] as Mesh).surface_get_arrays(0)


func _tris(mesh: Mesh) -> int:
	var n: int = 0
	for s in mesh.get_surface_count():
		n += (mesh.surface_get_arrays(s)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
	return n


func _rider() -> Rider:
	var r: Rider = (load(RIDER_SCENE) as PackedScene).instantiate()
	add_child_autofree(r)
	return r


static func _classic_palette() -> PackedColorArray:
	return PackedColorArray(RiderRegions.palette(RiderLook.preset(RiderLook.PRESET_CLASSIC)))


static func _dist(a: Color, b: Color) -> float:
	return maxf(maxf(absf(a.r - b.r), absf(a.g - b.g)), absf(a.b - b.b))


# --- p.1: regions in UV0 ---

## Every face of the mannequin and the bike lies inside one atlas column with a 10 % margin:
## all three vertices have U in [(k + 0.1)/32; (k + 0.9)/32] of the same k.
func test_every_face_inside_one_column_with_margin() -> void:
	for key in _meshes:
		var arr: Array = _arrays(key)
		var uv: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		assert_eq(uv.size(), verts.size(), "%s: UV0 on every vertex" % key)
		var bad: int = 0
		for t in range(0, idx.size(), 3):
			var k: int = MeshKit.uv_region(uv[idx[t]])
			var r: Vector2 = RiderRegions.u_range(k)
			for j in 3:
				var u: float = uv[idx[t + j]].x
				if MeshKit.uv_region(uv[idx[t + j]]) != k or u < r.x - 1e-6 or u > r.y + 1e-6:
					bad += 1
					break
		assert_eq(bad, 0, "%s: faces across columns or outside the margin" % key)


## Vertex colors are not used by the rider and bike: no COLOR array in the meshes.
func test_rider_meshes_have_no_vertex_colors() -> void:
	for key in _meshes:
		var c: Variant = _arrays(key)[Mesh.ARRAY_COLOR]
		assert_true(c == null or (c as PackedColorArray).is_empty(), "%s: no COLOR" % key)


## The bike uses regions 23-31 only, the rider — 0-22 only (regions 23-31 are the bike's).
func test_bike_and_rider_regions_split() -> void:
	for key in _meshes:
		var bike: bool = key in ["bike", "wheel", "rear_wheel", "wheel_shallow", "rear_wheel_shallow", "crank"]
		var used: Dictionary = {}
		for uv in _arrays(key)[Mesh.ARRAY_TEX_UV] as PackedVector2Array:
			used[MeshKit.uv_region(uv)] = true
		for k in used:
			if bike:
				assert_gte(int(k), RiderRegions.FIRST_BIKE, "%s: region %d" % [key, k])
			else:
				assert_lt(int(k), RiderRegions.FIRST_BIKE, "%s: region %d" % [key, k])
	# Composition of the bike: frame, accent, decal, bar tape, tyre, rim, metal, components, bottle.
	var bike_regions: Dictionary = {}
	for key in ["bike", "wheel", "rear_wheel", "crank"]:
		for uv in _arrays(key)[Mesh.ARRAY_TEX_UV] as PackedVector2Array:
			bike_regions[MeshKit.uv_region(uv)] = true
	for k in range(23, 32):
		assert_true(bike_regions.has(k), "bike has region %d (%s)" % [k, RiderRegions.region_name(k)])


## Writing the color of region k changes the color of the faces of region k only: per-face albedo
## by the palette of the rider material and the face UV (mirror of the shader), before and after.
func test_region_write_changes_only_that_region() -> void:
	var r := _rider()
	var probe := Color(1.0, 0.0, 1.0)
	var base_pal: PackedColorArray = RiderPalette.palette_of(r.material())
	var hl: Color = RiderPalette.lens_highlight_of(r.material())
	for k in [0, 2, 3, 8, 10, 16, 17, 19, 21, 23, 24, 26, 27, 31]:
		r.set_palette(base_pal, hl)
		r.set_region_color(k, probe)
		var pal: PackedColorArray = RiderPalette.palette_of(r.material())
		for i in RiderPalette.COUNT:
			if i == k:
				assert_eq(pal[i], probe, "region %d written" % k)
			else:
				assert_eq(pal[i], base_pal[i], "region %d: palette entry %d unchanged" % [k, i])
		var changed_other: int = 0
		var changed_own: int = 0
		for node in NODE_MESHES:
			var mi := r.find_child(node, true, false) as MeshInstance3D
			var arr: Array = mi.mesh.surface_get_arrays(0)
			var uv: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
			for t in range(0, idx.size(), 3):
				var face_uv: Vector2 = uv[idx[t]]
				var code: int = MeshKit.uv_region(face_uv)
				var v: float = 1.0 - face_uv.y
				var before: Color = RiderPalette.albedo(base_pal, hl, code, v)
				var after: Color = RiderPalette.albedo(pal, hl, code, v)
				if not before.is_equal_approx(after):
					if code == k:
						changed_own += 1
					else:
						changed_other += 1
		assert_eq(changed_other, 0, "region %d: faces of other regions keep their color" % k)
		if k != 19:
			assert_gt(changed_own, 0, "region %d: its faces change" % k)


# --- p.2: one material, palette, tone, highlight, outline weight ---

## One toon material on all 10 nodes, outline — `next_pass`; palette and outline weights are
## material parameters; 0 textures.
func test_one_material_with_palette_and_outline_pass() -> void:
	var r := _rider()
	var mats: Dictionary = {}
	var nodes: int = 0
	for mi in r.find_children("*", "MeshInstance3D", true, false):
		nodes += 1
		var m: Material = (mi as MeshInstance3D).get_active_material(0)
		mats[m] = true
	assert_lte(nodes, MAX_NODES, "MeshInstance3D of rider with bike")
	assert_eq(mats.size(), 1, "one material for the rider with the bike")
	var mat := Rider.RIDER_MATERIAL as ShaderMaterial
	assert_eq(mat.shader.resource_path, RIDER_TOON)
	assert_eq((mat.next_pass as ShaderMaterial).shader.resource_path, RIDER_OUTLINE, "outline — next_pass")
	assert_eq(RiderPalette.palette_of(mat).size(), 32, "32 region colors")
	for p in [mat, mat.next_pass]:
		for u in (p as ShaderMaterial).shader.get_shader_uniform_list():
			assert_ne(int(u["type"]), TYPE_OBJECT, "no textures: %s" % u["name"])
	# set_palette gives the rider its own copy; still one material.
	r.set_region_color(2, Color.BLACK)
	mats.clear()
	for mi in r.find_children("*", "MeshInstance3D", true, false):
		mats[(mi as MeshInstance3D).get_active_material(0)] = true
	assert_eq(mats.size(), 1, "after a palette write — still one material")
	assert_ne(r.material(), Rider.RIDER_MATERIAL, "own copy: the shared material is not touched")
	assert_eq(RiderPalette.palette_of(Rider.RIDER_MATERIAL)[2], _classic_palette()[2])


## Default palette — preset `classic` (`RiderRegions.palette`), highlight — `smoke`.
func test_default_palette_is_classic() -> void:
	var mat := Rider.RIDER_MATERIAL as ShaderMaterial
	var pal: PackedColorArray = RiderPalette.palette_of(mat)
	var want: PackedColorArray = _classic_palette()
	for k in 32:
		assert_lt(_dist(pal[k], want[k]), 1e-4, "region %d (%s)" % [k, RiderRegions.region_name(k)])
	var hl: Color = RiderRegions.lens_highlight(RiderLook.preset(RiderLook.PRESET_CLASSIC))
	assert_lt(_dist(RiderPalette.lens_highlight_of(mat), hl), 1e-4, "lens highlight")


## Outline weight by region: 0 for 18, 19, 20, 25, 28, 29, otherwise 1 — in the outline pass of the
## material and in `RiderRegions`.
func test_outline_weight_by_region_table() -> void:
	var mat := Rider.RIDER_MATERIAL as ShaderMaterial
	for k in 32:
		var want: float = 0.0 if SPEC_NO_OUTLINE.has(k) else 1.0
		assert_eq(RiderPalette.outline_weight(mat, k), want, "material: region %d" % k)
		assert_eq(RiderRegions.outline_weight(k), want, "RiderRegions: region %d" % k)
	var code: String = (load(RIDER_OUTLINE) as Shader).code
	assert_string_contains(code, "region_outline[rider_region(UV)]", "weight by the vertex region")
	assert_string_contains(code, "cull_front", "inverted hull")


## Albedo of the rider shader (before light, sRGB) for region k and tone V with `classic` equals
## the pixel of `rider_atlas_preview.png` in column k at height V ± 2/255; regions 0-31 at
## V = 0.1, 0.5, 0.9 and region 19 also at 0.74 and 0.76 (base tone and highlight, flat).
func test_shader_albedo_matches_preview_atlas() -> void:
	var img := Image.load_from_file(ProjectSettings.globalize_path(ATLAS))
	assert_not_null(img, "atlas")
	if img == null:
		return
	var mat := Rider.RIDER_MATERIAL as ShaderMaterial
	var pal: PackedColorArray = RiderPalette.palette_of(mat)
	var hl: Color = RiderPalette.lens_highlight_of(mat)
	var checks: Array = []
	for k in 32:
		for v in [0.1, 0.5, 0.9]:
			checks.append([k, v])
	checks.append([19, 0.74])
	checks.append([19, 0.76])
	for c in checks:
		var k: int = c[0]
		var v: float = c[1]
		var y: int = clampi(int(round((1.0 - v) * 256.0 - 0.5)), 0, 255)
		var px: Color = img.get_pixel(k * 32 + 16, y)
		var got: Color = RiderPalette.albedo(pal, hl, k, v)
		assert_lt(_dist(got, px), 2.0 / 255.0 + 1e-4, "region %d V %.2f: %s vs atlas %s" % [k, v, got, px])
	# The highlight is flat (no tone): equal at V 0.76 and 0.95.
	assert_eq(RiderPalette.albedo(pal, hl, 19, 0.76), RiderPalette.albedo(pal, hl, 19, 0.95))
	# The shader computes the same: tone in linear space, glTF V flip, flat highlight.
	var code: String = (load(RIDER_TOON) as Shader).code
	assert_string_contains(code, "min(vec3(1.0), (RIDER_TONE_MIN + RIDER_TONE_SPAN * v) * look_to_linear(palette[k].rgb))")
	assert_string_contains(code, "k == RIDER_LENS && v >= RIDER_LENS_HIGHLIGHT_V")
	assert_string_contains(code, "lin = look_to_linear(lens_highlight.rgb);")
	assert_false(code.contains("COLOR"), "vertex colors are not read")
	var inc: String = FileAccess.get_file_as_string("res://src/scene3d/shaders/rider_regions.gdshaderinc")
	assert_string_contains(inc, "floor(uv.x * float(RIDER_REGION_COUNT))", "region = floor(U · 32)")
	assert_string_contains(inc, "return 1.0 - uv.y;", "V flipped like glTF")


## Smoothed outline normals: TANGENT is the average normal over all vertices at one position
## (per bone part), so hard edges and region seams do not tear the outline. Positions whose
## normals cancel out (back-to-back thin parts) keep their own normal.
func test_outline_normals_are_smoothed_by_position() -> void:
	for key in ["bike", "crank", "shoe_r", "body_m", "hair_tail"]:
		var arr: Array = _arrays(key)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var n: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		var t: PackedFloat32Array = arr[Mesh.ARRAY_TANGENT]
		var bones: Variant = arr[Mesh.ARRAY_BONES]
		assert_eq(t.size(), v.size() * 4, "%s: TANGENT on every vertex" % key)
		var groups: Dictionary = {}
		for i in v.size():
			var bone: int = (bones as PackedInt32Array)[i * 4] if bones != null else 0
			var p := Vector3i((v[i] * 10000.0).round())
			var gk := Vector4i(p.x, p.y, p.z, bone)
			if not groups.has(gk):
				groups[gk] = []
			(groups[gk] as Array).append(i)
		var spread: float = 0.0
		var hard: int = 0
		for gk in groups:
			var ids: Array = groups[gk]
			var sum := Vector3.ZERO
			for i in ids:
				sum += n[i]
			if ids.size() < 2 or sum.length() < 0.1:
				continue
			var t0 := Vector3(t[ids[0] * 4], t[ids[0] * 4 + 1], t[ids[0] * 4 + 2])
			assert_lt(t0.angle_to(sum), deg_to_rad(1.0), "%s: outline normal = average normal" % key)
			for i in ids:
				spread = maxf(spread, t0.angle_to(Vector3(t[i * 4], t[i * 4 + 1], t[i * 4 + 2])))
				if n[i].angle_to(sum) > deg_to_rad(20.0):
					hard += 1
		assert_lt(rad_to_deg(spread), 1.0, "%s: one outline normal per position" % key)
		gut.p("%s: %d vertices on hard edges get the averaged outline normal" % [key, hard])
	var outline: String = (load(RIDER_OUTLINE) as Shader).code
	assert_string_contains(outline, "normalize(TANGENT)", "Forward+/Mobile: hull along the smoothed normal")


## Region seams duplicate vertices but keep their normal: no gap in the hull at a color border.
func test_region_seams_keep_normals() -> void:
	var arr: Array = _arrays("body_m")
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var n: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var uv: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
	var bones: PackedInt32Array = arr[Mesh.ARRAY_BONES]
	var seen: Dictionary = {}
	var seams: int = 0
	for i in v.size():
		var key := [Vector3i((v[i] * 100000.0).round()), Vector3i((n[i] * 1000.0).round()), bones[i * 4]]
		var k: int = MeshKit.uv_region(uv[i])
		if seen.has(key) and seen[key] != k:
			seams += 1
		seen[key] = k
	assert_gt(seams, 0, "jersey side panels are separate faces with shared positions and normals")


# --- jersey patterns (AVT-02 mechanism) ---

func test_four_patterns_give_regions_3_to_7_by_spec() -> void:
	var main := Color(0.1, 0.2, 0.3)
	var a1 := Color(0.4, 0.5, 0.6)
	var a2 := Color(0.7, 0.8, 0.9)
	var src := {"main": main, "a1": a1, "a2": a2}
	for pattern in SPEC_PATTERNS:
		var cols: Array[Color] = RiderPalette.jersey_regions({"jersey.pattern": pattern, "jersey.main": main,
			"jersey.accent1": a1, "jersey.accent2": a2})
		assert_eq(cols.size(), 5, pattern)
		for i in 5:
			assert_eq(cols[i], src[SPEC_PATTERNS[pattern][i]], "%s: region %d" % [pattern, 3 + i])
		var pal: PackedColorArray = RiderPalette.with_jersey(_classic_palette(), {"jersey.pattern": pattern,
			"jersey.main": main, "jersey.accent1": a1, "jersey.accent2": a2})
		assert_eq(pal[2], main, "%s: region 2 = main" % pattern)
		assert_eq(pal[31], a2, "%s: bottle = accent2" % pattern)
		assert_eq(pal[8], _classic_palette()[8], "%s: shorts untouched" % pattern)
	# Unknown pattern -> default `side_panels`; no dependency on src/profiles/.
	var d: Array[Color] = RiderPalette.jersey_regions({"jersey.pattern": "zebra", "jersey.main": main,
		"jersey.accent1": a1, "jersey.accent2": a2})
	assert_eq(d[0], a1, "unknown pattern -> side_panels")
	var code: String = FileAccess.get_file_as_string("res://src/scene3d/rider_palette.gd")
	assert_false(code.contains("RiderLook.") or code.contains("res://src/profiles"), "RiderPalette does not depend on src/profiles/")
	# Same table as RiderLook (T-108).
	for pattern in SPEC_PATTERNS:
		assert_eq(RiderPalette.PATTERN_SOURCES[pattern], RiderLook.PATTERN_SOURCES[pattern], pattern)


# --- p.3: additive rim ---

## The rim is a light line of sun tint added on top of the albedo (specular light — not
## multiplied by it), strength 0.35: visible on a black jersey.
func test_rim_is_additive_and_strength_035() -> void:
	var code: String = FileAccess.get_file_as_string(TOON_LIGHT)
	var rim_at: int = code.find("if (toon_rim > 0.0)")
	assert_gt(rim_at, -1)
	var block: String = code.substr(rim_at, code.find("}", rim_at) - rim_at)
	assert_string_contains(block, "SPECULAR_LIGHT += LIGHT_COLOR / PI", "rim — sun tint, added (not × albedo)")
	assert_false(block.contains("DIFFUSE_LIGHT"), "rim is not diffuse light (that is × albedo)")
	assert_almost_eq(float((Rider.RIDER_MATERIAL as ShaderMaterial).get_shader_parameter("toon_rim")), 0.35, 1e-6)
	assert_eq(float((Rider.RIDER_MATERIAL as ShaderMaterial).get_shader_parameter("toon_receive_shadow")), 0.0,
		"the rider does not receive shadows")


# --- helmet rule and rims (mechanism for p.20 and `bike.rims`) ---

## Helmet rule: the lower rim of the shell is solid main color (region 16) — the accent stripe
## (17) is on the top only; the main color covers more than half of the shell.
func test_helmet_lower_rim_main_color_and_main_majority() -> void:
	var arr: Array = _arrays("helmet")
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var uv: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var lo: float = INF
	var hi: float = -INF
	for i in v.size():
		if MeshKit.uv_region(uv[i]) in [16, 17]:
			lo = minf(lo, v[i].y)
			hi = maxf(hi, v[i].y)
	var main_area: float = 0.0
	var accent_area: float = 0.0
	for t in range(0, idx.size(), 3):
		var k: int = MeshKit.uv_region(uv[idx[t]])
		var a: float = (v[idx[t + 1]] - v[idx[t]]).cross(v[idx[t + 2]] - v[idx[t]]).length() * 0.5
		if k == 16:
			main_area += a
		elif k == 17:
			accent_area += a
			var y: float = minf(v[idx[t]].y, minf(v[idx[t + 1]].y, v[idx[t + 2]].y))
			assert_gt(y, lo + 0.015 + (hi - lo) * 0.3, "accent stripe stays above the lower rim (≥ 1.5 cm band)")
	assert_gt(accent_area, 0.0, "the helmet has the accent stripe")
	assert_lt(accent_area / (main_area + accent_area), 0.25, "helmet_accent ≤ 1/4 of the shell")


func test_rim_variants_deep_and_shallow() -> void:
	for pair in [["wheel", "wheel_shallow"], ["rear_wheel", "rear_wheel_shallow"]]:
		var depth: Array[float] = []
		for key in pair:
			var arr: Array = _arrays(key)
			var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var uv: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
			var r_in: float = INF
			for i in v.size():
				if MeshKit.uv_region(uv[i]) == RiderRegions.RIM_CARBON:
					r_in = minf(r_in, Vector2(v[i].y, v[i].z).length())
			depth.append(0.308 - r_in)
		assert_between(depth[0], 0.045, 0.056, "%s: deep rim ≈ 50 mm (%.3f)" % [pair[0], depth[0]])
		assert_between(depth[1], 0.027, 0.033, "%s: shallow rim ≈ 30 mm (%.3f)" % [pair[1], depth[1]])
	var r := _rider()
	r.set_rims("shallow")
	assert_eq((r.find_child("FrontWheel", true, false) as MeshInstance3D).mesh, _meshes["wheel_shallow"])
	assert_eq((r.find_child("RearWheel", true, false) as MeshInstance3D).mesh, _meshes["rear_wheel_shallow"])
	r.set_rims("deep")
	assert_eq((r.find_child("FrontWheel", true, false) as MeshInstance3D).mesh, _meshes["wheel"])


# --- p.5 budget ---

func test_budget_nodes_and_triangles() -> void:
	var r := _rider()
	var nodes: Array = r.find_children("*", "MeshInstance3D", true, false)
	assert_lte(nodes.size(), MAX_NODES, "MeshInstance3D ≤ 10")
	var total: int = 0
	for node in NODE_MESHES:
		var worst: int = 0
		for key in NODE_MESHES[node]:
			var n: int = _tris(_meshes[key])
			assert_lte(n, int(TRI_LIMITS[node]), "%s (%s): %d triangles" % [node, key, n])
			worst = maxi(worst, n)
		total += worst
	gut.p("rider with bike, heaviest variants: %d triangles" % total)
	assert_lte(total, TOTAL_TRIS, "≤ 18 500 triangles (heaviest variants)")
	var skel := r.find_child("Skeleton", true, false) as Skeleton3D
	assert_lte(skel.get_bone_count(), 28, "≤ 28 bones")


func test_budget_row_in_perf_budget_doc() -> void:
	var text: String = FileAccess.get_file_as_string("res://docs/perf_budget.md")
	assert_string_contains(text, "Гонщик с велосипедом: ≤ 18 500 треугольников (самые тяжёлые варианты), ≤ 10 `MeshInstance3D`, 1 материал, 0 текстур, ≤ 28 костей; эталон — MacBook Pro M1 Pro (MacBookPro18,3), У-25")


## Unique materials of the scene: the rider adds one material (as before T-106a3), and a palette
## write does not add one.
func test_scene_materials_not_more_than_before() -> void:
	var scene: RideScene = (load(RIDE_SCENE) as PackedScene).instantiate()
	add_child_autofree(scene)
	var before: int = int(PerfBudget.count(scene)["materials"])
	assert_lte(before, PerfBudget.MAX_MATERIALS)
	scene.rider().set_region_color(2, Color.BLACK)
	assert_eq(int(PerfBudget.count(scene)["materials"]), before, "own palette copy replaces the shared material")


# --- p.4 shadow ---

func test_shadow_filter_and_first_split() -> void:
	var q: int = int(ProjectSettings.get_setting("rendering/lights_and_shadows/directional_shadow/soft_shadow_filter_quality", 0))
	assert_gte(q, 1, "soft_shadow_filter_quality ≥ 1 (PCF soft low)")
	var scene: RideScene = (load(RIDE_SCENE) as PackedScene).instantiate()
	add_child_autofree(scene)
	var sun := scene.get_node("%Sun") as DirectionalLight3D
	assert_true(sun.shadow_enabled)
	assert_almost_eq(sun.directional_shadow_max_distance, 90.0, 1e-3, "max_distance 90 m")
	assert_lte(sun.directional_shadow_split_1, 0.15 + 1e-6, "split_1 ≤ 0.15 (first split ≤ 13.5 m)")
	assert_eq(sun.shadow_blur, 0.0, "hard shadow style: no extra blur")
	var rider := scene.rider()
	for mi in rider.find_children("*", "MeshInstance3D", true, false):
		assert_ne((mi as MeshInstance3D).cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "%s casts a shadow" % mi.name)
