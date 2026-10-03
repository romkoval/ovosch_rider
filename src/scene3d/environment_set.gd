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
## Облачность неба по умолчанию (0 — ясно, 1 — сплошные облака).
@export_range(0.0, 1.0) var cloud_cover: float = 0.36
## Цвет неба ниже линии горизонта (за краем рельефа-коридора): дымка над землёй.
@export var sky_ground_color: Color = Color(0.45, 0.52, 0.45)
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
## Поперечный склон рельефа на подъёмах: уклон поперёк дороги = gain · |g(s)|
## (`TerrainField.CROSS_GAIN`), потолок — `TerrainField.CROSS_MAX`.
@export var cross_slope_gain: float = 2.5
@export_range(0.0, 0.6) var cross_slope_max: float = 0.2
## Дальний рельеф стоит на месте (0…1, `TerrainField.relief_anchor`): у подъёма внизу
## видна долина, дорога поднимается относительно холмов горизонта.
@export_range(0.0, 1.0) var relief_anchor: float = 0.0

@export_group("Vegetation mix")
## Доля елей среди деревьев рощ: порог маски шума (−1 — все ели, 1 — ни одной).
@export_range(-1.0, 1.0) var conifer_threshold: float = 0.15
## Рощи на возвышенностях (0 — где угодно, 1 — почти только на вершинах холмов).
@export_range(0.0, 1.0) var tree_hilltop_bias: float = 0.0
## Лесополосы из тополей-«свечей» (ряды вдоль полей): рядов на километр трассы, длина
## ряда, шаг деревьев в ряду и удаление ряда от дороги (м).
@export var windbreak_rows_per_km: float = 0.0
@export var windbreak_length_m: Vector2 = Vector2(140.0, 360.0)
@export var windbreak_spacing_m: float = 7.0
@export var windbreak_offset_m: Vector2 = Vector2(40.0, 320.0)
## Низкие каменные изгороди вдоль полей (доля длины трассы, отступ от оси дороги, м).
@export_range(0.0, 1.0) var stone_wall_share: float = 0.0
@export var stone_wall_offset_m: float = 11.0

@export_group("Landmarks")
## Ориентиры трассы (`RouteCatalog.landmarks`): `LandmarkBuilder`, по одному узлу на ориентир.
## Включаются в наборе трассы, где типы ориентиров уже есть в `LandmarkBuilder` (равнина и
## холмы — T-083; горы и приморье — T-087/T-088).
@export var landmarks_enabled: bool = false
## Цвета построек ориентиров (деревни, хутор, ферма) — палитра трассы (`tracks.md` п. 6).
@export var building_wall_color: Color = Color(0.93, 0.89, 0.80)
@export var building_roof_color: Color = Color(0.78, 0.32, 0.24)
## Цвет воды ручьёв и озёр ориентиров.
@export var water_color: Color = Color(0.22, 0.62, 0.72)

@export_group("Roadside posts")
## Повторяющиеся объекты вдоль дороги (сигнальные столбики) — одним `MultiMeshInstance3D`.
@export var prop_material: Material = null
@export var prop_size: Vector3 = Vector3(0.12, 1.0, 0.12)
@export var prop_spacing_m: float = 25.0
## Отступ объектов от оси дороги, м.
@export var prop_offset_m: float = 4.6
