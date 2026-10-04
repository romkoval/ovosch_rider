// Контур «инвертированной оболочкой» (REQ-D3D-07, арт-библия «Контур»): вторая проходка
// материала, грани наружу отсечены, вершины сдвинуты по нормали на `outline_width`
// метров × альфа цвета вершины. Альфа 0 — контура нет (вершины схлопываются).
shader_type spatial;
render_mode cull_front, unshaded, shadows_disabled;
#include "res://src/scene3d/shaders/render_look.gdshaderinc"
#include "res://src/scene3d/shaders/conifer_form.gdshaderinc"

uniform vec4 outline_color : source_color = vec4(0.07, 0.06, 0.09, 1.0);
uniform float outline_width = 0.012;
// 0 — чистый цвет туши, 1 — затемнённый цвет объекта (мягкий контур для растительности).
uniform float albedo_mix : hint_range(0.0, 1.0) = 0.0;
uniform float albedo_darken : hint_range(0.0, 1.0) = 0.35;

varying vec3 v_col;

void vertex() {
	if (COLOR.a < 0.01 || conifer_hidden(UV2, INSTANCE_CUSTOM)) {
		VERTEX = vec3(0.0);
	} else {
		VERTEX += NORMAL * outline_width * COLOR.a;
	}
	v_col = look_vertex_color(COLOR.rgb);
}

void fragment() {
	ALBEDO = mix(outline_color.rgb, v_col * albedo_darken, albedo_mix);
}
