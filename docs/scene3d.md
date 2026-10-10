# 3D-сцена заезда: архитектура (REQ-D3D-01..08)

Игровой цикл не знает ни конкретной трассы, ни конкретного окружения. `RideScene` получает
телеметрию от `WorkoutSession` (закрытые слоты потока 1 Гц), превращает её в скорость
(`SpeedModel.step(P, m, dt)` или скорость станка при `speed_source == "trainer"`) и каденс,
интегрирует дистанцию `s` в кадре и спрашивает у трассы «дай точку на дистанции s»
(`Track.sample_into(s, out)`). Окружение (материал дороги, небо/туман, свет, повторяющиеся
объекты, опциональная сцена) приходит ресурсом `EnvironmentSet`. Поэтому новая трасса —
это новая реализация `Track`, новое окружение — новый `.tres`; код движения, камеры,
анимации и привязки к телеметрии не меняется (D3D-06 крит. 1, 2).

```
WorkoutSession ──second_elapsed──▶ RideScene.bind()            EnvironmentSet (.tres)
   samples.last_row()                │  speed_kmh, cadence       │ road_material, sky, fog,
   speed_source                      │  distance_m += v·dt       │ sun, props, [scene]
                                     ▼                           ▼
                       Track.sample_into(s, TrackSample) ──▶ Rider / Camera / Road / Props
                           ▲                 {position, forward, up, grade}
              ┌────────────┴──────────────┬───────────────────────────┐
     ProfiledTrack (план + h(s))   LoopTrack (Curve3D, seed)   GpxTrack (этап 10)   StraightTrack (тесты)
              ▲
  RouteWorld: id трассы ──▶ ProfiledTrack + EnvironmentSet ◀── RouteCatalog (RouteDef: профиль,
  RideScene.set_route(id)                                        layout, seed, мосты, ориентиры)
```

**Трассы каталога (REQ-D3D-08).** `RideScene.set_route(id)` берёт у `RouteWorld` трассу и набор
окружения по id каталога (`flat`, `hills`, `mountains`, `seaside`); по умолчанию сцена едет по
`flat` — поэтому тренировка по плану идёт на равнине без правки `workout_screen` (D3D-08 п.13),
`route_id = ""` — процедурная петля `LoopTrack`. `ProfiledTrack` строит план-схему один раз: форма
(`layout.shape`) — последовательность прямых и дуг с радиусами из `tracks.md`, кривизна сглаживается
(переходные кривые), три группы прямых с разными курсами подгоняются так, чтобы круг замкнулся и
длина плана равнялась длине профиля; позиция — (план(s), h(s)), `forward` — касательная плана с
уклоном профиля g(s) (продольный наклон велосипедиста = atan(g)), `up` — нормаль полотна. Скорость от
уклона не зависит (модель ровной дороги, D3D-02), высота и наклон — по профилю. Мир строится от
полотна, а не от средней высоты: **рельеф-коридор** (`TerrainField`, длинная трасса) — плитки
±700 м вдоль трассы, у дороги мелкая ячейка, дальше крупная (LOD), куски-меши с дальностью
видимости; высота земли у полотна — по ближайшим точкам оси (у дороги ровно h(s), ниже полотна на
`ROAD_SINK_M`), дальше — «поле высоты трассы» (сглаженное среднее высот точек трассы) с поперечным
склоном на подъёмах, поверх — увалы и холмы. **Куски**: дорога и обочина — общие кольца с шагом ~5 м
на любой длине (`RoadBuilder.ring_distances`, край асфальта совпадает с кромкой), до 800 сегментов
на кусок и до 5 кусков; растительность и столбики — куски ~500 м с `visibility_range`
(`docs/perf_budget.md`).

## Интерфейсы

- `Track` (`src/scene3d/track.gd`): `length_m()`, `is_loop()`, `wrap_distance(s)`, `sample_into(s, out: TrackSample)`,
  `sample(s)`. Контракт: `forward`/`up` единичные; `sample(0) == sample(length)` для петли;
  смещение позиции за Δs не больше Δs.
- `TrackSample`: `position`, `forward`, `up`, `grade`, `right()`, `transform()`.
- `EnvironmentSet` (`Resource`): материалы дороги и объектов, цвета неба/тумана, свет, шаг объектов,
  `environment_scene: PackedScene` (опционально).
- `RideScene`: `set_track(track)`, `bind(session, profile)`, `unbind()`, `apply_telemetry(...)`, `advance(dt)`.
- `RoadBuilder.build(track, material, width, segments, center_offset)` — дорога кусками: узел «Road»
  (кусок 0) и дети `Road_<k>`, шаг колец ~5 м, в куске ≤ `MAX_SEGMENTS`, кусков ≤ `MAX_CHUNKS`; число
  сегментов фиксировано при построении, не растёт со временем (D3D-03 крит. 2); ось дороги может
  быть сдвинута от линии трассы (`center_offset`) — велосипедист едет в правой полосе.
- `ProfiledTrack` (`Track`): трасса каталога по `RouteDef` (`from_id`, `from_route`); `RouteWorld`:
  `track(id)` (кэш), `environment(id)`, `environment_path(id)`; `RideScene.set_route(id)`, `route_id`.

## Мир (REQ-D3D-07)

Стиль и цифры — `docs/game/art-bible.md`. Всё строится по `Track` в `RideScene.set_track()` один раз
и работает с любой трассой (петля, прямая, GPX); каждую часть можно выключить в `EnvironmentSet`.

- `RoadsideBuilder.build(...)` → `{roadside, verge}`: кромка, бордюр, отбойник (материал мира) и
  полоса травы с кюветом (материал травы); на внутренней стороне крутых поворотов ширина
  ограничена радиусом.
- `TerrainField.build(track, …)` — рельеф: на компактной петле — одна сетка вокруг габарита, на длинной
  трассе — коридор кусками; высота отсчитывается от полотна (у дороги ниже него, дальше поле высоты
  трассы, увалы, на краю холмы); `height_at`/`road_distance_at` — для расстановки объектов.
- `SceneryBuilder.build(track, env, field, material, budget)` — деревья, ели, кусты, трава
  (`MultiMeshInstance3D` на тип), урезается под остаток бюджета MultiMesh; сигнальные столбики —
  `RideScene.props()`.
- `MeshKit` — процедурные меши с цветом вершин (альфа — вес контура); region kits (T-106a3,
  rider and bike) write the region code to UV0 instead of COLOR, one region per face, and the
  smoothed outline normal to TANGENT; `RiderModel` — меши и
  геометрия велосипедиста (IK `two_bone_joint`, `two_bone_joint_x`, оси костей `bone_basis`);
  велосипед подогнан под контракт скелета (T-106a1): седло, тормозные ручки, контактные педали —
  шатуны одним мешем со скиннингом на 3 кости (`CrankRig`), педали держат угол стопы θ(φ).
  Гонщик (T-106a2) — манекен на `Skeleton3D` контракта (`%Skeleton`, 25 костей): сетки `Body`
  (`body_m`/`body_f`), `Hair` (`hair_short`/`hair_tail`), `Helmet`, `Eyewear`, `ShoeL/R` со
  скиннингом, вес 1 на кость, один `Skin` (`RiderModel.rider_skin`); всего 10 `MeshInstance3D`
  с велосипедом. `Rider._pose_body` каждый кадр ставит позы костей без аллокаций: IK ног (шип на
  оси педали, θ(φ), колено вбок), arm IK (the elbow holds its rest angle; body sway turns the
  hand around `grip` by ≤ 2.5° and slides the palm on the hood by a few mm), крен таза вокруг S, крен и рыскание корпуса с компенсацией головы, пружина
  хвоста (сетка и оси — по костям `hair_tail.1/2`, кончик — окончание `hair_tail.2`). Числа движения — `RiderMotion`
  (спека «Движение по видео-референсу»); размах — коэффициент усилия k от P сэмпла и FTP
  профиля (`Rider.set_power`; `RideScene.apply_telemetry` + `bind`, свободная езда — экран), без
  мощности или FTP — от каденса.
- `RiderRig` — контракт скелета модели гонщика (25 костей, rest, окончания и оси костей,
  точки велосипеда, перевод осей Godot ↔ Blender ↔ glTF, эталонные ракурсы `VIEWS`,
  контрольные позы); `RiderRegions` — регионы цвета (UV-код), связь «регион → слот
  `RiderLook`», палитра внешности, атласы. Colors (T-106a3): one material `rider_toon.tres`
  (`rider_toon.gdshader`: palette of 32 regions + lens highlight, additive rim) with the outline
  `next_pass` (`rider_outline.gdshader`: weight by region; Forward+/Mobile — along the smoothed
  normal in TANGENT, Compatibility — along NORMAL: its skinning loses TANGENT); `RiderPalette` —
  palette read/write, jersey patterns (regions 3–7) from slot values without `src/profiles/`;
  `Rider.set_palette`/`set_region_color` (own material copy), `Rider.set_rims` (`deep`/`shallow`). Эталонный пакет для подготовки `rider.glb`
  (конвейер доводки в Blender, бриф художнику) — `assets/rider/reference/`
  (`./scripts/rider_artist_kit.sh` → `scripts/dev/rider_reference_pack.gd`, побайтно
  воспроизводим, в сборку не входит; проверка в Blender —
  `scripts/dev/check_rider_pack_blender.py`), ракурсы — `./scripts/rider_views.sh`. Тесты
  контракта скелета параметризованы источником модели
  (`tests/fixtures/scene3d/rider_contract.gd`, `RIG_SOURCES`).
- Материалы — `src/scene3d/materials/`, шейдеры — `src/scene3d/shaders/` (общий тун-свет
  `toon_light.gdshaderinc`; контур — `next_pass`). Пустой материал в `EnvironmentSet` заменяется
  материалом по умолчанию.
- В кадре (`advance`, без аллокаций): велосипедист ставится по трассе, камера в три четверти
  (`CAMERA_SIDE_RAD`) смотрит на точку впереди, наклон в повороте — atan(v²·κ/g) по кривизне
  между `s` и `s + LEAN_PROBE_M`, сглаженный; `Rider.advance` ставит ноги по углу шатуна.

## Как добавить маршрут GPX (без правки игрового цикла)

1. Реализовать `GpxTrack extends Track`: разобрать точки GPX в `Curve3D` (или массив точек с
   накопленной дистанцией), `is_loop() = false`, `sample_into` — интерполяция по дистанции с клампом.
2. В точке запуска тренировки вызвать `ride_scene.set_track(GpxTrack.new(path))` вместо `LoopTrack`.
3. При необходимости — свой `EnvironmentSet` (`.tres`) с другим материалом/небом.
Тесты D3D-02/04 выполняются на любой реализации `Track` (см. `StraightTrack` в `tests/integration/test_ride_scene.gd`).

## Бюджет и per-frame код

См. `docs/perf_budget.md`: подсчёт `MeshInstance3D`/материалов/света в инстанцированной сцене и
статическая проверка отсутствия аллокаций в `_process`/`_physics_process` файлов `src/scene3d/`.
