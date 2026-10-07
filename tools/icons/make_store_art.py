"""Game icon (512x512) and thumbnail (1920x1080) in the same style as the
icon set. Writes build/store_icon.html and build/store_thumb.html; render.sh
turns them into PNGs (copied to assets/store/)."""
import os

import make_icons as I

INK = I.INK


def sea(w, h, horizon):
    s = (
        '<linearGradient id="sky" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#3fb6ff"/><stop offset="1" stop-color="#bff0ff"/></linearGradient>'
        '<linearGradient id="sea" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#2ee6ff"/><stop offset="0.5" stop-color="#14b5e8"/><stop offset="1" stop-color="#0a64c8"/></linearGradient>'
        '<radialGradient id="sun" cx="0.5" cy="0.5" r="0.5"><stop offset="0" stop-color="#fffbe0"/><stop offset="0.5" stop-color="#ffe680" stop-opacity="0.8"/><stop offset="1" stop-color="#ffe680" stop-opacity="0"/></radialGradient>'
    )
    s += f'<rect width="{w}" height="{h}" fill="url(#sky)"/>'
    # sun rays
    cx, cy = w * 0.5, horizon * 0.55
    rays = ""
    for i in range(16):
        rays += f'<polygon points="{cx},{cy} {cx + 2000},{cy - 130} {cx + 2000},{cy + 130}" fill="#ffffff" opacity="0.12" transform="rotate({i * 22.5} {cx} {cy})"/>'
    s += rays
    s += f'<circle cx="{cx}" cy="{cy}" r="{h * 0.32}" fill="url(#sun)"/>'
    # clouds
    for x, y, k in ((w * 0.12, horizon * 0.3, 1.0), (w * 0.82, horizon * 0.22, 1.2), (w * 0.62, horizon * 0.5, 0.7)):
        r = h * 0.07 * k
        s += f'<g opacity="0.95">' + "".join(
            f'<circle cx="{x + dx * r}" cy="{y + dy * r}" r="{r * rr}" fill="#ffffff"/>'
            for dx, dy, rr in ((0, 0, 1), (1.1, 0.2, 0.8), (-1.1, 0.25, 0.75), (0.5, -0.5, 0.8))
        ) + "</g>"
    s += f'<rect y="{horizon}" width="{w}" height="{h - horizon}" fill="url(#sea)"/>'
    for i in range(7):
        y = horizon + (h - horizon) * (0.12 + i * 0.13)
        amp = 6 + i * 3
        d = f"M0,{y}"
        x = 0
        while x < w:
            d += f" q{amp * 3},{-amp} {amp * 6},0"
            x += amp * 6
        s += f'<path d="{d}" fill="none" stroke="#ffffff" stroke-width="{3 + i}" opacity="0.35" stroke-linecap="round"/>'
    return s


def avatar_on_duck(x, y, sc):
    """A blocky player in the rubber duck, fleeing left, looking back in panic."""
    s = f'<g transform="translate({x},{y}) scale({sc})">'
    # the player sits in the duck's body (drawn first so the duck rim overlaps)
    s += '<g transform="translate(86,40)">'
    s += f'<rect class="t" x="108" y="34" width="50" height="16" rx="8" fill="{I.g("blue")}" transform="rotate(-50 112 42)"/>'
    s += f'<rect class="t" x="34" y="30" width="50" height="16" rx="8" fill="{I.g("blue")}" transform="rotate(40 80 38)"/>'
    s += f'<rect class="o" x="80" y="30" width="46" height="48" rx="6" fill="{I.g("blue")}"/>'
    s += f'<rect class="o" x="76" y="-18" width="54" height="50" rx="10" fill="#ffd34d"/>'
    for ex in (98, 118):
        s += f'<circle cx="{ex}" cy="4" r="8" fill="#ffffff" stroke="{INK}" stroke-width="3"/><circle cx="{ex + 3}" cy="4" r="4.5" fill="{INK}"/>'
    s += f'<ellipse cx="108" cy="22" rx="7" ry="6" fill="{INK}"/>'
    s += f'<rect class="t" x="72" y="-28" width="62" height="16" rx="6" fill="{I.g("red")}"/>'
    s += "</g>"
    # duck faces left (away from the shark)
    s += f'<g transform="translate(256,0) scale(-1,1)">{I.duck("gold")}</g>'
    s += "</g>"
    return s


def splash(x, y, sc):
    s = f'<g transform="translate({x},{y}) scale({sc})">'
    for dx, dy, r in ((-60, -10, 26), (-20, -40, 34), (30, -30, 30), (70, -6, 22), (0, 0, 40)):
        s += f'<circle cx="{dx}" cy="{dy}" r="{r}" fill="#ffffff" stroke="{INK}" stroke-width="7"/>'
    s += "</g>"
    return s


def big_text(x, y, text, size, fill, anchor="middle", rot=0):
    return (
        f'<text x="{x}" y="{y}" font-family="Inter" font-weight="900" font-size="{size}" text-anchor="{anchor}" '
        f'fill="{fill}" stroke="{INK}" stroke-width="{size * 0.16:.0f}" stroke-linejoin="round" paint-order="stroke fill" '
        f'transform="rotate({rot} {x} {y})">{text}</text>'
    )


def page(w, h, body):
    return (
        '<!doctype html><html><head><style>html,body{margin:0;background:transparent}</style></head><body>'
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 {w} {h}"><style>{I.STYLE}</style>{I.defs()}'
        f"{body}</svg></body></html>"
    )


def store_icon():
    w = h = 512
    s = sea(w, h, 250)
    s += f'<g filter="url(#ds)">{I.shark_body(196, 160, 1.4, flip=True)}</g>'
    s += f'<g filter="url(#ds)">{avatar_on_duck(-8, 240, 1.0)}</g>'
    s += big_text(256, 98, "+1 SPEED", 96, "#ffe23a", rot=-4)
    s += f'<rect x="8" y="8" width="496" height="496" rx="56" fill="none" stroke="{INK}" stroke-width="16"/>'
    return page(w, h, s)


def store_thumb():
    w, h = 1920, 1080
    s = sea(w, h, 470)
    s += f'<g transform="translate(40,700) scale(1.15)">{I.i_island()}</g>'
    s += f'<g filter="url(#ds)">{I.shark_body(950, 330, 3.3, flip=True)}</g>'
    for i, y in enumerate((700, 780, 860)):
        s += f'<line x1="{880 - i * 30}" y1="{y}" x2="{1000 - i * 30}" y2="{y}" stroke="#ffffff" stroke-width="16" stroke-linecap="round" opacity="0.85"/>'
    s += f'<g filter="url(#ds)">{avatar_on_duck(330, 520, 2.3)}</g>'
    s += big_text(640, 200, "+1 SPEED", 210, "#ffe23a", rot=-4)
    s += big_text(680, 380, "ESCAPE THE SHARK!", 116, "#ffffff", rot=-4)
    s += f'<g transform="translate(1560,40) scale(1.2)">{I.bubble(128, 124, 100, "glass")}{I.clownfish(128, 124, 1.6)}</g>'
    return page(w, h, s)


if __name__ == "__main__":
    out = os.path.join(os.path.dirname(__file__), "build")
    os.makedirs(out, exist_ok=True)
    open(os.path.join(out, "store_icon.html"), "w").write(store_icon())
    open(os.path.join(out, "store_thumb.html"), "w").write(store_thumb())
    print("wrote store art")
