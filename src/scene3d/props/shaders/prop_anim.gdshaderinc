// Анимация частей ориентиров без кода в кадре (T-083, `tracks.md` п. 4.5): лопасти ветряков и
// крылья мельницы вращаются, воздушный шар медленно дрейфует. Параметры — данные экземпляра
// MultiMesh (INSTANCE_CUSTOM): x — угловая скорость вокруг локальной оси Z, рад/с; y — фаза,
// рад; z — амплитуда дрейфа по локальной X, м; w — амплитуда покачивания по Y, м. Дрейф —
// синус с частотой `drift_rate`: скорость не больше z · drift_rate (≤ 0.5 м/с).

uniform float drift_rate = 0.035;

void prop_anim(inout vec3 v, inout vec3 n, vec4 custom, float time) {
	float a = time * custom.x + custom.y;
	float c = cos(a);
	float s = sin(a);
	v.xy = vec2(c * v.x - s * v.y, s * v.x + c * v.y);
	n.xy = vec2(c * n.x - s * n.y, s * n.x + c * n.y);
	float d = time * drift_rate + custom.y;
	v.x += sin(d) * custom.z;
	v.y += sin(d * 1.7) * custom.w;
}
