-- Hand-built rides in the toy-brick low-poly style (blocks + wedges only,
-- studs on top faces). Root sits where the player's feet go (y = 0, water
-- level), everything faces -Z. Each ride is built around its rider pose
-- (Rig.POSES), and Rides.FIT says where that pose's anchor goes, so the
-- body sits on / in the ride instead of through it (tools/preview/fit.py
-- checks every ride against a stand-in R15 body):
--   sit      (tube, duck, donut, bathtub): hips sunk in the hole, knees over
--            the front rim, arms out over the sides
--   straddle (jet ski, banana, dolphin, boat): thighs on the seat, shins down
--            a footwell, hands on the grips
--   stand    (boards): soles on the deck      prone (boogie): lying on it
--   float    (noodle): forearms on one noodle across the front

local CollectionService = game:GetService("CollectionService")

local Build = require(script.Parent.Build)

local Rides = {}

local C = Color3.fromRGB
local WHITE = C(255, 255, 255)
local INK = C(27, 29, 63)

local builders: { [string]: (Model) -> () } = {}

local function darker(c: Color3, k: number?): Color3
	return c:Lerp(Color3.new(0, 0, 0), k or 0.2)
end

-- block with optional studs on top / all faces
local function blk(m: Model, size: Vector3, cf: CFrame, color: Color3, studs: any?, props: { [string]: any }?): Part
	local p = Build.part(m, size, cf, color, props)
	if studs == "all" then
		Build.studs(p, Build.ALL_FACES)
	elseif studs then
		Build.studs(p, { Enum.NormalId.Top })
	end
	return p
end

-- wedge whose slope faces -Z (a nose) unless rotated
local function wdg(m: Model, size: Vector3, cf: CFrame, color: Color3): WedgePart
	return Build.wedge(m, size, cf, color)
end

-- thin bar from a to b (reins, handles)
local function beam(m: Model, a: Vector3, b: Vector3, thick: number, color: Color3): Part
	local d = b - a
	local yaw = math.atan2(-d.X, -d.Z)
	local pitch = math.atan2(d.Y, math.sqrt(d.X * d.X + d.Z * d.Z))
	return blk(m, Vector3.new(thick, thick, d.Magnitude), CFrame.new((a + b) / 2) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(pitch, 0, 0), color)
end

-- An octagon ring (pool float / tube / donut): flat sides face front, back
-- and the sides, `rx`/`rz` are the distances to those flats (so the hole
-- can be wider than it is long). Straight segments end inside slightly
-- bigger "band" blocks at the corners, so no two faces overlap.
local TAN8 = math.tan(math.pi / 8)
local function ring(m: Model, rx: number, rz: number, thick: number, tall: number, center: Vector3, color: Color3, band: Color3?, studs: boolean?)
	local corners = {}
	for i = 0, 7 do
		local a = (i + 0.5) / 8 * math.pi * 2
		local cx, cz = math.cos(a), math.sin(a)
		-- corners of a regular octagon with apothem 1, stretched to rx/rz
		local x, z
		if math.abs(cx) > math.abs(cz) then
			x, z = math.sign(cx), math.sign(cz) * TAN8
		else
			x, z = math.sign(cx) * TAN8, math.sign(cz)
		end
		corners[i + 1] = Vector3.new(x * rx, 0, z * rz)
	end
	for i = 1, 8 do
		local a, b = corners[i], corners[i % 8 + 1]
		local d = b - a
		local yaw = math.atan2(-d.X, -d.Z)
		blk(m, Vector3.new(thick, tall, d.Magnitude), CFrame.new(center + (a + b) / 2) * CFrame.Angles(0, yaw, 0), color, studs)
		local prev = corners[(i - 2) % 8 + 1]
		local bis = (a - prev).Unit + d.Unit
		local jy = math.atan2(-bis.X, -bis.Z)
		blk(m, Vector3.new(thick * 1.14, tall * 1.08, thick * 1.14), CFrame.new(center + a) * CFrame.Angles(0, jy, 0), band or darker(color, 0.12), studs)
	end
end

-- two eyes on a face (looking -Z)
local function eyes(m: Model, at: CFrame, spread: number, size: number)
	for _, side in { -1, 1 } do
		local e = blk(m, Vector3.new(size, size, 0.1), at * CFrame.new(side * spread, 0, 0), WHITE)
		e:SetAttribute("KeepColor", true)
		local p = blk(m, Vector3.new(size * 0.55, size * 0.55, 0.12), at * CFrame.new(side * spread + side * size * 0.1, -size * 0.05, -0.02), INK)
		p:SetAttribute("KeepColor", true)
	end
end

-- a pointed board (surf / rocket / shark): stepped taper to the nose
local function board(m: Model, len: number, wid: number, color: Color3, stripe: Color3?)
	local y = -0.15 -- 0.4 thick, deck top at 0.05
	local body = len * 0.6
	local z0 = 0.15 * len
	blk(m, Vector3.new(wid, 0.4, body), CFrame.new(0, y, z0), color, true)
	blk(m, Vector3.new(wid * 0.75, 0.4, len * 0.17), CFrame.new(0, y, z0 - body / 2 - len * 0.085), color, true)
	blk(m, Vector3.new(wid * 0.45, 0.4, len * 0.12), CFrame.new(0, y, z0 - body / 2 - len * 0.23), color, true)
	wdg(m, Vector3.new(wid * 0.45, 0.4, len * 0.1), CFrame.new(0, y, z0 - body / 2 - len * 0.34), color)
	-- tail: two steps in
	blk(m, Vector3.new(wid * 0.8, 0.4, len * 0.06), CFrame.new(0, y, z0 + body / 2 + len * 0.03), color, true)
	if stripe then
		blk(m, Vector3.new(0.35, 0.44, body + len * 0.29), CFrame.new(0, y, z0 - len * 0.145), stripe)
	end
	-- fin under the tail
	wdg(m, Vector3.new(0.18, 0.8, 0.9), CFrame.new(0, y - 0.6, z0 + body / 2 - 0.5) * CFrame.Angles(math.pi, 0, 0), darker(color, 0.15))
end

-- T-bar with grips where the straddle pose's hands are
local GRIP = Vector3.new(1.78, 2.5, -1.6)
local function handlebar(m: Model, from: Vector3, color: Color3)
	beam(m, from, Vector3.new(0, GRIP.Y - 0.05, GRIP.Z), 0.3, color)
	blk(m, Vector3.new(GRIP.X * 2 - 0.4, 0.22, 0.22), CFrame.new(0, GRIP.Y, GRIP.Z), color, nil, { Name = "Grip" })
	for _, x in { -GRIP.X, GRIP.X } do
		blk(m, Vector3.new(0.5, 0.34, 0.34), CFrame.new(x, GRIP.Y, GRIP.Z), INK, nil, { Name = "Grip" })
	end
end

----------------------------------------------------------------- float
-- one long noodle across, at the waterline, under the forearms
builders.Noodle = function(m)
	local y, z = 0.0, -0.95
	for i, x in { -2.55, -0.85, 0.85, 2.55 } do
		local c = (i % 2 == 0) and C(255, 72, 150) or C(255, 140, 40)
		blk(m, Vector3.new(1.7, 0.8, 0.8), CFrame.new(x, y, z), c, true)
		blk(m, Vector3.new(1.66, 0.56, 0.56), CFrame.new(x, y, z) * CFrame.Angles(math.pi / 4, 0, 0), c)
	end
	for _, x in { -3.45, 3.45 } do
		blk(m, Vector3.new(0.1, 0.6, 0.6), CFrame.new(x, y, z), C(255, 220, 120))
	end
end

----------------------------------------------------------------- sit (rings + tub)
-- The rider's knees go over the front flat (KNEE), hips sink into the hole,
-- arms rest out over the side flats. Ring floats half under (surface -0.15).
local RING_Y, RING_T = -0.05, 1.1
local RING_RX, RING_RZ = 1.68, 1.25
local KNEE_Z = -0.9
local RING_C = Vector3.new(0, RING_Y, KNEE_Z + RING_RZ)
local KNEE_LIFT = 0.95 -- knee joint above the rim top (thighs clear the front corners)

local function float(m: Model, color: Color3, band: Color3, studs: boolean?)
	ring(m, RING_RX, RING_RZ, RING_T, RING_T, RING_C, color, band, studs)
end

builders.Tube = function(m)
	float(m, C(240, 70, 40), WHITE, true)
end

builders.Duck = function(m)
	local yellow, orange = C(255, 214, 40), C(255, 140, 30)
	float(m, yellow, darker(yellow, 0.08), true)
	-- neck rises from the front rim between the shins, head above the feet
	local top = RING_Y + RING_T / 2
	blk(m, Vector3.new(0.34, 2.1, 0.5), CFrame.new(0, top + 1.0, KNEE_Z - 0.45), yellow)
	blk(m, Vector3.new(1.3, 1.15, 1.3), CFrame.new(0, 2.85, KNEE_Z - 0.75), yellow, "all")
	blk(m, Vector3.new(0.9, 0.28, 0.7), CFrame.new(0, 2.65, KNEE_Z - 1.7), orange)
	wdg(m, Vector3.new(0.9, 0.24, 0.7), CFrame.new(0, 2.91, KNEE_Z - 1.7), orange)
	eyes(m, CFrame.new(0, 3.05, KNEE_Z - 1.42), 0.36, 0.32)
	-- tail behind the back rim
	wdg(m, Vector3.new(1.0, 0.9, 0.8), CFrame.new(0, RING_Y + 0.75, RING_C.Z + RING_RZ + 0.7) * CFrame.Angles(0, math.pi, 0), yellow)
end

local ICING_T = 0.28
builders.Donut = function(m)
	local dough, icing = C(214, 150, 80), C(255, 120, 190)
	float(m, dough, darker(dough, 0.1))
	-- icing: a slightly wider, thin ring on top with neon sprinkles
	local top = RING_Y + RING_T / 2
	ring(m, RING_RX, RING_RZ, RING_T + 0.1, ICING_T, Vector3.new(RING_C.X, top + ICING_T / 2 + 0.03, RING_C.Z), icing, darker(icing, 0.06))
	local cols = { WHITE, C(255, 220, 40), C(60, 200, 255), C(120, 230, 120) }
	local rng = Random.new(3)
	for i = 1, 22 do
		local a = i / 22 * math.pi * 2 + rng:NextNumber(-0.08, 0.08)
		local r = rng:NextNumber(-0.3, 0.3)
		local p = Vector3.new(math.cos(a) * (RING_RX + r), top + ICING_T + 0.1, RING_C.Z + math.sin(a) * (RING_RZ + r))
		blk(m, Vector3.new(0.4, 0.1, 0.13), CFrame.new(p) * CFrame.Angles(0, rng:NextNumber(0, 3), 0), cols[i % 4 + 1], nil, { Material = Enum.Material.Neon })
	end
end

-- bathtub: knees over the front wall, feet up out of the tub
local TUB_TOP = 0.95
builders.Bathtub = function(m)
	local tub, trim, gold = C(250, 250, 255), C(225, 232, 245), C(255, 200, 60)
	local zf, zb = KNEE_Z, 1.75 -- front / back wall centres
	local len = zb - zf
	blk(m, Vector3.new(3.3, 0.5, len), CFrame.new(0, -0.15, (zf + zb) / 2), tub)
	for _, x in { -1.45, 1.45 } do
		blk(m, Vector3.new(0.5, TUB_TOP + 0.4, len + 0.5), CFrame.new(x, (TUB_TOP - 0.4) / 2, (zf + zb) / 2), tub, true)
	end
	blk(m, Vector3.new(2.4, TUB_TOP + 0.4, 0.5), CFrame.new(0, (TUB_TOP - 0.4) / 2, zf), tub, true)
	blk(m, Vector3.new(2.4, TUB_TOP + 1.0, 0.5), CFrame.new(0, (TUB_TOP + 0.2) / 2, zb), tub, true)
	-- rolled rim
	for _, x in { -1.45, 1.45 } do
		blk(m, Vector3.new(0.62, 0.16, len + 0.62), CFrame.new(x, TUB_TOP + 0.08, (zf + zb) / 2), trim)
	end
	blk(m, Vector3.new(2.28, 0.16, 0.62), CFrame.new(0, TUB_TOP + 0.08, zf), trim)
	blk(m, Vector3.new(2.28, 0.16, 0.62), CFrame.new(0, TUB_TOP + 0.68, zb), trim)
	-- water + foam in the corners
	blk(m, Vector3.new(2.38, 0.1, len - 0.52), CFrame.new(0, TUB_TOP - 0.25, (zf + zb) / 2), C(140, 220, 255), nil, { Transparency = 0.4 })
	for _, x in { -0.95, -0.55, 0.55, 0.95 } do
		blk(m, Vector3.new(0.4, 0.3, 0.4), CFrame.new(x, TUB_TOP - 0.1, zb - 0.45), WHITE)
	end
	-- gold claw feet
	for _, x in { -1.3, 1.3 } do
		for _, z in { zf + 0.1, zb - 0.1 } do
			blk(m, Vector3.new(0.4, 0.4, 0.4), CFrame.new(x, -0.55, z), gold)
		end
	end
end

----------------------------------------------------------------- prone
builders.Boogie = function(m)
	local red = C(230, 40, 60)
	blk(m, Vector3.new(2.6, 0.4, 3.4), CFrame.new(0, 0.1, -0.1), red, true)
	blk(m, Vector3.new(2.0, 0.4, 0.6), CFrame.new(0, 0.1, -2.1), red, true)
	blk(m, Vector3.new(2.2, 0.4, 0.5), CFrame.new(0, 0.1, 1.85), red, true)
	blk(m, Vector3.new(0.4, 0.44, 4.5), CFrame.new(0, 0.1, -0.15), WHITE)
	-- leash cord at the tail
	blk(m, Vector3.new(0.12, 0.12, 0.8), CFrame.new(0.6, 0.0, 2.45), C(40, 40, 50))
end

----------------------------------------------------------------- stand
builders.Surf = function(m)
	board(m, 8, 2.4, C(40, 200, 220), C(255, 200, 40))
end

builders.Rocket = function(m)
	board(m, 8.4, 2.6, C(40, 40, 60), C(255, 60, 60))
	for _, x in { -0.75, 0.75 } do
		blk(m, Vector3.new(0.9, 0.9, 1.6), CFrame.new(x, 0.15, 4.15), C(200, 200, 210), nil, { Material = Enum.Material.Metal })
		local flame = blk(m, Vector3.new(0.6, 0.6, 0.6), CFrame.new(x, 0.15, 5.25), C(255, 140, 30), nil, { Material = Enum.Material.Neon })
		local fire = Instance.new("Fire")
		fire.Size = 3
		fire.Heat = 0
		fire.Color = C(255, 160, 40)
		fire.SecondaryColor = C(255, 60, 30)
		fire.Parent = flame
	end
	for _, side in { -1, 1 } do
		wdg(m, Vector3.new(0.15, 0.9, 1.2), CFrame.new(side * 1.2, 0.5, 3.0) * CFrame.Angles(0, math.pi, 0), C(255, 60, 60))
	end
end

builders.SharkBoard = function(m)
	local grey = C(106, 129, 153)
	board(m, 8, 2.6, grey, C(246, 247, 249))
	wdg(m, Vector3.new(0.3, 1.6, 1.8), CFrame.new(0, 0.85, 2.4) * CFrame.Angles(0, math.pi, 0), darker(grey, 0.1))
	for i = 0, 4 do
		wdg(m, Vector3.new(0.25, 0.35, 0.25), CFrame.new(-0.5 + i * 0.25, -0.2, -3.75) * CFrame.Angles(0, 0, math.pi), WHITE)
	end
	eyes(m, CFrame.new(0, -0.05, -3.25) * CFrame.Angles(-math.pi / 2, 0, 0), 0.45, 0.28)
end

----------------------------------------------------------------- straddle
-- Shared layout (Rig straddle pose): thighs on a seat whose top is y 1.0
-- (z 0.15 .. 1.95), shins down a footwell (z -1.4 .. 0.15, floor 0.2) on
-- each side, hands on grips at GRIP. Anything in front starts at z -1.4.
local SEAT_TOP = 1.0

builders.JetSki = function(m)
	local body, dark = C(230, 30, 50), C(30, 30, 40)
	blk(m, Vector3.new(2.8, 0.7, 5.2), CFrame.new(0, -0.15, 0.4), body, true)
	wdg(m, Vector3.new(2.8, 0.7, 1.6), CFrame.new(0, -0.15, -3.0), body)
	blk(m, Vector3.new(2.9, 0.18, 5.24), CFrame.new(0, -0.4, 0.4), WHITE)
	-- seat
	blk(m, Vector3.new(1.3, 0.6, 1.8), CFrame.new(0, 0.5, 1.05), body)
	blk(m, Vector3.new(1.4, 0.2, 1.8), CFrame.new(0, SEAT_TOP - 0.1, 1.05), dark)
	wdg(m, Vector3.new(1.3, 0.5, 0.8), CFrame.new(0, 0.45, 2.35) * CFrame.Angles(0, math.pi, 0), body)
	-- console + windshield in front of the footwell
	blk(m, Vector3.new(2.0, 1.1, 1.2), CFrame.new(0, 0.75, -2.0), body, true)
	wdg(m, Vector3.new(2.0, 0.7, 0.9), CFrame.new(0, 0.55, -3.05), body)
	blk(m, Vector3.new(1.5, 0.55, 0.12), CFrame.new(0, 1.55, -2.3) * CFrame.Angles(-0.45, 0, 0), C(160, 230, 255), nil, { Transparency = 0.3 })
	handlebar(m, Vector3.new(0, 1.3, -1.9), dark)
end

builders.RainbowSki = function(m)
	builders.JetSki(m)
	m:SetAttribute("Rainbow", true)
	CollectionService:AddTag(m, "Rainbow")
end

builders.Banana = function(m)
	local y, tip, dark = C(255, 220, 30), C(110, 70, 30), C(60, 60, 70)
	-- a chunky banana you sit astride (top 1.0), curling up at both ends
	blk(m, Vector3.new(1.0, 0.95, 2.1), CFrame.new(0, SEAT_TOP - 0.475, 1.3), y, true)
	blk(m, Vector3.new(0.42, 0.95, 1.7), CFrame.new(0, SEAT_TOP - 0.475, -0.55), y, true) -- between the shins
	blk(m, Vector3.new(0.9, 0.85, 1.3), CFrame.new(0, 0.75, -1.95) * CFrame.Angles(0.35, 0, 0), y, true)
	blk(m, Vector3.new(0.7, 0.7, 0.6), CFrame.new(0, 1.25, -2.75) * CFrame.Angles(0.65, 0, 0), tip)
	blk(m, Vector3.new(0.9, 0.85, 1.2), CFrame.new(0, 0.75, 2.85) * CFrame.Angles(-0.35, 0, 0), y, true)
	blk(m, Vector3.new(0.65, 0.65, 0.5), CFrame.new(0, 1.2, 3.55) * CFrame.Angles(-0.65, 0, 0), tip)
	-- side floats + footrests
	for _, side in { -1, 1 } do
		blk(m, Vector3.new(0.7, 0.5, 3.4), CFrame.new(side * 1.2, -0.1, 0.0), C(40, 140, 255), true)
		blk(m, Vector3.new(0.5, 0.12, 2.0), CFrame.new(side * 0.75, 0.1, -0.5), dark)
	end
	handlebar(m, Vector3.new(0, 0.9, -1.75), dark)
end

builders.Speedboat = function(m)
	local hull, trim, dark = C(250, 250, 255), C(30, 90, 220), C(40, 40, 50)
	blk(m, Vector3.new(4.0, 0.5, 6.4), CFrame.new(0, -0.45, 0.9), trim)
	blk(m, Vector3.new(4.0, 0.4, 6.4), CFrame.new(0, 0.0, 0.9), hull, true)
	wdg(m, Vector3.new(4.0, 0.9, 2.2), CFrame.new(0, -0.25, -3.4), hull)
	-- gunwales leave a cockpit; arms pass over them
	for _, x in { -1.82, 1.82 } do
		blk(m, Vector3.new(0.36, 1.0, 6.0), CFrame.new(x, 0.7, 0.9), hull)
		blk(m, Vector3.new(0.4, 0.12, 6.04), CFrame.new(x, 1.26, 0.9), trim)
	end
	-- seat + backrest
	blk(m, Vector3.new(1.6, 0.8, 1.8), CFrame.new(0, 0.6, 1.05), dark)
	blk(m, Vector3.new(1.6, 1.2, 0.35), CFrame.new(0, 1.4, 2.12), dark)
	-- dash + windshield
	blk(m, Vector3.new(3.28, 1.0, 0.9), CFrame.new(0, 0.7, -2.0), hull, true)
	blk(m, Vector3.new(3.2, 0.9, 0.12), CFrame.new(0, 1.6, -2.4) * CFrame.Angles(-0.5, 0, 0), C(160, 230, 255), nil, { Transparency = 0.35 })
	handlebar(m, Vector3.new(0, 1.2, -1.8), dark)
	-- outboard motor
	blk(m, Vector3.new(1.1, 1.5, 1.0), CFrame.new(0, 0.5, 4.6), dark, true)
	blk(m, Vector3.new(0.4, 1.0, 0.4), CFrame.new(0, -0.6, 4.6), dark)
end

builders.Dolphin = function(m)
	local grey, belly, strap = C(120, 160, 210), C(235, 244, 255), C(90, 50, 30)
	-- narrow back you sit astride (top 1.0), legs down both flanks
	blk(m, Vector3.new(1.0, 1.4, 2.4), CFrame.new(0, SEAT_TOP - 0.7, 1.45), grey, true)
	blk(m, Vector3.new(0.42, 1.4, 1.62), CFrame.new(0, SEAT_TOP - 0.7, -0.53), grey, true) -- between the shins
	blk(m, Vector3.new(0.9, 0.3, 2.2), CFrame.new(0, -0.55, 1.45), belly)
	-- head in front of the shins, beak, eyes on the sides
	blk(m, Vector3.new(1.0, 1.1, 1.3), CFrame.new(0, 0.25, -1.95), grey, true)
	blk(m, Vector3.new(0.55, 0.42, 0.9), CFrame.new(0, 0.0, -3.05), grey)
	for _, side in { -1, 1 } do
		local e = blk(m, Vector3.new(0.1, 0.3, 0.3), CFrame.new(side * 0.52, 0.45, -2.3), INK)
		e:SetAttribute("KeepColor", true)
		blk(m, Vector3.new(0.9, 0.14, 0.5), CFrame.new(side * 0.85, -0.45, -1.7) * CFrame.Angles(0, 0, side * -0.3), grey)
	end
	-- dorsal fin behind the rider, tail + flukes
	wdg(m, Vector3.new(0.22, 1.0, 1.1), CFrame.new(0, SEAT_TOP + 0.5, 2.3) * CFrame.Angles(0, math.pi, 0), darker(grey, 0.1))
	blk(m, Vector3.new(0.7, 0.7, 1.1), CFrame.new(0, 0.3, 3.2), grey)
	blk(m, Vector3.new(2.4, 0.2, 0.7), CFrame.new(0, 0.35, 3.95), darker(grey, 0.08))
	-- saddle strap + reins to the hands
	blk(m, Vector3.new(1.04, 0.12, 0.5), CFrame.new(0, SEAT_TOP + 0.02, 1.9), strap)
	for _, side in { -1, 1 } do
		beam(m, Vector3.new(side * 0.4, 0.75, -2.3), Vector3.new(side * GRIP.X, GRIP.Y, GRIP.Z), 0.1, strap).Name = "Grip"
		blk(m, Vector3.new(0.45, 0.3, 0.3), CFrame.new(side * GRIP.X, GRIP.Y, GRIP.Z), strap, nil, { Name = "Grip" })
	end
end

builders.GoldDuck = function(m)
	builders.Duck(m)
	Build.recolor(m, C(255, 200, 50), Enum.Material.Foil)
	local sp = Instance.new("Sparkles")
	sp.SparkleColor = C(255, 230, 120)
	sp.Parent = m:FindFirstChildWhichIsA("BasePart")
end

-- Where each ride wants the rider's stance anchor (Rig.ANCHOR), in ride
-- space (root at the feet, water surface at y -0.15):
--   stand / prone: deck top (y)        sit: knees over the front rim (y, z)
--   straddle: seat top (y) + hips (z)   float: shoulders (y, z)
local RIM_KNEE = Vector3.new(0, RING_Y + RING_T / 2 + KNEE_LIFT, KNEE_Z)
local SEAT = Vector3.new(0, SEAT_TOP, 0.3)
Rides.FIT = {
	Noodle = Vector3.new(0, 1.7, 0.35),
	Duck = RIM_KNEE, GoldDuck = RIM_KNEE, Tube = RIM_KNEE,
	Donut = RIM_KNEE + Vector3.new(0, ICING_T + 0.05, 0),
	Bathtub = Vector3.new(0, TUB_TOP + 0.16 + KNEE_LIFT, KNEE_Z),
	Boogie = Vector3.new(0, 0.3, 0),
	Surf = Vector3.new(0, 0.05, 0), Rocket = Vector3.new(0, 0.05, 0), SharkBoard = Vector3.new(0, 0.05, 0),
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
