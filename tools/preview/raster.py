"""Small numpy ray caster for Roblox-ish primitives (preview only).

Primitives are dicts: kind in B (block), W (wedge, slope faces -Z, tall at +Z),
E (SpecialMesh sphere = ellipsoid filling the box), S (Ball shape, sphere of
min size), C (Cylinder shape along X, diameter min(Y, Z)); c = centre,
s = size, r = 3x3 rotation rows (world = c + r @ local), col = rgb 0..1,
mat = material name, t = transparency, refl = reflectance.
"""
import math
import numpy as np
from PIL import Image

SUN = np.array([-0.45, 0.85, -0.35]); SUN /= np.linalg.norm(SUN)
SKY_TOP = np.array([0.80, 0.90, 1.0])
SKY_LOW = np.array([0.55, 0.62, 0.70])


def _camera(eye, target, W, H, fov):
    eye = np.asarray(eye, float); target = np.asarray(target, float)
    f = target - eye; f /= np.linalg.norm(f)
    r = np.cross(f, [0, 1, 0]); r /= np.linalg.norm(r)
    u = np.cross(r, f)
    tanh = math.tan(math.radians(fov) / 2)
    return eye, f, r, u, tanh


def _project(p, cam, W, H):
    eye, f, r, u, tanh = cam
    v = p - eye
    z = v @ f
    z = np.maximum(z, 1e-3)
    x = (v @ r) / z / tanh
    y = (v @ u) / z / tanh
    aspect = W / H
    px = (x / aspect * 0.5 + 0.5) * W
    py = (0.5 - y * 0.5) * H
    return px, py, z


def _intersect(kind, o, d, h):
    """o, d: (N,3) local rays; h half size. Returns t (inf = miss), normal (N,3) local."""
    N = o.shape[0]
    big = 1e9
    tn = np.full(N, -big); tf = np.full(N, big)
    nrm = np.zeros((N, 3))
    if kind in ("B", "W", "C"):
        axes = range(3) if kind != "C" else [0]
        with np.errstate(divide="ignore", invalid="ignore"):
            for a in axes:
                da = d[:, a]
                inv = np.where(np.abs(da) < 1e-12, np.inf, 1.0 / np.where(da == 0, 1, da))
                t1 = (-h[a] - o[:, a]) * inv
                t2 = (h[a] - o[:, a]) * inv
                par = np.abs(da) < 1e-12
                outside = par & (np.abs(o[:, a]) > h[a])
                lo = np.where(par, -big, np.minimum(t1, t2))
                hi = np.where(par, big, np.maximum(t1, t2))
                lo = np.where(outside, big, lo)
                upd = lo > tn
                tn = np.where(upd, lo, tn)
                n = np.zeros((N, 3)); n[:, a] = -np.sign(da)
                nrm = np.where(upd[:, None], n, nrm)
                tf = np.minimum(tf, hi)
    if kind == "W":
        pn = np.array([0.0, h[2], -h[1]]); pn /= np.linalg.norm(pn)
        den = d @ pn; num = -(o @ pn)
        with np.errstate(divide="ignore", invalid="ignore"):
            t = num / den
        ent = den < -1e-12
        ext = den > 1e-12
        par = ~ent & ~ext
        upd = ent & (t > tn)
        tn = np.where(upd, t, tn)
        nrm = np.where(upd[:, None], pn[None, :], nrm)
        tf = np.where(ext, np.minimum(tf, t), tf)
        tf = np.where(par & (num < 0), -big, tf)
    if kind == "C":
        rr = min(h[1], h[2])
        a = d[:, 1] ** 2 + d[:, 2] ** 2
        b = 2 * (o[:, 1] * d[:, 1] + o[:, 2] * d[:, 2])
        c = o[:, 1] ** 2 + o[:, 2] ** 2 - rr * rr
        disc = b * b - 4 * a * c
        ok = (disc >= 0) & (a > 1e-12)
        sq = np.sqrt(np.maximum(disc, 0))
        with np.errstate(divide="ignore", invalid="ignore"):
            t0 = (-b - sq) / (2 * a); t1 = (-b + sq) / (2 * a)
        t0 = np.where(ok, t0, big); t1 = np.where(ok, t1, -big)
        # parallel rays inside radius
        inside_par = (a <= 1e-12) & (c <= 0)
        t0 = np.where(inside_par, -big, t0); t1 = np.where(inside_par, big, t1)
        upd = t0 > tn
        p = o + d * t0[:, None]
        n = np.stack([np.zeros(N), p[:, 1], p[:, 2]], 1)
        n /= np.maximum(np.linalg.norm(n, axis=1, keepdims=True), 1e-9)
        tn = np.where(upd, t0, tn)
        nrm = np.where(upd[:, None], n, nrm)
        tf = np.minimum(tf, t1)
    if kind in ("E", "S"):
        hh = h if kind == "E" else np.full(3, min(h))
        oo = o / hh; dd = d / hh
        a = (dd * dd).sum(1); b = 2 * (oo * dd).sum(1); c = (oo * oo).sum(1) - 1
        disc = b * b - 4 * a * c
        ok = disc >= 0
        sq = np.sqrt(np.maximum(disc, 0))
        t0 = (-b - sq) / (2 * a); t1 = (-b + sq) / (2 * a)
        tn = np.where(ok, t0, big); tf = np.where(ok, t1, -big)
        p = o + d * tn[:, None]
        nrm = p / (hh * hh)
        nrm /= np.maximum(np.linalg.norm(nrm, axis=1, keepdims=True), 1e-9)
    hit = (tn <= tf) & (tf > 1e-4) & (tn > 1e-4)
    t = np.where(hit, tn, np.inf)
    return t, nrm


def _shade(col, n, view, mat, refl):
    """col (3,), n (N,3) world normals, view (N,3) dir from eye."""
    if mat == "Neon":
        return np.clip(np.tile(col * 1.15 + 0.08, (n.shape[0], 1)), 0, 1)
    ndl = n @ SUN
    diff = np.clip(ndl * 0.75 + 0.25, 0, 1)  # wrapped lambert
    hemi = (n[:, 1:2] * 0.5 + 0.5)
    amb = SKY_LOW * (1 - hemi) + SKY_TOP * hemi
    base = col[None, :] * (amb * 0.55 + diff[:, None] * 0.6)
    hv = SUN[None, :] - view
    hv /= np.linalg.norm(hv, axis=1, keepdims=True)
    nh = np.clip((n * hv).sum(1), 0, 1)
    metal = mat in ("Foil", "Metal", "DiamondPlate")
    shin = 60 if not metal else 30
    ks = 0.22 + refl * 1.5 + (0.45 if metal else 0)
    spec = ks * nh ** shin
    out = base + spec[:, None]
    if refl > 0 or metal:
        rv = view - 2 * (view * n).sum(1, keepdims=True) * n
        env = np.where(rv[:, 1:2] > 0, SKY_TOP[None, :] * (0.7 + 0.3 * rv[:, 1:2]), np.array([0.25, 0.45, 0.65])[None, :])
        k = min(0.6, refl + (0.3 if metal else 0))
        tint = col[None, :] if metal else 1
        out = out * (1 - k) + env * tint * k * 1.1
    # gentle rim light
    rim = np.clip(1 - np.abs((n * -view).sum(1)), 0, 1) ** 3 * 0.12
    out = out + rim[:, None]
    return np.clip(out, 0, 1)


def render(prims, eye, target, W=640, H=480, fov=34, water=None, bg=(0.91, 0.95, 0.98), ss=2, outline=True):
    W2, H2 = W * ss, H * ss
    cam = _camera(eye, target, W2, H2, fov)
    e, f, r, u, tanh = cam
    aspect = W2 / H2
    xs = ((np.arange(W2) + 0.5) / W2 * 2 - 1) * tanh * aspect
    ys = (1 - (np.arange(H2) + 0.5) / H2 * 2) * tanh
    X, Y = np.meshgrid(xs, ys)
    D = f[None, None, :] + X[..., None] * r[None, None, :] + Y[..., None] * u[None, None, :]
    D /= np.linalg.norm(D, axis=2, keepdims=True)
    depth = np.full((H2, W2), np.inf)
    ids = np.full((H2, W2), -1, int)
    img = np.zeros((H2, W2, 3)); img[:] = bg
    # background gradient
    g = np.linspace(0, 1, H2)[:, None, None]
    img = img * (1 - g * 0.12)
    opaque = [(i, p) for i, p in enumerate(prims) if p.get("t", 0) < 0.05]
    trans = [(i, p) for i, p in enumerate(prims) if p.get("t", 0) >= 0.05]

    def raycast(p, mask_fn=None):
        R = np.asarray(p["r"], float)
        c = np.asarray(p["c"], float); h = np.asarray(p["s"], float) / 2
        corners = np.array([[sx, sy, sz] for sx in (-1, 1) for sy in (-1, 1) for sz in (-1, 1)]) * h
        wc = corners @ R.T + c
        px, py, z = _project(wc, cam, W2, H2)
        if (z <= 1e-3).all():
            return None
        x0 = max(int(px.min()) - 2, 0); x1 = min(int(px.max()) + 3, W2)
        y0 = max(int(py.min()) - 2, 0); y1 = min(int(py.max()) + 3, H2)
        if x0 >= x1 or y0 >= y1:
            return None
        d = D[y0:y1, x0:x1].reshape(-1, 3)
        o = np.tile(e - c, (d.shape[0], 1))
        ol = o @ R; dl = d @ R  # world->local: R^T v  == v @ R
        t, nl = _intersect(p["kind"], ol, dl, h)
        nw = nl @ R.T
        return (y0, y1, x0, x1), t.reshape(y1 - y0, x1 - x0), nw.reshape(y1 - y0, x1 - x0, 3), d.reshape(y1 - y0, x1 - x0, 3)

    for i, p in opaque:
        res = raycast(p)
        if res is None:
            continue
        (y0, y1, x0, x1), t, nw, d = res
        sub = depth[y0:y1, x0:x1]
        win = t < sub
        if not win.any():
            continue
        sub[win] = t[win]
        ids[y0:y1, x0:x1][win] = i
        col = np.asarray(p["col"], float)
        sh = _shade(col, nw[win], d[win], p.get("mat", ""), p.get("refl", 0))
        img[y0:y1, x0:x1][win] = sh
    # transparent layers (back to front, single blend each)
    layers = []
    if water is not None:
        # water plane: y = water
        with np.errstate(divide="ignore", invalid="ignore"):
            tw = (water - e[1]) / D[..., 1]
        tw = np.where(tw > 0, tw, np.inf)
        layers.append((np.nanmean(np.where(np.isfinite(tw), tw, np.nan)) if np.isfinite(tw).any() else 0, "water", tw))
    for i, p in trans:
        res = raycast(p)
        if res is not None:
            dist = np.linalg.norm(np.asarray(p["c"]) - e)
            layers.append((dist, "prim", (i, p, res)))
    layers.sort(key=lambda L: -L[0])
    for _, kind, data in layers:
        if kind == "water":
            tw = data
            m = tw < depth
            P = e[None, None, :] + D * np.where(np.isfinite(tw), tw, 0)[..., None]
            ripple = 0.03 * np.sin(P[..., 0] * 2.2 + P[..., 2] * 1.3)
            wc = np.array([0.22, 0.55, 0.85]) + ripple[..., None]
            a = 0.55
            # depth fog for submerged stuff
            img[m] = img[m] * (1 - a) + wc[m] * a
        else:
            i, p, res = data
            (y0, y1, x0, x1), t, nw, d = res
            sub = depth[y0:y1, x0:x1]
            win = t < sub
            if not win.any():
                continue
            col = np.asarray(p["col"], float)
            sh = _shade(col, nw[win], d[win], p.get("mat", ""), p.get("refl", 0) + 0.15)
            a = 1 - p["t"]
            tile = img[y0:y1, x0:x1]
            tile[win] = tile[win] * (1 - a) + sh * a
    if outline:
        dep = np.where(np.isfinite(depth), depth, 1e4)
        edge = np.zeros((H2, W2), bool)
        soft = np.zeros((H2, W2), bool)
        for dy, dx in ((0, 1), (1, 0)):
            a = dep; b = np.roll(dep, (-dy, -dx), (0, 1))
            jump = np.abs(a - b) > 0.06 * np.minimum(a, b) ** 0.5 + 0.08
            edge |= jump
            ia = ids; ib = np.roll(ids, (-dy, -dx), (0, 1))
            soft |= (ia != ib)
        img[edge] *= 0.25
        img[soft & ~edge] *= 0.82
    out = Image.fromarray((np.clip(img, 0, 1) * 255).astype(np.uint8))
    if ss > 1:
        out = out.resize((W, H), Image.LANCZOS)
    return out
