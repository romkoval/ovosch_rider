"""Шаг 5 (посадка в rest) и шаг 7 (веса): арматура, автоматические веса, седло, контрольные позы."""

import bpy
import numpy as np
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree
from mathutils.kdtree import KDTree

from . import common, meshops, rig
from .contract import bone_matrix

BIKE_COLLECTION = "bike_reference"


def auto_weights_raw(body, armature, exclude=()):
    """Автоматические веса Blender (Bone Heat) на деформирующие кости; кости `exclude` на время
    без Deform. Итог — число вершин без весов (решение не найдено)."""
    saved = {}
    for b in armature.data.bones:
        if b.name in exclude:
            saved[b.name] = b.use_deform
            b.use_deform = False
    body.vertex_groups.clear()
    body.parent = None
    for m in list(body.modifiers):
        body.modifiers.remove(m)
    rig.set_active(armature)
    body.select_set(True)
    bpy.ops.object.parent_set(type="ARMATURE_AUTO")
    for name, val in saved.items():
        armature.data.bones[name].use_deform = val
    return unweighted(body)


def weight_matrix(body):
    """Веса как плотная матрица N × G (G — группы по индексу)."""
    n = len(body.data.vertices)
    w = np.zeros((n, len(body.vertex_groups)), dtype=np.float64)
    for v in body.data.vertices:
        for g in v.groups:
            w[v.index, g.group] = g.weight
    return w


def unweighted(body):
    return int(sum(1 for v in body.data.vertices if not any(g.weight > 0.0 for g in v.groups)))


def write_weights(body, w, names):
    body.vertex_groups.clear()
    groups = [body.vertex_groups.new(name=n) for n in names]
    for gi, g in enumerate(groups):
        idx = np.nonzero(w[:, gi] > 0.0)[0]
        for i in idx:
            g.add([int(i)], float(w[i, gi]), "REPLACE")


def limit_normalize(body, contract, armature, max_inf=4, prune=1e-3):
    """≤ max_inf влияний на вершину, сумма 1, без сокетов и костей вне `allowed`; вершины без
    весов — вес 1 на ближайшую кость (по отрезку кости)."""
    names = [g.name for g in body.vertex_groups]
    w = weight_matrix(body)
    allowed = [i for i, n in enumerate(names) if n in contract.by_name and contract.deform(n)
               and not n.startswith("hair_tail")]
    keep = np.zeros(len(names), dtype=bool)
    keep[allowed] = True
    w[:, ~keep] = 0.0
    w[w < prune] = 0.0
    if w.shape[1] > max_inf:
        idx = np.argsort(-w, axis=1)[:, max_inf:]
        np.put_along_axis(w, idx, 0.0, axis=1)
    s = w.sum(axis=1)
    fixed = int((s <= 0).sum())
    if fixed:
        co = meshops.verts_np(body.data)
        bones = [n for n in names if n in contract.by_name and keep[names.index(n)]]
        dist = np.stack([meshops.seg_dist(co, np.array(armature.data.bones[b].head_local),
                                          np.array(armature.data.bones[b].tail_local))[0] for b in bones], axis=1)
        for i in np.nonzero(s <= 0)[0]:
            w[i, names.index(bones[int(dist[i].argmin())])] = 1.0
        s = w.sum(axis=1)
    w = w / s[:, None]
    used = [i for i in range(len(names)) if w[:, i].any()]
    order = [n for n in contract.order if n in names and names.index(n) in used]
    write_weights(body, w[:, [names.index(n) for n in order]], order)
    infl = int((w > 0).sum(axis=1).max())
    return {"max_influences": infl, "weight_groups": len(order), "verts_fixed_nearest": fixed}


def apply_armature(body):
    """Применить деформацию арматуры (позу) к сетке: новая сетка вместо старой."""
    new = meshops.evaluated_copy(body, body.data.name)
    old = body.data
    name = old.name
    for m in list(body.modifiers):
        body.modifiers.remove(m)
    body.data = new
    bpy.data.meshes.remove(old)
    new.name = name
    body.parent = None
    body.matrix_world = Matrix.Identity(4)
    body.vertex_groups.clear()


def repose_to_rest(body, contract):
    """A-поза → rest контракта: временная арматура в A-позе, веса теплом, поза = rest
    контракта (каждая кость жёстко, длины равны), деформация с сохранением объёма (DQS)."""
    fit = rig.build_armature(contract, contract.apose_joints(), "fit_rig")
    missing = auto_weights_raw(body, fit, exclude=[n for n in contract.order if n.startswith("hair_tail")])
    stats = limit_normalize(body, contract, fit)
    mod = next(m for m in body.modifiers if m.type == "ARMATURE")
    mod.use_deform_preserve_volume = True
    rig.pose_to(fit, {n: contract.rest_matrix(n) for n in contract.order})
    worst = max((fit.matrix_world @ fit.pose.bones[n].head - contract.head(n)).length for n in contract.order)
    apply_armature(body)
    bpy.data.objects.remove(fit)
    warns = []
    if missing:
        warns.append("тепловые веса не нашли решения для %d вершин — ближайшая кость" % missing)
    if worst > 1e-4:
        raise common.StepError(5, "fit_rig", "поза не совпала с rest контракта: %.5f м" % worst)
    return {"pose_err_m": round(worst, 6), "temp_unweighted": missing, "temp_max_influences": stats["max_influences"]}, warns


def import_bike():
    """`bike_reference.glb` в коллекцию `bike_reference` (не экспортируется)."""
    if BIKE_COLLECTION in bpy.data.collections:
        return bpy.data.collections[BIKE_COLLECTION]
    col = bpy.data.collections.new(BIKE_COLLECTION)
    bpy.context.scene.collection.children.link(col)
    layer = bpy.context.view_layer.layer_collection.children[BIKE_COLLECTION]
    prev = bpy.context.view_layer.active_layer_collection
    bpy.context.view_layer.active_layer_collection = layer
    bpy.ops.import_scene.gltf(filepath=common.BIKE_GLB)
    bpy.context.view_layer.active_layer_collection = prev
    for o in col.objects:
        o.hide_select = True
    return col


def saddle_tree():
    import_bike()
    seat = bpy.data.objects.get("saddle")
    if seat is None:
        raise common.StepError(5, "bike_reference.glb", "нет узла saddle (пакет T-143) — пересоберите ./scripts/rider_artist_kit.sh")
    dg = bpy.context.evaluated_depsgraph_get()
    return BVHTree.FromObject(seat, dg)


def saddle_top(tree, co):
    """Верх седла над каждой точкой (NaN — точка не над седлом)."""
    out = np.full(len(co), np.nan)
    down = Vector((0.0, 0.0, -1.0))
    for i, p in enumerate(co):
        hit = tree.ray_cast(Vector((p[0], p[1], 5.0)), down)
        if hit[0] is not None:
            out[i] = hit[0].z
    return out


def seat_on_saddle(body, contract):
    """Таз и шорты на седле: вершины над седлом ниже его верха (до 10 см) поднимаются на верх
    + зазор (ягодицы приплюснуты), соседи — плавно (спад 8 см)."""
    seat = contract.data["seat"]
    clear = seat["seat_clearance_m"]
    tree = saddle_tree()
    me = body.data
    co = meshops.verts_np(me)
    top = saddle_top(tree, co)
    over = ~np.isnan(top)
    low = over & (co[:, 2] < top + clear) & (co[:, 2] > top - 0.10)
    depth_before = float(np.nanmax(np.where(low, top - co[:, 2], np.nan))) if low.any() else 0.0
    disp = np.zeros(len(co))
    disp[low] = top[low] + clear - co[low, 2]
    if low.any():
        kd = KDTree(int(low.sum()))
        idx = np.nonzero(low)[0]
        for j, i in enumerate(idx):
            kd.insert(Vector(co[i]), j)
        kd.balance()
        fall = 0.08
        for i in np.nonzero(~low)[0]:
            p, j, d = kd.find(Vector(co[i]))
            if d < fall:
                disp[i] = max(disp[i], disp[idx[j]] * (1.0 - d / fall) ** 2)
    co[:, 2] += disp
    meshops.set_verts_np(me, co)
    top2 = saddle_top(tree, co)
    m = ~np.isnan(top2) & (co[:, 2] > top2 - 0.12)
    min_gap = float(np.min(co[m, 2] - top2[m])) if m.any() else None
    s = contract.head("pelvis")
    s_top = saddle_top(tree, np.array([s[:]]))[0]
    return {"seat_moved_verts": int(low.sum()), "seat_depth_before_m": round(depth_before, 4),
            "seat_min_gap_m": round(min_gap, 4) if min_gap is not None else None,
            "s_above_saddle_m": round(float(s.z - s_top), 4)}


def auto_weights(body, armature, contract):
    """Шаг 7: тепловые веса на 17 костей тела (сокеты и хвост — без весов), ≤ 4 влияний, сумма 1."""
    exclude = [n for n in contract.order if n.startswith("hair_tail")]
    missing = auto_weights_raw(body, armature, exclude)
    pinned = pin_seat_to_pelvis(body)
    stats = limit_normalize(body, contract, armature, contract.data["budgets"]["max_influences"])
    stats["seat_pinned_verts"] = pinned
    mod = next(m for m in body.modifiers if m.type == "ARMATURE")
    mod.object = armature
    body.parent = armature
    body.matrix_parent_inverse = Matrix.Identity(4)
    warns = []
    if missing:
        warns.append("тепловые веса не нашли решения для %d вершин — вес на ближайшую кость" % missing)
    stats["heat_unweighted"] = missing
    return stats, warns


SEAT_PIN_M = 0.04


def pin_seat_to_pelvis(body):
    """Ягодицы на седле — на `pelvis`: вершины над седлом ближе SEAT_PIN_M к его верху получают
    вес pelvis с долей 1 − высота / SEAT_PIN_M (иначе вес бедра при отведённой назад ноге
    утапливает их в седло; бриф 5.3, 5.4 — таз не глубже 0.5 см)."""
    tree = saddle_tree()
    co = meshops.verts_np(body.data)
    top = saddle_top(tree, co)
    h = co[:, 2] - top
    zone = ~np.isnan(top) & (h < SEAT_PIN_M) & (h > -0.02)
    if not zone.any():
        return 0
    names = [g.name for g in body.vertex_groups]
    if "pelvis" not in names:
        body.vertex_groups.new(name="pelvis")
        names.append("pelvis")
    w = weight_matrix(body)
    f = np.clip(1.0 - h / SEAT_PIN_M, 0.0, 1.0)
    f[~zone] = 0.0
    w = w * (1.0 - f[:, None])
    w[:, names.index("pelvis")] += f
    write_weights(body, w, names)
    return int(zone.sum())


def dominant(body):
    """Кость с наибольшим весом у каждой вершины (имя)."""
    names = [g.name for g in body.vertex_groups]
    w = weight_matrix(body)
    return np.array(names, dtype=object)[w.argmax(axis=1)]


def leg_targets(contract, pose):
    """Матрицы thigh, shin, foot обеих ног для контрольной позы (`rider_contract.json`)."""
    out = {}
    for side in (".L", ".R"):
        p = {k: Vector(v) for k, v in pose[side[1]].items() if isinstance(v, list)}
        out["thigh" + side] = bone_matrix(p["hip"], p["knee"], contract.axis_z("thigh" + side))
        out["shin" + side] = bone_matrix(p["knee"], p["ankle"], contract.axis_z("shin" + side))
        rest_sole = contract.head("cleat" + side) - contract.head("heel" + side)
        q = rest_sole.rotation_difference(p["cleat"] - p["heel"])
        m = (q.to_matrix() @ contract.rest_matrix("foot" + side).to_3x3()).to_4x4()
        m.translation = p["ankle"]
        out["foot" + side] = m
    return out


def posed_coords(body):
    dg = bpy.context.evaluated_depsgraph_get()
    ev = body.evaluated_get(dg)
    me = ev.to_mesh()
    co = meshops.verts_np(me)
    n = len(me.polygons)
    fn = np.empty(n * 3)
    me.polygons.foreach_get("normal", fn)
    vn = np.empty(len(me.vertices) * 3)
    me.vertices.foreach_get("normal", vn)
    tris = meshops.tris_np(me)
    ev.to_mesh_clear()
    return co, fn.reshape(-1, 3), vn.reshape(-1, 3), tris


def control_pose_report(body, armature, contract):
    """Контрольные позы брифа 5.4 (φ 0/90/180/270): вывернутые грани (нормаль грани против
    нормалей её вершин), таз (вершины с главной костью pelvis) и бёдра глубже верха седла,
    наименьший зазор бедро — живот (spine, chest)."""
    tree = saddle_tree()
    dom = dominant(body)
    pelvis_only = dom == "pelvis"
    torso = np.isin(dom, ["spine", "chest"])
    thighs = np.isin(dom, ["thigh.L", "thigh.R"])
    poses = {p["phi_deg"]: p for p in contract.json["control_poses"]}
    me = body.data
    starts = [p.vertices[:] for p in me.polygons]
    out = {}

    def inverted(fn, vn):
        return sum(1 for fi, vs in enumerate(starts) if np.dot(fn[fi], vn[list(vs)].mean(axis=0)) < 0.0)

    rig.reset_pose(armature)
    _, fn0, vn0, _ = posed_coords(body)
    base = inverted(fn0, vn0)
    out["rest_inverted_faces"] = base
    for phi in (0, 90, 180, 270):
        rig.reset_pose(armature)
        rig.pose_to(armature, leg_targets(contract, poses[phi]))
        co, fn, vn, _ = posed_coords(body)
        inv = max(0, inverted(fn, vn) - base)
        top = saddle_top(tree, co)
        near = ~np.isnan(top) & (co[:, 2] > top - 0.12)
        m = pelvis_only & near
        pen = float(np.max(top[m] - co[m, 2])) if m.any() else 0.0
        mt = thighs & near
        pen_t = float(np.max(top[mt] - co[mt, 2])) if mt.any() else 0.0
        kd = KDTree(int(torso.sum()))
        for j, i in enumerate(np.nonzero(torso)[0]):
            kd.insert(Vector(co[i]), j)
        kd.balance()
        gap = min(kd.find(Vector(co[i]))[2] for i in np.nonzero(thighs)[0][::3]) if thighs.any() and torso.any() else None
        out["phi%d" % phi] = {"inverted_faces_added": inv, "seat_penetration_m": round(max(pen, 0.0), 4),
                              "thigh_into_saddle_m": round(max(pen_t, 0.0), 4),
                              "thigh_belly_gap_m": round(gap, 4) if gap is not None else None}
    rig.reset_pose(armature)
    return {"control_poses": out}
