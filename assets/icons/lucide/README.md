# Иконки Lucide

Источник: https://lucide.dev, релиз `lucide-icons-1.51.0.zip`
(https://github.com/lucide-icons/lucide/releases/tag/1.51.0). Лицензия — ISC, иконки,
унаследованные из Feather (`check`, `chevron-*`, `clock`, `plus`, `square`, `trash-2`,
`upload`, `x` и др.), — MIT; полный текст обеих лицензий — `LICENSE` рядом.

Состав — только иконки из `docs/game/ui.md` п. 7 и шевроны `chevron-up`/`chevron-down`
для `SpinBox`/`OptionButton` (п. 9.1).

Изменения относительно оригинала:

- `stroke="currentColor"` заменён на `#ffffff`: Godot рисует `currentColor` чёрным, а цвет
  иконки задаётся модуляцией (`ui.md` п. 7).
- Три файла названы по `ui.md` п. 7, в Lucide 1.51 у них новые имена (старые — устаревшие
  алиасы): `waves.svg` ← `waves-horizontal`, `history.svg` ← `rotate-ccw-clock`,
  `trash-2.svg` ← `trash`.

Импорт — `DPITexture` (импортёр `svg`, `base_scale` 1.0): логический размер 24×24 lp,
растр строится под фактический масштаб экрана, поэтому иконка чёткая и при `ui_scale` 1.8
на экране @3x.
