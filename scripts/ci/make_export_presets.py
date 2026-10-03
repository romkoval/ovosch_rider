#!/usr/bin/env python3
"""Генерирует export_presets.cfg для CI-экспорта macOS (REQ-NFR-07, REQ-DEV-01 крит. 6).

export_presets.cfg в репозиторий не коммитится (может содержать данные подписи, см.
.gitignore), поэтому CI собирает его из шаблона platform/macos/Info.plist.template:
фрагмент между маркерами ADDITIONAL_PLIST_CONTENT_BEGIN/END уходит в опцию
application/additional_plist_content (NSBluetoothAlwaysUsageDescription, типы документов).

Подпись в Godot отключена (codesign/codesign=0): встроенный ad-hoc подписчик Godot
не читает Info.plist фреймворка расширения и оставляет неполную подпись. CI подписывает
готовый бандл системным `codesign --sign -` (ad-hoc). Нотаризации нет: сборка для
тестирования, не для распространения через App Store.

Использование: make_export_presets.py <bundle_id> <short_version> <build_number> [out]
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
PLIST_TEMPLATE = os.path.join(ROOT, "platform", "macos", "Info.plist.template")


def cfg_string(value: str) -> str:
    """Строка в формате ConfigFile Godot: кавычки и обратные слэши экранируются."""
    return '"' + value.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n") + '"'


def plist_fragment(bundle_id: str) -> str:
    text = open(PLIST_TEMPLATE, encoding="utf-8").read()
    m = re.search(r"<!-- ADDITIONAL_PLIST_CONTENT_BEGIN -->(.*?)<!-- ADDITIONAL_PLIST_CONTENT_END -->", text, re.S)
    if m is None:
        sys.exit("make_export_presets: в %s нет маркеров ADDITIONAL_PLIST_CONTENT" % PLIST_TEMPLATE)
    fragment = m.group(1)
    # Комментарии XML не нужны в итоговом Info.plist.
    fragment = re.sub(r"<!--.*?-->", "", fragment, flags=re.S)
    fragment = fragment.replace("&lt;BUNDLE_ID_MACOS&gt;", bundle_id)
    if "&lt;" in fragment or "<BUNDLE_ID" in fragment:
        sys.exit("make_export_presets: во фрагменте остались плейсхолдеры")
    if "NSBluetoothAlwaysUsageDescription" not in fragment:
        sys.exit("make_export_presets: во фрагменте нет NSBluetoothAlwaysUsageDescription")
    lines = [line.rstrip() for line in fragment.strip("\n").split("\n")]
    return "\n".join(line for line in lines if line.strip())


def main() -> None:
    if len(sys.argv) < 4:
        sys.exit(__doc__)
    bundle_id, short_version, build_number = sys.argv[1:4]
    out = sys.argv[4] if len(sys.argv) > 4 else os.path.join(ROOT, "export_presets.cfg")
    if not re.fullmatch(r"[A-Za-z0-9.-]+", bundle_id):
        sys.exit("make_export_presets: недопустимый bundle id: %s" % bundle_id)
    if not re.fullmatch(r"\d+(\.\d+){0,2}", short_version):
        sys.exit("make_export_presets: CFBundleShortVersionString должен быть вида 1.2.3: %s" % short_version)

    exclude = ", ".join([
        "tests/*", "addons/gut/*", "docs/*", "platform/*", "scripts/*",
        "native/ble/src/*", "native/ble/godot-cpp/*", "export_presets.cfg",
    ])
    options = {
        "binary_format/architecture": cfg_string("universal"),
        "application/bundle_identifier": cfg_string(bundle_id),
        "application/app_category": cfg_string("Healthcare-fitness"),
        "application/short_version": cfg_string(short_version),
        "application/version": cfg_string(build_number),
        "application/additional_plist_content": cfg_string(plist_fragment(bundle_id)),
        "display/high_res": "true",
        "codesign/codesign": "0",
        "notarization/notarization": "0",
    }
    preset = [
        "[preset.0]",
        "",
        'name="macOS"',
        'platform="macOS"',
        "runnable=true",
        "dedicated_server=false",
        'custom_features=""',
        'export_filter="all_resources"',
        'include_filter=""',
        "exclude_filter=" + cfg_string(exclude),
        'export_path="build/ovosch-rider-macos.zip"',
        "",
        "[preset.0.options]",
        "",
    ] + ["%s=%s" % (k, v) for k, v in options.items()]
    with open(out, "w", encoding="utf-8") as f:
        f.write("\n".join(preset) + "\n")
    print("make_export_presets: %s (bundle %s, version %s (%s))" % (out, bundle_id, short_version, build_number))


if __name__ == "__main__":
    main()
