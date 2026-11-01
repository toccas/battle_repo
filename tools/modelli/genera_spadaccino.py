#!/usr/bin/env python3
"""Spadaccino low-poly: elmo chiuso, cotta di maglia e sopravveste, scudo a scudetto e spada.

Uso (dalla cartella del progetto):
    python3 tools/modelli/genera_spadaccino.py
Crea data/unithMesh/Units/Swordsman.gltf e Swordsman_Atlas.png; poi si cuoce con tools/vat_baker.tscn.
Le parti in comune con gli altri soldati sono in lowpoly.py.
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lowpoly import Model, QI, add, sub, mul, norm, cross, qe, qmul, qinv, qrot, qfromto, qslerp, lerp, vlerp, seg  # noqa: E402

PALETTE = [
    (238, 190, 152),  # 0 pelle
    (156, 40, 40),    # 1 sopravveste
    (128, 132, 142),  # 2 maglia di ferro
    (196, 200, 208),  # 3 acciaio
    (118, 74, 38),    # 4 cuoio
    (62, 40, 24),     # 5 stivali
    (232, 226, 210),  # 6 bianco (scudo)
    (220, 182, 70),   # 7 oro
    (22, 20, 20),     # 8 feritoia
    (84, 56, 32),     # 9 legno scuro
    (96, 100, 110),   # 10 acciaio scuro
    (156, 40, 40),    # 11 scudo
    (255, 255, 255),  # 12-15 liberi
    (255, 255, 255),
    (255, 255, 255),
    (255, 255, 255),
]
SKIN, SURCOAT, MAIL, STEEL, LEATHER, BOOT, WHITE, GOLD, SLIT, DARKWOOD, DARKSTEEL, SHIELD = range(12)

BONES = [
    ("Root", None, (0.0, 0.0, 0.0)),
    ("Hips", "Root", (0.0, 0.95, 0.0)),
    ("Spine", "Hips", (0.0, 1.08, 0.0)),
    ("Chest", "Spine", (0.0, 1.25, 0.0)),
    ("Head", "Chest", (0.0, 1.50, 0.0)),
    ("UpperArm.L", "Chest", (0.26, 1.42, 0.0)),
    ("LowerArm.L", "UpperArm.L", (0.28, 1.14, 0.0)),
    ("Hand.L", "LowerArm.L", (0.29, 0.88, 0.0)),
    ("UpperArm.R", "Chest", (-0.26, 1.42, 0.0)),
    ("LowerArm.R", "UpperArm.R", (-0.28, 1.14, 0.0)),
    ("Hand.R", "LowerArm.R", (-0.29, 0.88, 0.0)),
    ("UpperLeg.L", "Hips", (0.10, 0.92, 0.0)),
    ("LowerLeg.L", "UpperLeg.L", (0.10, 0.50, 0.0)),
    ("UpperLeg.R", "Hips", (-0.10, 0.92, 0.0)),
    ("LowerLeg.R", "UpperLeg.R", (-0.10, 0.50, 0.0)),
    ("Sword", "Hand.R", (-0.29, 0.84, 0.0)),      # impugnatura; a riposo la lama punta avanti (+Z)
    ("Shield", "LowerArm.L", (0.31, 1.01, 0.0)),  # legato all'avambraccio, faccia verso +X
]
M = Model("Swordsman", BONES, PALETTE)
R = M.rest
FWD = (0.0, 0.0, 1.0)
BLADE = 0.80


# ------------------------------------------------------------------ geometria
def plate(poly, center, u, v, n, thick, color, bone):
    """Lastra dal contorno convesso poly (coordinate (a, b) sugli assi u, v), spessa thick lungo n."""
    front = [add(center, add(add(mul(u, a), mul(v, b)), mul(n, thick * 0.5))) for a, b in poly]
    back = [add(center, add(add(mul(u, a), mul(v, b)), mul(n, -thick * 0.5))) for a, b in poly]
    cf = add(center, mul(n, thick * 0.5))
    cb = add(center, mul(n, -thick * 0.5))
    k = len(poly)
    for i in range(k):
        j = (i + 1) % k
        M.tri(cf, front[i], front[j], color, bone)
        M.tri(cb, back[j], back[i], color, bone)
        M.quad(front[j], front[i], back[i], back[j], color, bone)


def fix_winding(poly, u, v, n):
    """Ordina il contorno in modo che le facce anteriori guardino lungo n."""
    a = sub(add(mul(u, poly[1][0]), mul(v, poly[1][1])), add(mul(u, poly[0][0]), mul(v, poly[0][1])))
    b = sub(add(mul(u, poly[2][0]), mul(v, poly[2][1])), add(mul(u, poly[0][0]), mul(v, poly[0][1])))
    c = cross(a, b)
    return poly if (c[0] * n[0] + c[1] * n[1] + c[2] * n[2]) > 0 else poly[::-1]


def build_mesh():
    box, limb, prism = M.box, M.limb, M.prism
    # gambe: calze di maglia, ginocchiere, stivali
    for s, up, lo in ((1, "UpperLeg.L", "LowerLeg.L"), (-1, "UpperLeg.R", "LowerLeg.R")):
        x = 0.10 * s
        box((x, 0.71, 0.0), (0.155, 0.44, 0.165), MAIL, up, taper=(1.1, 1.05))
        box((x, 0.31, 0.0), (0.135, 0.40, 0.145), MAIL, lo, taper=(1.12, 1.1))
        box((x, 0.50, 0.075), (0.11, 0.10, 0.05), STEEL, lo, taper=(0.8, 0.8))         # ginocchiera
        box((x, 0.13, 0.0), (0.14, 0.20, 0.155), BOOT, lo)
        box((x, 0.04, 0.05), (0.14, 0.08, 0.25), BOOT, lo, taper=(1.0, 0.85), shift=(0, -0.02))
    # usbergo di maglia
    box((0.0, 0.80, 0.0), (0.41, 0.32, 0.25), MAIL, "Hips", taper=(0.88, 0.92))
    box((0.0, 1.07, 0.0), (0.35, 0.21, 0.22), MAIL, "Spine", taper=(1.06, 1.0))
    box((0.0, 1.31, 0.0), (0.41, 0.32, 0.235), MAIL, "Chest", taper=(1.06, 0.95))
    # sopravveste senza maniche, aperta ai lati sotto la cintura
    box((0.0, 1.29, 0.0), (0.39, 0.34, 0.245), SURCOAT, "Chest", taper=(1.02, 0.96))
    box((0.0, 1.07, 0.0), (0.355, 0.20, 0.232), SURCOAT, "Spine", taper=(1.07, 1.0))
    for z in (0.122, -0.122):
        box((0.0, 0.74, z), (0.30, 0.38, 0.014), SURCOAT, "Hips", taper=(1.1, 1.0))
    box((0.0, 1.30, 0.124), (0.05, 0.24, 0.006), GOLD, "Chest")                         # croce
    box((0.0, 1.35, 0.124), (0.18, 0.05, 0.006), GOLD, "Chest")
    box((0.0, 0.95, 0.0), (0.39, 0.06, 0.255), LEATHER, "Hips")                         # cintura
    box((0.0, 0.95, 0.13), (0.07, 0.055, 0.012), GOLD, "Hips")
    limb((0.19, 0.92, 0.04), (0.24, 0.38, 0.12), 0.06, 0.03, LEATHER, "Hips")           # fodero al fianco sinistro
    limb((0.24, 0.38, 0.12), (0.245, 0.34, 0.125), 0.06, 0.03, STEEL, "Hips")
    # elmo chiuso: feritoia, prese d'aria, rinforzo a croce
    box((0.0, 1.54, 0.0), (0.12, 0.08, 0.12), MAIL, "Head")
    box((0.0, 1.67, 0.005), (0.265, 0.30, 0.27), STEEL, "Head", taper=(0.94, 0.94))
    box((0.0, 1.83, 0.005), (0.25, 0.03, 0.255), DARKSTEEL, "Head")                       # coppo piatto
    box((0.0, 1.705, 0.138), (0.22, 0.022, 0.012), SLIT, "Head")                           # feritoia
    box((0.0, 1.655, 0.140), (0.035, 0.30, 0.014), DARKSTEEL, "Head")                      # rinforzo verticale
    for s in (1, -1):
        for k in range(3):
            box((0.065 * s, 1.58 + 0.035 * k, 0.137), (0.012, 0.012, 0.012), SLIT, "Head")
    box((0.0, 1.58, 0.0), (0.30, 0.04, 0.29), DARKSTEEL, "Head")                           # bordo inferiore
    # braccia: maniche di maglia, spallacci, gomitiere, guanti
    for s, ua, la, ha in ((1, "UpperArm.L", "LowerArm.L", "Hand.L"), (-1, "UpperArm.R", "LowerArm.R", "Hand.R")):
        sh, el, wr = R[ua], R[la], R[ha]
        limb(add(sh, (0, 0.05, 0)), el, 0.13, 0.13, MAIL, ua, taper=0.9)
        limb(add(el, (0, 0.03, 0)), add(wr, (0, 0.04, 0)), 0.11, 0.11, MAIL, la, taper=0.9)
        box(add(sh, (0.02 * s, 0.02, 0)), (0.17, 0.10, 0.19), STEEL, ua, taper=(0.75, 0.85), shift=(-0.02 * s, 0))
        box(add(el, (0.0, 0.0, -0.01)), (0.12, 0.08, 0.12), STEEL, la)                      # gomitiera
        limb(add(wr, (0, 0.09, 0)), add(wr, (0, -0.01, 0)), 0.12, 0.12, LEATHER, la, taper=1.1)
        limb(wr, add(wr, (0.003 * s, -0.10, 0.0)), 0.09, 0.09, LEATHER, ha, taper=0.85)
    # spada: lama avanti dalla mano destra (a riposo)
    g = R["Sword"]
    limb(add(g, (0, 0, -0.10)), add(g, (0, 0, 0.06)), 0.035, 0.035, DARKWOOD, "Sword")      # impugnatura
    prism(add(g, (0, 0, -0.14)), add(g, (0, 0, -0.10)), 0.035, 0.035, 6, GOLD, "Sword")    # pomo
    limb(add(g, (-0.12, 0, 0.075)), add(g, (0.12, 0, 0.075)), 0.03, 0.03, GOLD, "Sword")   # guardia
    limb(add(g, (0, 0, 0.09)), add(g, (0, 0, 0.09 + BLADE - 0.12)), 0.055, 0.012, STEEL, "Sword", side_hint=(0, 1, 0))
    limb(add(g, (0, 0, 0.09 + BLADE - 0.12)), add(g, (0, 0, 0.09 + BLADE)), 0.055, 0.012, STEEL, "Sword", taper=0.05, side_hint=(0, 1, 0))
    limb(add(g, (0, 0, 0.09)), add(g, (0, 0, 0.09 + BLADE - 0.2)), 0.012, 0.016, DARKSTEEL, "Sword", side_hint=(0, 1, 0))  # sguscio
    # scudo a scudetto: lato piatto in alto, punta in basso; faccia verso +X a riposo
    c = R["Shield"]
    u, v, n = (0.0, 1.0, 0.0), (0.0, 0.0, 1.0), (1.0, 0.0, 0.0)
    shape = [(0.26, -0.25), (0.26, 0.25), (0.02, 0.25), (-0.18, 0.18), (-0.33, 0.07), (-0.38, 0.0), (-0.33, -0.07), (-0.18, -0.18), (0.02, -0.25)]
    shape = fix_winding(shape, u, v, n)
    plate([(a * 1.06, b * 1.06) for a, b in shape], add(c, (0.035, 0, 0)), u, v, n, 0.02, DARKSTEEL, "Shield")   # bordo
    plate(shape, add(c, (0.055, 0, 0)), u, v, n, 0.03, SHIELD, "Shield")
    # stemma: banda bianca a scaglione e borchia
    f = add(c, (0.072, 0, 0))
    limb(add(f, (0, 0.02, -0.22)), add(f, (0, -0.16, 0.0)), 0.006, 0.08, WHITE, "Shield", side_hint=(1, 0, 0))
    limb(add(f, (0, -0.16, 0.0)), add(f, (0, 0.02, 0.22)), 0.006, 0.08, WHITE, "Shield", side_hint=(1, 0, 0))
    box(add(f, (0.004, 0.14, 0.0)), (0.01, 0.07, 0.07), GOLD, "Shield")
    box(add(c, (-0.01, 0, 0)), (0.03, 0.10, 0.30), LEATHER, "Shield")                       # cinghie


# ------------------------------------------------------------------ pose
def pose_dict(rot=None, pos=None):
    return {"rot": dict(rot or {}), "pos": dict(pos or {}), "scale": {}}


def hips_at(dy=0.0, dz=0.0, dx=0.0):
    return add(M.rest_local("Hips"), (dx, dy, dz))


def sword_dir(p, d_world):
    M.set_global_rot("Sword", qfromto(FWD, d_world), p["rot"], p["pos"])


def shield_side(p):
    p["rot"].setdefault("UpperArm.L", qe(x=-8, z=10))
    p["rot"].setdefault("LowerArm.L", qe(x=-35))
    p["rot"].setdefault("Shield", qe(y=-30))


def shield_guard(p, k=1.0, high=0.0):
    """Scudo davanti al corpo: avambraccio di traverso, faccia verso il nemico."""
    rot, pos = p["rot"], p["pos"]
    chest_r, chest_p = M.fk(rot, pos)["Chest"]
    target = add(chest_p, qrot(chest_r, (0.04, -0.06 + high, 0.34)))
    M.ik_arm("L", target, qrot(chest_r, (1.0, -0.6, 0.0)), rot, pos)
    M.set_global_rot("Shield", qmul(qe(y=-90), qe(x=-6)), rot, pos)
    rot["Hand.L"] = qe(x=-20)
    if k < 1.0:
        base = pose_dict()
        shield_side(base)
        for b in ("UpperArm.L", "LowerArm.L", "Shield", "Hand.L"):
            rot[b] = qslerp(base["rot"].get(b, QI), rot[b], k)


def low_guard(p):
    """Spada in basso davanti a sé, punta in avanti e giù."""
    p["rot"].update({"UpperArm.R": qe(x=-22, z=-10), "LowerArm.R": qe(x=-38), "Hand.R": QI})
    sword_dir(p, norm((0.12, -0.55, 1.0)))


def idle_pose(t=0.0, T=2.6):
    b = math.sin(2 * math.pi * t / T)
    p = pose_dict({"Spine": qe(x=1.5 * b), "Chest": qe(x=1.2 * b), "Head": qe(x=-2 * b, y=4 * math.sin(math.pi * t / T)),
                   "UpperLeg.L": qe(z=3, x=-4), "UpperLeg.R": qe(z=-3, x=3)},
                  {"Hips": hips_at(dy=-0.006 * (1 - b))})
    shield_side(p)
    low_guard(p)
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
    p = gait_legs(ph, 25, 40, 3, 0.035)
    p["rot"].update({"UpperArm.L": qe(x=-8 + 8 * s, z=10)})
    shield_side(p)
    # spada appoggiata sulla spalla
    p["rot"].update({"UpperArm.R": qe(x=-25 - 5 * s, z=-12), "LowerArm.R": qe(x=-110), "Hand.R": QI})
    sword_dir(p, norm((-0.15, 0.75, -0.65)))
    return p


def run(t, T=0.64):
    """Carica: scudo avanti, spada alzata pronta a colpire."""
    ph = 2 * math.pi * t / T
    s = math.sin(ph)
    p = gait_legs(ph, 38, 62, 14, 0.06)
    shield_guard(p, high=0.03 * s)
    cr, cp = M.fk(p["rot"], p["pos"])["Chest"]
    hand = add(cp, qrot(cr, (-0.28, 0.30 + 0.03 * s, 0.02)))
    M.ik_arm("R", hand, qrot(cr, (-1.0, -0.4, -0.5)), p["rot"], p["pos"])
    p["rot"]["Hand.R"] = QI
    sword_dir(p, qrot(cr, norm((0.1, 0.8, -0.45))))
    return p


# fendente: (tempo, mano nel riferimento del petto, direzione della lama nel riferimento del petto, torsione)
SLASH = [
    (0.00, (-0.22, -0.20, 0.30), (0.10, 0.45, 1.0), 0.0),
    (0.30, (-0.30, 0.36, -0.06), (-0.25, 0.55, -0.80), 22.0),
    (0.42, (-0.12, 0.18, 0.38), (0.15, 0.40, 1.0), 4.0),
    (0.52, (0.06, -0.12, 0.42), (0.45, -0.60, 0.70), -24.0),
    (0.62, (0.14, -0.28, 0.30), (0.65, -0.72, 0.20), -28.0),
    (0.95, (-0.22, -0.20, 0.30), (0.10, 0.45, 1.0), 0.0),
]


def slash_at(t):
    for (t0, h0, d0, y0), (t1, h1, d1, y1) in zip(SLASH, SLASH[1:]):
        if t <= t1:
            k = seg(t, t0, t1)
            return vlerp(h0, h1, k), norm(vlerp(norm(d0), norm(d1), k)), lerp(y0, y1, k)
    return SLASH[-1][1], norm(SLASH[-1][2]), SLASH[-1][3]


def attack(t):
    hand_c, dir_c, yaw = slash_at(t)
    lunge = seg(t, 0.30, 0.50) * (1 - seg(t, 0.62, 0.95))
    p = pose_dict({"Hips": qe(y=-yaw * 0.3), "Spine": qe(x=4 + 8 * lunge, y=yaw * 0.5), "Chest": qe(x=3 + 6 * lunge, y=yaw * 0.5),
                   "Head": qe(y=-yaw * 0.6, x=-6),
                   "UpperLeg.L": qe(x=-20 - 14 * lunge, z=4), "LowerLeg.L": qe(x=18 + 12 * lunge),
                   "UpperLeg.R": qe(x=10 + 6 * lunge, z=-5), "LowerLeg.R": qe(x=14)},
                  {"Hips": hips_at(dy=-0.04 - 0.03 * lunge, dz=0.10 * lunge)})
    guard = seg(t, 0.0, 0.15) * (1 - seg(t, 0.75, 0.95))
    shield_guard(p, k=max(guard, 0.001))
    cr, cp = M.fk(p["rot"], p["pos"])["Chest"]
    rest = idle_pose()
    M.ik_arm("R", add(cp, qrot(cr, hand_c)), qrot(cr, (-1.0, -0.5, -0.3)), p["rot"], p["pos"])
    p["rot"]["Hand.R"] = QI
    sword_dir(p, qrot(cr, dir_c))
    # all'inizio e alla fine si torna dolcemente alla guardia bassa
    edge = 1 - seg(t, 0.0, 0.12) * (1 - seg(t, 0.82, 0.95))
    if edge > 0.0:
        p = M.blend(p, rest, edge)
    return p


def hit(t):
    k = seg(t, 0.0, 0.10) * (1 - seg(t, 0.2, 0.6))
    p = idle_pose()
    p["rot"].update({"Spine": qe(x=-14 * k), "Chest": qe(x=-12 * k), "Head": qe(x=-20 * k, z=8 * k),
                     "UpperLeg.L": qe(x=-12 * k, z=3), "LowerLeg.L": qe(x=14 * k), "UpperLeg.R": qe(x=10 * k, z=-3)})
    p["pos"]["Hips"] = hips_at(dy=-0.03 * k, dz=-0.08 * k)
    shield_guard(p, k=max(k, 0.001), high=0.10)
    p["rot"]["UpperArm.R"] = qe(x=-22 + 10 * k, z=-10 - 30 * k)
    p["rot"]["LowerArm.R"] = qe(x=-38 + 20 * k)
    sword_dir(p, norm((-0.5 * k + 0.12, -0.55 + 0.3 * k, 1.0)))
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
                   "Head": qe(x=-25 * buckle * (1 - fall) + 12 * fall, y=25 * fall),
                   "UpperArm.L": qe(x=-8 - 40 * buckle * (1 - fall) - 40 * fall, z=10 + 45 * fall),
                   "LowerArm.L": qe(x=-35 + 10 * fall), "Shield": qe(y=-30 + 10 * fall, z=25 * fall),
                   "UpperArm.R": qe(x=-22 * (1 - buckle) - 50 * buckle * (1 - fall) - 60 * fall, z=-10 - 55 * fall),
                   "LowerArm.R": qe(x=-38 * (1 - fall) - 10 * fall)},
                  {"Hips": hips_at(dy=-0.16 * buckle * (1 - fall)), "Root": (0.0, 0.14 * fall, -0.18 * fall)})
    sword_dir(p, norm((0.12, -0.55, 1.0)))
    p["rot"]["Sword"] = qmul(p["rot"]["Sword"], qe(y=50 * drop, x=40 * drop))   # la spada scivola di mano
    return p


ANIMS = [
    ("Idle", idle, 2.6, True),
    ("Walk", walk, 1.0, True),
    ("Run", run, 0.64, True),
    ("Attack", attack, 0.95, False),
    ("HitRecieve", hit, 0.6, False),
    ("Death", death, 1.25, False),
]

if __name__ == "__main__":
    build_mesh()
    M.write(ANIMS)
