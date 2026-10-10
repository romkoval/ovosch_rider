extends GutTest
## Tester acceptance of T-106a3 — color regions in UV0, palette and per-region outline weight in
## one rider material, additive rim, jersey patterns, rider shadow, rider budget row
## (REQ-D3D-09 p.6, 7, 12 [auto] part; REQ-D3D-07 p.4; REQ-D3D-05 p.4; REQ-AVT-02 p.1–3
## mechanism).
##
## Independent of the developer tests (`test_rider_regions_palette.gd`): spec numbers (art bible
## «Rider» → «Appearance slots», «Composition and budget», «Rider shadow») are literals here, the
## region of a vertex is computed from the raw UV (floor(U · 32)), not through `MeshKit` /
## `RiderRegions`; scene budgets are compared with numbers measured on the pre-task base 3ddb4bb.

const RIDER_SCENE: String = "res://src/scene3d/rider.tscn"
const RIDE_SCENE: String = "res://src/scene3d/ride_scene.tscn"
const TRACKS: Array[String] = ["flat", "hills", "mountains", "seaside"]

## Spec palette of the form (sRGB).
const WHITE := Color(0.95, 0.95, 0.96)
const RED := Color(0.86, 0.14, 0.16)
const BLUE := Color(0.18, 0.28, 0.72)
const NAVY := Color(0.16, 0.18, 0.44)
const BLACK := Color(0.09, 0.09, 0.10)
const YELLOW := Color(0.98, 0.82, 0.18)
## Default appearance = preset `classic` → expected color of every region 0–31 (table of regions,
## slot table, presets table, pattern `side_panels`: 3 a1, 4 main, 5 main, 6 a2, 7 a2).
const SPEC_CLASSIC: Array[Color] = [
	Color(0.87, 0.64, 0.50), # 0 skin s3
	Color(0.24, 0.16, 0.11), # 1 hair dark_brown
	WHITE, # 2 jersey.main
	RED, # 3 side = accent1
	WHITE, # 4 band = main
	WHITE, # 5 yoke = main
	BLUE, # 6 cuff = accent2
	BLUE, # 7 collar = accent2
	NAVY, # 8 shorts.main
	BLACK, # 9 shorts.gripper
	WHITE, # 10 socks.main
	WHITE, # 11 socks.cuff
	WHITE, # 12 shoes.main
	BLACK, # 13 shoes.accent
	Color(0.14, 0.14, 0.16), # 14 sole (fixed)
	Color(0.82, 0.18, 0.16), # 15 cleat (fixed)
	WHITE, # 16 helmet.main
	BLACK, # 17 helmet.accent
	Color(0.12, 0.12, 0.14), # 18 helmet_inner (fixed)
	Color(0.18, 0.19, 0.22), # 19 lens smoke, base tone
	BLACK, # 20 glasses.frame
	BLACK, # 21 gloves.color (model short)
	Color(0.22, 0.22, 0.24), # 22 glove_palm (fixed, gloves present)
	RED, # 23 bike.frame
	YELLOW, # 24 bike.accent
	YELLOW, # 25 bike.rim_decal
	BLACK, # 26 bike.bar_tape
	Color(0.10, 0.10, 0.11), # 27 tire (fixed)
	Color(0.13, 0.13, 0.15), # 28 rim_carbon (fixed)
	Color(0.70, 0.71, 0.74), # 29 metal (fixed)
	Color(0.09, 0.09, 0.10), # 30 component (fixed)
	BLUE, # 31 bottle = jersey.accent2
]
const SPEC_SMOKE_HIGHLIGHT := Color(0.42, 0.44, 0.50)
## Regions without outline (column «Outline» of the table of regions).
const SPEC_NO_OUTLINE: Array[int] = [18, 19, 20, 25, 28, 29]
## Regions a node may carry (table of regions: «Slot» column; 23–31 — bike only).
const NODE_REGIONS: Dictionary = {
	"Body": [0, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 21, 22],
	"Hair": [1, 18],
	"Helmet": [16, 17, 18],
	"Eyewear": [18, 19, 20],
	"ShoeL": [12, 13, 14, 15],
	"ShoeR": [12, 13, 14, 15],
	"Bike": [23, 24, 25, 26, 27, 28, 29, 30, 31],
	"FrontWheel": [23, 24, 25, 26, 27, 28, 29, 30, 31],
	"RearWheel": [23, 24, 25, 26, 27, 28, 29, 30, 31],
	"CrankArm": [23, 24, 25, 26, 27, 28, 29, 30, 31],
}
## Bones a region of the body may sit on (anatomy of the region).
const REGION_BONES: Dictionary = {
	8: ["pelvis", "spine", "thigh.L", "thigh.R"], # shorts
	9: ["thigh.L", "thigh.R"], # shorts gripper
	10: ["shin.L", "shin.R", "foot.L", "foot.R"], # socks
	21: ["hand.L", "hand.R"], # glove
	22: ["hand.L", "hand.R"], # glove palm
}
const NOT_JERSEY_BONES: Array[String] = ["head", "thigh.L", "thigh.R", "shin.L", "shin.R", "foot.L", "foot.R", "hand.L", "hand.R"]
## Scene budget measured on the pre-task base 3ddb4bb (PerfBudget.count): unique materials per
## track; the task must not add materials (card «Criteria auto»).
const MATERIALS_BEFORE: Dictionary = {"flat": 5, "hills": 5, "mountains": 5, "seaside": 6}
## Slot → palette regions it may change (slot table «What it changes», pattern table, region 31).
const JERSEY_SLOT_REGIONS: Dictionary = {
	"jersey.pattern": [3, 4, 5, 6, 7],
	"jersey.main": [2, 3, 4, 5, 6, 7],
	"jersey.accent1": [3, 4, 5, 6, 7],
	"jersey.accent2": [3, 4, 5, 6, 7, 31],
}


func _rider() -> Rider:
	var r: Rider = (load(RIDER_SCENE) as PackedScene).instantiate()
	add_child_autofree(r)
	return r


func _scene(track: String) -> RideScene:
	var s: RideScene = (load(RIDE_SCENE) as PackedScene).instantiate()
	s.route_id = track
	add_child_autofree(s)
	return s


static func _region(uv: Vector2) -> int:
	return int(floor(uv.x * 32.0))


static func _dist(a: Color, b: Color) -> float:
	return maxf(maxf(absf(a.r - b.r), absf(a.g - b.g)), absf(a.b - b.b))


func _node(r: Rider, name: String) -> MeshInstance3D:
	return r.find_child(name, true, false) as MeshInstance3D


## All mesh variants a node can show (current mesh plus swaps of figure, hair and rims).
func _variants(r: Rider) -> Dictionary:
	var out: Dictionary = {}
	for name in NODE_REGIONS:
		out[name] = [_node(r, name).mesh]
	r.set_figure("f")
	r.set_hair_style("tail")
	r.set_rims("shallow")
	for name in ["Body", "Hair", "FrontWheel", "RearWheel"]:
		(out[name] as Array).append(_node(r, name).mesh)
	r.set_figure("m")
	r.set_hair_style("short")
	r.set_rims("deep")
	return out


# --- p.1 regions in UV0 ---

## Card «Criteria auto»: every face of the mannequin and the bike lies inside one column with a
## 10 % margin: U of all three vertices in [(k + 0.1)/32; (k + 0.9)/32] of one k; V in [0; 1].
## No vertex colors on rider and bike meshes.
func test_p1_every_face_in_one_column_with_margin_raw_uv() -> void:
	var r := _rider()
	var vars := _variants(r)
	for name in vars:
		for mesh in vars[name]:
			var arr: Array = (mesh as Mesh).surface_get_arrays(0)
			var uv: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
			var bad: int = 0
			var first: String = ""
			for t in range(0, idx.size(), 3):
				var k: int = _region(uv[idx[t]])
				for j in 3:
					var p: Vector2 = uv[idx[t + j]]
					var lo: float = (float(k) + 0.1) / 32.0
					var hi: float = (float(k) + 0.9) / 32.0
					if p.x < lo - 1e-6 or p.x > hi + 1e-6 or p.y < -1e-6 or p.y > 1.0 + 1e-6:
						bad += 1
						if first.is_empty():
							first = "face %d uv %s (column %d)" % [t / 3, p, k]
						break
			assert_eq(bad, 0, "%s (%s): faces outside one column with margin; first %s" % [name, (mesh as Mesh).resource_name, first])
			var col: Variant = arr[Mesh.ARRAY_COLOR]
			assert_true(col == null or (col as PackedColorArray).is_empty(), "%s: no COLOR_0 in the mesh" % name)


## Regions belong to the right node (table of regions «Slot»), and anatomical regions sit on the
## right bones: shorts on pelvis/thighs, socks on shins/feet, gloves on hands, jersey not on legs,
## head or hands. Regions the spec makes addressable on the mannequin are present: skin, hair,
## jersey main and pattern regions, shorts, socks, shoe, helmet main and accent, lens; the bike
## carries all of 23–31.
func test_p1_regions_on_the_right_nodes_and_bones() -> void:
	var r := _rider()
	var skel := r.skeleton()
	var vars := _variants(r)
	var present: Dictionary = {}
	for name in vars:
		for mesh in vars[name]:
			var arr: Array = (mesh as Mesh).surface_get_arrays(0)
			var uv: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
			var bones: Variant = arr[Mesh.ARRAY_BONES]
			var skinned: bool = _node(r, name).get_parent() is Skeleton3D
			var wrong_node: Dictionary = {}
			var wrong_bone: Dictionary = {}
			for i in uv.size():
				var k: int = _region(uv[i])
				present[k] = true
				if not (NODE_REGIONS[name] as Array).has(k):
					wrong_node[k] = true
				if skinned and name == "Body":
					var b: String = skel.get_bone_name((bones as PackedInt32Array)[i * 4])
					if REGION_BONES.has(k) and not (REGION_BONES[k] as Array).has(b):
						wrong_bone["%d@%s" % [k, b]] = true
					if k >= 2 and k <= 7 and NOT_JERSEY_BONES.has(b):
						wrong_bone["%d@%s" % [k, b]] = true
			assert_eq(wrong_node.size(), 0, "%s: regions of other nodes %s" % [name, wrong_node.keys()])
			assert_eq(wrong_bone.size(), 0, "%s: regions on wrong bones %s" % [name, wrong_bone.keys()])
	for k in [0, 1, 2, 3, 4, 5, 6, 8, 9, 10, 12, 14, 15, 16, 17, 18, 19, 21, 23, 24, 25, 26, 27, 28, 29, 30, 31]:
		assert_true(present.has(k), "region %d is on the model" % k)
	var missing: Array = []
	for k in 32:
		if not present.has(k):
			missing.append(k)
	gut.p("regions of the table not on the mannequin/bike: %s" % [missing])


## Tyre outside the rim on both rim variants (tyre region 27 at the largest radius, rim 28 inside).
func test_p1_tyre_outside_rim_on_both_rim_variants() -> void:
	var r := _rider()
	for rims in ["deep", "shallow"]:
		r.set_rims(rims)
		for name in ["FrontWheel", "RearWheel"]:
			var arr: Array = _node(r, name).mesh.surface_get_arrays(0)
			var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var uv: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
			var tyre_max: float = 0.0
			var rim_max: float = 0.0
			var rim_min: float = INF
			for i in v.size():
				var rad: float = Vector2(v[i].y, v[i].z).length()
				match _region(uv[i]):
					27:
						tyre_max = maxf(tyre_max, rad)
					28:
						rim_max = maxf(rim_max, rad)
						rim_min = minf(rim_min, rad)
			assert_gt(tyre_max, rim_max, "%s %s: tyre outside the rim" % [name, rims])
			gut.p("%s %s: rim radial depth %.1f mm" % [name, rims, (rim_max - rim_min) * 1000.0])


# --- p.2 one material, palette, outline weight ---

## Default appearance = `classic`: the live material of a fresh rider reads the spec colors of
## every region 0–31 and the `smoke` highlight (REQ-D3D-09 p.6: a region part reads from the
## palette and equals its slot color; AVT-02 p.1 for the default look).
func test_p2_default_palette_equals_spec_classic() -> void:
	var r := _rider()
	var mat := _node(r, "Body").get_active_material(0) as ShaderMaterial
	assert_not_null(mat, "rider material is a ShaderMaterial")
	var pal: PackedColorArray = RiderPalette.palette_of(mat)
	assert_eq(pal.size(), 32, "32 palette entries")
	for k in mini(pal.size(), 32):
		assert_lt(_dist(pal[k], SPEC_CLASSIC[k]), 1e-3, "region %d: %s vs spec %s" % [k, pal[k], SPEC_CLASSIC[k]])
	assert_lt(_dist(RiderPalette.lens_highlight_of(mat), SPEC_SMOKE_HIGHLIGHT), 1e-3, "lens highlight smoke")


## One material on all 10 nodes in every track scene, outline is its `next_pass` with the region
## weights of the spec; 0 textures in both passes; the rider adds no lights.
func test_p2_one_material_outline_weights_on_every_track() -> void:
	for track in TRACKS:
		var s := _scene(track)
		var r := s.rider()
		var mats: Dictionary = {}
		var nodes: int = 0
		for mi in r.find_children("*", "MeshInstance3D", true, false):
			nodes += 1
			for i in (mi as MeshInstance3D).mesh.get_surface_count():
				mats[(mi as MeshInstance3D).get_active_material(i)] = true
		assert_eq(nodes, 10, "%s: rider MeshInstance3D = 10" % track)
		assert_eq(mats.size(), 1, "%s: one rider material" % track)
		assert_eq(r.find_children("*", "Light3D", true, false).size(), 0, "%s: the rider adds no lights" % track)
		var mat := mats.keys()[0] as ShaderMaterial
		var outline := mat.next_pass as ShaderMaterial
		assert_not_null(outline, "%s: outline next_pass" % track)
		if outline == null:
			continue
		var w: PackedFloat32Array = outline.get_shader_parameter("region_outline")
		assert_eq(w.size(), 32, "%s: 32 outline weights" % track)
		for k in mini(w.size(), 32):
			assert_eq(w[k], 0.0 if SPEC_NO_OUTLINE.has(k) else 1.0, "%s: outline weight of region %d" % [track, k])
		for m_pass in [mat, outline]:
			for u in (m_pass as ShaderMaterial).shader.get_shader_uniform_list():
				assert_ne(int(u["type"]), TYPE_OBJECT, "%s: no texture uniform %s" % [track, u["name"]])


## Palette writes stay per rider and survive mesh swaps: a write on one rider does not change
## another rider or the shared material; after swapping figure, hair and rims the swapped nodes
## keep the written palette (same single material), node instances are the same, node count stays.
func test_p2_palette_write_isolated_and_kept_across_mesh_swaps() -> void:
	var a := _rider()
	var b := _rider()
	var ids: Dictionary = {}
	for mi in a.find_children("*", "MeshInstance3D", true, false):
		ids[mi.name] = mi.get_instance_id()
	a.set_region_color(2, BLACK)
	a.set_figure("f")
	a.set_hair_style("tail")
	a.set_rims("shallow")
	a.set_region_color(16, RED)
	var mats: Dictionary = {}
	for mi in a.find_children("*", "MeshInstance3D", true, false):
		assert_eq(mi.get_instance_id(), ids.get(mi.name, -1), "%s: same node instance" % mi.name)
		mats[(mi as MeshInstance3D).get_active_material(0)] = true
	assert_eq(ids.size(), 10, "10 nodes")
	assert_eq(mats.size(), 1, "one material after writes and swaps")
	var pa: PackedColorArray = RiderPalette.palette_of(mats.keys()[0] as ShaderMaterial)
	assert_lt(_dist(pa[2], BLACK), 1e-4, "written jersey kept after the figure swap")
	assert_lt(_dist(pa[16], RED), 1e-4, "written helmet main")
	var pb: PackedColorArray = RiderPalette.palette_of(_node(b, "Body").get_active_material(0) as ShaderMaterial)
	assert_lt(_dist(pb[2], WHITE), 1e-4, "the other rider keeps its jersey")
	assert_lt(_dist(RiderPalette.palette_of(Rider.RIDER_MATERIAL)[2], WHITE), 1e-4, "shared material untouched")
	var w: PackedFloat32Array = ((mats.keys()[0] as ShaderMaterial).next_pass as ShaderMaterial).get_shader_parameter("region_outline")
	for k in 32:
		assert_eq(w[k], 0.0 if SPEC_NO_OUTLINE.has(k) else 1.0, "own copy: outline weight of region %d" % k)


## AVT-02 p.3 mechanism: 20 palette writes in one ride scene keep the node
## instances, the rider MeshInstance3D count and the unique materials of the scene; scene budgets
## of D3D-05 p.4 hold and materials are not more than before the task (base 3ddb4bb).
func test_p2_twenty_palette_writes_keep_scene_budget() -> void:
	for track in TRACKS:
		var s := _scene(track)
		var before: Dictionary = PerfBudget.count(s)
		assert_lte(int(before["materials"]), int(MATERIALS_BEFORE[track]), "%s: materials not more than before T-106a3" % track)
		assert_lte(int(before["mesh_instances"]), 60, "%s: MeshInstance3D ≤ 60" % track)
		assert_lte(int(before["lights"]), 3, "%s: lights ≤ 3" % track)
		var r := s.rider()
		var ids: Array[int] = []
		for mi in r.find_children("*", "MeshInstance3D", true, false):
			ids.append(mi.get_instance_id())
		for i in 20:
			var pal := PackedColorArray(SPEC_CLASSIC)
			pal[2] = Color.from_hsv(float(i) / 20.0, 0.8, 0.6)
			pal[16] = Color.from_hsv(float(i) / 20.0 + 0.5, 0.7, 0.9)
			r.set_palette(pal, SPEC_SMOKE_HIGHLIGHT)
			var c: Dictionary = PerfBudget.count(s)
			assert_eq(int(c["materials"]), int(before["materials"]), "%s write %d: unique materials unchanged" % [track, i])
			assert_eq(int(c["mesh_instances"]), int(before["mesh_instances"]), "%s write %d: MeshInstance3D unchanged" % [track, i])
		var after: Array[int] = []
		for mi in r.find_children("*", "MeshInstance3D", true, false):
			after.append(mi.get_instance_id())
		assert_eq(after, ids, "%s: same rider nodes after 20 writes" % track)
		gut.p("%s: MeshInstance3D %d, materials %d (before T-106a3: %d), lights %d" % [track, int(before["mesh_instances"]),
			int(before["materials"]), int(MATERIALS_BEFORE[track]), int(before["lights"])])


## Jersey patterns by slot (AVT-02 p.2 mechanism): changing one jersey slot changes only the
## regions that slot drives (slot table «What it changes», pattern table, bottle = accent2).
func test_p2_jersey_slot_change_touches_only_its_regions() -> void:
	var base_vals := {"jersey.pattern": "side_panels", "jersey.main": WHITE, "jersey.accent1": RED, "jersey.accent2": BLUE}
	var base: PackedColorArray = RiderPalette.with_jersey(PackedColorArray(SPEC_CLASSIC), base_vals)
	for k in 32:
		assert_lt(_dist(base[k], SPEC_CLASSIC[k]), 1e-4, "classic jersey slots reproduce the classic palette: region %d" % k)
	var changes := {
		"jersey.pattern": ["solid", "chest_band", "shoulder_yoke"],
		"jersey.main": [Color(0.1, 0.62, 0.66)],
		"jersey.accent1": [Color(0.48, 0.26, 0.66)],
		"jersey.accent2": [Color(0.62, 0.82, 0.2)],
	}
	for slot in changes:
		for value in changes[slot]:
			var vals := base_vals.duplicate()
			vals[slot] = value
			var pal: PackedColorArray = RiderPalette.with_jersey(PackedColorArray(SPEC_CLASSIC), vals)
			for k in 32:
				if not (JERSEY_SLOT_REGIONS[slot] as Array).has(k):
					assert_eq(pal[k], base[k], "%s = %s: region %d unchanged" % [slot, value, k])


# --- helmet rule mechanism (p.20 on the mannequin) ---

## Helmet rule (spec rev. 4.6): main color (16) ≥ 1/2 of the shell, accent (17) ≤ 1/4; dark
## (accent + inner 18) ≤ 1/2 — by area of the helmet mesh.
func test_helmet_main_at_least_half_of_shell() -> void:
	var r := _rider()
	var arr: Array = _node(r, "Helmet").mesh.surface_get_arrays(0)
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var uv: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var area := {16: 0.0, 17: 0.0, 18: 0.0}
	for t in range(0, idx.size(), 3):
		var k: int = _region(uv[idx[t]])
		if area.has(k):
			area[k] += (v[idx[t + 1]] - v[idx[t]]).cross(v[idx[t + 2]] - v[idx[t]]).length() * 0.5
	var total: float = area[16] + area[17] + area[18]
	gut.p("helmet area: main %.4f, accent %.4f, inner %.4f m²" % [area[16], area[17], area[18]])
	assert_gte(area[16] / total, 0.5, "main ≥ 1/2 of the helmet")
	assert_lte(area[17] / total, 0.25, "accent ≤ 1/4")
	assert_lte((area[17] + area[18]) / total, 0.5, "dark ≤ 1/2")


# --- p.4 shadow ---

## Spec «Rider shadow»: soft filter ≥ 1, sun split_1 ≤ 0.15 at max_distance 90 m on every
## track; hard style (no blur); every rider node casts a shadow, the ground does not.
func test_p4_shadow_settings_on_every_track() -> void:
	assert_gte(int(ProjectSettings.get_setting("rendering/lights_and_shadows/directional_shadow/soft_shadow_filter_quality", 0)), 1,
		"soft_shadow_filter_quality ≥ 1")
	gut.p("soft_shadow_filter_quality.mobile = %s" % [ProjectSettings.get_setting(
		"rendering/lights_and_shadows/directional_shadow/soft_shadow_filter_quality.mobile", "(unset)")])
	for track in TRACKS:
		var s := _scene(track)
		var sun := s.get_node("%Sun") as DirectionalLight3D
		assert_true(sun.shadow_enabled, "%s: sun casts shadows" % track)
		assert_almost_eq(sun.directional_shadow_max_distance, 90.0, 1e-3, "%s: max_distance 90 m" % track)
		assert_lte(sun.directional_shadow_split_1, 0.15 + 1e-6, "%s: split_1 ≤ 0.15" % track)
		assert_eq(sun.shadow_blur, 0.0, "%s: hard shadow style" % track)
		for mi in s.rider().find_children("*", "MeshInstance3D", true, false):
			assert_ne((mi as MeshInstance3D).cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "%s: %s casts a shadow" % [track, mi.name])


# --- p.5 budget ---

## Budget of the composition table: heaviest variant per node within its node limit; total of the
## heaviest variants ≤ 18 500; ≤ 10 MeshInstance3D; ≤ 28 bones; budget row in perf_budget.md.
func test_p5_budget_and_row() -> void:
	var limits := {"Body": 8000, "Hair": 800, "Helmet": 1600, "Eyewear": 400, "ShoeL": 600, "ShoeR": 600,
		"Bike": 2600, "FrontWheel": 1600, "RearWheel": 1600, "CrankArm": 600}
	var r := _rider()
	var vars := _variants(r)
	var total: int = 0
	for name in limits:
		var worst: int = 0
		for mesh in vars[name]:
			var n: int = 0
			for si in (mesh as Mesh).get_surface_count():
				n += ((mesh as Mesh).surface_get_arrays(si)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
			assert_lte(n, int(limits[name]), "%s: %d triangles" % [name, n])
			worst = maxi(worst, n)
		total += worst
	gut.p("heaviest variants: %d triangles" % total)
	assert_lte(total, 18500, "rider with bike ≤ 18 500 triangles")
	assert_lte(r.find_children("*", "MeshInstance3D", true, false).size(), 10, "≤ 10 MeshInstance3D")
	assert_lte(r.skeleton().get_bone_count(), 28, "≤ 28 bones")
	var doc: String = FileAccess.get_file_as_string("res://docs/perf_budget.md")
	assert_string_contains(doc, "≤ 18 500 треугольников (самые тяжёлые варианты), ≤ 10 `MeshInstance3D`, 1 материал, 0 текстур, ≤ 28 костей")
	assert_string_contains(doc, "MacBook Pro M1 Pro")
