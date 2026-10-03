class_name EnvironmentSet
extends Resource
## Набор окружения для `RideScene` (REQ-D3D-03, REQ-D3D-06 крит. 1): материал дороги,
## цвета неба/тумана, параметры света и повторяющихся объектов вдоль трассы, опционально —
## сцена окружения. Замена набора не трогает игровой цикл и движение велосипедиста.

## Дополнительная сцена окружения (ландшафт, здания); null — только процедурные объекты.
@export var environment_scene: PackedScene = null
@export var road_material: Material = null
@export var sky_color: Color = Color(0.55, 0.72, 0.92)
@export var horizon_color: Color = Color(0.80, 0.85, 0.90)
@export var fog_color: Color = Color(0.75, 0.82, 0.90)
@export var fog_density: float = 0.004
@export var ambient_color: Color = Color(0.6, 0.65, 0.7)
@export var sun_energy: float = 1.2
@export var sun_rotation_deg: Vector3 = Vector3(-50.0, 35.0, 0.0)
## Повторяющиеся объекты вдоль дороги (столбы/деревья) — одним `MultiMeshInstance3D`.
@export var prop_material: Material = null
@export var prop_size: Vector3 = Vector3(0.3, 4.0, 0.3)
@export var prop_spacing_m: float = 25.0
## Отступ объектов от оси дороги, м.
@export var prop_offset_m: float = 5.0
