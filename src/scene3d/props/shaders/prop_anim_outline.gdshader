// Контур анимированных частей ориентиров (T-083): как `outline.gdshader`, вершины сначала
// проходят ту же анимацию (`prop_anim.gdshaderinc`).
shader_type spatial;
render_mode cull_front, unshaded, shadows_disabled;

#include "res://src/scene3d/props/shaders/prop_anim.gdshaderinc"
#include "res://src/scene3d/shaders/render_look.gdshaderinc"

uniform vec4 outline_color : source_color = vec4(0.10, 0.12, 0.10, 1.0);
uniform float outline_width = 0.06;
uniform float albedo_mix : hint_range(0.0, 1.0) = 0.7;
uniform float albedo_darken : hint_range(0.0, 1.0) = 0.35;

varying vec3 v_col;

void vertex() {
	prop_anim(VERTEX, NORMAL, INSTANCE_CUSTOM, TIME);
	if (COLOR.a < 0.01) {
		VERTEX = vec3(0.0);
	} else {
		VERTEX += NORMAL * outline_width * COLOR.a;
	}
	v_col = look_vertex_color(COLOR.rgb);
}

void fragment() {
	ALBEDO = mix(outline_color.rgb, v_col * albedo_darken, albedo_mix);
}
