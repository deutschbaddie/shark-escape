#!/usr/bin/env python3
"""
Hand-built low-poly shark generator for "+1 Speed to Escape the Shark".

Builds every shark variant from the same rig as a skinned, flat-shaded .glb
with a tiny palette texture. Import each .glb into Roblox Studio with the
3D Importer; the game animates the bones in code (no animation uploads).

Model space: +Y up, nose toward -Z, 1 unit = 1 stud.
Bones: Root, Head, Jaw, Spine2, Spine3, Spine4, Tail, PecL, PecR.

Usage: python3 tools/shark_gen.py   (writes assets/sharks/*.glb + preview data)
"""
import json, math, os, struct, zlib, base64

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "assets", "sharks")

# ---------------------------------------------------------------- vec math
def add(a, b): return (a[0]+b[0], a[1]+b[1], a[2]+b[2])
def sub(a, b): return (a[0]-b[0], a[1]-b[1], a[2]-b[2])
def mul(a, k): return (a[0]*k, a[1]*k, a[2]*k)
def dot(a, b): return a[0]*b[0] + a[1]*b[1] + a[2]*b[2]
def cross(a, b): return (a[1]*b[2]-a[2]*b[1], a[2]*b[0]-a[0]*b[2], a[0]*b[1]-a[1]*b[0])
def length(a): return math.sqrt(dot(a, a))
def norm(a):
    l = length(a)
    return (0.0, 1.0, 0.0) if l < 1e-12 else mul(a, 1.0/l)
def lerp(a, b, t): return a + (b - a) * t

def hexrgb(h):
    h = h.lstrip("#")
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16))

# ---------------------------------------------------------------- body profile
# s = 0 at the nose, 0.9 at the tail root. Values are fractions of length L.
PROFILE = [  # s,     full height, full width, center y
    (0.00, 0.060, 0.060, -0.004),
    (0.03, 0.110, 0.100,  0.000),
    (0.07, 0.160, 0.150,  0.004),
    (0.12, 0.205, 0.195,  0.008),
    (0.18, 0.240, 0.232,  0.010),
    (0.25, 0.268, 0.256,  0.012),
    (0.33, 0.280, 0.266,  0.012),
    (0.42, 0.270, 0.250,  0.012),
    (0.52, 0.236, 0.214,  0.012),
    (0.62, 0.190, 0.170,  0.015),
    (0.72, 0.140, 0.120,  0.020),
    (0.80, 0.096, 0.080,  0.025),
    (0.86, 0.066, 0.055,  0.028),
    (0.90, 0.056, 0.045,  0.030),
]
STATIONS = [0.00, 0.03, 0.07, 0.12, 0.17, 0.22, 0.25, 0.29, 0.33, 0.37, 0.42,
            0.47, 0.52, 0.57, 0.62, 0.67, 0.72, 0.76, 0.80, 0.83, 0.86, 0.90]
RING = 10
JAW_FROM, HINGE = 0.03, 0.22
BELLY_FLAT = 0.88

def profile(s):
    if s <= PROFILE[0][0]:
        return PROFILE[0][1:]
    for a, b in zip(PROFILE, PROFILE[1:]):
        if a[0] <= s <= b[0]:
            t = (s - a[0]) / (b[0] - a[0])
            return tuple(lerp(a[i], b[i], t) for i in (1, 2, 3))
    return PROFILE[-1][1:]

VARIANTS = {
    "Baby": dict(L=8, bulk=1.12, eye=1.75, brow=False, teeth=4, tooth=1.0,
                 fin=0.95, scars=0, stripes=False, mecha=False, hammer=False,
                 colors=dict(back="#6cc4f5", belly="#fff6e3", fin="#4fb0ea",
                             mouth="#b8344f", tongue="#ff7f9b", teeth="#ffffff",
                             eyewhite="#ffffff", pupil="#1b1d3f", gill="#3f8fc4")),
    "Hammerhead": dict(L=12, bulk=1.0, eye=1.0, brow=False, teeth=5, tooth=1.0,
                 fin=1.1, scars=0, stripes=False, mecha=False, hammer=True,
                 colors=dict(back="#8e9a74", belly="#f1eee2", fin="#7b8862",
                             mouth="#a8304a", tongue="#e8637f", teeth="#ffffff",
                             eyewhite="#f4e9a8", pupil="#1b1d3f", gill="#5f6a4c")),
    "Tiger": dict(L=14, bulk=1.04, eye=1.0, brow=True, teeth=6, tooth=1.1,
                 fin=1.0, scars=0, stripes=True, mecha=False, hammer=False,
                 colors=dict(back="#94896c", belly="#f5efdd", fin="#7f7558",
                             mouth="#a52c45", tongue="#e45f7c", teeth="#ffffff",
                             eyewhite="#fff4c9", pupil="#1b1d3f", gill="#4d4636",
                             stripe="#4e4535")),
    "GreatWhite": dict(L=18, bulk=1.06, eye=0.95, brow=True, teeth=7, tooth=1.2,
                 fin=1.05, scars=2, stripes=False, mecha=False, hammer=False,
                 colors=dict(back="#6a8199", belly="#f6f7f9", fin="#5a6f86",
                             mouth="#9e2840", tongue="#de5a78", teeth="#ffffff",
                             eyewhite="#ffffff", pupil="#111325", gill="#40546a",
                             scar="#b9c7d6")),
    "Mecha": dict(L=22, bulk=1.08, eye=1.0, brow=True, teeth=7, tooth=1.25,
                 fin=1.1, scars=0, stripes=False, mecha=True, hammer=False,
                 colors=dict(back="#9ba6b3", belly="#dde3ea", fin="#ef6b2c",
                             mouth="#3a2a36", tongue="#ff4d4d", teeth="#e9eef4",
                             eyewhite="#262b33", pupil="#ff2a2a", gill="#5b6573",
                             panel="#6b7684")),
    "Megalodon": dict(L=40, bulk=1.16, eye=0.8, brow=True, teeth=9, tooth=1.5,
                 fin=1.15, scars=3, stripes=False, mecha=False, hammer=False,
                 colors=dict(back="#3d4958", belly="#c8ced7", fin="#313c4a",
                             mouth="#7d1d30", tongue="#c94566", teeth="#fffdf2",
                             eyewhite="#e8e2c8", pupil="#0b0c14", gill="#232c37",
                             scar="#8c99aa")),
}

# ---------------------------------------------------------------- builder
class Shark:
    def __init__(self, name, v):
        self.name, self.v = name, v
        self.L = float(v["L"])
        self.tris = []   # (p0, p1, p2, colorName, group)
        names = list(v["colors"].keys())
        if "highlight" not in names:
            names.append("highlight")
        self.colors = names
        self.palette = dict(v["colors"])
        self.palette["highlight"] = "#ffffff"

    # helpers in L-units ---------------------------------------------------
    def z(self, s): return (s - 0.40) * self.L
    def prof(self, s):
        h, w, cy = profile(s)
        b = self.v["bulk"]
        if self.v["hammer"] and s < 0.16:
            h *= 0.85
        return h * self.L * b, w * self.L * b, cy * self.L

    def mouth_y(self, s):
        h, w, cy = self.prof(s)
        t = max(0.0, min(1.0, (s - JAW_FROM) / (HINGE - JAW_FROM)))
        m = lerp(0.42, 0.16, t)          # corners ride up toward the back: a grin
        return cy - (h / 2) * m

    def ring_point(self, s, k):
        h, w, cy = self.prof(s)
        th = 2 * math.pi * k / RING
        c = math.cos(th)
        y = cy + (h / 2) * c * (BELLY_FLAT if c < 0 else 1.0)
        return (w / 2 * math.sin(th), y, self.z(s))

    def surface(self, s, theta_deg, side=1, push=0.0):
        """Point on the body ellipse at angle theta from the top, plus outward normal."""
        h, w, cy = self.prof(s)
        th = math.radians(theta_deg)
        c, sn = math.cos(th), math.sin(th)
        hy = (h / 2) * (BELLY_FLAT if c < 0 else 1.0)
        p = (side * w / 2 * sn * 0.97, cy + hy * c * 0.97, self.z(s))
        n = norm((side * sn / max(w / 2, 1e-6), c / max(hy, 1e-6), 0.0))
        return add(p, mul(n, push)), n

    # face emitters ----------------------------------------------------------
    def tri(self, a, b, c, color, group, away_from=None, facing=None):
        n = cross(sub(b, a), sub(c, a))
        if length(n) < 1e-7 * self.L * self.L:
            return
        cen = mul(add(add(a, b), c), 1/3)
        want = None
        if facing is not None:
            want = facing
        elif away_from is not None:
            want = sub(cen, away_from)
        if want is not None and dot(n, want) < 0:
            b, c = c, b
        self.tris.append((a, b, c, color, group))

    def quad(self, a, b, c, d, color, group, away_from=None, facing=None):
        self.tri(a, b, c, color, group, away_from, facing)
        self.tri(a, c, d, color, group, away_from, facing)

    # body ---------------------------------------------------------------------
    def hull_color(self, cen, s0, s1, ring_cy, ring_h, k):
        v = self.v
        if cen[1] < ring_cy - 0.06 * ring_h:
            return "belly"
        mid = (s0 + s1) / 2
        idx = STATIONS.index(s0) if s0 in STATIONS else 0
        if v["stripes"] and 0.27 < mid < 0.85 and idx % 2 == 1 and cen[1] > ring_cy - 0.02 * ring_h:
            return "stripe"
        if v["mecha"] and 0.22 < mid < 0.88 and idx % 2 == 0 and cen[1] > ring_cy + 0.05 * ring_h:
            return "panel"
        return "back"

    def build_hull(self):
        rings = []
        for s in STATIONS:
            pts_head, pts_jaw = [], []
            ym = self.mouth_y(s) if JAW_FROM <= s <= HINGE else None
            for k in range(RING):
                p = self.ring_point(s, k)
                if ym is not None:
                    pts_head.append((p[0], max(p[1], ym), p[2]))
                    pts_jaw.append((p[0], min(p[1], ym - 0.004 * self.L), p[2]))
                else:
                    pts_head.append(p)
            rings.append((s, pts_head, pts_jaw if ym is not None else None))

        # nose cap
        s0, r0, _ = rings[0]
        h, w, cy = self.prof(0.0)
        tip = (0.0, cy - 0.01 * self.L, self.z(-0.018))
        for k in range(RING):
            a, b = r0[k], r0[(k + 1) % RING]
            col = "belly" if (a[1] + b[1]) / 2 < cy - 0.01 * self.L else "back"
            self.tri(tip, a, b, col, "body", away_from=(0, cy, self.z(0.03)))

        # main body strips
        for (sa, ra, _), (sb, rb, _) in zip(rings, rings[1:]):
            ha, wa, cya = self.prof(sa)
            for k in range(RING):
                a, b = ra[k], ra[(k + 1) % RING]
                c, d = rb[(k + 1) % RING], rb[k]
                cen = mul(add(add(a, b), add(c, d)), 0.25)
                center = (0.0, (cya + self.prof(sb)[2]) / 2, (a[2] + c[2]) / 2)
                col = self.hull_color(cen, sa, sb, cya, ha, k)
                flat_roof = all(abs(p[1] - self.mouth_y(min(max(p_s, JAW_FROM), HINGE))) < 1e-6
                                for p, p_s in ((a, sa), (b, sa), (c, sb), (d, sb))) \
                    and JAW_FROM <= sa and sb <= HINGE
                if flat_roof:
                    col = "mouth"
                if sa == HINGE and cen[1] < self.mouth_y(HINGE):
                    col = "mouth"          # throat behind the jaw
                self.quad(a, b, c, d, col, "body", away_from=center)

        # jaw: its own closed hull bound to the Jaw bone
        jaw = [(s, rj) for s, _, rj in rings if rj is not None]
        for (sa, ra), (sb, rb) in zip(jaw, jaw[1:]):
            ya = (self.mouth_y(sa) + self.prof(sa)[2] - self.prof(sa)[0] / 2 * BELLY_FLAT) / 2
            for k in range(RING):
                a, b = ra[k], ra[(k + 1) % RING]
                c, d = rb[(k + 1) % RING], rb[k]
                cen = mul(add(add(a, b), add(c, d)), 0.25)
                tongue = abs(a[1] - b[1]) < 1e-6 and abs(c[1] - d[1]) < 1e-6 and \
                    abs(a[1] - (self.mouth_y(sa) - 0.004 * self.L)) < 1e-6
                self.quad(a, b, c, d, "tongue" if tongue else "belly", "jaw",
                          away_from=(0.0, ya, cen[2]))
        # jaw caps
        for (s, r), front in ((jaw[0], True), (jaw[-1], False)):
            cen = mul(r[0], 0)
            for p in r:
                cen = add(cen, mul(p, 1.0 / RING))
            fz = -1 if front else 1
            for k in range(RING):
                self.tri(cen, r[k], r[(k + 1) % RING], "belly", "jaw", facing=(0, 0, fz))

        if self.v["hammer"]:
            self.build_hammer()

    def build_hammer(self):
        L = self.L
        _, _, cy = self.prof(0.06)
        y0 = cy + 0.004 * L
        th = 0.042 * L
        outline = [(-0.255, 0.065), (-0.235, 0.035), (-0.09, 0.022), (0.0, 0.012),
                   (0.09, 0.022), (0.235, 0.035), (0.255, 0.065), (0.24, 0.095),
                   (0.10, 0.105), (0.0, 0.115), (-0.10, 0.105), (-0.24, 0.095)]
        top = [(x * L, y0 + th / 2, self.z(s)) for x, s in outline]
        bot = [(x * L, y0 - th / 2, self.z(s)) for x, s in outline]
        ct = (0.0, y0 + th / 2, self.z(0.065))
        cb = (0.0, y0 - th / 2, self.z(0.065))
        n = len(outline)
        for i in range(n):
            j = (i + 1) % n
            self.tri(ct, top[i], top[j], "back", "head", facing=(0, 1, 0))
            self.tri(cb, bot[i], bot[j], "belly", "head", facing=(0, -1, 0))
            self.quad(top[i], top[j], bot[j], bot[i], "back", "head",
                      away_from=(0.0, y0, self.z(0.065)))
        # eyes on the tips
        for side in (-1, 1):
            c = (side * 0.258 * L, y0 + 0.004 * L, self.z(0.07))
            self.eye(c, (side, 0.25, -0.2), 0.022 * L * self.v["eye"], "head", brow=False)

    # details -----------------------------------------------------------------
    def disc(self, c, n, r, color, group, sides=8, bulge=0.0, rot=0.0):
        n = norm(n)
        up = (0, 0, -1) if abs(n[2]) < 0.9 else (0, 1, 0)
        u = norm(cross(n, up))
        w = cross(n, u)
        apex = add(c, mul(n, bulge))
        pts = []
        for i in range(sides):
            a = 2 * math.pi * i / sides + rot
            pts.append(add(c, add(mul(u, math.cos(a) * r), mul(w, math.sin(a) * r))))
        for i in range(sides):
            self.tri(apex, pts[i], pts[(i + 1) % sides], color, group, facing=n)
        return u, w

    def eye(self, c, n, r, group, brow=True):
        n = norm(n)
        L = self.L
        u, w = self.disc(c, n, r, "eyewhite", group, sides=10, bulge=r * 0.25)
        fwd = (0, 0, -1)
        pupil_c = add(add(c, mul(n, r * 0.26 + 0.002 * L)), mul(norm(sub(fwd, mul(n, dot(fwd, n)))), r * 0.22))
        self.disc(pupil_c, n, r * 0.56, "pupil", group, sides=10, bulge=r * 0.05)
        hl = add(add(pupil_c, mul(n, r * 0.06 + 0.001 * L)), add(mul(norm(sub((0, 1, 0), mul(n, dot((0, 1, 0), n)))), r * 0.22), mul(norm(sub(fwd, mul(n, dot(fwd, n)))), r * 0.12)))
        self.disc(hl, n, r * 0.17, "highlight", group, sides=6)
        if brow:
            # angry brow: a thick slab above the eye, low at the front
            up = norm(sub((0, 1, 0), mul(n, dot((0, 1, 0), n))))
            fw = norm(sub(fwd, mul(n, dot(fwd, n))))
            base = add(c, mul(n, r * 0.35))
            a = add(base, add(mul(up, r * 0.95), mul(fw, r * 1.15)))
            b = add(base, add(mul(up, r * 1.45), mul(fw, -r * 1.05)))
            d = add(a, mul(up, r * 0.42))
            e = add(b, mul(up, r * 0.42))
            self.quad(a, b, e, d, "gill", group, facing=n)

    def strip(self, p0, p1, n, width, color, group):
        """Flat ribbon on the surface (gills, scars)."""
        d = norm(sub(p1, p0))
        side = norm(cross(n, d))
        a, b = add(p0, mul(side, width / 2)), add(p1, mul(side, width / 2))
        c, e = add(p1, mul(side, -width / 2)), add(p0, mul(side, -width / 2))
        self.quad(a, b, c, e, color, group, facing=n)

    def build_face(self):
        v, L = self.v, self.L
        if not v["hammer"]:
            for side in (-1, 1):
                p, n = self.surface(0.105, 52, side, push=0.004 * L)
                n = norm(add(n, (0, 0.1, -0.22)))
                self.eye(p, n, 0.034 * L * v["eye"], "head", brow=v["brow"])
        # gills
        for side in (-1, 1):
            for i in range(4):
                s = 0.255 + i * 0.022
                p0, n0 = self.surface(s - 0.008, 64, side, push=0.003 * L)
                p1, _ = self.surface(s + 0.010, 116, side, push=0.003 * L)
                self.strip(p0, p1, n0, 0.009 * L, "gill", "body")
        # scars (one side only - character)
        for i in range(v["scars"]):
            s = 0.34 + i * 0.07
            p0, n0 = self.surface(s, 58 + i * 6, 1, push=0.0035 * L)
            p1, _ = self.surface(s + 0.05, 84 + i * 4, 1, push=0.0035 * L)
            self.strip(p0, p1, n0, 0.009 * L, "scar", "body")
            q0, _ = self.surface(s + 0.012, 76 + i * 6, 1, push=0.0036 * L)
            q1, _ = self.surface(s + 0.032, 66 + i * 6, 1, push=0.0036 * L)
            self.strip(q0, q1, n0, 0.007 * L, "scar", "body")

    def rim_x(self, s, y):
        h, w, cy = self.prof(s)
        hy = (h / 2) * (BELLY_FLAT if y < cy else 1.0)
        t = max(0.0, 1.0 - ((y - cy) / hy) ** 2)
        return (w / 2) * math.sqrt(t) * 0.93

    def tooth(self, base_c, inward, down, size, group, along):
        tw = size * 0.7
        p0 = add(base_c, mul(along, -tw / 2))
        p1 = add(base_c, mul(along, tw / 2))
        p2 = add(base_c, mul(inward, size * 0.45))
        tip = add(add(base_c, mul(down, size)), mul(inward, size * 0.12))
        cen = mul(add(add(p0, p1), add(p2, tip)), 0.25)
        for a, b, c in ((p0, p1, tip), (p1, p2, tip), (p2, p0, tip), (p0, p2, p1)):
            self.tri(a, b, c, "teeth", group, away_from=cen)

    def build_teeth(self):
        v, L = self.v, self.L
        n = v["teeth"]
        size = 0.026 * L * v["tooth"]
        s_from, s_to = 0.045, 0.195
        for side in (-1, 1):
            for i in range(n):
                t = i / max(n - 1, 1)
                s = lerp(s_from, s_to, t)
                ym = self.mouth_y(s)
                x = side * self.rim_x(s, ym)
                along = norm((0, 0, 1))
                self.tooth((x, ym + 0.002 * L, self.z(s)), (-side, 0, 0), (0, -1, 0),
                           size * lerp(1.1, 0.75, t), "head", along)
                # lower row, interleaved
                s2 = lerp(s_from, s_to, min(1.0, t + 0.5 / max(n - 1, 1)))
                if i < n - 1:
                    ym2 = self.mouth_y(s2) - 0.004 * L
                    x2 = side * self.rim_x(s2, ym2)
                    self.tooth((x2, ym2 - 0.002 * L, self.z(s2)), (-side, 0, 0), (0, 1, 0),
                               size * lerp(0.95, 0.65, t), "jaw", along)
        # front teeth across the snout
        ym = self.mouth_y(JAW_FROM + 0.004)
        for x in (-0.02, 0.02):
            self.tooth((x * L, ym + 0.002 * L, self.z(JAW_FROM + 0.004)), (0, 0, 1), (0, -1, 0),
                       size * 1.05, "head", (1, 0, 0))

    def fin(self, pts, fan_from, thick_dir, thick, factors, color, group):
        t = norm(thick_dir)
        left = [add(p, mul(t, -thick * f / 2)) for p, f in zip(pts, factors)]
        right = [add(p, mul(t, thick * f / 2)) for p, f in zip(pts, factors)]
        n = len(pts)
        center = mul(pts[0], 0)
        for p in pts:
            center = add(center, mul(p, 1.0 / n))
        for i in range(n):
            j = (i + 1) % n
            if i == fan_from or j == fan_from:
                continue
            self.tri(left[fan_from], left[i], left[j], color, group, facing=mul(t, -1))
            self.tri(right[fan_from], right[i], right[j], color, group, facing=t)
        for i in range(n):
            j = (i + 1) % n
            mid = mul(add(pts[i], pts[j]), 0.5)
            self.quad(left[i], left[j], right[j], right[i], color, group,
                      away_from=add(center, mul(sub(center, mid), 0.0)) if True else None)

    def top_y(self, s):
        h, w, cy = self.prof(s)
        return cy + h / 2

    def build_fins(self):
        v, L = self.v, self.L
        fs = v["fin"]
        # dorsal
        F = (0.0, self.top_y(0.29) - 0.012 * L, self.z(0.29))
        A = (0.0, self.top_y(0.36) + 0.215 * L * fs, self.z(0.445))
        N = (0.0, self.top_y(0.42) + 0.065 * L * fs, self.z(0.425))
        B = (0.0, self.top_y(0.47) - 0.012 * L, self.z(0.47))
        self.fin([F, A, N, B], 2, (1, 0, 0), 0.042 * L, [1, 0.15, 0.6, 1], "fin", "body")
        # second dorsal
        F2 = (0.0, self.top_y(0.70) - 0.006 * L, self.z(0.70))
        A2 = (0.0, self.top_y(0.72) + 0.055 * L * fs, self.z(0.755))
        B2 = (0.0, self.top_y(0.76) - 0.006 * L, self.z(0.76))
        self.fin([F2, A2, B2], 0, (1, 0, 0), 0.02 * L, [1, 0.2, 1], "fin", "body")
        # tail (heterocercal crescent)
        _, _, cyt = self.prof(0.88)
        Bt = (0.0, cyt + 0.026 * L, self.z(0.855))
        Ut = (0.0, cyt + 0.30 * L * fs, self.z(1.03))
        Nn = (0.0, cyt + 0.02 * L, self.z(0.955))
        Lt = (0.0, cyt - 0.175 * L * fs, self.z(0.99))
        Bb = (0.0, cyt - 0.024 * L, self.z(0.87))
        self.fin([Bt, Ut, Nn, Lt, Bb], 2, (1, 0, 0), 0.036 * L, [1, 0.1, 0.55, 0.1, 1], "fin", "tail")
        # pectorals
        for side, grp in ((-1, "pecL"), (1, "pecR")):
            r0, _ = self.surface(0.235, 118, side)
            r1, _ = self.surface(0.315, 118, side)
            h, w, cy = self.prof(0.30)
            tip = (side * (w / 2 + 0.205 * L * fs), cy - 0.185 * L, self.z(0.43))
            notch = (side * (w / 2 + 0.06 * L), cy - 0.075 * L, self.z(0.37))
            d = cross(sub(tip, r0), sub(r1, r0))
            self.fin([r0, tip, notch, r1], 2, d, 0.028 * L, [1, 0.12, 0.6, 1], "fin", grp)
        # pelvics
        for side in (-1, 1):
            r0, _ = self.surface(0.585, 130, side)
            r1, _ = self.surface(0.635, 130, side)
            h, w, cy = self.prof(0.62)
            tip = (side * (w / 2 + 0.05 * L), cy - h / 2 - 0.05 * L, self.z(0.67))
            d = cross(sub(tip, r0), sub(r1, r0))
            self.fin([r0, tip, r1], 0, d, 0.016 * L, [1, 0.15, 1], "fin", "body")

    def build(self):
        self.build_hull()
        self.build_face()
        self.build_teeth()
        self.build_fins()
        return self

    # skeleton -----------------------------------------------------------------
    def bones(self):
        L = self.L
        def at(s):
            return (0.0, self.prof(s)[2], self.z(s))
        hinge = (0.0, self.mouth_y(HINGE), self.z(HINGE))
        pec_l, _ = self.surface(0.27, 118, -1)
        pec_r, _ = self.surface(0.27, 118, 1)
        # name, parent, world position
        return [
            ("Root", None, at(0.32)),
            ("Head", "Root", at(0.14)),
            ("Jaw", "Head", hinge),
            ("Spine2", "Root", at(0.48)),
            ("Spine3", "Spine2", at(0.64)),
            ("Spine4", "Spine3", at(0.78)),
            ("Tail", "Spine4", at(0.89)),
            ("PecL", "Root", pec_l),
            ("PecR", "Root", pec_r),
        ]

    def weights_for(self, p, group, idx):
        if group == "jaw":
            return [(idx["Jaw"], 1.0)]
        if group == "head":
            return [(idx["Head"], 1.0)]
        if group == "pecL":
            return [(idx["PecL"], 1.0)]
        if group == "pecR":
            return [(idx["PecR"], 1.0)]
        if group == "tail":
            return [(idx["Tail"], 1.0)]
        chain = [("Head", 0.14), ("Root", 0.32), ("Spine2", 0.48), ("Spine3", 0.64),
                 ("Spine4", 0.78), ("Tail", 0.89)]
        s = p[2] / self.L + 0.40
        if s <= chain[0][1]:
            return [(idx["Head"], 1.0)]
        if s >= chain[-1][1]:
            return [(idx["Tail"], 1.0)]
        for (na, sa), (nb, sb) in zip(chain, chain[1:]):
            if sa <= s <= sb:
                t = (s - sa) / (sb - sa)
                t = t * t * (3 - 2 * t)   # smoothstep: softer bends
                return [(idx[na], 1 - t), (idx[nb], t)]
        return [(idx["Root"], 1.0)]


# ---------------------------------------------------------------- PNG palette
def png_bytes(w, h, pixels):
    raw = b"".join(b"\x00" + bytes(sum((list(pixels[y * w + x]) for x in range(w)), [])) for y in range(h))
    def chunk(t, d):
        c = struct.pack(">I", len(d)) + t + d
        return c + struct.pack(">I", zlib.crc32(t + d) & 0xffffffff)
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))

GRID, CELL = 4, 16

def palette_texture(names, palette):
    size = GRID * CELL
    px = [(255, 0, 255)] * (size * size)
    uv = {}
    for i, n in enumerate(names):
        gx, gy = i % GRID, i // GRID
        col = hexrgb(palette[n])
        for y in range(gy * CELL, (gy + 1) * CELL):
            for x in range(gx * CELL, (gx + 1) * CELL):
                px[y * size + x] = col
        uv[n] = ((gx + 0.5) / GRID, (gy + 0.5) / GRID)
    return png_bytes(size, size, px), uv


# ---------------------------------------------------------------- glTF writer
def write_glb(shark, path):
    bones = shark.bones()
    idx = {b[0]: i for i, b in enumerate(bones)}
    world = {b[0]: b[2] for b in bones}
    names = [n for n in shark.colors if any(t[3] == n for t in shark.tris)] or shark.colors
    png, uvs = palette_texture(names, shark.palette)

    pos, nrm, uv, jnt, wgt = [], [], [], [], []
    for a, b, c, col, group in shark.tris:
        n = norm(cross(sub(b, a), sub(c, a)))
        for p in (a, b, c):
            pos.append(p); nrm.append(n); uv.append(uvs.get(col, uvs[names[0]]))
            ws = shark.weights_for(p, group, idx)
            j4 = [w[0] for w in ws] + [0] * (4 - len(ws))
            w4 = [w[1] for w in ws] + [0.0] * (4 - len(ws))
            tot = sum(w4)
            jnt.append(j4); wgt.append([x / tot for x in w4])
    count = len(pos)
    indices = list(range(count))

    blob = bytearray()
    views, accessors = [], []
    def push(data, target=None):
        while len(blob) % 4:
            blob.append(0)
        off = len(blob)
        blob.extend(data)
        v = {"buffer": 0, "byteOffset": off, "byteLength": len(data)}
        if target:
            v["target"] = target
        views.append(v)
        return len(views) - 1

    def acc(view, ctype, cnt, typ, **kw):
        a = {"bufferView": view, "componentType": ctype, "count": cnt, "type": typ}
        a.update(kw)
        accessors.append(a)
        return len(accessors) - 1

    f32 = lambda arr: b"".join(struct.pack("<f", x) for x in arr)
    flat = lambda rows: [x for r in rows for x in r]

    mins = [min(p[i] for p in pos) for i in range(3)]
    maxs = [max(p[i] for p in pos) for i in range(3)]
    a_pos = acc(push(f32(flat(pos)), 34962), 5126, count, "VEC3", min=mins, max=maxs)
    a_nrm = acc(push(f32(flat(nrm)), 34962), 5126, count, "VEC3")
    a_uv = acc(push(f32(flat(uv)), 34962), 5126, count, "VEC2")
    a_jnt = acc(push(b"".join(struct.pack("<4H", *j) for j in jnt), 34962), 5123, count, "VEC4")
    a_wgt = acc(push(f32(flat(wgt)), 34962), 5126, count, "VEC4")
    a_idx = acc(push(b"".join(struct.pack("<I", i) for i in indices), 34963), 5125, count, "SCALAR")

    ibm = []
    for name, parent, p in bones:
        # column-major inverse of a pure translation
        ibm += [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, -p[0], -p[1], -p[2], 1]
    a_ibm = acc(push(f32(ibm)), 5126, len(bones), "MAT4")
    v_img = push(png)

    nodes = []
    for name, parent, p in bones:
        local = p if parent is None else sub(p, world[parent])
        nodes.append({"name": name, "translation": [round(x, 6) for x in local]})
    for i, (name, parent, p) in enumerate(bones):
        kids = [j for j, b in enumerate(bones) if b[1] == name]
        if kids:
            nodes[i]["children"] = kids
    mesh_node = len(nodes)
    nodes.append({"name": "Shark" + shark.name, "mesh": 0, "skin": 0})
    armature = len(nodes)
    nodes.append({"name": "Armature", "children": [idx["Root"]]})

    gltf = {
        "asset": {"version": "2.0", "generator": "revex shark_gen.py (hand-built)"},
        "scene": 0,
        "scenes": [{"name": shark.name, "nodes": [armature, mesh_node]}],
        "nodes": nodes,
        "meshes": [{"name": "Shark" + shark.name, "primitives": [{
            "attributes": {"POSITION": a_pos, "NORMAL": a_nrm, "TEXCOORD_0": a_uv,
                           "JOINTS_0": a_jnt, "WEIGHTS_0": a_wgt},
            "indices": a_idx, "material": 0, "mode": 4}]}],
        "skins": [{"name": "SharkRig", "joints": list(range(len(bones))),
                   "inverseBindMatrices": a_ibm, "skeleton": idx["Root"]}],
        "materials": [{"name": "SharkPalette" + shark.name,
                       "pbrMetallicRoughness": {"baseColorTexture": {"index": 0},
                                                "metallicFactor": 0.0, "roughnessFactor": 1.0}}],
        "textures": [{"source": 0, "sampler": 0}],
        "samplers": [{"magFilter": 9728, "minFilter": 9728}],
        "images": [{"bufferView": v_img, "mimeType": "image/png", "name": "palette"}],
        "buffers": [{"byteLength": 0}],
        "bufferViews": views,
        "accessors": accessors,
    }
    while len(blob) % 4:
        blob.append(0)
    gltf["buffers"][0]["byteLength"] = len(blob)
    js = json.dumps(gltf, separators=(",", ":")).encode()
    while len(js) % 4:
        js += b" "
    out = struct.pack("<III", 0x46546C67, 2, 12 + 8 + len(js) + 8 + len(blob))
    out += struct.pack("<II", len(js), 0x4E4F534A) + js
    out += struct.pack("<II", len(blob), 0x004E4942) + bytes(blob)
    with open(path, "wb") as fh:
        fh.write(out)
    return len(shark.tris), out


def main():
    os.makedirs(OUT, exist_ok=True)
    embed = {}
    for name, v in VARIANTS.items():
        s = Shark(name, v).build()
        path = os.path.join(OUT, f"Shark{name}.glb")
        tris, data = write_glb(s, path)
        embed[name] = base64.b64encode(data).decode()
        print(f"{name:11s} L={v['L']:>3} studs  {tris:5d} tris  -> {os.path.relpath(path)}")
    with open(os.path.join(HERE, "preview_data.js"), "w") as fh:
        fh.write("window.SHARKS = " + json.dumps(embed) + ";\n")


if __name__ == "__main__":
    main()
