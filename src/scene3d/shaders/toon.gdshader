// Тун-материал по цвету вершины (REQ-D3D-07): велосипедист, объекты у дороги, деревья.
// Цвет — COLOR (меш из MeshKit, для MultiMesh — умножен на цвет экземпляра), альфа — вес
// контура для прохода обводки, здесь не используется.
shader_type spatial;
render_mode cull_back, specular_disabled;

// Маска тени кроны хвойных (UV2.y, `conifer_form.gdshaderinc`) — в `toon_light`.
#define TOON_CROWN_MASK
#include "res://src/scene3d/shaders/toon_light.gdshaderinc"
#include "res://src/scene3d/shaders/render_look.gdshaderinc"
#include "res://src/scene3d/shaders/conifer_form.gdshaderinc"

uniform vec4 tint : source_color = vec4(1.0);

void vertex() {
	if (conifer_hidden(UV2, INSTANCE_CUSTOM)) {
		VERTEX = vec3(0.0);
	}
	v_receive = 1.0 - UV2.y;
}

void fragment() {
	ALBEDO = look_vertex_color(COLOR.rgb) * tint.rgb;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}
