# Состояние цикла оркестрации

Файл ведёт менеджер. Это единственная «память» между циклами: следующий цикл
начинается с чтения этого файла, `docs/backlog.md`, `docs/story-map.md` и нужных записей
`docs/requirements.md`, а не с истории диалога.

## Чекпоинт

### Checkpoint 2026-10-10, late (manager; HEAD = 64199e7; supersedes the queues below)
- Merged into `main` (c14736b): T-106a2 elbow fix accepted → `done`. T-106a3 — all auto criteria passed by tester, game-designer asked small fixes (spokes → `rim_carbon`, helmet stripe; art-bible rev. 4.7) → stays `review`, technical-artist fixing; T-106a4 → `in-progress`.
- Developer batch (accepted by tester, **not merged yet** — one merge together with the T-162 fixes): T-173, T-175, T-176 passed; T-174 auto passed + ru visual accepted (en shot pending); T-177 spike passed (owner's Mac check pending). Statuses stay `review` until the merge (then `done`, except T-174 until the en shot and T-177 until the owner's check per its task file).
- Returned to `in-progress`: T-161 — rework passed, but new WRK-04 p.6 (U-48: first resistance command carries the user level, no stray 0 / previous level) is a defect; T-162 — rework failed: D-2 FreeRide display rule, D-3 hint-slot priority, D-4 +/- = resistance with ERG off. Developer is fixing both first.
- Developer started T-187 and T-180 (`in-progress`, paused for the T-161 / T-162 fixes).
- Owner decisions: U-44 (first routes South China + islands, game-designer proposes T-191), U-45 / U-46 (one auto screenshot per ride around mid-workout, gameplay frame, PNG, on by default), U-47 (mini-HUD outside MVP, later release; T-177 spike stays), U-48 (DEV-11 p.9 (в) capability request in pause allowed; WRK-04 p.6).
- Requirements commits: HUD rules 61d807f; DEV-11 / WRK-04 eb482a2.
- Story map rev. 8 (A3.22 moved from 0.4 to "Дальше").
- Queues:
  - developer — T-161 (WRK-04 p.6) and T-162 (D-2..D-4) fixes → one merge with T-173..T-177 → T-180, T-187 (resume) → T-116b → T-181 → T-182, T-183;
  - technical-artist — T-106a3 fixes (art-bible rev. 4.7) → T-106a4 → T-109 → T-184 → T-185;
  - tester — re-check T-161, T-162 after fixes; T-174 en shot; re-check T-106a3 fixes;
  - game-designer — T-106a3 re-verdict, T-174 en verdict; T-178 → T-191 → T-179;
  - owner — T-177 build and checklist on the Mac; confirm T-191 shortlist; "0.4 routes separately"; Strava partner application.

### Checkpoint 2026-10-10, evening (manager; `main` = ea8516e; superseded by the checkpoint above)
- `done`: T-160, T-108, T-113, T-115 (tester verdicts in `main`: 304f63a, 65d3c72, cad3845, 3ddb4bb).
- `review` (acceptance running in other worktrees — do not edit their task files): T-161, T-162 (rework), T-173, T-174, T-175, T-176, T-177, T-106a2 (elbow fix), T-106a3.
- T-177 spike result (developer cannot edit task files; recorded here and in backlog section 4 "Mini-HUD spike"): window level `NSStatusWindowLevel`; collection behavior `canJoinAllSpaces | fullScreenAuxiliary`; App Nap guard while in mini-HUD; the Objective-C++ part is not compiled in the container — owner builds on the Mac and runs the checklist (over full-screen video, across Spaces, 10 min unfocused); fallback if it does not show over full-screen video — `NSPanel` or the accessory activation policy. Copy into T-177 History once acceptance is done there.
- Release 0.4 additions (REQ-D3D-11, STR-06, STR-07, LOC-08 — requirements ea8516e; У-39..У-43). New tasks T-178..T-191 (backlog section 2, "Release 0.4 — real-world routes"):
  - real routes, separate part "0.4 routes" (coordinator's proposal to the owner — does not hold the Neo exit criteria): T-178 spec, T-191 route shortlist, T-179 mockup (game-designer); T-180 catalog, T-181 session, T-182 GPS/FIT/Strava, T-183 route cards, T-186 route data (developer); T-184 road, T-185 scenery/streaming (technical-artist).
  - Н-80 answered by the owner: South China and islands, spectacular routes; game-designer proposes (T-191), owner confirms → T-186.
  - screenshots: T-187 guard (STR-07 p.6, 9) — `todo` now; T-188, T-189, T-190 — `blocked` until Strava partner access. Owner update: auto screenshot at a random moment around the middle of the workout, gameplay frame with full HUD, on by default — requirements is writing it into LOC-08 (T-189 points there).
- Queues:
  - developer — acceptance defects of the `review` batch → T-116b → T-180 → T-181 → T-182, T-183; T-187 as a filler; T-186 after T-191 is confirmed;
  - technical-artist — acceptance defects of T-106a2 / T-106a3 → T-106a4 → T-109 → T-184 → T-185;
  - game-designer — T-178 → T-191 → T-179 (and verdicts);
  - tester — acceptance of the `review` batch;
  - owner — confirm "0.4 routes as a separate part", confirm T-191 shortlist, apply for Strava partner status; Н-78 (в)–(ж), Н-79 (е), (з).

### Checkpoint 2026-10-10 (manager; supersedes the queues below where they differ)
- **3D stream pause (2026-10-05) lifted by the owner on 2026-10-10.** technical-artist is back at work.
- Closed 2026-10-10: T-106a1 (tester 2dce864), T-112 (tester 4cd73ea, game-designer cc37459), T-107 (tester de7f24e, game-designer after e19734e) — `done`. T-107 owner manual is in backlog section 4 (P8 / needles in Forward+, draw calls on «Mountain Pass», FPS).
- T-106a2 — back to `in-progress`: REQ-D3D-09 p.15, elbow swings 5.05° per revolution (spec ≤ 2°); tester test 58c5c0b not in `main` yet (red until the fix). T-106a3 — `in-progress` (started 2026-10-10).
- Queues:
  - developer — T-174 → T-173 → T-161 / T-162 rework → T-177 (mini-HUD spike) → T-176 → T-175;
  - technical-artist — T-106a2 elbow fix → T-106a3;
  - tester — idle (next: re-check T-106a2 p.15 after the fix);
  - game-designer — verdicts on demand.
- Process rules (new): one full test run per hand-off (not per commit); English language policy for new entries in docs (story-map stays Russian).

### Пауза по просьбе владельца (2026-10-05, запись оркестратора; снята 2026-10-10)
Агенты остановлены. **Бэклог разделён (2026-10-05):** `docs/backlog.md` — индекс (таблица раздела 2: статус только здесь), описание и критерии каждой задачи — `docs/tasks/<ID>.md`; правила — `CLAUDE.md`, `.claude/agents/*.md`, тест `tests/unit/arch/test_backlog_tasks.gd`. Статусы после приёмки 2026-10-05: T-149 `done`, T-150/T-154/T-143 `in-progress` (дефекты), T-160 `review`, новая T-164 `in-progress`. `main` = 2ec4ca6 (T-160 влита, полный GUT 3637/3637). Незаконченная работа сохранена WIP-коммитами в локальных ветках контейнера (на GitHub не запушены — при закрытии контейнера пропадут):
- `work/fix-150-154` (worktree `wt-fix`): fc018b4 — приёмочные тесты tester T-149/T-150/T-154 (5 красных по дефектам); 8551e45 — WIP developer: дефекты T-150 (п.2 «Режим разработки» в release, п.3 метка «Эмулятор» на HUD), T-154 (пустой список сервисов и отказ подписки → не «подключено»), T-164 (причина отказа станка на экране устройств, REQ-DEV-07 п.1). Полный прогон не делался.
- `work/t-143-r` (worktree `wt-143r`): 4f2ac07 — повторная приёмка tester T-143 (2 красных: макушка шага 3 впереди 0.0421 м при спеке 0.02–0.04; номиналы ред. 4.6 — шорты 70 %, джерси 0.24 м); 436def1 — WIP technical-artist по обоим дефектам, тесты не прогонялись. Решение координатора: конвейер берёт номиналы спеки (У-21).
- Приёмка: T-149 — принята tester (перевести в `done`); T-150, T-154 — дефекты (вернуть в `in-progress`); T-164 — завести в бэклоге (менеджер); T-160 — влита, ждёт приёмки tester; T-143 — дефекты.
- Открыто за game-designer: метка «Эмулятор» в строке истории сдвигает название (ui.md п. 8.5 решения нет).
- Владельцу: ручные проверки T-149/T-150/T-154 (протокол tester — в отчёте приёмки; перенести в раздел 4 бэклога), журнал BLE с Garmin; вопросы Н-48 (рама и мелочи), Н-61 (а, в, г), Н-63, Н-64..Н-66, Н-68, Н-69.

Дата: 2026-10-05 (конец цикла «обратная связь владельца по 0.3.0-preview.1–3»).
Ветка: **`main`**, голова **80cf008** (после a07517f — requirements: фото-референс гонщика). Рабочая ветка `claude/quirky-goldberg-m8r1ro` совпадает с `main`; по просьбе владельца работа ведётся в `main`, оркестратор пушит каждый проверенный коммит в обе ветки. Ветка по умолчанию на GitHub пока `claude/festive-mayer-w41i04` — владелец переключит на `main` в настройках.
Последний полный прогон GUT: **3614/3614** (T-154, e0ba22a).
Последняя сборка владельцу: **0.3.0-preview.3** (8eb3dd0), CI зелёный, артефакт выдан 2026-10-04.
Последний выпуск: 0.2.0 (f1a56e5, тег v0.2.0). Следующий — **0.3 «Качество мира и персонажа»**.

Модели агентов: developer, game-designer, technical-artist — Opus, effort high; manager, requirements, tester — Opus.
Скиллы — `.claude/skills/` (`ride-visual-review`, `indoor-cycling-game-design`, сторонние).

### Сделано за цикл
- **Предварительные сборки 0.3.0-preview.1–3.** preview.1 падала при запуске на Mac (T-147: потерянные экспортом узлы вложенной сцены `AppBar`). preview.2 (cd337ca) — исправление T-147; владелец нашёл дефект импорта `.zwo`, «not connected» у пульсометра Garmin, сделал замер FPS, попросил подсказки и «линию FTP» на превью плана. preview.3 (8eb3dd0) — T-149, T-150, T-154.
- **Задачи:** T-147 `done` (8c3f88b; принято оркестратором, сверка tester — в волне приёмки); T-149 `review` (1a61702, 3578/3578), T-150 `review` (537afe6, 3573/3573), T-154 `review` (e0ba22a, 3614/3614) — приёмка tester идёт сейчас одной волной.
- **Перенос в `main`** (a07517f; см. «Чекпоинт»).
- **Решения владельца** (requirements: 53a21f8, bb02a62 и последующие; сверено менеджером в бэклоге):
  - **У-23** — целевое устройство — любой FTMS-станок; Tacx Neo владельца — эталон ручной проверки (REQ-DEV-10). Н-62 закрыт: станки без FTMS — после MVP.
  - **У-24** (Н-57 (б)) — «линия FTP» на превью плана меняет и сохраняет FTP профиля, с подтверждением (UIX-03 п.6–8, PRF-02 п.7). Открыт Н-63 (шаг 5 Вт и момент подтверждения; флаг переопределения Intervals.icu).
  - **У-25** (Н-58 (б)) — эталонный Mac для 60 FPS — **MacBook Pro M1 Pro (MacBookPro18,3)** владельца, вместо базового M1. Условие выпуска 0.3 — 20-минутный «Замер FPS» на нём после T-106a3 и T-107. Предварительный замер 180 с (115.9 FPS, > 33 мс 0.0 %, draw calls до 150) — справка.
  - **У-26** (Н-61 (б)) — если цель ограничена станком, везде (HUD, сэмпл, FIT; столбик текущего шага HUD-10 — толкование requirements, подтвердить) — фактически заданное станку значение.
- **Фото-референс гонщика 2026-10-04** (ИИ-генерация, вид сзади; приватно у владельца, `reference/rider/` в `.gitignore`, в репозиторий не кладётся): сверка — `art-bible.md` ред. 4.6 (13a0a07), требования — REQ-D3D-09 п.20–22, AVT-01 п.5, AVT-02 п.5 (a07517f). В бэклоге: T-106a3 — кадры `work` φ 0/90/180/270 и `rear34_l` φ 90 с палитрой `volga_union`, Ф6–Ф12, п.20; T-106b′ — `rear_low` φ 0/90/180/270, Ф1–Ф5; T-109 и T-106c′ — п.20 и п.22 целиком (T-106c′ — ещё п.21); контраст тёмных пресетов — новая T-163 (T-108 не возвращается). Пять главных расхождений манекена с фото (шорты, икры, шея, плечи и руки, пропорции спины) — вход T-106b′/T-106c′.
- **Новые задачи в бэклоге:** T-155..T-160 (проверка preview.2), T-161 (возможности FTMS-станка от самого станка, 0.4), T-162 (ограниченная цель — У-26, 0.4), T-163 (контраст тёмных пресетов, AVT-01 п.5).

### В работе
- **2026-10-07, решение владельца У-29 (приоритет максимальный):** тренировка по датчику мощности без управляемого станка — REQ-WRK-09 (11a0226), макет T-151 (b83e099, `review`). Решения координатора: старт A + B, гистерезис и окно привыкания только в `power_meter`, свободная езда по модели с уклоном, метка «ЭМУЛЯТОР» — в строку даты истории (в T-153). Вопросы — Н-71.
- **T-152, T-153 — `done`** (приёмка tester cacd64c в `main`, GUT 3758/3758; Д-1, Д-2 исправлены в aaf9845). В T-171 отложены Д-3 и Д-4 (Д-4 ждёт Н-72 (б)), тест отладочного текста (Н-73) и две мелочи: «SIM 50 %» в «УКЛОН», фишка «СТАНОК».
- **T-166** — ручная сессия владельца с Quarq на Mac (`in-progress`).
- Владелец 2026-10-07: по режиму без станка — только минимум. Это T-152, T-153 (один коммит: старт сразу, диалог «Нужен станок или датчик мощности», HUD без управления) и протокол T-166. Доводка по макету T-151 — T-171 (P2, бэклог). T-169, T-170 — P1.
- requirements — перенос критериев `ui.md` п. 8.9.6 / `hud.md` п. 16 в WRK-09, подпункты Н-71 (к) и далее.
- Решения владельца 2026-10-07, вслед за У-29 (requirements c2a4b2e):
  - У-30 — скорость только по модели → T-169;
  - У-31 — режима без датчиков нет;
  - У-32 — датчик мощности важнее станка во всех режимах → T-152 (`power_meter`), T-170 (`smart`).
- Отложено (WIP сохранён): ветка `work/fix-150-154` (8551e45) — дефекты T-150, T-154, T-164; после T-169 — ребейз на `main`.
- technical-artist — задачи волн 3–4 сданы (статусы по git, `main` = 80cf008, сообщены оркестратором 2026-10-05):
  - T-107 — `review`: e7112df реализация, 64ad821 приёмка tester с дефектами, e19734e исправление; ждёт повторной сверки только по дефектам;
  - T-106a1 — `review`: влита вместе с 4670aa5; вердикта tester в карточке нет — подтвердить приёмку до слияния, тогда `done`;
  - T-106a2 — `review`: 0f3eb2c, R4 6b889e7 по вердикту game-designer, спека ред. 4.5 c1c20e2; ждёт приёмки tester;
  - T-143 — `review`, **не влита**: worktree `wt-143r`, b8884f8; повторная приёмка tester f07c550 прервана паузой агентов.
  Кадры лежат в `docs/game/shots/2026-10-04-t105`, `-t106a1`, `-t106a2`, `-t107`, `-t112` (прошлая запись «shots пуст» была ошибкой — смотрел устаревшее рабочее дерево).
- В `review` (ждут tester): T-104, T-105 (сверка спек), T-106a1, T-106a2, T-107, T-143, T-108, T-112..T-116a, T-142 (T-108, T-116a, T-142 влиты в `main` из `wip/t-116a-t-108`), T-149, T-150, T-154.

### Очередь
- **developer (с 2026-10-07, У-29..У-32):** **T-170** (следующая, P1: мощность «датчик > станок» в `smart`, У-32) → T-169 (P1, скорость только по модели, У-30) → дефекты T-150, T-154, T-164 (ветка `work/fix-150-154`) → FE-C T-167 → T-168 (REQ-DEV-11) → T-161 → T-162 → T-116b; затем T-148, T-163, T-156, T-158.
- **tester:** T-170, T-169 — по мере сдачи (вперёд прочих); протокол T-166 (WRK-09 п.13, Quarq на Mac) — параллельно, к preview с T-152 и T-153; затем очередь ниже.
- **Владелец:** сессия с Quarq на Mac по протоколу T-166 на preview с T-152 и T-153; ответы Н-71.
- **game-designer:** T-155 (подсказка интервала) → T-157 («линия FTP»); Н-67 (графа манекена в таблице Ф); вердикты TA-задач 0.3; T-151 сдан (b83e099, `review`) — вердикты по визуальным критериям T-171 (P2: кадры `pm_*`, меню, история), подтвердить правило первого состояния подсказки (WRK-09 п.5 (б), Н-71 (з)).
- **technical-artist:** TA-1 — T-106a3 (+ кадры Ф6–Ф12; после приёмки T-106a2) → T-106a4 → T-109; TA-2 — правки T-143 по повторной приёмке и слияние, затем T-159 (прогрев шейдеров, P3). В отчётах T-107 и T-106a3 — максимум draw calls на «Перевале» до и после (запаса нет: 150 при пределе 150).
- **tester (после T-152, T-153):** T-150, T-154, T-164 (после ребейза `work/fix-150-154`) → повторная приёмка T-143 на `wt-143r` (прервана) → T-106a2 → сверка дефектов T-107 (e19734e) → подтверждение T-106a1 → T-160, T-148, T-163; затем `review`-хвост 0.3.
- **requirements:** Н-56 (подсказка интервала — предложено UIX-03 п.9, т.к. п.6–8 заняты «линией FTP»), Н-59 (заезды на эмуляторе), Н-50..Н-52, Н-55; WRK-09 — перенос критериев T-151 (идёт); Н-67 — если game-designer предложит расширить п.22.
- **Владелец (ручное):** проверить preview.3 (`.zwo`, эмулятор, пульсометр по разделу 4 бэклога, журнал прислать); **до T-160 не привязывать Strava, тестовые заезды на эмуляторе удалить**; 20-минутный «Замер FPS» на M1 Pro — после T-106a3 и T-107.

### Открытые вопросы владельцу (подробно — `docs/backlog.md` раздел 5)
- Гонщик (вариант Г): Н-33 (0.3 с манекеном, итоговая модель — 0.3.1), Н-42 («максимум» в MVP), Н-43 (название «Волга Юнион»), Н-44 (внешность по умолчанию), Н-45 (где хранить `rider.glb`), Н-46 (женская фигура), Н-47 (лицо), Н-48 (цвета `volga_union`); по фото-референсу — **Н-64** (права на исходный кадр: можно ли отдавать сервису генерации или подрядчику), **Н-65** (стартовый номер — рекомендация не делать), **Н-66** (дополнение к Н-48: рама `grey`/`black`, кожа `s1`/`s2`/`s3`, перчатки `none`, фляга `grey`, туфли `black`). Сырые GLB и фото серий А–Г по `rider-photo-guide.md` — держат T-106b′.
- Станок: Н-61 (а) запасной диапазон 0..2000 Вт, (в) станок без сопротивления, (г) достаточно ли эталонного Neo, (д) пометка «ограничено станком»; Н-23 (точность ERG — до T-117).
- Превью плана: Н-63 (шаг линии FTP и момент подтверждения; FTP из Intervals.icu).
- Тренировка по датчику мощности (WRK-09, У-29..У-32): Н-71 (в), (г) допуск/гистерезис, (д), (е), (к) старт A + B и метка «ЭМУЛЯТОР»; Н-72 (а)–(е) — источник мощности и скорости; FE-C: Н-70.
- Strava и эмулятор: Н-52 (б) — эмулятор в магазинной сборке.
- Публикация и прочее: Н-10 (фоновый BLE iOS), Н-24, Н-25, Н-26, решение 16 для iPad, решение 23, В-6, решение 3; P2–P3 — У-7, У-9..У-11, У-14..У-16, Н-11, Н-12. Запасной путь гонщика (только при отказе от варианта Г): Н-29..Н-32.

### Владельцу — начать сейчас (сроки не наши)
Вступить в Apple Developer Program; написать разработчику Intervals.icu об OAuth-приложении; зарегистрировать API-приложение Strava (привязывать — после T-160); фото в форме и 2–3 генерации по `docs/game/rider-photo-guide.md`, архив `reference/ai/` с условиями тарифа — приватной ссылкой; переключить ветку по умолчанию на GitHub на `main`.

### Среда
- Облако (claude.ai/code): Ubuntu 24.04 x86_64, без GPU; Godot 4.7 в `/opt/godot/godot`, xvfb + Mesa, `bpy` в `/opt/bpy` (`scripts/cloud/setup.sh`). Снимки — только `gl_compatibility` (Н-49: Forward+ — владелец на Mac).
- Только на Mac владельца: Forward+, запуск приложения macOS, замер FPS (эталон M1 Pro), Tacx Neo, iOS.
- Референсы владельца (видео, фото) — только в `reference/` (в `.gitignore`), в `docs/` и отчёты не кладутся.

### Известные мелочи (не блокируют)
- В полном прогоне GUT сообщает о нескольких orphan-узлах; источник не найден.
- `UploadQueue._queued_result` не переносит код ошибки при повторе (на экране не видно).
- Карточка заезда, уже поставленного в очередь автоматически, показывает название и описание по умолчанию, а не из элемента очереди.
- Заезд, по которому пользователь не ответил в диалоге восстановления, сам в очередь Strava не попадает; выгрузка — вручную из карточки.
- Число тестов в отчётах T-149 (3578) больше, чем у более поздней T-150 (3573) — tester сверяет полным прогоном на голове.
