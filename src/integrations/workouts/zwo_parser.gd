class_name ZwoParser
extends RefCounted
## Парсер файлов ZWO (Zwift Workout) на `XMLParser` (REQ-IMP-01, REQ-IMP-05).
##
## Поддерживается:
## - `<workout_file>`: `name`, `description` → `Workout`; `author`, `sportType` и прочие
##   простые текстовые элементы → `ParseResult.metadata` (REQ-IMP-01 крит. 5);
## - `Warmup`, `Cooldown`, `Ramp` → рампа `PowerLow→PowerHigh` (крит. 1);
## - `SteadyState` → постоянная цель `Power` (крит. 1);
## - `IntervalsT` → `Repeat` × (`OnDuration`/`OnPower`, `OffDuration`/`OffPower`),
##   раскрывается в плоский список через `Workout.expand_repeat` (крит. 1);
## - `FreeRide` → шаг без цели (крит. 2); `MaxEffort` → как `FreeRide`, с предупреждением;
## - `Cadence`, `CadenceLow`/`CadenceHigh` (середина), `CadenceResting` (крит. 3);
## - `textevent` (`timeoffset`, `message`) → `TextCue` шага; `duration` игнорируется
##   (крит. 4). Внутри `IntervalsT` смещение отсчитывается от начала пары on/off
##   и повторяется в каждом повторе (так ведёт себя Zwift).
## - атрибуты `pace`, `OverUnder`, `SolidState` — предупреждение «не поддерживается».
##
## Мощность в ZWO — доля FTP (0.75 → 75 %), длительности — секунды.
## Имена элементов и атрибутов сравниваются без учёта регистра.
##
## Ошибки (REQ-IMP-05): неизвестный элемент внутри `<workout>` или шага → ошибка
## с именем элемента и номером строки (1-based), ключ `unknown_element`; не-XML или
## обрыв разметки → одна структурная ошибка. При любой ошибке `workout == null`.

const STEP_ELEMENTS: Array[String] = ["warmup", "cooldown", "steadystate", "intervalst", "ramp", "freeride", "maxeffort"]
const UNSUPPORTED_ATTRIBUTES: Array[String] = ["pace", "overunder", "solidstate"]
const ROOT_ELEMENT: String = "workout_file"
const WORKOUT_ELEMENT: String = "workout"
const TEXT_EVENT: String = "textevent"
## sportType, при которых не выдаётся предупреждение «не велосипед».
const BIKE_SPORT_TYPES: Array[String] = ["bike", "", "cycling"]


## Разобранный план или ошибки. Никогда не бросает и не пишет ошибок движка.
static func parse(xml_text: String) -> ParseResult:
	var result := ParseResult.new()
	if xml_text.strip_edges().is_empty():
		result.add_error("файл пуст", 0, 0, "", "empty_file")
		return result
	var parser := XMLParser.new()
	if parser.open_buffer(xml_text.to_utf8_buffer()) != OK:
		result.add_error("не удалось прочитать файл как XML", 0, 0, "", "invalid_xml")
		return result

	var workout := Workout.new()
	workout.source = "zwo"
	var steps: Array[WorkoutStep] = []
	var stack: Array[String] = []  # имена открытых элементов (в нижнем регистре)
	var saw_root := false
	var saw_workout := false
	var meta_text := ""
	# Шаги текущего элемента-шага (1 для простых, 2 для IntervalsT) и число повторов.
	var pending: Array[WorkoutStep] = []
	var pending_repeat: int = 1
	var pending_is_intervals := false
	var last_line: int = 1

	while true:
		var err := parser.read()
		if err != OK:
			break
		var node_type := parser.get_node_type()
		last_line = parser.get_current_line() + 1
		match node_type:
			XMLParser.NODE_ELEMENT:
				var name: String = parser.get_node_name()
				var lname := name.to_lower()
				var line := parser.get_current_line() + 1
				var attrs := _attributes(parser)
				var self_closing := parser.is_empty()
				var depth := stack.size()
				if depth == 0:
					if lname != ROOT_ELEMENT:
						result.add_error("файл не является тренировкой ZWO: корневой элемент <%s>, ожидался <workout_file>" % name,
								line, 0, name, "not_zwo")
						return result
					saw_root = true
				elif depth == 1:
					if lname == WORKOUT_ELEMENT:
						saw_workout = true
					else:
						meta_text = ""
				elif stack[depth - 1] == WORKOUT_ELEMENT:
					if STEP_ELEMENTS.has(lname):
						pending = []
						pending_repeat = 1
						pending_is_intervals = lname == "intervalst"
						_warn_unsupported_attributes(result, attrs, name, line)
						var built := _build_step(lname, attrs, name, line, result)
						pending = built.steps
						pending_repeat = built.repeat
					elif lname == TEXT_EVENT:
						result.add_warning("подсказка textevent вне шага игнорируется", line, 0, name, "cue_outside_step")
					else:
						result.add_error("элемент %s не поддерживается" % name, line, 0, name, "unknown_element")
				elif STEP_ELEMENTS.has(stack[depth - 1]):
					if lname == TEXT_EVENT:
						_attach_cue(pending, attrs, name, line, result)
					else:
						result.add_error("элемент %s не поддерживается" % name, line, 0, name, "unknown_element")
				# Глубже (например, <tags><tag/>) — метаданные, молча пропускаем.
				if self_closing:
					if depth == 2 and stack[depth - 1] == WORKOUT_ELEMENT and STEP_ELEMENTS.has(lname):
						_flush_pending(steps, pending, pending_repeat, pending_is_intervals)
						pending = []
					elif depth == 1 and lname != WORKOUT_ELEMENT:
						_store_meta(workout, result, lname, "")
				else:
					stack.append(lname)
			XMLParser.NODE_ELEMENT_END:
				var lname := parser.get_node_name().to_lower()
				var line := parser.get_current_line() + 1
				if stack.is_empty() or stack[stack.size() - 1] != lname:
					var expected := "" if stack.is_empty() else stack[stack.size() - 1]
					result.add_error("нарушена структура XML: закрывающий тег </%s>, ожидался </%s>" % [parser.get_node_name(), expected],
							line, 0, parser.get_node_name(), "invalid_xml")
					return result
				stack.pop_back()
				var depth := stack.size()
				if depth == 2 and stack[1] == WORKOUT_ELEMENT and STEP_ELEMENTS.has(lname):
					_flush_pending(steps, pending, pending_repeat, pending_is_intervals)
					pending = []
				elif depth == 1 and lname != WORKOUT_ELEMENT:
					_store_meta(workout, result, lname, meta_text.strip_edges())
					meta_text = ""
			XMLParser.NODE_TEXT, XMLParser.NODE_CDATA:
				if stack.size() == 2 and stack[1] != WORKOUT_ELEMENT:
					meta_text += parser.get_node_data()
			_:
				pass

	if not saw_root:
		result.add_error("файл не является тренировкой ZWO: нет корневого элемента <workout_file>", 0, 0, "", "not_zwo")
		return result
	if not stack.is_empty():
		result.add_error("XML обрывается: не закрыт элемент <%s>" % stack[stack.size() - 1], last_line, 0,
				stack[stack.size() - 1], "invalid_xml")
		return result
	if not saw_workout:
		result.add_error("в файле нет элемента <workout>", 0, 0, "workout", "no_workout")
		return result
	if not result.errors.is_empty():
		return result
	if steps.is_empty():
		result.add_error("тренировка не содержит шагов", 0, 0, "workout", "no_steps")
		return result
	workout.steps = steps
	for e in workout.validate():
		result.add_error(e, 0, 0, "", "invalid_workout")
	result.set_workout(workout)
	return result


# ---------------------------------------------------------------------------
# Вспомогательные
# ---------------------------------------------------------------------------

## Атрибуты элемента: имя в нижнем регистре → значение.
static func _attributes(parser: XMLParser) -> Dictionary:
	var attrs := {}
	for i in parser.get_attribute_count():
		attrs[parser.get_attribute_name(i).to_lower()] = parser.get_attribute_value(i)
	return attrs


static func _warn_unsupported_attributes(result: ParseResult, attrs: Dictionary, element: String, line: int) -> void:
	for a in UNSUPPORTED_ATTRIBUTES:
		if attrs.has(a):
			result.add_warning("атрибут %s не поддерживается и игнорируется" % a, line, 0, element, "unsupported_attribute")


## Доля FTP → проценты с округлением до сотых (0.65 → 65.0 без хвоста плавающей точки).
static func _to_percent(fraction: float) -> float:
	return roundf(fraction * 10000.0) / 100.0


## Числовой атрибут; `null`, если атрибута нет; ошибка, если не число.
static func _number(attrs: Dictionary, key: String, element: String, line: int, result: ParseResult) -> Variant:
	if not attrs.has(key):
		return null
	var raw: String = str(attrs[key]).strip_edges().replace(",", ".")
	if not raw.is_valid_float():
		result.add_error("атрибут %s: ожидалось число, получено '%s'" % [key, raw], line, 0, element, "bad_number")
		return null
	return raw.to_float()


static func _duration(attrs: Dictionary, key: String, element: String, line: int, result: ParseResult) -> int:
	var v: Variant = _number(attrs, key, element, line, result)
	if v == null:
		if not attrs.has(key):
			result.add_error("у элемента %s нет атрибута %s" % [element, key], line, 0, element, "missing_attribute")
		return 0
	var dur := roundi(float(v))
	if dur <= 0:
		result.add_error("атрибут %s должен быть > 0 с (сейчас %s)" % [key, str(v)], line, 0, element, "bad_duration")
		return 0
	return dur


## Целевой каденс из `Cadence` либо середины `CadenceLow`/`CadenceHigh`; 0 — не задан.
static func _cadence(attrs: Dictionary, element: String, line: int, result: ParseResult, key: String = "cadence") -> int:
	var c: Variant = _number(attrs, key, element, line, result)
	if c != null:
		return maxi(0, roundi(float(c)))
	if key != "cadence":
		return 0
	var lo: Variant = _number(attrs, "cadencelow", element, line, result)
	var hi: Variant = _number(attrs, "cadencehigh", element, line, result)
	if lo != null and hi != null:
		return maxi(0, roundi((float(lo) + float(hi)) / 2.0))
	if lo != null:
		return maxi(0, roundi(float(lo)))
	if hi != null:
		return maxi(0, roundi(float(hi)))
	return 0


## Шаги элемента: `{steps: Array[WorkoutStep], repeat: int}`. При ошибке — пустой список.
static func _build_step(lname: String, attrs: Dictionary, element: String, line: int, result: ParseResult) -> Dictionary:
	var out: Array[WorkoutStep] = []
	var repeat: int = 1
	match lname:
		"warmup", "cooldown", "ramp":
			var dur := _duration(attrs, "duration", element, line, result)
			var low: Variant = _number(attrs, "powerlow", element, line, result)
			var high: Variant = _number(attrs, "powerhigh", element, line, result)
			var power: Variant = _number(attrs, "power", element, line, result)
			if low == null and high == null and power != null:
				low = power
				high = power
			elif low == null and high != null:
				low = high
			elif high == null and low != null:
				high = low
			if low == null:
				result.add_error("у элемента %s нет атрибутов PowerLow/PowerHigh" % element, line, 0, element, "missing_attribute")
			if dur > 0 and low != null:
				var kind := WorkoutStep.StepKind.RAMP
				if lname == "warmup":
					kind = WorkoutStep.StepKind.WARMUP
				elif lname == "cooldown":
					kind = WorkoutStep.StepKind.COOLDOWN
				var s := WorkoutStep.ramp_percent(dur, _to_percent(float(low)), _to_percent(float(high)), kind)
				s.cadence_rpm = _cadence(attrs, element, line, result)
				out.append(s)
		"steadystate":
			var dur := _duration(attrs, "duration", element, line, result)
			var power: Variant = _number(attrs, "power", element, line, result)
			if power == null and not attrs.has("power"):
				result.add_error("у элемента %s нет атрибута Power" % element, line, 0, element, "missing_attribute")
			if dur > 0 and power != null:
				var s := WorkoutStep.percent(dur, _to_percent(float(power)), WorkoutStep.StepKind.STEADY)
				s.cadence_rpm = _cadence(attrs, element, line, result)
				out.append(s)
		"intervalst":
			var rep: Variant = _number(attrs, "repeat", element, line, result)
			repeat = roundi(float(rep)) if rep != null else 1
			if repeat <= 0:
				result.add_error("атрибут Repeat должен быть ≥ 1 (сейчас %d)" % repeat, line, 0, element, "bad_repeat")
			var on_dur := _duration(attrs, "onduration", element, line, result)
			var off_dur := _duration(attrs, "offduration", element, line, result)
			var on_pow: Variant = _number(attrs, "onpower", element, line, result)
			var off_pow: Variant = _number(attrs, "offpower", element, line, result)
			if on_pow == null and not attrs.has("onpower"):
				result.add_error("у элемента %s нет атрибута OnPower" % element, line, 0, element, "missing_attribute")
			if off_pow == null and not attrs.has("offpower"):
				result.add_error("у элемента %s нет атрибута OffPower" % element, line, 0, element, "missing_attribute")
			if repeat > 0 and on_dur > 0 and off_dur > 0 and on_pow != null and off_pow != null:
				var on := WorkoutStep.percent(on_dur, _to_percent(float(on_pow)), WorkoutStep.StepKind.INTERVAL_ON)
				on.cadence_rpm = _cadence(attrs, element, line, result)
				var off := WorkoutStep.percent(off_dur, _to_percent(float(off_pow)), WorkoutStep.StepKind.INTERVAL_OFF)
				off.cadence_rpm = _cadence(attrs, element, line, result, "cadenceresting")
				out.append(on)
				out.append(off)
		"freeride", "maxeffort":
			if lname == "maxeffort":
				result.add_warning("элемент MaxEffort трактуется как свободная езда без цели", line, 0, element, "max_effort_as_free_ride")
			var dur := _duration(attrs, "duration", element, line, result)
			if dur > 0:
				var s := WorkoutStep.free_ride(dur)
				s.cadence_rpm = _cadence(attrs, element, line, result)
				out.append(s)
	return {"steps": out, "repeat": repeat}


## Подсказка `textevent` в шаг(и) текущего элемента по смещению.
static func _attach_cue(pending: Array[WorkoutStep], attrs: Dictionary, element: String, line: int, result: ParseResult) -> void:
	if pending.is_empty():
		return  # шаг не построен (ошибка уже записана)
	var off_v: Variant = _number(attrs, "timeoffset", element, line, result)
	var offset: int = maxi(0, roundi(float(off_v))) if off_v != null else 0
	var message: String = str(attrs.get("message", "")).strip_edges()
	if message.is_empty():
		result.add_warning("подсказка textevent без текста (message) пропущена", line, 0, element, "empty_cue")
		return
	var start: int = 0
	for step in pending:
		if offset < start + step.duration_sec:
			step.text_cues.append(TextCue.make(offset - start, message))
			return
		start += step.duration_sec
	result.add_warning("подсказка на %d с выходит за длительность шага (%d с) и пропущена" % [offset, start],
			line, 0, element, "cue_out_of_step")


static func _flush_pending(steps: Array[WorkoutStep], pending: Array[WorkoutStep], repeat: int, is_intervals: bool) -> void:
	if pending.is_empty():
		return
	if is_intervals:
		steps.append_array(Workout.expand_repeat(pending, repeat))
	else:
		steps.append_array(pending)


static func _store_meta(workout: Workout, result: ParseResult, lname: String, text: String) -> void:
	match lname:
		"name":
			workout.name = text
		"description":
			workout.description = text
		"author":
			result.metadata["author"] = text
		"sporttype":
			result.metadata["sport_type"] = text
			if not BIKE_SPORT_TYPES.has(text.to_lower()):
				result.add_warning("sportType '%s': тренировка не велосипедная" % text, 0, 0, "sportType", "not_bike")
		_:
			if not text.is_empty():
				result.metadata[lname] = text
