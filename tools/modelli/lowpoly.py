"""Strumenti comuni per i soldati low-poly generati da codice (vedi genera_lanciere.py).

Ogni modello: uno scheletro (posa a riposo con sole traslazioni), pezzi rigidi legati alle ossa,
una tavolozza 4x4 come texture e un'animazione per stato, scritti in un .gltf in stile Quaternius
(guarda verso +Z, piedi a y = 0). Si cuoce poi con tools/vat_baker.tscn.
"""
import base64
import json
import math
import os
import struct
import zlib

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
OUT_DIR = os.path.join(ROOT, "data", "unithMesh", "Units")


# ------------------------------------------------------------------ vettori e quaternioni
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
    """Gradi: prima rollio (Z), poi beccheggio (X), poi imbardata (Y).
    Il modello guarda +Z: x negativo porta in avanti braccia e gambe, x positivo piega le ginocchia."""
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


# ------------------------------------------------------------------ modello
class Model:
    def __init__(self, name, bones, palette):
        """bones: lista di (nome, genitore, posizione nel modello); palette: 16 colori RGB."""
        self.name = name
        self.bones = bones
        self.palette = palette
        self.bi = {b[0]: i for i, b in enumerate(bones)}
        self.parent = {b[0]: b[1] for b in bones}
        self.rest = {b[0]: b[2] for b in bones}
        self.P, self.N, self.UV, self.J, self.W = [], [], [], [], []

    def rest_local(self, name):
        p = self.parent[name]
        return self.rest[name] if p is None else sub(self.rest[name], self.rest[p])

    # -------------------------------------------------------------- geometria
    @staticmethod
    def uv_of(c):
        return ((c % 4 + 0.5) / 4.0, (c // 4 + 0.5) / 4.0)

    def tri(self, a, b, c, color, bones):
        """bones: un nome di osso, oppure per vertice una lista [(osso, peso)]."""
        n = norm(cross(sub(b, a), sub(c, a)))
        for k, v in enumerate((a, b, c)):
            self.P.append(v)
            self.N.append(n)
            self.UV.append(self.uv_of(color))
            bw = bones[k] if isinstance(bones, list) else [(bones, 1.0)]
            self.J.append([self.bi[x[0]] for x in bw] + [0] * (4 - len(bw)))
            self.W.append([x[1] for x in bw] + [0.0] * (4 - len(bw)))

    def quad(self, a, b, c, d, color, bones):
        if isinstance(bones, list):
            self.tri(a, b, c, color, [bones[0], bones[1], bones[2]])
            self.tri(a, c, d, color, [bones[0], bones[2], bones[3]])
        else:
            self.tri(a, b, c, color, bones)
            self.tri(a, c, d, color, bones)

    def hexa(self, c, color, bone):
        """c: 8 angoli, 0-3 sotto (in senso orario visto dall'alto), 4-7 sopra."""
        self.quad(c[0], c[1], c[2], c[3], color, bone)
        self.quad(c[4], c[7], c[6], c[5], color, bone)
        for i in range(4):
            j = (i + 1) % 4
            self.quad(c[i], c[i + 4], c[j + 4], c[j], color, bone)

    def box(self, center, size, color, bone, taper=(1.0, 1.0), shift=(0.0, 0.0)):
        """Scatola allineata agli assi; taper e shift modificano la faccia superiore (x, z)."""
        cx, cy, cz = center
        hx, hy, hz = size[0] / 2, size[1] / 2, size[2] / 2
        bot = [(-1, -1), (1, -1), (1, 1), (-1, 1)]
        c = [(cx + sx * hx, cy - hy, cz + sz * hz) for sx, sz in bot]
        c += [(cx + shift[0] + sx * hx * taper[0], cy + hy, cz + shift[1] + sz * hz * taper[1]) for sx, sz in bot]
        self.hexa(c, color, bone)

    def limb(self, p0, p1, w, d, color, bone, taper=1.0, side_hint=(1, 0, 0)):
        """Scatola orientata da p0 a p1 (sezione w x d; in cima scalata di taper)."""
        a = norm(sub(p1, p0))
        t = norm(cross(side_hint, a))
        if length(t) < 1e-6:
            t = norm(cross((0, 0, 1), a))
        s = norm(cross(a, t))
        corners = []
        for p, k in ((p0, 1.0), (p1, taper)):
            for sx, sz in [(-1, -1), (-1, 1), (1, 1), (1, -1)]:
                corners.append(add(p, add(mul(s, sx * w / 2 * k), mul(t, sz * d / 2 * k))))
        if dot(cross(sub(corners[1], corners[0]), sub(corners[2], corners[0])), a) > 0:
            corners = corners[:4][::-1] + corners[4:][::-1]
        self.hexa(corners, color, bone)

    def prism(self, p0, p1, r0, r1, sides, color, bone, phase=0.0, caps=True):
        a = norm(sub(p1, p0))
        ref = (0, 0, 1) if abs(a[2]) < 0.9 else (1, 0, 0)
        u = norm(cross(a, ref))
        v = cross(a, u)
        def ring(p, r):
            return [add(p, add(mul(u, math.cos(phase + 2 * math.pi * i / sides) * r),
                               mul(v, math.sin(phase + 2 * math.pi * i / sides) * r))) for i in range(sides)]
        b, t = ring(p0, r0), ring(p1, r1)
        for i in range(sides):
            j = (i + 1) % sides
            if r0 > 1e-5 or r1 > 1e-5:
                self.quad(b[i], b[j], t[j], t[i], color, bone)
            if caps:
                self.tri(p0, b[j], b[i], color, bone)
                self.tri(p1, t[i], t[j], color, bone)

    # -------------------------------------------------------------- cinematica
    def fk(self, rot, pos):
        """Trasformazioni globali di ogni osso: (rotazione, posizione)."""
        g = {}
        for name, parent, _ in self.bones:
            r = rot.get(name, QI)
            t = pos.get(name, self.rest_local(name))
            if parent is None:
                g[name] = (r, t)
            else:
                pr, pt = g[parent]
                g[name] = (qmul(pr, r), add(pt, qrot(pr, t)))
        return g

    def ik_arm(self, side, target_world, pole_world, rot, pos, prefix=""):
        """Due ossa: porta il polso su target, col gomito verso pole.
        prefix: per i modelli con più personaggi (ossa "C1.Chest", "C1.UpperArm.L"...)."""
        ua, la, ha = prefix + "UpperArm." + side, prefix + "LowerArm." + side, prefix + "Hand." + side
        R = self.rest
        g = self.fk(rot, pos)
        cr, cp = g[prefix + "Chest"]
        inv = qinv(cr)
        S = sub(R[ua], R[prefix + "Chest"])
        T = qrot(inv, sub(target_world, cp))
        Pl = qrot(inv, pole_world)
        a = length(sub(R[la], R[ua]))
        b = length(sub(R[ha], R[la]))
        dv = sub(T, S)
        c = min(max(length(dv), 0.05), a + b - 1e-4)
        u = norm(dv)
        cos_a = (a * a + c * c - b * b) / (2 * a * c)
        sin_a = math.sqrt(max(0.0, 1 - cos_a * cos_a))
        v = norm(sub(Pl, mul(u, dot(Pl, u))))
        E = add(S, mul(add(mul(u, cos_a), mul(v, sin_a)), a))
        H = add(S, mul(u, c))
        Ru = qfromto(sub(R[la], R[ua]), sub(E, S))
        fore = qrot(Ru, sub(R[ha], R[la]))
        Rf = qmul(qfromto(fore, sub(H, E)), Ru)
        rot[ua] = Ru
        rot[la] = qmul(qinv(Ru), Rf)

    def point_arm(self, side, dir_world, rot, pos, prefix=""):
        """Braccio teso nella direzione data."""
        ua = prefix + "UpperArm." + side
        cr = self.fk(rot, pos)[prefix + "Chest"][0]
        rest_dir = sub(self.rest[prefix + "Hand." + side], self.rest[ua])
        rot[ua] = qfromto(rest_dir, qrot(qinv(cr), dir_world))
        rot[prefix + "LowerArm." + side] = QI

    def set_global_rot(self, name, q_world, rot, pos):
        pr = self.fk(rot, pos)[self.parent[name]][0]
        rot[name] = qmul(qinv(pr), q_world)

    def blend(self, a, b, t):
        out = {"rot": {}, "pos": {}, "scale": {}}
        for k in set(a["rot"]) | set(b["rot"]):
            out["rot"][k] = qslerp(a["rot"].get(k, QI), b["rot"].get(k, QI), t)
        for k in set(a["pos"]) | set(b["pos"]):
            out["pos"][k] = vlerp(a["pos"].get(k, self.rest_local(k)), b["pos"].get(k, self.rest_local(k)), t)
        out["scale"] = dict(b["scale"] if t > 0.5 else a["scale"])
        return out

    # -------------------------------------------------------------- scrittura
    def write(self, anims, fps=30, translated=("Root", "Hips"), scaled=()):
        """anims: lista di (nome, funzione t -> posa, durata, ciclica). Una posa è
        {"rot": {osso: quat}, "pos": {osso: traslazione locale}, "scale": {osso: (x, y, z)}}."""
        os.makedirs(OUT_DIR, exist_ok=True)
        _write_png(os.path.join(OUT_DIR, self.name + "_Atlas.png"), 4, 4, self.palette)
        buf = _Buf()
        n = len(self.P)
        a_pos = buf.add("3f", self.P, 5126, "VEC3", 34962, minmax=True)
        a_nrm = buf.add("3f", self.N, 5126, "VEC3", 34962)
        a_uv = buf.add("2f", self.UV, 5126, "VEC2", 34962)
        a_j = buf.add("4H", self.J, 5123, "VEC4", 34962)
        a_w = buf.add("4f", self.W, 5126, "VEC4", 34962)
        a_idx = buf.add("H" if n < 65535 else "I", list(range(n)), 5123 if n < 65535 else 5125, "SCALAR", 34963)
        ibm = [(1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, -p[0], -p[1], -p[2], 1) for _, _, p in self.bones]
        a_ibm = buf.add("16f", ibm, 5126, "MAT4")
        nb = len(self.bones)
        nodes = [{"name": "CharacterArmature", "children": [1, nb + 1]}]
        for name, parent, _ in self.bones:
            node = {"name": name, "translation": list(self.rest_local(name))}
            kids = [i + 1 for i, b in enumerate(self.bones) if b[1] == name]
            if kids:
                node["children"] = kids
            nodes.append(node)
        nodes.append({"name": self.name, "mesh": 0, "skin": 0})
        animations = []
        for aname, fn, dur, loop in anims:
            frames = int(round(dur * fps)) + 1
            times = [i / fps for i in range(frames)]
            times[-1] = dur
            poses = [fn(t) for t in times]
            if loop:
                poses[-1] = fn(0.0)
            a_t = buf.add("f", times, 5126, "SCALAR", minmax=True)
            samplers, channels = [], []
            for bi, (bname, _, _) in enumerate(self.bones):
                qs, prev = [], None
                for p in poses:
                    q = p["rot"].get(bname, QI)
                    if prev is not None and sum(x * y for x, y in zip(prev, q)) < 0:
                        q = tuple(-x for x in q)
                    qs.append(q)
                    prev = q
                samplers.append({"input": a_t, "output": buf.add("4f", qs, 5126, "VEC4"), "interpolation": "LINEAR"})
                channels.append({"sampler": len(samplers) - 1, "target": {"node": bi + 1, "path": "rotation"}})
                if bname in translated:
                    ts = [p["pos"].get(bname, self.rest_local(bname)) for p in poses]
                    samplers.append({"input": a_t, "output": buf.add("3f", ts, 5126, "VEC3"), "interpolation": "LINEAR"})
                    channels.append({"sampler": len(samplers) - 1, "target": {"node": bi + 1, "path": "translation"}})
                if bname in scaled:
                    ss = [p["scale"].get(bname, (1.0, 1.0, 1.0)) for p in poses]
                    samplers.append({"input": a_t, "output": buf.add("3f", ss, 5126, "VEC3"), "interpolation": "STEP"})
                    channels.append({"sampler": len(samplers) - 1, "target": {"node": bi + 1, "path": "scale"}})
            animations.append({"name": aname, "samplers": samplers, "channels": channels})
        gltf = {
            "asset": {"version": "2.0", "generator": "tools/modelli/lowpoly.py"},
            "scene": 0,
            "scenes": [{"name": "Scene", "nodes": [0]}],
            "nodes": nodes,
            "meshes": [{"name": self.name, "primitives": [{
                "attributes": {"POSITION": a_pos, "NORMAL": a_nrm, "TEXCOORD_0": a_uv, "JOINTS_0": a_j, "WEIGHTS_0": a_w},
                "indices": a_idx, "material": 0}]}],
            "skins": [{"name": "CharacterArmature", "joints": list(range(1, nb + 1)),
                       "inverseBindMatrices": a_ibm, "skeleton": 1}],
            "materials": [{"name": "Atlas", "pbrMetallicRoughness": {
                "baseColorTexture": {"index": 0}, "metallicFactor": 0.0, "roughnessFactor": 0.9}}],
            "textures": [{"sampler": 0, "source": 0}],
            "samplers": [{"magFilter": 9728, "minFilter": 9728}],
            "images": [{"uri": self.name + "_Atlas.png"}],
            "animations": animations,
            "accessors": buf.accessors,
            "bufferViews": buf.views,
            "buffers": [{"byteLength": len(buf.data),
                         "uri": "data:application/octet-stream;base64," + base64.b64encode(bytes(buf.data)).decode()}],
        }
        path = os.path.join(OUT_DIR, self.name + ".gltf")
        with open(path, "w") as f:
            json.dump(gltf, f, separators=(",", ":"))
        print("%s: %d triangoli, %d ossa, %d animazioni" % (path, n // 3, nb, len(anims)))
        return path


class _Buf:
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


def _write_png(path, w, h, pixels):
    raw = b"".join(b"\x00" + bytes(sum((list(pixels[y * w + x]) for x in range(w)), [])) for y in range(h))
    def chunk(t, d): return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xffffffff)
    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)) \
        + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b"")
    with open(path, "wb") as f:
        f.write(png)
