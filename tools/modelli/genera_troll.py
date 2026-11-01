#!/usr/bin/env python3
"""Troll low-poly: gobbo, braccia lunghe, zanne, perizoma e una clava ricavata da un tronco.

Uso (dalla cartella del progetto):
    python3 tools/modelli/genera_troll.py
Crea data/unithMesh/Units/Troll.gltf e Troll_Atlas.png; poi si cuoce con tools/vat_baker.tscn
(viene portato all'altezza dell'unità, 4,2 m).
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lowpoly import Model, QI, add, sub, mul, norm, qe, qmul, qrot, qfromto, qslerp, lerp, vlerp, seg  # noqa: E402

PALETTE = [
    (112, 142, 96),   # 0 pelle
    (84, 110, 72),    # 1 pelle scura (macchie, nocche)
    (232, 220, 186),  # 2 zanne e unghie
    (110, 70, 40),    # 3 perizoma
    (196, 170, 118),  # 4 corda
    (104, 76, 50),    # 5 corteccia
    (150, 112, 70),   # 6 legno chiaro
    (180, 40, 30),    # 7 occhi
    (40, 34, 28),     # 8 capelli
    (130, 134, 140),  # 9 ferro (chiodi della clava)
    (156, 120, 100),  # 10 bocca
    (255, 255, 255), (255, 255, 255), (255, 255, 255), (255, 255, 255), (255, 255, 255),
]
SKIN, SKIN2, IVORY, CLOTH, ROPE, BARK, WOODL, EYE, HAIR, IRON, MOUTH = range(11)

BONES = [
    ("Root", None, (0.0, 0.0, 0.0)),
    ("Hips", "Root", (0.0, 1.00, 0.0)),
    ("Spine", "Hips", (0.0, 1.28, 0.02)),
    ("Chest", "Spine", (0.0, 1.62, 0.06)),
    ("Head", "Chest", (0.0, 2.08, 0.30)),
    ("UpperArm.L", "Chest", (0.52, 1.98, 0.10)),
    ("LowerArm.L", "UpperArm.L", (0.62, 1.44, 0.14)),
    ("Hand.L", "LowerArm.L", (0.66, 0.94, 0.18)),
    ("UpperArm.R", "Chest", (-0.52, 1.98, 0.10)),
    ("LowerArm.R", "UpperArm.R", (-0.62, 1.44, 0.14)),
    ("Hand.R", "LowerArm.R", (-0.66, 0.94, 0.18)),
    ("UpperLeg.L", "Hips", (0.22, 0.98, 0.0)),
    ("LowerLeg.L", "UpperLeg.L", (0.25, 0.52, 0.04)),
    ("UpperLeg.R", "Hips", (-0.22, 0.98, 0.0)),
    ("LowerLeg.R", "UpperLeg.R", (-0.25, 0.52, 0.04)),
    ("Weapon.Club", "Hand.R", (-0.66, 0.84, 0.18)),   # a riposo la clava punta avanti (+Z)
]
M = Model("Troll", BONES, PALETTE)
R = M.rest
FWD = (0.0, 0.0, 1.0)
CLUB = 1.45


def build_mesh():
    box, limb, prism = M.box, M.limb, M.prism
    # gambe corte e grosse, piedi larghi a tre dita
    for s, up, lo in ((1, "UpperLeg.L", "LowerLeg.L"), (-1, "UpperLeg.R", "LowerLeg.R")):
        hip, knee = R[up], R[lo]
        limb(add(hip, (0, 0.06, 0)), knee, 0.34, 0.36, SKIN, up, taper=0.85)
        limb(knee, (knee[0] + 0.01 * s, 0.12, 0.06), 0.28, 0.30, SKIN, lo, taper=0.85)
        box((knee[0] + 0.01 * s, 0.07, 0.13), (0.30, 0.14, 0.40), SKIN2, lo, taper=(0.95, 0.8))
        for k in (-1, 0, 1):
            box((knee[0] + 0.09 * k + 0.01 * s, 0.05, 0.35), (0.07, 0.07, 0.06), IVORY, lo)
        box((knee[0], 0.52, 0.17), (0.18, 0.14, 0.06), SKIN2, lo)                      # ginocchio nodoso
    # perizoma e corda
    box((0.0, 0.94, 0.0), (0.74, 0.30, 0.56), CLOTH, "Hips", taper=(1.05, 1.05))
    box((0.0, 0.70, 0.26), (0.36, 0.34, 0.03), CLOTH, "Hips", taper=(1.2, 1.0))
    box((0.0, 0.70, -0.26), (0.40, 0.30, 0.03), CLOTH, "Hips", taper=(1.2, 1.0))
    box((0.0, 1.07, 0.0), (0.78, 0.06, 0.60), ROPE, "Hips")
    box((0.30, 0.96, 0.24), (0.10, 0.14, 0.08), IVORY, "Hips")                           # osso appeso
    # pancione, torace largo e gobba
    box((0.0, 1.32, 0.06), (0.86, 0.50, 0.72), SKIN, "Spine", taper=(1.05, 0.95))
    box((0.0, 1.32, 0.40), (0.50, 0.36, 0.06), SKIN2, "Spine")                           # pancia
    box((0.0, 1.78, 0.06), (1.06, 0.48, 0.70), SKIN, "Chest", taper=(1.0, 0.85), shift=(0, 0.06))
    box((0.0, 1.95, -0.22), (0.62, 0.34, 0.36), SKIN, "Chest", taper=(0.7, 0.7))          # gobba
    for x, y, z in ((0.22, 2.02, -0.30), (-0.12, 2.06, -0.28), (0.02, 1.90, -0.40), (-0.28, 1.86, -0.25)):
        box((x, y, z), (0.08, 0.06, 0.06), SKIN2, "Chest")                                 # escrescenze
    box((0.0, 1.70, 0.40), (0.60, 0.26, 0.04), SKIN2, "Chest", taper=(1.1, 1.0))          # pettorali
    # testa bassa e avanti: mascella, zanne, naso, orecchie
    h = R["Head"]
    limb(add(h, (0, -0.12, -0.18)), add(h, (0, 0.0, 0.0)), 0.30, 0.28, SKIN, "Head")      # collo
    box(add(h, (0, 0.12, 0.08)), (0.40, 0.30, 0.38), SKIN, "Head", taper=(0.85, 0.85))
    box(add(h, (0, -0.06, 0.16)), (0.44, 0.16, 0.36), SKIN2, "Head", taper=(1.0, 1.0))     # mascella
    box(add(h, (0, 0.21, 0.27)), (0.36, 0.06, 0.06), SKIN2, "Head")                        # arcata
    for s in (1, -1):
        box(add(h, (0.09 * s, 0.17, 0.27)), (0.05, 0.035, 0.02), EYE, "Head")
        limb(add(h, (0.15 * s, -0.02, 0.30)), add(h, (0.17 * s, 0.12, 0.34)), 0.05, 0.05, IVORY, "Head", taper=0.2)   # zanne
        limb(add(h, (0.20 * s, 0.16, 0.04)), add(h, (0.38 * s, 0.26, -0.04)), 0.05, 0.14, SKIN, "Head", taper=0.2)    # orecchie
    box(add(h, (0, 0.10, 0.31)), (0.12, 0.14, 0.10), SKIN2, "Head", taper=(0.7, 0.5))     # naso
    box(add(h, (0, 0.00, 0.34)), (0.24, 0.04, 0.02), MOUTH, "Head")
    box(add(h, (0, 0.30, -0.02)), (0.16, 0.08, 0.22), HAIR, "Head")                        # ciuffo
    # braccia lunghissime, avambracci grossi, manone
    for s, ua, la, ha in ((1, "UpperArm.L", "LowerArm.L", "Hand.L"), (-1, "UpperArm.R", "LowerArm.R", "Hand.R")):
        sh, el, wr = R[ua], R[la], R[ha]
        box(add(sh, (0.0, 0.06, 0)), (0.42, 0.30, 0.42), SKIN, ua, taper=(0.8, 0.8))        # spalla
        limb(sh, el, 0.26, 0.28, SKIN, ua, taper=0.85)
        limb(el, wr, 0.30, 0.30, SKIN, la, taper=0.9)
        box(add(el, (0, -0.15, -0.12)), (0.12, 0.20, 0.06), SKIN2, la)
        limb(add(wr, (0, 0.02, 0)), add(wr, (0.01 * s, -0.22, 0.02)), 0.26, 0.20, SKIN2, ha, taper=0.9)
        for k in (-1, 0, 1):
            limb(add(wr, (0.07 * k, -0.20, 0.06)), add(wr, (0.07 * k, -0.30, 0.10)), 0.06, 0.06, SKIN2, ha)
            box(add(wr, (0.07 * k, -0.31, 0.11)), (0.05, 0.03, 0.04), IVORY, ha)
    # clava: tronco nodoso con chiodi, più grosso in punta
    g = R["Weapon.Club"]
    prism(add(g, (0, 0, -0.18)), add(g, (0, 0, 0.35)), 0.07, 0.085, 6, BARK, "Weapon.Club")
    prism(add(g, (0, 0, 0.35)), add(g, (0, 0, CLUB - 0.15)), 0.085, 0.19, 7, BARK, "Weapon.Club", phase=0.3)
    prism(add(g, (0, 0, CLUB - 0.15)), add(g, (0, 0, CLUB)), 0.19, 0.12, 7, WOODL, "Weapon.Club", phase=0.3)
    for k, (dx, dy, z) in enumerate(((0.17, 0.05, 0.95), (-0.16, 0.08, 1.05), (0.02, 0.19, 1.15), (0.05, -0.18, 1.0), (-0.10, -0.14, 1.2))):
        c = add(g, (dx, dy, z))
        limb(c, add(c, mul(norm((dx, dy, 0.0)), 0.10)), 0.035, 0.035, IRON, "Weapon.Club", taper=0.1)
    prism(add(g, (0.09, 0.0, 0.6)), add(g, (0.20, 0.06, 0.66)), 0.04, 0.02, 5, BARK, "Weapon.Club")   # moncone di ramo


# ------------------------------------------------------------------ pose
def pose_dict(rot=None, pos=None):
    return {"rot": dict(rot or {}), "pos": dict(pos or {}), "scale": {}}


def hips_at(dy=0.0, dz=0.0, dx=0.0):
    return add(M.rest_local("Hips"), (dx, dy, dz))


def club_dir(p, d):
    M.set_global_rot("Weapon.Club", qfromto(FWD, norm(d)), p["rot"], p["pos"])


def idle_pose(t=0.0, T=3.0):
    b = math.sin(2 * math.pi * t / T)
    p = pose_dict({"Spine": qe(x=6 + 3 * b), "Chest": qe(x=8 + 3 * b), "Head": qe(x=-12 - 3 * b, y=14 * math.sin(math.pi * t / T)),
                   "UpperArm.L": qe(x=-8 + 3 * b, z=12), "LowerArm.L": qe(x=-20),
                   "UpperArm.R": qe(x=-10, z=-10), "LowerArm.R": qe(x=-22),
                   "UpperLeg.L": qe(x=-10, z=6), "LowerLeg.L": qe(x=14), "UpperLeg.R": qe(x=-6, z=-6), "LowerLeg.R": qe(x=12)},
                  {"Hips": hips_at(dy=-0.05 - 0.02 * (1 - b))})
    club_dir(p, (-0.15, -0.9, 0.45))   # la clava poggia a terra davanti al piede destro
    return p


def idle(t): return idle_pose(t)


def gait(t, T, leg, knee, lean, bob, roll, arm, club):
    ph = 2 * math.pi * t / T
    s = math.sin(ph)
    kl = knee * max(0.0, math.sin(ph + 1.2))
    kr = knee * max(0.0, math.sin(ph + 1.2 + math.pi))
    p = pose_dict({"UpperLeg.L": qe(x=-leg * s - 8, z=6), "LowerLeg.L": qe(x=kl + 12),
                   "UpperLeg.R": qe(x=leg * s - 8, z=-6), "LowerLeg.R": qe(x=kr + 12),
                   "Hips": qe(y=8 * s, z=roll * s), "Spine": qe(x=lean * 0.5 + 6, z=-roll * 0.6 * s),
                   "Chest": qe(x=lean * 0.5 + 8, y=-8 * s), "Head": qe(x=-lean * 0.8 - 12, y=6 * s),
                   "UpperArm.L": qe(x=arm * s, z=14), "LowerArm.L": qe(x=-25 - 10 * max(0.0, s)),
                   "UpperArm.R": qe(x=-arm * 0.6 * s + club[0], z=-12), "LowerArm.R": qe(x=club[1])},
                  {"Hips": hips_at(dy=bob * abs(math.cos(ph)) - bob - 0.05)})
    club_dir(p, club[2])
    return p


def walk(t): return gait(t, 1.4, 22, 34, 6, 0.06, 5, 22, (-6, -24, (-0.2, -0.75, 0.6)))
def run(t): return gait(t, 0.9, 32, 55, 18, 0.10, 6, 30, (-40, -70, (-0.25, 0.75, -0.6)))


def attack(t):
    # carica il colpo sopra la testa, schianta la clava a terra davanti a sé, poi si rialza
    wind = seg(t, 0.0, 0.45) * (1 - seg(t, 0.45, 0.62))
    smash = seg(t, 0.45, 0.62) * (1 - seg(t, 0.85, 1.3))
    p = pose_dict({"Spine": qe(x=6 - 14 * wind + 22 * smash, y=18 * wind - 10 * smash),
                   "Chest": qe(x=8 - 12 * wind + 18 * smash, y=14 * wind - 8 * smash),
                   "Head": qe(x=-12 + 10 * wind - 10 * smash),
                   "UpperArm.R": qe(x=-10 - 170 * wind - 70 * smash, z=-10 - 10 * wind),
                   "LowerArm.R": qe(x=-22 - 40 * wind - 5 * smash),
                   "UpperArm.L": qe(x=-8 - 60 * wind - 30 * smash, z=12 + 25 * wind),
                   "LowerArm.L": qe(x=-20 - 30 * wind),
                   "UpperLeg.L": qe(x=-10 - 30 * smash, z=6), "LowerLeg.L": qe(x=14 + 25 * smash),
                   "UpperLeg.R": qe(x=-6 + 16 * smash, z=-6), "LowerLeg.R": qe(x=12 + 10 * smash)},
                  {"Hips": hips_at(dy=-0.05 + 0.04 * wind - 0.12 * smash, dz=0.18 * smash)})
    p0 = idle_pose()
    d_rest = (-0.15, -0.9, 0.45)
    d_wind = (-0.1, 0.35, -0.95)
    d_smash = (-0.05, -0.75, 0.65)
    if t < 0.45:
        d = vlerp(d_rest, d_wind, seg(t, 0.0, 0.45))
    elif t < 0.62:
        d = vlerp(d_wind, d_smash, seg(t, 0.45, 0.62))
    else:
        d = vlerp(d_smash, d_rest, seg(t, 0.85, 1.3))
    club_dir(p, d)
    edge = 1 - seg(t, 0.0, 0.1) * (1 - seg(t, 1.15, 1.3))
    return M.blend(p, p0, edge) if edge > 0 else p


def hit(t):
    k = seg(t, 0.0, 0.12) * (1 - seg(t, 0.25, 0.8))
    p = idle_pose()
    p["rot"].update({"Spine": qe(x=6 - 16 * k), "Chest": qe(x=8 - 14 * k), "Head": qe(x=-12 - 25 * k, z=10 * k),
                     "UpperArm.L": qe(x=-8 - 40 * k, z=12 + 30 * k), "LowerArm.L": qe(x=-20 - 40 * k),
                     "UpperLeg.L": qe(x=-10 - 12 * k, z=6), "UpperLeg.R": qe(x=-6 + 12 * k, z=-6)})
    p["pos"]["Hips"] = hips_at(dy=-0.05 - 0.03 * k, dz=-0.12 * k)
    club_dir(p, (-0.3, -0.9 + 0.5 * k, 0.45))
    return p


def death(t):
    # cade in avanti, a faccia in giù
    buckle = seg(t, 0.0, 0.4)
    fall = seg(t, 0.3, 1.1)
    p = pose_dict({"Root": qe(x=84 * fall),
                   "UpperLeg.L": qe(x=-10 - 40 * buckle * (1 - fall), z=6), "LowerLeg.L": qe(x=14 + 60 * buckle * (1 - 0.8 * fall)),
                   "UpperLeg.R": qe(x=-6 - 30 * buckle * (1 - fall), z=-6), "LowerLeg.R": qe(x=12 + 50 * buckle * (1 - 0.8 * fall)),
                   "Spine": qe(x=6 + 20 * buckle - 20 * fall), "Chest": qe(x=8 + 10 * buckle - 12 * fall),
                   "Head": qe(x=-12 - 25 * buckle * (1 - fall), y=30 * fall),
                   "UpperArm.L": qe(x=-8 - 140 * fall, z=12 + 20 * fall), "LowerArm.L": qe(x=-20 + 10 * fall),
                   "UpperArm.R": qe(x=-10 - 60 * buckle * (1 - fall) - 150 * fall, z=-10 - 30 * fall),
                   "LowerArm.R": qe(x=-22 + 15 * fall)},
                  {"Hips": hips_at(dy=-0.05 - 0.25 * buckle * (1 - fall)), "Root": (0.0, 0.34 * fall, 0.10 * fall)})
    club_dir(p, (-0.15, -0.9, 0.45))
    p["rot"]["Weapon.Club"] = qmul(p["rot"]["Weapon.Club"], qe(y=60 * fall))
    return p


ANIMS = [
    ("Idle", idle, 3.0, True),
    ("Walk", walk, 1.4, True),
    ("Run", run, 0.9, True),
    ("Attack", attack, 1.3, False),
    ("HitRecieve", hit, 0.8, False),
    ("Death", death, 1.5, False),
]

if __name__ == "__main__":
    build_mesh()
    M.write(ANIMS)
