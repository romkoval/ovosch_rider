extends GutTest
## Тесты процедурной зацикленной трассы LoopTrack (REQ-D3D-03 крит. 1, 2; REQ-D3D-06 крит. 1 — контракт Track).

var _track: LoopTrack


func before_each() -> void:
	_track = LoopTrack.new(42)


func test_length_is_about_two_kilometres() -> void:
	assert_gt(_track.length_m(), 1500.0)
	assert_lt(_track.length_m(), 3000.0)
	assert_true(_track.is_loop())


func test_sample_at_zero_equals_sample_at_length() -> void:
	var a := _track.sample(0.0)
	var b := _track.sample(_track.length_m())
	assert_lt(a.position.distance_to(b.position), 0.01, "петля: sample(0) == sample(length)")
	assert_lt(a.forward.distance_to(b.forward), 0.05)


func test_forward_and_up_are_unit_vectors() -> void:
	for s in range(0, int(_track.length_m()), 37):
		var p := _track.sample(float(s))
		assert_almost_eq(p.forward.length(), 1.0, 1e-4, "forward единичный на s=%d" % s)
		assert_almost_eq(p.up.length(), 1.0, 1e-6)
		assert_almost_eq(p.right().length(), 1.0, 1e-4)


func test_position_is_continuous_along_distance() -> void:
	var prev := _track.sample(0.0).position
	var s: float = 0.0
	var step: float = 1.0
	while s < _track.length_m() + 5.0:
		s += step
		var pos := _track.sample(s).position
		assert_true(prev.distance_to(pos) <= step * 1.01, "|Δpos| ≤ Δs·1.01 на s=%.0f (факт %.3f)" % [s, prev.distance_to(pos)])
		prev = pos


func test_forward_turns_smoothly() -> void:
	var prev := _track.sample(0.0).forward
	for s in range(1, int(_track.length_m()), 1):
		var f := _track.sample(float(s)).forward
		assert_lt(prev.angle_to(f), deg_to_rad(6.0), "поворот за 1 м < 6° на s=%d" % s)
		prev = f


func test_grade_is_small() -> void:
	for s in range(0, int(_track.length_m()), 11):
		var g := _track.sample(float(s)).grade
		assert_true(absf(g) < 0.12, "уклон |%.3f| < 12 %% на s=%d" % [g, s])


func test_wrap_handles_negative_and_beyond_length() -> void:
	var length := _track.length_m()
	assert_almost_eq(_track.wrap_distance(length + 10.0), 10.0, 1e-6)
	assert_almost_eq(_track.wrap_distance(-10.0), length - 10.0, 1e-6)
	assert_almost_eq(_track.wrap_distance(length * 3.0 + 5.0), 5.0, 1e-3)
	var a := _track.sample(5.0)
	var b := _track.sample(length * 2.0 + 5.0)
	assert_lt(a.position.distance_to(b.position), 1e-3, "дистанция оборачивается по модулю длины")


func test_80_km_stays_on_track() -> void:
	# REQ-D3D-03 крит. 1: 2 часа на 40 км/ч — позиция корректно оборачивается, нет «конца».
	var s: float = 0.0
	var sample := TrackSample.new()
	var max_radius: float = _track.radius_m * (1.0 + _track.waviness) + 5.0
	for i in 7200:
		s += 40.0 / 3.6
		_track.sample_into(s, sample)
		assert_true(sample.position.is_finite())
		assert_lt(Vector2(sample.position.x, sample.position.z).length(), max_radius, "в пределах контура на %d с" % i)
	assert_gt(s, 79000.0)


func test_same_seed_is_deterministic_and_different_seed_differs() -> void:
	var other := LoopTrack.new(42)
	assert_almost_eq(other.length_m(), _track.length_m(), 1e-6)
	for s in [0.0, 100.0, 777.0, 1500.0]:
		assert_lt(other.sample(s).position.distance_to(_track.sample(s).position), 1e-6)
	var third := LoopTrack.new(43)
	var differs := false
	for s in [100.0, 777.0, 1500.0]:
		if third.sample(s).position.distance_to(_track.sample(s).position) > 1.0:
			differs = true
	assert_true(differs, "другой seed — другая трасса")


func test_sample_into_does_not_allocate_new_object() -> void:
	var out := TrackSample.new()
	var id := out.get_instance_id()
	_track.sample_into(123.0, out)
	assert_eq(out.get_instance_id(), id)
	assert_true(out.position.is_finite())
	assert_eq(out.transform().origin, out.position)


func test_parameters_are_clamped() -> void:
	var t := LoopTrack.new(1, 5.0, 2.0, 3, -1.0)
	assert_eq(t.point_count, LoopTrack.MIN_POINTS)
	assert_almost_eq(t.radius_m, 10.0, 1e-9)
	assert_almost_eq(t.waviness, 0.6, 1e-9)
	assert_almost_eq(t.elevation_m, 0.0, 1e-9)
	assert_gt(t.length_m(), 0.0)
