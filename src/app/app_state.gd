class_name AppState
extends RefCounted
## Состояние навигации приложения (REQ-PRF-05, заделка REQ-NFR-08 крит. 3).
## Чистая модель без узлов сцены — проверяется headless.
##
## Правило старта (`initial_screen`): 0 профилей → экран выбора в режиме
## создания первого профиля; 1 профиль → он становится активным, сразу HOME;
## ≥2 профилей → экран выбора, главный экран недоступен до явного выбора
## (`select_profile`) — даже если в репозитории сохранён активный с прошлого запуска.

enum Screen {
	PROFILE_SELECT,
	HOME,
	WORKOUT,
	HISTORY,
	SETTINGS,
	DEV,
	DEVICES,
	PLAN,
}

## Экран сменился.
signal screen_changed(screen: int)
## Профиль выбран в этой сессии (id).
signal profile_selected(id: String)
## Язык интерфейса сменён (REQ-NFR-08 крит. 3, 4): экраны перерисовывают тексты.
signal locale_changed(locale: String)

var current_screen: int = Screen.PROFILE_SELECT
## Экран выбора открыт в режиме создания первого профиля (0 профилей).
var create_mode: bool = false

## Поддерживаемые языки интерфейса (UI берёт список отсюда, не из `AppLocale`).
const SUPPORTED_LOCALES: Array[String] = AppLocale.SUPPORTED_LOCALES

var _repo: ProfileRepository
var _settings: AppSettings = null
var _profile_chosen: bool = false
## Код ошибки последнего `select_profile` ("" — успех): `profile_not_found` или
## `storage_write_failed` (`ProfileRepository.ERR_*`); экран выбора показывает его как
## `error.profile.<code>`.
var _last_select_error: String = ""


## `settings` — хранилище настроек приложения (язык); null — язык не сохраняется.
func _init(repo: ProfileRepository, settings: AppSettings = null) -> void:
	_repo = repo
	_settings = settings


func repository() -> ProfileRepository:
	return _repo


## Стартовый экран по числу профилей, без побочных эффектов.
static func initial_screen(repo: ProfileRepository) -> int:
	return Screen.HOME if repo.count() == 1 else Screen.PROFILE_SELECT


## Язык интерфейса по языку системы (делегирует `AppLocale.pick`).
static func pick_locale(system_language: String) -> String:
	return AppLocale.pick(system_language)


## Применить язык без перезапуска (REQ-NFR-08 крит. 3, 4): сохранить в `AppSettings`,
## `TranslationServer.set_locale`, `locale_changed` для перерисовки экранов.
## Неподдерживаемый язык → false. Единственная точка смены языка для UI (Н-5).
func set_locale(locale: String) -> bool:
	if not SUPPORTED_LOCALES.has(locale):
		return false
	if _settings != null:
		_settings.locale = locale
		_settings.save()
	TranslationServer.set_locale(locale)
	locale_changed.emit(locale)
	return true


## Текущий язык интерфейса ("en"/"ru").
func locale() -> String:
	return TranslationServer.get_locale().substr(0, 2)


func settings() -> AppSettings:
	return _settings


## Применить правило старта: единственный профиль выбирается автоматически. Если выбор
## не удался (не записан активный профиль) — остаётся экран выбора с ошибкой в `last_select_error()`.
func start() -> void:
	_profile_chosen = false
	create_mode = _repo.count() == 0
	if _repo.count() == 1:
		var only: Profile = _repo.list()[0]
		if select_profile(only.id):
			return
	_set_screen(Screen.PROFILE_SELECT)


## Можно ли открывать экраны за пределами выбора профиля.
func can_open_main() -> bool:
	return _profile_chosen and _repo.get_active() != null


func is_profile_chosen() -> bool:
	return _profile_chosen


## Код ошибки последнего `select_profile` ("" — успех).
func last_select_error() -> String:
	return _last_select_error


## Выбрать профиль: делает его активным и открывает HOME. false — профиль не найден или
## активный профиль не записан на диск; код — в `last_select_error()`, экран не меняется.
func select_profile(id: String) -> bool:
	if _repo.get_by_id(id) == null:
		_last_select_error = ProfileRepository.ERR_PROFILE_NOT_FOUND
		return false
	var err := _repo.set_active(id)
	_last_select_error = err
	if not err.is_empty():
		return false
	_profile_chosen = true
	create_mode = false
	profile_selected.emit(id)
	_set_screen(Screen.HOME)
	return true


## Вернуться к выбору профиля; главный экран снова недоступен до выбора.
func switch_profile() -> void:
	_profile_chosen = false
	create_mode = _repo.count() == 0
	_set_screen(Screen.PROFILE_SELECT)


## Перейти на экран. Экраны кроме PROFILE_SELECT требуют выбранного профиля → иначе false.
func navigate(screen: int) -> bool:
	if screen != Screen.PROFILE_SELECT and not can_open_main():
		return false
	_set_screen(screen)
	return true


func _set_screen(screen: int) -> void:
	var changed_screen: bool = screen != current_screen
	current_screen = screen
	if changed_screen:
		screen_changed.emit(screen)


static func screen_name(screen: int) -> String:
	var keys := Screen.keys()
	if screen >= 0 and screen < keys.size():
		return str(keys[screen]).to_lower()
	return "unknown"
