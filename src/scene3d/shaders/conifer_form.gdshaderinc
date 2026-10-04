// Хвойные (T-107, `ConiferKit`): меш слоя MultiMesh несёт все формы трассы одного уровня
// детализации — UV2.x вершины — номер формы в меше + 1 (0 — меш одной формы и все прочие меши),
// INSTANCE_CUSTOM.r — форма экземпляра. Вершины чужих форм схлопываются в точку: один слой
// (и вызов отрисовки на кусок) вместо слоя на форму. UV2.y — 1 у кроны: она не принимает тень
// (`toon.gdshader`: самозатенение ярусов давало в Forward+ полосы и пятна).
#ifndef CONIFER_FORM_INC
#define CONIFER_FORM_INC

bool conifer_hidden(vec2 uv2, vec4 custom) {
	return uv2.x > 0.5 && abs(uv2.x - 1.0 - custom.r) > 0.5;
}

#endif
