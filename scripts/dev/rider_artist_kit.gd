extends SceneTree
## Сборка эталонного пакета `assets/rider/reference/` (T-106a1): пишет файлы, которые строит
## `scripts/dev/rider_reference_pack.gd` (`bike_reference.glb`, `rider_rig_reference.glb`,
## атласы регионов), из кода проекта, воспроизводимо побайтно.
## Запуск: ./scripts/rider_artist_kit.sh [каталог=assets/rider/reference]

const DEFAULT_OUT: String = "res://assets/rider/reference"
const Pack := preload("res://scripts/dev/rider_reference_pack.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else DEFAULT_OUT
	var dir: String = ProjectSettings.globalize_path(out)
	DirAccess.make_dir_recursive_absolute(dir)
	var files: Dictionary = Pack.new().build()
	var errors: Array[String] = []
	for name in Pack.FILES:
		var data: PackedByteArray = files[name]
		var err: Error = ERR_CANT_CREATE if data.is_empty() else _write(dir.path_join(name), data)
		print("rider_artist_kit: %s — %s (%d байт)" % [name, error_string(err), data.size()])
		if err != OK:
			errors.append(name)
	if not errors.is_empty():
		push_error("rider_artist_kit: %s" % ", ".join(errors))
		quit(1)
		return
	print("rider_artist_kit: %s" % dir)
	quit(0)


func _write(path: String, data: PackedByteArray) -> Error:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_buffer(data)
	f.close()
	return OK
