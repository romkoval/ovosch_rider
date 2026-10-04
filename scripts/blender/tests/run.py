"""Тесты конвейера доводки (T-143) под bpy: `scripts/blender/test.sh` [-k шаблон] [--update-fixture].

  /opt/bpy/bin/python scripts/blender/tests/run.py [-k шаблон] [--update-fixture]
  blender -b -P scripts/blender/tests/run.py -- [...]
"""

import os
import sys
import unittest

sys.dont_write_bytecode = True
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
sys.path.insert(0, HERE)

import bpy  # noqa: E402,F401

from rider_refine import common  # noqa: E402


def main():
    args = common.script_args()
    if "--update-fixture" in args:
        os.environ["RR_UPDATE_FIXTURE"] = "1"
        args.remove("--update-fixture")
    common.quiet_bpy()
    loader = unittest.TestLoader()
    if "-k" in args:
        loader.testNamePatterns = ["*%s*" % args[args.index("-k") + 1]]
    suite = loader.discover(HERE, pattern="test_*.py", top_level_dir=HERE)
    res = unittest.TextTestRunner(verbosity=2, stream=sys.stdout).run(suite)
    print("ИТОГ: %d тестов, ошибок %d, падений %d, пропущено %d" % (res.testsRun, len(res.errors), len(res.failures), len(res.skipped)))
    return 0 if res.wasSuccessful() else 1


common.run_main(main)
