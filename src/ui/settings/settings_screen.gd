class_name SettingsScreen
extends Control
## Экран настроек (`AppState.Screen.SETTINGS`; `docs/game/ui.md` п. 8.6; REQ-UIX-04 крит. 1, 3).
##
## Раскладка. Сверху `AppBar` «Настройки» с кнопкой «назад» (`AppState.go_back()`) и фишкой
## профиля справа (нажатие — смена профиля). Ниже разделы ровно в порядке UIX-04 крит. 3
## (`SettingsSections.ORDER`): «Профиль», «Тренировка», «Зоны», «Интеграции», «Интерфейс»,
## «О программе»; каждый — заголовок H2 и карточка со строками «подпись слева, контрол справа,
## пояснение под подписью». Regular (ширина холста ≥ 1100 lp): слева навигация по разделам
## (260 lp, выбранный — `surface3` и полоса `accent`), справа прокрутка с разделами до 720 lp;
## нажатие в навигации прокручивает к разделу. Compact: один столбец с прокруткой. Экран
## открывается прокрученным в начало.
##
## Функции экрана (как до T-086):
## - язык (REQ-NFR-08 крит. 3, 4) — через `AppState.set_locale`, без перезапуска;
## - профиль (REQ-PRF-02 крит. 1, REQ-DEV-05 крит. 2): имя, FTP, вес, макс. пульс, источник
##   мощности; «Сохранить профиль» активна только при изменениях; FTP пишется через
##   `Profile.set_ftp_local()` (источник — «локально», REQ-INT-06 крит. 4); ошибки — по кодам
##   `error.profile.<code>`; источник мощности уходит в `ConnectionManager.hub`;
## - тренировка (REQ-WRK-04 крит. 1): сопротивление вне ERG, интенсивность по умолчанию,
##   крутизна SIM по умолчанию (`Profile.sim_steepness_pct`, T-061) — сохраняются сразу при
##   изменении (в форме профиля они тоже сохраняются);
## - зоны: источник FTP и зон, переопределение (REQ-INT-06 крит. 5–7), баннер «зоны пульса
##   недоступны»;
## - Intervals.icu (REQ-INT-01, REQ-PRF-03 крит. 2): ключ через `SecureStore` и диалог,
##   синхронизация, отвязка; Strava (T-049) — официальная кнопка `StravaConnectButton`;
## - нечитаемое хранилище секретов — баннер с подтверждённым сбросом (`SecureStore.reset_store()`);
## - «О программе»: версия, лицензии (лист), политика конфиденциальности.
##
## Тексты — ключи переводов: прежние (`strings.csv`) — `STATIC_TEXTS`, новые T-086
## (`strings_menu.csv`) — `SettingsSections.TEXTS`; оба применяются `tr()` при каждой
## перерисовке. Стили — только вариации темы (UIX-01 крит. 2); цвета точки статуса и полосы
## выбранного раздела — данные состояния, рисуются.

const ERROR_KEY_PREFIX: String = "error.profile."
const LICENSES_DOC: String = "docs/publishing/licenses.md"
## Политика конфиденциальности (REQ-NFR-07 крит. 1): адрес публикации задаёт владелец перед
## релизом; до этого на экране — путь к документу.
const PRIVACY_POLICY_DOC: String = "docs/publishing/privacy_policy.md"
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
	ApiResult.CODE_STORAGE_FAILED: "ui.settings.err_storage_failed",
}
const API_ERROR_UNKNOWN_KEY: String = "ui.settings.err_unknown"
## Notice: the language was applied but `AppSettings` could not be written.
const LOCALE_SAVE_FAILED_KEY: String = "ui.settings.locale_save_failed"
const STORE_RESET_DONE_KEY: String = "ui.settings.store_reset_done"
const STORE_RESET_FAILED_KEY: String = "ui.settings.store_reset_failed"
## Вид баннера уведомления по ключу (сброс удался — сведения, не удался — ошибка, язык не
## сохранён — предупреждение).
const NOTICE_KINDS: Dictionary = {
	LOCALE_SAVE_FAILED_KEY: Banner.Kind.WARN,
	STORE_RESET_DONE_KEY: Banner.Kind.INFO,
	STORE_RESET_FAILED_KEY: Banner.Kind.ERROR,
}
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
	ApiResult.CODE_STORAGE_FAILED: "ui.settings.strava_err_storage_failed",
	"timeout": "ui.settings.strava_err_timeout",
	"access_denied": "ui.settings.strava_err_access_denied",
	"bad_request": "ui.settings.strava_err_bad_redirect",
	"state_mismatch": "ui.settings.strava_err_bad_redirect",
}
const TITLE_KEY: String = "ui.settings.title"
const SWITCH_PROFILE_KEY: String = "ui.settings.switch_profile"
const STORE_WARNING_KEY: String = "ui.settings.store_unreadable"
const STORE_RESET_KEY: String = "ui.settings.store_reset"
const HR_ZONES_AVAILABLE_KEY: String = "ui.settings.hr_zones_available"
const HR_ZONES_UNAVAILABLE_KEY: String = "ui.settings.hr_zones_unavailable"
const UNIT_PCT_KEY: String = SettingsSections.UNIT_PCT
const UNIT_W_KEY: String = SettingsSections.UNIT_W

const _C: String = SettingsSections.CONTENT
## Static labels/buttons: node path -> key (`strings.csv`). `Control.text` keeps the
## translated text, so they are re-applied with `tr()` on every render — this is what makes
## the language switch take effect without a restart (REQ-NFR-08 crit. 4).
const STATIC_TEXTS: Dictionary = {
	_C + "ProfileSection/Card/Rows/NameRow/NameLabel": "ui.settings.name",
	_C + "ProfileSection/Card/Rows/FtpRow/FtpLabel": "ui.settings.ftp",
	_C + "ProfileSection/Card/Rows/WeightRow/WeightLabel": "ui.settings.weight",
	_C + "ProfileSection/Card/Rows/MaxHrRow/MaxHrLabel": "ui.settings.max_hr",
	_C + "ProfileSection/Card/Rows/PowerSourceRow/PowerSourceLabel": "ui.settings.power_source",
	_C + "ProfileSection/Card/Rows/Footer/SaveProfileButton": "ui.settings.save_profile",
	_C + "TrainingSection/Card/Rows/ResistanceRow/Texts/Label": "ui.settings.resistance",
	_C + "ZonesSection/Card/Rows/OverrideCheck": "ui.settings.intervals_override",
	_C + "IntegrationsSection/IntervalsCard/Rows/Header/IntervalsTitle": "ui.settings.intervals_title",
	_C + "IntegrationsSection/IntervalsCard/Rows/IntervalsButtons/IntervalsKeyButton": "ui.settings.intervals_set_key",
	_C + "IntegrationsSection/IntervalsCard/Rows/IntervalsButtons/IntervalsSyncButton": "ui.settings.intervals_sync",
	_C + "IntegrationsSection/IntervalsCard/Rows/IntervalsButtons/IntervalsForgetButton": "ui.settings.intervals_forget",
	_C + "IntegrationsSection/StravaCard/Rows/StravaTitle": "ui.settings.strava_title",
	_C + "InterfaceSection/Card/Rows/LanguageRow/Label": "ui.settings.language",
	_C + "AboutSection/Title": "ui.settings.about_title",
}

## Брейкпоинт compact по ширине холста, lp — тот же, что у AppBar (`ui.md` п. 3).
const COMPACT_MAX_WIDTH: float = AppBar.COMPACT_MAX_WIDTH
## Навигация по разделам (regular) и ширина содержимого (`ui.md` п. 8.6).
const NAV_WIDTH: float = 260.0
const NAV_ROW_HEIGHT: float = 48.0
const NAV_MARKER_WIDTH: float = 3.0
const NAV_MARKER_INSET: float = 10.0
const BODY_GAP: float = 24.0
const CONTENT_MAX_WIDTH: float = 720.0
## Точка статуса Intervals.icu (как у фишек статуса, `ui.md` п. 6).
const STATUS_DOT_DIAMETER: float = 10.0
## Аватар в фишке профиля AppBar (`ui.md` п. 6: 28 lp).
const CHIP_AVATAR_DIAMETER: float = 28.0
## Запас прокрутки при определении текущего раздела, lp.
const NAV_SYNC_SLACK: float = 8.0

var _repo: ProfileRepository
var _app_state: AppState
var _store: SecureStore
var _transport: HttpTransport
var _connections: ConnectionManager
var _last_sync_result: ApiResult = null
var _last_sync_warnings: Array[String] = []
## Ждёт подтверждения сброса хранилища секретов («Сбросить привязки»).
var _reset_pending: bool = false
## Translation key of the current screen-level notice ("" — none).
var _notice_key: String = ""
## Форма заполняется программно: изменения полей не сохраняются и не помечают форму.
var _rendering: bool = false
var _compact: bool = false
var _nav_buttons: Dictionary = {}
var _nav_group: ButtonGroup = ButtonGroup.new()
## Сервис Strava активного профиля (T-049); null — привязка недоступна.
var _strava: StravaService = null
var _profile_chip: Button = null
var _chip_placeholder: ImageTexture = null

@onready var _root: VBoxContainer = %Root
@onready var _app_bar: AppBar = %AppBar
@onready var _margin: MarginContainer = %Margin
@onready var _body: HBoxContainer = %Body
@onready var _nav: VBoxContainer = %Nav
@onready var _scroll: ScrollContainer = %Scroll
@onready var _content: VBoxContainer = %Content
@onready var _locale_option: OptionButton = %LocaleOption
@onready var _name_edit: LineEdit = %NameEdit
@onready var _ftp_spin: SpinBox = %FtpSpin
@onready var _weight_spin: SpinBox = %WeightSpin
@onready var _max_hr_spin: SpinBox = %MaxHrSpin
@onready var _resistance_spin: SpinBox = %ResistanceSpin
@onready var _intensity_spin: SpinBox = %IntensitySpin
@onready var _steepness_slider: HSlider = %SteepnessSlider
@onready var _steepness_value: Label = %SteepnessValue
@onready var _training_error_label: Label = %TrainingErrorLabel
@onready var _power_source_option: OptionButton = %PowerSourceOption
@onready var _save_button: Button = %SaveProfileButton
@onready var _profile_error_label: Label = %ProfileErrorLabel
@onready var _profile_status_label: Label = %ProfileStatusLabel
@onready var _sources_label: Label = %SourcesLabel
@onready var _hr_zones_banner: Banner = %HrZonesBanner
@onready var _override_check: CheckButton = %OverrideCheck
@onready var _intervals_dot: Control = %IntervalsDot
@onready var _intervals_status_label: Label = %IntervalsStatusLabel
@onready var _intervals_buttons: BoxContainer = %IntervalsButtons
@onready var _intervals_key_button: Button = %IntervalsKeyButton
@onready var _intervals_sync_button: Button = %IntervalsSyncButton
@onready var _intervals_forget_button: Button = %IntervalsForgetButton
@onready var _intervals_message_label: Label = %IntervalsMessageLabel
@onready var _key_dialog: IntervalsKeyDialog = %IntervalsKeyDialog
@onready var _store_warning: Banner = %StoreWarning
@onready var _notice_banner: Banner = %NoticeBanner
@onready var _reset_store_dialog: ConfirmationDialog = %ResetStoreDialog
@onready var _strava_status_label: Label = %StravaStatusLabel
@onready var _strava_connect_button: StravaConnectButton = %StravaConnectButton
@onready var _version_label: Label = %VersionLabel
@onready var _licenses_button: Button = %LicensesButton
@onready var _licenses_dialog: AcceptDialog = %LicensesDialog
@onready var _licenses_label: Label = %LicensesLabel
@onready var _privacy_doc_label: Label = %PrivacyDocLabel
## Текст и действие баннеров доступны экрану по уникальным именам (контракт тестов T-057).
var _store_warning_label: Label
var _reset_store_button: Button
## Screen-level notice (store reset result, unsaved language); re-translated on every render.
var _notice_label: Label
var _back_button: Button


func setup(repo: ProfileRepository, app_state: AppState, store: SecureStore,
		transport: HttpTransport, connections: ConnectionManager = null) -> void:
	_repo = repo
	_app_state = app_state
	_store = store
	_transport = transport
	_connections = connections
	if is_node_ready():
		_app_bar.setup(app_state)
		refresh()


func _ready() -> void:
	_app_bar.setup(_app_state)
	_app_bar.set_title(TITLE_KEY)
	_back_button = _expose(_app_bar.back_button(), "BackButton") as Button
	_store_warning_label = _expose(_store_warning.text_label(), "StoreWarningLabel") as Label
	_reset_store_button = _expose(_store_warning.action_button(), "ResetStoreButton") as Button
	_notice_label = _expose(_notice_banner.text_label(), "NoticeLabel") as Label
	_build_profile_chip()
	_build_nav()
	_locale_option.clear()
	for i in LOCALE_IDS.size():
		_locale_option.add_item(LOCALE_IDS[i], i)
	_power_source_option.clear()
	for i in POWER_SOURCE_IDS.size():
		_power_source_option.add_item(POWER_SOURCE_IDS[i], i)
	_steepness_slider.min_value = Profile.MIN_SIM_STEEPNESS_PCT
	_steepness_slider.max_value = Profile.MAX_SIM_STEEPNESS_PCT
	_steepness_slider.step = Profile.SIM_STEEPNESS_STEP_PCT
	_intensity_spin.min_value = Profile.MIN_INTENSITY_PCT
	_intensity_spin.max_value = Profile.MAX_INTENSITY_PCT
	_locale_option.item_selected.connect(_on_locale_selected)
	_save_button.pressed.connect(_on_save_pressed)
	_name_edit.text_changed.connect(_on_form_text_changed)
	for spin: SpinBox in [_ftp_spin, _weight_spin, _max_hr_spin]:
		spin.value_changed.connect(_on_form_value_changed)
	_power_source_option.item_selected.connect(_on_form_item_selected)
	_resistance_spin.value_changed.connect(_on_training_value_changed)
	_intensity_spin.value_changed.connect(_on_training_value_changed)
	_steepness_slider.value_changed.connect(_on_steepness_changed)
	_override_check.toggled.connect(set_override_local)
	_intervals_key_button.pressed.connect(open_key_dialog)
	_intervals_sync_button.pressed.connect(_on_sync_pressed)
	_intervals_forget_button.pressed.connect(forget_intervals)
	_intervals_dot.draw.connect(_draw_intervals_dot)
	_key_dialog.submitted.connect(_on_key_submitted)
	_strava_connect_button.connect_requested.connect(start_strava_connect)
	_strava_connect_button.disconnect_requested.connect(disconnect_strava)
	_strava_connect_button.set_available(false)
	_reset_store_button.pressed.connect(request_reset_store)
	_reset_store_dialog.confirmed.connect(confirm_reset_store)
	_reset_store_dialog.canceled.connect(cancel_reset_store)
	_reset_store_dialog.get_ok_button().theme_type_variation = &"DangerButton"
	_licenses_button.pressed.connect(open_licenses)
	_scroll.follow_focus = true
	_scroll.get_v_scroll_bar().value_changed.connect(_on_scrolled)
	_attach_touch_targets()
	var scale_source := TouchTarget.default_runtime()
	if scale_source != null:
		scale_source.scale_changed.connect(_on_scale_changed)
	get_viewport().size_changed.connect(_update_layout)
	if _repo != null:
		refresh()
	else:
		refresh_texts_static()
	_update_layout()
	scroll_to_top()


func _exit_tree() -> void:
	var scale_source := TouchTarget.default_runtime()
	if scale_source != null and scale_source.scale_changed.is_connected(_on_scale_changed):
		scale_source.scale_changed.disconnect(_on_scale_changed)
	var viewport := get_viewport()
	if viewport != null and viewport.size_changed.is_connected(_update_layout):
		viewport.size_changed.disconnect(_update_layout)


func _enter_tree() -> void:
	# Повторный вход в дерево (переподвешивание экрана): подписки сняты в `_exit_tree`.
	if not is_node_ready():
		return
	var scale_source := TouchTarget.default_runtime()
	if scale_source != null and not scale_source.scale_changed.is_connected(_on_scale_changed):
		scale_source.scale_changed.connect(_on_scale_changed)
	if not get_viewport().size_changed.is_connected(_update_layout):
		get_viewport().size_changed.connect(_update_layout)


func _notification(what: int) -> void:
	# Экран открывается прокрученным в начало (UIX-04 крит. 3).
	if what == NOTIFICATION_VISIBILITY_CHANGED and is_node_ready() and is_visible_in_tree():
		_update_layout()
		scroll_to_top()


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
	refresh_texts_static()
	_render_store_warning()
	_render_notice()
	_render_locale()
	_render_power_source_items()
	_render_profile_status()
	_render_profile_chip()
	_render_sources()
	_render_intervals()
	_render_strava()
	_render_about()
	_update_save_enabled()


## Тексты, не зависящие от данных: подписи, заголовки разделов, навигация.
func refresh_texts_static() -> void:
	if not is_node_ready():
		return
	_render_static()
	_render_nav_texts()
	_apply_steepness_text()
	_licenses_dialog.title = tr(SettingsSections.LICENSES_TITLE)


func _render_static() -> void:
	for texts: Dictionary in [STATIC_TEXTS, SettingsSections.TEXTS]:
		for path: String in texts:
			var node := get_node_or_null(path)
			if node != null:
				node.set("text", tr(texts[path]))


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
	_profile_status_label.text = tr("ui.settings.no_profile") if p == null else tr("ui.settings.profile_title").format({"name": p.name})


## Fill the form fields from the active profile (overwrites unsaved input).
func _render_profile_form() -> void:
	var p := _active()
	_rendering = true
	if p == null:
		_name_edit.text = ""
	else:
		_name_edit.text = p.name
		_ftp_spin.value = p.ftp_w
		_weight_spin.value = p.weight_kg
		_max_hr_spin.value = p.max_hr
		_resistance_spin.value = p.resistance_level_default
		_intensity_spin.value = p.intensity_default
		_steepness_slider.value = p.sim_steepness_pct
		_power_source_option.select(maxi(POWER_SOURCE_IDS.find(p.power_source), 0))
		_override_check.set_pressed_no_signal(p.intervals_override_local)
	_rendering = false
	_apply_steepness_text()
	_profile_error_label.visible = false
	_profile_error_label.text = ""
	_show_training_errors([])
	_update_save_enabled()


func _render_sources() -> void:
	var p := _active()
	_hr_zones_banner.visible = p != null
	if p == null:
		_sources_label.text = ""
		return
	_sources_label.text = tr("ui.settings.sources").format({
		"ftp": source_text(p.ftp_source), "zones": source_text(p.zones_source)})
	# Зоны пульса недоступны — баннер-предупреждение, а не строка текста (`ui.md` п. 8.6).
	if p.has_hr_zones():
		_hr_zones_banner.show_banner(Banner.Kind.INFO, HR_ZONES_AVAILABLE_KEY, "", "check")
	else:
		_hr_zones_banner.show_banner(Banner.Kind.WARN, HR_ZONES_UNAVAILABLE_KEY, "", UiIcons.BANNER_WARN)


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
	_intervals_dot.set_meta(&"linked", linked)
	_intervals_dot.queue_redraw()
	_intervals_key_button.disabled = p == null
	_intervals_sync_button.disabled = not (client != null and client.is_configured())
	_intervals_forget_button.disabled = not linked
	_override_check.disabled = p == null
	_intervals_message_label.text = _sync_message()
	_intervals_message_label.visible = not _intervals_message_label.text.is_empty()


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
		tr(SettingsSections.LICENSE_INTER),
		tr(SettingsSections.LICENSE_LUCIDE),
		tr("ui.settings.licenses_doc").format({"path": LICENSES_DOC}),
	]
	_licenses_label.text = "\n".join(lines)
	_privacy_doc_label.text = tr(SettingsSections.PRIVACY_DOC).format({"path": PRIVACY_POLICY_DOC})


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
## The language is applied even if saving fails; then a notice says it was not saved
## (`AppState.last_settings_error()`), and a later successful save removes the notice.
func set_locale(locale: String) -> bool:
	if _app_state == null or not _app_state.set_locale(locale):
		return false
	if _app_state.last_settings_error() != OK:
		_notice_key = LOCALE_SAVE_FAILED_KEY
	elif _notice_key == LOCALE_SAVE_FAILED_KEY:
		_notice_key = ""
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
	_rendering = true
	_name_edit.text = profile_name
	_ftp_spin.value = ftp_w
	_weight_spin.value = weight_kg
	_max_hr_spin.value = max_hr
	if resistance_pct >= 0:
		_resistance_spin.value = resistance_pct
	if not power_source.is_empty():
		_power_source_option.select(maxi(POWER_SOURCE_IDS.find(power_source), 0))
	_rendering = false
	_update_save_enabled()


## Save the form into the active profile (profile and training fields). Returns error codes
## (empty = saved).
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
	p.power_source = POWER_SOURCE_IDS[clampi(_power_source_option.selected, 0, POWER_SOURCE_IDS.size() - 1)]
	_apply_training_fields(p)
	var errors := _repo.save(p)
	if errors.is_empty():
		_apply_power_source(p)
		refresh()
		_profile_status_label.text = tr("ui.settings.profile_saved").format({"name": p.name})
	else:
		_show_profile_errors(errors)
	return errors


## Профиль в форме отличается от сохранённого (кнопка «Сохранить профиль» активна).
func is_profile_form_dirty() -> bool:
	var p := _active()
	if p == null:
		return false
	return _name_edit.text != p.name \
		or int(_ftp_spin.value) != p.ftp_w \
		or not is_equal_approx(_weight_spin.value, p.weight_kg) \
		or int(_max_hr_spin.value) != p.max_hr \
		or POWER_SOURCE_IDS[clampi(_power_source_option.selected, 0, POWER_SOURCE_IDS.size() - 1)] != p.power_source


## Сохранить раздел «Тренировка» (сопротивление вне ERG, интенсивность, крутизна SIM) в
## активный профиль, не трогая несохранённые поля профиля. Возвращает коды ошибок.
func save_training() -> Array[String]:
	var active := _active()
	if active == null:
		return [ProfileRepository.ERR_PROFILE_NOT_FOUND]
	var p := active.duplicate_profile()
	_apply_training_fields(p)
	var errors := _repo.save(p)
	_show_training_errors(errors)
	return errors


## Крутизна SIM по умолчанию на слайдере, %.
func steepness_pct() -> int:
	return int(_steepness_slider.value)


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
	return _hr_zones_banner.text_label().text


func _show_profile_errors(codes: Array[String]) -> void:
	_profile_error_label.text = _error_lines(codes)
	_profile_error_label.visible = not codes.is_empty()


func _show_training_errors(codes: Array[String]) -> void:
	_training_error_label.text = _error_lines(codes)
	_training_error_label.visible = not codes.is_empty()


func _error_lines(codes: Array[String]) -> String:
	var lines: Array[String] = []
	for code in codes:
		lines.append(tr(ERROR_KEY_PREFIX + code))
	return "\n".join(lines)


func _apply_training_fields(p: Profile) -> void:
	p.resistance_level_default = int(_resistance_spin.value)
	p.intensity_default = int(_intensity_spin.value)
	p.sim_steepness_pct = Profile.snap_sim_steepness(_steepness_slider.value)


func _apply_power_source(p: Profile) -> void:
	if _connections != null and _connections.hub != null:
		_connections.hub.set_power_source(p.power_source)


func _update_save_enabled() -> void:
	_save_button.disabled = not is_profile_form_dirty()


func _on_form_text_changed(_text: String) -> void:
	_update_save_enabled()


func _on_form_value_changed(_value: float) -> void:
	_update_save_enabled()


func _on_form_item_selected(_index: int) -> void:
	_update_save_enabled()


func _on_training_value_changed(_value: float) -> void:
	if not _rendering:
		save_training()


func _on_steepness_changed(value: float) -> void:
	var pct := Profile.snap_sim_steepness(value)
	if not is_equal_approx(value, pct):
		_steepness_slider.set_value_no_signal(pct)
	_apply_steepness_text()
	if not _rendering:
		save_training()


func _apply_steepness_text() -> void:
	_steepness_value.text = "%d %s" % [steepness_pct(), tr(UNIT_PCT_KEY)]


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
		_set_intervals_message(tr("ui.settings.key_saved").format({"name": athlete_name}))
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
		ApiResult.CODE_STORAGE_FAILED:
			return tr("ui.settings.key_save_failed").format({"reason": api_error_text(code)})
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
	_set_intervals_message(tr("ui.settings.intervals_unlinked"))


func intervals_status_text() -> String:
	return _intervals_status_label.text


func intervals_message_text() -> String:
	return _intervals_message_label.text


func key_dialog() -> IntervalsKeyDialog:
	return _key_dialog


func _set_intervals_message(text: String) -> void:
	_intervals_message_label.text = text
	_intervals_message_label.visible = not text.is_empty()


func _draw_intervals_dot() -> void:
	var linked: bool = _intervals_dot.get_meta(&"linked", false)
	var color := UiTokens.ACCENT if linked else UiTokens.TEXT_DISABLED
	_intervals_dot.draw_circle(_intervals_dot.size * 0.5, STATUS_DOT_DIAMETER * 0.5, color, true, -1.0, true)


# ---------------------------------------------------------------------------
# Secure store (REQ-NFR-05): unreadable store -> warning and "reset links"
# ---------------------------------------------------------------------------

## The secret store exists but could not be read (e.g. the device key changed): reads give
## empty values and writes are refused, so links look missing and cannot be re-created.
func is_store_unreadable() -> bool:
	return _store != null and not _store.loaded_ok()


func is_store_warning_visible() -> bool:
	return _store_warning.visible


func store_warning_text() -> String:
	return _store_warning_label.text if _store_warning.visible else ""


## Screen-level notice text ("" — none): store reset result or unsaved language.
func notice_text() -> String:
	return _notice_label.text


func _set_notice(key: String) -> void:
	_notice_key = key
	_render_notice()


func _render_notice() -> void:
	var shown := not _notice_key.is_empty()
	_notice_banner.show_banner(NOTICE_KINDS.get(_notice_key, Banner.Kind.INFO), _notice_key)
	_notice_label.visible = shown
	_notice_banner.visible = shown


func _render_store_warning() -> void:
	_store_warning.show_banner(Banner.Kind.ERROR, STORE_WARNING_KEY, STORE_RESET_KEY, UiIcons.BANNER_ERROR)
	_store_warning.visible = is_store_unreadable()
	_reset_store_button.disabled = not is_store_unreadable()
	_reset_store_dialog.title = tr("ui.settings.store_reset")
	_reset_store_dialog.dialog_text = tr("ui.settings.store_reset_confirm")
	_reset_store_dialog.ok_button_text = tr("ui.settings.store_reset_confirm_ok")
	_reset_store_dialog.cancel_button_text = tr("ui.common.cancel")


## "Reset links": ask for confirmation first. false — nothing to reset.
func request_reset_store() -> bool:
	if not is_store_unreadable():
		return false
	_reset_pending = true
	_render_store_warning()
	_reset_store_dialog.popup_centered()
	return true


## Confirmed reset: wipe the store (`SecureStore.reset_store`) and re-render; Strava and
## Intervals.icu then show as not linked. The local profile data are untouched.
func confirm_reset_store() -> void:
	if not _reset_pending:
		return
	_reset_pending = false
	if _reset_store_dialog.visible:
		_reset_store_dialog.hide()
	if _store == null:
		return
	_store.reset_store()
	_last_sync_result = null
	_last_sync_warnings = []
	refresh_texts()
	_set_notice(STORE_RESET_DONE_KEY if _store.loaded_ok() else STORE_RESET_FAILED_KEY)


func cancel_reset_store() -> void:
	_reset_pending = false
	if _reset_store_dialog.visible:
		_reset_store_dialog.hide()


func is_reset_store_pending() -> bool:
	return _reset_pending


# ---------------------------------------------------------------------------
# «О программе»
# ---------------------------------------------------------------------------

## Открыть лист лицензий.
func open_licenses() -> void:
	_licenses_dialog.title = tr(SettingsSections.LICENSES_TITLE)
	_licenses_dialog.ok_button_text = tr("ui.common.ok")
	_licenses_dialog.popup_centered()


func version_text() -> String:
	return _version_label.text


func licenses_text() -> String:
	return _licenses_label.text


func privacy_text() -> String:
	return _privacy_doc_label.text


func strava_status_text() -> String:
	return _strava_status_label.text


# ---------------------------------------------------------------------------
# Navigation
# ---------------------------------------------------------------------------

func switch_profile() -> void:
	if _app_state != null:
		_app_state.switch_profile()


## «Назад»: на экран, с которого пришли (REQ-UIX-04 крит. 1).
func back() -> void:
	_app_bar.press_back()


func app_bar() -> AppBar:
	return _app_bar


func is_compact() -> bool:
	return _compact


## id разделов в порядке на экране (по порядку узлов в содержимом, сверху вниз).
func section_ids() -> Array[String]:
	var by_node: Dictionary = {}
	for section in SettingsSections.ORDER:
		var node := get_node_or_null(str(section["node"]))
		if node != null:
			by_node[node] = str(section["id"])
	var out: Array[String] = []
	for child in _content.get_children():
		if by_node.has(child):
			out.append(by_node[child])
	return out


## Узел раздела по id (заголовок + карточка).
func section_node(id: String) -> Control:
	var section := SettingsSections.find(id)
	return get_node_or_null(str(section.get("node", ""))) as Control


## Заголовок раздела (вариация H2 темы).
func section_title(id: String) -> Label:
	var node := section_node(id)
	return node.get_node_or_null("Title") as Label if node != null else null


func nav_button(id: String) -> Button:
	return _nav_buttons.get(id, null)


## Выбранный в навигации раздел ("" — нет).
func selected_section() -> String:
	for id: String in _nav_buttons:
		if (_nav_buttons[id] as Button).button_pressed:
			return id
	return ""


func scroll_container() -> ScrollContainer:
	return _scroll


## Прокрутить содержимое к разделу и выделить его в навигации.
func scroll_to_section(id: String) -> void:
	var node := section_node(id)
	if node == null:
		return
	_scroll.scroll_vertical = int(node.position.y)
	_select_nav(id)


func scroll_to_top() -> void:
	_scroll.scroll_vertical = 0
	_select_nav(str(SettingsSections.ORDER[0]["id"]))


# ---------------------------------------------------------------------------
# Навигация по разделам и раскладка
# ---------------------------------------------------------------------------

func _build_nav() -> void:
	for section in SettingsSections.ORDER:
		var id: String = section["id"]
		var button := Button.new()
		button.name = "Nav_" + id
		button.theme_type_variation = &"GhostButton"
		button.toggle_mode = true
		button.button_group = _nav_group
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		button.icon = UiIcons.icon(str(section["icon"]))
		button.pressed.connect(scroll_to_section.bind(id))
		button.draw.connect(_draw_nav_marker.bind(button))
		button.toggled.connect(_on_nav_toggled.bind(button))
		_nav.add_child(button)
		TouchTarget.attach(button, TouchTarget.Kind.UI, Vector2(0, NAV_ROW_HEIGHT))
		_nav_buttons[id] = button


func _render_nav_texts() -> void:
	for section in SettingsSections.ORDER:
		var button: Button = _nav_buttons.get(section["id"])
		if button != null:
			button.text = tr(str(section["title"]))


func _select_nav(id: String) -> void:
	if not _nav_buttons.has(id):
		return
	# `set_pressed_no_signal` не снимает выбор с остальных кнопок группы — снимаем сами.
	for other_id: String in _nav_buttons:
		var other: Button = _nav_buttons[other_id]
		var pressed := other_id == id
		if other.button_pressed != pressed:
			other.set_pressed_no_signal(pressed)
			other.queue_redraw()


func _on_nav_toggled(_on: bool, button: Button) -> void:
	button.queue_redraw()


## Полоса `accent` слева у выбранного раздела (`ui.md` п. 8.6).
func _draw_nav_marker(button: Button) -> void:
	if not button.button_pressed:
		return
	var height := maxf(button.size.y - NAV_MARKER_INSET * 2.0, 0.0)
	button.draw_rect(Rect2(0.0, NAV_MARKER_INSET, NAV_MARKER_WIDTH, height), UiTokens.ACCENT)


## Прокрутка: в навигации выделяется раздел, заголовок которого последним ушёл за верх.
func _on_scrolled(_value: float) -> void:
	var top := float(_scroll.scroll_vertical) + NAV_SYNC_SLACK
	var current: String = str(SettingsSections.ORDER[0]["id"])
	for section in SettingsSections.ORDER:
		var node := get_node_or_null(str(section["node"])) as Control
		if node != null and node.position.y <= top:
			current = section["id"]
	var bar := _scroll.get_v_scroll_bar()
	if bar.visible and bar.value >= bar.max_value - bar.page - 1.0:
		current = str(SettingsSections.ORDER[-1]["id"])
	_select_nav(current)


func _build_profile_chip() -> void:
	_profile_chip = Button.new()
	_profile_chip.name = "SwitchProfileButton"
	_profile_chip.theme_type_variation = &"ChipButton"
	_profile_chip.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_profile_chip.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_profile_chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_chip_placeholder = ImageTexture.create_from_image(Image.create_empty(int(CHIP_AVATAR_DIAMETER), int(CHIP_AVATAR_DIAMETER), false, Image.FORMAT_RGBA8))
	_profile_chip.icon = _chip_placeholder
	_profile_chip.pressed.connect(switch_profile)
	_profile_chip.draw.connect(_draw_chip_avatar)
	_app_bar.add_action(_profile_chip)
	_expose(_profile_chip, "SwitchProfileButton")
	TouchTarget.attach(_profile_chip, TouchTarget.Kind.UI)


## Фишка профиля: «Имя · FTP Вт» (compact — только имя), подсказка — «Сменить профиль».
func _render_profile_chip() -> void:
	var p := _active()
	if p == null:
		_profile_chip.text = "—"
	elif _compact:
		_profile_chip.text = p.name
	else:
		_profile_chip.text = "%s · %d %s" % [p.name, p.ftp_w, tr(UNIT_W_KEY)]
	_profile_chip.tooltip_text = tr(SWITCH_PROFILE_KEY)
	_profile_chip.queue_redraw()


func profile_chip() -> Button:
	return _profile_chip


func _draw_chip_avatar() -> void:
	var p := _active()
	if p == null:
		return
	var box := _profile_chip.get_theme_stylebox("normal")
	var left: float = box.get_margin(SIDE_LEFT) if box != null else 0.0
	var center := Vector2(left + CHIP_AVATAR_DIAMETER * 0.5, _profile_chip.size.y * 0.5)
	ProfileAvatar.draw_on(_profile_chip, center, CHIP_AVATAR_DIAMETER, p.id, p.name)


## Цели нажатия (`touch_ui`, UIX-05 крит. 1): основные и вторичные кнопки — `Kind.BUTTON`,
## поля, переключатели и списки — `Kind.UI`. Кнопка Strava — по брендбуку Strava со своими
## размерами (исключение UIX-01), помощник к ней не цепляется.
func _attach_touch_targets() -> void:
	for button: Button in [_save_button, _intervals_key_button, _intervals_sync_button,
			_intervals_forget_button, _licenses_button]:
		TouchTarget.attach(button, TouchTarget.Kind.BUTTON)
	# Поле `SpinBox` фокусируется внутренним `LineEdit`: высоту цели задаёт сам `SpinBox`.
	for spin: SpinBox in [_ftp_spin, _weight_spin, _max_hr_spin, _resistance_spin, _intensity_spin]:
		TouchTarget.attach(spin, TouchTarget.Kind.UI)
	for section in SettingsSections.ORDER:
		var node := get_node_or_null(str(section["node"]))
		if node == null:
			continue
		for child in node.get_children():
			if child != _strava_connect_button.get_parent().get_parent():
				TouchTarget.attach_all(child, TouchTarget.Kind.UI)


func _on_scale_changed(_scale: float) -> void:
	_update_layout()


## Раскладка по ширине холста: regular — навигация слева и содержимое до 720 lp, compact —
## один столбец. Отступы корня — безопасная зона (`UiScale.safe_margins`, UIX-05 крит. 2).
func _update_layout() -> void:
	if not is_node_ready() or not is_inside_tree():
		return
	var safe := Vector4.ZERO
	var scale_source := TouchTarget.default_runtime()
	if scale_source != null:
		safe = scale_source.safe_margins()
	_root.offset_left = safe.x
	_root.offset_top = safe.y
	_root.offset_right = -safe.z
	_root.offset_bottom = -safe.w
	var canvas := get_viewport_rect().size
	var compact := canvas.x < COMPACT_MAX_WIDTH
	_compact = compact
	_margin.theme_type_variation = &"ScreenMarginCompact" if compact else &"ScreenMargin"
	_nav.visible = not compact
	var available := canvas.x - safe.x - safe.z \
		- float(_margin.get_theme_constant("margin_left")) - float(_margin.get_theme_constant("margin_right"))
	var width := minf(available, CONTENT_MAX_WIDTH)
	if not compact:
		width = minf(available, NAV_WIDTH + BODY_GAP + CONTENT_MAX_WIDTH)
	_body.custom_minimum_size.x = maxf(width, 0.0)
	_update_intervals_buttons(width - (0.0 if compact else NAV_WIDTH + BODY_GAP))
	if _repo != null:
		_render_profile_chip()


## Кнопки Intervals.icu в ряд, если помещаются в карточку, иначе столбиком.
func _update_intervals_buttons(content_width: float) -> void:
	var card := _intervals_buttons.get_parent().get_parent() as Control
	var box := card.get_theme_stylebox("panel") if card != null else null
	var inner := content_width - (box.get_margin(SIDE_LEFT) + box.get_margin(SIDE_RIGHT) if box != null else 0.0)
	var needed := 0.0
	var count := 0
	for child in _intervals_buttons.get_children():
		var control := child as Control
		if control != null and control.visible:
			needed += control.get_combined_minimum_size().x
			count += 1
	needed += float(_intervals_buttons.get_theme_constant("separation")) * maxf(count - 1, 0)
	var vertical := needed > inner
	_intervals_buttons.vertical = vertical
	_intervals_buttons.theme_type_variation = &"Stack8" if vertical else &"Row12"


# ---------------------------------------------------------------------------
# Internal
# ---------------------------------------------------------------------------

## Узел внутри компонента (AppBar, баннер) доступен экрану как `%name` (контракт тестов):
## узел переименовывается и переходит во владение экрана.
func _expose(node: Node, unique_name: String) -> Node:
	node.name = unique_name
	node.owner = self
	node.unique_name_in_owner = true
	return node


func _active() -> Profile:
	return _repo.get_active() if _repo != null else null


func _client(p: Profile) -> IntervalsIcuClient:
	if p == null or _transport == null or _store == null:
		return null
	return IntervalsIcuClient.for_profile(_transport, _store, p)
