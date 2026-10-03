# 3D-сцена заезда: архитектура (REQ-D3D-01..07)

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
              ┌────────────┴─────────────┐
         LoopTrack (Curve3D, seed)   GpxTrack (этап 10, маршрут)   StraightTrack (тесты)
```

## Интерфейсы

- `Track` (`src/scene3d/track.gd`): `length_m()`, `is_loop()`, `wrap_distance(s)`, `sample_into(s, out: TrackSample)`,
  `sample(s)`. Контракт: `forward`/`up` единичные; `sample(0) == sample(length)` для петли;
  смещение позиции за Δs не больше Δs.
- `TrackSample`: `position`, `forward`, `up`, `grade`, `right()`, `transform()`.
- `EnvironmentSet` (`Resource`): материалы дороги и объектов, цвета неба/тумана, свет, шаг объектов,
  `environment_scene: PackedScene` (опционально).
- `RideScene`: `set_track(track)`, `bind(session, profile)`, `unbind()`, `apply_telemetry(...)`, `advance(dt)`.
- `RoadBuilder.build(track, material, width, segments, center_offset)` — один `MeshInstance3D`, число
  сегментов фиксировано (`MAX_SEGMENTS`), не растёт со временем (D3D-03 крит. 2); ось дороги может
  быть сдвинута от линии трассы (`center_offset`) — велосипедист едет в правой полосе.

## Мир (REQ-D3D-07)

Стиль и цифры — `docs/game/art-bible.md`. Всё строится по `Track` в `RideScene.set_track()` один раз
и работает с любой трассой (петля, прямая, GPX); каждую часть можно выключить в `EnvironmentSet`.

- `RoadsideBuilder.build(...)` → `{roadside, verge}`: кромка, бордюр, отбойник (материал мира) и
  полоса травы с кюветом (материал травы); на внутренней стороне крутых поворотов ширина
  ограничена радиусом.
- `TerrainField.build(track, …)` — сетка высот вокруг габарита трассы: у дороги ниже полотна,
  дальше увалы, на краю холмы; `height_at`/`road_distance_at` — для расстановки объектов.
- `SceneryBuilder.build(track, env, field, material, budget)` — деревья, ели, кусты, трава
  (`MultiMeshInstance3D` на тип), урезается под остаток бюджета MultiMesh; сигнальные столбики —
  `RideScene.props()`.
- `MeshKit` — процедурные меши с цветом вершин (альфа — вес контура); `RiderModel` — меши и
  геометрия велосипедиста (IK ног `two_bone_joint`, `bone_transform`).
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
