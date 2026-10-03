class_name ZoneBar
extends Control
## Мини-полоса «время в зонах» (REQ-LOC-04 крит. 5): сегменты пропорциональны
## секундам в зоне, цвета — `ZonePalette` по токенам зон мощности или пульса; подложка —
## `inset` (`docs/game/ui.md` п. 4). В карточке заезда — полоса 12 lp с подписями долей,
## в строке истории — 4 lp во всю ширину строки (`ui.md` п. 8.5).

const BACKGROUND := UiTokens.INSET

var _times := PackedInt32Array()
var _tokens: Array[String] = []
var _total: int = 0


## `times[i]` — секунд в зоне i+1; `tokens[i]` — токен зоны для цвета.
func set_zones(times: PackedInt32Array, tokens: Array[String]) -> void:
	_times = times
	_tokens = tokens
	_total = 0
	for t in times:
		_total += maxi(t, 0)
	queue_redraw()


func total_sec() -> int:
	return _total


func zone_count() -> int:
	return _times.size()


## Доли зон с временем: `[{zone, token, sec, pct}]` по порядку зон (подписи «Z2 35 %»).
func shares() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if _total <= 0:
		return out
	for i in _times.size():
		var sec: int = maxi(_times[i], 0)
		if sec <= 0:
			continue
		out.append({
			"zone": i + 1, "token": _tokens[i] if i < _tokens.size() else "", "sec": sec,
			"pct": roundi(float(sec) * 100.0 / float(_total)),
		})
	return out


func _draw() -> void:
	var w: float = size.x
	var h: float = size.y
	if w <= 0.0 or h <= 0.0:
		return
	draw_rect(Rect2(0, 0, w, h), BACKGROUND)
	if _total <= 0:
		return
	var x: float = 0.0
	for i in _times.size():
		var sw: float = float(maxi(_times[i], 0)) / float(_total) * w
		if sw <= 0.0:
			continue
		var token: String = _tokens[i] if i < _tokens.size() else ""
		draw_rect(Rect2(x, 0, sw, h), ZonePalette.color(token))
		x += sw
