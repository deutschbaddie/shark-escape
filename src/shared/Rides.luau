-- Hand-built rides in a smooth, glossy toy look: inflatables and hulls are
-- made of ellipsoids, balls and cylinders (round things are round), crisp
-- details use blocks and wedges. Root sits where the player's feet go
-- (y = 0, water surface at y -0.15), everything faces -Z. Each ride is built
-- around its rider pose (Rig.POSES), and Rides.FIT says where that pose's
-- anchor goes, so the body sits on / in the ride instead of through it
-- (tools/preview/fit.py checks every ride against a stand-in R15 body and
-- renders close-ups to tools/preview/rides/):
--   sit      (tube, duck, donut, bathtub): hips over the hole, knees over
--            the front rim, arms out over the sides
--   straddle (jet ski, banana, dolphin, boat): thighs on the seat, shins down
--            either side, hands on the grips
--   stand    (boards): soles on the deck      prone (boogie): lying on it
--   float    (noodle): forearms on the noodle across the front

local Build = require(script.Parent.Build)

local Rides = {}

local C = Color3.fromRGB
local WHITE = C(255, 255, 255)
local INK = C(24, 26, 40)
local GLASS = C(120, 200, 255)

local builders: { [string]: (Model) -> () } = {}

local function darker(c: Color3, k: number?): Color3
	return c:Lerp(Color3.new(0, 0, 0), k or 0.2)
end

local function lighter(c: Color3, k: number?): Color3
	return c:Lerp(Color3.new(1, 1, 1), k or 0.3)
end

local function keep(p: BasePart): BasePart
	p:SetAttribute("KeepColor", true)
	return p
end

-- block
local function blk(m: Model, size: Vector3, cf: CFrame, color: Color3, props: { [string]: any }?): Part
	return Build.part(m, size, cf, color, props)
end

-- wedge: slope faces -Z (tall at +Z) unless rotated
local function wdg(m: Model, size: Vector3, cf: CFrame, color: Color3, props: { [string]: any }?): WedgePart
	return Build.wedge(m, size, cf, color, props)
end

-- smooth ellipsoid (inflatables, hulls, heads), a little glossy
local function ell(m: Model, size: Vector3, cf: CFrame, color: Color3, props: { [string]: any }?): Part
	local p = Build.ell(m, size, cf, color, props)
	if not (props and props.Reflectance) then
		p.Reflectance = 0.06
	end
	return p
end

local function ball(m: Model, at: Vector3, d: number, color: Color3, props: { [string]: any }?): Part
	local p = Build.ball(m, d, CFrame.new(at), color, props)
	if not (props and props.Reflectance) then
		p.Reflectance = 0.06
	end
	return p
end

-- round rod (cylinder) from a to b
local function rod(m: Model, a: Vector3, b: Vector3, d: number, color: Color3, props: { [string]: any }?): Part
	local mid = (a + b) / 2
	local dir = b - a
	local cf
	if math.abs(dir.Unit.Y) > 0.999 then
		cf = CFrame.new(mid) * CFrame.Angles(0, 0, math.pi / 2)
	else
		cf = CFrame.lookAt(mid, b) * CFrame.Angles(0, math.pi / 2, 0)
	end
	local p = Build.part(m, Vector3.new(dir.Magnitude, d, d), cf, color, props)
	p.Shape = Enum.PartType.Cylinder
	if not (props and props.Reflectance) then
		p.Reflectance = 0.05
	end
	return p
end

-- smooth tube through points: rods with balls at the joints
local function path(m: Model, pts: { Vector3 }, d: number, color: Color3, closed: boolean?, caps: boolean?)
	local n = #pts
	for i = 1, (closed and n or n - 1) do
		rod(m, pts[i], pts[i % n + 1], d, color)
	end
	for i, p in pts do
		if closed or caps or (i > 1 and i < n) then
			ball(m, p, d, color)
		end
	end
end

-- points on an ellipse in the XZ plane (angle 0 = +X, increasing toward +Z)
local function ellipse(c: Vector3, rx: number, rz: number, n: number): { Vector3 }
	local pts = {}
	for i = 0, n - 1 do
		local a = i / n * math.pi * 2
		table.insert(pts, c + Vector3.new(math.cos(a) * rx, 0, math.sin(a) * rz))
	end
	return pts
end

-- point on an elliptic ring's centreline + its outward / tangent directions
local function ringFrame(c: Vector3, rx: number, rz: number, a: number): (Vector3, Vector3, Vector3)
	local p = c + Vector3.new(math.cos(a) * rx, 0, math.sin(a) * rz)
	local out = Vector3.new(math.cos(a) / rx, 0, math.sin(a) / rz).Unit
	local tan = Vector3.new(-math.sin(a) * rx, 0, math.cos(a) * rz).Unit
	return p, out, tan
end

-- solid rounded rectangle slab (w across X, l along Z, h tall)
local function rrect(m: Model, w: number, l: number, h: number, r: number, cf: CFrame, color: Color3, props: { [string]: any }?)
	blk(m, Vector3.new(w - 2 * r, h, l), cf, color, props)
	blk(m, Vector3.new(w, h, l - 2 * r), cf, color, props)
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			Build.cyl(m, h, 2 * r, cf * CFrame.new(sx * (w / 2 - r), 0, sz * (l / 2 - r)), color, props)
		end
	end
end

-- a frame on the surface of an ellipsoid (centre cf, full size `size`) in the
-- local direction u, facing outward (-Z along the surface normal)
local function surf(cf: CFrame, size: Vector3, u: Vector3, sink: number?): CFrame
	local h = size / 2
	u = u.Unit
	local k = 1 / math.sqrt((u.X / h.X) ^ 2 + (u.Y / h.Y) ^ 2 + (u.Z / h.Z) ^ 2)
	local p = u * (k - (sink or 0))
	local n = Vector3.new(p.X / (h.X * h.X), p.Y / (h.Y * h.Y), p.Z / (h.Z * h.Z)).Unit
	local wp = cf * p
	local wn = cf.Rotation * n
	if math.abs(wn.Y) > 0.98 then
		return CFrame.new(wp) * CFrame.Angles(wn.Y > 0 and math.pi / 2 or -math.pi / 2, 0, 0)
	end
	return CFrame.lookAt(wp, wp + wn)
end

-- glossy cartoon eye: dark ellipsoid with a white glint, facing `at` -Z
local function eye(m: Model, at: CFrame, size: Vector3)
	keep(ell(m, size, at, INK, { Reflectance = 0.2 }))
	keep(ell(m, size * 0.3, at * CFrame.new(size.X * 0.17, size.Y * 0.22, -size.Z * 0.4), WHITE, { Material = Enum.Material.Neon }))
end

-- fin hanging under a board / hull: flat top, swept leading edge, tip at the back
local function underFin(m: Model, at: Vector3, h: number, l: number, color: Color3, toe: number?)
	wdg(m, Vector3.new(0.12, h, l), CFrame.new(at) * CFrame.Angles(0, toe or 0, 0) * CFrame.new(0, -h / 2, 0) * CFrame.Angles(0, 0, math.pi), color)
end

-- white foam puffs on the water behind a fast ride
local function wake(m: Model, z: number, width: number)
	for _, x in { -1, 0, 1 } do
		local s = 1 - math.abs(x) * 0.25
		ell(m, Vector3.new(width * 0.5 * s, 0.22, 0.9 * s), CFrame.new(x * width * 0.35, -0.13, z + math.abs(x) * 0.25), WHITE, { Transparency = 0.25 })
	end
end

----------------------------------------------------------------- float
-- one hot-pink foam noodle bent gently round in front of the chest, under
-- the forearms, with open ends showing the hole
builders.Noodle = function(m)
	local pink, hole = C(255, 70, 160), C(200, 40, 120)
	local pts = {}
	local n = 9
	for i = 0, n - 1 do
		local t = -1.0 + 2.0 * i / (n - 1)
		table.insert(pts, Vector3.new(3.3 * math.sin(t), 0.0, 1.25 - 2.2 * math.cos(t)))
	end
	path(m, pts, 0.85, pink)
	-- open ends: a lighter foam rim and the dark hole
	for _, i in { 1, n } do
		local o = pts[i]
		local inward = (i == 1) and (pts[2] - pts[1]).Unit or (pts[n - 1] - pts[n]).Unit
		rod(m, o - inward * 0.02, o + inward * 0.06, 0.86, lighter(pink, 0.25))
		rod(m, o - inward * 0.04, o + inward * 0.1, 0.3, hole)
	end
	-- foam ridges: a few lighter rings along the noodle
	for i = 2, n - 2, 2 do
		local a, b = pts[i], pts[i + 1]
		local mid = (a + b) / 2
		local dir = (b - a).Unit
		rod(m, mid - dir * 0.09, mid + dir * 0.09, 0.9, lighter(pink, 0.35))
	end
end

----------------------------------------------------------------- sit (rings + tub)
-- Ring floats: a smooth torus (rods + balls) around the rider. The rider's
-- knees go over the front of the ring (KNEE_Z), hips over the hole, arms
-- out over the sides.
local KNEE_Z = -0.9
local KNEE_LIFT = 0.95 -- knee joint above the rim top (thighs clear the rim)
local RING_RX, RING_RZ = 1.7, 1.25
local RING_D = 1.2
local RING_Y = -0.1
local RING_C = Vector3.new(0, RING_Y, KNEE_Z + RING_RZ)
local RING_TOP = RING_Y + RING_D / 2

local function torus(m: Model, color: Color3, d: number?, y: number?, n: number?)
	local c = Vector3.new(RING_C.X, y or RING_Y, RING_C.Z)
	path(m, ellipse(c, RING_RX, RING_RZ, n or 16), d or RING_D, color, true)
end

-- a band around the ring tube at angle a (stripes on the inner tube)
local function band(m: Model, a: number, w: number, d: number, color: Color3)
	local p, _, tan = ringFrame(RING_C, RING_RX, RING_RZ, a)
	rod(m, p - tan * w / 2, p + tan * w / 2, d, color)
end

builders.Tube = function(m)
	local red = C(235, 50, 50)
	torus(m, red)
	-- candy stripes, the classic pool ring
	for i = 0, 5 do
		band(m, (i + 0.5) / 6 * math.pi * 2, 0.55, RING_D + 0.04, WHITE)
	end
	-- valve stem on the outside, with a cap
	local p, out = ringFrame(RING_C, RING_RX, RING_RZ, math.pi * 0.2)
	local base = p + out * (RING_D / 2 - 0.05) + Vector3.new(0, 0.12, 0)
	rod(m, base, base + out * 0.32, 0.16, C(60, 60, 70))
	rod(m, base + out * 0.3, base + out * 0.42, 0.2, C(250, 200, 40))
	-- shiny highlight streak on top
	local h, _, tan = ringFrame(RING_C, RING_RX, RING_RZ, math.pi * 1.25)
	ell(m, Vector3.new(0.3, 0.08, 0.9), CFrame.lookAt(h, h + tan) * CFrame.new(0, RING_D / 2 - 0.01, 0) * CFrame.Angles(0.05, 0, 0), WHITE, { Transparency = 0.35 })
end

-- Rubber duck float: a glossy yellow ring body, a plump chest under your
-- legs, a big friendly head out in front, little wings and a tail flick.
local DUCK_YELLOW = C(255, 214, 30)
local DUCK_ORANGE = C(255, 130, 20)
local function duck(m: Model, yellow: Color3, orange: Color3)
	torus(m, yellow, 1.25, -0.05)
	-- rump + tail flick behind your back
	ell(m, Vector3.new(2.3, 1.35, 1.7), CFrame.new(0, 0.2, RING_C.Z + RING_RZ + 0.25), yellow)
	ell(m, Vector3.new(1.3, 0.75, 1.3), CFrame.new(0, 0.85, RING_C.Z + RING_RZ + 0.75) * CFrame.Angles(0.75, 0, 0), yellow)
	ell(m, Vector3.new(0.7, 0.55, 0.9), CFrame.new(0, 1.35, RING_C.Z + RING_RZ + 1.05) * CFrame.Angles(1.1, 0, 0), yellow)
	-- wings folded along the sides, tips swept up at the back
	for _, s in { -1, 1 } do
		ell(m, Vector3.new(0.4, 0.75, 1.8), CFrame.new(s * (RING_RX + 0.5), 0.25, RING_C.Z + 0.4) * CFrame.Angles(-0.3, 0, s * 0.18), darker(yellow, 0.05))
	end
	-- plump chest under your shins, a thick neck, then the head
	ell(m, Vector3.new(2.2, 1.3, 2.4), CFrame.new(0, 0.05, KNEE_Z - 1.2), yellow)
	ell(m, Vector3.new(1.6, 2.0, 1.6), CFrame.new(0, 0.85, KNEE_Z - 2.25) * CFrame.Angles(0.25, 0, 0), yellow)
	local head = CFrame.new(0, 2.2, KNEE_Z - 2.35)
	local HEAD = Vector3.new(2.15, 2.0, 2.0)
	ell(m, HEAD, head, yellow)
	-- tuft of feathers on top
	ell(m, Vector3.new(0.3, 0.55, 0.45), head * CFrame.new(0, 1.05, 0.05) * CFrame.Angles(0.35, 0, 0), yellow)
	ell(m, Vector3.new(0.25, 0.4, 0.35), head * CFrame.new(0, 1.0, 0.35) * CFrame.Angles(0.9, 0, 0), yellow)
	-- flat orange bill: wide upper half, smaller lower half
	local bill = head * CFrame.new(0, -0.22, -0.88)
	keep(ell(m, Vector3.new(1.35, 0.36, 1.05), bill * CFrame.new(0, 0.1, -0.12) * CFrame.Angles(-0.12, 0, 0), orange, { Name = "Bill" }))
	keep(ell(m, Vector3.new(1.05, 0.3, 0.8), bill * CFrame.new(0, -0.14, -0.02) * CFrame.Angles(0.1, 0, 0), darker(orange, 0.12), { Name = "Bill" }))
	-- big friendly eyes + rosy cheeks
	for _, s in { -1, 1 } do
		eye(m, surf(head, HEAD, Vector3.new(s * 0.42, 0.3, -1), 0.06), Vector3.new(0.48, 0.64, 0.24))
		keep(ell(m, Vector3.new(0.42, 0.26, 0.14), surf(head, HEAD, Vector3.new(s * 0.85, -0.18, -1), 0.04), C(255, 140, 130), { Name = "Cheek" }))
	end
	-- glossy highlight on the head
	keep(ell(m, Vector3.new(0.55, 0.3, 0.14), surf(head, HEAD, Vector3.new(-0.45, 0.75, -0.45), 0.04), WHITE, { Transparency = 0.4, Name = "Shine" }))
end

builders.Duck = function(m)
	duck(m, DUCK_YELLOW, DUCK_ORANGE)
end

builders.GoldDuck = function(m)
	duck(m, DUCK_YELLOW, DUCK_ORANGE)
	Build.recolor(m, C(255, 186, 20), Enum.Material.SmoothPlastic)
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") and not d:GetAttribute("KeepColor") then
			d.Reflectance = 0.25
		elseif d.Name == "Bill" then
			(d :: BasePart).Color = C(255, 140, 30);
			(d :: BasePart).Reflectance = 0.25
		end
	end
	-- a little crown with gems
	local head = CFrame.new(0, 2.2, KNEE_Z - 2.35)
	local crown = head * CFrame.new(0, 0.98, 0.25) * CFrame.Angles(-0.12, 0, 0)
	local gold = C(255, 205, 50)
	keep(Build.cyl(m, 0.32, 0.95, crown, gold, { Reflectance = 0.35 }))
	for i = 0, 4 do
		local a = i / 5 * math.pi * 2
		keep(ball(m, (crown * CFrame.new(math.cos(a) * 0.4, 0.27, math.sin(a) * 0.4)).Position, 0.24, gold, { Reflectance = 0.35 }))
	end
	keep(ell(m, Vector3.new(0.24, 0.24, 0.12), crown * CFrame.new(0, 0, -0.47), C(230, 30, 70), { Reflectance = 0.3 }))
	for _, s in { -1, 1 } do
		keep(ell(m, Vector3.new(0.16, 0.16, 0.1), crown * CFrame.Angles(0, s * 0.8, 0) * CFrame.new(0, 0, -0.47), C(40, 160, 255), { Reflectance = 0.3 }))
	end
	local sp = Instance.new("Sparkles")
	sp.SparkleColor = C(255, 230, 120)
	sp.Parent = m:FindFirstChildWhichIsA("BasePart")
end

-- frosted donut: golden dough torus, pink icing poured over the top with
-- drips down the sides, and rainbow sprinkles
local ICING_UP = 0.26
builders.Donut = function(m)
	local dough, icing = C(222, 160, 90), C(255, 120, 190)
	local d = 1.35
	torus(m, dough, d, -0.1, 18)
	local ic = Vector3.new(RING_C.X, -0.1 + ICING_UP, RING_C.Z)
	path(m, ellipse(ic, RING_RX, RING_RZ, 18), d + 0.02, icing, true)
	-- drips down the outside
	local doughC = Vector3.new(RING_C.X, -0.1, RING_C.Z)
	for i = 0, 8 do
		local a = (i + 0.3) / 9 * math.pi * 2 + (i % 2) * 0.15
		local p, out = ringFrame(doughC, RING_RX, RING_RZ, a)
		local len = (i % 3 == 0) and 0.6 or 0.42
		ell(m, Vector3.new(0.3, len, 0.3), CFrame.new(p + out * (d / 2 - 0.05) + Vector3.new(0, 0.24 - len / 2, 0)), icing)
	end
	-- sprinkles lying on the icing (on top and the outer slope)
	local cols = { WHITE, C(255, 220, 40), C(60, 190, 255), C(110, 220, 110), C(170, 90, 255), C(255, 90, 60) }
	local rng = Random.new(7)
	local R = (d + 0.02) / 2
	for i = 1, 26 do
		local a = i / 26 * math.pi * 2 + rng:NextNumber(-0.06, 0.06)
		local p, out, tan = ringFrame(ic, RING_RX, RING_RZ, a)
		local phi = rng:NextNumber(-0.7, 0.8) -- 0 = straight up, + = outward
		local nrm = (out * math.sin(phi) + Vector3.new(0, math.cos(phi), 0)).Unit
		local at = p + nrm * (R + 0.02)
		local spin = rng:NextNumber(0, math.pi)
		local side = tan:Cross(nrm).Unit
		local dir = (tan * math.cos(spin) + side * math.sin(spin)).Unit
		rod(m, at - dir * 0.17, at + dir * 0.17, 0.1, cols[i % #cols + 1])
	end
end
local DONUT_TOP = -0.1 + ICING_UP + (1.35 + 0.02) / 2

-- clawfoot bathtub: pastel tub with straight sides over a rounded belly, a
-- rolled white rim, gold claw feet and taps, a bubble bath you sit in
-- (knees over the front rim) and a rubber duckie
local TUB_W, TUB_FRONT, TUB_BACK, TUB_R = 3.2, KNEE_Z - 0.3, 2.7, 1.0
local TUB_TOP = 1.2 -- rim centre height
builders.Bathtub = function(m)
	local body, rim, gold, water = C(110, 200, 235), WHITE, C(255, 196, 40), C(150, 225, 255)
	local len = TUB_BACK - TUB_FRONT
	local zc = (TUB_FRONT + TUB_BACK) / 2
	local wallY = 0.5 -- walls run from the belly up to the rim
	-- straight walls, then a rounded belly underneath
	rrect(m, TUB_W - 0.2, len - 0.2, TUB_TOP - wallY, TUB_R - 0.1, CFrame.new(0, (TUB_TOP + wallY) / 2, zc), body)
	ell(m, Vector3.new(TUB_W - 0.15, 1.1, len - 0.1), CFrame.new(0, wallY, zc), body)
	-- a darker trim band low on the walls
	rrect(m, TUB_W - 0.16, len - 0.16, 0.12, TUB_R - 0.08, CFrame.new(0, wallY + 0.12, zc), darker(body, 0.15))
	-- bubbly water inside the rim
	rrect(m, TUB_W - 0.5, len - 0.5, 0.1, TUB_R - 0.25, CFrame.new(0, TUB_TOP + 0.02, zc), water)
	-- rolled rim (rounded-rect tube)
	local pts = {}
	local hw, hl, r = TUB_W / 2 - 0.15, len / 2 - 0.15, TUB_R - 0.15
	for q, c in { { 1, 1 }, { -1, 1 }, { -1, -1 }, { 1, -1 } } do
		local cx, cz = c[1] * (hw - r), zc + c[2] * (hl - r)
		for k = 0, 2 do
			local ang = (q - 1) * math.pi / 2 + k / 2 * math.pi / 2
			table.insert(pts, Vector3.new(cx + math.cos(ang) * r, TUB_TOP, cz + math.sin(ang) * r))
		end
	end
	path(m, pts, 0.38, rim, true)
	-- claw feet: a curved gold leg + ball-and-claw foot at each corner
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			local x, z = sx * (TUB_W / 2 - 0.6), zc + sz * (len / 2 - 0.7)
			ell(m, Vector3.new(0.4, 0.75, 0.4), CFrame.new(x + sx * 0.15, 0.05, z + sz * 0.15) * CFrame.Angles(sz * 0.4, 0, -sx * 0.4), gold, { Reflectance = 0.25 })
			ell(m, Vector3.new(0.5, 0.36, 0.5), CFrame.new(x + sx * 0.32, -0.25, z + sz * 0.32), gold, { Reflectance = 0.25 })
		end
	end
	-- gold taps at the back with a curved spout and hot / cold knobs
	local tz = TUB_BACK - 0.18
	local gp = { Reflectance = 0.3 }
	rod(m, Vector3.new(0, TUB_TOP, tz), Vector3.new(0, TUB_TOP + 0.75, tz), 0.2, gold, gp)
	ball(m, Vector3.new(0, TUB_TOP + 0.75, tz), 0.2, gold, gp)
	rod(m, Vector3.new(0, TUB_TOP + 0.75, tz), Vector3.new(0, TUB_TOP + 0.75, tz - 0.5), 0.2, gold, gp)
	rod(m, Vector3.new(0, TUB_TOP + 0.75, tz - 0.5), Vector3.new(0, TUB_TOP + 0.58, tz - 0.5), 0.26, gold, gp)
	for _, sd in { -1, 1 } do
		rod(m, Vector3.new(sd * 0.42, TUB_TOP, tz), Vector3.new(sd * 0.42, TUB_TOP + 0.32, tz), 0.12, gold, gp)
		ball(m, Vector3.new(sd * 0.42, TUB_TOP + 0.38, tz), 0.24, sd < 0 and C(240, 60, 60) or C(60, 140, 255))
	end
	-- bubble bath foam piled round the edges (clear of the rider)
	local rng = Random.new(11)
	local foam = {
		Vector3.new(-1.0, 0, 2.15), Vector3.new(-0.55, 0, 2.3), Vector3.new(0.55, 0, 2.3), Vector3.new(1.0, 0, 2.1),
		Vector3.new(-1.1, 0, 1.45), Vector3.new(1.1, 0, 1.4), Vector3.new(-1.15, 0, -0.75), Vector3.new(1.15, 0, -0.75),
		Vector3.new(-1.15, 0, 0.35), Vector3.new(1.1, 0, 0.5), Vector3.new(-0.7, 0, 1.9),
	}
	for _, f in foam do
		local dd = rng:NextNumber(0.42, 0.68)
		ball(m, Vector3.new(f.X, TUB_TOP + 0.05 + dd * 0.2, f.Z), dd, WHITE)
	end
	-- floating soap bubbles
	for _, bb in { Vector3.new(-1.0, 2.5, 2.4), Vector3.new(-1.45, 3.2, 2.8), Vector3.new(1.35, 2.9, 2.9) } do
		ball(m, bb, 0.38 + (bb.Y - 2.5) * 0.2, C(220, 240, 255), { Transparency = 0.45, Reflectance = 0.3 })
	end
	-- little rubber duckie bobbing in the back corner
	local dk = CFrame.new(0.95, TUB_TOP + 0.28, TUB_BACK - 0.75) * CFrame.Angles(0, 0.5, 0)
	ell(m, Vector3.new(0.5, 0.42, 0.65), dk, DUCK_YELLOW)
	ell(m, Vector3.new(0.25, 0.28, 0.25), dk * CFrame.new(0, 0.12, 0.33) * CFrame.Angles(0.8, 0, 0), DUCK_YELLOW)
	ball(m, (dk * CFrame.new(0, 0.38, -0.2)).Position, 0.38, DUCK_YELLOW)
	ell(m, Vector3.new(0.24, 0.08, 0.2), dk * CFrame.new(0, 0.34, -0.42), DUCK_ORANGE)
	for _, sd in { -1, 1 } do
		ell(m, Vector3.new(0.07, 0.09, 0.05), dk * CFrame.new(sd * 0.1, 0.45, -0.37), INK)
	end
end

----------------------------------------------------------------- prone
-- bodyboard: rounded nose, blue deck / yellow rail / white slick, a wave
-- logo on the nose and a coiled leash at the tail
builders.Boogie = function(m)
	local deck, rail, slick = C(30, 120, 240), C(255, 210, 30), C(250, 250, 252)
	local zc, w, l = -0.15, 2.5, 4.5
	rrect(m, w - 0.06, l - 0.06, 0.12, 0.62, CFrame.new(0, -0.02, zc), slick)
	rrect(m, w, l, 0.08, 0.65, CFrame.new(0, 0.08, zc), rail)
	rrect(m, w - 0.04, l - 0.04, 0.16, 0.63, CFrame.new(0, 0.2, zc), deck)
	-- nose bulb + wave logo
	local nose = zc - l / 2
	ell(m, Vector3.new(1.6, 0.1, 0.55), CFrame.new(0, 0.28, nose + 0.5), WHITE)
	ell(m, Vector3.new(0.9, 0.06, 0.32), CFrame.new(-0.15, 0.31, nose + 0.5), C(255, 90, 90))
	-- side channels (lighter stripes) + tail crescent
	for _, s in { -1, 1 } do
		blk(m, Vector3.new(0.14, 0.05, l - 1.6), CFrame.new(s * (w / 2 - 0.35), 0.29, zc + 0.2), lighter(deck, 0.35))
	end
	ell(m, Vector3.new(1.2, 0.08, 0.4), CFrame.new(0, 0.27, zc + l / 2 - 0.25), rail)
	-- leash plug + coiled cord
	ball(m, Vector3.new(0.75, 0.3, zc + l / 2 - 0.35), 0.18, INK)
	for i = 0, 5 do
		local z = zc + l / 2 - 0.25 + i * 0.13
		rod(m, Vector3.new(0.75, 0.28 - math.min(i, 1) * 0.1, z), Vector3.new(0.75, 0.22 - math.min(i, 1) * 0.1, z + 0.13), 0.08, INK)
	end
end

----------------------------------------------------------------- stand
-- A surfboard: lens-shaped deck over a colored rail, a pointier nose with
-- a little rocker, a center stripe and three fins.
-- Deck top (where the soles go) is y 0.05.
local DECK = 0.05
local function surfboard(m: Model, len: number, wid: number, deck: Color3, rail: Color3, stripe: Color3?)
	local th = 0.34
	local yc = DECK - th / 2
	local zMain, lMain = len * 0.08, len * 0.84
	local zNose, lNose = -len * 0.2, len * 0.6
	local rocker = CFrame.Angles(0.05, 0, 0)
	local function layer(dy: number, grow: number, color: Color3, wscale: number?, dyNose: number?)
		local ws = wscale or 1
		ell(m, Vector3.new(wid * ws + grow, th, lMain + grow), CFrame.new(0, yc + dy, zMain), color)
		ell(m, Vector3.new(wid * 0.74 * ws + grow, th, lNose + grow), CFrame.new(0, yc + dy + (dyNose or 0), zNose) * rocker, color)
	end
	layer(-0.07, 0.06, rail)
	layer(0, 0, deck)
	if stripe then
		layer(0.025, 0, stripe, 0.16, 0.01)
	end
	-- thruster fins
	local tail = zMain + lMain / 2
	underFin(m, Vector3.new(0, yc - 0.06, tail - 0.75), 0.8, 0.85, darker(rail, 0.1))
	for _, s in { -1, 1 } do
		underFin(m, Vector3.new(s * wid * 0.3, yc - 0.06, tail - 1.25), 0.55, 0.6, darker(rail, 0.1), s * 0.08)
	end
	return tail, zNose - lNose / 2
end

builders.Surf = function(m)
	local _, nose = surfboard(m, 8, 2.3, C(40, 205, 220), C(255, 120, 60), C(255, 210, 40))
	-- sunny logo near the nose (rings sit a hair proud of the deck)
	ell(m, Vector3.new(0.85, 0.34, 0.85), CFrame.new(0, DECK - 0.17 + 0.035, nose + 2.1), WHITE)
	ell(m, Vector3.new(0.62, 0.34, 0.62), CFrame.new(0, DECK - 0.17 + 0.05, nose + 2.1), C(255, 120, 60))
	ell(m, Vector3.new(0.36, 0.34, 0.36), CFrame.new(0, DECK - 0.17 + 0.065, nose + 2.1), C(255, 210, 40))
end

builders.Rocket = function(m)
	local navy, red, yel, steel = C(38, 42, 90), C(240, 50, 60), C(255, 200, 40), C(225, 228, 238)
	local tail, nose = surfboard(m, 8.4, 2.5, navy, red, yel)
	-- red nose cone tip
	ell(m, Vector3.new(0.9, 0.36, 1.3), CFrame.new(0, DECK - 0.15, nose + 0.6), red)
	-- twin rocket boosters on the tail
	for _, s in { -1, 1 } do
		local x, y = s * 0.62, DECK + 0.32
		local z0, z1 = tail - 2.4, tail - 0.4
		rod(m, Vector3.new(x, y, z0), Vector3.new(x, y, z1), 0.62, steel, { Reflectance = 0.2 })
		ell(m, Vector3.new(0.62, 0.62, 0.9), CFrame.new(x, y, z0), red)
		rod(m, Vector3.new(x, y, z0 + 0.55), Vector3.new(x, y, z0 + 0.75), 0.64, red)
		-- nozzle bell + glow
		rod(m, Vector3.new(x, y, z1), Vector3.new(x, y, z1 + 0.35), 0.5, C(70, 70, 80), { Reflectance = 0.2 })
		rod(m, Vector3.new(x, y, z1 + 0.33), Vector3.new(x, y, z1 + 0.36), 0.4, C(255, 160, 40), { Material = Enum.Material.Neon })
		-- fins
		wdg(m, Vector3.new(0.08, 0.45, 0.6), CFrame.new(x + s * 0.4, y + 0.05, z1 - 0.3) * CFrame.Angles(0, 0, s * 1.2), red)
		wdg(m, Vector3.new(0.08, 0.45, 0.6), CFrame.new(x, y + 0.48, z1 - 0.3), red)
		-- flame: hot core inside a soft outer flame
		ell(m, Vector3.new(0.4, 0.4, 1.3), CFrame.new(x, y, z1 + 0.95), C(255, 230, 120), { Material = Enum.Material.Neon })
		local flame = ell(m, Vector3.new(0.58, 0.58, 2.0), CFrame.new(x, y, z1 + 1.2), C(255, 120, 30), { Material = Enum.Material.Neon, Transparency = 0.35 })
		local fire = Instance.new("Fire")
		fire.Size = 3
		fire.Heat = 0
		fire.Color = C(255, 160, 40)
		fire.SecondaryColor = C(255, 60, 30)
		fire.Parent = flame
	end
	-- speed chevrons on the deck nose
	for i = 0, 1 do
		for _, s in { -1, 1 } do
			blk(m, Vector3.new(0.5, 0.04, 0.14), CFrame.new(s * 0.2, DECK + 0.005, nose + 2.2 + i * 0.4) * CFrame.Angles(0, s * 0.6, 0), yel)
		end
	end
end

builders.SharkBoard = function(m)
	local grey, belly, dark, gum = C(100, 130, 170), C(245, 247, 250), C(72, 95, 130), C(150, 25, 45)
	local len, wid = 8, 2.5
	local tail, nose = surfboard(m, len, wid, grey, belly)
	local yc = DECK - 0.17
	-- dorsal fin behind the rider: swept wedge on a rounded base
	wdg(m, Vector3.new(0.26, 1.5, 1.7), CFrame.new(0, DECK + 0.68, tail - 2.0) * CFrame.Angles(0.12, 0, 0), dark)
	ell(m, Vector3.new(0.5, 0.3, 1.9), CFrame.new(0, DECK - 0.05, tail - 2.05), dark)
	-- tail fin standing up at the very back
	wdg(m, Vector3.new(0.2, 0.9, 0.8), CFrame.new(0, DECK + 0.35, tail - 0.1) * CFrame.Angles(-0.5, 0, 0), dark)
	-- toothy grin across the front of the nose: dark mouth + white teeth
	local zNose, lNose, wNose = -len * 0.2, len * 0.6, wid * 0.74
	local rocker = CFrame.Angles(0.05, 0, 0)
	local noseCf = CFrame.new(0, yc, zNose) * rocker
	local tipZ = -lNose / 2
	ell(m, Vector3.new(1.5, 0.16, 1.1), noseCf * CFrame.new(0, -0.01, tipZ + 0.45), gum)
	local hx, hz = wNose / 2, lNose / 2
	for i = -3, 3 do
		local t = i / 3 * 0.42
		local at = noseCf * Vector3.new(hx * math.sin(t), 0.02, -hz * math.cos(t))
		local outward = noseCf.Rotation * Vector3.new(math.sin(t) / hx, 0, -math.cos(t) / hz).Unit
		keep(wdg(m, Vector3.new(0.14, 0.2, 0.12), CFrame.lookAt(at, at + outward) * CFrame.new(0, -0.06, 0.02) * CFrame.Angles(0, math.pi, 0) * CFrame.Angles(math.pi, 0, 0), WHITE))
	end
	-- pectoral fins out from the rails
	for _, sd in { -1, 1 } do
		ell(m, Vector3.new(1.3, 0.1, 0.6), CFrame.new(sd * (wid / 2 + 0.35), yc - 0.08, -0.9) * CFrame.Angles(0, sd * 0.55, sd * -0.15), dark)
	end
	-- eyes on little bumps, gills down the sides
	local face = nose + 1.7
	for _, sd in { -1, 1 } do
		local BUMP = Vector3.new(0.75, 0.42, 0.75)
		local bump = CFrame.new(sd * 0.5, DECK - 0.06, face)
		ell(m, BUMP, bump, grey)
		eye(m, surf(bump, BUMP, Vector3.new(sd * 0.5, 0.6, -1), 0.03), Vector3.new(0.4, 0.4, 0.16))
		keep(ell(m, Vector3.new(0.42, 0.1, 0.14), bump * CFrame.new(sd * 0.04, 0.22, 0.02) * CFrame.Angles(0, sd * 0.35, sd * 0.35), dark))
		for g = 0, 2 do
			blk(m, Vector3.new(0.05, 0.05, 0.36), CFrame.new(sd * (0.72 - g * 0.03), DECK - 0.015, face + 0.75 + g * 0.24) * CFrame.Angles(0, sd * 0.15, 0), dark)
		end
	end
end

----------------------------------------------------------------- straddle
-- Shared layout (Rig straddle pose): thighs on a seat whose top is y 1.0
-- (z 0.15 .. 1.95), shins down either side (x > 0.5, z -1.2 .. 0.3, feet at
-- y 0.25 out to x 1.6), hands on grips at GRIP. Anything in front starts at
-- z -1.3.
local SEAT_TOP = 1.0
local GRIP = Vector3.new(1.78, 2.5, -1.6)

local function grips(m: Model, color: Color3, d: number?)
	for _, x in { -GRIP.X, GRIP.X } do
		rod(m, Vector3.new(x - 0.28, GRIP.Y, GRIP.Z), Vector3.new(x + 0.28, GRIP.Y, GRIP.Z), d or 0.32, color, { Name = "Grip" })
	end
end

-- handlebar: column from `from` up to a bar between the grips
local function handlebar(m: Model, from: Vector3, color: Color3, grip: Color3)
	local top = Vector3.new(0, GRIP.Y - 0.1, GRIP.Z)
	rod(m, from, top, 0.28, color)
	ball(m, top, 0.34, color)
	for _, s in { -1, 1 } do
		rod(m, top, Vector3.new(s * (GRIP.X - 0.3), GRIP.Y, GRIP.Z), 0.2, color, { Name = "Grip" })
	end
	grips(m, grip)
end

-- jet ski: white hull nose-up, a sleek colored hood merged into the bow,
-- a console between your knees, a padded saddle on a rounded pedestal,
-- footwells either side, handlebar, nozzle and wake. `hood` is one color,
-- or a list of rainbow colors (nested hood layers + side stripes).
local function jetSki(m: Model, hood: { Color3 }, trim: Color3)
	local hull, seat, mat = C(245, 247, 252), C(28, 30, 38), C(55, 60, 72)
	local main = hood[1]
	local HULL = Vector3.new(3.5, 1.0, 8.4)
	local hullCf = CFrame.new(0, -0.22, -0.3) * CFrame.Angles(0.05, 0, 0)
	ell(m, HULL, hullCf, hull)
	-- side stripes: thin bands following the hull's curve
	local bands = #hood > 1 and hood or { trim }
	for i, col in bands do
		local dy = 0.22 - (i - 1) * 0.1
		local k = math.sqrt(1 - (dy / (HULL.Y / 2)) ^ 2)
		ell(m, Vector3.new(HULL.X * k + 0.07, 0.11, HULL.Z * k + 0.07), hullCf * CFrame.new(0, dy, 0), col)
	end
	-- deck with dark foot mats
	rrect(m, 3.2, 4.4, 0.14, 0.7, CFrame.new(0, 0.13, 0.6), hull)
	for _, sd in { -1, 1 } do
		rrect(m, 0.95, 1.9, 0.04, 0.3, CFrame.new(sd * 1.05, 0.21, -0.3), mat)
	end
	-- console between the knees, pedestal + saddle (top at SEAT_TOP)
	ell(m, Vector3.new(0.9, 1.0, 2.4), CFrame.new(0, 0.5, -0.75), main)
	ell(m, Vector3.new(1.3, 1.1, 3.1), CFrame.new(0, 0.42, 1.5), main)
	ell(m, Vector3.new(1.46, 0.56, 2.8), CFrame.new(0, SEAT_TOP - 0.28, 1.35), seat)
	ell(m, Vector3.new(1.2, 0.5, 0.9), CFrame.new(0, SEAT_TOP - 0.1, 2.55), seat)
	-- rear platform + jet nozzle
	rrect(m, 2.4, 1.0, 0.3, 0.45, CFrame.new(0, 0.05, 3.25), hull)
	rod(m, Vector3.new(0, -0.18, 3.4), Vector3.new(0, -0.18, 4.05), 0.5, C(60, 62, 70))
	-- hood: a low dome over the bow (rainbow = nested layers to a violet cap)
	local n = #hood
	local HOOD = Vector3.new(3.1, 1.2, 4.0)
	local hoodCf = CFrame.new(0, 0.15, -3.3) * CFrame.Angles(0.14, 0, 0)
	-- (rainbow: each layer is shorter at the nose and a hair higher, so the
	-- colors show as arcs sweeping back over the hood)
	for i, col in hood do
		local k = (i - 1) / n
		ell(m, Vector3.new(HOOD.X - k * 0.3, HOOD.Y, HOOD.Z - k * 2.9), hoodCf * CFrame.new(0, k * 0.16, k * 1.45), col)
	end
	-- cowl sweeping from the hood up to the console
	ell(m, Vector3.new(1.4, 1.1, 2.8), CFrame.new(0, 0.55, -1.85) * CFrame.Angles(-0.2, 0, 0), main)
	if n == 1 then
		-- white racing stripe over the top
		ell(m, Vector3.new(0.55, HOOD.Y, HOOD.Z), hoodCf * CFrame.new(0, 0.03, 0), WHITE)
	end
	-- headlights on the nose
	for _, sd in { -1, 1 } do
		ell(m, Vector3.new(0.6, 0.16, 0.1), surf(hoodCf, HOOD, Vector3.new(sd * 0.7, 0.3, -1), 0.03) * CFrame.Angles(0, 0, sd * 0.25), C(200, 240, 255), { Material = Enum.Material.Neon })
	end
	-- windshield + handlebar
	ell(m, Vector3.new(1.3, 0.7, 0.1), CFrame.new(0, 1.18, -1.95) * CFrame.Angles(-0.7, 0, 0), C(80, 160, 230), { Transparency = 0.35 })
	handlebar(m, Vector3.new(0, 0.95, -1.45), C(45, 48, 58), INK)
	wake(m, 4.5, 2.6)
end

builders.JetSki = function(m)
	jetSki(m, { C(232, 30, 50) }, C(232, 30, 50))
end

builders.RainbowSki = function(m)
	jetSki(m, { C(235, 45, 55), C(255, 140, 30), C(255, 214, 40), C(70, 200, 80), C(40, 140, 255), C(150, 70, 230) }, WHITE)
end

-- inflatable banana boat: a smooth curved yellow tube you sit astride,
-- tapered ends with a green stem at the nose, side pontoons, a padded
-- handlebar and a passenger handle behind
builders.Banana = function(m)
	local yel, tipC, stem, blue, pad = C(255, 222, 40), C(110, 75, 35), C(130, 170, 50), C(40, 140, 255), C(255, 120, 40)
	local D = 1.05
	local pts = {
		Vector3.new(0, 1.05, 3.35), Vector3.new(0, 0.62, 2.6), Vector3.new(0, 0.45, 1.5), Vector3.new(0, 0.38, 0.3),
		Vector3.new(0, 0.33, -0.8), Vector3.new(0, 0.45, -2.0), Vector3.new(0, 0.85, -2.95), Vector3.new(0, 1.45, -3.55),
	}
	path(m, pts, D, yel)
	-- tapered ends: nose -> stem, tail -> dark tip
	local nd = (pts[8] - pts[7]).Unit
	local noseCf = CFrame.lookAt(pts[8], pts[8] + nd)
	ell(m, Vector3.new(D, D, 1.2), noseCf, yel)
	ell(m, Vector3.new(0.72, 0.72, 0.7), noseCf * CFrame.new(0, 0, -0.55), C(200, 215, 60))
	rod(m, (noseCf * CFrame.new(0, 0, -0.75)).Position, (noseCf * CFrame.new(0, 0, -1.3)).Position, 0.34, stem)
	ell(m, Vector3.new(0.4, 0.4, 0.22), noseCf * CFrame.new(0, 0, -1.33), tipC)
	local td = (pts[1] - pts[2]).Unit
	local tailCf = CFrame.lookAt(pts[1], pts[1] + td)
	ell(m, Vector3.new(D, D, 1.0), tailCf, yel)
	ell(m, Vector3.new(0.42, 0.42, 0.3), tailCf * CFrame.new(0, 0, -0.5), tipC)
	-- a seam line along the top of the tube
	for i = 2, 6 do
		local a, b = pts[i], pts[i + 1]
		rod(m, a + Vector3.new(0, D / 2 - 0.03, 0), b + Vector3.new(0, D / 2 - 0.03, 0), 0.1, lighter(yel, 0.45))
	end
	-- side pontoons (half under water) with cross struts
	for _, sd in { -1, 1 } do
		path(m, { Vector3.new(sd * 1.8, -0.2, 2.9), Vector3.new(sd * 1.8, -0.2, -0.6) }, 0.72, blue, false, true)
		rod(m, Vector3.new(sd * 1.8, -0.2, 0.4), Vector3.new(0, -0.2, 0.4), 0.22, blue)
		rod(m, Vector3.new(sd * 1.8, -0.2, 2.3), Vector3.new(0, -0.2, 2.3), 0.22, blue)
	end
	-- padded handlebar on a post in front of you
	handlebar(m, Vector3.new(0, 0.8, -1.65), blue, pad)
	-- passenger handle behind
	for _, sd in { -1, 1 } do
		rod(m, Vector3.new(sd * 0.35, 0.95, 2.55), Vector3.new(sd * 0.35, 1.55, 2.55), 0.16, blue)
	end
	rod(m, Vector3.new(-0.45, 1.55, 2.55), Vector3.new(0.45, 1.55, 2.55), 0.24, pad)
	wake(m, 4.4, 2.4)
end

-- sporty speedboat: white topsides over a blue V hull with a red speed
-- stripe, pointed bow, wraparound windshield, bucket seat, outboard motor
builders.Speedboat = function(m)
	local white, blue, red, dark, chrome = C(250, 250, 255), C(30, 90, 220), C(240, 50, 60), C(40, 42, 52), C(205, 210, 220)
	local W, z0, z1, bowZ = 4.4, -1.3, 3.6, -5.0 -- hull width, bow start, transom, bow tip
	local L = z1 - z0
	local zc = (z0 + z1) / 2
	local bowL = z0 - bowZ
	-- one slice of the hull: box + two wedges for the pointed bow
	local function slice(y0: number, h: number, color: Color3, grow: number)
		local yc = y0 + h / 2
		local w = W + grow
		blk(m, Vector3.new(w, h, L + grow), CFrame.new(0, yc, zc), color)
		for _, sd in { -1, 1 } do
			wdg(m, Vector3.new(h, w / 2, bowL + grow), CFrame.new(sd * w / 4, yc, z0 - (bowL + grow) / 2 + grow / 2) * CFrame.Angles(0, 0, -sd * math.pi / 2), color)
		end
	end
	slice(-0.55, 0.55, blue, 0) -- lower hull
	slice(0.0, 0.2, white, 0) -- cockpit floor level (top 0.2)
	slice(0.16, 0.12, red, 0.06) -- speed stripe
	-- V bottom under the hull: two long wedges meeting at the keel
	for _, sd in { -1, 1 } do
		wdg(m, Vector3.new(L, 0.45, W / 2), CFrame.new(sd * W / 4, -0.55 - 0.225, zc) * CFrame.Angles(0, -sd * math.pi / 2, 0) * CFrame.Angles(0, 0, math.pi), darker(blue, 0.25))
	end
	-- topsides: gunwales round the cockpit with rounded caps, foredeck
	local top = 1.25
	local gx = W / 2 - 0.21
	for _, sd in { -1, 1 } do
		blk(m, Vector3.new(0.42, top - 0.3, L), CFrame.new(sd * gx, (top + 0.3) / 2, zc), white)
		rod(m, Vector3.new(sd * gx, top, z0), Vector3.new(sd * gx, top, z1), 0.42, white)
		ball(m, Vector3.new(sd * gx, top, z1), 0.42, white)
		ball(m, Vector3.new(sd * gx, top, z0), 0.42, white)
		wdg(m, Vector3.new(top - 0.3, W / 2, bowL), CFrame.new(sd * W / 4, (top + 0.3) / 2, z0 - bowL / 2) * CFrame.Angles(0, 0, -sd * math.pi / 2), white)
	end
	blk(m, Vector3.new(W - 0.84, top - 0.3, 0.4), CFrame.new(0, (top + 0.3) / 2, z1 - 0.2), white)
	rod(m, Vector3.new(-gx, top, z1), Vector3.new(gx, top, z1), 0.42, white)
	-- blue racing chevron on the foredeck + bow rail
	for _, sd in { -1, 1 } do
		blk(m, Vector3.new(0.3, 0.04, 1.6), CFrame.new(sd * 0.42, top - 0.33 + 0.37, z0 - 1.1) * CFrame.Angles(0, -sd * 0.45, 0), blue)
	end
	rod(m, Vector3.new(0, top + 0.1, bowZ + 0.6), Vector3.new(0, top + 0.1, z0 - 0.6), 0.12, chrome, { Reflectance = 0.3 })
	for _, z in { bowZ + 0.6, z0 - 0.6 } do
		rod(m, Vector3.new(0, top - 0.33 + 0.35, z), Vector3.new(0, top + 0.1, z), 0.1, chrome, { Reflectance = 0.3 })
	end
	-- wraparound windshield on the dash with a chrome grab rail (the grips)
	local wz = -1.5
	local glass = GLASS
	blk(m, Vector3.new(2.0, 0.85, 0.08), CFrame.new(0, top + 0.4, wz - 0.12) * CFrame.Angles(-0.35, 0, 0), glass, { Transparency = 0.4 })
	for _, sd in { -1, 1 } do
		blk(m, Vector3.new(0.85, 0.7, 0.08), CFrame.new(sd * 1.35, top + 0.35, wz + 0.12) * CFrame.Angles(0, -sd * 0.6, 0) * CFrame.Angles(-0.3, 0, 0), glass, { Transparency = 0.4 })
	end
	rod(m, Vector3.new(-1.0, top + 0.8, wz - 0.26), Vector3.new(1.0, top + 0.8, wz - 0.26), 0.1, chrome, { Reflectance = 0.3 })
	for _, sd in { -1, 1 } do
		ball(m, Vector3.new(sd * 1.0, top + 0.8, wz - 0.26), 0.14, chrome, { Reflectance = 0.3 })
		rod(m, Vector3.new(sd * 1.0, top + 0.8, wz - 0.26), Vector3.new(sd * (GRIP.X - 0.28), GRIP.Y, GRIP.Z), 0.12, chrome, { Reflectance = 0.3, Name = "Grip" })
		rod(m, Vector3.new(sd * (GRIP.X + 0.1), top + 0.1, GRIP.Z + 0.35), Vector3.new(sd * (GRIP.X + 0.05), GRIP.Y - 0.12, GRIP.Z), 0.12, chrome, { Reflectance = 0.3, Name = "Grip" })
	end
	grips(m, dark, 0.26)
	-- dash: steering wheel ahead of your knees
	local wheelAt = CFrame.new(0, top + 0.22, -1.42) * CFrame.Angles(-0.9, 0, 0)
	Build.cyl(m, 0.1, 0.75, wheelAt, dark)
	Build.cyl(m, 0.12, 0.25, wheelAt, chrome)
	-- bucket seat (top SEAT_TOP) with a padded backrest
	rrect(m, 1.3, 1.8, 0.8, 0.45, CFrame.new(0, 0.6, 1.3), white)
	rrect(m, 1.5, 2.0, 0.22, 0.5, CFrame.new(0, SEAT_TOP - 0.11, 1.3), red)
	rrect(m, 1.5, 1.2, 0.35, 0.45, CFrame.new(0, 1.65, 2.35) * CFrame.Angles(math.pi / 2 - 0.15, 0, 0), red)
	-- outboard motor on the transom
	local mz = z1 + 0.5
	rrect(m, 0.9, 1.0, 1.0, 0.4, CFrame.new(0, 1.0, mz), dark)
	ell(m, Vector3.new(0.92, 0.5, 1.02), CFrame.new(0, 1.5, mz), dark)
	blk(m, Vector3.new(0.94, 0.14, 1.04), CFrame.new(0, 1.0, mz), red)
	blk(m, Vector3.new(0.3, 1.1, 0.4), CFrame.new(0, -0.05, mz + 0.05), dark)
	ell(m, Vector3.new(0.5, 0.35, 0.8), CFrame.new(0, -0.6, mz + 0.05), dark)
	wake(m, z1 + 1.4, 3.6)
end

-- friendly dolphin: curved blue body you sit astride, rounded melon head
-- with a smiling beak, pale belly, flippers, dorsal fin, tail flukes up,
-- red saddle and reins to two handles
builders.Dolphin = function(m)
	local blue, belly, saddle, rein = C(80, 160, 230), C(225, 240, 252), C(235, 60, 70), C(255, 200, 60)
	-- body + tail stock (rising behind you)
	local BODY = Vector3.new(1.1, 1.5, 4.0)
	local body = CFrame.new(0, 0.22, 0.6)
	ell(m, BODY, body, blue)
	ell(m, Vector3.new(1.12, 1.3, 3.9), CFrame.new(0, 0.08, 0.6), belly)
	ell(m, Vector3.new(0.8, 0.9, 2.6), CFrame.new(0, 0.55, 2.9) * CFrame.Angles(-0.35, 0, 0), blue)
	-- flukes
	for _, sd in { -1, 1 } do
		ell(m, Vector3.new(1.3, 0.14, 0.62), CFrame.new(sd * 0.55, 1.05, 4.15) * CFrame.Angles(-0.3, sd * 0.45, 0), blue)
	end
	-- head: melon + beak with a smile line, pale chin
	local HEAD = Vector3.new(1.3, 1.25, 1.85)
	local head = CFrame.new(0, 0.55, -1.95) * CFrame.Angles(0.12, 0, 0)
	ell(m, HEAD, head, blue)
	ell(m, Vector3.new(1.15, 0.9, 1.6), head * CFrame.new(0, -0.2, -0.1), belly)
	ell(m, Vector3.new(0.62, 0.44, 1.1), head * CFrame.new(0, -0.22, -1.1), blue)
	ell(m, Vector3.new(0.56, 0.32, 1.0), head * CFrame.new(0, -0.36, -1.08), belly)
	keep(ell(m, Vector3.new(0.66, 0.05, 1.2), head * CFrame.new(0, -0.28, -0.95) * CFrame.Angles(0.08, 0, 0), INK, { Name = "Smile" }))
	-- big eyes + blowhole
	for _, sd in { -1, 1 } do
		eye(m, surf(head, HEAD, Vector3.new(sd * 0.9, 0.35, -0.75), 0.04), Vector3.new(0.3, 0.38, 0.16))
	end
	keep(ell(m, Vector3.new(0.2, 0.08, 0.12), surf(head, HEAD, Vector3.new(0, 1, 0.25), 0.02), INK))
	-- flippers
	for _, sd in { -1, 1 } do
		ell(m, Vector3.new(0.9, 0.12, 0.5), CFrame.new(sd * 0.75, -0.25, -0.7) * CFrame.Angles(0, sd * 0.5, sd * -0.5), blue)
	end
	-- dorsal fin behind the saddle, swept back
	wdg(m, Vector3.new(0.18, 0.95, 1.1), CFrame.new(0, SEAT_TOP + 0.3, 2.05) * CFrame.Angles(-0.25, 0, 0), darker(blue, 0.12))
	ell(m, Vector3.new(0.3, 0.3, 1.2), CFrame.new(0, SEAT_TOP - 0.1, 2.0), darker(blue, 0.12))
	-- saddle pad on top of the back, harness band round the head, reins
	ell(m, Vector3.new(1.16, 0.5, 1.7), CFrame.new(0, SEAT_TOP - 0.24, 0.85), saddle)
	ell(m, Vector3.new(1.2, 0.2, 1.4), CFrame.new(0, SEAT_TOP - 0.24, 0.85), C(255, 210, 70))
	local hb = head * CFrame.new(0, 0, 0.3)
	ell(m, Vector3.new(1.34, 1.29, 0.14), hb, saddle)
	for _, sd in { -1, 1 } do
		local from = (hb * CFrame.new(sd * 0.64, 0.05, 0)).Position
		rod(m, from, Vector3.new(sd * (GRIP.X - 0.28), GRIP.Y, GRIP.Z), 0.08, rein, { Name = "Grip" })
	end
	grips(m, saddle, 0.3)
end

-- Where each ride wants the rider's stance anchor (Rig.ANCHOR), in ride
-- space (root at the feet, water surface at y -0.15):
--   stand / prone: deck top (y)        sit: knees over the front rim (y, z)
--   straddle: seat top (y) + hips (z)   float: shoulders (y, z)
local function knee(top: number): Vector3
	return Vector3.new(0, top + KNEE_LIFT, KNEE_Z)
end
local SEAT = Vector3.new(0, SEAT_TOP, 0.3)
Rides.FIT = {
	Noodle = Vector3.new(0, 1.7, 0.35),
	Tube = knee(RING_TOP + 0.02),
	Duck = knee(-0.05 + 1.25 / 2), GoldDuck = knee(-0.05 + 1.25 / 2),
	Donut = knee(DONUT_TOP),
	Bathtub = knee(TUB_TOP + 0.19),
	Boogie = Vector3.new(0, 0.3, 0),
	Surf = Vector3.new(0, DECK, 0), Rocket = Vector3.new(0, DECK, 0), SharkBoard = Vector3.new(0, DECK, 0),
	JetSki = SEAT, RainbowSki = SEAT, Banana = SEAT, Speedboat = SEAT, Dolphin = SEAT,
} :: { [string]: Vector3 }

function Rides.build(id: string): Model
	local m = Build.model("Ride_" .. id)
	Build.root(m)
	local fn = builders[id] or builders.Noodle
	fn(m)
	Build.ghost(m)
	return m
end

return Rides
