"""Check every ride against a stand-in R15 body.

Runs the real Rides.luau + Rig.luau (poses and fitting) in the Luau CLI with
mock.luau, on an approximate default R15 block rig at a few body scales.
Reports how deep any body part sinks into the ride (oriented-box overlap) and
draws side + 3/4 views to rides.png.

    python3 tools/preview/fit.py path/to/luau
"""
import math, os, re, subprocess, sys
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(__file__)
ROOT = os.path.join(HERE, "..", "..", "src", "shared")
LUAU = sys.argv[1] if len(sys.argv) > 1 else "luau"
ONLY = sys.argv[2].split(",") if len(sys.argv) > 2 else None
SCALES = [1.0, 0.9, 1.12]


def module(name):
    src = open(os.path.join(ROOT, name + ".luau")).read()
    src = re.sub(r"^export type", "type", src, flags=re.M)
    return f"MODULES.{name} = function()\nlocal script = {{ Parent = SHARED }}\n{src}\nend\n"


harness = open(os.path.join(HERE, "mock.luau")).read()
harness += """
MODULES = {}
local LOADED = {}
SHARED = setmetatable({}, { __index = function(_, k) return "mod:" .. k end })
function require(x)
	local name = x:sub(5)
	if LOADED[name] == nil then LOADED[name] = MODULES[name]() end
	return LOADED[name]
end
"""
for m in ("Config", "Build", "Rides", "Rig"):
    harness += module(m)
harness += r"""
local Config = require("mod:Config")
local Rides = require("mod:Rides")
local Rig = require("mod:Rig")

-- approximate default R15 block rig (feet at y = 0, hip joints at y = 2)
local function rig(s)
	local parts, joints = {}, {}
	local function part(name, x, y, z) parts[name] = { Name = name, Size = Vector3.new(x, y, z) * s } return parts[name] end
	local function j(name, p0, p1, c0, c1)
		table.insert(joints, { Name = name, Part0 = parts[p0], Part1 = parts[p1],
			C0 = CFrame.new(c0[1] * s, c0[2] * s, c0[3] * s), C1 = CFrame.new(c1[1] * s, c1[2] * s, c1[3] * s) })
	end
	part("HumanoidRootPart", 2, 2, 1)
	part("LowerTorso", 2, 0.4, 1); part("UpperTorso", 2, 1.6, 1); part("Head", 1.2, 1.2, 1.2)
	for _, side in { "Left", "Right" } do
		part(side .. "UpperArm", 1, 1.2, 1); part(side .. "LowerArm", 1, 1.1, 1); part(side .. "Hand", 1, 0.4, 1)
		part(side .. "UpperLeg", 1, 1.2, 1); part(side .. "LowerLeg", 1, 1.2, 1); part(side .. "Foot", 1, 0.3, 1)
	end
	j("Root", "HumanoidRootPart", "LowerTorso", { 0, -0.8, 0 }, { 0, 0, 0 })
	j("Waist", "LowerTorso", "UpperTorso", { 0, 0.2, 0 }, { 0, -0.8, 0 })
	j("Neck", "UpperTorso", "Head", { 0, 0.8, 0 }, { 0, -0.6, 0 })
	for _, side in { "Left", "Right" } do
		local x = side == "Left" and -1 or 1
		j(side .. "Shoulder", "UpperTorso", side .. "UpperArm", { x, 0.56, 0 }, { -x * 0.5, 0.4, 0 })
		j(side .. "Elbow", side .. "UpperArm", side .. "LowerArm", { 0, -0.4, 0 }, { 0, 0.35, 0 })
		j(side .. "Wrist", side .. "LowerArm", side .. "Hand", { 0, -0.5, 0 }, { 0, 0.15, 0 })
		j(side .. "Hip", "LowerTorso", side .. "UpperLeg", { x * 0.5, -0.2, 0 }, { 0, 0.4, 0 })
		j(side .. "Knee", side .. "UpperLeg", side .. "LowerLeg", { 0, -0.45, 0 }, { 0, 0.35, 0 })
		j(side .. "Ankle", side .. "LowerLeg", side .. "Foot", { 0, -0.55, 0 }, { 0, 0.1, 0 })
	end
	return parts.HumanoidRootPart, joints, 3 * s -- feet are 3 below the root part's centre
end

local function box(tag, name, c, s, col)
	local r = c.r
	print(tag, name, c.p.X, c.p.Y, c.p.Z, s.X, s.Y, s.Z, r[1][1], r[1][2], r[1][3], r[2][1], r[2][2], r[2][3], r[3][1], r[3][2], r[3][3], col[1], col[2], col[3])
end

for _, ride in Config.Rides do
	for _, s in { SCALES } do
		local root, joints, drop = rig(s)
		local k = math.clamp(Rig.legLength(joints, root) / Rig.REF_LEG, 0.8, 1.35)
		local stance = Config.feel(ride.id).stance
		local fit = Rides.FIT[ride.id] or Vector3.new()
		local target = Vector3.new(0, fit.Y * k - drop, fit.Z * k)
		local d = Rig.fit(joints, root, stance, target)
		local tf = {}
		for name, fn in Rig.POSES[stance] do tf[name] = fn(0, 1) end
		tf.Root = CFrame.new(d.X, d.Y, d.Z) * tf.Root
		local cfs = Rig.solve(joints, root, tf)
		print("R", ride.id, stance, s, k)
		for p, c in cfs do
			if p.Name ~= "HumanoidRootPart" then
				local n = p.Name
				local col = (n:find("Torso") and { 0.16, 0.42, 0.9 }) or (n:find("Leg") or n:find("Foot")) and { 0.3, 0.62, 0.25 } or { 0.98, 0.84, 0.25 }
				box("P", p.Name, CFrame.new(0, drop, 0) * c, p.Size, col)
			end
		end
		PARTS = {}
		local m = Rides.build(ride.id)
		for _, p in m:GetDescendants() do
			if (p.ClassName == "Part" or p.ClassName == "WedgePart") and p.Transparency < 1 then
				local c = p.CFrame
				local mesh = p:FindFirstChild("SpecialMesh") or (#p:GetChildren() > 0 and p:GetChildren()[1])
				local isEll = mesh and mesh.ClassName == "SpecialMesh"
				box(p.ClassName == "WedgePart" and "W" or (isEll and "E" or "B"), p.Name or "part", CFrame.new(c.p.X * k, c.p.Y * k, c.p.Z * k) * c.Rotation, p.Size * k, { p.Color.R, p.Color.G, p.Color.B })
			end
		end
	end
end
""".replace("{ SCALES }", "{ " + ", ".join(str(s) for s in SCALES) + " }")

path = os.path.join(HERE, "fit_harness.luau")
open(path, "w").write(harness)
out = subprocess.run([LUAU, path], capture_output=True, text=True)
os.remove(path)
if out.returncode != 0:
    print(out.stdout[-2000:], out.stderr[-3000:])
    sys.exit(1)

# ---------------------------------------------------------------- parse
cases = []
for line in out.stdout.splitlines():
    f = line.split("\t")
    if f[0] == "R":
        cur = {"id": f[1], "stance": f[2], "s": float(f[3]), "k": float(f[4]), "body": [], "ride": []}
        cases.append(cur)
    elif f[0] in ("P", "B", "W", "E"):
        v = [float(x) for x in f[2:20]]
        b = {"name": f[1], "c": v[0:3], "s": v[3:6], "r": [v[6:9], v[9:12], v[12:15]], "col": v[15:18], "wedge": f[0] == "W", "ell": f[0] == "E"}
        (cur["body"] if f[0] == "P" else cur["ride"]).append(b)


def axes(b):  # columns of r = local axes in world
    r = b["r"]
    return [[r[0][i], r[1][i], r[2][i]] for i in range(3)]


def dot(a, b): return a[0]*b[0] + a[1]*b[1] + a[2]*b[2]
def cross(a, b): return [a[1]*b[2]-a[2]*b[1], a[2]*b[0]-a[0]*b[2], a[0]*b[1]-a[1]*b[0]]


def penetration(a, b):
    """Smallest separating overlap of two oriented boxes (SAT); 0 if apart."""
    A, B = axes(a), axes(b)
    cand = A + B + [cross(x, y) for x in A for y in B]
    t = [b["c"][i] - a["c"][i] for i in range(3)]
    best = 1e9
    for ax in cand:
        m = math.sqrt(dot(ax, ax))
        if m < 1e-6:
            continue
        ax = [ax[0]/m, ax[1]/m, ax[2]/m]
        ra = sum(abs(dot(A[i], ax)) * a["s"][i] / 2 for i in range(3))
        rb = sum(abs(dot(B[i], ax)) * b["s"][i] / 2 for i in range(3))
        o = ra + rb - abs(dot(t, ax))
        if o <= 0:
            return 0
        best = min(best, o)
    return best


def ell_penetration(box, e):
    """How deep a body box reaches into an ellipsoid (sampled)."""
    A, E = axes(box), axes(e)
    semi = [e["s"][i] / 2 for i in range(3)]
    best = 0
    n = 6
    for i in range(n):
        for j in range(n):
            for k in range(n):
                u = [(i + 0.5) / n - 0.5, (j + 0.5) / n - 0.5, (k + 0.5) / n - 0.5]
                p = [box["c"][q] + sum(A[a][q] * u[a] * box["s"][a] for a in range(3)) for q in range(3)]
                d = [p[q] - e["c"][q] for q in range(3)]
                loc = [dot(E[a], d) / semi[a] for a in range(3)]
                r = math.sqrt(sum(x * x for x in loc))
                if r < 1:
                    best = max(best, (1 - r) * min(semi))
    return best


worst_all = []
for c in cases:
    hits = []
    for p in c["body"]:
        for q in c["ride"]:
            if q["wedge"]:
                # wedges: test the half box under the slope only roughly (as a box shrunk 30%)
                q = dict(q); q["s"] = [q["s"][0], q["s"][1] * 0.7, q["s"][2] * 0.7]
            if q["name"] == "Grip" and ("Hand" in p["name"] or "LowerArm" in p["name"]):
                continue  # holding on is the point
            d = ell_penetration(p, q) if q.get("ell") else penetration(p, q)
            if d > 0.05:
                hits.append((d, p["name"], q["name"] + "@(%.2f,%.2f,%.2f)s(%.2f,%.2f,%.2f)" % (*q["c"], *q["s"])))
    hits.sort(reverse=True)
    c["hits"] = hits
    worst = hits[0][0] if hits else 0
    worst_all.append(worst)
    print(f'{c["id"]:11s} {c["stance"]:8s} body x{c["s"]:.2f} ride x{c["k"]:.2f}  worst {worst:.2f}  ' +
          ", ".join(f"{n}:{d:.2f}" for d, n, _ in hits[:4]))

if os.environ.get("DEBUG"):
    for c in cases:
        if c["id"] in (ONLY or []) and abs(c["s"] - 1) < 1e-6:
            print("==", c["id"])
            for b in c["body"]:
                A = axes(b)
                ys = [b["c"][1] + sum(A[i][1] * sx * b["s"][i] / 2 for i, sx in enumerate(sg)) for sg in [(a, bb, cc) for a in (-1, 1) for bb in (-1, 1) for cc in (-1, 1)]]
                zs = [b["c"][2] + sum(A[i][2] * sx * b["s"][i] / 2 for i, sx in enumerate(sg)) for sg in [(a, bb, cc) for a in (-1, 1) for bb in (-1, 1) for cc in (-1, 1)]]
                print(f'  {b["name"]:14s} c=({b["c"][0]:5.2f},{b["c"][1]:5.2f},{b["c"][2]:5.2f}) y[{min(ys):5.2f},{max(ys):5.2f}] z[{min(zs):5.2f},{max(zs):5.2f}]')
            for d, n, q in c["hits"][:8]:
                print(f"  hit {n} x {q} {d:.2f}")

# ---------------------------------------------------------------- draw
CELL = 420


def project(eye, target):
    def norm(a):
        m = math.sqrt(dot(a, a)); return [a[0]/m, a[1]/m, a[2]/m]
    fwd = norm([target[i] - eye[i] for i in range(3)])
    right = norm(cross(fwd, [0, 1, 0]))
    up = cross(right, fwd)
    return fwd, right, up


def hull2d(points):
    pts = sorted(set((round(x, 2), round(y, 2)) for x, y in points))
    if len(pts) < 3:
        return pts
    def cr(o, a, b): return (a[0]-o[0])*(b[1]-o[1]) - (a[1]-o[1])*(b[0]-o[0])
    lower, upper = [], []
    for p in pts:
        while len(lower) >= 2 and cr(lower[-2], lower[-1], p) <= 0: lower.pop()
        lower.append(p)
    for p in reversed(pts):
        while len(upper) >= 2 and cr(upper[-2], upper[-1], p) <= 0: upper.pop()
        upper.append(p)
    return lower[:-1] + upper[:-1]


def draw(img, case, ox, oy, eye):
    target = [0, 1.2, 0]
    fwd, right, up = project(eye, target)
    light = [-0.4, 0.9, -0.5]
    m = math.sqrt(dot(light, light)); light = [x/m for x in light]
    faces = []
    for b, kind in [(b, "body") for b in case["body"]] + [(b, "ride") for b in case["ride"] if not b.get("ell")]:
        A = axes(b)
        for i in range(3):
            for sg in (-1, 1):
                n = [A[i][j] * sg for j in range(3)]
                if dot(n, fwd) >= 0:
                    continue
                j1, j2 = [x for x in range(3) if x != i]
                pts = []
                for u, w in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
                    p = [b["c"][q] + A[i][q]*sg*b["s"][i]/2 + A[j1][q]*u*b["s"][j1]/2 + A[j2][q]*w*b["s"][j2]/2 for q in range(3)]
                    pts.append(p)
                depth = sum(dot([p[q]-eye[q] for q in range(3)], fwd) for p in pts) / 4
                shade = 0.55 + 0.45 * max(0, dot(n, light))
                col = tuple(int(255 * min(1, ch * shade)) for ch in b["col"])
                faces.append((depth, pts, col, kind))
    for b in case["ride"]:
        if not b.get("ell"):
            continue
        E = axes(b)
        pts = []
        for i in range(24):
            for j in range(1, 12):
                th, ph = 2 * math.pi * i / 24, math.pi * j / 12
                u = [math.sin(ph) * math.cos(th), math.cos(ph), math.sin(ph) * math.sin(th)]
                pts.append([b["c"][q] + sum(E[a][q] * u[a] * b["s"][a] / 2 for a in range(3)) for q in range(3)])
        depth = dot([b["c"][q] - eye[q] for q in range(3)], fwd)
        faces.append((depth, pts, tuple(int(255 * min(1, ch * 0.95)) for ch in b["col"]), "ell"))
    faces = [f for f in faces if not (f[3] == "ride" and False)]
    faces.sort(key=lambda f: -f[0])
    scale = 34
    d = ImageDraw.Draw(img)
    for depth, pts, col, kind in faces:
        poly = []
        for p in pts:
            v = [p[q] - eye[q] for q in range(3)]
            z = dot(v, fwd)
            poly.append((ox + CELL/2 + dot(v, right) / z * scale * 12, oy + CELL*0.62 - dot(v, up) / z * scale * 12))
        if kind == "ell":
            poly = hull2d(poly)
        d.polygon(poly, fill=col, outline=(0, 0, 0) if kind in ("ride", "ell") else (20, 20, 30))
    # waterline
    d.line([(ox, oy + CELL*0.62 + 0.15 * scale * 1.0), (ox + CELL, oy + CELL*0.62 + 0.15*scale*1.0)], fill=(60, 140, 255))


base = [c for c in cases if abs(c["s"] - 1.0) < 1e-6 and (not ONLY or c["id"] in ONLY)]
img = Image.new("RGB", (CELL * 3, CELL * len(base)), (232, 244, 250))
d = ImageDraw.Draw(img)
for row, c in enumerate(base):
    draw(img, c, 0, row * CELL, [14, 2.0, 0.01])        # side (rider faces -Z = right)
    draw(img, c, CELL, row * CELL, [8, 5.5, 10])         # 3/4 from behind
    draw(img, c, CELL * 2, row * CELL, [7, 4.5, -11])    # 3/4 front
    worst = c["hits"][0][0] if c["hits"] else 0
    d.text((6, row * CELL + 6), f'{c["id"]} ({c["stance"]})  worst overlap {worst:.2f}', fill=(0, 0, 0))
img.save(os.path.join(HERE, "rides.png"))
print("worst overall", max(worst_all))
