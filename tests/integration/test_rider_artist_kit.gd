extends GutTest
## Эталонный пакет `assets/rider/reference/` (T-106a1, T-143; подготовка REQ-D3D-09 п.1, 2, 5, 6;
## бриф разделы 4–6, 10, 18; арт-библия
## «Гонщик» → «Слоты внешности», «Вариант Г»): файлы собирает сценарий
## (`scripts/rider_artist_kit.sh` → `scripts/dev/rider_reference_pack.gd`) из кода
## (`RiderRig`, `RiderModel`, `RiderRegions`, `RiderLook`) воспроизводимо побайтно и не
## устарели; атласы — по таблице регионов спеки и пресету `classic`; `bike_reference.glb`
## импортируется в Godot (`GLTFDocument`, как редактор), точки после круга «экспорт → импорт» —
## в ±1 мм, оси — как у экспорта Blender «+Y Up» из координат брифа; каталог не входит в
## сборку. Скелет `rider_rig_reference.glb` — `test_rider_rig_contract.gd`.

const RiderContract := preload("res://tests/fixtures/scene3d/rider_contract.gd")
const Pack := preload("res://scripts/dev/rider_reference_pack.gd")
const DIR: String = "res://assets/rider/reference"
const MM: float = 0.001

## Таблица регионов спеки (арт-библия «Слоты внешности»): код → [имя, вес контура].
const SPEC_REGIONS: Array = [
	["skin", 1], ["hair", 1], ["jersey_main", 1], ["jersey_side", 1], ["jersey_band", 1],
	["jersey_yoke", 1], ["jersey_cuff", 1], ["jersey_collar", 1], ["shorts_main", 1],
	["shorts_gripper", 1], ["socks_main", 1], ["socks_cuff", 1], ["shoe_main", 1], ["shoe_accent", 1],
	["shoe_sole", 1], ["cleat", 1], ["helmet_main", 1], ["helmet_accent", 1], ["helmet_inner", 0],
	["lens", 0], ["glasses_frame", 0], ["glove", 1], ["glove_palm", 1], ["frame_main", 1],
	["frame_accent", 1], ["rim_decal", 0], ["bar_tape", 1], ["tire", 1], ["rim_carbon", 0],
	["metal", 0], ["component", 1], ["bottle", 1],
]
## Цвет колонки атласа-превью (sRGB, тон 1.0) — пресет `classic` по таблицам спеки: палитра
## формы, кожа s3, волосы dark_brown, линза smoke, узор side_panels (main white, a1 red,
## a2 blue), фиксированные цвета регионов.
const SPEC_CLASSIC: Array = [
	Color(0.87, 0.64, 0.50), Color(0.24, 0.16, 0.11), Color(0.95, 0.95, 0.96), Color(0.86, 0.14, 0.16),
	Color(0.95, 0.95, 0.96), Color(0.95, 0.95, 0.96), Color(0.18, 0.28, 0.72), Color(0.18, 0.28, 0.72),
	Color(0.16, 0.18, 0.44), Color(0.09, 0.09, 0.10), Color(0.95, 0.95, 0.96), Color(0.95, 0.95, 0.96),
	Color(0.95, 0.95, 0.96), Color(0.09, 0.09, 0.10), Color(0.14, 0.14, 0.16), Color(0.82, 0.18, 0.16),
	Color(0.95, 0.95, 0.96), Color(0.09, 0.09, 0.10), Color(0.12, 0.12, 0.14), Color(0.18, 0.19, 0.22),
	Color(0.09, 0.09, 0.10), Color(0.09, 0.09, 0.10), Color(0.22, 0.22, 0.24), Color(0.86, 0.14, 0.16),
	Color(0.98, 0.82, 0.18), Color(0.98, 0.82, 0.18), Color(0.09, 0.09, 0.10), Color(0.10, 0.10, 0.11),
	Color(0.13, 0.13, 0.15), Color(0.70, 0.71, 0.74), Color(0.09, 0.09, 0.10), Color(0.18, 0.28, 0.72),
]
const SPEC_LENS_HIGHLIGHT := Color(0.42, 0.44, 0.50)
## Различимость колонок атласа-проверки, ΔE76 (CIELAB): любые две — не меньше, соседние —
## не меньше (промах острова на одну колонку виден сразу).
const ID_MIN_DE: float = 15.0
const ID_MIN_DE_ADJACENT: float = 40.0


func _path(file: String) -> String:
	return ProjectSettings.globalize_path(DIR.path_join(file))


func _import(file: String) -> Node:
	var holder := Node3D.new()
	add_child_autofree(holder)
	var scene: Node = RiderContract.import_glb(DIR.path_join(file), holder)
	assert_not_null(scene, "%s импортируется" % file)
	return scene


## Импорт Blender glTF (+Y Up): (x, y, z) → (x, −z, y) — `convert_swizzle_location`.
static func blender_from_gltf(g: Vector3) -> Vector3:
	return Vector3(g.x, -g.z, g.y)


static func _rgb_dist(a: Color, b: Color) -> float:
	return Vector3(a.r - b.r, a.g - b.g, a.b - b.b).length()


static func _lab_f(t: float) -> float:
	return pow(t, 1.0 / 3.0) if t > 0.008856 else 7.787 * t + 16.0 / 116.0


## sRGB → CIELAB (D65).
static func _lab(c: Color) -> Vector3:
	var l: Color = c.srgb_to_linear()
	var x: float = _lab_f((0.4124 * l.r + 0.3576 * l.g + 0.1805 * l.b) / 0.95047)
	var y: float = _lab_f(0.2126 * l.r + 0.7152 * l.g + 0.0722 * l.b)
	var z: float = _lab_f((0.0193 * l.r + 0.1192 * l.g + 0.9505 * l.b) / 1.08883)
	return Vector3(116.0 * y - 16.0, 500.0 * (x - y), 200.0 * (y - z))


# --- Воспроизводимость и состав ---

## Сценарий даёт те же байты при каждом запуске, и они совпадают с файлами в репозитории
## (пакет не устарел: после правки `RiderRig`/`RiderModel`/`RiderRegions`/`RiderLook` —
## `./scripts/rider_artist_kit.sh`).
func test_pack_reproducible_and_matches_committed_files() -> void:
	var first: Dictionary = Pack.new().build()
	var second: Dictionary = Pack.new().build()
	assert_eq(first.keys(), Array(Pack.FILES), "состав пакета")
	for name in Pack.FILES:
		var data: PackedByteArray = first[name]
		assert_gt(data.size(), 0, "%s собирается" % name)
		assert_true(data == second[name], "%s: два запуска — те же байты" % name)
		var committed: PackedByteArray = FileAccess.get_file_as_bytes(_path(name))
		assert_eq(committed.size(), data.size(), "%s: размер как у сценария — пересоберите пакет" % name)
		assert_true(committed == data, "%s: файл = вывод сценария побайтно — пересоберите пакет" % name)


## В glTF нет номера сборки движка: файл не меняется от патч-версии Godot.
func test_glb_generator_is_fixed() -> void:
	for name in ["bike_reference.glb", "rider_rig_reference.glb"]:
		var bytes: PackedByteArray = FileAccess.get_file_as_bytes(_path(name))
		var json: Dictionary = JSON.parse_string(bytes.slice(20, 20 + bytes.decode_u32(12)).get_string_from_utf8())
		assert_eq(json["asset"]["generator"], Pack.GENERATOR, name)
		assert_eq(json["asset"]["version"], "2.0", name)
		assert_false(json.has("extensionsRequired"), "%s: без обязательных расширений" % name)
		# Сетка названа как её объект (бриф 12; импорт Godot добавляет к имени сетки имя сцены).
		for node in json["nodes"]:
			if (node as Dictionary).has("mesh"):
				assert_eq(json["meshes"][int(node["mesh"])]["name"], node["name"], "%s: сетка %s" % [name, node["name"]])


func test_package_files_present_and_excluded_from_build() -> void:
	for f in Pack.FILES + ["README.md"]:
		assert_true(FileAccess.file_exists(_path(f)), f)
	assert_true(FileAccess.file_exists(_path(".gdignore")), "каталог не импортируется и не попадает в сборку")
	assert_false(ResourceLoader.exists(DIR.path_join("bike_reference.glb")), "редактор не видит .glb пакета")
	var total: int = 0
	for f in Pack.FILES:
		total += FileAccess.get_file_as_bytes(_path(f)).size()
	assert_lt(total, 1024 * 1024, "пакет меньше 1 МБ (%d байт)" % total)
	# Если появятся пресеты экспорта: фильтр «включить» не должен затянуть пакет.
	var presets := ConfigFile.new()
	if presets.load("res://export_presets.cfg") != OK:
		return
	for section in presets.get_sections():
		var include: String = str(presets.get_value(section, "include_filter", ""))
		var exclude: String = str(presets.get_value(section, "exclude_filter", ""))
		if not include.is_empty():
			assert_string_contains(exclude, "assets/rider/reference", "%s: пакет исключён из экспорта" % section)


# --- Атласы ---

func test_regions_table_matches_spec() -> void:
	assert_eq(RiderRegions.COUNT, SPEC_REGIONS.size())
	for k in RiderRegions.COUNT:
		assert_eq(RiderRegions.region_name(k), SPEC_REGIONS[k][0], "регион %d" % k)
		assert_eq(RiderRegions.outline_weight(k), float(SPEC_REGIONS[k][1]), "контур региона %d" % k)
	assert_eq(RiderRegions.LENS, 19)
	assert_eq(RiderRegions.FIRST_BIKE, 23)


## Цвета колонок превью — пресет `classic` `RiderLook` (T-108) через связь «регион → слот», и
## это числа спеки.
func test_classic_palette_from_rider_look_matches_spec() -> void:
	var look: RiderLook = RiderRegions.preview_look()
	assert_true(look.equals(RiderLook.default_look()), "превью — внешность по умолчанию")
	assert_eq(look.matching_preset(), RiderLook.PRESET_CLASSIC)
	var colors: Array[Color] = RiderRegions.palette(look)
	assert_eq(colors.size(), 32)
	for k in 32:
		assert_lt(_rgb_dist(colors[k], SPEC_CLASSIC[k]), 1e-6, "регион %d (%s)" % [k, SPEC_REGIONS[k][0]])
	assert_lt(_rgb_dist(RiderRegions.lens_highlight(look), SPEC_LENS_HIGHLIGHT), 1e-6, "блик линзы smoke")
	# Другая внешность меняет свои регионы: без перчаток 21, 22 — цвет кожи; узор кокетки.
	var bare: RiderLook = RiderLook.preset(RiderLook.PRESET_ALPINE)
	var c2: Array[Color] = RiderRegions.palette(bare)
	assert_eq(c2[21], RiderLook.SKIN_TONES["s5"])
	assert_eq(c2[22], RiderLook.SKIN_TONES["s5"])
	assert_eq(c2[3], RiderLook.form_color("navy"), "shoulder_yoke: бока = accent2")
	assert_eq(c2[31], RiderLook.form_color("navy"), "фляга = accent2")


func test_preview_atlas_columns_tone_and_lens() -> void:
	var img := Image.load_from_file(_path("rider_atlas_preview.png"))
	assert_eq(img.get_size(), Vector2i(1024, 256), "1024 × 256")
	assert_eq(RiderRegions.ATLAS_SIZE.x / RiderRegions.COLUMN_PX, 32, "32 колонки по 32 px")
	for k in 32:
		var x0: int = k * 32
		for y in [0, 100, 255]:
			assert_eq(img.get_pixel(x0, y), img.get_pixel(x0 + 31, y), "колонка %d однородна, строка %d" % [k, y])
		# Тон по V (Blender: 0 — низ): тон = 0.6 + 0.8·V, множитель в линейном пространстве.
		for y in [255, 191, 128, 64, 0]:
			var v: float = 1.0 - (float(y) + 0.5) / 256.0
			var base: Color = SPEC_CLASSIC[k]
			if k == 19 and v >= 0.75:
				base = SPEC_LENS_HIGHLIGHT
			var lin: Color = base.srgb_to_linear() * (0.6 + 0.8 * v)
			var want := Color(minf(lin.r, 1.0), minf(lin.g, 1.0), minf(lin.b, 1.0)).linear_to_srgb()
			assert_lt(_rgb_dist(img.get_pixel(x0 + 16, y), want), 2.0 / 255.0,
				"колонка %d (%s), V = %.2f" % [k, SPEC_REGIONS[k][0], v])
	assert_gt(img.get_pixel(16, 0).get_luminance(), img.get_pixel(16, 255).get_luminance(), "верх (тон 1.4) светлее низа (0.6)")
	assert_gt(img.get_pixel(19 * 32 + 16, 10).v, (SPEC_CLASSIC[19] as Color).v * 1.6, "у линзы вверху — блик")


func test_id_atlas_distinct_columns_with_numbers() -> void:
	var img := Image.load_from_file(_path("rider_atlas_id.png"))
	assert_eq(img.get_size(), Vector2i(1024, 256), "1024 × 256")
	var labs: Array[Vector3] = []
	var bands: Array[PackedByteArray] = []
	for k in 32:
		var x0: int = k * 32
		var bg: Color = img.get_pixel(x0 + 3, 50)
		assert_lt(_rgb_dist(bg, RiderRegions.id_color(k)), 2.0 / 255.0, "колонка %d — свой оттенок" % k)
		labs.append(_lab(bg))
		assert_lt(img.get_pixel(x0, 128).get_luminance(), 0.1, "колонка %d: тёмная линия границы" % k)
		# Номер колонки цифрами — три раза по высоте; маска цифр у колонок разная.
		for top in [16, 112, 208]:
			var mask := PackedByteArray()
			var ink: int = 0
			for y in range(top, top + 15):
				for x in range(x0 + 2, x0 + 31):
					var on: bool = _rgb_dist(img.get_pixel(x, y), bg) > 0.2
					mask.append(1 if on else 0)
					ink += 1 if on else 0
			assert_gt(ink, 20, "колонка %d: номер в строке %d" % [k, top])
			if top == 16:
				assert_false(bands.has(mask), "колонка %d: номер отличается от других" % k)
				bands.append(mask)
		# Колонки велосипеда (23–31) помечены крестом.
		var cross: bool = _rgb_dist(img.get_pixel(x0 + 6, 70), bg) > 0.2 and _rgb_dist(img.get_pixel(x0 + 25, 70), bg) > 0.2
		assert_eq(cross, k >= RiderRegions.FIRST_BIKE, "колонка %d: крест только у велосипеда" % k)
	var min_de: float = INF
	for a in 32:
		for b in range(a + 1, 32):
			min_de = minf(min_de, labs[a].distance_to(labs[b]))
		if a < 31:
			assert_gt(labs[a].distance_to(labs[a + 1]), ID_MIN_DE_ADJACENT, "соседи %d–%d различимы" % [a, a + 1])
	assert_gt(min_de, ID_MIN_DE, "32 различимых оттенка: наименьшее ΔE76 = %.1f" % min_de)


# --- bike_reference.glb ---

func test_bike_reference_points_axes_and_geometry() -> void:
	var scene := _import("bike_reference.glb")
	if scene == null:
		return
	for part in ["bike_frame", "saddle", "wheel_front", "wheel_rear", "crankset"]:
		var mi := scene.find_child(part, true, false) as MeshInstance3D
		assert_not_null(mi, part)
		if mi == null:
			continue
		assert_eq(mi.transform, Transform3D.IDENTITY, "%s: поворот и масштаб применены" % part)
		for s in mi.mesh.get_surface_count():
			var arr: Array = mi.mesh.surface_get_arrays(s)
			assert_true(arr[Mesh.ARRAY_COLOR] == null or (arr[Mesh.ARRAY_COLOR] as PackedColorArray).is_empty(),
				"%s: без цвета вершин" % part)
			assert_string_starts_with(String(mi.mesh.surface_get_material(s).resource_name), "M_bike_", "%s: материал" % part)
	var points: Dictionary = Pack.bike_points()
	for n in points:
		var node := scene.find_child(n, true, false) as Node3D
		assert_not_null(node, n)
		if node != null:
			assert_lt(RiderRig.from_gltf(node.global_position).distance_to(points[n]), MM, "%s ± 1 мм" % n)
	# Оси глазами Blender — числа брифа раздел 6.
	var want := {
		"pt_saddle_S": Vector3(0.0, RiderContract.BRIEF_SADDLE_S_Y, RiderContract.BRIEF_SADDLE_TOP_M),
		"pt_grip_L": RiderContract.BRIEF_GRIP_L, "pt_grip_R": RiderContract.BRIEF_GRIP_L * Vector3(-1, 1, 1),
		"pt_cleat_R_pedal_axis": RiderContract.BRIEF_CLEAT_R, "pt_bb": RiderContract.BRIEF_BB,
		"pt_axle_rear": RiderContract.BRIEF_REAR_AXLE, "pt_axle_front": RiderContract.BRIEF_FRONT_AXLE,
	}
	for n in want:
		var b: Vector3 = blender_from_gltf((scene.find_child(n, true, false) as Node3D).global_position)
		assert_lt(b.distance_to(want[n]), MM, "Blender: %s %s (бриф %s)" % [n, b, want[n]])
	# Геометрия после круга экспорт → импорт: верх седла под S и ручки.
	var frame := scene.find_child("bike_frame", true, false) as MeshInstance3D
	var saddle := scene.find_child("saddle", true, false) as MeshInstance3D
	var to_godot: Transform3D = RiderRig.gltf_flip()
	var s: Vector3 = RiderRig.head("pelvis")
	assert_almost_eq(RiderContract.top_at(saddle.mesh, s.x, s.z, to_godot), 0.965, 0.002, "верх седла под S в файле")
	assert_lt(RiderContract.top_at(frame.mesh, s.x, s.z, to_godot), 0.94, "седло вынесено из bike_frame (T-143)")
	for side in ["grip.L", "grip.R"]:
		var g: Vector3 = RiderRig.head(side)
		var hood: float = RiderContract.top_at(frame.mesh, g.x, g.z, to_godot)
		assert_almost_eq(hood + RiderModel.HOOD_PALM_CLEARANCE_M, g.y, 0.005, "%s в файле" % side)
	# Колёса 700c на своих осях: верх покрышки — ось + радиус 0.335 м.
	for part in ["wheel_front", "wheel_rear"]:
		var axle: Vector3 = RiderRig.FRONT_AXLE if part == "wheel_front" else RiderRig.REAR_AXLE
		var mi := scene.find_child(part, true, false) as MeshInstance3D
		assert_almost_eq(RiderContract.top_at(mi.mesh, 0.0, axle.z, to_godot), axle.y + RiderRig.WHEEL_RADIUS_M, 0.003, part)


func test_bike_reference_crank_at_rest_right_pedal_forward() -> void:
	var scene := _import("bike_reference.glb")
	if scene == null:
		return
	var crank := scene.find_child("crankset", true, false) as MeshInstance3D
	var cleat_r: Vector3 = RiderRig.head("cleat.R")
	var cleat_l := Vector3(-cleat_r.x, RiderRig.BB.y, -cleat_r.z)
	for target in [cleat_r, cleat_l]:
		var lo := Vector3(INF, INF, INF)
		var hi := Vector3(-INF, -INF, -INF)
		for si in crank.mesh.get_surface_count():
			for g in crank.mesh.surface_get_arrays(si)[Mesh.ARRAY_VERTEX] as PackedVector3Array:
				var p: Vector3 = RiderRig.from_gltf(g)
				if absf(p.z - target.z) < 0.06 and absf(p.y - target.y) < 0.03 and absf(p.x - target.x) < 0.03:
					lo = lo.min(p)
					hi = hi.max(p)
		assert_almost_eq((lo.x + hi.x) * 0.5, target.x, 0.003, "корпус педали на оси %s" % target)
		assert_between(target.y, lo.y, hi.y + 0.001, "педаль у оси %s" % target)
		assert_gt(hi.z - lo.z, 0.06, "контактная педаль — платформа %s" % target)
	assert_lt(cleat_r.z, 0.0, "правая педаль впереди (Godot −Z)")
	assert_almost_eq(Vector2(cleat_r.y - RiderRig.BB.y, cleat_r.z - RiderRig.BB.z).length(), RiderRig.CRANK_LENGTH_M, 1e-6, "шатун 0.17")


func test_rig_reference_has_armature_rider_rig_and_joint_markers() -> void:
	var scene := _import("rider_rig_reference.glb")
	if scene == null:
		return
	assert_eq(String(scene.name), Pack.RIG_NAME, "объект арматуры в Blender — rider_rig (бриф 12)")
	var markers := scene.find_children("*", "MeshInstance3D", true, false)
	assert_eq(markers.size(), 1, "одна сетка меток суставов")
	if markers.is_empty():
		return
	var mi := markers[0] as MeshInstance3D
	assert_eq(String(mi.name), "rig_joints")
	assert_eq(mi.mesh.get_surface_count(), 2, "метки суставов и сокетов")
	assert_eq(mi.skin.get_bind_count(), RiderRig.BONE_COUNT, "метка на каждую кость")


## T-143: седло — отдельный узел `saddle`, геометрия велосипеда та же, что в игре: рама + седло
## пакета = `bike_frame` из `RiderModel.reference_kits` (те же треугольники), игра узлы не меняет.
func test_bike_reference_saddle_split_keeps_geometry() -> void:
	var kits: Dictionary = RiderModel.reference_kits(RiderRig.REST_CRANK_RAD)
	var split: Dictionary = Pack.split_saddle(kits)
	assert_eq(split.keys(), ["bike_frame", "saddle", "wheel_front", "wheel_rear", "crankset"], "состав частей")
	var src: MeshKit = kits["bike_frame"]
	var frame: MeshKit = split["bike_frame"]
	var saddle: MeshKit = split["saddle"]
	assert_eq(frame.indices.size() + saddle.indices.size(), src.indices.size(), "треугольники рамы и седла — все треугольники рамы игры")
	assert_eq(frame.vertices.size() + saddle.vertices.size(), src.vertices.size(), "вершины не теряются и не дублируются")
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	for p in saddle.vertices:
		lo = lo.min(p)
		hi = hi.max(p)
	var s: Vector3 = RiderRig.head("pelvis")
	assert_almost_eq(hi.z - lo.z, RiderRig.SADDLE_LENGTH_M, 0.003, "седло: длина")
	assert_almost_eq(hi.x - lo.x, RiderRig.SADDLE_REAR_WIDTH_M, 0.003, "седло: ширина сзади")
	assert_between(hi.y, s.y, s.y + 0.01, "седло: верх у S")
	assert_gt(lo.y, s.y - 0.05, "в узле только седло (без штыря и рамок)")
