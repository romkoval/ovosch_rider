"""Шаг 8: регионы цвета. Граница — по размерам спеки (рёбра уже прорезаны на шаге 4, у граней
метки звена `seg_bone`, `seg_t`, `seg_n` в A-позе), цвет текстуры скана — только подсказка
(волосы на голове; доля несогласий — в отчёт). UV0 по атласу: U — центр колонки региона,
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
            hair = hcls is not None and hcls[i] == "dark" and t > 0.45
            out[i] = 1 if hair else 0
        elif base == "upperarm":
            cuff = sleeve - r["jersey_cuff_m"]["value"] / L(bone, "forearm" + bone[-2:])
            out[i] = 2 if t < cuff else (6 if t < sleeve else 0)
        elif base == "forearm":
            out[i] = 0
        elif base == "hand":
            if t > r["glove_fingertip_t"]["value"]:
                out[i] = 0
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
    # Нет волос по подсказке — скальп по форме (затылок и макушка), чтобы регион был.
    head = np.array([names[b].startswith("head") for b in seg_bone])
    if not (out == 1).any() and head.any():
        out[head & (seg_t > 0.75)] = 1
    return out, hcls


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
