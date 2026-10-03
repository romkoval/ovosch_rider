// Небо (REQ-D3D-07, арт-библия «Небо»): градиент от светлого горизонта к насыщенному
// зениту, солнечный ореол и плоские «нарисованные» кучевые облака в два тона.
shader_type sky;

#include "res://src/scene3d/shaders/noise.gdshaderinc"

uniform vec4 top_color : source_color = vec4(0.33, 0.58, 0.90, 1.0);
uniform vec4 horizon_color : source_color = vec4(0.78, 0.87, 0.95, 1.0);
uniform vec4 ground_color : source_color = vec4(0.45, 0.52, 0.45, 1.0);
uniform vec4 cloud_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 cloud_shade : source_color = vec4(0.80, 0.85, 0.95, 1.0);
uniform float cloud_cover : hint_range(0.0, 1.0) = 0.36;
uniform float cloud_scale = 0.8;

void sky() {
	vec3 d = EYEDIR;
	float y = d.y;
	vec3 col = mix(horizon_color.rgb, top_color.rgb, smoothstep(0.0, 0.55, y));
	col = mix(col, ground_color.rgb, smoothstep(0.0, -0.08, y));
	if (!AT_CUBEMAP_PASS && y > 0.0) {
		vec2 uv = d.xz / (y + 0.12) * cloud_scale;
		float n = fbm3(uv + vec2(3.1, 1.7));
		float thr = 1.0 - cloud_cover;
		float aa = max(fwidth(n), 1e-3);
		float c = smoothstep(thr - aa, thr + aa, n);
		float core = smoothstep(thr + 0.08 - aa, thr + 0.08 + aa, fbm3(uv + vec2(3.1, 1.7) + vec2(0.04, 0.05)));
		vec3 cl = mix(cloud_shade.rgb, cloud_color.rgb, core);
		float fade = smoothstep(0.02, 0.18, y);
		col = mix(col, cl, c * fade);
	}
	float sun = dot(d, normalize(LIGHT0_DIRECTION));
	col += LIGHT0_COLOR * 0.25 * smoothstep(0.96, 1.0, sun);
	col = mix(col, vec3(1.0, 0.98, 0.9), smoothstep(0.9993, 0.9996, sun));
	COLOR = col;
}
