"""Кадры результата конвейера для отчёта (T-143): `rider.blend`/`NN_*.blend` рабочего каталога с
велосипедом `bike_reference.glb`, ракурсы контракта (бриф §14; по умолчанию `work`, `side_r`),
регионы — цветами атласа-превью (только в кадре, файл не меняется). Cycles на CPU, без дисплея.

  /opt/bpy/bin/python scripts/blender/render_views.py <файл.blend> <каталог> [ракурс,...] [ширина высота]
"""

import os
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bpy  # noqa: E402

from rider_refine import common, render, weights  # noqa: E402
from rider_refine.contract import Contract  # noqa: E402


def atlas_material():
    mat = bpy.data.materials.new("M_rider_preview")
    mat.use_nodes = True
    tex = mat.node_tree.nodes.new("ShaderNodeTexImage")
    tex.image = bpy.data.images.load(os.path.join(common.REFERENCE_DIR, "rider_atlas_preview.png"))
    tex.interpolation = "Closest"
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    mat.node_tree.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.8
    return mat


def main():
    args = common.script_args()
    blend, out = os.path.abspath(args[0]), os.path.abspath(args[1])
    names = args[2].split(",") if len(args) > 2 else ["work", "side_r"]
    w, h = (int(args[3]), int(args[4])) if len(args) > 4 else (1280, 720)
    os.makedirs(out, exist_ok=True)
    bpy.ops.wm.open_mainfile(filepath=blend)
    weights.import_bike()
    body = bpy.data.objects.get("body_m")
    if body is not None and body.data.uv_layers and "M_rider" in [m.name for m in body.data.materials]:
        body.data.materials[0] = atlas_material()
    for o in bpy.data.objects:
        if o.type == "MESH" and o.name in ("scan", "raw_hair", "raw_shoes"):
            o.hide_render = True
    render.setup(w, h, samples=16)
    views = {v["name"]: v for v in Contract().json["views"]}
    for n in names:
        print("render_views:", render.view_shot(os.path.join(out, "%s.png" % n), views[n]))


main()
