extends SceneTree
## Пересборка шрифта, начертаний Inter (`src/ui/theme/fonts/*.tres`) и темы `app_theme.tres`
## по `AppThemeBuilder` и `UiTokens`:
## `godot --headless --path . -s res://src/ui/theme/tools/generate_theme.gd`.


func _initialize() -> void:
	var failed := not _save(AppThemeBuilder.make_font_file(), AppThemeBuilder.INTER_PATH, ResourceSaver.FLAG_COMPRESS)
	var base: FontFile = load(AppThemeBuilder.INTER_PATH)
	for name: String in AppThemeBuilder.FONT_SPECS:
		failed = not _save(AppThemeBuilder.make_font(name, base), AppThemeBuilder.FONT_DIR + name + ".tres") or failed
	var theme := AppThemeBuilder.build(AppThemeBuilder.load_fonts())
	failed = not _save(theme, AppThemeBuilder.THEME_PATH) or failed
	print("generate_theme: ", "FAILED" if failed else "ok")
	quit(1 if failed else 0)


func _save(res: Resource, path: String, flags: int = 0) -> bool:
	if ResourceLoader.exists(path):
		res.take_over_path(path)
	return ResourceSaver.save(res, path, flags) == OK
