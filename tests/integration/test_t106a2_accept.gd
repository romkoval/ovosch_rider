extends GutTest
## Tester acceptance of T-106a2 — skeleton, two-figure mannequin, IK on bone poses, tail spring
## (REQ-D3D-09 p.1–5, 7, 15, 16 (e), 17, 18; REQ-D3D-07 p.2; REQ-D3D-04 p.2; REQ-D3D-05 p.4).
##
## Independent of the developer tests (`test_rider_pose.gd`): poses are read from the
## `Skeleton3D` of the mannequin after real `advance()` frames (the crank turns by the
## `AnimationPlayer`, not by `set_crank_angle`), the pedal axis is taken from the visible crank
## node (`%Crank` transform), numbers come from the art bible «Rider» section (spec) and are
## written here as literals, not read from `RiderMotion` / `RiderRig`. Limits are checked
## strictly (no extra slack over the spec).

const RiderContract := preload("res://tests/fixtures/scene3d/rider_contract.gd")
const FRAME: float = 1.0 / 60.0
const FTP: int = 200
## Spec «Proportions and seating» / skeleton contract (Godot, m).
const S_REST := Vector3(0.0, 0.965, 0.23)
const SADDLE_REAR_Z: float = 0.23 + 0.065
const GRIP_R := Vector3(0.21, 0.885, -0.62)
const THIGH_M: float = 0.44
const TAIL_TIP_REST := Vector3(0.0, 1.385, -0.08)
## Crank 0.17 m, pedal axis ±0.115 m: right pedal in the local frame of `%Crank` (the mount turns
## the crank by 180° about Y, so +X of the rider is −X of the crank).
const PEDAL_R_LOCAL := Vector3(-0.115, 0.17, 0.0)
const PEDAL_L_LOCAL := Vector3(0.115, -0.17, 0.0)
## RideScene lean filter (to emulate a turn entry the way the scene drives `set_lean`).
const LEAN_TAU: float = 0.35
## float32 resolution of coordinates near 1 m (vertex positions, bone origins), m.
const FLOAT_EPS_M: float = 1e-6


func _rider(src: Dictionary) -> Rider:
	var holder := Node3D.new()
	add_child_autofree(holder)
	return RiderContract.load_rider(src, holder)


func _p(r: Rider, bone: String) -> Vector3:
	return r.bone_pose(bone).origin


func _rest(r: Rider, bone: String) -> Transform3D:
	var skel := r.skeleton()
	return skel.get_bone_global_rest(skel.find_bone(bone))


## Pedal axis of the side in the `Lean` frame from the crank node.
func _pedal(r: Rider, right: bool) -> Vector3:
	var lean: Node3D = r.get_node("%Lean")
	var crank: Node3D = r.get_node("%Crank")
	return lean.global_transform.affine_inverse() * crank.global_transform * (PEDAL_R_LOCAL if right else PEDAL_L_LOCAL)


func _theta(r: Rider, side: String) -> float:
	var c := _p(r, "cleat" + side)
	var h := _p(r, "heel" + side)
	return rad_to_deg(atan2(c.y - h.y, h.z - c.z))


func _angle_at(a: Vector3, o: Vector3, b: Vector3) -> float:
	return rad_to_deg((a - o).angle_to(b - o))


## Tail deviation from rest in the head frame, degrees: x — sideways (signed), y — drop of the
## line «root hair_tail.1 — tip» in the sagittal plane (+ = down), z — cone angle.
func _tail_dev(r: Rider) -> Vector3:
	var head_m: Transform3D = r.bone_pose("head") * _rest(r, "head").affine_inverse()
	var t2_m: Transform3D = r.bone_pose("hair_tail.2") * _rest(r, "hair_tail.2").affine_inverse()
	var inv := head_m.affine_inverse()
	var v: Vector3 = inv * (t2_m * TAIL_TIP_REST) - inv * _p(r, "hair_tail.1")
	var v0: Vector3 = TAIL_TIP_REST - _rest(r, "hair_tail.1").origin
	var side: float = rad_to_deg(atan2(v.x, Vector2(v.y, v.z).length()))
	var drop: float = rad_to_deg(atan2(v0.y, v0.z) - atan2(v.y, v.z))
	return Vector3(side, drop, rad_to_deg(v.angle_to(v0)))


## Seating checks of p.1–5 on the current frame; returns the list of violations.
func _seat_violations(r: Rider, saddle_top: float, rest_elbow: Dictionary, rest_wrist: Dictionary) -> Array[String]:
	var bad: Array[String] = []
	var s := _p(r, "pelvis")
	if s.distance_to(S_REST) > 0.001:
		bad.append("p1 S moved %.4f m" % s.distance_to(S_REST))
	# FLOAT_EPS_M — float32 resolution of mesh vertices and bone origins near 1 m, not a tolerance.
	if s.y - saddle_top < -FLOAT_EPS_M or s.y - saddle_top > 0.015:
		bad.append("p1 S above saddle %.7f" % (s.y - saddle_top))
	if SADDLE_REAR_Z - s.z < 0.03 or SADDLE_REAR_Z - s.z > 0.10:
		bad.append("p1 S ahead of rear edge %.4f" % (SADDLE_REAR_Z - s.z))
	for side in [".R", ".L"]:
		var right: bool = side == ".R"
		var hip := _p(r, "thigh" + side)
		var knee := _p(r, "shin" + side)
		var ankle := _p(r, "foot" + side)
		var cleat := _p(r, "cleat" + side)
		var pedal := _pedal(r, right)
		if hip.y - saddle_top < 0.075 or hip.y - saddle_top > 0.095:
			bad.append("p2 %s HIP above saddle %.4f" % [side, hip.y - saddle_top])
		if hip.z - s.z < -0.06 or hip.z - s.z > -0.02:
			bad.append("p2 %s HIP.z - S.z %.4f" % [side, hip.z - s.z])
		if absf(hip.x) < 0.085 or absf(hip.x) > 0.095:
			bad.append("p2 %s |HIP.x| %.4f" % [side, absf(hip.x)])
		if absf(hip.distance_to(knee) - THIGH_M) > 0.01:
			bad.append("p3 %s thigh %.4f" % [side, hip.distance_to(knee)])
		if absf(knee.distance_to(ankle) - _rest(r, "shin" + side).origin.distance_to(_rest(r, "foot" + side).origin)) > 0.001:
			bad.append("p3 %s shin length %.5f" % [side, knee.distance_to(ankle)])
		if absf(hip.distance_to(knee) - _rest(r, "thigh" + side).origin.distance_to(_rest(r, "shin" + side).origin)) > 0.001:
			bad.append("p3 %s thigh length %.5f" % [side, hip.distance_to(knee)])
		if cleat.distance_to(pedal) > 0.01:
			bad.append("p3 %s cleat off pedal axis %.4f" % [side, cleat.distance_to(pedal)])
		var a := Vector2(hip.y, hip.z)
		var d := (Vector2(pedal.y, pedal.z) - a).normalized()
		var w := Vector2(knee.y, knee.z) - a
		w -= d * w.dot(d)
		if w.length() < 0.03 or w.x <= 0.0 or w.y >= 0.0:
			bad.append("p3 %s knee vs hip-pedal line (dy %.4f, dz %.4f)" % [side, w.x, w.y])
		if absf(knee.x) < 0.07 or absf(knee.x) > 0.13:
			bad.append("p3 %s |knee.x| %.4f" % [side, absf(knee.x)])
		var th := _theta(r, side)
		if th < -35.0 or th > 10.0:
			bad.append("p4 %s theta %.2f" % [side, th])
		if cleat.z >= _p(r, "heel" + side).z:
			bad.append("p4 %s toe behind heel" % side)
		var grip := _p(r, "grip" + side)
		var hood := Vector3(GRIP_R.x * (1.0 if right else -1.0), GRIP_R.y, GRIP_R.z)
		if grip.distance_to(hood) > 0.015:
			bad.append("p5 %s grip %.4f from hood" % [side, grip.distance_to(hood)])
		var sh := _p(r, "upperarm" + side)
		var el := _p(r, "forearm" + side)
		var wr := _p(r, "hand" + side)
		var elbow := _angle_at(sh, el, wr)
		if elbow < 140.0 or elbow > 165.0:
			bad.append("p5 %s elbow %.2f (rest %.2f)" % [side, elbow, rest_elbow[side]])
		var wrist := rad_to_deg((wr - el).angle_to(grip - wr))
		if absf(wrist - float(rest_wrist[side])) > 5.0:
			bad.append("p5 %s wrist %.2f vs rest %.2f" % [side, wrist, rest_wrist[side]])
	return bad


func _rest_arm_angles(r: Rider) -> Array[Dictionary]:
	var elbow := {}
	var wrist := {}
	for side in [".R", ".L"]:
		var sh := _rest(r, "upperarm" + side).origin
		var el := _rest(r, "forearm" + side).origin
		var wr := _rest(r, "hand" + side).origin
		var gr := _rest(r, "grip" + side).origin
		elbow[side] = _angle_at(sh, el, wr)
		wrist[side] = rad_to_deg((wr - el).angle_to(gr - wr))
	return [elbow, wrist]


## P.1–5 (and D3D-07 p.2) on every frame of real pedalling: 120 rpm, P = 1.5 FTP (k at the upper
## bound 1.3) and P = FTP (k = 1), lean driven like RideScene (filtered) through a slalom
## −0.45…+0.45 rad, 12 s per run, for both figures.
func test_p1_5_hold_on_every_frame_of_real_pedalling(src = use_parameters(RiderContract.POSE_SOURCES)) -> void:
	for p_w in [FTP * 3 / 2, FTP]:
		var r := _rider(src)
		var saddle := RiderContract.top_at((r.get_node("%Bike") as MeshInstance3D).mesh, S_REST.x, S_REST.z)
		var arm := _rest_arm_angles(r)
		r.set_power(p_w, true, FTP)
		r.set_cadence(120)
		var lean: float = 0.0
		var frames_bad: int = 0
		var first_bad: Array[String] = []
		var head_x_max: float = 0.0
		var elbow_lo := {".R": INF, ".L": INF}
		var elbow_hi := {".R": -INF, ".L": -INF}
		for i in 12 * 60:
			var t: float = float(i) * FRAME
			var target: float = 0.45 * signf(sin(TAU * 0.25 * t))
			lean += (target - lean) * (1.0 - exp(-FRAME / LEAN_TAU))
			r.set_lean(lean)
			r.advance(FRAME)
			var bad := _seat_violations(r, saddle, arm[0], arm[1])
			if not bad.is_empty():
				frames_bad += 1
				if first_bad.is_empty():
					first_bad = bad
					first_bad.push_front("frame %d phi %.1f deg k %.3f" % [i, rad_to_deg(r.crank_rotation_rad()), r.effort_k])
			head_x_max = maxf(head_x_max, absf(_p(r, "head").x))
			# Elbow swing over the last 2 revolutions (k settled): spec list p.8 / criteria — ≤ 2°.
			if i >= 11 * 60:
				for side in [".R", ".L"]:
					var e := _angle_at(_p(r, "upperarm" + side), _p(r, "forearm" + side), _p(r, "hand" + side))
					elbow_lo[side] = minf(elbow_lo[side], e)
					elbow_hi[side] = maxf(elbow_hi[side], e)
		assert_eq(frames_bad, 0, "%s P %d W: frames violating p.1–5: %d; first: %s" % [src["name"], p_w, frames_bad, ", ".join(first_bad)])
		for side in [".R", ".L"]:
			gut.p("%s P %d W: elbow %s %.2f…%.2f° (rest %.2f°)" % [src["name"], p_w, side, elbow_lo[side], elbow_hi[side], arm[0][side]])
			assert_lte(elbow_hi[side] - elbow_lo[side], 2.0, "%s P %d W: elbow %s swing per revolution %.2f° (spec ≤ 2°)" % [
				src["name"], p_w, side, elbow_hi[side] - elbow_lo[side]])
		assert_lte(head_x_max, 0.02, "%s P %d W: head origin sideways %.4f m (spec ≤ 0.02)" % [src["name"], p_w, head_x_max])


## Spec «Hair», «Tail motion» and «Proposed criteria» (rev. 4.3): with k = 1.3, 90–120 rpm and
## lean in a turn ±0.45 rad the line «root — tip» drops from rest by no more than 4° (hard limit
## to the back), sideways ≤ 8°, the 20° cone is never reached. Lean driven like RideScene.
func test_p18_tail_line_limits_with_k_high_and_turns() -> void:
	var src: Dictionary = RiderContract.POSE_SOURCES[1]
	for rpm in [90, 100, 120]:
		for lean_mode in ["straight", "hold_left", "hold_right", "slalom"]:
			var r := _rider(src)
			r.set_power(FTP * 2, true, FTP)
			r.set_effort_k(1.3)
			r.set_cadence(rpm)
			var lean: float = 0.0
			var worst := Vector3.ZERO
			var max_up: float = 0.0
			for i in 30 * 60:
				var target: float = 0.0
				match lean_mode:
					"hold_left":
						target = 0.45
					"hold_right":
						target = -0.45
					"slalom":
						target = 0.45 * signf(sin(TAU * 0.3 * float(i) * FRAME))
				lean += (target - lean) * (1.0 - exp(-FRAME / LEAN_TAU))
				r.set_lean(lean)
				r.advance(FRAME)
				var d := _tail_dev(r)
				worst = Vector3(maxf(worst.x, absf(d.x)), maxf(worst.y, d.y), maxf(worst.z, d.z))
				max_up = maxf(max_up, -d.y)
			var tag := "%d rpm %s" % [rpm, lean_mode]
			assert_lte(worst.y, 4.0, "%s: tail line drops %.3f° (spec ≤ 4° to the back)" % [tag, worst.y])
			# Rise of the line is bounded by the spring parameter «up–down ±4°» (checked by the
			# constants); the hard line limit of the spec criteria is to the back (drop). The rise of
			# the line is logged for the report: the clamp acts on the spring angle, not on the line.
			if max_up > 4.0:
				gut.p("%s: NOTE tail line rises %.3f° (> 4° of the spring parameter)" % [tag, max_up])
			assert_lte(worst.x, 8.0, "%s: tail sideways %.3f° (spec ≤ 8°)" % [tag, worst.x])
			assert_lt(worst.z, 20.0, "%s: cone %.3f° (20° must not be reached)" % [tag, worst.z])


## Emergency cases: long frames (pause, hitch) and a lean jump — the tail stays finite and inside
## the 20° cone; the rest of the pose stays seated (cleat on pedal).
func test_p18_tail_long_frames_and_lean_jump_stay_in_cone() -> void:
	var src: Dictionary = RiderContract.POSE_SOURCES[1]
	var r := _rider(src)
	r.set_power(FTP * 2, true, FTP)
	r.set_cadence(120)
	for i in 300:
		r.set_lean(0.45 if (i / 30) % 2 == 0 else -0.45)
		r.advance(FRAME)
		var d := _tail_dev(r)
		assert_lt(d.z, 20.0, "lean jump frame %d: cone %.2f°" % [i, d.z])
		if d.z >= 20.0:
			return
	for dt in [0.1, 0.5, 2.0, 10.0]:
		r.set_lean(-r.lean_rad)
		r.advance(dt)
		var d := _tail_dev(r)
		assert_false(is_nan(d.x) or is_nan(d.y) or is_nan(d.z), "frame %.1f s: tail angles finite" % dt)
		assert_lt(d.z, 20.0, "frame %.1f s: cone %.2f°" % [dt, d.z])
		assert_lte(_p(r, "cleat.R").distance_to(_pedal(r, true)), 0.01, "frame %.1f s: cleat on pedal" % dt)


func _tail_amplitude(samples: PackedVector2Array) -> float:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for s in samples:
		lo = Vector2(minf(lo.x, s.x), minf(lo.y, s.y))
		hi = Vector2(maxf(hi.x, s.x), maxf(hi.y, s.y))
	return maxf(hi.x - lo.x, hi.y - lo.y) * 0.5


## REQ-D3D-09 p.18 as written: constant cadence 90/100/120 rpm, k at the upper bound, 60 s:
## amplitude over the last 10 revolutions ≤ the first 10 (+2 %); after the crank stops (cadence 0)
## the amplitude 3 s later ≤ 10 % of the amplitude before the stop. Amplitudes — half range of
## the sideways and vertical deviation of the tail line (the cone angle is not an amplitude).
func test_p18_tail_amplitude_does_not_grow_and_decays_after_stop() -> void:
	var src: Dictionary = RiderContract.POSE_SOURCES[1]
	for rpm in [90, 100, 120]:
		var r := _rider(src)
		r.set_power(FTP * 2, true, FTP)
		r.set_effort_k(1.3)
		r.set_cadence(rpm)
		var rev: int = int(round(3600.0 / float(rpm)))
		var total: int = 60 * 60
		var first := PackedVector2Array()
		var settled := PackedVector2Array()
		var last := PackedVector2Array()
		for i in total:
			r.advance(FRAME)
			var d := _tail_dev(r)
			var v := Vector2(d.x, d.y)
			if i < rev * 10:
				first.append(v)
			if i >= 180 and i < 180 + rev * 10:
				settled.append(v)
			if i >= total - rev * 10:
				last.append(v)
		var a_first := _tail_amplitude(first)
		var a_settled := _tail_amplitude(settled)
		var a_last := _tail_amplitude(last)
		gut.p("%d rpm: tail amplitude first 10 rev %.4f°, after 3 s %.4f°, last 10 rev %.4f°" % [rpm, a_first, a_settled, a_last])
		assert_gt(a_last, 0.05, "%d rpm: tail moves" % rpm)
		assert_lte(a_last, a_settled * 1.02, "%d rpm: last 10 rev ≤ 10 rev after settling (spec rev. 4.4)" % rpm)
		assert_lte(a_last, a_first * 1.02, "%d rpm: last 10 rev ≤ first 10 rev (REQ-D3D-09 p.18 wording)" % rpm)
		var before := PackedVector2Array()
		for v in last.slice(last.size() - rev):
			before.append(v)
		r.set_cadence(0)
		for i in 180:
			r.advance(FRAME)
		var after := PackedVector2Array()
		for i in rev:
			r.advance(FRAME)
			var d := _tail_dev(r)
			after.append(Vector2(d.x, d.y))
		var a_before := _tail_amplitude(before)
		var a_after := _tail_amplitude(after)
		assert_lte(a_after, a_before * 0.1, "%d rpm: 3 s after stop %.4f° ≤ 10 %% of %.4f°" % [rpm, a_after, a_before])


func _pose_snapshot(r: Rider) -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	var skel := r.skeleton()
	for i in skel.get_bone_count():
		out.append(skel.get_bone_global_pose(i))
	return out


func _pose_diff(a: Array[Transform3D], b: Array[Transform3D]) -> Vector2:
	var worst := Vector2.ZERO
	for i in a.size():
		var dq: float = rad_to_deg(a[i].basis.get_rotation_quaternion().angle_to(b[i].basis.get_rotation_quaternion()))
		worst = Vector2(maxf(worst.x, a[i].origin.distance_to(b[i].origin)), maxf(worst.y, dq))
	return worst


## P.16 (e) / D3D-04 p.2 after real pedalling: pedal 90 rpm at P = 0.5 FTP, then cadence 0; once
## the crank has stopped, P jumps to 1.5 FTP and back for 5 s. The pose (all bones) does not move
## (±1 mm, ±0.1°) and equals the pose of a twin rider that got no P change; k does not change.
func test_p16e_cadence_zero_after_pedalling_p_change_does_not_move_pose(src = use_parameters(RiderContract.POSE_SOURCES)) -> void:
	var a := _rider(src)
	var b := _rider(src)
	for r in [a, b]:
		r.set_power(FTP / 2, true, FTP)
		r.set_cadence(90)
		for i in 600:
			r.advance(FRAME)
		r.set_cadence(0)
	var settle: int = 0
	while a.is_pedaling() and settle < 600:
		a.advance(FRAME)
		b.advance(FRAME)
		settle += 1
	assert_false(a.is_pedaling(), "%s: crank stops after cadence 0 (frames %d)" % [src["name"], settle])
	var k0: float = a.effort_k
	var start := _pose_snapshot(a)
	var worst_twin := Vector2.ZERO
	var worst_abs := Vector2.ZERO
	for i in 5 * 60:
		a.set_power(FTP * 3 / 2 if (i / 60) % 2 == 0 else FTP / 4, true, FTP)
		a.advance(FRAME)
		b.advance(FRAME)
		var pa := _pose_snapshot(a)
		var dt := _pose_diff(pa, _pose_snapshot(b))
		var da := _pose_diff(pa, start)
		worst_twin = Vector2(maxf(worst_twin.x, dt.x), maxf(worst_twin.y, dt.y))
		worst_abs = Vector2(maxf(worst_abs.x, da.x), maxf(worst_abs.y, da.y))
	assert_almost_eq(a.effort_k, k0, 1e-9, "%s: k frozen at cadence 0" % src["name"])
	assert_lte(worst_twin.x, 0.001, "%s: P change moves bones by %.5f m" % [src["name"], worst_twin.x])
	assert_lte(worst_twin.y, 0.1, "%s: P change turns bones by %.4f°" % [src["name"], worst_twin.y])
	gut.p("%s: crank stopped %d frames after cadence 0; pose drift over 5 s %.5f m / %.4f°" % [src["name"], settle, worst_abs.x, worst_abs.y])
	assert_lte(worst_abs.x, 0.001, "%s: pose stands at cadence 0 (moved %.5f m)" % [src["name"], worst_abs.x])
	assert_lte(worst_abs.y, 0.1, "%s: pose stands at cadence 0 (turned %.4f°)" % [src["name"], worst_abs.y])


## P.7 / task: figure and hair swap while riding — the same nodes (instance_id), still 10
## `MeshInstance3D`, one material on all parts, the mesh of `Body`/`Hair` changes, the pose stays
## seated on the next frame.
func test_p7_swap_figure_and_hair_mid_ride_keeps_nodes_and_seat() -> void:
	var r := _rider(RiderContract.POSE_SOURCES[0])
	r.set_power(FTP, true, FTP)
	r.set_cadence(95)
	for i in 120:
		r.advance(FRAME)
	var ids := {}
	for n in r.find_children("*", "MeshInstance3D", true, false):
		ids[n.name] = n.get_instance_id()
	assert_eq(ids.size(), 10, "10 MeshInstance3D before swap")
	var body: MeshInstance3D = r.get_node("%Body")
	var hair: MeshInstance3D = r.get_node("%Hair")
	var meshes := [body.mesh, hair.mesh]
	for combo in [["f", "tail"], ["m", "tail"], ["f", "short"], ["m", "short"]]:
		r.set_figure(combo[0])
		r.set_hair_style(combo[1])
		for i in 30:
			r.advance(FRAME)
		var now := {}
		for n in r.find_children("*", "MeshInstance3D", true, false):
			now[n.name] = n.get_instance_id()
		assert_eq(now, ids, "%s/%s: same nodes" % combo)
		assert_lte(_p(r, "cleat.R").distance_to(_pedal(r, true)), 0.01, "%s/%s: cleat on pedal after swap" % combo)
		assert_lte(_p(r, "cleat.L").distance_to(_pedal(r, false)), 0.01, "%s/%s: left cleat on pedal after swap" % combo)
		var mats := {}
		for n in r.find_children("*", "MeshInstance3D", true, false):
			var mi := n as MeshInstance3D
			for s in mi.mesh.get_surface_count():
				var m: Material = mi.get_active_material(s)
				mats[m.get_instance_id() if m != null else 0] = true
		assert_eq(mats.size(), 1, "%s/%s: one rider material" % combo)
	r.set_figure("f")
	r.set_hair_style("tail")
	assert_ne(body.mesh, meshes[0], "Body mesh replaced by figure f")
	assert_ne(hair.mesh, meshes[1], "Hair mesh replaced by tail")


## P.7 / P.17 (d) / D3D-05 p.4: the per-frame path of `Rider` (advance → _pose_body → IK, sway,
## tail) and the static helpers it calls do not allocate: no `Array`/`Dictionary` literals or
## constructors, `new()`, `instantiate()`, string building, `duplicate()`, `append`/`resize`.
func test_p7_per_frame_rider_code_has_no_allocations() -> void:
	var files := {
		"res://src/scene3d/rider.gd": ["advance", "_process", "_pose_body", "_turn", "_solve_arm", "_solve_leg",
			"_step_tail", "_pose_tail", "_tail_turn", "effort_target", "set_lean"],
		"res://src/scene3d/rider_motion.gd": ["wave", "foot_pitch_rad", "knee_x", "pelvis_roll_rad", "chest_roll_rad",
			"chest_yaw_rad", "has_effort_source", "effort_target", "smooth_effort"],
		"res://src/scene3d/rider_model.gd": ["two_bone_joint", "two_bone_joint_x", "arm_frame", "bone_basis", "pedal_bone_angle"],
		"res://src/scene3d/rider_rig.gd": ["foot_pitch_rad"],
	}
	var re_bad := RegEx.create_from_string("(\\[\\s*\\]|\\[[^\\]]*,|\\{|\\.new\\(|instantiate\\(|\\bstr\\(|\" ?%|\\.duplicate\\(|\\.append\\(|\\.resize\\(|\\bArray\\(|\\bDictionary\\(|String\\(|PackedVector3Array\\(|PackedFloat32Array\\()")
	for path in files:
		var text := FileAccess.get_file_as_string(path)
		assert_false(text.is_empty(), "%s readable" % path)
		for fn in files[path]:
			var body := _func_body(text, fn)
			assert_false(body.is_empty(), "%s: func %s found" % [path, fn])
			for line in body.split("\n"):
				var code: String = line.split("#")[0]
				if code.strip_edges().begins_with("assert"):
					continue
				var m := re_bad.search(code)
				assert_null(m, "%s %s(): allocation in per-frame code: %s" % [path.get_file(), fn, code.strip_edges()])


func _func_body(text: String, fn: String) -> String:
	var re := RegEx.create_from_string("(?m)^(static )?func " + fn + "\\(")
	var m := re.search(text)
	if m == null:
		return ""
	var rest := text.substr(m.get_end())
	var lines := rest.split("\n")
	var out := PackedStringArray()
	for i in range(1, lines.size()):
		var l: String = lines[i]
		if not l.is_empty() and not l.begins_with("\t") and not l.begins_with(" "):
			break
		out.append(l)
	return "\n".join(out)
