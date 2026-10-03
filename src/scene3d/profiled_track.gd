class_name ProfiledTrack
extends Track
## Трасса каталога (REQ-D3D-08 п.2, 4, 5; `docs/game/tracks.md` п. 4–5): план-схема по
## `layout` + `seed` из `RouteCatalog`, высота оси дороги — профиль h(s) трассы.
##
## План строится один раз: форма трассы (`layout.shape`) задаётся последовательностью
## примитивов — прямых и дуг заданного радиуса (углы поворота «углов» петли в сумме дают
## ±360°). Кривизна κ(s) примитивов раскладывается в ряд с шагом ~1 м, дважды сглаживается
## скользящим окном (переходные кривые вместо скачка кривизны) и интегрируется в курс и
## точки плана. Замыкание круга — три группы прямых с разными курсами («регулируемые»):
## их длины решают систему «конец = начало, длина = L» (смещение конца линейно по длине
## прямой). Поэтому длина плана равна длине профиля, курс и позиция на стыке непрерывны
## (горизонтальная геометрия стыка, D3D-08 п.2), а дуги сохраняют радиусы из `tracks.md`.
## Попытки с другим seed — если части петли подходят друг к другу ближе `MIN_GAP_M`
## (тогда и подъём со спуском «Перевала» не ближе 30 м, D3D-08 п.10).
##
## s — горизонтальная длина дуги плана; позиция = (план(s), h(s)); `forward` — касательная
## плана с вертикальной составляющей g(s) = уклон профиля по окну 100 м, поэтому продольный
## наклон велосипедиста = atan(g) (D3D-08 п.5); `up` — нормаль полотна (перпендикулярна
## `forward`, правый вектор горизонтален). Выборка между узлами — кубика Эрмита по
## касательным, без аллокаций.

## Шаг узлов плана, м (не больше; точный шаг — длина / число узлов).
const STEP_M: float = 1.0
## Окно сглаживания кривизны (два прохода), м: переходная кривая ~2 окна.
const SMOOTH_WINDOW_M: float = 21.0
## Регулируемая прямая не короче этого (длиннее полной ширины сглаживания).
const MIN_STRAIGHT_M: float = 60.0
## Проверка сближения частей петли: шаг точек, расстояние по дуге, с которого точки — «разные
## части», и минимальное расстояние между ними по горизонтали.
const CHECK_STEP_M: float = 20.0
const GAP_ARC_M: float = 500.0
const MIN_GAP_M: float = 100.0
const MAX_ATTEMPTS: int = 40

var route_id: String = ""
var profile: RouteProfile = null
## Описание трассы из каталога (seed, layout, мосты, ориентиры).
var route: RouteCatalog.RouteDef = null
## Минимальное расстояние между разными частями петли, м (диагностика).
var min_gap_m: float = 0.0
## Попытка (0 — с seed трассы), на которой план прошёл проверки.
var attempt: int = -1

var _length: float = 0.0
var _n: int = 0
var _step: float = 1.0
## Узлы плана (x, z), n + 1 штук (последний совпадает с первым) и единичные касательные.
var _pts := PackedVector2Array()
var _tan := PackedVector2Array()


## Последовательность примитивов плана: длина, кривизна (> 0 — поворот вправо по ходу),
## группа регулируемой прямой (−1 — нет), признак «угла» петли (его длина подгоняется так,
## чтобы сумма поворотов была ровно ±360°).
class Plan:
	extends RefCounted
	var lengths := PackedFloat64Array()
	var kappas := PackedFloat64Array()
	var groups := PackedInt32Array()
	var corners := PackedByteArray()

	func straight(length_m: float, group: int = -1) -> void:
		lengths.append(maxf(length_m, 1.0))
		kappas.append(0.0)
		groups.append(group)
		corners.append(0)

	## Дуга радиуса `radius_m` на угол `deg` (> 0 — вправо, < 0 — влево).
	func arc(radius_m: float, deg: float, corner: bool = false) -> void:
		lengths.append(radius_m * deg_to_rad(absf(deg)))
		kappas.append(signf(deg) / radius_m)
		groups.append(-1)
		corners.append(1 if corner else 0)

	## S-связка: дуга на `deg` и обратная, между ними прямая `gap_m`.
	func s_bend(radius_m: float, deg: float, gap_m: float) -> void:
		arc(radius_m, deg)
		if gap_m > 0.0:
			straight(gap_m)
		arc(radius_m, -deg)

	func total() -> float:
		var t: float = 0.0
		for l in lengths:
			t += l
		return t

	func size() -> int:
		return lengths.size()


## Трасса каталога по id (null — неизвестный id).
static func from_id(id: String) -> ProfiledTrack:
	var def: RouteCatalog.RouteDef = RouteCatalog.get_route(id)
	return from_route(def) if def != null else null


static func from_route(def: RouteCatalog.RouteDef) -> ProfiledTrack:
	var t := ProfiledTrack.new()
	t._build(def)
	return t


func length_m() -> float:
	return _length


func is_loop() -> bool:
	return true


## Точки плана (x, z) с шагом ~`STEP_M` (копия; последняя совпадает с первой).
func plan_points() -> PackedVector2Array:
	return _pts.duplicate()


func sample_into(distance_m: float, out: TrackSample) -> void:
	var s: float = wrap_distance(distance_m)
	var f: float = s / _step
	var i: int = mini(int(f), _n - 1)
	var t: float = f - float(i)
	var p0: Vector2 = _pts[i]
	var p1: Vector2 = _pts[i + 1]
	var m0: Vector2 = _tan[i] * _step
	var m1: Vector2 = _tan[i + 1] * _step
	var t2: float = t * t
	var t3: float = t2 * t
	var pos: Vector2 = p0 * (2.0 * t3 - 3.0 * t2 + 1.0) + m0 * (t3 - 2.0 * t2 + t) \
		+ p1 * (-2.0 * t3 + 3.0 * t2) + m1 * (t3 - t2)
	var d: Vector2 = p0 * (6.0 * t2 - 6.0 * t) + m0 * (3.0 * t2 - 4.0 * t + 1.0) \
		+ p1 * (6.0 * t - 6.0 * t2) + m1 * (3.0 * t2 - 2.0 * t)
	if d.length_squared() < 1e-12:
		d = _tan[i]
	d = d.normalized()
	var g: float = profile.grade_at(s) / 100.0
	var fwd := Vector3(d.x, g, d.y).normalized()
	var right := Vector3(-d.y, 0.0, d.x)
	out.position = Vector3(pos.x, profile.height_at(s), pos.y)
	out.forward = fwd
	out.up = right.cross(fwd).normalized()
	out.grade = g


# ---------------------------------------------------------------------------
# Построение плана (один раз)
# ---------------------------------------------------------------------------

func _build(def: RouteCatalog.RouteDef) -> void:
	route = def
	route_id = def.id
	profile = def.profile
	_length = profile.length_m()
	_n = maxi(int(ceil(_length / STEP_M)), 8)
	_step = _length / float(_n)
	var best_gap: float = -1.0
	var best_pts := PackedVector2Array()
	var best_tan := PackedVector2Array()
	for a in MAX_ATTEMPTS:
		var rng := RandomNumberGenerator.new()
		rng.seed = def.seed + a * 7919
		var plan := Plan.new()
		var turn: float = _design(def, rng, plan)
		if not _close(plan, turn):
			continue
		var gap: float = _min_gap()
		if gap > best_gap:
			best_gap = gap
			best_pts = _pts.duplicate()
			best_tan = _tan.duplicate()
			attempt = a
		if gap >= MIN_GAP_M:
			break
	if best_gap < 0.0:
		push_error("ProfiledTrack: plan of route %s did not close" % def.id)
		_fallback_circle()
		return
	_pts = best_pts
	_tan = best_tan
	min_gap_m = best_gap
	if best_gap < MIN_GAP_M:
		push_warning("ProfiledTrack %s: loop parts come within %.0f m" % [def.id, best_gap])


## Окружность длиной L — на случай, если план не замкнулся (не должно случаться).
func _fallback_circle() -> void:
	var r: float = _length / TAU
	_pts.resize(_n + 1)
	_tan.resize(_n + 1)
	for i in _n + 1:
		var a: float = TAU * float(i) / float(_n)
		_pts[i] = Vector2(sin(a), 1.0 - cos(a)) * r
		_tan[i] = Vector2(cos(a), sin(a))
	min_gap_m = 2.0 * r


## Примитивы плана по форме трассы; возвращает знак суммы поворотов (+1 — петля вправо).
func _design(def: RouteCatalog.RouteDef, rng: RandomNumberGenerator, plan: Plan) -> float:
	var shape: String = String(def.layout.get("shape", "quad"))
	match shape:
		"winding":
			return _design_winding(def.layout, rng, plan)
		"pass_loop":
			return _design_pass_loop(def.layout, rng, plan)
		"d_loop":
			return _design_d_loop(def.layout, rng, plan)
	return _design_quad(def.layout, rng, plan)


## Равнина: неправильный четырёхугольник — четыре дуги R 250–600 м по ~90°, длинные прямые,
## на двух сторонах пологая S-связка (`waviness`).
func _design_quad(layout: Dictionary, rng: RandomNumberGenerator, plan: Plan) -> float:
	var radii: Vector2 = layout.get("arc_radius_m", Vector2(250.0, 600.0))
	var wave: float = float(layout.get("waviness", 0.15))
	var angles := PackedFloat64Array()
	var sum: float = 0.0
	for k in 4:
		angles.append(90.0 + rng.randf_range(-18.0, 18.0))
		sum += angles[k]
	var corner_r := PackedFloat64Array()
	var fixed: float = 0.0
	for k in 4:
		angles[k] *= 360.0 / sum
		corner_r.append(rng.randf_range(radii.x + 100.0, radii.y))
		fixed += corner_r[k] * deg_to_rad(angles[k])
	var wiggle_deg: float = 100.0 * wave + rng.randf_range(-3.0, 3.0)
	var wiggle_r: float = 700.0
	fixed += 2.0 * 2.0 * wiggle_r * deg_to_rad(wiggle_deg)
	var straights: float = _length - fixed
	var weights: Array[float] = [1.2, 0.8, 1.2, 0.8]
	for k in 4:
		var side: float = straights * weights[k] / 4.0
		var group: int = k if k < 3 else -1
		if k % 2 == 0:
			var first: float = side * rng.randf_range(0.45, 0.65)
			plan.straight(first, group)
			plan.s_bend(wiggle_r, wiggle_deg * (1.0 if k == 0 else -1.0), 0.0)
			plan.straight(side - first, group)
		else:
			plan.straight(side, group)
		plan.arc(corner_r[k], angles[k], true)
	return 1.0


## Холмы: шесть углов по ~60° R 120–250 м, на каждой стороне три S-связки R 80–200 м,
## прямые между ними ≤ ~600 м.
func _design_winding(layout: Dictionary, rng: RandomNumberGenerator, plan: Plan) -> float:
	var radii: Vector2 = layout.get("arc_radius_m", Vector2(80.0, 250.0))
	var corners: int = 6
	var angles := PackedFloat64Array()
	var sum: float = 0.0
	for k in corners:
		angles.append(60.0 + rng.randf_range(-15.0, 15.0))
		sum += angles[k]
	var fixed: float = 0.0
	var corner_r := PackedFloat64Array()
	for k in corners:
		angles[k] *= 360.0 / sum
		corner_r.append(rng.randf_range(120.0, radii.y))
		fixed += corner_r[k] * deg_to_rad(angles[k])
	var bends: Array[Vector3] = []
	for k in corners * 3:
		var r: float = rng.randf_range(radii.x, 200.0)
		var deg: float = rng.randf_range(30.0, 60.0) * (1.0 if (k + rng.randi_range(0, 1)) % 2 == 0 else -1.0)
		var gap: float = rng.randf_range(60.0, 160.0)
		bends.append(Vector3(r, deg, gap))
		fixed += 2.0 * r * deg_to_rad(absf(deg)) + gap
	var per_straight: float = (_length - fixed) / float(corners * 4)
	for k in corners:
		var group: int = k / 2 if k % 2 == 0 else -1
		for j in 3:
			plan.straight(per_straight * rng.randf_range(0.8, 1.2), group)
			var b: Vector3 = bends[k * 3 + j]
			plan.s_bend(b.x, b.y, b.z)
		plan.straight(per_straight * rng.randf_range(0.8, 1.2), group)
		plan.arc(corner_r[k], angles[k], true)
	return 1.0


## Перевал — петля: долина (0–3 км) вдоль реки, подъём по одному склону (траверс, затем
## «змейка» из `switchback_count` виражей R 40–60 м на 150° с траверсами ~330 м), седловина,
## спуск по другому склону (S-связки R 80–150 м), снова долина. Регулируемые прямые — после
## подъёма (седловина, спуск, долина), чтобы змейка осталась на крутой части профиля.
func _design_pass_loop(layout: Dictionary, rng: RandomNumberGenerator, plan: Plan) -> float:
	var sw_count: int = int(layout.get("switchback_count", 7))
	var sw_r: Vector2 = layout.get("switchback_radius_m", Vector2(40.0, 60.0))
	var desc_r: Vector2 = layout.get("descent_radius_m", Vector2(80.0, 150.0))
	var climb: Vector2 = layout.get("climb_range_m", Vector2(3000.0, 10000.0))
	var traverse: float = rng.randf_range(320.0, 360.0)
	var zig_r: float = rng.randf_range(sw_r.x + 5.0, sw_r.y)
	var zig_turn: float = 150.0
	# Долина до подъёма: прямые и пологие изгибы R ≥ 300 м.
	var bend_deg: float = rng.randf_range(8.0, 14.0)
	var valley_r: float = rng.randf_range(400.0, 600.0)
	var corner_a_r: float = 320.0
	var valley_len: float = climb.x - 200.0 - corner_a_r * deg_to_rad(90.0) * 0.5
	var valley_bends: float = 4.0 * valley_r * deg_to_rad(bend_deg)
	var vs: float = (valley_len - valley_bends) / 3.0
	plan.straight(vs)
	plan.s_bend(valley_r, -bend_deg, 0.0)
	plan.straight(vs)
	plan.s_bend(valley_r, bend_deg, 0.0)
	plan.straight(vs)
	plan.arc(corner_a_r, 90.0, true)
	# Змейка заканчивается к концу подъёма; перед ней — траверс по склону.
	var zig_len: float = float(sw_count + 1) * traverse + float(sw_count) * zig_r * deg_to_rad(zig_turn)
	var entry_r: float = 150.0
	var entry_len: float = entry_r * deg_to_rad(75.0)
	var zig_start: float = climb.y - 100.0 - zig_len
	var approach: float = zig_start - entry_len - plan.total()
	var appr_r: float = rng.randf_range(220.0, 300.0)
	var appr_deg: float = rng.randf_range(18.0, 28.0)
	var appr_straight: float = (approach - 4.0 * appr_r * deg_to_rad(appr_deg)) / 3.0
	plan.straight(appr_straight)
	plan.arc(appr_r, appr_deg)
	plan.arc(appr_r, -appr_deg)
	plan.straight(appr_straight)
	plan.arc(appr_r, -appr_deg)
	plan.arc(appr_r, appr_deg)
	plan.straight(appr_straight)
	plan.arc(entry_r, 75.0, true)
	for k in sw_count:
		plan.straight(traverse)
		plan.arc(zig_r, -zig_turn if k % 2 == 0 else zig_turn)
	plan.straight(traverse)
	# Седловина перевала: широкая дуга на +90° и прямая; остальной поворот к другому склону —
	# уже на спуске (разворота на вершине нет, D3D-08 п.10).
	plan.arc(350.0, 90.0, true)
	plan.straight(700.0, 0)
	plan.arc(250.0, 75.0, true)
	plan.straight(300.0)
	plan.arc(150.0, 60.0, true)
	# Спуск по другому склону: S-связки R 80–150 м.
	var descent_end: float = 17000.0
	var descent: float = descent_end - plan.total()
	var bends: Array[Vector3] = []
	var bend_total: float = 0.0
	for k in 5:
		var r: float = rng.randf_range(desc_r.x, desc_r.y)
		var deg: float = rng.randf_range(35.0, 55.0) * (1.0 if k % 2 == 0 else -1.0)
		var gap: float = rng.randf_range(80.0, 200.0)
		bends.append(Vector3(r, deg, gap))
		bend_total += 2.0 * r * deg_to_rad(absf(deg)) + gap
	var ds: float = (descent - bend_total) / 6.0
	for k in 5:
		plan.straight(ds * rng.randf_range(0.8, 1.2), 1)
		plan.s_bend(bends[k].x, bends[k].y, bends[k].z)
	plan.straight(ds, 1)
	# Снова долина: угол к курсу старта и прямые вдоль реки.
	plan.arc(350.0, 120.0, true)
	var rest: float = _length - plan.total() - 2.0 * valley_r * deg_to_rad(bend_deg)
	plan.straight(rest * 0.5, 2)
	plan.s_bend(valley_r, bend_deg, 0.0)
	plan.straight(rest * 0.5, 2)
	return 1.0


## Приморье — «D»: береговая сторона (0–4.8 км, море справа — снаружи петли, петля влево)
## с двумя пологими дугами набережной R 600–800 м, угол и прямая через реку с мостом
## (`bridges`, мост — внутри прямой), мыс с поворотами R 60–120 м и дуга к старту.
## Регулируемые прямые — после моста (мост остаётся на своём s).
func _design_d_loop(layout: Dictionary, rng: RandomNumberGenerator, plan: Plan) -> float:
	var coast: Vector2 = layout.get("coast_range_m", Vector2(0.0, 4800.0))
	var coast_r: Vector2 = layout.get("coast_radius_m", Vector2(300.0, 800.0))
	var cape_r: Vector2 = layout.get("cape_radius_m", Vector2(60.0, 120.0))
	var bridge_end: float = 6330.0
	if route != null and not route.bridges.is_empty():
		bridge_end = route.bridges[route.bridges.size() - 1].y
	# Набережная: прямые и две пологие дуги влево (в сумме ~60°).
	var r1: float = rng.randf_range(coast_r.y - 200.0, coast_r.y)
	var d1: float = rng.randf_range(27.0, 33.0)
	var cs: float = (coast.y - 2.0 * r1 * deg_to_rad(d1)) / 3.0
	plan.straight(cs * rng.randf_range(0.9, 1.1))
	plan.arc(r1, -d1)
	plan.straight(cs * rng.randf_range(0.9, 1.1))
	plan.arc(r1, -d1)
	plan.straight(coast.y - plan.total())
	# Угол у устья и прямая через реку с мостом.
	plan.arc(coast_r.x, -rng.randf_range(85.0, 95.0), true)
	plan.straight(bridge_end + 200.0 - plan.total())
	# Пологая дуга к мысу, повороты мыса R 60–120 м, дуга к старту.
	plan.arc(coast_r.y, -rng.randf_range(45.0, 55.0), true)
	plan.straight(1300.0, 0)
	plan.arc(rng.randf_range(cape_r.x + 20.0, cape_r.y - 20.0), -rng.randf_range(27.0, 33.0), true)
	plan.straight(1300.0, 1)
	plan.arc(rng.randf_range(cape_r.x + 30.0, cape_r.y), -rng.randf_range(36.0, 44.0), true)
	plan.straight(1300.0, 2)
	plan.arc(coast_r.x, -90.0, true)
	return -1.0


## Замкнуть план: поворот ровно на ±360°, длина L, конец = начало; затем разложить в узлы.
## false — регулируемые прямые не уложились в `MIN_STRAIGHT_M`.
func _close(plan: Plan, turn: float) -> bool:
	# Сумма поворотов: подгоняются длины «углов».
	var total_turn: float = 0.0
	var corner_turn: float = 0.0
	for k in plan.size():
		total_turn += plan.kappas[k] * plan.lengths[k]
		if plan.corners[k] == 1:
			corner_turn += plan.kappas[k] * plan.lengths[k]
	var want: float = corner_turn + (turn * TAU - total_turn)
	if absf(corner_turn) < 1e-6 or want / corner_turn <= 0.2:
		return false
	var scale: float = want / corner_turn
	for k in plan.size():
		if plan.corners[k] == 1:
			plan.lengths[k] *= scale
	# Курсы групп регулируемых прямых.
	var heading := PackedFloat64Array()
	heading.resize(3)
	var seen := PackedByteArray()
	seen.resize(3)
	var theta: float = 0.0
	for k in plan.size():
		var g: int = plan.groups[k]
		if g >= 0 and g < 3:
			if seen[g] == 0:
				heading[g] = theta
				seen[g] = 1
			elif absf(wrapf(theta - heading[g], -PI, PI)) > 1e-6:
				push_error("ProfiledTrack: straights of group %d have different headings" % g)
				return false
		theta += plan.kappas[k] * plan.lengths[k]
	for g in 3:
		if seen[g] == 0:
			return false
	var det_m := Basis(Vector3(cos(heading[0]), sin(heading[0]), 1.0), Vector3(cos(heading[1]), sin(heading[1]), 1.0),
		Vector3(cos(heading[2]), sin(heading[2]), 1.0))
	if absf(det_m.determinant()) < 0.05:
		return false
	var inv: Basis = det_m.inverse()
	for it in 4:
		var e: Vector2 = _integrate(plan)
		var rhs := Vector3(-e.x, -e.y, _length - plan.total())
		var delta: Vector3 = inv * rhs
		for g in 3:
			var group_len: float = 0.0
			for k in plan.size():
				if plan.groups[k] == g:
					group_len += plan.lengths[k]
			for k in plan.size():
				if plan.groups[k] == g:
					plan.lengths[k] += delta[g] * plan.lengths[k] / group_len
					if plan.lengths[k] < MIN_STRAIGHT_M:
						return false
		if e.length() < 1e-3 and absf(rhs.z) < 1e-6:
			break
	var e_final: Vector2 = _integrate(plan)
	if e_final.length() > 1.0:
		return false
	# Остаток невязки — линейно по дистанции (доли миллиметра на метр).
	for i in _n + 1:
		_pts[i] -= e_final * float(i) / float(_n)
	_pts[_n] = _pts[0]
	_tan[_n] = _tan[0]
	# Центр габарита — в начале координат (меньше координаты — точнее float в рендере).
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p in _pts:
		lo = lo.min(p)
		hi = hi.max(p)
	var center: Vector2 = (lo + hi) * 0.5
	for i in _n + 1:
		_pts[i] -= center
	return true


## Кривизна по узлам → сглаживание → курс и точки плана. Возвращает невязку конца.
func _integrate(plan: Plan) -> Vector2:
	var kappa := PackedFloat64Array()
	kappa.resize(_n)
	# Средняя кривизна примитивов в каждой ячейке [i·step; (i+1)·step].
	var seg: int = 0
	var seg_start: float = 0.0
	var count: int = plan.size()
	for i in _n:
		var a: float = float(i) * _step
		var b: float = a + _step
		var acc: float = 0.0
		var k: int = seg
		var k_start: float = seg_start
		while k < count and k_start < b:
			var k_end: float = k_start + plan.lengths[k] if k < count - 1 else INF
			var lo: float = maxf(a, k_start)
			var hi: float = minf(b, k_end)
			if hi > lo:
				acc += plan.kappas[k] * (hi - lo)
			if k_end <= b:
				k += 1
				k_start = k_end
				seg = k
				seg_start = k_start
			else:
				break
		kappa[i] = acc / _step
	var w: int = maxi(int(round(SMOOTH_WINDOW_M / _step)) | 1, 1)
	kappa = _box(_box(kappa, w), w)
	_pts.resize(_n + 1)
	_tan.resize(_n + 1)
	var theta: float = 0.0
	var p := Vector2.ZERO
	for i in _n:
		_pts[i] = p
		_tan[i] = Vector2(cos(theta), sin(theta))
		var mid: float = theta + kappa[i] * _step * 0.5
		p += Vector2(cos(mid), sin(mid)) * _step
		theta += kappa[i] * _step
	_pts[_n] = p
	_tan[_n] = Vector2(cos(theta), sin(theta))
	return p - _pts[0]


## Периодическое скользящее среднее шириной `w` (нечётное) — сумма сохраняется.
static func _box(values: PackedFloat64Array, w: int) -> PackedFloat64Array:
	var n: int = values.size()
	var half: int = w / 2
	var out := PackedFloat64Array()
	out.resize(n)
	var acc: float = 0.0
	for j in range(-half, half + 1):
		acc += values[posmod(j, n)]
	for i in n:
		out[i] = acc / float(w)
		acc += values[posmod(i + half + 1, n)] - values[posmod(i - half, n)]
	return out


## Наименьшее расстояние между точками плана, разнесёнными по дуге не меньше `GAP_ARC_M`.
func _min_gap() -> float:
	var every: int = maxi(int(round(CHECK_STEP_M / _step)), 1)
	var cell: float = MIN_GAP_M * 2.0
	var grid: Dictionary = {}
	var idx := PackedInt32Array()
	for i in range(0, _n, every):
		idx.append(i)
		var key := Vector2i(floori(_pts[i].x / cell), floori(_pts[i].y / cell))
		if not grid.has(key):
			grid[key] = PackedInt32Array()
		var list: PackedInt32Array = grid[key]
		list.append(i)
		grid[key] = list
	var best: float = cell
	for i in idx:
		var key := Vector2i(floori(_pts[i].x / cell), floori(_pts[i].y / cell))
		for dz in range(-1, 2):
			for dx in range(-1, 2):
				var other := key + Vector2i(dx, dz)
				if not grid.has(other):
					continue
				for j in (grid[other] as PackedInt32Array):
					var sep: float = absf(float(j - i)) * _step
					sep = minf(sep, _length - sep)
					if sep < GAP_ARC_M:
						continue
					best = minf(best, _pts[i].distance_to(_pts[j]))
	return best
