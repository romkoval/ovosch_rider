class_name RouteSelectScreen
extends Control
## Выбор трассы свободной езды (REQ-FRD-02, `docs/game/ui.md` п. 8.4) — заготовка
## навигационного каркаса (T-061): экран в навигации, «назад» и предвыбранная трасса
## из профиля. Карточки трасс, деталь, слайдер крутизны и «Поехать» — T-080.

var _repo: ProfileRepository
var _app_state: AppState

@onready var _back_button: Button = %BackButton


func setup(repo: ProfileRepository, app_state: AppState) -> void:
	_repo = repo
	_app_state = app_state


func _ready() -> void:
	_back_button.pressed.connect(back)


## Перечитать данные профиля при входе на экран (заготовка: отрисовывать пока нечего).
func refresh() -> void:
	pass


## Трасса, предвыбранная при открытии экрана (REQ-FRD-02 крит. 3): последняя выбранная
## в активном профиле, при первом запуске — `Profile.DEFAULT_ROUTE_ID`.
func preselected_route_id() -> String:
	var active: Profile = _repo.get_active() if _repo != null else null
	return active.effective_route_id() if active != null else Profile.DEFAULT_ROUTE_ID


## Крутизна SIM активного профиля, % (REQ-FRD-05 крит. 1) — начальное значение слайдера.
func preselected_sim_steepness_pct() -> int:
	var active: Profile = _repo.get_active() if _repo != null else null
	return active.sim_steepness_pct if active != null else Profile.DEFAULT_SIM_STEEPNESS_PCT


## Системный «назад» (Esc, Android): true — экран обработал его сам (например, закрыл лист
## детали на телефоне, T-080); false — решает стек `AppState`.
func handle_back() -> bool:
	return false


## Кнопка «назад»: на экран, с которого пришли (REQ-UIX-04 крит. 1).
func back() -> void:
	if _app_state != null:
		_app_state.go_back()
