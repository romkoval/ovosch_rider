extends GutTest
## Сцены экспортируются целиком (REQ-DEV-01: кнопка «Искать» на экране устройств, T-147).
## Узел, добавленный внутрь вложенной сцены (`parent="Root/AppBar/Row/Actions"`, где `Root/AppBar` —
## `instance=`), сохраняется в release-сборке только при строке `[editable path="Root/AppBar"]`.
## Редактор и GUT такую сцену загружают и без неё, а экспорт узлы теряет: `%ScanButton` = null,
## и release-сборка падает при запуске (GDScript в release не проверяет вызов у null).

const SRC: String = "res://src"


static func _scenes(dir_path: String, out: Array[String]) -> void:
	var d := DirAccess.open(dir_path)
	if d == null:
		return
	for f in d.get_files():
		if f.ends_with(".tscn"):
			out.append(dir_path.path_join(f))
	for sub in d.get_directories():
		_scenes(dir_path.path_join(sub), out)


## Путь узла от корня сцены («.» — корень).
static func _node_path(name: String, parent: String) -> String:
	if parent == "":
		return "."
	return name if parent == "." else parent + "/" + name


## Узлы внутри вложенных сцен без `[editable]`: «файл: родитель → вложенная сцена».
static func missing_editable(text: String) -> Array[String]:
	var node_re := RegEx.create_from_string(r'^\[node name="([^"]+)"(?:[^\]]*?parent="([^"]*)")?([^\]]*)\]')
	var editable_re := RegEx.create_from_string(r'^\[editable path="([^"]+)"\]')
	var instanced: Array[String] = []
	var editable: Array[String] = []
	var parents: Array[String] = []
	for line in text.split("\n"):
		var m := node_re.search(line)
		if m != null:
			var parent := m.get_string(2)
			if line.contains("instance="):
				instanced.append(_node_path(m.get_string(1), parent))
			if parent != "" and parent != ".":
				parents.append(parent)
			continue
		var e := editable_re.search(line)
		if e != null:
			editable.append(e.get_string(1))
	var out: Array[String] = []
	for parent in parents:
		for inst in instanced:
			if parent.begins_with(inst + "/") and not editable.has(inst):
				out.append("%s → %s" % [parent, inst])
	return out


func test_nodes_inside_instanced_scenes_are_marked_editable() -> void:
	var files: Array[String] = []
	_scenes(SRC, files)
	assert_gt(files.size(), 10, "сцены найдены")
	var bad: Array[String] = []
	for path in files:
		for item in missing_editable(FileAccess.get_file_as_string(path)):
			bad.append("%s: %s" % [path, item])
	assert_eq(bad, [] as Array[String], "узел внутри вложенной сцены без [editable path=…] — в release-сборке его не будет")


func test_detector_catches_missing_editable() -> void:
	var text := "\n".join([
		'[node name="S" type="Control"]',
		'[node name="Bar" parent="." instance=ExtResource("1")]',
		'[node name="Btn" type="Button" parent="Bar/Row"]',
	])
	assert_eq(missing_editable(text).size(), 1)
	assert_eq(missing_editable(text + '\n[editable path="Bar"]').size(), 0)
