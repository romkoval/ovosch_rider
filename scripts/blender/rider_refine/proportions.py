"""Шаг 3: пропорции. Скан (ориентиры суставов) → A-поза контрактного скелета (рост 1.75, ред. 4.2):
каждое звено — аффинное преобразование «звено скана → звено контракта» (сдвиг к суставу,
поворот к направлению A-позы, длина — контрактная, обхват — к таблице `m`), смешанное по
расстоянию до звеньев (гладко, без швов). Голова — целиком в своей системе (взгляд
горизонтально): поворот «макушка скана → макушка контракта», масштаб по таблице размера головы
(ширина × высота «подбородок — макушка» × длина), а не по расстоянию до макушки: макушка и рост —
следствие. Обхваты и размеры головы доводятся повтором: мера результата → поправка множителей."""

import math

import numpy as np
from mathutils import Matrix, Vector

from . import common, meshops

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


def head_numbers():
    """Голова по спеке (pipeline_data): макушка и центр габарита в системе головы (вверх, вперёд)
    от начала head, размер (ширина, высота, длина)."""
    d = common.data()
    return (d["apose"]["crown_in_head_m"]["value"], d["proportions"]["head_center_in_head_m"]["value"],
            d["proportions"]["head_size_m"]["value"])


def head_system(joints):
    """Система головы (взгляд горизонтально) по суставам head и crown: начало head, поворот
    Q (столбцы — оси головы в мире: X вбок, Y назад, Z вверх) и масштаб k (макушка скана /
    макушка спеки). Поворот — кратчайший от направления «начало head → макушка» спеки к
    направлению скана: наклон головы скана снимается, ширина, длина и высота меряются по осям
    головы."""
    (up, ahead), _, _ = head_numbers()
    v0 = Vector((0.0, -ahead, up))
    v = Vector(joints["crown"]) - Vector(joints["head"])
    q = np.array(v0.rotation_difference(v).to_matrix())
    return np.array(joints["head"]), q, v.length / v0.length


def head_local(co, joints):
    h, q, k = head_system(joints)
    return (co - h) @ q, k


def head_distance(co, joints):
    """«Расстояние до поверхности» головы — эллипсоид габарита головы спеки (центр, размер) в
    системе головы скана, масштаб k; внутри — отрицательное. Звено «начало head → макушка» для
    головы не годится: подбородок ниже начала head и ближе к оси шеи."""
    _, (cu, cf), size = head_numbers()
    loc, k = head_local(co, joints)
    e = (loc - np.array((0.0, -cf, cu)) * k) / (np.array((size[0], size[2], size[1])) * 0.5 * k)
    r = np.maximum(np.linalg.norm(e, axis=1), 1e-9)
    radial = np.linalg.norm(loc - np.array((0.0, -cf, cu)) * k, axis=1)
    return radial * (1.0 - 1.0 / r)


def owners(co, joints, segs):
    """«Расстояние до поверхности» каждого звена (N × S, см. NOMINAL_R; голова — эллипсоид
    `head_distance`) и параметр t вдоль звена."""
    d = np.empty((len(co), len(segs)))
    t = np.empty((len(co), len(segs)))
    for k, (bone, a, b) in enumerate(segs):
        pa, pb = np.array(joints[a]), np.array(joints[b])
        t[:, k] = meshops.seg_param(co, pa, pb)
        if bone == "head":
            d[:, k] = head_distance(co, joints)
            continue
        dist, _ = meshops.seg_dist(co, pa, pb)
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


def shoulders_width(co, joints, band=0.01):
    """Плечи снаружи по дельтам (таблица `m`): вся ширина сетки на высоте плечевых суставов —
    в A-позе руки уходят вниз, на этой высоте снаружи дельты."""
    z = (joints["upperarm.L"][2] + joints["upperarm.R"][2]) / 2
    xs = co[np.abs(co[:, 2] - z) < band, 0]
    return float(xs.max() - xs.min()) if len(xs) >= 4 else None


def waist_width(co, joints, band=0.01, gap=0.02):
    """Талия (ширина): связное по X (без разрывов > gap) сечение корпуса вокруг x = 0 на высоте
    начала spine — руки A-позы отдельно и не считаются."""
    xs = co[np.abs(co[:, 2] - joints["spine"][2]) < band, 0]

    def reach(v):
        v = np.sort(v)
        if len(v) == 0:
            return None
        gaps = np.where(np.diff(v) > gap)[0]
        return float(v[gaps[0]] if len(gaps) else v[-1])

    r, l = reach(xs[xs >= 0]), reach(-xs[xs <= 0])
    return None if r is None or l is None else r + l


CROWN_CAP_M = 0.004


def head_measures(co, joints):
    """Голова в своей системе (взгляд горизонтально), м: высота «подбородок — макушка», ширина,
    длина; макушка (верхняя точка сетки головы) — вверх и вперёд от начала head. Подбородок —
    нижняя точка лица впереди шеи (передний край шеи — по полосе на 0.09–0.11 м ниже начала
    head), полосы — в долях масштаба головы k."""
    loc, k = head_local(co, joints)
    near = (np.abs(loc[:, 0]) < 0.15 * k) & (loc[:, 1] > -0.25 * k) & (loc[:, 1] < 0.2 * k) & \
           (loc[:, 2] > -0.2 * k) & (loc[:, 2] < 0.3 * k)
    if near.sum() < 20:
        return {}
    # Макушка — верхняя точка сетки головы; на плоском куполе (закрытая дыра, срез) верхняя
    # вершина прыгает по краю, поэтому — середина вершин в 4 мм от верха.
    zmax = float(loc[near, 2].max())
    cap = near & (loc[:, 2] > zmax - CROWN_CAP_M)
    out = {"crown_up_m": zmax, "crown_forward_m": float(-loc[cap, 1].mean())}
    neck = near & (np.abs(loc[:, 0]) < 0.05 * k) & (loc[:, 2] > -0.11 * k) & (loc[:, 2] < -0.09 * k)
    if neck.sum() >= 4:
        front = float(loc[neck, 1].min())
        chin = near & (loc[:, 1] < front - 0.02 * k) & (np.abs(loc[:, 0]) < 0.05 * k) & (loc[:, 2] > -0.12 * k) & \
            (loc[:, 2] < 0.0)
        if chin.sum() >= 4:
            out["chin_m"] = float(loc[chin, 2].min())
            out["head_height_m"] = out["crown_up_m"] - out["chin_m"]
    temple = near & (loc[:, 2] > 0.02 * k) & (loc[:, 2] < 0.10 * k)
    if temple.sum() >= 4:
        out["head_width_m"] = float(loc[temple, 0].max() - loc[temple, 0].min())
    lng = near & (loc[:, 2] > -0.02 * k) & (np.abs(loc[:, 0]) < 0.06 * k)
    if lng.sum() >= 4:
        out["head_length_m"] = float(loc[lng, 1].max() - loc[lng, 1].min())
    return out


def head_center_local(co, joints, measured=None):
    """Центр габарита головы в системе головы (X вбок, Y назад, Z вверх; от начала head, без
    масштаба): по высоте — середина «подбородок — макушка», по длине и ширине — середина
    габарита. Подбородок не найден — None."""
    m = measured or head_measures(co, joints)
    if "chin_m" not in m:
        return None
    loc, k = head_local(co, joints)
    sel = (loc[:, 2] >= m["chin_m"]) & (loc[:, 2] <= m["crown_up_m"]) & (np.abs(loc[:, 0]) < 0.15 * k) & \
        (loc[:, 1] > -0.25 * k) & (loc[:, 1] < 0.2 * k)
    lng = sel & (loc[:, 2] > -0.02 * k) & (np.abs(loc[:, 0]) < 0.06 * k)
    if not sel.any() or not lng.any():
        return None
    return np.array((0.5 * (loc[sel, 0].max() + loc[sel, 0].min()), 0.5 * (loc[lng, 1].max() + loc[lng, 1].min()),
                     0.5 * (m["chin_m"] + m["crown_up_m"])))


def head_center(co, joints, measured=None):
    """Центр габарита головы (`head_center_local`) в мире; None — не измерить."""
    c = head_center_local(co, joints, measured)
    if c is None:
        return None
    h, q, _ = head_system(joints)
    return h + q @ c


def head_box(co, joints, front_y=-0.03):
    """Габарит сетки головы `co` (только вершины головы, напр. грани с меткой звена head) в
    системе головы: подбородок — нижняя точка лица (впереди `front_y`; затылок у шеи ниже
    подбородка и тянется весами шеи), макушка — верх; ширина и длина — по вершинам между ними.
    Итог: (центр в системе головы, размер (ширина, высота, длина)) или None."""
    loc, _ = head_local(co, joints)
    face = loc[:, 1] < front_y
    if face.sum() < 4:
        return None
    chin = float(loc[face, 2].min())
    top = float(loc[:, 2].max())
    sel = loc[:, 2] >= chin
    lo, hi = loc[sel].min(axis=0), loc[sel].max(axis=0)
    c = np.array((0.5 * (lo[0] + hi[0]), 0.5 * (lo[1] + hi[1]), 0.5 * (chin + top)))
    return c, np.array((hi[0] - lo[0], top - chin, hi[1] - lo[1]))


def spec_center_local():
    """Центр головы спеки в системе головы: `head_center_in_head_m` (вверх, вперёд) → (0, −вперёд, вверх)."""
    _, (cu, cf), _ = head_numbers()
    return np.array((0.0, -cf, cu))


def measures(co, joints, segs, data):
    """Обхваты (по станциям `girth_stations`), ширины корпуса и размеры головы, м."""
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
    thighs = [i for i, n in enumerate(names) if n.startswith("thigh")]
    out["pelvis_outer_m"] = measure_width(co, d, (joints["thigh.L"].z + joints["thigh.R"].z) / 2, torso + thighs)
    out["waist_width_m"] = waist_width(co, joints)
    out["shoulders_outer_m"] = shoulders_width(co, joints)
    out.update(head_measures(co, joints))
    return out


def _mid(rng):
    return (rng[0] + rng[1]) * 0.5


def target_joints(contract):
    params = contract.apose_params()
    tj = contract.apose_joints(params)
    target = {n: v[0].copy() for n, v in tj.items()}
    target["crown"] = contract.crown(tj, params)
    return target


# Подгонка обхватов и головы: столько повторов «мера результата → поправка множителя».
FIT_PASSES = 4
# Кивок головы при подгонке не больше этого (рад, 10°): больше — голова скана не по спеке.
NOD_MAX = math.radians(10.0)
NOD_MARGIN_M = 0.003
# Ключ меры → индекс в `head_size_m` (ширина × высота × длина) и ось системы головы (X, Y, Z).
HEAD_KEYS = {"head_width_m": 0, "head_height_m": 1, "head_length_m": 2}
HEAD_AXIS = {"head_width_m": 0, "head_length_m": 1, "head_height_m": 2}


def _map(co, src, target, segs, w, ratios, shoulder_root, head_place):
    """Скан → A-поза контракта при множителях обхватов `ratios` (ключ таблицы → множитель).
    Голова — целиком в своей системе: центр габарита скана `cs` → центр `ct` (системы головы
    скана и контракта), масштаб по осям — множители размера головы, кивок `pitch` (рад, + —
    вперёд) вокруг центра; `head_place` = (cs, ct, pitch)."""
    st_t = {"thigh": [("thigh_at_shorts_d_m", 0.30), ("thigh_at_knee_d_m", 0.88)], "shin": [("calf_d_m", 0.32), ("ankle_d_m", 0.92)],
            "forearm": [("wrist_d_m", 0.95)], "neck": [("neck_d_m", 0.5)], "upperarm": [("upperarm_d_m", 0.5)]}
    g = {base: [(t, ratios[key]) for key, t in pts] for base, pts in st_t.items()}
    g["upperarm"] = [(0.0, shoulder_root)] + g["upperarm"]
    g["pelvis"] = [(0.0, ratios["pelvis_outer_m"])]
    g["spine"] = [(0.0, ratios["waist_width_m"])]
    g["chest"] = [(0.0, ratios["chest"])]
    hs, qs, _ = head_system(src)
    ht, qt, _ = head_system(target)
    head_s = np.zeros(3)
    for key, ax in HEAD_AXIS.items():
        head_s[ax] = ratios[key]
    cs, ct, pitch = head_place
    ca, sa = math.cos(pitch), math.sin(pitch)
    nod = np.array(((1.0, 0.0, 0.0), (0.0, ca, -sa), (0.0, sa, ca)))
    out = np.zeros_like(co)
    for k, (bone, a, b) in enumerate(segs):
        base = bone.split(".")[0]
        if base == "head":
            new = ((((co - hs) @ qs - cs) * head_s) @ nod.T + ct) @ qt.T + ht
            out += w[:, k:k + 1] * new
            continue
        ls = max((src[b] - src[a]).length, 1e-6)
        sy = (target[b] - target[a]).length / ls
        fs, ft = np.array(frame(src[a], src[b])), np.array(frame(target[a], target[b]))
        loc = (co - np.array(src[a])) @ fs
        tt = np.clip(loc[:, 1] / ls, 0.0, 1.0)
        if base in ("hand", "foot"):
            sx = sz = np.full(len(co), sy)
        else:
            pts = g[base]
            gx = np.interp(tt, [p[0] for p in pts], [p[1] for p in pts]) if len(pts) > 1 else np.full(len(co), pts[0][1])
            sx = gx
            sz = 1.0 + 0.5 * (gx - 1.0) if base in ("pelvis", "spine", "chest") else gx
        new = np.stack((loc[:, 0] * sx, loc[:, 1] * sy, loc[:, 2] * sz), axis=1)
        out += w[:, k:k + 1] * (np.array(target[a]) + new @ ft.T)
    return out


def fit(obj, lm, contract):
    """Скан в A-позу контракта. Итог: метрики, предупреждения, суставы-цели (кость → точка)."""
    data = contract.data
    fig = data["figures"]["m"]
    head_size = data["proportions"]["head_size_m"]["value"]
    target = target_joints(contract)
    segs = segments()
    me = obj.data
    co = meshops.verts_np(me)
    src = {k: Vector(v) for k, v in lm.items()}
    before = measures(co, src, segs, data)
    warns = []
    want = {key: _mid(rng) for key, rng in fig.items()}
    want.update({key: head_size[i] for key, i in HEAD_KEYS.items()})

    def first(key):
        got = before.get(key)
        if not got:
            warns.append("не измерить %s на скане — не подгоняется" % key)
            return 1.0
        r = want[key] / got
        if not 0.8 <= r <= 1.25:
            warns.append("%s: скан %.3f м, таблица %.3f м — поправка %.2f (больше 20 %%)" % (key, got, want[key], r))
        return min(max(r, 0.7), 1.4)

    ratios = {key: first(key) for key in want}
    ratios["chest"] = ratios["shoulders_outer_m"]
    xj = (abs(target["upperarm.L"].x) + abs(target["upperarm.R"].x)) / 2

    def delt(got, joint_x):
        """Выступ дельты за плечевой сустав: (ширина по дельтам / 2 − |x сустава|), таблица / мера."""
        if not got:
            return 1.0
        return (want["shoulders_outer_m"] / 2 - xj) / max(got / 2 - joint_x, 0.01)

    shoulder_root = min(max(delt(before.get("shoulders_outer_m"), (abs(src["upperarm.L"].x) + abs(src["upperarm.R"].x)) / 2), 0.5), 1.5)
    d, _ = owners(co, src, segs)
    w = np.exp(-(d - d.min(axis=1, keepdims=True)) / SIGMA_M)
    w /= w.sum(axis=1, keepdims=True)
    # Голова: центр габарита скана → центр спеки (0.04 вверх и вперёд от начала head), затем
    # масштаб к размеру спеки — макушка (центр + половина высоты) и рост выходят следствием.
    spec_c = spec_center_local()
    cs = head_center_local(co, src, before)
    if cs is None:
        warns.append("голова: подбородок на скане не найден — центр головы по макушке и пропорциям спеки")
        _, _, k = head_system(src)
        cs = spec_c * k
    ct = spec_c.copy()
    # Кивок: система головы спеки задана макушкой (0.02–0.04 м впереди начала head), ориентир
    # crown скана — только оценка наклона. Макушка вне полосы (с запасом NOD_MARGIN_M) — кивок
    # вокруг центра до ближней границы полосы; внутри — не трогать (на круглом куполе макушка
    # почти не двигается от кивка, точная подгонка дала бы большой поворот лица).
    lo_f, hi_f = data["apose"]["crown_in_head_m"]["forward_range"]
    pitch = 0.0
    for n in range(FIT_PASSES):
        out = _map(co, src, target, segs, w, ratios, shoulder_root, (cs, ct, pitch))
        after = measures(out, target, segs, data)
        if n == FIT_PASSES - 1:
            break
        for key in want:
            if key == "shoulders_outer_m" or not after.get(key) or not before.get(key):
                continue
            ratios[key] = min(max(ratios[key] * want[key] / after[key], 0.5), 2.0)
        if after.get("shoulders_outer_m"):
            shoulder_root = min(max(shoulder_root * delt(after["shoulders_outer_m"], xj), 0.3), 3.0)
        c_after = head_center_local(out, target, after)
        if c_after is not None:
            ct = ct + (spec_c - c_after)
            if "crown_up_m" in after:
                fwd = after["crown_forward_m"]
                want_f = min(max(fwd, lo_f + NOD_MARGIN_M), hi_f - NOD_MARGIN_M)
                dz = after["crown_up_m"] - c_after[2]
                got = math.atan2(-fwd - c_after[1], dz)
                aim = math.atan2(-want_f - c_after[1], dz)
                pitch = min(max(pitch + got - aim, -NOD_MAX), NOD_MAX)
    meshops.set_verts_np(me, out)
    height = float(out[:, 2].max())
    metrics = {"height_before_m": round(float(co[:, 2].max()), 4), "height_m": round(height, 4)}
    for key, rng in fig.items():
        if after.get(key) is not None:
            metrics[key] = round(after[key], 4)
            if not rng[0] - 0.01 <= after[key] <= rng[1] + 0.01:
                warns.append("%s после подгонки %.3f м вне таблицы m %s ± 0.01" % (key, after[key], rng))
    tol = data["proportions"]["head_size_m"]["tol"]
    for key, i in HEAD_KEYS.items():
        if after.get(key) is not None:
            metrics[key] = round(after[key], 4)
            if abs(after[key] - head_size[i]) > tol:
                warns.append("%s после подгонки %.3f м, таблица %.3f ± %.2f" % (key, after[key], head_size[i], tol))
    (up, _), _, _ = head_numbers()
    c_after = head_center_local(out, target, after)
    metrics["head_nod_deg"] = round(math.degrees(pitch), 2)
    if abs(pitch) >= NOD_MAX - 1e-6:
        warns.append("голова: кивок при подгонке упёрся в %.0f° — проверьте ориентир crown и кадр шага 3" % math.degrees(NOD_MAX))
    if c_after is not None:
        metrics["head_center_up_m"] = round(float(c_after[2]), 4)
        metrics["head_center_forward_m"] = round(float(-c_after[1]), 4)
    if "crown_up_m" in after:
        metrics["crown_up_m"] = round(after["crown_up_m"], 4)
        metrics["crown_forward_m"] = round(after["crown_forward_m"], 4)
        ctol = data["apose"]["crown_in_head_m"]["tol"]
        lo, hi = data["apose"]["crown_in_head_m"]["forward_range"]
        if abs(after["crown_up_m"] - up) > ctol or not lo <= after["crown_forward_m"] <= hi:
            warns.append("макушка %.3f м над началом head и %.3f м впереди (спека %.2f ± %.2f и %.2f–%.2f)"
                         % (after["crown_up_m"], after["crown_forward_m"], up, ctol, lo, hi))
    hv = data["height_m"]
    if abs(height - hv["value"]) > hv["tol"]:
        warns.append("рост после подгонки %.3f м (контракт %.2f ± %.2f)" % (height, hv["value"], hv["tol"]))
    return metrics, warns, target
