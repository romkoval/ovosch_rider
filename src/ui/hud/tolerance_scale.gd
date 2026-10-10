class_name ToleranceScale
extends RefCounted
## "Above / below target" with a tolerance scale (`docs/game/hud.md` p. 16.2–16.3, REQ-WRK-09 p.5
## (б)–(г), REQ-HUD-02 p.6): the one component for every case where nothing holds the target for
## the rider — `smart` with ERG off or unavailable and `power_meter` (T-175; T-171 reuses it).
##
## Numbers: tol = max(5 % · T, 10 W), h = max(2.5 % · T, 5 W), half range R = 3 · tol; the tolerance
## band is the middle third of the scale. The marker stands at x = 0.5 + clamp((P − T) / R, −1, 1) / 2
## of the width (no hysteresis), beyond R it becomes a triangle at the edge.
##
## States (per sample, `update`): entering "on" — |P − T| ≤ tol; leaving "on" — only when
## |P − T| > tol + h; "above" ↔ "below" at once. The first state (after `reset`, after the
## acclimatisation window, after "no data") has no hysteresis. In the window (the first 5 s of a
## step) the state is `STATE_WINDOW`: marker in `hud.text`, no glyph and no difference.

const TOL_PCT: float = 0.05
const TOL_MIN_W: float = 10.0
const HYST_PCT: float = 0.025
const HYST_MIN_W: float = 5.0
## Half range of the scale in tolerances.
const RANGE_TOLS: float = 3.0
## Acclimatisation window: samples 1…5 of a step.
const WINDOW_SEC: int = 5
const STATE_WINDOW: String = "window"

var _state: String = HudModel.DEVIATION_HIDDEN


static func tolerance(target_w: float) -> float:
	return maxf(TOL_PCT * target_w, TOL_MIN_W)


static func hysteresis(target_w: float) -> float:
	return maxf(HYST_PCT * target_w, HYST_MIN_W)


static func half_range(target_w: float) -> float:
	return RANGE_TOLS * tolerance(target_w)


## Marker position as a share of the scale width from the left edge (0…1).
static func marker_fraction(power_w: float, target_w: float) -> float:
	return 0.5 + clampf((power_w - target_w) / half_range(target_w), -1.0, 1.0) * 0.5


## −1 — beyond the left edge (◀), 1 — beyond the right edge (▶), 0 — on the scale.
static func edge(power_w: float, target_w: float) -> int:
	var d := power_w - target_w
	var r := half_range(target_w)
	if d < -r:
		return -1
	if d > r:
		return 1
	return 0


## Tolerance band as shares of the width: always the middle third (R = 3 · tol).
static func band() -> Vector2:
	return Vector2(0.5 - 0.5 / RANGE_TOLS, 0.5 + 0.5 / RANGE_TOLS)


## Next state from `previous` (`HudModel.DEVIATION_HIDDEN` — first state, no hysteresis).
static func next_state(previous: String, power_w: float, target_w: float) -> String:
	var d := power_w - target_w
	var tol := tolerance(target_w)
	var off := HudModel.DEVIATION_ABOVE if d > 0.0 else HudModel.DEVIATION_BELOW
	match previous:
		HudModel.DEVIATION_ON:
			return HudModel.DEVIATION_ON if absf(d) <= tol + hysteresis(target_w) else off
		_:
			return HudModel.DEVIATION_ON if absf(d) <= tol else off


## Forget the previous state: the next one has no hysteresis (scale just switched on).
func reset() -> void:
	_state = HudModel.DEVIATION_HIDDEN


func state() -> String:
	return _state


## One sample: `has_power` false — "no data" (hidden); `in_window` — acclimatisation window.
func update(power_w: float, target_w: float, has_power: bool, in_window: bool) -> String:
	if not has_power or target_w <= 0.0:
		_state = HudModel.DEVIATION_HIDDEN
		return _state
	if in_window:
		_state = HudModel.DEVIATION_HIDDEN
		return STATE_WINDOW
	_state = next_state(_state, power_w, target_w)
	return _state
