"""Particle textures for the game's VFX (assets/vfx/*.png).

White on transparent: Roblox tints particles with their Color, so one white
texture serves every rarity / zone color. 256x256, soft edges (no hard
pixels when a particle grows big on screen). Upload each PNG (Asset Manager
> Import) and paste the id next to its name in Config.Images.Vfx.

    python3 tools/vfx/make_vfx.py          # writes assets/vfx/*.png + sheet
"""
import math
import os

import numpy as np
from PIL import Image

N = 256
OUT = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "vfx")

yy, xx = np.mgrid[0:N, 0:N].astype(np.float64)
cx = cy = (N - 1) / 2
dx, dy = (xx - cx) / (N / 2), (yy - cy) / (N / 2)  # -1..1
r = np.sqrt(dx * dx + dy * dy)
ang = np.arctan2(dy, dx)


def smooth(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)


def save(name, alpha, rgb=None):
    a = np.clip(alpha, 0, 1)
    img = np.zeros((N, N, 4), np.uint8)
    col = np.ones((N, N, 3)) if rgb is None else np.clip(rgb, 0, 1)
    img[..., :3] = (col * 255).astype(np.uint8)
    img[..., 3] = (a * 255).astype(np.uint8)
    Image.fromarray(img, "RGBA").save(os.path.join(OUT, name + ".png"))
    return img


def glow():
    # soft round light: bright core, long falloff
    return np.exp(-(r * 2.6) ** 2) * 0.9 + np.exp(-(r * 6) ** 2) * 0.4 * (1 - smooth(0.9, 1, r))


def star():
    # four-point glint (+ a fainter diagonal pair) over a small glow
    def ray(theta, width, length):
        d = np.abs(np.sin(ang - theta)) * r  # distance from the ray's line
        along = np.abs(np.cos(ang - theta)) * r
        return np.exp(-(d / width) ** 2) * np.clip(1 - along / length, 0, 1) ** 1.6
    a = ray(0, 0.045, 1.0) + ray(math.pi / 2, 0.045, 1.0)
    a += 0.45 * (ray(math.pi / 4, 0.03, 0.55) + ray(-math.pi / 4, 0.03, 0.55))
    a += np.exp(-(r * 7) ** 2)
    return a * (1 - smooth(0.92, 1, r))


def ring():
    # shockwave: a bright thin band with a soft inner haze
    band = np.exp(-((r - 0.82) / 0.05) ** 2)
    haze = smooth(0.35, 0.8, r) * (1 - smooth(0.8, 0.9, r)) * 0.25
    return band + haze


def smoke(seed=3):
    # puffy cloud: soft blobs summed (no seams), lit from the top
    rng = np.random.default_rng(seed)
    dens = np.zeros((N, N))
    shade = np.zeros((N, N))
    for _ in range(16):
        bx, by = rng.normal(0, 0.24, 2)
        br = rng.uniform(0.22, 0.4)
        d = np.sqrt((dx - bx) ** 2 + (dy - by) ** 2) / br
        blob = np.exp(-d ** 2 * 1.8)
        dens += blob
        shade += blob * np.clip(0.5 - (dy - by) / br * 0.5, 0, 1)
    a = (1 - np.exp(-dens * 1.6)) * (1 - smooth(0.65, 1, r))
    lit = 0.8 + 0.2 * np.clip(shade / (dens + 1e-6), 0, 1)
    return a * 0.9, np.stack([lit] * 3, -1)


def streak():
    # a spark / speed streak, vertical: particles with VelocityParallel
    # line it up with the way they fly
    a = np.exp(-(dx / 0.05) ** 2) * np.clip(1 - np.abs(dy), 0, 1) ** 1.2
    a += 0.5 * np.exp(-(dx / 0.14) ** 2) * np.clip(1 - np.abs(dy) * 1.4, 0, 1) ** 2
    return a


def burst():
    # impact star: uneven radial spikes, the anime "hit" shape
    rng = np.random.default_rng(7)
    spikes = 14
    lens = rng.uniform(0.55, 1.0, spikes)
    a = np.zeros((N, N))
    for i in range(spikes):
        th = i / spikes * 2 * math.pi + rng.uniform(-0.08, 0.08)
        d = np.abs(np.sin(ang - th)) * r
        along = np.cos(ang - th) * r
        w = 0.06 * np.clip(1 - along / lens[i], 0, 1)
        a = np.maximum(a, (along > 0) * smooth(0, 1, (w - d) / 0.02 + 0.5) * (along < lens[i]))
    a = np.maximum(a, np.exp(-(r * 3.2) ** 2))
    return a


def droplet():
    # water drop (tip up, it flies upward): round body, pointed top, highlight
    body = np.sqrt(dx ** 2 + (dy - 0.2) ** 2) - 0.5
    cone = np.abs(dx) - (dy + 0.85) * 0.5
    cone = np.where(dy < -0.85, 1, np.where(dy > 0.0, 1, cone))
    d = np.minimum(body, cone)
    a = (1 - smooth(-0.02, 0.03, d)) * 0.55
    hl = np.exp(-(((dx + 0.18) / 0.09) ** 2 + ((dy - 0.12) / 0.15) ** 2))
    return np.clip(a + hl * 0.6, 0, 1)


def bubble():
    rim = np.exp(-((r - 0.78) / 0.07) ** 2)
    inside = (1 - smooth(0.7, 0.8, r)) * 0.12
    hl = np.exp(-(((dx + 0.35) / 0.14) ** 2 + ((dy + 0.35) / 0.1) ** 2))
    return rim + inside + hl * 0.9


def beam():
    # a soft light shaft for Beams (Beam textures run along the image's X,
    # so the bright core is a horizontal line; the Beam fades the ends)
    return np.exp(-(dy / 0.34) ** 2) * (0.55 + 0.45 * np.exp(-(dy / 0.09) ** 2)) + 0 * dx


TEXTURES = {
    "Glow": glow,
    "Star": star,
    "Ring": ring,
    "Smoke": smoke,
    "Streak": streak,
    "Burst": burst,
    "Droplet": droplet,
    "Bubble": bubble,
    "Beam": beam,
}


def main():
    os.makedirs(OUT, exist_ok=True)
    tiles = []
    for name, fn in TEXTURES.items():
        res = fn()
        img = save(name, *res) if isinstance(res, tuple) else save(name, res)
        tiles.append(img)
    # a contact sheet on dark blue, to eyeball them
    cols = 5
    rows = math.ceil(len(tiles) / cols)
    sheet = Image.new("RGBA", (cols * N, rows * N), (20, 34, 70, 255))
    for i, t in enumerate(tiles):
        sheet.alpha_composite(Image.fromarray(t, "RGBA"), ((i % cols) * N, (i // cols) * N))
    sheet.convert("RGB").save(os.path.join(OUT, "..", "..", "tools", "vfx", "sheet.png"))
    print("wrote", len(tiles), "textures to", os.path.normpath(OUT))


if __name__ == "__main__":
    main()
