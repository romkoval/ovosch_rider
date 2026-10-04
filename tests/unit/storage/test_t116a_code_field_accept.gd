extends GutTest
## Повторная приёмка T-116a (tester; REQ-NFR-05 п.2): компромисс фильтра для поля `code` (77a2787).
## Код OAuth Strava — 40 строчных шестнадцатеричных символов (в нём есть цифры), поэтому он
## маскируется в любой форме: словарь разбора redirect, JSON-текст, `str()` словаря. Открытыми
## остаются только символьные коды ошибок (`auth_failed`, `network`) и числовые коды — их
## маскирование сделало бы журнал бесполезным для разбора отказов.

## Реалистичный код Strava (формат: 40 hex), не настоящий.
const HEX_CODE: String = "9f2c4e81a0b37d65c1e09a4f7b2d8c3e6a5f0b19"


func _filter() -> SecureStoreFilter:
	return SecureStoreFilter.new()


func test_realistic_hex_oauth_code_masked_in_parsed_redirect() -> void:
	var parsed := StravaOAuth.parse_redirect("ovoschrider://strava?state=s1&code=%s&scope=activity:write" % HEX_CODE)
	var out: Variant = _filter().redact_value(parsed)
	assert_false(JSON.stringify(out).contains(HEX_CODE), "hex-код из разбора redirect: %s" % JSON.stringify(out))
	assert_false(str(out).contains(HEX_CODE), "и в str()")


func test_realistic_hex_oauth_code_masked_in_text_forms() -> void:
	var f := _filter()
	for text: String in [
		JSON.stringify({"code": HEX_CODE, "state": "s1"}),
		str({"code": HEX_CODE}),
		"{'code': '%s'}" % HEX_CODE,
		"redirect ?code=%s&state=s1" % HEX_CODE,
	]:
		assert_false(f.redact(text).contains(HEX_CODE), "код в тексте: %s → %s" % [text, f.redact(text)])


func test_symbolic_and_numeric_error_codes_stay_readable() -> void:
	var f := _filter()
	for code: String in ["auth_failed", "network", "rate_limited", "not_found"]:
		var out: Dictionary = f.redact_value({"code": code, "status_code": 401})
		assert_eq(out["code"], code, "символьный код ошибки открыт: %s" % code)
		assert_eq(out["status_code"], 401, "числовой код открыт")
		assert_true(f.redact(JSON.stringify({"code": code})).contains(code), "и в JSON-тексте: %s" % code)
	var num: Dictionary = f.redact_value({"code": 429})
	assert_eq(num["code"], 429, "числовой code — не строка, открыт")


func test_mixed_case_or_digit_codes_are_masked_conservatively() -> void:
	# Всё, что не «строчные слова через _», считается возможным секретом (лишнее маскирование
	# безопасно): так ведёт себя фильтр и в словаре, и в тексте.
	var f := _filter()
	for code: String in ["Auth_Failed", "e401", "abc-def", "x" + HEX_CODE]:
		var out: Dictionary = f.redact_value({"code": code})
		assert_ne(out["code"], code, "не символьный код маскируется: %s" % code)
		assert_false(f.redact(JSON.stringify({"code": code})).contains(code), "и в JSON-тексте: %s" % code)
