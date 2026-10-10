"""Lay out the real HUD + Notify screens at several device sizes and draw them.

Runs src/client/UI.luau, Notify.luau and HUD.luau (plus shared Config/Build/
Layout) in the Luau CLI with mock.luau + gui_mock.luau, with sample player
data and a few sample messages, then does a simplified Roblox layout
(UDim2, AnchorPoint, UIListLayout, UIPadding, UIScale, AutomaticSize) and
draws boxes + text to ui_<device>.png. It's a layout check (sizes, overlap,
what fits on a phone), not a pixel-perfect render: fonts and icons differ.

    python3 tools/preview/ui.py path/to/luau
"""
import json, math, os, re, subprocess, sys
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(__file__)
SRC = os.path.join(HERE, "..", "..", "src")
LUAU = sys.argv[1] if len(sys.argv) > 1 else "luau"

DEVICES = [
    ("desktop_1600x900", 1600, 900, False),
    ("studio_1610x1030", 1610, 1030, False),
    ("phone_844x390", 844, 390, True),
    ("tablet_1180x820", 1180, 820, True),
]


def module(name, folder, prefix):
    src = open(os.path.join(SRC, folder, name + ".luau")).read()
    src = re.sub(r"^export type", "type", src, flags=re.M)
    parent = "SHARED" if folder == "shared" else "CLIENT"
    return f"MODULES['{prefix}{name}'] = function()\nlocal script = {{ Parent = {parent} }}\n{src}\nend\n"


def harness(w, h, touch, scene):
    s = open(os.path.join(HERE, "mock.luau")).read()
    s += open(os.path.join(HERE, "gui_mock.luau")).read()
    s += f"""
VIEWPORT = Vector2.new({w}, {h})
workspace.CurrentCamera.ViewportSize = VIEWPORT
TOUCH = {str(touch).lower()}
MODULES = {{}}
local LOADED = {{}}
SHARED = setmetatable({{}}, {{ __index = function(_, k) return "mod:" .. k end }})
CLIENT = setmetatable({{}}, {{ __index = function(_, k) return "cmod:" .. k end }})
game.ReplicatedStorage = game:GetService("ReplicatedStorage")
rawset(game.ReplicatedStorage, "Shared", SHARED)
function require(x)
	if LOADED[x] == nil then
		local f = MODULES[x]
		assert(f, "no module " .. tostring(x))
		LOADED[x] = f()
	end
	return LOADED[x]
end
-- task: coroutines that run until their first wait (no time passes)
task = {{
	spawn = function(f, ...) local co = coroutine.create(f); coroutine.resume(co, ...); return co end,
	delay = function() end,
	defer = function() end,
	wait = function() if coroutine.isyieldable() then coroutine.yield() end return 0 end,
}}
"""
    for m in ("Config", "Build", "Layout"):
        s += module(m, "shared", "mod:")
    for m in ("UI", "Sounds", "Fx", "Notify", "Guide", "Travel", "Prompts", "HUDMobile", "HUDDesktop", "HUD", "Rewards", "Shop", "Index", "Tank", "Sell", "Hub", "PlayGifts", "Reel", "Haul", "Countdown"):
        s += module(m, "client", "cmod:")
    s += """
local sig = function() return { Connect = function() end } end
MODULES["mod:Remotes"] = function() return { get = function() return { OnClientEvent = sig(), FireServer = function() end } end } end
SAMPLE = {
	speed = 866, coins = 12500, gain = 5, rebirths = 0, income = 255, active = 4, slots = 4, friendBoost = 0, slow = false,
	creatures = { { e = true, v = 60 }, { e = true, v = 70 }, { e = false, v = 90 } }, shields = 1, boostLeft = 0, luckLeft = 600,
	index = { a = true }, claimed = {}, rides = { Noodle = true, Duck = true, Tube = true, Boogie = true, Surf = true },
	playtime = 900, passes = {}, plot = 1, pending = 0, carrying = { r = "Rare", z = "Reef", s = 2.2 },
	dailyDay = 3, dailyWait = 0, groupWait = 0, tut = 5,
}
MODULES["cmod:State"] = function() return { data = SAMPLE, Changed = sig(), action = function() end, wait = function() return SAMPLE end } end
MODULES["cmod:Water"] = function() return { setSafeGlow = function() end } end
MODULES["cmod:SharkView"] = function() return { myHunter = function() return nil end, breach = function() end } end
MODULES["cmod:Travel"] = function() return { go = function() end } end
-- 3D builders: a stand-in model (viewports draw as a placeholder box)
local function fakeModel()
	return { PivotTo = function() end, GetBoundingBox = function() return CFrame.new(), Vector3.new(2, 2, 2) end, ScaleTo = function() end,
		GetExtentsSize = function() return Vector3.new(2, 2, 2) end }
end
MODULES["mod:Rides"] = function() return { build = fakeModel } end
MODULES["mod:Creatures"] = function() return { build = fakeModel } end
local HUD = require("cmod:HUD")
local Notify = require("cmod:Notify")
HUD.start()
"""
    s += scene
    s += r"""
-- dump every visible ScreenGui under PlayerGui
local out = {}
local function enc(v)
	local t = type(v)
	if t == "table" and v.X and type(v.X) == "table" then return { v.X.Scale, v.X.Offset, v.Y.Scale, v.Y.Offset } end
	if t == "table" and v.R then return { v.R, v.G, v.B } end
	if t == "table" and v.X then return { v.X, v.Y } end
	if t == "table" and v.Scale then return { v.Scale, v.Offset } end
	if t == "table" and v.Name and v.EnumType then return v.Name end
	if t == "string" or t == "number" or t == "boolean" then return v end
	return nil
end
local KEYS = { "ClassName", "Name", "Visible", "Enabled", "Size", "Position", "AnchorPoint", "BackgroundTransparency", "BackgroundColor3",
	"Text", "TextScaled", "TextSize", "TextColor3", "TextXAlignment", "TextYAlignment", "TextTransparency", "LayoutOrder", "ZIndex",
	"Padding", "FillDirection", "HorizontalAlignment", "VerticalAlignment", "SortOrder", "Scale", "AutomaticSize", "CornerRadius",
	"Thickness", "Color", "ApplyStrokeMode", "PaddingLeft", "PaddingRight", "PaddingTop", "PaddingBottom", "Image", "Rotation", "DisplayOrder",
	"CellSize", "CellPadding", "TextWrapped", "Transparency", "PlaceholderText", "PlaceholderColor3", "MaxTextSize", "ClipsDescendants", "ImageTransparency", "FillEmptySpaceColumns" }
local function walk(n)
	local p = rawget(n, "_p")
	local o = {}
	for _, k in KEYS do
		local v = p[k]
		if v ~= nil then o[k] = enc(v) end
	end
	o.kids = {}
	for _, c in p._kids do table.insert(o.kids, walk(c)) end
	return o
end
for _, g in GUI_ROOTS do
	if rawget(g, "_p").Parent ~= nil then
		table.insert(out, walk(g))
	end
end
-- tiny JSON encoder
local function j(v)
	local t = type(v)
	if t == "table" then
		if #v > 0 or next(v) == nil then
			local parts = {}
			for _, x in v do table.insert(parts, j(x)) end
			return "[" .. table.concat(parts, ",") .. "]"
		end
		local parts = {}
		for k, x in v do table.insert(parts, string.format("%q", k) .. ":" .. j(x)) end
		return "{" .. table.concat(parts, ",") .. "}"
	elseif t == "string" then
		return (string.format("%q", v):gsub("\\\n", "\\n"))
	elseif t == "boolean" then
		return tostring(v)
	end
	return tostring(v)
end
print("JSON" .. j(out))
"""
    return s


SCENE_PLAY = """
Notify.status("Coral Reef · 340 m")
Notify.banner("Coral Reef", { key = "zone", priority = 2, sub = "🦈 Hammerhead waters", color = Color3.fromRGB(150, 230, 240) })
Notify.toast("🐙 Huge Octopus  +$1.2K/s · NEW!", Color3.fromRGB(64, 156, 255))
Notify.toast("✅ The sharks are gone. Back to the water!", Color3.fromRGB(78, 206, 48))
"""
SCENE_TUT = """
Notify.status("Lagoon · 12 m")
Notify.banner("Grab a creature", { key = "tut", sticky = true, priority = 3, sub = "Swim to a bubble, then tap", step = "1/5" })
Notify.toast("Rare Clownfish  +$5/s · NEW!", Color3.fromRGB(64, 156, 255))
"""
SCENE_TUT_COMPACT = """
Notify.banner("Grab a creature", { key = "tut", sticky = true, priority = 3, sub = "Swim to a bubble, then tap", step = "1/5", compact = true })
"""
SCENE_DAILY = """
local Rewards = require("cmod:Rewards")
Rewards.start()
Rewards.openDaily()
"""
SCENE_TAKEOVER = """
Notify.status("Coral Reef · 340 m")
Notify.banner("🦈 SHARK ATTACK IN 4!", { key = "shark", sticky = true, priority = 5, sub = "Get to sand or an island", color = Color3.fromRGB(235, 40, 40) })
Notify.takeover("SHARK INCOMING!", "Get to sand or an island!", Color3.fromRGB(235, 40, 40), 1.4)
"""

# ---------------------------------------------------------------- layout
def ud(v, size):  # UDim2 list -> (x, y) given parent size
    return (v[0] * size[0] + v[1], v[2] * size[1] + v[3])


FONT_PATH = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
_fonts = {}


def font(px):
    px = max(6, int(px))
    if px not in _fonts:
        try:
            _fonts[px] = ImageFont.truetype(FONT_PATH, px)
        except OSError:
            _fonts[px] = ImageFont.load_default()
    return _fonts[px]


def text_w(text, px):
    if not text:
        return 0
    return font(px).getlength(text)


def is_gui(n):
    c = n.get("ClassName", "")
    return c in ("Frame", "TextLabel", "TextButton", "TextBox", "ImageLabel", "ImageButton", "ScrollingFrame", "ViewportFrame", "CanvasGroup")


def natural(n, avail):
    """size of an AutomaticSize element (content-driven), in canvas units"""
    size = list(ud(n.get("Size", [0, 0, 0, 0]), avail))
    auto = n.get("AutomaticSize")
    if not auto or auto == "None":
        return size
    pad = [0, 0, 0, 0]
    for k in n["kids"]:
        if k.get("ClassName") == "UIPadding":
            pad = [k.get("PaddingLeft", [0, 0])[1], k.get("PaddingRight", [0, 0])[1], k.get("PaddingTop", [0, 0])[1], k.get("PaddingBottom", [0, 0])[1]]
    cw, ch = 0, 0
    if n.get("ClassName") in ("TextLabel", "TextButton") and n.get("Text"):
        px = n.get("TextSize", 14)
        cw, ch = text_w(n["Text"], px), px * 1.2
    layout = next((k for k in n["kids"] if k.get("ClassName") == "UIListLayout"), None)
    kids = [k for k in n["kids"] if is_gui(k) and k.get("Visible", True)]
    if kids:
        sizes = [natural(k, avail) for k in kids]
        horiz = layout and layout.get("FillDirection") == "Horizontal"
        gap = (layout.get("Padding", [0, 0])[1] if layout else 0)
        if layout and horiz:
            cw = max(cw, sum(s[0] for s in sizes) + gap * (len(sizes) - 1))
            ch = max(ch, max(s[1] for s in sizes))
        elif layout:
            cw = max(cw, max(s[0] for s in sizes))
            ch = max(ch, sum(s[1] for s in sizes) + gap * (len(sizes) - 1))
        else:
            cw = max(cw, max(s[0] for s in sizes))
            ch = max(ch, max(s[1] for s in sizes))
    if "X" in auto:
        size[0] = max(size[0], cw + pad[0] + pad[1])
    if "Y" in auto:
        size[1] = max(size[1], ch + pad[2] + pad[3])
    return size


def place(n, pos, size, out, depth, clip=None):
    n["_rect"] = (pos[0], pos[1], size[0], size[1])
    n["_depth"] = depth
    n["_clip"] = clip
    out.append(n)
    # scrolling frames / ClipsDescendants: children are clipped to this rect
    if n.get("ClassName") == "ScrollingFrame" or n.get("ClipsDescendants"):
        r = (pos[0], pos[1], pos[0] + size[0], pos[1] + size[1])
        clip = r if clip is None else (max(clip[0], r[0]), max(clip[1], r[1]), min(clip[2], r[2]), min(clip[3], r[3]))
    pad = [0, 0, 0, 0]
    for k in n["kids"]:
        if k.get("ClassName") == "UIPadding":
            pad = [k.get("PaddingLeft", [0, 0])[1], k.get("PaddingRight", [0, 0])[1], k.get("PaddingTop", [0, 0])[1], k.get("PaddingBottom", [0, 0])[1]]
    inner_pos = (pos[0] + pad[0], pos[1] + pad[2])
    inner = (size[0] - pad[0] - pad[1], size[1] - pad[2] - pad[3])
    layout = next((k for k in n["kids"] if k.get("ClassName") == "UIListLayout"), None)
    grid = next((k for k in n["kids"] if k.get("ClassName") == "UIGridLayout"), None)
    kids = [k for k in n["kids"] if is_gui(k) and k.get("Visible", True)]
    if grid:
        kids.sort(key=lambda k: k.get("LayoutOrder", 0))
        cs = ud(grid.get("CellSize", [0, 100, 0, 100]), inner)
        cp = ud(grid.get("CellPadding", [0, 5, 0, 5]), inner)
        cols = max(1, int((inner[0] + cp[0]) // (cs[0] + cp[0])))
        cols = min(cols, max(1, len(kids)))
        roww = cols * cs[0] + (cols - 1) * cp[0]
        x0 = inner_pos[0] + {"Left": 0, "Center": (inner[0] - roww) / 2, "Right": inner[0] - roww}.get(grid.get("HorizontalAlignment", "Left"), 0)
        for i, k in enumerate(kids):
            c, r = i % cols, i // cols
            place(k, (x0 + c * (cs[0] + cp[0]), inner_pos[1] + r * (cs[1] + cp[1])), cs, out, depth + 1, clip)
    elif layout:
        kids.sort(key=lambda k: k.get("LayoutOrder", 0))
        horiz = layout.get("FillDirection") == "Horizontal"
        gap = layout.get("Padding", [0, 0])[1] + layout.get("Padding", [0, 0])[0] * (inner[0] if horiz else inner[1])
        sizes = [natural(k, inner) for k in kids]
        total = sum(s[0 if horiz else 1] for s in sizes) + gap * max(0, len(kids) - 1)
        va, ha = layout.get("VerticalAlignment", "Top"), layout.get("HorizontalAlignment", "Left")
        if horiz:
            cur = inner_pos[0] + {"Left": 0, "Center": (inner[0] - total) / 2, "Right": inner[0] - total}.get(ha, 0)
        else:
            cur = inner_pos[1] + {"Top": 0, "Center": (inner[1] - total) / 2, "Bottom": inner[1] - total}.get(va, 0)
        for k, s in zip(kids, sizes):
            if horiz:
                y = inner_pos[1] + {"Top": 0, "Center": (inner[1] - s[1]) / 2, "Bottom": inner[1] - s[1]}.get(va, 0)
                place(k, (cur, y), s, out, depth + 1, clip)
                cur += s[0] + gap
            else:
                x = inner_pos[0] + {"Left": 0, "Center": (inner[0] - s[0]) / 2, "Right": inner[0] - s[0]}.get(ha, 0)
                place(k, (x, cur), s, out, depth + 1, clip)
                cur += s[1] + gap
    else:
        for k in kids:
            s = natural(k, inner)
            p = ud(k.get("Position", [0, 0, 0, 0]), inner)
            a = k.get("AnchorPoint", [0, 0])
            place(k, (inner_pos[0] + p[0] - a[0] * s[0], inner_pos[1] + p[1] - a[1] * s[1]), s, out, depth + 1, clip)


def rgb(c, a=255):
    return (int(c[0] * 255), int(c[1] * 255), int(c[2] * 255), a)


def wrap(text, px, width):
    words, lines, cur = text.split(" "), [], ""
    for wd in words:
        t = (cur + " " + wd).strip()
        if text_w(t, px) <= width or not cur:
            cur = t
        else:
            lines.append(cur)
            cur = wd
    lines.append(cur)
    return lines


def draw_item(d, n, scale, inset, ox, oy, report):
    x, y, ww, hh = n["_rect"]
    X, Y, W, H = x * scale + ox, y * scale + inset + oy, ww * scale, hh * scale
    cls = n.get("ClassName")
    stroke = next((k for k in n["kids"] if k.get("ClassName") == "UIStroke"), None)
    corner = next((k for k in n["kids"] if k.get("ClassName") == "UICorner"), None)
    limit = next((k for k in n["kids"] if k.get("ClassName") == "UITextSizeConstraint"), None)
    r = 0
    if corner:
        cr = corner.get("CornerRadius", [0, 8])
        r = min(cr[1] * scale + cr[0] * min(W, H), min(W, H) / 2)
    if cls in ("Frame", "TextButton", "TextBox", "ImageButton", "ScrollingFrame") and n.get("BackgroundTransparency", 0) < 0.99 and W > 0 and H > 0:
        a = int(255 * (1 - n.get("BackgroundTransparency", 0)))
        outline = None
        if stroke and stroke.get("ApplyStrokeMode") == "Border" and stroke.get("Transparency", 0) < 0.99:
            outline = rgb(stroke.get("Color", [0.09, 0.09, 0.13]))
        d.rounded_rectangle([X, Y, X + W, Y + H], radius=r, fill=rgb(n.get("BackgroundColor3", [1, 1, 1]), a),
                            outline=outline, width=max(1, int((stroke or {}).get("Thickness", 1) * scale)) if outline else 1)
    elif cls == "Frame" and stroke and stroke.get("ApplyStrokeMode") == "Border" and W > 0 and H > 0:
        d.rounded_rectangle([X, Y, X + W, Y + H], radius=r, outline=rgb(stroke.get("Color", [1, 1, 1])),
                            width=max(1, int(stroke.get("Thickness", 1) * scale)))
    if cls in ("ImageLabel", "ImageButton"):
        d.rectangle([X, Y, X + W, Y + H], outline=(255, 255, 255, 90))
    if cls == "ViewportFrame" and W > 2 and H > 2:
        # stand-in for the 3D model: a soft blob
        d.ellipse([X + W * 0.25, Y + H * 0.2, X + W * 0.75, Y + H * 0.8], fill=(255, 255, 255, 50))
    if cls == "TextBox" and not n.get("Text") and n.get("PlaceholderText"):
        n = dict(n, Text=n["PlaceholderText"], TextColor3=n.get("PlaceholderColor3", [0.6, 0.6, 0.6]))
        cls = "TextLabel"
    if cls in ("TextLabel", "TextButton") and n.get("Text") and n.get("TextTransparency", 0) < 0.99 and W > 1 and H > 1:
        text = n["Text"]
        lines = [text]
        if n.get("TextScaled"):
            px = H * 0.9
            if limit and limit.get("MaxTextSize"):
                px = min(px, limit["MaxTextSize"] * scale)
            if n.get("TextWrapped"):
                while px > 6:
                    lines = wrap(text, px, W * 0.98)
                    if len(lines) * px * 1.15 <= H and all(text_w(l, px) <= W * 0.98 for l in lines):
                        break
                    px -= 0.5
            else:
                tw = text_w(text, px)
                if tw > W * 0.98:
                    px *= (W * 0.98) / tw
        else:
            px = n.get("TextSize", 14) * scale
        f = font(px)
        xa = n.get("TextXAlignment", "Center")
        c = n.get("TextColor3", [1, 1, 1])
        st = max(1, int(px / 9))
        scol = rgb(stroke.get("Color", [0.09, 0.09, 0.13])) if stroke else None
        total = len(lines) * px * 1.15
        for i, ln in enumerate(lines):
            tw = f.getlength(ln)
            tx = X if xa == "Left" else (X + W - tw if xa == "Right" else X + (W - tw) / 2)
            ty = Y + (H - total) / 2 + i * px * 1.15
            d.text((tx, ty), ln, font=f, fill=rgb(c), stroke_width=st if stroke else 0, stroke_fill=scol)
        if px < 11 and report is not None:
            report.append(f"small text {px:.1f}px: {text[:40]}")


def draw_device(name, w, h, touch, scene, tag):
    code = harness(w, h, touch, scene)
    path = os.path.join(HERE, f"ui_harness_{os.getpid()}.luau")
    open(path, "w").write(code)
    res = subprocess.run([LUAU, path], capture_output=True, text=True)
    os.remove(path)
    line = next((l for l in res.stdout.splitlines() if l.startswith("JSON")), None)
    if res.returncode != 0 or not line:
        print(res.stdout[-1500:], res.stderr[-2500:])
        sys.exit(1)
    roots = json.loads(line[4:])
    img = Image.new("RGB", (w, h), (120, 196, 120))
    d = ImageDraw.Draw(img, "RGBA")
    # topbar inset (CoreUISafeInsets): the Roblox menu buttons sit up here
    inset = 58
    d.rectangle([0, 0, w, inset], fill=(40, 40, 48, 120))
    report = []
    roots.sort(key=lambda r: r.get("DisplayOrder", 0))
    for root in roots:
        if root.get("Enabled") is False:
            continue
        scale = next((k.get("Scale", 1) for k in root["kids"] if k.get("ClassName") == "UIScale"), 1)
        canvas = (w / scale, (h - inset) / scale)
        items = []
        for k in root["kids"]:
            if is_gui(k) and k.get("Visible", True):
                s = natural(k, canvas)
                p = ud(k.get("Position", [0, 0, 0, 0]), canvas)
                a = k.get("AnchorPoint", [0, 0])
                place(k, (p[0] - a[0] * s[0], p[1] - a[1] * s[1]), s, items, 1)
        for n in items:
            cl = n.get("_clip")
            if cl:
                cx0, cy0 = int(max(0, cl[0] * scale)), int(max(0, cl[1] * scale + inset))
                cx1, cy1 = int(min(w, cl[2] * scale)), int(min(h, cl[3] * scale + inset))
                if cx1 <= cx0 or cy1 <= cy0:
                    continue
                x, y, ww, hh = n["_rect"]
                if x * scale > cx1 or y * scale + inset > cy1 or (x + ww) * scale < cx0 or (y + hh) * scale + inset < cy0:
                    continue
                layer = Image.new("RGBA", (cx1 - cx0, cy1 - cy0), (0, 0, 0, 0))
                draw_item(ImageDraw.Draw(layer, "RGBA"), n, scale, inset, -cx0, -cy0, None)
                img.paste(layer, (cx0, cy0), layer)
            else:
                draw_item(d, n, scale, inset, 0, 0, report)
        for n in items:
            x, y, ww, hh = n["_rect"]
            X, Y, W, H = x * scale, y * scale + inset, ww * scale, hh * scale
            if n["_depth"] == 1 and n.get("Name") != "Backdrop" and (X < -1 or Y < inset - 1 or X + W > w + 1 or Y + H > h + 1) and W > 0 and H > 0:
                report.append(f"off-screen: {root.get('Name')}/{n.get('Name')} at {X:.0f},{Y:.0f} {W:.0f}x{H:.0f}")
    if touch:
        # thumbstick (bottom-left) and jump button (bottom-right) on phones/tablets
        js, jb = 150, 140
        d.rectangle([0, h - js, js, h], outline=(255, 60, 60, 255), width=2)
        d.rectangle([w - jb, h - jb, w, h], outline=(255, 60, 60, 255), width=2)
    out = os.path.join(HERE, f"ui_{name}_{tag}.png")
    img.save(out)
    print(out, "|", "; ".join(sorted(set(report))) or "ok")


MENU_SAMPLE = """
SAMPLE.coins = 450
SAMPLE.ride = "Tube"
SAMPLE.rides = { Noodle = true, Duck = true, Tube = true }
SAMPLE.index = { ["Lagoon:Common"] = true, ["Lagoon:Uncommon"] = true, ["Lagoon:Rare"] = true, ["Reef:Common"] = true }
SAMPLE.claimed = { ["Lagoon:Common"] = true }
SAMPLE.active, SAMPLE.slots, SAMPLE.income, SAMPLE.dead, SAMPLE.maxDead, SAMPLE.slotPrice = 3, 4, 42, 2, 10, 400
SAMPLE.creatures = {
	{ id = "a", e = true, v = 24, r = "Rare", z = "Lagoon", s = 1.4 },
	{ id = "b", e = true, v = 9, r = "Uncommon", z = "Lagoon", s = 1 },
	{ id = "c", e = true, v = 9, r = "Common", z = "Reef", m = "Gold", s = 1 },
	{ id = "d", e = false, v = 3, r = "Common", z = "Lagoon", s = 0.8 },
	{ id = "e", e = false, v = 2, r = "Common", z = "Lagoon", s = 1 },
}
SAMPLE.rebirths = 1
SAMPLE.speed = 30000
SAMPLE.quests = { { text = "Catch 3 Rares or better", n = 1, goal = 3 }, { text = "Bring 15 creatures home", n = 15, goal = 15 },
	{ text = "Ride through 5 boost rings", n = 0, goal = 5 } }
SAMPLE.questsReset = 5 * 3600 + 120
"""
MENU_SCENES = {
    "index": 'require("cmod:Shop").start()\nrequire("cmod:Index").open()',
    "rides": 'require("cmod:Shop").start()\nrequire("cmod:Shop").openRides()',
    "store": 'require("cmod:Shop").start()\nrequire("cmod:Shop").openStore()',
    "tank": 'require("cmod:Tank").start()\nrequire("cmod:Tank").open()',
    "sell": 'require("cmod:Sell").open()',
    "rebirth": 'require("cmod:Shop").start()\nrequire("cmod:Hub").confirmRebirth()',
    "reel": 'require("cmod:Reel").play(7, "Kraken")',
    "event": 'require("cmod:Countdown").preview()',
    "hunger": 'local H = require("cmod:Haul")\nH.start()\nH.preview(64)',
    "daily": 'local R = require("cmod:Rewards")\nR.start()\nR.openDaily()',
}

if len(sys.argv) > 2 and sys.argv[2] == "menus":
    # menu scenes: python3 tools/preview/ui.py <luau> menus [scene ...]
    pick = sys.argv[3:] or list(MENU_SCENES)
    for key in pick:
        for name, w, h, touch in (("phone_844x390", 844, 390, True), ("desktop_1600x900", 1600, 900, False)):
            draw_device(name, w, h, touch, MENU_SAMPLE + MENU_SCENES[key], "menu_" + key)
    sys.exit(0)

for name, w, h, touch in DEVICES:
    draw_device(name, w, h, touch, SCENE_PLAY, "play")
draw_device("phone_844x390", 844, 390, True, SCENE_TAKEOVER, "takeover")
draw_device("phone_844x390", 844, 390, True, SCENE_TUT, "tutorial")
draw_device("phone_844x390", 844, 390, True, SCENE_TUT_COMPACT, "tutorial_compact")
draw_device("phone_844x390", 844, 390, True, SCENE_DAILY, "daily")
draw_device("desktop_1600x900", 1600, 900, False, SCENE_DAILY, "daily")
draw_device("desktop_1600x900", 1600, 900, False, SCENE_TAKEOVER, "takeover")
