extends GutTest
## Приёмка T-108 (tester): REQ-AVT-01 п.1, 3, 5 — сверка `RiderLook` со спекой напрямую по
## тексту `docs/game/art-bible.md` («Гонщик» ред. 4, «Слоты внешности»): таблица слотов
## (имена, типы, допустимые значения, умолчания), палитра формы, кожа, волосы, линзы, узоры
## джерси и таблица пресетов (6 столбцов, «—» — по умолчанию), названия пресетов из заголовка
## таблицы против `strings_menu.csv`. Таблицы читаются из документа, значения в тест не
## переписаны — расхождение кода и спеки в любую сторону даёт падение.
## Плюс п.3 по каждому слоту на неумолчательной внешности: неверный тип, цвет не в формате
## спеки, неизвестное значение — сбрасывается только этот слот; п.1 — `rider_look` не словарь.

const SPEC: String = "res://docs/game/art-bible.md"
const MENU_CSV: String = "res://assets/i18n/strings_menu.csv"

var _spec: PackedStringArray
var _dir: String


func before_all() -> void:
	_spec = FileAccess.get_file_as_string(SPEC).split("\n")


func before_each() -> void:
	_dir = "user://test_t108_accept_%d_%d/" % [Time.get_ticks_usec(), randi() % 1000000]


func after_each() -> void:
	var abs_path := ProjectSettings.globalize_path(_dir)
	if DirAccess.dir_exists_absolute(abs_path):
		for f in DirAccess.get_files_at(abs_path):
			DirAccess.remove_absolute(abs_path.path_join(f))
		DirAccess.remove_absolute(abs_path)


# ---------------------------------------------------------------------------
# Разбор спеки
# ---------------------------------------------------------------------------

## Строки таблицы после строки, содержащей `marker` (первая таблица после маркера).
func _table_after(marker: String) -> Array[PackedStringArray]:
	var rows: Array[PackedStringArray] = []
	var start := -1
	for i in _spec.size():
		if _spec[i].contains(marker):
			start = i
			break
	assert_true(start >= 0, "в спеке есть «%s»" % marker)
	if start < 0:
		return rows
	var in_table := false
	for i in range(start + 1, _spec.size()):
		var line := _spec[i].strip_edges()
		if line.begins_with("|"):
			in_table = true
			var cells := PackedStringArray()
			var parts := line.split("|")
			for j in range(1, parts.size() - 1):
				cells.append(parts[j].strip_edges())
			rows.append(cells)
		elif in_table:
			break
	return rows


## Ключи в обратных кавычках.
static func _ticks(cell: String) -> PackedStringArray:
	var out := PackedStringArray()
	var re := RegEx.new()
	re.compile("`([^`]+)`")
	for m in re.search_all(cell):
		out.append(m.get_string(1))
	return out


static func _color(cell: String) -> Color:
	var re := RegEx.new()
	re.compile("\\(([0-9.]+),\\s*([0-9.]+),\\s*([0-9.]+)\\)")
	var m := re.search(cell)
	if m == null:
		return Color(-1, -1, -1)
	return Color(float(m.get_string(1)), float(m.get_string(2)), float(m.get_string(3)))


## Таблица слотов спеки: слот → {type, allowed: Array (пусто — любой цвет формы), default}.
func _spec_slots() -> Dictionary:
	var out := {}
	var rows := _table_after("**Таблица слотов**")
	for r: PackedStringArray in rows.slice(2):
		var slot := _ticks(r[0])
		if slot.is_empty():
			continue
		var allowed: Array = Array(_ticks(r[2])) if r[1] == "перечисление" else []
		# Диапазон «`s1`…`s6`» — все значения между.
		if r[2].contains("…") and allowed.size() == 2:
			var re := RegEx.new()
			re.compile("^([a-z_]*)(\\d+)$")
			var a := re.search(str(allowed[0]))
			var b := re.search(str(allowed[1]))
			if a != null and b != null and a.get_string(1) == b.get_string(1):
				allowed = []
				for n in range(int(a.get_string(2)), int(b.get_string(2)) + 1):
					allowed.append("%s%d" % [a.get_string(1), n])
		out[slot[0]] = {"type": r[1], "allowed": allowed, "default": _ticks(r[3])[0]}
	return out


## Палитра формы спеки: ключ → цвет.
func _spec_palette() -> Dictionary:
	var out := {}
	for r: PackedStringArray in _table_after("**Палитра формы**").slice(2):
		for c in [0, 2]:
			var key := _ticks(r[c])
			if not key.is_empty():
				out[key[0]] = _color(r[c + 1])
	return out


func _spec_two_col(marker: String) -> Dictionary:
	var out := {}
	for r: PackedStringArray in _table_after(marker).slice(2):
		var key := _ticks(r[0])
		if not key.is_empty():
			out[key[0]] = _color(r[1])
	return out


## Пресеты спеки: [ids, names: id → [ru, en], values: id → {slot → значение или ""}].
func _spec_presets() -> Array:
	var rows := _table_after("**Пресеты**")
	var header := rows[0]
	var ids: Array[String] = []
	var names := {}
	var re_ru := RegEx.new()
	re_ru.compile("«([^»]+)»")
	var re_en := RegEx.new()
	re_en.compile("\"([^\"]+)\"")
	for c in range(1, header.size()):
		var id := _ticks(header[c])[0]
		ids.append(id)
		names[id] = [re_ru.search(header[c]).get_string(1), re_en.search(header[c]).get_string(1)]
	var values := {}
	for id in ids:
		values[id] = {}
	for r: PackedStringArray in rows.slice(2):
		var slot_parts := r[0].split("/")
		var slots: Array[String] = []
		var group := ""
		for part in slot_parts:
			var name := _ticks(part)[0]
			if name.contains("."):
				group = name.get_slice(".", 0)
				slots.append(name)
			else:
				slots.append(group + "." + name)
		for c in range(1, r.size()):
			var vals := r[c].split("/")
			for k in slots.size():
				var cell := vals[k].strip_edges() if k < vals.size() else "—"
				var t := _ticks(cell)
				(values[ids[c - 1]] as Dictionary)[slots[k]] = t[0] if not t.is_empty() else ""
	return [ids, names, values]


# ---------------------------------------------------------------------------
# п.5 — слоты, палитры, пресеты против спеки
# ---------------------------------------------------------------------------

func test_slot_table_matches_spec_exactly() -> void:
	var spec := _spec_slots()
	assert_eq(spec.size(), 28, "в спеке 28 слотов")
	var code: Array = Array(RiderLook.SLOTS).duplicate()
	var spec_keys: Array = spec.keys()
	code.sort()
	spec_keys.sort()
	assert_eq(code, spec_keys, "набор слотов: ни лишнего, ни недостающего")
	for slot: String in spec:
		var s: Dictionary = spec[slot]
		assert_eq(RiderLook.default_value(slot), s["default"], "%s: значение по умолчанию" % slot)
		var allowed: Array = Array(RiderLook.allowed_values(slot))
		if s["type"] == "перечисление":
			assert_true(RiderLook.ENUMS.has(slot), "%s — перечисление" % slot)
			var expected: Array = s["allowed"]
			allowed.sort()
			expected.sort()
			assert_eq(allowed, expected, "%s: допустимые значения" % slot)
		else:
			assert_eq(s["type"], "цвет формы", "%s: тип по спеке" % slot)
			assert_true(RiderLook.is_color_slot(slot), "%s — цвет формы" % slot)
			var palette: Array = _spec_palette().keys()
			allowed.sort()
			palette.sort()
			assert_eq(allowed, palette, "%s: любой ключ палитры формы" % slot)


func test_palettes_match_spec_values() -> void:
	var palette := _spec_palette()
	assert_eq(palette.size(), 16, "палитра формы — 16 ключей")
	assert_eq(RiderLook.FORM_COLORS.size(), 16)
	for key: String in palette:
		assert_true(RiderLook.FORM_COLORS.has(key), "ключ %s" % key)
		assert_true((RiderLook.FORM_COLORS.get(key, Color.BLACK) as Color).is_equal_approx(palette[key]), "цвет %s" % key)
	var skin := _spec_two_col("**Кожа**")
	assert_eq(skin.size(), RiderLook.SKIN_TONES.size(), "тонов кожи")
	for key: String in skin:
		assert_true((RiderLook.SKIN_TONES.get(key, Color.BLACK) as Color).is_equal_approx(skin[key]), "кожа %s" % key)
	var hair := _spec_two_col("**Волосы**")
	assert_eq(hair.size(), RiderLook.HAIR_COLORS.size(), "цветов волос")
	for key: String in hair:
		assert_true((RiderLook.HAIR_COLORS.get(key, Color.BLACK) as Color).is_equal_approx(hair[key]), "волосы %s" % key)
	var lens_rows := _table_after("**Линзы**").slice(2)
	assert_eq(lens_rows.size(), RiderLook.LENSES.size(), "линз")
	for r: PackedStringArray in lens_rows:
		var key := _ticks(r[0])[0]
		var pair: Array = RiderLook.LENSES.get(key, [])
		assert_eq(pair.size(), 2, "линза %s" % key)
		if pair.size() == 2:
			assert_true((pair[0] as Color).is_equal_approx(_color(r[1])), "линза %s: основной тон" % key)
			assert_true((pair[1] as Color).is_equal_approx(_color(r[2])), "линза %s: блик" % key)


func test_jersey_pattern_scheme_matches_spec() -> void:
	var rows := _table_after("Узор джерси — откуда берут цвет")
	var seen := 0
	for r: PackedStringArray in rows.slice(2):
		var key := _ticks(r[0])[0]
		var expected: Array = [r[1], r[2], r[3], r[4], r[5]]
		assert_eq(RiderLook.PATTERN_SOURCES.get(key, []), expected, "узор %s" % key)
		seen += 1
	assert_eq(seen, RiderLook.PATTERN_SOURCES.size(), "узоров столько же, сколько в спеке")


func test_presets_match_spec_table_slot_by_slot() -> void:
	var parsed := _spec_presets()
	var ids: Array[String] = parsed[0]
	var values: Dictionary = parsed[2]
	assert_eq(ids.size(), 6, "в спеке ред. 4 — 6 пресетов")
	assert_true(ids.has("volga_union"), "есть volga_union")
	assert_eq(Array(RiderLook.PRESET_IDS), Array(ids), "пресеты и их порядок — как в спеке")
	for id in ids:
		var look := RiderLook.preset(id)
		assert_not_null(look, "пресет %s есть" % id)
		if look == null:
			continue
		var spec_values: Dictionary = values[id]
		assert_eq(spec_values.size(), 28, "%s: в таблице пресетов все 28 слотов" % id)
		for slot: String in RiderLook.SLOTS:
			var want: String = spec_values.get(slot, "?")
			if want.is_empty():
				want = RiderLook.default_value(slot)
			assert_eq(look.get_value(slot), want, "%s.%s" % [id, slot])
		# Пресет проходит проверку п.3 без замен.
		var reread := RiderLook.from_dict(look.to_dict())
		assert_eq(reread.reset_slots(), [] as Array[String], "%s: без замен при чтении" % id)
		assert_true(reread.equals(look), "%s: round-trip" % id)
	assert_true(RiderLook.default_look().equals(RiderLook.preset("classic")), "по умолчанию — classic")


func test_preset_names_equal_spec_header_ru_en() -> void:
	var parsed := _spec_presets()
	var names: Dictionary = parsed[1]
	var csv := {}
	var f := FileAccess.open(MENU_CSV, FileAccess.READ)
	var header := f.get_csv_line()
	var ru := header.find("ru")
	var en := header.find("en")
	while not f.eof_reached():
		var row := f.get_csv_line()
		if row.size() > maxi(ru, en):
			csv[row[0]] = [row[ru], row[en]]
	for id: String in names:
		var key := "ui.menu.rider_look.preset." + id
		assert_eq(RiderLook.preset_name_key(id), key, "%s: ключ перевода по шаблону" % id)
		assert_true(csv.has(key), "%s в strings_menu.csv" % key)
		if csv.has(key):
			assert_eq(csv[key], names[id], "%s: тексты ru/en равны названиям спеки" % key)
	for locale in ["ru", "en"]:
		var prev := TranslationServer.get_locale()
		TranslationServer.set_locale(locale)
		for id: String in names:
			var i := 0 if locale == "ru" else 1
			assert_eq(String(TranslationServer.translate("ui.menu.rider_look.preset." + id)), str(names[id][i]), "%s %s: перевод" % [locale, id])
		TranslationServer.set_locale(prev)


# ---------------------------------------------------------------------------
# п.3 и п.1 — порча данных
# ---------------------------------------------------------------------------

func test_every_slot_with_every_kind_of_bad_value_resets_only_itself() -> void:
	var base := RiderLook.preset(RiderLook.PRESET_VOLGA_UNION)
	var bad_values: Array = [42, 1.5, true, null, ["black"], {"v": "black"}, "", "#FFFFFF", "Black", " black",
		"Color(0.1, 0.1, 0.1)", "unknown_model"]
	for slot: String in RiderLook.SLOTS:
		for bad: Variant in bad_values:
			var data := base.to_dict()
			data[slot] = bad
			var look := RiderLook.from_dict(data)
			assert_eq(look.get_value(slot), RiderLook.default_value(slot), "%s = %s → умолчание" % [slot, var_to_str(bad)])
			var others_ok := true
			for other: String in RiderLook.SLOTS:
				if other != slot and look.get_value(other) != base.get_value(other):
					others_ok = false
			assert_true(others_ok, "%s = %s: остальные слоты сохранены" % [slot, var_to_str(bad)])


func test_profile_with_non_dict_rider_look_reads_with_default_look() -> void:
	var repo := ProfileRepository.new(_dir)
	var p := repo.create("Rider")
	p.ftp_w = 260
	assert_eq(repo.save(p), [])
	for junk: Variant in ["classic", 7, ["m", "short"], null]:
		var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(repo.file_path()))
		(data["profiles"][0] as Dictionary)["rider_look"] = junk
		var f := FileAccess.open(repo.file_path(), FileAccess.WRITE)
		f.store_string(JSON.stringify(data))
		f.close()
		var reread := ProfileRepository.new(_dir).get_by_id(p.id)
		assert_not_null(reread, "rider_look = %s: профиль прочитан" % var_to_str(junk))
		if reread != null:
			assert_true(reread.rider_look.equals(RiderLook.default_look()), "rider_look = %s: внешность по умолчанию" % var_to_str(junk))
			assert_eq(reread.ftp_w, 260, "rider_look = %s: прочие поля целы" % var_to_str(junk))
