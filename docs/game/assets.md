# Реестр ассетов

У каждого внешнего ассета в сборке есть строка здесь: источник, лицензия, где лежит.
Ассет без лицензии, пригодной для магазинов приложений, не коммитится. Мир заезда сейчас
полностью процедурный (`src/scene3d/`), внешних 3D-ассетов нет. Шрифты GUT
(`addons/gut/fonts/`) относятся к тестовому аддону и в продукт не входят.

| Ассет | Где в проекте | Источник | Лицензия | Статус | Зачем |
|---|---|---|---|---|---|
| Inter 4.1, вариативный (оси `wght`, `opsz`), ~0.9 МБ | `assets/fonts/inter/Inter-Variable.ttf` + `OFL.txt`; рабочая копия `Inter-Variable.res` (`FontFile` с теми же байтами, TTF не импортируется); начертания — `src/ui/theme/fonts/*.tres` (`FontVariation`) | https://github.com/rsms/inter/releases | SIL OFL 1.1 | в проекте (T-060) | единый шрифт HUD и меню, `tnum`, кириллица (`hud.md` п. 5.2, `ui.md` п. 5) |
| Lucide icons 1.51.0 (SVG, 39 шт.: 32 из первого списка `ui.md` п. 7 + `chevron-up`, `chevron-down` + `info`, `triangle-alert`, `circle-alert` + `picture-in-picture-2`, `maximize-2`) | `assets/icons/lucide/*.svg` + `LICENSE` + `README.md` | https://lucide.dev, https://github.com/lucide-icons/lucide/releases/tag/1.51.0 | ISC (иконки из Feather — MIT), обе в `LICENSE` | в проекте (T-060; баннерные `info`, `triangle-alert`, `circle-alert` — T-093, из Feather; `picture-in-picture-2` — the «Мини» button, `maximize-2` — mini-HUD "back to full", T-177, `hud.md` 18.1–18.2, ISC) | иконки меню и HUD |
| Переключатель 44×26, бегунок слайдера 22 | файлов нет: SVG собираются в коде темы (`src/ui/theme/app_theme_builder.gd`, `_switch_icon`, `_circle_icon`) из цветов `UiTokens` | свои | свои | в проекте (T-060) | `ui.md` п. 9.1 |

Изменения Lucide относительно оригинала (подробно — `assets/icons/lucide/README.md`):
`stroke="currentColor"` заменён на `#ffffff` (цвет задаёт модуляция); три файла названы
по `ui.md` п. 7, в Lucide 1.51 у них новые имена: `waves.svg` ← `waves-horizontal`,
`history.svg` ← `rotate-ccw-clock`, `trash-2.svg` ← `trash`.

При добавлении ассета: файл лицензии кладётся рядом, строка здесь переходит в статус
«в проекте», в «О программе» (`settings_screen`, лист лицензий) появляется запись, а в
`docs/publishing/licenses.md` п. 1 — строка таблицы. Для Inter и Lucide это сделано в
T-086: «Шрифт Inter 4.1 — SIL Open Font License 1.1 (© The Inter Project Authors)» и
«Иконки Lucide 1.51 — ISC (© Lucide Icons and Contributors; часть иконок — Feather, MIT)».

Свои 3D-ассеты мира (ориентиры T-083, T-087: таблички, водопад, шале, галерея, канатная
дорога и т. п.) собираются в коде из примитивов (`src/scene3d/`). Внешних файлов нет,
поэтому строк в реестре для них нет.

## Растительность: хвойные (T-105, REQ-D3D-10)

Хвойные остаются процедурными (`SceneryBuilder`, `MeshKit`): формы, LOD и бюджет — раздел
«Растительность: хвойные» `art-bible.md`. Внешних файлов нет, строк в реестре нет.

Рассмотрены и не взяты:

| Кандидат | Лицензия | Почему не берём |
|---|---|---|
| Quaternius, Stylized Nature MegaKit (сосны Pine 1–5), https://quaternius.com/packs/stylizednaturemegakit.html | CC0 | лицензия подходит. Не подходят материалы и текстуры набора (сверх бюджета материалов D3D-05, REQ-D3D-10 п.4), нет веса контура в цвете вершин, палитра не наша, а LOD и вариации всё равно пришлось бы делать у нас. Используем только как референс разнообразия форм |
| Hand-painted хвойные с альфа-текстурой края (магазины ассетов) | платные или CC-BY | нужен материал с альфой (+1 материал, отдельный путь контура), лицензии для магазинов надо проверять поштучно |

Если в T-107 выяснится, что геометрией в бюджет треугольников не уложиться, вопрос о внешнем
ассете возвращается сюда: строка с источником и лицензией, затем `docs/publishing/licenses.md`.

## Гонщик (T-104, REQ-D3D-09)

Ред. 2 (2026-10-04, решение владельца): модель гонщика — **внешний ассет**, glTF от
художника, которого нанимает владелец. Контракт модели — раздел «Гонщик» `art-bible.md`,
ТЗ художнику — `rider-artist-brief.md`. Велосипед остаётся процедурным (`MeshKit`), строк
для него нет.

Ред. 4 (2026-10-04, решение владельца): путь модели — **вариант Г**. Тело (и шлем, туфля)
генерируются сервисом 3D по фото владельца (`rider-photo-guide.md`), доводит TA в Blender
(арт-библия, «Вариант Г»). Художник по брифу — запасной путь.

| Ассет | Где в проекте | Источник | Лицензия | Статус | Зачем |
|---|---|---|---|---|---|
| Модель гонщика `rider.glb` (фигуры `m`, `f`, причёски, шлемы, очки, туфли; скелет 25 костей) и исходник `rider.blend` | путь выбирает TA в T-106a (например `assets/rider/`) | вариант Г: сервис генерации 3D (название, тариф, дата генерации — при поступлении) по фото владельца, доводка TA; сетки, сделанные TA по спеке, — собственные. Запасной путь: заказ художнику по `rider-artist-brief.md` (ФИО или студия, номер договора) | вариант Г: условия тарифа сервиса на дату генерации (коммерческое использование, принадлежность результата; копия условий — `reference/ai/license/`, вне репозитория), фото — владелец сам на себе. Запасной путь: исключительное право заказчика по договору (бриф, раздел 16) | ожидается (съёмка и генерация владельцем) | REQ-D3D-09, REQ-AVT-01/02 |

При поступлении файла в репозиторий в том же коммите: статус «в проекте», источник и
договор в этой строке, строка в `docs/publishing/licenses.md` п. 1 (REQ-D3D-09 п.9). Если
художник использовал CC0-части (базовые сетки и т. п.), каждая — отдельной строкой с
источником. До прихода модели в сцене — временная модель TA с тем же скелетом (своя, строк
не требует).

Эталонный пакет для подготовки `rider.glb` — `assets/rider/reference/` (T-106a1: `bike_reference.glb`,
`rider_rig_reference.glb`, атласы регионов) — свои файлы, собранные сценарием
`scripts/rider_artist_kit.sh` из кода проекта; каталог с `.gdignore`, в сборку не входит, строк
не требует.

Референсы — не ассеты, в сборку не входят: кадры `shots/2026-10-03-reference/ref_1.png`,
`ref_2.png` (в репозитории), фото владельца для генерации (`reference/ai/`) и видео владельца
(на видео — сам владелец, согласие есть; `reference/`, в
`.gitignore`, в репозиторий и в `docs/` не попадает, кадры из него тоже). Что из видео взято
в спеку — раздел «Гонщик» `art-bible.md`, ред. 3. Передавать видео подрядчикам и сервисам
можно (решение владельца 2026-10-04; бриф, раздел 18).

Рассмотрены и не взяты (ред. 1, остаётся в силе):

| Кандидат | Лицензия | Почему не берём |
|---|---|---|
| Quaternius, Universal Base Characters (гуманоиды с ригом, glTF) | CC0 | лицензия подходит. Нет посадки на велосипеде, пропорции «игрушечные», нет экипировки (шлем, туфли, очки). Как базовую сетку художник может взять только с согласия заказчика (бриф, раздел 16) |
| Sketchfab Store, «Low Poly Cyclist – Remastered (Incl. Rig)» | платная лицензия магазина | не CC0 и не своя. Распространение исходника в открытом репозитории под вопросом |
| Модели велосипедистов CGTrader и TurboSquid | платные, лицензия на место | то же; стиль и состав частей не наш |

### Rider model files: rights records (REQ-D3D-09 p.9)

Format fixed 2026-10-10 (game-designer, T-106a4). One row per file of the rider model that
lies in the repository or goes into the build (`assets/rider/**` except `reference/`,
`*.import`, `*.uid`, `*.md` and dot files). Code-built files (bike, mannequin, reference pack)
get no row. The row is added in the same commit as the file; the planned row above
(«ожидается») stays as the summary of the path.

Columns, in this order:
1. **File** — the repository path of exactly one file in backticks, e.g.
   `` `assets/rider/<file>.glb` ``.
2. **Basis** — exactly one token, nothing else in the cell: `(а)` generation from photos and
   our finishing (variant Г), `(б)` freelancer contract, `(в)` third-party file. The letters are
   Cyrillic а, б, в (U+0430, U+0431, U+0432), as in REQ-D3D-09 p.9.
3. **Rights fields** — `; `-separated fields `label: value`; a value never contains `;` or `|`
   (list several items with commas):
   - `(а)`: `(1) service: …; (2) plan: …; (3) generated: …; (4) terms: …; (5) allows: …;
     (6) photos: …; (7) our work: …` — all seven, in this order, labels exactly as written.
     (3) — date of every raw model used (`body 2026-11-02, helmet 2026-11-03`); (4) — URL of
     the terms and «copy kept in reference/ai/license/»; (5) — commercial use, distribution in
     the app stores, publication in the open repository, attribution required or not; (6) —
     whose photos and the consent fact with its date (no consent text, no personal data);
     (7) — which meshes come from generation and were finished by TA, which were made by TA
     from the spec, and for `body_f` whether it is derived from `body_m` (Н-46).
   - `(б)`: `contract: <date>; author: <name, or «withheld by agreement»>`.
   - `(в)`: `licence: <name>; source: <URL>`.
4. **Status** — `in repo`, `in build` or `in repo and build`.

| File | Basis | Rights fields | Status |
|---|---|---|---|

What the `[авто]` test of REQ-D3D-09 p.9 parses (so the format above and the test agree):
- the table is the first Markdown table after the heading
  `### Rider model files: rights records (REQ-D3D-09 p.9)`, up to the next line starting with
  `#`; rows are lines starting with `|`, cells are the parts between `|` with spaces trimmed;
  columns are found by the header names `File`, `Basis`, `Rights fields`;
- the row of a file is the row whose `File` cell, with backticks removed, **equals** the
  repository path of the file (not «contains»: `rider.glb` must not match a row of
  `rider.glb.bak`); exactly one such row;
- `Basis` **equals** `(а)`, `(б)` or `(в)`;
- for `(а)`: for each n = 1…7 the `Rights fields` cell matches
  `\(N\)[^:;|]*:\s*([^;|]+)` with N replaced by the digit n, and the captured value, trimmed, is not empty and is not a
  placeholder (`—`, `–`, `-`, `?`, `…`, `...`, `TBD`, `TODO`);
- recommended, not required by p.9: for `(б)` the keys `contract` and `author`, for `(в)` the
  keys `licence` and `source` match `\bkey:\s*([^;|]+)` with a non-placeholder value.

`docs/publishing/licenses.md` (table p.1, not a game-designer file — proposal to its owner): one
row per file; the cell «Где в проекте» contains the repository path in backticks; the cell
«Лицензия» **starts with** the same basis token `(а)`, `(б)` or `(в)` followed by a short text
(e.g. «(а) terms of <service> <plan>, generation <date>»). The test reads the token at the start
of that cell instead of searching the whole row.
