#!/usr/bin/env python3
"""Arciere low-poly con scheletro e animazioni, scritto come .gltf (stile Quaternius).

Uso (dalla cartella del progetto):
    python3 tools/modelli/genera_arciere.py
Crea data/unithMesh/Units/Archer.gltf e Archer_Atlas.png. Poi si cuoce con tools/vat_baker.tscn
(o tools/vat_bake_cli.gd) come qualsiasi altro modello.

Il modello guarda verso +Z (come i modelli scaricati), alto circa 1,8 m, piedi a y = 0.
Ogni pezzo segue un solo osso (tranne la corda dell'arco, che si tende).
I colori sono in una piccola tavolozza: cambia PALETTE per ricolorarlo.
"""
import base64
import json
import math
import os
import struct
import zlib

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
OUT_DIR = os.path.join(ROOT, "data", "unithMesh", "Units")
NAME = "Archer"

# ------------------------------------------------------------------ tavolozza (4x4 pixel)
PALETTE = [
    (238, 190, 152),  # 0 pelle
    (72, 122, 56),    # 1 tunica verde
    (40, 78, 38),     # 2 cappuccio e mantello
    (118, 74, 38),    # 3 cuoio
    (62, 40, 24),     # 4 stivali
    (132, 112, 80),   # 5 brache
    (140, 92, 48),    # 6 legno dell'arco
    (232, 226, 205),  # 7 corda
    (178, 182, 190),  # 8 metallo
    (244, 244, 240),  # 9 piume
    (28, 22, 20),     # 10 occhi
    (214, 176, 76),   # 11 fibbia
    (92, 58, 32),     # 12 capelli
    (176, 48, 40),    # 13 piume rosse
    (96, 64, 34),     # 14 faretra
    (255, 255, 255),  # 15 libero
]
SKIN, TUNIC, HOOD, LEATHER, BOOT, PANTS, WOOD, STRING, METAL, FEATHER, EYE, GOLD, HAIR, RED, QUIVER = range(15)


def uv_of(c):
    return ((c % 4 + 0.5) / 4.0, (c // 4 + 0.5) / 4.0)


# ------------------------------------------------------------------ matematica
def add(a, b): return (a[0] + b[0], a[1] + b[1], a[2] + b[2])
def sub(a, b): return (a[0] - b[0], a[1] - b[1], a[2] - b[2])
def mul(a, s): return (a[0] * s, a[1] * s, a[2] * s)
def dot(a, b): return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]
def cross(a, b): return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])
def length(a): return math.sqrt(dot(a, a))


def norm(a):
    l = length(a)
    return mul(a, 1.0 / l) if l > 1e-9 else (0.0, 0.0, 0.0)


QI = (0.0, 0.0, 0.0, 1.0)


def qmul(a, b):
    ax, ay, az, aw = a
    bx, by, bz, bw = b
    return (aw * bx + ax * bw + ay * bz - az * by,
            aw * by - ax * bz + ay * bw + az * bx,
            aw * bz + ax * by - ay * bx + az * bw,
            aw * bw - ax * bx - ay * by - az * bz)


def qaxis(axis, deg):
    h = math.radians(deg) * 0.5
    s = math.sin(h)
    a = norm(axis)
    return (a[0] * s, a[1] * s, a[2] * s, math.cos(h))


def qe(x=0.0, y=0.0, z=0.0):
    """Gradi: prima rollio (Z), poi beccheggio (X), poi imbardata (Y)."""
    return qmul(qaxis((0, 1, 0), y), qmul(qaxis((1, 0, 0), x), qaxis((0, 0, 1), z)))


def qinv(q): return (-q[0], -q[1], -q[2], q[3])


def qrot(q, v):
    p = qmul(qmul(q, (v[0], v[1], v[2], 0.0)), qinv(q))
    return (p[0], p[1], p[2])


def qfromto(u, v):
    u, v = norm(u), norm(v)
    d = dot(u, v)
    if d < -0.99999:
        ax = cross((1, 0, 0), u)
        if length(ax) < 1e-6:
            ax = cross((0, 1, 0), u)
        return qaxis(ax, 180.0)
    c = cross(u, v)
    q = (c[0], c[1], c[2], 1.0 + d)
    l = math.sqrt(sum(x * x for x in q))
    return tuple(x / l for x in q)


def qslerp(a, b, t):
    d = sum(x * y for x, y in zip(a, b))
    if d < 0:
        b = tuple(-x for x in b)
        d = -d
    if d > 0.9995:
        r = tuple(x + (y - x) * t for x, y in zip(a, b))
    else:
        th = math.acos(d)
        s = math.sin(th)
        wa, wb = math.sin((1 - t) * th) / s, math.sin(t * th) / s
        r = tuple(x * wa + y * wb for x, y in zip(a, b))
    l = math.sqrt(sum(x * x for x in r))
    return tuple(x / l for x in r)


def lerp(a, b, t): return a + (b - a) * t
def vlerp(a, b, t): return tuple(lerp(x, y, t) for x, y in zip(a, b))
def smooth(t): t = min(max(t, 0.0), 1.0); return t * t * (3 - 2 * t)
def seg(t, a, b): return smooth((t - a) / (b - a)) if b > a else (1.0 if t >= b else 0.0)


# ------------------------------------------------------------------ scheletro (posa a riposo: solo spostamenti)
BONES = [  # nome, genitore, posizione nel modello
    ("Root", None, (0.0, 0.0, 0.0)),
    ("Hips", "Root", (0.0, 0.95, 0.0)),
    ("Spine", "Hips", (0.0, 1.08, 0.0)),
    ("Chest", "Spine", (0.0, 1.25, 0.0)),
    ("Head", "Chest", (0.0, 1.50, 0.0)),
    ("UpperArm.L", "Chest", (0.25, 1.42, 0.0)),
    ("LowerArm.L", "UpperArm.L", (0.27, 1.14, 0.0)),
    ("Hand.L", "LowerArm.L", (0.28, 0.88, 0.0)),
    ("UpperArm.R", "Chest", (-0.25, 1.42, 0.0)),
    ("LowerArm.R", "UpperArm.R", (-0.27, 1.14, 0.0)),
    ("Hand.R", "LowerArm.R", (-0.28, 0.88, 0.0)),
    ("UpperLeg.L", "Hips", (0.10, 0.92, 0.0)),
    ("LowerLeg.L", "UpperLeg.L", (0.10, 0.50, 0.0)),
    ("UpperLeg.R", "Hips", (-0.10, 0.92, 0.0)),
    ("LowerLeg.R", "UpperLeg.R", (-0.10, 0.50, 0.0)),
    ("Bow", "Hand.L", (0.28, 0.84, 0.0)),
    ("BowString", "Bow", (0.28, 0.84, -0.10)),
    ("Arrow", "BowString", (0.28, 0.84, -0.10)),
]
BI = {b[0]: i for i, b in enumerate(BONES)}
PARENT = {b[0]: b[1] for b in BONES}
REST = {b[0]: b[2] for b in BONES}


def rest_local(name):
    p = PARENT[name]
    return REST[name] if p is None else sub(REST[name], REST[p])


# ------------------------------------------------------------------ geometria
P, N, UV, J, W = [], [], [], [], []


def tri(a, b, c, color, bones):
    """bones: per vertice una lista [(osso, peso)], oppure un solo nome per tutti."""
    n = norm(cross(sub(b, a), sub(c, a)))
    for v, k in zip((a, b, c), range(3)):
        P.append(v)
        N.append(n)
        UV.append(uv_of(color))
        bw = bones[k] if isinstance(bones, list) else [(bones, 1.0)]
        js = [BI[x[0]] for x in bw] + [0] * (4 - len(bw))
        ws = [x[1] for x in bw] + [0.0] * (4 - len(bw))
        J.append(js)
        W.append(ws)


def quad(a, b, c, d, color, bones):
    if isinstance(bones, list):
        tri(a, b, c, color, [bones[0], bones[1], bones[2]])
        tri(a, c, d, color, [bones[0], bones[2], bones[3]])
    else:
        tri(a, b, c, color, bones)
        tri(a, c, d, color, bones)


def hexa(c, color, bone):
    """c: 8 angoli, 0-3 sotto (in senso orario visto dall'alto), 4-7 sopra."""
    quad(c[0], c[1], c[2], c[3], color, bone)        # sotto
    quad(c[4], c[7], c[6], c[5], color, bone)        # sopra
    for i in range(4):
        j = (i + 1) % 4
        quad(c[i], c[i + 4], c[j + 4], c[j], color, bone)


def box(center, size, color, bone, taper=(1.0, 1.0), shift=(0.0, 0.0)):
    """Scatola allineata agli assi; taper e shift modificano la faccia superiore (x, z)."""
    cx, cy, cz = center
    hx, hy, hz = size[0] / 2, size[1] / 2, size[2] / 2
    bot = [(-1, -1), (1, -1), (1, 1), (-1, 1)]
    c = [(cx + sx * hx, cy - hy, cz + sz * hz) for sx, sz in bot]
    c += [(cx + shift[0] + sx * hx * taper[0], cy + hy, cz + shift[1] + sz * hz * taper[1]) for sx, sz in bot]
    hexa(c, color, bone)


def limb(p0, p1, w, d, color, bone, taper=1.0, side_hint=(1, 0, 0)):
    """Scatola orientata da p0 a p1 (sezione w x d, in cima scalata di taper)."""
    a = norm(sub(p1, p0))
    t = norm(cross(side_hint, a))
    if length(t) < 1e-6:
        t = norm(cross((0, 0, 1), a))
    s = norm(cross(a, t))
    corners = []
    for p, k in ((p0, 1.0), (p1, taper)):
        for sx, sz in [(-1, -1), (-1, 1), (1, 1), (1, -1)]:
            corners.append(add(p, add(mul(s, sx * w / 2 * k), mul(t, sz * d / 2 * k))))
    # p0 è "sotto": l'ordine delle facce deve restare coerente con hexa
    if dot(cross(sub(corners[1], corners[0]), sub(corners[2], corners[0])), a) > 0:
        corners = corners[:4][::-1] + corners[4:][::-1]
    hexa(corners, color, bone)


def prism(p0, p1, r0, r1, sides, color, bone, phase=0.0):
    a = norm(sub(p1, p0))
    ref = (0, 0, 1) if abs(a[2]) < 0.9 else (1, 0, 0)
    u = norm(cross(a, ref))
    v = cross(a, u)
    ring = lambda p, r: [add(p, add(mul(u, math.cos(phase + 2 * math.pi * i / sides) * r),
                                    mul(v, math.sin(phase + 2 * math.pi * i / sides) * r))) for i in range(sides)]
    b, t = ring(p0, r0), ring(p1, r1)
    for i in range(sides):
        j = (i + 1) % sides
        quad(b[i], b[j], t[j], t[i], color, bone)
        tri(p0, b[j], b[i], color, bone)
        tri(p1, t[i], t[j], color, bone)


def build_mesh():
    # gambe: brache e stivali alti
    for s, up, lo in ((1, "UpperLeg.L", "LowerLeg.L"), (-1, "UpperLeg.R", "LowerLeg.R")):
        x = 0.10 * s
        box((x, 0.71, 0.0), (0.15, 0.44, 0.16), PANTS, up, taper=(1.1, 1.05))
        box((x, 0.31, 0.0), (0.13, 0.42, 0.14), BOOT, lo, taper=(1.12, 1.1))
        box((x, 0.47, 0.0), (0.15, 0.06, 0.16), LEATHER, lo)              # risvolto
        box((x, 0.05, 0.04), (0.13, 0.10, 0.24), BOOT, lo, taper=(1.0, 0.8), shift=(0, -0.02))
    # bacino e gonnellino della tunica
    box((0.0, 0.83, 0.0), (0.40, 0.26, 0.24), TUNIC, "Hips", taper=(0.88, 0.88))
    box((0.0, 0.95, 0.0), (0.37, 0.07, 0.23), LEATHER, "Hips")            # cintura
    box((0.0, 0.95, 0.118), (0.07, 0.06, 0.012), GOLD, "Hips")            # fibbia
    box((0.13, 0.86, 0.11), (0.08, 0.1, 0.04), LEATHER, "Hips")           # borsello
    # busto
    box((0.0, 1.07, 0.0), (0.34, 0.20, 0.21), TUNIC, "Spine", taper=(1.06, 1.0))
    box((0.0, 1.30, 0.0), (0.38, 0.30, 0.22), TUNIC, "Chest", taper=(1.08, 0.95))
    # bandoliera della faretra, in diagonale sul petto
    limb((-0.17, 1.12, 0.115), (0.16, 1.44, 0.10), 0.05, 0.012, LEATHER, "Chest", side_hint=(0, 0, 1))
    # mantellina sulle spalle e mantello corto
    box((0.0, 1.45, -0.005), (0.48, 0.08, 0.27), HOOD, "Chest", taper=(0.75, 0.85))
    box((0.0, 1.10, -0.135), (0.42, 0.62, 0.03), HOOD, "Chest", taper=(0.85, 1.0), shift=(0, 0.02))
    # faretra sulla schiena, con le frecce
    q0, q1 = (0.13, 0.98, -0.19), (-0.09, 1.52, -0.19)
    prism(q0, q1, 0.055, 0.06, 6, QUIVER, "Chest")
    prism(add(q1, (0.0, -0.04, 0.0)), q1, 0.065, 0.065, 6, LEATHER, "Chest")
    qa = norm(sub(q1, q0))
    for k, off in enumerate(((0.02, 0.0, 0.02), (-0.025, 0.0, 0.0), (0.0, 0.0, -0.025))):
        base = add(q1, off)
        limb(base, add(base, mul(qa, 0.16)), 0.012, 0.012, WOOD, "Chest")
        fl = add(base, mul(qa, 0.08))
        limb(fl, add(fl, mul(qa, 0.08)), 0.05, 0.008, RED if k == 1 else FEATHER, "Chest", side_hint=(0, 0, 1))
    # testa, capelli e cappuccio a punta
    box((0.0, 1.535, 0.0), (0.08, 0.07, 0.08), SKIN, "Head")             # collo
    box((0.0, 1.66, 0.01), (0.24, 0.24, 0.24), SKIN, "Head", taper=(0.92, 0.92))
    box((0.0, 1.645, 0.135), (0.05, 0.06, 0.04), SKIN, "Head", taper=(0.6, 0.6))   # naso
    for s in (1, -1):
        box((0.055 * s, 1.68, 0.131), (0.035, 0.045, 0.01), EYE, "Head")
    box((0.0, 1.765, 0.115), (0.22, 0.05, 0.04), HAIR, "Head")            # frangia
    box((0.0, 1.70, -0.03), (0.30, 0.34, 0.26), HOOD, "Head", taper=(0.82, 0.86), shift=(0, -0.01))
    box((0.0, 1.73, -0.19), (0.12, 0.14, 0.12), HOOD, "Head", taper=(0.2, 0.2), shift=(0, -0.08))
    # braccia: maniche, bracciali di cuoio, mani
    for s, ua, la, ha in ((1, "UpperArm.L", "LowerArm.L", "Hand.L"), (-1, "UpperArm.R", "LowerArm.R", "Hand.R")):
        sh, el, wr = REST[ua], REST[la], REST[ha]
        limb(add(sh, (0, 0.04, 0)), el, 0.12, 0.12, TUNIC, ua, taper=0.9)
        limb(add(el, (0, 0.02, 0)), wr, 0.10, 0.10, LEATHER, la, taper=0.9)
        limb(wr, add(wr, (0.003 * s, -0.10, 0.0)), 0.085, 0.085, SKIN, ha, taper=0.85)
    # arco: archi di legno curvi nel piano YZ, impugnatura nella mano sinistra
    g = REST["Bow"]
    L, bulge, n = 0.64, 0.10, 6
    def bow_pt(y):  # impugnatura avanti (z = 0), punte indietro (z = -bulge)
        return add(g, (0.0, y, -bulge * (abs(y) / L) ** 1.6))
    for side in (1, -1):
        for k in range(n):
            y0, y1 = side * L * k / n, side * L * (k + 1) / n
            th = lerp(0.05, 0.028, k / n)
            limb(bow_pt(y0), bow_pt(y1), 0.04, th, WOOD, "Bow", side_hint=(1, 0, 0))
    box(add(g, (0, 0, 0.0)), (0.05, 0.14, 0.055), LEATHER, "Bow")       # impugnatura
    # corda: le punte seguono l'arco, il centro segue l'osso della corda (si tende)
    sp = REST["BowString"]
    for side in (1, -1):
        tip = bow_pt(side * L)
        w = 0.006
        for dx, dz in ((w, 0), (0, w)):
            a, b = add(tip, (-dx, 0, -dz)), add(tip, (dx, 0, dz))
            c, d = add(sp, (dx, 0, dz)), add(sp, (-dx, 0, -dz))
            bw = [[("Bow", 1.0)], [("Bow", 1.0)], [("BowString", 1.0)], [("BowString", 1.0)]]
            quad(a, b, c, d, STRING, bw)
            quad(d, c, b, a, STRING, bw[::-1])
    # freccia incoccata (visibile solo mentre tira): dalla corda in avanti
    a0 = REST["Arrow"]
    limb(a0, add(a0, (0, 0, 0.74)), 0.014, 0.014, WOOD, "Arrow")
    limb(add(a0, (0, 0, 0.74)), add(a0, (0, 0, 0.82)), 0.035, 0.012, METAL, "Arrow", taper=0.05)
    limb(add(a0, (0, 0, 0.02)), add(a0, (0, 0, 0.12)), 0.012, 0.05, RED, "Arrow")
    limb(add(a0, (0, 0, 0.02)), add(a0, (0, 0, 0.12)), 0.05, 0.012, FEATHER, "Arrow")


# ------------------------------------------------------------------ cinematica (per mirare con l'arco)
def fk(rot, pos):
    """Trasformazioni globali di ogni osso: (rotazione, posizione)."""
    g = {}
    for name, parent, _ in BONES:
        r = rot.get(name, QI)
        t = pos.get(name, rest_local(name))
        if parent is None:
            g[name] = (r, t)
        else:
            pr, pt = g[parent]
            g[name] = (qmul(pr, r), add(pt, qrot(pr, t)))
    return g


def ik_arm(side, target_world, pole_world, rot, pos):
    """Due ossa: mette il polso su target. Scrive in rot le rotazioni locali di braccio e avambraccio."""
    ua, la, ha = "UpperArm." + side, "LowerArm." + side, "Hand." + side
    g = fk(rot, pos)
    cr, cp = g["Chest"]
    inv = qinv(cr)
    S = sub(REST[ua], REST["Chest"])
    T = qrot(inv, sub(target_world, cp))
    Pl = qrot(inv, pole_world)
    a = length(sub(REST[la], REST[ua]))
    b = length(sub(REST[ha], REST[la]))
    dv = sub(T, S)
    c = min(max(length(dv), 0.05), a + b - 1e-4)
    u = norm(dv)
    cos_a = (a * a + c * c - b * b) / (2 * a * c)
    sin_a = math.sqrt(max(0.0, 1 - cos_a * cos_a))
    v = norm(sub(Pl, mul(u, dot(Pl, u))))
    E = add(S, mul(add(mul(u, cos_a), mul(v, sin_a)), a))
    H = add(S, mul(u, c))
    Ru = qfromto(sub(REST[la], REST[ua]), sub(E, S))
    fore = qrot(Ru, sub(REST[ha], REST[la]))
    Rf = qmul(qfromto(fore, sub(H, E)), Ru)
    rot[ua] = Ru
    rot[la] = qmul(qinv(Ru), Rf)


def point_arm(side, dir_world, rot, pos):
    """Braccio teso nella direzione data."""
    ua = "UpperArm." + side
    g = fk(rot, pos)
    cr = g["Chest"][0]
    rest_dir = sub(REST["Hand." + side], REST[ua])
    rot[ua] = qfromto(rest_dir, qrot(qinv(cr), dir_world))
    rot["LowerArm." + side] = QI


def set_global_rot(name, q_world, rot, pos):
    g = fk(rot, pos)
    pr = g[PARENT[name]][0]
    rot[name] = qmul(qinv(pr), q_world)


HIDDEN = (0.001, 0.001, 0.001)


def base_pose():
    """Fermo, arco in mano lungo il fianco (un po' inclinato in avanti), freccia nascosta."""
    rot = {
        "UpperArm.L": qe(z=4), "LowerArm.L": qe(x=-12), "Hand.L": QI,
        "UpperArm.R": qe(z=-4), "LowerArm.R": qe(x=-8),
        "Bow": qe(x=34, z=-8),
    }
    return {"rot": rot, "pos": {}, "scale": {"Arrow": HIDDEN}}


def merge(pose, rot=None, pos=None, scale=None):
    for k, v in (rot or {}).items():
        pose["rot"][k] = v
    for k, v in (pos or {}).items():
        pose["pos"][k] = v
    for k, v in (scale or {}).items():
        pose["scale"][k] = v
    return pose


def hips_at(dy=0.0, dz=0.0, dx=0.0):
    return add(rest_local("Hips"), (dx, dy, dz))


# ------------------------------------------------------------------ animazioni
def idle(t, T=2.4):
    ph = 2 * math.pi * t / T
    b = math.sin(ph)
    return merge(base_pose(),
                 rot={"Spine": qe(x=1.5 * b), "Chest": qe(x=1.5 * b), "Head": qe(x=-2 * b, y=4 * math.sin(ph * 0.5)),
                      "UpperArm.L": qe(z=4 + 1.5 * b), "UpperArm.R": qe(z=-4 - 1.5 * b),
                      "UpperLeg.L": qe(z=2), "UpperLeg.R": qe(z=-2)},
                 pos={"Hips": hips_at(dy=-0.006 * (1 - b))})


def gait(t, T, leg, knee, arm, lean, bob, fore_l, fore_r):
    ph = 2 * math.pi * t / T
    s, c = math.sin(ph), math.cos(ph)
    kl = knee * max(0.0, math.sin(ph + 1.2))       # il ginocchio si piega mentre la gamba torna avanti
    kr = knee * max(0.0, math.sin(ph + 1.2 + math.pi))
    return merge(base_pose(),
                 rot={"UpperLeg.L": qe(x=-leg * s), "LowerLeg.L": qe(x=kl + 4),
                      "UpperLeg.R": qe(x=leg * s), "LowerLeg.R": qe(x=kr + 4),
                      "Hips": qe(y=5 * s), "Spine": qe(x=lean * 0.5, y=-4 * s), "Chest": qe(x=lean * 0.5, y=-4 * s),
                      "Head": qe(x=-lean * 0.6, y=3 * s),
                      "UpperArm.R": qe(x=-arm * s, z=-6), "LowerArm.R": qe(x=fore_r),
                      "UpperArm.L": qe(x=arm * 0.5 * s, z=6), "LowerArm.L": qe(x=fore_l),
                      "Bow": qe(x=34 + 6 * s, z=-8)},
                 pos={"Hips": hips_at(dy=-bob * 0.5 + bob * abs(math.cos(ph)) - bob * 0.5)})


def walk(t): return gait(t, 1.0, 26, 40, 22, 4, 0.035, -18, -12)
def run(t): return gait(t, 0.64, 40, 60, 40, 14, 0.07, -40, -70)


def aim_pose(draw, nocked=True):
    """Posa di tiro: busto di fianco, braccio sinistro teso verso il bersaglio (+Z), corda tesa di `draw` (0-1)."""
    pose = base_pose()
    rot, pos = pose["rot"], pose["pos"]
    rot.update({"Hips": qe(y=-15), "Spine": qe(y=-30, x=-2), "Chest": qe(y=-30, x=-3),
                "UpperLeg.L": qe(x=-10, y=-10, z=8), "UpperLeg.R": qe(x=8, z=-8), "LowerLeg.L": qe(x=6),
                "Hand.L": QI, "Hand.R": QI})
    g = fk(rot, pos)
    rot["Head"] = qmul(qinv(g["Chest"][0]), qe(x=4, y=-8, z=-6))      # la testa guarda il bersaglio, inclinata sulla freccia
    sh = fk(rot, pos)["UpperArm.L"][1]
    grip_target = (sh[0] - 0.20, sh[1] + 0.06, sh[2] + 0.50)
    point_arm("L", sub(grip_target, sh), rot, pos)
    set_global_rot("Bow", qe(x=-3, z=12), rot, pos)                    # arco quasi verticale, un po' inclinato
    pos["BowString"] = (0.0, 0.0, -0.10 - 0.52 * draw)
    g = fk(rot, pos)
    target = add(g["BowString"][1], qrot(g["Bow"][0], (-0.03, -0.035, 0.0)))
    ik_arm("R", target, (0.2, 0.25, -1.0), rot, pos)
    rot["Hand.R"] = qe(z=-70)
    if nocked:
        pose["scale"]["Arrow"] = (1.0, 1.0, 1.0)
    return pose


def blend(a, b, t):
    out = {"rot": {}, "pos": {}, "scale": {}}
    for k in set(a["rot"]) | set(b["rot"]):
        out["rot"][k] = qslerp(a["rot"].get(k, QI), b["rot"].get(k, QI), t)
    for k in set(a["pos"]) | set(b["pos"]):
        out["pos"][k] = vlerp(a["pos"].get(k, rest_local(k)), b["pos"].get(k, rest_local(k)), t)
    out["scale"] = dict(b["scale"] if t > 0.5 else a["scale"])
    return out


def shoot(t):
    # 0-0,3 alza l'arco e incocca · 0,3-0,55 tende · 0,62 scocca · poi abbassa
    rest = idle(0.0)
    if t < 0.30:
        k = seg(t, 0.0, 0.30)
        p = blend(rest, aim_pose(0.12 * k), k)
        if t > 0.08:
            p["scale"]["Arrow"] = (1.0, 1.0, 1.0)
        return p
    if t < 0.62:
        return aim_pose(lerp(0.12, 1.0, seg(t, 0.30, 0.55)))
    if t < 0.70:                                   # la corda scatta in avanti e vibra
        k = (t - 0.62) / 0.08
        d = max(0.0, 1.0 - k * 1.3) - 0.06 * math.sin(k * math.pi * 3) * (1 - k)
        p = aim_pose(d, nocked=False)
        p["rot"]["Hand.R"] = qe(z=-70, x=-25 * k)     # la mano di tiro scivola indietro
        return p
    k = seg(t, 0.70, 1.20)
    return blend(aim_pose(0.0, nocked=False), rest, k)


def attack(t):
    # colpo con l'arco usato come bastone: carica a destra, fendente verso sinistra in avanti
    wind = seg(t, 0.0, 0.28) * (1 - seg(t, 0.28, 0.46))
    hitk = seg(t, 0.28, 0.46) * (1 - seg(t, 0.62, 0.9))
    def mix(a, b): return a * wind + b * hitk
    return merge(base_pose(),
                 rot={"Spine": qe(y=mix(28, -26), x=mix(-4, 10)), "Chest": qe(y=mix(22, -22), x=mix(-4, 8)),
                      "Head": qe(y=mix(-30, 30)),
                      "UpperArm.L": qe(x=mix(-40, -75), y=mix(10, -45), z=mix(85, 15)),
                      "LowerArm.L": qe(x=mix(-70, -15)),
                      "Bow": qe(x=34 + mix(30, 20), z=-8 - 80 * hitk),
                      "UpperArm.R": qe(x=mix(-20, 30), z=-12), "LowerArm.R": qe(x=-30),
                      "UpperLeg.L": qe(x=mix(6, -30)), "LowerLeg.L": qe(x=mix(4, 24)),
                      "UpperLeg.R": qe(x=mix(-4, 14)), "LowerLeg.R": qe(x=mix(8, 10))},
                 pos={"Hips": hips_at(dy=-0.04 * hitk, dz=0.08 * hitk)})


def hit(t):
    k = seg(t, 0.0, 0.10) * (1 - seg(t, 0.18, 0.6))
    return merge(base_pose(),
                 rot={"Spine": qe(x=-16 * k), "Chest": qe(x=-14 * k), "Head": qe(x=-22 * k, z=8 * k),
                      "UpperArm.L": qe(x=-25 * k, z=4 + 30 * k), "UpperArm.R": qe(x=-30 * k, z=-4 - 35 * k),
                      "LowerArm.R": qe(x=-8 - 40 * k), "UpperLeg.L": qe(x=-12 * k), "LowerLeg.L": qe(x=14 * k),
                      "UpperLeg.R": qe(x=10 * k), "LowerLeg.R": qe(x=10 * k)},
                 pos={"Hips": hips_at(dy=-0.03 * k, dz=-0.07 * k)})


def death(t):
    buckle = seg(t, 0.0, 0.35)
    fall = seg(t, 0.25, 0.95)
    settle = seg(t, 0.9, 1.15)
    land = fall * (1 - 0.35 * settle)
    return merge(base_pose(),
                 rot={"Root": qe(x=-88 * fall),
                      "UpperLeg.L": qe(x=-35 * buckle * (1 - 0.7 * fall), z=6 * fall),
                      "LowerLeg.L": qe(x=55 * buckle * (1 - 0.8 * fall)),
                      "UpperLeg.R": qe(x=-20 * buckle * (1 - 0.6 * fall), z=-10 * fall),
                      "LowerLeg.R": qe(x=40 * buckle * (1 - 0.7 * fall)),
                      "Spine": qe(x=-12 * buckle + 10 * fall), "Chest": qe(x=-8 * buckle + 6 * fall),
                      "Head": qe(x=-25 * buckle * (1 - fall) + 12 * fall, y=25 * fall),
                      "UpperArm.L": qe(x=-50 * buckle * (1 - fall) - 70 * land, z=4 + 40 * fall),
                      "UpperArm.R": qe(x=-60 * buckle * (1 - fall) - 60 * land, z=-4 - 55 * fall),
                      "LowerArm.L": qe(x=-12 - 20 * fall), "LowerArm.R": qe(x=-8 - 35 * fall),
                      "Bow": qe(x=34 + 50 * fall, z=-8 - 30 * fall)},
                 pos={"Hips": hips_at(dy=-0.16 * buckle * (1 - fall)),
                      "Root": (0.0, 0.13 * fall, -0.18 * fall)})


ANIMS = [  # nome (come nei pacchetti Quaternius), durata, ciclica
    ("Idle", idle, 2.4, True),
    ("Walk", walk, 1.0, True),
    ("Run", run, 0.64, True),
    ("Attack", attack, 0.9, False),
    ("Shoot", shoot, 1.2, False),
    ("HitRecieve", hit, 0.6, False),
    ("Death", death, 1.25, False),
]
FPS = 30


# ------------------------------------------------------------------ scrittura glTF
class Buf:
    def __init__(self):
        self.data = bytearray()
        self.views, self.accessors = [], []

    def add(self, fmt, rows, comp, typ, target=None, minmax=False):
        while len(self.data) % 4:
            self.data.append(0)
        off = len(self.data)
        for r in rows:
            self.data += struct.pack("<" + fmt, *(r if isinstance(r, (tuple, list)) else (r,)))
        view = {"buffer": 0, "byteOffset": off, "byteLength": len(self.data) - off}
        if target:
            view["target"] = target
        self.views.append(view)
        acc = {"bufferView": len(self.views) - 1, "componentType": comp, "count": len(rows), "type": typ}
        if minmax:
            cols = list(zip(*[(r if isinstance(r, (tuple, list)) else (r,)) for r in rows]))
            acc["min"] = [min(c) for c in cols]
            acc["max"] = [max(c) for c in cols]
        self.accessors.append(acc)
        return len(self.accessors) - 1


def write_png(path, w, h, pixels):
    raw = b"".join(b"\x00" + bytes(sum((list(pixels[y * w + x]) for x in range(w)), [])) for y in range(h))
    def chunk(t, d): return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xffffffff)
    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)) \
        + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b"")
    with open(path, "wb") as f:
        f.write(png)


def main():
    build_mesh()
    os.makedirs(OUT_DIR, exist_ok=True)
    write_png(os.path.join(OUT_DIR, NAME + "_Atlas.png"), 4, 4, PALETTE)
    buf = Buf()
    n = len(P)
    a_pos = buf.add("3f", P, 5126, "VEC3", 34962, minmax=True)
    a_nrm = buf.add("3f", N, 5126, "VEC3", 34962)
    a_uv = buf.add("2f", UV, 5126, "VEC2", 34962)
    a_j = buf.add("4H", J, 5123, "VEC4", 34962)
    a_w = buf.add("4f", W, 5126, "VEC4", 34962)
    a_idx = buf.add("H" if n < 65535 else "I", list(range(n)), 5123 if n < 65535 else 5125, "SCALAR", 34963)
    ibm = [(1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, -p[0], -p[1], -p[2], 1) for _, _, p in BONES]
    a_ibm = buf.add("16f", ibm, 5126, "MAT4")

    # nodi: 0 = Armature, 1.. = ossa, ultimo = mesh
    nodes = [{"name": "CharacterArmature", "children": [1, len(BONES) + 1]}]
    for name, parent, _ in BONES:
        node = {"name": name, "translation": list(rest_local(name))}
        kids = [i + 1 for i, b in enumerate(BONES) if b[1] == name]
        if kids:
            node["children"] = kids
        nodes.append(node)
    nodes.append({"name": NAME, "mesh": 0, "skin": 0})

    animations = []
    for aname, fn, dur, loop in ANIMS:
        frames = int(round(dur * FPS)) + 1
        times = [i / FPS for i in range(frames)]
        times[-1] = dur
        poses = [fn(0.0 if loop and i == frames - 1 and False else t) for i, t in enumerate(times)]
        if loop:
            poses[-1] = fn(0.0)
        a_t = buf.add("f", times, 5126, "SCALAR", minmax=True)
        samplers, channels = [], []
        for bi, (bname, _, _) in enumerate(BONES):
            qs, prev = [], None
            for p in poses:
                q = p["rot"].get(bname, QI)
                if prev is not None and sum(x * y for x, y in zip(prev, q)) < 0:
                    q = tuple(-x for x in q)
                qs.append(q)
                prev = q
            samplers.append({"input": a_t, "output": buf.add("4f", qs, 5126, "VEC4"), "interpolation": "LINEAR"})
            channels.append({"sampler": len(samplers) - 1, "target": {"node": bi + 1, "path": "rotation"}})
            if bname in ("Root", "Hips", "BowString"):
                ts = [p["pos"].get(bname, rest_local(bname)) for p in poses]
                samplers.append({"input": a_t, "output": buf.add("3f", ts, 5126, "VEC3"), "interpolation": "LINEAR"})
                channels.append({"sampler": len(samplers) - 1, "target": {"node": bi + 1, "path": "translation"}})
            if bname == "Arrow":
                ss = [p["scale"].get(bname, (1.0, 1.0, 1.0)) for p in poses]
                samplers.append({"input": a_t, "output": buf.add("3f", ss, 5126, "VEC3"), "interpolation": "STEP"})
                channels.append({"sampler": len(samplers) - 1, "target": {"node": bi + 1, "path": "scale"}})
        animations.append({"name": aname, "samplers": samplers, "channels": channels})

    gltf = {
        "asset": {"version": "2.0", "generator": "genera_arciere.py"},
        "scene": 0,
        "scenes": [{"name": "Scene", "nodes": [0]}],
        "nodes": nodes,
        "meshes": [{"name": NAME, "primitives": [{
            "attributes": {"POSITION": a_pos, "NORMAL": a_nrm, "TEXCOORD_0": a_uv, "JOINTS_0": a_j, "WEIGHTS_0": a_w},
            "indices": a_idx, "material": 0}]}],
        "skins": [{"name": "CharacterArmature", "joints": list(range(1, len(BONES) + 1)),
                   "inverseBindMatrices": a_ibm, "skeleton": 1}],
        "materials": [{"name": "Atlas", "pbrMetallicRoughness": {
            "baseColorTexture": {"index": 0}, "metallicFactor": 0.0, "roughnessFactor": 0.9}}],
        "textures": [{"sampler": 0, "source": 0}],
        "samplers": [{"magFilter": 9728, "minFilter": 9728}],
        "images": [{"uri": NAME + "_Atlas.png"}],
        "animations": animations,
        "accessors": buf.accessors,
        "bufferViews": buf.views,
        "buffers": [{"byteLength": len(buf.data),
                     "uri": "data:application/octet-stream;base64," + base64.b64encode(bytes(buf.data)).decode()}],
    }
    path = os.path.join(OUT_DIR, NAME + ".gltf")
    with open(path, "w") as f:
        json.dump(gltf, f, separators=(",", ":"))
    print("%s: %d vertici, %d triangoli, %d ossa, %d animazioni" % (path, n, n // 3, len(BONES), len(ANIMS)))


if __name__ == "__main__":
    main()
