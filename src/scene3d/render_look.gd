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
## сцены — `apply` раскладывает их по материалам мира один раз при построении трассы. Общие
## материалы (тун, контур, асфальт, велосипедист) — ресурсы на процесс: в них окружение
## последней построенной сцены (сцена заезда в процессе одна); материал рельефа — свой у набора.
##
## Тень солнца (`ride_scene.tscn`): нормальное смещение 6.0. При 1.0 в Forward+/Mobile карта
## теней даёт «угри» (самозатенение полосами) — муар на асфальте, бордюре и траве, полосы на
## кронах, и освещённая земля в среднем темнеет; Compatibility при 6.0 выглядит как при 1.0.

## Материалы с этим фрагментом в коде шейдера получают параметры (`#include` тун-света/вида).
const LOOK_MARKERS: PackedStringArray = ["toon_light", "render_look"]


## Окружающий свет (линейный, с энергией) и туман (линейный цвет, плотность) набора окружения —
## в параметры `look_ambient`/`look_fog` всех материалов мира под `root` (общие ресурсы
## материалов — тоже: сцена заезда в процессе одна).
static func apply(root: Node, e: EnvironmentSet) -> void:
	var amb: Color = e.ambient_color.srgb_to_linear() * e.ambient_energy
	var fog: Color = e.fog_color.srgb_to_linear()
	var ambient := Vector3(amb.r, amb.g, amb.b)
	var fog_param := Vector4(fog.r, fog.g, fog.b, e.fog_density)
	var seen: Dictionary = {}
	for mat in materials_under(root):
		if seen.has(mat):
			continue
		seen[mat] = true
		mat.set_shader_parameter("look_ambient", ambient)
		mat.set_shader_parameter("look_fog", fog_param)


## Шейдерные материалы мира под `root` с тун-светом (переопределения узла, поверхности мешей,
## MultiMesh, цепочки next_pass).
static func materials_under(root: Node) -> Array[ShaderMaterial]:
	var out: Array[ShaderMaterial] = []
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for child in node.get_children():
			stack.append(child)
		if not (node is GeometryInstance3D):
			continue
		var gi := node as GeometryInstance3D
		_collect(gi.material_override, out)
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
	return out


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
