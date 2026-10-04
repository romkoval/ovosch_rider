// Одинаковая картинка мира в трёх рендерерах (T-102, `RenderLook`). Эталон — Compatibility
// (кадры `screenshot.sh`, по ним приняты арт-библия и палитры трасс). Отличия Forward+/Mobile,
// которые здесь выравниваются (в Compatibility функции ничего не меняют):
// 1. Цвет вершин (COLOR, у MultiMesh — вместе с цветом экземпляра) Compatibility переводит из
//    sRGB в линейный, Forward+/Mobile отдают как есть — `look_vertex_color`.
// 2. Солнце с тенью Compatibility рисует отдельным проходом и складывает с основным
//    (окружающий свет + туман) уже в sRGB, а свет прохода гасит туманом:
//      итог = sRGB(mix(a·окр, туман, f)) + sRGB(a·солнце·(1 − f)),
//    Forward+/Mobile — линейно: mix(a·(окр + солнце), туман, f). `look_diffuse` возвращает
//    добавку DIFFUSE_LIGHT, при которой линейный путь даёт тот же итог. Для этого материалу нужны
//    окружающий свет и туман сцены — `look_ambient`, `look_fog` (ставит `RenderLook.apply`).
#ifndef RENDER_LOOK_INC
#define RENDER_LOOK_INC

// Окружающий свет сцены: линейный цвет × энергия.
uniform vec3 look_ambient = vec3(0.27, 0.32, 0.54);
// Туман сцены: линейный цвет (rgb) и плотность экспоненциального тумана (a).
uniform vec4 look_fog = vec4(0.69, 0.71, 0.64, 0.0005);

vec3 look_to_linear(vec3 c) {
	c = max(c, vec3(0.0));
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

vec3 look_to_srgb(vec3 c) {
	c = max(c, vec3(0.0));
	return mix(c * 12.92, 1.055 * pow(c, vec3(1.0 / 2.4)) - 0.055, step(vec3(0.0031308), c));
}

vec3 look_vertex_color(vec3 c) {
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	return c;
#else
	return look_to_linear(c);
#endif
}

// Добавка к DIFFUSE_LIGHT от солнца `sun` (LIGHT_COLOR / PI × освещённость × тень) на точке с
// альбедо `albedo`. `fragcoord`, `viewport`, `inv_proj` — FRAGCOORD, VIEWPORT_SIZE и
// INV_PROJECTION_MATRIX из light(): по ним — расстояние до камеры для тумана.
vec3 look_diffuse(vec3 sun, vec3 albedo, vec4 fragcoord, vec2 viewport, mat4 inv_proj) {
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	return sun;
#else
	vec3 a = max(albedo, vec3(1e-3));
	vec4 ndc = vec4(fragcoord.xy / viewport * 2.0 - 1.0, fragcoord.z, 1.0);
	vec4 vp = inv_proj * ndc;
	float dist = length(vp.xyz / vp.w);
	float f = 1.0 - exp(min(0.0, -dist * look_fog.a));
	vec3 amb = a * look_ambient;
	vec3 base = mix(amb, look_fog.rgb, f);
	vec3 target = look_to_linear(min(look_to_srgb(base) + look_to_srgb(a * sun * (1.0 - f)), vec3(1.0)));
	// Forward+: mix(amb + a·D, туман, f) = target.
	vec3 lit = (target - look_fog.rgb * f) / max(1.0 - f, 1e-3);
	return max(lit - amb, vec3(0.0)) / a;
#endif
}

#endif
