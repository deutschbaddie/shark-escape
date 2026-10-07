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
	slots: Folder,
	owner: Player?,
}
World.Plots = {} :: { Plot }
World.board = nil :: Folder?

local map: Folder

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
	p.Material = Enum.Material.Plastic
	for _, face in { "TopSurface", "FrontSurface", "BackSurface", "LeftSurface", "RightSurface" } do
		(p :: any)[face] = Enum.SurfaceType.Studs
	end
	p.BottomSurface = Enum.SurfaceType.Inlet
	return p
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

-- checkered stud wall with a grass topper, from a to b (axis aligned)
local function checkerWall(parent: Instance, a: Vector3, b: Vector3, bottom: number, top: number, block: number?)
	local len = (b - a).Magnitude
	local dir = (b - a).Unit
	local alongX = math.abs(dir.X) > 0.5
	local blockLen = block or 12
	local rows = math.max(1, math.floor((top - bottom) / 8 + 0.5))
	local rowH = (top - bottom) / rows
	local n = math.max(1, math.floor(len / blockLen + 0.5))
	local step = len / n
	for i = 0, n - 1 do
		local mid = a + dir * (step * (i + 0.5))
		for r = 0, rows - 1 do
			local size = alongX and Vector3.new(step, rowH, WALL_T) or Vector3.new(WALL_T, rowH, step)
			local p = Build.part(parent, size, CFrame.new(mid.X, bottom + rowH * (r + 0.5), mid.Z), ((i + r) % 2 == 0) and WALL_A or WALL_B)
			studAll(p)
		end
	end
	-- grass topper: slightly wider than the wall, in long runs
	local runs = math.max(1, math.ceil(len / 400))
	local runLen = len / runs
	for i = 0, runs - 1 do
		local mid = a + dir * (runLen * (i + 0.5))
		local size = alongX and Vector3.new(runLen + 0.02, 2, WALL_T + 1.6) or Vector3.new(WALL_T + 1.6, 2, runLen + 0.02)
		Build.studs(Build.part(parent, size, CFrame.new(mid.X, top + 1, mid.Z), GRASS, { Name = "Topper" }))
		local lip = alongX and Vector3.new(runLen + 0.02, 0.8, WALL_T + 2.2) or Vector3.new(WALL_T + 2.2, 0.8, runLen + 0.02)
		Build.part(parent, lip, CFrame.new(mid.X, top + 0.2, mid.Z), GRASS2, { Name = "Drip" })
	end
end

----------------------------------------------------------------- terrain
local function fill(minV: Vector3, maxV: Vector3, mat: Enum.Material)
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
	Terrain:Clear()
	local X = 900
	local zFar = Config.OCEAN_END + 600
	-- open ocean all around (seen over the walls)
	fill(Vector3.new(-X, -16, PLAZA_BACK - 300), Vector3.new(X, 0, zFar), Enum.Material.Water)
	fill(Vector3.new(-X, -24, PLAZA_BACK - 300), Vector3.new(X, -16, zFar), Enum.Material.Sand)
	-- the lane: each zone gets deeper and darker
	for _, zone in Config.Zones do
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

	Terrain.WaterColor = Config.Zones[1].water
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
	local rampLen = 8
	local drop = top - Config.FLOOR_TOP
	Build.wedge(plaza, Vector3.new(W, drop, rampLen), CFrame.new(0, Config.FLOOR_TOP + drop / 2, rampLen / 2) * CFrame.Angles(0, math.pi, 0), SAND,
		{ Name = "Ramp", Material = Enum.Material.Plastic })
	-- walls: back and both sides of the plaza
	checkerWall(plaza, Vector3.new(-WALL_X - WALL_T / 2, 0, PLAZA_BACK - WALL_T / 2), Vector3.new(WALL_X + WALL_T / 2, 0, PLAZA_BACK - WALL_T / 2), top - 2, top + 14)
	for _, side in { -1, 1 } do
		checkerWall(plaza, Vector3.new(side * WALL_X, 0, PLAZA_BACK), Vector3.new(side * WALL_X, 0, 0), top - 2, top + 14)
	end
	-- a few palms and bushes against the back wall (kept small)
	for i = 0, 6 do
		local x = -W / 2 + 14 + i * (W - 28) / 6
		Props.palm(plaza, CFrame.new(x, top, PLAZA_BACK + 8), 13 + (i % 3) * 2)
	end
	-- invisible spawn fallback
	local spawn = Instance.new("SpawnLocation")
	spawn.Anchored = true
	spawn.Size = Vector3.new(12, 1, 12)
	spawn.CFrame = CFrame.new(0, top + 0.5, -70)
	spawn.Transparency = 1
	spawn.CanCollide = false
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Parent = map
end

----------------------------------------------------------------- shop huts
-- small studded stalls; stepping on the glowing pad opens the menu (client)
local function hut(kind: string, title: string, color: Color3, pos: Vector3)
	local m = Build.model(kind .. "Hut", map)
	local base = CFrame.new(pos)
	local pad = Build.cyl(m, 0.3, 14, base * CFrame.new(0, 0.15, 6), color, { Name = "Pad", Material = Enum.Material.Neon, Transparency = 0.35, CanCollide = false })
	pad.CastShadow = false
	Build.cyl(m, 0.25, 11, base * CFrame.new(0, 0.2, 6), C(255, 255, 255), { Material = Enum.Material.SmoothPlastic, Transparency = 0.6, CanCollide = false })
	-- counter, posts, striped awning
	studAll(Build.part(m, Vector3.new(12, 3.5, 3), base * CFrame.new(0, 1.75, -1), C(150, 100, 60)))
	studAll(Build.part(m, Vector3.new(12.6, 0.6, 3.6), base * CFrame.new(0, 3.8, -1), color))
	for _, x in { -6, 6 } do
		studAll(Build.part(m, Vector3.new(1.2, 10, 1.2), base * CFrame.new(x, 5, -3), C(120, 80, 50)))
		studAll(Build.part(m, Vector3.new(1.2, 10, 1.2), base * CFrame.new(x, 5, 1.5), C(120, 80, 50)))
	end
	for i = 0, 6 do
		local stripe = (i % 2 == 0) and color or C(255, 255, 255)
		Build.studs(Build.part(m, Vector3.new(14 / 7, 0.8, 7), base * CFrame.new(-7 + 1 + i * 2, 10.4, -0.7) * CFrame.Angles(math.rad(-12), 0, 0), stripe))
	end
	local sign = Build.part(m, Vector3.new(12, 3, 0.6), base * CFrame.new(0, 12.8, -1.5), C(30, 32, 44), { Name = "Sign" })
	Build.part(m, Vector3.new(12.6, 3.6, 0.4), base * CFrame.new(0, 12.8, -1.75), color)
	surfaceText(sign, Enum.NormalId.Back, title, C(255, 255, 255))
	m:SetAttribute("Kind", kind)
	m:SetAttribute("PadX", pos.X)
	m:SetAttribute("PadZ", pos.Z + 6)
	CollectionService:AddTag(m, "ShopPad")
end

----------------------------------------------------------------- leaderboard board
local function buildBoard()
	local m = Build.model("Leaderboard", map)
	local cf = CFrame.new(0, Config.BEACH_TOP, PLAZA_BACK + 10)
	for _, x in { -11, 11 } do
		studAll(Build.part(m, Vector3.new(2, 8, 2), cf * CFrame.new(x, 4, 0), C(40, 140, 230)))
	end
	studAll(Build.part(m, Vector3.new(28, 26, 2.4), cf * CFrame.new(0, 21, 0), C(40, 160, 255)))
	local screen = Build.part(m, Vector3.new(24, 20, 0.4), cf * CFrame.new(0, 20, 1.3), C(24, 26, 38), { Name = "Screen" })
	local head = Build.part(m, Vector3.new(30, 5, 3), cf * CFrame.new(0, 35.5, 0), C(255, 196, 30))
	studAll(head)
	surfaceText(head, Enum.NormalId.Back, "⚡ FASTEST ⚡", C(255, 255, 255), Vector2.new(600, 100))
	local sg = Instance.new("SurfaceGui")
	sg.Face = Enum.NormalId.Back
	sg.CanvasSize = Vector2.new(480, 400)
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
	for i = 1, 10 do
		local row = Instance.new("Frame")
		row.Name = "Row" .. i
		row.LayoutOrder = i
		row.Size = UDim2.new(1, 0, 0, 34)
		row.BackgroundColor3 = i % 2 == 0 and C(255, 255, 255) or C(232, 240, 255)
		row.Parent = sg
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0, 6)
		c.Parent = row
		local function cell(name: string, x: number, w: number, align: Enum.TextXAlignment, color: Color3)
			local t = Instance.new("TextLabel")
			t.Name = name
			t.BackgroundTransparency = 1
			t.Size = UDim2.new(w, 0, 1, -6)
			t.Position = UDim2.new(x, 0, 0, 3)
			t.Font = Enum.Font.FredokaOne
			t.TextScaled = true
			t.TextXAlignment = align
			t.TextColor3 = color
			t.Text = ""
			t.Parent = row
		end
		cell("Rank", 0.02, 0.1, Enum.TextXAlignment.Center, C(255, 160, 0))
		cell("Name", 0.14, 0.52, Enum.TextXAlignment.Left, C(22, 22, 34))
		cell("Value", 0.66, 0.32, Enum.TextXAlignment.Right, C(40, 130, 255))
	end
	World.board = sg :: any
end

----------------------------------------------------------------- lane
local function buildLane()
	local lane = Build.model("Lane", map)
	-- hidden floor players ride on, one slab per zone (parts max out at 2048)
	for _, zone in Config.Zones do
		Build.part(lane, Vector3.new(W + 2, 2, zone.length + 0.5),
			CFrame.new(0, Config.FLOOR_TOP - 1, zone.zStart + zone.length / 2), C(255, 255, 255),
			{ Name = "WaterFloor", Transparency = 1, CastShadow = false })
	end
	-- the corridor walls (visible) + tall invisible guards above them
	local walls = Build.model("LaneWalls", map)
	for _, side in { -1, 1 } do
		checkerWall(walls, Vector3.new(side * WALL_X, 0, 0), Vector3.new(side * WALL_X, 0, Config.OCEAN_END), -6, 10)
		local z = 0
		while z < Config.OCEAN_END do
			local len = math.min(2000, Config.OCEAN_END - z)
			Build.part(lane, Vector3.new(WALL_T, 200, len), CFrame.new(side * WALL_X, 110, z + len / 2), C(255, 255, 255),
				{ Name = "Guard", Transparency = 1, CastShadow = false })
			z += len
		end
	end
	checkerWall(walls, Vector3.new(-WALL_X - WALL_T / 2, 0, Config.OCEAN_END + WALL_T / 2), Vector3.new(WALL_X + WALL_T / 2, 0, Config.OCEAN_END + WALL_T / 2), -6, 10)
	-- foam line at the shore (client pulses it)
	local foam = Build.part(lane, Vector3.new(W, 0.2, 3), CFrame.new(0, 0.12, 9), C(255, 255, 255),
		{ Name = "ShoreFoam", Transparency = 0.25, CanCollide = false, CanQuery = false })
	CollectionService:AddTag(foam, "ShoreFoam")
end

----------------------------------------------------------------- gates
-- a checkered arch with a lock sign; the glowing wall is visual only (the
-- server enforces gates, the client fades unlocked ones)
local function buildGates()
	local folder = Instance.new("Folder")
	folder.Name = "Gates"
	folder.Parent = map
	for _, zone in Config.Zones do
		if zone.gate > 0 then
			local g = Build.model("Gate_" .. zone.id, folder)
			local z = zone.zStart
			local wall = Build.part(g, Vector3.new(W, 40, 0.6), CFrame.new(0, 18, z), C(255, 214, 64), {
				Name = "Wall", Material = Enum.Material.ForceField, Transparency = 0.2, CastShadow = false, CanCollide = false, CanQuery = false,
			})
			g.PrimaryPart = wall
			g:SetAttribute("Gate", zone.gate)
			g:SetAttribute("ZoneName", zone.name)
			for _, side in { -1, 1 } do
				for r = 0, 3 do
					studAll(Build.part(g, Vector3.new(6, 6, 6), CFrame.new(side * (W / 2 - 3), -3 + r * 6 + 3, z), (r % 2 == 0) and WALL_A or WALL_B))
				end
				Build.studs(Build.part(g, Vector3.new(7, 1.5, 7), CFrame.new(side * (W / 2 - 3), 21.75, z), GRASS))
			end
			local board = Build.part(g, Vector3.new(60, 10, 1.2), CFrame.new(0, 26, z), C(30, 32, 44), { Name = "Banner", CanCollide = false })
			for _, y in { 20.6, 31.4 } do
				Build.studs(Build.part(g, Vector3.new(62, 1.2, 1.6), CFrame.new(0, y, z), C(255, 196, 30), { CanCollide = false }))
			end
			for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
				surfaceText(board, face, ("🔒 %s  ⚡%s"):format(zone.name, tostring(zone.gate)), C(255, 255, 255), Vector2.new(600, 100))
			end
			-- rope of buoys across the water
			for x = -W / 2 + 12, W / 2 - 12, 12 do
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
	for _, zone in Config.Zones do
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
		end
		-- scenery islands outside the corridor
		for _ = 1, math.floor(zone.length / 200) do
			for _, side in { -1, 1 } do
				local x = side * rng:NextNumber(W / 2 + 50, W / 2 + 220)
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
		{ Vector3.new(1, 1.2, 30.4), Vector3.new(-15, 0.1, -1) }, { Vector3.new(1, 1.2, 30.4), Vector3.new(15, 0.1, -1) } } do
		Build.studs(Build.part(m, s[1], cf * CFrame.new(s[2]), dark))
	end
	-- tank
	local tcf = CFrame.new(Layout.tankPos(cf)) * cf.Rotation * CFrame.new(0, 0.5, 0)
	local frame = C(40, 140, 240)
	studAll(Build.part(m, Vector3.new(17, 0.8, 6), tcf * CFrame.new(0, 0.4, 0), frame))
	studAll(Build.part(m, Vector3.new(17, 0.8, 6), tcf * CFrame.new(0, 8.8, 0), frame))
	for _, x in { -8.2, 8.2 } do
		studAll(Build.part(m, Vector3.new(0.8, 8, 6), tcf * CFrame.new(x, 4.6, 0), frame))
	end
	local glass = C(200, 240, 255)
	Build.part(m, Vector3.new(15.8, 7.6, 0.2), tcf * CFrame.new(0, 4.6, -2.9), glass, { Material = Enum.Material.Glass, Transparency = 0.75 })
	Build.part(m, Vector3.new(15.8, 7.6, 0.2), tcf * CFrame.new(0, 4.6, 2.9), glass, { Material = Enum.Material.Glass, Transparency = 0.75 })
	Build.part(m, Vector3.new(15.8, 6.8, 5.4), tcf * CFrame.new(0, 4.4, 0), C(60, 210, 240), { Transparency = 0.6, CanCollide = false, Name = "TankWater" })
	Build.studs(Build.part(m, Vector3.new(15.8, 0.6, 5.4), tcf * CFrame.new(0, 1.1, 0), SAND))
	local slots = Instance.new("Folder")
	slots.Name = "Slots"
	slots.Parent = m
	local deck = m:FindFirstChild("Deck") :: BasePart
	local sign = label(deck, Vector2.new(14, 3), (tcf * CFrame.new(0, 12, 0)).Position - deck.Position, "Empty Dock", nil, 140)
	-- collect pad
	local pcf = CFrame.new(Layout.padPos(cf)) * CFrame.new(0, 0.55, 0)
	Build.cyl(m, 0.3, 7.4, pcf, C(90, 240, 90), { Material = Enum.Material.Neon, Name = "PadRim", CastShadow = false })
	local pad = Build.cyl(m, 0.5, 6.2, pcf * CFrame.new(0, 0.15, 0), C(50, 190, 70), { Name = "Pad" })
	local padLabel = label(pad, Vector2.new(8, 2.4), Vector3.new(0, 3.2, 0), "💰 0", C(140, 255, 90), 90)
	return { index = i, cf = cf, model = m, padLabel = padLabel, signLabel = sign, slots = slots, owner = nil }
end

function World.build()
	map = Instance.new("Folder")
	map.Name = "Map"
	map.Parent = Workspace
	-- clear the template baseplate so it doesn't fight the plaza
	for _, name in { "Baseplate", "SpawnLocation" } do
		local old = Workspace:FindFirstChild(name)
		if old and old:IsA("BasePart") then
			old:Destroy()
		end
	end
	buildLighting()
	buildPlaza()
	for i, cf in Layout.Plots do
		World.Plots[i] = buildPlot(i, cf)
	end
	hut("Rides", "🛟 RIDES", C(40, 190, 255), Vector3.new(-62, Config.BEACH_TOP, -92))
	hut("Index", "📖 INDEX", C(255, 150, 30), Vector3.new(62, Config.BEACH_TOP, -92))
	hut("Shop", "🛒 SHOP", C(255, 70, 170), Vector3.new(-112, Config.BEACH_TOP, -100))
	buildBoard()
	buildTerrain()
	buildLane()
	buildGates()
	buildIslands()
	buildDecor()
	Workspace:SetAttribute("WorldReady", true)
end

return World
