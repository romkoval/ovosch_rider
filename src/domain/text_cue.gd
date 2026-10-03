class_name TextCue
extends RefCounted
## Текстовая подсказка внутри шага тренировки (REQ-INT-03): показывается
## на `at_sec`-й секунде от начала шага.

## Смещение от начала шага, с.
var at_sec: int = 0
## Текст подсказки.
var text: String = ""


static func make(at: int, cue_text: String) -> TextCue:
	var c := TextCue.new()
	c.at_sec = at
	c.text = cue_text
	return c


func duplicate_cue() -> TextCue:
	return TextCue.make(at_sec, text)


## Сериализация: `{at_sec, text}`.
func to_dict() -> Dictionary:
	return {"at_sec": at_sec, "text": text}


## Восстановление из словаря; null, если нет поля `text`.
static func from_dict(data: Dictionary) -> TextCue:
	if not data.has("text"):
		return null
	return TextCue.make(int(data.get("at_sec", 0)), str(data["text"]))


func _to_string() -> String:
	return "TextCue(%d s: %s)" % [at_sec, text]
