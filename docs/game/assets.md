# Реестр ассетов

У каждого внешнего ассета в сборке есть строка здесь: источник, лицензия, где лежит.
Ассет без лицензии, пригодной для магазинов приложений, не коммитится. Мир заезда сейчас
полностью процедурный (`src/scene3d/`), внешних 3D-ассетов нет. Шрифты GUT
(`addons/gut/fonts/`) относятся к тестовому аддону и в продукт не входят.

| Ассет | Где в проекте | Источник | Лицензия | Статус | Зачем |
|---|---|---|---|---|---|
| Inter 4.1, вариативный (оси `wght`, `opsz`), ~0.9 МБ | `assets/fonts/inter/Inter-Variable.ttf` + `OFL.txt`; рабочая копия `Inter-Variable.res` (`FontFile` с теми же байтами, TTF не импортируется); начертания — `src/ui/theme/fonts/*.tres` (`FontVariation`) | https://github.com/rsms/inter/releases | SIL OFL 1.1 | в проекте (T-060) | единый шрифт HUD и меню, `tnum`, кириллица (`hud.md` п. 5.2, `ui.md` п. 5) |
| Lucide icons 1.51.0 (SVG, 37 шт.: 32 из первого списка `ui.md` п. 7 + `chevron-up`, `chevron-down` + `info`, `triangle-alert`, `circle-alert`) | `assets/icons/lucide/*.svg` + `LICENSE` + `README.md` | https://lucide.dev, https://github.com/lucide-icons/lucide/releases/tag/1.51.0 | ISC (иконки из Feather — MIT), обе в `LICENSE` | в проекте (T-060; баннерные `info`, `triangle-alert`, `circle-alert` — T-093, из Feather) | иконки меню и HUD |
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
