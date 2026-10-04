"""Приёмка T-143 (tester): конвейер доводки ИИ-модели гонщика в Blender — независимо от тестов
исполнителя (`scripts/blender/tests`). REQ-D3D-09 п.7, 9 — механизм; п.1–5 — на синтетике.

Источник истины — art-bible «Гонщик» ред. 4.1, «Вариант Г» (шаги 0–11, «Вход конвейера из
пакета», A-поза) и бриф `docs/game/rider-artist-brief.md` §3–§6, §10–§12, §14 Т1–Т7. Числа
брифа переписаны сюда вручную (не из `rider_contract.json` и не из `pipeline_data.json`).

Запуск: `tests/blender/run.sh` (нужен Python с `bpy` или Blender — `scripts/blender/env.sh`).
Конвейер запускается так же, как его запускает TA: `scripts/rider_refine.sh` отдельным
процессом, рабочий каталог — временный, вне репозитория.
"""

import hashlib
import json
import math
import os
import shutil
import struct
import subprocess
import tempfile
import unittest

import numpy as np

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
REFINE = os.path.join(ROOT, "scripts", "rider_refine.sh")
FIXTURE = os.path.join(ROOT, "tests", "fixtures", "rider_synthetic", "rider_synthetic.glb")
CONTRACT = os.path.join(ROOT, "assets", "rider", "reference", "rider_contract.json")
BIKE = os.path.join(ROOT, "assets", "rider", "reference", "bike_reference.glb")
# Коммит до T-143 (рабочая ветка 3a27e6f): bike_reference.glb без узла saddle.
BIKE_BEFORE_REV = "3a27e6f"

# --- бриф §5.1 (Blender, м; .L, у .R x с минусом) ---
BONES = [  # имя, родитель, начало, деформирует
    ("pelvis", "", (0.0, 0.230, 0.965), True),
    ("spine", "pelvis", (0.0, 0.105, 1.147), True),
    ("chest", "spine", (0.0, -0.018, 1.234), True),
    ("neck", "chest", (0.0, -0.190, 1.380), True),
    ("head", "neck", (0.0, -0.310, 1.420), True),
    ("upperarm.L", "chest", (0.180, -0.220, 1.340), True),
    ("forearm.L", "upperarm.L", (0.240, -0.345, 1.060), True),
    ("hand.L", "forearm.L", (0.215, -0.560, 0.925), True),
    ("grip.L", "hand.L", (0.210, -0.620, 0.885), False),
    ("thigh.L", "pelvis", (0.090, 0.190, 1.050), True),
    ("shin.L", "thigh.L", (0.100, -0.170, 0.797), True),
    ("foot.L", "shin.L", (0.110, -0.063, 0.371), True),
    ("cleat.L", "foot.L", (0.115, -0.170, 0.270), False),
    ("heel.L", "foot.L", (0.115, 0.018, 0.296), False),
    ("hair_tail.1", "head", (0.0, -0.250, 1.390), True),
]


def _mirror(name):
    return name.replace(".L", ".R")


def brief_bones():
    out = {}
    for name, parent, head, deform in BONES:
        out[name] = (parent, np.array(head), deform)
        if name.endswith(".L"):
            out[_mirror(name)] = (_mirror(parent), np.array((-head[0], head[1], head[2])), deform)
    return out  # hair_tail.2 — отдельно: 0.09–0.10 м от hair_tail.1


# Окончания по брифу §5.1: «начало дочерней», явные точки и «3 см вниз» у сокетов.
TAIL_CHILD = {"pelvis": "spine", "spine": "chest", "chest": "neck", "neck": "head",
              "upperarm.L": "forearm.L", "forearm.L": "hand.L", "hand.L": "grip.L",
              "thigh.L": "shin.L", "shin.L": "foot.L", "hair_tail.1": "hair_tail.2"}
TAIL_POINT = {"head": (0.0, -0.40, 1.56), "foot.L": (0.115, -0.259, 0.258)}
SOCKETS = ("grip.L", "grip.R", "cleat.L", "cleat.R", "heel.L", "heel.R")

# Бриф §5.4: правая нога, (y, z) Blender; угол колена; наклон стопы.
CONTROL = {
    0: ((0.000, 0.440), (0.092, 0.555), (-0.213, 0.873), 70.0, -16.0),
    90: ((-0.170, 0.270), (-0.053, 0.360), (-0.162, 0.786), 113.0, -2.0),
    180: ((0.000, 0.100), (0.100, 0.208), (0.026, 0.642), 148.0, -12.0),
    270: ((0.170, 0.270), (0.241, 0.399), (-0.078, 0.701), 96.0, -26.0),
    "rest": ((-0.170, 0.270), (-0.063, 0.371), (-0.170, 0.797), 111.0, -8.0),
}
# Бриф §14: ракурсы в координатах Blender.
VIEWS = {
    "work": ((0.49, 3.77, 2.10), (0.0, -6.0, 0.60), 55.0, [0, 90, 180, 270]),
    "side_r": ((-2.8, -0.1, 0.95), (0.0, -0.1, 0.85), 40.0, [0, 90, 180, 270]),
    "hips_r": ((-1.3, 0.15, 0.97), (0.0, 0.05, 0.87), 35.0, [0, 90, 180, 270]),
    "rear34_l": ((1.5, 2.0, 1.55), (0.0, 0.05, 0.95), 40.0, [90]),
    "front34_r": ((-1.6, -2.2, 1.35), (0.0, -0.25, 1.05), 40.0, [90]),
    "head_34": ((-0.7, -1.1, 1.55), (0.0, -0.38, 1.42), 30.0, [90]),
}
# Бриф §3: бюджеты; §10: регионы тела; §14 Т6.
BUDGET = {"body_m": 8000, "body_f": 8000, "hair_short": 300, "hair_tail": 800, "helmet_aero": 1600,
          "helmet_vented": 1600, "glasses_shield": 400, "glasses_half_frame": 400, "shoe_boa_L": 600,
          "shoe_boa_R": 600, "shoe_strap_L": 600, "shoe_strap_R": 600}
BODY_REGIONS = set(range(0, 12)) | {21, 22}
# art-bible «Пропорции и посадка» — таблица m (обхваты/ширины, м).
FIG_M = {"shoulders_outer": (0.44, 0.46), "waist": (0.30, 0.30)}


# ---------------------------------------------------------------- GLB (свой разбор, без bpy)

COMP = {5121: np.uint8, 5123: np.uint16, 5125: np.uint32, 5126: np.float32, 5120: np.int8, 5122: np.int16}
WIDTH = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}


def glb(path_or_bytes):
    data = open(path_or_bytes, "rb").read() if isinstance(path_or_bytes, str) else path_or_bytes
    magic, ver, _ = struct.unpack_from("<III", data, 0)
    assert magic == 0x46546C67 and ver == 2, "не GLB 2.0"
    jlen, _ = struct.unpack_from("<II", data, 12)
    doc = json.loads(data[20:20 + jlen])
    off = 20 + jlen
    blen, _ = struct.unpack_from("<II", data, off)
    return doc, data[off + 8:off + 8 + blen]


def acc(doc, binary, i):
    a = doc["accessors"][i]
    v = doc["bufferViews"][a["bufferView"]]
    dt = np.dtype(COMP[a["componentType"]])
    w = WIDTH[a["type"]]
    start = v.get("byteOffset", 0) + a.get("byteOffset", 0)
    stride = v.get("byteStride") or dt.itemsize * w
    rows = [np.frombuffer(binary, dtype=dt, count=w, offset=start + k * stride) for k in range(a["count"])]
    out = np.array(rows, dtype=np.float64 if dt.kind == "f" else np.int64)
    if a.get("normalized"):
        out = out / np.iinfo(dt).max
    return out


def trs(node):
    if "matrix" in node:
        return np.array(node["matrix"], dtype=float).reshape(4, 4).T
    x, y, z, w = node.get("rotation", [0, 0, 0, 1])
    r = np.array([[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
                  [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
                  [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]])
    m = np.eye(4)
    m[:3, :3] = r * np.array(node.get("scale", [1, 1, 1]))
    m[:3, 3] = node.get("translation", [0, 0, 0])
    return m


def world(doc):
    parent = {}
    for i, n in enumerate(doc["nodes"]):
        for c in n.get("children", []):
            parent[c] = i
    out = {}

    def get(i):
        if i not in out:
            out[i] = (get(parent[i]) if i in parent else np.eye(4)) @ trs(doc["nodes"][i])
        return out[i]
    for i in range(len(doc["nodes"])):
        get(i)
    return out, parent


def to_blender(p):
    """glTF (+Y вверх) → Blender (Z вверх): (x, y, z)_glTF = (x, z, −y)_Blender."""
    p = np.asarray(p, dtype=float)
    return np.stack([p[..., 0], -p[..., 2], p[..., 1]], axis=-1)


def world_triangles(doc, binary):
    """Все треугольники всех узлов с сеткой в мировых координатах (glTF), без скиннинга."""
    w, _ = world(doc)
    tris = []
    for i, n in enumerate(doc["nodes"]):
        if "mesh" not in n:
            continue
        for prim in doc["meshes"][n["mesh"]]["primitives"]:
            pos = acc(doc, binary, prim["attributes"]["POSITION"])
            idx = acc(doc, binary, prim["indices"]).reshape(-1).astype(int) if "indices" in prim else np.arange(len(pos))
            p = (w[i] @ np.c_[pos, np.ones(len(pos))].T).T[:, :3]
            tris.append(p[idx].reshape(-1, 3, 3))
    return np.concatenate(tris) if tris else np.zeros((0, 3, 3))


def top_at(tris_blender, x, y):
    """Верх поверхности (наибольшая z) треугольников над точкой (x, y) Blender; None — нет."""
    best = None
    for t in tris_blender:
        a, b, c = t
        d = (b[1] - c[1]) * (a[0] - c[0]) + (c[0] - b[0]) * (a[1] - c[1])
        if abs(d) < 1e-12:
            continue
        l1 = ((b[1] - c[1]) * (x - c[0]) + (c[0] - b[0]) * (y - c[1])) / d
        l2 = ((c[1] - a[1]) * (x - c[0]) + (a[0] - c[0]) * (y - c[1])) / d
        l3 = 1 - l1 - l2
        if min(l1, l2, l3) >= -1e-9:
            z = l1 * a[2] + l2 * b[2] + l3 * c[2]
            best = z if best is None else max(best, z)
    return best


# ---------------------------------------------------------------- запуск конвейера


def refine(*args, cwd=ROOT):
    res = subprocess.run([REFINE, *args], cwd=cwd, capture_output=True, text=True, timeout=900)
    return res.returncode, res.stdout, res.stderr


def sha(path):
    return hashlib.sha256(open(path, "rb").read()).hexdigest()


class T143(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.mkdtemp(prefix="t143_accept_")
        cls.raw_dir = os.path.join(cls.tmp, "raw")
        res = subprocess.run(["bash", "-c", "source scripts/blender/env.sh && bpy_run scripts/blender/make_synthetic.py \"$0\"",
                              cls.raw_dir], cwd=ROOT, capture_output=True, text=True, timeout=600)
        cls.synth_code = res.returncode  # проверяется в test_cli_full_run_succeeds_with_exit_0
        cls.raw = {v: os.path.join(cls.raw_dir, "synthetic_%s.glb" % v)
                   for v in ("m", "cm", "axes", "bad_notex", "bad_legs", "bad_two")}
        for p in cls.raw.values():
            assert os.path.isfile(p), "make_synthetic.py: нет %s\n%s" % (p, res.stderr[-2000:])
        cls.work = os.path.join(cls.tmp, "w_m")
        cls.code, cls.out, cls.err = refine(cls.raw["m"], "--work", cls.work)
        cls.glb_path = os.path.join(cls.work, "rider.glb")

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.tmp, ignore_errors=True)

    def _raw_copy(self, name, src="m", landmarks=None):
        """Копия синтетики со своими ориентирами (испорченный вход)."""
        d = os.path.join(self.tmp, "bad_" + name)
        os.makedirs(d, exist_ok=True)
        dst = os.path.join(d, name + ".glb")
        shutil.copy(self.raw[src], dst)
        lm = os.path.join(d, name + ".landmarks.json")
        if landmarks is None:
            shutil.copy(os.path.splitext(self.raw[src])[0] + ".landmarks.json", lm)
        else:
            open(lm, "w").write(landmarks)
        return dst

    def _lm(self, src="m"):
        return json.load(open(os.path.splitext(self.raw[src])[0] + ".landmarks.json"))

    def _assert_clear_stop(self, raw, label, steps=(1, 2)):
        work = os.path.join(self.tmp, "w_" + label)
        code, out, err = refine(raw, "--work", work)
        text = out + err
        self.assertNotIn("Traceback", text, "%s: падение Python вместо понятной ошибки:\n%s" % (label, err[-1500:]))
        self.assertEqual(code, 1, "%s: код выхода 1 (ошибка шага), факт %d" % (label, code))
        lines = [ln for ln in err.splitlines() if ln.startswith("ШАГ ")]
        self.assertTrue(lines, "%s: нет строки «ШАГ N (шаг): объект: что не так»" % label)
        self.assertIn(int(lines[0].split()[1]), steps, "%s: остановка на шаге %s, ждали %s" % (label, lines[0], steps))
        self.assertFalse(os.path.exists(os.path.join(work, "rider.glb")), "%s: rider.glb не собран" % label)
        return lines[0]

    # ------------------------------------------------------------ CLI, детерминизм, git

    def test_cli_full_run_succeeds_with_exit_0(self):
        """README/refine.py: «Код выхода: 0 — шаги пройдены». Запуск одной командой (карточка T-143)."""
        self.assertIn("rider_refine: готово", self.out, self.err[-1500:])
        self.assertTrue(os.path.isfile(self.glb_path))
        self.assertEqual((self.code, self.synth_code), (0, 0),
                         "успешный прогон rider_refine.sh / make_synthetic.py: коды выхода %s (139 = SIGSEGV при выходе); "
                         "stderr: %s" % ((self.code, self.synth_code), self.err.strip().splitlines()[-1:]))

    def test_blender_test_suite_exit_code_matches_result(self):
        """`scripts/blender/test.sh`: при «ИТОГ: … ошибок 0, падений 0» код выхода 0 (иначе CI и
        `set -e` считают зелёный прогон красным)."""
        res = subprocess.run([os.path.join(ROOT, "scripts", "blender", "test.sh")], cwd=ROOT,
                             capture_output=True, text=True, timeout=900)
        summary = [ln for ln in res.stdout.splitlines() if ln.startswith("ИТОГ: ") and "тестов" in ln]
        self.assertTrue(summary, res.stdout[-800:])
        if "ошибок 0, падений 0" in summary[-1]:
            self.assertEqual(res.returncode, 0, "%s, но код выхода %d; %s" % (summary[-1], res.returncode,
                                                                           (res.stdout + res.stderr).strip().splitlines()[-1:]))

    def test_cli_rerun_is_deterministic_and_matches_gut_fixture(self):
        work2 = os.path.join(self.tmp, "w_m2")
        refine(self.raw["m"], "--work", work2)
        self.assertEqual(sha(os.path.join(work2, "rider.glb")), sha(self.glb_path), "два чистых прогона — один rider.glb")
        self.assertEqual(sha(FIXTURE), sha(self.glb_path), "фикстура GUT = выход конвейера на синтетике m")

    def test_cli_from_to_resume_and_errors(self):
        work = os.path.join(self.tmp, "w_split")
        code, out, err = refine(self.raw["m"], "--work", work, "--to", "8")
        self.assertEqual(code, 0, err[-500:])
        self.assertFalse(os.path.exists(os.path.join(work, "rider.glb")), "--to 8: экспорта нет")
        for n in ("01_check", "02_clean", "03_proportions", "04_retopo", "05_rest", "07_weights", "08_regions"):
            self.assertTrue(os.path.isfile(os.path.join(work, n + ".blend")), n)
        refine(self.raw["m"], "--work", work, "--from", "11")
        self.assertEqual(sha(os.path.join(work, "rider.glb")), sha(self.glb_path), "--to 8, затем --from 11 = полный прогон")
        code, out, err = refine(self.raw["m"], "--work", work, "--from", "4", "--to", "4")
        self.assertEqual(code, 0, "повтор одного шага --from 4 --to 4")
        self.assertIn("шаги 4–4", out)
        empty = os.path.join(self.tmp, "w_empty")
        code, out, err = refine(self.raw["m"], "--work", empty, "--from", "5")
        self.assertEqual(code, 1)
        self.assertIn("ШАГ 4", err, "--from 5 без результата шага 4 — понятная ошибка")
        for bad in (("--from", "6"), ("--from", "8", "--to", "5"), ("--to", "9"), ("--retopo", "x")):
            code, _, _ = refine(self.raw["m"], "--work", empty, *bad)
            self.assertEqual(code, 2, "неверные аргументы %s → код 2" % (bad,))

    def test_default_work_dir_outside_git(self):
        """Промежуточные .blend и отчёт не попадают в git (рабочий каталог по умолчанию)."""
        name = "t143_accept_gitcheck"
        raw = os.path.join(self.tmp, name + ".glb")
        shutil.copy(self.raw["m"], raw)
        shutil.copy(os.path.splitext(self.raw["m"])[0] + ".landmarks.json", os.path.join(self.tmp, name + ".landmarks.json"))
        before = subprocess.run(["git", "status", "--porcelain", "--untracked-files=all"], cwd=ROOT,
                                capture_output=True, text=True).stdout
        work = os.path.join(ROOT, "reference", "ai", "work", name)
        try:
            refine(raw)
            self.assertTrue(os.path.isfile(os.path.join(work, "05_rest.blend")), "рабочий каталог по умолчанию — reference/ai/work/<имя>")
            after = subprocess.run(["git", "status", "--porcelain", "--untracked-files=all"], cwd=ROOT,
                                   capture_output=True, text=True).stdout
            self.assertEqual(after, before, "git status после прогона не изменился")
            ign = subprocess.run(["git", "check-ignore", "-q", os.path.join(work, "rider.blend")], cwd=ROOT)
            self.assertEqual(ign.returncode, 0, "rider.blend в рабочем каталоге игнорируется git")
        finally:
            shutil.rmtree(work, ignore_errors=True)

    def test_compare_picks_good_variant_and_fails_when_none(self):
        """Шаг 1: «выбор лучшего из 2–3 вариантов»; ни один не годится — условие отказа 1."""
        code, out, err = refine("--compare", self.raw["bad_legs"], self.raw["m"], self.raw["cm"])
        self.assertEqual(code, 0, err[-500:])
        self.assertIn("НЕ ГОДИТСЯ", out)
        best = [ln for ln in out.splitlines() if ln.startswith("ИТОГ")]
        self.assertTrue(best and "bad_legs" not in best[0], best)
        code, out, err = refine("--compare", self.raw["bad_legs"], self.raw["bad_two"], self.raw["bad_notex"])
        self.assertEqual(code, 1)
        self.assertIn("ни один вариант не годится", out)

    # ------------------------------------------------------------ испорченные входы

    def test_broken_copies_stop_with_clear_error(self):
        for v, what in (("bad_notex", "текстур"), ("bad_legs", "ноги"), ("bad_two", "не одна фигура")):
            line = self._assert_clear_stop(self.raw[v], v, steps=(1,))
            self.assertIn(what, line, v)

    def test_garbage_and_empty_files_stop_with_clear_error(self):
        g = os.path.join(self.tmp, "garbage.glb")
        open(g, "wb").write(bytes(range(256)) * 20)
        self._assert_clear_stop(g, "garbage", steps=(1,))
        self._assert_clear_stop(os.path.join(self.tmp, "nonexistent.glb"), "missing", steps=(1,))

    def test_multi_object_glb_stops_with_clear_error(self):
        """Сырьё из нескольких объектов (сервис отдал части отдельно; здесь — bike_reference.glb):
        понятная ошибка шага 1, не трейсбек."""
        raw = os.path.join(self.tmp, "multi", "multi.glb")
        os.makedirs(os.path.dirname(raw), exist_ok=True)
        shutil.copy(BIKE, raw)
        open(os.path.join(os.path.dirname(raw), "multi.landmarks.json"), "w").write(json.dumps(self._lm()))
        self._assert_clear_stop(raw, "multi", steps=(1,))

    def test_single_mesh_under_root_node_passes_step1(self):
        """Сырой GLB, где единственная сетка — ребёнок пустого корневого узла (так экспортируют
        многие инструменты и конвертеры FBX → GLB: «world», «RootNode», «Sketchfab_model»).
        Это обычный вход — шаг 1 должен пройти (форма та же, что у synthetic_m)."""
        d = os.path.join(self.tmp, "parented")
        os.makedirs(d, exist_ok=True)
        raw = os.path.join(d, "parented.glb")
        script = os.path.join(d, "mk.py")
        open(script, "w").write(
            "import bpy, os\n"
            "bpy.ops.wm.read_factory_settings(use_empty=True)\n"
            "bpy.ops.import_scene.gltf(filepath=os.environ['T143_SRC'])\n"
            "mesh = [o for o in bpy.context.scene.objects if o.type == 'MESH'][0]\n"
            "bpy.ops.object.empty_add()\n"
            "root = bpy.context.object\n"
            "root.name = 'world'\n"
            "mesh.parent = root\n"
            "bpy.ops.export_scene.gltf(filepath=os.environ['T143_DST'], export_format='GLB')\n")
        env = dict(os.environ, T143_SRC=self.raw["m"], T143_DST=raw)
        subprocess.run(["bash", "-c", "source scripts/blender/env.sh && bpy_run \"$0\"", script], cwd=ROOT, env=env,
                       capture_output=True, text=True, timeout=600)
        self.assertTrue(os.path.isfile(raw), "фикстура parented.glb собрана")
        shutil.copy(os.path.splitext(self.raw["m"])[0] + ".landmarks.json", os.path.join(d, "parented.landmarks.json"))
        code, out, err = refine(raw, "--work", os.path.join(self.tmp, "w_parented"), "--to", "1")
        self.assertNotIn("Traceback", out + err, "трейсбек на шаге 1: %s" % err.strip().splitlines()[-1:])
        self.assertEqual(code, 0, err[-600:])

    def test_malformed_landmarks_json_stops_with_clear_error(self):
        raw = self._raw_copy("badjson", landmarks="{joints: [oops")
        self._assert_clear_stop(raw, "badjson", steps=(1, 2, 3))

    def test_missing_landmark_stops_with_clear_error(self):
        lm = self._lm()
        lm["joints"].pop("thigh.R")
        raw = self._raw_copy("nohip", landmarks=json.dumps(lm))
        line = self._assert_clear_stop(raw, "nohip", steps=(1, 2, 3))
        self.assertIn("thigh.R", line)

    def test_swapped_left_right_landmarks_stop(self):
        """Ориентиры .L/.R перепутаны (частая ошибка: «лево» со стороны зрителя). Шаг 2 ставит оси
        по ориентирам; согласованность с формой (носок впереди пятки) не проверяется → фигура
        развёрнута на 180° (смотрит в +Y) и идёт дальше. Ждём остановку шага 1–2."""
        lm = self._lm()
        sw = {}
        for n, v in lm["joints"].items():
            sw[n.replace(".L", ".#").replace(".R", ".L").replace(".#", ".R")] = v
        raw = self._raw_copy("swapped", landmarks=json.dumps({"joints": sw}))
        self._assert_clear_stop(raw, "swapped", steps=(1, 2))

    def test_units_mm_normalized_like_meters(self):
        """Сантиметры (вариант исполнителя cm) — тот же результат шага 2, что и метры (±2 мм)."""
        hs = {}
        for v in ("m", "cm", "axes"):
            work = os.path.join(self.tmp, "w_units_" + v)
            code, out, err = refine(self.raw[v], "--work", work, "--to", "3")
            self.assertEqual(code, 0, "%s: %s" % (v, err[-800:]))
            rep = json.load(open(os.path.join(work, "report.json")))
            hs[v] = rep["03_proportions"]["metrics"]["height_m"]
        for v in ("cm", "axes"):
            self.assertAlmostEqual(hs[v], hs["m"], delta=0.002, msg=v)

    # ------------------------------------------------------------ запасной путь шага 4

    def test_retopo_decimate_reaches_rider_glb(self):
        """`--retopo decimate` объявлен в README и `--help` как запасной путь шага 4. Ждём либо
        rider.glb (Т1–Т7), либо понятную остановку на самом шаге 4 — не падение шага 8."""
        work = os.path.join(self.tmp, "w_decimate")
        code, out, err = refine(self.raw["m"], "--work", work, "--retopo", "decimate")
        stop = [ln for ln in err.splitlines() if ln.startswith("ШАГ ")]
        if stop:
            self.assertTrue(stop[0].startswith("ШАГ 4"), "decimate: остановка не на шаге 4, а %s" % stop[0])
        else:
            self.assertTrue(os.path.isfile(os.path.join(work, "rider.glb")), "decimate: rider.glb")

    # ------------------------------------------------------------ шаг 3: A-поза и размеры

    def _step3(self):
        script = (
            "import bpy, json, os\n"
            "bpy.ops.wm.open_mainfile(filepath=os.environ['T143_BLEND'])\n"
            "st = json.loads(bpy.context.scene['rr_state'])\n"
            "me = bpy.data.objects['scan'].data\n"
            "co = [list(v.co) for v in me.vertices]\n"
            "json.dump({'joints': st['landmarks'], 'co': co}, open(os.environ['T143_OUT'], 'w'))\n")
        sp = os.path.join(self.tmp, "dump3.py")
        open(sp, "w").write(script)
        out = os.path.join(self.tmp, "step3.json")
        env = dict(os.environ, T143_BLEND=os.path.join(self.work, "03_proportions.blend"), T143_OUT=out)
        res = subprocess.run(["bash", "-c", "source scripts/blender/env.sh && bpy_run \"$0\"", sp], cwd=ROOT, env=env,
                             capture_output=True, text=True)
        self.assertEqual(res.returncode, 0, res.stderr[-1000:])
        d = json.load(open(out))
        return {k: np.array(v) for k, v in d["joints"].items()}, np.array(d["co"])

    @staticmethod
    def _angle(a, b, c):
        u, v = a - b, c - b
        return math.degrees(math.acos(np.clip(u @ v / np.linalg.norm(u) / np.linalg.norm(v), -1, 1)))

    def test_step3_apose_and_lengths(self):
        """art-bible «A-поза контрактного скелета», предлагаемые критерии [авто] T-143."""
        j, co = self._step3()
        bb = brief_bones()
        for s in (".L", ".R"):
            self.assertTrue(0.10 <= abs(j["foot" + s][0]) <= 0.12, "|голеностоп%s.x| = %.3f" % (s, j["foot" + s][0]))
            self.assertGreaterEqual(self._angle(j["thigh" + s], j["shin" + s], j["foot" + s]), 178.0, "колено%s" % s)
            arm = j["forearm" + s] - j["upperarm" + s]
            ang = math.degrees(math.atan2(abs(arm[0]), -arm[2]))
            self.assertTrue(40.0 <= ang <= 45.0, "плечо%s от вертикали в XZ: %.1f°" % (s, ang))
            el = self._angle(j["upperarm" + s], j["forearm" + s], j["hand" + s])
            self.assertTrue(160.0 <= el <= 170.0, "локоть%s %.1f°" % (s, el))
            for a, b in (("thigh", "shin"), ("shin", "foot"), ("upperarm", "forearm"), ("forearm", "hand"), ("hand", "grip")):
                want = np.linalg.norm(bb[b + s][1] - bb[a + s][1])
                got = np.linalg.norm(j[b + s] - j[a + s])
                self.assertAlmostEqual(got, want, delta=0.005, msg="%s%s—%s: %.4f vs %.4f" % (a, s, b, got, want))
        self.assertAlmostEqual(abs(j["thigh.L"][0] - j["thigh.R"][0]), 0.18, delta=0.005, msg="HIP")
        chain = ["pelvis", "spine", "chest", "neck", "head"]
        for a, b in zip(chain, chain[1:]):
            d = j[b] - j[a]
            self.assertLessEqual(math.degrees(math.acos(d[2] / np.linalg.norm(d))), 3.0, "%s→%s от вертикали" % (a, b))
        h = float(co[:, 2].max())
        self.assertTrue(1.77 <= h <= 1.79, "рост (верх сетки над z = 0) %.3f" % h)

    @staticmethod
    def _section_half_width(co, z, band=0.01):
        """Половина ширины связного (по X, без разрывов > 2 см) сечения вокруг x = 0 на высоте z."""
        xs = np.sort(co[np.abs(co[:, 2] - z) < band, 0])
        right = xs[xs >= 0]
        left = -xs[xs <= 0][::-1]
        def reach(v):
            v = np.sort(v)
            if len(v) == 0:
                return 0.0
            gaps = np.where(np.diff(v) > 0.02)[0]
            return float(v[gaps[0]] if len(gaps) else v[-1])
        return reach(right), reach(left)

    def test_step3_girths_follow_table_m(self):
        """art-bible шаг 3: «обхваты — к таблице m» (выход шага — «форма в размерах контракта»).
        Плечи снаружи по дельтам — наибольшая |x| сечения на высоте плечевых суставов (в A-позе
        руки уходят вниз, на этой высоте снаружи — дельты), талия — ширина связного сечения
        корпуса на высоте spine (без рук); таблица m ± 0.01 м."""
        j, co = self._step3()
        z = (j["upperarm.L"][2] + j["upperarm.R"][2]) / 2
        band = co[np.abs(co[:, 2] - z) < 0.01]
        width = float(band[:, 0].max() - band[:, 0].min())
        lo, hi = FIG_M["shoulders_outer"]
        self.assertTrue(lo - 0.01 <= width <= hi + 0.01, "плечи снаружи %.3f м, таблица m %s ± 0.01" % (width, FIG_M["shoulders_outer"]))
        r, l = self._section_half_width(co, j["spine"][2])
        lo, hi = FIG_M["waist"]
        self.assertTrue(lo - 0.01 <= r + l <= hi + 0.01, "талия %.3f м, таблица m %s ± 0.01" % (r + l, FIG_M["waist"]))

    # ------------------------------------------------------------ rider.glb: Т1–Т7 по файлу

    def test_glb_t1_t2_t7_names_bones_rest_transforms(self):
        doc, binary = glb(self.glb_path)
        names = [n.get("name") for n in doc["nodes"]]
        self.assertIn("rider_rig", names, "Т1: арматура rider_rig")
        meshes = [n["name"] for n in doc["nodes"] if "mesh" in n]
        self.assertEqual(meshes, ["body_m"], "на этом этапе — только body_m (остальные 11 сеток — T-106c′)")
        self.assertEqual([m["name"] for m in doc["meshes"]], ["body_m"], "Т1: сетка (mesh data) = имя объекта")
        self.assertEqual(len(doc["skins"]), 1)
        skin = doc["skins"][0]
        joints = [doc["nodes"][i]["name"] for i in skin["joints"]]
        w, parent = world(doc)
        bb = brief_bones()
        self.assertEqual(len(joints), 25, "Т2: 25 костей")
        self.assertEqual(sorted(joints), sorted(list(bb) + ["hair_tail.2"]))
        idx = {doc["nodes"][i]["name"]: i for i in skin["joints"]}
        rig = names.index("rider_rig")
        for n, (par, head, _) in bb.items():
            p = parent.get(idx[n])
            pname = doc["nodes"][p]["name"] if p is not None else None
            self.assertEqual(pname, par or "rider_rig", "Т2: родитель %s" % n)
            got = to_blender(w[idx[n]][:3, 3])
            self.assertLess(np.linalg.norm(got - head), 0.001, "Т2 (заявлено ±0 мм; бриф ±5): %s %s vs %s" % (n, got, head))
        t1 = to_blender(w[idx["hair_tail.1"]][:3, 3])
        t2 = to_blender(w[idx["hair_tail.2"]][:3, 3])
        self.assertTrue(0.09 - 1e-4 <= np.linalg.norm(t2 - t1) <= 0.10 + 1e-4, "hair_tail.2 в 0.09–0.10 м от hair_tail.1")
        # Т7: арматура в начале координат, масштаб 1, поворот 0; тело — ребёнок rider_rig.
        body = names.index("body_m")
        for i in (rig, body):
            n = doc["nodes"][i]
            self.assertLess(np.abs(np.array(n.get("translation", [0, 0, 0]))).max(), 1e-6, "Т7: %s в начале" % n["name"])
            self.assertLess(np.abs(np.array(n.get("scale", [1, 1, 1])) - 1).max(), 1e-6, "Т7: масштаб %s" % n["name"])
            self.assertLess(np.abs(np.array(n.get("rotation", [0, 0, 0, 1])) - [0, 0, 0, 1]).max(), 1e-6, "Т7: поворот %s" % n["name"])
        self.assertEqual(parent.get(body), rig, "бриф §12: объекты — дети rider_rig")
        self.assertNotIn(rig, parent, "rider_rig — корень сцены")

    def test_glb_t3_t4_t5_material_attributes_budget_weights(self):
        doc, binary = glb(self.glb_path)
        self.assertEqual([m["name"] for m in doc.get("materials", [])], ["M_rider"], "Т3: один M_rider")
        for k in ("animations", "images", "textures", "cameras"):
            self.assertNotIn(k, doc, "Т3/§12: нет %s" % k)
        used = set(doc.get("extensionsUsed", []))
        self.assertFalse(used & {"KHR_draco_mesh_compression", "EXT_meshopt_compression"}, "§12: без сжатия")
        self.assertFalse(any("KHR_lights" in u for u in used), "§12: без света")
        skin = doc["skins"][0]
        jn = [doc["nodes"][i]["name"] for i in skin["joints"]]
        no_weight = {jn.index(s) for s in SOCKETS} | {jn.index("hair_tail.1"), jn.index("hair_tail.2")}
        tris = 0
        for prim in doc["meshes"][0]["primitives"]:
            a = prim["attributes"]
            self.assertEqual(sorted(a), ["JOINTS_0", "NORMAL", "POSITION", "TEXCOORD_0", "WEIGHTS_0"],
                             "Т3: нет COLOR_0, второго UV, касательных, JOINTS_1")
            self.assertNotIn("targets", prim, "Т3: нет shape keys")
            self.assertEqual(prim.get("mode", 4), 4)
            tris += doc["accessors"][prim["indices"]]["count"] // 3
            jj = acc(doc, binary, a["JOINTS_0"]).astype(int)
            ww = acc(doc, binary, a["WEIGHTS_0"])
            self.assertLess(float(np.abs(ww.sum(axis=1) - 1).max()), 2e-3, "Т5: сумма весов 1")
            self.assertLessEqual(int((ww > 0).sum(axis=1).max()), 4, "Т5: ≤ 4 кости")
            on = jj[ww > 1e-6]
            bad = sorted({jn[k] for k in on if k in no_weight})
            self.assertEqual(bad, [], "Т5: сокеты (и хвост на body_m) без весов")
        self.assertLessEqual(tris, BUDGET["body_m"], "Т4: body_m ≤ 8000")
        self.assertEqual(tris, 7942, "заявлено исполнителем: 7942 треугольника")

    def test_glb_t6_uv_columns_and_body_regions(self):
        doc, binary = glb(self.glb_path)
        cols = set()
        for prim in doc["meshes"][0]["primitives"]:
            uv = acc(doc, binary, prim["attributes"]["TEXCOORD_0"])
            idx = acc(doc, binary, prim["indices"]).reshape(-1, 3).astype(int)
            u = uv[idx, 0] * 32.0  # (грань, 3)
            k = np.floor(u[:, 0])
            same = (np.floor(u) == k[:, None]).all(axis=1)
            self.assertTrue(bool(same.all()), "Т6: грань в одной колонке (%d граней вне)" % int((~same).sum()))
            frac = u - k[:, None]
            inside = ((frac >= 0.1 - 1e-4) & (frac <= 0.9 + 1e-4)).all(axis=1)
            self.assertTrue(bool(inside.all()), "Т6: отступ 10 %% (%d граней у края)" % int((~inside).sum()))
            cols |= set(k.astype(int).tolist())
        self.assertFalse({c for c in cols if c >= 23}, "Т6: регионы 23–31 (велосипед) не используются")
        self.assertTrue(BODY_REGIONS <= cols, "Т6: у фигуры регионы 0–11 и 21–22; нет %s" % sorted(BODY_REGIONS - cols))

    # ------------------------------------------------------------ rider_contract.json против брифа §5

    def test_contract_json_bones_vs_brief(self):
        c = json.load(open(CONTRACT))
        bb = brief_bones()
        bones = {b["name"]: b for b in c["bones"]}
        self.assertEqual(len(c["bones"]), 25)
        self.assertEqual(set(bones), set(bb) | {"hair_tail.2"})
        for n, (par, head, deform) in bb.items():
            b = bones[n]
            self.assertEqual(b["parent"], par, n)
            self.assertLess(np.linalg.norm(np.array(b["head"]) - head), 1e-4, "head %s" % n)
            self.assertEqual(b["deform"], deform, "Deform %s" % n)
        self.assertEqual(sorted(n for n, b in bones.items() if not b["deform"]), sorted(SOCKETS), "Deform off ровно у 6 сокетов")
        self.assertEqual(bones["hair_tail.2"]["parent"], "hair_tail.1")
        for n, b in bones.items():
            head, tail = np.array(b["head"]), np.array(b["tail"])
            base = n.replace(".R", ".L")
            sx = -1.0 if n.endswith(".R") else 1.0
            if base in TAIL_CHILD:
                child = TAIL_CHILD[base].replace(".L", ".R") if n.endswith(".R") else TAIL_CHILD[base]
                self.assertLess(np.linalg.norm(tail - np.array(bones[child]["head"])), 1e-4, "tail %s = начало %s" % (n, child))
            elif base in TAIL_POINT:
                p = np.array(TAIL_POINT[base]) * [sx, 1, 1]
                self.assertLess(np.linalg.norm(tail - p), 0.01, "tail %s ≈ %s" % (n, p))
            elif n in SOCKETS:
                self.assertLess(np.linalg.norm(tail - (head - [0, 0, 0.03])), 1e-4, "tail %s — 3 см вниз" % n)
            # Roll: локальная X — проекция мировой +X на плоскость, перпендикулярную кости (Global +X).
            y = (tail - head) / np.linalg.norm(tail - head)
            x = np.array(b["axis_x"])
            want = np.array([1.0, 0, 0]) - y * y[0]
            want /= np.linalg.norm(want)
            self.assertLess(np.linalg.norm(x - want), 1e-3, "roll %s: X = Global +X" % n)

    def test_contract_json_control_poses_vs_brief(self):
        c = json.load(open(CONTRACT))
        table = {r["phi_deg"]: r for r in c["control_poses_table"]}
        for phi in (0, 90, 180, 270):
            cleat, ankle, knee, kdeg, fdeg = CONTROL[phi]
            r = table[phi]
            self.assertLess(np.linalg.norm(np.array(r["cleat"]) - [-0.115, *cleat]), 1e-4, "шип φ=%d" % phi)
            self.assertLess(np.linalg.norm(np.array(r["ankle"]) - [-0.110, *ankle]), 1e-4, "голеностоп φ=%d" % phi)
            self.assertLess(np.linalg.norm(np.array(r["knee"]) - [-0.100, *knee]), 1e-4, "колено φ=%d" % phi)
            self.assertEqual((r["knee_deg"], r["foot_deg"]), (kdeg, fdeg), "углы φ=%d" % phi)
        poses = {p["phi_deg"]: p for p in c["control_poses"]}
        self.assertEqual(sorted(poses), list(range(0, 360, 15)), "φ 0…345 шаг 15")
        bones = {b["name"]: np.array(b["head"]) for b in c["bones"]}
        thigh = np.linalg.norm(bones["shin.R"] - bones["thigh.R"])
        shin = np.linalg.norm(bones["foot.R"] - bones["shin.R"])
        for phi, p in poses.items():
            R, L = p["R"], p["L"]
            rad = math.radians(phi)
            pedal = np.array([-0.115, -0.17 * math.sin(rad), 0.27 + 0.17 * math.cos(rad)])
            self.assertLess(np.linalg.norm(np.array(R["cleat"]) - pedal), 0.001, "шип R на оси педали φ=%d" % phi)
            self.assertAlmostEqual(np.linalg.norm(np.array(R["knee"]) - R["hip"]), thigh, delta=0.001)
            self.assertAlmostEqual(np.linalg.norm(np.array(R["ankle"]) - R["knee"]), shin, delta=0.001)
            theta = -14 + 12 * math.cos(math.radians(phi - 100))
            self.assertAlmostEqual(R["foot_deg"], theta, delta=1.0, msg="θ(φ=%d) по кривой ред. 3" % phi)
            m = poses[(phi + 180) % 360]["R"]
            for k in ("hip", "knee", "ankle", "cleat", "heel"):
                self.assertLess(np.linalg.norm(np.array(L[k]) - np.array(m[k]) * [-1, 1, 1]), 0.001,
                                "L(φ=%d) = зеркало R(φ+180) %s" % (phi, k))
            if phi in CONTROL:
                cleat, ankle, knee, kdeg, _ = CONTROL[phi]
                self.assertLess(np.linalg.norm(np.array(R["knee"])[1:] - knee), 0.01, "колено φ=%d ±0.01" % phi)
                self.assertLess(np.linalg.norm(np.array(R["ankle"])[1:] - ankle), 0.01, "голеностоп φ=%d ±0.01" % phi)
                self.assertAlmostEqual(R["knee_deg"], kdeg, delta=2.0)

    def test_contract_json_has_rest_and_apose(self):
        """art-bible «Вход конвейера из пакета»: в JSON-контракте — контрольные позы правой ноги
        «φ = 0/90/180/270 и rest» и A-поза; предлагаемый критерий: «есть позы φ = 0/90/180/270,
        rest и A-поза»."""
        c = json.load(open(CONTRACT))
        text = json.dumps(c).lower()
        rows = [r.get("phi_deg") for r in c["control_poses_table"]]
        self.assertTrue("rest" in rows or any(r.get("name") == "rest" for r in c["control_poses_table"]),
                        "строка rest таблицы «Контрольные позы» в rider_contract.json (есть φ: %s)" % rows)
        self.assertTrue("apose" in text or "a_pose" in text or "a-поза" in text,
                        "A-поза в rider_contract.json (сейчас — только в scripts/blender/pipeline_data.json)")
        cleat, ankle, knee, kdeg, fdeg = CONTROL["rest"]
        bones = {b["name"]: np.array(b["head"]) for b in c["bones"]}
        self.assertLess(np.linalg.norm(bones["shin.R"][1:] - knee), 1e-4)
        self.assertLess(np.linalg.norm(bones["foot.R"][1:] - ankle), 1e-4)
        self.assertLess(np.linalg.norm(bones["cleat.R"][1:] - cleat), 1e-4)

    def test_contract_json_bike_sway_views_vs_brief(self):
        c = json.load(open(CONTRACT))
        b = c["bike"]
        self.assertEqual(b["bb"], [0.0, 0.0, 0.27])
        self.assertEqual((b["crank_m"], b["pedal_x_m"], b["wheel_radius_m"]), (0.17, 0.115, 0.335))
        self.assertEqual(b["rear_axle"], [0.0, 0.405, 0.335])
        self.assertEqual(b["front_axle"], [0.0, -0.585, 0.335])
        self.assertEqual((b["saddle_node"], b["saddle_top_m"], b["saddle_length_m"], b["saddle_rear_width_m"]),
                         ("saddle", 0.965, 0.27, 0.13))
        self.assertTrue(0.03 <= b["saddle_rear_behind_s_m"] <= 0.10)
        self.assertEqual(b["points"]["pt_grip_L"], [0.21, -0.62, 0.885])
        self.assertEqual(b["points"]["pt_cleat_R_pedal_axis"], [-0.115, -0.17, 0.27])
        sway = {tuple(s["bones"]): s for s in c["sway"]}
        self.assertEqual(sway[("pelvis",)]["roll_deg"], 1.0)
        self.assertEqual((sway[("spine", "chest")]["roll_deg"], sway[("spine", "chest")]["yaw_deg"]), (1.5, 1.2))
        self.assertEqual((sway[("head",)]["roll_deg"], sway[("head",)]["yaw_deg"]), (1.5, 1.0))
        self.assertEqual(sway[("shin.L", "shin.R")]["side_m"], 0.01)

    def test_contract_json_views_vs_brief_rev41(self):
        """Бриф §14 / art-bible ред. 4.1: hips_r поднят на 0.12 м. Строку в коде (`RiderRig`) по спеке
        меняет TA в T-106a2; JSON-контракт собирается из кода — до T-106a2 расходится."""
        c = json.load(open(CONTRACT))
        views = {v["name"]: v for v in c["views"]}
        for name, (cam, tgt, fov, crank) in VIEWS.items():
            v = views[name]
            self.assertLess(np.linalg.norm(np.array(v["camera"]) - cam), 1e-6, "%s: камера %s, бриф %s" % (name, v["camera"], cam))
            self.assertLess(np.linalg.norm(np.array(v["target"]) - tgt), 1e-6, "%s: цель %s, бриф %s" % (name, v["target"], tgt))
            self.assertEqual((v["fov_deg"], v["crank_deg"]), (fov, crank), name)

    # ------------------------------------------------------------ bike_reference.glb: узел saddle

    def test_bike_reference_saddle_node_and_same_geometry(self):
        doc, binary = glb(BIKE)
        names = [n.get("name") for n in doc["nodes"]]
        self.assertIn("saddle", names, "узел saddle")
        si = names.index("saddle")
        self.assertIn("mesh", doc["nodes"][si], "saddle — узел с сеткой")
        w, _ = world(doc)
        sub = {"nodes": [doc["nodes"][si] if i == si else {k: v for k, v in n.items() if k != "mesh"}
                         for i, n in enumerate(doc["nodes"])], "meshes": doc["meshes"],
               "accessors": doc["accessors"], "bufferViews": doc["bufferViews"]}
        saddle = to_blender(world_triangles(sub, binary))
        top = top_at(saddle, 0.0, 0.230)
        self.assertIsNotNone(top, "седло под S")
        self.assertAlmostEqual(top, 0.965, delta=0.002, msg="верх седла под S")
        old = subprocess.run(["git", "show", "%s:assets/rider/reference/bike_reference.glb" % BIKE_BEFORE_REV],
                             cwd=ROOT, capture_output=True).stdout
        odoc, obin = glb(old)
        self.assertNotIn("saddle", [n.get("name") for n in odoc["nodes"]], "в старом пакете седла отдельно нет")
        a = world_triangles(doc, binary)
        b = world_triangles(odoc, obin)
        self.assertEqual(len(a), len(b), "сумма треугольников всех узлов равна прежней")

        def canon(t):
            t = np.round(t, 5)
            rows = [tuple(sorted(map(tuple, tri))) for tri in t]
            return sorted(rows)
        self.assertEqual(canon(a), canon(b), "те же треугольники в мире (геометрия велосипеда не изменилась)")


if __name__ == "__main__":
    unittest.main(verbosity=2)
