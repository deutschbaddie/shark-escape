-- Builds the whole map at server start: terrain ocean with a depth gradient,
-- beach, hidden water floor, gates, safe islands, decorations and plots.

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

local map: Folder

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
	local zFar = Config.OCEAN_END + 500
	-- open ocean around everything
	fill(Vector3.new(-X, -16, -40), Vector3.new(X, 0, zFar), Enum.Material.Water)
	fill(Vector3.new(-X, -24, -40), Vector3.new(X, -16, zFar), Enum.Material.Sand)
	-- the lane: each zone gets deeper and darker
	for _, zone in Config.Zones do
		local half = W / 2 + 24
		fill(Vector3.new(-half, -zone.depth, zone.zStart), Vector3.new(half, 0, zone.zEnd), Enum.Material.Water)
		fill(Vector3.new(-half, -zone.depth - 8, zone.zStart), Vector3.new(half, -zone.depth, zone.zEnd), zone.floor)
		Terrain:SetMaterialColor(zone.floor, zone.floorColor)
	end
	-- beach and a gentle slope into the water
	fill(Vector3.new(-X, -24, -260), Vector3.new(X, Config.BEACH_TOP, -24), Enum.Material.Sand)
	for z = -24, 8, 4 do
		local top = z <= 0 and (Config.BEACH_TOP * (-z) / 24) or (-7 * z / 12)
		fill(Vector3.new(-X, -24, z), Vector3.new(X, top, z + 4), Enum.Material.Sand)
	end
	Terrain:SetMaterialColor(Enum.Material.Sand, C(255, 236, 180))

	Terrain.WaterColor = Config.Zones[1].water
	Terrain.WaterTransparency = 0.85
	Terrain.WaterReflectance = 0.35
	Terrain.WaterWaveSize = 0.12
	Terrain.WaterWaveSpeed = 12

	local clouds = Terrain:FindFirstChildOfClass("Clouds") or Instance.new("Clouds")
	clouds.Cover = 0.55
	clouds.Density = 0.7
	clouds.Color = C(255, 255, 255)
	clouds.Parent = Terrain
end

----------------------------------------------------------------- lighting
local function buildLighting()
	Lighting.ClockTime = 14.2
	Lighting.Brightness = 3
	Lighting.Ambient = C(90, 110, 130)
	Lighting.OutdoorAmbient = C(160, 180, 200)
	Lighting.EnvironmentDiffuseScale = 1
	Lighting.EnvironmentSpecularScale = 1
	Lighting.GlobalShadows = true
	local function get(class: string, name: string): Instance
		local i = Lighting:FindFirstChild(name) or Instance.new(class)
		i.Name = name
		i.Parent = Lighting
		return i
	end
	local atm = get("Atmosphere", "Atmosphere") :: Atmosphere
	atm.Density = 0.28
	atm.Offset = 0.1
	atm.Color = C(199, 233, 255)
	atm.Decay = C(106, 180, 220)
	atm.Glare = 0.2
	atm.Haze = 1.2
	local bloom = get("BloomEffect", "Bloom") :: BloomEffect
	bloom.Intensity = 0.6
	bloom.Size = 24
	bloom.Threshold = 1.6
	local rays = get("SunRaysEffect", "SunRays") :: SunRaysEffect
	rays.Intensity = 0.06
	local cc = get("ColorCorrectionEffect", "Grade") :: ColorCorrectionEffect
	cc.Saturation = 0.18
	cc.Contrast = 0.06
	if not Lighting:FindFirstChildOfClass("Sky") then
		Instance.new("Sky").Parent = Lighting
	end
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
	-- side walls and end wall
	local z0, z1 = -200, Config.OCEAN_END
	local z = z0
	while z < z1 do
		local len = math.min(2000, z1 - z)
		for _, side in { -1, 1 } do
			Build.part(lane, Vector3.new(2, 120, len), CFrame.new(side * (W / 2 + 1), 50, z + len / 2), C(255, 255, 255),
				{ Name = "LaneWall", Transparency = 1, CastShadow = false })
		end
		z += len
	end
	Build.part(lane, Vector3.new(W + 4, 120, 2), CFrame.new(0, 50, Config.OCEAN_END), C(255, 255, 255),
		{ Name = "EndWall", Transparency = 1 })
	-- foam line at the shore (client pulses it)
	local foam = Build.part(lane, Vector3.new(900, 0.2, 3), CFrame.new(0, 0.12, 1), C(255, 255, 255),
		{ Name = "ShoreFoam", Transparency = 0.25, CanCollide = false, CanQuery = false, Material = Enum.Material.SmoothPlastic })
	CollectionService:AddTag(foam, "ShoreFoam")
	-- buoy ropes down both sides
	local deco = Build.model("Buoys", map)
	local i = 0
	for bz = 12, Config.OCEAN_END, 44 do
		i += 1
		for _, side in { -1, 1 } do
			Props.buoy(deco, Vector3.new(side * (W / 2 + 1), 0, bz), (i % 2 == 0) and C(255, 255, 255) or C(255, 70, 70))
		end
	end
	Build.ghost(deco)
end

----------------------------------------------------------------- gates
local function buildGates()
	local folder = Instance.new("Folder")
	folder.Name = "Gates"
	folder.Parent = map
	for _, zone in Config.Zones do
		if zone.gate > 0 then
			local g = Build.model("Gate_" .. zone.id, folder)
			local wall = Build.part(g, Vector3.new(W, 60, 1.2), CFrame.new(0, 28, zone.zStart), C(255, 214, 64), {
				Name = "Wall", Material = Enum.Material.ForceField, Transparency = 0.15, CastShadow = false,
			})
			g.PrimaryPart = wall
			g:SetAttribute("Gate", zone.gate)
			g:SetAttribute("ZoneName", zone.name)
			for x = -W / 2 + 8, W / 2 - 8, 16 do
				Props.buoy(g, Vector3.new(x, 0, zone.zStart), C(255, 196, 40))
			end
			local banner = Build.part(g, Vector3.new(84, 14, 1), CFrame.new(0, 22, zone.zStart - 1), C(27, 29, 63), {
				Name = "Banner", CanCollide = false,
			})
			for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
				local sg = Instance.new("SurfaceGui")
				sg.Face = face
				sg.CanvasSize = Vector2.new(840, 140)
				sg.LightInfluence = 0
				sg.Parent = banner
				local t = Instance.new("TextLabel")
				t.Name = "Text"
				t.Size = UDim2.fromScale(1, 1)
				t.BackgroundTransparency = 1
				t.Font = Enum.Font.FredokaOne
				t.TextScaled = true
				t.TextColor3 = C(255, 255, 255)
				t.Text = ("🔒 %s · %s SPEED"):format(zone.name:upper(), tostring(zone.gate))
				t.Parent = sg
			end
			for _, side in { -1, 1 } do
				Build.studs(Build.part(g, Vector3.new(3, 34, 3), CFrame.new(side * 44, 14, zone.zStart - 1), C(255, 196, 40)))
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
local function buildDecor()
	local deco = Build.model("Decor", map)
	local rng = Random.new(42)
	local function laneXZ(zone: Config.Zone): (number, number)
		return rng:NextNumber(-W / 2 + 10, W / 2 - 10), rng:NextNumber(zone.zStart + 10, zone.zEnd - 10)
	end
	for _, zone in Config.Zones do
		local floorY = -zone.depth
		if zone.id == "Lagoon" then
			for _ = 1, 7 do
				local x, z = laneXZ(zone)
				Props.beachBall(deco, Vector3.new(x, 0.9, z))
			end
			for _ = 1, 14 do
				local x, z = laneXZ(zone)
				Props.coral(deco, CFrame.new(x, floorY, z), rng)
			end
		elseif zone.id == "Reef" then
			for _ = 1, 60 do
				local x, z = laneXZ(zone)
				Props.coral(deco, CFrame.new(x, floorY, z) * CFrame.Angles(0, rng:NextNumber(0, 6), 0), rng)
			end
		elseif zone.id == "Kelp" then
			for _ = 1, 80 do
				local x, z = laneXZ(zone)
				Props.kelp(deco, CFrame.new(x, floorY, z), zone.depth - rng:NextNumber(0.5, 4), rng)
			end
		elseif zone.id == "Shipwreck" then
			for i = 1, 3 do
				local z = zone.zStart + zone.length * (i / 4)
				local x = (i % 2 == 0 and -1 or 1) * rng:NextNumber(50, 110)
				Props.shipwreck(deco, CFrame.new(x, -2, z) * CFrame.Angles(0, rng:NextNumber(0, 6), 0))
			end
			for _ = 1, 16 do
				local x, z = laneXZ(zone)
				Props.crate(deco, Vector3.new(x, 0.4, z), rng)
			end
		elseif zone.id == "Deep" then
			for _ = 1, 30 do
				local x, z = laneXZ(zone)
				Props.jellyfish(deco, Vector3.new(x, -3.5, z), rng)
			end
		elseif zone.id == "Abyss" then
			for _ = 1, 16 do
				local x, z = laneXZ(zone)
				Props.spikeRock(deco, CFrame.new(x, 0, z) * CFrame.Angles(0, rng:NextNumber(0, 6), 0), rng:NextNumber(10, 22))
			end
			Props.jawArch(deco, CFrame.new(0, -2, zone.zEnd - 30), W * 0.8)
		end
		-- scenery islands outside the lane frame each zone
		for _ = 1, math.floor(zone.length / 160) do
			for _, side in { -1, 1 } do
				local x = side * rng:NextNumber(W / 2 + 40, W / 2 + 200)
				local z = rng:NextNumber(zone.zStart, zone.zEnd)
				local r = rng:NextNumber(14, 30)
				local isl = Props.island(deco, Vector3.new(x, 0, z), r, true)
				Props.palm(isl, CFrame.new(x - r * 0.3, 0.5, z + r * 0.2), 16)
			end
		end
	end
	Build.ghost(deco)
	-- beach props
	local beach = Build.model("BeachDecor", map)
	for i = 1, 14 do
		local x = -260 + i * 37
		if math.abs(x) > W / 2 + 8 then
			Props.palm(beach, CFrame.new(x, Config.BEACH_TOP, -30 - (i % 3) * 14), 14 + (i % 4) * 2)
		end
	end
	for i = 1, Config.PLOT_COUNT + 1 do
		local x = (i - (Config.PLOT_COUNT + 2) / 2) * Config.PLOT_SPACING
		Props.palm(beach, CFrame.new(x, Config.BEACH_TOP, -64), 16)
	end
end

----------------------------------------------------------------- plots
local function label(parent: Instance, size: UDim2, offset: Vector3, text: string, color: Color3?): TextLabel
	local bb = Instance.new("BillboardGui")
	bb.Size = size
	bb.StudsOffsetWorldSpace = offset
	bb.AlwaysOnTop = false
	bb.MaxDistance = 160
	bb.LightInfluence = 0
	bb.Parent = parent
	local t = Instance.new("TextLabel")
	t.Size = UDim2.fromScale(1, 1)
	t.BackgroundTransparency = 1
	t.Font = Enum.Font.FredokaOne
	t.TextScaled = true
	t.TextColor3 = color or C(255, 255, 255)
	t.TextStrokeTransparency = 0.2
	t.TextStrokeColor3 = C(27, 29, 63)
	t.Text = text
	t.Parent = bb
	return t
end

local function buildPlot(i: number, cf: CFrame): Plot
	local m = Build.model("Plot" .. i, map)
	local wood, dark = C(196, 140, 86), C(150, 100, 60)
	local deck = Build.part(m, Vector3.new(30, 1, 30), cf * CFrame.new(0, 0, -1), wood, { Material = Enum.Material.WoodPlanks, Name = "Deck" })
	for _, x in { -14, 14 } do
		for _, z in { -15, 13 } do
			Build.cyl(m, 3, 1.2, cf * CFrame.new(x, 0, z), dark)
		end
	end
	-- tank
	local tcf = CFrame.new(Layout.tankPos(cf)) * cf.Rotation * CFrame.new(0, 0.5, 0)
	local glass = C(190, 236, 255)
	Build.part(m, Vector3.new(17, 0.8, 6), tcf * CFrame.new(0, 0.4, 0), C(40, 120, 220))
	Build.part(m, Vector3.new(17, 0.8, 6), tcf * CFrame.new(0, 8.8, 0), C(40, 120, 220))
	for _, x in { -8.2, 8.2 } do
		Build.part(m, Vector3.new(0.6, 8, 6), tcf * CFrame.new(x, 4.6, 0), C(40, 120, 220))
	end
	Build.part(m, Vector3.new(15.8, 7.6, 0.2), tcf * CFrame.new(0, 4.6, -2.9), glass, { Material = Enum.Material.Glass, Transparency = 0.7 })
	Build.part(m, Vector3.new(15.8, 7.6, 0.2), tcf * CFrame.new(0, 4.6, 2.9), glass, { Material = Enum.Material.Glass, Transparency = 0.7 })
	Build.part(m, Vector3.new(15.8, 6.6, 5.4), tcf * CFrame.new(0, 4.4, 0), C(60, 200, 235), { Transparency = 0.6, CanCollide = false, Name = "TankWater" })
	Build.part(m, Vector3.new(15.8, 0.6, 5.4), tcf * CFrame.new(0, 1.1, 0), C(255, 230, 170), { Material = Enum.Material.Sand })
	local slots = Instance.new("Folder")
	slots.Name = "Slots"
	slots.Parent = m
	local sign = label(deck, UDim2.fromOffset(240, 60), (tcf * CFrame.new(0, 12, 0)).Position - deck.Position, "Empty Dock")
	-- collect pad
	local pcf = CFrame.new(Layout.padPos(cf)) * CFrame.new(0, 0.55, 0)
	Build.cyl(m, 0.3, 7, pcf, C(70, 220, 110), { Material = Enum.Material.Neon, Name = "PadRim" })
	local pad = Build.cyl(m, 0.4, 6, pcf * CFrame.new(0, 0.1, 0), C(40, 180, 90), { Name = "Pad" })
	Build.studs(pad)
	local padLabel = label(pad, UDim2.fromOffset(200, 60), Vector3.new(0, 4, 0), "💰 0", C(255, 224, 80))
	return { index = i, cf = cf, model = m, padLabel = padLabel, signLabel = sign, slots = slots, owner = nil }
end

function World.build()
	map = Instance.new("Folder")
	map.Name = "Map"
	map.Parent = Workspace
	buildLighting()
	local spawn = Instance.new("SpawnLocation")
	spawn.Anchored = true
	spawn.Size = Vector3.new(12, 1, 12)
	spawn.CFrame = CFrame.new(0, Config.BEACH_TOP + 0.5, -20)
	spawn.Transparency = 1
	spawn.CanCollide = false
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Parent = map
	for i, cf in Layout.Plots do
		World.Plots[i] = buildPlot(i, cf)
	end
	buildTerrain()
	buildLane()
	buildGates()
	buildIslands()
	buildDecor()
	Workspace:SetAttribute("WorldReady", true)
end

return World
