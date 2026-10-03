// Общий тун-свет мира ovosch-rider (REQ-D3D-07, арт-библия «Свет»): два тона — «свет»
// и «тень» с узкой мягкой границей, без бликов. Тень и сторона, отвёрнутая от солнца,
// получают только окружающий свет (холодный, голубоватый — задаётся в Environment),
// поэтому тени не чёрные, а синие, как в иллюстрации.

uniform float toon_threshold : hint_range(-1.0, 1.0) = 0.02;
uniform float toon_softness : hint_range(0.001, 0.5) = 0.05;
uniform float toon_sun_gain : hint_range(0.0, 4.0) = 1.0;
uniform float toon_rim : hint_range(0.0, 2.0) = 0.0;
// 0 — объект не принимает тени (велосипедист: без «грязи» самозатенения на тонких деталях).
uniform float toon_receive_shadow : hint_range(0.0, 1.0) = 1.0;

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float lit = smoothstep(toon_threshold - toon_softness, toon_threshold + toon_softness, ndl);
	float shadow = mix(1.0, smoothstep(0.3, 0.7, ATTENUATION), toon_receive_shadow);
	float l = lit * shadow;
	DIFFUSE_LIGHT += LIGHT_COLOR / PI * l * toon_sun_gain;
	if (toon_rim > 0.0) {
		float rim = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
		DIFFUSE_LIGHT += LIGHT_COLOR / PI * smoothstep(0.62, 0.68, rim) * l * toon_rim;
	}
}
