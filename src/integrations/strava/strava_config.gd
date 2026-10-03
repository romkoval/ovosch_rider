class_name StravaConfig
extends RefCounted
## Параметры приложения Strava: `client_id`/`client_secret` (REQ-STR-01 крит. 5, 6; решение В-6).
##
## Источники (по убыванию приоритета):
## 1. файл `user://secrets.cfg`, секция `[strava]`, ключи `client_id`, `client_secret`
##    (dev-сборки; в репозитории — только `secrets.example.cfg.txt` с плейсхолдерами);
## 2. переменные окружения `OVOSCH_STRAVA_CLIENT_ID` / `OVOSCH_STRAVA_CLIENT_SECRET` —
##    читаются через переданную `env_lookup(name) -> String` (платформенный вызов
##    `OS.get_environment` разрешён только в оболочке/хранилище, REQ-NFR-06);
## 3. настройки проекта `ovosch_rider/strava/client_id|client_secret` (подставляются
##    конфигурацией магазинной сборки вне репозитория).
## Ничего не найдено → `is_configured() == false`, `unavailable_message()` — понятный
## текст; приложение не падает. Секрет не логируется: `_to_string()` маскирует.

const DEFAULT_CFG_PATH: String = "user://secrets.cfg"
## Секция файла совпадает с именем сервиса в `SecureStore` (ключи токенов — там же).
const CFG_SECTION: String = SecureStore.SERVICE_STRAVA
const ENV_CLIENT_ID: String = "OVOSCH_STRAVA_CLIENT_ID"
const ENV_CLIENT_SECRET: String = "OVOSCH_STRAVA_CLIENT_SECRET"
const SETTING_CLIENT_ID: String = "ovosch_rider/strava/client_id"
const SETTING_CLIENT_SECRET: String = "ovosch_rider/strava/client_secret"
## Значения-плейсхолдеры из примера не считаются настройкой.
const PLACEHOLDER_MARKERS: Array[String] = ["PLACEHOLDER", "placeholder", "YOUR_", "<"]

const SOURCE_NONE: String = "none"
const SOURCE_CONFIG_FILE: String = "config_file"
const SOURCE_ENVIRONMENT: String = "environment"
const SOURCE_BUILD: String = "build_settings"

var client_id: String = ""
var source: String = SOURCE_NONE
var _client_secret: String = ""


## Загрузить из источников. `env_lookup` — `func(name: String) -> String` (пустая
## строка — переменной нет); невалидный Callable — окружение не читается.
static func load(cfg_path: String = DEFAULT_CFG_PATH, env_lookup: Callable = Callable()) -> StravaConfig:
	var c := StravaConfig.new()
	var cfg := ConfigFile.new()
	if FileAccess.file_exists(cfg_path) and cfg.load(cfg_path) == OK:
		var id := str(cfg.get_value(CFG_SECTION, "client_id", "")).strip_edges()
		var secret := str(cfg.get_value(CFG_SECTION, "client_secret", "")).strip_edges()
		if _usable(id) and _usable(secret):
			return c._assign(id, secret, SOURCE_CONFIG_FILE)
	if env_lookup.is_valid():
		var id := str(env_lookup.call(ENV_CLIENT_ID)).strip_edges()
		var secret := str(env_lookup.call(ENV_CLIENT_SECRET)).strip_edges()
		if _usable(id) and _usable(secret):
			return c._assign(id, secret, SOURCE_ENVIRONMENT)
	var bid := str(ProjectSettings.get_setting(SETTING_CLIENT_ID, "")).strip_edges()
	var bsecret := str(ProjectSettings.get_setting(SETTING_CLIENT_SECRET, "")).strip_edges()
	if _usable(bid) and _usable(bsecret):
		return c._assign(bid, bsecret, SOURCE_BUILD)
	return c


## Конфигурация из явных значений (тесты, будущие источники).
static func from_values(id: String, secret: String, config_source: String = SOURCE_BUILD) -> StravaConfig:
	return StravaConfig.new()._assign(id.strip_edges(), secret.strip_edges(), config_source)


func is_configured() -> bool:
	return not client_id.is_empty() and not _client_secret.is_empty()


## Секрет — только для формирования запросов к Strava; не логировать.
func client_secret() -> String:
	return _client_secret


## Текст для пользователя, когда привязка недоступна (REQ-STR-01 крит. 6).
func unavailable_message() -> String:
	return "Привязка Strava недоступна: не заданы client_id и client_secret приложения (user://secrets.cfg или переменные окружения %s/%s)" % [ENV_CLIENT_ID, ENV_CLIENT_SECRET]


func _assign(id: String, secret: String, config_source: String) -> StravaConfig:
	client_id = id
	_client_secret = secret
	source = config_source if is_configured() else SOURCE_NONE
	return self


static func _usable(value: String) -> bool:
	if value.is_empty():
		return false
	for marker in PLACEHOLDER_MARKERS:
		if value.contains(marker):
			return false
	return true


func _to_string() -> String:
	return "StravaConfig(client_id=%s, secret=%s, source=%s)" % [client_id, "***" if not _client_secret.is_empty() else "нет", source]
