extends GutTest
## T-102: одинаковая картинка мира в Forward+/Mobile и Compatibility (REQ-D3D-07 п.6, 7), подъём в
## горах читается (REQ-D3D-08 п.8, решение game-designer 14), бюджет (REQ-D3D-05); T-100 — кэш
## `RouteWorld` очищается (REQ-INF-01 п.2, 5).
##
## Пиксели рендера headless не проверить — здесь контракт: материалы мира получают окружающий
## свет и туман сцены (`RenderLook.apply`), шейдеры выравнивают свет, цвет вершин и небо по
## `CURRENT_RENDERER`, шумы гаснут по размеру пикселя на земле по обеим осям, тень солнца — с
## нормальным смещением против «угрей» в Forward+/Mobile. Средние цвета по рендерерам — снимки
## `docs/game/shots/2026-10-04-t102/` (отчёт T-102).

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

func _assert_look(m: ShaderMaterial, e: EnvironmentSet, label: String) -> void:
	var amb: Color = e.ambient_color.srgb_to_linear() * e.ambient_energy
	var fog: Color = e.fog_color.srgb_to_linear()
	var a: Vector3 = m.get_shader_parameter("look_ambient")
	var f: Vector4 = m.get_shader_parameter("look_fog")
	assert_true(a.is_equal_approx(Vector3(amb.r, amb.g, amb.b)), "%s %s: окружающий свет %s" % [label, m.shader.resource_path, a])
	assert_true(f.is_equal_approx(Vector4(fog.r, fog.g, fog.b, e.fog_density)), "%s %s: туман %s" % [label, m.shader.resource_path, f])


## Общие материалы (тун, контур, асфальт, велосипедист) — ресурсы на процесс: в них окружение
## последней построенной сцены (здесь — приморье); материал рельефа — свой у каждого набора.
func test_world_materials_get_scene_ambient_and_fog() -> void:
	var last: RideScene = _scenes[RouteCatalog.SEASIDE]
	var shaders: Dictionary = {}
	for m in RenderLook.materials_under(last):
		shaders[m.shader.resource_path.get_file()] = true
		_assert_look(m, last.environment_set, RouteCatalog.SEASIDE)
	for need in ["toon.gdshader", "grass.gdshader", "road.gdshader", "outline.gdshader", "water.gdshader"]:
		assert_true(shaders.has(need), "%s среди материалов мира с выравниванием" % need)
	for id in IDS:
		var s: RideScene = _scenes[id]
		var terrain_mat: ShaderMaterial = s.environment_set.terrain_material as ShaderMaterial
		assert_not_null(terrain_mat, "%s: свой материал рельефа" % id)
		_assert_look(terrain_mat, s.environment_set, id)


func test_rider_materials_are_aligned_too() -> void:
	var s: RideScene = _scenes[RouteCatalog.FLAT]
	var rider_mats: Array[ShaderMaterial] = RenderLook.materials_under(s.rider())
	assert_gt(rider_mats.size(), 0, "у велосипедиста тун-материалы")
	for m in rider_mats:
		assert_not_null(m.get_shader_parameter("look_ambient"), m.shader.resource_path)


func test_shaders_branch_by_renderer_and_compatibility_stays_reference() -> void:
	var inc: String = _code("res://src/scene3d/shaders/render_look.gdshaderinc")
	assert_string_contains(inc, "#if CURRENT_RENDERER == RENDERER_COMPATIBILITY", "ветвление по рендереру")
	assert_string_contains(inc, "vec3 look_diffuse(", "солнце — как сложение проходов в sRGB")
	assert_string_contains(inc, "vec3 look_vertex_color(", "цвет вершин — из sRGB")
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
