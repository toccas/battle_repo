#!/usr/bin/env python3
"""Lanciere low-poly: elmo conico con nasale, giaco imbottito e sopravveste, scudo tondo e lancia.

Uso (dalla cartella del progetto):
    python3 tools/modelli/genera_lanciere.py
Crea data/unithMesh/Units/Spearman.gltf e Spearman_Atlas.png; poi si cuoce con tools/vat_baker.tscn.
Le parti in comune con gli altri soldati sono in lowpoly.py.
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lowpoly import Model, QI, add, qe, qmul, qrot, qfromto, qslerp, seg  # noqa: E402

PALETTE = [
    (238, 190, 152),  # 0 pelle
    (58, 86, 150),    # 1 sopravveste
    (206, 190, 150),  # 2 giaco imbottito
    (118, 74, 38),    # 3 cuoio
    (62, 40, 24),     # 4 stivali
    (88, 78, 70),     # 5 brache
    (150, 104, 58),   # 6 asta della lancia
    (190, 194, 202),  # 7 acciaio
    (118, 122, 132),  # 8 maglia di ferro
    (64, 92, 160),    # 9 scudo
    (222, 188, 72),   # 10 giallo (stemma)
    (28, 22, 20),     # 11 occhi
    (100, 64, 36),    # 12 barba
    (214, 176, 76),   # 13 fibbia
    (96, 64, 34),     # 14 legno scuro
    (255, 255, 255),  # 15 libero
]
SKIN, TABARD, GAMB, LEATHER, BOOT, PANTS, WOOD, STEEL, MAIL, SHIELD, YELLOW, EYE, BEARD, GOLD, DARKWOOD = range(15)

BONES = [
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
    ("Spear", "Hand.R", (-0.28, 0.84, 0.0)),     # impugnatura, a un terzo dell'asta
    ("Shield", "LowerArm.L", (0.30, 1.01, 0.0)),  # legato all'avambraccio
]
M = Model("Spearman", BONES, PALETTE)
R = M.rest

SPEAR_BACK, SPEAR_FRONT = 0.80, 1.86   # asta dietro e davanti alla mano (m)


def build_mesh():
    box, limb, prism = M.box, M.limb, M.prism
    # gambe: brache, fasce di cuoio, stivali
    for s, up, lo in ((1, "UpperLeg.L", "LowerLeg.L"), (-1, "UpperLeg.R", "LowerLeg.R")):
        x = 0.10 * s
        box((x, 0.71, 0.0), (0.15, 0.44, 0.16), PANTS, up, taper=(1.1, 1.05))
        box((x, 0.36, 0.0), (0.13, 0.30, 0.14), LEATHER, lo, taper=(1.1, 1.08))
        for y in (0.28, 0.38):
            box((x, y, 0.0), (0.142, 0.025, 0.152), PANTS, lo)                     # lacci
        box((x, 0.12, 0.0), (0.135, 0.22, 0.15), BOOT, lo)
        box((x, 0.04, 0.05), (0.135, 0.08, 0.24), BOOT, lo, taper=(1.0, 0.85), shift=(0, -0.02))
    # giaco imbottito lungo fino al ginocchio, sotto la sopravveste
    box((0.0, 0.79, 0.0), (0.42, 0.34, 0.25), GAMB, "Hips", taper=(0.86, 0.9))
    box((0.0, 1.07, 0.0), (0.35, 0.21, 0.22), GAMB, "Spine", taper=(1.06, 1.0))
    box((0.0, 1.31, 0.0), (0.40, 0.32, 0.23), GAMB, "Chest", taper=(1.05, 0.95))
    # sopravveste: pannelli davanti e dietro, con lo stemma
    for z, sgn in ((0.118, 1), (-0.118, -1)):
        box((0.0, 1.29, z), (0.30, 0.36, 0.012), TABARD, "Chest")
        box((0.0, 1.06, z * 1.0), (0.29, 0.20, 0.012), TABARD, "Spine")
        box((0.0, 0.76, z * 1.08), (0.27, 0.30, 0.012), TABARD, "Hips", taper=(1.12, 1.0))
    box((0.0, 1.30, 0.126), (0.05, 0.22, 0.008), YELLOW, "Chest")
    box((0.0, 1.34, 0.126), (0.17, 0.05, 0.008), YELLOW, "Chest")
    box((0.0, 0.95, 0.0), (0.38, 0.07, 0.25), LEATHER, "Hips")                     # cintura
    box((0.0, 0.95, 0.128), (0.07, 0.06, 0.012), GOLD, "Hips")
    box((-0.15, 0.86, 0.06), (0.05, 0.16, 0.05), LEATHER, "Hips")                  # fodero del coltello
    box((-0.15, 0.97, 0.06), (0.03, 0.06, 0.03), DARKWOOD, "Hips")
    # testa: viso, barba, cappuccio di maglia, elmo conico con nasale
    box((0.0, 1.535, 0.0), (0.09, 0.07, 0.09), SKIN, "Head")
    box((0.0, 1.655, 0.015), (0.23, 0.23, 0.23), SKIN, "Head", taper=(0.94, 0.94))
    for s in (1, -1):
        box((0.052 * s, 1.675, 0.131), (0.033, 0.035, 0.01), EYE, "Head")
    box((0.0, 1.575, 0.115), (0.19, 0.08, 0.05), BEARD, "Head", taper=(1.1, 1.0))
    box((0.0, 1.615, 0.135), (0.11, 0.03, 0.02), BEARD, "Head")                     # baffi
    box((0.0, 1.62, -0.035), (0.29, 0.20, 0.25), MAIL, "Head", taper=(1.0, 1.0))   # maglia su collo e nuca
    box((0.0, 1.47, -0.01), (0.34, 0.06, 0.28), MAIL, "Chest", taper=(0.9, 0.9))   # bavero di maglia
    prism((0.0, 1.725, 0.012), (0.0, 1.775, 0.012), 0.150, 0.150, 8, STEEL, "Head", phase=math.pi / 8)
    prism((0.0, 1.775, 0.012), (0.0, 1.97, 0.0), 0.150, 0.012, 8, STEEL, "Head", phase=math.pi / 8)
    box((0.0, 1.69, 0.152), (0.03, 0.12, 0.02), STEEL, "Head")                       # nasale
    # braccia: maniche imbottite, guanti di cuoio, mani
    for s, ua, la, ha in ((1, "UpperArm.L", "LowerArm.L", "Hand.L"), (-1, "UpperArm.R", "LowerArm.R", "Hand.R")):
        sh, el, wr = R[ua], R[la], R[ha]
        limb(add(sh, (0, 0.05, 0)), el, 0.13, 0.13, GAMB, ua, taper=0.9)
        limb(add(el, (0, 0.03, 0)), add(wr, (0, 0.06, 0)), 0.11, 0.11, GAMB, la, taper=0.85)
        limb(add(wr, (0, 0.08, 0)), wr, 0.105, 0.105, LEATHER, la)
        limb(wr, add(wr, (0.003 * s, -0.10, 0.0)), 0.09, 0.09, LEATHER, ha, taper=0.85)
    # lancia: verticale nella mano destra (a riposo)
    g = R["Spear"]
    butt, top = add(g, (0, -SPEAR_BACK, 0)), add(g, (0, SPEAR_FRONT, 0))
    prism(butt, top, 0.02, 0.018, 6, WOOD, "Spear")
    prism(add(butt, (0, -0.02, 0)), add(butt, (0, 0.05, 0)), 0.024, 0.024, 6, STEEL, "Spear")   # puntale
    prism(add(top, (0, -0.06, 0)), add(top, (0, 0.03, 0)), 0.026, 0.022, 6, STEEL, "Spear")    # gorbia
    limb(add(top, (0, 0.03, 0)), add(top, (0, 0.10, 0)), 0.035, 0.016, STEEL, "Spear", taper=2.1, side_hint=(0, 0, 1))
    limb(add(top, (0, 0.10, 0)), add(top, (0, 0.30, 0)), 0.074, 0.016, STEEL, "Spear", taper=0.04, side_hint=(0, 0, 1))
    # scudo tondo sull'avambraccio sinistro, faccia verso l'esterno (+X) a riposo
    c = R["Shield"]
    face0, face1 = add(c, (0.03, 0, 0)), add(c, (0.06, 0, 0))
    prism(add(c, (0.025, 0, 0)), add(c, (0.045, 0, 0)), 0.355, 0.355, 12, DARKWOOD, "Shield", phase=math.pi / 12)  # bordo
    prism(face0, face1, 0.34, 0.33, 12, SHIELD, "Shield", phase=math.pi / 12)
    prism(face1, add(face1, (0.06, 0, 0)), 0.08, 0.03, 8, STEEL, "Shield")                                         # umbone
    box(add(face1, (0.002, 0, 0)), (0.008, 0.58, 0.08), YELLOW, "Shield")
    box(add(face1, (0.002, 0, 0)), (0.008, 0.08, 0.58), YELLOW, "Shield")
    box(add(c, (-0.005, 0, 0)), (0.03, 0.10, 0.30), LEATHER, "Shield")                                             # cinghie


# ------------------------------------------------------------------ pose
def pose_dict(rot=None, pos=None):
    return {"rot": dict(rot or {}), "pos": dict(pos or {}), "scale": {}}


def hips_at(dy=0.0, dz=0.0, dx=0.0):
    return add(M.rest_local("Hips"), (dx, dy, dz))


UP = (0.0, 1.0, 0.0)


def spear_dir(d):
    """Rotazione globale che punta la lancia (asse Y a riposo) nella direzione d."""
    return qfromto(UP, d)


def carry_spear(p, tilt=4.0, sway=0.0):
    """Lancia dritta nella destra, puntale vicino al piede."""
    M.set_global_rot("Spear", qe(x=tilt, z=sway), p["rot"], p["pos"])


def shield_side(p):
    """Scudo appeso al braccio, lungo il fianco."""
    p["rot"].setdefault("UpperArm.L", qe(z=8))
    p["rot"].setdefault("LowerArm.L", qe(x=-14))


def shield_guard(p, k=1.0, high=0.0):
    """Scudo davanti al corpo: avambraccio di traverso, faccia verso il nemico."""
    rot, pos = p["rot"], p["pos"]
    g = M.fk(rot, pos)
    chest_r, chest_p = g["Chest"]
    target = add(chest_p, qrot(chest_r, (0.02, -0.08 + high, 0.33)))
    M.ik_arm("L", target, add(qrot(chest_r, (1.0, -0.6, 0.0)), (0, 0, 0)), rot, pos)
    M.set_global_rot("Shield", qmul(qe(y=-90), qe(x=0)), rot, pos)
    rot["Hand.L"] = qe(x=-20)
    if k < 1.0:
        base = pose_dict()
        shield_side(base)
        for b in ("UpperArm.L", "LowerArm.L", "Shield", "Hand.L"):
            rot[b] = qslerp(base["rot"].get(b, QI), rot[b], k)


def idle_pose(t=0.0, T=2.6):
    b = math.sin(2 * math.pi * t / T)
    p = pose_dict({"Spine": qe(x=1.5 * b), "Chest": qe(x=1.2 * b), "Head": qe(x=-2 * b, y=3 * math.sin(math.pi * t / T)),
                   "UpperArm.R": qe(x=-6, z=-10), "LowerArm.R": qe(x=-32), "Hand.R": qe(x=10),
                   "UpperLeg.L": qe(z=3), "UpperLeg.R": qe(z=-3)},
                  {"Hips": hips_at(dy=-0.006 * (1 - b))})
    shield_side(p)
    carry_spear(p)
    return p


def idle(t): return idle_pose(t)


def gait_legs(ph, leg, knee, lean, bob):
    s = math.sin(ph)
    kl = knee * max(0.0, math.sin(ph + 1.2))
    kr = knee * max(0.0, math.sin(ph + 1.2 + math.pi))
    return pose_dict({"UpperLeg.L": qe(x=-leg * s), "LowerLeg.L": qe(x=kl + 4),
                      "UpperLeg.R": qe(x=leg * s), "LowerLeg.R": qe(x=kr + 4),
                      "Hips": qe(y=5 * s), "Spine": qe(x=lean * 0.5, y=-4 * s), "Chest": qe(x=lean * 0.5, y=-4 * s),
                      "Head": qe(x=-lean * 0.7, y=3 * s)},
                     {"Hips": hips_at(dy=bob * abs(math.cos(ph)) - bob)})


def walk(t, T=1.0):
    ph = 2 * math.pi * t / T
    s = math.sin(ph)
    p = gait_legs(ph, 26, 40, 3, 0.035)
    p["rot"].update({"UpperArm.R": qe(x=-6 - 6 * s, z=-10), "LowerArm.R": qe(x=-32), "Hand.R": qe(x=10),
                     "UpperArm.L": qe(x=10 * s, z=8), "LowerArm.L": qe(x=-14)})
    carry_spear(p, tilt=6 + 3 * s, sway=2 * s)
    return p


def run(t, T=0.64):
    """Carica: scudo avanti e lancia abbassata all'altezza del fianco."""
    ph = 2 * math.pi * t / T
    s = math.sin(ph)
    p = gait_legs(ph, 38, 62, 14, 0.06)
    shield_guard(p, high=0.04 * s)
    g = M.fk(p["rot"], p["pos"])
    hip = g["Hips"][1]
    M.ik_arm("R", add(hip, (-0.24, 0.10 + 0.03 * s, 0.10)), (-0.6, -0.3, -1.0), p["rot"], p["pos"])
    p["rot"]["Hand.R"] = QI
    M.set_global_rot("Spear", spear_dir((0.03, 0.10 + 0.02 * s, 1.0)), p["rot"], p["pos"])
    return p


def guard_pose(thrust=0.0, crouch=1.0):
    """In guardia dietro lo scudo, lancia alzata sopra la spalla (affondo dall'alto)."""
    p = pose_dict({"Hips": qe(y=-8 * crouch), "Spine": qe(x=6 * crouch + 6 * thrust, y=4 * crouch - 10 * thrust),
                   "Chest": qe(x=4 * crouch + 4 * thrust, y=4 * crouch - 8 * thrust),
                   "Head": qe(x=-8 * crouch, y=6 * thrust),
                   "UpperLeg.L": qe(x=-24 * crouch - 6 * thrust, z=4), "LowerLeg.L": qe(x=22 * crouch),
                   "UpperLeg.R": qe(x=10 * crouch, z=-6), "LowerLeg.R": qe(x=18 * crouch)},
                  {"Hips": hips_at(dy=-0.05 * crouch, dz=0.04 * thrust)})
    shield_guard(p)
    g = M.fk(p["rot"], p["pos"])
    cr, cp = g["Chest"]
    hand = add(cp, qrot(cr, (-0.22 + 0.06 * thrust, 0.38 - 0.06 * thrust, -0.10 + 0.55 * thrust)))
    M.ik_arm("R", hand, (-1.0, -0.2, -0.6), p["rot"], p["pos"])
    p["rot"]["Hand.R"] = qe(x=-30)
    M.set_global_rot("Spear", spear_dir((0.04, -0.13 - 0.05 * thrust, 1.0)), p["rot"], p["pos"])
    return p


def attack(t):
    # 0-0,18 alza la lancia · 0,18-0,3 carica il colpo · 0,3-0,42 affondo · ritorna · 0,62-0,9 riposo
    if t < 0.18:
        return M.blend(idle_pose(), guard_pose(0.0), seg(t, 0.0, 0.18))
    if t < 0.62:
        th = -0.25 * seg(t, 0.18, 0.30) + 1.25 * seg(t, 0.30, 0.42) - 1.0 * seg(t, 0.46, 0.62)
        return guard_pose(th)
    return M.blend(guard_pose(0.0), idle_pose(), seg(t, 0.62, 0.9))


def hit(t):
    k = seg(t, 0.0, 0.10) * (1 - seg(t, 0.2, 0.6))
    p = idle_pose()
    p["rot"].update({"Spine": qe(x=-14 * k), "Chest": qe(x=-12 * k), "Head": qe(x=-20 * k, z=-8 * k),
                     "UpperLeg.L": qe(x=-12 * k, z=3), "LowerLeg.L": qe(x=14 * k), "UpperLeg.R": qe(x=10 * k, z=-3),
                     "UpperArm.R": qe(x=-6 - 20 * k, z=-10 - 25 * k)})
    p["pos"]["Hips"] = hips_at(dy=-0.03 * k, dz=-0.08 * k)
    shield_guard(p, k=k, high=0.08)
    carry_spear(p, tilt=4 - 18 * k, sway=-10 * k)
    return p


def death(t):
    buckle = seg(t, 0.0, 0.32)
    fall = seg(t, 0.22, 0.95)
    drop = seg(t, 0.15, 0.85)
    p = pose_dict({"Root": qe(x=-88 * fall),
                   "UpperLeg.L": qe(x=-35 * buckle * (1 - 0.7 * fall), z=6 * fall),
                   "LowerLeg.L": qe(x=55 * buckle * (1 - 0.8 * fall)),
                   "UpperLeg.R": qe(x=-20 * buckle * (1 - 0.6 * fall), z=-10 * fall),
                   "LowerLeg.R": qe(x=40 * buckle * (1 - 0.7 * fall)),
                   "Spine": qe(x=-12 * buckle + 10 * fall), "Chest": qe(x=-8 * buckle + 6 * fall),
                   "Head": qe(x=-25 * buckle * (1 - fall) + 12 * fall, y=-25 * fall),
                   "UpperArm.L": qe(x=-40 * buckle * (1 - fall) - 50 * fall, z=8 + 45 * fall),
                   "LowerArm.L": qe(x=-14 - 30 * fall), "Shield": qe(z=20 * fall, y=-30 * fall),
                   "LowerArm.R": qe(x=-32 * (1 - fall) - 10 * fall), "UpperArm.R": qe(x=-6 * (1 - buckle) - 50 * buckle * (1 - fall) - 70 * fall, z=-10 - 50 * fall),
                   "Hand.R": qe(x=10)},
                  {"Hips": hips_at(dy=-0.16 * buckle * (1 - fall)), "Root": (0.0, 0.14 * fall, -0.18 * fall)})
    carry_spear(p, tilt=4 * (1 - drop))
    p["rot"]["Spear"] = qmul(p["rot"]["Spear"], qe(x=-55 * drop, z=-35 * drop))   # la lancia cade
    return p


ANIMS = [  # nomi come nei pacchetti Quaternius: il baker li riconosce da solo
    ("Idle", idle, 2.6, True),
    ("Walk", walk, 1.0, True),
    ("Run", run, 0.64, True),
    ("Attack", attack, 0.9, False),
    ("HitRecieve", hit, 0.6, False),
    ("Death", death, 1.25, False),
]

if __name__ == "__main__":
    build_mesh()
    M.write(ANIMS)
