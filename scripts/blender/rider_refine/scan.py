"""Сырьё: импорт, ориентиры, оси и единицы, разбор на куски (шаги 1–2)."""

import math
import os

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector

from . import common, meshops

LEFT_RIGHT = (("thigh.L", "thigh.R"), ("upperarm.L", "upperarm.R"), ("foot.L", "foot.R"))


def import_raw(path, step):
    """Сырой файл (GLB/glTF, FBX, OBJ) в чистую сцену; все сетки — один объект `scan`
    (трансформы применены, модификаторы и арматура авто-рига сняты)."""
    if not os.path.isfile(path):
        raise common.StepError(step, path, "файла нет")
    bpy.ops.wm.read_factory_settings(use_empty=True)
    ext = os.path.splitext(path)[1].lower()
    try:
        if ext in (".glb", ".gltf"):
            res = bpy.ops.import_scene.gltf(filepath=path, merge_vertices=True)
        elif ext == ".fbx":
            res = bpy.ops.import_scene.fbx(filepath=path)
        elif ext == ".obj":
            res = bpy.ops.wm.obj_import(filepath=path)
        else:
            raise common.StepError(step, path, "формат %s не поддержан (GLB, glTF, FBX, OBJ)" % ext)
    except RuntimeError as e:
        raise common.StepError(step, path, "не импортируется: %s" % e)
    if res != {"FINISHED"}:
        raise common.StepError(step, path, "не импортируется")
    meshes = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    if not meshes:
        raise common.StepError(step, path, "в файле нет сеток")
    for o in meshes:
        for m in list(o.modifiers):
            o.modifiers.remove(m)
        o.data = o.data.copy() if o.data.users > 1 else o.data
        o.data.transform(o.matrix_world)
        o.parent = None
        o.matrix_world = Matrix.Identity(4)
        o.shape_key_clear()
    for o in list(bpy.context.scene.objects):
        if o.type != "MESH":
            bpy.data.objects.remove(o)
    meshes = sorted(meshes, key=lambda o: o.name)
    for o in bpy.context.view_layer.objects:
        o.select_set(o in meshes)
    bpy.context.view_layer.objects.active = meshes[0]
    if len(meshes) > 1:
        bpy.ops.object.join()
    obj = bpy.context.view_layer.objects.active
    obj.name = "scan"
    obj.data.name = "scan"
    # Швы UV и нормалей в файле рвут сетку на куски: склеить совпадающие вершины.
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    ext = max((max(v.co[i] for v in bm.verts) - min(v.co[i] for v in bm.verts)) for i in range(3)) if bm.verts else 1.0
    bmesh.ops.remove_doubles(bm, verts=bm.verts[:], dist=1e-6 * max(ext, 1e-3))
    bm.to_mesh(obj.data)
    bm.free()
    return obj, len(meshes)


def find_landmarks(raw_path, override=None):
    """Ориентиры: `--landmarks`, иначе `<имя>.landmarks.json`, иначе `landmarks.json` рядом."""
    cands = [override] if override else []
    stem = os.path.splitext(raw_path)[0]
    cands += [stem + ".landmarks.json", os.path.join(os.path.dirname(raw_path), "landmarks.json")]
    for c in cands:
        if c and os.path.isfile(c):
            data = common.load_json(c)
            return {k: Vector(v) for k, v in data["joints"].items()}, c
    return None, None


def _snap(rot):
    """Ближайший поворот на кратные 90° (знаковая перестановка осей) и угол до него."""
    m = np.array(rot)
    p = np.zeros((3, 3))
    used = set()
    for r in np.argsort(-np.abs(m).max(axis=1)):
        order = np.argsort(-np.abs(m[r]))
        c = next(int(c) for c in order if int(c) not in used)
        used.add(c)
        p[r, c] = 1.0 if m[r, c] >= 0 else -1.0
    snapped = Matrix(p.tolist())
    if snapped.determinant() < 0:
        return rot, 180.0
    ang = math.degrees((snapped.to_quaternion().rotation_difference(rot.to_quaternion())).angle)
    return snapped, ang


def orient(co, lm):
    """Поворот файла → оси брифа (Z вверх, лицом −Y, левая +X) и способ. По ориентирам —
    вверх: стопы → макушка/голова, влево: правые → левые суставы; без них — по форме: вверх —
    самая длинная ось (низ — где след шире), влево — вторая по длине (руки A-позы), вперёд —
    куда выступают стопы."""
    warnings = []
    if lm and all(k in lm for k in ("foot.L", "foot.R")) and ("crown" in lm or "head" in lm):
        top = lm.get("crown", lm.get("head"))
        up = (top - (lm["foot.L"] + lm["foot.R"]) * 0.5).normalized()
        left = Vector((0.0, 0.0, 0.0))
        for a, b in LEFT_RIGHT:
            if a in lm and b in lm:
                left += lm[a] - lm[b]
        left = (left - up * left.dot(up)).normalized()
        how = "ориентиры"
    else:
        ext = co.max(axis=0) - co.min(axis=0)
        ax = list(np.argsort(-ext))
        up_i, lat_i, fwd_i = int(ax[0]), int(ax[1]), int(ax[2])
        lo, hi = co[:, up_i].min(), co[:, up_i].max()
        h = hi - lo

        def width(sel):
            pts = co[sel]
            return float((pts[:, lat_i].max() - pts[:, lat_i].min()) * (pts[:, fwd_i].max() - pts[:, fwd_i].min())) if len(pts) else 0.0

        bottom = co[:, up_i] < lo + 0.08 * h
        topm = co[:, up_i] > hi - 0.08 * h
        sign = 1.0 if width(bottom) >= width(topm) else -1.0
        up = Vector((0.0, 0.0, 0.0))
        up[up_i] = sign
        base = bottom if sign > 0 else topm
        feet = co[base]
        shins = co[(np.abs((co[:, up_i] - (lo if sign > 0 else hi)) / h - 0.3) < 0.05)]
        fwd = Vector((0.0, 0.0, 0.0))
        fwd[fwd_i] = 1.0 if (feet[:, fwd_i].mean() - shins[:, fwd_i].mean()) >= 0 else -1.0
        left = (-fwd).cross(up)
        how = "форма (ориентиров нет)"
        warnings.append("оси определены по форме, без ориентиров: проверьте кадр шага 2")
    back = up.cross(left)
    rot = Matrix((left, back, up))
    snapped, ang = _snap(rot)
    if ang < 15.0:
        rot = snapped
    else:
        warnings.append("оси файла повернуты не на кратный 90° угол (%.1f°): поворот по ориентирам" % ang)
    return rot, how, warnings


def units(height, data, step, name):
    for unit, (lo, hi) in data["raw_check"]["height_units"].items():
        if lo <= height <= hi:
            return unit, {"m": 1.0, "cm": 0.01, "mm": 0.001}[unit]
    raise common.StepError(step, name, "рост %.4g ед. — не похож на человека ни в м, ни в см, ни в мм" % height)


def classify(co, tris, labels, counts, data):
    """Куски сетки: main (самый большой), slab (плоская плита), internal (внутри main),
    figure (ещё одна фигура), fragment (мелкий кусок), other."""
    h = co[:, 2].max() - co[:, 2].min()
    main_tris = tris[np.all(labels[tris] == 0, axis=1)]
    bvh = None
    rc = data["raw_check"]
    n_all = len(co)
    order = np.argsort(labels, kind="stable")
    bounds = np.searchsorted(labels[order], np.arange(len(counts) + 1))
    kinds = []
    for k in range(len(counts)):
        if k == 0:
            kinds.append("main")
            continue
        pts = co[order[bounds[k]:bounds[k + 1]]]
        ext = pts.max(axis=0) - pts.min(axis=0)
        if ext[2] < rc["slab_flat_ratio"] * h and max(ext[0], ext[1]) > 0.25 * h:
            kinds.append("slab")
        elif ext[2] > rc["second_figure_min_height"] * h:
            kinds.append("figure")
        elif counts[k] < 64:
            kinds.append("fragment")
        else:
            if bvh is None:
                bvh = meshops.bvh_from(co, main_tris)
            if all(meshops.inside(bvh, pts[i]) for i in (0, len(pts) // 2, len(pts) - 1)):
                kinds.append("internal")
            elif counts[k] < rc["fragment_max_share"] * n_all:
                kinds.append("fragment")
            else:
                kinds.append("other")
    return kinds


def footprint(co, z0, z1):
    sel = co[(co[:, 2] >= z0) & (co[:, 2] < z1)]
    if len(sel) < 3:
        return 0.0
    e = sel.max(axis=0) - sel.min(axis=0)
    return float(e[0] * e[1])


def fused_slab_top(co):
    """Верх плиты пола, слитой со стопами (None — плиты нет): след нижнего слоя много шире
    следа стоп; срез — где след сужается."""
    lo, hi = co[:, 2].min(), co[:, 2].max()
    h = hi - lo
    dz = max(0.004 * h, 0.004)
    ref = footprint(co, lo + 0.05 * h, lo + 0.06 * h)
    base = footprint(co, lo, lo + dz)
    if ref <= 0 or base < 3.0 * ref:
        return None
    z = lo
    while z < lo + 0.05 * h:
        if footprint(co, z, z + dz) < 1.6 * ref:
            return z + dz
        z += dz
    return None


def section_counts(co, tris, lm, height):
    """Сечения: ноги (середина бедра) и руки (уровень локтя) — число контуров."""
    if lm and all(k in lm for k in ("thigh.L", "shin.L", "forearm.L")):
        z_leg = (lm["thigh.L"].z + lm["shin.L"].z) * 0.5
        z_arm = lm["forearm.L"].z
        x_leg = abs(lm["thigh.L"].x) + 0.15
    else:
        z_leg = 0.39 * height
        z_arm = 0.63 * height
        x_leg = 0.25

    legs = meshops.section_loops(co, tris, (0.0, 0.0, z_leg), (0.0, 0.0, 1.0),
                                 region=lambda p: np.abs(p[:, 0]) < x_leg)
    arms = meshops.section_loops(co, tris, (0.0, 0.0, z_arm), (0.0, 0.0, 1.0))
    return legs, arms, z_leg, z_arm


def arm_angle(lm):
    if not lm or not all(k in lm for k in ("upperarm.L", "hand.L", "upperarm.R", "hand.R")):
        return None
    out = []
    for s in (".L", ".R"):
        d = lm["hand" + s] - lm["upperarm" + s]
        out.append(math.degrees(d.angle(Vector((0.0, 0.0, -1.0)))))
    return sum(out) / 2.0
