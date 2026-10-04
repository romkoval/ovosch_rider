// Тун-вода (T-088, `docs/game/tracks.md` п. 4.4, 6; арт-библия «Свет и цвет»): плоская
// поверхность без отражений, прозрачности и текстуры глубины — одна непрозрачная проходка,
// одинаково на Forward+, Mobile и Compatibility. Глубина под водой (уровень − рельеф, м) приходит
// в UV.x меша (`TerrainField.build_water_mesh`): мель и глубина — два тона с чёткой волнистой
// границей; у берега — пена, её кромка «дышит», к берегу набегают пенные штрихи; на глубине —
// светлые штрихи ряби (вдали гаснут — без муара); блик солнца — тун-полоса по отражённому лучу
// с рябью нормали. Всё анимируется в шейдере по TIME, без кода в кадре.
shader_type spatial;
render_mode cull_back, diffuse_lambert;

#include "res://src/scene3d/shaders/noise.gdshaderinc"
#include "res://src/scene3d/shaders/render_look.gdshaderinc"

uniform vec4 deep_color : source_color = vec4(0.10, 0.42, 0.62, 1.0);
uniform vec4 shallow_color : source_color = vec4(0.22, 0.68, 0.75, 1.0);
uniform vec4 foam_color : source_color = vec4(0.95, 0.97, 0.98, 1.0);
uniform vec4 ripple_color : source_color = vec4(0.62, 0.84, 0.90, 1.0);
// Граница мели и глубины, м; волнистость границы (доля шума), м.
uniform float shallow_depth_m = 1.6;
uniform float shallow_wobble_m = 1.0;
// Пена у берега: глубина кромки, «дыхание» кромки (м) и его скорость; набегающие штрихи —
// откуда (глубина, м), период (с) и толщина (м).
uniform float foam_depth_m = 0.3;
uniform float foam_breath_m = 0.18;
uniform float foam_speed = 0.9;
uniform float surf_from_m = 1.3;
uniform float surf_period_s = 7.0;
uniform float surf_width_m = 0.07;
// Рябь: масштаб (1/м), скорость, контраст штрихов, сила наклона нормали для блика.
uniform float ripple_scale = 0.05;
uniform float ripple_speed = 0.035;
uniform float ripple_amount : hint_range(0.0, 1.0) = 0.45;
uniform float normal_strength = 0.6;
// Блик солнца: порог по cos(угла между нормалью и половинным вектором) и сила.
uniform float glint_threshold : hint_range(0.9, 1.0) = 0.992;
uniform float glint_strength = 0.8;
// Тун-свет: как `toon_light.gdshaderinc` (два тона, тень — только окружающий свет).
uniform float toon_threshold : hint_range(-1.0, 1.0) = 0.0;
uniform float toon_softness : hint_range(0.001, 0.5) = 0.08;

varying vec3 world_pos;
varying float depth;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	depth = UV.x;
}

void fragment() {
	vec2 p = world_pos.xz;
	float t = TIME;
	vec2 q1 = p * ripple_scale + vec2(t * ripple_speed, t * ripple_speed * 0.6);
	vec2 q2 = p * ripple_scale * 2.3 - vec2(t * ripple_speed * 0.7, -t * ripple_speed * 0.9);
	float n1 = vnoise(q1);
	float n2 = vnoise(q2);
	float n = n1 * 0.65 + n2 * 0.35;
	// Мель и глубина: два тона, граница волнится шумом.
	float d = depth + (n - 0.5) * shallow_wobble_m * 2.0;
	float aa = max(fwidth(d), 0.02);
	vec3 col = mix(shallow_color.rgb, deep_color.rgb, smoothstep(shallow_depth_m - aa, shallow_depth_m + aa, d));
	// Штрихи ряби — изолинии бегущего шума; гаснут, когда тоньше пикселя (вдали).
	float fw = max(fwidth(n2), 1e-4);
	float crest = 1.0 - smoothstep(0.0, fw * 1.5, abs(n2 - 0.63) - 0.008);
	float fade = 1.0 - smoothstep(0.015, 0.05, fw);
	col = mix(col, ripple_color.rgb, crest * fade * ripple_amount * smoothstep(0.4, 1.2, depth));
	// Набегающие на берег пенные штрихи: полоса идёт с глубины `surf_from_m` к кромке, рвётся шумом.
	float phase = fract(t / surf_period_s + n1 * 0.15);
	float surf_d = mix(surf_from_m, foam_depth_m, phase);
	float da = max(fwidth(depth), 0.01);
	float surf = (1.0 - smoothstep(surf_width_m, surf_width_m + da * 1.5, abs(depth - surf_d)))
		* step(0.42, vnoise(p * 0.12 + vec2(3.1, 7.7))) * (1.0 - phase * 0.6);
	// Пена у кромки: «дышит» по времени, край рваный.
	float edge = foam_depth_m + foam_breath_m * (0.5 + 0.5 * sin(t * foam_speed + n1 * 6.2832));
	float foam = 1.0 - smoothstep(edge - da, edge + da, depth + (n2 - 0.5) * 0.12);
	col = mix(col, foam_color.rgb, clamp(max(foam, surf), 0.0, 1.0));
	// Рябь нормали — только для блика (цвет от неё не зависит).
	float e = 0.35;
	vec2 grad = vec2(vnoise(q1 + vec2(e, 0.0)) - n1, vnoise(q1 + vec2(0.0, e)) - n1) / e
		+ vec2(vnoise(q2 + vec2(e, 0.0)) - n2, vnoise(q2 + vec2(0.0, e)) - n2) / e * 0.5;
	vec3 wn = normalize(vec3(-grad.x * normal_strength, 1.0, -grad.y * normal_strength));
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
	ALBEDO = col;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float lit = smoothstep(toon_threshold - toon_softness, toon_threshold + toon_softness, ndl);
	float shadow = smoothstep(0.3, 0.7, ATTENUATION);
	DIFFUSE_LIGHT += look_diffuse(LIGHT_COLOR / PI * lit * shadow, ALBEDO, FRAGCOORD, VIEWPORT_SIZE, INV_PROJECTION_MATRIX);
	vec3 h = normalize(LIGHT + VIEW);
	float g = dot(NORMAL, h);
	float ga = max(fwidth(g), 1e-4);
	SPECULAR_LIGHT += LIGHT_COLOR * glint_strength * smoothstep(glint_threshold - ga, glint_threshold + ga, g) * shadow;
}
