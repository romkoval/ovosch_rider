extends GutTest
## Приёмка T-094 (tester), инструмент снимков UI для `[визуальная проверка]` REQ-HUD-10 крит. 8 и
## REQ-HUD-11 крит. 8: кадр сохраняется только ровно запрошенного размера `WxH` (на macOS с Retina
## был кадр 2704×1522 под именем 1280×720). Сам снимок с окном в контейнере не снимается —
## проверяются разбор разрешения и порядок «проверка размера → сохранение → проверка файла»
## в `scripts/dev/ui_screenshot.gd`; реальный прогон на Retina — в ручных проверках.

const SHOT_SCRIPT: String = "res://scripts/dev/ui_screenshot.gd"


func test_req_hud_10_c8_ui_screenshot_parses_requested_frame_size() -> void:
	var script: GDScript = load(SHOT_SCRIPT)
	assert_not_null(script)
	assert_eq(script.parse_resolution("1280x720"), Vector2i(1280, 720))
	assert_eq(script.parse_resolution("1024x768"), Vector2i(1024, 768))
	assert_eq(script.parse_resolution("2556x1179"), Vector2i(2556, 1179))
	for bad in ["", "1280", "1280x", "x720", "1280×720", "1280x720x2", "-1280x720", "0x720", "abcxdef", "1280 x 720"]:
		assert_eq(script.parse_resolution(bad), Vector2i.ZERO, "«%s» — не разрешение" % bad)


func test_req_hud_10_c8_ui_screenshot_checks_size_before_saving_and_rechecks_saved_file() -> void:
	var code := FileAccess.get_file_as_string(SHOT_SCRIPT)
	var shoot_at: int = code.find("func _shoot(")
	assert_gt(shoot_at, 0, "есть _shoot")
	var body: String = code.substr(shoot_at, code.find("\nfunc ", shoot_at + 10) - shoot_at)
	var check_at: int = body.find("image.get_size() != _requested_size")
	var save_at: int = body.find("save_png(")
	var reload_at: int = body.find("Image.load_from_file(")
	assert_gt(check_at, 0, "размер кадра сверяется с запрошенным")
	assert_gt(save_at, check_at, "сверка — до сохранения")
	assert_gt(reload_at, save_at, "сохранённый файл перечитывается и сверяется")
	var fail_before_save: int = body.find("_fail(", check_at)
	assert_between(fail_before_save, check_at, save_at, "при несовпадении — ошибка и выход до save_png")
	var fail_body: String = code.substr(code.find("func _fail("), 200)
	assert_true(fail_body.contains("_failures += 1"), "_fail считает ошибки")
	assert_true(code.contains("quit(0 if _failures == 0 else 1)"), "любая ошибка — код выхода 1")
