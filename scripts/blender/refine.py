"""Конвейер доводки ИИ-модели гонщика (T-143): шаги 1–5, 7, 8, 11 «Варианта Г».

Запуск — `scripts/rider_refine.sh` (ищет Blender); напрямую:
  /opt/bpy/bin/python scripts/blender/refine.py <сырой.glb> [--landmarks J] [--from N] [--to M] [--work DIR] [--retopo project|decimate]
  blender -b -P scripts/blender/refine.py -- <сырой.glb> [...]
  ... --compare a.glb b.glb c.glb   — только шаг 1 по нескольким вариантам сырья, таблица и лучший.
Код выхода: 0 — шаги пройдены; 1 — ошибка шага (строка «ШАГ N …»); 2 — неверные аргументы.
"""

import argparse
import os
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from rider_refine import common  # noqa: E402
from rider_refine.steps import Run, check_raw, raw_score  # noqa: E402


def parse(argv):
    p = argparse.ArgumentParser(prog="rider_refine", description="Конвейер доводки модели гонщика (T-143)")
    p.add_argument("raw", nargs="+", help="сырой GLB/glTF/FBX/OBJ (с --compare — несколько)")
    p.add_argument("--landmarks", help="ориентиры суставов JSON (по умолчанию <имя>.landmarks.json или landmarks.json рядом)")
    p.add_argument("--from", dest="first", type=int, default=1, help="первый шаг (1, 2, 3, 4, 5, 7, 8, 11)")
    p.add_argument("--to", dest="last", type=int, default=11, help="последний шаг")
    p.add_argument("--work", help="рабочий каталог (по умолчанию reference/ai/work/<имя сырого>)")
    p.add_argument("--retopo", choices=("project", "decimate"), default="project", help="шаг 4: проекция базовой сетки или децимация")
    p.add_argument("--compare", action="store_true", help="только шаг 1 по всем файлам, выбор лучшего")
    return p.parse_args(argv)


def compare(paths, landmarks):
    rows = []
    for path in paths:
        metrics, warns, errors = check_raw(os.path.abspath(path), landmarks, common.data())
        rows.append((raw_score(metrics, warns, errors), path, metrics, warns, errors))
        print("%s: %s" % (os.path.basename(path), "НЕ ГОДИТСЯ — " + "; ".join(errors) if errors else "годится"))
        for k, v in metrics.items():
            print("    %s = %s" % (k, v))
        for w in warns:
            print("    ВНИМАНИЕ: " + w)
    rows.sort(key=lambda r: (r[0], r[1]))
    good = [r for r in rows if not r[4]]
    print("ИТОГ: %s" % ("лучший — %s" % good[0][1] if good else "ни один вариант не годится (условие отказа 1, art-bible «Вариант Г»)"))
    return 0 if good else 1


def main():
    args = parse(common.script_args())
    common.quiet_bpy()
    if args.compare:
        return compare(args.raw, args.landmarks)
    if len(args.raw) != 1:
        print("нужен один сырой файл (или --compare)", file=sys.stderr)
        return 2
    steps = [n for n, _, _ in common.STEPS]
    if args.first not in steps or args.last not in steps or args.first > args.last:
        print("--from/--to: шаги %s (6, 9, 10 — T-106c′)" % steps, file=sys.stderr)
        return 2
    raw = os.path.abspath(args.raw[0])
    work = os.path.abspath(args.work) if args.work else os.path.join(common.WORK_ROOT, os.path.splitext(os.path.basename(raw))[0])
    os.makedirs(work, exist_ok=True)
    if args.first == 1:
        for f in ("report.txt", "report.json", "state.json"):
            if os.path.exists(os.path.join(work, f)):
                os.remove(os.path.join(work, f))
    run = Run(raw, work, args.landmarks, args.retopo)
    print("rider_refine: %s → %s, шаги %d–%d" % (raw, work, args.first, args.last), flush=True)
    for n in steps:
        if args.first <= n <= args.last:
            with common.Timer() as t:
                try:
                    getattr(run, "step%d" % n)()
                except common.StepError as e:
                    print(str(e), file=sys.stderr, flush=True)
                    return 1
            print("    шаг %d: %.1f с" % (n, t.seconds), flush=True)
    print("rider_refine: готово — %s" % work)
    return 0


sys.exit(main())
