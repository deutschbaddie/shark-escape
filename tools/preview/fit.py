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

local function box(tag, name, c, s, col, mat, t, refl)
	local r = c.r
	print(tag, name, c.p.X, c.p.Y, c.p.Z, s.X, s.Y, s.Z, r[1][1], r[1][2], r[1][3], r[2][1], r[2][2], r[2][3], r[3][1], r[3][2], r[3][3], col[1], col[2], col[3], mat or "SmoothPlastic", t or 0, refl or 0)
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
				local isEll = false
				for _, ch in p:GetChildren() do
					if ch.ClassName == "SpecialMesh" then isEll = true end
				end
				local shape = p.Shape and p.Shape.Name
				local tag = p.ClassName == "WedgePart" and "W" or (isEll and "E") or (shape == "Ball" and "S") or (shape == "Cylinder" and "C") or "B"
				box(tag, p.Name or "part", CFrame.new(c.p.X * k, c.p.Y * k, c.p.Z * k) * c.Rotation, p.Size * k, { p.Color.R, p.Color.G, p.Color.B }, p.Material and p.Material.Name, p.Transparency, p.Reflectance)
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
    elif f[0] in ("P", "B", "W", "E", "S", "C"):
        v = [float(x) for x in f[2:20]]
        b = {"name": f[1], "c": v[0:3], "s": v[3:6], "r": [v[6:9], v[9:12], v[12:15]], "col": v[15:18], "wedge": f[0] == "W", "ell": f[0] in ("E", "S"),
             "kind": "B" if f[0] == "P" else f[0], "mat": f[20] if len(f) > 20 else "SmoothPlastic",
             "t": float(f[21]) if len(f) > 21 and f[21] not in ("nil", "") else 0, "refl": float(f[22]) if len(f) > 22 and f[22] not in ("nil", "") else 0}
        if f[0] == "S":
            m = min(b["s"]); b["s"] = [m, m, m]
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


def cyl_penetration(box, e):
    """How deep a body box reaches into a cylinder along local X (sampled)."""
    A, E = axes(box), axes(e)
    hx, r = e["s"][0] / 2, min(e["s"][1], e["s"][2]) / 2
    best = 0
    n = 6
    for i in range(n):
        for j in range(n):
            for k in range(n):
                u = [(i + 0.5) / n - 0.5, (j + 0.5) / n - 0.5, (k + 0.5) / n - 0.5]
                p = [box["c"][q] + sum(A[a][q] * u[a] * box["s"][a] for a in range(3)) for q in range(3)]
                d = [p[q] - e["c"][q] for q in range(3)]
                loc = [dot(E[a], d) for a in range(3)]
                rad = math.sqrt(loc[1] ** 2 + loc[2] ** 2)
                pen = min(r - rad, hx - abs(loc[0]))
                if pen > 0:
                    best = max(best, pen)
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
            if q.get("ell"):
                d = ell_penetration(p, q)
            elif q.get("kind") == "C":
                d = cyl_penetration(p, q) if penetration(p, q) > 0 else 0
            else:
                d = penetration(p, q)
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
import raster
from PIL import ImageDraw

OUT = os.path.join(HERE, "rides")
os.makedirs(OUT, exist_ok=True)
VIEWS = {  # view directions (from target toward the eye)
    "front34": [7.5, 4.6, -10.5],
    "side": [13.5, 1.2, 0.01],
    "back34": [8.5, 5.5, 9.5],
}


def frame(ps, view, fov, aspect=4 / 3):
    """Eye + target that fit all primitives (bounding sphere) in the view."""
    lo = [min(b["c"][i] - max(b["s"]) / 2 for b in ps) for i in range(3)]
    hi = [max(b["c"][i] + max(b["s"]) / 2 for b in ps) for i in range(3)]
    c = [(lo[i] + hi[i]) / 2 for i in range(3)]
    r = math.sqrt(sum((hi[i] - lo[i]) ** 2 for i in range(3))) / 2 * 0.78
    d = VIEWS[view]
    m = math.sqrt(sum(x * x for x in d))
    dist = r / math.tan(math.radians(fov) / 2)
    return [c[i] + d[i] / m * dist for i in range(3)], c


def shot(c, rider, view, W, H, fov=28, water=None):
    ps = prims(c, rider)
    eye, tgt = frame(ps, view, fov)
    return raster.render(ps, eye, tgt, W, H, fov=fov, water=water)


def prims(c, rider=True):
    out = [b for b in c["ride"]]
    if rider:
        out = out + [dict(b, kind="B", mat="SmoothPlastic", t=0, refl=0) for b in c["body"]]
    return out


base = [c for c in cases if abs(c["s"] - 1.0) < 1e-6 and (not ONLY or c["id"] in ONLY)]
CELLW, CELLH = 360, 270


def render_case(c):
    tiles = [
        shot(c, True, "front34", CELLW, CELLH, water=-0.15),
        shot(c, False, "front34", CELLW, CELLH),
        shot(c, False, "side", CELLW, CELLH),
        shot(c, True, "back34", CELLW, CELLH, water=-0.15),
    ]
    worst = c["hits"][0][0] if c["hits"] else 0
    big = Image.new("RGB", (1200, 900), (255, 255, 255))
    big.paste(shot(c, False, "front34", 600, 450), (0, 0))
    big.paste(shot(c, True, "front34", 600, 450, water=-0.15), (600, 0))
    big.paste(shot(c, False, "side", 600, 450), (0, 450))
    big.paste(shot(c, False, "back34", 600, 450), (600, 450))
    ImageDraw.Draw(big).text((8, 8), f'{c["id"]} parts {len(c["ride"])} overlap {worst:.2f}', fill=(0, 0, 0))
    big.save(os.path.join(OUT, c["id"] + ".png"))
    return tiles


from multiprocessing import Pool
with Pool(min(8, os.cpu_count() or 2)) as pool:
    all_tiles = pool.map(render_case, base)
sheet = Image.new("RGB", (CELLW * 4, CELLH * len(base)), (255, 255, 255))
for row, (c, tiles) in enumerate(zip(base, all_tiles)):
    for i, t in enumerate(tiles):
        sheet.paste(t, (i * CELLW, row * CELLH))
    worst = c["hits"][0][0] if c["hits"] else 0
    ImageDraw.Draw(sheet).text((6, row * CELLH + 6), f'{c["id"]} ({c["stance"]}) parts {len(c["ride"])} overlap {worst:.2f}', fill=(0, 0, 0))
if not ONLY:
    sheet.save(os.path.join(HERE, "rides.png"))
print("worst overall", max(worst_all))
