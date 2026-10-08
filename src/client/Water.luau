-- Makes the water feel amazing without making it harder to play:
--  * water color/clarity shifts zone by zone (turquoise lagoon -> inky abyss)
--  * every rider gets a foam wake + spray that grows with speed
--  * riders hold a surf stance instead of running on water
--  * splash on entry, pulsing shore foam, bobbing props, swimming tank fish

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")

local Shared = game.ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Layout = require(Shared.Layout)
local Fx = require(script.Parent.Fx)
local UI = require(script.Parent.UI)

local Water = {}
local player = Players.LocalPlayer
local Terrain = Workspace.Terrain

----------------------------------------------------------------- zone tint
local function zoneBlend(z: number): (Color3, number, Color3)
	local zones = Config.Zones
	if z <= Config.SHORE_Z then
		return zones[1].water, zones[1].clarity, zones[1].tint
	end
	for i, zone in zones do
		local nextZone = zones[i + 1]
		local edge = zone.zEnd
		if z < edge or not nextZone then
			-- blend over the last 80 studs of a zone into the next one
			local t = nextZone and math.clamp((z - (edge - 80)) / 80, 0, 1) or 0
			local n = nextZone or zone
			return zone.water:Lerp(n.water, t), zone.clarity + (n.clarity - zone.clarity) * t, zone.tint:Lerp(n.tint, t)
		end
	end
	return zones[#zones].water, zones[#zones].clarity, zones[#zones].tint
end

local grade: ColorCorrectionEffect? = nil
local atmosphere: Atmosphere? = nil
local baseDecay = Color3.fromRGB(106, 180, 220)

local function updateTint(dt: number)
	local cam = Workspace.CurrentCamera
	local col, clarity, tint = zoneBlend(cam.Focus.Position.Z)
	local a = 1 - math.exp(-dt * 3)
	Terrain.WaterColor = Terrain.WaterColor:Lerp(col, a)
	Terrain.WaterTransparency += (clarity - Terrain.WaterTransparency) * a
	grade = grade or Lighting:FindFirstChild("Grade") :: ColorCorrectionEffect?
	if grade then
		grade.TintColor = grade.TintColor:Lerp(tint, a)
	end
	atmosphere = atmosphere or Lighting:FindFirstChildOfClass("Atmosphere")
	if atmosphere then
		atmosphere.Decay = atmosphere.Decay:Lerp(baseDecay:Lerp(col, 0.5), a)
	end
end

----------------------------------------------------------------- riders
type Rider = {
	char: Model,
	hrp: BasePart,
	hum: Humanoid,
	foam: ParticleEmitter,
	spray: ParticleEmitter,
	trail: Trail,
	ring: Part,
	wasWet: boolean,
	motors: { [string]: Motor6D },
	animate: LocalScript?,
}

local riders: { [Model]: Rider } = {}

local function emitter(parent: Instance, props: { [string]: any }): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	for k, v in props do
		(e :: any)[k] = v
	end
	e.Parent = parent
	return e
end

local function addRider(char: Model)
	local hrp = char:WaitForChild("HumanoidRootPart", 10) :: BasePart?
	local hum = char:WaitForChild("Humanoid", 10) :: Humanoid?
	if not hrp or not hum or riders[char] then
		return
	end
	local feetY = -(hum.HipHeight + hrp.Size.Y / 2)
	local back = Instance.new("Attachment")
	back.Name = "WakeBack"
	back.Position = Vector3.new(0, feetY, 1.8)
	back.Parent = hrp
	local foam = emitter(back, {
		Texture = Fx.TEX.smoke, Color = ColorSequence.new(Color3.new(1, 1, 1)),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 3.5) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(1, 1) }),
		Lifetime = NumberRange.new(0.7, 1.2), Rate = 0, Speed = NumberRange.new(0.5, 2),
		SpreadAngle = Vector2.new(70, 10), EmissionDirection = Enum.NormalId.Top,
		Orientation = Enum.ParticleOrientation.VelocityPerpendicular,
	})
	local spray = emitter(back, {
		Texture = Fx.TEX.sparkle, Color = ColorSequence.new(Color3.fromRGB(210, 250, 255)),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0.1) }),
		Lifetime = NumberRange.new(0.35, 0.6), Rate = 0, Speed = NumberRange.new(8, 16),
		SpreadAngle = Vector2.new(40, 25), EmissionDirection = Enum.NormalId.Top,
		Acceleration = Vector3.new(0, -50, 0), LightEmission = 0.8,
	})
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(-1.3, feetY + 0.1, 0.8)
	a0.Parent = hrp
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(1.3, feetY + 0.1, 0.8)
	a1.Parent = hrp
	local trail = Instance.new("Trail")
	trail.Attachment0, trail.Attachment1 = a0, a1
	trail.Color = ColorSequence.new(Color3.new(1, 1, 1))
	trail.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) })
	trail.WidthScale = NumberSequence.new(1, 2.5)
	trail.Lifetime = 0.8
	trail.FaceCamera = false
	trail.Enabled = false
	trail.Parent = hrp
	local ring = Instance.new("Part")
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.CastShadow = false
	ring.Shape = Enum.PartType.Cylinder
	ring.Color = Color3.new(1, 1, 1)
	ring.Material = Enum.Material.SmoothPlastic
	ring.Transparency = 1
	ring.Size = Vector3.new(0.1, 6, 6)
	ring.Parent = Fx.folder
	local motors = {}
	for _, d in char:GetDescendants() do
		if d:IsA("Motor6D") then
			motors[d.Name] = d
		end
	end
	local rider: Rider = {
		char = char, hrp = hrp, hum = hum, foam = foam, spray = spray, trail = trail, ring = ring,
		wasWet = false, motors = motors, animate = char:FindFirstChild("Animate") :: LocalScript?,
	}
	riders[char] = rider
	char.AncestryChanged:Connect(function(_, parent)
		if not parent then
			ring:Destroy()
			riders[char] = nil
		end
	end)
end

local function trackPlayer(p: Player)
	if p.Character then
		task.spawn(addRider, p.Character)
	end
	p.CharacterAdded:Connect(function(c)
		task.spawn(addRider, c)
	end)
end

-- Ride poses, one per stance (Config.RideFeel[ride].stance). Applied after
-- the Animator each frame (PreSimulation) so they win; the local player's
-- Animate script is switched off while riding (Ride.luau), so there's no
-- walk cycle on the water. t = time, s = sway (0.3..1.5 with speed).
local A = CFrame.Angles
local function hold() return CFrame.new() end
local POSES: { [string]: { [string]: (number, number) -> CFrame } } = {
	-- standing surf stance: knees bent, arms out for balance
	stand = {
		Root = function(t, s) return CFrame.new(0, -0.35 + math.sin(t * 6) * 0.05, 0) * A(0, 0, math.sin(t * 2) * 0.05 * s) end,
		Waist = function() return A(0.12, 0.35, 0) end,
		Neck = function() return A(-0.05, -0.3, 0) end,
		LeftShoulder = function(t) return A(0, 0, -1.15 + math.sin(t * 3) * 0.08) end,
		RightShoulder = function(t) return A(0, 0, 1.15 - math.sin(t * 3) * 0.08) end,
		LeftElbow = function() return A(0.25, 0, 0) end,
		RightElbow = function() return A(0.25, 0, 0) end,
		LeftHip = function() return A(0.55, 0, -0.08) end,
		RightHip = function() return A(-0.05, 0, 0.08) end,
		LeftKnee = function() return A(-0.75, 0, 0) end,
		RightKnee = function() return A(-0.55, 0, 0) end,
		LeftAnkle = function() return A(0.2, 0, 0) end,
		RightAnkle = function() return A(0.5, 0, 0) end,
	},
	-- sitting in a ring (tube, duck, donut, bathtub): legs forward, hands on the rim
	sit = {
		Root = function(t) return CFrame.new(0, -1.25 + math.sin(t * 3) * 0.04, 0) end,
		Waist = function() return A(-0.15, 0, 0) end,
		Neck = function(t) return A(0.1, math.sin(t * 0.8) * 0.15, 0) end,
		LeftShoulder = function(t) return A(0.2, 0, -0.55 + math.sin(t * 2) * 0.05) end,
		RightShoulder = function(t) return A(0.2, 0, 0.55 - math.sin(t * 2) * 0.05) end,
		LeftElbow = function() return A(0.4, 0, 0) end,
		RightElbow = function() return A(0.4, 0, 0) end,
		LeftHip = function() return A(1.45, 0, -0.12) end,
		RightHip = function() return A(1.45, 0, 0.12) end,
		LeftKnee = function(t) return A(-0.55 + math.sin(t * 2.4) * 0.12, 0, 0) end,
		RightKnee = function(t) return A(-0.55 - math.sin(t * 2.4) * 0.12, 0, 0) end,
		LeftAnkle = hold, RightAnkle = hold,
	},
	-- straddling a jet ski / boat / banana / dolphin: lean in, hands forward
	straddle = {
		Root = function(t, s) return CFrame.new(0, -0.95, 0) * A(-0.12 * s, 0, 0) end,
		Waist = function() return A(-0.2, 0, 0) end,
		Neck = function() return A(0.2, 0, 0) end,
		LeftShoulder = function(t) return A(1.25, 0, -0.18 + math.sin(t * 9) * 0.02) end,
		RightShoulder = function(t) return A(1.25, 0, 0.18 - math.sin(t * 9) * 0.02) end,
		LeftElbow = function() return A(0.35, 0, 0) end,
		RightElbow = function() return A(0.35, 0, 0) end,
		LeftHip = function() return A(1.15, 0, -0.35) end,
		RightHip = function() return A(1.15, 0, 0.35) end,
		LeftKnee = function() return A(-1.5, 0, 0) end,
		RightKnee = function() return A(-1.5, 0, 0) end,
		LeftAnkle = function() return A(0.4, 0, 0) end,
		RightAnkle = function() return A(0.4, 0, 0) end,
	},
	-- lying on a boogie board, paddling
	prone = {
		Root = function(t) return CFrame.new(0, -1.7, 0.4) * A(-1.42, 0, math.sin(t * 3) * 0.04) end,
		Waist = function() return A(0.25, 0, 0) end,
		Neck = function() return A(0.9, 0, 0) end,
		LeftShoulder = function(t) return A(2.6 + math.sin(t * 6) * 0.5, 0, -0.15) end,
		RightShoulder = function(t) return A(2.6 - math.sin(t * 6) * 0.5, 0, 0.15) end,
		LeftElbow = hold, RightElbow = hold,
		LeftHip = function() return A(0, 0, -0.1) end,
		RightHip = function() return A(0, 0, 0.1) end,
		LeftKnee = function(t) return A(-0.3 - math.max(0, math.sin(t * 6)) * 0.6, 0, 0) end,
		RightKnee = function(t) return A(-0.3 - math.max(0, -math.sin(t * 6)) * 0.6, 0, 0) end,
		LeftAnkle = hold, RightAnkle = hold,
	},
	-- floating on a pool noodle: chest-deep, arms over the noodle, kicking
	float = {
		Root = function(t) return CFrame.new(0, -1.9 + math.sin(t * 2) * 0.08, 0) * A(-0.35, 0, 0) end,
		Waist = function() return A(0.1, 0, 0) end,
		Neck = function() return A(0.3, 0, 0) end,
		LeftShoulder = function() return A(1.35, 0, -0.35) end,
		RightShoulder = function() return A(1.35, 0, 0.35) end,
		LeftElbow = function() return A(0.9, 0, 0) end,
		RightElbow = function() return A(0.9, 0, 0) end,
		LeftHip = function(t) return A(-0.2 + math.sin(t * 7) * 0.35, 0, 0) end,
		RightHip = function(t) return A(-0.2 - math.sin(t * 7) * 0.35, 0, 0) end,
		LeftKnee = function() return A(-0.3, 0, 0) end,
		RightKnee = function() return A(-0.3, 0, 0) end,
		LeftAnkle = hold, RightAnkle = hold,
	},
}

RunService.PreSimulation:Connect(function()
	local t = os.clock()
	for char, r in riders do
		if r.wasWet and r.motors.Waist then -- R15 only
			local speed = (r.hrp.AssemblyLinearVelocity * Vector3.new(1, 0, 1)).Magnitude
			local sway = math.clamp(speed / 60, 0.3, 1.5)
			local pose = POSES[Config.feel(char:GetAttribute("Ride") :: string?).stance] or POSES.stand
			for name, fn in pose do
				local m = r.motors[name]
				if m then
					m.Transform = fn(t, sway)
				end
			end
		end
	end
end)

local function updateRiders(dt: number)
	local myChar = player.Character
	for char, r in riders do
		local pos = r.hrp.Position
		local wet = Layout.inWater(pos) and not Layout.islandAt(pos, 0) and r.hum.Health > 0
		local vel = r.hrp.AssemblyLinearVelocity * Vector3.new(1, 0, 1)
		local speed = vel.Magnitude
		if wet ~= r.wasWet then
			r.wasWet = wet
			if not wet then
				for _, m in r.motors do
					m.Transform = CFrame.new()
				end
			end
			if wet then
				Fx.splash(Vector3.new(pos.X, 0.4, pos.Z), 0.9)
				if char == myChar then
					Fx.sound("splash", 0.5, 1 + math.random() * 0.2)
				end
			end
			local run = r.hrp:FindFirstChild("Running")
			if run and run:IsA("Sound") then
				run.Volume = wet and 0 or 0.65
			end
		end
		local moving = wet and speed > 4
		local k = math.clamp(speed / 120, 0, 1.6)
		r.foam.Rate = moving and (18 + 50 * k) or (wet and 4 or 0)
		r.spray.Rate = moving and (6 + 60 * k) or 0
		r.spray.Speed = NumberRange.new(8 + 10 * k, 16 + 22 * k)
		r.trail.Enabled = moving
		r.trail.Lifetime = 0.5 + 0.8 * k
		if wet then
			local pulse = 1 + math.sin(os.clock() * 4 + pos.X) * 0.08
			r.ring.Transparency = 0.55
			r.ring.Size = Vector3.new(0.1, (4.5 + k * 2) * pulse, (4.5 + k * 2) * pulse)
			r.ring.CFrame = CFrame.new(pos.X, 0.12, pos.Z) * CFrame.Angles(0, 0, math.pi / 2)
		else
			r.ring.Transparency = 1
		end
	end
end

----------------------------------------------------------------- speed lines
local lines: Frame
local lineBits = {}
local function buildLines()
	lines = UI.frame(Fx.screen(), { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 1, Name = "SpeedLines" })
	for i = 1, 14 do
		local f = UI.frame(lines, { Size = UDim2.new(0, 3, 0.18, 0), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5) })
		lineBits[i] = { f = f, a = (i / 14) * math.pi * 2, t = math.random() }
	end
end

local function updateLines(dt: number)
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local speed = hrp and (hrp.AssemblyLinearVelocity * Vector3.new(1, 0, 1)).Magnitude or 0
	local k = math.clamp((speed - 90) / 120, 0, 1)
	for _, b in lineBits do
		b.t = (b.t + dt * (1.5 + k * 2)) % 1
		local r = 0.38 + b.t * 0.3
		b.f.Position = UDim2.fromScale(0.5 + math.cos(b.a) * r * 0.75, 0.5 + math.sin(b.a) * r)
		b.f.Rotation = math.deg(b.a) + 90
		b.f.BackgroundTransparency = 1 - k * 0.55 * math.sin(b.t * math.pi)
	end
end

----------------------------------------------------------------- props
local function animateTagged(dt: number)
	local t = os.clock()
	for _, m in CollectionService:GetTagged("Bubble") do
		if m:IsA("Model") and m.PrimaryPart then
			local base = m:GetAttribute("BaseCF") :: CFrame?
			if not base then
				base = m:GetPivot()
				m:SetAttribute("BaseCF", base)
			end
			local seed = (base :: CFrame).Position.X
			m:PivotTo((base :: CFrame) * CFrame.new(0, math.sin(t * 2 + seed) * 0.5, 0) * CFrame.Angles(0, t * 0.8 + seed, 0))
		end
	end
end

local rainbowParts: { BasePart } = {}
local function scanRainbow()
	table.clear(rainbowParts)
	for _, m in CollectionService:GetTagged("Rainbow") do
		for _, p in m:GetDescendants() do
			if p:IsA("BasePart") and p.Transparency < 1 and not p:GetAttribute("KeepColor") then
				table.insert(rainbowParts, p)
			end
		end
	end
end

local foamParts: { BasePart } = {}

----------------------------------------------------------------- safe rings during attacks
function Water.setSafeGlow(on: boolean)
	for _, island in CollectionService:GetTagged("Island") do
		local ring = island:FindFirstChild("SafeRing", true)
		if ring and ring:IsA("BasePart") then
			TweenService:Create(ring, TweenInfo.new(0.4), { Transparency = on and 0.25 or 1 }):Play()
		end
	end
end

function Water.start()
	for _, p in Players:GetPlayers() do
		trackPlayer(p)
	end
	Players.PlayerAdded:Connect(trackPlayer)
	buildLines()
	local function addFoam(f: Instance)
		if f:IsA("BasePart") then
			table.insert(foamParts, f)
		end
	end
	for _, f in CollectionService:GetTagged("ShoreFoam") do
		addFoam(f)
	end
	CollectionService:GetInstanceAddedSignal("ShoreFoam"):Connect(addFoam)
	task.spawn(function()
		while true do
			scanRainbow()
			task.wait(2)
		end
	end)
	RunService.RenderStepped:Connect(function(dt)
		updateTint(dt)
		updateRiders(dt)
		updateLines(dt)
		animateTagged(dt)
		local t = os.clock()
		local hue = (t * 0.25) % 1
		for i, p in rainbowParts do
			local c = Color3.fromHSV((hue + i * 0.04) % 1, 0.7, 1)
			p.Color = c
			for _, tex in p:GetChildren() do
				if tex:IsA("Texture") then
					tex.Color3 = c
				end
			end
		end
		for _, f in foamParts do
			f.Transparency = 0.2 + 0.3 * (0.5 + 0.5 * math.sin(t * 1.6))
			f.Size = Vector3.new(f.Size.X, 0.2, 3 + math.sin(t * 1.6) * 1.2)
		end
	end)
end

return Water
