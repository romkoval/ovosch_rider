extends GutTest
## Коэффициент усилия гонщика k (REQ-D3D-09 п.16 (а), (б), (г); спека «Каденс и мощность»;
## решение менеджера по Н-39: P — мощность сэмпла 1 Гц сессии, FTP — активного профиля, в
## тренировке по плану и в свободной езде; «k по каденсу» — только без мощности или без FTP).
## Сессии на `FakeTrainer` с постоянным каденсом 90 об/мин; k читается у `Rider` сцены.
## Формулы — из спеки: k = clamp(0.35 + 0.65·P/FTP, 0.35, 1.3), τ = 0.6 с; запасная —
## clamp(каденс/90, 0, 1). П.16 (в), (д) — `test_rider_pose.gd`.

const RIDE_SCENE: String = "res://src/scene3d/ride_scene.tscn"
const FREE_RIDE_SCENE: String = "res://src/ui/free_ride/free_ride_screen.tscn"
const FRAME: float = 1.0 / 60.0
const TAU_K: float = 0.6
const FTP: int = 200

var _now_usec: int = 0
var _dir: String


## Станок, у которого можно убрать мощность из сэмплов («нет данных»), каденс остаётся.
class PowerlessTrainer extends FakeTrainer:
	var strip_power: bool = false

	func _emit_sample(sample_sec: int) -> void:
		if not strip_power:
			super(sample_sec)
			return
		samples_emitted += 1
		var out := TrainerSample.full(float(sample_sec), 0, rider_cadence_rpm, 25.0)
		out.has_power = false
		telemetry.emit(out)


static func _formula(p_over_ftp: float) -> float:
	return clampf(0.35 + 0.65 * p_over_ftp, 0.35, 1.3)


static func _cadence_formula(rpm: float) -> float:
	return clampf(rpm / 90.0, 0.0, 1.0)


func before_each() -> void:
	_now_usec = 3_000_000
	_dir = "user://test_rider_effort_%d_%d/" % [Time.get_ticks_usec(), randi() % 100000]


func after_each() -> void:
	_remove_tree(ProjectSettings.globalize_path(_dir))


static func _remove_tree(abs_path: String) -> void:
	if not DirAccess.dir_exists_absolute(abs_path):
		return
	var d := DirAccess.open(abs_path)
	for f in d.get_files():
		DirAccess.remove_absolute(abs_path.path_join(f))
	for sub in d.get_directories():
		_remove_tree(abs_path.path_join(sub))
	DirAccess.remove_absolute(abs_path)


func _trainer(power_w: int) -> PowerlessTrainer:
	var t := PowerlessTrainer.new(5)
	t.connect_delay_sec = 0.0
	t.power_noise_w = 0.0
	t.power_tau_sec = 0.01
	t.cadence_noise_rpm = 0.0
	t.set_rider_cadence(90)
	t.set_rider_power(power_w)
	t.connect_device("effort")
	return t


func _profile(ftp: int) -> Profile:
	var p := Profile.create("Effort")
	p.ftp_w = ftp
	p.weight_kg = 75.0
	return p


# ---------------------------------------------------------------------------
# Тренировка по плану: RideScene.bind(session, profile)
# ---------------------------------------------------------------------------

## План: шаги по `watts` (ERG) по `sec` секунд.
func _plan(watts: Array, sec: int) -> Workout:
	var steps: Array[WorkoutStep] = []
	for w in watts:
		steps.append(WorkoutStep.watts(sec, float(w)))
	return Workout.make("effort", steps)


func _workout(trainer: FakeTrainer, profile: Profile, watts: Array, sec: int) -> Array:
	var s: RideScene = load(RIDE_SCENE).instantiate()
	s.route_id = ""
	add_child_autofree(s)
	var session := WorkoutSession.new(_plan(watts, sec), trainer, profile.ftp_w, 1.0, profile.weight_kg)
	s.bind(session, profile)
	session.start()
	return [s, session]


## `seconds` секунд: тик сессии 1 с + 60 кадров сцены.
func _run_workout(pair: Array, seconds: int) -> void:
	for i in seconds:
		(pair[1] as WorkoutSession).tick(1.0)
		for f in 60:
			(pair[0] as RideScene).advance(FRAME)


## (а) Тренировка: P/FTP = 0.5 и 1.5 → k по формуле ±0.02 через 4τ, значения различаются как
## требует формула; (г) скачок P 0.5 → 1.5 FTP без скачка k: первый кадр ≤ 5 % разности, через
## 4τ — в 5 % от нового значения.
func test_a_g_workout_power_and_profile_ftp() -> void:
	var trainer := _trainer(100)
	var pair := _workout(trainer, _profile(FTP), [100, 300], 8)
	_run_workout(pair, 6)
	var rider: Rider = (pair[0] as RideScene).rider()
	assert_eq((pair[0] as RideScene).ftp_w, FTP, "FTP — из профиля (bind)")
	var k_low: float = rider.effort_k
	assert_almost_eq(k_low, _formula(0.5), 0.02, "P/FTP 0.5: k = %.3f" % k_low)
	# Дотянуть до смены шага: тики, пока сэмпл не принесёт 300 Вт.
	var s: RideScene = pair[0]
	var session: WorkoutSession = pair[1]
	var guard: int = 0
	while int(session.samples.last_row()["power_w"]) < 300 and guard < 10:
		session.tick(1.0)
		guard += 1
		if int(session.samples.last_row()["power_w"]) < 300:
			for f in 60:
				s.advance(FRAME)
	assert_lt(guard, 10, "шаг 300 Вт начался")
	var k0: float = rider.effort_k
	s.advance(FRAME)
	var k1: float = rider.effort_k
	var span: float = _formula(1.5) - k0
	assert_lte(absf(k1 - k0), absf(span) * 0.05, "(г) первый кадр: Δk %.4f ≤ 5 %% от %.3f" % [k1 - k0, span])
	for f in int(ceil(4.0 * TAU_K / FRAME)):
		s.advance(FRAME)
	assert_lte(absf(rider.effort_k - _formula(1.5)), absf(span) * 0.05, "(г) через 4τ: k = %.3f" % rider.effort_k)
	_run_workout(pair, 3)
	var k_high: float = rider.effort_k
	assert_almost_eq(k_high, _formula(1.5), 0.02, "P/FTP 1.5: k = %.3f" % k_high)
	assert_almost_eq(k_high - k_low, _formula(1.5) - _formula(0.5), 0.03, "k различаются по формуле, а не по каденсу")


## (б) Тренировка: сэмплы без мощности → k по каденсу; мощность вернулась → формула (а);
## профиль без FTP → k по каденсу.
func test_b_workout_fallback_without_power_or_ftp() -> void:
	var trainer := _trainer(100)
	var pair := _workout(trainer, _profile(FTP), [100], 60)
	var rider: Rider = (pair[0] as RideScene).rider()
	_run_workout(pair, 4)
	assert_almost_eq(rider.effort_k, _formula(0.5), 0.02, "есть мощность: формула (а)")
	trainer.strip_power = true
	_run_workout(pair, 4)
	assert_false(bool((pair[1] as WorkoutSession).samples.last_row()["has_power"]), "в сэмплах нет мощности")
	assert_almost_eq(rider.effort_k, _cadence_formula(90.0), 0.02, "нет мощности: k по каденсу (%.3f)" % rider.effort_k)
	trainer.strip_power = false
	_run_workout(pair, 4)
	assert_almost_eq(rider.effort_k, _formula(0.5), 0.02, "мощность вернулась: формула (а) (%.3f)" % rider.effort_k)
	# Профиль без FTP: мощность есть, k — по каденсу.
	var t2 := _trainer(100)
	var pair2 := _workout(t2, _profile(0), [100], 60)
	var rider2: Rider = (pair2[0] as RideScene).rider()
	rider2.set_effort_k(0.5)
	_run_workout(pair2, 4)
	assert_almost_eq(rider2.effort_k, _cadence_formula(90.0), 0.02, "без FTP: k по каденсу (%.3f)" % rider2.effort_k)
	assert_between(rider2.effort_k, 0.0, 1.3, "k в границах")


## (а) Границы: при P/FTP от 0 до 3 k не выходит за [0.35; 1.3].
func test_a_bounds_over_power_range() -> void:
	var r: Rider = (load("res://src/scene3d/rider.tscn") as PackedScene).instantiate()
	add_child_autofree(r)
	r.set_process(false)
	r.set_cadence(90)
	for i in 31:
		var p: int = int(round(FTP * 0.1 * i))
		r.set_power(p, true, FTP)
		for f in 30:
			r.advance(FRAME)
		assert_between(r.effort_k, 0.35, 1.3, "P/FTP %.1f: k = %.3f" % [0.1 * i, r.effort_k])
		assert_almost_eq(r.effort_target(), _formula(0.1 * i), 1e-5, "P/FTP %.1f: цель k по формуле" % (0.1 * i))


# ---------------------------------------------------------------------------
# Свободная езда: экран передаёт P сэмпла и FTP профиля рядом с каденсом
# ---------------------------------------------------------------------------

func _clock() -> int:
	return _now_usec


func _keep(_on: bool) -> void:
	pass


func _free_ride(trainer: FakeTrainer, profile: Profile) -> FreeRideScreen:
	var state := AppState.new(ProfileRepository.new(_dir + "profiles/"))
	var screen: FreeRideScreen = load(FREE_RIDE_SCENE).instantiate()
	screen.clock_usec = _clock
	screen.keep_awake_setter = _keep
	add_child_autofree(screen)
	screen.setup(state, profile, trainer)
	assert_true(screen.start(), "свободная езда началась")
	screen.ride_scene().set_process(false)
	return screen


## `seconds` секунд свободной езды: время сессии шагами 0.5 с и кадры гонщика.
func _run_free(screen: FreeRideScreen, seconds: int) -> void:
	var rider := screen.ride_scene().rider()
	for i in seconds * 2:
		_now_usec += 500_000
		screen.ticker().poll()
		for f in 30:
			rider.advance(FRAME)


## (а), (б) Свободная езда: P/FTP 0.5 и 1.5 — формула; без мощности и без FTP — k по каденсу;
## мощность вернулась — формула.
func test_a_b_free_ride_power_and_profile_ftp() -> void:
	var trainer := _trainer(100)
	var screen := _free_ride(trainer, _profile(FTP))
	var rider := screen.ride_scene().rider()
	_run_free(screen, 4)
	var k_low: float = rider.effort_k
	assert_almost_eq(k_low, _formula(0.5), 0.02, "свободная езда, P/FTP 0.5: k = %.3f" % k_low)
	trainer.set_rider_power(300)
	_run_free(screen, 4)
	var k_high: float = rider.effort_k
	assert_almost_eq(k_high, _formula(1.5), 0.02, "свободная езда, P/FTP 1.5: k = %.3f" % k_high)
	assert_almost_eq(k_high - k_low, _formula(1.5) - _formula(0.5), 0.03, "k различаются по формуле")
	trainer.set_rider_power(100)
	_run_free(screen, 4)
	trainer.strip_power = true
	_run_free(screen, 4)
	assert_almost_eq(rider.effort_k, _cadence_formula(90.0), 0.02, "без мощности: k по каденсу (%.3f)" % rider.effort_k)
	trainer.strip_power = false
	_run_free(screen, 4)
	assert_almost_eq(rider.effort_k, _formula(0.5), 0.02, "мощность вернулась: формула (а) (%.3f)" % rider.effort_k)


func test_b_free_ride_without_ftp_uses_cadence() -> void:
	var trainer := _trainer(100)
	var screen := _free_ride(trainer, _profile(0))
	var rider := screen.ride_scene().rider()
	rider.set_effort_k(0.5)
	_run_free(screen, 4)
	assert_almost_eq(rider.effort_k, _cadence_formula(90.0), 0.02, "без FTP: k по каденсу (%.3f)" % rider.effort_k)
