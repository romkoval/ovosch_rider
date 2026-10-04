"""Синтетический «сырой» вход конвейера доводки (T-143) — без файлов владельца.

  /opt/bpy/bin/python scripts/blender/make_synthetic.py [каталог=reference/ai/synthetic] [вариант ...]
  blender -b -P scripts/blender/make_synthetic.py -- [каталог] [вариант ...]

Варианты: m, cm, axes, bad_notex, bad_legs, bad_two (по умолчанию все). Рядом с каждым
`synthetic_<вариант>.glb` — `synthetic_<вариант>.landmarks.json`.
"""

import os
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from rider_refine import common, synthetic  # noqa: E402


def main():
    args = common.script_args()
    out = os.path.abspath(args[0]) if args else os.path.join(common.ROOT, "reference", "ai", "synthetic")
    variants = args[1:] or list(synthetic.VARIANTS)
    common.quiet_bpy()
    for v in variants:
        print("synthetic:", synthetic.build(v, out))


main()
