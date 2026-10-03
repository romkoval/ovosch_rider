class_name TouchTarget
extends Node
## Минимальный размер цели нажатия (`docs/game/ui.md` п. 3, 6, 9.2; REQ-UIX-05 крит. 1).
##
## Тема одна для всех устройств и минимальные размеры не задаёт: их выставляет этот помощник
## по типу устройства из автозагрузки `UiScaleRuntime` — `touch_ui` (52 lp на сенсорных,
## 40 lp на компьютере) для меню, `touch_hud` для кнопок HUD. Размер пересчитывается по
## сигналу `UiScaleRuntime.scale_changed` (переключение меню/HUD).
##
## Использование — один вызов на интерактивный узел (кнопка, строка, карточка, поле):
## `TouchTarget.attach(button)`; для основной и вторичной кнопки — `Kind.BUTTON` (высота
## не меньше 44 lp и на компьютере); нижняя граница от компонента — `floor_size` (кнопка
## «назад» AppBar — 48 на компьютере, строка списка — 64/76 по высоте). `attach_all(root)`
## обходит поддерево и цепляет помощника ко всем узлам с `focus_mode` ≠ NONE.
##
## Помощник — внутренний дочерний узел цели (`INTERNAL_MODE_BACK`): в `get_children()` и
## раскладку контейнеров он не попадает. Повторный `attach` возвращает уже прикреплённый узел.

enum Kind {
	## `touch_ui` × `touch_ui`: кнопка-иконка, фишка, строка, карточка, поле, переключатель.
	UI,
	## Основная/вторичная/опасная кнопка: ширина ≥ `touch_ui`, высота ≥ max(`touch_ui`, 44).
	BUTTON,
	## Кнопка HUD: `touch_hud` × `touch_hud` (lp HUD).
	HUD,
}

## Высота основной и вторичной кнопки на компьютере (`ui.md` п. 6: 52 на сенсорных, 44 на компьютере).
const BUTTON_MIN_HEIGHT: float = 44.0
## Путь автозагрузки `UiScale` (`project.godot`).
const RUNTIME_PATH: NodePath = ^"/root/UiScaleRuntime"
const NODE_NAME: StringName = &"TouchTarget"

@export var kind: Kind = Kind.UI
## Нижняя граница размера цели в lp, не зависящая от устройства (0 — нет).
@export var floor_size: Vector2 = Vector2.ZERO

## Источник `touch_ui`/`touch_hud`; null — автозагрузка `UiScaleRuntime` (если её нет — значения компьютера).
var runtime: UiScale = null

var _connected_runtime: UiScale = null


## Прикрепить помощника к `target` и сразу применить размер. `custom_minimum_size`, заданный
## цели до вызова, сохраняется как часть нижней границы. `scale_source` — подмена `UiScale` (тесты).
static func attach(target: Control, target_kind: Kind = Kind.UI, min_floor: Vector2 = Vector2.ZERO, scale_source: UiScale = null) -> TouchTarget:
	var existing := of(target)
	if existing != null:
		existing.kind = target_kind
		existing.floor_size = existing.floor_size.max(min_floor)
		if scale_source != null:
			existing.set_runtime(scale_source)
		existing.apply()
		return existing
	var helper := TouchTarget.new()
	helper.name = NODE_NAME
	helper.kind = target_kind
	helper.floor_size = min_floor.max(target.custom_minimum_size)
	helper.runtime = scale_source
	target.add_child(helper, false, Node.INTERNAL_MODE_BACK)
	helper.apply()
	return helper


## Прикрепить помощника ко всем интерактивным узлам поддерева `root` (включая сам `root`),
## у которых его ещё нет. Возвращает число обработанных узлов.
static func attach_all(root: Node, target_kind: Kind = Kind.UI, scale_source: UiScale = null) -> int:
	var count := 0
	var control := root as Control
	if control != null and control.focus_mode != Control.FOCUS_NONE:
		if of(control) == null:
			attach(control, target_kind, Vector2.ZERO, scale_source)
		count += 1
	for child in root.get_children():
		count += attach_all(child, target_kind, scale_source)
	return count


## Помощник, прикреплённый к `target`, или null.
static func of(target: Control) -> TouchTarget:
	for child in target.get_children(true):
		if child is TouchTarget:
			return child
	return null


## Минимальный размер цели: чистая функция от вида, `touch_ui`, `touch_hud` и нижней границы.
static func min_size_for(target_kind: Kind, touch_ui: float, touch_hud: float, min_floor: Vector2 = Vector2.ZERO) -> Vector2:
	var size: Vector2
	match target_kind:
		Kind.BUTTON:
			size = Vector2(touch_ui, maxf(touch_ui, BUTTON_MIN_HEIGHT))
		Kind.HUD:
			size = Vector2(touch_hud, touch_hud)
		_:
			size = Vector2(touch_ui, touch_ui)
	return size.max(min_floor)


## Автозагрузка `UiScaleRuntime` или null (вне дерева сцены, в инструментах).
static func default_runtime() -> UiScale:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null(RUNTIME_PATH) as UiScale


## Сменить источник масштаба (переподключает `scale_changed`, если узел в дереве).
func set_runtime(scale_source: UiScale) -> void:
	runtime = scale_source
	if is_inside_tree():
		_connect_runtime()
	apply()


## Поднять нижнюю границу (компонент сменил свою высоту) и применить.
func set_floor(min_floor: Vector2) -> void:
	floor_size = min_floor
	apply()


## Текущий минимальный размер цели по источнику масштаба.
func min_size() -> Vector2:
	var source := _source()
	var touch_ui := source.touch_ui() if source != null else UiScale.TOUCH_UI_DESKTOP
	var touch_hud := source.touch_hud() if source != null else UiScale.TOUCH_HUD_DESKTOP
	return min_size_for(kind, touch_ui, touch_hud, floor_size)


## Выставить `custom_minimum_size` цели.
func apply() -> void:
	var target := get_parent() as Control
	if target == null:
		return
	var size := min_size()
	if target.custom_minimum_size != size:
		target.custom_minimum_size = size


func _enter_tree() -> void:
	_connect_runtime()
	apply()


func _exit_tree() -> void:
	_disconnect_runtime()


func _source() -> UiScale:
	return runtime if runtime != null else default_runtime()


func _connect_runtime() -> void:
	var source := _source()
	if source == _connected_runtime:
		return
	_disconnect_runtime()
	if source != null:
		source.scale_changed.connect(_on_scale_changed)
		_connected_runtime = source


func _disconnect_runtime() -> void:
	if _connected_runtime != null and is_instance_valid(_connected_runtime) and _connected_runtime.scale_changed.is_connected(_on_scale_changed):
		_connected_runtime.scale_changed.disconnect(_on_scale_changed)
	_connected_runtime = null


func _on_scale_changed(_scale: float) -> void:
	apply()
