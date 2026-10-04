"""Проверка эталонного пакета assets/rider/reference/ в Blender (T-106a1, бриф разделы 4-6, 12).

Импорт glTF 2.0 с настройками по умолчанию (как сделает человек или скрипт конвейера
доводки, арт-библия «Вариант Г»), затем: оси и масштаб (бриф 4), арматура `rider_rig`
(25 костей, имена, родители, начала, оси 5.3), точки и геометрия велосипеда (раздел 6).
Числа костей — из `src/scene3d/rider_rig.gd` (таблица `BONES`, Godot → Blender:
(x, y, z) → (-x, z, y)), числа велосипеда — бриф раздел 6.

Запуск (Blender как модуль bpy или сам Blender):
  /opt/bpy/bin/python scripts/dev/check_rider_pack_blender.py [каталог=assets/rider/reference]
  blender -b -P scripts/dev/check_rider_pack_blender.py -- [каталог]
Код выхода 0 — всё в допуске, 1 — есть ошибки (строки FAIL).
"""

import math
import os
import re
import sys

import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
MM = 0.001
BRIEF_POINTS = {
    "pt_bb": (0.0, 0.0, 0.27),
    "pt_saddle_S": (0.0, 0.23, 0.965),
    "pt_grip_L": (0.21, -0.62, 0.885),
    "pt_grip_R": (-0.21, -0.62, 0.885),
    "pt_cleat_R_pedal_axis": (-0.115, -0.17, 0.27),
    "pt_axle_rear": (0.0, 0.405, 0.335),
    "pt_axle_front": (0.0, -0.585, 0.335),
}
CHAIN = {"pelvis": "spine", "spine": "chest", "chest": "neck", "neck": "head", "upperarm": "forearm",
         "forearm": "hand", "hand": "grip", "thigh": "shin", "shin": "foot", "hair_tail.1": "hair_tail.2"}

failures = []


def check(ok, what):
    print(("PASS " if ok else "FAIL ") + what)
    if not ok:
        failures.append(what)


def contract_bones():
    """Кость -> (родитель, начало в Blender) из таблицы `RiderRig.BONES`."""
    src = open(os.path.join(ROOT, "src", "scene3d", "rider_rig.gd"), encoding="utf-8").read()
    rows = re.findall(r'\["([\w.]+)", "([\w.]*)", Vector3\(([-\d.]+), ([-\d.]+), ([-\d.]+)\), (?:true|false)\]', src)
    return {n: (p, Vector((-float(x), float(z), float(y)))) for n, p, x, y, z in rows}


def import_glb(path):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    result = bpy.ops.import_scene.gltf(filepath=path)
    check(result == {"FINISHED"}, "%s импортируется" % os.path.basename(path))


def identity(obj):
    return (obj.matrix_world.translation.length < 1e-6 and max(abs(a) for a in obj.rotation_euler) < 1e-6
            and max(abs(s - 1.0) for s in obj.scale) < 1e-6)


def check_rig(path):
    import_glb(path)
    check(abs(bpy.context.scene.unit_settings.scale_length - 1.0) < 1e-9, "1 единица = 1 м")
    rig = bpy.data.objects.get("rider_rig")
    check(rig is not None and rig.type == "ARMATURE", "объект арматуры rider_rig")
    if rig is None:
        return
    check(identity(rig), "rider_rig: в начале координат, поворот 0, масштаб 1")
    table = contract_bones()
    bones = rig.data.bones
    check(len(table) == 25 and len(bones) == 25, "25 костей (таблица %d, файл %d)" % (len(table), len(bones)))
    worst = 0.0
    for name, (parent, head) in table.items():
        b = bones.get(name)
        if b is None:
            check(False, "кость %s" % name)
            continue
        check((b.parent.name if b.parent else "") == parent, "%s: родитель %s" % (name, parent or "—"))
        worst = max(worst, ((rig.matrix_world @ b.head_local) - head).length)
        m = b.matrix_local.to_3x3()
        check(m.col[0].x > 0.95, "%s: крен — X кости ∥ X мира (%.3f)" % (name, m.col[0].x))
        side = name[-2:] if name[-2:] in (".L", ".R") else ""
        child = CHAIN.get(name[: len(name) - len(side)] if side else name)
        if child:
            d = table[child + side][1] - head
            check(m.col[1].angle(d) < math.radians(0.1), "%s: Y кости к %s" % (name, child + side))
    check(worst < MM, "начала костей — по таблице, наибольшее отклонение %.5f м" % worst)
    left = bones.get("thigh.L")
    check(left is not None and left.head_local.x > 0, "кости .L — на +X (левая сторона гонщика)")


def check_bike(path):
    import_glb(path)
    for name in ("bike_frame", "wheel_front", "wheel_rear", "crankset"):
        obj = bpy.data.objects.get(name)
        check(obj is not None and obj.type == "MESH", "сетка %s" % name)
        if obj is not None:
            check(identity(obj), "%s: поворот 0, масштаб 1, в начале координат" % name)
            check(obj.data.name == name, "%s: имя сетки = имя объекта" % name)
            check(len(obj.data.color_attributes) == 0, "%s: без цвета вершин" % name)
    for name, want in BRIEF_POINTS.items():
        obj = bpy.data.objects.get(name)
        got = obj.matrix_world.translation if obj else None
        check(got is not None and (got - Vector(want)).length < MM, "%s = %s (%s)" % (name, want, tuple(round(v, 4) for v in got) if got else None))
    front = bpy.data.objects.get("pt_axle_front")
    check(front is not None and front.matrix_world.translation.y < 0, "велосипед смотрит в -Y (бриф 4)")
    frame = bpy.data.objects.get("bike_frame")
    if frame is None:
        return
    deps = bpy.context.evaluated_depsgraph_get()
    tree = BVHTree.FromObject(frame, deps)

    def top(x, y):
        hit = tree.ray_cast(Vector((x, y, 5.0)), Vector((0.0, 0.0, -1.0)))
        return hit[0].z if hit[0] is not None else float("nan")

    saddle = top(0.0, 0.23)
    check(abs(saddle - 0.965) <= 0.002, "верх седла под S: %.4f м (0.965 ± 0.002)" % saddle)
    for x in (0.21, -0.21):
        hood = top(x, -0.62)
        check(abs(hood + 0.015 - 0.885) <= 0.005, "ручка x=%+.2f: верх %.4f + 0.015 ≈ 0.885" % (x, hood))
    xs = [v.co.x for v in frame.data.vertices] + [v.co.x for v in bpy.data.objects["wheel_rear"].data.vertices]
    check(max(xs) - min(xs) < 0.6, "ширина велосипеда %.3f м — масштаб 1" % (max(xs) - min(xs)))


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
    pack = os.path.abspath(argv[0]) if argv else os.path.join(ROOT, "assets", "rider", "reference")
    print("Blender", bpy.app.version_string, "—", pack)
    check_rig(os.path.join(pack, "rider_rig_reference.glb"))
    check_bike(os.path.join(pack, "bike_reference.glb"))
    print("ИТОГ: %s" % ("всё в допуске" if not failures else "%d ошибок" % len(failures)))
    sys.exit(1 if failures else 0)


main()
