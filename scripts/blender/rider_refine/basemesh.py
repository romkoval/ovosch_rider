"""Шаг 4: ретопология. Базовая low-poly сетка человека строится кодом (не хранится): граф
суставов A-позы контракта → модификатор Skin (квадратные сечения, развилки в паху и плечах)
→ Subdivision ×2 (16 сегментов по окружности, 4 кольца на звено графа, сгибы колен и локтей —
кольцами у сустава) → проекция на скан (Shrinkwrap по нормалям + сглаживание) → рёбра по
границам регионов спеки (сечения плоскостями поперёк кости) → метки звена у граней для шага 8.

Запасной путь — `decimate`: децимация скана до бюджета (хуже деформация, art-bible «Вариант Г»).
"""

import math

import bmesh
import bpy
import numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree

from . import meshops, regions
from .proportions import frame, head_system, owners, ring, segments, spec_center_local, target_joints

PROJECT_LIMIT_M = 0.06
# Базовая сетка до рёбер регионов (≈ 850 треугольников на сечения, с манжетами перчаток) — бюджет body_m 8000.
BASE_BUDGET = 7050


# Узлы графа головы: ниже и выше центра габарита по оси «вверх» головы, м.
HEAD_NODE_BELOW_M = 0.07
HEAD_NODE_ABOVE_M = 0.09


def head_axis(T):
    """Центр габарита головы спеки (мир) и ось «вверх» системы головы по суставам `T`."""
    h, q, k = head_system(T)
    return Vector(h + q @ (spec_center_local() * k)), Vector(q[:, 2])


def skeleton(T):
    """Вершины графа (точка, радиус-оценка, звено, t) и рёбра. Звенья — `proportions.segments`."""
    verts, edges = [], []

    def add(p, bone, t):
        verts.append((Vector(p), bone, t))
        return len(verts) - 1

    def on(bone, a, b, t):
        return add(T[a].lerp(T[b], t), bone, t)

    hipmid = (T["thigh.L"] + T["thigh.R"]) * 0.5
    p0 = add(hipmid + Vector((0.0, 0.01, -0.02)), "pelvis", 0.0)
    sp = on("spine", "spine", "chest", 0.0)
    ch = on("chest", "chest", "neck", 0.0)
    sb = on("chest", "chest", "neck", 0.92)
    # Голова — по оси «вверх» через центр габарита спеки (0.04 вверх и вперёд от начала head):
    # ось «начало head → макушка» идёт по затылку, лицо и подбородок до неё не дотягиваются.
    hc, up = head_axis(T)
    hd = add(hc - up * HEAD_NODE_BELOW_M, "head", 0.1)
    ht = add(hc + up * HEAD_NODE_ABOVE_M, "head", 0.9)
    chain = [p0, sp, ch, sb, hd, ht]
    edges += list(zip(chain[:-1], chain[1:]))
    for s in (".L", ".R"):
        th = on("thigh" + s, "thigh" + s, "shin" + s, 0.45)
        kn = on("shin" + s, "shin" + s, "foot" + s, 0.0)
        end = on("shin" + s, "shin" + s, "foot" + s, 1.0)
        edges += [(p0, th), (th, kn), (kn, end)]
        ua = on("upperarm" + s, "upperarm" + s, "forearm" + s, 0.4)
        el = on("forearm" + s, "forearm" + s, "hand" + s, 0.0)
        wr = on("hand" + s, "hand" + s, "grip" + s, 0.0)
        tip = on("hand" + s, "hand" + s, "grip" + s, 1.9)
        edges += [(sb, ua), (ua, el), (el, wr), (wr, tip)]
    return verts, edges


def radii(verts, scan_co, T):
    """Радиус вершины графа по скану: медиана расстояния до оси звена у вершин скана рядом
    (поперёк звена ±1.5 см, своё звено — ближайшее), ×0.9 (сетка внутри скана)."""
    segs = segments()
    names = [s[0] for s in segs]
    d, t = owners(scan_co, T, segs)
    out = []
    hc, _ = head_axis(T)
    hk = names.index("head")
    _, hq, _ = head_system(T)
    for p, bone, t0 in verts:
        if bone == "head":
            # Сечение головы — в её системе, от оси через центр габарита.
            loc = (scan_co - np.array(hc)) @ hq
            pz = float((np.array(p) - np.array(hc)) @ hq[:, 2])
            sel = (d.argmin(axis=1) == hk) & (np.abs(loc[:, 2] - pz) < 0.015)
            loc = loc[sel][:, :2]
            if len(loc) < 6:
                out.append((0.04, 0.04))
                continue
            out.append((max(float(np.percentile(np.abs(loc[:, 0]), 90)), 0.02) * 0.9,
                        max(float(np.percentile(np.abs(loc[:, 1]), 90)), 0.02) * 0.9))
            continue
        loc = ring(scan_co, d, t, T, segs, bone, min(max(t0, 0.0), 1.0), slab=0.015)
        if bone in ("pelvis", "spine", "chest", "neck", "head"):
            # Корпус: соседние части (руки) не отсечь по радиусу — берём полосу целиком.
            k = names.index(bone)
            _, a, b = segs[k]
            sel = (d.argmin(axis=1) == k) & (np.abs(t[:, k] - min(max(t0, 0.0), 1.0)) * (T[b] - T[a]).length < 0.015)
            loc = ((scan_co[sel] - np.array(T[a])) @ np.array(frame(T[a], T[b])))[:, [0, 2]]
        if len(loc) < 6:
            out.append((0.04, 0.04))
            continue
        rx = float(np.percentile(np.abs(loc[:, 0]), 90))
        rz = float(np.percentile(np.abs(loc[:, 1]), 90))
        out.append((max(rx, 0.02) * 0.9, max(rz, 0.02) * 0.9))
    return out


def build_base(T, scan_co, name="base_m"):
    verts, edges = skeleton(T)
    me = bpy.data.meshes.new(name + "_skel")
    me.from_pydata([v[0] for v in verts], edges, [])
    obj = meshops.mesh_object(name + "_skel", me)
    skin = obj.modifiers.new("skin", "SKIN")
    skin.branch_smoothing = 0.0
    skin.use_smooth_shade = True
    rr = radii(verts, scan_co, T)
    for i, sv in enumerate(me.skin_vertices[0].data):
        bone = verts[i][1]
        rx, rz = rr[i]
        if bone in ("pelvis", "spine", "chest") or bone.startswith("head"):
            sv.radius = (rx, rz)
        else:
            r = (rx + rz) * 0.5
            sv.radius = (r, r)
        sv.use_root = i == 0
    sub = obj.modifiers.new("subsurf", "SUBSURF")
    sub.levels = 2
    sub.render_levels = 2
    base = meshops.evaluated_copy(obj, name)
    bpy.data.objects.remove(obj)
    bpy.data.meshes.remove(me)
    # Развилки Skin (пах, плечи) дают россыпь мелких граней: если сетка с запасом на рёбра
    # регионов не влезает в бюджет — схлопнуть самые короткие рёбра (симметрично по X).
    tris = meshops.triangle_count(base)
    if tris > BASE_BUDGET:
        tmp = meshops.mesh_object(name + "_dec", base)
        dec = tmp.modifiers.new("decimate", "DECIMATE")
        dec.ratio = BASE_BUDGET / tris
        dec.use_symmetry = True
        dec.symmetry_axis = "X"
        new = meshops.evaluated_copy(tmp, name)
        bpy.data.objects.remove(tmp)
        bpy.data.meshes.remove(base)
        base = new
    return base, len(verts), len(edges)


def wrap(obj, target, passes=(("PROJECT", 0.04, 0.5, 3), ("NEAREST_SURFACEPOINT", 0.0, 0.5, 2), ("NEAREST_SURFACEPOINT", 0.0, 0.0, 0))):
    """Проекция на скан: проходы (метод, предел, сглаживание, итерации) — сначала по нормалям
    в обе стороны (предел 4 см: дальше — чужая часть), затем к ближайшей точке, между ними
    сглаживание (иначе на стыках плеч и в паху сетка мнётся)."""
    for k, (method, limit, factor, iters) in enumerate(passes):
        sw = obj.modifiers.new("wrap%d" % k, "SHRINKWRAP")
        sw.target = target
        sw.wrap_method = method
        if method == "PROJECT":
            sw.use_negative_direction = True
            sw.use_positive_direction = True
            sw.project_limit = limit
            sw.cull_face = "OFF"
        if iters:
            sm = obj.modifiers.new("smooth%d" % k, "SMOOTH")
            sm.factor = factor
            sm.iterations = iters
    new = meshops.evaluated_copy(obj, obj.name)
    old = obj.data
    obj.modifiers.clear()
    obj.data = new
    bpy.data.meshes.remove(old)
    new.name = obj.name


def torso_at(T, arc):
    """Звено корпуса и t на дуге `arc` от S по оси pelvis → spine (суставы `T`)."""
    pl = (T["pelvis"] - T["spine"]).length
    if arc <= pl:
        return "pelvis", arc / pl
    return "spine", (arc - pl) / (T["spine"] - T["chest"]).length


def cut_planes(contract, T, cuts=None):
    """Плоскости границ регионов (A-поза): [(звено, t, имя)] — по `pipeline_data` «regions»;
    шорты и низ джерси — `cuts` (`regions.nominal_cuts`, низ джерси — после `jersey_bottom_apose`)."""
    r = contract.data["regions"]
    cuts = cuts or regions.nominal_cuts(contract)
    L = lambda a, b: (T[a] - T[b]).length  # noqa: E731
    out = []
    for s in (".L", ".R"):
        th = L("thigh" + s, "shin" + s)
        end = cuts["shorts_end_t"]
        out += [("thigh" + s, end, "shorts_end"), ("thigh" + s, end - r["shorts_gripper_m"]["value"] / th, "gripper")]
        sh = L("shin" + s, "foot" + s)
        top = sum(r["sock_top_above_ankle_m"]["range"]) / 2
        out += [("shin" + s, 1.0 - top / sh, "sock_top"), ("shin" + s, 1.0 - (top - r["sock_cuff_m"]["value"]) / sh, "sock_cuff")]
        ua = L("upperarm" + s, "forearm" + s)
        sl = sum(r["sleeve_end_t"]["range"]) / 2
        out += [("upperarm" + s, sl, "sleeve_end"), ("upperarm" + s, sl - r["jersey_cuff_m"]["value"] / ua, "jersey_cuff")]
        out.append(("forearm" + s, r["glove_cuff_t"]["value"], "glove_cuff"))
    ch = L("chest", "neck")
    band = sum(r["jersey_band_m"]["range"]) / 2
    c = r["jersey_band_center_t"]["value"]
    out += [("chest", c - band / 2 / ch, "band_lo"), ("chest", c + band / 2 / ch, "band_hi"),
            ("chest", r["jersey_yoke_t"]["value"], "yoke"), ("neck", r["collar_t"]["value"], "collar")]
    # Низ джерси: по оси корпуса от S (pelvis → spine → chest).
    out.append(torso_at(T, cuts["jersey_bottom_m"]) + ("jersey_bottom",))
    return out


def _group(bone):
    """Цепь звена: корпус с головой или конечность своей стороны."""
    if bone in ("pelvis", "spine", "chest", "neck", "head"):
        return "torso"
    side = bone[-2:]
    for limb, parts in (("leg", ("thigh", "shin", "foot")), ("arm", ("upperarm", "forearm", "hand"))):
        if bone.split(".")[0] in parts:
            return limb + side
    return bone


def _plane(T, bone, t0):
    segs = segments()
    _, a, b = segs[[s[0] for s in segs].index(bone)]
    return T[a].lerp(T[b], t0), (T[b] - T[a]).normalized()


def _cut_mask(co, T, bone, point, normal):
    """Вершины цепи звена (`_group`) и вершины не дальше CUT_BAND_M от плоскости границы."""
    segs = segments()
    names = [s[0] for s in segs]
    d, _ = owners(co, T, segs)
    group = [i for i, n in enumerate(names) if _group(n) == _group(bone)]
    return np.isin(d.argmin(axis=1), group), np.abs((co - np.array(point)) @ np.array(normal)) < CUT_BAND_M


# Режется грань своей цепи, у которой хоть одна вершина ближе этого к плоскости: длинная грань
# (на спине у сгиба корпуса — до 6 см) с дальней вершиной иначе не режется, и кольцо границы
# обходит её зубцом.
CUT_BAND_M = 0.05


# Поправка низа джерси на сгиб корпуса в rest: столько повторов «дуга в rest → поправка дуги A-позы».
JB_FIT_PASSES = 6
JB_FIT_TOL_M = 0.0002


def jersey_bottom_apose(obj, contract, T, cuts):
    """Дуга низа джерси в A-позе (м по оси корпуса от S), при которой кольцо рёбер в rest контракта
    ложится на `cuts["jersey_bottom_m"]` по оси корпуса rest («по спине», art-bible «Корпус»). В A-позе корпус
    прямой, в rest он сгибается у начала spine, и вес pelvis тянет кольцо за суставом назад к тазу:
    без поправки номинал 0.24 в rest выходит ≈ 0.232. Каждый повтор — пробная копия сетки: рез
    плоскостью, триангуляция и посадка в rest, как на шагах 4–5 (тепловые веса, DQS); мера —
    центр кольца новых вершин. Итог: (дуга A-позы, дуга кольца в rest)."""
    from . import weights
    target = cuts["jersey_bottom_m"]
    chain = [np.array(contract.head(n)) for n in ("pelvis", "spine", "chest")]
    nv = len(obj.data.vertices)

    def rest_arc(arc):
        probe = meshops.mesh_object("jb_probe", obj.data.copy())
        cut_regions(probe, contract, T, dict(cuts, jersey_bottom_m=arc), only=("jersey_bottom",))
        bm = bmesh.new()
        bm.from_mesh(probe.data)
        bmesh.ops.triangulate(bm, faces=bm.faces[:])
        bm.to_mesh(probe.data)
        bm.free()
        weights.repose_to_rest(probe, contract)
        ring_rest = meshops.verts_np(probe.data)[nv:]
        me = probe.data
        bpy.data.objects.remove(probe)
        bpy.data.meshes.remove(me)
        for arm in [a for a in bpy.data.armatures if a.users == 0]:
            bpy.data.armatures.remove(arm)
        return regions.torso_arc(ring_rest.mean(axis=0), chain)

    arc = target
    got = rest_arc(arc)
    for _ in range(JB_FIT_PASSES):
        if abs(target - got) < JB_FIT_TOL_M:
            break
        arc += target - got
        got = rest_arc(arc)
    return arc, got


def cut_regions(obj, contract, T, cuts=None, only=None, skip=()):
    """Рёбра по границам регионов: сечение граней своего звена плоскостью поперёк кости
    (`only` — только эти границы, `skip` — кроме этих; имена — `cut_planes`)."""
    count = 0
    for bone, t0, name in cut_planes(contract, T, cuts):
        if (only is not None and name not in only) or name in skip:
            continue
        point, normal = _plane(T, bone, t0)
        bm = bmesh.new()
        bm.from_mesh(obj.data)
        co = np.array([v.co[:] for v in bm.verts])
        own, near = _cut_mask(co, T, bone, point, normal)
        faces = [f for f in bm.faces if all(own[v.index] for v in f.verts) and any(near[v.index] for v in f.verts)]
        geom = list({e for f in faces for e in f.edges}) + faces + list({v for f in faces for v in f.verts})
        res = bmesh.ops.bisect_plane(bm, geom=geom, plane_co=point, plane_no=normal, dist=1e-5)
        count += sum(1 for g in res["geom_cut"] if isinstance(g, bmesh.types.BMVert))
        bmesh.ops.triangulate(bm, faces=[f for f in bm.faces if len(f.verts) > 4])
        bm.to_mesh(obj.data)
        bm.free()
    return count


def tag_faces(obj, T):
    """Метки граней для шага 8 (A-поза): звено (номер в `segments`), t вдоль звена, нормаль в
    системе звена (X — вбок, Y — вдоль, Z — вперёд/назад)."""
    me = obj.data
    segs = segments()
    n = len(me.polygons)
    cen = np.empty(n * 3)
    me.polygons.foreach_get("center", cen)
    cen = cen.reshape(-1, 3)
    nor = np.empty(n * 3)
    me.polygons.foreach_get("normal", nor)
    nor = nor.reshape(-1, 3)
    d, t = owners(cen, T, segs)
    own = d.argmin(axis=1)
    tt = t[np.arange(n), own]
    loc_n = np.empty((n, 3))
    for k, (_, a, b) in enumerate(segs):
        sel = own == k
        loc_n[sel] = nor[sel] @ np.array(frame(T[a], T[b]))
    for key, typ, vals in (("seg_bone", "INT", own.astype(np.int32)), ("seg_t", "FLOAT", tt.astype(np.float32))):
        attr = me.attributes.get(key) or me.attributes.new(key, typ, "FACE")
        attr.data.foreach_set("value", vals)
    attr = me.attributes.get("seg_n") or me.attributes.new("seg_n", "FLOAT_VECTOR", "FACE")
    attr.data.foreach_set("vector", loc_n.astype(np.float32).reshape(-1))


def project(scan_obj, contract, data):
    T = target_joints(contract)
    scan_co = meshops.verts_np(scan_obj.data)
    base, nv, ne = build_base(T, scan_co)
    base_tris = meshops.triangle_count(base)
    obj = meshops.mesh_object("body_m", base)
    base.name = "body_m"
    wrap(obj, scan_obj)
    region_cuts = regions.nominal_cuts(contract)
    cuts = cut_regions(obj, contract, T, region_cuts, skip=("jersey_bottom",))
    # Низ джерси — последним: пробная посадка в rest идёт по сетке со всеми прочими рёбрами границ.
    jb_rest = region_cuts["jersey_bottom_m"]
    region_cuts["jersey_bottom_m"], jb_got = jersey_bottom_apose(obj, contract, T, region_cuts)
    cuts += cut_regions(obj, contract, T, region_cuts, only=("jersey_bottom",))
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.triangulate(bm, faces=bm.faces[:])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    bm.to_mesh(obj.data)
    bm.free()
    tag_faces(obj, T)
    for p in obj.data.polygons:
        p.use_smooth = True
    metrics, warns = quality(obj, scan_obj, data)
    metrics.update({"graph_verts": nv, "graph_edges": ne, "base_tris": base_tris, "region_cut_verts": cuts,
                    "shorts_end_t": round(region_cuts["shorts_end_t"], 4),
                    "jersey_bottom_apose_m": round(region_cuts["jersey_bottom_m"], 4),
                    "jersey_bottom_rest_m": round(jb_got, 4)})
    if abs(jb_got - jb_rest) > 0.002:
        warns.append("низ джерси в rest %.3f м по оси корпуса, номинал %.3f — поправка на сгиб корпуса не сошлась" % (jb_got, jb_rest))
    obj["region_cuts"] = region_cuts
    return obj, metrics, warns


def quality(obj, scan_obj, data):
    me = obj.data
    tris = meshops.triangle_count(me)
    loops, nonman = meshops.boundary_loops(me)
    co = meshops.verts_np(me)
    dg = bpy.context.evaluated_depsgraph_get()
    bvh = BVHTree.FromObject(scan_obj, dg)
    dist = np.array([bvh.find_nearest(Vector(p))[3] or 0.0 for p in co])
    warns = []
    budget = data["budgets"]["tris"]["body_m"]
    if tris > budget:
        warns.append("body_m: %d треугольников > бюджета %d" % (tris, budget))
    if loops or nonman:
        warns.append("body_m: дыр %d, неманифолдных рёбер %d" % (loops, nonman))
    far = float(np.mean(dist > 0.01))
    if far > 0.05:
        warns.append("%.0f %% вершин дальше 1 см от скана — проверьте кадр шага 4" % (far * 100))
    return {"body_tris": tris, "body_verts": len(co), "holes": loops, "nonmanifold": nonman,
            "dist_to_scan_mean_mm": round(float(dist.mean()) * 1000, 2), "dist_to_scan_p95_mm": round(float(np.percentile(dist, 95)) * 1000, 2)}, warns


def decimate(scan_obj, contract, data):
    """Запасной путь: децимация скана до 95 % бюджета (кольца сгиба — вручную, T-106b′); метки
    звена у граней для шага 8 — как у проекции (рёбер по границам регионов нет: граница идёт
    по ближайшим рёбрам скана)."""
    budget = data["budgets"]["tris"]["body_m"]
    me = scan_obj.data.copy()
    obj = meshops.mesh_object("body_m", me)
    me.name = "body_m"
    n = meshops.triangle_count(me)
    mod = obj.modifiers.new("decimate", "DECIMATE")
    mod.ratio = min(1.0, 0.95 * budget / max(n, 1))
    new = meshops.evaluated_copy(obj, "body_m")
    obj.modifiers.clear()
    obj.data = new
    bpy.data.meshes.remove(me)
    new.name = "body_m"
    for p in new.polygons:
        p.use_smooth = True
    tag_faces(obj, target_joints(contract))
    metrics, warns = quality(obj, scan_obj, data)
    warns.append("децимация: колец сгиба нет, деформация хуже (запасной путь)")
    return obj, metrics, warns


def transfer_hint(scan_obj, body):
    """Подсказка цвета (текстура скана) → грани тела: ближайшая точка скана."""
    sm = scan_obj.data
    if sm.attributes.get("hint_rgb") is None:
        return
    sm.calc_loop_triangles()
    tri_poly = np.empty(len(sm.loop_triangles), dtype=np.int64)
    sm.loop_triangles.foreach_get("polygon_index", tri_poly)
    co = meshops.verts_np(sm)
    tris = meshops.tris_np(sm)
    bvh = meshops.bvh_from(co, tris)
    rgba = np.empty(len(sm.polygons) * 4, dtype=np.float32)
    sm.attributes["hint_rgb"].data.foreach_get("color", rgba)
    rgba = rgba.reshape(-1, 4)
    bm = body.data
    n = len(bm.polygons)
    cen = np.empty(n * 3)
    bm.polygons.foreach_get("center", cen)
    out = np.zeros((n, 4), dtype=np.float32)
    for i, c in enumerate(cen.reshape(-1, 3)):
        hit = bvh.find_nearest(Vector(c))
        if hit[2] is not None:
            out[i] = rgba[tri_poly[hit[2]]]
    attr = bm.attributes.get("hint_rgb") or bm.attributes.new("hint_rgb", "FLOAT_COLOR", "FACE")
    attr.data.foreach_set("color", out.reshape(-1))
