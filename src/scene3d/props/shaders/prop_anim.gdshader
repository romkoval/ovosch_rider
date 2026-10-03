// Тун-материал анимированных частей ориентиров (T-083): цвет вершины, как `toon.gdshader`,
// плюс вращение/дрейф из `prop_anim.gdshaderinc`. Контур — `prop_anim_outline.gdshader`
// (та же анимация, иначе обводка отстаёт от лопастей).
shader_type spatial;
render_mode cull_back, specular_disabled;

#include "res://src/scene3d/shaders/toon_light.gdshaderinc"
#include "res://src/scene3d/props/shaders/prop_anim.gdshaderinc"

void vertex() {
	prop_anim(VERTEX, NORMAL, INSTANCE_CUSTOM, TIME);
}

void fragment() {
	ALBEDO = COLOR.rgb;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}
