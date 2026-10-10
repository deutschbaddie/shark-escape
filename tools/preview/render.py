"""Draw creatures.txt (from dump.py) as a 3/4-view contact sheet."""
import math, os, sys
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(__file__)
CELL = int(os.environ.get("CELL", "260"))

def load():
    out, cur = [], None
    for line in open(os.path.join(HERE, "creatures.txt")):
        f = line.rstrip("\n").split("\t")
        if f[0] == "C":
            cur = {"zone": f[1], "rarity": f[2], "name": f[3], "boxes": []}
            out.append(cur)
        elif f[0] == "B":
            v = [float(x) for x in f[1:20]]
            cur["boxes"].append({"c": v[0:3], "s": v[3:6], "r": [v[6:9], v[9:12], v[12:15]], "col": v[15:18], "t": v[18], "mat": f[20]})
    return out

def sub(a, b): return [a[0]-b[0], a[1]-b[1], a[2]-b[2]]
def dot(a, b): return a[0]*b[0]+a[1]*b[1]+a[2]*b[2]
def cross(a, b): return [a[1]*b[2]-a[2]*b[1], a[2]*b[0]-a[0]*b[2], a[0]*b[1]-a[1]*b[0]]
def norm(a):
    m = math.sqrt(dot(a, a)); return [a[0]/m, a[1]/m, a[2]/m]
def rot(r, v): return [dot(r[0], v), dot(r[1], v), dot(r[2], v)]

def draw(sp, img, ox, oy, eye):
    target = [0, 0.3, 0]
    fwd = norm(sub(target, eye)); right = norm(cross(fwd, [0, 1, 0])); up = cross(right, fwd)
    light = norm([-0.4, 1.0, -0.6])
    faces = []
    for b in sp["boxes"]:
        hx, hy, hz = b["s"][0]/2, b["s"][1]/2, b["s"][2]/2
        for axis in range(3):
            for sgn in (-1, 1):
                n_local = [0, 0, 0]; n_local[axis] = sgn
                n = rot(b["r"], n_local)
                corners = []
                for u in (-1, 1):
                    for w in (-1, 1):
                        p = [0, 0, 0]
                        p[axis] = sgn * [hx, hy, hz][axis]
                        others = [i for i in range(3) if i != axis]
                        p[others[0]] = u * [hx, hy, hz][others[0]]
                        p[others[1]] = w * [hx, hy, hz][others[1]] * (u if False else 1)
                        corners.append(p)
                corners = [corners[0], corners[1], corners[3], corners[2]]
                world = [[b["c"][0]+q[0], b["c"][1]+q[1], b["c"][2]+q[2]] for q in (rot(b["r"], c) for c in corners)]
                center = [sum(p[i] for p in world)/4 for i in range(3)]
                if dot(n, sub(eye, center)) <= 0:
                    continue
                shade = 0.55 + 0.45 * max(0, dot(n, light))
                if b["mat"] == "Neon": shade = 1.15
                col = tuple(min(255, int(255 * c * shade)) for c in b["col"])
                faces.append((dot(sub(center, eye), sub(center, eye)), world, col, b["t"]))
    faces.sort(key=lambda f: -f[0])
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    for _, world, col, t in faces:
        pts = []
        for p in world:
            v = sub(p, eye); z = dot(v, fwd)
            sx = dot(v, right) / z * 2 * CELL; sy = -dot(v, up) / z * 2 * CELL
            pts.append((ox + CELL/2 + sx, oy + CELL/2 + 10 + sy))
        a = int(255 * (1 - t))
        d.polygon(pts, fill=col + (a,), outline=(20, 20, 30, 255))
    img.alpha_composite(layer)

def main():
    sps = load()
    cols = int(os.environ.get("COLS", "6"))
    rows = math.ceil(len(sps) / cols)
    img = Image.new("RGBA", (cols * CELL, rows * CELL), (58, 63, 82, 255))
    d = ImageDraw.Draw(img)
    try:
        font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 15)
    except Exception:
        font = None
    k = float(os.environ.get("DIST", "1"))
    eye = [3.4 * k, 2.4 * k, -5.2 * k]
    for i, sp in enumerate(sps):
        ox, oy = (i % cols) * CELL, (i // cols) * CELL
        d.rectangle([ox + 2, oy + 2, ox + CELL - 3, oy + CELL - 3], outline=(90, 96, 120))
        draw(sp, img, ox, oy, eye)
        ImageDraw.Draw(img).text((ox + 8, oy + 6), f"{sp['zone']} {sp['rarity']}: {sp['name']}", fill=(255, 255, 255), font=font)
    out = os.path.join(HERE, "creatures.png")
    img.save(out)
    print(out)

main()
