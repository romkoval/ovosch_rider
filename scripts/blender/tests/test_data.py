"""Данные конвейера (`pipeline_data.json`) против спеки (art-bible, бриф) и контракта из кода
(`assets/rider/reference/rider_contract.json` ← `RiderRig`, `RiderRegions`): расхождение — падение
(T-143 п.5; REQ-D3D-09 п.1–5, 7)."""

import math
import os
import re
import unittest

import bpy  # noqa: F401
from mathutils import Vector

from rider_refine import common
from rider_refine.contract import Contract

ART = os.path.join(common.ROOT, "docs", "game", "art-bible.md")
BRIEF = os.path.join(common.ROOT, "docs", "game", "rider-artist-brief.md")
RIG_GD = os.path.join(common.ROOT, "src", "scene3d", "rider_rig.gd")
REGIONS_GD = os.path.join(common.ROOT, "src", "scene3d", "rider_regions.gd")
NUM = r"\d+(?:\.\d+)?"


def norm(text):
    return re.sub(r"\s+", " ", text)


def table_row(text, label):
    for line in text.splitlines():
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        if len(cells) > 1 and cells[0].startswith(label):
            return cells
    raise AssertionError("в спеке нет строки «%s»" % label)


def ranges(cell):
    out = []
    for part in cell.split("/"):
        nums = [float(x) for x in re.findall(NUM, part)]
        if nums:
            out.append([nums[0], nums[1] if len(nums) > 1 else nums[0]])
    return out


class DataVsSpec(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.c = Contract()
        cls.d = cls.c.data
        cls.art = open(ART, encoding="utf-8").read()
        cls.brief = open(BRIEF, encoding="utf-8").read()

    def test_figure_tables_m_f(self):
        rows = {"Плечи снаружи": ["shoulders_outer_m"], "Талия (ширина)": ["waist_width_m"],
                "Таз снаружи по шортам": ["pelvis_outer_m"], "Бедро у шорт / у колена": ["thigh_at_shorts_d_m", "thigh_at_knee_d_m"],
                "Икра / лодыжка": ["calf_d_m", "ankle_d_m"], "Плечо (рука) / запястье": ["upperarm_d_m", "wrist_d_m"],
                "Шея": ["neck_d_m"]}
        for label, keys in rows.items():
            cells = table_row(self.art, label)
            for fig, cell in (("m", cells[1]), ("f", cells[2])):
                got = ranges(cell)
                self.assertEqual(len(got), len(keys), "%s: %s" % (label, cell))
                for k, r in zip(keys, got):
                    self.assertEqual(self.d["figures"][fig][k], r, "%s %s (%s)" % (fig, k, label))

    def test_proportions_table(self):
        rows = {"Бедро (тазобедренный": "thigh_m", "Голень (колено": "shin_m", "Плечо (плечевой": "upperarm_m",
                "Предплечье + кисть": "forearm_to_grip_m", "Тазобедренный сустав — плечевой": "torso_m"}
        for label, key in rows.items():
            cell = table_row(self.art, label)[1]
            val, tol = re.findall(NUM, cell)[:2]
            self.assertEqual(self.d["proportions"][key]["value"], float(val), key)
            self.assertEqual(self.d["proportions"][key]["tol"], float(tol), key)
        self.assertEqual(self.d["proportions"]["torso_tilt_deg"]["range"],
                         [float(x) for x in re.findall(NUM, table_row(self.art, "Наклон корпуса")[1])[:2]])
        self.assertIn("Рост —\n1.78 м у обеих", self.art)
        self.assertEqual(self.d["height_m"]["value"], 1.78)

    def test_region_boundaries_in_spec_text(self):
        r = self.d["regions"]
        art = norm(self.art)
        brief = norm(self.brief)
        lo, hi = r["shorts_leg_end_t"]["range"]
        self.assertIn("%d–%d %% длины бедра" % (lo * 100, hi * 100), art)
        self.assertIn("резинкой шириной %d см" % (r["shorts_gripper_m"]["value"] * 100), art)
        lo, hi = r["sock_top_above_ankle_m"]["range"]
        self.assertIn("на %.2f–%.2f м выше голеностопа" % (lo, hi), art)
        self.assertIn("Манжета %d см (регион `socks_cuff`)" % (r["sock_cuff_m"]["value"] * 100), art)
        lo, hi = r["sleeve_end_t"]["range"]
        self.assertIn("до середины плеча (%d–%d %%), манжета %.1f см" % (lo * 100, hi * 100, r["jersey_cuff_m"]["value"] * 100), art)
        lo, hi = r["jersey_bottom_back_m"]["range"]
        self.assertIn("на %.2f–%.2f м выше верха седла" % (lo, hi), art)
        lo, hi = r["jersey_band_m"]["range"]
        self.assertIn("(высота %d–%d см)" % (lo * 100, hi * 100), brief)

    def test_budgets_from_brief_section3(self):
        for name, tris in self.d["budgets"]["tris"].items():
            m = re.search(r"\| [^|]*`%s`[^|]*\| (\d+)" % re.escape(name), self.brief)
            if m is None:
                m = re.search(r"`%s`, `[^`]+` \| (\d+)" % re.escape(name), self.brief) or \
                    re.search(r"`[^`]+`, `%s` \| (\d+)" % re.escape(name), self.brief)
            self.assertIsNotNone(m, name)
            self.assertEqual(int(m.group(1)), tris, name)
        self.assertIn("**4 костей**", self.brief)
        self.assertEqual(self.d["budgets"]["max_influences"], 4)
        self.assertIn("до 4 МБ", self.art)


class DataVsContract(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.c = Contract()
        cls.d = cls.c.data

    def test_contract_json_matches_rider_rig_gd(self):
        """JSON пакета = таблица `RiderRig.BONES` (независимый разбор .gd; свежесть JSON — GUT
        test_rider_artist_kit)."""
        src = open(RIG_GD, encoding="utf-8").read()
        rows = re.findall(r'\["([\w.]+)", "([\w.]*)", Vector3\(([-\d.]+), ([-\d.]+), ([-\d.]+)\), (true|false)\]', src)
        self.assertEqual([r[0] for r in rows], self.c.order)
        for n, p, x, y, z, deform in rows:
            self.assertEqual(self.c.parent(n), p, n)
            self.assertEqual(self.c.deform(n), deform == "true", n)
            self.assertLess((self.c.head(n) - Vector((-float(x), float(z), float(y)))).length, 1e-6, n)
        self.assertEqual(len(rows), self.c.json["bone_count"])
        self.assertEqual(sorted(self.c.sockets()), sorted(n for n in self.c.order if n.split(".")[0] in ("grip", "cleat", "heel")))

    def test_regions_match_code(self):
        src = open(REGIONS_GD, encoding="utf-8").read()
        names = re.findall(r'\["(\w+)", [\d.]+\]', src)
        self.assertEqual([r["name"] for r in self.c.json["regions"]["list"]], names)
        req = self.d["regions"]["required_body"]["value"]
        self.assertTrue(all(k < self.c.json["regions"]["first_bike"] for k in req))
        self.assertEqual(self.c.json["regions"]["margin"], 0.1)

    def test_proportions_agree_with_contract(self):
        p = self.d["proportions"]
        for key in ("thigh_m", "shin_m", "upperarm_m", "forearm_to_grip_m"):
            a, b = p[key]["joints"]
            for s in (".L", ".R"):
                got = self.c.length(a + s, b + s)
                self.assertLessEqual(abs(got - p[key]["value"]), p[key]["tol"], "%s%s %.4f" % (key, s, got))
        for key in ("hip_span_m", "shoulder_span_m"):
            a, b = p[key]["joints"]
            self.assertLessEqual(abs(self.c.length(a, b) - p[key]["value"]), p[key]["tol"], key)
        hips = (self.c.head("thigh.L") + self.c.head("thigh.R")) / 2
        sh = (self.c.head("upperarm.L") + self.c.head("upperarm.R")) / 2
        self.assertLessEqual(abs((sh - hips).length - p["torso_m"]["value"]), p["torso_m"]["tol"])
        tilt = math.degrees(math.atan2(sh.z - hips.z, hips.y - sh.y))
        lo, hi = p["torso_tilt_deg"]["range"]
        self.assertTrue(lo <= tilt <= hi, tilt)
        self.assertAlmostEqual(self.c.head("pelvis").z, p["saddle_top_m"]["value"], delta=p["saddle_top_m"]["tol"])
        self.assertEqual(self.c.json["max_bones"], 28)

    def test_control_poses_from_curve_match_table(self):
        """Позы φ 0…345° пакета (кривая стопы, двухзвенная цепь) сходятся с таблицей брифа 5.4."""
        poses = {p["phi_deg"]: p for p in self.c.json["control_poses"]}
        self.assertEqual(sorted(poses), list(range(0, 360, 15)))
        for row in self.c.json["control_poses_table"]:
            got = poses[row["phi_deg"]]["R"]
            for k in ("cleat", "ankle", "knee"):
                self.assertLess((Vector(got[k]) - Vector(row[k])).length, 0.003, "φ %d %s" % (row["phi_deg"], k))
            self.assertAlmostEqual(got["knee_deg"], row["knee_deg"], delta=1.5)
            self.assertAlmostEqual(got["foot_deg"], row["foot_deg"], delta=0.5)
        for phi, p in poses.items():
            for s in ("L", "R"):
                hip, knee, ankle = (Vector(p[s][k]) for k in ("hip", "knee", "ankle"))
                self.assertAlmostEqual((knee - hip).length, self.c.length("thigh.L", "shin.L"), delta=0.001)
                self.assertLess(Vector(p[s]["cleat"]).y, Vector(p[s]["heel"]).y, "носок впереди пятки φ %d" % phi)
            left = Vector(p["L"]["cleat"])
            right = Vector(poses[(phi + 180) % 360]["R"]["cleat"])
            self.assertLess((left - Vector((-right.x, right.y, right.z))).length, 1e-5, "левая = правая при φ + 180°")
