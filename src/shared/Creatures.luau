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

type Ctx = { m: Model, s: number, sp: any }

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
		-- claws
		local claw = { anim = "claw", hinge = Vector3.new(side * 0.8, 0, -0.35), side = side }
		blk(x, Vector3.new(0.28, 0.28, 0.6), Vector3.new(side * 0.95, 0.05, -0.6), c1, claw)
		blk(x, Vector3.new(0.5, 0.4, 0.5), Vector3.new(side * 1.05, 0.1, -1.05), c1, { studs = "top", anim = "claw", hinge = claw.hinge, side = side })
		blk(x, Vector3.new(0.2, 0.18, 0.3), Vector3.new(side * 0.9, 0.1, -1.38), c2, { anim = "claw", hinge = claw.hinge, side = side })
		-- legs
		local legLen = sp.long and 0.95 or 0.6
		for i, z in { -0.15, 0.15, 0.45 } do
			blk(x, Vector3.new(legLen, 0.12, 0.12), Vector3.new(side * (0.8 + legLen / 2), -0.22, z), darker(c1, 0.1),
				{ anim = "leg", hinge = Vector3.new(side * 0.8, -0.22, z), side = side, phase = i * 1.3 })
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

----------------------------------------------------------------- build
-- rarity + zone -> species model (anchored, visual only)
function Creatures.build(rarityId: string, mutationId: string?, scale: number?, zoneId: string?): Model
	local sp = Config.species(zoneId, rarityId)
	local m = Build.model(sp.name)
	Build.root(m)
	local fn = builders[sp.kind] or builders.fish
	fn({ m = m, s = (scale or 1) * (sp.size or 1), sp = sp })
	m:SetAttribute("Rarity", rarityId)
	m:SetAttribute("Species", sp.name)
	if mutationId == "Gold" then
		Build.recolor(m, Color3.fromRGB(255, 200, 50), Enum.Material.Foil)
	elseif mutationId == "Diamond" then
		Build.recolor(m, Color3.fromRGB(160, 236, 255), Enum.Material.Glass)
	elseif mutationId == "Rainbow" then
		m:SetAttribute("Rainbow", true) -- clients cycle the hue
		CollectionService:AddTag(m, "Rainbow")
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
