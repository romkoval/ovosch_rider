extends GutTest
## Acceptance of T-173 (tester): the recovery dialog writes the start date as the ride card in
## history does — `HistoryFormat.full_date` in the current locale: «10 окт 2026, 10:55» /
## "Oct 10, 2026, 10:55"; no machine `YYYY-MM-DD` (REQ-LOC-07 p.3, REQ-NFR-08).

const THEME_PATH: String = "res://src/ui/theme/app_theme.tres"

var _dialog: RecoveryDialog
var _locale: String


func before_each() -> void:
	_locale = TranslationServer.get_locale()
	var vp := SubViewport.new()
	vp.gui_embed_subwindows = true
	vp.size = Vector2i(1280, 720)
	add_child_autofree(vp)
	var host := Control.new()
	if ResourceLoader.exists(THEME_PATH):
		host.theme = load(THEME_PATH) as Theme
	host.set_anchors_preset(Control.PRESET_FULL_RECT)
	vp.add_child(host)
	_dialog = RecoveryDialog.new()
	host.add_child(_dialog)


func after_each() -> void:
	TranslationServer.set_locale(_locale)


## Unix time of the local wall clock 2026-10-10 10:55 (the same bias `HistoryFormat` applies).
static func _local_1055() -> int:
	var bias_sec: int = int(Time.get_time_zone_from_system().get("bias", 0)) * 60
	return int(Time.get_unix_time_from_datetime_dict({"year": 2026, "month": 10, "day": 10, "hour": 10, "minute": 55, "second": 0})) - bias_sec


func test_req_loc_07_c3_recovery_date_ru_en_literal_and_equal_to_ride_card() -> void:
	var ride := Ride.new()
	ride.started_at_unix = _local_1055()
	ride.id = Ride.generate_id(ride.started_at_unix)
	ride.name = "Утро"
	ride.compute_summary()
	var want := {"ru": "10 окт 2026, 10:55", "en": "Oct 10, 2026, 10:55"}
	for loc in ["ru", "en"]:
		TranslationServer.set_locale(loc)
		_dialog.show_for([ride] as Array[Ride])
		await wait_process_frames(2)
		var text := _dialog.dialog_text
		gut.p("%s: %s" % [loc, text])
		assert_string_contains(text, str(want[loc]), "%s: literal date of the criterion" % loc)
		assert_eq(HistoryFormat.full_date(ride.started_at_unix), str(want[loc]), "%s: the ride card string" % loc)
		assert_null(RegEx.create_from_string("\\d{4}-\\d{2}-\\d{2}").search(text), "%s: no YYYY-MM-DD" % loc)
		_dialog.hide()
