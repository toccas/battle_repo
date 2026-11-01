#!/usr/bin/env python3
"""Cavaliere e generale a cavallo, low-poly.

Uso (dalla cartella del progetto):
    python3 tools/modelli/genera_cavaliere.py            # tutti e due
    python3 tools/modelli/genera_cavaliere.py knight     # solo il cavaliere
    python3 tools/modelli/genera_cavaliere.py general    # solo il generale
Crea data/unithMesh/Units/Knight.gltf e General.gltf (con le tavolozze); poi si cuociono con
tools/vat_baker.tscn, assegnandoli a knights.tres e general.tres.

Cavaliere: elmo chiuso, sopravveste, scudo a mandorla, lancia con pennone; cavallo baio con gualdrappa.
Generale: armatura con fregi d'oro, corona sull'elmo e pennacchio, mantello, spada; cavallo bianco.
Il cavallo ha uno scheletro suo (corpo, collo, testa, quattro zampe, coda): passo a quattro tempi
e galoppo; il cavaliere è seduto in sella e segue il corpo del cavallo.
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lowpoly import Model, QI, add, sub, mul, norm, cross, qe, qmul, qrot, qfromto, qslerp, lerp, vlerp, seg  # noqa: E402

VARIANTS = {
    "knight": {
        "name": "Knight",
        "palette": [
            (238, 190, 152),  # 0 pelle
            (52, 84, 160),    # 1 sopravveste e gualdrappa
            (128, 132, 142),  # 2 maglia
            (196, 200, 208),  # 3 acciaio
            (118, 74, 38),    # 4 cuoio
            (62, 40, 24),     # 5 stivali e zoccoli
            (232, 226, 210),  # 6 bianco
            (220, 182, 70),   # 7 oro
            (22, 20, 20),     # 8 nero (feritoia, occhi)
            (120, 78, 46),    # 9 mantello del cavallo
            (52, 36, 26),     # 10 criniera
            (150, 104, 58),   # 11 legno
            (96, 100, 110),   # 12 acciaio scuro
            (176, 44, 40),    # 13 rosso
            (90, 60, 40),     # 14 muso
            (255, 255, 255),
        ],
        "weapon": "lance",
    },
    "general": {
        "name": "General",
        "palette": [
            (238, 190, 152),  # 0 pelle
            (150, 32, 40),    # 1 mantello, gualdrappa
            (128, 132, 142),  # 2 maglia
            (206, 210, 218),  # 3 acciaio
            (118, 74, 38),    # 4 cuoio
            (50, 34, 22),     # 5 stivali e zoccoli
            (240, 236, 224),  # 6 bianco
            (232, 190, 72),   # 7 oro
            (22, 20, 20),     # 8 nero
            (226, 222, 214),  # 9 mantello del cavallo (bianco)
            (190, 184, 172),  # 10 criniera
            (120, 80, 46),    # 11 legno
            (96, 100, 110),   # 12 acciaio scuro
            (176, 44, 40),    # 13 rosso (pennacchio)
            (150, 140, 132),  # 14 muso
            (255, 255, 255),
        ],
        "weapon": "sword",
    },
}
SKIN, CLOTH, MAIL, STEEL, LEATHER, BOOT, WHITE, GOLD, BLACK, COAT, MANE, WOOD, DARKSTEEL, RED, MUZZLE = range(15)

# ------------------------------------------------------------------ scheletro
HORSE = [
    ("Root", None, (0.0, 0.0, 0.0)),
    ("Horse.Body", "Root", (0.0, 1.25, 0.0)),
    ("Horse.Neck", "Horse.Body", (0.0, 1.45, 0.78)),
    ("Horse.Head", "Horse.Neck", (0.0, 1.98, 1.16)),
    ("Horse.Tail", "Horse.Body", (0.0, 1.45, -0.96)),
]
for side, x in (("L", 0.17), ("R", -0.17)):
    HORSE += [
        ("Horse.FrontUpper." + side, "Horse.Body", (x, 1.12, 0.66)),
        ("Horse.FrontLower." + side, "Horse.FrontUpper." + side, (x, 0.62, 0.70)),
        ("Horse.BackUpper." + side, "Horse.Body", (x, 1.20, -0.70)),
        ("Horse.BackLower." + side, "Horse.BackUpper." + side, (x, 0.60, -0.80)),
    ]
SEAT = (0.0, 0.72, -0.12)   # dal riferimento in piedi a quello in sella
HUMAN = [
    ("Hips", "Horse.Body", (0.0, 0.95, 0.0)), ("Spine", "Hips", (0.0, 1.08, 0.0)), ("Chest", "Spine", (0.0, 1.25, 0.0)),
    ("Head", "Chest", (0.0, 1.50, 0.0)),
    ("UpperArm.L", "Chest", (0.26, 1.42, 0.0)), ("LowerArm.L", "UpperArm.L", (0.28, 1.14, 0.0)),
    ("Hand.L", "LowerArm.L", (0.29, 0.88, 0.0)),
    ("UpperArm.R", "Chest", (-0.26, 1.42, 0.0)), ("LowerArm.R", "UpperArm.R", (-0.28, 1.14, 0.0)),
    ("Hand.R", "LowerArm.R", (-0.29, 0.88, 0.0)),
    ("UpperLeg.L", "Hips", (0.10, 0.92, 0.0)), ("LowerLeg.L", "UpperLeg.L", (0.10, 0.50, 0.0)),
    ("UpperLeg.R", "Hips", (-0.10, 0.92, 0.0)), ("LowerLeg.R", "UpperLeg.R", (-0.10, 0.50, 0.0)),
]
RP = "Rider."


def make_bones(weapon):
    b = list(HORSE)
    for n, parent, p in HUMAN:
        b.append((RP + n, parent if parent.startswith("Horse") else RP + parent, add(p, SEAT)))
    hand = add((-0.29, 0.84, 0.0), SEAT)
    b.append(("Lance" if weapon == "lance" else "Sword", RP + "Hand.R", hand))
    b.append(("Shield", RP + "LowerArm.L", add((0.31, 1.01, 0.0), SEAT)))
    return b


M = None
R = None
V = None
FWD = (0.0, 0.0, 1.0)
UP = (0.0, 1.0, 0.0)
LANCE_BACK, LANCE_FRONT = 0.75, 2.85
BLADE = 0.85


# ------------------------------------------------------------------ geometria
def plate(poly, center, u, v, n, thick, color, bone):
    """Lastra dal contorno convesso poly (coordinate (a, b) sugli assi u, v), spessa thick lungo n."""
    a = sub(add(mul(u, poly[1][0]), mul(v, poly[1][1])), add(mul(u, poly[0][0]), mul(v, poly[0][1])))
    b = sub(add(mul(u, poly[2][0]), mul(v, poly[2][1])), add(mul(u, poly[0][0]), mul(v, poly[0][1])))
    c = cross(a, b)
    if c[0] * n[0] + c[1] * n[1] + c[2] * n[2] < 0:
        poly = poly[::-1]
    front = [add(center, add(add(mul(u, x), mul(v, y)), mul(n, thick * 0.5))) for x, y in poly]
    back = [add(center, add(add(mul(u, x), mul(v, y)), mul(n, -thick * 0.5))) for x, y in poly]
    cf, cb = add(center, mul(n, thick * 0.5)), add(center, mul(n, -thick * 0.5))
    k = len(poly)
    for i in range(k):
        j = (i + 1) % k
        M.tri(cf, front[i], front[j], color, bone)
        M.tri(cb, back[j], back[i], color, bone)
        M.quad(front[j], front[i], back[i], back[j], color, bone)


def build_horse():
    box, limb, prism = M.box, M.limb, M.prism
    B = "Horse.Body"
    box((0, 1.25, 0.0), (0.52, 0.60, 1.30), COAT, B, taper=(1.0, 1.0))                  # tronco
    box((0, 1.30, 0.70), (0.48, 0.58, 0.36), COAT, B, taper=(0.9, 0.9), shift=(0, 0.03))  # petto
    box((0, 1.32, -0.74), (0.54, 0.56, 0.42), COAT, B, taper=(0.85, 0.9))                 # groppa
    # gualdrappa sui fianchi e sella
    for x in (0.285, -0.285):
        box((x, 1.18, 0.0), (0.02, 0.62, 1.55), CLOTH, B)
        box((x, 0.88, 0.0), (0.024, 0.05, 1.56), GOLD, B)                                    # orlo
    box((0, 1.56, -0.02), (0.56, 0.04, 1.0), CLOTH, B)
    box((0, 1.60, -0.10), (0.36, 0.06, 0.58), LEATHER, B)                                    # sella
    box((0, 1.68, -0.38), (0.32, 0.14, 0.06), LEATHER, B)                                    # arcione dietro
    box((0, 1.66, 0.18), (0.22, 0.10, 0.06), LEATHER, B)                                     # arcione davanti
    for x in (0.27, -0.27):
        limb((x, 1.58, 0.05), (x * 1.18, 1.05, 0.12), 0.03, 0.01, LEATHER, B)                # staffili
        box((x * 1.18, 1.02, 0.12), (0.06, 0.03, 0.12), STEEL, B)                           # staffe
    # collo e criniera
    N = "Horse.Neck"
    limb((0, 1.38, 0.72), (0, 1.98, 1.14), 0.26, 0.38, COAT, N, taper=0.72, side_hint=(1, 0, 0))
    limb((0, 1.66, 0.70), (0, 2.12, 1.08), 0.06, 0.14, MANE, N, taper=0.8, side_hint=(1, 0, 0))
    # testa: cranio, muso, orecchie, occhi, briglie
    H = "Horse.Head"
    limb((0, 2.05, 1.10), (0, 1.74, 1.60), 0.21, 0.26, COAT, H, taper=0.72, side_hint=(1, 0, 0))
    limb((0, 1.82, 1.48), (0, 1.70, 1.66), 0.15, 0.16, MUZZLE, H, taper=0.9, side_hint=(1, 0, 0))
    for s in (1, -1):
        limb((0.06 * s, 2.10, 1.10), (0.08 * s, 2.24, 1.06), 0.05, 0.035, COAT, H, taper=0.3)
        box((0.105 * s, 2.0, 1.24), (0.012, 0.035, 0.05), BLACK, H)
        limb((0.10 * s, 2.02, 1.12), (0.08 * s, 1.74, 1.52), 0.012, 0.03, LEATHER, H)       # briglia
    box((0, 2.11, 1.08), (0.10, 0.06, 0.14), MANE, H)                                         # ciuffo
    limb((0.08, 1.76, 1.50), (0.22, 1.66, 0.62), 0.015, 0.015, LEATHER, H)                   # redini (fino al collo)
    limb((-0.08, 1.76, 1.50), (-0.12, 1.66, 0.62), 0.015, 0.015, LEATHER, H)
    # zampe
    for side, x in (("L", 0.17), ("R", -0.17)):
        fu, fl = "Horse.FrontUpper." + side, "Horse.FrontLower." + side
        bu, bl = "Horse.BackUpper." + side, "Horse.BackLower." + side
        limb(R[fu], R[fl], 0.15, 0.22, COAT, fu, taper=0.65, side_hint=(1, 0, 0))
        limb(R[fl], (x, 0.10, 0.72), 0.085, 0.10, COAT, fl, taper=0.9, side_hint=(1, 0, 0))
        box((x, 0.05, 0.74), (0.11, 0.10, 0.13), BOOT, fl, taper=(1.1, 0.95))
        limb(add(R[bu], (0, 0.08, 0.04)), R[bl], 0.20, 0.34, COAT, bu, taper=0.55, side_hint=(1, 0, 0))
        limb(R[bl], (x, 0.10, -0.74), 0.085, 0.10, COAT, bl, taper=0.9, side_hint=(1, 0, 0))
        box((x, 0.05, -0.73), (0.11, 0.10, 0.13), BOOT, bl, taper=(1.1, 0.95))
    T = "Horse.Tail"
    limb((0, 1.48, -0.94), (0, 1.25, -1.10), 0.10, 0.10, MANE, T)
    limb((0, 1.25, -1.10), (0, 0.80, -1.16), 0.13, 0.08, MANE, T, taper=0.6)


def rider_pt(x, y, z): return add((x, y, z), SEAT)


def build_rider():
    box, limb, prism = M.box, M.limb, M.prism
    gen = V["weapon"] == "sword"
    def B(n): return RP + n
    for s, up, lo in ((1, "UpperLeg.L", "LowerLeg.L"), (-1, "UpperLeg.R", "LowerLeg.R")):
        x = 0.10 * s
        box(rider_pt(x, 0.71, 0), (0.155, 0.44, 0.165), MAIL if not gen else STEEL, B(up), taper=(1.1, 1.05))
        box(rider_pt(x, 0.31, 0), (0.135, 0.40, 0.145), MAIL if not gen else STEEL, B(lo), taper=(1.12, 1.1))
        box(rider_pt(x, 0.50, 0.075), (0.11, 0.10, 0.05), STEEL if not gen else GOLD, B(lo), taper=(0.8, 0.8))
        box(rider_pt(x, 0.13, 0), (0.14, 0.20, 0.155), BOOT, B(lo))
        box(rider_pt(x, 0.04, 0.05), (0.14, 0.08, 0.25), BOOT, B(lo), taper=(1.0, 0.85), shift=(0, -0.02))
    box(rider_pt(0, 0.86, 0), (0.40, 0.22, 0.25), MAIL, B("Hips"), taper=(0.9, 0.92))
    if gen:
        box(rider_pt(0, 1.08, 0), (0.36, 0.22, 0.24), STEEL, B("Spine"), taper=(1.06, 1.0))
        box(rider_pt(0, 1.31, 0), (0.42, 0.32, 0.25), STEEL, B("Chest"), taper=(1.06, 0.95))
        box(rider_pt(0, 1.30, 0.126), (0.30, 0.03, 0.01), GOLD, B("Chest"))
        box(rider_pt(0, 1.19, 0.12), (0.30, 0.03, 0.01), GOLD, B("Spine"))
        box(rider_pt(0, 1.38, 0.13), (0.10, 0.10, 0.01), GOLD, B("Chest"))                    # stemma
        box(rider_pt(0, 0.86, 0.125), (0.30, 0.20, 0.012), CLOTH, B("Hips"))
        # mantello dalle spalle fino alla groppa
        box(rider_pt(0, 1.18, -0.15), (0.44, 0.64, 0.03), CLOTH, B("Chest"), taper=(0.85, 1.0), shift=(0, 0.02))
        box(rider_pt(0, 1.46, -0.10), (0.46, 0.06, 0.12), GOLD, B("Chest"))
    else:
        box(rider_pt(0, 1.07, 0), (0.35, 0.21, 0.22), MAIL, B("Spine"), taper=(1.06, 1.0))
        box(rider_pt(0, 1.31, 0), (0.41, 0.32, 0.235), MAIL, B("Chest"), taper=(1.06, 0.95))
        box(rider_pt(0, 1.29, 0), (0.39, 0.34, 0.245), CLOTH, B("Chest"), taper=(1.02, 0.96))
        box(rider_pt(0, 1.07, 0), (0.355, 0.20, 0.232), CLOTH, B("Spine"), taper=(1.07, 1.0))
        box(rider_pt(0, 0.80, 0.0), (0.37, 0.24, 0.26), CLOTH, B("Hips"), taper=(1.1, 1.0))
        box(rider_pt(0, 1.30, 0.124), (0.05, 0.24, 0.006), WHITE, B("Chest"))
        box(rider_pt(0, 1.35, 0.124), (0.18, 0.05, 0.006), WHITE, B("Chest"))
    box(rider_pt(0, 0.95, 0), (0.39, 0.06, 0.26), LEATHER, B("Hips"))
    # elmo
    box(rider_pt(0, 1.54, 0), (0.12, 0.08, 0.12), MAIL, B("Head"))
    box(rider_pt(0, 1.67, 0.005), (0.265, 0.30, 0.27), STEEL, B("Head"), taper=(0.94, 0.94))
    box(rider_pt(0, 1.705, 0.138), (0.22, 0.022, 0.012), BLACK, B("Head"))
    box(rider_pt(0, 1.655, 0.140), (0.035, 0.30, 0.014), GOLD if gen else DARKSTEEL, B("Head"))
    if gen:
        for k in range(8):   # corona
            a = 2 * math.pi * k / 8
            c = rider_pt(0.13 * math.sin(a), 1.85, 0.005 + 0.13 * math.cos(a))
            box(c, (0.06, 0.06, 0.06), GOLD, B("Head"), taper=(0.3, 0.3))
        box(rider_pt(0, 1.825, 0.005), (0.28, 0.04, 0.28), GOLD, B("Head"))
        limb(rider_pt(0, 1.84, -0.02), rider_pt(0, 2.08, -0.14), 0.07, 0.10, RED, B("Head"), taper=1.4)      # pennacchio
        limb(rider_pt(0, 2.08, -0.14), rider_pt(0, 2.02, -0.42), 0.10, 0.12, RED, B("Head"), taper=0.2)
    else:
        box(rider_pt(0, 1.83, 0.005), (0.25, 0.03, 0.255), DARKSTEEL, B("Head"))
    # braccia
    for s, ua, la, ha in ((1, "UpperArm.L", "LowerArm.L", "Hand.L"), (-1, "UpperArm.R", "LowerArm.R", "Hand.R")):
        sh, el, wr = R[B(ua)], R[B(la)], R[B(ha)]
        limb(add(sh, (0, 0.05, 0)), el, 0.13, 0.13, STEEL if gen else MAIL, B(ua), taper=0.9)
        limb(add(el, (0, 0.03, 0)), add(wr, (0, 0.04, 0)), 0.11, 0.11, STEEL if gen else MAIL, B(la), taper=0.9)
        box(add(sh, (0.02 * s, 0.02, 0)), (0.17, 0.10, 0.19), GOLD if gen else STEEL, B(ua), taper=(0.75, 0.85), shift=(-0.02 * s, 0))
        box(el, (0.12, 0.08, 0.12), STEEL, B(la))
        limb(add(wr, (0, 0.09, 0)), add(wr, (0, -0.01, 0)), 0.12, 0.12, LEATHER, B(la), taper=1.1)
        limb(wr, add(wr, (0.003 * s, -0.10, 0.0)), 0.09, 0.09, LEATHER, B(ha), taper=0.85)
    # scudo a mandorla sull'avambraccio sinistro
    c = R["Shield"]
    u, v, n = UP, FWD, (1.0, 0.0, 0.0)
    shape = [(0.30, 0.0), (0.27, 0.15), (0.16, 0.22), (-0.05, 0.20), (-0.28, 0.12), (-0.48, 0.0),
             (-0.28, -0.12), (-0.05, -0.20), (0.16, -0.22), (0.27, -0.15)]
    sc = 0.85 if gen else 1.0
    shape = [(a * sc, b * sc) for a, b in shape]
    plate([(a * 1.06, b * 1.06) for a, b in shape], add(c, (0.035, 0, 0)), u, v, n, 0.02, GOLD if gen else DARKSTEEL, "Shield")
    plate(shape, add(c, (0.055, 0, 0)), u, v, n, 0.03, CLOTH, "Shield")
    f = add(c, (0.072, 0, 0))
    if gen:
        box(add(f, (0.004, 0.0, 0.0)), (0.01, 0.16, 0.16), GOLD, "Shield", taper=(1.0, 0.4))
    else:
        box(add(f, (0.004, -0.06, 0.0)), (0.01, 0.62, 0.06), WHITE, "Shield")
        box(add(f, (0.004, 0.08, 0.0)), (0.01, 0.06, 0.30), WHITE, "Shield")
    box(add(c, (-0.01, 0, 0)), (0.03, 0.10, 0.30), LEATHER, "Shield")
    # arma
    if V["weapon"] == "lance":
        g = R["Lance"]
        prism(add(g, (0, -LANCE_BACK, 0)), add(g, (0, LANCE_FRONT - 0.25, 0)), 0.035, 0.022, 6, WOOD, "Lance")
        prism(add(g, (0, 0.05, 0)), add(g, (0, 0.22, 0)), 0.09, 0.035, 8, STEEL, "Lance")                   # rotella
        limb(add(g, (0, LANCE_FRONT - 0.25, 0)), add(g, (0, LANCE_FRONT, 0)), 0.05, 0.05, STEEL, "Lance", taper=0.05)
        for k in range(3):   # pennone a due code
            y0 = LANCE_FRONT - 0.45 - k * 0.0
            M.tri(add(g, (0.0, y0, 0.0)), add(g, (0.0, y0 - 0.22, 0.0)), add(g, (0.0, y0 - 0.06, -0.45)), WHITE if k == 0 else CLOTH, "Lance")
            M.tri(add(g, (0.0, y0, 0.0)), add(g, (0.0, y0 - 0.06, -0.45)), add(g, (0.0, y0 - 0.22, 0.0)), WHITE if k == 0 else CLOTH, "Lance")
    else:
        g = R["Sword"]
        limb(add(g, (0, 0, -0.10)), add(g, (0, 0, 0.06)), 0.035, 0.035, LEATHER, "Sword")
        prism(add(g, (0, 0, -0.14)), add(g, (0, 0, -0.10)), 0.04, 0.04, 6, GOLD, "Sword")
        limb(add(g, (-0.13, 0, 0.075)), add(g, (0.13, 0, 0.075)), 0.035, 0.035, GOLD, "Sword")
        limb(add(g, (0, 0, 0.09)), add(g, (0, 0, 0.09 + BLADE - 0.12)), 0.06, 0.012, STEEL, "Sword", side_hint=(0, 1, 0))
        limb(add(g, (0, 0, 0.09 + BLADE - 0.12)), add(g, (0, 0, 0.09 + BLADE)), 0.06, 0.012, STEEL, "Sword", taper=0.05, side_hint=(0, 1, 0))


# ------------------------------------------------------------------ pose
def new_pose():
    return {"rot": {}, "pos": {}, "scale": {}}


def legs_horse(p, phases, T, t, amp_f, amp_b, lift_f, lift_b):
    """Zampe: phases = sfasamento (0-1) di ogni zampa nel ciclo."""
    for leg, off in phases.items():
        ph = 2 * math.pi * (t / T - off)
        front = "Front" in leg
        amp = amp_f if front else amp_b
        lift = lift_f if front else lift_b
        swing = -amp * math.sin(ph)                    # negativo = avanti
        bend = lift * max(0.0, math.cos(ph)) ** 1.5    # si piega mentre la zampa torna avanti
        up, lo = leg, leg.replace("Upper", "Lower")
        if front:
            p["rot"][up] = qe(x=swing - 0.3 * bend)
            p["rot"][lo] = qe(x=bend)
        else:
            p["rot"][up] = qe(x=swing + 0.35 * bend)
            p["rot"][lo] = qe(x=-0.5 * bend + 8 * math.sin(ph) + 6)


def body(p, dy=0.0, pitch=0.0, roll=0.0):
    p["pos"]["Horse.Body"] = add(M.rest_local("Horse.Body"), (0, dy, 0))
    p["rot"]["Horse.Body"] = qe(x=pitch, z=roll)


def seated(p, lean=0.0, rise=0.0):
    """Cavaliere in sella: cosce divaricate attorno al cavallo, gambe giù lungo i fianchi."""
    p["rot"].update({RP + "UpperLeg.L": qe(x=-62, z=24), RP + "LowerLeg.L": qe(x=68),
                     RP + "UpperLeg.R": qe(x=-62, z=-24), RP + "LowerLeg.R": qe(x=68),
                     RP + "Spine": qe(x=lean * 0.5), RP + "Chest": qe(x=lean * 0.5), RP + "Head": qe(x=-lean * 0.8)})
    p["pos"][RP + "Hips"] = add(M.rest_local(RP + "Hips"), (0, rise, 0))


def reins(p):
    g = M.fk(p["rot"], p["pos"])
    br, bp = g["Horse.Body"]
    target = add(bp, qrot(br, (0.10, 0.58, 0.40)))
    M.ik_arm("L", target, qrot(br, (1.0, -0.6, -0.4)), p["rot"], p["pos"], prefix=RP)
    p["rot"][RP + "Hand.L"] = qe(x=-40)


def weapon_dir(p, d_world, rest_axis):
    name = "Lance" if V["weapon"] == "lance" else "Sword"
    M.set_global_rot(name, qfromto(rest_axis, norm(d_world)), p["rot"], p["pos"])


def hold_upright(p, sway=0.0):
    """Lancia dritta (o spada alzata) nella destra."""
    g = M.fk(p["rot"], p["pos"])
    cr, cp = g[RP + "Chest"]
    if V["weapon"] == "lance":
        hand = add(cp, qrot(cr, (-0.30, -0.28, 0.16)))
        M.ik_arm("R", hand, qrot(cr, (-1.0, -0.8, -0.2)), p["rot"], p["pos"], prefix=RP)
        p["rot"][RP + "Hand.R"] = QI
        weapon_dir(p, (0.02, 1.0, 0.10 + sway), UP)
    else:
        hand = add(cp, qrot(cr, (-0.30, 0.02, 0.22)))
        M.ik_arm("R", hand, qrot(cr, (-1.0, -0.8, -0.2)), p["rot"], p["pos"], prefix=RP)
        p["rot"][RP + "Hand.R"] = QI
        weapon_dir(p, (-0.05, 1.0, 0.35 + sway), FWD)


def couched(p, thrust=0.0):
    """Carica: lancia in resta (o spada tesa in avanti)."""
    g = M.fk(p["rot"], p["pos"])
    cr, cp = g[RP + "Chest"]
    if V["weapon"] == "lance":
        hand = add(cp, qrot(cr, (-0.24, -0.20, 0.10 + 0.45 * thrust)))
        M.ik_arm("R", hand, qrot(cr, (-1.0, -0.6, -0.5)), p["rot"], p["pos"], prefix=RP)
        p["rot"][RP + "Hand.R"] = QI
        weapon_dir(p, (0.10, -0.06 - 0.06 * thrust, 1.0), UP)
    else:
        hand = add(cp, qrot(cr, (-0.28, 0.25, 0.42)))
        M.ik_arm("R", hand, qrot(cr, (-1.0, -0.5, -0.3)), p["rot"], p["pos"], prefix=RP)
        p["rot"][RP + "Hand.R"] = QI
        weapon_dir(p, (-0.05, 0.25, 1.0), FWD)


def idle(t, T=3.0):
    p = new_pose()
    b = math.sin(2 * math.pi * t / T)
    legs_horse(p, {}, T, t, 0, 0, 0, 0)
    body(p, dy=0.008 * b)
    p["rot"].update({"Horse.Neck": qe(x=4 * b), "Horse.Head": qe(x=-3 * b, y=8 * math.sin(math.pi * t / T)),
                     "Horse.Tail": qe(z=10 * math.sin(2 * math.pi * t / 1.5), x=5),
                     "Horse.BackLower.R": qe(x=8 + 6 * max(0.0, math.sin(2 * math.pi * t / T)))})   # sposta il peso
    seated(p)
    p["rot"][RP + "Head"] = qe(y=10 * math.sin(math.pi * t / T))
    reins(p)
    hold_upright(p)
    return p


WALK_PH = {"Horse.BackUpper.L": 0.0, "Horse.FrontUpper.L": 0.25, "Horse.BackUpper.R": 0.5, "Horse.FrontUpper.R": 0.75}
GALLOP_PH = {"Horse.BackUpper.L": 0.0, "Horse.BackUpper.R": 0.1, "Horse.FrontUpper.L": 0.45, "Horse.FrontUpper.R": 0.55}


def walk(t, T=1.2):
    p = new_pose()
    ph = 2 * math.pi * t / T
    legs_horse(p, WALK_PH, T, t, 18, 16, 45, 40)
    body(p, dy=0.02 * math.sin(2 * ph), pitch=1.0 * math.sin(2 * ph), roll=1.2 * math.sin(ph))
    p["rot"].update({"Horse.Neck": qe(x=5 * math.sin(2 * ph)), "Horse.Head": qe(x=-4 * math.sin(2 * ph)),
                     "Horse.Tail": qe(z=6 * math.sin(ph), x=8)})
    seated(p)
    p["rot"][RP + "Spine"] = qe(z=-1.5 * math.sin(ph))
    reins(p)
    hold_upright(p, sway=0.03 * math.sin(ph))
    return p


def run(t, T=0.6):
    p = new_pose()
    ph = 2 * math.pi * t / T
    legs_horse(p, GALLOP_PH, T, t, 34, 32, 80, 60)
    body(p, dy=0.07 * math.sin(ph + 0.6), pitch=4.0 * math.sin(ph + 1.2))
    p["rot"].update({"Horse.Neck": qe(x=-8 + 9 * math.sin(ph + 2.0)), "Horse.Head": qe(x=12 - 5 * math.sin(ph + 2.0)),
                     "Horse.Tail": qe(x=40 + 8 * math.sin(ph))})
    seated(p, lean=12, rise=0.04 + 0.03 * math.sin(ph + 2.5))
    reins(p)
    couched(p)
    return p


GEN_SLASH = [  # fendente del generale: mano e direzione della lama nel riferimento del petto
    (0.00, (-0.30, 0.02, 0.22), (-0.05, 1.0, 0.35)),
    (0.32, (-0.32, 0.42, -0.04), (-0.30, 0.55, -0.80)),
    (0.45, (-0.32, 0.20, 0.40), (-0.20, 0.35, 1.0)),
    (0.56, (-0.40, -0.18, 0.40), (-0.50, -0.65, 0.60)),
    (0.66, (-0.42, -0.32, 0.22), (-0.55, -0.80, 0.10)),
    (1.00, (-0.30, 0.02, 0.22), (-0.05, 1.0, 0.35)),
]


def attack(t):
    p = new_pose()
    hit_k = seg(t, 0.30, 0.48) * (1 - seg(t, 0.6, 1.0))
    # il cavallo si slancia in avanti e scalpita
    legs_horse(p, {}, 1.0, t, 0, 0, 0, 0)
    rear = math.sin(seg(t, 0.0, 0.7) * math.pi)
    body(p, dy=0.06 * rear, pitch=-6 * rear)
    p["rot"].update({"Horse.FrontUpper.L": qe(x=-35 * rear), "Horse.FrontLower.L": qe(x=70 * rear),
                     "Horse.FrontUpper.R": qe(x=-20 * rear), "Horse.FrontLower.R": qe(x=50 * rear),
                     "Horse.BackUpper.L": qe(x=8 * rear), "Horse.BackUpper.R": qe(x=8 * rear),
                     "Horse.Neck": qe(x=-14 * rear), "Horse.Head": qe(x=10 * rear), "Horse.Tail": qe(x=20 * rear)})
    seated(p, lean=10 * hit_k)
    reins(p)
    if V["weapon"] == "lance":
        lower = seg(t, 0.0, 0.25) * (1 - seg(t, 0.75, 1.0))
        thr = math.sin(seg(t, 0.25, 0.65) * math.pi)
        p["rot"][RP + "Chest"] = qe(x=6 * thr, y=-12 * thr)
        up = new_pose()
        up["rot"].update(p["rot"])
        up["pos"].update(p["pos"])
        hold_upright(up)
        couched(p, thrust=thr)
        for b in (RP + "UpperArm.R", RP + "LowerArm.R", RP + "Hand.R", "Lance"):
            p["rot"][b] = qslerp(up["rot"][b], p["rot"][b], lower)
    else:
        for (t0, h0, d0), (t1, h1, d1) in zip(GEN_SLASH, GEN_SLASH[1:]):
            if t <= t1:
                k = seg(t, t0, t1)
                hand_c, dir_c = vlerp(h0, h1, k), norm(vlerp(norm(d0), norm(d1), k))
                break
        else:
            hand_c, dir_c = GEN_SLASH[-1][1], norm(GEN_SLASH[-1][2])
        p["rot"][RP + "Chest"] = qe(y=lerp(0, 20, seg(t, 0.0, 0.32)) - 40 * hit_k)
        cr, cp = M.fk(p["rot"], p["pos"])[RP + "Chest"]
        M.ik_arm("R", add(cp, qrot(cr, hand_c)), qrot(cr, (-1.0, -0.5, -0.3)), p["rot"], p["pos"], prefix=RP)
        p["rot"][RP + "Hand.R"] = QI
        weapon_dir(p, qrot(cr, dir_c), FWD)
    return p


def hit(t):
    p = idle(0.0)
    k = seg(t, 0.0, 0.1) * (1 - seg(t, 0.2, 0.7))
    body(p, dy=0.02 * k, pitch=-4 * k, roll=4 * k)
    p["rot"].update({"Horse.Neck": qe(x=-18 * k, z=8 * k), "Horse.Head": qe(x=-10 * k),
                     "Horse.FrontUpper.L": qe(x=-15 * k), "Horse.FrontLower.L": qe(x=40 * k)})
    p["rot"][RP + "Spine"] = qe(x=-12 * k)
    p["rot"][RP + "Chest"] = qe(x=-10 * k)
    p["rot"][RP + "Head"] = qe(x=-15 * k)
    reins(p)
    hold_upright(p, sway=-0.4 * k)
    return p


def death(t):
    # il cavallo piega le zampe anteriori e si rovescia su un fianco col cavaliere
    p = idle(0.0)
    kneel = seg(t, 0.0, 0.45)
    fall = seg(t, 0.35, 1.15)
    p["rot"]["Root"] = qe(z=84 * fall)
    p["pos"]["Root"] = (0.36 * fall, 0.30 * fall, 0.0)
    body(p, dy=-0.30 * kneel * (1 - fall), pitch=10 * kneel * (1 - fall))
    p["rot"].update({"Horse.FrontUpper.L": qe(x=30 * kneel - 30 * fall), "Horse.FrontLower.L": qe(x=100 * kneel * (1 - 0.5 * fall)),
                     "Horse.FrontUpper.R": qe(x=30 * kneel - 20 * fall), "Horse.FrontLower.R": qe(x=100 * kneel * (1 - 0.6 * fall)),
                     "Horse.BackUpper.L": qe(x=-10 * kneel + 25 * fall), "Horse.BackLower.L": qe(x=-30 * fall),
                     "Horse.BackUpper.R": qe(x=-10 * kneel + 15 * fall), "Horse.BackLower.R": qe(x=-20 * fall),
                     "Horse.Neck": qe(x=20 * kneel - 10 * fall, z=-20 * fall), "Horse.Head": qe(x=-10 * fall),
                     "Horse.Tail": qe(x=-5)})
    seated(p)
    p["rot"][RP + "Spine"] = qe(x=-15 * fall, z=-20 * fall)
    p["rot"][RP + "Head"] = qe(x=-20 * fall)
    p["rot"][RP + "UpperArm.L"] = qe(x=-40 * fall, z=30 + 30 * fall)
    p["rot"][RP + "UpperArm.R"] = qe(x=-60 * fall, z=-30 - 40 * fall)
    p["rot"][RP + "LowerArm.L"] = qe(x=-20)
    p["rot"][RP + "LowerArm.R"] = qe(x=-20)
    name = "Lance" if V["weapon"] == "lance" else "Sword"
    p["rot"][name] = qmul(p["rot"].get(name, QI), qe(x=60 * fall))
    return p


ANIMS = [
    ("Idle", idle, 3.0, True),
    ("Walk", walk, 1.2, True),
    ("Run", run, 0.6, True),
    ("Attack", attack, 1.0, False),
    ("HitRecieve", hit, 0.7, False),
    ("Death", death, 1.5, False),
]


def make(variant):
    global M, R, V
    V = VARIANTS[variant]
    M = Model(V["name"], make_bones(V["weapon"]), V["palette"])
    R = M.rest
    build_horse()
    build_rider()
    M.write(ANIMS, translated=["Root", "Horse.Body", RP + "Hips"])


if __name__ == "__main__":
    for v in (sys.argv[1:] or ["knight", "general"]):
        make(v)
