extends GutTest
## Тесты палитры зон (REQ-HUD-03 крит. 2, REQ-HUD-04 крит. 2, REQ-INT-05 крит. 3).


func test_seven_power_tokens_with_required_colors() -> void:
	assert_eq(ZonePalette.POWER_TOKENS.size(), 7)
	var expected := ["gray", "blue", "green", "yellow", "orange", "red", "purple"]
	for z in range(1, 8):
		var token := ZonePalette.power_token(z)
		assert_eq(token, "z%d" % z)
		assert_eq(ZonePalette.color_name(token), expected[z - 1], "REQ-HUD-03 крит. 2: Z%d" % z)
		assert_true(ZonePalette.is_valid_token(token))


func test_five_hr_tokens() -> void:
	assert_eq(ZonePalette.HR_TOKENS.size(), 5)
	for z in range(1, 6):
		assert_eq(ZonePalette.hr_token(z), "hr%d" % z)
		assert_false(ZonePalette.color_name(ZonePalette.hr_token(z)).is_empty())


func test_zero_or_out_of_range_zone_gives_no_token() -> void:
	assert_eq(ZonePalette.power_token(0), "")
	assert_eq(ZonePalette.power_token(8), "")
	assert_eq(ZonePalette.power_token(-1), "")
	assert_eq(ZonePalette.hr_token(0), "")
	assert_eq(ZonePalette.hr_token(6), "")
	assert_false(ZonePalette.is_valid_token(""))


func test_colors_are_distinct_for_power_zones() -> void:
	var seen := {}
	for token in ZonePalette.POWER_TOKENS:
		var c := ZonePalette.color(token)
		assert_false(seen.has(c.to_html()), "цвет %s уникален" % token)
		seen[c.to_html()] = true
		assert_ne(c, ZonePalette.NO_ZONE_COLOR)


func test_unknown_token_gives_neutral_color() -> void:
	assert_eq(ZonePalette.color(""), ZonePalette.NO_ZONE_COLOR)
	assert_eq(ZonePalette.color("z99"), ZonePalette.NO_ZONE_COLOR)
	assert_eq(ZonePalette.color_name("nope"), "")


func test_color_lookup_matches_name_table() -> void:
	assert_eq(ZonePalette.color("z6"), ZonePalette.COLORS["red"])
	assert_eq(ZonePalette.color("hr1"), ZonePalette.COLORS["gray"])
