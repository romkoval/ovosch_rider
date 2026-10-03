// Трава и рельеф (REQ-D3D-07, арт-библия «Земля»): пятна трёх тонов зелёного с чёткой
// границей (плакатная заливка, не градиент), сухие проплешины; цвет — по мировым
// координатам, поэтому полоса обочины и сетка рельефа стыкуются без шва. Цвет вершины
// умножается (сухая трава у бордюра).
//
// Лоскуты полей (T-083, `tracks.md` п. 4.1–4.2): прямоугольные участки в мировых
// координатах (сетка повёрнута на `field_angle`, ряды сдвинуты), у каждого — культура по
// хешу: четыре цвета `field_a..d` или трава (доля `field_grass_share`), межа по краю и
// борозды вблизи. Сила — `field_strength` × (1 − альфа цвета вершины): рельеф пишет в альфу
// близость к дороге (`TerrainField.field_color`), полоса травы у дороги — альфа 1, без полей.
// По умолчанию `field_strength` = 0 — мир петли не меняется.
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

uniform float field_strength : hint_range(0.0, 1.0) = 0.0;
uniform vec4 field_a : source_color = vec4(0.86, 0.74, 0.40, 1.0);
uniform vec4 field_b : source_color = vec4(0.78, 0.64, 0.32, 1.0);
uniform vec4 field_c : source_color = vec4(0.52, 0.40, 0.30, 1.0);
uniform vec4 field_d : source_color = vec4(0.42, 0.62, 0.28, 1.0);
// Доли культур a, b, c (d — остаток) среди участков, не оставленных травой.
uniform vec3 field_weights = vec3(0.34, 0.26, 0.16);
uniform float field_grass_share : hint_range(0.0, 1.0) = 0.2;
uniform vec2 field_size = vec2(120.0, 260.0);
uniform float field_angle = 0.6;
uniform vec4 field_margin : source_color = vec4(0.36, 0.50, 0.22, 1.0);
uniform float field_margin_m = 1.6;
uniform float furrow_period_m = 2.4;
uniform float furrow_contrast = 0.07;
// Лоскуты гаснут на крутых склонах и высоко на холмах горизонта (там — трава и камень).
uniform float field_max_height_m = 400.0;
// Террасы-тропинки по горизонталям (холмы): тёмные полосы по уровням высоты через
// `contour_m` на склонах — форма склона и уклон дороги читаются по тому, как полосы
// пересекают кадр. 0 — выключено.
uniform float contour_m = 0.0;
uniform float contour_contrast = 0.0;

varying vec3 world_pos;
varying vec3 world_normal;
// Высота над полем высоты трассы (UV.x рельефа, `TerrainField.heights_rel`); у полосы травы — 0.
varying float rel_h;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	rel_h = UV.x;
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
	float rel_y = rel_h;
	float fmask = field_strength * (1.0 - COLOR.a) * smoothstep(0.80, 0.90, world_normal.y)
		* (1.0 - smoothstep(field_max_height_m * 0.7, field_max_height_m, rel_y));
	if (fmask > 0.001) {
		float ca = cos(field_angle);
		float sa = sin(field_angle);
		vec2 q = vec2(ca * p.x - sa * p.y, sa * p.x + ca * p.y);
		float row = floor(q.y / field_size.y);
		float qx = q.x + hash12(vec2(row, 3.7)) * field_size.x;
		vec2 cell = vec2(floor(qx / field_size.x), row);
		vec2 f = vec2(fract(qx / field_size.x), fract(q.y / field_size.y)) * field_size;
		float h = hash12(cell + vec2(11.3, 5.1));
		float pick = (h - field_grass_share) / max(1.0 - field_grass_share, 1e-3);
		vec3 crop = field_d.rgb;
		crop = pick < field_weights.x + field_weights.y + field_weights.z ? field_c.rgb : crop;
		crop = pick < field_weights.x + field_weights.y ? field_b.rgb : crop;
		crop = pick < field_weights.x ? field_a.rgb : crop;
		crop *= 0.94 + 0.12 * hash12(cell + vec2(2.9, 8.4));
		// Борозды вдоль длинной или короткой стороны участка, только вблизи.
		float fa = max(fwidth(q.x), 1e-4);
		float along = hash12(cell + vec2(7.7, 1.3)) < 0.5 ? f.x : f.y;
		float furrow = sin(along * 6.2832 / furrow_period_m) * (1.0 - smoothstep(0.05, 0.25, fa / furrow_period_m));
		crop *= 1.0 + furrow * furrow_contrast;
		// Межа: полоса травы по краю участка (гаснет, когда тоньше пикселя).
		float edge = min(min(f.x, field_size.x - f.x), min(f.y, field_size.y - f.y));
		float margin = (1.0 - smoothstep(field_margin_m - fa, field_margin_m + fa, edge)) * (1.0 - smoothstep(0.3, 1.0, fa / field_margin_m));
		crop = mix(crop, field_margin.rgb, margin);
		float use = h < field_grass_share ? 0.0 : 1.0;
		col = mix(col, crop, fmask * use);
	}
	if (contour_m > 0.0) {
		float cy = world_pos.y / contour_m + vnoise(p * 0.02) * 0.6;
		float cw = max(fwidth(cy), 1e-4);
		float band = 1.0 - smoothstep(0.18 - cw, 0.18 + cw, abs(fract(cy) - 0.5) * 2.0 - 0.62);
		float slope = 1.0 - smoothstep(0.93, 0.985, world_normal.y);
		float fade = 1.0 - smoothstep(0.25, 0.6, cw);
		col *= 1.0 - contour_contrast * (1.0 - band) * slope * fade * (1.0 - COLOR.a);
	}
	col *= 1.0 + (vnoise(p * 2.5) - 0.5) * 0.16 * near;
	// Крутые склоны холмов — каменистые.
	float steep = 1.0 - smoothstep(0.72, 0.80, world_normal.y);
	col = mix(col, rock_color.rgb, steep);
	col = mix(col, hill_color.rgb, 0.7 * smoothstep(hill_from_m, hill_to_m, rel_y));
	ALBEDO = col * COLOR.rgb;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}
