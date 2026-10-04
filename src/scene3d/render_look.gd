class_name RenderLook
extends RefCounted
## Одинаковая картинка мира в трёх рендерерах (T-102, REQ-D3D-07 п.6–7): Forward+ (macOS,
## десктоп), Mobile (iOS) и Compatibility (снимки `screenshot.sh`, эталоны арт-библии и палитр).
##
## Compatibility (1) переводит цвет вершин из sRGB в линейный, (2) складывает проход солнца с
## основным проходом уже в sRGB и гасит его туманом, (3) считает шейдер неба в sRGB. Forward+ и
## Mobile делают всё линейно — без выравнивания освещённая сторона в них темнее и бледнее
## (трава 94,132,67 против 126,182,89), объекты по цвету вершин — светлее. Выравнивание — в
## шейдерах (`render_look.gdshaderinc`, `sky.gdshader`, ветвление по `CURRENT_RENDERER`; в
## Compatibility ничего не меняется). Шейдерам освещённой стороны нужны окружающий свет и туман
## сцены — `apply` раскладывает их один раз при построении трассы.
##
## Свет и туман — параметры экземпляра (T-112): `instance uniform` в шейдере, значение — у узла
## (`GeometryInstance3D.set_instance_shader_parameter`; у `MultiMeshInstance3D` — на все его
## экземпляры). Общие материалы (тун, контур, асфальт, трава, вода, велосипедист) остаются
## ресурсами на процесс и не меняются: две сцены разных трасс одновременно (тренировка и
## свободная езда в `main.tscn`) получают каждая свои туман и свет, число материалов не растёт.
## Параметры экземпляра объявлены только в Forward+/Mobile (глобальный буфер — 4096 узлов на
## процесс, `PerfBudget.MAX_LOOK_INSTANCES` на сцену); Compatibility свет и туман не читает, и
## его буфер (UBO, 256 узлов на процесс) меньше одной сцены гор — там параметров в шейдере нет,
## `apply` их не задаёт.
##
## Тень солнца (`ride_scene.tscn`): нормальное смещение 6.0. При 1.0 в Forward+/Mobile карта
## теней даёт «угри» (самозатенение полосами) — муар на асфальте, бордюре и траве, полосы на
## кронах, и освещённая земля в среднем темнеет; Compatibility при 6.0 выглядит как при 1.0.

## Материалы с этим фрагментом в коде шейдера получают параметры (`#include` тун-света/вида).
const LOOK_MARKERS: PackedStringArray = ["toon_light", "render_look"]


## Имена параметров экземпляра (`render_look.gdshaderinc`).
const AMBIENT_PARAM: StringName = &"look_ambient"
const FOG_PARAM: StringName = &"look_fog"


## Окружающий свет (линейный, с энергией) и туман (линейный цвет, плотность) набора окружения —
## в параметры экземпляра `look_ambient`/`look_fog` всех узлов мира под `root`, у которых есть
## материал с выравниванием. Материалы не меняются (общие ресурсы — без чужого окружения).
## В Compatibility — ничего: шейдер параметров не объявляет, а заданное значение сервер рендера
## всё равно держит в буфере параметров экземпляра (переполнение уже на двух сценах).
static func apply(root: Node, e: EnvironmentSet) -> void:
	if not uses_instance_look():
		return
	var ambient: Vector3 = ambient_of(e)
	var fog_param: Vector4 = fog_of(e)
	for gi in instances_under(root):
		gi.set_instance_shader_parameter(AMBIENT_PARAM, ambient)
		gi.set_instance_shader_parameter(FOG_PARAM, fog_param)


## Параметры вида нужны рендереру: Forward+ и Mobile (`render_look.gdshaderinc`); не
## Compatibility (в том числе откат на него с Forward+). Headless-прогон — рендерер проекта.
static func uses_instance_look() -> bool:
	return RenderingServer.get_current_rendering_method() != "gl_compatibility"


## Окружающий свет набора для шейдера: линейный цвет × энергия.
static func ambient_of(e: EnvironmentSet) -> Vector3:
	var amb: Color = e.ambient_color.srgb_to_linear() * e.ambient_energy
	return Vector3(amb.r, amb.g, amb.b)


## Туман набора для шейдера: линейный цвет и плотность.
static func fog_of(e: EnvironmentSet) -> Vector4:
	var fog: Color = e.fog_color.srgb_to_linear()
	return Vector4(fog.r, fog.g, fog.b, e.fog_density)


## Узлы геометрии под `root` (включительно), у которых хотя бы один материал с выравниванием.
static func instances_under(root: Node) -> Array[GeometryInstance3D]:
	var out: Array[GeometryInstance3D] = []
	var mats: Array[ShaderMaterial] = []
	for node in _geometry_under(root):
		mats.clear()
		_materials_of(node, mats)
		if not mats.is_empty():
			out.append(node)
	return out


## Шейдерные материалы мира под `root` с тун-светом (переопределения узла, поверхности мешей,
## MultiMesh, цепочки next_pass), без повторов.
static func materials_under(root: Node) -> Array[ShaderMaterial]:
	var all: Array[ShaderMaterial] = []
	for node in _geometry_under(root):
		_materials_of(node, all)
	var out: Array[ShaderMaterial] = []
	var seen: Dictionary = {}
	for m in all:
		if not seen.has(m):
			seen[m] = true
			out.append(m)
	return out


static func _geometry_under(root: Node) -> Array[GeometryInstance3D]:
	var out: Array[GeometryInstance3D] = []
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for child in node.get_children():
			stack.append(child)
		if node is GeometryInstance3D:
			out.append(node as GeometryInstance3D)
	return out


static func _materials_of(gi: GeometryInstance3D, out: Array[ShaderMaterial]) -> void:
	_collect(gi.material_override, out)
	_collect(gi.material_overlay, out)
	var mesh: Mesh = null
	if gi is MeshInstance3D:
		mesh = (gi as MeshInstance3D).mesh
		for i in (gi as MeshInstance3D).get_surface_override_material_count():
			_collect((gi as MeshInstance3D).get_surface_override_material(i), out)
	elif gi is MultiMeshInstance3D and (gi as MultiMeshInstance3D).multimesh != null:
		mesh = (gi as MultiMeshInstance3D).multimesh.mesh
	if mesh != null:
		for i in mesh.get_surface_count():
			_collect(mesh.surface_get_material(i), out)


static func _collect(mat: Material, out: Array[ShaderMaterial]) -> void:
	var m: Material = mat
	while m != null:
		if m is ShaderMaterial and (m as ShaderMaterial).shader != null:
			var code: String = (m as ShaderMaterial).shader.code
			for marker in LOOK_MARKERS:
				if code.contains(marker):
					out.append(m as ShaderMaterial)
					break
		m = m.next_pass
