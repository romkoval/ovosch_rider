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
// Полосы гаснут, когда их период по экрану меньше этих долей пикселя (вдали — без муара).
uniform vec2 contour_fade = vec2(0.25, 0.6);
// Горы (T-087, `tracks.md` п. 4.3): выше `rock_from_m`…`rock_to_m` (абсолютная высота, м) луг
// сменяется камнем двух тонов со слоями-уступами по горизонталям через `strata_m` (уступы
// горизонтальны — уклон дороги читается по ним), выше `snow_from_m`…`snow_to_m` на пологих
// местах — снег (тень снега — от тун-света и холодного окружающего). У дороги (альфа цвета
// вершины) камня меньше — там луг. По умолчанию выключено.
uniform float rock_from_m = 100000.0;
uniform float rock_to_m = 100001.0;
uniform vec4 rock_light : source_color = vec4(0.55, 0.54, 0.56, 1.0);
uniform vec4 rock_dark : source_color = vec4(0.42, 0.42, 0.46, 1.0);
uniform float strata_m = 0.0;
uniform float snow_from_m = 100000.0;
uniform float snow_to_m = 100001.0;
uniform vec4 snow_color : source_color = vec4(0.95, 0.97, 1.0, 1.0);
// Снег — не ниже этой высоты над полем высоты трассы (UV.x рельефа), м.
uniform float snow_rel_m = 0.0;
// Приморье (T-088, `tracks.md` п. 4.4): по высоте над уровнем воды `water_level` (абсолютная, м)
// — песок пляжа до `sand_to_m` (у воды — мокрый, темнее), выше до `dune_to_m` — дюнная трава
// пятнами, под водой — дно. Обрывы остаются камнем. По умолчанию выключено.
uniform float water_level = -100000.0;
uniform float sand_to_m = 2.6;
uniform float dune_to_m = 7.0;
uniform vec4 sand_color : source_color = vec4(0.90, 0.82, 0.62, 1.0);
uniform vec4 sand_wet : source_color = vec4(0.74, 0.66, 0.48, 1.0);
uniform vec4 dune_grass : source_color = vec4(0.62, 0.66, 0.36, 1.0);
uniform vec4 seabed_color : source_color = vec4(0.56, 0.62, 0.50, 1.0);

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
		float fade = 1.0 - smoothstep(contour_fade.x, contour_fade.y, cw);
		col *= 1.0 - contour_contrast * (1.0 - band) * slope * fade * (1.0 - COLOR.a);
	}
	col *= 1.0 + (vnoise(p * 2.5) - 0.5) * 0.16 * near;
	// Крутые склоны холмов — каменистые.
	float steep = 1.0 - smoothstep(0.72, 0.80, world_normal.y);
	col = mix(col, rock_color.rgb, steep);
	col = mix(col, hill_color.rgb, 0.7 * smoothstep(hill_from_m, hill_to_m, rel_y));
	if (rock_from_m < 50000.0) {
		float wy = world_pos.y;
		float nr = vnoise(p * 0.011) - 0.5;
		float alt = smoothstep(rock_from_m + nr * 70.0, rock_to_m + nr * 70.0, wy);
		// Высоко камень — на склонах; пологие места остаются выгоревшим альпийским лугом.
		// Границы камня чёткие (плакатная заливка), с рваным краем по шуму.
		float ny = world_normal.y + (vnoise(p * 0.05 + vec2(9.0, 4.0)) - 0.5) * 0.1;
		float naa = max(fwidth(ny), 0.004);
		float sloped = 1.0 - smoothstep(0.90 - naa, 0.90 + naa, ny);
		col = mix(col, grass_dry.rgb, alt * 0.45 * (1.0 - sloped));
		float cliff = 1.0 - smoothstep(0.76 - naa, 0.76 + naa, ny);
		float rmask = max(step(0.5, alt) * sloped * (1.0 - 0.8 * COLOR.a), cliff);
		vec3 rock = mix(rock_dark.rgb, rock_light.rgb, smoothstep(0.42, 0.58, vnoise(p * 0.035 + vec2(5.0, 1.0))));
		if (strata_m > 0.0) {
			float sy = wy / strata_m + vnoise(p * 0.015) * 0.8;
			float sw = max(fwidth(sy), 1e-4);
			float ledge = smoothstep(0.80 - sw, 0.80 + sw, fract(sy)) * (1.0 - smoothstep(0.02, 0.07, sw));
			rock = mix(rock, rock_dark.rgb * 0.82, ledge * (1.0 - smoothstep(0.75, 0.9, world_normal.y)));
		}
		col = mix(col, rock, rmask);
		float ns = vnoise(p * 0.006 + vec2(17.0, 3.0)) - 0.5;
		// Снег — только на вершинах: высоко и над полем высоты трассы (не на плато у перевала).
		float smask = smoothstep(snow_from_m + ns * 120.0, snow_to_m + ns * 120.0, wy)
			* smoothstep(snow_rel_m + ns * 80.0, snow_rel_m + 40.0 + ns * 80.0, rel_y)
			* smoothstep(0.62 - naa, 0.62 + naa, ny);
		col = mix(col, snow_color.rgb, smask);
	}
	if (water_level > -50000.0) {
		float hw = world_pos.y - water_level;
		float nn = vnoise(p * 0.03 + vec2(4.0, 11.0)) - 0.5;
		float haa = max(fwidth(hw), 0.01);
		float flat_ground = smoothstep(0.70, 0.80, world_normal.y);
		float sand = (1.0 - smoothstep(sand_to_m + nn * 1.4 - haa, sand_to_m + nn * 1.4 + haa, hw)) * flat_ground;
		float dune = (1.0 - smoothstep(dune_to_m + nn * 4.0 - haa, dune_to_m + nn * 4.0 + haa, hw))
			* smoothstep(0.42 - aa, 0.42 + aa, n1) * flat_ground * (1.0 - COLOR.a * 0.8);
		col = mix(col, dune_grass.rgb, dune);
		vec3 sandc = mix(sand_wet.rgb, sand_color.rgb, smoothstep(0.05, 0.45, hw));
		sandc *= 1.0 + (n2 - 0.5) * 0.06;
		sandc = mix(seabed_color.rgb, sandc, smoothstep(-0.8, -0.1, hw));
		col = mix(col, sandc, max(sand, 1.0 - smoothstep(-0.5, 0.0, hw)));
	}
	ALBEDO = col * COLOR.rgb;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}
