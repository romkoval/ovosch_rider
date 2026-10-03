# Лицензии сторонних компонентов (REQ-NFR-07 крит. 4, ТЗ раздел 3)

Все компоненты — под пермиссивными лицензиями (MIT и совместимые). Это допускает распространение
через App Store, Mac App Store, Google Play, Microsoft Store, Steam и Flathub: ни одна из них
не требует раскрытия исходного кода приложения и не конфликтует с DRM/условиями магазинов
(проблемы возникают только с GPL-семейством, которого в проекте нет). Единственное обязательство —
**сохранить уведомления об авторских правах и текст лицензии** в поставляемом продукте.

## 1. Перечень

| Компонент | Версия | Лицензия | Где в проекте | Попадает в сборку? |
| --- | --- | --- | --- | --- |
| Godot Engine | 4.7 | MIT | движок/экспортные шаблоны | да |
| Сторонние библиотеки внутри Godot (FreeType, mbedTLS, ENet, zlib/zstd, miniupnpc, …) | в составе 4.7 | MIT, Apache-2.0, BSD, FTL, zlib и др. — все пермиссивные | бинарник движка | да |
| godot-cpp | ветка 4.5 (см. `native/ble/README.md`) | MIT | `native/ble/godot-cpp` (клон, не в репозитории) → `libovosch_ble.*` | да |
| GUT (Godot Unit Test) | 9.7.1 | MIT | `addons/gut/` | **нет** — исключить из экспорта фильтром пресета; уведомление всё равно оставляем на случай попадания |
| Ассеты брендбука Strava | — | Strava Brand Guidelines (не свободная лицензия, условия использования) | `assets/branding/strava/` (после загрузки владельцем) | да — только по правилам `strava_api_checklist.md` |
| Шрифты, 3D-модели, текстуры | — | уточнить при добавлении (OFL для шрифтов, CC0/CC-BY для моделей) | `assets/` | да — дополнять таблицу при каждом добавлении |

Правило: любой новый сторонний файл в `assets/` или новая зависимость в `native/` — строка в этой таблице в том же коммите.

## 2. Тексты уведомлений для экрана «О программе»

Рекомендуемая реализация экрана: тексты движка **не копировать вручную**, а брать из ядра во время выполнения —
`Engine.get_license_text()` (полный текст лицензии Godot), `Engine.get_copyright_info()` (авторские права всех
встроенных компонентов) и `Engine.get_license_info()` (тексты их лицензий). Так уведомления всегда совпадают
с фактической версией движка. Ниже — тексты для компонентов, о которых ядро не знает, плюс краткая шапка.

### Godot Engine (MIT)

```
This software uses Godot Engine, available under the following license:

Copyright (c) 2014-present Godot Engine contributors.
Copyright (c) 2007-2014 Juan Linietsky, Ariel Manzur.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and
associated documentation files (the "Software"), to deal in the Software without restriction,
including without limitation the rights to use, copy, modify, merge, publish, distribute,
sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or
substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT
NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM,
DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
```

Плюс абзац: «Godot Engine включает сторонние компоненты; их авторские права и лицензии —
см. раздел "Third-party components"» (выводится из `Engine.get_copyright_info()`).

### godot-cpp (MIT)

```
This software uses godot-cpp (C++ bindings for the Godot Engine's GDExtensions API).

Copyright (c) 2017-present Godot Engine contributors.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and
associated documentation files (the "Software"), to deal in the Software without restriction,
including without limitation the rights to use, copy, modify, merge, publish, distribute,
sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or
substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT
NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM,
DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
```

### GUT — Godot Unit Test (MIT)

Используется только для тестов и в поставку не входит. Если `addons/gut` всё же окажется в экспорте —
уведомление (точный год и имя правообладателя взять из `addons/gut/LICENSE.md`):

```
This software may include GUT (Godot Unit Test), https://github.com/bitwes/Gut

Copyright (c) Butch Wesley (bitwes).

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and
associated documentation files (the "Software"), to deal in the Software without restriction, …
[полный текст MIT — как выше]
```

### Strava

```
Strava and the Strava logo are trademarks of Strava, Inc. This app is not affiliated with or
endorsed by Strava. "Powered by Strava" assets are used under the Strava Brand Guidelines.
```

## 3. Проверка совместимости с магазинами

| Магазин | Требование | Статус |
| --- | --- | --- |
| App Store / Mac App Store | нет copyleft, уведомления доступны пользователю (Guideline 5.2 — права на использование) | MIT/Apache/BSD — совместимы; экран «О программе» с текстами выше |
| Google Play | Open Source Notices — рекомендуемая практика (экран лицензий) | тот же экран |
| Microsoft Store | Store Policies 10.x — лицензии третьих лиц соблюдены | совместимо |
| Steam | нет требований к пермиссивным лицензиям | совместимо |
| Flathub | метаданные AppStream: `project_license` — лицензия самого приложения (`<ЛИЦЕНЗИЯ_ПРИЛОЖЕНИЯ>`, выбирает владелец: проприетарная допускается), сторонние — в `LICENSES/` | решить лицензию приложения |

Открытый вопрос владельцу: лицензия самого ovosch-rider (проприетарная / MIT / иная) — влияет только на Flathub-метаданные
и на README; на магазины Apple/Google — нет.

## 4. Чеклист

- [ ] Экран «О программе» показывает версию, разделы «Godot Engine», «Third-party components» (из `Engine.get_copyright_info()`), «godot-cpp», «Strava».
- [ ] `addons/gut`, `tests/`, `docs/`, `platform/` исключены из экспортных пресетов.
- [ ] При добавлении шрифтов/моделей — лицензия проверена и внесена в таблицу раздела 1.
- [ ] Текст MIT в разделе 2 сверен с `LICENSE.txt` Godot 4.7 и `LICENSE.md` godot-cpp актуальной ветки.
