// Тун-материал по цвету вершины (REQ-D3D-07): велосипедист, объекты у дороги, деревья.
// Цвет — COLOR (меш из MeshKit, для MultiMesh — умножен на цвет экземпляра), альфа — вес
// контура для прохода обводки, здесь не используется.
shader_type spatial;
render_mode cull_back, specular_disabled;

#include "res://src/scene3d/shaders/toon_light.gdshaderinc"

uniform vec4 tint : source_color = vec4(1.0);

void fragment() {
	ALBEDO = COLOR.rgb * tint.rgb;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}
