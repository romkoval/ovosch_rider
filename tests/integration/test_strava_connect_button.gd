extends GutTest
## Тесты StravaConnectButton и Strava-секции настроек (REQ-STR-01 крит. 7/9 — брендбук; T-049).

const SCENE: String = "res://src/ui/common/strava_connect_button.tscn"


func _button() -> StravaConnectButton:
	var b: StravaConnectButton = load(SCENE).instantiate()
	add_child_autofree(b)
	return b


func test_unauthorized_state_is_brand_orange_48px_connect_with_strava() -> void:
	var b := _button()
	assert_eq(b.button_text(), "Connect with Strava", "текст по брендбуку, не переводится")
	assert_eq(b.brand_color(), StravaBranding.BRAND_COLOR, "оранжевый #FC5200")
	assert_eq(StravaBranding.BRAND_COLOR.to_html(false).to_upper(), "FC5200")
	assert_eq(int((b.get_node("%Button") as Button).custom_minimum_size.y), 48, "высота 48 px")
	assert_false(b.is_authorized())
	assert_eq((b.get_node("%PoweredBy") as Label).text, "Powered by Strava")


func test_authorized_state_shows_disconnect_text() -> void:
	var b := _button()
	b.set_authorized(true)
	assert_true(b.is_authorized())
	assert_eq(b.button_text(), tr("ui.settings.strava_disconnect"))
	assert_ne(b.brand_color(), StravaBranding.BRAND_COLOR, "нейтральный стиль при привязке")
	b.set_authorized(false)
	assert_eq(b.button_text(), "Connect with Strava")


func test_pressed_emits_connect_or_disconnect_request() -> void:
	var b := _button()
	var events: Array[String] = []
	b.connect_requested.connect(func() -> void: events.append("connect"))
	b.disconnect_requested.connect(func() -> void: events.append("disconnect"))
	(b.get_node("%Button") as Button).pressed.emit()
	b.set_authorized(true)
	(b.get_node("%Button") as Button).pressed.emit()
	assert_eq(events, ["connect", "disconnect"])


func test_authorize_url_link_busy_and_availability() -> void:
	var b := _button()
	assert_eq(b.authorize_url(), "")
	b.set_authorize_url("https://www.strava.com/oauth/authorize?x=1")
	assert_eq(b.authorize_url(), "https://www.strava.com/oauth/authorize?x=1")
	assert_true((b.get_node("%OpenLink") as LinkButton).visible, "ссылка на вход видна")
	assert_eq((b.get_node("%OpenLink") as LinkButton).uri, "https://www.strava.com/oauth/authorize?x=1")
	b.set_authorized(true)
	assert_eq(b.authorize_url(), "", "после привязки ссылка скрыта")
	b.set_busy(true)
	assert_true(b.is_button_disabled())
	b.set_busy(false)
	assert_false(b.is_button_disabled())
	b.set_available(false)
	assert_true(b.is_button_disabled(), "без client_id/secret кнопка выключена")


func test_settings_screen_uses_component_and_service_state() -> void:
	var dir := "user://test_strava_settings_%d/" % Time.get_ticks_usec()
	var screen: SettingsScreen = load("res://src/ui/settings/settings_screen.tscn").instantiate()
	var repo := ProfileRepository.new(dir + "profiles/")
	var profile := repo.create("Даша")
	var store := MemorySecureStore.new()
	var mock := MockHttpTransport.new()
	var app_state := AppState.new(repo)
	screen.setup(repo, app_state, store, mock)
	add_child_autofree(screen)
	assert_true(screen.strava_button() is StravaConnectButton, "заглушка заменена компонентом")
	assert_true(screen.strava_button().is_button_disabled(), "без сервиса — выключена")
	var rides := FileRideRepository.new(dir + "rides/")
	var service := StravaService.new(profile, mock, store, rides, StravaConfig.from_values("1", "fixture-secret"), Callable(), dir)
	service.oauth.base_url = "https://mock.strava.test"
	screen.set_strava_service(service)
	assert_false(screen.strava_button().is_button_disabled(), "с настроенным сервисом — доступна")
	assert_eq(screen.strava_status_text(), tr("ui.settings.strava_not_linked"))
	screen.start_strava_connect()
	assert_true(screen.strava_button().authorize_url().begins_with("https://mock.strava.test/oauth/authorize?"), "URL входа показан ссылкой")
	assert_eq(screen.strava_status_text(), tr("ui.settings.strava_connecting"))
	service.connect_flow_cancel()
	store.set_secret(service.oauth.secret_key(SecureStore.ITEM_REFRESH_TOKEN), "fixture-refresh")
	service.authorized_changed.emit(true)
	assert_true(screen.strava_button().is_authorized())
	assert_eq(screen.strava_status_text(), tr("ui.settings.strava_linked"))
	var unavailable := StravaService.new(profile, mock, store, rides, StravaConfig.load("user://nonexistent_fixture.cfg"), Callable(), dir)
	screen.set_strava_service(unavailable)
	assert_true(screen.strava_button().is_button_disabled())
	assert_eq(screen.strava_status_text(), tr("ui.settings.strava_unavailable"), "REQ-STR-01 крит. 6: понятное сообщение")
	service.dispose()
	unavailable.dispose()
	var abs := ProjectSettings.globalize_path(dir)
	for sub in ["profiles", "rides"]:
		var d := DirAccess.open(abs.path_join(sub))
		if d != null:
			for f in d.get_files():
				DirAccess.remove_absolute(abs.path_join(sub).path_join(f))
			DirAccess.remove_absolute(abs.path_join(sub))
	DirAccess.remove_absolute(abs)
