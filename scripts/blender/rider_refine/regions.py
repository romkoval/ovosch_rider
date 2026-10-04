"""Шаг 8: регионы цвета. Граница — по размерам спеки (рёбра уже прорезаны на шаге 4, у граней
метки звена `seg_bone`, `seg_t`, `seg_n` в A-позе), цвет текстуры скана — только подсказка
(волосы: линия роста по подсказке — плоскость и кольцо рёбер шага 4, метка грани `hair`; доля
несогласий — в отчёт). UV0 по атласу: U — центр колонки региона,
V = 0.5; прочие UV, цвет вершин и текстура удаляются; один материал `M_rider`."""

import math

import bpy
import numpy as np

from .proportions import segments

MATERIAL = "M_rider"


def _attr(me, key, width):
    a = me.attributes.get(key)
    if a is None:
        return None
    n = len(me.polygons)
    if width == 1:
        out = np.empty(n, dtype=np.float64 if a.data_type == "FLOAT" else np.int64)
        a.data.foreach_get("value", out)
    else:
        out = np.empty(n * width, dtype=np.float64)
        a.data.foreach_get("vector" if a.data_type == "FLOAT_VECTOR" else "color", out)
        out = out.reshape(-1, width)
    return out


def hint_class(rgb):
    """Подсказка по цвету: 'skin', 'dark', 'light', 'other'."""
    r, g, b = rgb[:, 0], rgb[:, 1], rgb[:, 2]
    mx = rgb.max(axis=1)
    skin = (r > 0.12) & (r > b * 1.6) & (r > g * 1.15) & (mx < 0.9)
    out = np.full(len(rgb), "other", dtype=object)
    out[mx < 0.08] = "dark"
    out[(mx > 0.6) & ((mx - rgb.min(axis=1)) < 0.15)] = "light"
    out[skin] = "skin"
    return out


def classify(contract, seg_bone, seg_t, seg_n, hint):
    """Регион каждой грани по правилам спеки (pipeline_data «regions»)."""
    r = contract.data["regions"]
    names = [s[0] for s in segments()]
    T = {}
    L = lambda a, b: (contract.head(a) - contract.head(b)).length  # noqa: E731
    shorts_end = sum(r["shorts_leg_end_t"]["range"]) / 2
    sock_top = sum(r["sock_top_above_ankle_m"]["range"]) / 2
    sleeve = sum(r["sleeve_end_t"]["range"]) / 2
    band = sum(r["jersey_band_m"]["range"]) / 2
    jb = sum(r["jersey_bottom_back_m"]["range"]) / 2
    lp, ls, lc = L("pelvis", "spine"), L("spine", "chest"), L("chest", "neck")
    side_cos = math.sin(math.radians(r["jersey_side_deg"]["value"]))
    cuff_t = r["glove_cuff_t"]["value"]
    hcls = hint_class(hint) if hint is not None else None
    out = np.zeros(len(seg_bone), dtype=np.int64)
    for i in range(len(seg_bone)):
        bone = names[seg_bone[i]]
        base = bone.split(".")[0]
        sx = 1.0 if bone.endswith(".L") else -1.0
        t = seg_t[i]
        n = seg_n[i]
        if base in ("pelvis", "spine", "chest"):
            s = {"pelvis": t * lp, "spine": lp + t * ls, "chest": lp + ls + t * lc}[base]
            if s < jb:
                out[i] = 8
                continue
            if base == "chest":
                c = r["jersey_band_center_t"]["value"] * lc
                if abs(t * lc - c) < band / 2:
                    out[i] = 4
                    continue
                if t > r["jersey_yoke_t"]["value"]:
                    out[i] = 5
                    continue
            out[i] = 3 if abs(n[0]) > side_cos else 2
        elif base == "neck":
            out[i] = 7 if t < r["collar_t"]["value"] else 0
        elif base == "head":
            out[i] = 0  # волосы — метка грани `hair` шага 4 (`cut_hairline`), в `assign`
        elif base == "upperarm":
            cuff = sleeve - r["jersey_cuff_m"]["value"] / L(bone, "forearm" + bone[-2:])
            out[i] = 2 if t < cuff else (6 if t < sleeve else 0)
        elif base == "forearm":
            # Манжета перчатки — плоскость поперёк предплечья (кольцо рёбер шага 4).
            out[i] = (22 if n[0] * sx < -0.3 else 21) if t >= cuff_t else 0
        elif base == "hand":
            fore = L("forearm" + bone[-2:], "hand" + bone[-2:])
            if t > r["glove_fingertip_t"]["value"]:
                out[i] = 0
            elif t * L(bone, "grip" + bone[-2:]) < (cuff_t - 1.0) * fore:
                out[i] = 0  # кисть по метке, но выше манжеты (у запястья метки звена смешаны)
            else:
                out[i] = 22 if n[0] * sx < -0.3 else 21
        elif base == "thigh":
            grip = shorts_end - r["shorts_gripper_m"]["value"] / L(bone, "shin" + bone[-2:])
            out[i] = 8 if t < grip else (9 if t < shorts_end else 0)
        elif base == "shin":
            d = (1.0 - t) * L(bone, "foot" + bone[-2:])
            out[i] = 0 if d > sock_top else (11 if d > sock_top - r["sock_cuff_m"]["value"] else 10)
        elif base == "foot":
            out[i] = 10
    return out, hcls


def hairline_plane(contract, cen, head, hcls, joints):
    """Линия роста волос — плоскость в системе головы (от центра габарита спеки): «выше» —
    rel_z − s · rel_y > a (затылок, +Y, ниже лба). Оценка по подсказке цвета: в секторах вокруг
    оси «вверх» — порог высоты с наименьшим числом несогласий с «тёмным», затем плоскость по
    порогам секторов (наименьшие квадраты). Подсказки нет или тёмного на голове < 5 % — линия
    по форме: лоб 0.06 м над центром, затылок у центра. Итог: (a, s, как)."""
    from . import proportions
    loc, _ = proportions.head_local(cen, joints)
    rel = loc - proportions.spec_center_local()
    idx = np.nonzero(head)[0]
    dark = np.zeros(len(cen), dtype=bool) if hcls is None else (hcls == "dark")
    shape = (HAIR_SHAPE_A, HAIR_SHAPE_S, "форма")
    if len(idx) == 0 or dark[idx].mean() < 0.05:
        return shape
    n_sec = contract.data["regions"]["hairline_sectors"]["value"]
    az = np.arctan2(rel[:, 0], rel[:, 1])
    width = 2 * math.pi / n_sec
    sec = np.clip(((az[idx] + math.pi) / width).astype(int), 0, n_sec - 1)
    ys, zs = [], []
    for k in range(n_sec):
        m = idx[sec == k]
        if len(m) < 3:
            continue
        z = np.sort(rel[m, 2])
        cand = np.concatenate(([z[0] - 1e-3], (z[:-1] + z[1:]) / 2, [z[-1] + 1e-3]))
        cost = [int((dark[m] & (rel[m, 2] < h)).sum() + (~dark[m] & (rel[m, 2] > h)).sum()) for h in cand]
        h = float(cand[int(np.argmin(cost))])
        if h >= z[-1]:
            continue  # сектор без волос (лицо) — линии в нём нет
        # Сектор весь в волосах (затылок до шеи) — линия по низу граней головы.
        near = m[np.abs(rel[m, 2] - max(h, z[0])) < 0.02]
        ys.append(float(np.median(rel[near, 1])))
        zs.append(h)
    if len(ys) < 6:
        return shape
    A = np.stack((np.ones(len(ys)), np.array(ys)), axis=1)
    (a, s), *_ = np.linalg.lstsq(A, np.array(zs), rcond=None)
    return float(a), float(s), "подсказка"


# Линия волос по форме (подсказки нет): лоб 0.06 м над центром головы, затылок у центра.
HAIR_SHAPE_A = 0.03
HAIR_SHAPE_S = -0.3


def cut_hairline(body, contract, joints):
    """Шаг 4: кольцо рёбер по линии роста волос (плоскость `hairline_plane` в системе головы
    A-позы) только у граней головы и метка грани `hair` (1 — волосы) — граница волосы / кожа
    идёт по рёбрам, без «пилы». Итог: метрики."""
    import bmesh

    from . import proportions
    from .basemesh import tag_faces

    me = body.data
    names = [s[0] for s in segments()]
    k = names.index("head")
    seg = _attr(me, "seg_bone", 1)
    hint = _attr(me, "hint_rgb", 4)
    hcls = hint_class(hint[:, :3]) if hint is not None else None
    cen = np.empty(len(me.polygons) * 3)
    me.polygons.foreach_get("center", cen)
    cen = cen.reshape(-1, 3)
    a, s, how = hairline_plane(contract, cen, seg == k, hcls, joints)
    h, q, _ = proportions.head_system(joints)
    point = h + q @ (proportions.spec_center_local() + np.array((0.0, 0.0, a)))
    normal = q @ np.array((0.0, -s, 1.0))
    normal = normal / np.linalg.norm(normal)
    bm = bmesh.new()
    bm.from_mesh(me)
    bm.faces.ensure_lookup_table()
    faces = [f for f in bm.faces if seg[f.index] == k]
    geom = list({e for f in faces for e in f.edges}) + faces + list({v for f in faces for v in f.verts})
    res = bmesh.ops.bisect_plane(bm, geom=geom, plane_co=point, plane_no=normal, dist=1e-5)
    cut = sum(1 for g in res["geom_cut"] if isinstance(g, bmesh.types.BMVert))
    bmesh.ops.triangulate(bm, faces=[f for f in bm.faces if len(f.verts) > 3])
    bm.to_mesh(me)
    bm.free()
    me.update()
    tag_faces(body, joints)
    seg = _attr(me, "seg_bone", 1)
    cen = np.empty(len(me.polygons) * 3)
    me.polygons.foreach_get("center", cen)
    side = (cen.reshape(-1, 3) - point) @ normal
    hair = ((seg == k) & (side > 0)).astype(np.int32)
    attr = me.attributes.get("hair") or me.attributes.new("hair", "INT", "FACE")
    attr.data.foreach_set("value", hair)
    return {"hairline": how, "hairline_a_m": round(a, 4), "hairline_slope": round(s, 3), "hairline_cut_verts": cut,
            "hair_faces": int(hair.sum())}


def assign(body, armature, contract):
    me = body.data
    seg_bone = _attr(me, "seg_bone", 1)
    if seg_bone is None:
        from . import common
        raise common.StepError(8, body.name, "нет меток звена seg_bone (шаг 4 этого конвейера)")
    seg_t = _attr(me, "seg_t", 1)
    seg_n = _attr(me, "seg_n", 3)
    hint = _attr(me, "hint_rgb", 4)
    hint = hint[:, :3] if hint is not None else None
    reg, hcls = classify(contract, seg_bone, seg_t, seg_n, hint)
    hair = _attr(me, "hair", 1)
    if hair is None:
        from . import common
        raise common.StepError(8, body.name, "нет метки волос hair (шаг 4 этого конвейера)")
    reg[hair > 0] = 1
    count = contract.json["regions"]["count"]
    # UV0: U — центр колонки, V = 0.5.
    while me.uv_layers:
        me.uv_layers.remove(me.uv_layers[0])
    uv = me.uv_layers.new(name="UVMap")
    v = contract.data["regions"]["default_v"]["value"]
    loop_reg = np.repeat(reg, [p.loop_total for p in me.polygons])
    uvs = np.stack(((loop_reg + 0.5) / count, np.full(len(loop_reg), v)), axis=1)
    uv.data.foreach_set("uv", uvs.reshape(-1))
    attr = me.attributes.get("region") or me.attributes.new("region", "INT", "FACE")
    attr.data.foreach_set("value", reg.astype(np.int32))
    for ca in list(me.color_attributes):
        me.color_attributes.remove(ca)
    me.materials.clear()
    mat = bpy.data.materials.get(MATERIAL) or bpy.data.materials.new(MATERIAL)
    mat.use_nodes = False
    mat.diffuse_color = (0.8, 0.8, 0.8, 1.0)
    me.materials.append(mat)
    for m in list(bpy.data.materials):
        if m.users == 0:
            bpy.data.materials.remove(m)
    for img in list(bpy.data.images):
        if img.users == 0 or img.name.endswith("_tex") or img.packed_file is not None:
            bpy.data.images.remove(img)
    present = sorted(int(x) for x in np.unique(reg))
    required = contract.data["regions"]["required_body"]["value"]
    warns = []
    missing = [k for k in required if k not in present]
    if missing:
        warns.append("нет регионов %s (бриф §14 Т6)" % missing)
    metrics = {"regions": present, "faces_per_region": {int(k): int((reg == k).sum()) for k in present}}
    if hcls is not None:
        skin_reg = np.isin(reg, [0])
        cloth = np.isin(reg, [2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 21, 22])
        disagree = float(np.mean(hcls[skin_reg] != "skin")) if skin_reg.any() else 0.0
        cloth_skin = float(np.mean(hcls[cloth] == "skin")) if cloth.any() else 0.0
        metrics["hint_skin_not_skin"] = round(disagree, 3)
        metrics["hint_cloth_is_skin"] = round(cloth_skin, 3)
        if disagree > 0.25 or cloth_skin > 0.25:
            warns.append("цвет скана расходится с границами спеки (кожа %.0f %%, форма %.0f %%) — проверьте кадр шага 8"
                         % (disagree * 100, cloth_skin * 100))
    return metrics, warns
