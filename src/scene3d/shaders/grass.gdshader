// Трава и рельеф (REQ-D3D-07, арт-библия «Земля»): пятна трёх тонов зелёного с чёткой
// границей (плакатная заливка, не градиент), сухие проплешины; цвет — по мировым
// координатам, поэтому полоса обочины и сетка рельефа стыкуются без шва. Цвет вершины
// умножается (сухая трава у бордюра).
shader_type spatial;
render_mode cull_back, specular_disabled;

#include "res://src/scene3d/shaders/toon_light.gdshaderinc"
#include "res://src/scene3d/shaders/noise.gdshaderinc"

uniform vec4 grass_light : source_color = vec4(0.40, 0.60, 0.25, 1.0);
uniform vec4 grass_mid : source_color = vec4(0.33, 0.52, 0.22, 1.0);
uniform vec4 grass_dark : source_color = vec4(0.25, 0.42, 0.19, 1.0);
uniform vec4 grass_dry : source_color = vec4(0.60, 0.62, 0.34, 1.0);
uniform vec4 rock_color : source_color = vec4(0.52, 0.55, 0.50, 1.0);
uniform float patch_scale = 0.035;
// Склоны холмов горизонта темнее и холоднее — силуэты читаются сквозь дымку.
uniform vec4 hill_color : source_color = vec4(0.24, 0.40, 0.30, 1.0);
uniform float hill_from_m = 8.0;
uniform float hill_to_m = 70.0;

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec2 p = world_pos.xz;
	float aa = max(fwidth(p.x * patch_scale), 1e-4) * 2.0;
	float n1 = fbm3(p * patch_scale);
	float n2 = vnoise(p * patch_scale * 3.7 + vec2(31.0, 7.0));
	vec3 col = grass_mid.rgb;
	col = mix(col, grass_light.rgb, smoothstep(0.56 - aa, 0.56 + aa, n1));
	col = mix(col, grass_dark.rgb, 1.0 - smoothstep(0.40 - aa, 0.40 + aa, n1));
	col = mix(col, grass_dry.rgb, smoothstep(0.78 - aa, 0.78 + aa, n2) * 0.6);
	// Мелкая вариация вблизи — рябь травы, гаснет с расстоянием.
	float near = 1.0 - smoothstep(0.004, 0.02, aa);
	col *= 1.0 + (vnoise(p * 2.5) - 0.5) * 0.16 * near;
	// Крутые склоны холмов — каменистые.
	float steep = 1.0 - smoothstep(0.72, 0.80, world_normal.y);
	col = mix(col, rock_color.rgb, steep);
	col = mix(col, hill_color.rgb, 0.7 * smoothstep(hill_from_m, hill_to_m, world_pos.y));
	ALBEDO = col * COLOR.rgb;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}
