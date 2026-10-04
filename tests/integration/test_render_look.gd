extends GutTest
## T-102: одинаковая картинка мира в Forward+/Mobile и Compatibility (REQ-D3D-07 п.6, 7), подъём в
## горах читается (REQ-D3D-08 п.8, решение game-designer 14), бюджет (REQ-D3D-05); T-100 — кэш
## `RouteWorld` очищается (REQ-INF-01 п.2, 5).
##
## Пиксели рендера headless не проверить — здесь контракт: узлы мира получают окружающий
## свет и туман своей сцены параметрами экземпляра (`RenderLook.apply`, T-112: две сцены разных
## трасс одновременно, общие материалы не меняются), шейдеры выравнивают свет, цвет вершин и небо по
## `CURRENT_RENDERER`, шумы гаснут по размеру пикселя на земле по обеим осям, тень солнца — с
## нормальным смещением против «угрей» в Forward+/Mobile. Средние цвета по рендерерам — снимки
## `docs/game/shots/2026-10-04-t102/` (отчёт T-102), сцена после сцены другой трассы —
## `docs/game/shots/2026-10-04-t112/` (T-112).

const SCENE: String = "res://src/scene3d/ride_scene.tscn"
const FRAME: float = 1.0 / 60.0
const IDS: Array[String] = [RouteCatalog.FLAT, RouteCatalog.HILLS, RouteCatalog.MOUNTAINS, RouteCatalog.SEASIDE]
const SHOT: Vector2 = Vector2(1280.0, 720.0)

var _scenes: Dictionary = {}


func before_all() -> void:
	for id in IDS:
		var s: RideScene = load(SCENE).instantiate()
		s.route_id = id
		add_child(s)
		_scenes[id] = s


func after_all() -> void:
	for id in _scenes:
		var s: RideScene = _scenes[id]
		if is_instance_valid(s):
			s.free()
	_scenes.clear()
	RouteWorld.clear_cache()


func _drive_to(s: RideScene, at_m: float, kmh: float) -> void:
	s.distance_m = maxf(at_m - kmh / 3.6 * 2.0, 0.0)
	s.apply_telemetry(0, false, 90, true, kmh, true)
	for i in 120:
		s.advance(FRAME)


func _code(path: String) -> String:
	return FileAccess.get_file_as_string(path)


# ---------------------------------------------------------------------------
# Свет и цвет под рендерер
# ---------------------------------------------------------------------------

func _assert_look(gi: GeometryInstance3D, e: EnvironmentSet, label: String) -> void:
	var a: Variant = gi.get_instance_shader_parameter(RenderLook.AMBIENT_PARAM)
	var f: Variant = gi.get_instance_shader_parameter(RenderLook.FOG_PARAM)
	assert_true(a is Vector3 and (a as Vector3).is_equal_approx(RenderLook.ambient_of(e)), "%s %s: окружающий свет %s" % [label, gi.name, a])
	assert_true(f is Vector4 and (f as Vector4).is_equal_approx(RenderLook.fog_of(e)), "%s %s: туман %s" % [label, gi.name, f])


func test_look_values_are_linear_ambient_and_fog_of_environment() -> void:
	assert_true(RenderLook.uses_instance_look(), "headless-прогон — рендерер проекта (Forward+): параметры вида задаются")
	var e: EnvironmentSet = (_scenes[RouteCatalog.MOUNTAINS] as RideScene).environment_set
	var amb: Color = e.ambient_color.srgb_to_linear() * e.ambient_energy
	var fog: Color = e.fog_color.srgb_to_linear()
	assert_true(RenderLook.ambient_of(e).is_equal_approx(Vector3(amb.r, amb.g, amb.b)), "окружающий свет: линейный цвет × энергия")
	assert_true(RenderLook.fog_of(e).is_equal_approx(Vector4(fog.r, fog.g, fog.b, e.fog_density)), "туман: линейный цвет и плотность")


## T-112: все четыре сцены живут одновременно — у узлов каждой свет и туман своей трассы, а не
## последней построенной; общие материалы (тун, контур, асфальт, велосипедист) одни на процесс
## и параметров вида не несут.
func test_each_scene_gets_own_ambient_and_fog_while_all_alive() -> void:
	var shaders: Dictionary = {}
	for id in IDS:
		var s: RideScene = _scenes[id]
		var look: Array[GeometryInstance3D] = RenderLook.instances_under(s)
		assert_gt(look.size(), 10, "%s: узлы мира с выравниванием" % id)
		for gi in look:
			_assert_look(gi, s.environment_set, id)
		for m in RenderLook.materials_under(s):
			shaders[m.shader.resource_path.get_file()] = true
			assert_null(m.get_shader_parameter(RenderLook.AMBIENT_PARAM), "%s %s: в материале нет окружающего света сцены" % [id, m.shader.resource_path])
			assert_null(m.get_shader_parameter(RenderLook.FOG_PARAM), "%s %s: в материале нет тумана сцены" % [id, m.shader.resource_path])
	for need in ["toon.gdshader", "grass.gdshader", "road.gdshader", "outline.gdshader", "water.gdshader"]:
		assert_true(shaders.has(need), "%s среди материалов мира с выравниванием" % need)
	var flat_road: Material = (_scenes[RouteCatalog.FLAT] as RideScene).road().material_override
	var hills_road: Material = (_scenes[RouteCatalog.HILLS] as RideScene).road().material_override
	if flat_road != null and hills_road != null:
		assert_same(flat_road, hills_road, "асфальт — общий материал на процесс (копий нет)")


## Значения доходят до сервера рендера: параметр экземпляра у RID узла, а не у материала.
func test_look_values_reach_rendering_server_per_instance() -> void:
	for id in [RouteCatalog.FLAT, RouteCatalog.MOUNTAINS]:
		var s: RideScene = _scenes[id]
		var gi: GeometryInstance3D = s.road()
		var a: Variant = RenderingServer.instance_geometry_get_shader_parameter(gi.get_instance(), RenderLook.AMBIENT_PARAM)
		assert_true(a is Vector3 and (a as Vector3).is_equal_approx(RenderLook.ambient_of(s.environment_set)), "%s: окружающий свет у экземпляра дороги в RenderingServer (%s)" % [id, a])
	assert_ne(RenderLook.ambient_of((_scenes[RouteCatalog.FLAT] as RideScene).environment_set),
		RenderLook.ambient_of((_scenes[RouteCatalog.MOUNTAINS] as RideScene).environment_set), "предусловие: у равнины и гор разный окружающий свет")


func test_rider_materials_are_aligned_too() -> void:
	for id in [RouteCatalog.FLAT, RouteCatalog.SEASIDE]:
		var s: RideScene = _scenes[id]
		var rider_mats: Array[ShaderMaterial] = RenderLook.materials_under(s.rider())
		assert_gt(rider_mats.size(), 0, "у велосипедиста тун-материалы")
		var parts: Array[GeometryInstance3D] = RenderLook.instances_under(s.rider())
		assert_gt(parts.size(), 0, "части велосипедиста с выравниванием")
		for gi in parts:
			_assert_look(gi, s.environment_set, "%s велосипедист" % id)


## Параметры экземпляра — в глобальном буфере Forward+/Mobile (4096 узлов на процесс): на сцену
## не больше `PerfBudget.MAX_LOOK_INSTANCES`, документ бюджета совпадает с константой.
func test_look_instances_per_scene_in_budget() -> void:
	var re := RegEx.create_from_string("\\|[^|]*параметрами экземпляра[^|]*\\| *(\\d+) *\\|")
	var m := re.search(FileAccess.get_file_as_string("res://docs/perf_budget.md"))
	assert_not_null(m, "строка бюджета узлов с параметрами экземпляра")
	if m != null:
		assert_eq(int(m.get_string(1)), PerfBudget.MAX_LOOK_INSTANCES)
	assert_lte(PerfBudget.MAX_LOOK_INSTANCES * 3, 4096, "два экрана и пересборка одного — в буфере 65536 / 16 слотов")
	for id in IDS:
		var n: int = RenderLook.instances_under(_scenes[id]).size()
		gut.p("%s: узлов с параметрами экземпляра %d" % [id, n])
		assert_lte(n, PerfBudget.MAX_LOOK_INSTANCES, "%s: узлов с параметрами экземпляра" % id)
		assert_lte(int(PerfBudget.count(_scenes[id])["materials"]), PerfBudget.MAX_MATERIALS, "%s: уникальных материалов в бюджете" % id)


func test_shaders_branch_by_renderer_and_compatibility_stays_reference() -> void:
	var inc: String = _code("res://src/scene3d/shaders/render_look.gdshaderinc")
	assert_string_contains(inc, "#if CURRENT_RENDERER == RENDERER_COMPATIBILITY", "ветвление по рендереру")
	assert_string_contains(inc, "vec3 look_diffuse(", "солнце — как сложение проходов в sRGB")
	assert_string_contains(inc, "vec3 look_vertex_color(", "цвет вершин — из sRGB")
	var branch: int = inc.find("#if CURRENT_RENDERER != RENDERER_COMPATIBILITY")
	var decl: int = inc.find("instance uniform vec3 look_ambient : instance_index(0)")
	assert_true(branch >= 0 and decl > branch and inc.find("#endif", branch) > decl,
		"окружающий свет — параметр экземпляра только в Forward+/Mobile (Compatibility его не читает)")
	assert_string_contains(inc, "instance uniform vec4 look_fog : instance_index(1)", "туман — параметр экземпляра")
	assert_string_contains(_code("res://src/scene3d/render_look.gd"), "get_current_rendering_method() != \"gl_compatibility\"",
		"в Compatibility параметры вида не задаются: буфер параметров экземпляра там мал (UBO)")
	assert_false(inc.contains("\nuniform vec3 look_ambient"), "не параметр материала: общий материал не несёт окружение сцены")
	var toon_light: String = _code("res://src/scene3d/shaders/toon_light.gdshaderinc")
	assert_string_contains(toon_light, "look_diffuse(", "тун-свет через выравнивание")
	for path in ["res://src/scene3d/shaders/toon.gdshader", "res://src/scene3d/shaders/grass.gdshader",
			"res://src/scene3d/shaders/outline.gdshader", "res://src/scene3d/props/shaders/prop_anim.gdshader",
			"res://src/scene3d/props/shaders/prop_anim_outline.gdshader"]:
		var code: String = _code(path)
		assert_string_contains(code, "look_vertex_color(COLOR.rgb)", "%s: цвет вершин через выравнивание" % path)
	assert_string_contains(_code("res://src/scene3d/shaders/water.gdshader"), "look_diffuse(", "вода")
	var sky: String = _code("res://src/scene3d/shaders/sky.gdshader")
	assert_string_contains(sky, "#if CURRENT_RENDERER == RENDERER_COMPATIBILITY", "небо смешивается в sRGB во всех рендерерах")
	assert_string_contains(sky, "COLOR = from_look(col);")


func test_ground_noise_fades_by_pixel_footprint_on_both_axes() -> void:
	for path in ["res://src/scene3d/shaders/road.gdshader", "res://src/scene3d/shaders/grass.gdshader"]:
		var code: String = _code(path)
		assert_string_contains(code, "max(max(fwidth(p.x), fwidth(p.y)), 1e-4)", "%s: размер пикселя на земле по худшей оси" % path)
	assert_string_contains(_code("res://src/scene3d/shaders/grass.gdshader"), "max(max(fwidth(q.x), fwidth(q.y)), 1e-4)",
		"борозды полей гаснут по обеим осям участка")


func test_sun_shadow_has_normal_bias_against_acne() -> void:
	var s: RideScene = _scenes[RouteCatalog.FLAT]
	var sun: DirectionalLight3D = s.get_node("%Sun")
	assert_true(sun.shadow_enabled, "тени остаются")
	assert_gte(sun.shadow_normal_bias, 4.0, "нормальное смещение тени: без «угрей» на земле, бордюре и кронах в Forward+/Mobile")
	assert_lte(sun.shadow_bias, 0.1, "постоянное смещение мало — тень не отрывается от столбиков")
	for id in IDS:
		var e: EnvironmentSet = (_scenes[id] as RideScene).environment_set
		assert_almost_eq((_scenes[id] as RideScene).get_node("%Sun").light_energy, e.sun_energy, 1e-5,"%s: энергия солнца — из набора окружения (выравнивание — в шейдере)" % id)


# ---------------------------------------------------------------------------
# Подъём в горах (решение game-designer 14)
# ---------------------------------------------------------------------------

func test_near_rise_threshold_is_environment_parameter() -> void:
	for id in IDS:
		var e: EnvironmentSet = (_scenes[id] as RideScene).environment_set
		var want: float = 30.0 if id == RouteCatalog.MOUNTAINS else 20.0
		assert_eq(e.terrain_near_rise_max_m, want, "%s: порог перепада рельефа в 40 м от дороги" % id)
	assert_eq(EnvironmentSet.new().terrain_near_rise_max_m, 20.0, "по умолчанию — 20 м (T-070)")
	var m: EnvironmentSet = (_scenes[RouteCatalog.MOUNTAINS] as RideScene).environment_set
	assert_gt(m.cut_bank_m, 0.0, "горы: откос со стороны склона")
	assert_eq(EnvironmentSet.new().cut_bank_m, 0.0, "по умолчанию откоса нет")


func test_mountains_cut_bank_rises_on_uphill_side_road_stays_clear() -> void:
	var s: RideScene = _scenes[RouteCatalog.MOUNTAINS]
	var tf: TerrainField = s.terrain()
	var e: EnvironmentSet = s.environment_set
	var sample := TrackSample.new()
	var raised: int = 0
	var n: int = 0
	var above: Array[String] = []
	var at: float = 3500.0
	while at < 9500.0:
		s.track.sample_into(at, sample)
		var r: Vector3 = sample.right()
		var hl: float = tf.height_at(sample.position.x - r.x * 60.0, sample.position.z - r.z * 60.0)
		var hr: float = tf.height_at(sample.position.x + r.x * 60.0, sample.position.z + r.z * 60.0)
		var up: float = 1.0 if hr > hl else -1.0
		var p: Vector3 = sample.position + r * up * 40.0
		if tf.height_at(p.x, p.z) - sample.position.y > e.cut_bank_m * 0.6:
			raised += 1
		n += 1
		for off in [-6.0, -3.0, 0.0, 3.0, 6.0]:
			var q: Vector3 = sample.position + r * (e.road_center_offset_m + off)
			if tf.height_at(q.x, q.z) > sample.position.y - 0.02:
				above.append("s=%.0f off=%+.0f" % [at, off])
		at += 100.0
	assert_gt(float(raised) / float(n), 0.8, "на подъёме со стороны склона в 40 м земля выше полотна (%d из %d)" % [raised, n])
	assert_eq(above, [] as Array[String], "полотно не закрыто откосом")


## Верх земли (ближе `max_m`) над гонщиком в кадре 1280×720, доля высоты кадра: лучи из камеры
## по столбцам половины кадра со стороны склона.
func _ground_above_rider(s: RideScene, uphill_right: bool, max_m: float) -> float:
	var cam: Camera3D = s.camera()
	var vp: Vector2 = cam.get_viewport().get_visible_rect().size
	var to_vp: Vector2 = vp / SHOT
	var top_y: float = SHOT.y
	for node in s.rider().find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		var box: AABB = mi.global_transform * mi.get_aabb()
		for k in 8:
			top_y = minf(top_y, (cam.unproject_position(box.get_endpoint(k)) / to_vp).y)
	var tf: TerrainField = s.terrain()
	var best: float = SHOT.y
	var x: float = 672.0 if uphill_right else 16.0
	while x < (SHOT.x if uphill_right else 640.0):
		var y: float = 0.0
		while y < top_y:
			var o: Vector3 = cam.project_ray_origin(Vector2(x, y) * to_vp)
			var d: Vector3 = cam.project_ray_normal(Vector2(x, y) * to_vp)
			var t: float = 1.0
			var hit: bool = false
			while t < max_m:
				var q: Vector3 = o + d * t
				if q.y < tf.height_at(q.x, q.z):
					hit = true
					break
				t += 1.0 + t * 0.02
			if hit:
				best = minf(best, y)
				break
			y += 12.0
		x += 64.0
	return (top_y - best) / SHOT.y


func test_mountains_frames_6000_and_8600_show_ground_above_rider_on_uphill_side() -> void:
	var s: RideScene = _scenes[RouteCatalog.MOUNTAINS]
	var tf: TerrainField = s.terrain()
	var sample := TrackSample.new()
	for stop in [6000.0, 8600.0]:
		_drive_to(s, stop, 32.0)
		s.track.sample_into(stop + 60.0, sample)
		var r: Vector3 = sample.right()
		var hl: float = tf.height_at(sample.position.x - r.x * 60.0, sample.position.z - r.z * 60.0)
		var hr: float = tf.height_at(sample.position.x + r.x * 60.0, sample.position.z + r.z * 60.0)
		var share: float = _ground_above_rider(s, hr > hl, 300.0)
		gut.p("горы %.0f м: земля со стороны склона выше гонщика на %.0f%% кадра" % [stop, share * 100.0])
		assert_gte(share, 0.15, "горы %.0f м: земля со стороны склона выше гонщика ≥ 15 %% кадра" % stop)


# ---------------------------------------------------------------------------
# T-100: кэш планов трасс
# ---------------------------------------------------------------------------

func test_route_world_cache_clears_and_hooks_root_exit() -> void:
	var a: ProfiledTrack = RouteWorld.track(RouteCatalog.FLAT)
	assert_same(RouteWorld.track(RouteCatalog.FLAT), a, "план строится один раз")
	assert_gt(RouteWorld.cached_count(), 0)
	assert_true(RouteWorld.is_exit_hooked(), "кэш очистится при выходе корня дерева сцен")
	RouteWorld.clear_cache()
	assert_eq(RouteWorld.cached_count(), 0, "кэш пуст")
	var b: ProfiledTrack = RouteWorld.track(RouteCatalog.FLAT)
	assert_ne(b, a, "после очистки — новый план")
	assert_eq(b.length_m(), a.length_m(), "тот же маршрут")
	assert_eq(RouteWorld.cached_count(), 1)
