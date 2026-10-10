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
local Rides = require(Shared.Rides)
local Rig = require(Shared.Rig)
local Fx = require(script.Parent.Fx)
local UI = require(script.Parent.UI)

local Water = {}
-- set by Bonk.luau: (character, its joints by name, time) -> layer a move on
-- top of the ride pose
Water.poseOverlay = nil :: ((Model, { [string]: any }, number) -> ())?
local player = Players.LocalPlayer
local Terrain = Workspace.Terrain

----------------------------------------------------------------- zone tint
local function zoneBlend(z: number, w: number): (Color3, number, Color3)
	local zones = Config.worldZones(w)
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
	local focus = cam.Focus.Position
	local col, clarity, tint = zoneBlend(focus.Z, Config.worldAt(focus))
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
	wasWet: boolean,
	joints: { [string]: any }, -- Motor6D or AnimationConstraint, by R15 joint name
	jointsStale: boolean,
	animate: LocalScript?,
	fit: Vector3?,
	fitKey: string?,
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
	-- wake color: rebirth tier, VIP gold; VIP also gets a tag over the head
	local owner = Players:GetPlayerFromCharacter(char)
	local function paintWake()
		local rb = owner and owner:GetAttribute("Rebirths")
		local vip = owner ~= nil and owner:GetAttribute("VIP") == true
		local c = Config.wakeColor(typeof(rb) == "number" and rb or 0, vip)
		trail.Color = ColorSequence.new(c or Color3.new(1, 1, 1))
		trail.LightEmission = c and 0.6 or 0
		spray.Color = ColorSequence.new(c and c:Lerp(Color3.new(1, 1, 1), 0.4) or Color3.fromRGB(210, 250, 255))
		local head = char:FindFirstChild("Head")
		local tag = head and head:FindFirstChild("VipTag")
		if vip and head and not tag then
			local bb = Instance.new("BillboardGui")
			bb.Name = "VipTag"
			bb.Size = UDim2.fromScale(2.6, 0.9)
			bb.StudsOffsetWorldSpace = Vector3.new(0, 2.4, 0)
			bb.LightInfluence = 0
			bb.MaxDistance = 120
			bb.Parent = head
			local t = UI.outlined(bb, "VIP", { Size = UDim2.fromScale(1, 1), TextColor3 = Config.VIP_WAKE })
			t.Font = UI.FONT
		elseif not vip and tag then
			tag:Destroy()
		end
	end
	if owner then
		paintWake()
		owner:GetAttributeChangedSignal("Rebirths"):Connect(paintWake)
		owner:GetAttributeChangedSignal("VIP"):Connect(paintWake)
	end
	local rider: Rider = {
		char = char, hrp = hrp, hum = hum, foam = foam, spray = spray, trail = trail,
		wasWet = false, joints = {}, jointsStale = true, animate = char:FindFirstChild("Animate") :: LocalScript?,
	}
	riders[char] = rider
	-- limbs swapped by an appearance load, or joints upgraded after spawn
	local function stale(d: Instance)
		if Rig.isJoint(d) or d:IsA("Attachment") then
			rider.jointsStale = true
			rider.fitKey = nil
		end
	end
	char.DescendantAdded:Connect(stale)
	char.DescendantRemoving:Connect(stale)
	char.AncestryChanged:Connect(function(_, parent)
		if not parent then
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

-- Ride poses live in Shared/Rig (one per stance). Each rider gets a fitted
-- Root offset so the pose lands on the ride for their body size (Rig.fit:
-- forward kinematics over the real joints). Applied after the Animator each
-- frame (PreSimulation) so they win; the local player's Animate script is
-- switched off while riding (Ride.luau), so there's no walk cycle on water.
local function refreshJoints(r: Rider): { Rig.Joint }
	local list = Rig.joints(r.char)
	table.clear(r.joints)
	for _, j in list do
		r.joints[j.Name] = j.inst
	end
	r.jointsStale = false
	return list
end

local function fitOffset(r: Rider, rideId: string, stance: string): Vector3
	local k = (r.char:GetAttribute("RideScale") :: number?) or 1
	local key = string.format("%s|%.3f|%.3f|%d", rideId, k, r.hum.HipHeight, os.clock() // 3)
	if r.fitKey == key and r.fit then
		return r.fit
	end
	local joints = refreshJoints(r)
	local fit = Rides.FIT[rideId] or Vector3.zero
	local drop = r.hum.HipHeight + r.hrp.Size.Y / 2
	local target = Vector3.new(0, fit.Y * k - drop, fit.Z * k)
	r.fit = Rig.fit(joints, r.hrp, stance, target) or Vector3.zero
	r.fitKey = key
	return r.fit
end

local function resetPose(r: Rider)
	for _, j in r.joints do
		if j.Parent then
			j.Transform = CFrame.new()
		end
	end
end

RunService.PreSimulation:Connect(function()
	local t = os.clock()
	for char, r in riders do
		if not r.wasWet then
			continue
		end
		if r.jointsStale then
			refreshJoints(r)
		end
		if r.joints.Waist then -- R15 only
			local speed = (r.hrp.AssemblyLinearVelocity * Vector3.new(1, 0, 1)).Magnitude
			local sway = math.clamp(speed / 60, 0.3, 1.5)
			local rideId = (char:GetAttribute("Ride") :: string?) or "Noodle"
			local stance = Config.feel(rideId).stance
			local pose = Rig.POSES[stance] or Rig.POSES.stand
			local offset = fitOffset(r, rideId, stance)
			-- in the shallows the body rises out of the ride (a noodle rider is
			-- chest-deep, which would drag on the ramp and catch the beach)
			local shallow = math.clamp((r.hrp.Position.Z - Config.SHORE_Z - Layout.RAMP_LEN) / 10, 0, 1)
			if offset.Y < 0 and shallow < 1 then
				offset = Vector3.new(offset.X, offset.Y * shallow, offset.Z)
			end
			for name, fn in pose do
				local j = r.joints[name]
				if j and j.Parent then
					j.Transform = name == "Root" and CFrame.new(offset) * fn(t, sway) or fn(t, sway)
				end
			end
			-- moves layered on top of the ride pose (the Noodle Bonk swing)
			if Water.poseOverlay then
				Water.poseOverlay(char, r.joints, t)
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
				resetPose(r)
			end
			if wet then
				Fx.splash(Vector3.new(pos.X, 0.4, pos.Z), 0.9)
				if char == myChar then
					Fx.sound("splash", 0.5, 1 + math.random() * 0.2)
				else
					Fx.sound("splash", 0.45, 1 + math.random() * 0.2, Vector3.new(pos.X, 1, pos.Z)) -- 3D
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
-- Bubble Rain bubbles (attribute DropAt): fall in from high up, hit the
-- water with a splash, bounce and settle into the usual bob
local DROP_H, DROP_T = 70, 1.1
local landed: { [Model]: boolean } = {}

local function animateTagged(dt: number)
	local t = os.clock()
	local now = Workspace:GetServerTimeNow()
	for _, m in CollectionService:GetTagged("Bubble") do
		if m:IsA("Model") and m.PrimaryPart then
			local base = m:GetAttribute("BaseCF") :: CFrame?
			if not base then
				base = m:GetPivot()
				m:SetAttribute("BaseCF", base)
			end
			local seed = (base :: CFrame).Position.X
			local y = math.sin(t * 2 + seed) * 0.5
			local dropAt = m:GetAttribute("DropAt")
			if typeof(dropAt) == "number" then
				local k = (now - dropAt) / DROP_T
				if k < 1 then
					y += DROP_H * (1 - math.max(k, 0)) ^ 2 -- (accelerating down)
				elseif not landed[m] then
					landed[m] = true
					local p = (base :: CFrame).Position
					Fx.splash(Vector3.new(p.X, 0.5, p.Z), 1.1)
					m.Destroying:Once(function()
						landed[m] = nil
					end)
				else
					local b = k - 1 -- (a little bounce after landing)
					y += math.abs(math.sin(b * 9)) * 2.2 * math.exp(-b * 4)
				end
			end
			m:PivotTo((base :: CFrame) * CFrame.new(0, y, 0) * CFrame.Angles(0, t * 0.8 + seed, 0))
		end
	end
	-- dock showcases: a slow turn and a gentle float
	for _, m in CollectionService:GetTagged("Showcase") do
		if m:IsA("Model") and m.PrimaryPart then
			local base = m:GetAttribute("BaseCF") :: CFrame?
			if not base then
				base = m:GetPivot()
				m:SetAttribute("BaseCF", base)
			end
			m:PivotTo((base :: CFrame) * CFrame.new(0, math.sin(t * 1.3) * 0.8, 0) * CFrame.Angles(0, t * 0.5, 0))
		end
	end
end

-- a new best creature on a dock pops in (grows from small, overshoots a
-- touch, settles) with a sparkle, if you're close enough to see it
CollectionService:GetInstanceAddedSignal("Showcase"):Connect(function(m)
	if not m:IsA("Model") then
		return
	end
	local cam = Workspace.CurrentCamera
	local at = m:GetPivot().Position
	if not cam or (cam.CFrame.Position - at).Magnitude > 260 then
		return
	end
	local t0 = os.clock()
	local conn
	conn = RunService.RenderStepped:Connect(function()
		local k = math.clamp((os.clock() - t0) / 0.6, 0, 1)
		if not m.Parent then
			conn:Disconnect()
			return
		end
		-- ease out back: 0.2 -> 1.08 -> 1
		local c1, c3 = 1.70158, 2.70158
		local e = 1 + c3 * (k - 1) ^ 3 + c1 * (k - 1) ^ 2
		pcall(m.ScaleTo, m, math.max(0.05, 0.2 + 0.8 * e))
		if k >= 1 then
			conn:Disconnect()
			pcall(m.ScaleTo, m, 1)
		end
	end)
	Fx.sparkle(at, Color3.fromRGB(255, 230, 120), 30)
end)

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


----------------------------------------------------------------- safe rings during attacks
function Water.setSafeGlow(on: boolean)
	for _, island in CollectionService:GetTagged("Island") do
		local ring = island:FindFirstChild("SafeRing", true)
		if ring and ring:IsA("BasePart") then
			TweenService:Create(ring, TweenInfo.new(0.4), { Transparency = on and 0.25 or 1 }):Play()
		end
	end
end

-- island shelter (SharkView drives it): the ring of an island you're sheltering
-- on drains green -> yellow -> red, then flashes red once it can't protect you
local RING_GREEN = Color3.fromRGB(80, 255, 140)
local RING_YELLOW = Color3.fromRGB(255, 220, 60)
local RING_RED = Color3.fromRGB(255, 50, 60)
local ringByIsland: { [number]: BasePart } = {}
local ringScanAt = -1e9

local function islandRing(i: number): BasePart?
	local ring = ringByIsland[i]
	if ring and ring.Parent then
		return ring
	end
	if os.clock() - ringScanAt < 2 then
		return nil
	end
	ringScanAt = os.clock()
	for _, model in CollectionService:GetTagged("Island") do
		local r = model:FindFirstChild("SafeRing", true)
		if r and r:IsA("BasePart") then
			local best, bestD = nil, math.huge
			for j, island in Layout.Islands do
				local d = Vector2.new(r.Position.X - island.pos.X, r.Position.Z - island.pos.Z).Magnitude
				if d < bestD then
					best, bestD = j, d
				end
			end
			if best and bestD < 4 then
				ringByIsland[best] = r
			end
		end
	end
	return ringByIsland[i]
end

-- frac = share of the shelter left (0 = used up), nil = back to normal
function Water.setIslandShelter(i: number, frac: number?)
	local ring = islandRing(i)
	if not ring then
		return
	end
	if frac == nil then
		ring.Color = RING_GREEN
	elseif frac > 0.5 then
		ring.Color = RING_YELLOW:Lerp(RING_GREEN, (frac - 0.5) * 2)
	elseif frac > 0 then
		ring.Color = RING_RED:Lerp(RING_YELLOW, frac * 2)
	else
		local pulse = 0.5 + 0.5 * math.sin(os.clock() * 12)
		ring.Color = RING_RED:Lerp(Color3.fromRGB(90, 0, 10), pulse)
		ring.Transparency = 0.1
	end
end

function Water.start()
	for _, p in Players:GetPlayers() do
		trackPlayer(p)
	end
	Players.PlayerAdded:Connect(trackPlayer)
	buildLines()
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
	end)
end

return Water
