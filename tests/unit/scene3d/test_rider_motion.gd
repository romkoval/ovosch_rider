extends GutTest
## Константы и функции движения гонщика (T-106a2; REQ-D3D-09 п.14–18; арт-библия «Гонщик» →
## «Движение по видео-референсу», список «Что закодировать в T-106a2»): числа спеки, формула
## k, IK колена с заданным X, оси костей как у контракта.


func test_constants_match_spec_list() -> void:
	assert_eq(RiderMotion.THETA_MEAN_DEG, -14.0)
	assert_eq(RiderMotion.THETA_AMP_DEG, 12.0)
	assert_eq(RiderMotion.THETA_PHASE_DEG, 100.0)
	assert_eq(RiderMotion.KNEE_X_AMP_M, 0.008)
	assert_eq(RiderMotion.KNEE_X_PHASE_DEG, 0.0)
	assert_eq(RiderMotion.PELVIS_ROLL_AMP_DEG, 0.6)
	assert_eq(RiderMotion.PELVIS_ROLL_PHASE_DEG, 180.0)
	assert_eq(RiderMotion.CHEST_ROLL_AMP_DEG, 1.5)
	assert_eq(RiderMotion.CHEST_ROLL_PHASE_DEG, 150.0)
	assert_eq(RiderMotion.CHEST_YAW_AMP_DEG, 0.8)
	assert_eq(RiderMotion.CHEST_YAW_PHASE_DEG, 90.0)
	assert_eq(RiderMotion.SPINE_YAW_SHARE, 0.4)
	assert_eq(RiderMotion.HEAD_COMP, 0.7)
	assert_eq(RiderMotion.K_MIN, 0.35)
	assert_eq(RiderMotion.K_SLOPE, 0.65)
	assert_eq(RiderMotion.K_MAX, 1.3)
	assert_eq(RiderMotion.K_TAU_SEC, 0.6)


func test_foot_curve_extremes_and_rig_delegates() -> void:
	assert_almost_eq(rad_to_deg(RiderMotion.foot_pitch_rad(deg_to_rad(100.0))), -2.0, 1e-4)
	assert_almost_eq(rad_to_deg(RiderMotion.foot_pitch_rad(deg_to_rad(280.0))), -26.0, 1e-4)
	for i in 24:
		var phi: float = deg_to_rad(15.0 * i)
		assert_eq(RiderRig.foot_pitch_rad(phi), RiderMotion.foot_pitch_rad(phi), "одна кривая на педали и стопе")


func test_effort_target_branches() -> void:
	assert_almost_eq(RiderMotion.effort_target(100, true, 200, 90.0), 0.675, 1e-6, "P/FTP 0.5")
	assert_almost_eq(RiderMotion.effort_target(200, true, 200, 90.0), 1.0, 1e-6, "порог")
	assert_almost_eq(RiderMotion.effort_target(600, true, 200, 90.0), 1.3, 1e-6, "верхняя граница")
	assert_almost_eq(RiderMotion.effort_target(0, true, 200, 90.0), 0.35, 1e-6, "нижняя граница")
	assert_almost_eq(RiderMotion.effort_target(300, false, 200, 45.0), 0.5, 1e-6, "нет мощности — по каденсу")
	assert_almost_eq(RiderMotion.effort_target(300, true, 0, 120.0), 1.0, 1e-6, "нет FTP — по каденсу, ≤ 1")
	assert_almost_eq(RiderMotion.smooth_effort(0.0, 1.0, 0.6), 1.0 - exp(-1.0), 1e-6, "τ = 0.6 с")


func test_two_bone_joint_x_hits_x_and_keeps_lengths() -> void:
	var hip: Vector3 = RiderRig.head("thigh.R")
	var ankle: Vector3 = RiderRig.head("foot.R")
	for x in [0.092, 0.1, 0.108]:
		var knee := RiderModel.two_bone_joint_x(hip, ankle, RiderModel.THIGH_M, RiderModel.SHIN_M, RiderModel.KNEE_HINT, x)
		assert_almost_eq(knee.x, x, 1e-5, "колено по X")
		assert_almost_eq(knee.distance_to(hip), RiderModel.THIGH_M, 1e-5)
		assert_almost_eq(knee.distance_to(ankle), RiderModel.SHIN_M, 1e-5)
		assert_lt(knee.z, hip.z, "колено вперёд")
	var rest := RiderModel.two_bone_joint_x(hip, ankle, RiderModel.THIGH_M, RiderModel.SHIN_M, RiderModel.KNEE_HINT, 0.1)
	assert_lt(rest.distance_to(RiderRig.head("shin.R")), 0.002, "в rest — колено контракта")


func test_bone_basis_matches_contract_axes_and_lengths() -> void:
	for b in RiderRig.BONES:
		var name: String = b[0]
		var dir: Vector3 = RiderRig.tail(name) - RiderRig.head(name)
		assert_true(RiderModel.bone_basis(dir).is_equal_approx(RiderRig.rest_basis(name)), "%s: оси как у контракта" % name)
	assert_almost_eq(RiderModel.THIGH_M, RiderRig.span("thigh.R", "shin.R"), 1e-5, "бедро из контракта")
	assert_almost_eq(RiderModel.SHIN_M, RiderRig.span("shin.R", "foot.R"), 1e-5, "голень из контракта")
	assert_eq(RiderModel.HIP, RiderRig.head("thigh.R"))
