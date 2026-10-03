class_name TimeAxis
extends RefCounted
## Шкала времени нижнего графика HUD (REQ-HUD-10 крит. 4, REQ-FRD-06 крит. 4; `docs/game/hud.md` п. 7, 8).
##
## Чистые функции, без узлов. Подпись — словарь
## `{sec: int, fraction: float, text: String, is_now: bool}`:
## - `sec` — момент подписи в секундах той же шкалы, что и точки графика;
## - `fraction` — положение по X в долях ширины поля (0 — левый край, 1 — правый);
## - `text` — готовая подпись: минуты до часа (`0`, `5`, `45`), от часа — `ч:мм` (`1:00`, `1:30`);
##   в скользящем окне подписи относительные со знаком минус U+2212 (`−30`, `−5`);
## - `is_now` — подпись «сейчас» у правого края скользящего окна; текста у неё нет
##   (`text == ""`), перевод подставляет view через `tr()`.
##
## Шаг подписей — наименьший из ряда 1, 2, 5, 10, 15, 30, 60 мин, при котором подписей
## (включая 0) не больше `MAX_LABELS`; если не хватает и 60 мин — кратное 60 мин.
## План 60 мин → шаг 10 мин (0, 10, …, 1:00); план 20 мин → шаг 5 мин.

## Ряд шагов подписей, мин.
const STEP_SERIES_MIN: Array[int] = [1, 2, 5, 10, 15, 30, 60]
## Не больше стольких подписей, включая 0.
const MAX_LABELS: int = 10
## Знак минус для относительных подписей окна (U+2212, как в FRD-06 крит. 1).
const MINUS: String = "−"


## Шаг подписей в минутах для шкалы длиной `span_sec`.
static func step_minutes(span_sec: int, max_labels: int = MAX_LABELS) -> int:
	var limit: int = maxi(max_labels, 2)
	var span: int = maxi(span_sec, 0)
	for step in STEP_SERIES_MIN:
		if label_count(span, step) <= limit:
			return step
	var k: int = 2
	while label_count(span, 60 * k) > limit:
		k += 1
	return 60 * k


## Число подписей (включая 0) при шаге `step_min` на шкале `span_sec`.
static func label_count(span_sec: int, step_min: int) -> int:
	if step_min <= 0:
		return 0
	return maxi(span_sec, 0) / (step_min * 60) + 1


## Подписи шкалы «весь план целиком» (HUD-10.4): 0, шаг, 2·шаг, … ≤ `span_sec`.
## `fraction = sec / span_sec`; при `span_sec <= 0` — одна подпись «0» у левого края.
static func labels(span_sec: int, max_labels: int = MAX_LABELS) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var span: int = maxi(span_sec, 0)
	var step_sec: int = step_minutes(span, max_labels) * 60
	var sec: int = 0
	while sec <= span:
		var fraction: float = float(sec) / float(span) if span > 0 else 0.0
		out.append(_label(sec, fraction, format_minutes(sec), false))
		sec += step_sec
	return out


## Подписи графика «история усилия» свободной езды (FRD-06 крит. 4, `hud.md` п. 8).
## Пока `elapsed_sec <= window_sec` — шкала 0…окно с абсолютными подписями, как `labels(window_sec)`.
## Дальше окно скользит: подписи относительные `−30 … −5` и «сейчас» у правого края
## (`is_now`), стоят на месте, а линия под ними сдвигается. `sec` — абсолютное время подписи.
static func window_labels(elapsed_sec: int, window_sec: int, max_labels: int = MAX_LABELS) -> Array[Dictionary]:
	var window: int = maxi(window_sec, 1)
	if elapsed_sec <= window:
		return labels(window, max_labels)
	var out: Array[Dictionary] = []
	var step_sec: int = step_minutes(window, max_labels) * 60
	var back: int = (window / step_sec) * step_sec
	while back >= 0:
		var fraction: float = float(window - back) / float(window)
		var is_now: bool = back == 0
		var text: String = "" if is_now else MINUS + format_minutes(back)
		out.append(_label(elapsed_sec - back, fraction, text, is_now))
		back -= step_sec
	return out


## Подпись времени: минуты до часа (`0`, `5`, `59`), от часа — `ч:мм` (`1:00`, `2:15`).
## Секунды отбрасываются (подписи всегда кратны минуте). Отрицательное — со знаком U+2212.
static func format_minutes(sec: int) -> String:
	if sec < 0:
		return MINUS + format_minutes(-sec)
	var minutes: int = sec / 60
	if minutes < 60:
		return "%d" % minutes
	return "%d:%02d" % [minutes / 60, minutes % 60]


static func _label(sec: int, fraction: float, text: String, is_now: bool) -> Dictionary:
	return {"sec": sec, "fraction": fraction, "text": text, "is_now": is_now}
