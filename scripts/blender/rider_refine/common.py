"""Общее для шагов конвейера доводки (T-143): пути, отчёт, ошибки шагов, файлы .blend."""

import json
import os
import sys
import time

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
BLENDER_DIR = os.path.join(ROOT, "scripts", "blender")
REFERENCE_DIR = os.path.join(ROOT, "assets", "rider", "reference")
CONTRACT_JSON = os.path.join(REFERENCE_DIR, "rider_contract.json")
DATA_JSON = os.path.join(BLENDER_DIR, "pipeline_data.json")
BIKE_GLB = os.path.join(REFERENCE_DIR, "bike_reference.glb")
RIG_GLB = os.path.join(REFERENCE_DIR, "rider_rig_reference.glb")
WORK_ROOT = os.path.join(ROOT, "reference", "ai", "work")

# Шаги конвейера «Вариант Г», которые делает этот пакет (6, 9, 10 — T-106c′).
STEPS = [
    (1, "check", "проверка сырья"),
    (2, "clean", "очистка и нормализация"),
    (3, "proportions", "пропорции"),
    (4, "retopo", "ретопология проекцией"),
    (5, "rest", "посадка в rest"),
    (7, "weights", "веса"),
    (8, "regions", "регионы"),
    (11, "export", "сборка и экспорт"),
]
STEP_NAMES = {n: name for n, name, _ in STEPS}


class StepError(Exception):
    """Ошибка шага: номер шага, объект, что не так — конвейер останавливается."""

    def __init__(self, step, obj, what):
        super().__init__("ШАГ %d (%s): %s: %s" % (step, STEP_NAMES.get(step, "?"), obj, what))
        self.step = step
        self.obj = obj
        self.what = what


def finish(code):
    """Выход процесса с кодом `code` после сброса буферов, без штатного завершения Python.

    bpy как модуль Python (облако, /opt/bpy) падает SIGSEGV (код 139) при выходе после экспорта
    glTF: статические деструкторы Blender (`SpaceType` → `bpy_class_free`) зовут
    `PyGILState_Ensure`, когда интерпретатор уже завершён. Файлы шагов к этому моменту записаны,
    поэтому выход — `os._exit` (деструкторы не зовутся); в бинарнике Blender — то же самое."""
    try:
        sys.stdout.flush()
        sys.stderr.flush()
    finally:
        os._exit(int(code))


def run_main(main):
    """Точка входа скрипта: код выхода `main()` (None — 0; `SystemExit` argparse — его код;
    необработанное исключение — трейсбек и 1), затем `finish` — честный код без SIGSEGV."""
    import traceback
    try:
        code = main()
        code = 0 if code is None else code
    except SystemExit as e:
        code = e.code if isinstance(e.code, int) else (0 if e.code is None else 1)
    except BaseException:  # noqa: B902 — трейсбек и код 1, как у обычного Python
        traceback.print_exc()
        code = 1
    finish(code)


def script_args():
    """Аргументы скрипта и при `python script.py ...`, и при `blender -b -P script.py -- ...`."""
    if "--" in sys.argv:
        return sys.argv[sys.argv.index("--") + 1:]
    return sys.argv[1:]


def load_json(path):
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def save_json(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=1, sort_keys=False)
        f.write("\n")


def data():
    return load_json(DATA_JSON)


class Report:
    """Отчёт прогона: строка на шаг в `report.txt`, подробности — `report.json`."""

    def __init__(self, work_dir):
        self.work_dir = work_dir
        self.path_txt = os.path.join(work_dir, "report.txt")
        self.path_json = os.path.join(work_dir, "report.json")
        self.entries = load_json(self.path_json) if os.path.exists(self.path_json) else {}

    def step(self, num, status, done, metrics=None, warnings=None, seconds=0.0):
        key = "%02d_%s" % (num, STEP_NAMES.get(num, "step"))
        entry = {"status": status, "done": done, "metrics": metrics or {}, "warnings": warnings or [],
                 "seconds": round(seconds, 2)}
        self.entries[key] = entry
        self.entries = dict(sorted(self.entries.items()))
        save_json(self.path_json, self.entries)
        line = "[%s] %s: %s" % (key, status, done)
        if metrics:
            line += "; " + ", ".join("%s=%s" % (k, _fmt(v)) for k, v in metrics.items())
        for w in warnings or []:
            line += "\n    ВНИМАНИЕ: " + w
        with open(self.path_txt, "a", encoding="utf-8") as f:
            f.write(line + "\n")
        print(line, flush=True)


def _fmt(v):
    if isinstance(v, float):
        return "%.4g" % v
    if isinstance(v, (list, tuple)):
        return "[" + ", ".join(_fmt(x) for x in v) + "]"
    return str(v)


def blend_path(work_dir, num):
    return os.path.join(work_dir, "%02d_%s.blend" % (num, STEP_NAMES[num]))


def quiet_bpy():
    """Меньше служебного вывода glTF-импорта/экспорта в отчётах."""
    import logging
    logging.getLogger("glTFImporter").setLevel(logging.WARNING)
    os.environ.setdefault("BLENDER_GLTF_LOGLEVEL", "WARNING")


class Timer:
    def __enter__(self):
        self.t0 = time.time()
        return self

    def __exit__(self, *exc):
        self.seconds = time.time() - self.t0
        return False
