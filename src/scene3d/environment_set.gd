class_name EnvironmentSet
extends Resource
## Набор окружения для `RideScene` (REQ-D3D-03, REQ-D3D-06 крит. 1, REQ-D3D-07): материалы
## дороги, мира и рельефа, небо/туман/свет, обочина и отбойник, рельеф и растительность,
## повторяющиеся столбики вдоль трассы, опционально — сцена окружения. Замена набора не
## трогает игровой цикл и движение велосипедиста. Пустые материалы (null) заменяются
## материалами по умолчанию из `src/scene3d/materials/`.

## Дополнительная сцена окружения (ландшафт, здания); null — только процедурный мир.
@export var environment_scene: PackedScene = null

@export_group("Sky, fog, light")
## Шейдер неба (`sky.gdshader`); null — материал по умолчанию с цветами ниже.
@export var sky_material: Material = null
## Цвет зенита (и фон без неба).
@export var sky_color: Color = Color(0.55, 0.72, 0.92)
@export var horizon_color: Color = Color(0.80, 0.85, 0.90)
@export var fog_color: Color = Color(0.75, 0.82, 0.90)
@export var fog_density: float = 0.004
## Окружающий свет — цвет теней (тун: в тени только он).
@export var ambient_color: Color = Color(0.6, 0.65, 0.7)
@export var ambient_energy: float = 1.0
@export var sun_color: Color = Color(1.0, 0.97, 0.9)
@export var sun_energy: float = 1.2
@export var sun_rotation_deg: Vector3 = Vector3(-50.0, 35.0, 0.0)

@export_group("Road")
@export var road_material: Material = null
@export var road_width_m: float = 6.5
## Смещение оси дороги относительно линии движения, м (минус — влево): велосипедист
## едет по оси трассы, а дорога сдвинута так, что это правая полоса.
@export var road_center_offset_m: float = -1.4
## Бордюр, гравийная кромка и отбойник (материал мира, цвет вершин).
@export var roadside_enabled: bool = true
@export var guardrail_enabled: bool = true

@export_group("World")
## Тун-материал по цвету вершины: объекты у дороги, деревья, кусты, бордюр.
@export var world_material: Material = null
## Материал травы и рельефа (`grass.gdshader`).
@export var terrain_material: Material = null
@export var terrain_enabled: bool = true
## Высота холмов на краю мира и пологих увалов у дороги, м.
@export var hills_height_m: float = 120.0
@export var rolling_height_m: float = 5.0
## Число деревьев, кустов и пучков травы (MultiMesh; общий потолок — `PerfBudget`).
@export var tree_count: int = 380
@export var bush_count: int = 220
@export var tuft_count: int = 900
@export var scenery_seed: int = 11

@export_group("Roadside posts")
## Повторяющиеся объекты вдоль дороги (сигнальные столбики) — одним `MultiMeshInstance3D`.
@export var prop_material: Material = null
@export var prop_size: Vector3 = Vector3(0.12, 1.0, 0.12)
@export var prop_spacing_m: float = 25.0
## Отступ объектов от оси дороги, м.
@export var prop_offset_m: float = 4.6
