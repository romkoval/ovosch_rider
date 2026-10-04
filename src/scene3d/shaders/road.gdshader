// Асфальт с разметкой (REQ-D3D-07, арт-библия «Дорога»): тёмный холодно-серый асфальт с
// крупными заплатками и мелким зерном (шумы гаснут к среднему по размеру пикселя на земле —
// по худшей оси, без муара вдали в любом рендерере),
// сплошные белые линии по краям, прерывистая осевая. UV меша дороги (RoadBuilder):
// u — поперёк 0..1, v — дистанция / ширина.
shader_type spatial;
render_mode cull_back, specular_disabled;

#include "res://src/scene3d/shaders/toon_light.gdshaderinc"
#include "res://src/scene3d/shaders/noise.gdshaderinc"

uniform float road_width = 6.5;
uniform vec4 asphalt_color : source_color = vec4(0.25, 0.26, 0.29, 1.0);
uniform vec4 patch_color : source_color = vec4(0.21, 0.22, 0.25, 1.0);
uniform vec4 line_color : source_color = vec4(0.95, 0.95, 0.92, 1.0);
uniform float edge_inset = 0.28;
uniform float edge_width = 0.16;
uniform float center_width = 0.12;
uniform float dash_length = 3.0;
uniform float dash_period = 9.0;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float band(float d, float half_w, float aa) {
	return 1.0 - smoothstep(half_w - aa, half_w + aa, d);
}

void fragment() {
	float x = (UV.x - 0.5) * road_width;
	float s = UV.y * road_width;
	float ax = abs(x);
	float aa = max(fwidth(x), 1e-4);
	vec2 p = world_pos.xz;

	// Метров на пиксель — по худшей оси: вдоль дороги под скользящим углом шаг в разы больше,
	// чем поперёк (`aa`), и шум, гасимый только по поперечной оси, рябит муаром (T-102).
	float px = max(max(fwidth(p.x), fwidth(p.y)), 1e-4);
	float big = vnoise(p * 0.07);
	float mid = vnoise(p * 0.9);
	float patches = smoothstep(0.62 - px * 0.07, 0.64 + px * 0.07, big);
	vec3 col = mix(asphalt_color.rgb, patch_color.rgb, patches);
	// Шум гаснет к среднему, пока его период не стал короче ~4 пикселей.
	col *= 0.94 + 0.12 * mix(0.5, mid, 1.0 - smoothstep(0.12, 0.28, px));
	// Зерно: мелкая рябь только вблизи.
	float near = 1.0 - smoothstep(0.012, 0.03, px);
	col *= 1.0 + (vnoise(p * 9.0) - 0.5) * 0.10 * near;
	// Накатанная колея (светлее) и масляная полоса по центру полосы (темнее).
	float lane = road_width * 0.25;
	col *= 1.0 - 0.07 * exp(-pow((ax - lane) / 0.35, 2.0));
	col *= 1.0 + 0.05 * exp(-pow((abs(ax - lane) - 0.8) / 0.3, 2.0));
	// Пыль у кромки.
	col = mix(col, col * vec3(1.08, 1.04, 0.95), smoothstep(road_width * 0.5 - 0.35, road_width * 0.5, ax));

	float edge = band(abs(ax - (road_width * 0.5 - edge_inset)), edge_width * 0.5, aa);
	float t = s / dash_period;
	float ft = max(fwidth(t), 1e-4);
	float ph = fract(t);
	float on = dash_length / dash_period;
	float dash = smoothstep(0.0, ft, ph) * (1.0 - smoothstep(on - ft, on, ph));
	float center = band(ax, center_width * 0.5, aa) * dash;
	float paint = max(edge, center) * (0.86 + 0.14 * mix(0.5, vnoise(p * 3.0), 1.0 - smoothstep(0.04, 0.09, px)));
	col = mix(col, line_color.rgb, paint);

	ALBEDO = col;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}
