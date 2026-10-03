class_name IntervalsIcuWorkoutParser
extends RefCounted
## Разбор структурированной тренировки из события календаря Intervals.icu
## (`GET /api/v1/athlete/{id}/events`) в `Workout` (REQ-INT-03, REQ-NFR-09 крит. 3).
##
## Два источника внутри события:
## 1. `workout_doc.steps` — массив шагов `{duration, power: {value|start,end|low,high,
##    units: "%ftp"|"w"}, ramp, cadence, text, freeride, warmup, cooldown, reps, steps[]}`;
##    вложенные `steps` с `reps` — повтор (крит. 5); `power.start/end` с `ramp: true` —
##    рампа (крит. 4), без `ramp` — диапазон → середина (крит. 3); `low/high` → середина;
##    `freeride: true` — шаг без цели.
## 2. Текстовое описание (`description`) в синтаксисе Intervals.icu — когда
##    `workout_doc` нет (см. `parse_description_text`):
##      - 10m 65%            → 600 с, 65 % FTP (крит. 1)
##      - 5m 250w            → 300 с, 250 Вт (крит. 2)
##      - 10m 85-95%         → середина 90 % (крит. 3)
##      - 8m ramp 50-75%     → рампа 50 → 75 % (крит. 4)
##      3x                   → блок следующих строк «- …» до пустой строки повторяется 3 раза
##      3x (4m 105%, 2m 50%) → то же в одну строку (крит. 5)
##      - 4m 105% 95rpm      → каденс 95 (крит. 6; `80-90rpm` → середина)
##      Строка без дефиса → текстовая подсказка следующего шага (крит. 7).
##      Слова после целей внутри шага (например `- 10m 65% Spin easy`) — подсказка шага.
##    Неподдерживаемые цели → ошибка с номером строки и позицией (крит. 9): только токены,
##    похожие на цель — пульс `140bpm`/`140-150bpm`/`80%hr`, зона `Z2`, темп `4:30/km`,
##    `press lap` у шага без цели по мощности. Свободные слова (`Keep HR low`) после валидной
##    цели — подсказка, не ошибка.
##
## Сумма длительностей сверяется с заявленной (`event.duration`, иначе
## `workout_doc.duration`, иначе `event.moving_time`): расхождение > 1 с →
## предупреждение (крит. 8). Любая ошибка → `workout == null` (крит. 9).
##
## Для `workout_doc` в ошибках `line` — порядковый номер шага верхнего уровня
## (1-based), `element` — путь вида `steps[2].steps[0].power`.

const UNITS_PERCENT: Array[String] = ["%ftp", "%", "percent_ftp", "ftp"]
const UNITS_WATTS: Array[String] = ["w", "watts", "watt"]

## Токен-цель, которую движок не поддерживает (пульс, зоны, темп).
const UNSUPPORTED_TARGET_RE: String = "^(?:\\d+(?:[.,:]\\d+)?(?:-\\d+(?:[.,:]\\d+)?)?(?:bpm|%hr|%lthr|%maxhr|/km|/mi|km/h|kph|mph)|z[1-7])$"
const DURATION_RE: String = "^(?:(\\d+)h)?(?:(\\d+)m)?(?:(\\d+)s)?$"
const CLOCK_RE: String = "^(\\d+):(\\d{1,2})(?::(\\d{1,2}))?$"
const POWER_RE: String = "^(\\d+(?:[.,]\\d+)?)(?:-(\\d+(?:[.,]\\d+)?))?(%|w)$"
const CADENCE_RE: String = "^(\\d+)(?:-(\\d+))?rpm$"
const REPEAT_LINE_RE: String = "^(\\d+)\\s*[xX×](?:\\s*\\((.*)\\))?\\s*$"


## Событие календаря → план.
static func parse(event: Dictionary) -> ParseResult:
	var result: ParseResult
	var doc: Variant = event.get("workout_doc")
	if doc is Dictionary and (doc as Dictionary).get("steps") is Array:
		result = _parse_doc(doc as Dictionary)
	else:
		result = parse_description_text(str(event.get("description", "")))
	if result.workout != null:
		var w: Workout = result.workout
		var name := str(event.get("name", ""))
		if not name.is_empty():
			w.name = name
		if w.description.is_empty():
			w.description = str(event.get("description", ""))
		w.source = "intervals_icu"
	for key in ["id", "start_date_local", "type", "category", "external_id", "icu_training_load"]:
		if event.has(key):
			result.metadata[key] = event[key]
	if result.workout != null:
		result.workout.metadata = result.metadata.duplicate(true)
		if event.has("id"):
			result.workout.metadata["event_id"] = str(event["id"])
	_check_declared_duration(result, event, doc)
	return result


# ---------------------------------------------------------------------------
# workout_doc
# ---------------------------------------------------------------------------

static func _parse_doc(doc: Dictionary) -> ParseResult:
	var result := ParseResult.new()
	var steps: Array[WorkoutStep] = _parse_doc_steps(doc["steps"], "steps", 0, result)
	if not result.errors.is_empty():
		return result
	if steps.is_empty():
		result.add_error("тренировка не содержит шагов", 0, 0, "workout_doc.steps", "no_steps")
		return result
	var w := Workout.new()
	w.source = "intervals_icu"
	w.steps = steps
	w.description = str(doc.get("description", ""))
	for e in w.validate():
		result.add_error(e, 0, 0, "workout_doc", "invalid_workout")
	result.set_workout(w)
	return result


## Рекурсивный разбор массива шагов. `top_line` — номер шага верхнего уровня (0 — мы на верхнем уровне).
static func _parse_doc_steps(items: Array, path: String, top_line: int, result: ParseResult) -> Array[WorkoutStep]:
	var out: Array[WorkoutStep] = []
	for i in items.size():
		var item: Variant = items[i]
		var step_path := "%s[%d]" % [path, i]
		var line := top_line if top_line > 0 else i + 1
		if not (item is Dictionary):
			result.add_error("шаг должен быть объектом", line, 0, step_path, "bad_step")
			continue
		var step: Dictionary = item
		if step.get("steps") is Array:
			var reps := int(step.get("reps", 1))
			if reps <= 0:
				result.add_error("число повторов должно быть ≥ 1 (сейчас %d)" % reps, line, 0, step_path + ".reps", "bad_repeat")
				continue
			var block := _parse_doc_steps(step["steps"], step_path + ".steps", line, result)
			out.append_array(Workout.expand_repeat(block, reps))
			continue
		var s := _parse_doc_step(step, step_path, line, result)
		if s != null:
			out.append(s)
	return out


static func _parse_doc_step(step: Dictionary, path: String, line: int, result: ParseResult) -> WorkoutStep:
	var duration := _doc_duration(step.get("duration"))
	if duration <= 0:
		result.add_error("длительность шага должна быть > 0 с (сейчас %s)" % str(step.get("duration", "нет")), line, 0, path + ".duration", "bad_duration")
		return null
	var s: WorkoutStep = null
	var kind := WorkoutStep.StepKind.STEADY
	if bool(step.get("warmup", false)):
		kind = WorkoutStep.StepKind.WARMUP
	elif bool(step.get("cooldown", false)):
		kind = WorkoutStep.StepKind.COOLDOWN
	for unsupported in ["hr", "pace"]:
		if step.has(unsupported) and step[unsupported] != null:
			result.add_error("цель '%s' не поддерживается (только мощность)" % unsupported, line, 0, path + "." + unsupported, "unsupported_target")
			return null
	var power: Variant = step.get("power")
	if bool(step.get("freeride", false)) or power == null:
		if power == null and not bool(step.get("freeride", false)):
			result.add_warning("у шага нет цели по мощности — свободная езда", line, 0, path, "no_target")
		s = WorkoutStep.free_ride(duration)
	elif power is Dictionary:
		s = _doc_power_step(power as Dictionary, duration, bool(step.get("ramp", false)), kind, path + ".power", line, result)
		if s == null:
			return null
	elif power is float or power is int:
		s = WorkoutStep.percent(duration, float(power), kind)
	else:
		result.add_error("поле power имеет неподдерживаемый вид", line, 0, path + ".power", "bad_power")
		return null
	var cadence: Variant = step.get("cadence")
	if cadence is Dictionary:
		var cd: Dictionary = cadence
		if cd.has("value"):
			s.cadence_rpm = int(cd["value"])
		elif cd.has("start") and cd.has("end"):
			s.cadence_rpm = roundi((float(cd["start"]) + float(cd["end"])) / 2.0)
		elif cd.has("low") and cd.has("high"):
			s.cadence_rpm = roundi((float(cd["low"]) + float(cd["high"])) / 2.0)
	elif cadence is float or cadence is int:
		s.cadence_rpm = int(cadence)
	var text := str(step.get("text", "")).strip_edges()
	if not text.is_empty():
		s.text_cues.append(TextCue.make(0, text))
	return s


static func _doc_duration(v: Variant) -> int:
	if v is float or v is int:
		return roundi(float(v))
	if v is String:
		var d := _parse_duration_token(str(v))
		return d
	return 0


static func _doc_power_step(power: Dictionary, duration: int, ramp: bool, kind: WorkoutStep.StepKind,
		path: String, line: int, result: ParseResult) -> WorkoutStep:
	var units := str(power.get("units", "%ftp")).to_lower().strip_edges()
	var in_watts := false
	if UNITS_WATTS.has(units):
		in_watts = true
	elif not UNITS_PERCENT.has(units):
		result.add_error("единицы мощности '%s' не поддерживаются (ожидается %%ftp или w)" % units, line, 0, path + ".units", "unsupported_units")
		return null
	var lo: Variant = null
	var hi: Variant = null
	if power.has("value"):
		lo = power["value"]
		hi = lo
	elif power.has("start") or power.has("end"):
		lo = power.get("start", power.get("end"))
		hi = power.get("end", power.get("start"))
	elif power.has("low") or power.has("high"):
		lo = power.get("low", power.get("high"))
		hi = power.get("high", power.get("low"))
		ramp = false
	if lo == null or hi == null or not (_is_num(lo) and _is_num(hi)):
		result.add_error("у цели по мощности нет числового значения", line, 0, path, "bad_power")
		return null
	var a := float(lo)
	var b := float(hi)
	if a < 0.0 or b < 0.0:
		result.add_error("отрицательная целевая мощность", line, 0, path, "negative_target")
		return null
	if ramp and not is_equal_approx(a, b):
		var rk := kind if kind != WorkoutStep.StepKind.STEADY else WorkoutStep.StepKind.RAMP
		return WorkoutStep.ramp_watts(duration, a, b, rk) if in_watts else WorkoutStep.ramp_percent(duration, a, b, rk)
	var mid := (a + b) / 2.0
	return WorkoutStep.watts(duration, mid, kind) if in_watts else WorkoutStep.percent(duration, mid, kind)


static func _is_num(v: Variant) -> bool:
	return v is float or v is int


# ---------------------------------------------------------------------------
# Текстовое описание
# ---------------------------------------------------------------------------

## Разбор текстового описания тренировки Intervals.icu (см. шапку файла).
static func parse_description_text(text: String) -> ParseResult:
	var result := ParseResult.new()
	if text.strip_edges().is_empty():
		result.add_error("описание тренировки пустое", 0, 0, "description", "empty_description")
		return result
	var lines: PackedStringArray = text.replace("\r\n", "\n").replace("\r", "\n").split("\n")
	var steps: Array[WorkoutStep] = []
	var block: Array[WorkoutStep] = []  # шаги текущего повтора
	var block_reps: int = 0  # 0 — вне повтора
	var pending_cues: Array[String] = []
	var repeat_re := RegEx.create_from_string(REPEAT_LINE_RE)
	var line_no: int = 0
	for raw in lines:
		line_no += 1
		var line := raw.strip_edges()
		if line.is_empty():
			if block_reps > 0:
				steps.append_array(Workout.expand_repeat(block, block_reps))
				block = []
				block_reps = 0
			continue
		var rm := repeat_re.search(line)
		if rm != null:
			if block_reps > 0:
				steps.append_array(Workout.expand_repeat(block, block_reps))
				block = []
			var reps := int(rm.get_string(1))
			if reps <= 0:
				result.add_error("число повторов должно быть ≥ 1 (сейчас %d)" % reps, line_no, 1, line, "bad_repeat")
				continue
			var inline := rm.get_string(2).strip_edges()
			if not inline.is_empty():
				var inline_block: Array[WorkoutStep] = []
				var col_base := line.find("(") + 2
				for part in inline.split(","):
					var s := _parse_step_text(part.strip_edges(), line_no, col_base, pending_cues, result)
					col_base += part.length() + 1
					if s != null:
						inline_block.append(s)
				steps.append_array(Workout.expand_repeat(inline_block, reps))
				block_reps = 0
			else:
				block_reps = reps
			continue
		if line.begins_with("-") or line.begins_with("•") or line.begins_with("*"):
			var body := line.substr(1).strip_edges()
			var col := raw.find(body) + 1
			var s := _parse_step_text(body, line_no, col, pending_cues, result)
			if s != null:
				if block_reps > 0:
					block.append(s)
				else:
					steps.append(s)
			continue
		pending_cues.append(line)
	if block_reps > 0:
		steps.append_array(Workout.expand_repeat(block, block_reps))
	if not pending_cues.is_empty():
		result.add_warning("текст без шага после него не привязан к подсказкам: '%s'" % " / ".join(pending_cues), line_no, 0, "", "dangling_text")
	if not result.errors.is_empty():
		return result
	if steps.is_empty():
		result.add_error("в описании не найдено ни одного шага (строки вида «- 10m 65%»)", 0, 0, "description", "no_steps")
		return result
	var w := Workout.new()
	w.source = "intervals_icu"
	w.steps = steps
	for e in w.validate():
		result.add_error(e, 0, 0, "description", "invalid_workout")
	result.set_workout(w)
	return result


## Один шаг из текста вида `10m 65% 90rpm Some text`. `col` — позиция начала текста в строке (1-based).
static func _parse_step_text(body: String, line_no: int, col: int, pending_cues: Array[String], result: ParseResult) -> WorkoutStep:
	var tokens: PackedStringArray = body.split(" ", false)
	var duration: int = -1
	var is_ramp := false
	var free := false
	var has_power := false
	var in_watts := false
	var p_lo := 0.0
	var p_hi := 0.0
	var cadence: int = 0
	var text_words: Array[String] = []
	var power_re := RegEx.create_from_string(POWER_RE)
	var cadence_re := RegEx.create_from_string(CADENCE_RE)
	var unsupported_re := RegEx.create_from_string(UNSUPPORTED_TARGET_RE)
	var cursor := col
	var idx := 0
	var step_has_power := false
	for t in tokens:
		if power_re.search(t.to_lower()) != null:
			step_has_power = true
	while idx < tokens.size():
		var tok := tokens[idx]
		var tok_l := tok.to_lower()
		var tok_col := cursor
		cursor += tok.length() + 1
		idx += 1
		if duration < 0:
			var d := _parse_duration_token(tok_l)
			if d > 0:
				duration = d
				continue
		if tok_l == "ramp":
			is_ramp = true
			continue
		if tok_l == "freeride" or tok_l == "free":
			free = true
			continue
		var pm := power_re.search(tok_l)
		if pm != null and not has_power:
			if pm.get_string(3) == "%" and idx < tokens.size() and tokens[idx].to_lower() == "hr":
				result.add_error("элемент '%s hr' не поддерживается (только цели по мощности)" % tok, line_no, tok_col, tok + " hr", "unsupported_element")
				return null
			has_power = true
			p_lo = pm.get_string(1).replace(",", ".").to_float()
			p_hi = pm.get_string(2).replace(",", ".").to_float() if not pm.get_string(2).is_empty() else p_lo
			in_watts = pm.get_string(3) == "w"
			continue
		var cm := cadence_re.search(tok_l)
		if cm != null:
			var lo := int(cm.get_string(1))
			var hi := int(cm.get_string(2)) if not cm.get_string(2).is_empty() else lo
			cadence = roundi(float(lo + hi) / 2.0)
			continue
		if unsupported_re.search(tok_l) != null:
			result.add_error("элемент '%s' не поддерживается (только цели по мощности)" % tok, line_no, tok_col, tok, "unsupported_element")
			return null
		if tok_l == "press" and idx < tokens.size() and tokens[idx].to_lower() == "lap" and not step_has_power:
			result.add_error("элемент 'press lap' не поддерживается (шаг без цели по мощности)", line_no, tok_col, "press lap", "unsupported_element")
			return null
		text_words.append(tok)
	if duration <= 0:
		result.add_error("у шага нет длительности (например «10m»): '%s'" % body, line_no, col, body, "missing_duration")
		return null
	var s: WorkoutStep
	if free or not has_power:
		if not has_power and not free:
			result.add_warning("у шага нет цели по мощности — свободная езда: '%s'" % body, line_no, col, body, "no_target")
		s = WorkoutStep.free_ride(duration)
	elif is_ramp and not is_equal_approx(p_lo, p_hi):
		s = WorkoutStep.ramp_watts(duration, p_lo, p_hi) if in_watts else WorkoutStep.ramp_percent(duration, p_lo, p_hi)
	else:
		var mid := (p_lo + p_hi) / 2.0
		s = WorkoutStep.watts(duration, mid) if in_watts else WorkoutStep.percent(duration, mid)
	s.cadence_rpm = cadence
	for cue in pending_cues:
		s.text_cues.append(TextCue.make(0, cue))
	pending_cues.clear()
	if not text_words.is_empty():
		s.text_cues.append(TextCue.make(0, " ".join(text_words)))
	return s


## `10m`, `30s`, `1h`, `1h30m`, `90s`, `10:00`, `1:00:00` → секунды; 0 — не длительность.
static func _parse_duration_token(tok: String) -> int:
	var t := tok.strip_edges().to_lower()
	if t.is_empty():
		return 0
	var clock := RegEx.create_from_string(CLOCK_RE).search(t)
	if clock != null:
		var a := int(clock.get_string(1))
		var b := int(clock.get_string(2))
		if clock.get_string(3).is_empty():
			return a * 60 + b
		return a * 3600 + b * 60 + int(clock.get_string(3))
	var m := RegEx.create_from_string(DURATION_RE).search(t)
	if m == null:
		return 0
	var total := 0
	if not m.get_string(1).is_empty():
		total += int(m.get_string(1)) * 3600
	if not m.get_string(2).is_empty():
		total += int(m.get_string(2)) * 60
	if not m.get_string(3).is_empty():
		total += int(m.get_string(3))
	return total


static func _check_declared_duration(result: ParseResult, event: Dictionary, doc: Variant) -> void:
	if result.workout == null:
		return
	var declared: Variant = null
	if _is_num(event.get("duration")):
		declared = event["duration"]
	elif doc is Dictionary and _is_num((doc as Dictionary).get("duration")):
		declared = (doc as Dictionary)["duration"]
	elif _is_num(event.get("moving_time")):
		declared = event["moving_time"]
	if declared == null:
		return
	var total := result.workout.total_duration_sec()
	if absi(total - roundi(float(declared))) > 1:
		result.add_warning("сумма длительностей шагов %d с не совпадает с заявленной %d с" % [total, roundi(float(declared))],
				0, 0, "duration", "duration_mismatch")
