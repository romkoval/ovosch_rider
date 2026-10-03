extends GutTest
## Независимая приёмка пакета публикации и портов (тестировщик, T-053/T-055, коммит 7319347).
## По одному тесту на критерий `[авто]`: REQ-NFR-07 крит. 1–4, REQ-NFR-06 крит. 4, REQ-NFR-05 крит. 3,
## REQ-STR-01 крит. 6, 7, 9, REQ-INT-01 крит. 5, REQ-IMP-03 крит. 3. Проверяется наличие файлов и разделов
## по формулировкам критериев; содержательная часть и ревью магазинов — `[вне контейнера]`.

const PRIVACY: String = "res://docs/publishing/privacy_policy.md"
const APP_STORE: String = "res://docs/publishing/app_store_checklist.md"
const STRAVA: String = "res://docs/publishing/strava_api_checklist.md"
const INTERVALS_OAUTH: String = "res://docs/publishing/intervals_icu_oauth.md"
const LICENSES: String = "res://docs/publishing/licenses.md"
const SECURE_STORE: String = "res://docs/secure_store.md"
const PORTS_README: String = "res://docs/ports/README.md"
const PORTS_ANDROID: String = "res://docs/ports/android.md"
const IOS_PLIST: String = "res://platform/ios/Info.plist.template"
const MACOS_PLIST: String = "res://platform/macos/Info.plist.template"
const ANDROID_MANIFEST: String = "res://platform/android/AndroidManifest.template.xml"
const SECRETS_EXAMPLE: String = "res://secrets.example.cfg.txt"
const BLE_BACKEND_H: String = "res://native/ble/src/ble_backend.h"


func _read(path: String) -> String:
	assert_true(FileAccess.file_exists(path), "файл существует: %s" % path)
	if not FileAccess.file_exists(path):
		return ""
	var text := FileAccess.get_file_as_string(path)
	assert_false(text.strip_edges().is_empty(), "файл непустой: %s" % path)
	return text


func _has_all(text: String, needles: Array, what: String) -> void:
	for needle in needles:
		assert_true(text.containsn(needle), "%s: содержит «%s»" % [what, needle])


## Значение <string> после <key>NAME</key>; "" если ключа нет.
func _plist_string(text: String, key: String) -> String:
	var regex := RegEx.new()
	regex.compile("<key>%s</key>\\s*<string>([^<]*)</string>" % key)
	var m := regex.search(text)
	return m.get_string(1).strip_edges() if m else ""


## Элемент <uses-permission android:name="android.permission.NAME" .../> целиком; "" если нет.
func _permission(text: String, name: String) -> String:
	var regex := RegEx.new()
	regex.compile("<uses-permission[^>]*android:name=\"android\\.permission\\.%s\"[^>]*/>" % name)
	var m := regex.search(text)
	return m.get_string(0) if m else ""


# REQ-NFR-07 крит. 1: политика конфиденциальности — какие данные (пульс — здоровье), где хранятся,
# куда передаются (Intervals.icu, Strava), как удалить.
func test_req_nfr_07_c1_privacy_policy_has_required_sections() -> void:
	var text := _read(PRIVACY)
	_has_all(text, ["Какие данные", "Где хранятся", "Куда и когда передаются", "Удаление данных"], "политика (ru): разделы")
	_has_all(text, ["Data the app processes", "Where data is stored", "Where and when data is transmitted", "Deleting data"],
		"политика (en): разделы")
	_has_all(text, ["пульс", "здоровь", "Intervals.icu", "Strava", "Keychain", "heart rate", "health"], "политика: содержание")


# REQ-NFR-07 крит. 2: NSBluetoothAlwaysUsageDescription с непустым текстом на ru и en (iOS и macOS).
func test_req_nfr_07_c2_bluetooth_usage_description_ru_and_en_in_ios_and_macos_templates() -> void:
	for path in [IOS_PLIST, MACOS_PLIST]:
		var text := _read(path)
		var en := _plist_string(text, "NSBluetoothAlwaysUsageDescription")
		assert_false(en.is_empty(), "%s: ключ с непустым английским текстом" % path)
		assert_true(en.containsn("Bluetooth"), "%s: en-текст объясняет Bluetooth: «%s»" % [path, en])
		var ru_regex := RegEx.new()
		ru_regex.compile("\"NSBluetoothAlwaysUsageDescription\"\\s*=\\s*\"([^\"]+)\"")
		var ru := ru_regex.search(text)
		assert_not_null(ru, "%s: русский текст для InfoPlist.strings присутствует" % path)
		if ru != null:
			assert_true(ru.get_string(1).contains("Bluetooth") and ru.get_string(1).contains("использует"),
				"%s: ru-текст непустой и осмысленный: «%s»" % [path, ru.get_string(1)])


# REQ-NFR-07 крит. 3: BLUETOOTH_SCAN (neverForLocation), BLUETOOTH_CONNECT, legacy для API < 31.
func test_req_nfr_07_c3_android_manifest_permissions() -> void:
	var text := _read(ANDROID_MANIFEST)
	var scan := _permission(text, "BLUETOOTH_SCAN")
	assert_false(scan.is_empty(), "BLUETOOTH_SCAN объявлен")
	assert_true(scan.contains("neverForLocation"), "BLUETOOTH_SCAN с usesPermissionFlags=neverForLocation")
	assert_false(_permission(text, "BLUETOOTH_CONNECT").is_empty(), "BLUETOOTH_CONNECT объявлен")
	for legacy in ["BLUETOOTH", "BLUETOOTH_ADMIN", "ACCESS_FINE_LOCATION"]:
		var perm := _permission(text, legacy)
		assert_false(perm.is_empty(), "legacy %s объявлен для API < 31" % legacy)
		assert_true(perm.contains("android:maxSdkVersion=\"30\""), "%s ограничен maxSdkVersion=30" % legacy)


# REQ-NFR-07 крит. 4: чеклисты App Store и Android — Privacy Nutrition Labels / Data Safety,
# данные о здоровье, лицензии сторонних компонентов (Godot MIT, GUT MIT).
func test_req_nfr_07_c4_checklists_cover_privacy_labels_health_and_licenses() -> void:
	var app_store := _read(APP_STORE)
	_has_all(app_store, ["Nutrition label", "App Privacy", "Health", "пульс", "licenses.md"], "app_store_checklist.md")
	var android := _read(PORTS_ANDROID)
	_has_all(android, ["Data safety", "Health", "пульс", "licenses.md"], "docs/ports/android.md")
	var licenses := _read(LICENSES)
	_has_all(licenses, ["Godot", "GUT", "MIT"], "licenses.md")


# REQ-NFR-06 крит. 4: в docs/ports/README.md перечислены точки реализации контракта моста для Android, Linux, Windows.
func test_req_nfr_06_c4_ports_readme_lists_backend_contract_points_per_platform() -> void:
	var readme := _read(PORTS_README)
	_has_all(readme, ["BleBackend", "BleListener", "native/ble/src/ble_backend.h", "Android", "Linux", "Windows",
		"android.md", "linux_windows.md"], "docs/ports/README.md")
	assert_true(FileAccess.file_exists("res://docs/ports/linux_windows.md"), "docs/ports/linux_windows.md существует")
	# Каждый метод контракта из заголовка упомянут в README (таблица «Контракт порта»).
	var header := _read(BLE_BACKEND_H)
	var regex := RegEx.new()
	regex.compile("virtual \\w+ (\\w+)\\(")
	var checked := 0
	for m in regex.search_all(header):
		var method := m.get_string(1)
		if method.begins_with("~") or method.begins_with("on_"):
			continue
		checked += 1
		assert_true(readme.contains(method), "README портов упоминает метод контракта %s" % method)
	assert_gt(checked, 0, "в ble_backend.h найдены методы контракта")


# REQ-NFR-05 крит. 3: Keychain (iOS/macOS), Android Keystore, libsecret/Credential Manager описаны в docs/secure_store.md.
func test_req_nfr_05_c3_secure_store_doc_describes_platform_backends() -> void:
	var text := _read(SECURE_STORE)
	_has_all(text, ["Keychain", "iOS", "macOS", "Keystore", "Android", "libsecret", "Linux", "Credential Manager", "Windows",
		"secure_store.gd"], "docs/secure_store.md")


# REQ-STR-01 крит. 6: dev — user://secrets.cfg или окружение, в репозитории только пример с плейсхолдерами;
# магазинные сборки — конфигурация сборки вне репозитория, способ описан в strava_api_checklist.md.
func test_req_str_01_c6_strava_checklist_describes_secret_sources_and_example_has_placeholders_only() -> void:
	var text := _read(STRAVA)
	_has_all(text, ["secrets.cfg", "OVOSCH_STRAVA_CLIENT_ID", "OVOSCH_STRAVA_CLIENT_SECRET", "Client Secret", "магазинные сборки",
		"не попадает"], "strava_api_checklist.md")
	var example := _read(SECRETS_EXAMPLE)
	_has_all(example, ["client_id", "client_secret"], "secrets.example.cfg.txt")
	var value_regex := RegEx.new()
	value_regex.compile("client_secret\\s*=\\s*\"([^\"]*)\"")
	var m := value_regex.search(example)
	if m != null:
		var value := m.get_string(1)
		assert_true(value.is_empty() or value.containsn("placeholder") or value.contains("<") or value.containsn("your"),
			"в примере только плейсхолдер, не значение секрета: «%s»" % value)


# REQ-STR-01 крит. 7: loopback http://127.0.0.1:<port>/callback на десктопе, схема ovoschrider://strava на iOS/Android —
# описано в чеклисте и зарегистрировано в заготовках Info.plist и AndroidManifest.
func test_req_str_01_c7_redirect_loopback_and_url_scheme_documented_and_registered() -> void:
	var text := _read(STRAVA)
	_has_all(text, ["127.0.0.1", "/callback", "ovoschrider://strava"], "strava_api_checklist.md: redirect")
	var ios := _read(IOS_PLIST)
	assert_true(ios.contains("<key>CFBundleURLSchemes</key>") and ios.contains("<string>ovoschrider</string>"),
		"iOS Info.plist: схема ovoschrider зарегистрирована")
	var manifest := _read(ANDROID_MANIFEST)
	assert_true(manifest.contains("android:scheme=\"ovoschrider\""), "AndroidManifest: intent-filter со схемой ovoschrider")


# REQ-STR-01 крит. 9: «Connect with Strava», «Powered by Strava», брендбук, заявка на ревью — в чеклисте.
func test_req_str_01_c9_strava_checklist_covers_brand_and_review() -> void:
	var text := _read(STRAVA)
	_has_all(text, ["Connect with Strava", "Powered by Strava", "Brand Guidelines", "ревью"], "strava_api_checklist.md")


# REQ-INT-01 крит. 5: шаги согласования с разработчиком Intervals.icu, redirect URI и scope.
func test_req_int_01_c5_intervals_oauth_doc_describes_agreement_redirect_and_scope() -> void:
	var text := _read(INTERVALS_OAUTH)
	_has_all(text, ["согласовать с разработчиком Intervals.icu", "redirect URI", "scope", "127.0.0.1", "ovoschrider://intervals",
		"CALENDAR:READ", "SETTINGS:READ", "вне контейнера"], "intervals_icu_oauth.md")


# REQ-IMP-03 крит. 3: типы документов .zwo/.erg/.mrc в заготовках iOS/macOS; чеклист в app_store_checklist.md.
func test_req_imp_03_c3_document_types_declared_in_plists_and_checklist() -> void:
	for path in [IOS_PLIST, MACOS_PLIST]:
		var text := _read(path)
		assert_true(text.contains("<key>CFBundleDocumentTypes</key>"), "%s: CFBundleDocumentTypes" % path)
		assert_true(text.contains("<key>UTExportedTypeDeclarations</key>"), "%s: UTExportedTypeDeclarations" % path)
		for ext in ["zwo", "erg", "mrc"]:
			assert_true(text.contains("<string>%s</string>" % ext), "%s: расширение .%s объявлено" % [path, ext])
	var checklist := _read(APP_STORE)
	_has_all(checklist, ["CFBundleDocumentTypes", ".zwo", ".erg", ".mrc"], "app_store_checklist.md: типы документов")
