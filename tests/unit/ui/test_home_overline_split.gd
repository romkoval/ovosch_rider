extends GutTest
## T-103 (`ui.md` п. 8.2, решение ред. 2; REQ-UIX-05 крит. 3): надзаголовок карточки главного
## рядом с текстовой кнопкой на узком телефоне делится на две строки по фактическому зазору до
## кнопки; короткое слово (≤ 2 букв) не остаётся последним в строке; на месте переноса « · » не
## рисуется. Ожидаемо для плана на телефоне 1280×590 с вырезом (ru): «ПО ПЛАНУ» / «ERG» (кадр
## `screen_home_1280x590_ru_safe_phone`).



func _overline_label() -> Label:
	var l := Label.new()
	l.theme_type_variation = &"OverlineAccent"
	l.uppercase = true
	add_child_autofree(l)
	return l


func _width(l: Label, text: String) -> float:
	return l.get_theme_font("font").get_string_size(text.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1,
			l.get_theme_font_size("font_size")).x


func test_split_rules_short_word_and_separator() -> void:
	var l := _overline_label()
	var text := "по плану · ERG"
	var gap := _width(l, "по плану") + 4.0
	assert_eq(HomeScreen.split_to_fit(l, text, gap), "по плану\nERG", "перенос на « · »: разделитель не рисуется")
	assert_eq(HomeScreen.split_to_fit(l, text, _width(l, text) + 1.0), text, "помещается — как есть")
	var narrow := _width(l, "плану · ERG") + 1.0
	var two := HomeScreen.split_to_fit(l, "в плане сегодня", _width(l, "плане сегодня") + 1.0)
	assert_eq(two, "в плане\nсегодня", "«в» не остаётся последним словом строки")
	assert_false(HomeScreen.split_to_fit(l, text, narrow).begins_with("по\n"), "«ПО» одно в строке не остаётся")
	assert_eq(HomeScreen.split_to_fit(l, "свободная езда · SIM", _width(l, "свободная") + 1.0),
			"свободная\nезда · SIM", "езда: правилам не противоречит")
