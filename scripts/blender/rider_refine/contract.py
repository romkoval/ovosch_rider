"""Контракт скелета для конвейера: `assets/rider/reference/rider_contract.json` (собирает
`scripts/rider_artist_kit.sh` из `RiderRig`), A-поза контрактного скелета, данные спеки.

Всё в координатах Blender (бриф §4): Z вверх, гонщик смотрит в −Y, левая сторона +X, метры.
"""

import math

from mathutils import Matrix, Quaternion, Vector

from . import common

# Окончание кости = начало «своего» ребёнка цепочки (бриф 5.1).
CHAIN = {"pelvis": "spine", "spine": "chest", "chest": "neck", "neck": "head", "upperarm": "forearm",
         "forearm": "hand", "hand": "grip", "thigh": "shin", "shin": "foot", "hair_tail.1": "hair_tail.2"}
SIDES = (".L", ".R")


def side_of(name):
    return name[-2:] if name[-2:] in SIDES else ""


def base_of(name):
    s = side_of(name)
    return name[: -2] if s else name


class Contract:
    def __init__(self, path=common.CONTRACT_JSON):
        self.path = path
        self.json = common.load_json(path)
        self.bones = self.json["bones"]
        self.order = [b["name"] for b in self.bones]
        self.by_name = {b["name"]: b for b in self.bones}
        self.data = common.data()

    def head(self, name):
        return Vector(self.by_name[name]["head"])

    def tail(self, name):
        return Vector(self.by_name[name]["tail"])

    def parent(self, name):
        return self.by_name[name]["parent"]

    def deform(self, name):
        return self.by_name[name]["deform"]

    def is_socket(self, name):
        return self.by_name[name]["socket"]

    def axis_z(self, name):
        return Vector(self.by_name[name]["axis_z"])

    def rest_matrix(self, name):
        """Матрица кости в rest (пространство арматуры): оси X, Y, Z контракта, начало — сустав."""
        b = self.by_name[name]
        m = Matrix((b["axis_x"], b["axis_y"], b["axis_z"])).transposed().to_4x4()
        m.translation = Vector(b["head"])
        return m

    def deform_bones(self):
        return [n for n in self.order if self.deform(n)]

    def sockets(self):
        return [n for n in self.order if self.is_socket(n)]

    def chain_child(self, name):
        c = CHAIN.get(base_of(name))
        return c + side_of(name) if c else ""

    def rest_joints(self):
        """Кость → (начало, окончание, ось Z) в rest контракта."""
        return {n: (self.head(n), self.tail(n), self.axis_z(n)) for n in self.order}

    def length(self, a, b):
        return (self.head(a) - self.head(b)).length

    # --- A-поза ---

    def apose_rotations(self, params=None):
        """Кость → поворот (кватернион, мировой) из rest контракта в A-позу (`pipeline_data`
        «apose»): корпус и голова вертикально, ноги прямые с голеностопами на ±ankle_x, подошва
        горизонтальна носком вперёд, руки во фронтальной плоскости под углом к вертикали, сгиб
        локтя вперёд до заданного угла. Дети без своей цели (сокеты, хвост) идут с родителем."""
        p = params or self.apose_params()
        up = Vector((0.0, 0.0, 1.0))
        fwd = Vector((0.0, -1.0, 0.0))
        aims = {}
        for n in ("pelvis", "spine", "chest", "neck", "head"):
            aims[n] = ("bone", up)
        a = math.radians(p["arm_from_vertical_deg"])
        bend = math.radians(180.0 - p["elbow_deg"])
        for s, sx in ((".L", 1.0), (".R", -1.0)):
            hip = self.head("thigh" + s)
            leg = self.length("thigh" + s, "shin" + s) + self.length("shin" + s, "foot" + s)
            dx = sx * p["ankle_x_m"] - hip.x
            d = Vector((dx, 0.0, -math.sqrt(max(leg * leg - dx * dx, 1e-6)))).normalized()
            aims["thigh" + s] = ("bone", d)
            aims["shin" + s] = ("bone", d)
            aims["foot" + s] = ("sole", fwd)
            u = Vector((sx * math.sin(a), 0.0, -math.cos(a)))
            aims["upperarm" + s] = ("bone", u)
            f = (u * math.cos(bend) + fwd * math.sin(bend)).normalized()
            aims["forearm" + s] = ("bone", f)
            aims["hand" + s] = ("bone", f)
        rot = {}
        for n in self.order:
            par = self.parent(n)
            qp = rot[par] if par else Quaternion()
            if n in aims:
                kind, target = aims[n]
                if kind == "bone":
                    v = (self.tail(n) - self.head(n)).normalized()
                else:
                    s = side_of(n)
                    v = (self.head("cleat" + s) - self.head("heel" + s)).normalized()
                rot[n] = (qp @ v).rotation_difference(target) @ qp
            else:
                rot[n] = qp.copy()
        return rot

    def apose_params(self, **over):
        p = {k: v["value"] for k, v in self.data["apose"].items() if isinstance(v, dict)}
        p.update(over)
        return p

    def apose_joints(self, params=None, scales=None):
        """Кость → (начало, окончание, ось Z) в A-позе; подошва на z = 0, середина голеностопов
        над началом координат. Длины костей — контрактные (поворот каждой кости жёсткий).
        `scales` (база кости → множитель длины, для синтетики с «чужими» пропорциями) растягивает
        кость и смещения её детей в её системе."""
        params = params or self.apose_params()
        rot = self.apose_rotations(params)
        k = scales or {}
        pos = {}
        for n in self.order:
            par = self.parent(n)
            if par:
                pos[n] = pos[par] + rot[par] @ ((self.head(n) - self.head(par)) * k.get(base_of(par), 1.0))
            else:
                pos[n] = Vector((0.0, 0.0, 0.0))
        sole = min(pos["cleat.L"].z, pos["heel.L"].z)
        mid = (pos["foot.L"] + pos["foot.R"]) * 0.5
        shift = Vector((-mid.x, -mid.y, -sole))
        out = {}
        for n in self.order:
            h = pos[n] + shift
            out[n] = (h, h + rot[n] @ ((self.tail(n) - self.head(n)) * k.get(base_of(n), 1.0)), rot[n] @ self.axis_z(n))
        return out

    def crown(self, joints, params=None):
        """Макушка: `crown_from_head_m` от начала head по оси кости (данные конвейера, «apose»)."""
        d = params["crown_from_head_m"] if params else self.data["apose"]["crown_from_head_m"]["value"]
        h, t, _ = joints["head"]
        return h + (t - h).normalized() * d

    def apose_height(self, joints=None):
        j = joints or self.apose_joints()
        return self.crown(j).z


def bone_matrix(head, tail, axis_z):
    """Матрица кости Blender (Y — к окончанию, Z — по `axis_z`, X = Y × Z), начало — head."""
    y = (tail - head).normalized()
    z = (axis_z - y * axis_z.dot(y)).normalized()
    x = y.cross(z)
    m = Matrix((x, y, z)).transposed().to_4x4()
    m.translation = head
    return m
