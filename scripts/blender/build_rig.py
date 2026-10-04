"""Арматура `rider_rig` в Blender из контракта `assets/rider/reference/rider_contract.json`
(T-143): 25 костей — начала и окончания по таблице, крен «X кости ∥ X мира», Deform выкл. у
шести сокетов; по желанию — в A-позе контрактного скелета (подгонка к стоячему скану, шаг 3).

  /opt/bpy/bin/python scripts/blender/build_rig.py <выход.blend> [--apose] [--glb выход.glb]
  blender -b -P scripts/blender/build_rig.py -- <выход.blend> [--apose] [--glb выход.glb]
"""

import argparse
import os
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bpy  # noqa: E402

from rider_refine import common, rig  # noqa: E402
from rider_refine.contract import Contract  # noqa: E402


def main():
    p = argparse.ArgumentParser(prog="build_rig")
    p.add_argument("blend")
    p.add_argument("--apose", action="store_true", help="A-поза контрактного скелета вместо rest (посадки)")
    p.add_argument("--glb", help="ещё и экспорт арматуры в glTF (+Y Up, как бриф §12)")
    a = p.parse_args(common.script_args())
    common.quiet_bpy()
    bpy.ops.wm.read_factory_settings(use_empty=True)
    c = Contract()
    joints = c.apose_joints() if a.apose else c.rest_joints()
    arm = rig.build_armature(c, joints, rig.RIG_NAME)
    bpy.context.preferences.filepaths.save_version = 0
    bpy.ops.wm.save_as_mainfile(filepath=os.path.abspath(a.blend))
    print("build_rig: %s — %d костей, %s" % (a.blend, len(arm.data.bones), "A-поза" if a.apose else "rest контракта"))
    if a.glb:
        rig.set_active(arm)
        bpy.ops.export_scene.gltf(filepath=os.path.abspath(a.glb), export_format="GLB", use_selection=True,
                                  export_yup=True, export_def_bones=False, export_animations=False)
        print("build_rig: %s" % a.glb)


main()
