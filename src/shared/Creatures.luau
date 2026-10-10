-- Blocky, studded sea creatures (the same toy-brick look as the map).
-- 30 species (Config.Species) built from 10 body plans. Each model is about
-- 2.4 studs long at scale 1, faces -Z, pivots at its center, and marks its
-- moving bits (tail, fins, tentacles, legs...) with attributes the client
-- animates (Animals.luau): Anim = kind, Rest = CFrame from the root,
-- Hinge = pivot point, Side = -1/1, Phase = offset.

local CollectionService = game:GetService("CollectionService")

local Config = require(script.Parent.Config)
local Build = require(script.Parent.Build)

local Creatures = {}

local WHITE = Color3.fromRGB(255, 255, 255)
local INK = Color3.fromRGB(20, 20, 30)

type Ctx = { m: Model, s: number, sp: any, body: { BasePart } } -- body: the studded blocks (biome decor sits on them)

local function darker(c: Color3, k: number?): Color3
	return c:Lerp(Color3.new(0, 0, 0), k or 0.25)
end

-- one block. opts: studs (true = all faces), anim, hinge, side, phase, neon,
-- t (transparency), keep (KeepColor), rot (CFrame)
local function blk(x: Ctx, size: Vector3, pos: Vector3, color: Color3, opts: { [string]: any }?): Part
	local o = opts or {}
	local s = x.s
	local cf = CFrame.new(pos * s) * (o.rot or CFrame.identity)
	local p = Build.part(x.m, size * s, cf, color)
	if o.neon then
		p.Material = Enum.Material.Neon
	elseif o.studs then
		Build.studs(p, o.studs == "top" and { Enum.NormalId.Top } or Build.ALL_FACES)
		table.insert(x.body, p)
	end
	if o.mat then
		p.Material = o.mat
	end
	if o.t then
		p.Transparency = o.t
	end
	if o.keep then
		p:SetAttribute("KeepColor", true)
	end
	if o.anim then
		p:SetAttribute("Anim", o.anim)
		p:SetAttribute("Rest", cf)
		p:SetAttribute("Hinge", (o.hinge or pos) * s)
		p:SetAttribute("Side", o.side or 1)
		p:SetAttribute("Phase", o.phase or 0)
	end
	return p
end

-- two side eyes (fish-style) at height y, depth z, spread x
local function eyes(x: Ctx, y: number, z: number, spread: number, size: number?)
	local d = size or 0.3
	for _, side in { -1, 1 } do
		blk(x, Vector3.new(0.12, d, d), Vector3.new(side * spread, y, z), WHITE, { keep = true })
		blk(x, Vector3.new(0.13, d * 0.55, d * 0.55), Vector3.new(side * (spread + 0.01), y - d * 0.05, z - d * 0.12), INK, { keep = true })
	end
end

-- two front-facing eyes on a face at depth z (octopus, puffer, jelly)
local function frontEyes(x: Ctx, y: number, z: number, spread: number, size: number?)
	local d = size or 0.3
	for _, side in { -1, 1 } do
		blk(x, Vector3.new(d, d, 0.1), Vector3.new(side * spread, y, z), WHITE, { keep = true })
		blk(x, Vector3.new(d * 0.55, d * 0.55, 0.11), Vector3.new(side * spread + side * d * 0.12, y - d * 0.06, z - 0.01), INK, { keep = true })
	end
end

local builders: { [string]: (Ctx) -> () } = {}

----------------------------------------------------------------- fish
builders.fish = function(x)
	local sp = x.sp
	local c1, c2, c3 = sp.c1, sp.c2, sp.c3 or sp.c1
	blk(x, Vector3.new(1.0, 1.2, 1.6), Vector3.new(0, 0, 0), c1, { studs = true })
	blk(x, Vector3.new(0.7, 0.25, 1.1), Vector3.new(0, 0.72, 0.05), c1, { studs = "top" })
	blk(x, Vector3.new(0.7, 0.22, 1.1), Vector3.new(0, -0.7, 0), darker(c1, 0.15))
	blk(x, Vector3.new(0.82, 0.86, 0.36), Vector3.new(0, -0.05, -0.96), c1, { studs = true })
	-- stripes / glowing dots
	for _, z in { -0.4, 0.35 } do
		blk(x, Vector3.new(1.04, 1.24, 0.18), Vector3.new(0, 0, z), c2, { neon = sp.glow })
	end
	-- forked tail and fins (animated)
	local tail = { anim = "tail", hinge = Vector3.new(0, 0, 0.8) }
	blk(x, Vector3.new(0.18, 0.8, 0.5), Vector3.new(0, 0, 1.1), c3, tail)
	blk(x, Vector3.new(0.18, 0.4, 0.45), Vector3.new(0, 0.45, 1.42), c3, tail)
	blk(x, Vector3.new(0.18, 0.4, 0.45), Vector3.new(0, -0.45, 1.42), c3, tail)
	blk(x, Vector3.new(0.15, 0.4, 0.7), Vector3.new(0, 0.98, 0.15), c3)
	for _, side in { -1, 1 } do
		blk(x, Vector3.new(0.45, 0.12, 0.38), Vector3.new(side * 0.68, -0.25, -0.1), c3,
			{ anim = "fin", hinge = Vector3.new(side * 0.5, -0.25, -0.1), side = side })
	end
	eyes(x, 0.18, -0.98, 0.42)
	if sp.bill then
		blk(x, Vector3.new(0.14, 0.14, 1.4), Vector3.new(0, -0.05, -1.85), c2)
	end
	if sp.lure then
		blk(x, Vector3.new(0.08, 0.7, 0.08), Vector3.new(0, 0.95, -0.95), c3, { rot = CFrame.Angles(-0.5, 0, 0), anim = "lure", hinge = Vector3.new(0, 0.62, -0.85) })
		blk(x, Vector3.new(0.3, 0.3, 0.3), Vector3.new(0, 1.3, -1.25), c2, { neon = true, keep = true, anim = "lure", hinge = Vector3.new(0, 0.62, -0.85) })
		for i = -1, 1 do -- big toothy mouth
			blk(x, Vector3.new(0.12, 0.18, 0.08), Vector3.new(i * 0.2, -0.3, -1.16), WHITE, { keep = true })
		end
	end
end

----------------------------------------------------------------- puffer
builders.puffer = function(x)
	local sp = x.sp
	blk(x, Vector3.new(1.5, 1.4, 1.5), Vector3.new(0, 0, 0), sp.c1, { studs = true })
	blk(x, Vector3.new(1.2, 0.25, 1.2), Vector3.new(0, 0.82, 0), sp.c1, { studs = "top" })
	blk(x, Vector3.new(1.3, 0.3, 1.3), Vector3.new(0, -0.75, 0), sp.c2)
	-- spikes all over
	for _, p in {
		Vector3.new(0.8, 0.3, 0.2), Vector3.new(-0.8, 0.3, 0.2), Vector3.new(0.8, -0.3, -0.3), Vector3.new(-0.8, -0.3, -0.3),
		Vector3.new(0.4, 0.95, 0.4), Vector3.new(-0.4, 0.95, -0.3), Vector3.new(0, 0.95, 0.6), Vector3.new(0.5, 0.2, 0.8), Vector3.new(-0.5, -0.2, 0.8),
	} do
		blk(x, Vector3.new(0.16, 0.16, 0.16), p, darker(sp.c1, 0.35))
	end
	blk(x, Vector3.new(0.35, 0.25, 0.12), Vector3.new(0, -0.2, -0.8), Color3.fromRGB(255, 120, 120), { keep = true })
	local tail = { anim = "tail", hinge = Vector3.new(0, 0, 0.75) }
	blk(x, Vector3.new(0.15, 0.6, 0.45), Vector3.new(0, 0, 0.98), sp.c1, tail)
	for _, side in { -1, 1 } do
		blk(x, Vector3.new(0.35, 0.12, 0.3), Vector3.new(side * 0.88, -0.1, 0), sp.c1, { anim = "fin", hinge = Vector3.new(side * 0.75, -0.1, 0), side = side })
	end
	frontEyes(x, 0.3, -0.78, 0.38, 0.38)
end

----------------------------------------------------------------- crab / lobster / hermit
builders.crab = function(x)
	local sp = x.sp
	local c1, c2 = sp.c1, sp.c2
	blk(x, Vector3.new(1.6, 0.55, 1.1), Vector3.new(0, 0, 0), c1, { studs = true })
	blk(x, Vector3.new(1.2, 0.25, 0.8), Vector3.new(0, 0.38, -0.05), c1, { studs = "top" })
	for _, side in { -1, 1 } do
		-- eye stalks
		blk(x, Vector3.new(0.1, 0.4, 0.1), Vector3.new(side * 0.28, 0.6, -0.45), c1)
		blk(x, Vector3.new(0.2, 0.2, 0.2), Vector3.new(side * 0.28, 0.85, -0.47), WHITE, { keep = true })
		blk(x, Vector3.new(0.12, 0.12, 0.12), Vector3.new(side * 0.28, 0.86, -0.56), INK, { keep = true })
		-- claws: an arm that grows out of the front corner of the body (it
		-- overlaps it, and swings from a shoulder inside it, so it never comes
		-- loose), then the pincer and its finger, each overlapping the last
		local claw = { anim = "claw", hinge = Vector3.new(side * 0.7, 0.05, -0.45), side = side }
		blk(x, Vector3.new(0.3, 0.3, 0.75), Vector3.new(side * 0.72, 0.05, -0.75), c1, claw)
		blk(x, Vector3.new(0.55, 0.45, 0.55), Vector3.new(side * 0.78, 0.1, -1.25), c1, { studs = "top", anim = "claw", hinge = claw.hinge, side = side })
		blk(x, Vector3.new(0.2, 0.18, 0.32), Vector3.new(side * 0.62, 0.12, -1.6), c2, { anim = "claw", hinge = claw.hinge, side = side })
		-- legs: start inside the body's underside and reach out (they lift and
		-- step from the hip, staying attached)
		local legLen = sp.long and 0.95 or 0.65
		for i, z in { -0.2, 0.12, 0.42 } do
			blk(x, Vector3.new(legLen + 0.2, 0.13, 0.13), Vector3.new(side * (0.6 + (legLen + 0.2) / 2), -0.2, z), darker(c1, 0.1),
				{ anim = "leg", hinge = Vector3.new(side * 0.65, -0.2, z), side = side, phase = i * 1.3 })
		end
	end
	if sp.shell then
		local c = c2
		blk(x, Vector3.new(1.0, 0.7, 1.0), Vector3.new(0, 0.75, 0.3), c, { studs = true })
		blk(x, Vector3.new(0.7, 0.5, 0.7), Vector3.new(0, 1.25, 0.4), darker(c, 0.12), { studs = true })
		blk(x, Vector3.new(0.4, 0.3, 0.4), Vector3.new(0, 1.62, 0.46), c, { studs = "top" })
	elseif sp.long then
		-- lobster tail
		local tail = { anim = "fluke", hinge = Vector3.new(0, 0, 0.55) }
		blk(x, Vector3.new(0.9, 0.4, 0.45), Vector3.new(0, -0.02, 0.75), c1, tail)
		blk(x, Vector3.new(0.7, 0.35, 0.4), Vector3.new(0, -0.04, 1.15), darker(c1, 0.1), tail)
		blk(x, Vector3.new(1.0, 0.14, 0.4), Vector3.new(0, -0.08, 1.5), c2, tail)
	end
end

----------------------------------------------------------------- turtle
builders.turtle = function(x)
	local sp = x.sp
	local shell, rim = sp.c1, sp.c2
	blk(x, Vector3.new(2.0, 0.18, 2.2), Vector3.new(0, -0.2, 0), rim)
	blk(x, Vector3.new(1.8, 0.4, 2.0), Vector3.new(0, 0.08, 0), shell, { studs = true })
	blk(x, Vector3.new(1.4, 0.35, 1.6), Vector3.new(0, 0.45, 0), darker(shell, 0.12), { studs = true })
	blk(x, Vector3.new(0.9, 0.3, 1.0), Vector3.new(0, 0.77, 0), shell, { studs = "top" })
	local skin = shell:Lerp(Color3.fromRGB(200, 230, 150), 0.5)
	blk(x, Vector3.new(0.6, 0.5, 0.65), Vector3.new(0, 0.05, -1.35), skin, { anim = "head", hinge = Vector3.new(0, 0, -1.05) })
	eyes(x, 0.15, -1.6, 0.31, 0.2)
	for _, side in { -1, 1 } do
		blk(x, Vector3.new(0.95, 0.12, 0.45), Vector3.new(side * 1.25, -0.15, -0.6), skin,
			{ anim = "flipper", hinge = Vector3.new(side * 0.85, -0.15, -0.6), side = side })
		blk(x, Vector3.new(0.5, 0.1, 0.35), Vector3.new(side * 0.95, -0.15, 0.85), skin,
			{ anim = "flipper", hinge = Vector3.new(side * 0.75, -0.15, 0.85), side = side, phase = 1.5 })
	end
end

----------------------------------------------------------------- whale (narwhal, orca, megalodon pup)
builders.whale = function(x)
	local sp = x.sp
	blk(x, Vector3.new(1.1, 1.0, 2.3), Vector3.new(0, 0, 0), sp.c1, { studs = true })
	blk(x, Vector3.new(0.9, 0.85, 0.5), Vector3.new(0, -0.05, -1.35), sp.c1, { studs = true })
	blk(x, Vector3.new(0.75, 0.25, 1.6), Vector3.new(0, 0.6, -0.1), sp.c1, { studs = "top" })
	blk(x, Vector3.new(0.9, 0.3, 2.0), Vector3.new(0, -0.43, -0.2), sp.c2)
	local fluke = { anim = "fluke", hinge = Vector3.new(0, 0, 1.15) }
	blk(x, Vector3.new(0.5, 0.5, 0.6), Vector3.new(0, 0.05, 1.42), sp.c1, fluke)
	blk(x, Vector3.new(1.5, 0.12, 0.5), Vector3.new(0, 0.05, 1.9), sp.c1, fluke)
	local finH = (sp.fin and 0.9) or (sp.name == "Orca" and 0.8) or 0.4
	blk(x, Vector3.new(0.15, finH, 0.55), Vector3.new(0, 0.6 + finH / 2, 0.2), sp.c1)
	for _, side in { -1, 1 } do
		blk(x, Vector3.new(0.5, 0.12, 0.35), Vector3.new(side * 0.75, -0.3, -0.5), sp.c1, { anim = "fin", hinge = Vector3.new(side * 0.55, -0.3, -0.5), side = side })
		if sp.name == "Orca" then
			blk(x, Vector3.new(0.12, 0.25, 0.4), Vector3.new(side * 0.56, 0.2, -0.9), sp.c2, { keep = true })
		end
	end
	eyes(x, 0.1, -1.1, 0.56, 0.22)
	if sp.horn then
		for i = 0, 3 do
			blk(x, Vector3.new(0.14 - i * 0.02, 0.14 - i * 0.02, 0.4), Vector3.new(0, 0.12, -1.8 - i * 0.38), sp.c2)
		end
	end
	if sp.fin then
		for i = -1, 1 do
			blk(x, Vector3.new(0.12, 0.18, 0.08), Vector3.new(i * 0.22, -0.32, -1.61), WHITE, { keep = true })
		end
	end
end

----------------------------------------------------------------- seahorse
builders.seahorse = function(x)
	local sp = x.sp
	local c1, c2 = sp.c1, sp.c2
	blk(x, Vector3.new(0.6, 0.6, 0.65), Vector3.new(0, 1.15, 0), c1, { studs = true })
	blk(x, Vector3.new(0.25, 0.25, 0.65), Vector3.new(0, 1.1, -0.6), c1)
	blk(x, Vector3.new(0.12, 0.35, 0.25), Vector3.new(0, 1.55, 0.15), c2)
	blk(x, Vector3.new(0.5, 0.5, 0.5), Vector3.new(0, 0.7, 0.12), c1)
	blk(x, Vector3.new(0.7, 0.8, 0.7), Vector3.new(0, 0.15, 0.05), c1, { studs = true })
	blk(x, Vector3.new(0.55, 0.5, 0.55), Vector3.new(0, -0.45, 0), c2)
	local tail = { anim = "curl", hinge = Vector3.new(0, -0.65, 0.05) }
	blk(x, Vector3.new(0.4, 0.35, 0.4), Vector3.new(0, -0.85, 0.2), c1, tail)
	blk(x, Vector3.new(0.3, 0.3, 0.3), Vector3.new(0, -1.1, 0.45), c1, tail)
	blk(x, Vector3.new(0.22, 0.22, 0.22), Vector3.new(0, -1.02, 0.7), c2, tail)
	blk(x, Vector3.new(0.1, 0.45, 0.3), Vector3.new(0, 0.3, 0.48), c2, { anim = "fin", hinge = Vector3.new(0, 0.3, 0.35) })
	eyes(x, 1.2, -0.05, 0.31, 0.22)
end

----------------------------------------------------------------- octopus / squid / kraken
builders.ceph = function(x)
	local sp = x.sp
	local c1, c2 = sp.c1, sp.c2
	local t = sp.ghost and 0.35 or nil
	if sp.long then
		blk(x, Vector3.new(0.9, 1.15, 0.9), Vector3.new(0, 0.75, 0), c1, { studs = true, t = t })
		blk(x, Vector3.new(0.55, 0.35, 0.55), Vector3.new(0, 1.5, 0), c1, { studs = "top", t = t })
		for _, side in { -1, 1 } do
			blk(x, Vector3.new(0.45, 0.1, 0.45), Vector3.new(side * 0.6, 1.35, 0), c2, { anim = "fin", hinge = Vector3.new(side * 0.42, 1.35, 0), side = side })
		end
		frontEyes(x, 0.55, -0.46, 0.2, 0.28)
	else
		blk(x, Vector3.new(1.2, 0.9, 1.2), Vector3.new(0, 0.6, 0), c1, { studs = true, t = t })
		blk(x, Vector3.new(0.9, 0.4, 0.9), Vector3.new(0, 1.2, 0.05), c1, { studs = true, t = t })
		blk(x, Vector3.new(0.5, 0.25, 0.5), Vector3.new(0, 1.5, 0.08), c1, { studs = "top", t = t })
		frontEyes(x, 0.6, -0.61, 0.28, 0.34)
	end
	local n = 6
	for i = 1, n do
		local a = (i / n) * math.pi * 2
		local dx, dz = math.cos(a) * 0.42, math.sin(a) * 0.42
		local tent = { anim = "tent", hinge = Vector3.new(dx, 0.15, dz), phase = i * 1.1, t = t }
		blk(x, Vector3.new(0.26, 0.6, 0.26), Vector3.new(dx, -0.15, dz), c1, tent)
		blk(x, Vector3.new(0.2, 0.5, 0.2), Vector3.new(dx * 1.3, -0.65, dz * 1.3), sp.glow and c2 or darker(c1, 0.1),
			{ anim = "tent", hinge = tent.hinge, phase = tent.phase, neon = sp.glow, t = t })
	end
end

----------------------------------------------------------------- ray
builders.ray = function(x)
	local sp = x.sp
	local c1, c2 = sp.c1, sp.c2
	blk(x, Vector3.new(1.0, 0.32, 1.5), Vector3.new(0, 0, 0), c1, { studs = true })
	blk(x, Vector3.new(1.4, 0.1, 1.3), Vector3.new(0, -0.18, 0), c2)
	for _, side in { -1, 1 } do
		local wing = { anim = "wing", hinge = Vector3.new(side * 0.5, 0, 0), side = side }
		blk(x, Vector3.new(1.0, 0.2, 1.1), Vector3.new(side * 0.98, 0, 0.05), c1, { studs = "top", anim = "wing", hinge = wing.hinge, side = side })
		blk(x, Vector3.new(0.65, 0.15, 0.65), Vector3.new(side * 1.75, 0, 0.18), sp.glow and c2 or c1, { anim = "wing", hinge = wing.hinge, side = side, neon = sp.glow })
		blk(x, Vector3.new(0.22, 0.18, 0.45), Vector3.new(side * 0.36, 0, -0.95), c1)
	end
	blk(x, Vector3.new(0.1, 0.1, 1.6), Vector3.new(0, 0, 1.55), c1, { anim = "tail", hinge = Vector3.new(0, 0, 0.75) })
	eyes(x, 0.12, -0.76, 0.42, 0.18)
end

----------------------------------------------------------------- serpent (eel, dragons, leviathan)
builders.serpent = function(x)
	local sp = x.sp
	local c1, c2 = sp.c1, sp.c2
	blk(x, Vector3.new(0.8, 0.7, 0.9), Vector3.new(0, 0.05, -1.55), c1, { studs = true })
	blk(x, Vector3.new(0.7, 0.22, 0.65), Vector3.new(0, -0.38, -1.62), darker(c1, 0.15), { anim = "jaw", hinge = Vector3.new(0, -0.3, -1.3) })
	eyes(x, 0.2, -1.92, 0.36, 0.22)
	local sizes = { 0.75, 0.68, 0.6, 0.5, 0.4 }
	for i, sz in sizes do
		local z = -0.95 + (i - 1) * 0.55
		local seg = { anim = "seg", hinge = Vector3.new(0, 0, z - 0.25), phase = i * 0.9 }
		blk(x, Vector3.new(sz, sz * 0.9, 0.58), Vector3.new(0, 0, z), (i % 2 == 0) and darker(c1, 0.1) or c1, { studs = "top", anim = "seg", hinge = seg.hinge, phase = seg.phase })
		blk(x, Vector3.new(0.1, 0.28, 0.32), Vector3.new(0, sz * 0.45 + 0.12, z), c2, { anim = "seg", hinge = seg.hinge, phase = seg.phase, neon = sp.glow })
	end
	blk(x, Vector3.new(0.12, 0.5, 0.45), Vector3.new(0, 0, 1.85), c2, { anim = "seg", hinge = Vector3.new(0, 0, 1.4), phase = 6 * 0.9 })
	if sp.horns then
		for _, side in { -1, 1 } do
			blk(x, Vector3.new(0.14, 0.55, 0.14), Vector3.new(side * 0.25, 0.6, -1.35), c2, { rot = CFrame.Angles(0.5, 0, side * 0.2) })
		end
	end
end

----------------------------------------------------------------- jellyfish
builders.jelly = function(x)
	local sp = x.sp
	local c1, c2 = sp.c1, sp.c2
	local bell = { anim = "bell", hinge = Vector3.zero, t = 0.2 }
	blk(x, Vector3.new(1.5, 0.12, 1.5), Vector3.new(0, 0.25, 0), c2, { anim = "bell", hinge = Vector3.zero })
	blk(x, Vector3.new(1.4, 0.5, 1.4), Vector3.new(0, 0.55, 0), c1, { studs = true, anim = "bell", hinge = Vector3.zero, t = bell.t })
	blk(x, Vector3.new(1.0, 0.35, 1.0), Vector3.new(0, 0.95, 0), c1, { studs = true, anim = "bell", hinge = Vector3.zero, t = bell.t })
	blk(x, Vector3.new(0.55, 0.25, 0.55), Vector3.new(0, 1.22, 0), c1, { studs = "top", anim = "bell", hinge = Vector3.zero, t = bell.t })
	blk(x, Vector3.new(0.5, 0.3, 0.5), Vector3.new(0, 0.6, 0), c2, { neon = sp.glow, anim = "bell", hinge = Vector3.zero })
	frontEyes(x, 0.55, -0.71, 0.28, 0.24)
	for i = 1, 7 do
		local a = (i / 7) * math.pi * 2
		local dx, dz = math.cos(a) * 0.5, math.sin(a) * 0.5
		blk(x, Vector3.new(0.1, 1.1, 0.1), Vector3.new(dx, -0.35, dz), c2, { anim = "tent", hinge = Vector3.new(dx, 0.2, dz), phase = i * 0.9, neon = sp.glow })
	end
end

----------------------------------------------------------------- biome looks
-- The further out the sea, the fancier its creatures: each deep biome
-- (Config.SpeciesTheme) dresses every species' studded body blocks in its
-- own look. Decor sits on the outside of a block and moves with it.

-- deterministic 0..1 noise (every copy of a species looks the same)
local function noise(i: number): number
	return (math.sin(i * 12.9898 + 4.1) * 43758.5453) % 1
end

-- a block stuck onto `src` at `pos` (studs, in src's space), riding its animation
local function stick(x: Ctx, src: BasePart, size: Vector3, pos: Vector3, color: Color3, o: { [string]: any }?): Part
	local opts = o or {}
	local cf = src.CFrame * CFrame.new(pos) * (opts.rot or CFrame.identity)
	local p = Build.part(x.m, size * x.s, cf, color)
	if opts.neon then
		p.Material = Enum.Material.Neon
	elseif opts.mat then
		p.Material = opts.mat
	end
	if opts.t then
		p.Transparency = opts.t
	end
	local kind = src:GetAttribute("Anim")
	if kind then
		p:SetAttribute("Anim", kind)
		p:SetAttribute("Rest", cf)
		p:SetAttribute("Hinge", src:GetAttribute("Hinge"))
		p:SetAttribute("Side", src:GetAttribute("Side"))
		p:SetAttribute("Phase", src:GetAttribute("Phase"))
	end
	return p
end

-- the biggest body block (most of the decor goes on it)
local function core(x: Ctx): BasePart?
	local best, vol = nil, 0
	for _, p in x.body do
		local v = p.Size.X * p.Size.Y * p.Size.Z
		if v > vol then
			best, vol = p, v
		end
	end
	return best
end

-- body blocks big enough to decorate
local function blocks(x: Ctx): { BasePart }
	local out = {}
	for _, p in x.body do
		if math.min(p.Size.X, p.Size.Z) >= 0.45 * x.s and p.Size.Y >= 0.3 * x.s then
			table.insert(out, p)
		end
	end
	return out
end

local THEMES: { [string]: (Ctx) -> () } = {}
local SPRINKLE: (Ctx, BasePart, number, number?) -> ()
local AURA = { frost = "snow", ember = "embers", fizz = "fizz", sprinkles = "sugar" }

-- Frozen Sea: a snow cap, ice crystals on top, icicles underneath
THEMES.frost = function(x)
	local ice = Color3.fromRGB(205, 240, 255)
	local c = core(x)
	if c then
		local h = c.Size / 2
		stick(x, c, Vector3.new(h.X * 1.7 / x.s, 0.08, h.Z * 1.7 / x.s), Vector3.new(0, h.Y + 0.035 * x.s, 0), WHITE)
		for i = -1, 1 do
			local len = 0.22 + noise(i + 7) * 0.18
			stick(x, c, Vector3.new(0.1, len, 0.1), Vector3.new(i * h.X * 0.55, -h.Y - len / 2 * x.s + 0.02 * x.s, (noise(i + 3) - 0.5) * h.Z),
				ice, { mat = Enum.Material.Glass, t = 0.15 })
		end
	end
	for i, p in blocks(x) do
		local h = p.Size / 2
		for k = 0, 1 do
			local n = noise(i * 5 + k)
			local len = 0.3 + n * 0.25
			stick(x, p, Vector3.new(0.13, len, 0.13), Vector3.new((k - 0.5) * h.X * 0.9, h.Y + len / 2 * x.s * 0.8, (n - 0.5) * h.Z * 1.2),
				ice, { mat = Enum.Material.Glass, t = 0.1, rot = CFrame.Angles((n - 0.5) * 0.6, 0, (k - 0.5) * 0.7) })
		end
	end
end

-- Volcano Vents: glowing lava cracks down both sides
THEMES.ember = function(x)
	local lava = Color3.fromRGB(255, 130, 30)
	for i, p in blocks(x) do
		local h = p.Size / 2
		for _, side in { -1, 1 } do
			local z0 = -h.Z * 0.6
			local y = (noise(i + side) - 0.5) * h.Y * 0.6
			for k = 0, 2 do
				local seg = h.Z * 0.5
				local tilt = (k % 2 == 0) and 0.55 or -0.55
				stick(x, p, Vector3.new(0.05, 0.13, seg / x.s), Vector3.new(side * (h.X + 0.01 * x.s), y, z0 + seg * 0.5 + k * seg * 0.85),
					lava, { neon = true, rot = CFrame.Angles(tilt, 0, 0) })
				y += (tilt > 0 and -1 or 1) * seg * 0.25
			end
		end
	end
end

-- Lost City: a gold band and a little crown
THEMES.royal = function(x)
	local gold = Color3.fromRGB(255, 205, 70)
	local c = core(x)
	if not c then
		return
	end
	local h = c.Size / 2
	stick(x, c, Vector3.new(h.X * 2 / x.s + 0.06, 0.12, h.Z * 2 / x.s + 0.06), Vector3.new(0, -h.Y * 0.35, 0), gold, { mat = Enum.Material.Foil })
	-- the crown sits on the front-most body block (the head end)
	local head = c
	for _, p in x.body do
		if p.CFrame.Position.Z < head.CFrame.Position.Z - 0.2 * x.s and p.CFrame.Position.Y >= c.CFrame.Position.Y - 0.3 * x.s then
			head = p
		end
	end
	local hh = head.Size / 2
	local top = Vector3.new(0, hh.Y + 0.06 * x.s, 0)
	stick(x, head, Vector3.new(0.5, 0.12, 0.5), top, gold, { mat = Enum.Material.Foil })
	for _, d in { Vector3.new(-1, 0, -1), Vector3.new(1, 0, -1), Vector3.new(-1, 0, 1), Vector3.new(1, 0, 1) } do
		stick(x, head, Vector3.new(0.1, 0.22, 0.1), top + Vector3.new(d.X * 0.2, 0.16, d.Z * 0.2) * x.s, gold, { mat = Enum.Material.Foil })
	end
	stick(x, head, Vector3.new(0.14, 0.14, 0.06), top + Vector3.new(0, 0.12, -0.26) * x.s, Color3.fromRGB(80, 230, 255), { neon = true })
end

-- Soda Shallows: fizzy bubbles clinging to the sides
THEMES.fizz = function(x)
	local bubble = Color3.fromRGB(235, 250, 255)
	for i, p in blocks(x) do
		local h = p.Size / 2
		for k = 1, 6 do
			local n1, n2 = noise(i * 11 + k), noise(i * 13 + k * 3)
			local side = (k % 2 == 0) and -1 or 1
			local d = 0.14 + n1 * 0.14
			stick(x, p, Vector3.new(d, d, d), Vector3.new(side * (h.X + d / 2 * x.s * 0.6), (n2 - 0.5) * h.Y * 1.4, (n1 - 0.5) * h.Z * 1.4),
				bubble, { mat = Enum.Material.Glass, t = 0.2 })
		end
	end
end

-- Gumdrop Reef: shiny gummy candy dusted with sugar
THEMES.sugar = function(x)
	for _, p in x.body do
		p.Material = Enum.Material.Glass
	end
	for i, p in blocks(x) do
		local h = p.Size / 2
		for k = 1, 5 do
			local n1, n2 = noise(i * 7 + k), noise(i * 9 + k * 2)
			stick(x, p, Vector3.new(0.09, 0.09, 0.09), Vector3.new((n1 - 0.5) * h.X * 1.7, h.Y + 0.03 * x.s, (n2 - 0.5) * h.Z * 1.7),
				WHITE, { rot = CFrame.Angles(0, n1 * 3, 0) })
		end
	end
end

-- Lollipop Lagoon: a lollipop swirl on each side
THEMES.swirl = function(x)
	local c = core(x)
	if not c then
		return
	end
	local h = c.Size / 2
	local r = math.min(h.Y, h.Z) * 0.85 / x.s
	local a, b = x.sp.c2, WHITE
	for _, side in { -1, 1 } do
		for k = 0, 3 do
			local w = r * 2 * (1 - k * 0.24)
			stick(x, c, Vector3.new(0.04 + k * 0.012, w, w), Vector3.new(side * (h.X + (0.02 + k * 0.012) * x.s), 0, 0),
				(k % 2 == 0) and a or b, { rot = CFrame.Angles(k * 0.35, 0, 0) })
		end
	end
end

-- Candy Cane Cove: candy cane bands
THEMES.stripes = function(x)
	local red, white = Color3.fromRGB(235, 40, 60), WHITE
	for i, p in blocks(x) do
		local h = p.Size / 2
		local hue, sat = p.Color:ToHSV()
		local band = (sat > 0.45 and (hue < 0.05 or hue > 0.92)) and white or red
		for k = -1, 1, 2 do
			stick(x, p, Vector3.new(h.X * 2 / x.s + 0.05, h.Y * 2 / x.s + 0.05, 0.14), Vector3.new(0, 0, k * h.Z * 0.45),
				band, { rot = CFrame.Angles(0.2, 0, 0) })
		end
		if i >= 4 then
			break
		end
	end
end

-- Chocolate Deep: frosting on top, drips down the sides, sprinkles
THEMES.drip = function(x)
	local frost = Color3.fromRGB(255, 205, 225)
	local c = core(x)
	if not c then
		return
	end
	local h = c.Size / 2
	local w, d = h.X * 2 / x.s, h.Z * 2 / x.s
	stick(x, c, Vector3.new(w + 0.06, 0.12, d + 0.06), Vector3.new(0, h.Y + 0.02 * x.s, 0), frost)
	for k = 1, 6 do
		local n = noise(k * 3)
		local len = 0.2 + n * 0.3
		local side = (k % 2 == 0) and -1 or 1
		local z = (k / 7 - 0.5) * h.Z * 1.6
		stick(x, c, Vector3.new(0.08, len, 0.18), Vector3.new(side * (h.X + 0.03 * x.s), h.Y - len / 2 * x.s, z), frost)
	end
	SPRINKLE(x, c, 7)
end

-- Sugar Abyss: rainbow sprinkles everywhere
THEMES.sprinkles = function(x)
	for i, p in blocks(x) do
		SPRINKLE(x, p, 9, i)
	end
end

local SPRINKLES = {
	Color3.fromRGB(255, 80, 120), Color3.fromRGB(255, 220, 60), Color3.fromRGB(90, 220, 255),
	Color3.fromRGB(120, 255, 140), Color3.fromRGB(200, 120, 255), WHITE,
}
SPRINKLE = function(x: Ctx, p: BasePart, n: number, seed: number?)
	local h = p.Size / 2
	local s0 = (seed or 1) * 17
	for k = 1, n do
		local n1, n2 = noise(s0 + k), noise(s0 + k * 5 + 2)
		local col = SPRINKLES[k % #SPRINKLES + 1]
		if k % 3 == 0 then -- (some on the sides, too)
			local side = (k % 2 == 0) and -1 or 1
			stick(x, p, Vector3.new(0.08, 0.26, 0.08), Vector3.new(side * (h.X + 0.03 * x.s), (n1 - 0.5) * h.Y * 1.4, (n2 - 0.5) * h.Z * 1.7),
				col, { rot = CFrame.Angles(n1 * 6, 0, 0) })
		else
			stick(x, p, Vector3.new(0.08, 0.08, 0.28), Vector3.new((n1 - 0.5) * h.X * 1.7, h.Y + 0.035 * x.s, (n2 - 0.5) * h.Z * 1.7),
				col, { rot = CFrame.Angles(0, n1 * 6, 0) })
		end
	end
end

----------------------------------------------------------------- Mythics
-- one per zone (Config.Species[zone].Mythic): their own body plans, more
-- pieces and more moving parts than anything else in the sea

local BROWN = Color3.fromRGB(130, 88, 50)
local GOLD = Color3.fromRGB(255, 205, 60)

-- a sea turtle carrying a tiny island (sp.prop: palm, chest or lolly)
builders.isle = function(x)
	local sp = x.sp
	builders.turtle(x)
	local sand = sp.c2
	blk(x, Vector3.new(1.1, 0.18, 1.2), Vector3.new(0, 1.0, 0.05), sand, { studs = "top" })
	blk(x, Vector3.new(0.72, 0.14, 0.8), Vector3.new(0.05, 1.15, 0.12), darker(sand, 0.06), { studs = "top" })
	if sp.prop == "chest" then
		blk(x, Vector3.new(0.52, 0.3, 0.38), Vector3.new(0, 1.37, 0.1), Color3.fromRGB(120, 75, 40))
		blk(x, Vector3.new(0.54, 0.06, 0.4), Vector3.new(0, 1.42, 0.1), GOLD, { mat = Enum.Material.Foil })
		blk(x, Vector3.new(0.42, 0.06, 0.3), Vector3.new(0, 1.53, 0.1), GOLD, { neon = true })
		local lid = { anim = "lid", hinge = Vector3.new(0, 1.53, 0.29) }
		blk(x, Vector3.new(0.54, 0.16, 0.4), Vector3.new(0, 1.6, 0.1), Color3.fromRGB(140, 88, 46), lid)
		blk(x, Vector3.new(0.1, 0.12, 0.05), Vector3.new(0, 1.52, -0.11), GOLD, { mat = Enum.Material.Foil, anim = "lid", hinge = lid.hinge })
		for i, p in { Vector3.new(-0.4, 1.24, -0.3), Vector3.new(0.38, 1.24, 0.45), Vector3.new(0.3, 1.1, -0.45) } do
			blk(x, Vector3.new(0.16, 0.05, 0.16), p, GOLD, { mat = Enum.Material.Foil, rot = CFrame.Angles(0, i, 0) })
		end
		return
	end
	-- a tree that sways: a palm, or a lollipop
	local top = Vector3.new(0.3, 2.12, 0.2)
	local sway = { anim = "palm", hinge = Vector3.new(0.1, 1.2, 0.2) }
	if sp.prop == "lolly" then
		blk(x, Vector3.new(0.09, 0.55, 0.09), Vector3.new(0.1, 1.47, 0.2), WHITE, sway)
		for k = 0, 3 do
			local w = 0.62 * (1 - k * 0.23)
			blk(x, Vector3.new(0.12 + k * 0.03, w, w), Vector3.new(0.1, 1.95, 0.2), (k % 2 == 0) and sp.c3 or WHITE,
				{ anim = "palm", hinge = sway.hinge, rot = CFrame.Angles(k * 0.4, 0, 0) })
		end
		for i, p in { Vector3.new(-0.38, 1.27, -0.25), Vector3.new(0.4, 1.27, 0.48), Vector3.new(-0.25, 1.27, 0.5) } do
			blk(x, Vector3.new(0.2, 0.18, 0.2), p, ({ Color3.fromRGB(255, 90, 120), Color3.fromRGB(120, 230, 120), Color3.fromRGB(255, 210, 70) })[i],
				{ mat = Enum.Material.Glass })
		end
		return
	end
	for i, seg in { { 0.17, 1.38, -0.12 }, { 0.2, 1.7, -0.24 }, { 0.26, 1.98, -0.36 } } do
		blk(x, Vector3.new(0.17 - i * 0.01, 0.36, 0.17 - i * 0.01), Vector3.new(seg[1], seg[2], 0.2), BROWN,
			{ rot = CFrame.Angles(0, 0, seg[3]), anim = "palm", hinge = sway.hinge })
	end
	local leaf = Color3.fromRGB(60, 190, 80)
	for i = 0, 4 do
		local a = i / 5 * math.pi * 2
		local c = top + Vector3.new(-math.sin(a) * 0.36, -0.05, -math.cos(a) * 0.36)
		blk(x, Vector3.new(0.2, 0.07, 0.72), c, i % 2 == 0 and leaf or darker(leaf, 0.15),
			{ rot = CFrame.Angles(0, a, 0) * CFrame.Angles(-0.35, 0, 0), anim = "palm", hinge = sway.hinge })
	end
	for _, side in { -1, 1 } do
		blk(x, Vector3.new(0.15, 0.15, 0.15), top + Vector3.new(side * 0.09, -0.14, 0.04), Color3.fromRGB(110, 70, 35), { anim = "palm", hinge = sway.hinge })
	end
	blk(x, Vector3.new(0.2, 0.06, 0.2), Vector3.new(-0.35, 1.25, -0.3), Color3.fromRGB(255, 120, 150)) -- a shell on the beach
end

-- an axolotl: wide smiling head, feathery gills, little legs
builders.axolotl = function(x)
	local sp = x.sp
	local c1, c2 = sp.c1, sp.c2
	blk(x, Vector3.new(0.95, 0.65, 1.5), Vector3.new(0, 0, 0.1), c1, { studs = true })
	blk(x, Vector3.new(0.8, 0.12, 1.3), Vector3.new(0, -0.36, 0.1), c1:Lerp(WHITE, 0.35))
	blk(x, Vector3.new(0.08, 0.18, 1.2), Vector3.new(0, 0.41, 0.25), c2)
	blk(x, Vector3.new(1.25, 0.7, 0.85), Vector3.new(0, 0.08, -0.95), c1, { studs = true })
	eyes(x, 0.2, -1.12, 0.63, 0.2)
	blk(x, Vector3.new(0.55, 0.05, 0.04), Vector3.new(0, -0.12, -1.39), INK, { keep = true })
	for _, side in { -1, 1 } do
		blk(x, Vector3.new(0.05, 0.05, 0.04), Vector3.new(side * 0.29, -0.09, -1.39), INK, { keep = true })
		blk(x, Vector3.new(0.18, 0.1, 0.04), Vector3.new(side * 0.42, 0.0, -1.39), Color3.fromRGB(255, 140, 170), { keep = true })
		-- three feathery gills fanning out behind the head
		for k = 0, 2 do
			local ang = 0.35 + k * 0.55
			local base = Vector3.new(side * 0.55, 0.32 - k * 0.14, -0.8)
			local gill = { anim = "gill", hinge = base, side = side, phase = k * 0.8 }
			local dir = Vector3.new(side * math.sin(ang), math.cos(ang), 0)
			blk(x, Vector3.new(0.11, 0.5, 0.11), base + dir * 0.25, c2, { rot = CFrame.Angles(0, 0, -side * ang), anim = "gill", hinge = base, side = side, phase = gill.phase })
			for j = 1, 2 do
				blk(x, Vector3.new(0.2, 0.08, 0.08), base + dir * (0.18 + j * 0.13), c2:Lerp(WHITE, 0.3),
					{ rot = CFrame.Angles(0, 0, -side * ang), anim = "gill", hinge = base, side = side, phase = gill.phase, neon = sp.glow })
			end
		end
		for i, z in { -0.35, 0.6 } do
			local leg = { anim = "leg", hinge = Vector3.new(side * 0.42, -0.22, z), side = side, phase = i * 1.6 + (side > 0 and 0 or math.pi) }
			blk(x, Vector3.new(0.42, 0.14, 0.2), Vector3.new(side * 0.66, -0.25, z), c1, leg)
			blk(x, Vector3.new(0.14, 0.1, 0.28), Vector3.new(side * 0.85, -0.28, z - 0.05), c1:Lerp(WHITE, 0.2),
				{ anim = "leg", hinge = leg.hinge, side = side, phase = leg.phase })
		end
	end
	for i, sz in { 0.62, 0.48, 0.34 } do
		local z = 0.95 + (i - 1) * 0.47
		local seg = { anim = "seg", hinge = Vector3.new(0, 0, z - 0.24), phase = i * 0.9 }
		blk(x, Vector3.new(sz * 0.8, sz * 0.8, 0.5), Vector3.new(0, 0, z), c1, seg)
		blk(x, Vector3.new(0.07, sz * 0.5 + 0.1, 0.48), Vector3.new(0, sz * 0.4 + 0.12, z), c2, { anim = "seg", hinge = seg.hinge, phase = seg.phase })
		blk(x, Vector3.new(0.07, sz * 0.3, 0.48), Vector3.new(0, -sz * 0.4 - 0.06, z), c2, { anim = "seg", hinge = seg.hinge, phase = seg.phase })
	end
end

-- a mantis shrimp: rainbow plates, stalk eyes, and a very fast punch
builders.mantis = function(x)
	local sp = x.sp
	local c1, c2, c3 = sp.c1, sp.c2, sp.c3 or sp.c2
	blk(x, Vector3.new(0.8, 0.58, 0.7), Vector3.new(0, 0.05, -0.85), c1, { studs = true })
	blk(x, Vector3.new(0.7, 0.1, 0.6), Vector3.new(0, 0.38, -0.85), c2)
	for i = 1, 4 do
		local w, h = 0.86 - i * 0.07, 0.6 - i * 0.04
		local z = -0.4 + (i - 1) * 0.45
		blk(x, Vector3.new(w, h, 0.46), Vector3.new(0, 0, z), (i % 2 == 0) and darker(c1, 0.15) or c1, { studs = "top" })
		blk(x, Vector3.new(w * 0.9, 0.08, 0.3), Vector3.new(0, h / 2 + 0.04, z), (i % 2 == 0) and c3 or c2)
	end
	for _, side in { -1, 1 } do
		local stalk = { anim = "stalk", hinge = Vector3.new(side * 0.2, 0.3, -1.1), phase = side }
		blk(x, Vector3.new(0.1, 0.32, 0.1), Vector3.new(side * 0.2, 0.46, -1.1), c1, stalk)
		blk(x, Vector3.new(0.28, 0.28, 0.28), Vector3.new(side * 0.2, 0.72, -1.12), c3, { anim = "stalk", hinge = stalk.hinge, phase = stalk.phase, keep = true })
		blk(x, Vector3.new(0.3, 0.07, 0.3), Vector3.new(side * 0.2, 0.72, -1.12), INK, { anim = "stalk", hinge = stalk.hinge, phase = stalk.phase, keep = true })
		local ant = { anim = "lure", hinge = Vector3.new(side * 0.22, 0.25, -1.15) }
		blk(x, Vector3.new(0.05, 0.05, 1.0), Vector3.new(side * 0.4, 0.5, -1.6), c2, { rot = CFrame.Angles(0.35, side * 0.35, 0), anim = "lure", hinge = ant.hinge })
		blk(x, Vector3.new(0.24, 0.05, 0.36), Vector3.new(side * 0.36, 0.2, -1.35), c3, { rot = CFrame.Angles(0, side * 0.3, 0), anim = "lure", hinge = ant.hinge })
		-- the punching arms, folded under the head
		local punch = { anim = "punch", hinge = Vector3.new(side * 0.3, -0.28, -0.75), phase = side > 0 and 0 or 0.5 }
		blk(x, Vector3.new(0.17, 0.17, 0.55), Vector3.new(side * 0.3, -0.35, -1.0), c2, punch)
		blk(x, Vector3.new(0.24, 0.24, 0.3), Vector3.new(side * 0.3, -0.35, -1.38), c3, { anim = "punch", hinge = punch.hinge, phase = punch.phase })
		for i, z in { -0.35, 0.05, 0.45 } do
			blk(x, Vector3.new(0.42, 0.08, 0.08), Vector3.new(side * 0.5, -0.3, z), c2,
				{ anim = "leg", hinge = Vector3.new(side * 0.3, -0.3, z), side = side, phase = i * 1.3 })
		end
	end
	local fan = { anim = "fluke", hinge = Vector3.new(0, 0, 1.2) }
	blk(x, Vector3.new(0.55, 0.26, 0.45), Vector3.new(0, 0, 1.42), c1, fan)
	for i = -1, 1 do
		blk(x, Vector3.new(0.3, 0.07, 0.55), Vector3.new(i * 0.32, 0, 1.85), (i == 0) and c3 or c2,
			{ anim = "fluke", hinge = fan.hinge, rot = CFrame.Angles(0, -i * 0.35, 0) })
		blk(x, Vector3.new(0.2, 0.08, 0.12), Vector3.new(i * 0.4, 0, 2.12), c3, { anim = "fluke", hinge = fan.hinge, neon = true, rot = CFrame.Angles(0, -i * 0.35, 0) })
	end
end

-- a three-headed sea serpent
builders.hydra = function(x)
	local sp = x.sp
	local c1, c2 = sp.c1, sp.c2
	blk(x, Vector3.new(1.3, 0.9, 1.4), Vector3.new(0, 0, 0.3), c1, { studs = true })
	blk(x, Vector3.new(1.1, 0.15, 1.2), Vector3.new(0, -0.5, 0.3), c1:Lerp(c2, 0.35))
	for i, z in { -0.05, 0.35, 0.75 } do
		blk(x, Vector3.new(0.12, 0.32 - i * 0.04, 0.22), Vector3.new(0, 0.58, z), c2, { neon = sp.glow })
	end
	for _, side in { -1, 1 } do
		blk(x, Vector3.new(0.7, 0.12, 0.4), Vector3.new(side * 0.95, -0.3, 0.0), c1, { anim = "flipper", hinge = Vector3.new(side * 0.62, -0.3, 0.0), side = side })
		blk(x, Vector3.new(0.5, 0.1, 0.35), Vector3.new(side * 0.85, -0.3, 0.8), c1, { anim = "flipper", hinge = Vector3.new(side * 0.62, -0.3, 0.8), side = side, phase = 1.5 })
	end
	for i, sz in { 0.6, 0.45, 0.32 } do
		local z = 1.25 + (i - 1) * 0.45
		blk(x, Vector3.new(sz, sz * 0.9, 0.5), Vector3.new(0, 0, z), (i % 2 == 0) and darker(c1, 0.1) or c1,
			{ anim = "seg", hinge = Vector3.new(0, 0, z - 0.25), phase = i * 0.9 })
	end
	blk(x, Vector3.new(0.1, 0.45, 0.35), Vector3.new(0, 0, 2.3), c2, { anim = "seg", hinge = Vector3.new(0, 0, 1.95), phase = 3.6 })
	-- three necks rising from the front of the body
	for n, a in { -0.6, 0, 0.6 } do
		local base = Vector3.new(math.sin(a) * 0.45, 0.3, -0.25)
		local tall = (a == 0) and 1.15 or 1
		local o = { anim = "neck", hinge = base, phase = n * 2.1 }
		local function at(k: number): Vector3
			return base + Vector3.new(math.sin(a) * 0.22 * k, 0.3 * k * tall, -0.26 * k)
		end
		for k = 1, 3 do
			local sz = 0.44 - k * 0.04
			blk(x, Vector3.new(sz, sz, sz), at(k), (k % 2 == 0) and darker(c1, 0.1) or c1, o)
		end
		local head = at(3.7)
		blk(x, Vector3.new(0.5, 0.42, 0.62), head, c1, { studs = "top", anim = "neck", hinge = base, phase = o.phase })
		blk(x, Vector3.new(0.36, 0.2, 0.32), head + Vector3.new(0, -0.08, -0.44), c1, o)
		blk(x, Vector3.new(0.3, 0.08, 0.3), head + Vector3.new(0, -0.22, -0.4), darker(c1, 0.3), o)
		for _, side in { -1, 1 } do
			blk(x, Vector3.new(0.06, 0.1, 0.06), head + Vector3.new(side * 0.1, -0.16, -0.56), WHITE, { keep = true, anim = "neck", hinge = base, phase = o.phase })
			blk(x, Vector3.new(0.07, 0.14, 0.14), head + Vector3.new(side * 0.26, 0.07, -0.12), WHITE, { keep = true, anim = "neck", hinge = base, phase = o.phase })
			blk(x, Vector3.new(0.08, 0.08, 0.08), head + Vector3.new(side * 0.28, 0.06, -0.15), sp.glow and c2 or INK,
				{ keep = true, neon = sp.glow, anim = "neck", hinge = base, phase = o.phase })
			blk(x, Vector3.new(0.08, 0.28, 0.08), head + Vector3.new(side * 0.15, 0.3, 0.15), c2,
				{ rot = CFrame.Angles(0.6, 0, side * 0.25), anim = "neck", hinge = base, phase = o.phase })
		end
	end
end

-- a whale made of night sky: stars, and two rings that circle it
builders.cosmic = function(x)
	local sp = x.sp
	builders.whale(x)
	local star, ring = sp.c2, sp.c3 or sp.c2
	for i = 1, 14 do
		local n1, n2 = noise(i * 3.1), noise(i * 7.7)
		local d = 0.08 + (i % 3) * 0.03
		if i % 3 == 0 then
			blk(x, Vector3.new(d, d, d), Vector3.new((n1 - 0.5) * 0.6, 0.74, (n2 - 0.5) * 1.4), star, { neon = true })
		else
			local side = (i % 2 == 0) and -1 or 1
			blk(x, Vector3.new(d, d, d), Vector3.new(side * 0.56, (n1 - 0.5) * 0.7, (n2 - 0.5) * 2.0), star, { neon = true })
		end
	end
	-- a constellation drawn down each side
	for _, side in { -1, 1 } do
		local pts = { Vector3.new(side * 0.565, 0.25, -0.8), Vector3.new(side * 0.565, -0.05, -0.2), Vector3.new(side * 0.565, 0.2, 0.4), Vector3.new(side * 0.565, -0.1, 0.9) }
		for i = 1, #pts - 1 do
			local a, b = pts[i], pts[i + 1]
			local mid, len = (a + b) / 2, (b - a).Magnitude
			blk(x, Vector3.new(0.02, 0.03, len), mid, star, { neon = true, t = 0.3, rot = CFrame.Angles(-math.atan2(b.Y - a.Y, b.Z - a.Z), 0, 0) })
			blk(x, Vector3.new(0.05, 0.12, 0.12), a, star, { neon = true })
		end
	end
	blk(x, Vector3.new(1.62, 0.06, 0.14), Vector3.new(0, 0.05, 2.15), star, { neon = true, anim = "fluke", hinge = Vector3.new(0, 0, 1.15) })
	for r, tilt in { 0.45, -0.35 } do
		for i = 1, 16 do
			local a = i / 16 * math.pi * 2
			local p = CFrame.Angles(tilt, 0, tilt * 0.6) * Vector3.new(math.cos(a) * 1.55, 0, math.sin(a) * 1.55)
			blk(x, Vector3.new(0.12, 0.06, 0.32), p, ring, { neon = true, t = 0.15, rot = CFrame.Angles(tilt, 0, tilt * 0.6) * CFrame.Angles(0, -a, 0),
				anim = "orbit", hinge = Vector3.zero, side = r == 1 and 1 or -1 })
		end
	end
end

-- a phoenix that swims: fire-feather wings and long trailing tail plumes
builders.phoenix = function(x)
	local sp = x.sp
	local c1, c2, c3 = sp.c1, sp.c2, sp.c3 or sp.c2
	blk(x, Vector3.new(0.8, 0.7, 1.3), Vector3.new(0, 0, 0.1), c1, { studs = true })
	blk(x, Vector3.new(0.68, 0.5, 0.35), Vector3.new(0, -0.08, -0.62), c3)
	blk(x, Vector3.new(0.62, 0.56, 0.6), Vector3.new(0, 0.28, -0.92), c1, { studs = true })
	blk(x, Vector3.new(0.2, 0.16, 0.34), Vector3.new(0, 0.22, -1.38), GOLD)
	blk(x, Vector3.new(0.14, 0.08, 0.24), Vector3.new(0, 0.1, -1.32), darker(GOLD, 0.2))
	eyes(x, 0.36, -1.04, 0.32, 0.18)
	for k = 0, 2 do
		blk(x, Vector3.new(0.08, 0.5 - k * 0.08, 0.16), Vector3.new(0, 0.72 - k * 0.04, -0.95 + k * 0.17), (k == 0) and c2 or c3,
			{ rot = CFrame.Angles(0.5 + k * 0.25, 0, 0), neon = k == 0, anim = "crest", hinge = Vector3.new(0, 0.55, -0.9), phase = k * 0.6 })
	end
	for _, side in { -1, 1 } do
		local w = { anim = "flap", hinge = Vector3.new(side * 0.38, 0.15, -0.05), side = side }
		blk(x, Vector3.new(0.65, 0.12, 0.75), Vector3.new(side * 0.68, 0.15, 0.0), c1, { studs = "top", anim = "flap", hinge = w.hinge, side = side })
		blk(x, Vector3.new(0.55, 0.1, 0.6), Vector3.new(side * 1.2, 0.15, 0.08), c2, w)
		for j = 0, 2 do
			blk(x, Vector3.new(0.45, 0.08, 0.17), Vector3.new(side * 1.62, 0.15, -0.12 + j * 0.21), c3,
				{ anim = "flap", hinge = w.hinge, side = side, neon = sp.glow, rot = CFrame.Angles(0, side * (j - 1) * 0.18, 0) })
		end
	end
	for j = -1, 1 do
		for k = 0, 2 do
			blk(x, Vector3.new(0.13, 0.06, 0.5), Vector3.new(j * 0.2, 0.05 - k * 0.05, 0.98 + k * 0.45), ({ c1, c2, c3 })[k + 1],
				{ anim = "seg", hinge = Vector3.new(j * 0.2, 0, 0.75), phase = k * 0.9 + j * 0.7, neon = k == 2 and sp.glow })
		end
	end
end

-- a hippocampus: a sea horse in the old sense (horse in front, fish behind)
builders.hippo = function(x)
	local sp = x.sp
	local c1, c2 = sp.c1, sp.c2
	blk(x, Vector3.new(0.85, 0.85, 0.9), Vector3.new(0, 0.25, -0.3), c1, { studs = true })
	blk(x, Vector3.new(0.55, 0.7, 0.5), Vector3.new(0, 0.85, -0.65), c1, { rot = CFrame.Angles(-0.35, 0, 0) })
	blk(x, Vector3.new(0.55, 0.55, 0.75), Vector3.new(0, 1.3, -0.95), c1, { studs = "top" })
	blk(x, Vector3.new(0.45, 0.4, 0.42), Vector3.new(0, 1.18, -1.48), c1:Lerp(WHITE, 0.25))
	for _, side in { -1, 1 } do
		blk(x, Vector3.new(0.06, 0.06, 0.04), Vector3.new(side * 0.1, 1.2, -1.7), INK, { keep = true })
		blk(x, Vector3.new(0.1, 0.24, 0.1), Vector3.new(side * 0.18, 1.66, -0.78), c1)
	end
	eyes(x, 1.4, -1.1, 0.28, 0.2)
	if sp.horn then
		for i = 0, 2 do
			blk(x, Vector3.new(0.12 - i * 0.03, 0.22, 0.12 - i * 0.03), Vector3.new(0, 1.66 + i * 0.17, -1.15 - i * 0.08), c2, { neon = true, rot = CFrame.Angles(-0.4, 0, 0) })
		end
	end
	for k = 0, 4 do
		local p = Vector3.new(0, 1.62 - k * 0.2, -0.72 + k * 0.13)
		blk(x, Vector3.new(0.08, 0.3, 0.24), p + Vector3.new(0, 0.08, 0.1), c2, { anim = "mane", hinge = p, phase = k * 0.7, neon = sp.glow })
	end
	for _, side in { -1, 1 } do
		local leg = { anim = "gallop", hinge = Vector3.new(side * 0.28, -0.05, -0.5), phase = side > 0 and 0 or math.pi }
		blk(x, Vector3.new(0.22, 0.5, 0.22), Vector3.new(side * 0.28, -0.3, -0.55), c1, leg)
		blk(x, Vector3.new(0.26, 0.16, 0.28), Vector3.new(side * 0.28, -0.6, -0.6), c2, { anim = "gallop", hinge = leg.hinge, phase = leg.phase })
		blk(x, Vector3.new(0.06, 0.26, 0.26), Vector3.new(side * 0.28, -0.32, -0.35), c2, { anim = "gallop", hinge = leg.hinge, phase = leg.phase })
		blk(x, Vector3.new(0.42, 0.08, 0.3), Vector3.new(side * 0.55, 0.1, 0.45), c2, { anim = "fin", hinge = Vector3.new(side * 0.35, 0.1, 0.45), side = side })
	end
	blk(x, Vector3.new(0.75, 0.7, 0.6), Vector3.new(0, 0.2, 0.35), c1, { studs = true })
	for i, sz in { 0.6, 0.45, 0.32 } do
		local z = 0.85 + (i - 1) * 0.43
		blk(x, Vector3.new(sz, sz * 0.92, 0.5), Vector3.new(0, 0.18 + i * 0.03, z), (i % 2 == 0) and darker(c1, 0.1) or c1,
			{ studs = "top", anim = "seg", hinge = Vector3.new(0, 0.2, z - 0.25), phase = i * 0.9 })
	end
	local tail = { anim = "seg", hinge = Vector3.new(0, 0.2, 1.65), phase = 4 * 0.9 }
	blk(x, Vector3.new(0.1, 0.65, 0.45), Vector3.new(0, 0.55, 1.95), c2, { rot = CFrame.Angles(0.55, 0, 0), anim = "seg", hinge = tail.hinge, phase = tail.phase })
	blk(x, Vector3.new(0.1, 0.65, 0.45), Vector3.new(0, -0.05, 1.95), c2, { rot = CFrame.Angles(-0.55, 0, 0), anim = "seg", hinge = tail.hinge, phase = tail.phase })
end

----------------------------------------------------------------- build
-- rarity + zone -> species model (anchored, visual only)
function Creatures.build(rarityId: string, mutationId: string?, scale: number?, zoneId: string?): Model
	local sp = Config.species(zoneId, rarityId)
	local m = Build.model(sp.name)
	Build.root(m)
	local fn = builders[sp.kind] or builders.fish
	local x = { m = m, s = (scale or 1) * (sp.size or 1), sp = sp, body = {} }
	fn(x)
	local themeId = Config.SpeciesTheme[zoneId or "Lagoon"]
	local theme = THEMES[themeId or ""]
	if theme and not (rarityId == "Mythic" and themeId == "stripes") then -- (the Mythic wears its own stripes)
		theme(x)
	end
	if rarityId == "Mythic" then
		m:SetAttribute("Aura", "mythic") -- (clients add the sparkle aura: Animals.luau)
	elseif theme and Config.SpeciesTheme[zoneId or ""] then
		local aura = AURA[Config.SpeciesTheme[zoneId :: string]]
		if aura then
			m:SetAttribute("Aura", aura)
		end
	end
	m:SetAttribute("Rarity", rarityId)
	m:SetAttribute("Species", sp.name)
	if mutationId == "Gold" then
		Build.recolor(m, Color3.fromRGB(255, 200, 50), Enum.Material.Foil)
	elseif mutationId == "Diamond" then
		Build.recolor(m, Color3.fromRGB(160, 236, 255), Enum.Material.Glass)
	elseif mutationId == "Rainbow" then
		m:SetAttribute("Rainbow", true) -- clients cycle the hue
		CollectionService:AddTag(m, "Rainbow")
	else
		for _, l in Config.Limited do
			if l.id == mutationId then
				Build.recolor(m, l.color, l.material)
			end
		end
	end
	if mutationId then
		m:SetAttribute("Mutation", mutationId)
	end
	Build.ghost(m)
	CollectionService:AddTag(m, "Creature")
	m.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	return m
end

function Creatures.label(rarityId: string, mutationId: string?, zoneId: string?): string
	return Config.creatureName(zoneId, rarityId, mutationId)
end

return Creatures
