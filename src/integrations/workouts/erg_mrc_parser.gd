class_name ErgMrcParser
extends RefCounted
## Парсер файлов .erg (ватты) и .mrc (% FTP) формата CompuTrainer/TrainerRoad
## (REQ-IMP-02, REQ-IMP-05).
##
## Секции (регистр не важен, CRLF и LF):
## - `[COURSE HEADER]`…`[END COURSE HEADER]`: `VERSION`, `UNITS`, `DESCRIPTION`,
##   `FILE NAME`, `FTP` → `ParseResult.metadata` (FTP не меняет профиль — крит. 4);
##   строка колонок `MINUTES WATTS` / `MINUTES PERCENT` — подсказка единиц;
## - `[COURSE DATA]`…`[END COURSE DATA]`: пары «минуты значение». Соседние точки с
##   одинаковым временем — скачок (шаг не создаётся); с разным временем и равным
##   значением — постоянный шаг, с разным значением — рампа (крит. 1).
##   Дробные минуты: 2.5 → 150 с (крит. 6);
## - `[COURSE TEXT]`…`[END COURSE TEXT]`: `секунды<TAB>текст<TAB>длительность` →
##   `TextCue` шага, в который попадает секунда (крит. 3; длительность показа игнорируется).
##
## `kind`: "erg" — ватты, "mrc" — % FTP; определяется расширением файла и имеет
## приоритет над заголовком (крит. 2; расхождение — предупреждение). `kind` "" или
## "auto" — по заголовку (`MINUTES PERCENT` → mrc, иначе erg).
##
## Десятичная запятая принимается с предупреждением. Ошибки — с номером строки:
## нет `[COURSE DATA]`, меньше двух точек, немонотонное время, нечисловое значение.

const KIND_ERG: String = "erg"
const KIND_MRC: String = "mrc"
const KIND_AUTO: String = "auto"


static func parse(text: String, kind: String = KIND_AUTO) -> ParseResult:
	var result := ParseResult.new()
	var wanted_kind := kind.strip_edges().to_lower()
	if wanted_kind.is_empty():
		wanted_kind = KIND_AUTO
	if not [KIND_ERG, KIND_MRC, KIND_AUTO].has(wanted_kind):
		result.add_error("неизвестный тип файла '%s' (ожидается erg или mrc)" % kind, 0, 0, "", "unknown_kind")
		return result
	if text.strip_edges().is_empty():
		result.add_error("файл пуст", 0, 0, "", "empty_file")
		return result

	var lines: PackedStringArray = text.replace("\r\n", "\n").replace("\r", "\n").split("\n")
	var section := ""
	var saw_data := false
	var header_units := ""  # "watts" | "percent" | ""
	var points: Array[Dictionary] = []  # {line, minutes, value}
	var cues: Array[Dictionary] = []  # {line, sec, text}
	var comma_warned := false
	var line_no: int = 0

	for raw_line in lines:
		line_no += 1
		var line: String = raw_line.strip_edges()
		if line.is_empty():
			continue
		if line.begins_with("[") and line.ends_with("]"):
			var tag := line.substr(1, line.length() - 2).strip_edges().to_upper().replace("  ", " ")
			match tag:
				"COURSE HEADER":
					section = "header"
				"COURSE DATA":
					section = "data"
					saw_data = true
				"COURSE TEXT":
					section = "text"
				"END COURSE HEADER", "END COURSE DATA", "END COURSE TEXT":
					section = ""
				_:
					result.add_warning("неизвестная секция [%s] пропущена" % tag, line_no, 0, tag, "unknown_section")
					section = "skip"
			continue
		match section:
			"header":
				var upper := line.to_upper()
				if upper.begins_with("MINUTES"):
					if upper.contains("PERCENT"):
						header_units = "percent"
					elif upper.contains("WATTS"):
						header_units = "watts"
					continue
				var eq := line.find("=")
				if eq == -1:
					result.add_warning("строка заголовка без '=' пропущена: '%s'" % line, line_no, 0, "", "bad_header_line")
					continue
				var key := line.substr(0, eq).strip_edges().to_upper()
				var value := line.substr(eq + 1).strip_edges()
				match key:
					"DESCRIPTION":
						result.metadata["description"] = value
					"FILE NAME", "FILENAME":
						result.metadata["file_name"] = value
					"FTP":
						var ftp_raw := value.replace(",", ".")
						if ftp_raw.is_valid_float():
							result.metadata["ftp"] = roundi(ftp_raw.to_float())
						else:
							result.add_warning("FTP в заголовке не число: '%s'" % value, line_no, 0, "FTP", "bad_ftp")
					_:
						result.metadata[key.to_lower().replace(" ", "_")] = value
			"data":
				var tokens := _split_tokens(line)
				if tokens.size() < 2:
					result.add_error("ожидались два числа «минуты значение», получено '%s'" % line, line_no, 0, "", "bad_data_line")
					continue
				var m_raw := tokens[0]
				var v_raw := tokens[1]
				if m_raw.contains(",") or v_raw.contains(","):
					if not comma_warned:
						result.add_warning("десятичная запятая заменена на точку", line_no, 0, "", "decimal_comma")
						comma_warned = true
					m_raw = m_raw.replace(",", ".")
					v_raw = v_raw.replace(",", ".")
				if not m_raw.is_valid_float() or not v_raw.is_valid_float():
					result.add_error("нечисловое значение в данных: '%s'" % line, line_no, 0, "", "bad_number")
					continue
				points.append({"line": line_no, "minutes": m_raw.to_float(), "value": v_raw.to_float()})
			"text":
				var cue := _parse_text_line(line)
				if cue.is_empty():
					result.add_warning("строка подсказки не распознана и пропущена: '%s'" % line, line_no, 0, "", "bad_text_line")
				else:
					cue["line"] = line_no
					cues.append(cue)
			_:
				pass

	if not saw_data:
		result.add_error("нет секции [COURSE DATA]", 0, 0, "COURSE DATA", "no_course_data")
		return result
	if not result.errors.is_empty():
		return result
	if points.size() < 2:
		result.add_error("в [COURSE DATA] меньше двух точек (%d)" % points.size(), 0, 0, "COURSE DATA", "too_few_points")
		return result

	# Единицы: расширение главнее заголовка.
	var resolved_kind := wanted_kind
	if resolved_kind == KIND_AUTO:
		resolved_kind = KIND_MRC if header_units == "percent" else KIND_ERG
	elif header_units == "percent" and resolved_kind == KIND_ERG:
		result.add_warning("заголовок указывает PERCENT, но файл .erg — значения трактуются как ватты", 0, 0, "MINUTES", "units_mismatch")
	elif header_units == "watts" and resolved_kind == KIND_MRC:
		result.add_warning("заголовок указывает WATTS, но файл .mrc — значения трактуются как % FTP", 0, 0, "MINUTES", "units_mismatch")
	var use_watts := resolved_kind == KIND_ERG

	var steps: Array[WorkoutStep] = []
	for i in range(1, points.size()):
		var a: Dictionary = points[i - 1]
		var b: Dictionary = points[i]
		var t0: float = a["minutes"]
		var t1: float = b["minutes"]
		if t1 < t0 - 1e-9:
			result.add_error("время должно не убывать: %s мин после %s мин" % [_fmt(t1), _fmt(t0)], int(b["line"]), 0, "", "non_monotonic_time")
			return result
		var dur := roundi((t1 - t0) * 60.0)
		if dur <= 0:
			continue  # скачок значения в тот же момент времени
		var v0: float = a["value"]
		var v1: float = b["value"]
		if v0 < 0.0 or v1 < 0.0:
			result.add_error("отрицательная целевая мощность", int(b["line"]), 0, "", "negative_target")
			return result
		var step: WorkoutStep
		if is_equal_approx(v0, v1):
			step = WorkoutStep.watts(dur, v0) if use_watts else WorkoutStep.percent(dur, v0)
		else:
			step = WorkoutStep.ramp_watts(dur, v0, v1) if use_watts else WorkoutStep.ramp_percent(dur, v0, v1)
		steps.append(step)
	if steps.is_empty():
		result.add_error("точки [COURSE DATA] не образуют ни одного шага ненулевой длительности", 0, 0, "COURSE DATA", "no_steps")
		return result

	var workout := Workout.new()
	workout.source = resolved_kind
	workout.steps = steps
	workout.description = str(result.metadata.get("description", ""))
	var file_name := str(result.metadata.get("file_name", ""))
	workout.name = file_name.get_file().get_basename() if not file_name.is_empty() else workout.description

	for cue in cues:
		var sec: int = int(cue["sec"])
		var idx := workout.step_index_at(float(sec))
		if idx < 0:
			result.add_warning("подсказка на %d с выходит за длительность тренировки (%d с) и пропущена" % [sec, workout.total_duration_sec()],
					int(cue["line"]), 0, "", "cue_out_of_workout")
			continue
		workout.steps[idx].text_cues.append(TextCue.make(sec - workout.step_start_sec(idx), str(cue["text"])))

	for e in workout.validate():
		result.add_error(e, 0, 0, "", "invalid_workout")
	result.set_workout(workout)
	return result


## Разбить строку по пробелам/табуляциям, отбросив пустые токены.
static func _split_tokens(line: String) -> PackedStringArray:
	var out := PackedStringArray()
	for t in line.replace("\t", " ").split(" ", false):
		out.append(t)
	return out


## Строка `[COURSE TEXT]`: `секунды<TAB>текст<TAB>длительность`. Пусто — не распознана.
## Допускается разделение пробелами: первый токен — секунды, последний (если число) —
## длительность показа, остальное — текст.
static func _parse_text_line(line: String) -> Dictionary:
	var parts: PackedStringArray = line.split("\t", false)
	var sec_raw := ""
	var text := ""
	if parts.size() >= 2:
		sec_raw = parts[0].strip_edges()
		text = parts[1].strip_edges()
	else:
		var tokens := _split_tokens(line)
		if tokens.size() < 2:
			return {}
		sec_raw = tokens[0]
		var last := tokens.size()
		if tokens.size() >= 3 and tokens[last - 1].is_valid_int():
			last -= 1
		text = " ".join(tokens.slice(1, last))
	sec_raw = sec_raw.replace(",", ".")
	if not sec_raw.is_valid_float() or text.is_empty():
		return {}
	return {"sec": roundi(sec_raw.to_float()), "text": text}


static func _fmt(v: float) -> String:
	return str(snappedf(v, 0.001))
