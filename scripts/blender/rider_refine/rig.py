"""Арматура `rider_rig` в Blender из контракта (`rider_contract.json`): rest контракта или
A-поза; позирование по матрицам костей; веса."""

import bpy
from mathutils import Matrix

from .contract import bone_matrix

RIG_NAME = "rider_rig"


def link(obj):
    bpy.context.scene.collection.objects.link(obj)
    return obj


def set_active(obj):
    for o in bpy.context.view_layer.objects:
        o.select_set(False)
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)


def build_armature(contract, joints, name=RIG_NAME):
    """Арматура из `joints` (кость → начало, окончание, ось Z): имена, родители и Deform —
    по контракту (у сокетов Deform выкл.); кости не соединены (начала — точно по таблице)."""
    arm = bpy.data.armatures.new(name)
    obj = link(bpy.data.objects.new(name, arm))
    set_active(obj)
    bpy.ops.object.mode_set(mode="EDIT")
    ebs = {}
    for n in contract.order:
        h, t, z = joints[n]
        eb = arm.edit_bones.new(n)
        eb.head = h
        eb.tail = t
        eb.align_roll(z)
        eb.use_deform = contract.deform(n)
        eb.use_connect = False
        ebs[n] = eb
    for n in contract.order:
        par = contract.parent(n)
        if par:
            ebs[n].parent = ebs[par]
    bpy.ops.object.mode_set(mode="OBJECT")
    return obj


def build_rest_rig(contract, name=RIG_NAME):
    return build_armature(contract, contract.rest_joints(), name)


def pose_to(rig, targets):
    """Поза: кость → целевая матрица (пространство арматуры, оси и начало). Базис позы каждой
    кости — rest⁻¹ · rest_родителя · поза_родителя⁻¹ · цель (наследование поворота и масштаба)."""
    bones = rig.data.bones
    for pb in rig.pose.bones:
        b = bones[pb.name]
        target = targets.get(pb.name)
        if b.parent is None:
            parent_pose = Matrix.Identity(4)
            parent_rest = Matrix.Identity(4)
        else:
            parent_rest = b.parent.matrix_local
            parent_pose = targets.get(b.parent.name, None)
            if parent_pose is None:
                parent_pose = _pose_of(rig, targets, b.parent.name)
        if target is None:
            target = parent_pose @ parent_rest.inverted() @ b.matrix_local
            targets[pb.name] = target
        pb.matrix_basis = b.matrix_local.inverted() @ parent_rest @ parent_pose.inverted() @ target
    bpy.context.view_layer.update()


def _pose_of(rig, targets, name):
    b = rig.data.bones[name]
    if name in targets:
        return targets[name]
    if b.parent is None:
        return b.matrix_local.copy()
    return _pose_of(rig, targets, b.parent.name) @ b.parent.matrix_local.inverted() @ b.matrix_local


def joints_matrices(joints):
    return {n: bone_matrix(h, t, z) for n, (h, t, z) in joints.items()}


def reset_pose(rig):
    for pb in rig.pose.bones:
        pb.matrix_basis = Matrix.Identity(4)
    bpy.context.view_layer.update()
