# 3D-сцена заезда: архитектура (REQ-D3D-01..06)

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
- `RoadBuilder.build(track, material, width, segments)` — один `MeshInstance3D`, число сегментов
  фиксировано (`MAX_SEGMENTS`), не растёт со временем (D3D-03 крит. 2).

## Как добавить маршрут GPX (без правки игрового цикла)

1. Реализовать `GpxTrack extends Track`: разобрать точки GPX в `Curve3D` (или массив точек с
   накопленной дистанцией), `is_loop() = false`, `sample_into` — интерполяция по дистанции с клампом.
2. В точке запуска тренировки вызвать `ride_scene.set_track(GpxTrack.new(path))` вместо `LoopTrack`.
3. При необходимости — свой `EnvironmentSet` (`.tres`) с другим материалом/небом.
Тесты D3D-02/04 выполняются на любой реализации `Track` (см. `StraightTrack` в `tests/integration/test_ride_scene.gd`).

## Бюджет и per-frame код

См. `docs/perf_budget.md`: подсчёт `MeshInstance3D`/материалов/света в инстанцированной сцене и
статическая проверка отсутствия аллокаций в `_process`/`_physics_process` файлов `src/scene3d/`.
