-- Builds the whole map at server start, in one simple studded style:
--   * a studded grass plaza with 8 docks, three small shop huts and a
--     leaderboard board, boxed in by checkered stud walls with a grass topper
--   * the same walls run down both sides of the ocean lane (one long corridor)
--   * terrain water that gets deeper/darker zone by zone, arch gates between
--     zones, blocky sand islands (the safe spots), light decorations
-- Only the important things are big: the water, the gates, your dock.

local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")
local CollectionService = game:GetService("CollectionService")

local Shared = game.ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Layout = require(Shared.Layout)
local Npc = require(Shared.Npc)
local Build = require(Shared.Build)
local Props = require(Shared.Props)

local World = {}
local C = Color3.fromRGB
local W = Config.LANE_WIDTH
local Terrain = Workspace.Terrain

export type Plot = {
	index: number,
	cf: CFrame,
	model: Model,
	padLabel: TextLabel,
	signLabel: TextLabel,
	tankIncome: TextLabel,
	viewPrompt: ProximityPrompt,
	tankOffline: TextLabel,
	slots: Folder,
	owner: Player?,
}
World.Plots = {} :: { Plot }
World.boards = {} :: { [string]: { SurfaceGui } } -- a copy of each board in every world

local map: Instance
-- the world being built (World.build runs every builder once per world)
local WORLD, OX = 1, 0
local ZONES = Config.worldZones(1)
local OCEAN = Config.oceanEnd(1)

local GRASS = C(110, 214, 64)
local GRASS2 = C(98, 198, 56)
local SAND = C(255, 226, 150)
local WALL_A = C(222, 172, 108)
local WALL_B = C(178, 122, 72)
local PLAZA_BACK = -128
local WALL_T = 8 -- wall thickness
local WALL_X = W / 2 + WALL_T / 2 -- wall center line

----------------------------------------------------------------- helpers
local function studAll(p: BasePart): BasePart
	return Build.studs(p, Build.ALL_FACES)
end

local function label(parent: Instance, studs: Vector2, offset: Vector3, text: string, color: Color3?, maxDist: number?): TextLabel
	-- sized in studs (fromScale) so signs shrink with distance instead of
	-- covering the screen
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromScale(studs.X, studs.Y)
	bb.StudsOffsetWorldSpace = offset
	bb.MaxDistance = maxDist or 110
	bb.LightInfluence = 0
	bb.Parent = parent
	local t = Instance.new("TextLabel")
	t.Size = UDim2.fromScale(1, 1)
	t.BackgroundTransparency = 1
	t.Font = Enum.Font.FredokaOne
	t.TextScaled = true
	t.TextColor3 = color or C(255, 255, 255)
	t.Text = text
	t.Parent = bb
	local s = Instance.new("UIStroke")
	s.Color = C(22, 22, 34)
	s.Thickness = 2.5
	s.Parent = t
	return t
end

local function surfaceText(part: BasePart, face: Enum.NormalId, text: string, color: Color3?, canvas: Vector2?): TextLabel
	local sg = Instance.new("SurfaceGui")
	sg.Face = face
	sg.CanvasSize = canvas or Vector2.new(400, 100)
	sg.LightInfluence = 0
	sg.Parent = part
	local t = Instance.new("TextLabel")
	t.Name = "Text"
	t.Size = UDim2.fromScale(0.94, 0.86)
	t.Position = UDim2.fromScale(0.03, 0.07)
	t.BackgroundTransparency = 1
	t.Font = Enum.Font.FredokaOne
	t.TextScaled = true
	t.TextColor3 = color or C(255, 255, 255)
	t.Text = text
	t.Parent = sg
	local s = Instance.new("UIStroke")
	s.Color = C(22, 22, 34)
	s.Thickness = 4
	s.Parent = t
	return t
end

-- Checkered stud wall with a grass topper, from a to b (axis aligned).
-- `inner` is the face players see (gets studs); trims shorten the topper
-- at either end so corner toppers never overlap (no z-fighting).
local function checkerWall(parent: Instance, a: Vector3, b: Vector3, bottom: number, top: number, inner: { Enum.NormalId }, trimA: number?, trimB: number?)
	local len = (b - a).Magnitude
	local dir = (b - a).Unit
	local alongX = math.abs(dir.X) > 0.5
	local rows = math.max(1, math.floor((top - bottom) / 8 + 0.5))
	local rowH = (top - bottom) / rows
	local n = math.max(1, math.floor(len / 12 + 0.5))
	local step = len / n
	for i = 0, n - 1 do
		local mid = a + dir * (step * (i + 0.5))
		for r = 0, rows - 1 do
			local size = alongX and Vector3.new(step, rowH, WALL_T) or Vector3.new(WALL_T, rowH, step)
			local p = Build.part(parent, size, CFrame.new(mid.X, bottom + rowH * (r + 0.5), mid.Z), ((i + r) % 2 == 0) and WALL_A or WALL_B)
			Build.studs(p, inner)
		end
	end
	-- grass topper in long runs that meet exactly end to end
	local a2 = a + dir * (trimA or 0)
	local len2 = len - (trimA or 0) - (trimB or 0)
	local runs = math.max(1, math.ceil(len2 / 400))
	local runLen = len2 / runs
	for i = 0, runs - 1 do
		local mid = a2 + dir * (runLen * (i + 0.5))
		local size = alongX and Vector3.new(runLen, 2, WALL_T + 1.6) or Vector3.new(WALL_T + 1.6, 2, runLen)
		local topper = Build.part(parent, size, CFrame.new(mid.X, top + 1, mid.Z), GRASS, { Name = "Topper" })
		Build.studs(topper, { Enum.NormalId.Top })
		local lip = alongX and Vector3.new(runLen, 0.8, WALL_T + 2.2) or Vector3.new(WALL_T + 2.2, 0.8, runLen)
		Build.part(parent, lip, CFrame.new(mid.X, top + 0.25, mid.Z), GRASS2, { Name = "Drip" })
	end
end

local WALL_BOTTOM, WALL_TOP = -6, 16 -- tall checker walls, terraced grass banks with trees above

----------------------------------------------------------------- terrain
local function fill(minV: Vector3, maxV: Vector3, mat: Enum.Material)
	minV += Vector3.new(OX, 0, 0) -- terrain can't be moved after: offset here
	maxV += Vector3.new(OX, 0, 0)
	local step = 512
	local x = minV.X
	while x < maxV.X do
		local x2 = math.min(x + step, maxV.X)
		local z = minV.Z
		while z < maxV.Z do
			local z2 = math.min(z + step, maxV.Z)
			Terrain:FillBlock(
				CFrame.new((x + x2) / 2, (minV.Y + maxV.Y) / 2, (z + z2) / 2),
				Vector3.new(x2 - x, maxV.Y - minV.Y, z2 - z),
				mat
			)
			z = z2
		end
		x = x2
		task.wait()
	end
end

local function buildTerrain()
	if WORLD == 1 then
		Terrain:Clear()
	end
	local X = 900
	local zFar = OCEAN + 600
	-- open ocean all around (seen over the walls)
	fill(Vector3.new(-X, -16, PLAZA_BACK - 300), Vector3.new(X, 0, zFar), Enum.Material.Water)
	fill(Vector3.new(-X, -24, PLAZA_BACK - 300), Vector3.new(X, -16, zFar), Enum.Material.Sand)
	-- the lane: each zone gets deeper and darker
	for _, zone in ZONES do
		local half = W / 2 + 2
		fill(Vector3.new(-half, -zone.depth, zone.zStart), Vector3.new(half, 0, zone.zEnd), Enum.Material.Water)
		fill(Vector3.new(-half, -zone.depth - 8, zone.zStart), Vector3.new(half, -zone.depth, zone.zEnd), zone.floor)
		Terrain:SetMaterialColor(zone.floor, zone.floorColor)
	end
	-- under the plaza (parts sit on top) and the shallow slope off the beach
	fill(Vector3.new(-W / 2 - 20, -24, PLAZA_BACK - 10), Vector3.new(W / 2 + 20, -1, 0), Enum.Material.Sand)
	for z = 0, 12, 4 do
		fill(Vector3.new(-W / 2 - 2, -24, z), Vector3.new(W / 2 + 2, -2 - z * 0.4, z + 4), Enum.Material.Sand)
	end
	Terrain:SetMaterialColor(Enum.Material.Sand, C(255, 232, 170))

	Terrain.WaterColor = Config.Worlds[1].zones[1].water
	Terrain.WaterTransparency = 0.9
	Terrain.WaterReflectance = 0.55
	Terrain.WaterWaveSize = 0.14
	Terrain.WaterWaveSpeed = 10

	local clouds = Terrain:FindFirstChildOfClass("Clouds") or Instance.new("Clouds")
	clouds.Cover = 0.62
	clouds.Density = 0.75
	clouds.Color = C(255, 255, 255)
	clouds.Parent = Terrain
end

----------------------------------------------------------------- lighting
-- bright midday, punchy colors, soft haze on the horizon
local function buildLighting()
	Lighting.ClockTime = 13.6
	Lighting.GeographicLatitude = 30
	Lighting.Brightness = 3.2
	Lighting.Ambient = C(120, 130, 150)
	Lighting.OutdoorAmbient = C(170, 180, 200)
	Lighting.ColorShift_Top = C(255, 244, 222)
	Lighting.ColorShift_Bottom = C(0, 0, 0)
	Lighting.EnvironmentDiffuseScale = 1
	Lighting.EnvironmentSpecularScale = 1
	Lighting.GlobalShadows = true
	Lighting.ShadowSoftness = 0.25
	pcall(function()
		Lighting.Technology = Enum.Technology.Future
	end)
	local function get(class: string, name: string): Instance
		local i = Lighting:FindFirstChild(name) or Instance.new(class)
		i.Name = name
		i.Parent = Lighting
		return i
	end
	local atm = get("Atmosphere", "Atmosphere") :: Atmosphere
	atm.Density = 0.24
	atm.Offset = 0.2
	atm.Color = C(206, 236, 255)
	atm.Decay = C(120, 190, 235)
	atm.Glare = 0.15
	atm.Haze = 0.7
	local sky = get("Sky", "Sky") :: Sky
	sky.SunAngularSize = 13
	sky.MoonAngularSize = 8
	sky.StarCount = 0
	sky.CelestialBodiesShown = true
	local bloom = get("BloomEffect", "Bloom") :: BloomEffect
	bloom.Intensity = 0.45
	bloom.Size = 20
	bloom.Threshold = 2
	local rays = get("SunRaysEffect", "SunRays") :: SunRaysEffect
	rays.Intensity = 0.05
	rays.Spread = 0.6
	local cc = get("ColorCorrectionEffect", "Grade") :: ColorCorrectionEffect
	cc.Saturation = 0.26
	cc.Contrast = 0.08
	cc.Brightness = 0.02
end

----------------------------------------------------------------- plaza
local function buildPlaza()
	local plaza = Build.model("Plaza", map)
	local top = Config.BEACH_TOP
	-- checker grass tiles
	local tile = 24
	local x0, x1 = -W / 2, W / 2
	local z0, z1 = PLAZA_BACK, -12
	local ix = 0
	for x = x0, x1 - 0.01, tile do
		local iz = 0
		local w = math.min(tile, x1 - x)
		for z = z0, z1 - 0.01, tile do
			local d = math.min(tile, z1 - z)
			Build.studs(Build.part(plaza, Vector3.new(w, 4, d), CFrame.new(x + w / 2, top - 2, z + d / 2),
				((ix + iz) % 2 == 0) and GRASS or GRASS2, { Name = "Grass" }))
			iz += 1
		end
		ix += 1
	end
	-- sand strip and a ramp down onto the water
	Build.studs(Build.part(plaza, Vector3.new(W, 4, 12), CFrame.new(0, top - 2, -6), SAND, { Name = "Beach" }))
	local rampLen = Layout.RAMP_LEN
	local drop = top - Config.FLOOR_TOP
	Build.wedge(plaza, Vector3.new(W, drop, rampLen), CFrame.new(0, Config.FLOOR_TOP + drop / 2, rampLen / 2) * CFrame.Angles(0, math.pi, 0), SAND,
		{ Name = "Ramp" })
	-- back wall (side walls run the whole corridor, see buildLane)
	local bz = PLAZA_BACK - WALL_T / 2
	checkerWall(plaza, Vector3.new(-WALL_X - WALL_T / 2, 0, bz), Vector3.new(WALL_X + WALL_T / 2, 0, bz), WALL_BOTTOM, WALL_TOP, { Enum.NormalId.Back })
	Build.part(plaza, Vector3.new(W + 2 * WALL_T, 200, WALL_T), CFrame.new(0, WALL_TOP + 100, bz), C(255, 255, 255),
		{ Name = "Guard", Transparency = 1, CastShadow = false })
	-- a few palms against the back wall, clear of the buildings
	for i = 0, 6 do
		local x = -W / 2 + 14 + i * (W - 28) / 6
		local clear = math.abs(x) > 22 and math.abs(x - Layout.Board.X) > 34
		for _, b in Layout.Boards do
			clear = clear and math.abs(x - b.pos.X) > 12
		end
		for _, h in Layout.Huts do
			clear = clear and math.abs(x - h.pos.X) > 14
		end
		if clear then
			Props.palm(plaza, CFrame.new(x, top, PLAZA_BACK + 7), 13 + (i % 3) * 2)
		end
	end
	-- invisible spawn fallback
	if WORLD ~= 1 then
		return -- one spawn fallback, in Shark Beach
	end
	local spawn = Instance.new("SpawnLocation")
	spawn.Anchored = true
	spawn.Size = Vector3.new(12, 1, 12)
	spawn.CFrame = CFrame.new(0, top + 0.5, -56)
	spawn.Transparency = 1
	spawn.CanCollide = false
	spawn.Neutral = true
	spawn.Duration = 0
	for _, d in spawn:GetChildren() do
		if d:IsA("Decal") then
			d:Destroy() -- the spawn logo would still draw on the invisible pad
		end
	end
	spawn.Parent = map
end

----------------------------------------------------------------- shop huts
-- glowing step-on pad (no z-fighting: both discs sit above the ground)
local function stepPad(parent: Instance, at: Vector3, color: Color3, d: number): BasePart
	Build.cyl(parent, 0.2, d, CFrame.new(at + Vector3.new(0, 0.12, 0)), color, { Name = "PadRim", Material = Enum.Material.Neon, CanCollide = false, CastShadow = false })
	return Build.cyl(parent, 0.3, d - 2.4, CFrame.new(at + Vector3.new(0, 0.17, 0)), C(255, 255, 255),
		{ Name = "Pad", Transparency = 0.25, CanCollide = false, CastShadow = false })
end

local function awning(parent: Instance, base: CFrame, width: number, color: Color3, y: number)
	local n = math.floor(width / 2)
	local w = width / n
	for i = 0, n - 1 do
		local stripe = (i % 2 == 0) and color or C(255, 255, 255)
		Build.studs(Build.part(parent, Vector3.new(w, 0.8, 7), base * CFrame.new(-width / 2 + w * (i + 0.5), y, -0.7) * CFrame.Angles(math.rad(-12), 0, 0), stripe))
	end
end

-- what each stall shows on its counter
local function goods(m: Model, kind: string, top: CFrame)
	if kind == "Shop" then
		for i, c in { C(255, 70, 170), C(255, 205, 40), C(40, 170, 255) } do
			local s = 1.4 - (i - 1) * 0.2
			local box = top * CFrame.new(-3.6 + (i - 1) * 1.9, s / 2, 0) * CFrame.Angles(0, math.rad(i * 17), 0)
			studAll(Build.part(m, Vector3.new(s, s, s), box, c))
			Build.part(m, Vector3.new(s + 0.06, s + 0.06, 0.3), box, C(255, 255, 255))
			Build.part(m, Vector3.new(0.3, s + 0.06, s + 0.06), box, C(255, 255, 255))
		end
	elseif kind == "Index" then
		for _, side in { -1, 1 } do
			Build.part(m, Vector3.new(1.4, 0.15, 2), top * CFrame.new(-2.2 + side * 0.68, 0.25, 0) * CFrame.Angles(0, 0, math.rad(side * -10)), C(255, 250, 235))
		end
		Build.part(m, Vector3.new(3, 0.2, 2.2), top * CFrame.new(-2.2, 0.1, 0), C(200, 90, 40))
		Build.ball(m, 1.4, top * CFrame.new(2.6, 1.1, 0), C(60, 170, 255))
		Build.part(m, Vector3.new(0.9, 0.4, 0.9), top * CFrame.new(2.6, 0.2, 0), C(110, 80, 50))
	elseif kind == "Sell" then
		Build.part(m, Vector3.new(7, 0.4, 2), top * CFrame.new(0, 0.2, 0), C(235, 245, 255), { Name = "Ice" })
		for i, c in { C(255, 140, 40), C(70, 170, 255), C(255, 205, 40) } do
			local fish = top * CFrame.new(-2.3 + (i - 1) * 2.3, 0.7, 0) * CFrame.Angles(0, math.rad(80 + i * 12), 0)
			Build.ell(m, Vector3.new(0.7, 0.7, 1.6), fish, c)
			Build.wedge(m, Vector3.new(0.2, 0.6, 0.5), fish * CFrame.new(0, 0, 0.95), c)
		end
	end
end

-- Studded market stall: floor, back + side walls, counter with goods, the
-- keeper behind it, striped awning, a roof and a lit sign. Stepping on the
-- glowing pad in front opens the menu (client).
local function hut(kind: string, title: string, color: Color3, pos: Vector3)
	local m = Build.model(kind .. "Hut", map)
	local base = CFrame.new(pos)
	local wood, dark = C(170, 118, 70), C(120, 80, 50)
	local light = color:Lerp(C(255, 255, 255), 0.45)
	stepPad(m, pos + Vector3.new(0, 0, 9), color, 13)
	-- floor
	studAll(Build.part(m, Vector3.new(16, 1, 10.5), base * CFrame.new(0, 0.5, -2.75), wood, { Name = "Floor" }))
	-- back wall: color / light checker; side walls half deep
	for i = 0, 3 do
		for r = 0, 1 do
			studAll(Build.part(m, Vector3.new(4, 4.5, 1), base * CFrame.new(-6 + i * 4, 1 + 2.25 + r * 4.5, -7.5), ((i + r) % 2 == 0) and color or light))
		end
	end
	for _, sx in { -1, 1 } do
		studAll(Build.part(m, Vector3.new(1, 9, 4), base * CFrame.new(sx * 7.5, 5.5, -5), light))
		-- front posts (stop under the awning)
		studAll(Build.part(m, Vector3.new(1.2, 9.6, 1.2), base * CFrame.new(sx * 7.4, 5.8, 1.4), dark))
		-- sign posts on the roof
		Build.part(m, Vector3.new(0.6, 1.4, 0.6), base * CFrame.new(sx * 4.5, 13, -3.05), dark)
	end
	-- counter + colored top, goods on it
	studAll(Build.part(m, Vector3.new(12, 3.5, 2.4), base * CFrame.new(0, 2.75, 1), wood, { Name = "Counter" }))
	studAll(Build.part(m, Vector3.new(12.6, 0.6, 3), base * CFrame.new(0, 4.8, 1), color))
	goods(m, kind, base * CFrame.new(0, 5.1, 1))
	-- the keeper stands on a hidden step behind the counter, facing the pad
	Build.part(m, Vector3.new(5, 1.6, 2.4), base * CFrame.new(0, 1.8, -2.8), wood, { Name = "Step" })
	Npc.build(m, kind, CFrame.lookAt(pos + Vector3.new(0, 2.6, -2.8), pos + Vector3.new(0, 2.6, 9)))
	-- roof + striped awning
	studAll(Build.part(m, Vector3.new(17, 1, 7), base * CFrame.new(0, 11.9, -5), color, { Name = "Roof" }))
	awning(m, base, 16.4, color, 11.2)
	-- sign: dark board in a colored studded frame, with bulbs along the bottom
	local sign = Build.part(m, Vector3.new(12, 3, 0.6), base * CFrame.new(0, 14.6, -2.5), C(30, 32, 44), { Name = "Sign" })
	studAll(Build.part(m, Vector3.new(13, 4, 0.5), base * CFrame.new(0, 14.6, -3.05), color))
	surfaceText(sign, Enum.NormalId.Back, title, C(255, 255, 255))
	for i = 0, 5 do
		Build.ball(m, 0.45, base * CFrame.new(-5 + i * 2, 12.75, -2.2), (i % 2 == 0) and C(255, 240, 150) or C(255, 255, 255),
			{ Material = Enum.Material.Neon, CanCollide = false, CastShadow = false })
	end
	m:SetAttribute("Kind", kind)
	m:SetAttribute("PadX", pos.X)
	m:SetAttribute("PadZ", pos.Z + 9)
	CollectionService:AddTag(m, "ShopPad")
end

-- The Ride Shop: where rides are bought. The client shows your next ride
-- spinning on the pedestal; step on the pad to shop.
local function buildRideShop()
	local m = Build.model("RideShop", map)
	local c = Layout.RideShop
	local blue, white = C(40, 170, 255), C(255, 255, 255)
	-- floor
	studAll(Build.part(m, Vector3.new(34, 0.6, 24), CFrame.new(c.X, c.Y + 0.3, c.Z - 2), C(214, 160, 100), { Name = "Floor" }))
	-- back wall + side walls (checker, studs facing in)
	for i = 0, 5 do
		for r = 0, 1 do
			studAll(Build.part(m, Vector3.new(34 / 6, 7, 2), CFrame.new(c.X - 17 + 34 / 12 * (2 * i + 1), c.Y + 0.6 + 3.5 + r * 7, c.Z - 13), ((i + r) % 2 == 0) and WALL_A or WALL_B))
		end
	end
	for _, sx in { -1, 1 } do
		for i = 0, 1 do
			studAll(Build.part(m, Vector3.new(2, 14, 10), CFrame.new(c.X + sx * 16, c.Y + 7.6, c.Z - 7 + i * 10), (i % 2 == 0) and WALL_B or WALL_A))
		end
	end
	-- roof with a striped front awning
	studAll(Build.part(m, Vector3.new(36, 1.2, 26), CFrame.new(c.X, c.Y + 15.2, c.Z - 2), blue, { Name = "Roof" }))
	awning(m, CFrame.new(c.X, c.Y, c.Z + 14.5), 36, blue, 15.2)
	-- big sign on the roof
	local sign = Build.part(m, Vector3.new(28, 6, 1), CFrame.new(c.X, c.Y + 18.8, c.Z + 8), C(30, 32, 44), { Name = "Sign" })
	studAll(Build.part(m, Vector3.new(29.4, 7.4, 0.6), CFrame.new(c.X, c.Y + 18.8, c.Z + 7.2), C(255, 196, 30)))
	surfaceText(sign, Enum.NormalId.Back, "RIDE SHOP", white, Vector2.new(600, 130))
	-- pedestal (the next ride spins on top, placed by the client)
	studAll(Build.part(m, Vector3.new(8, 3, 8), CFrame.new(c.X, c.Y + 2.1, c.Z), C(255, 196, 30), { Name = "Pedestal" }))
	Build.cyl(m, 0.3, 9, CFrame.new(c.X, c.Y + 3.75, c.Z), C(255, 255, 255), { Material = Enum.Material.Neon, CanCollide = false, CastShadow = false })
	stepPad(m, Layout.RideShopPad, C(70, 230, 80), 15)
	-- the keeper, beside the pedestal, turned a little toward the pad
	-- (clear of the spinning showcase ride, which stays within 6 studs of center)
	local feet = Vector3.new(c.X + 11.5, c.Y + 0.6, c.Z + 4)
	Npc.build(m, "Rides", CFrame.lookAt(feet, Vector3.new(Layout.RideShopPad.X, feet.Y, Layout.RideShopPad.Z)))
	m:SetAttribute("Kind", "Rides")
	m:SetAttribute("PadX", Layout.RideShopPad.X)
	m:SetAttribute("PadZ", Layout.RideShopPad.Z)
	CollectionService:AddTag(m, "ShopPad")
end

----------------------------------------------------------------- leaderboard board
-- a studded top-10 board: posts, a colored frame, a dark screen of rows
local function buildBoard(key: string, title: string, color: Color3, at: Vector3)
	local m = Build.model("Leaderboard_" .. key, map)
	local cf = CFrame.new(at)
	for _, x in { -7, 7 } do
		studAll(Build.part(m, Vector3.new(1.6, 7, 1.6), cf * CFrame.new(x, 3.5, 0), color:Lerp(C(0, 0, 0), 0.2)))
	end
	studAll(Build.part(m, Vector3.new(19, 19, 2), cf * CFrame.new(0, 16.5, 0), color))
	local screen = Build.part(m, Vector3.new(16.4, 14, 0.4), cf * CFrame.new(0, 15.6, 1.1), C(24, 26, 38), { Name = "Screen" })
	local head = Build.part(m, Vector3.new(20, 4, 2.6), cf * CFrame.new(0, 27.6, 0), C(255, 196, 30))
	studAll(head)
	surfaceText(head, Enum.NormalId.Back, title, C(255, 255, 255), Vector2.new(500, 100))
	local sg = Instance.new("SurfaceGui")
	sg.Face = Enum.NormalId.Back
	sg.CanvasSize = Vector2.new(480, 410)
	sg.LightInfluence = 0
	sg.Parent = screen
	local list = Instance.new("UIListLayout")
	list.Padding = UDim.new(0, 4)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = sg
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 8)
	pad.PaddingLeft = UDim.new(0, 10)
	pad.PaddingRight = UDim.new(0, 10)
	pad.Parent = sg
	local medal = { C(255, 196, 30), C(200, 210, 225), C(215, 140, 80) }
	for i = 1, 10 do
		local row = Instance.new("Frame")
		row.Name = "Row" .. i
		row.LayoutOrder = i
		row.Size = UDim2.new(1, 0, 0, 35)
		row.BackgroundColor3 = i % 2 == 0 and C(255, 255, 255) or C(232, 240, 255)
		row.Parent = sg
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0, 6)
		c.Parent = row
		local function cell(name: string, x: number, w: number, align: Enum.TextXAlignment, tc: Color3)
			local t = Instance.new("TextLabel")
			t.Name = name
			t.BackgroundTransparency = 1
			t.Size = UDim2.new(w, 0, 1, -6)
			t.Position = UDim2.new(x, 0, 0, 3)
			t.Font = Enum.Font.FredokaOne
			t.TextScaled = true
			t.TextXAlignment = align
			t.TextColor3 = tc
			t.Text = ""
			t.Parent = row
			if name == "Rank" then
				local st = Instance.new("UIStroke")
				st.Thickness = 2
				st.Color = C(22, 22, 34)
				st.Parent = t
			end
		end
		cell("Rank", 0.02, 0.1, Enum.TextXAlignment.Center, medal[i] or C(120, 130, 150))
		cell("Name", 0.14, 0.52, Enum.TextXAlignment.Left, C(22, 22, 34))
		cell("Value", 0.66, 0.32, Enum.TextXAlignment.Right, color:Lerp(C(0, 0, 0), 0.15))
	end
	World.boards[key] = World.boards[key] or {}
	table.insert(World.boards[key], sg)
end

local function buildBoards()
	for _, b in Layout.Boards do
		buildBoard(b.key, b.title, b.color, b.pos)
	end
end

----------------------------------------------------------------- lane
-- Terraced grass banks beyond the walls (like the classic stud obbies and
-- the thumbnail): a first grass terrace on top of the lane wall, a second
-- checker step, a higher terrace, voxel trees on both, palms near the start
-- and darker trees out deep.
local TERRACE1 = 34 -- first terrace runs from the wall to W/2 + 34
local TERRACE2 = 100 -- second terrace out to W/2 + 100
local BANK_W = TERRACE2
local STEP_H = 12 -- the second terrace is this much higher

local function grassRun(parent: Instance, side: number, inner: number, outer: number, top: number)
	local z = PLAZA_BACK - WALL_T
	while z < OCEAN + WALL_T do
		local len = math.min(400, OCEAN + WALL_T - z)
		local grass = Build.part(parent, Vector3.new(outer - inner, 6, len), CFrame.new(side * (inner + outer) / 2, top - 3, z + len / 2), GRASS, { Name = "Bank" })
		Build.studs(grass, { Enum.NormalId.Top })
		z += len
	end
end

local function treeRow(parent: Instance, rng: Random, side: number, x: number, y: number, step: number, big: number)
	local z = PLAZA_BACK + rng:NextNumber(0, step)
	while z < OCEAN do
		local zone = Config.zoneAt(z, WORLD)
		local idx = zone and zone.index or 1
		local pos = Vector3.new(side * (x + rng:NextNumber(-4, 4)), y, z)
		local scale = rng:NextNumber(0.85, 1.25) * big
		if idx <= 2 and rng:NextNumber() < 0.3 then
			Props.palm(parent, CFrame.new(pos), rng:NextNumber(12, 17) * big)
		elseif idx >= 5 then
			Props.blockTree(parent, pos, scale, C(38, 92, 78), C(52, 118, 96)) -- deep water: dark teal
		elseif idx >= 3 then
			Props.blockTree(parent, pos, scale, C(46, 140, 56), C(64, 166, 66))
		else
			Props.blockTree(parent, pos, scale)
		end
		z += step + rng:NextNumber(-5, 5)
	end
end

local function buildBanks()
	local banks = Build.model("Banks", map)
	local trees = Build.model("Trees", map)
	local rng = Random.new(7)
	local top1 = WALL_TOP + 2
	local stepX = W / 2 + TERRACE1 + WALL_T / 2
	local top2 = top1 + STEP_H
	for _, side in { -1, 1 } do
		-- terrace 1, the checker step up, terrace 2
		grassRun(banks, side, WALL_X + (WALL_T + 1.6) / 2, W / 2 + TERRACE1, top1)
		checkerWall(banks, Vector3.new(side * stepX, 0, PLAZA_BACK - WALL_T), Vector3.new(side * stepX, 0, OCEAN + WALL_T),
			top1 - 4, top2 - 2, { side < 0 and Enum.NormalId.Right or Enum.NormalId.Left })
		grassRun(banks, side, stepX + (WALL_T + 1.6) / 2, W / 2 + TERRACE2, top2)
		treeRow(trees, rng, side, W / 2 + 20, top1, 26, 0.9)
		treeRow(trees, rng, side, W / 2 + 58, top2, 32, 1.15)
		treeRow(trees, rng, side, W / 2 + 84, top2, 42, 1.3)
	end
	Build.ghost(trees)
end

local function buildLane()
	local lane = Build.model("Lane", map)
	-- hidden floor players ride on, one slab per zone (parts max out at 2048)
	for _, zone in ZONES do
		Build.part(lane, Vector3.new(W + 2, 2, zone.length + 0.5),
			CFrame.new(0, Config.FLOOR_TOP - 1, zone.zStart + zone.length / 2), C(255, 255, 255),
			{ Name = "WaterFloor", Transparency = 1, CastShadow = false })
	end
	-- the corridor walls run from the back of the plaza to the end of the ocean
	local walls = Build.model("LaneWalls", map)
	local endZ = OCEAN + WALL_T / 2
	for _, side in { -1, 1 } do
		checkerWall(walls, Vector3.new(side * WALL_X, 0, PLAZA_BACK), Vector3.new(side * WALL_X, 0, OCEAN), WALL_BOTTOM, WALL_TOP,
			{ side < 0 and Enum.NormalId.Right or Enum.NormalId.Left }, 0.8, 0.8)
		local z = PLAZA_BACK
		while z < OCEAN do
			local len = math.min(2000, OCEAN - z)
			Build.part(lane, Vector3.new(WALL_T, 200, len), CFrame.new(side * WALL_X, WALL_TOP + 100, z + len / 2), C(255, 255, 255),
				{ Name = "Guard", Transparency = 1, CastShadow = false })
			z += len
		end
	end
	checkerWall(walls, Vector3.new(-WALL_X - WALL_T / 2, 0, endZ), Vector3.new(WALL_X + WALL_T / 2, 0, endZ), WALL_BOTTOM, WALL_TOP, { Enum.NormalId.Front })
	buildBanks()
end

----------------------------------------------------------------- gates
-- a checkered arch with a lock sign; the glowing wall is visual only (the
-- server enforces gates, the client fades unlocked ones)
local function buildGates()
	local folder = Instance.new("Folder")
	folder.Name = "Gates"
	folder.Parent = map
	for _, zone in ZONES do
		if zone.gate > 0 then
			-- no walls: just the zone's sign. Ride as far as you dare; under the
			-- recommended speed, the zone's shark hunts you nonstop (Sharks)
			local g = Build.model("Gate_" .. zone.id, folder)
			local z = zone.zStart
			g:SetAttribute("Gate", zone.gate)
			g:SetAttribute("ZoneName", zone.name)
			-- the sign: zone name + what it takes to get in, on two posts
			local tint = zone.water:Lerp(C(255, 255, 255), 0.25)
			local sy = WALL_TOP + 9 -- sign centre, above the shimmer
			for _, x in { -14, 14 } do
				Build.studs(Build.part(g, Vector3.new(1.4, 9, 1.4), CFrame.new(x, sy - 8.5, z), C(250, 250, 255), { CanCollide = false }))
			end
			local board = Build.part(g, Vector3.new(44, 11, 1.2), CFrame.new(0, sy, z), C(28, 32, 58), { Name = "Banner", CanCollide = false })
			Build.studs(Build.part(g, Vector3.new(46, 1.2, 1.8), CFrame.new(0, sy + 6.1, z), tint, { CanCollide = false }))
			Build.studs(Build.part(g, Vector3.new(46, 1.2, 1.8), CFrame.new(0, sy - 6.1, z), tint, { CanCollide = false }))
			for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
				local name = surfaceText(board, face, ("%s"):format(zone.name), C(255, 255, 255), Vector2.new(600, 150))
				name.Size = UDim2.fromScale(0.94, 0.56)
				name.Position = UDim2.fromScale(0.03, 0.06)
				local need = name:Clone()
				need.Name = "Sub"
				need.Text = ("Recommended: %s speed"):format(tostring(zone.gate))
				need.TextColor3 = C(255, 214, 60)
				need.Size = UDim2.fromScale(0.9, 0.3)
				need.Position = UDim2.fromScale(0.05, 0.64)
				need.Parent = name.Parent
			end
			-- a buoy under each sign post marks the line
			for _, x in { -14, 14 } do
				Props.buoy(g, Vector3.new(x, 0, z), C(255, 196, 40))
			end
			CollectionService:AddTag(g, "Gate")
		end
	end
end

----------------------------------------------------------------- islands
local function buildIslands()
	local folder = Instance.new("Folder")
	folder.Name = "Islands"
	folder.Parent = map
	for _, island in Layout.Islands do
		local m = Props.island(folder, island.pos, island.radius, island.palm)
		CollectionService:AddTag(m, "Island")
	end
end

----------------------------------------------------------------- decorations
-- light touch: a few things per zone so each one reads differently
local function buildDecor()
	local deco = Build.model("Decor", map)
	local rng = Random.new(42)
	local function laneXZ(zone: Config.Zone): (number, number)
		return rng:NextNumber(-W / 2 + 10, W / 2 - 10), rng:NextNumber(zone.zStart + 10, zone.zEnd - 10)
	end
	for _, zone in ZONES do
		local floorY = -zone.depth
		if zone.id == "Lagoon" then
			for _ = 1, 5 do
				local x, z = laneXZ(zone)
				Props.beachBall(deco, Vector3.new(x, 0.9, z))
			end
			for _ = 1, 10 do
				local x, z = laneXZ(zone)
				Props.coral(deco, CFrame.new(x, floorY, z), rng)
			end
		elseif zone.id == "Reef" then
			for _ = 1, 36 do
				local x, z = laneXZ(zone)
				Props.coral(deco, CFrame.new(x, floorY, z) * CFrame.Angles(0, rng:NextNumber(0, 6), 0), rng)
			end
		elseif zone.id == "Kelp" then
			for _ = 1, 50 do
				local x, z = laneXZ(zone)
				Props.kelp(deco, CFrame.new(x, floorY, z), zone.depth - rng:NextNumber(0.5, 4), rng)
			end
		elseif zone.id == "Shipwreck" then
			for i = 1, 3 do
				local z = zone.zStart + zone.length * (i / 4)
				local x = (i % 2 == 0 and -1 or 1) * rng:NextNumber(50, 100)
				Props.shipwreck(deco, CFrame.new(x, -2, z) * CFrame.Angles(0, rng:NextNumber(0, 6), 0))
			end
			for _ = 1, 10 do
				local x, z = laneXZ(zone)
				Props.crate(deco, Vector3.new(x, 0.4, z), rng)
			end
		elseif zone.id == "Deep" then
			for _ = 1, 24 do
				local x, z = laneXZ(zone)
				Props.jellyfish(deco, Vector3.new(x, -3.5, z), rng)
			end
		elseif zone.id == "Abyss" then
			for _ = 1, 12 do
				local x, z = laneXZ(zone)
				Props.spikeRock(deco, CFrame.new(x, 0, z) * CFrame.Angles(0, rng:NextNumber(0, 6), 0), rng:NextNumber(10, 22))
			end
			Props.jawArch(deco, CFrame.new(0, -2, zone.zEnd - 30), W * 0.8)
		elseif zone.id == "Soda" then
			for _ = 1, 8 do
				local x, z = laneXZ(zone)
				Props.beachBall(deco, Vector3.new(x, 0.9, z))
			end
			for _ = 1, 14 do
				local x, z = laneXZ(zone)
				Props.gumdrop(deco, CFrame.new(x, floorY, z), rng:NextNumber(3, 5), rng)
			end
		elseif zone.id == "Gumdrop" then
			for _ = 1, 40 do
				local x, z = laneXZ(zone)
				Props.gumdrop(deco, CFrame.new(x, floorY, z), rng:NextNumber(4, 9), rng)
			end
		elseif zone.id == "Lolly" then
			for _ = 1, 30 do
				local x, z = laneXZ(zone)
				Props.lollipop(deco, CFrame.new(x, floorY, z), zone.depth - rng:NextNumber(3, 7), rng)
			end
		elseif zone.id == "Cane" then
			for _ = 1, 26 do
				local x, z = laneXZ(zone)
				Props.candyCane(deco, CFrame.new(x, floorY, z) * CFrame.Angles(0, rng:NextNumber(0, 6), 0), zone.depth - rng:NextNumber(4, 9))
			end
		elseif zone.id == "Choco" then
			for _ = 1, 20 do
				local x, z = laneXZ(zone)
				Props.chocoBar(deco, CFrame.new(x, floorY, z) * CFrame.Angles(0, rng:NextNumber(0, 6), 0), rng:NextNumber(10, 20))
			end
		elseif zone.id == "Sugar" then
			for _ = 1, 14 do
				local x, z = laneXZ(zone)
				Props.spikeRock(deco, CFrame.new(x, 0, z) * CFrame.Angles(0, rng:NextNumber(0, 6), 0), rng:NextNumber(10, 22))
			end
			for _ = 1, 20 do
				local x, z = laneXZ(zone)
				Props.lollipop(deco, CFrame.new(x, floorY, z), rng:NextNumber(20, 40), rng)
			end
		elseif zone.id == "Frozen" then
			for _ = 1, 30 do
				local x, z = laneXZ(zone)
				Props.iceCrystal(deco, CFrame.new(x, floorY, z), rng:NextNumber(6, 14), rng)
			end
			for _ = 1, 10 do
				for _, side in { -1, 1 } do
					local x = side * rng:NextNumber(W / 2 + BANK_W + 30, W / 2 + BANK_W + 160)
					Props.iceberg(deco, CFrame.new(x, 0, rng:NextNumber(zone.zStart, zone.zEnd)), rng:NextNumber(18, 40), rng)
				end
			end
		elseif zone.id == "Volcano" then
			for _ = 1, 22 do
				local x, z = laneXZ(zone)
				Props.vent(deco, CFrame.new(x, floorY, z), rng:NextNumber(8, 16))
			end
			for _ = 1, 4 do
				for _, side in { -1, 1 } do
					local x = side * rng:NextNumber(W / 2 + BANK_W + 60, W / 2 + BANK_W + 200)
					Props.vent(deco, CFrame.new(x, -12, rng:NextNumber(zone.zStart, zone.zEnd)), rng:NextNumber(40, 70))
				end
			end
		elseif zone.id == "Atlantis" then
			for _ = 1, 40 do
				local x, z = laneXZ(zone)
				Props.column(deco, CFrame.new(x, floorY, z), rng:NextNumber(14, zone.depth - 4), rng:NextNumber() < 0.4)
			end
			for i = 1, 6 do
				for _, side in { -1, 1 } do
					local x = side * (W / 2 + BANK_W + 40 + (i % 3) * 30)
					Props.column(deco, CFrame.new(x, -10, zone.zStart + zone.length * i / 7), rng:NextNumber(40, 60), i % 2 == 0)
				end
			end
		end
		-- scenery islands outside the corridor
		for _ = 1, math.floor(zone.length / 200) do
			for _, side in { -1, 1 } do
				local x = side * rng:NextNumber(W / 2 + BANK_W + 40, W / 2 + BANK_W + 220)
				local z = rng:NextNumber(zone.zStart, zone.zEnd)
				Props.island(deco, Vector3.new(x, 0, z), rng:NextNumber(14, 28), true)
			end
		end
	end
	Build.ghost(deco)
end

----------------------------------------------------------------- plots
local function buildPlot(i: number, cf: CFrame): Plot
	local m = Build.model("Plot" .. i, map)
	local wood, dark = C(214, 160, 100), C(160, 108, 64)
	-- studded deck with a darker trim
	studAll(Build.part(m, Vector3.new(30, 1, 30), cf * CFrame.new(0, 0, -1), wood, { Name = "Deck" }))
	for _, s in { { Vector3.new(30.4, 1.2, 1), Vector3.new(0, 0.1, -16) }, { Vector3.new(30.4, 1.2, 1), Vector3.new(0, 0.1, 14) },
		{ Vector3.new(1, 1.2, 28.4), Vector3.new(-15, 0.1, -1) }, { Vector3.new(1, 1.2, 28.4), Vector3.new(15, 0.1, -1) } } do
		Build.studs(Build.part(m, s[1], cf * CFrame.new(s[2]), dark))
	end
	-- the showcase tank: Active creatures swim inside (clients move them
	-- within the invisible TankInterior box)
	local tcf = CFrame.new(Layout.tankPos(cf)) * cf.Rotation * CFrame.new(0, 0.5, 0)
	local tk = Build.model("Tank", m) -- the glass box (what the View Tank prompt outlines)
	local frame = C(40, 140, 240)
	studAll(Build.part(tk, Vector3.new(23, 1, 9), tcf * CFrame.new(0, 0.5, 0), frame, { Name = "TankBase" }))
	Build.studs(Build.part(tk, Vector3.new(21.6, 0.6, 7.6), tcf * CFrame.new(0, 1.3, 0), SAND))
	local glass = C(210, 245, 255)
	for _, z in { -3.9, 3.9 } do
		Build.part(tk, Vector3.new(21.6, 8, 0.2), tcf * CFrame.new(0, 5.4, z), glass, { Material = Enum.Material.Glass, Transparency = 0.8 })
	end
	for _, x in { -10.9, 10.9 } do
		Build.part(tk, Vector3.new(0.2, 8, 7.6), tcf * CFrame.new(x, 5.4, 0), glass, { Material = Enum.Material.Glass, Transparency = 0.8 })
	end
	for _, x in { -11.1, 11.1 } do
		for _, z in { -4.1, 4.1 } do
			studAll(Build.part(tk, Vector3.new(0.8, 8, 0.8), tcf * CFrame.new(x, 5.4, z), frame))
		end
	end
	for _, z in { -4.1, 4.1 } do
		studAll(Build.part(tk, Vector3.new(23, 0.8, 0.8), tcf * CFrame.new(0, 9.8, z), frame))
	end
	for _, x in { -11.1, 11.1 } do
		studAll(Build.part(tk, Vector3.new(0.8, 0.8, 7.4), tcf * CFrame.new(x, 9.8, 0), frame))
	end
	-- the raid shield (Raids.luau shows it while the owner is home)
	Build.part(m, Vector3.new(25, 11.5, 11), tcf * CFrame.new(0, 5.2, 0), C(90, 255, 140), { Name = "Guard", Material = Enum.Material.ForceField,
		Transparency = 1, CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false })
	local water = Build.part(tk, Vector3.new(21.4, 7.2, 7.4), tcf * CFrame.new(0, 5.2, 0), C(70, 200, 240),
		{ Name = "TankWater", Transparency = 0.78, CanCollide = false, CanQuery = false, CastShadow = false })
	local light = Instance.new("PointLight")
	light.Color = C(120, 230, 255)
	light.Brightness = 1.2
	light.Range = 16
	light.Parent = water
	-- a little decor on the sand
	local rng = Random.new(i * 31)
	for k = 1, 4 do
		local x = -8.5 + (k - 1) * 5.6 + rng:NextNumber(-1, 1)
		Build.studs(Build.part(tk, Vector3.new(1.4, 0.9, 1.2), tcf * CFrame.new(x, 2.05, rng:NextNumber(-2.5, 2.5)), C(150, 156, 170)))
		local kelpH = rng:NextNumber(2.5, 4.5)
		Build.part(tk, Vector3.new(0.4, kelpH, 0.4), tcf * CFrame.new(x + 1.4, 1.6 + kelpH / 2, rng:NextNumber(-2.5, 2.5)), C(60, 170, 80))
	end
	local interior = Build.part(m, Vector3.new(19, 5.6, 5.6), tcf * CFrame.new(0, 5, 0), C(255, 255, 255),
		{ Name = "TankInterior", Transparency = 1, CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false })
	interior:SetAttribute("Plot", i)
	local slots = Instance.new("Folder")
	slots.Name = "Slots"
	slots.Parent = m
	-- "View Tank" on the back of the tank (the plaza side): a close look at
	-- everyone swimming, with names and weights on hover / tap (TankView.luau)
	local viewSpot = Build.part(tk, Vector3.new(4, 4, 0.2), tcf * CFrame.new(0, 4.4, 4.5), C(255, 255, 255),
		{ Name = "ViewSpot", Transparency = 1, CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false })
	local view = Instance.new("ProximityPrompt")
	view.Name = "ViewTank"
	view.ActionText = "View Tank"
	view.ObjectText = "Empty Dock"
	view.HoldDuration = 0
	view.MaxActivationDistance = 11
	view.RequiresLineOfSight = false
	view.Style = Enum.ProximityPromptStyle.Custom
	view.KeyboardKeyCode = Enum.KeyCode.E -- E for everything
	view:SetAttribute("Plot", i)
	view.Parent = viewSpot
	-- RAID: other players hold F here while the owner is out at sea (Raids.luau;
	-- the client only shows it on docks that aren't yours)
	local raid = Instance.new("ProximityPrompt")
	raid.Name = "RaidTank"
	raid.ActionText = "Raid"
	raid.ObjectText = "Tank"
	raid.HoldDuration = 1
	raid.MaxActivationDistance = 12
	raid.RequiresLineOfSight = false
	raid.Style = Enum.ProximityPromptStyle.Custom
	raid.KeyboardKeyCode = Enum.KeyCode.F
	raid.Enabled = false
	raid:SetAttribute("Plot", i)
	-- its own spot at the tank's side, so the two prompts never overlap
	raid.Parent = Build.part(tk, Vector3.new(2, 2, 2), tcf * CFrame.new(6.5, 2.4, 2.5), C(255, 255, 255),
		{ Name = "RaidSpot", Transparency = 1, CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false })
	-- sign over the tank: owner, what it earns, what it earns per day offline
	local signAnchor = Build.part(m, Vector3.new(0.2, 0.2, 0.2), tcf * CFrame.new(0, 13.2, 0), C(255, 255, 255),
		{ Name = "TankSign", Transparency = 1, CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false })
	local sign = label(signAnchor, Vector2.new(12, 2.3), Vector3.new(0, 2.2, 0), "Empty Dock", nil, 140)
	local tankIncome = label(signAnchor, Vector2.new(12, 1.9), Vector3.new(0, 0.1, 0), "", C(130, 255, 90), 120)
	local tankOffline = label(signAnchor, Vector2.new(11, 1.5), Vector3.new(0, -1.6, 0), "", C(170, 220, 255), 80)
	-- collect pad
	local pcf = CFrame.new(Layout.padPos(cf)) * CFrame.new(0, 0.55, 0)
	Build.cyl(m, 0.2, 7.4, pcf * CFrame.new(0, -0.03, 0), C(90, 240, 90), { Material = Enum.Material.Neon, Name = "PadRim", CastShadow = false })
	local pad = Build.cyl(m, 0.4, 6.2, pcf * CFrame.new(0, 0.1, 0), C(50, 190, 70), { Name = "Pad" })
	-- the label hangs off its own invisible anchor above the pad and draws on
	-- top, so the deck and pad can never cover it
	local anchor = Build.part(m, Vector3.new(0.2, 0.2, 0.2), CFrame.new(pad.Position + Vector3.new(0, 4.2, 0)), C(255, 255, 255),
		{ Name = "PadSign", Transparency = 1, CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false })
	local padLabel = label(anchor, Vector2.new(7, 2.2), Vector3.zero, "$0", C(140, 255, 90), 90);
	(padLabel.Parent :: BillboardGui).AlwaysOnTop = true
	return {
		index = i, cf = cf, model = m, padLabel = padLabel, signLabel = sign, slots = slots, owner = nil,
		tankIncome = tankIncome, tankOffline = tankOffline, viewPrompt = view,
	}
end

----------------------------------------------------------------- group chest
-- the CLAIM chest: a red studded chest with gold trim on a glowing ring; the
-- prompt asks the server (Rewards.luau), the client updates the sign
local function buildGroupChest()
	local m = Build.model("GroupChest", map)
	local base = CFrame.new(Layout.GroupChest) * CFrame.Angles(0, math.pi, 0) -- faces the docks
	local red, gold = C(220, 36, 44), C(255, 196, 40)
	Build.cyl(m, 0.2, 13, base * CFrame.new(0, 0.12, 0), C(255, 230, 80), { Material = Enum.Material.Neon, Transparency = 0.35, CastShadow = false, CanCollide = false })
	Build.cyl(m, 0.22, 10.5, base * CFrame.new(0, 0.13, 0), C(255, 248, 200), { Transparency = 0.2, CastShadow = false, CanCollide = false })
	local box = studAll(Build.part(m, Vector3.new(7, 3.6, 4.6), base * CFrame.new(0, 2.0, 0), red, { Name = "Box" }))
	studAll(Build.part(m, Vector3.new(7.2, 1.6, 4.8), base * CFrame.new(0, 4.6, 0), red, { Name = "Lid" }))
	for _, x in { -2.6, 2.6 } do
		Build.studs(Build.part(m, Vector3.new(0.8, 5.5, 4.95), base * CFrame.new(x, 2.95, 0), gold))
	end
	Build.studs(Build.part(m, Vector3.new(7.4, 0.5, 5.0), base * CFrame.new(0, 3.85, 0), gold))
	Build.part(m, Vector3.new(1.0, 1.2, 0.3), base * CFrame.new(0, 3.3, -2.45), C(40, 40, 50), { Name = "Lock" })
	m.PrimaryPart = box
	-- sign: rainbow CLAIM + what it takes (the client fills in the timer)
	local anchor = Build.part(m, Vector3.new(0.2, 0.2, 0.2), base * CFrame.new(0, 10.5, 0), C(255, 255, 255),
		{ Name = "Sign", Transparency = 1, CanCollide = false, CanQuery = false, CanTouch = false })
	local title = label(anchor, Vector2.new(16, 3.4), Vector3.new(0, 1.2, 0), "CLAIM", C(255, 255, 255), 140)
	title.Name = "Title"
	title.Font = Enum.Font.LuckiestGuy
	local rainbow = Instance.new("UIGradient")
	local keys = {}
	for i = 0, 6 do
		table.insert(keys, ColorSequenceKeypoint.new(i / 6, Color3.fromHSV(i / 6, 0.85, 1)))
	end
	rainbow.Color = ColorSequence.new(keys)
	rainbow.Parent = title
	local sub = label(anchor, Vector2.new(16, 1.6), Vector3.new(0, -1.3, 0), Config.GroupId ~= 0 and "Join Group & Like To Claim!" or "Like The Game To Claim!", C(255, 214, 60), 140)
	sub.Name = "Sub"
	-- prompt (E, like everything)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "GroupChest"
	prompt.ActionText = "Claim"
	prompt.ObjectText = "Group Chest"
	prompt.HoldDuration = 0.25
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Style = Enum.ProximityPromptStyle.Custom
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.Parent = box
end

----------------------------------------------------------------- boost rings
local function buildRings()
	local folder = Build.model("Rings", map)
	for i, p in Layout.Rings do
		local m = Build.model("Ring" .. i, folder)
		local cf = CFrame.new(p) * CFrame.Angles(math.pi / 2, 0, 0) -- stand the hoop up, facing the lane
		Build.ring(m, Layout.RING_RADIUS, 0.9, cf, C(255, 210, 50), 14, C(255, 255, 255))
		for _, part in m:GetChildren() do
			if part:IsA("BasePart") then
				part.Material = Enum.Material.Neon
			end
		end
		m:SetAttribute("Index", i)
	end
	Build.ghost(folder)
end

----------------------------------------------------------------- event board
-- The plaza board for Megalodon Hour and the next update: the client fills
-- the countdowns (client Countdown.luau)
local function buildEventBoard()
	local m = Build.model("EventBoard", map)
	local base = CFrame.new(Layout.EventBoard)
	local red, dark = C(220, 50, 70), C(26, 28, 44)
	for _, x in { -8, 8 } do
		studAll(Build.part(m, Vector3.new(1.6, 9, 1.6), base * CFrame.new(x, 4.5, 0), C(60, 64, 90)))
	end
	studAll(Build.part(m, Vector3.new(19, 11, 1.6), base * CFrame.new(0, 14, 0), red))
	local screen = Build.part(m, Vector3.new(17, 9, 0.4), base * CFrame.new(0, 14, 0.9), dark, { Name = "Screen" })
	local sg = Instance.new("SurfaceGui")
	sg.Name = "Countdown"
	sg.Face = Enum.NormalId.Back
	sg.CanvasSize = Vector2.new(560, 300)
	sg.LightInfluence = 0
	sg.Parent = screen
	local function line(name: string, y: number, h: number, text: string, color: Color3)
		local t = Instance.new("TextLabel")
		t.Name = name
		t.BackgroundTransparency = 1
		t.Size = UDim2.new(0.94, 0, 0, h)
		t.Position = UDim2.new(0.03, 0, 0, y)
		t.Font = Enum.Font.FredokaOne
		t.TextScaled = true
		t.TextColor3 = color
		t.Text = text
		t.Parent = sg
		local s = Instance.new("UIStroke")
		s.Thickness = 3
		s.Color = C(10, 10, 20)
		s.Parent = t
	end
	line("Title", 6, 56, Config.Event.name, C(255, 90, 100))
	line("When", 64, 28, "Every Saturday · 3 PM ET", C(200, 210, 230))
	line("Time", 96, 58, "", C(255, 255, 255))
	line("Limited", 160, 40, "", C(255, 255, 255)) -- this week's limited catch (client Countdown)
	line("Update", 206, 38, "", C(255, 210, 60))
	local goal = Config.LikeGoal
	line("Likes", 250, 36, goal > 0 and ("New code at %s likes"):format(goal >= 1000 and (goal / 1000 .. "K") or tostring(goal)) or "",
		C(120, 230, 255))
end

----------------------------------------------------------------- portal
-- A studded arch in the next world's color with a swirling force field;
-- its prompt asks the server to teleport (Game actions.portal). The client
-- shows locked / open on the sign (Portal.luau).
local function buildPortal()
	local other = Config.Worlds[WORLD == 1 and 2 or 1]
	local m = Build.model("Portal", map)
	local base = CFrame.new(Layout.Portal) * CFrame.Angles(0, Layout.PORTAL_YAW, 0)
	local col, trim = other.color, other.color:Lerp(C(255, 255, 255), 0.5)
	studAll(Build.part(m, Vector3.new(18, 1, 8), base * CFrame.new(0, 0.5, 0), C(70, 74, 100), { Name = "Base" }))
	for _, sx in { -1, 1 } do
		studAll(Build.part(m, Vector3.new(3, 15, 3), base * CFrame.new(sx * 7.5, 8.5, 0), col))
		studAll(Build.part(m, Vector3.new(3.6, 1.2, 3.6), base * CFrame.new(sx * 7.5, 1.6, 0), trim))
		studAll(Build.part(m, Vector3.new(3.6, 1.2, 3.6), base * CFrame.new(sx * 7.5, 15.4, 0), trim))
	end
	studAll(Build.part(m, Vector3.new(19, 3, 3.4), base * CFrame.new(0, 17.5, 0), col, { Name = "Top" }))
	-- the gateway itself
	local field = Build.part(m, Vector3.new(12, 14, 0.6), base * CFrame.new(0, 8, 0), col:Lerp(C(255, 255, 255), 0.25), {
		Name = "Field", Material = Enum.Material.ForceField, Transparency = 0.05, CanCollide = false, CanQuery = false, CastShadow = false,
	})
	local light = Instance.new("PointLight")
	light.Color = col
	light.Range = 18
	light.Brightness = 2
	light.Parent = field
	-- sign: where it goes (the client adds the lock line)
	local anchor = Build.part(m, Vector3.new(0.2, 0.2, 0.2), base * CFrame.new(0, 21.5, 0), C(255, 255, 255),
		{ Name = "Sign", Transparency = 1, CanCollide = false, CanQuery = false, CanTouch = false })
	local title = label(anchor, Vector2.new(18, 3.6), Vector3.new(0, 1.2, 0), other.name:upper(), C(255, 255, 255), 160)
	title.Name = "Title"
	title.Font = Enum.Font.LuckiestGuy
	local sub = label(anchor, Vector2.new(18, 1.8), Vector3.new(0, -1.4, 0), "", trim, 160)
	sub.Name = "Sub"
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "Portal"
	prompt.ActionText = "Enter"
	prompt.ObjectText = other.name
	prompt.HoldDuration = 0.4
	prompt.MaxActivationDistance = 14
	prompt.RequiresLineOfSight = false
	prompt.Style = Enum.ProximityPromptStyle.Custom
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.Parent = field
	m:SetAttribute("Target", other.id)
end

-- Builds everything. Safe to run again (and from the Studio command bar to
-- preview the map in edit mode): the old map is removed first.
-- every world's plots, by world then dock number (World.Plots = Shark Beach's)
World.WorldPlots = {} :: { { Plot } }

-- Runs every builder once per world. A world's plaza / lane / decor are
-- built at Shark Beach's coordinates, then the whole model slides WORLD_GAP
-- studs over; terrain, docks, islands and rings are placed directly.
function World.build()
	local old = Workspace:FindFirstChild("Map")
	if old then
		old:Destroy()
	end
	table.clear(World.Plots)
	table.clear(World.WorldPlots)
	table.clear(World.boards)
	local root = Instance.new("Folder")
	root.Name = "Map"
	root.Parent = Workspace
	-- clear the template baseplate so it doesn't fight the plaza
	for _, name in { "Baseplate", "SpawnLocation" } do
		local part = Workspace:FindFirstChild(name)
		if part and part:IsA("BasePart") then
			part:Destroy()
		end
	end
	buildLighting()
	for w in Config.Worlds do
		WORLD, OX = w, Config.originX(w)
		ZONES, OCEAN = Config.worldZones(w), Config.oceanEnd(w)
		-- Shark Beach builds straight into Map (the client looks things up
		-- there); other worlds into Map/World<n>
		local holder: Instance = root
		if w > 1 then
			local m = Instance.new("Model")
			m.Name = "World" .. w
			m.Parent = root
			holder = m
		end
		map = holder
		buildPlaza()
		buildRideShop()
		for _, h in Layout.Huts do
			hut(h.kind, h.title, h.color, h.pos)
		end
		buildBoards()
		buildGroupChest()
		buildPortal()
		buildEventBoard()
		buildLane()
		buildGates()
		buildDecor()
		if holder:IsA("Model") then
			holder:TranslateBy(Vector3.new(OX, 0, 0))
			-- step-on pads remember where they are: move those numbers too
			for _, d in holder:GetDescendants() do
				local px = d:GetAttribute("PadX")
				if typeof(px) == "number" then
					d:SetAttribute("PadX", px + OX)
				end
			end
		end
		buildTerrain()
		-- placed directly (already in world coordinates)
		local plots = {}
		for i, cf in Layout.WorldPlots[w] do
			plots[i] = buildPlot(i, cf)
		end
		World.WorldPlots[w] = plots
	end
	for i, p in World.WorldPlots[1] do
		World.Plots[i] = p
	end
	map = root
	buildRings()
	buildIslands()
	WORLD, OX, ZONES, OCEAN = 1, 0, Config.worldZones(1), Config.oceanEnd(1)
	Workspace:SetAttribute("WorldReady", true)
end

return World
