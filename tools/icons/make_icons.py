"""Shark Escape icon set -> two 1024x1024 sprite sheets (4x4 grid of 256px cells).

One style for every icon: thick ink outline, hard drop shadow, top-lit
gradient and a gloss highlight. Run:

    python3 tools/icons/make_icons.py            # writes tools/icons/build/*.html
    (then the render step in README / render.sh turns them into PNGs)

The cell order here MUST match Config.Icons in src/shared/Config.luau.
"""
import math
import os

INK = "#15151f"
OUT = os.path.join(os.path.dirname(__file__), "build")

GRADS = {
    "gold": ("#fff27a", "#ffc21a", "#e88a00"),
    "red": ("#ff8a80", "#ff3b3b", "#c4121f"),
    "blue": ("#8fe0ff", "#2ea8ff", "#1260e0"),
    "green": ("#b6ff7a", "#4fd43a", "#1f9a2a"),
    "pink": ("#ffb3e1", "#ff4fb0", "#d6157e"),
    "orange": ("#ffd27a", "#ff9a1f", "#e85d00"),
    "purple": ("#e2b8ff", "#a65cff", "#6b1fe0"),
    "white": ("#ffffff", "#f2f6fb", "#c9d6e4"),
    "gray": ("#eef2f7", "#b8c3d1", "#7a8799"),
    "teal": ("#b5fbff", "#38dcef", "#0f9fbf"),
    "brown": ("#f0b878", "#c47f3e", "#8a4e1c"),
    "shark": ("#c4e6ff", "#7fb4e0", "#3f73a8"),
    "darkred": ("#c0303c", "#8a1424", "#5a0b16"),
    "sand": ("#fff3c4", "#ffd97a", "#e6b04a"),
    "glass": ("#e8fbff", "#9fe8ff", "#58c6f0"),
    "silver": ("#ffffff", "#d7dee8", "#8f9cad"),
}


def defs():
    out = ["<defs>"]
    for name, (a, b, c) in GRADS.items():
        out.append(
            f'<linearGradient id="g-{name}" x1="0" y1="0" x2="0" y2="1">'
            f'<stop offset="0" stop-color="{a}"/><stop offset="0.5" stop-color="{b}"/><stop offset="1" stop-color="{c}"/>'
            "</linearGradient>"
        )
    out.append(
        '<linearGradient id="g-rainbow" x1="0" y1="0" x2="1" y2="0">'
        + "".join(
            f'<stop offset="{i/6:.3f}" stop-color="{c}"/>'
            for i, c in enumerate(["#ff4d4d", "#ff9a1f", "#ffe23a", "#4fd43a", "#2ea8ff", "#7a5cff", "#ff4fb0"])
        )
        + "</linearGradient>"
    )
    out.append(
        '<filter id="ds" x="-20%" y="-20%" width="140%" height="150%">'
        f'<feDropShadow dx="0" dy="9" stdDeviation="0" flood-color="{INK}" flood-opacity="0.38"/></filter>'
    )
    out.append("</defs>")
    return "".join(out)


STYLE = f"""
.o {{ stroke:{INK}; stroke-width:16; stroke-linejoin:round; stroke-linecap:round; paint-order:stroke fill; }}
.t {{ stroke:{INK}; stroke-width:10; stroke-linejoin:round; stroke-linecap:round; paint-order:stroke fill; }}
.l {{ fill:none; stroke:{INK}; stroke-width:9; stroke-linecap:round; stroke-linejoin:round; }}
.hl {{ fill:#ffffff; opacity:0.55; }}
.hl2 {{ fill:none; stroke:#ffffff; stroke-width:9; stroke-linecap:round; opacity:0.6; }}
.txt {{ font-family:'Inter'; font-weight:900; stroke:{INK}; stroke-width:16; paint-order:stroke fill; stroke-linejoin:round; }}
"""


def g(name):
    return f"url(#g-{name})"


def pol(pts):
    return " ".join(f"{x:.1f},{y:.1f}" for x, y in pts)


# ----------------------------------------------------------------- icons
def bolt(scale=1.0, dx=0, dy=0, color="gold"):
    pts = [(152, 14), (54, 142), (116, 142), (92, 242), (204, 100), (140, 100), (176, 14)]
    pts = [(128 + (x - 128) * scale + dx, 128 + (y - 128) * scale + dy) for x, y in pts]
    hl = [(150, 34), (84, 128), (106, 128), (156, 48)]
    hl = [(128 + (x - 128) * scale + dx, 128 + (y - 128) * scale + dy) for x, y in hl]
    return f'<polygon class="o" fill="{g(color)}" points="{pol(pts)}"/><polygon class="hl" points="{pol(hl)}"/>'


def i_speed():
    return bolt()


def coin(cx=128, cy=122, r=94, emboss="fin"):
    s = f'<ellipse class="o" cx="{cx}" cy="{cy+14}" rx="{r}" ry="{r*0.98}" fill="#c27400"/>'
    s += f'<circle class="o" cx="{cx}" cy="{cy}" r="{r}" fill="{g("gold")}"/>'
    s += f'<circle cx="{cx}" cy="{cy}" r="{r*0.72}" fill="none" stroke="#e08a00" stroke-width="{r*0.09:.1f}"/>'
    if emboss == "fin":
        k = r / 94
        s += (
            f'<path d="M{cx-38*k},{cy+34*k} Q{cx-4*k},{cy-50*k} {cx+40*k},{cy-50*k} Q{cx+18*k},{cy-6*k} {cx+30*k},{cy+34*k} Z" '
            f'fill="#e08a00" stroke="#c46f00" stroke-width="{4*k:.1f}" stroke-linejoin="round"/>'
        )
    s += f'<path class="hl2" d="M{cx-r*0.62},{cy-r*0.28} A{r*0.7},{r*0.7} 0 0 1 {cx-r*0.1},{cy-r*0.7}"/>'
    return s


def i_coins():
    return coin()


def i_rides():
    cx, cy, r, w = 128, 128, 72, 48
    s = f'<circle cx="{cx}" cy="{cy}" r="{r}" fill="none" stroke="{INK}" stroke-width="{w+18}" filter="url(#ds)"/>'
    s += f'<circle cx="{cx}" cy="{cy}" r="{r}" fill="none" stroke="#f4f8ff" stroke-width="{w}"/>'
    circ = 2 * math.pi * r
    seg = circ / 8
    s += (
        f'<circle cx="{cx}" cy="{cy}" r="{r}" fill="none" stroke="#ff3b3b" stroke-width="{w}" '
        f'stroke-dasharray="{seg:.1f} {seg:.1f}" transform="rotate(-22 {cx} {cy})"/>'
    )
    # shading on the lower half + ink seams
    s += f'<path d="M{cx-r-w/2},{cy} A{r+w/2},{r+w/2} 0 0 0 {cx+r+w/2},{cy} L{cx+r-w/2},{cy} A{r-w/2},{r-w/2} 0 0 1 {cx-r+w/2},{cy} Z" fill="#000" opacity="0.12"/>'
    s += f'<circle cx="{cx}" cy="{cy}" r="{r+w/2}" fill="none" stroke="{INK}" stroke-width="9"/>'
    s += f'<circle cx="{cx}" cy="{cy}" r="{r-w/2}" fill="none" stroke="{INK}" stroke-width="9"/>'
    # rope
    s += f'<circle cx="{cx}" cy="{cy}" r="{r}" fill="none" stroke="#f7e3b0" stroke-width="5" stroke-dasharray="14 10"/>'
    s += f'<path class="hl2" d="M{cx-r-8},{cy-26} A{r+8},{r+8} 0 0 1 {cx-24},{cy-r-8}"/>'
    return s


def i_index():
    s = f'<g filter="url(#ds)"><rect class="o" x="58" y="40" width="160" height="186" rx="16" fill="#ffffff"/>'
    s += f'<rect x="58" y="196" width="160" height="22" fill="#e9eef5"/>'
    for y in (204, 212):
        s += f'<line x1="70" y1="{y}" x2="206" y2="{y}" stroke="#c3cdda" stroke-width="3"/>'
    s += f'<rect class="o" x="40" y="26" width="160" height="178" rx="16" fill="{g("orange")}"/></g>'
    s += f'<rect x="40" y="26" width="30" height="178" rx="12" fill="#c45200" opacity="0.55"/>'
    s += f'<line x1="70" y1="34" x2="70" y2="196" stroke="{INK}" stroke-width="7"/>'
    # fish emblem
    s += '<g transform="translate(136,112)">'
    s += f'<path class="t" d="M-44,0 C-30,-30 18,-34 40,0 C18,34 -30,30 -44,0 Z" fill="#ffffff"/>'
    s += f'<path class="t" d="M36,0 L60,-22 L56,0 L60,22 Z" fill="#ffffff"/>'
    s += f'<circle cx="-22" cy="-6" r="6" fill="{INK}"/></g>'
    s += '<rect class="hl" x="84" y="38" width="96" height="14" rx="7"/>'
    return s


def i_shop():
    s = '<g filter="url(#ds)">'
    s += f'<path class="l" d="M18,44 L50,44 L80,176 L198,176" stroke-width="30"/>'
    s += f'<path d="M18,44 L50,44 L80,176 L198,176" fill="none" stroke="{g("silver")}" stroke-width="14" stroke-linecap="round" stroke-linejoin="round"/>'
    s += f'<path class="o" d="M58,70 L232,70 L210,156 L80,156 Z" fill="{g("pink")}"/>'
    for x in (104, 146, 188):
        s += f'<line x1="{x}" y1="80" x2="{x - 6}" y2="146" stroke="#ffffff" stroke-width="7" opacity="0.6" stroke-linecap="round"/>'
    s += f'<line x1="70" y1="112" x2="220" y2="112" stroke="#ffffff" stroke-width="7" opacity="0.6" stroke-linecap="round"/>'
    for x in (96, 184):
        s += f'<circle class="t" cx="{x}" cy="206" r="22" fill="{g("gray")}"/><circle cx="{x}" cy="206" r="7" fill="{INK}"/>'
    s += "</g>"
    s += '<path class="hl" d="M66,76 L224,76 L220,90 L70,90 Z" opacity="0.4"/>'
    return s


def arc_pt(a, r=72, c=(128, 128)):
    return c[0] + r * math.cos(math.radians(a)), c[1] + r * math.sin(math.radians(a))


def arrow_arc(a0, a1, color, r=72):
    x0, y0 = arc_pt(a0, r)
    x1, y1 = arc_pt(a1, r)
    d = f"M{x0:.1f},{y0:.1f} A{r},{r} 0 0 1 {x1:.1f},{y1:.1f}"
    # arrowhead at a1 pointing clockwise
    tx, ty = -math.sin(math.radians(a1)), math.cos(math.radians(a1))
    nx, ny = math.cos(math.radians(a1)), math.sin(math.radians(a1))
    tip = (x1 + tx * 46, y1 + ty * 46)
    b1 = (x1 + nx * 40, y1 + ny * 40)
    b2 = (x1 - nx * 40, y1 - ny * 40)
    s = f'<path d="{d}" fill="none" stroke="{INK}" stroke-width="58" stroke-linecap="round"/>'
    s += f'<polygon class="o" points="{pol([tip, b1, b2])}" fill="{color}"/>'
    s += f'<path d="{d}" fill="none" stroke="{color}" stroke-width="40" stroke-linecap="round"/>'
    return s


def i_rebirth():
    s = '<g filter="url(#ds)">'
    s += arrow_arc(160, 320, g("green"))
    s += arrow_arc(340, 140, g("green"))
    s += "</g>"
    s += '<path class="hl2" d="M66,104 A66,66 0 0 1 104,62"/>'
    return s


def shark_body(tx=0, ty=0, sc=1.0, flip=False):
    tr = f"translate({tx},{ty}) scale({-sc if flip else sc},{sc})"
    if flip:
        tr = f"translate({tx + 256 * sc},{ty}) scale({-sc},{sc})"
    s = f'<g transform="{tr}">'
    s += f'<polygon points="236,124 192,134 234,152" fill="{g("darkred")}" class="t"/>'
    s += f'<path class="o" d="M60,128 L18,82 L32,128 L18,176 Z" fill="{g("shark")}"/>'
    s += f'<path class="o" d="M110,80 L130,20 L166,76 Z" fill="{g("shark")}"/>'
    s += f'<path class="o" d="M120,168 L94,216 L156,178 Z" fill="{g("shark")}"/>'
    s += (
        f'<path class="o" d="M46,128 C70,70 150,56 202,88 C222,100 236,114 240,124 L192,134 L236,152 '
        f'C218,184 160,202 110,188 C80,180 60,162 46,128 Z" fill="{g("shark")}"/>'
    )
    s += f'<path d="M70,150 C110,184 170,186 226,156 L194,138 C170,156 120,164 70,150 Z" fill="#ffffff"/>'
    # teeth
    for x, y in [(228, 125), (216, 127), (204, 130)]:
        s += f'<polygon points="{x-5},{y} {x+5},{y-1} {x},{y+10}" fill="#ffffff" stroke="{INK}" stroke-width="2.5"/>'
    for x, y in [(222, 150), (210, 146), (199, 141)]:
        s += f'<polygon points="{x-5},{y} {x+5},{y+1} {x},{y-10}" fill="#ffffff" stroke="{INK}" stroke-width="2.5"/>'
    s += f'<circle cx="184" cy="100" r="11" fill="#ffffff" stroke="{INK}" stroke-width="4"/><circle cx="187" cy="101" r="6" fill="{INK}"/>'
    s += f'<path d="M168,84 L198,92" stroke="{INK}" stroke-width="7" stroke-linecap="round"/>'
    for x in (140, 152, 164):
        s += f'<path d="M{x},106 Q{x-6},120 {x},134" fill="none" stroke="{INK}" stroke-width="4" stroke-linecap="round" opacity="0.7"/>'
    s += '<path class="hl2" d="M86,104 C110,82 140,76 168,78"/>'
    s += "</g>"
    return s


def i_shark():
    return f'<g filter="url(#ds)">{shark_body()}</g>'


def clownfish(tx, ty, sc=1.0):
    s = f'<g transform="translate({tx},{ty}) scale({sc})">'
    s += f'<path class="t" d="M28,0 L48,-18 L44,0 L48,18 Z" fill="{g("orange")}"/>'
    s += f'<ellipse class="t" cx="0" cy="0" rx="34" ry="22" fill="{g("orange")}"/>'
    s += f'<path d="M-8,-21 Q-2,0 -8,21" stroke="#ffffff" stroke-width="9" fill="none"/>'
    s += f'<path d="M14,-18 Q20,0 14,18" stroke="#ffffff" stroke-width="8" fill="none"/>'
    s += f'<circle cx="-20" cy="-5" r="5" fill="{INK}"/></g>'
    return s


def tank(x=30, y=56, w=196, h=158):
    s = f'<g filter="url(#ds)"><rect class="o" x="{x}" y="{y}" width="{w}" height="{h}" rx="16" fill="{g("glass")}"/></g>'
    s += f'<rect x="{x+6}" y="{y+h-34}" width="{w-12}" height="28" rx="8" fill="{g("sand")}"/>'
    s += f'<path d="M{x+6},{y+30} Q{x+w/4},{y+22} {x+w/2},{y+30} T{x+w-6},{y+30}" fill="none" stroke="#ffffff" stroke-width="6" opacity="0.8"/>'
    s += clownfish(x + w / 2 - 6, y + h / 2 + 4, 1.25)
    for bx, by, br in [(x + w - 40, y + 60, 8), (x + w - 30, y + 84, 5), (x + 40, y + 52, 6)]:
        s += f'<circle cx="{bx}" cy="{by}" r="{br}" fill="none" stroke="#ffffff" stroke-width="4"/>'
    s += f'<rect class="o" x="{x-8}" y="{y-14}" width="{w+16}" height="26" rx="10" fill="{g("blue")}"/>'
    s += f'<rect class="hl" x="{x+14}" y="{y+22}" width="14" height="{h-70}" rx="7" opacity="0.45"/>'
    return s


def i_tank():
    return tank()


def shield(fill="blue", emblem=True):
    s = f'<g filter="url(#ds)"><path class="o" d="M128,20 L218,52 C218,140 186,198 128,236 C70,198 38,140 38,52 Z" fill="{g(fill)}"/></g>'
    s += f'<path d="M128,44 L196,68 C194,136 170,180 128,210 C86,180 62,136 60,68 Z" fill="none" stroke="#ffffff" stroke-width="7" opacity="0.5"/>'
    if emblem:
        s += f'<path class="t" d="M96,166 Q124,82 168,74 Q150,120 160,166 Z" fill="#ffffff"/>'
    s += '<path class="hl" d="M58,60 L124,36 L124,58 L76,76 Z" opacity="0.5"/>'
    return s


def i_shield():
    return shield()


def i_boost():
    s = '<g filter="url(#ds)">'
    s += f'<polygon class="o" points="24,52 124,128 24,204" fill="{g("orange")}"/>'
    s += f'<polygon class="o" points="116,52 216,128 116,204" fill="{g("orange")}"/>'
    s += "</g>"
    s += '<polygon class="hl" points="40,82 92,120 40,108" opacity="0.5"/><polygon class="hl" points="132,82 184,120 132,108" opacity="0.5"/>'
    return s


def clover(cx, cy, r, ink=True):
    s = ""
    cls = "t" if ink else ""
    for a in (0, 90, 180, 270):
        x = cx + math.cos(math.radians(a - 45)) * r * 0.62
        y = cy + math.sin(math.radians(a - 45)) * r * 0.62
        s += f'<circle class="{cls}" cx="{x:.1f}" cy="{y:.1f}" r="{r*0.52:.1f}" fill="{g("green")}"/>'
    s += f'<circle cx="{cx}" cy="{cy}" r="{r*0.3:.1f}" fill="#3fbf2f"/>'
    return s


def i_potion():
    s = '<g filter="url(#ds)">'
    s += f'<path class="o" d="M104,30 L152,30 L152,92 C196,106 214,142 206,178 C198,216 162,236 128,236 C94,236 58,216 50,178 C42,142 60,106 104,92 Z" fill="{g("glass")}"/>'
    s += "</g>"
    s += f'<path d="M58,162 C70,150 100,146 128,154 C156,162 186,156 200,148 C202,190 172,226 128,226 C84,226 56,198 58,162 Z" fill="{g("green")}"/>'
    s += f'<rect class="t" x="96" y="16" width="64" height="30" rx="8" fill="{g("brown")}"/>'
    s += clover(128, 184, 30, False)
    for bx, by, br in [(92, 140, 6), (166, 124, 5)]:
        s += f'<circle cx="{bx}" cy="{by}" r="{br}" fill="none" stroke="#ffffff" stroke-width="3.5"/>'
    s += '<path class="hl2" d="M74,150 C72,132 84,116 100,108"/>'
    return s


def i_lock():
    s = f'<path d="M78,118 L78,84 A50,50 0 0 1 178,84 L178,118" fill="none" stroke="{INK}" stroke-width="44"/>'
    s += f'<path d="M78,118 L78,84 A50,50 0 0 1 178,84 L178,118" fill="none" stroke="{g("silver")}" stroke-width="26"/>'
    s += f'<g filter="url(#ds)"><rect class="o" x="44" y="108" width="168" height="124" rx="22" fill="{g("gold")}"/></g>'
    s += f'<path class="t" d="M128,144 a18,18 0 0 1 10,33 l6,30 l-32,0 l6,-30 a18,18 0 0 1 10,-33 Z" fill="{INK}" stroke-width="0"/>'
    s += '<rect class="hl" x="60" y="118" width="120" height="14" rx="7" opacity="0.5"/>'
    return s


def i_gift():
    s = '<g filter="url(#ds)">'
    s += f'<rect class="o" x="46" y="108" width="164" height="124" rx="14" fill="{g("red")}"/>'
    s += f'<rect class="o" x="34" y="82" width="188" height="44" rx="12" fill="{g("red")}"/>'
    s += "</g>"
    s += f'<rect x="112" y="82" width="32" height="150" fill="{g("gold")}" stroke="{INK}" stroke-width="7"/>'
    s += f'<path class="o" d="M128,84 C96,40 54,52 70,80 C80,96 110,90 128,84 Z" fill="{g("gold")}"/>'
    s += f'<path class="o" d="M128,84 C160,40 202,52 186,80 C176,96 146,90 128,84 Z" fill="{g("gold")}"/>'
    s += '<rect class="hl" x="48" y="90" width="56" height="12" rx="6" opacity="0.5"/>'
    return s


def i_clock():
    s = '<g filter="url(#ds)">'
    for x, rot in ((70, -30), (186, 30)):
        s += f'<ellipse class="o" cx="{x}" cy="52" rx="30" ry="22" fill="{g("gold")}" transform="rotate({rot} {x} 52)"/>'
    s += f'<line x1="78" y1="220" x2="66" y2="238" stroke="{INK}" stroke-width="16" stroke-linecap="round"/>'
    s += f'<line x1="178" y1="220" x2="190" y2="238" stroke="{INK}" stroke-width="16" stroke-linecap="round"/>'
    s += f'<circle class="o" cx="128" cy="140" r="92" fill="{g("blue")}"/></g>'
    s += f'<circle cx="128" cy="140" r="70" fill="#ffffff" stroke="{INK}" stroke-width="7"/>'
    for a in range(0, 360, 30):
        x0, y0 = arc_pt(a, 58, (128, 140))
        x1, y1 = arc_pt(a, 64, (128, 140))
        s += f'<line x1="{x0:.1f}" y1="{y0:.1f}" x2="{x1:.1f}" y2="{y1:.1f}" stroke="{INK}" stroke-width="5" stroke-linecap="round"/>'
    s += f'<path d="M128,140 L128,92 M128,140 L162,156" stroke="{INK}" stroke-width="10" stroke-linecap="round" fill="none"/>'
    s += f'<circle cx="128" cy="140" r="9" fill="#ff3b3b" stroke="{INK}" stroke-width="4"/>'
    s += '<path class="hl2" d="M58,108 A76,76 0 0 1 100,64"/>'
    return s


def i_trophy():
    s = '<g filter="url(#ds)">'
    for side in (-1, 1):
        x = 128 + side * 78
        s += f'<path d="M{128 + side*52},72 C{x + side*30},72 {x + side*26},140 {128 + side*48},146" fill="none" stroke="{INK}" stroke-width="30" stroke-linecap="round"/>'
        s += f'<path d="M{128 + side*52},72 C{x + side*30},72 {x + side*26},140 {128 + side*48},146" fill="none" stroke="{g("gold")}" stroke-width="14" stroke-linecap="round"/>'
    s += f'<path class="o" d="M60,36 L196,36 L188,120 C182,160 158,176 128,176 C98,176 74,160 68,120 Z" fill="{g("gold")}"/>'
    s += f'<rect class="o" x="110" y="170" width="36" height="34" fill="{g("gold")}"/>'
    s += f'<rect class="o" x="66" y="200" width="124" height="34" rx="10" fill="{g("brown")}"/></g>'
    s += f'<polygon points="{pol(star_pts(128, 104, 34, 15, 5))}" fill="#ffffff" opacity="0.85" stroke="{INK}" stroke-width="5" stroke-linejoin="round"/>'
    s += '<path class="hl" d="M76,46 L104,46 L96,120 L84,120 Z" opacity="0.45"/>'
    return s


def star_pts(cx, cy, ro, ri, n, rot=-90):
    pts = []
    for i in range(n * 2):
        r = ro if i % 2 == 0 else ri
        a = math.radians(rot + i * 180 / n)
        pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    return pts


def i_sparkle():
    s = f'<g filter="url(#ds)"><polygon class="o" points="{pol(star_pts(118, 128, 104, 30, 4))}" fill="{g("gold")}"/></g>'
    s += f'<polygon class="t" points="{pol(star_pts(204, 58, 34, 11, 4))}" fill="{g("white")}"/>'
    s += f'<polygon class="t" points="{pol(star_pts(206, 196, 22, 8, 4))}" fill="{g("white")}"/>'
    s += f'<polygon class="hl" points="{pol(star_pts(104, 108, 40, 10, 4))}" opacity="0.5"/>'
    return s


def badge_x2(x=168, y=200, size=78, color="#ffffff"):
    return f'<text class="txt" x="{x}" y="{y}" font-size="{size}" text-anchor="middle" fill="{color}">x2</text>'


def i_x2speed():
    return f'<g filter="url(#ds)">{bolt(0.86, -18, -12)}</g>' + badge_x2(176, 226, 88, "#7dff5a")


def i_x2coins():
    return f'<g filter="url(#ds)">{coin(112, 108, 84)}</g>' + badge_x2(176, 228, 88, "#7dff5a")


def i_magnet():
    s = '<g filter="url(#ds)">'
    d = "M58,40 L58,128 A70,70 0 0 0 198,128 L198,40"
    s += f'<path d="{d}" fill="none" stroke="{INK}" stroke-width="72" stroke-linejoin="round"/>'
    s += f'<path d="{d}" fill="none" stroke="{g("red")}" stroke-width="54" stroke-linejoin="round"/>'
    s += "</g>"
    for x in (58, 198):
        s += f'<rect class="t" x="{x-27}" y="22" width="54" height="40" rx="6" fill="{g("silver")}"/>'
    s += '<path class="hl2" d="M44,80 L44,124"/>'
    for x0, y0, x1, y1 in [(20, 200, 44, 176), (128, 236, 128, 214), (236, 200, 212, 176)]:
        s += f'<line x1="{x0}" y1="{y0}" x2="{x1}" y2="{y1}" stroke="#ffe23a" stroke-width="10" stroke-linecap="round"/>'
    s += coin(128, 214, 0) if False else ""
    return s


def i_lucky():
    s = '<g filter="url(#ds)">'
    s += f'<path d="M128,170 Q136,214 168,236" fill="none" stroke="{INK}" stroke-width="26" stroke-linecap="round"/>'
    s += f'<path d="M128,170 Q136,214 168,236" fill="none" stroke="#2f9a2a" stroke-width="12" stroke-linecap="round"/>'
    for a in (0, 90, 180, 270):
        x = 128 + math.cos(math.radians(a - 45)) * 58
        y = 110 + math.sin(math.radians(a - 45)) * 58
        s += f'<circle class="o" cx="{x:.1f}" cy="{y:.1f}" r="50" fill="{g("green")}"/>'
    s += "</g>"
    for a in (0, 90, 180, 270):
        x = 128 + math.cos(math.radians(a - 45)) * 58
        y = 110 + math.sin(math.radians(a - 45)) * 58
        s += f'<circle cx="{x:.1f}" cy="{y:.1f}" r="50" fill="{g("green")}"/>'
        s += f'<ellipse class="hl" cx="{x-12:.1f}" cy="{y-16:.1f}" rx="16" ry="10" opacity="0.45"/>'
    s += f'<circle cx="128" cy="110" r="16" fill="#2f9a2a"/>'
    return s


def i_bigtank():
    s = tank(20, 70, 176, 140)
    s += f'<g filter="url(#ds)"><circle class="t" cx="200" cy="74" r="40" fill="{g("green")}"/></g>'
    s += f'<path d="M200,52 L200,96 M178,74 L222,74" stroke="#ffffff" stroke-width="13" stroke-linecap="round"/>'
    return s


def i_crown():
    pts = [(28, 196), (40, 70), (88, 128), (128, 44), (168, 128), (216, 70), (228, 196)]
    s = f'<g filter="url(#ds)"><polygon class="o" points="{pol(pts)}" fill="{g("gold")}"/>'
    s += f'<rect class="o" x="28" y="180" width="200" height="44" rx="10" fill="{g("gold")}"/></g>'
    for x, c in ((76, "red"), (128, "blue"), (180, "green")):
        s += f'<circle class="t" cx="{x}" cy="202" r="13" fill="{g(c)}"/>'
    for x, y in ((40, 70), (128, 44), (216, 70)):
        s += f'<circle class="t" cx="{x}" cy="{y}" r="14" fill="{g("white")}"/>'
    s += '<polygon class="hl" points="52,104 82,140 60,170" opacity="0.4"/>'
    return s


def duck(color="gold"):
    s = '<g filter="url(#ds)">'
    s += f'<path class="o" d="M40,150 C40,120 70,110 110,118 C120,96 112,58 150,44 C192,30 222,64 206,100 C200,112 190,118 182,122 C214,128 230,150 220,180 C206,222 140,232 100,226 C60,220 40,190 40,150 Z" fill="{g(color)}"/>'
    s += f'<path class="o" d="M200,82 C224,74 246,80 244,92 C238,104 216,104 200,98 Z" fill="{g("orange")}"/>'
    s += "</g>"
    s += f'<path d="M84,150 C100,130 140,132 154,156 C130,170 104,170 84,150 Z" fill="#000" opacity="0.12"/>'
    s += f'<circle cx="170" cy="72" r="10" fill="{INK}"/><circle cx="173" cy="68" r="3.5" fill="#ffffff"/>'
    s += '<path class="hl2" d="M138,60 C148,52 160,50 172,52"/><path class="hl2" d="M62,146 C70,132 84,126 100,126"/>'
    return s


def i_goldduck():
    s = duck("gold")
    s += f'<polygon class="t" points="{pol(star_pts(54, 62, 26, 9, 4))}" fill="{g("white")}"/>'
    return s


def i_sharkboard():
    s = '<g filter="url(#ds)" transform="rotate(-38 128 128)">'
    s += f'<path class="o" d="M128,8 C168,40 174,200 128,248 C82,200 88,40 128,8 Z" fill="{g("blue")}"/>'
    s += f'<path d="M128,20 C150,60 152,180 128,232" fill="none" stroke="#ffffff" stroke-width="10"/>'
    s += f'<path d="M104,120 L152,120 L144,136 L136,124 L128,138 L120,124 L112,136 Z" fill="#ffffff" stroke="{INK}" stroke-width="4" stroke-linejoin="round"/>'
    s += "</g>"
    s += f'<path class="o" d="M110,140 L148,52 L176,128 Z" fill="{g("shark")}"/>'
    s += '<path class="hl2" d="M128,118 L146,74"/>'
    return s


def i_rainbowski():
    s = '<g filter="url(#ds)">'
    s += f'<path class="o" d="M20,170 L60,132 L176,132 C206,132 230,150 240,176 L228,196 L40,196 Z" fill="url(#g-rainbow)"/>'
    s += f'<path class="o" d="M96,132 L120,92 L168,92 L176,132 Z" fill="{g("white")}"/>'
    s += f'<path class="t" d="M124,92 L142,60 L156,64 L148,92" fill="{g("gray")}"/>'
    s += f'<rect class="t" x="132" y="48" width="44" height="14" rx="7" fill="{g("gray")}"/>'
    s += "</g>"
    s += f'<rect x="40" y="182" width="190" height="12" fill="#000" opacity="0.18"/>'
    s += '<path class="hl2" d="M66,146 L170,146"/>'
    for x, y in ((40, 220), (90, 228), (150, 224)):
        s += f'<path d="M{x-14},{y} q7,-10 14,0 t14,0" fill="none" stroke="#38dcef" stroke-width="7" stroke-linecap="round"/>'
    return s


def bubble(cx=128, cy=124, r=100, tint="glass"):
    s = f'<g filter="url(#ds)"><circle class="o" cx="{cx}" cy="{cy}" r="{r}" fill="{g(tint)}" fill-opacity="0.85"/></g>'
    s += f'<path class="hl2" d="M{cx-r*0.66},{cy-r*0.2} A{r*0.7},{r*0.7} 0 0 1 {cx-r*0.18},{cy-r*0.68}" stroke-width="12"/>'
    s += f'<circle cx="{cx+r*0.5}" cy="{cy+r*0.48}" r="{r*0.08}" fill="#ffffff" opacity="0.7"/>'
    return s


def i_goldbubble():
    s = bubble(tint="gold")
    s += f'<polygon class="t" points="{pol(star_pts(128, 132, 52, 22, 5))}" fill="{g("white")}"/>'
    s += f'<polygon class="t" points="{pol(star_pts(214, 40, 24, 8, 4))}" fill="{g("white")}"/>'
    return s


def i_chest():
    s = '<g filter="url(#ds)">'
    s += f'<rect class="o" x="30" y="118" width="196" height="112" rx="10" fill="{g("brown")}"/>'
    s += f'<path class="o" d="M30,124 L30,94 C30,52 226,52 226,94 L226,124 Z" fill="{g("brown")}"/></g>'
    for x in (62, 194):
        s += f'<rect x="{x-12}" y="62" width="24" height="168" fill="{g("gold")}" stroke="{INK}" stroke-width="6"/>'
    s += f'<rect x="30" y="116" width="196" height="16" fill="{g("gold")}" stroke="{INK}" stroke-width="6"/>'
    s += f'<rect class="t" x="108" y="106" width="40" height="46" rx="8" fill="{g("gold")}"/>'
    s += f'<circle cx="128" cy="124" r="7" fill="{INK}"/>'
    s += '<path class="hl2" d="M80,74 C110,62 150,62 176,72"/>'
    return s


def waves(y=196):
    s = f'<path class="o" d="M10,{y} q30,-26 60,0 t60,0 t60,0 t60,0 L246,248 L10,248 Z" fill="{g("blue")}"/>'
    s += f'<path d="M22,{y+8} q24,-16 48,0" fill="none" stroke="#ffffff" stroke-width="8" stroke-linecap="round" opacity="0.8"/>'
    s += f'<path d="M142,{y+8} q24,-16 48,0" fill="none" stroke="#ffffff" stroke-width="8" stroke-linecap="round" opacity="0.8"/>'
    return s


def i_fin():
    s = '<g filter="url(#ds)">'
    s += f'<path class="o" d="M60,200 C90,120 130,40 196,26 C170,90 176,150 204,200 Z" fill="{g("shark")}"/>'
    s += waves(194)
    s += "</g>"
    s += '<path class="hl2" d="M96,160 C112,110 136,70 166,50"/>'
    return s


def i_arrow():
    pts = [(128, 236), (32, 128), (88, 128), (88, 22), (168, 22), (168, 128), (224, 128)]
    s = f'<g filter="url(#ds)"><polygon class="o" points="{pol(pts)}" fill="{g("gold")}"/></g>'
    s += '<rect class="hl" x="104" y="36" width="16" height="84" rx="8" opacity="0.5"/>'
    return s


def i_moneybag():
    s = '<g filter="url(#ds)">'
    s += f'<path class="o" d="M96,74 C60,100 34,150 40,190 C46,226 90,238 128,238 C166,238 210,226 216,190 C222,150 196,100 160,74 Z" fill="{g("brown")}"/>'
    s += f'<path class="o" d="M90,30 L166,30 L148,78 L108,78 Z" fill="{g("brown")}"/>'
    s += f'<rect class="t" x="94" y="70" width="68" height="16" rx="8" fill="{g("gold")}"/></g>'
    s += coin(128, 170, 42, "fin")
    s += '<path class="hl2" d="M70,140 C76,120 88,104 104,94"/>'
    return s


def i_fish():
    return f'<g filter="url(#ds)">{clownfish(118, 128, 2.6)}</g>' + '<path class="hl2" d="M60,96 C80,80 110,74 130,76"/>'


def i_island():
    s = '<g filter="url(#ds)">'
    s += f'<ellipse class="o" cx="128" cy="196" rx="104" ry="34" fill="{g("sand")}"/>'
    s += f'<path class="o" d="M120,192 C124,150 136,110 156,78" fill="none" stroke-width="26"/>'
    s += f'<path d="M120,192 C124,150 136,110 156,78" fill="none" stroke="{g("brown")}" stroke-width="12" stroke-linecap="round"/>'
    for d in ("M156,78 C120,52 80,62 64,88 C96,78 128,80 156,78 Z", "M156,78 C190,50 230,62 240,92 C210,80 180,80 156,78 Z",
              "M156,78 C140,40 160,20 188,22 C172,40 164,58 156,78 Z", "M156,78 C130,86 112,112 110,134 C126,112 142,96 156,78 Z"):
        s += f'<path class="t" d="{d}" fill="{g("green")}"/>'
    s += "</g>"
    s += f'<path d="M30,222 q24,-14 48,0 t48,0 t48,0 t48,0" fill="none" stroke="#38dcef" stroke-width="8" stroke-linecap="round"/>'
    return s


def i_sneaker():
    """Speed: a sneaker with motion lines and a yellow + badge."""
    s = '<g filter="url(#ds)">'
    for i, y in enumerate((96, 128, 160)):
        s += f'<line x1="{14 + i * 6}" y1="{y}" x2="{58 + i * 6}" y2="{y}" stroke="{INK}" stroke-width="16" stroke-linecap="round"/>'
        s += f'<line x1="{14 + i * 6}" y1="{y}" x2="{58 + i * 6}" y2="{y}" stroke="#7fd8ff" stroke-width="7" stroke-linecap="round"/>'
    # sole
    s += f'<path class="o" d="M58,178 L226,178 C238,178 242,192 232,200 L66,200 C52,200 48,184 58,178 Z" fill="{g("white")}"/>'
    # upper
    s += (f'<path class="o" d="M64,180 C62,140 74,100 104,84 L128,74 C140,96 150,108 168,118 C200,128 226,140 230,170 L230,180 Z" '
          f'fill="{g("blue")}"/>')
    s += f'<path d="M104,84 L128,74 C134,88 140,98 148,106 L114,120 Z" fill="#ffffff" opacity="0.9"/>'
    for i in range(3):
        x = 126 + i * 16
        s += f'<line x1="{x}" y1="{112 + i * 6}" x2="{x + 18}" y2="{104 + i * 6}" stroke="#ffffff" stroke-width="7" stroke-linecap="round"/>'
    s += f'<path d="M180,140 C200,146 216,154 222,172" fill="none" stroke="#ffffff" stroke-width="8" stroke-linecap="round" opacity="0.8"/>'
    s += "</g>"
    s += '<path class="hl2" d="M80,160 C80,132 90,110 108,96"/>'
    # + badge
    s += f'<rect class="t" x="168" y="168" width="68" height="68" rx="10" fill="{g("gold")}"/>'
    s += f'<path d="M202,182 L202,222 M182,202 L222,202" stroke="{INK}" stroke-width="12" stroke-linecap="round"/>'
    return s


def i_cash():
    """Money: a fat stack of green bills with a $ band."""
    s = '<g filter="url(#ds)">'
    for k in range(3):
        y = 150 - k * 30
        s += f'<g transform="rotate(-14 128 {y + 40})">'
        s += f'<rect class="o" x="30" y="{y}" width="196" height="80" rx="10" fill="{g("green")}"/>'
        s += f'<rect x="44" y="{y + 12}" width="168" height="56" rx="8" fill="none" stroke="#1f8a2a" stroke-width="6"/>'
        s += f'<circle cx="128" cy="{y + 40}" r="20" fill="#1f8a2a" opacity="0.5"/>'
        s += "</g>"
    s += f'<g transform="rotate(-14 128 130)"><rect class="t" x="98" y="76" width="60" height="120" rx="8" fill="{g("gold")}"/>'
    s += f'<text class="txt" x="128" y="152" font-size="64" text-anchor="middle" fill="#ffffff" style="stroke-width:10">$</text></g>'
    s += "</g>"
    return s


SHEET_A = [
    ("Speed", i_speed), ("Coins", i_coins), ("Rides", i_rides), ("Index", i_index),
    ("Shop", i_shop), ("Rebirth", i_rebirth), ("Shark", i_shark), ("Tank", i_tank),
    ("Shield", i_shield), ("Boost", i_boost), ("Potion", i_potion), ("Lock", i_lock),
    ("Gift", i_gift), ("Clock", i_clock), ("Trophy", i_trophy), ("Sparkle", i_sparkle),
]
SHEET_B = [
    ("X2Speed", i_x2speed), ("X2Coins", i_x2coins), ("Magnet", i_magnet), ("Clover", i_lucky),
    ("BigTank", i_bigtank), ("Crown", i_crown), ("GoldDuck", i_goldduck), ("SharkBoard", i_sharkboard),
    ("RainbowSki", i_rainbowski), ("GoldBubble", i_goldbubble), ("Chest", i_chest), ("Fin", i_fin),
    ("Arrow", i_arrow), ("MoneyBag", i_moneybag), ("Fish", i_fish), ("Island", i_island),
]


SINGLES = [("Sneaker", i_sneaker), ("Cash", i_cash)] + SHEET_A + SHEET_B


def single(fn):
    return (
        '<!doctype html><html><head><style>html,body{margin:0;background:transparent}</style></head><body>'
        f'<svg xmlns="http://www.w3.org/2000/svg" width="512" height="512" viewBox="0 0 256 256"><style>{STYLE}</style>{defs()}'
        f'<g transform="translate(128,128) scale(0.9) translate(-128,-122)">{fn()}</g></svg></body></html>'
    )


def sheet(icons, preview=False):
    cells = []
    for i, (name, fn) in enumerate(icons):
        x, y = (i % 4) * 256, (i // 4) * 256
        cells.append(f'<g transform="translate({x},{y})"><g transform="translate(128,128) scale(0.9) translate(-128,-122)">{fn()}</g></g>')
        if preview:
            cells.append(f'<text x="{x+8}" y="{y+18}" font-size="14" fill="#fff" font-family="Inter">{i+1} {name}</text>')
    bg = '<rect width="1024" height="1024" fill="#3a3f52"/>' if preview else ""
    return (
        '<!doctype html><html><head><style>html,body{margin:0;background:transparent}</style></head><body>'
        f'<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024"><style>{STYLE}</style>{defs()}{bg}{"".join(cells)}</svg>'
        "</body></html>"
    )


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    os.makedirs(os.path.join(OUT, "single"), exist_ok=True)
    for name, fn in SINGLES:
        open(os.path.join(OUT, "single", f"{name}.html"), "w").write(single(fn))
    for name, icons in (("sheet_a", SHEET_A), ("sheet_b", SHEET_B)):
        open(os.path.join(OUT, f"{name}.html"), "w").write(sheet(icons))
        open(os.path.join(OUT, f"{name}_preview.html"), "w").write(sheet(icons, preview=True))
    print("wrote", OUT)
