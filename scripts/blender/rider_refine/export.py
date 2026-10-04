"""Шаг 11: сборка и экспорт `rider.glb` по брифу §12 (+ `rider.blend`), затем проверки
Т1–Т7 по файлу (`glbcheck`) и, если есть, `scripts/rider_check.sh` (T-106a4)."""

import hashlib
import os
import subprocess

import bpy
from mathutils import Matrix

from . import common, glbcheck, rig

EXPORT = dict(export_format="GLB", use_selection=True, export_yup=True, export_apply=True,
              export_texcoords=True, export_normals=True, export_tangents=False, export_vertex_color="NONE",
              export_attributes=False, use_mesh_edges=False, use_mesh_vertices=False, export_materials="EXPORT",
              export_image_format="NONE", export_morph=False, export_def_bones=False,
              export_hierarchy_flatten_bones=False, export_armature_object_remove=False,
              export_rest_position_armature=True, export_skins=True, export_all_influences=False,
              export_influence_nb=4, export_animations=False, export_draco_mesh_compression_enable=False,
              export_cameras=False, export_lights=False, export_extras=False, export_leaf_bone=False)


def assemble_and_export(work, contract, glb_name="rider.glb"):
    arm = bpy.data.objects.get(rig.RIG_NAME)
    body = bpy.data.objects.get("body_m")
    if arm is None or body is None:
        raise common.StepError(11, "rider_rig/body_m", "нет арматуры или тела (шаги 7–8)")
    rig.reset_pose(arm)
    arm.matrix_world = Matrix.Identity(4)
    body.parent = arm
    body.matrix_parent_inverse = Matrix.Identity(4)
    body.matrix_basis = Matrix.Identity(4)
    if body.data.name != "body_m":
        body.data.name = "body_m"
    for o in bpy.context.view_layer.objects:
        o.select_set(o in (arm, body))
    bpy.context.view_layer.objects.active = arm
    path = os.path.join(work, glb_name)
    bpy.ops.export_scene.gltf(filepath=path, **EXPORT)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(work, os.path.splitext(glb_name)[0] + ".blend"), copy=True, compress=True)
    metrics, errors = glbcheck.check(path, contract)
    metrics["sha256"] = hashlib.sha256(open(path, "rb").read()).hexdigest()[:16]
    metrics["bytes"] = os.path.getsize(path)
    warns = ["в rider.glb только body_m: остальные 11 сеток брифа §3 (волосы, шлемы, очки, туфли, body_f) — T-106c′"]
    check = os.path.join(common.ROOT, "scripts", "rider_check.sh")
    if os.path.isfile(check):
        res = subprocess.run([check, path], capture_output=True, text=True)
        metrics["rider_check"] = res.returncode
        if res.returncode != 0:
            errors.append("rider_check.sh: код %d" % res.returncode)
    else:
        warns.append("scripts/rider_check.sh (T-106a4) ещё нет — Т1–Т7 проверены по файлу, Т8 в Godot — тест контракта")
    return metrics, warns, errors
