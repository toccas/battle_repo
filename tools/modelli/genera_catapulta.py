#!/usr/bin/env python3
"""Catapulta low-poly: mangano a torsione su quattro ruote, con due serventi.

Uso (dalla cartella del progetto):
    python3 tools/modelli/genera_catapulta.py
Crea data/unithMesh/Units/Catapult.gltf e Catapult_Atlas.png; poi si cuoce con tools/vat_baker.tscn.
Stampa anche l'altezza naturale del modello: cuocilo con quell'altezza (--height) per tenere
le proporzioni vere tra macchina e serventi.

Il braccio a riposo è abbassato all'indietro; al tiro scatta in alto contro la traversa imbottita
e scaglia il masso in avanti (+Z). Poi i serventi lo riabbassano con l'argano e ricaricano.
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lowpoly import Model, QI, add, sub, mul, norm, qe, qmul, qrot, qfromto, lerp, seg  # noqa: E402

PALETTE = [
    (238, 190, 152),  # 0 pelle
    (150, 64, 44),    # 1 tunica dei serventi
    (120, 82, 46),    # 2 legno
    (88, 58, 32),     # 3 legno scuro
    (62, 40, 24),     # 4 stivali
    (96, 88, 74),     # 5 brache
    (196, 170, 118),  # 6 corda
    (130, 134, 142),  # 7 ferro
    (140, 136, 128),  # 8 pietra
    (118, 74, 38),    # 9 cuoio
    (180, 150, 96),   # 10 imbottitura
    (28, 22, 20),     # 11 occhi
    (100, 64, 36),    # 12 barba e capelli
    (70, 76, 60),     # 13 berretto
    (108, 104, 98),   # 14 pietra scura
    (255, 255, 255),  # 15 libero
]
SKIN, TUNIC, WOOD, DARKWOOD, BOOT, PANTS, ROPE, IRON, STONE, LEATHER, PAD, EYE, HAIR, CAP, STONE2 = range(15)

S = 1.35                          # scala della macchina rispetto ai serventi (alti 1,8 m)
WHEEL_R = 0.40 * S
PIVOT = (0.0, 0.65 * S, -0.20 * S)
ARM_LEN = 1.62 * S
ARM_REST = 15.0                   # gradi sopra l'orizzontale, verso il retro
ARM_UP = 76.0                     # rotazione del braccio quando batte sulla traversa
ARM_DIR = (0.0, math.sin(math.radians(ARM_REST)), -math.cos(math.radians(ARM_REST)))
TIP = add(PIVOT, mul(ARM_DIR, ARM_LEN))
WINCH = (0.0, 0.42 * S, -1.36 * S)
CREW_X, CREW_Z = 0.80 * S, -2.12 * S
WHEELS = {"Wheel.FL": (0.72 * S, WHEEL_R, 0.90 * S), "Wheel.FR": (-0.72 * S, WHEEL_R, 0.90 * S),
          "Wheel.BL": (0.72 * S, WHEEL_R, -1.12 * S), "Wheel.BR": (-0.72 * S, WHEEL_R, -1.12 * S)}

HUMAN = [  # ossa di un servente, relative ai suoi piedi
    ("Hips", None, (0.0, 0.95, 0.0)), ("Spine", "Hips", (0.0, 1.08, 0.0)), ("Chest", "Spine", (0.0, 1.25, 0.0)),
    ("Head", "Chest", (0.0, 1.50, 0.0)),
    ("UpperArm.L", "Chest", (0.24, 1.42, 0.0)), ("LowerArm.L", "UpperArm.L", (0.26, 1.14, 0.0)),
    ("Hand.L", "LowerArm.L", (0.27, 0.88, 0.0)),
    ("UpperArm.R", "Chest", (-0.24, 1.42, 0.0)), ("LowerArm.R", "UpperArm.R", (-0.26, 1.14, 0.0)),
    ("Hand.R", "LowerArm.R", (-0.27, 0.88, 0.0)),
    ("UpperLeg.L", "Hips", (0.10, 0.92, 0.0)), ("LowerLeg.L", "UpperLeg.L", (0.10, 0.50, 0.0)),
    ("UpperLeg.R", "Hips", (-0.10, 0.92, 0.0)), ("LowerLeg.R", "UpperLeg.R", (-0.10, 0.50, 0.0)),
    ("Hammer", "Hand.R", (-0.27, 0.84, 0.0)),
]
CREW = {"C1.": (CREW_X, 0.0, CREW_Z), "C2.": (-CREW_X, 0.0, CREW_Z)}


def make_bones():
    b = [("Root", None, (0.0, 0.0, 0.0)), ("Frame", "Root", (0.0, 0.45 * S, 0.0))]
    for n, p in WHEELS.items():
        b.append((n, "Frame", p))
    b.append(("Arm", "Frame", PIVOT))
    b.append(("Stone", "Arm", add(TIP, (0.0, 0.16 * S, 0.0))))
    b.append(("Winch", "Frame", WINCH))
    for pre, off in CREW.items():
        for name, parent, p in HUMAN:
            b.append((pre + name, pre + parent if parent else "Root", add(off, p)))
    return b


M = Model("Catapult", make_bones(), PALETTE)
R = M.rest


def sc(x, y, z): return (x * S, y * S, z * S)


# ------------------------------------------------------------------ geometria
def build_frame():
    box, limb, prism = M.box, M.limb, M.prism
    F = "Frame"
    # due longheroni e le traverse
    for x in (0.55, -0.55):
        box(sc(x, 0.47, -0.10), sc(0.18, 0.16, 3.10), WOOD, F)
    for z, w in ((1.30, 1.28), (0.30, 1.28), (-1.52, 1.28)):
        box(sc(0, 0.47, z), sc(w, 0.14, 0.16), DARKWOOD, F)
    box(sc(0, 0.40, -0.75), sc(0.92, 0.04, 1.2), DARKWOOD, F)        # assito sotto il braccio
    # assali
    for z in (0.90, -1.12):
        box(sc(0, 0.40, z), sc(1.56, 0.08, 0.08), IRON, F)
    # montanti con la traversa imbottita
    zc = PIVOT[2] / S + 0.15
    for x in (0.46, -0.46):
        box(sc(x, 1.10, zc), sc(0.14, 1.26, 0.14), WOOD, F)
        limb(sc(x, 1.62, zc + 0.04), sc(x, 0.55, 1.20), 0.10 * S, 0.10 * S, DARKWOOD, F)   # puntelli
        limb(sc(x, 1.30, zc - 0.04), sc(x, 0.55, -0.95), 0.09 * S, 0.09 * S, DARKWOOD, F)
    box(sc(0, 1.70, zc), sc(1.06, 0.16, 0.18), WOOD, F)
    box(sc(0, 1.66, zc - 0.11), sc(0.40, 0.22, 0.08), PAD, F)          # cuscino
    for x in (-0.12, 0.0, 0.12):
        box(sc(x, 1.66, zc - 0.155), sc(0.02, 0.23, 0.01), ROPE, F)
    # matassa di torsione attorno al perno del braccio
    prism(add(PIVOT, sc(-0.48, 0, 0)), add(PIVOT, sc(0.48, 0, 0)), 0.13 * S, 0.13 * S, 8, ROPE, F)
    for x in (0.47, -0.47):
        prism(add(PIVOT, sc(x - 0.04, 0, 0)), add(PIVOT, sc(x + 0.04, 0, 0)), 0.17 * S, 0.17 * S, 8, IRON, F)
    # argano sul retro, con le manovelle fuori dai longheroni
    prism(add(WINCH, sc(-0.46, 0, 0)), add(WINCH, sc(0.46, 0, 0)), 0.07 * S, 0.07 * S, 8, DARKWOOD, F)


def build_winch():
    box, limb, prism = M.box, M.limb, M.prism
    W = "Winch"
    prism(add(WINCH, sc(-0.40, 0, 0)), add(WINCH, sc(0.40, 0, 0)), 0.10 * S, 0.10 * S, 8, ROPE, W)
    for x in (0.66, -0.66):
        c = add(WINCH, sc(x, 0, 0))
        limb(add(c, sc(-0.04 if x > 0 else 0.04, 0, 0)), add(c, sc(0.04 if x > 0 else -0.04, 0, 0)), 0.36 * S, 0.05 * S, WOOD, W, side_hint=(0, 0, 1))
        limb(add(c, sc(-0.04 if x > 0 else 0.04, 0, 0)), add(c, sc(0.04 if x > 0 else -0.04, 0, 0)), 0.05 * S, 0.36 * S, WOOD, W, side_hint=(0, 0, 1))
        prism(add(WINCH, sc(0.46 if x > 0 else -0.46, 0, 0)), c, 0.03 * S, 0.03 * S, 6, IRON, W)


def build_wheels():
    for n, c in WHEELS.items():
        s = 1 if c[0] > 0 else -1
        a, b = add(c, (-0.07 * S, 0, 0)), add(c, (0.07 * S, 0, 0))
        M.prism(a, b, WHEEL_R, WHEEL_R, 10, DARKWOOD, n, phase=math.pi / 10)
        M.prism(add(a, (-0.005, 0, 0)), add(b, (0.005, 0, 0)), WHEEL_R * 0.72, WHEEL_R * 0.72, 10, WOOD, n, phase=math.pi / 10)
        for ang in (0, 90):   # raggi a croce (simmetria di 90°: la rotazione si ripete pulita)
            d = qrot(qe(x=ang), (0, 1, 0))
            M.limb(add(c, mul(d, -WHEEL_R * 0.95)), add(c, mul(d, WHEEL_R * 0.95)), 0.17 * S, 0.06 * S, DARKWOOD, n, side_hint=(1, 0, 0))
        M.prism(add(c, (s * 0.06 * S, 0, 0)), add(c, (s * 0.13 * S, 0, 0)), 0.08 * S, 0.06 * S, 8, IRON, n)


def build_arm():
    limb, box, prism = M.limb, M.box, M.prism
    A = "Arm"
    limb(add(PIVOT, mul(ARM_DIR, -0.12 * S)), TIP, 0.14 * S, 0.15 * S, WOOD, A, taper=0.75, side_hint=(1, 0, 0))
    for k in (0.35, 0.65):   # fasciature
        p = add(PIVOT, mul(ARM_DIR, ARM_LEN * k))
        limb(add(p, mul(ARM_DIR, -0.04 * S)), add(p, mul(ARM_DIR, 0.04 * S)), 0.16 * S, 0.17 * S, IRON, A, side_hint=(1, 0, 0))
    # coppa per il masso
    up = norm(qrot(qe(x=-ARM_REST), (0, 1, 0)))
    cup = add(TIP, mul(up, 0.06 * S))
    box(cup, sc(0.42, 0.06, 0.42), DARKWOOD, A)
    for dx, dz, w, d in ((0.19, 0, 0.04, 0.42), (-0.19, 0, 0.04, 0.42), (0, 0.19, 0.42, 0.04), (0, -0.19, 0.42, 0.04)):
        box(add(cup, sc(dx, 0.07, dz)), sc(w, 0.12, d), DARKWOOD, A)
    # masso
    st = R["Stone"]
    M.prism(add(st, sc(0, -0.14, 0)), add(st, sc(0, 0.02, 0)), 0.10 * S, 0.17 * S, 6, STONE, "Stone", phase=0.3)
    M.prism(add(st, sc(0, 0.02, 0)), add(st, sc(0, 0.16, 0)), 0.17 * S, 0.08 * S, 6, STONE2, "Stone", phase=0.8)


def build_crew(pre, off, beard):
    box, limb = M.box, M.limb
    def P(x, y, z): return add(off, (x, y, z))
    for s in (1, -1):
        up, lo = pre + ("UpperLeg.L" if s > 0 else "UpperLeg.R"), pre + ("LowerLeg.L" if s > 0 else "LowerLeg.R")
        x = 0.10 * s
        box(P(x, 0.71, 0), (0.15, 0.44, 0.16), PANTS, up, taper=(1.1, 1.05))
        box(P(x, 0.30, 0), (0.13, 0.40, 0.14), BOOT, lo, taper=(1.1, 1.1))
        box(P(x, 0.05, 0.04), (0.13, 0.10, 0.23), BOOT, lo, taper=(1.0, 0.8), shift=(0, -0.02))
    box(P(0, 0.84, 0), (0.38, 0.26, 0.23), TUNIC, pre + "Hips", taper=(0.9, 0.9))
    box(P(0, 0.95, 0), (0.36, 0.06, 0.23), LEATHER, pre + "Hips")
    box(P(0, 0.83, 0.12), (0.26, 0.30, 0.012), LEATHER, pre + "Hips")              # grembiule
    box(P(0, 1.07, 0), (0.33, 0.20, 0.21), TUNIC, pre + "Spine", taper=(1.06, 1.0))
    box(P(0, 1.06, 0.112), (0.24, 0.20, 0.012), LEATHER, pre + "Spine")
    box(P(0, 1.31, 0), (0.38, 0.30, 0.22), TUNIC, pre + "Chest", taper=(1.05, 0.95))
    box(P(0, 1.535, 0), (0.08, 0.07, 0.08), SKIN, pre + "Head")
    box(P(0, 1.655, 0.01), (0.23, 0.23, 0.23), SKIN, pre + "Head", taper=(0.94, 0.94))
    for s in (1, -1):
        box(P(0.052 * s, 1.675, 0.126), (0.033, 0.035, 0.01), EYE, pre + "Head")
    if beard:
        box(P(0, 1.575, 0.11), (0.19, 0.08, 0.05), HAIR, pre + "Head", taper=(1.1, 1.0))
    box(P(0, 1.70, -0.02), (0.25, 0.14, 0.24), HAIR, pre + "Head")                 # capelli
    M.prism(P(0, 1.765, 0.0), P(0, 1.80, 0.0), 0.17, 0.17, 8, CAP, pre + "Head")   # berretto a falda
    M.prism(P(0, 1.80, -0.01), P(0, 1.88, -0.03), 0.125, 0.08, 8, CAP, pre + "Head")
    for s, side in ((1, "L"), (-1, "R")):
        ua, la, ha = pre + "UpperArm." + side, pre + "LowerArm." + side, pre + "Hand." + side
        sh, el, wr = R[ua], R[la], R[ha]
        limb(add(sh, (0, 0.04, 0)), el, 0.12, 0.12, TUNIC, ua, taper=0.9)
        limb(add(el, (0, 0.02, 0)), wr, 0.10, 0.10, SKIN, la, taper=0.9)
        limb(wr, add(wr, (0.003 * s, -0.10, 0.0)), 0.085, 0.085, SKIN, ha, taper=0.85)
    # mazzuolo nella destra
    h = R[pre + "Hammer"]
    limb(add(h, (0, 0.08, 0)), add(h, (0, -0.36, 0)), 0.035, 0.035, WOOD, pre + "Hammer")
    box(add(h, (0, -0.40, 0)), (0.10, 0.10, 0.20), DARKWOOD, pre + "Hammer")


def build_mesh():
    build_frame()
    build_winch()
    build_wheels()
    build_arm()
    build_crew("C1.", CREW["C1."], True)
    build_crew("C2.", CREW["C2."], False)


# ------------------------------------------------------------------ pose
HIDDEN = (0.001, 0.001, 0.001)


def new_pose():
    return {"rot": {}, "pos": {}, "scale": {}}


def crew_hips(p, pre, dx=0.0, dy=0.0, dz=0.0):
    p["pos"][pre + "Hips"] = add(M.rest_local(pre + "Hips"), (dx, dy, dz))


def crew_idle(p, pre, t, phase=0.0, T=3.0):
    b = math.sin(2 * math.pi * t / T + phase)
    p["rot"].update({pre + "Spine": qe(x=1.5 * b), pre + "Chest": qe(x=1.2 * b),
                     pre + "Head": qe(x=-2 * b, y=12 * math.sin(math.pi * t / T + phase)),
                     pre + "UpperArm.L": qe(z=5), pre + "LowerArm.L": qe(x=-10),
                     pre + "UpperArm.R": qe(z=-5), pre + "LowerArm.R": qe(x=-12),
                     pre + "UpperLeg.L": qe(z=3), pre + "UpperLeg.R": qe(z=-3)})
    crew_hips(p, pre, dy=-0.005 * (1 - b))


def crew_legs(p, pre, ph, leg, knee, lean, bob):
    s = math.sin(ph)
    kl = knee * max(0.0, math.sin(ph + 1.2))
    kr = knee * max(0.0, math.sin(ph + 1.2 + math.pi))
    p["rot"].update({pre + "UpperLeg.L": qe(x=-leg * s - lean * 0.5), pre + "LowerLeg.L": qe(x=kl + 6),
                     pre + "UpperLeg.R": qe(x=leg * s - lean * 0.5), pre + "LowerLeg.R": qe(x=kr + 6),
                     pre + "Hips": qe(x=lean * 0.5, y=4 * s), pre + "Spine": qe(x=lean * 0.3), pre + "Chest": qe(x=lean * 0.2),
                     pre + "Head": qe(x=-lean * 0.8)})
    crew_hips(p, pre, dy=bob * abs(math.cos(ph)) - bob - 0.04 * lean / 30.0)


def frame_world(p, local):
    g = M.fk(p["rot"], p["pos"])
    fr, fp = g["Frame"]
    return add(fp, qrot(fr, sub(local, R["Frame"])))


def push(p, pre):
    """Mani sulla testata del longherone, gomiti piegati verso il basso."""
    x = 0.55 * S * (1 if pre == "C1." else -1)
    for side, dx in (("L", 0.07 * S), ("R", -0.07 * S)):
        target = frame_world(p, (x + dx, 0.55 * S, -1.62 * S))
        M.ik_arm(side, target, (1.0 if side == "L" else -1.0, -1.0, -0.2), p["rot"], p["pos"], prefix=pre)
        p["rot"][pre + "Hand." + side] = qe(x=-60)


def wheels_roll(p, ang):
    for n in WHEELS:
        p["rot"][n] = qe(x=ang)


def idle(t):
    p = new_pose()
    crew_idle(p, "C1.", t)
    crew_idle(p, "C2.", t, phase=1.9)
    p["rot"]["C2.Head"] = qe(y=-15 + 10 * math.sin(2 * math.pi * t / 3.0))
    return p


def moving(t, T, legs, knee, bob):
    p = new_pose()
    ph = 2 * math.pi * t / T
    for pre, off in (("C1.", 0.0), ("C2.", math.pi)):
        crew_legs(p, pre, ph + off, legs, knee, 30, bob)
        push(p, pre)
    wheels_roll(p, 270.0 * t / T)               # multiplo di 90°: il ciclo si ripete senza scatti
    p["rot"]["Frame"] = qe(z=0.6 * math.sin(2 * ph))
    p["pos"]["Frame"] = add(M.rest_local("Frame"), (0, 0.008 * abs(math.sin(ph * 2)), 0))
    return p


def walk(t): return moving(t, 1.2, 22, 34, 0.03)
def run(t): return moving(t, 0.9, 30, 50, 0.05)


def winch_hands(p, pre, ang):
    """Mani sulla manovella dell'argano, che gira di ang gradi."""
    s = 1 if pre == "C1." else -1
    c = add(WINCH, (s * 0.70 * S, 0, 0))
    h = qrot(qe(x=ang), (0, 0.15 * S, 0))
    target = frame_world(p, add(c, h))
    for side in ("L", "R"):
        off = (0.05 if side == "L" else -0.05, 0, 0)
        M.ik_arm(side, add(target, off), (s * 1.0, -0.8, -0.3), p["rot"], p["pos"], prefix=pre)


def shoot(t):
    # 0-0,2 il primo servente tira la leva · 0,2-0,4 il braccio scatta · rimbalzo ·
    # 0,8-3,2 i serventi girano l'argano e lo riabbassano · 3,2-3,8 ricaricano il masso
    p = idle(t)
    lever = seg(t, 0.0, 0.18) * (1 - seg(t, 0.3, 0.6))
    p["rot"].update({"C1.UpperArm.R": qe(x=-30 + 60 * lever, z=-10), "C1.LowerArm.R": qe(x=-50 + 30 * lever),
                     "C1.Spine": qe(x=-10 * lever, y=-15 * lever)})
    fire = seg(t, 0.18, 0.36)
    fire = fire * fire                            # accelera: la torsione si scarica di colpo
    bounce = math.sin(seg(t, 0.36, 0.75) * math.pi * 2) * (1 - seg(t, 0.36, 0.75)) * 6
    lower = seg(t, 1.0, 3.2)
    arm = ARM_UP * fire - bounce * (1 - lower)
    arm = arm * (1 - lower)
    p["rot"]["Arm"] = qe(x=arm)
    p["scale"]["Stone"] = HIDDEN if 0.32 < t < 3.35 else (1.0, 1.0, 1.0)
    kick = seg(t, 0.30, 0.38) * (1 - seg(t, 0.38, 0.9))
    p["rot"]["Frame"] = qe(x=-2.5 * kick)
    p["pos"]["Frame"] = add(M.rest_local("Frame"), (0, 0.04 * kick, -0.06 * kick))
    # all'argano: un passo avanti, poi la manovella gira mentre il braccio scende
    step = seg(t, 0.7, 1.0) * (1 - seg(t, 3.2, 3.6))
    crank = 360.0 * 3 * lower
    p["rot"]["Winch"] = qe(x=-crank)
    for pre in ("C1.", "C2."):
        if step > 0.0:
            crew_hips(p, pre, dz=0.55 * step, dy=-0.12 * step)
            p["rot"][pre + "Spine"] = qe(x=18 * step)
            p["rot"][pre + "Chest"] = qe(x=10 * step)
            p["rot"][pre + "UpperLeg.L"] = qe(x=-28 * step, z=4)
            p["rot"][pre + "LowerLeg.L"] = qe(x=30 * step)
            p["rot"][pre + "UpperLeg.R"] = qe(x=6 * step, z=-4)
            p["rot"][pre + "LowerLeg.R"] = qe(x=18 * step)
            if 0.95 < t < 3.25:
                winch_hands(p, pre, -crank + (0 if pre == "C1." else 180))
                p["rot"][pre + "Spine"] = qe(x=18 + 6 * math.sin(math.radians(crank)))
    # il secondo servente rimette il masso nella coppa
    load = seg(t, 3.15, 3.35) * (1 - seg(t, 3.45, 3.8))
    if load > 0.0:
        p["rot"]["C2.UpperArm.L"] = qe(x=-70 * load, z=5 + 20 * load)
        p["rot"]["C2.LowerArm.L"] = qe(x=-30 * load)
        p["rot"]["C2.Spine"] = qe(x=15 * load, y=25 * load)
    return p


def attack(t):
    # i serventi si difendono a colpi di mazzuolo
    p = idle(0.0)
    for pre, d in (("C1.", 0.0), ("C2.", 0.12)):
        u = t - d
        wind = seg(u, 0.0, 0.3) * (1 - seg(u, 0.3, 0.45))
        hitk = seg(u, 0.3, 0.45) * (1 - seg(u, 0.6, 0.95))
        p["rot"].update({pre + "UpperArm.R": qe(x=-160 * wind - 60 * hitk, z=-10),
                         pre + "LowerArm.R": qe(x=-40 * wind - 10 * hitk),
                         pre + "Hammer": qe(x=-30 * wind + 70 * hitk),
                         pre + "Spine": qe(x=-8 * wind + 18 * hitk, y=10 * wind - 10 * hitk),
                         pre + "Chest": qe(x=-6 * wind + 12 * hitk),
                         pre + "UpperArm.L": qe(x=-30 * hitk, z=15),
                         pre + "UpperLeg.L": qe(x=-25 * hitk), pre + "LowerLeg.L": qe(x=20 * hitk),
                         pre + "UpperLeg.R": qe(x=10 * hitk)})
        crew_hips(p, pre, dy=-0.04 * hitk, dz=0.12 * hitk)
    return p


def hit(t):
    p = idle(0.0)
    k = seg(t, 0.0, 0.08) * (1 - seg(t, 0.15, 0.6))
    w = math.sin(t * 40) * k
    p["rot"]["Frame"] = qe(z=3 * w, x=-1.5 * k)
    p["rot"]["Arm"] = qe(x=4 * w)
    for pre, s in (("C1.", 1), ("C2.", -1)):
        p["rot"].update({pre + "Spine": qe(x=-14 * k, z=6 * s * k), pre + "Head": qe(x=-18 * k),
                         pre + "UpperArm.L": qe(x=-30 * k, z=5 + 30 * k), pre + "UpperArm.R": qe(x=-30 * k, z=-5 - 30 * k),
                         pre + "LowerArm.L": qe(x=-40 * k), pre + "LowerArm.R": qe(x=-40 * k)})
        crew_hips(p, pre, dz=-0.10 * k, dy=-0.03 * k)
    return p


def death(t):
    # una ruota cede, la macchina si accascia, il braccio ricade di lato, i serventi cadono
    p = idle(0.0)
    brk = seg(t, 0.05, 0.6)
    p["rot"]["Frame"] = qe(z=-10 * brk, x=5 * brk)
    p["pos"]["Frame"] = add(M.rest_local("Frame"), (0, -0.22 * S * brk, 0))
    p["pos"]["Wheel.BL"] = add(M.rest_local("Wheel.BL"), (0.35 * S * brk, -0.05 * brk + 0.2 * S * brk * (1 - brk), 0))
    p["rot"]["Wheel.BL"] = qe(z=-80 * seg(t, 0.15, 0.9))
    p["rot"]["Wheel.FL"] = qe(z=-6 * brk)
    p["rot"]["Arm"] = qe(x=-8 * brk, z=-12 * brk)
    fall = seg(t, 0.15, 0.6)
    p["pos"]["Stone"] = add(M.rest_local("Stone"), (0, -0.5 * S * fall, 0.1 * fall))
    for pre, back, d in (("C1.", True, 0.0), ("C2.", False, 0.15)):
        u = t - d
        buckle = seg(u, 0.1, 0.4)
        f = seg(u, 0.3, 1.0)
        sgn = -1 if back else 1
        p["rot"].update({pre + "Hips": qe(x=sgn * 85 * f),
                         pre + "UpperLeg.L": qe(x=-30 * buckle * (1 - f)), pre + "LowerLeg.L": qe(x=50 * buckle * (1 - 0.8 * f)),
                         pre + "UpperLeg.R": qe(x=-20 * buckle * (1 - f)), pre + "LowerLeg.R": qe(x=40 * buckle * (1 - 0.8 * f)),
                         pre + "UpperArm.L": qe(x=-60 * f, z=5 + 40 * f), pre + "UpperArm.R": qe(x=-60 * f, z=-5 - 40 * f),
                         pre + "Head": qe(x=sgn * -15 * f, y=20 * f)})
        # il bacino scende e si allontana man mano che il corpo si stende
        crew_hips(p, pre, dy=-0.18 * buckle * (1 - f) - 0.82 * f, dz=sgn * 0.15 * f)
    return p


ANIMS = [
    ("Idle", idle, 3.0, True),
    ("Walk", walk, 1.2, True),
    ("Run", run, 0.9, True),
    ("Attack", attack, 1.1, False),
    ("Shoot", shoot, 3.8, False),
    ("HitRecieve", hit, 0.6, False),
    ("Death", death, 1.6, False),
]

if __name__ == "__main__":
    build_mesh()
    top = max(v[1] for v in M.P)
    print("altezza naturale: %.2f m (cuoci con --height=%.2f)" % (top, top))
    M.write(ANIMS, translated=["Root", "Frame", "Wheel.BL", "Stone", "C1.Hips", "C2.Hips"], scaled=["Stone"])
