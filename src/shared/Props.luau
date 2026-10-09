-- Hand-built world props in the same low-poly stud family.

local Build = require(script.Parent.Build)

local Props = {}
local C = Color3.fromRGB

function Props.palm(parent: Instance, base: CFrame, height: number?)
	local m = Build.model("Palm", parent)
	local h = height or 14
	local segs = 6
	local lean = CFrame.Angles(0, math.random() * math.pi * 2, 0)
	local cf = base * lean
	for i = 1, segs do
		local seg = h / segs
		cf = cf * CFrame.Angles(0.06, 0, 0)
		local c = (i % 2 == 0) and C(160, 112, 66) or C(140, 96, 56)
		Build.part(m, Vector3.new(1.3 - i * 0.07, seg + 0.2, 1.3 - i * 0.07), cf * CFrame.new(0, seg / 2, 0), c)
		cf = cf * CFrame.new(0, seg, 0)
	end
	local top = cf
	for i = 1, 7 do
		local a = i / 7 * math.pi * 2
		local leaf = top * CFrame.Angles(0, a, 0) * CFrame.Angles(-0.35, 0, 0) * CFrame.new(0, 0, -3.2)
		Build.wedge(m, Vector3.new(1.8, 0.35, 6.5), leaf, (i % 2 == 0) and C(70, 190, 70) or C(50, 166, 64))
	end
	for i = 1, 3 do
		Build.ball(m, 0.9, top * CFrame.new(math.cos(i * 2) * 0.6, -0.6, math.sin(i * 2) * 0.6), C(110, 76, 40))
	end
	return m
end

-- chunky voxel tree (the classic studded kind): trunk + stacked leaf cubes
function Props.blockTree(parent: Instance, pos: Vector3, scale: number, leaf: Color3?, leaf2: Color3?)
	local m = Build.model("Tree", parent)
	local k = scale
	local g1, g2 = leaf or C(64, 176, 60), leaf2 or C(92, 204, 72)
	Build.part(m, Vector3.new(1.6, 6, 1.6) * k, CFrame.new(pos + Vector3.new(0, 3 * k, 0)), C(122, 84, 52))
	-- studs on top only: there are hundreds of these, keep them cheap
	Build.studs(Build.part(m, Vector3.new(7, 4, 7) * k, CFrame.new(pos + Vector3.new(0, 7.5 * k, 0)), g1))
	Build.studs(Build.part(m, Vector3.new(5, 3, 5) * k, CFrame.new(pos + Vector3.new(0, 11 * k, 0)), g2))
	Build.studs(Build.part(m, Vector3.new(2.6, 1.8, 2.6) * k, CFrame.new(pos + Vector3.new(0, 13.4 * k, 0)), g2))
	return m
end

function Props.rock(parent: Instance, cf: CFrame, size: number, color: Color3?)
	local m = Build.model("Rock", parent)
	local col = color or C(150, 156, 170)
	local rng = Random.new(math.floor(cf.Position.X * 7 + cf.Position.Z * 13))
	for i = 1, 4 do
		local s = size * rng:NextNumber(0.55, 1)
		local p = Build.part(m, Vector3.new(s, s * rng:NextNumber(0.6, 1.1), s),
			cf * CFrame.new(rng:NextNumber(-0.4, 0.4) * size, 0, rng:NextNumber(-0.4, 0.4) * size)
				* CFrame.Angles(rng:NextNumber(-0.5, 0.5), rng:NextNumber(0, 3), rng:NextNumber(-0.5, 0.5)),
			col:Lerp(C(255, 255, 255), (i % 2) * 0.08))
		p.Material = Enum.Material.Slate
	end
	return m
end

local CORAL = { C(255, 110, 150), C(255, 160, 60), C(190, 110, 255), C(255, 220, 80), C(90, 220, 200) }

function Props.coral(parent: Instance, base: CFrame, rng: Random)
	local m = Build.model("Coral", parent)
	local col = CORAL[rng:NextInteger(1, #CORAL)]
	local kind = rng:NextInteger(1, 3)
	if kind == 1 then -- branching
		for i = 1, 5 do
			local h = rng:NextNumber(2, 5)
			Build.cyl(m, h, 0.6, base * CFrame.Angles(rng:NextNumber(-0.5, 0.5), 0, rng:NextNumber(-0.5, 0.5)) * CFrame.new(0, h / 2, 0), col)
			Build.ball(m, 0.9, base * CFrame.new(rng:NextNumber(-1, 1), h, rng:NextNumber(-1, 1)), col)
		end
	elseif kind == 2 then -- brain coral
		Build.ell(m, Vector3.new(4, 2.6, 4), base * CFrame.new(0, 1, 0), col)
	else -- tube sponges
		for i = 1, 4 do
			local h = rng:NextNumber(2.5, 6)
			Build.cyl(m, h, 1.2, base * CFrame.new((i - 2.5) * 1.2, h / 2, rng:NextNumber(-0.6, 0.6)), col)
		end
	end
	return m
end

function Props.kelp(parent: Instance, base: CFrame, height: number, rng: Random)
	local m = Build.model("Kelp", parent)
	local segs = math.max(3, math.floor(height / 3))
	local cf = base
	for i = 1, segs do
		local seg = height / segs
		cf = cf * CFrame.Angles(rng:NextNumber(-0.12, 0.12), 0, rng:NextNumber(-0.12, 0.12))
		Build.part(m, Vector3.new(0.35, seg, 0.35), cf * CFrame.new(0, seg / 2, 0), C(60, 150, 60))
		if i % 2 == 0 then
			Build.wedge(m, Vector3.new(0.2, 1.4, 1.6), cf * CFrame.new(0.5, seg / 2, 0) * CFrame.Angles(0, math.pi / 2, 0.4), C(90, 190, 70))
		end
		cf = cf * CFrame.new(0, seg, 0)
	end
	return m
end

function Props.buoy(parent: Instance, pos: Vector3, color: Color3?)
	local m = Build.model("Buoy", parent)
	local col = color or C(255, 70, 70)
	Build.ball(m, 2.2, CFrame.new(pos + Vector3.new(0, 0.3, 0)), col)
	Build.cyl(m, 0.6, 2.25, CFrame.new(pos + Vector3.new(0, 0.3, 0)), C(255, 255, 255))
	Build.cyl(m, 1.4, 0.3, CFrame.new(pos + Vector3.new(0, 1.9, 0)), C(60, 60, 70))
	return m
end

function Props.jellyfish(parent: Instance, pos: Vector3, rng: Random)
	local m = Build.model("Jelly", parent)
	local col = ({ C(255, 120, 220), C(140, 200, 255), C(190, 140, 255) })[rng:NextInteger(1, 3)]
	Build.ell(m, Vector3.new(3, 2, 3), CFrame.new(pos), col, { Material = Enum.Material.Neon, Transparency = 0.25 })
	for i = 1, 5 do
		local a = i / 5 * math.pi * 2
		Build.part(m, Vector3.new(0.2, 3, 0.2), CFrame.new(pos + Vector3.new(math.cos(a) * 0.8, -2, math.sin(a) * 0.8)), col, { Material = Enum.Material.Neon, Transparency = 0.4 })
	end
	m:SetAttribute("Bob", true)
	return m
end

function Props.beachBall(parent: Instance, pos: Vector3)
	local m = Build.model("BeachBall", parent)
	local ball = Build.ball(m, 2.6, CFrame.new(pos), C(255, 255, 255))
	local bands = { C(255, 70, 70), C(40, 140, 255), C(255, 214, 40) }
	for i, c in bands do
		Build.ell(m, Vector3.new(2.66, 2.66, 0.7), CFrame.new(pos) * CFrame.Angles(0, i * math.pi / 3, 0), c)
	end
	m.PrimaryPart = ball
	m:SetAttribute("Bob", true)
	return m
end

function Props.shipwreck(parent: Instance, cf: CFrame)
	local m = Build.model("Shipwreck", parent)
	local wood, dark = C(140, 92, 52), C(96, 62, 36)
	local tilt = cf * CFrame.Angles(0.15, 0, 0.35)
	Build.part(m, Vector3.new(10, 6, 30), tilt * CFrame.new(0, -1, 0), wood, { Material = Enum.Material.WoodPlanks })
	Build.wedge(m, Vector3.new(10, 6, 8), tilt * CFrame.new(0, -1, -19) * CFrame.Angles(0, math.pi, 0), wood, { Material = Enum.Material.WoodPlanks })
	Build.part(m, Vector3.new(10.4, 0.8, 30), tilt * CFrame.new(0, 2.2, 0), dark)
	local mast = tilt * CFrame.new(0, 2, -4)
	Build.part(m, Vector3.new(1, 22, 1), mast * CFrame.new(0, 11, 0), dark)
	Build.part(m, Vector3.new(9, 0.6, 0.6), mast * CFrame.new(0, 17, 0), dark)
	Build.part(m, Vector3.new(8, 7, 0.2), mast * CFrame.new(0, 13.2, 0.5) * CFrame.Angles(0.15, 0, 0.1), C(240, 232, 210))
	Build.part(m, Vector3.new(2, 1.5, 0.2), mast * CFrame.new(0, 23, 0.2), C(30, 30, 36)) -- pirate flag
	return m
end

function Props.crate(parent: Instance, pos: Vector3, rng: Random)
	local p = Build.part(parent, Vector3.new(2.4, 2.4, 2.4), CFrame.new(pos) * CFrame.Angles(rng:NextNumber(-0.4, 0.4), rng:NextNumber(0, 3), 0), C(170, 118, 66), { Material = Enum.Material.WoodPlanks, Name = "Crate", CanCollide = false })
	p:SetAttribute("Bob", true)
	return p
end

function Props.spikeRock(parent: Instance, cf: CFrame, h: number)
	local m = Build.model("SpikeRock", parent)
	Build.wedge(m, Vector3.new(h * 0.4, h, h * 0.5), cf * CFrame.new(0, h / 2 - 4, 0), C(36, 32, 50))
	Build.wedge(m, Vector3.new(h * 0.4, h * 0.8, h * 0.5), cf * CFrame.new(0, h * 0.4 - 4, 0) * CFrame.Angles(0, math.pi, 0), C(48, 42, 66))
	Build.part(m, Vector3.new(0.8, h * 0.4, 0.8), cf * CFrame.new(h * 0.15, h * 0.3, 0) * CFrame.Angles(0, 0, 0.3), C(170, 80, 255), { Material = Enum.Material.Neon })
	return m
end

-- Frozen Sea: a studded iceberg (stacked blocks, white over pale blue)
function Props.iceberg(parent: Instance, base: CFrame, size: number, rng: Random)
	local m = Build.model("Iceberg", parent)
	local layers = 4
	for i = 0, layers - 1 do
		local k = 1 - i / layers * 0.75
		local w, h = size * k, size * 0.32
		local cf = base * CFrame.new(rng:NextNumber(-1, 1) * size * 0.08, -size * 0.25 + h * (i + 0.5), 0) * CFrame.Angles(0, rng:NextNumber(-0.4, 0.4), 0)
		Build.studs(Build.part(m, Vector3.new(w, h, w * rng:NextNumber(0.7, 1)), cf, i == layers - 1 and C(255, 255, 255) or C(200 + i * 15, 235, 255)), Build.ALL_FACES)
	end
	return m
end

-- Frozen Sea floor: a cluster of glowing ice crystals
function Props.iceCrystal(parent: Instance, base: CFrame, h: number, rng: Random)
	local m = Build.model("IceCrystal", parent)
	for i = 1, 3 do
		local hh = h * rng:NextNumber(0.5, 1)
		Build.part(m, Vector3.new(hh * 0.25, hh, hh * 0.25), base * CFrame.Angles(rng:NextNumber(-0.4, 0.4), i * 2, rng:NextNumber(-0.4, 0.4)) * CFrame.new(0, hh / 2, 0),
			C(170, 230, 255), { Material = Enum.Material.Glass, Transparency = 0.25 })
	end
	return m
end

-- Volcano Vents: a dark rock cone with a glowing lava mouth
function Props.vent(parent: Instance, base: CFrame, h: number)
	local m = Build.model("Vent", parent)
	local rock, rock2, lava = C(50, 38, 38), C(70, 52, 48), C(255, 110, 30)
	for i = 0, 2 do
		local w = h * (0.9 - i * 0.25)
		Build.studs(Build.part(m, Vector3.new(w, h / 3, w), base * CFrame.new(0, h / 6 + i * h / 3, 0) * CFrame.Angles(0, i * 0.5, 0), i % 2 == 0 and rock or rock2), Build.ALL_FACES)
	end
	Build.part(m, Vector3.new(h * 0.3, 0.6, h * 0.3), base * CFrame.new(0, h + 0.2, 0), lava, { Material = Enum.Material.Neon })
	return m
end

-- Lost City: a marble column with a gold cap (sometimes broken off)
function Props.column(parent: Instance, base: CFrame, h: number, broken: boolean)
	local m = Build.model("Column", parent)
	local marble, gold = C(240, 235, 220), C(255, 205, 60)
	Build.studs(Build.part(m, Vector3.new(h * 0.3, h * 0.06, h * 0.3), base * CFrame.new(0, h * 0.03, 0), marble), Build.ALL_FACES)
	local shaft = broken and h * 0.55 or h * 0.88
	Build.cyl(m, shaft, h * 0.2, base * CFrame.new(0, h * 0.06 + shaft / 2, 0), marble)
	if not broken then
		Build.studs(Build.part(m, Vector3.new(h * 0.3, h * 0.06, h * 0.3), base * CFrame.new(0, h * 0.97, 0), gold), Build.ALL_FACES)
	end
	return m
end

----------------------------------------------------------------- Candy Bay
local CANDY = { C(255, 90, 160), C(120, 220, 255), C(255, 210, 60), C(130, 230, 120), C(190, 120, 255), C(255, 140, 60) }

-- a sugar-coated gumdrop (a squat dome on the floor)
function Props.gumdrop(parent: Instance, base: CFrame, size: number, rng: Random)
	local m = Build.model("Gumdrop", parent)
	local c = CANDY[rng:NextInteger(1, #CANDY)]
	Build.ell(m, Vector3.new(size, size * 0.9, size), base * CFrame.new(0, size * 0.25, 0), c, { Material = Enum.Material.Glass, Transparency = 0.15 })
	Build.ell(m, Vector3.new(size * 0.7, size * 0.5, size * 0.7), base * CFrame.new(0, size * 0.42, 0), c:Lerp(C(255, 255, 255), 0.4))
	return m
end

-- a swirl lollipop: stick + disc of stripes
function Props.lollipop(parent: Instance, base: CFrame, h: number, rng: Random)
	local m = Build.model("Lollipop", parent)
	Build.cyl(m, h, h * 0.06, base * CFrame.new(0, h / 2, 0), C(255, 255, 255))
	local a, b = CANDY[rng:NextInteger(1, #CANDY)], C(255, 255, 255)
	local face = base * CFrame.new(0, h + h * 0.18, 0) * CFrame.Angles(0, rng:NextNumber(0, 6), 0)
	for i, k in { 1, 0.78, 0.56, 0.34 } do
		local p = Build.part(m, Vector3.new(h * 0.08 + i * 0.01, h * 0.42 * k, h * 0.42 * k), face * CFrame.Angles(0, math.pi / 2, 0), i % 2 == 1 and a or b)
		p.Shape = Enum.PartType.Cylinder
	end
	return m
end

-- a candy cane: red and white rings up a pole, hooked at the top
function Props.candyCane(parent: Instance, base: CFrame, h: number)
	local m = Build.model("CandyCane", parent)
	local seg = h / 10
	for i = 0, 9 do
		Build.cyl(m, seg, h * 0.08, base * CFrame.new(0, seg * (i + 0.5), 0), i % 2 == 0 and C(235, 40, 60) or C(255, 255, 255))
	end
	-- the hook: a few blocks around a half circle
	local r = h * 0.12
	for i = 1, 6 do
		local a = i / 6 * math.pi
		Build.ball(m, h * 0.085, base * CFrame.new(r - math.cos(a) * r, h + math.sin(a) * r, 0), i % 2 == 0 and C(235, 40, 60) or C(255, 255, 255))
	end
	return m
end

-- a chocolate bar: a slab of studded squares, half sunk
function Props.chocoBar(parent: Instance, base: CFrame, size: number)
	local m = Build.model("ChocoBar", parent)
	for x = 0, 2 do
		for z = 0, 1 do
			Build.studs(Build.part(m, Vector3.new(size * 0.31, size * 0.18, size * 0.31),
				base * CFrame.new((x - 1) * size * 0.33, size * 0.09, (z - 0.5) * size * 0.33), C(100, 58, 34)), Build.ALL_FACES)
		end
	end
	return m
end

-- giant fossil jaw arch at the end of the Abyss
function Props.jawArch(parent: Instance, cf: CFrame, width: number)
	local m = Build.model("MegalodonJaw", parent)
	local bone = C(236, 228, 206)
	local n = 16
	for i = 0, n do
		local a = i / n * math.pi
		local x = math.cos(a) * width / 2
		local y = math.sin(a) * width * 0.45
		Build.part(m, Vector3.new(5, 5, 5), cf * CFrame.new(x, y, 0) * CFrame.Angles(0, 0, a), bone)
		if i > 0 and i < n then
			Build.wedge(m, Vector3.new(1.5, 6, 3), cf * CFrame.new(x * 0.9, y * 0.9 - 3, 0) * CFrame.Angles(0, 0, a + math.pi / 2), C(255, 255, 255))
		end
	end
	return m
end

-- a blocky sandbar island (two studded squares = a low-poly octagon):
-- the only place sharks can't reach you
function Props.island(parent: Instance, pos: Vector3, radius: number, palm: boolean)
	local m = Build.model("Island", parent)
	local sand, wet = C(255, 228, 150), C(236, 200, 120)
	local side = radius * 2
	-- the 45-degree block sits a hair lower so the two tops never z-fight
	for i, a in { 0, math.pi / 4 } do
		local drop = (i - 1) * 0.06
		Build.studs(Build.part(m, Vector3.new(side, 3, side), CFrame.new(pos + Vector3.new(0, -1 - drop, 0)) * CFrame.Angles(0, a, 0), sand))
		Build.part(m, Vector3.new(side + 3, 2, side + 3), CFrame.new(pos + Vector3.new(0, -2.2 - drop, 0)) * CFrame.Angles(0, a, 0), wet, { CanCollide = false })
	end
	if palm then
		for i, a in { 0, math.pi / 4 } do
			Build.studs(Build.part(m, Vector3.new(side * 0.45, 0.6, side * 0.45), CFrame.new(pos + Vector3.new(radius * 0.25, 0.8 - (i - 1) * 0.06, 0)) * CFrame.Angles(0, a, 0), C(110, 214, 64)))
		end
	end
	-- glow ring lit up during attacks (client tweens it)
	local ring = Build.cyl(m, 0.3, side + 1.2, CFrame.new(pos + Vector3.new(0, 0.42, 0)), C(80, 255, 140), {
		Name = "SafeRing", Material = Enum.Material.Neon, Transparency = 1, CanCollide = false, CanQuery = false,
	})
	ring:SetAttribute("SafeRing", true)
	if palm then
		Props.palm(m, CFrame.new(pos + Vector3.new(radius * 0.25, 1.1, 0)), 12 + radius * 0.3)
	else
		Props.rock(m, CFrame.new(pos + Vector3.new(-radius * 0.3, 1.2, radius * 0.2)), 3.2)
	end
	return m
end

return Props
