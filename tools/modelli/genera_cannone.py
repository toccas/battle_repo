#!/usr/bin/env python3
"""Cannone low-poly: canna di bronzo su affusto a due ruote con coda, e due serventi
(uno con lo scovolo, uno con la miccia sull'asta).

Uso (dalla cartella del progetto):
    python3 tools/modelli/genera_cannone.py
Crea data/unithMesh/Units/Cannon.gltf e Cannon_Atlas.png; poi si cuoce con tools/vat_baker.tscn,
con l'altezza naturale che lo script stampa (--height).

Tiro: la miccia tocca il focone, lampo e nuvola di fumo, il pezzo rincula; il primo servente
scovola e calca dalla bocca, poi insieme lo riportano in batteria.
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lowpoly import Model, QI, add, sub, mul, norm, qe, qmul, qrot, qfromto, lerp, seg  # noqa: E402

PALETTE = [
    (238, 190, 152),  # 0 pelle
    (56, 66, 108),    # 1 giubba
    (176, 52, 42),    # 2 risvolti rossi
    (178, 128, 62),   # 3 bronzo
    (122, 84, 48),    # 4 legno dell'affusto
    (84, 56, 32),     # 5 legno scuro
    (40, 30, 24),     # 6 stivali
    (196, 186, 156),  # 7 calzoni
    (36, 34, 34),     # 8 tricorno
    (226, 226, 220),  # 9 fumo chiaro
    (176, 176, 172),  # 10 fumo scuro
    (255, 196, 70),   # 11 lampo e brace
    (28, 22, 20),     # 12 occhi
    (96, 62, 36),     # 13 capelli
    (92, 96, 104),    # 14 ferro
    (150, 120, 84),   # 15 scovolo (lana)
]
SKIN, COAT, TRIM, BRONZE, WOOD, DARKWOOD, BOOT, PANTS, HAT, SMOKE, SMOKE2, FLASH, EYE, HAIR, IRON, SPONGE = range(16)

S = 1.15                                 # scala del pezzo rispetto ai serventi (alti 1,8 m)
WHEEL_R = 0.62 * S
AXLE = (0.0, WHEEL_R, 0.0)
TRUNNION = (0.0, 0.92 * S, 0.06 * S)
BREECH_Z, MUZZLE_Z = -0.75 * S, 1.30 * S  # rispetto agli orecchioni
TRAIL_END = (0.0, 0.08, -1.95 * S)
WHEELS = {"Wheel.L": (0.50 * S, WHEEL_R, 0.0), "Wheel.R": (-0.50 * S, WHEEL_R, 0.0)}
MUZZLE_W = add(TRUNNION, (0.0, 0.0, MUZZLE_Z))
VENT = add(TRUNNION, (0.0, 0.15 * S, BREECH_Z + 0.18 * S))
RECOIL = 0.6 * S

HUMAN = [
    ("Hips", None, (0.0, 0.95, 0.0)), ("Spine", "Hips", (0.0, 1.08, 0.0)), ("Chest", "Spine", (0.0, 1.25, 0.0)),
    ("Head", "Chest", (0.0, 1.50, 0.0)),
    ("UpperArm.L", "Chest", (0.24, 1.42, 0.0)), ("LowerArm.L", "UpperArm.L", (0.26, 1.14, 0.0)),
    ("Hand.L", "LowerArm.L", (0.27, 0.88, 0.0)),
    ("UpperArm.R", "Chest", (-0.24, 1.42, 0.0)), ("LowerArm.R", "UpperArm.R", (-0.26, 1.14, 0.0)),
    ("Hand.R", "LowerArm.R", (-0.27, 0.88, 0.0)),
    ("UpperLeg.L", "Hips", (0.10, 0.92, 0.0)), ("LowerLeg.L", "UpperLeg.L", (0.10, 0.50, 0.0)),
    ("UpperLeg.R", "Hips", (-0.10, 0.92, 0.0)), ("LowerLeg.R", "UpperLeg.R", (-0.10, 0.50, 0.0)),
]
CREW = {"C1.": (-1.10 * S, 0.0, 0.30 * S), "C2.": (1.10 * S, 0.0, -0.45 * S)}
TOOL = {"C1.": "Prop.Rammer", "C2.": "Prop.Linstock"}
RAM_UP, RAM_DOWN = 1.00, 0.85             # scovolo sopra e sotto la mano (m)
LIN_UP, LIN_DOWN = 0.62, 0.55             # asta della miccia


def make_bones():
    b = [("Root", None, (0.0, 0.0, 0.0)), ("Carriage", "Root", AXLE)]
    for n, p in WHEELS.items():
        b.append((n, "Carriage", p))
    b.append(("Barrel", "Carriage", TRUNNION))
    b.append(("Prop.Flash", "Barrel", MUZZLE_W))
    b.append(("Prop.Smoke", "Root", add(MUZZLE_W, (0.0, 0.0, 0.25))))
    for pre, off in CREW.items():
        for name, parent, p in HUMAN:
            b.append((pre + name, pre + parent if parent else "Root", add(off, p)))
        b.append((TOOL[pre], pre + "Hand.R", add(off, (-0.27, 0.84, 0.0))))
    return b


M = Model("Cannon", make_bones(), PALETTE)
R = M.rest


# ------------------------------------------------------------------ geometria
def build_carriage():
    box, limb, prism = M.box, M.limb, M.prism
    C = "Carriage"
    # guance: due fiancate che scendono dagli orecchioni fino alla coda
    for x in (0.20 * S, -0.20 * S):
        limb((x, 0.96 * S, 0.30 * S), (x * 0.45, TRAIL_END[1] + 0.12, TRAIL_END[2] + 0.25), 0.08 * S, 0.30 * S, WOOD, C, taper=0.7, side_hint=(1, 0, 0))
        box((x, 0.97 * S, 0.06 * S), (0.10 * S, 0.06 * S, 0.16 * S), IRON, C)          # cappe sugli orecchioni
    # coda con vanga e anello
    limb((0, 0.42 * S, -0.45 * S), TRAIL_END, 0.30 * S, 0.12 * S, DARKWOOD, C, taper=0.8, side_hint=(1, 0, 0))
    box(add(TRAIL_END, (0, 0.03, -0.04)), (0.30 * S, 0.06, 0.18 * S), IRON, C)
    prism(add(TRAIL_END, (0, 0.10, -0.02)), add(TRAIL_END, (0, 0.16, -0.02)), 0.07, 0.07, 6, IRON, C)
    # traverse e assale
    box((0, 0.62 * S, -0.30 * S), (0.42 * S, 0.10 * S, 0.12 * S), DARKWOOD, C)
    box((0, 0.42 * S, -1.05 * S), (0.30 * S, 0.08 * S, 0.12 * S), DARKWOOD, C)
    box(AXLE, (1.06 * S, 0.10 * S, 0.12 * S), DARKWOOD, C)
    # cuneo di mira sotto la culatta e cassetta delle munizioni sulla coda
    box((0, 0.74 * S, BREECH_Z + 0.25 * S), (0.24 * S, 0.10 * S, 0.34 * S), WOOD, C, taper=(1.0, 1.0), shift=(0, 0.03))
    box((0, 0.60 * S, -1.20 * S), (0.36 * S, 0.18 * S, 0.26 * S), DARKWOOD, C)
    for x in (-0.08 * S, 0.08 * S):
        prism((x, 0.70 * S, -1.20 * S), (x, 0.74 * S, -1.20 * S), 0.055 * S, 0.04 * S, 6, IRON, C)   # palle


def build_barrel():
    prism = M.prism
    B = "Barrel"
    t = TRUNNION
    def at(z, dy=0.0): return add(t, (0.0, dy, z))
    prism(at(BREECH_Z), at(BREECH_Z + 0.55 * S), 0.18 * S, 0.17 * S, 10, BRONZE, B, phase=math.pi / 10)
    prism(at(BREECH_Z + 0.55 * S), at(MUZZLE_Z - 0.16 * S), 0.15 * S, 0.12 * S, 10, BRONZE, B, phase=math.pi / 10)
    prism(at(MUZZLE_Z - 0.16 * S), at(MUZZLE_Z), 0.15 * S, 0.15 * S, 10, BRONZE, B, phase=math.pi / 10)   # gioia
    prism(at(MUZZLE_Z + 0.002), at(MUZZLE_Z + 0.004), 0.08 * S, 0.08 * S, 10, IRON, B, caps=True)          # anima
    for z, r in ((BREECH_Z + 0.06 * S, 0.19), (BREECH_Z + 0.55 * S, 0.18), (MUZZLE_Z - 0.6 * S, 0.14)):
        prism(at(z - 0.03 * S), at(z + 0.03 * S), r * S, r * S, 10, BRONZE, B, phase=math.pi / 10)          # cerchiature
    prism(at(BREECH_Z), at(BREECH_Z - 0.10 * S), 0.10 * S, 0.06 * S, 8, BRONZE, B)                          # bottone di culatta
    prism(at(BREECH_Z - 0.10 * S), at(BREECH_Z - 0.17 * S), 0.07 * S, 0.0, 8, BRONZE, B)
    prism(add(t, (-0.26 * S, 0, 0)), add(t, (0.26 * S, 0, 0)), 0.06 * S, 0.06 * S, 8, BRONZE, B)            # orecchioni
    for x in (0.08 * S, -0.08 * S):                                                                          # maniglie a delfino
        M.limb(at(0.05 * S, 0.15 * S), at(0.25 * S, 0.15 * S), 0.035 * S, 0.06 * S, BRONZE, B)
    M.box(VENT, (0.04, 0.02, 0.04), IRON, B)


def build_wheels():
    for n, c in WHEELS.items():
        s = 1 if c[0] > 0 else -1
        a, b = add(c, (-0.05 * S, 0, 0)), add(c, (0.05 * S, 0, 0))
        # cerchione: 12 tratti di legno con il cerchio di ferro all'esterno
        for k in range(12):
            for rr, th, w, col in ((WHEEL_R * 0.90, 0.10 * S, 0.11 * S, WOOD), (WHEEL_R * 0.985, 0.03 * S, 0.12 * S, IRON)):
                p0 = add(c, qrot(qe(x=k * 30.0 - 1.5), (0, rr, 0)))
                p1 = add(c, qrot(qe(x=(k + 1) * 30.0 + 1.5), (0, rr, 0)))
                M.limb(p0, p1, w, th, col, n, side_hint=(1, 0, 0))
        for ang in (0, 60, 120):   # sei raggi: la rotazione si ripete ogni 60°
            d = qrot(qe(x=ang), (0, 1, 0))
            M.limb(add(c, mul(d, -WHEEL_R * 0.86)), add(c, mul(d, WHEEL_R * 0.86)), 0.04 * S, 0.06 * S, WOOD, n, side_hint=(1, 0, 0))
        M.prism(add(c, (-s * 0.09 * S, 0, 0)), add(c, (s * 0.12 * S, 0, 0)), 0.10 * S, 0.07 * S, 8, DARKWOOD, n)


def build_fx():
    f = R["Prop.Flash"]
    M.prism(f, add(f, (0, 0, 0.35)), 0.10, 0.22, 6, FLASH, "Prop.Flash")
    M.prism(add(f, (0, 0, 0.35)), add(f, (0, 0, 0.70)), 0.22, 0.0, 6, FLASH, "Prop.Flash")
    s = R["Prop.Smoke"]
    puffs = [((0, 0, 0), 0.40, SMOKE), ((0.30, 0.18, 0.35), 0.32, SMOKE2), ((-0.28, 0.12, 0.30), 0.34, SMOKE),
             ((0.05, 0.38, 0.55), 0.36, SMOKE), ((-0.12, -0.05, 0.75), 0.30, SMOKE2), ((0.20, 0.10, 0.95), 0.28, SMOKE)]
    for off, r, col in puffs:
        c = add(s, off)
        M.prism(add(c, (0, -r * 0.8, 0)), c, r * 0.55, r, 6, col, "Prop.Smoke", phase=0.4)
        M.prism(c, add(c, (0, r * 0.8, 0)), r, r * 0.45, 6, col, "Prop.Smoke", phase=0.4)


def build_crew(pre, off, beard):
    box, limb = M.box, M.limb
    def P(x, y, z): return add(off, (x, y, z))
    for s in (1, -1):
        up, lo = pre + ("UpperLeg.L" if s > 0 else "UpperLeg.R"), pre + ("LowerLeg.L" if s > 0 else "LowerLeg.R")
        x = 0.10 * s
        box(P(x, 0.71, 0), (0.15, 0.44, 0.16), PANTS, up, taper=(1.1, 1.05))
        box(P(x, 0.30, 0), (0.13, 0.42, 0.14), BOOT, lo, taper=(1.12, 1.1))
        box(P(x, 0.05, 0.04), (0.13, 0.10, 0.23), BOOT, lo, taper=(1.0, 0.8), shift=(0, -0.02))
    box(P(0, 0.88, 0), (0.37, 0.20, 0.23), COAT, pre + "Hips", taper=(0.95, 0.95))
    box(P(0, 0.70, -0.10), (0.34, 0.36, 0.04), COAT, pre + "Hips", taper=(1.0, 1.0))  # falde della giubba
    box(P(0, 0.95, 0), (0.36, 0.05, 0.235), PANTS, pre + "Hips")                       # cinturone
    box(P(0, 1.07, 0), (0.33, 0.20, 0.21), COAT, pre + "Spine", taper=(1.06, 1.0))
    box(P(0, 1.31, 0), (0.38, 0.30, 0.22), COAT, pre + "Chest", taper=(1.05, 0.95))
    for s in (1, -1):
        box(P(0.07 * s, 1.24, 0.112), (0.07, 0.42, 0.012), TRIM, pre + "Chest")          # risvolti
    box(P(0, 1.47, 0), (0.18, 0.06, 0.16), PANTS, pre + "Chest")                         # fazzoletto al collo
    box(P(0, 1.535, 0), (0.08, 0.07, 0.08), SKIN, pre + "Head")
    box(P(0, 1.655, 0.01), (0.23, 0.23, 0.23), SKIN, pre + "Head", taper=(0.94, 0.94))
    for s in (1, -1):
        box(P(0.052 * s, 1.675, 0.126), (0.033, 0.035, 0.01), EYE, pre + "Head")
    if beard:
        box(P(0, 1.60, 0.125), (0.14, 0.035, 0.02), HAIR, pre + "Head")                 # baffi
    box(P(0, 1.68, -0.035), (0.245, 0.18, 0.22), HAIR, pre + "Head")
    box(P(0, 1.56, -0.13), (0.06, 0.10, 0.04), HAIR, pre + "Head")                       # codino
    M.prism(P(0, 1.765, 0.0), P(0, 1.79, 0.0), 0.22, 0.20, 3, HAT, pre + "Head", phase=math.pi / 2)   # tricorno
    M.prism(P(0, 1.79, 0.0), P(0, 1.86, 0.0), 0.13, 0.10, 8, HAT, pre + "Head")
    for s, side in ((1, "L"), (-1, "R")):
        ua, la, ha = pre + "UpperArm." + side, pre + "LowerArm." + side, pre + "Hand." + side
        sh, el, wr = R[ua], R[la], R[ha]
        limb(add(sh, (0, 0.04, 0)), el, 0.12, 0.12, COAT, ua, taper=0.9)
        limb(add(el, (0, 0.02, 0)), add(wr, (0, 0.07, 0)), 0.10, 0.10, COAT, la, taper=0.9)
        limb(add(wr, (0, 0.09, 0)), add(wr, (0, 0.02, 0)), 0.115, 0.115, TRIM, la)        # paramani
        limb(wr, add(wr, (0.003 * s, -0.10, 0.0)), 0.085, 0.085, SKIN, ha, taper=0.85)
    tool = TOOL[pre]
    h = R[tool]
    if pre == "C1.":   # scovolo: lana da una parte, calcatoio dall'altra
        M.prism(add(h, (0, -RAM_DOWN, 0)), add(h, (0, RAM_UP, 0)), 0.02, 0.02, 6, WOOD, tool)
        M.prism(add(h, (0, RAM_UP, 0)), add(h, (0, RAM_UP + 0.22, 0)), 0.07, 0.07, 8, SPONGE, tool)
        M.prism(add(h, (0, -RAM_DOWN - 0.12, 0)), add(h, (0, -RAM_DOWN, 0)), 0.07, 0.07, 8, DARKWOOD, tool)
    else:              # buttafuoco: asta con la forcella e la miccia accesa
        M.prism(add(h, (0, -LIN_DOWN, 0)), add(h, (0, LIN_UP, 0)), 0.018, 0.018, 6, WOOD, tool)
        M.limb(add(h, (0, LIN_UP, 0)), add(h, (0.06, LIN_UP + 0.10, 0)), 0.02, 0.02, IRON, tool)
        M.limb(add(h, (0, LIN_UP, 0)), add(h, (-0.06, LIN_UP + 0.10, 0)), 0.02, 0.02, IRON, tool)
        M.box(add(h, (0.06, LIN_UP + 0.12, 0)), (0.035, 0.04, 0.035), FLASH, tool)


def build_mesh():
    build_carriage()
    build_barrel()
    build_wheels()
    build_fx()
    build_crew("C1.", CREW["C1."], True)
    build_crew("C2.", CREW["C2."], False)


# ------------------------------------------------------------------ pose
HIDDEN = (0.001, 0.001, 0.001)
UP = (0.0, 1.0, 0.0)


def new_pose():
    return {"rot": {}, "pos": {}, "scale": {"Prop.Flash": HIDDEN, "Prop.Smoke": HIDDEN}}


def crew_hips(p, pre, dx=0.0, dy=0.0, dz=0.0):
    p["pos"][pre + "Hips"] = add(M.rest_local(pre + "Hips"), (dx, dy, dz))


def hold_tool(p, pre, tilt=6.0):
    """Attrezzo dritto in mano, appoggiato a terra."""
    M.set_global_rot(TOOL[pre], qe(x=tilt), p["rot"], p["pos"])


def crew_idle(p, pre, t, phase=0.0, T=3.2):
    b = math.sin(2 * math.pi * t / T + phase)
    p["rot"].update({pre + "Spine": qe(x=1.5 * b), pre + "Chest": qe(x=1.2 * b),
                     pre + "Head": qe(x=-2 * b, y=10 * math.sin(math.pi * t / T + phase)),
                     pre + "UpperArm.L": qe(z=5), pre + "LowerArm.L": qe(x=-10),
                     pre + "UpperArm.R": qe(x=-8, z=-8), pre + "LowerArm.R": qe(x=-30),
                     pre + "UpperLeg.L": qe(z=3), pre + "UpperLeg.R": qe(z=-3)})
    crew_hips(p, pre, dy=-0.005 * (1 - b))
    hold_tool(p, pre)


def idle(t):
    p = new_pose()
    crew_idle(p, "C1.", t)
    crew_idle(p, "C2.", t, phase=2.1)
    return p


def crew_legs(p, pre, ph, leg, knee, lean, bob, dx=0.0, dz=0.0):
    s = math.sin(ph)
    kl = knee * max(0.0, math.sin(ph + 1.2))
    kr = knee * max(0.0, math.sin(ph + 1.2 + math.pi))
    p["rot"].update({pre + "UpperLeg.L": qe(x=-leg * s - lean * 0.5), pre + "LowerLeg.L": qe(x=kl + 6),
                     pre + "UpperLeg.R": qe(x=leg * s - lean * 0.5), pre + "LowerLeg.R": qe(x=kr + 6),
                     pre + "Hips": qe(x=lean * 0.5, y=4 * s), pre + "Spine": qe(x=lean * 0.3), pre + "Chest": qe(x=lean * 0.2),
                     pre + "Head": qe(x=-lean * 0.8)})
    crew_hips(p, pre, dx=dx, dz=dz, dy=bob * abs(math.cos(ph)) - bob - 0.04 * lean / 30.0)


def world_of(p, bone, local):
    g = M.fk(p["rot"], p["pos"])
    r, t = g[bone]
    return add(t, qrot(r, sub(local, R[bone])))


def hands_on_wheel(p, pre):
    """Mani sul cerchione della ruota del proprio lato, che spingono."""
    w = "Wheel.R" if pre == "C1." else "Wheel.L"
    s = 1 if pre == "C2." else -1
    c = world_of(p, "Carriage", WHEELS[w])
    for side, dz in (("L", 0.12), ("R", -0.12)):
        target = add(c, (s * 0.14 * S, WHEEL_R * 0.75, dz - 0.25 * S))
        M.ik_arm(side, target, (s * 1.0, -1.0, -0.3), p["rot"], p["pos"], prefix=pre)
        p["rot"][pre + "Hand." + side] = qe(x=-50)
    M.set_global_rot(TOOL[pre], qe(x=-15, z=-s * 70), p["rot"], p["pos"])   # attrezzo sotto il braccio


def wheels_roll(p, ang):
    for n in WHEELS:
        p["rot"][n] = qe(x=ang)


def moving(t, T, legs, knee, bob):
    p = new_pose()
    ph = 2 * math.pi * t / T
    for pre, off in (("C1.", 0.0), ("C2.", math.pi)):
        crew_legs(p, pre, ph + off, legs, knee, 22, bob, dx=(0.25 if pre == "C1." else -0.25) * S)
        hands_on_wheel(p, pre)
    wheels_roll(p, 180.0 * t / T)               # multiplo di 60°: ciclo senza scatti
    p["rot"]["Carriage"] = qe(z=0.6 * math.sin(2 * ph))
    return p


def walk(t): return moving(t, 1.2, 22, 34, 0.03)
def run(t): return moving(t, 0.85, 32, 52, 0.05)


def ram(p, insert):
    """Primo servente davanti alla bocca, girato verso il pezzo: spinge lo scovolo nell'anima."""
    m = world_of(p, "Barrel", MUZZLE_W)
    d = norm(sub(world_of(p, "Barrel", add(TRUNNION, (0, 0, BREECH_Z))), m))   # dalla bocca verso la culatta
    hand = add(m, mul(d, -RAM_UP + insert))
    hand = add(hand, (0.0, -0.03, 0.0))
    M.ik_arm("R", hand, (-1.0, -1.0, 0.5), p["rot"], p["pos"], prefix="C1.")
    M.set_global_rot("Prop.Rammer", qfromto(UP, d), p["rot"], p["pos"])
    M.ik_arm("L", add(hand, mul(d, 0.42)), (-0.5, -1.0, 0.2), p["rot"], p["pos"], prefix="C1.")


def touch_vent(p, k):
    """Il secondo servente allunga la miccia fino al focone."""
    v = world_of(p, "Barrel", VENT)
    sh = M.fk(p["rot"], p["pos"])["C2.UpperArm.R"][1]
    d = norm(add(sub(v, sh), (0, 0.55, 0)))
    hand = sub(v, mul(d, LIN_UP + 0.10))
    rest_hand = M.fk(p["rot"], p["pos"])["C2.Hand.R"][1]
    M.ik_arm("R", add(mul(rest_hand, 1 - k), mul(hand, k)), (0.5, -1.0, -0.6), p["rot"], p["pos"], prefix="C2.")
    M.set_global_rot("Prop.Linstock", qfromto(UP, add(mul(UP, 1 - k), mul(d, k))), p["rot"], p["pos"])


def shoot(t):
    # 0-0,3 miccia al focone · 0,3 sparo: lampo, fumo, rinculo · 0,8-2,3 scovolare e calcare ·
    # 2,3-3,6 riportare il pezzo in batteria · 3,6-4,2 di nuovo pronti
    p = idle(t)
    fire_t = 0.30
    # rinculo all'indietro, e poi in avanti mentre lo spingono
    back = seg(t, fire_t, fire_t + 0.16)
    fwd = seg(t, 2.5, 3.6)
    z = -RECOIL * back * (1 - fwd)
    p["pos"]["Carriage"] = add(M.rest_local("Carriage"), (0, 0.03 * S * math.sin(back * math.pi), z))
    wheels_roll(p, math.degrees(z / WHEEL_R))
    p["rot"]["Carriage"] = qe(x=-3.5 * math.sin(back * math.pi))
    p["rot"]["Barrel"] = qe(x=-2.0 - 2.0 * math.sin(back * math.pi))
    # lampo e fumo (il fumo resta dov'è stato sparato, sale e si dissolve)
    if fire_t <= t < fire_t + 0.10:
        p["scale"]["Prop.Flash"] = (1.0, 1.0, 1.0 + 4 * (t - fire_t))
    if fire_t <= t < 2.6:
        u = (t - fire_t) / (2.6 - fire_t)
        grow = lerp(0.35, 1.0, seg(u, 0.0, 0.12)) * (1.0 + 0.8 * u)
        fade = 1.0 - seg(u, 0.55, 1.0)
        sc = max(0.001, grow * fade)
        p["scale"]["Prop.Smoke"] = (sc, sc, sc)
        p["pos"]["Prop.Smoke"] = add(M.rest_local("Prop.Smoke"), (0.25 * u, 0.9 * u, 0.6 * u + 0.35 * seg(u, 0, 0.1)))
    # secondo servente: miccia al focone, poi si ritrae; più tardi spinge la ruota
    reach = seg(t, 0.0, 0.25) * (1 - seg(t, 0.40, 0.70))
    if reach > 0.0:
        p["rot"]["C2.Spine"] = qe(x=10 * reach, y=-20 * reach)
        crew_hips(p, "C2.", dx=-0.25 * reach, dz=0.05 * reach)
        touch_vent(p, reach)
    # primo servente: si tappa le orecchie, poi va davanti alla bocca a scovolare
    ears = seg(t, 0.05, 0.25) * (1 - seg(t, 0.55, 0.75))
    if ears > 0.0:
        p["rot"].update({"C1.UpperArm.L": qe(x=-30 * ears, z=5 + 95 * ears), "C1.LowerArm.L": qe(x=-140 * ears),
                         "C1.Spine": qe(x=10 * ears, y=15 * ears), "C1.Head": qe(x=12 * ears, z=-15 * ears)})
        hold_tool(p, "C1.")
    go = seg(t, 0.70, 1.00) * (1 - seg(t, 2.15, 2.45))
    if go > 0.0:
        m = world_of(p, "Barrel", MUZZLE_W)
        start = R["C1.Hips"]
        stand = add(m, (-0.38, 0.0, 1.15))
        dxz = sub(stand, start)
        crew_hips(p, "C1.", dx=dxz[0] * go, dz=dxz[2] * go, dy=-0.04 * go)
        p["rot"]["C1.Hips"] = qe(y=200 * go)
        p["rot"]["C1.UpperLeg.L"] = qe(x=-18 * go, z=4)
        p["rot"]["C1.LowerLeg.L"] = qe(x=16 * go)
        p["rot"]["C1.UpperLeg.R"] = qe(x=12 * go, z=-4)
        p["rot"]["C1.LowerLeg.R"] = qe(x=10 * go)
        p["rot"]["C1.Spine"] = qe(x=14 * go)
        if go > 0.999:
            # due colpi: scovolo (lana) e calcatoio
            ins = 0.55 * (math.sin(math.pi * seg(t, 1.05, 1.55)) + math.sin(math.pi * seg(t, 1.65, 2.10)))
            ram(p, ins)
            p["rot"]["C1.Spine"] = qe(x=14 + 12 * ins)
    # tutti e due spingono il pezzo in batteria
    pushk = seg(t, 2.45, 2.6) * (1 - seg(t, 3.6, 3.9))
    if pushk > 0.0:
        ph = 2 * math.pi * (t - 2.45) / 0.8
        for pre, off in (("C1.", 0.0), ("C2.", math.pi)):
            crew_legs(p, pre, ph + off, 16 * pushk, 26 * pushk, 26 * pushk, 0.02, dx=(0.25 if pre == "C1." else -0.25) * S * pushk,
                      dz=z + RECOIL * 0.0)
            hands_on_wheel(p, pre)
    return p


def attack(t):
    # i serventi si difendono menando colpi con scovolo e buttafuoco
    p = idle(0.0)
    for pre, d in (("C1.", 0.0), ("C2.", 0.15)):
        u = t - d
        wind = seg(u, 0.0, 0.3) * (1 - seg(u, 0.3, 0.45))
        hitk = seg(u, 0.3, 0.45) * (1 - seg(u, 0.65, 1.0))
        p["rot"].update({pre + "Spine": qe(x=-6 * wind + 16 * hitk, y=25 * wind - 25 * hitk),
                         pre + "Chest": qe(x=10 * hitk, y=15 * wind - 15 * hitk),
                         pre + "UpperLeg.L": qe(x=-25 * hitk), pre + "LowerLeg.L": qe(x=20 * hitk),
                         pre + "UpperLeg.R": qe(x=10 * hitk)})
        crew_hips(p, pre, dy=-0.04 * hitk, dz=0.12 * hitk)
        g = M.fk(p["rot"], p["pos"])
        cr, cp = g[pre + "Chest"]
        hand = add(cp, qrot(cr, (-0.15 - 0.15 * wind, 0.35 * wind + 0.05 * hitk, 0.10 + 0.35 * hitk)))
        M.ik_arm("R", hand, (-1.0, -0.5, -0.5), p["rot"], p["pos"], prefix=pre)
        M.ik_arm("L", add(hand, qrot(cr, (0.10, -0.25, 0.02))), (1.0, -1.0, 0.0), p["rot"], p["pos"], prefix=pre)
        M.set_global_rot(TOOL[pre], qmul(cr, qe(x=-30 * wind + 75 * hitk)), p["rot"], p["pos"])
    return p


def hit(t):
    p = idle(0.0)
    k = seg(t, 0.0, 0.08) * (1 - seg(t, 0.15, 0.6))
    w = math.sin(t * 40) * k
    p["rot"]["Carriage"] = qe(z=3 * w, x=-1.5 * k)
    for pre, s in (("C1.", 1), ("C2.", -1)):
        p["rot"].update({pre + "Spine": qe(x=-14 * k, z=6 * s * k), pre + "Head": qe(x=-18 * k),
                         pre + "UpperArm.L": qe(x=-30 * k, z=5 + 30 * k), pre + "LowerArm.L": qe(x=-40 * k)})
        crew_hips(p, pre, dz=-0.10 * k, dy=-0.03 * k)
        hold_tool(p, pre, tilt=6 - 20 * k)
    return p


def death(t):
    # una ruota cede, il pezzo si rovescia di lato col muso a terra; i serventi cadono
    p = idle(0.0)
    brk = seg(t, 0.05, 0.6)
    p["rot"]["Carriage"] = qe(z=16 * brk, x=8 * brk)
    p["pos"]["Carriage"] = add(M.rest_local("Carriage"), (0, -0.28 * S * brk, 0))
    p["rot"]["Wheel.R"] = qe(z=70 * seg(t, 0.1, 0.8))
    p["rot"]["Barrel"] = qe(x=10 * brk)
    for pre, back, d in (("C1.", True, 0.0), ("C2.", False, 0.15)):
        u = t - d
        buckle = seg(u, 0.1, 0.4)
        f = seg(u, 0.3, 1.0)
        sgn = -1 if back else 1
        p["rot"].update({pre + "Hips": qe(x=sgn * 85 * f),
                         pre + "UpperLeg.L": qe(x=-30 * buckle * (1 - f)), pre + "LowerLeg.L": qe(x=50 * buckle * (1 - 0.8 * f)),
                         pre + "UpperLeg.R": qe(x=-20 * buckle * (1 - f)), pre + "LowerLeg.R": qe(x=40 * buckle * (1 - 0.8 * f)),
                         pre + "UpperArm.L": qe(x=-60 * f, z=5 + 40 * f), pre + "UpperArm.R": qe(x=-60 * f, z=-8 - 40 * f),
                         pre + "Head": qe(x=sgn * -15 * f, y=20 * f)})
        crew_hips(p, pre, dy=-0.18 * buckle * (1 - f) - 0.82 * f, dz=sgn * 0.15 * f)
        M.set_global_rot(TOOL[pre], qe(x=6 + sgn * 80 * f, z=30 * f), p["rot"], p["pos"])
    return p


ANIMS = [
    ("Idle", idle, 3.2, True),
    ("Walk", walk, 1.2, True),
    ("Run", run, 0.85, True),
    ("Attack", attack, 1.1, False),
    ("Shoot", shoot, 4.2, False),
    ("HitRecieve", hit, 0.6, False),
    ("Death", death, 1.6, False),
]

if __name__ == "__main__":
    build_mesh()
    top = max(v[1] for v, j in zip(M.P, M.J) if not M.bones[j[0]][0].startswith("Prop."))
    print("altezza naturale: %.2f m (cuoci con --height=%.2f)" % (top, top))
    M.write(ANIMS, translated=["Root", "Carriage", "Prop.Smoke", "C1.Hips", "C2.Hips"], scaled=["Prop.Flash", "Prop.Smoke"])
