// Тун-материал анимированных частей ориентиров (T-083): цвет вершины, как `toon.gdshader`,
// плюс вращение/дрейф из `prop_anim.gdshaderinc`. Контур — `prop_anim_outline.gdshader`
// (та же анимация, иначе обводка отстаёт от лопастей). Свечение (T-088, свет маяка) — эмиссия
// цвета вершины по данным экземпляра, без источника света.
shader_type spatial;
render_mode cull_back, specular_disabled;

#include "res://src/scene3d/shaders/toon_light.gdshaderinc"
#include "res://src/scene3d/props/shaders/prop_anim.gdshaderinc"
#include "res://src/scene3d/shaders/render_look.gdshaderinc"

varying float glow;

void vertex() {
	prop_anim(VERTEX, NORMAL, INSTANCE_CUSTOM, TIME);
	glow = prop_anim_glow(INSTANCE_CUSTOM);
}

void fragment() {
	vec3 col = look_vertex_color(COLOR.rgb);
	ALBEDO = col;
	EMISSION = col * glow;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}
