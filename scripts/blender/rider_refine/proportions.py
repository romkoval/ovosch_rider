"""Шаг 3: пропорции. Скан (ориентиры суставов) → A-поза контрактного скелета (рост 1.78):
каждое звено — аффинное преобразование «звено скана → звено контракта» (сдвиг к суставу,
поворот к направлению A-позы, длина — контрактная, обхват — к таблице `m`), смешанное по
расстоянию до звеньев (гладко, без швов)."""

import math

import numpy as np
from mathutils import Matrix, Vector

from . import meshops

SIGMA_M = 0.015


def segments():
    """[(звено, сустав начала, сустав конца)]; звено — имя кости контракта."""
    segs = [("pelvis", "pelvis", "spine"), ("spine", "spine", "chest"), ("chest", "chest", "neck"),
            ("neck", "neck", "head"), ("head", "head", "crown")]
    for s in (".L", ".R"):
        segs += [("upperarm" + s, "upperarm" + s, "forearm" + s), ("forearm" + s, "forearm" + s, "hand" + s),
                 ("hand" + s, "hand" + s, "grip" + s), ("thigh" + s, "thigh" + s, "shin" + s),
                 ("shin" + s, "shin" + s, "foot" + s), ("foot" + s, "foot" + s, "cleat" + s)]
    return segs


def needed(contract=None):
    out = []
    for _, a, b in segments():
        for j in (a, b):
            if j not in out:
                out.append(j)
    return out


def frame(a, b):
    y = (b - a).normalized()
    ref = Vector((1.0, 0.0, 0.0)) if abs(y.x) < 0.95 else Vector((0.0, 1.0, 0.0))
    x = (ref - y * ref.dot(y)).normalized()
    z = x.cross(y)
    return Matrix((x, y, z)).transposed()


# Номинальные полуоси сечения звена (вбок, вперёд-назад), м: «расстояние до поверхности
# звена» = расстояние до оси − полуось в этом направлении. Без этого бок корпуса у A-позы
# ближе к оси плеча, чем к оси корпуса. Порядок величин — таблица фигур `m` (половины).
NOMINAL_R = {"pelvis": (0.17, 0.12), "spine": (0.15, 0.11), "chest": (0.17, 0.11), "neck": (0.06, 0.06),
             "head": (0.08, 0.10), "upperarm": (0.045, 0.045), "forearm": (0.035, 0.035), "hand": (0.03, 0.03),
             "thigh": (0.085, 0.09), "shin": (0.055, 0.06), "foot": (0.045, 0.05)}


def owners(co, joints, segs):
    """«Расстояние до поверхности» каждого звена (N × S, см. NOMINAL_R) и параметр t вдоль звена."""
    d = np.empty((len(co), len(segs)))
    t = np.empty((len(co), len(segs)))
    for k, (bone, a, b) in enumerate(segs):
        pa, pb = np.array(joints[a]), np.array(joints[b])
        dist, _ = meshops.seg_dist(co, pa, pb)
        t[:, k] = meshops.seg_param(co, pa, pb)
        f = np.array(frame(joints[a], joints[b]))
        loc = (co - pa) @ f
        rx, rz = NOMINAL_R[bone.split(".")[0]]
        ang = np.arctan2(loc[:, 2], loc[:, 0])
        r = rx * rz / np.sqrt((rz * np.cos(ang)) ** 2 + (rx * np.sin(ang)) ** 2)
        # За концами звена полуось сходит на нет на длине 0.5 r (непрерывно, без швов).
        length = float(np.linalg.norm(pb - pa))
        over = np.maximum(np.maximum(-t[:, k], t[:, k] - 1.0), 0.0) * length
        d[:, k] = dist - r * np.clip(1.0 - over / (0.5 * r), 0.0, 1.0)
    return d, t


def section_diameter(pts2):
    """Наибольший поперечник сечения (по 18 направлениям), м."""
    if len(pts2) < 4:
        return None
    best = 0.0
    for k in range(18):
        a = math.pi * k / 18
        p = pts2 @ np.array([math.cos(a), math.sin(a)])
        best = max(best, float(p.max() - p.min()))
    return best


def ring(co, d, t, joints, segs, bone, t0, slab=0.012):
    """Точки сечения звена у t0 в системе звена (x, z): свои вершины в полосе ±slab, без
    чужих частей рядом (дальше 1.5 × 10-го перцентиля расстояния до оси)."""
    k = [s[0] for s in segs].index(bone)
    _, a, b = segs[k]
    length = (joints[b] - joints[a]).length
    own = d.argmin(axis=1) == k
    sel = own & (np.abs(t[:, k] - t0) * length < slab)
    f = np.array(frame(joints[a], joints[b]))
    loc = ((co[sel] - np.array(joints[a])) @ f)[:, [0, 2]]
    if len(loc) < 6:
        return loc
    rad = np.linalg.norm(loc, axis=1)
    return loc[rad <= 1.5 * np.percentile(rad, 10) + 0.005]


def measure_limb(co, d, t, joints, segs, bone, t0):
    return section_diameter(ring(co, d, t, joints, segs, bone, t0))


def measure_width(co, d, z0, owners_ok, axis=0, slab=0.012):
    own = np.isin(d.argmin(axis=1), owners_ok)
    sel = own & (np.abs(co[:, 2] - z0) < slab)
    if sel.sum() < 4:
        return None
    return float(co[sel, axis].max() - co[sel, axis].min())


def measures(co, joints, segs, data):
    """Обхваты (по станциям `girth_stations`) и ширины корпуса, м."""
    d, t = owners(co, joints, segs)
    names = [s[0] for s in segs]
    out = {}
    for key, st in data["girth_stations"].items():
        if key == "ref":
            continue
        sides = ("",) if st["bone"] == "neck" else (".L", ".R")
        vals = [measure_limb(co, d, t, joints, segs, st["bone"] + sfx, st["t"]) for sfx in sides]
        vals = [v for v in vals if v]
        out[key] = sum(vals) / len(vals) if vals else None
    torso = [names.index(n) for n in ("pelvis", "spine", "chest")]
    arms = [i for i, n in enumerate(names) if n.startswith("upperarm")]
    thighs = [i for i, n in enumerate(names) if n.startswith("thigh")]
    out["pelvis_outer_m"] = measure_width(co, d, (joints["thigh.L"].z + joints["thigh.R"].z) / 2, torso + thighs)
    out["waist_width_m"] = measure_width(co, d, joints["spine"].z, torso)
    out["shoulders_outer_m"] = measure_width(co, d, (joints["upperarm.L"].z + joints["upperarm.R"].z) / 2,
                                             torso + arms + [names.index("neck")])
    hd = names.index("head")
    zc = joints["head"].lerp(joints["crown"], 0.45).z
    out["head_width_m"] = measure_width(co, d, zc, [hd], axis=0)
    out["head_length_m"] = measure_width(co, d, zc, [hd], axis=1)
    return out


def _mid(rng):
    return (rng[0] + rng[1]) * 0.5


def target_joints(contract):
    params = contract.apose_params()
    tj = contract.apose_joints(params)
    target = {n: v[0].copy() for n, v in tj.items()}
    target["crown"] = contract.crown(tj, params)
    return target


def fit(obj, lm, contract):
    """Скан в A-позу контракта. Итог: метрики, предупреждения, суставы-цели (кость → точка)."""
    data = contract.data
    fig = data["figures"]["m"]
    target = target_joints(contract)
    segs = segments()
    me = obj.data
    co = meshops.verts_np(me)
    src = {k: Vector(v) for k, v in lm.items()}
    before = measures(co, src, segs, data)
    warns = []

    def ratio(key, want):
        got = before.get(key)
        if not got:
            warns.append("не измерить %s на скане — обхват не подгоняется" % key)
            return 1.0
        r = want / got
        if not 0.8 <= r <= 1.25:
            warns.append("%s: скан %.3f м, таблица %.3f м — поправка %.2f (больше 20 %%)" % (key, got, want, r))
        return min(max(r, 0.7), 1.4)

    st = data["girth_stations"]

    def station(key):
        return (st[key]["t"], ratio(key, _mid(fig[key])))

    def shoulder_ratio():
        """Выступ дельты за плечевой сустав: (ширина по дельтам / 2 − |x сустава|), таблица / скан."""
        got = before.get("shoulders_outer_m")
        if not got:
            return 1.0
        want = _mid(fig["shoulders_outer_m"]) / 2 - abs(target["upperarm.L"].x)
        have = got / 2 - (abs(src["upperarm.L"].x) + abs(src["upperarm.R"].x)) / 2
        return min(max(want / max(have, 0.01), 0.5), 1.5)

    # Обхват звена — кусочно-линейно по t между станциями таблицы (бедро: у шорт и у колена,
    # голень: икра и лодыжка), корпус — ширины.
    g = {
        "thigh": [station("thigh_at_shorts_d_m"), station("thigh_at_knee_d_m")],
        "shin": [station("calf_d_m"), station("ankle_d_m")],
        "upperarm": [(0.0, shoulder_ratio()), station("upperarm_d_m")],
        "forearm": [station("wrist_d_m")],
        "neck": [station("neck_d_m")],
        "pelvis": [(0.0, ratio("pelvis_outer_m", _mid(fig["pelvis_outer_m"])))],
        "spine": [(0.0, ratio("waist_width_m", _mid(fig["waist_width_m"])))],
        "chest": [(0.0, ratio("shoulders_outer_m", _mid(fig["shoulders_outer_m"])))],
    }
    head_size = data["proportions"]["head_size_m"]["value"]
    g_head_x = ratio("head_width_m", head_size[0])
    g_head_z = ratio("head_length_m", head_size[2])
    d, _ = owners(co, src, segs)
    w = np.exp(-(d - d.min(axis=1, keepdims=True)) / SIGMA_M)
    w /= w.sum(axis=1, keepdims=True)
    out = np.zeros_like(co)
    for k, (bone, a, b) in enumerate(segs):
        base = bone.split(".")[0]
        ls = max((src[b] - src[a]).length, 1e-6)
        sy = (target[b] - target[a]).length / ls
        fs, ft = np.array(frame(src[a], src[b])), np.array(frame(target[a], target[b]))
        loc = (co - np.array(src[a])) @ fs
        tt = np.clip(loc[:, 1] / ls, 0.0, 1.0)
        if base in ("hand", "foot"):
            sx = sz = np.full(len(co), sy)
        elif base == "head":
            sx, sz = np.full(len(co), g_head_x), np.full(len(co), g_head_z)
        else:
            pts = g[base]
            gx = np.interp(tt, [p[0] for p in pts], [p[1] for p in pts]) if len(pts) > 1 else np.full(len(co), pts[0][1])
            sx = gx
            sz = 1.0 + 0.5 * (gx - 1.0) if base in ("pelvis", "spine", "chest") else gx
        new = np.stack((loc[:, 0] * sx, loc[:, 1] * sy, loc[:, 2] * sz), axis=1)
        out += w[:, k:k + 1] * (np.array(target[a]) + new @ ft.T)
    meshops.set_verts_np(me, out)
    after = measures(out, target, segs, data)
    height = float(out[:, 2].max())
    metrics = {"height_before_m": round(float(co[:, 2].max()), 4), "height_m": round(height, 4)}
    for key, rng in fig.items():
        if after.get(key) is not None:
            metrics[key] = round(after[key], 4)
            if not rng[0] - 0.01 <= after[key] <= rng[1] + 0.01:
                warns.append("%s после подгонки %.3f м вне таблицы m %s ± 0.01" % (key, after[key], rng))
    if abs(height - data["height_m"]["value"]) > data["height_m"]["tol"] + 0.01:
        warns.append("рост после подгонки %.3f м (контракт 1.78)" % height)
    return metrics, warns, target
