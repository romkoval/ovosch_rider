extends GutTest
## Независимая приёмка доменной модели (T-005/T-008, коммит 0ca2af5) по критериям
## `docs/requirements.md`: REQ-INT-03, REQ-INT-05, REQ-WRK-07, REQ-PRF-02 (крит. 2, 3, 5, 6),
## REQ-HUD-03 (крит. 1, 3), REQ-HUD-04 (крит. 1, 2), REQ-HUD-09 (крит. 1–3).
## Имена: test_req_<area>_<nn>_c<k>_<описание>. Критерии про UI/парсеры/исполнитель здесь не
## проверяются (n/a на этом этапе).

const FTP: int = 200
const NO_DATA: int = -1


func _steps(arr: Array) -> Array[WorkoutStep]:
	var out: Array[WorkoutStep] = []
	for s in arr:
		out.append(s)
	return out


func _pct(arr: Array) -> Array[float]:
	var out: Array[float] = []
	for v in arr:
		out.append(float(v))
	return out


# ---------------------------------------------------------------------------
# REQ-INT-03 — модель шага: длительность, цель % FTP / Вт, рампа, повторы, каденс, подсказки
# ---------------------------------------------------------------------------

func test_req_int_03_c1_percent_step_keeps_seconds_and_pct() -> void:
	# `10m 65%` → 600 с, 65 % FTP (число сохраняется, не пересчитывается в ватты).
	var s := WorkoutStep.percent(600, 65.0)
	assert_eq(s.duration_sec, 600, "длительность в секундах")
	assert_eq(s.target_kind, WorkoutStep.TargetKind.PERCENT_FTP, "тип цели — % FTP")
	assert_eq(s.target_start, 65.0, "число цели сохранено")
	assert_eq(s.target_end, 65.0, "постоянный шаг: конец = начало")
	assert_false(s.is_ramp())
	assert_false(s.is_free_ride())
	assert_eq(s.target_watts_at(0.0, FTP), 130, "65 % от 200 = 130 Вт")
	assert_eq(s.target_watts_at(599.0, FTP), 130, "цель постоянна на всём шаге")


func test_req_int_03_c2_watts_step_keeps_watts_regardless_of_ftp() -> void:
	# `5m 250w` → 300 с, 250 Вт; FTP на такой шаг не влияет.
	var s := WorkoutStep.watts(300, 250.0)
	assert_eq(s.duration_sec, 300)
	assert_eq(s.target_kind, WorkoutStep.TargetKind.WATTS)
	assert_eq(s.target_start, 250.0)
	assert_eq(s.target_watts_at(0.0, 200), 250)
	assert_eq(s.target_watts_at(150.0, 999), 250, "ватты не зависят от FTP")
	assert_eq(s.target_watts_at(150.0, 0), 250, "ватты не зависят от FTP 0")


func test_req_int_03_c3_mid_range_target_representable() -> void:
	# Само правило «середина диапазона» — у парсера (n/a). Модель должна уметь хранить 65 %
	# как постоянную цель — проверяем лишь представимость.
	var s := WorkoutStep.percent(60, (60.0 + 70.0) / 2.0)
	assert_eq(s.target_start, 65.0)
	assert_false(s.is_ramp())


func test_req_int_03_c4_ramp_keeps_start_and_end_targets() -> void:
	var r := WorkoutStep.ramp_percent(600, 50.0, 100.0)
	assert_true(r.is_ramp())
	assert_eq(r.target_start, 50.0)
	assert_eq(r.target_end, 100.0)
	assert_eq(r.start_watts(FTP), 100, "начало рампы = 50 % × 200")
	assert_eq(r.end_watts(FTP), 200, "конец рампы = 100 % × 200")
	assert_eq(r.target_watts_at(300.0, FTP), 150, "середина рампы линейна")
	var rw := WorkoutStep.ramp_watts(120, 150.0, 250.0)
	assert_true(rw.is_ramp())
	assert_eq(rw.start_watts(0), 150)
	assert_eq(rw.end_watts(0), 250)
	assert_eq(rw.target_watts_at(60.0, 0), 200)


func test_req_int_03_c4_descending_ramp_is_linear() -> void:
	var r := WorkoutStep.ramp_watts(100, 300.0, 100.0)
	assert_eq(r.target_watts_at(0.0, FTP), 300)
	assert_eq(r.target_watts_at(25.0, FTP), 250)
	assert_eq(r.target_watts_at(100.0, FTP), 100)


func test_req_int_03_c4_edge_zero_duration_ramp_is_invalid_and_does_not_crash() -> void:
	var r := WorkoutStep.ramp_watts(0, 100.0, 200.0)
	# Не должно быть деления на ноль; значение детерминировано.
	var w0 := r.target_watts_at(0.0, FTP)
	var w1 := r.target_watts_at(5.0, FTP)
	assert_true(w0 >= 0 and w1 >= 0, "без исключений и отрицательных значений")
	var errors := r.validate()
	assert_gt(errors.size(), 0, "шаг нулевой длительности невалиден")
	var w := Workout.make("zero ramp", _steps([r]))
	assert_false(w.is_valid())
	assert_eq(w.total_duration_sec(), 0)
	assert_eq(w.power_profile(FTP).size(), 0, "профиль пустого по времени плана пуст")


func test_req_int_03_c5_expand_repeat_count_times_block_size() -> void:
	var block := _steps([WorkoutStep.percent(60, 120.0), WorkoutStep.percent(120, 50.0)])
	var flat := Workout.expand_repeat(block, 3)
	assert_eq(flat.size(), 6, "3 повтора × 2 шага = 6")
	for i in 3:
		assert_eq(flat[i * 2].target_start, 120.0, "повтор %d: ON" % i)
		assert_eq(flat[i * 2 + 1].target_start, 50.0, "повтор %d: OFF" % i)
	var w := Workout.make("repeat", flat)
	assert_eq(w.total_duration_sec(), 540)
	assert_eq(w.steps.size(), 6, "в модели хранится плоская последовательность")


func test_req_int_03_c5_edge_expand_repeat_count_1_and_0() -> void:
	var block := _steps([WorkoutStep.percent(60, 120.0), WorkoutStep.percent(120, 50.0)])
	var once := Workout.expand_repeat(block, 1)
	assert_eq(once.size(), 2, "1 повтор = сам блок")
	assert_false(once[0] == block[0], "повтор — копия, а не тот же объект")
	assert_eq(once[0].target_start, block[0].target_start)
	assert_eq(Workout.expand_repeat(block, 0).size(), 0, "0 повторов — пусто")
	assert_eq(Workout.expand_repeat(block, -2).size(), 0, "отрицательное число повторов — пусто")
	assert_eq(Workout.expand_repeat(_steps([]), 5).size(), 0, "пустой блок — пусто")


func test_req_int_03_c5_expand_repeat_copies_are_independent() -> void:
	var step := WorkoutStep.percent(60, 100.0)
	step.cadence_rpm = 90
	step.text_cues.append(TextCue.make(10, "Держи"))
	var flat := Workout.expand_repeat(_steps([step]), 2)
	flat[0].target_start = 1.0
	flat[0].cadence_rpm = 1
	flat[0].text_cues[0].text = "изменено"
	assert_eq(flat[1].target_start, 100.0, "правка первого повтора не трогает второй")
	assert_eq(flat[1].cadence_rpm, 90)
	assert_eq(flat[1].text_cues[0].text, "Держи", "подсказки скопированы глубоко")
	assert_eq(step.target_start, 100.0, "исходный блок не изменён")
	assert_eq(step.text_cues[0].text, "Держи")


func test_req_int_03_c6_cadence_transferred_and_not_set_by_default() -> void:
	var s := WorkoutStep.percent(60, 80.0)
	assert_eq(s.cadence_rpm, 0, "каденс по умолчанию «не задан» (0)")
	s.cadence_rpm = 95
	assert_eq(s.cadence_rpm, 95)
	assert_eq(s.validate().size(), 0)
	assert_eq(s.duplicate_step().cadence_rpm, 95, "каденс переживает копирование")


func test_req_int_03_c6_edge_negative_cadence_rejected() -> void:
	var s := WorkoutStep.percent(60, 80.0)
	s.cadence_rpm = -5
	assert_gt(s.validate().size(), 0, "отрицательный каденс — ошибка валидации")


func test_req_int_03_c7_text_cue_kept_with_offset() -> void:
	var s := WorkoutStep.percent(300, 90.0)
	s.text_cues.append(TextCue.make(0, "Старт интервала"))
	s.text_cues.append(TextCue.make(299, "Последняя секунда"))
	assert_eq(s.text_cues.size(), 2)
	assert_eq(s.text_cues[0].at_sec, 0)
	assert_eq(s.text_cues[0].text, "Старт интервала")
	assert_eq(s.text_cues[1].at_sec, 299)
	assert_eq(s.validate().size(), 0, "подсказки внутри [0; duration) валидны")


func test_req_int_03_c7_edge_cue_outside_step_rejected() -> void:
	var s := WorkoutStep.percent(300, 90.0)
	s.text_cues.append(TextCue.make(300, "вне шага"))
	assert_gt(s.validate().size(), 0, "подсказка на at_sec == duration — вне шага")
	var s2 := WorkoutStep.percent(300, 90.0)
	s2.text_cues.append(TextCue.make(-1, "вне шага"))
	assert_gt(s2.validate().size(), 0, "отрицательное смещение подсказки")


func test_req_int_03_c8_total_duration_sums_all_steps_exactly() -> void:
	var w := Workout.make("sum", _steps([
		WorkoutStep.percent(600, 50.0),
		WorkoutStep.ramp_percent(300, 50.0, 100.0),
		WorkoutStep.free_ride(120),
		WorkoutStep.watts(7, 250.0),
	]))
	assert_eq(w.total_duration_sec(), 1027, "сумма без потерь (в т.ч. свободная езда)")


func test_req_int_03_c9_invalid_plan_is_not_valid() -> void:
	# Сама ошибка разбора «с указанием позиции» — у парсера (n/a). Модель: частично собранный
	# план с дефектным шагом не проходит валидацию, с указанием номера шага.
	var w := Workout.make("bad", _steps([
		WorkoutStep.percent(600, 50.0),
		WorkoutStep.percent(0, 50.0),
		WorkoutStep.percent(60, -10.0),
	]))
	assert_false(w.is_valid())
	var errors := w.validate()
	assert_eq(errors.size(), 2, "по одной ошибке на дефектный шаг")
	assert_string_contains(errors[0], "шаг 2")
	assert_string_contains(errors[1], "шаг 3")
	assert_false(Workout.new().is_valid(), "пустой план невалиден")
	assert_true(Workout.make("ok", _steps([WorkoutStep.percent(60, 50.0)])).is_valid())


func test_req_int_03_edge_negative_values_rejected_and_clamped() -> void:
	var neg_pct := WorkoutStep.percent(60, -50.0)
	assert_gt(neg_pct.validate().size(), 0, "отрицательный % FTP — ошибка")
	assert_eq(neg_pct.target_watts_at(0.0, FTP), 0, "цель не уходит в минус")
	var neg_w := WorkoutStep.watts(60, -100.0)
	assert_gt(neg_w.validate().size(), 0, "отрицательные ватты — ошибка")
	assert_eq(neg_w.target_watts_at(30.0, FTP), 0)
	var neg_ramp := WorkoutStep.ramp_watts(60, 100.0, -100.0)
	assert_gt(neg_ramp.validate().size(), 0, "рампа в минус — ошибка")
	assert_eq(neg_ramp.target_watts_at(60.0, FTP), 0)
	var neg_dur := WorkoutStep.percent(-60, 50.0)
	assert_gt(neg_dur.validate().size(), 0, "отрицательная длительность — ошибка")
	var w := Workout.make("neg", _steps([WorkoutStep.percent(60, 50.0), neg_dur]))
	assert_false(w.is_valid())


func test_req_int_03_edge_ftp_zero_and_negative_give_zero_watts_for_pct() -> void:
	var s := WorkoutStep.percent(60, 100.0)
	assert_eq(s.target_watts_at(10.0, 0), 0, "FTP 0 → 0 Вт (без деления на ноль)")
	assert_eq(s.target_watts_at(10.0, -200), 0, "отрицательный FTP → 0 Вт, не минус")
	var w := Workout.make("ftp0", _steps([s]))
	assert_eq(w.target_watts_at(10.0, 0), 0)
	var profile := w.power_profile(0)
	assert_eq(profile.size(), 60)
	assert_eq(profile[0], 0)
	assert_eq(profile[59], 0)


func test_req_int_03_edge_offset_outside_step_is_clamped() -> void:
	var r := WorkoutStep.ramp_watts(60, 100.0, 200.0)
	assert_eq(r.target_watts_at(-10.0, FTP), 100, "до начала — цель начала")
	assert_eq(r.target_watts_at(1000.0, FTP), 200, "после конца — цель конца")


# ---------------------------------------------------------------------------
# REQ-INT-05 — профиль целевой мощности
# ---------------------------------------------------------------------------

func test_req_int_05_c1_two_steps_profile_at_ftp_200() -> void:
	var w := Workout.make("10m 50% / 5m 100%", _steps([
		WorkoutStep.percent(600, 50.0), WorkoutStep.percent(300, 100.0)]))
	var p := w.power_profile(FTP)
	assert_eq(p.size(), 900, "одна точка на секунду, t = индекс")
	assert_eq(p[0], 100, "t=0: 100 Вт")
	assert_eq(p[599], 100, "t=599: ещё 100 Вт")
	assert_eq(p[600], 200, "t=600: уже 200 Вт")
	assert_eq(p[899], 200, "t=899: 200 Вт")
	var ok := true
	for t in 900:
		var expected := 100 if t < 600 else 200
		if p[t] != expected:
			ok = false
			break
	assert_true(ok, "ступени 100 Вт на [0;600) и 200 Вт на [600;900) без выбросов")


func test_req_int_05_c1_profile_consistent_with_target_watts_at() -> void:
	var w := Workout.make("mix", _steps([
		WorkoutStep.percent(10, 50.0), WorkoutStep.ramp_watts(10, 100.0, 200.0),
		WorkoutStep.free_ride(5), WorkoutStep.watts(5, 300.0)]))
	var p := w.power_profile(FTP)
	assert_eq(p.size(), 30)
	for t in 30:
		assert_eq(p[t], w.target_watts_at(float(t), FTP), "профиль[t] == цель в момент t (t=%d)" % t)


func test_req_int_05_c1_profile_resolution_length_is_ceil() -> void:
	var w := Workout.make("res", _steps([WorkoutStep.percent(600, 50.0), WorkoutStep.percent(300, 100.0)]))
	var p60 := w.power_profile(FTP, 60)
	assert_eq(p60.size(), 15, "900 / 60 = 15 слотов")
	assert_eq(p60[9], 100, "t=540")
	assert_eq(p60[10], 200, "t=600")
	var p7 := w.power_profile(FTP, 7)
	assert_eq(p7.size(), ceili(900.0 / 7.0), "ceil(900/7) = 129")
	assert_eq(p7[128], 200, "последний слот начинается на 896 с → 200 Вт")
	var p0 := w.power_profile(FTP, 0)
	assert_eq(p0.size(), 900, "разрешение 0 трактуется как 1 с")


func test_req_int_05_c2_ramp_profile_is_linear_and_starts_at_start_target() -> void:
	var w := Workout.make("ramp", _steps([WorkoutStep.ramp_watts(60, 100.0, 200.0)]))
	var p := w.power_profile(FTP)
	assert_eq(p.size(), 60)
	assert_eq(p[0], 100, "первая точка = цель начала")
	assert_eq(p[30], 150, "середина")
	# Линейность: монотонно неубывающая, шаг не больше 2 Вт при наклоне 100 Вт / 60 с.
	var monotone := true
	for t in range(1, 60):
		if p[t] < p[t - 1] or p[t] - p[t - 1] > 2:
			monotone = false
	assert_true(monotone, "профиль рампы линейный/монотонный")


func test_req_int_05_c2_ramp_profile_end_point_equals_end_target() -> void:
	# REQ-INT-05 крит. 2: «начальная и конечная точки равны целям начала и конца».
	# Уточнение спецификации (после D-1): носитель точек (t, Вт) для графика —
	# `power_points`; `power_profile` — посекундная выборка (profile[t] == target_watts_at(t)).
	var ramp := WorkoutStep.ramp_watts(60, 100.0, 200.0)
	var w := Workout.make("ramp", _steps([ramp]))
	var pts := w.power_points(FTP)
	assert_eq(pts.size(), 2, "одиночная рампа — две точки")
	assert_eq(pts[0], Vector2(0.0, 100.0), "начальная точка (0, 100) = цель начала")
	assert_eq(pts[1], Vector2(60.0, 200.0), "конечная точка (60, 200) = цель конца")
	# Посекундная выборка остаётся согласованной с целью по времени.
	var p := w.power_profile(FTP)
	assert_eq(p[0], 100)
	assert_eq(p[59], w.target_watts_at(59.0, FTP))


func test_req_int_05_c2_ramp_profile_end_point_pct_ramp_at_ftp_200() -> void:
	# Тот же критерий для рампы в % FTP как последнего шага плана (60 с, 50 → 100 %)
	# и для рампы вниз в середине плана: концы рамп равны целям начала/конца.
	var w := Workout.make("ramp pct", _steps([
		WorkoutStep.percent(60, 50.0), WorkoutStep.ramp_percent(60, 50.0, 100.0)]))
	var pts := w.power_points(FTP)
	assert_eq(pts.size(), 4)
	assert_eq(pts[2], Vector2(60.0, 100.0), "начало рампы = 50 % × 200 в t=60")
	assert_eq(pts[3], Vector2(120.0, 200.0), "конец рампы = 100 % × 200 в t=120")
	var w2 := Workout.make("ramp down", _steps([
		WorkoutStep.watts(10, 300.0), WorkoutStep.ramp_watts(30, 300.0, 120.0), WorkoutStep.watts(10, 150.0)]))
	var pts2 := w2.power_points(FTP)
	assert_eq(pts2[2], Vector2(10.0, 300.0))
	assert_eq(pts2[3], Vector2(40.0, 120.0), "рампа вниз заканчивается целью конца")
	assert_eq(pts2[4], Vector2(40.0, 150.0), "скачок на стыке: та же t, новая мощность")


func test_req_int_05_c1_power_points_steps_two_points_per_step_and_jumps() -> void:
	var w := Workout.make("10m 50% / 5m 100%", _steps([
		WorkoutStep.percent(600, 50.0), WorkoutStep.percent(300, 100.0)]))
	var pts := w.power_points(FTP)
	assert_eq(pts.size(), 4, "по две точки на шаг")
	assert_eq(pts[0], Vector2(0.0, 100.0))
	assert_eq(pts[1], Vector2(600.0, 100.0), "ступень 100 Вт держится до t=600")
	assert_eq(pts[2], Vector2(600.0, 200.0), "скачок в t=600: две точки с одним t")
	assert_eq(pts[3], Vector2(900.0, 200.0))
	assert_eq(pts[pts.size() - 1].x, float(w.total_duration_sec()), "последняя t = длительность плана")
	assert_eq(Workout.new().power_points(FTP).size(), 0, "пустой план — пусто")


func test_req_int_05_c1_power_points_free_ride_and_intensity() -> void:
	var w := Workout.make("fr", _steps([
		WorkoutStep.watts(10, 200.0), WorkoutStep.free_ride(20), WorkoutStep.ramp_watts(10, 100.0, 200.0)]))
	var pts := w.power_points(FTP, 1.1)
	assert_eq(pts.size(), 6)
	assert_eq(pts[0], Vector2(0.0, 220.0), "множитель применён (200 × 1.1)")
	assert_eq(pts[2], Vector2(10.0, 0.0), "свободная езда — 0 Вт")
	assert_eq(pts[3], Vector2(30.0, 0.0))
	assert_eq(pts[4], Vector2(30.0, 110.0))
	assert_eq(pts[5], Vector2(40.0, 220.0), "конец рампы с множителем")
	# Монотонность по t.
	for i in range(1, pts.size()):
		assert_true(pts[i].x >= pts[i - 1].x, "t не убывает (i=%d)" % i)


# ---------------------------------------------------------------------------
# REQ-HUD-07 крит. 1, 2 — сегменты полосы прогресса
# ---------------------------------------------------------------------------

func test_req_hud_07_c1_segments_fields_and_sum_equals_total() -> void:
	var w := Workout.make("seg", _steps([
		WorkoutStep.percent(600, 50.0), WorkoutStep.ramp_percent(300, 50.0, 100.0), WorkoutStep.free_ride(60)]))
	var segs := w.segments(FTP)
	assert_eq(segs.size(), 3, "сегмент на шаг")
	var sum := 0
	for s in segs:
		sum += int(s["duration_sec"])
	assert_eq(sum, w.total_duration_sec(), "сумма длительностей = длительность плана")
	assert_eq(segs[0]["index"], 0)
	assert_eq(segs[0]["start_sec"], 0)
	assert_eq(segs[0]["duration_sec"], 600)
	assert_eq(segs[0]["start_watts"], 100)
	assert_eq(segs[0]["end_watts"], 100)
	assert_eq(segs[0]["zone"], 1, "100 Вт при FTP 200 — Z1")
	assert_eq(segs[1]["start_sec"], 600)
	assert_eq(segs[1]["start_watts"], 100)
	assert_eq(segs[1]["end_watts"], 200, "рампа: конец = цель конца")
	assert_eq(segs[2]["start_sec"], 900)
	assert_eq(segs[2]["start_watts"], 0, "свободная езда — 0 Вт")
	assert_eq(segs[2]["zone"], 1, "0 Вт → Z1 (HUD-03 крит. 3)")
	assert_eq(Workout.new().segments(FTP).size(), 0)


func test_req_hud_07_c2_segment_zone_recomputed_with_intensity() -> void:
	var w := Workout.make("seg", _steps([WorkoutStep.percent(60, 100.0), WorkoutStep.watts(60, 300.0)]))
	var base := w.segments(FTP)
	assert_eq(base[0]["start_watts"], 200)
	assert_eq(base[0]["zone"], 4, "200 Вт / FTP 200 = 100 % → Z4")
	assert_eq(base[1]["zone"], 6, "300 Вт = 150 % → Z6 (граница — нижняя зона)")
	var up := w.segments(FTP, 1.1)
	assert_eq(up[0]["start_watts"], 220)
	assert_eq(up[0]["zone"], 5, "220 Вт = 110 % → Z5")
	assert_eq(up[1]["start_watts"], 330)
	assert_eq(up[1]["zone"], 7, "330 Вт = 165 % → Z7")
	var down := w.segments(FTP, 0.5)
	assert_eq(down[0]["start_watts"], 100)
	assert_eq(down[0]["zone"], 1)
	assert_eq(down[1]["zone"], 2, "150 Вт = 75 % → Z2")
	assert_eq(up[0]["duration_sec"], base[0]["duration_sec"], "множитель не меняет время")


# ---------------------------------------------------------------------------
# REQ-PRF-02 крит. 4 / REQ-INT-06 крит. 3 — абсолютные границы пульса без max_hr
# ---------------------------------------------------------------------------

func test_req_prf_02_c4_custom_bpm_zones_work_without_max_hr() -> void:
	var z := HrZones.custom_bpm([108, 126, 144, 162] as Array[int])
	assert_true(z.is_absolute())
	assert_eq(z.max_hr, 0, "max_hr не задан")
	assert_eq(z.zone_count(), 5)
	assert_eq(z.validate().size(), 0, "валидны без max_hr")
	var table := {107: 1, 108: 2, 125: 2, 126: 3, 143: 3, 144: 4, 161: 4, 162: 5, 200: 5}
	for bpm in table:
		assert_eq(z.zone_of(bpm), table[bpm], "%d уд/мин → Z%d (эквивалент five_zone(180))" % [bpm, table[bpm]])
	for bpm in [50, 107, 108, 126, 144, 162, 190]:
		assert_eq(z.zone_of(bpm), HrZones.five_zone(180).zone_of(bpm), "совпадает с five_zone(180) при %d" % bpm)


func test_req_prf_02_c4_custom_bpm_no_data_and_arbitrary_count() -> void:
	var z := HrZones.custom_bpm([120, 150] as Array[int])
	assert_eq(z.zone_count(), 3, "произвольное число зон")
	assert_eq(z.zone_of(0), 0, "нет датчика → нет зоны (HUD-04 крит. 2)")
	assert_eq(z.zone_of(-1), 0, "«нет данных» → нет зоны")
	assert_eq(z.zone_of(119), 1)
	assert_eq(z.zone_of(120), 2)
	assert_eq(z.zone_of(150), 3)
	assert_eq(z.zone_of(250), 3)
	assert_eq(HrZones.custom_bpm([] as Array[int]).is_absolute(), false, "пустой список — не абсолютные зоны")
	assert_eq(HrZones.custom_bpm([] as Array[int]).zone_of(140), 0, "пустые абсолютные границы и max_hr 0 → нет зоны")


func test_req_prf_02_c4_custom_bpm_validation_and_independence() -> void:
	assert_gt(HrZones.custom_bpm([150, 120] as Array[int]).validate().size(), 0, "невозрастающие границы")
	assert_gt(HrZones.custom_bpm([120, 120] as Array[int]).validate().size(), 0, "равные границы")
	assert_gt(HrZones.custom_bpm([0, 120] as Array[int]).validate().size(), 0, "нулевая граница")
	assert_gt(HrZones.custom_bpm([-5, 120] as Array[int]).validate().size(), 0, "отрицательная граница")
	var src: Array[int] = [108, 126, 144, 162]
	var z := HrZones.custom_bpm(src)
	src[0] = 1
	assert_eq(z.boundaries_bpm[0], 108, "границы скопированы, внешняя правка не влияет")


func test_req_int_05_edge_free_ride_step_is_zero_in_profile() -> void:
	var w := Workout.make("free", _steps([
		WorkoutStep.watts(10, 150.0), WorkoutStep.free_ride(10), WorkoutStep.watts(10, 250.0)]))
	var p := w.power_profile(FTP)
	assert_eq(p.size(), 30, "свободная езда занимает время в профиле")
	assert_eq(p[9], 150)
	assert_eq(p[10], 0, "свободная езда — цель 0 Вт")
	assert_eq(p[19], 0)
	assert_eq(p[20], 250)
	assert_eq(w.target_watts_at(15.0, FTP), 0)
	assert_true(w.steps[1].is_free_ride())
	assert_eq(w.steps[1].target_watts_at(5.0, FTP, 1.5), 0, "множитель не делает свободную езду целевой")


func test_req_int_05_edge_single_second_steps_and_huge_power() -> void:
	var w := Workout.make("tiny", _steps([
		WorkoutStep.watts(1, 100.0), WorkoutStep.watts(1, 200.0), WorkoutStep.watts(1, 100000.0)]))
	var p := w.power_profile(FTP)
	assert_eq(p.size(), 3)
	assert_eq(p[0], 100)
	assert_eq(p[1], 200)
	assert_eq(p[2], 100000, "очень большие ватты не портятся")
	var big := WorkoutStep.percent(60, 10000.0)
	assert_eq(big.target_watts_at(0.0, 600), 60000, "10000 % × 600 Вт")
	assert_eq(big.validate().size(), 0, "большая, но положительная цель валидна")


func test_req_int_05_c3_n_a_segment_zone_from_profile_target() -> void:
	# Окраска сегментов — T-030 (n/a). Проверяем лишь, что зона цели сегмента вычислима.
	var w := Workout.make("z", _steps([WorkoutStep.percent(600, 50.0), WorkoutStep.percent(300, 100.0)]))
	var p := w.power_profile(FTP)
	assert_eq(Zones.power_zone(p[0], FTP), 1, "100 Вт при FTP 200 — Z1")
	assert_eq(Zones.power_zone(p[600], FTP), 4, "200 Вт при FTP 200 — Z4")


# ---------------------------------------------------------------------------
# REQ-WRK-07 — множитель интенсивности в расчёте цели
# ---------------------------------------------------------------------------

func test_req_wrk_07_c1_default_multiplier_is_100_percent() -> void:
	var s := WorkoutStep.watts(60, 200.0)
	assert_eq(s.target_watts_at(0.0, FTP), s.target_watts_at(0.0, FTP, 1.0), "по умолчанию 1.0")
	var w := Workout.make("d", _steps([s]))
	assert_eq(w.power_profile(FTP), w.power_profile(FTP, 1, 1.0))


func test_req_wrk_07_c2_multiplier_applies_to_watts_200_at_110_is_220() -> void:
	var s := WorkoutStep.watts(60, 200.0)
	assert_eq(s.target_watts_at(0.0, FTP, 1.1), 220, "200 Вт при 110 % → 220 Вт")
	assert_eq(s.target_watts_at(0.0, FTP, 0.9), 180, "200 Вт при 90 % → 180 Вт")


func test_req_wrk_07_c2_multiplier_applies_to_percent_ftp() -> void:
	var s := WorkoutStep.percent(60, 100.0)
	assert_eq(s.target_watts_at(0.0, FTP, 1.1), 220, "100 % FTP 200 при 110 % → 220 Вт")
	assert_eq(WorkoutStep.percent(60, 65.0).target_watts_at(0.0, FTP, 1.1), 143, "65 % × 200 × 1.1 = 143")


func test_req_wrk_07_c2_edge_multiplier_0_5_and_1_5() -> void:
	var sw := WorkoutStep.watts(60, 200.0)
	assert_eq(sw.target_watts_at(0.0, FTP, 0.5), 100, "200 Вт × 0.5")
	assert_eq(sw.target_watts_at(0.0, FTP, 1.5), 300, "200 Вт × 1.5")
	var sp := WorkoutStep.percent(60, 65.0)
	assert_eq(sp.target_watts_at(0.0, FTP, 0.5), 65, "130 Вт × 0.5")
	assert_eq(sp.target_watts_at(0.0, FTP, 1.5), 195, "130 Вт × 1.5")
	var r := WorkoutStep.ramp_watts(60, 100.0, 200.0)
	assert_eq(r.start_watts(FTP, 0.5), 50)
	assert_eq(r.end_watts(FTP, 1.5), 300)
	assert_eq(r.target_watts_at(30.0, FTP, 1.5), 225, "рампа: множитель к интерполированной цели")


func test_req_wrk_07_c2_edge_multiplier_zero_and_negative_do_not_go_below_zero() -> void:
	var s := WorkoutStep.watts(60, 200.0)
	assert_eq(s.target_watts_at(0.0, FTP, 0.0), 0)
	assert_eq(s.target_watts_at(0.0, FTP, -1.0), 0, "цель не отрицательна")


func test_req_wrk_07_c4_profile_reflects_multiplier() -> void:
	var w := Workout.make("m", _steps([
		WorkoutStep.percent(10, 100.0), WorkoutStep.watts(10, 200.0), WorkoutStep.ramp_watts(10, 100.0, 200.0)]))
	var p := w.power_profile(FTP, 1, 1.1)
	assert_eq(p[0], 220, "% FTP с множителем")
	assert_eq(p[10], 220, "ватты с множителем")
	assert_eq(p[20], 110, "начало рампы с множителем")
	assert_eq(p[25], 165, "середина рампы с множителем")
	assert_eq(w.target_watts_at(5.0, FTP, 1.1), 220)
	var p_half := w.power_profile(FTP, 1, 0.5)
	assert_eq(p_half[0], 100)
	assert_eq(p_half[10], 100)


# ---------------------------------------------------------------------------
# REQ-PRF-02 — зоны по умолчанию и таблица при FTP 200
# ---------------------------------------------------------------------------

func test_req_prf_02_c2_default_power_zones_are_seven_coggan() -> void:
	var z := PowerZones.coggan(FTP)
	assert_eq(z.zone_count(), 7, "7 зон Coggan")
	assert_eq(z.boundaries_pct, _pct([55, 75, 90, 105, 120, 150]), "границы 55/75/90/105/120/150 % FTP")
	assert_eq(z.validate().size(), 0)


func test_req_prf_02_c2_zone_ranges_in_percent_of_ftp() -> void:
	# Z1 ≤55 %, Z2 56–75 %, Z3 76–90 %, Z4 91–105 %, Z5 106–120 %, Z6 121–150 %, Z7 >150 %.
	# При FTP 100 проценты равны ваттам — проверяем все целые проценты 0..200.
	var z := PowerZones.coggan(100)
	for pct in range(0, 201):
		var expected: int
		if pct <= 55: expected = 1
		elif pct <= 75: expected = 2
		elif pct <= 90: expected = 3
		elif pct <= 105: expected = 4
		elif pct <= 120: expected = 5
		elif pct <= 150: expected = 6
		else: expected = 7
		assert_eq(z.zone_of(pct), expected, "%d %% FTP → Z%d" % [pct, expected])


func test_req_prf_02_c3_default_hr_zones_are_five_from_max_hr() -> void:
	var z := HrZones.five_zone(180)
	assert_eq(z.zone_count(), 5, "5 зон пульса")
	assert_eq(z.boundaries_pct, _pct([60, 70, 80, 90]), "границы 60/70/80/90 % от max_hr")
	assert_eq(z.validate().size(), 0)


func test_req_prf_02_c3_hr_zone_ranges_in_percent_of_max_hr() -> void:
	# Z1 <60 %, Z2 60–69 %, Z3 70–79 %, Z4 80–89 %, Z5 ≥90 %. При max_hr 100 проценты = уд/мин.
	var z := HrZones.five_zone(100)
	for pct in range(1, 121):
		var expected: int
		if pct < 60: expected = 1
		elif pct < 70: expected = 2
		elif pct < 80: expected = 3
		elif pct < 90: expected = 4
		else: expected = 5
		assert_eq(z.zone_of(pct), expected, "%d %% max_hr → Z%d" % [pct, expected])


func test_req_prf_02_c3_hr_boundaries_overridable() -> void:
	# Границы переопределяются вручную / из Intervals.icu — пользовательские границы работают.
	var z := HrZones.custom(200, _pct([50, 65, 80, 95]))
	assert_eq(z.zone_count(), 5)
	assert_eq(z.zone_of(99), 1)
	assert_eq(z.zone_of(100), 2, "50 % от 200 = 100 → Z2 (граница — к верхней зоне)")
	assert_eq(z.zone_of(129), 2)
	assert_eq(z.zone_of(130), 3)
	assert_eq(z.zone_of(190), 5)
	var z3 := HrZones.custom(180, _pct([70, 85]))
	assert_eq(z3.zone_count(), 3, "число зон = число границ + 1")
	assert_eq(z3.zone_of(179), 3)


func test_req_prf_02_c5_zone_instances_independent_between_profiles() -> void:
	# Профиль (T-009) ещё не реализован — проверяем независимость объектов зон:
	# изменение FTP/границ у A не трогает B.
	var a := PowerZones.coggan(200)
	var b := PowerZones.coggan(250)
	a.ftp_w = 300
	a.boundaries_pct[0] = 10.0
	assert_eq(b.ftp_w, 250, "FTP профиля B не изменился")
	assert_eq(b.boundaries_pct[0], 55.0, "границы B не изменились")
	assert_eq(PowerZones.COGGAN_BOUNDARIES_PCT[0], 55.0, "константа не испорчена")
	var ha := HrZones.five_zone(180)
	var hb := HrZones.five_zone(190)
	ha.max_hr = 170
	ha.boundaries_pct[0] = 1.0
	assert_eq(hb.max_hr, 190)
	assert_eq(hb.boundaries_pct[0], 60.0)
	assert_eq(HrZones.DEFAULT_BOUNDARIES_PCT[0], 60.0)


func test_req_prf_02_c6_power_zone_table_at_ftp_200() -> void:
	var table := {110: 1, 111: 2, 150: 2, 151: 3, 180: 3, 181: 4,
		210: 4, 211: 5, 240: 5, 241: 6, 300: 6, 301: 7}
	for p in table:
		assert_eq(Zones.power_zone(p, FTP), table[p], "%d Вт при FTP 200 → Z%d" % [p, table[p]])
		assert_eq(PowerZones.coggan(FTP).zone_of(p), table[p], "PowerZones: %d Вт" % p)


func test_req_prf_02_c6_power_zone_boundary_belongs_to_lower_zone_all_boundaries() -> void:
	# Следствие таблицы: ровно на границе (55/75/90/105/120/150 % от 200) — нижняя зона.
	var bounds := [110, 150, 180, 210, 240, 300]
	for i in bounds.size():
		assert_eq(Zones.power_zone(bounds[i], FTP), i + 1, "%d Вт — граница, нижняя зона Z%d" % [bounds[i], i + 1])
		assert_eq(Zones.power_zone(bounds[i] + 1, FTP), i + 2, "%d Вт — следующая зона Z%d" % [bounds[i] + 1, i + 2])


func test_req_prf_02_c6_edge_non_integer_boundary_and_odd_ftp() -> void:
	# FTP 250: 55 % = 137.5 Вт → 137 в Z1, 138 в Z2 (сравнение без накопления ошибки).
	assert_eq(Zones.power_zone(137, 250), 1)
	assert_eq(Zones.power_zone(138, 250), 2)
	# FTP 333: 90 % = 299.7 → 299 Z3, 300 Z4.
	assert_eq(Zones.power_zone(299, 333), 3)
	assert_eq(Zones.power_zone(300, 333), 4)


func test_req_prf_02_edge_ftp_zero_negative_and_huge_power() -> void:
	assert_eq(Zones.power_zone(150, 0), 0, "FTP 0 — зона не определена (0)")
	assert_eq(Zones.power_zone(150, -100), 0, "отрицательный FTP — 0")
	assert_eq(Zones.power_zone(-50, FTP), 1, "отрицательная мощность — Z1, не падение")
	assert_eq(Zones.power_zone(2147483647, FTP), 7, "огромная мощность — Z7")
	assert_eq(Zones.power_zone(5000, 600), 7)
	assert_eq(PowerZones.coggan(0).zone_of(100), 0)
	assert_gt(PowerZones.coggan(0).validate().size(), 0, "FTP 0 — ошибка конфигурации")
	assert_gt(PowerZones.coggan(-5).validate().size(), 0)


func test_req_prf_02_edge_power_zone_custom_boundaries_validation() -> void:
	assert_gt(PowerZones.custom(FTP, _pct([75, 55])).validate().size(), 0, "невозрастающие границы")
	assert_gt(PowerZones.custom(FTP, _pct([55, 55])).validate().size(), 0, "равные границы")
	assert_gt(PowerZones.custom(FTP, _pct([0, 55])).validate().size(), 0, "нулевая граница")
	assert_gt(PowerZones.custom(FTP, _pct([-10, 55])).validate().size(), 0, "отрицательная граница")
	assert_gt(PowerZones.custom(FTP, _pct([])).validate().size(), 0, "нет границ")
	assert_gt(HrZones.custom(180, _pct([90, 60])).validate().size(), 0, "HR: невозрастающие")
	assert_gt(HrZones.custom(0, _pct([60, 70])).validate().size(), 0, "HR: max_hr 0")


# ---------------------------------------------------------------------------
# REQ-HUD-03 — зона мощности
# ---------------------------------------------------------------------------

func test_req_hud_03_c1_zone_from_smoothed_power_and_profile_zones() -> void:
	var smoother := PowerSmoother.new()
	var zones := PowerZones.coggan(FTP)
	smoother.push(100)
	smoother.push(200)
	var smoothed := smoother.push(300)
	assert_eq(smoothed, 200, "сглаженная 200 Вт")
	assert_eq(zones.zone_of(smoothed), 4, "зона по сглаженной мощности: 200 Вт при FTP 200 — Z4")
	assert_eq(zones.zone_of(300), 6, "по сырой было бы Z6 — используется именно сглаженная")
	# Шаг 300 → 300 → окно 200/300/300 = 267 → Z6.
	assert_eq(zones.zone_of(smoother.push(300)), 6)


func test_req_hud_03_c1_zone_uses_actual_zone_count_from_intervals() -> void:
	# INT-06.2: зоны из Intervals.icu — произвольное число границ (1–9 зон).
	var z3 := PowerZones.custom(FTP, _pct([60, 100]))
	assert_eq(z3.zone_count(), 3)
	assert_eq(z3.zone_of(120), 1)
	assert_eq(z3.zone_of(121), 2)
	assert_eq(z3.zone_of(200), 2)
	assert_eq(z3.zone_of(201), 3, "выше последней границы — последняя зона (Z3, не Z7)")
	assert_eq(z3.zone_of(1000), 3)
	var z9 := PowerZones.custom(FTP, _pct([10, 20, 30, 40, 50, 60, 70, 80]))
	assert_eq(z9.zone_count(), 9)
	assert_eq(z9.zone_of(161), 9)
	assert_eq(z9.zone_of(20), 1)
	assert_eq(z9.zone_of(21), 2)
	var z2 := PowerZones.custom(FTP, _pct([100]))
	assert_eq(z2.zone_count(), 2)
	assert_eq(z2.zone_of(200), 1)
	assert_eq(z2.zone_of(201), 2)


func test_req_hud_03_c3_zero_power_and_no_data_give_z1() -> void:
	assert_eq(Zones.power_zone(0, FTP), 1, "мощность 0 → Z1")
	assert_eq(Zones.power_zone(NO_DATA, FTP), 1, "«нет данных» (−1) → Z1")
	assert_eq(Zones.power_zone(PowerSmoother.NO_VALUE, FTP), 1, "NO_VALUE сглаживателя → Z1")
	assert_eq(PowerZones.custom(FTP, _pct([60, 100])).zone_of(0), 1, "и для пользовательских зон")
	var s := PowerSmoother.new()
	s.push_missing()
	assert_eq(Zones.power_zone(s.value(), FTP), 1, "пустое окно сглаживания → Z1")


# ---------------------------------------------------------------------------
# REQ-HUD-04 — зона пульса
# ---------------------------------------------------------------------------

func test_req_hud_04_c1_hr_zone_table_at_max_180() -> void:
	var table := {107: 1, 108: 2, 126: 3, 144: 4, 162: 5}
	for bpm in table:
		assert_eq(Zones.hr_zone(bpm, 180), table[bpm], "%d уд/мин при max 180 → Z%d" % [bpm, table[bpm]])
		assert_eq(HrZones.five_zone(180).zone_of(bpm), table[bpm], "HrZones: %d" % bpm)
	# Соседние значения: граница принадлежит верхней зоне.
	assert_eq(Zones.hr_zone(125, 180), 2)
	assert_eq(Zones.hr_zone(143, 180), 3)
	assert_eq(Zones.hr_zone(161, 180), 4)
	assert_eq(Zones.hr_zone(180, 180), 5)
	assert_eq(Zones.hr_zone(250, 180), 5, "выше max_hr — Z5")
	assert_eq(Zones.hr_zone(1, 180), 1)


func test_req_hud_04_c1_hr_zone_uses_profile_zones() -> void:
	# Зоны профиля могут быть переопределены — функция должна использовать их, а не константы.
	var z := HrZones.custom(180, _pct([50, 60, 70, 80]))
	assert_eq(z.zone_of(108), 3, "108 при границах 50/60/70/80 → Z3 (а не Z2 по умолчанию)")
	assert_eq(z.zone_of(144), 5)


func test_req_hud_04_c2_no_sensor_or_no_max_hr_gives_no_zone() -> void:
	assert_eq(Zones.hr_zone(0, 180), 0, "нет датчика (0) → нет зоны")
	assert_eq(Zones.hr_zone(NO_DATA, 180), 0, "«нет данных» (−1) → нет зоны")
	assert_eq(Zones.hr_zone(140, 0), 0, "max_hr не задан → нет зоны")
	assert_eq(Zones.hr_zone(140, -1), 0)
	assert_eq(Zones.hr_zone(0, 0), 0)
	assert_eq(HrZones.five_zone(0).zone_of(140), 0)
	assert_eq(HrZones.five_zone(180).zone_of(0), 0)
	# Переопределённые границы при max_hr 0 — зона всё равно 0 (границы заданы в % от max_hr).
	assert_eq(HrZones.custom(0, _pct([60, 70, 80, 90])).zone_of(140), 0)


func test_req_hud_04_edge_huge_bpm_and_max_hr() -> void:
	assert_eq(Zones.hr_zone(2147483647, 180), 5)
	assert_eq(Zones.hr_zone(100, 2147483647), 1)


# ---------------------------------------------------------------------------
# REQ-HUD-09 — сглаживание мощности 3 с
# ---------------------------------------------------------------------------

func test_req_hud_09_c1_100_200_300_gives_200_then_300_gives_267() -> void:
	var s := PowerSmoother.new()
	assert_eq(s.window_size, 3, "окно по умолчанию — 3 с")
	s.push(100)
	s.push(200)
	assert_eq(s.push(300), 200, "(100+200+300)/3 = 200")
	assert_eq(s.push(300), 267, "(200+300+300)/3 = 266.67 → 267")
	assert_eq(s.value(), 267, "value() совпадает с возвратом push")
	assert_eq(s.sample_count(), 3, "в окне не больше 3 слотов")


func test_req_hud_09_c1_rounding_to_integer() -> void:
	var s := PowerSmoother.new()
	s.push(100)
	s.push(100)
	assert_eq(s.push(101), 100, "100.33 → 100")
	var s2 := PowerSmoother.new()
	s2.push(100)
	s2.push(101)
	assert_eq(s2.push(101), 101, "100.67 → 101")
	var s3 := PowerSmoother.new()
	s3.push(100)
	s3.push(200)
	s3.push(300)
	s3.push(400)
	assert_eq(s3.value(), 300, "окно скользит: (200+300+400)/3 = 300, 100 выпал")


func test_req_hud_09_c2_fewer_than_three_samples_average_available() -> void:
	var s := PowerSmoother.new()
	assert_false(s.has_value(), "до первого сэмпла — нет значения")
	assert_eq(s.push(100), 100, "один сэмпл → он сам")
	assert_eq(s.push(200), 150, "два сэмпла → (100+200)/2")
	assert_eq(s.sample_count(), 2)


func test_req_hud_09_c3_missing_excluded_and_all_missing_gives_no_value() -> void:
	var s := PowerSmoother.new()
	s.push(100)
	s.push_missing()
	assert_eq(s.push(300), 200, "пропуск исключён: (100+300)/2 = 200")
	assert_eq(s.sample_count(), 3, "пропуск занимает слот окна")
	s.push_missing()
	assert_eq(s.value(), 300, "окно: пропуск/300/пропуск → 300")
	s.push_missing()
	assert_eq(s.value(), 300, "окно: 300/пропуск/пропуск → 300")
	assert_eq(s.push_missing(), PowerSmoother.NO_VALUE, "все три — «нет данных»")
	assert_false(s.has_value())
	assert_eq(s.value(), -1, "NO_VALUE = −1")
	assert_eq(s.push(150), 150, "после восстановления данных — среднее по доступным")


func test_req_hud_09_c3_missing_pushes_old_sample_out() -> void:
	var s := PowerSmoother.new()
	s.push(100)
	s.push(200)
	s.push(300)
	s.push_missing()
	assert_eq(s.value(), 250, "100 выпал из окна (время идёт): (200+300)/2")
	s.push_missing()
	assert_eq(s.value(), 300)


func test_req_hud_09_edge_window_size_1_and_0() -> void:
	var s := PowerSmoother.new(1)
	assert_eq(s.window_size, 1)
	assert_eq(s.push(100), 100)
	assert_eq(s.push(250), 250, "окно 1 — всегда последний сэмпл")
	assert_eq(s.sample_count(), 1)
	assert_eq(s.push_missing(), PowerSmoother.NO_VALUE, "окно 1 с пропуском — нет значения")
	assert_eq(s.push(80), 80)
	var s0 := PowerSmoother.new(0)
	assert_gt(s0.window_size, 0, "окно 0 не допускается (минимум 1)")
	assert_eq(s0.push(120), 120)
	var sn := PowerSmoother.new(-3)
	assert_gt(sn.window_size, 0, "отрицательное окно не допускается")
	assert_eq(sn.push(120), 120)


func test_req_hud_09_edge_very_large_power_values() -> void:
	var s := PowerSmoother.new()
	var big: int = 2000000000
	s.push(big)
	s.push(big)
	assert_eq(s.push(big), big, "сумма трёх 2e9 не переполняется")
	var s2 := PowerSmoother.new()
	s2.push(2147483647)
	s2.push(2147483647)
	assert_eq(s2.push(2147483647), 2147483647, "сумма трёх INT32_MAX в 64-битном int")
	var s3 := PowerSmoother.new()
	s3.push(100000)
	s3.push(0)
	assert_eq(s3.push(0), 33333, "100000/3 = 33333.33 → 33333")


func test_req_hud_09_edge_zero_and_negative_power() -> void:
	var s := PowerSmoother.new()
	s.push(0)
	s.push(0)
	assert_eq(s.push(0), 0, "нули — это данные, а не пропуски")
	assert_true(s.has_value())
	assert_eq(s.push(300), 100, "(0+0+300)/3")


func test_req_hud_09_edge_reset_clears_window() -> void:
	var s := PowerSmoother.new()
	s.push(100)
	s.push(200)
	s.reset()
	assert_false(s.has_value())
	assert_eq(s.sample_count(), 0)
	assert_eq(s.push(50), 50, "после сброса среднее начинается заново")
