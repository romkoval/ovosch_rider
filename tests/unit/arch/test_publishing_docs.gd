extends GutTest
## Пакет публикации и порты — документы и заготовки конфигурации (T-053, T-055):
## REQ-NFR-07 крит. 1–4 (политика, описание Bluetooth, манифест Android, чеклисты),
## REQ-NFR-05 крит. 3 (docs/secure_store.md), REQ-STR-01 крит. 6, 9 (чеклист Strava),
## REQ-INT-01 крит. 5 (OAuth Intervals.icu), REQ-NFR-06 крит. 4 (порты), REQ-IMP-03 крит. 3
## (типы документов в Info.plist). Проверяется только наличие файлов и ключевых разделов/ключей —
## содержательная часть и прохождение ревью остаются `[вне контейнера]`.

const PRIVACY_POLICY: String = "res://docs/publishing/privacy_policy.md"
const APP_STORE_CHECKLIST: String = "res://docs/publishing/app_store_checklist.md"
const STRAVA_CHECKLIST: String = "res://docs/publishing/strava_api_checklist.md"
const INTERVALS_OAUTH: String = "res://docs/publishing/intervals_icu_oauth.md"
const LICENSES: String = "res://docs/publishing/licenses.md"
const SECURE_STORE_DOC: String = "res://docs/secure_store.md"
const PORTS_README: String = "res://docs/ports/README.md"
const PORTS_ANDROID: String = "res://docs/ports/android.md"
const PORTS_LINUX_WINDOWS: String = "res://docs/ports/linux_windows.md"
const PLATFORM_README: String = "res://platform/README.md"
const IOS_PLIST: String = "res://platform/ios/Info.plist.template"
const MACOS_PLIST: String = "res://platform/macos/Info.plist.template"
const MACOS_ENTITLEMENTS: String = "res://platform/macos/entitlements.template.plist"
const ANDROID_MANIFEST: String = "res://platform/android/AndroidManifest.template.xml"
const GITIGNORE: String = "res://.gitignore"

const ALL_FILES: Array[String] = [
	PRIVACY_POLICY, APP_STORE_CHECKLIST, STRAVA_CHECKLIST, INTERVALS_OAUTH, LICENSES,
	SECURE_STORE_DOC, PORTS_README, PORTS_ANDROID, PORTS_LINUX_WINDOWS, PLATFORM_README,
	IOS_PLIST, MACOS_PLIST, MACOS_ENTITLEMENTS, ANDROID_MANIFEST,
]

## Текст NSBluetoothAlwaysUsageDescription должен быть непустым на обоих языках (REQ-NFR-07 крит. 2).
const BLUETOOTH_KEY: String = "NSBluetoothAlwaysUsageDescription"


func _read(path: String) -> String:
	assert_true(FileAccess.file_exists(path), "файл существует: %s" % path)
	return FileAccess.get_file_as_string(path)


## Значение <string> сразу после <key>NAME</key> в plist-тексте; "" если ключа нет.
func _plist_string(text: String, key: String) -> String:
	var regex := RegEx.new()
	regex.compile("<key>%s</key>\\s*<string>([^<]*)</string>" % key)
	var m := regex.search(text)
	return m.get_string(1).strip_edges() if m else ""


## Разрешение <uses-permission android:name="NAME" .../> — полный текст элемента; "" если нет.
func _manifest_permission(text: String, name: String) -> String:
	var regex := RegEx.new()
	regex.compile("<uses-permission[^>]*android:name=\"android\\.permission\\.%s\"[^>]*/>" % name)
	var m := regex.search(text)
	return m.get_string(0) if m else ""


func test_req_nfr_07_all_publishing_and_port_files_exist() -> void:
	for path in ALL_FILES:
		assert_true(FileAccess.file_exists(path), "файл пакета публикации/портов существует: %s" % path)
		assert_false(FileAccess.get_file_as_string(path).strip_edges().is_empty(), "файл непустой: %s" % path)


func test_req_nfr_07_c1_privacy_policy_has_ru_and_en_sections() -> void:
	var text := _read(PRIVACY_POLICY)
	assert_true(text.contains("\n## Политика конфиденциальности"), "раздел на русском «## Политика конфиденциальности»")
	assert_true(text.contains("\n## Privacy Policy"), "раздел на английском «## Privacy Policy»")
	assert_true(text.find("## Политика конфиденциальности") < text.find("## Privacy Policy"), "русская версия идёт первой")


func test_req_nfr_07_c1_privacy_policy_covers_health_storage_transfer_deletion() -> void:
	var text := _read(PRIVACY_POLICY)
	for needle in ["пульс", "здоровье", "Keychain", "Intervals.icu", "Strava", "Удаление данных", "Deleting data", "heart rate", "health data"]:
		assert_true(text.containsn(needle), "политика упоминает «%s»" % needle)
	assert_true(text.contains("не ведёт аналитику") and text.contains("no usage analytics"),
		"политика явно говорит об отсутствии аналитики на обоих языках")


func test_req_nfr_07_c2_ios_plist_has_bluetooth_usage_description() -> void:
	var text := _read(IOS_PLIST)
	var en := _plist_string(text, BLUETOOTH_KEY)
	assert_false(en.is_empty(), "iOS: %s с непустым текстом (en)" % BLUETOOTH_KEY)
	assert_true(en.containsn("Bluetooth"), "iOS: английский текст объясняет назначение Bluetooth")
	assert_true(text.contains("\"%s\" = \"" % BLUETOOTH_KEY) and text.contains("использует Bluetooth"),
		"iOS: русский текст описания для InfoPlist.strings присутствует и непустой")


func test_req_nfr_07_c2_macos_plist_has_bluetooth_usage_description_and_category() -> void:
	var text := _read(MACOS_PLIST)
	var en := _plist_string(text, BLUETOOTH_KEY)
	assert_false(en.is_empty(), "macOS: %s с непустым текстом (en)" % BLUETOOTH_KEY)
	assert_true(text.contains("использует Bluetooth"), "macOS: русский текст описания присутствует")
	assert_eq(_plist_string(text, "LSApplicationCategoryType"), "public.app-category.healthcare-fitness",
		"категория Health & Fitness")


func test_req_imp_03_c3_plists_declare_zwo_erg_mrc_document_types() -> void:
	for path in [IOS_PLIST, MACOS_PLIST]:
		var text := _read(path)
		assert_true(text.contains("<key>CFBundleDocumentTypes</key>"), "%s: CFBundleDocumentTypes" % path)
		assert_true(text.contains("<key>UTExportedTypeDeclarations</key>"), "%s: UTExportedTypeDeclarations" % path)
		for ext in ["zwo", "erg", "mrc"]:
			assert_true(text.contains("<string>%s</string>" % ext), "%s: расширение .%s объявлено" % [path, ext])


func test_req_str_01_c7_ios_plist_registers_ovoschrider_url_scheme() -> void:
	var text := _read(IOS_PLIST)
	assert_true(text.contains("<key>CFBundleURLSchemes</key>"), "CFBundleURLTypes со схемами")
	assert_true(text.contains("<string>ovoschrider</string>"), "схема ovoschrider (redirect OAuth, В-6)")
	var manifest := _read(ANDROID_MANIFEST)
	assert_true(manifest.contains("android:scheme=\"ovoschrider\""), "Android: intent-filter со схемой ovoschrider")


func test_req_nfr_07_macos_entitlements_enable_sandbox_and_bluetooth() -> void:
	var text := _read(MACOS_ENTITLEMENTS)
	for key in ["com.apple.security.app-sandbox", "com.apple.security.device.bluetooth", "com.apple.security.network.client"]:
		var regex := RegEx.new()
		regex.compile("<key>%s</key>\\s*<true/>" % key.replace(".", "\\."))
		assert_not_null(regex.search(text), "entitlement %s = true" % key)
	assert_false(text.contains("<key>com.apple.security.cs.disable-library-validation</key>"),
		"disable-library-validation не включён")


func test_req_nfr_07_c3_android_manifest_has_api31_ble_permissions_with_never_for_location() -> void:
	var text := _read(ANDROID_MANIFEST)
	var scan := _manifest_permission(text, "BLUETOOTH_SCAN")
	assert_false(scan.is_empty(), "BLUETOOTH_SCAN объявлен")
	assert_true(scan.contains("android:usesPermissionFlags=\"neverForLocation\""), "BLUETOOTH_SCAN с neverForLocation")
	assert_false(_manifest_permission(text, "BLUETOOTH_CONNECT").is_empty(), "BLUETOOTH_CONNECT объявлен")
	assert_true(text.contains("android.hardware.bluetooth_le"), "uses-feature bluetooth_le")


func test_req_nfr_07_c3_android_manifest_has_legacy_permissions_limited_to_api30() -> void:
	var text := _read(ANDROID_MANIFEST)
	for name in ["BLUETOOTH", "BLUETOOTH_ADMIN", "ACCESS_FINE_LOCATION"]:
		var perm := _manifest_permission(text, name)
		assert_false(perm.is_empty(), "legacy-разрешение %s объявлено" % name)
		assert_true(perm.contains("android:maxSdkVersion=\"30\""), "%s ограничено maxSdkVersion=30" % name)
	assert_true(_manifest_permission(text, "ACCESS_BACKGROUND_LOCATION").is_empty(), "фоновая геолокация не запрашивается")


func test_req_nfr_07_c4_app_store_checklist_covers_privacy_label_and_export_preset() -> void:
	var text := _read(APP_STORE_CHECKLIST)
	for needle in ["Health & Fitness", "Identifiers", "Usage Data", BLUETOOTH_KEY, "com.apple.security.device.bluetooth",
			"TestFlight", "export_presets.cfg", "Скриншоты", "рейтинг"]:
		assert_true(text.containsn(needle), "чеклист App Store содержит «%s»" % needle)


func test_req_nfr_07_c4_licenses_mention_godot_gut_godot_cpp_as_mit() -> void:
	var text := _read(LICENSES)
	for needle in ["Godot", "GUT", "godot-cpp", "MIT"]:
		assert_true(text.contains(needle), "licenses.md упоминает «%s»" % needle)
	assert_true(text.contains("Engine.get_license_text()"), "рекомендован вывод лицензии движка из ядра")
	assert_true(text.contains("О программе"), "тексты предназначены для экрана «О программе»")


func test_req_str_01_c6_c9_strava_checklist_covers_review_brand_and_rate_limits() -> void:
	var text := _read(STRAVA_CHECKLIST)
	for needle in ["Connect with Strava", "Powered by Strava", "одного атлета", "ревью", "100 запросов за 15 минут", "1000 запросов в сутки",
			"developers.strava.com/guidelines", "В-6"]:
		assert_true(text.containsn(needle), "чеклист Strava содержит «%s»" % needle)
	assert_false(text.contains("client_secret = \""), "в чеклисте нет значений client_secret")


func test_req_int_01_c5_intervals_oauth_describes_redirect_scope_and_secret_storage() -> void:
	var text := _read(INTERVALS_OAUTH)
	for needle in ["redirect", "scope", "CALENDAR:READ", "SETTINGS:READ", "client_secret", "В-6", "127.0.0.1", "ovoschrider://"]:
		assert_true(text.containsn(needle), "документ OAuth Intervals.icu содержит «%s»" % needle)


func test_req_nfr_05_c3_secure_store_doc_describes_all_platform_backends_and_migration() -> void:
	var text := _read(SECURE_STORE_DOC)
	for needle in ["EncryptedFileSecureStore", "Keychain", "Keystore", "EncryptedSharedPreferences", "libsecret", "DPAPI",
			"native/secure/", "OvoschSecure", "Миграция", "set_secret", "get_secret", "delete_secret"]:
		assert_true(text.contains(needle), "docs/secure_store.md содержит «%s»" % needle)


func test_req_nfr_06_c4_ports_docs_reference_backend_contract_and_channels() -> void:
	var readme := _read(PORTS_README)
	assert_true(readme.contains("native/ble/src/ble_backend.h"), "README портов ссылается на контракт BleBackend")
	assert_true(readme.contains("BleBackend") and readme.contains("BleListener"), "README портов называет оба интерфейса")
	var android := _read(PORTS_ANDROID)
	for needle in ["BLUETOOTH_SCAN", "neverForLocation", "Data safety", "foreground service", "targetSdk", "BluetoothGatt"]:
		assert_true(android.containsn(needle), "android.md содержит «%s»" % needle)
	var lw := _read(PORTS_LINUX_WINDOWS)
	for needle in ["org.bluez", "GattCharacteristic1", "BluetoothLEAdvertisementWatcher", "Steam", "Flathub", "Microsoft Store", "открытый вопрос"]:
		assert_true(lw.containsn(needle), "linux_windows.md содержит «%s»" % needle)
	# Все методы контракта упомянуты в таблицах портов.
	var backend_h := _read("res://native/ble/src/ble_backend.h")
	var regex := RegEx.new()
	regex.compile("virtual \\w+ (\\w+)\\(")
	for m in regex.search_all(backend_h):
		var method := m.get_string(1)
		if method in ["~BleBackend", "~BleListener"] or method.begins_with("on_"):
			continue
		assert_true(lw.contains(method) and android.contains(method), "метод контракта %s описан в документах портов" % method)


func test_req_nfr_07_export_presets_ignored_and_platform_readme_explains_usage() -> void:
	var ignore := _read(GITIGNORE)
	var found := false
	for line in ignore.split("\n"):
		if line.strip_edges() == "export_presets.cfg":
			found = true
	assert_true(found, "export_presets.cfg в .gitignore (пресеты с подписью не коммитятся)")
	var readme := _read(PLATFORM_README)
	for needle in ["additional_plist_content", "Info.plist.template", "entitlements.template.plist", "AndroidManifest.template.xml"]:
		assert_true(readme.contains(needle), "platform/README.md объясняет применение «%s»" % needle)
