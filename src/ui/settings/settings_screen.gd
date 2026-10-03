class_name SettingsScreen
extends Control
## Settings screen (`AppState.Screen.SETTINGS`): language (REQ-NFR-08 crit. 3, 4), active
## profile (REQ-PRF-02 crit. 1, REQ-WRK-04 crit. 1, REQ-DEV-05 crit. 2), Intervals.icu link,
## sync and FTP/zone sources (REQ-INT-06 crit. 5-7, REQ-PRF-03 crit. 2), Strava placeholder
## (T-049), about. All strings are translation keys; profile errors via `error.profile.<code>`.
##
## FTP is written only through `Profile.set_ftp_local()` (source resets to "local",
## REQ-INT-06 crit. 4); zones are not edited here. Power source goes to the profile and to
## `ConnectionManager.hub.set_power_source()`.

const ERROR_KEY_PREFIX: String = "error.profile."
const LICENSES_DOC: String = "docs/publishing/licenses.md"
const LOCALE_IDS: Array[String] = AppState.SUPPORTED_LOCALES
const POWER_SOURCE_IDS: Array[String] = [Profile.POWER_SOURCE_TRAINER, Profile.POWER_SOURCE_POWER_METER]
## Full translation keys per id (no key concatenation: the i18n inventory scans literals).
const LOCALE_KEYS: Dictionary = {
	"en": "ui.settings.lang_en",
	"ru": "ui.settings.lang_ru",
}
const POWER_SOURCE_KEYS: Dictionary = {
	Profile.POWER_SOURCE_TRAINER: "ui.settings.power_source_trainer",
	Profile.POWER_SOURCE_POWER_METER: "ui.settings.power_source_power_meter",
}
## Human-readable texts for `ApiResult` failure codes (REQ-NFR-08 crit. 1: no raw codes in UI).
const API_ERROR_KEYS: Dictionary = {
	ApiResult.CODE_AUTH_FAILED: "ui.settings.err_auth_failed",
	ApiResult.CODE_REAUTH_REQUIRED: "ui.settings.err_reauth_required",
	ApiResult.CODE_NETWORK: "ui.settings.err_network",
	ApiResult.CODE_RATE_LIMITED: "ui.settings.err_rate_limited",
	ApiResult.CODE_NOT_CONFIGURED: "ui.settings.err_not_configured",
	ApiResult.CODE_BAD_RESPONSE: "ui.settings.err_bad_response",
}
const API_ERROR_UNKNOWN_KEY: String = "ui.settings.err_unknown"
## Human-readable texts for `IntervalsSync.WARN_*` (local_override has its own message).
const SYNC_WARNING_KEYS: Dictionary = {
	IntervalsSync.WARN_FTP_MISSING: "ui.settings.warn_ftp_missing",
	IntervalsSync.WARN_FTP_OUT_OF_RANGE: "ui.settings.warn_ftp_out_of_range",
	IntervalsSync.WARN_POWER_ZONES_MISSING: "ui.settings.warn_power_zones_missing",
	IntervalsSync.WARN_POWER_ZONES_COUNT: "ui.settings.warn_power_zones_count",
	IntervalsSync.WARN_POWER_ZONES_INVALID: "ui.settings.warn_power_zones_invalid",
	IntervalsSync.WARN_HR_ZONES_MISSING: "ui.settings.warn_hr_zones_missing",
	IntervalsSync.WARN_HR_ZONES_INVALID: "ui.settings.warn_hr_zones_invalid",
	IntervalsSync.WARN_HR_ZONES_COUNT: "ui.settings.warn_hr_zones_count",
	IntervalsSync.WARN_MAX_HR_MISSING: "ui.settings.warn_max_hr_missing",
	IntervalsSync.WARN_NO_BIKE_SETTINGS: "ui.settings.warn_no_bike_settings",
}
const SYNC_WARNING_UNKNOWN_KEY: String = "ui.settings.warn_unknown"
## Human-readable reasons for a failed Strava sign-in (`StravaService.flow_error_code()`:
## `ApiResult.CODE_*` or a redirect refusal from `StravaOAuth`). The service's `message`
## is a log text and is never shown. `not_configured` has its own full message.
const STRAVA_ERROR_KEYS: Dictionary = {
	ApiResult.CODE_AUTH_FAILED: "ui.settings.strava_err_auth_failed",
	ApiResult.CODE_REAUTH_REQUIRED: "ui.settings.strava_err_auth_failed",
	ApiResult.CODE_NETWORK: "ui.settings.strava_err_network",
	ApiResult.CODE_RATE_LIMITED: "ui.settings.strava_err_rate_limited",
	ApiResult.CODE_BAD_RESPONSE: "ui.settings.strava_err_bad_response",
	"timeout": "ui.settings.strava_err_timeout",
	"access_denied": "ui.settings.strava_err_access_denied",
	"bad_request": "ui.settings.strava_err_bad_redirect",
	"state_mismatch": "ui.settings.strava_err_bad_redirect",
}
## Static labels/buttons: node path -> key. `Control.text` keeps the raw key (auto-translate
## applies only at draw time), so they are re-applied with `tr()` on every `refresh()` —
## this is what makes the language switch take effect without a restart (REQ-NFR-08 crit. 4).
const STATIC_TEXTS: Dictionary = {
	"Margin/Scroll/VBox/Title": "ui.settings.title",
	"Margin/Scroll/VBox/LanguageTitle": "ui.settings.language",
	"Margin/Scroll/VBox/Grid/NameLabel": "ui.settings.name",
	"Margin/Scroll/VBox/Grid/FtpLabel": "ui.settings.ftp",
	"Margin/Scroll/VBox/Grid/WeightLabel": "ui.settings.weight",
	"Margin/Scroll/VBox/Grid/MaxHrLabel": "ui.settings.max_hr",
	"Margin/Scroll/VBox/Grid/ResistanceLabel": "ui.settings.resistance",
	"Margin/Scroll/VBox/Grid/PowerSourceLabel": "ui.settings.power_source",
	"Margin/Scroll/VBox/SaveProfileButton": "ui.settings.save_profile",
	"Margin/Scroll/VBox/IntervalsTitle": "ui.settings.intervals_title",
	"Margin/Scroll/VBox/OverrideCheck": "ui.settings.intervals_override",
	"Margin/Scroll/VBox/IntervalsButtons/IntervalsKeyButton": "ui.settings.intervals_set_key",
	"Margin/Scroll/VBox/IntervalsButtons/IntervalsSyncButton": "ui.settings.intervals_sync",
	"Margin/Scroll/VBox/IntervalsButtons/IntervalsForgetButton": "ui.settings.intervals_forget",
	"Margin/Scroll/VBox/StravaTitle": "ui.settings.strava_title",
	"Margin/Scroll/VBox/AboutTitle": "ui.settings.about_title",
	"Margin/Scroll/VBox/Footer/SwitchProfileButton": "ui.settings.switch_profile",
	"Margin/Scroll/VBox/Footer/BackButton": "ui.settings.back",
}

var _repo: ProfileRepository
var _app_state: AppState
var _store: SecureStore
var _transport: HttpTransport
var _connections: ConnectionManager
var _last_sync_result: ApiResult = null
var _last_sync_warnings: Array[String] = []

@onready var _locale_option: OptionButton = %LocaleOption
@onready var _name_edit: LineEdit = %NameEdit
@onready var _ftp_spin: SpinBox = %FtpSpin
@onready var _weight_spin: SpinBox = %WeightSpin
@onready var _max_hr_spin: SpinBox = %MaxHrSpin
@onready var _resistance_spin: SpinBox = %ResistanceSpin
@onready var _power_source_option: OptionButton = %PowerSourceOption
@onready var _save_button: Button = %SaveProfileButton
@onready var _profile_error_label: Label = %ProfileErrorLabel
@onready var _profile_status_label: Label = %ProfileStatusLabel
@onready var _sources_label: Label = %SourcesLabel
@onready var _hr_zones_label: Label = %HrZonesLabel
@onready var _override_check: CheckButton = %OverrideCheck
@onready var _intervals_status_label: Label = %IntervalsStatusLabel
@onready var _intervals_key_button: Button = %IntervalsKeyButton
@onready var _intervals_sync_button: Button = %IntervalsSyncButton
@onready var _intervals_forget_button: Button = %IntervalsForgetButton
@onready var _intervals_message_label: Label = %IntervalsMessageLabel
@onready var _key_dialog: IntervalsKeyDialog = %IntervalsKeyDialog
@onready var _strava_status_label: Label = %StravaStatusLabel
@onready var _strava_connect_button: StravaConnectButton = %StravaConnectButton
## Сервис Strava активного профиля (T-049); null — привязка недоступна.
var _strava: StravaService = null
@onready var _version_label: Label = %VersionLabel
@onready var _licenses_label: Label = %LicensesLabel
@onready var _switch_button: Button = %SwitchProfileButton
@onready var _back_button: Button = %BackButton


func setup(repo: ProfileRepository, app_state: AppState, store: SecureStore,
		transport: HttpTransport, connections: ConnectionManager = null) -> void:
	_repo = repo
	_app_state = app_state
	_store = store
	_transport = transport
	_connections = connections
	if is_node_ready():
		refresh()


func _ready() -> void:
	_locale_option.clear()
	for i in LOCALE_IDS.size():
		_locale_option.add_item(LOCALE_IDS[i], i)
	_power_source_option.clear()
	for i in POWER_SOURCE_IDS.size():
		_power_source_option.add_item(POWER_SOURCE_IDS[i], i)
	_locale_option.item_selected.connect(_on_locale_selected)
	_save_button.pressed.connect(_on_save_pressed)
	_override_check.toggled.connect(set_override_local)
	_intervals_key_button.pressed.connect(open_key_dialog)
	_intervals_sync_button.pressed.connect(_on_sync_pressed)
	_intervals_forget_button.pressed.connect(forget_intervals)
	_key_dialog.submitted.connect(_on_key_submitted)
	_switch_button.pressed.connect(switch_profile)
	_back_button.pressed.connect(back)
	_strava_connect_button.connect_requested.connect(start_strava_connect)
	_strava_connect_button.disconnect_requested.connect(disconnect_strava)
	_strava_connect_button.set_available(false)
	if _repo != null:
		refresh()


## Signal handlers are bound methods (no lambdas); the coroutine results are not awaited here.
func _on_save_pressed() -> void:
	save_profile()


func _on_sync_pressed() -> void:
	sync_intervals()


func _on_key_submitted(athlete_id: String, key: String) -> void:
	submit_key(athlete_id, key)


# ---------------------------------------------------------------------------
# Rendering
# ---------------------------------------------------------------------------

## Full re-render from the repository, settings and store, including the profile form fields.
## Call on entering the screen, after saving the profile and after a sync — i.e. only when the
## form must reflect the stored profile. Unsaved form input is overwritten here by design.
func refresh() -> void:
	if _repo == null or not is_node_ready():
		return
	refresh_texts()
	_render_profile_form()


## Re-render labels, buttons, statuses and option texts without touching the values the user
## typed into the profile form (language switch, override toggle, key/unlink actions).
func refresh_texts() -> void:
	if _repo == null or not is_node_ready():
		return
	_render_static()
	_render_locale()
	_render_power_source_items()
	_render_profile_status()
	_render_sources()
	_render_intervals()
	_render_strava()
	_render_about()


func _render_static() -> void:
	for path: String in STATIC_TEXTS:
		var node := get_node_or_null(path)
		if node != null:
			node.set("text", tr(STATIC_TEXTS[path]))


func _render_locale() -> void:
	var current := _app_state.locale() if _app_state != null else TranslationServer.get_locale().substr(0, 2)
	for i in LOCALE_IDS.size():
		_locale_option.set_item_text(i, tr(str(LOCALE_KEYS.get(LOCALE_IDS[i], LOCALE_IDS[i]))))
	var idx := LOCALE_IDS.find(current)
	if idx >= 0:
		_locale_option.select(idx)


func _render_power_source_items() -> void:
	for i in POWER_SOURCE_IDS.size():
		_power_source_option.set_item_text(i, tr(str(POWER_SOURCE_KEYS.get(POWER_SOURCE_IDS[i], POWER_SOURCE_IDS[i]))))


func _render_profile_status() -> void:
	var p := _active()
	_save_button.disabled = p == null
	_profile_status_label.text = tr("ui.settings.no_profile") if p == null else tr("ui.settings.profile_title").format({"name": p.name})


## Fill the form fields from the active profile (overwrites unsaved input).
func _render_profile_form() -> void:
	var p := _active()
	if p == null:
		_name_edit.text = ""
		return
	_name_edit.text = p.name
	_ftp_spin.value = p.ftp_w
	_weight_spin.value = p.weight_kg
	_max_hr_spin.value = p.max_hr
	_resistance_spin.value = p.resistance_level_default
	_power_source_option.select(maxi(POWER_SOURCE_IDS.find(p.power_source), 0))
	_override_check.set_pressed_no_signal(p.intervals_override_local)
	_profile_error_label.visible = false
	_profile_error_label.text = ""


func _render_sources() -> void:
	var p := _active()
	if p == null:
		_sources_label.text = ""
		_hr_zones_label.text = ""
		return
	_sources_label.text = tr("ui.settings.sources").format({
		"ftp": source_text(p.ftp_source), "zones": source_text(p.zones_source)})
	_hr_zones_label.text = tr("ui.settings.hr_zones_available") if p.has_hr_zones() else tr("ui.settings.hr_zones_unavailable")


func _render_intervals() -> void:
	var p := _active()
	var client := _client(p)
	var linked := client != null and client.is_linked()
	if p == null:
		_intervals_status_label.text = tr("ui.settings.no_profile")
	elif linked:
		var aid := p.intervals_athlete_id if not p.intervals_athlete_id.is_empty() else "—"
		_intervals_status_label.text = tr("ui.settings.intervals_linked").format({"athlete_id": aid})
	else:
		_intervals_status_label.text = tr("ui.settings.intervals_not_linked")
	_intervals_key_button.disabled = p == null
	_intervals_sync_button.disabled = not (client != null and client.is_configured())
	_intervals_forget_button.disabled = not linked
	_override_check.disabled = p == null
	_intervals_message_label.text = _sync_message()


## Подключить сервис Strava активного профиля (вызывает оболочка при выборе профиля).
func set_strava_service(service: StravaService) -> void:
	if _strava != null:
		if _strava.authorized_changed.is_connected(_on_strava_authorized_changed):
			_strava.authorized_changed.disconnect(_on_strava_authorized_changed)
		if _strava.connect_flow_changed.is_connected(_on_strava_flow_changed):
			_strava.connect_flow_changed.disconnect(_on_strava_flow_changed)
	_strava = service
	if _strava != null:
		_strava.authorized_changed.connect(_on_strava_authorized_changed)
		_strava.connect_flow_changed.connect(_on_strava_flow_changed)
	if is_node_ready():
		_render_strava()


func start_strava_connect() -> void:
	if _strava == null:
		return
	var url := _strava.connect_flow_start()
	_strava_connect_button.set_authorize_url(url)


func disconnect_strava() -> void:
	if _strava == null:
		return
	_strava_connect_button.set_busy(true)
	await _strava.disconnect_strava()
	_strava_connect_button.set_busy(false)
	_render_strava()


func _on_strava_authorized_changed(_authorized: bool) -> void:
	_strava_connect_button.set_authorize_url("")
	_render_strava()


func _on_strava_flow_changed(state: String, _message: String) -> void:
	match state:
		"waiting":
			_strava_status_label.text = tr("ui.settings.strava_connecting")
		"exchanging":
			_strava_connect_button.set_busy(true)
		"failed":
			_strava_connect_button.set_busy(false)
			_strava_connect_button.set_authorize_url("")
			_strava_status_label.text = strava_error_text(_strava.flow_error_code() if _strava != null else "")
		_:
			_strava_connect_button.set_busy(false)


func _render_strava() -> void:
	if _strava == null or not _strava.is_configured():
		_strava_status_label.text = tr("ui.settings.strava_unavailable") if _strava != null else tr("ui.settings.strava_not_linked")
		_strava_connect_button.set_authorized(false)
		_strava_connect_button.set_available(false)
		return
	_strava_connect_button.set_available(true)
	_strava_connect_button.set_authorized(_strava.is_authorized())
	_strava_status_label.text = tr("ui.settings.strava_linked") if _strava.is_authorized() else tr("ui.settings.strava_not_linked")


## Translated text for a failed Strava sign-in by reason code (never the service message).
func strava_error_text(code: String) -> String:
	if code == ApiResult.CODE_NOT_CONFIGURED:
		return tr("ui.settings.strava_unavailable")
	return tr("ui.settings.strava_error").format({"message": tr(str(STRAVA_ERROR_KEYS.get(code, API_ERROR_UNKNOWN_KEY)))})


func strava_button() -> StravaConnectButton:
	return _strava_connect_button


func _render_about() -> void:
	_version_label.text = tr("ui.settings.version").format({"version": app_version()})
	var lines: PackedStringArray = [
		tr("ui.settings.licenses_title"),
		tr("ui.settings.license_godot"),
		tr("ui.settings.license_gut"),
		tr("ui.settings.license_godot_cpp"),
		tr("ui.settings.licenses_doc").format({"path": LICENSES_DOC}),
	]
	_licenses_label.text = "\n".join(lines)


## Human-readable FTP/zones source: "local" or "intervals:<date>".
func source_text(source: String) -> String:
	if source.begins_with(Profile.SOURCE_INTERVALS_PREFIX):
		var parts := source.split(":")
		var date := parts[1] if parts.size() > 1 else "—"
		return tr("ui.settings.source_intervals").format({"date": date})
	return tr("ui.settings.source_local")


static func app_version() -> String:
	var v := str(ProjectSettings.get_setting("application/config/version", ""))
	return v if not v.is_empty() else "—"


func _sync_message() -> String:
	if _last_sync_result == null:
		return ""
	if _last_sync_result.ok:
		if _last_sync_warnings.has(IntervalsSync.WARN_LOCAL_OVERRIDE):
			return tr("ui.settings.sync_skipped_override")
		if _last_sync_warnings.is_empty():
			return tr("ui.settings.sync_done")
		var texts: PackedStringArray = []
		for code in _last_sync_warnings:
			texts.append(tr(str(SYNC_WARNING_KEYS.get(code, SYNC_WARNING_UNKNOWN_KEY))))
		return tr("ui.settings.sync_done_with_warnings").format({"warnings": "; ".join(texts)})
	return tr("ui.settings.sync_failed").format({"reason": api_error_text(_last_sync_result.code)})


## Translated reason for an `ApiResult` failure code (never the raw code).
func api_error_text(code: String) -> String:
	return tr(str(API_ERROR_KEYS.get(code, API_ERROR_UNKNOWN_KEY)))


# ---------------------------------------------------------------------------
# Language (REQ-NFR-08 crit. 3, 4)
# ---------------------------------------------------------------------------

## Apply and persist the interface language through `AppState.set_locale` (the only
## place that touches the translation server and settings); false if unsupported.
func set_locale(locale: String) -> bool:
	if _app_state == null or not _app_state.set_locale(locale):
		return false
	refresh_texts()
	return true


func _on_locale_selected(index: int) -> void:
	if index >= 0 and index < LOCALE_IDS.size():
		set_locale(LOCALE_IDS[index])


# ---------------------------------------------------------------------------
# Profile (REQ-PRF-02 crit. 1, REQ-WRK-04 crit. 1, REQ-DEV-05 crit. 2)
# ---------------------------------------------------------------------------

func fill_profile_form(profile_name: String, ftp_w: int, weight_kg: float, max_hr: int,
		resistance_pct: int = -1, power_source: String = "") -> void:
	_name_edit.text = profile_name
	_ftp_spin.value = ftp_w
	_weight_spin.value = weight_kg
	_max_hr_spin.value = max_hr
	if resistance_pct >= 0:
		_resistance_spin.value = resistance_pct
	if not power_source.is_empty():
		_power_source_option.select(maxi(POWER_SOURCE_IDS.find(power_source), 0))


## Save the form into the active profile. Returns error codes (empty = saved).
func save_profile() -> Array[String]:
	var active := _active()
	if active == null:
		return [ProfileRepository.ERR_PROFILE_NOT_FOUND]
	var p := active.duplicate_profile()
	p.name = _name_edit.text
	var new_ftp := int(_ftp_spin.value)
	if new_ftp != p.ftp_w:
		p.set_ftp_local(new_ftp)
	p.weight_kg = _weight_spin.value
	p.max_hr = int(_max_hr_spin.value)
	p.resistance_level_default = int(_resistance_spin.value)
	p.power_source = POWER_SOURCE_IDS[clampi(_power_source_option.selected, 0, POWER_SOURCE_IDS.size() - 1)]
	var errors := _repo.save(p)
	if errors.is_empty():
		_apply_power_source(p)
		refresh()
		_profile_status_label.text = tr("ui.settings.profile_saved").format({"name": p.name})
	else:
		_show_profile_errors(errors)
	return errors


func set_override_local(enabled: bool) -> void:
	var active := _active()
	if active == null:
		return
	var p := active.duplicate_profile()
	p.intervals_override_local = enabled
	var errors := _repo.save(p)
	if not errors.is_empty():
		_show_profile_errors(errors)
	_override_check.set_pressed_no_signal(_active().intervals_override_local)
	refresh_texts()


func profile_error_text() -> String:
	return _profile_error_label.text if _profile_error_label.visible else ""


func profile_status_text() -> String:
	return _profile_status_label.text


func sources_text() -> String:
	return _sources_label.text


func hr_zones_text() -> String:
	return _hr_zones_label.text


func _show_profile_errors(codes: Array[String]) -> void:
	var lines: Array[String] = []
	for code in codes:
		lines.append(tr(ERROR_KEY_PREFIX + code))
	_profile_error_label.text = "\n".join(lines)
	_profile_error_label.visible = not lines.is_empty()


func _apply_power_source(p: Profile) -> void:
	if _connections != null and _connections.hub != null:
		_connections.hub.set_power_source(p.power_source)


# ---------------------------------------------------------------------------
# Intervals.icu (REQ-INT-06 crit. 5-7, REQ-PRF-03 crit. 2)
# ---------------------------------------------------------------------------

func open_key_dialog() -> void:
	var p := _active()
	_key_dialog.open(p.intervals_athlete_id if p != null else "")


## Verify and store the key (REQ-INT-01 crit. 1-4). The dialog closes only on success; on
## failure it stays open with a translated message (empty fields have their own text).
## Returns the API result.
func submit_key(athlete_id: String, key: String) -> ApiResult:
	var p := _active()
	if p == null:
		return ApiResult.failure(ApiResult.CODE_NOT_CONFIGURED, "no profile")
	var client := IntervalsIcuClient.for_profile(_transport, _store, p)
	var result: ApiResult = await client.verify_key(athlete_id, key)
	if result.ok:
		var updated := p.duplicate_profile()
		updated.intervals_athlete_id = client.athlete_id
		_repo.save(updated)
		_key_dialog.hide()
		_last_sync_result = null
		var athlete_name := str((result.data as Dictionary).get("name", "")) if result.data is Dictionary else ""
		if athlete_name.is_empty():
			athlete_name = client.athlete_id
		refresh_texts()
		_intervals_message_label.text = tr("ui.settings.key_saved").format({"name": athlete_name})
	else:
		_key_dialog.show_error(key_error_text(result.code))
	return result


## Translated message for a failed key verification (REQ-INT-01 crit. 3).
func key_error_text(code: String) -> String:
	match code:
		ApiResult.CODE_AUTH_FAILED, ApiResult.CODE_REAUTH_REQUIRED:
			return tr("ui.settings.key_rejected")
		ApiResult.CODE_NOT_CONFIGURED:
			return tr("ui.settings.key_fill_both")
		_:
			return tr("ui.settings.key_check_failed").format({"reason": api_error_text(code)})


## Pull the athlete from Intervals.icu and apply it to the active profile
## (`IntervalsSync.sync_profile`; honours `intervals_override_local`). Returns the API result.
func sync_intervals() -> ApiResult:
	var p := _active()
	if p == null:
		return ApiResult.failure(ApiResult.CODE_NOT_CONFIGURED, "no profile")
	var client := IntervalsIcuClient.for_profile(_transport, _store, p)
	if not client.is_configured():
		_last_sync_result = ApiResult.failure(ApiResult.CODE_NOT_CONFIGURED, "not configured")
		_last_sync_warnings = []
		refresh_texts()
		return _last_sync_result
	var result: ApiResult = await client.get_athlete()
	_last_sync_result = result
	_last_sync_warnings = []
	if result.ok:
		var updated := p.duplicate_profile()
		_last_sync_warnings = IntervalsSync.sync_profile(updated, result.data)
		var errors := _repo.save(updated)
		if not errors.is_empty():
			_show_profile_errors(errors)
	refresh()
	return result


## Unlink Intervals.icu: delete the key (REQ-PRF-03 crit. 2); FTP/zone sources are kept.
func forget_intervals() -> void:
	var p := _active()
	if p == null:
		return
	var client := IntervalsIcuClient.for_profile(_transport, _store, p)
	client.forget_key()
	var updated := p.duplicate_profile()
	updated.intervals_athlete_id = ""
	_repo.save(updated)
	_last_sync_result = null
	refresh_texts()
	_intervals_message_label.text = tr("ui.settings.intervals_unlinked")


func intervals_status_text() -> String:
	return _intervals_status_label.text


func intervals_message_text() -> String:
	return _intervals_message_label.text


func key_dialog() -> IntervalsKeyDialog:
	return _key_dialog


# ---------------------------------------------------------------------------
# Navigation
# ---------------------------------------------------------------------------

func switch_profile() -> void:
	if _app_state != null:
		_app_state.switch_profile()


func back() -> void:
	if _app_state != null:
		_app_state.navigate(AppState.Screen.HOME)


func version_text() -> String:
	return _version_label.text


func licenses_text() -> String:
	return _licenses_label.text


func strava_status_text() -> String:
	return _strava_status_label.text


# ---------------------------------------------------------------------------
# Internal
# ---------------------------------------------------------------------------

func _active() -> Profile:
	return _repo.get_active() if _repo != null else null


func _client(p: Profile) -> IntervalsIcuClient:
	if p == null or _transport == null or _store == null:
		return null
	return IntervalsIcuClient.for_profile(_transport, _store, p)
