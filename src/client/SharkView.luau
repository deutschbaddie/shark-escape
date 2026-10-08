-- Draws and animates every shark on this client.
-- Real sharks: rigged .glb imports in ReplicatedStorage/Assets/Sharks, driven
-- bone-by-bone in code (swim wave, menacing jaw, bite lunge, dive, breach).
-- Missing imports fall back to a part-built shark so the game always runs.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local SharkFallback = require(Shared.SharkFallback)
local Layout = require(Shared.Layout)
local Creatures = require(Shared.Creatures)
local Fx = require(script.Parent.Fx)
local UI = require(script.Parent.UI)
local Guide = require(script.Parent.Guide)
local TweenService = game:GetService("TweenService")

local SharkView = {}

local player = Players.LocalPlayer
local VARIANTS = { "Baby", "Hammerhead", "Tiger", "GreatWhite", "Mecha", "Megalodon" }
-- wire codes from server Sharks.luau ("chase" = the charge)
local STATE_NAMES = { "chase", "circle", "leave", "bite", "stalk", "overshoot" }
local BONES = { "Root", "Head", "Jaw", "Spine2", "Spine3", "Spine4", "Tail", "PecL", "PecR" }

local folder = Instance.new("Folder")
folder.Name = "Sharks"
folder.Parent = Workspace

type Rig = {
	model: Model,
	bones: { [string]: Bone },
	rest: { [string]: CFrame },
	parts: { [string]: BasePart }, -- fallback rig
	calib: CFrame,
	fallback: boolean,
}

type Shark = {
	id: number,
	variant: string,
	L: number,
	rig: Rig,
	pos: Vector3,
	yaw: number,
	targetPos: Vector3,
	targetYaw: number,
	lastSnap: number,
	state: string,
	phase: number,
	biteT: number,
	sinkT: number,
	roll: number,
	wake: Part,
	wakeEmitter: ParticleEmitter,
	victim: number,
	alive: boolean,
	dived: boolean?,
	extra: { [string]: any }?,
}

local sharks: { [number]: Shark } = {}

----------------------------------------------------------------- templates
local function findTemplate(variant: string): Instance?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local lib = assets and assets:FindFirstChild("Sharks")
	if not lib then
		return nil
	end
	return lib:FindFirstChild("Shark" .. variant) or lib:FindFirstChild(variant)
end

local function yawOfDir(d: Vector3): number
	return math.atan2(-d.X, -d.Z)
end

local function buildRig(variant: string, L: number): Rig
	local template = findTemplate(variant)
	if template then
		local model: Model
		if template:IsA("Model") then
			model = template:Clone()
		else
			model = Instance.new("Model")
			template:Clone().Parent = model
		end
		local bones = {}
		for _, d in model:GetDescendants() do
			if d:IsA("Bone") and table.find(BONES, d.Name) then
				bones[d.Name] = d
			elseif d:IsA("BasePart") then
				d.Anchored = true
				d.CanCollide = false
				d.CanQuery = false
				d.CanTouch = false
				d.CastShadow = false
			end
		end
		if bones.Head and bones.Tail and bones.Jaw then
			model.Parent = folder
			-- scale to the design length (head bone sits at 14%, tail at 89%)
			local span = (bones.Head.WorldPosition - bones.Tail.WorldPosition).Magnitude
			local now = span / 0.75
			if math.abs(now - L) / L > 0.04 then
				model:ScaleTo(model:GetScale() * L / now)
			end
			-- calibrate: whatever axes the importer chose, nose -> -Z, centered
			local pivot = model:GetPivot()
			local h = pivot:PointToObjectSpace(bones.Head.WorldPosition)
			local t = pivot:PointToObjectSpace(bones.Tail.WorldPosition)
			local f = h - t
			local yaw0 = yawOfDir(Vector3.new(f.X, 0, f.Z))
			local center = (h + t) / 2
			local calib = CFrame.Angles(0, -yaw0, 0) * CFrame.new(-center)
			model:PivotTo(CFrame.new() * calib)
			local rest = {}
			for name, b in bones do
				rest[name] = b.WorldCFrame.Rotation
			end
			return { model = model, bones = bones, rest = rest, parts = {}, calib = calib, fallback = false }
		end
		model:Destroy()
		warn(("[SharkView] %s template is missing Head/Jaw/Tail bones - using fallback"):format(variant))
	end
	local model = SharkFallback.build(variant, L)
	model.Parent = folder
	local parts = {}
	for _, n in { "Body", "Head", "Jaw", "Tail" } do
		parts[n] = model:FindFirstChild(n) :: BasePart
	end
	for _, d in model:GetChildren() do
		if d:IsA("BasePart") and not parts[d.Name] then
			d:SetAttribute("RestFromBody", parts.Body.CFrame:ToObjectSpace(d.CFrame))
		end
	end
	return { model = model, bones = {}, rest = {}, parts = parts, calib = CFrame.new(0, 0, -L * 0.05), fallback = true }
end

----------------------------------------------------------------- pose
local function setBone(rig: Rig, name: string, rot: CFrame)
	local b = rig.bones[name]
	if b then
		local r = rig.rest[name]
		b.Transform = r:Inverse() * rot * r
	end
end

local function animate(sh: Shark, dt: number, now: number)
	local L = sh.L
	local rig = sh.rig
	local chasing = sh.state == "chase"
	local stalking = sh.state == "stalk"
	local freq = chasing and 9 or (sh.state == "leave" and 5 or (stalking and 7.5 or 6.5))
	sh.phase += dt * freq
	local w = sh.phase
	local amp = chasing and 1.25 or 1

	-- jaw
	local jaw = 0.06 + 0.04 * math.sin(now * 2.3)
	if chasing then
		jaw = 0.24 + 0.08 * math.sin(now * 3.1)
	elseif stalking then
		jaw = 0.12 + 0.05 * math.sin(now * 1.9) -- slow, menacing
	end
	local lunge, pitch = 0, 0
	if sh.biteT > 0 then
		local t = now - sh.biteT
		if t < 0.14 then
			jaw = 0.95 * (t / 0.14)
		elseif t < 0.24 then
			jaw = 0.95
		elseif t < 0.32 then
			jaw = 0.95 * (1 - (t - 0.24) / 0.08)
		elseif t < 0.9 then
			jaw = 0.05 + 0.12 * math.abs(math.sin((t - 0.32) * 18)) -- chew chew
		else
			sh.biteT = 0
		end
		local k = math.clamp(t / 0.32, 0, 1)
		lunge = math.sin(k * math.pi) * L * 0.22
		pitch = math.sin(k * math.pi) * 0.45
	end

	-- dive when leaving
	local sink = 0
	if sh.state == "leave" or sh.dived then
		sh.sinkT = math.min(sh.sinkT + dt / 2.2, 1)
		sink = sh.sinkT
		pitch -= 0.28 * sink
	end

	local e = sh.extra
	local yOverride: number? = e and e.y
	if yOverride then
		pitch = e.pitch or 0
	end
	if e and e.jaw then
		jaw = e.jaw
	end

	if rig.fallback then
		local body = rig.parts.Body
		local base = CFrame.new(sh.pos.X, yOverride and (yOverride - L * 0.1) or (-L * 0.1 + lunge - sink * L * 0.7), sh.pos.Z)
			* CFrame.Angles(0, sh.yaw, 0) * CFrame.Angles(pitch, 0, sh.roll)
		body.CFrame = base * rig.calib
		local tail = rig.parts.Tail
		tail.CFrame = body.CFrame * CFrame.Angles(0, 0.35 * amp * math.sin(w - 3), 0) * (tail:GetAttribute("Rest") :: CFrame)
		local head = rig.parts.Head
		head.CFrame = body.CFrame * CFrame.Angles(0, -0.06 * math.sin(w), 0) * (head:GetAttribute("Rest") :: CFrame)
		local jawP = rig.parts.Jaw
		jawP.CFrame = head.CFrame * (head:GetAttribute("Rest") :: CFrame):Inverse() * (jawP:GetAttribute("Rest") :: CFrame) * CFrame.new(0, -jaw * L * 0.06, 0)
		for _, d in rig.model:GetChildren() do
			local rest = d:IsA("BasePart") and d:GetAttribute("RestFromBody") :: CFrame?
			if rest then
				(d :: BasePart).CFrame = body.CFrame * rest
			end
		end
		return
	end

	setBone(rig, "Head", CFrame.Angles(0, -0.07 * amp * math.sin(w), 0))
	setBone(rig, "Spine2", CFrame.Angles(0, 0.09 * amp * math.sin(w - 0.9), 0))
	setBone(rig, "Spine3", CFrame.Angles(0, 0.13 * amp * math.sin(w - 1.8), 0))
	setBone(rig, "Spine4", CFrame.Angles(0, 0.17 * amp * math.sin(w - 2.7), 0))
	setBone(rig, "Tail", CFrame.Angles(0, 0.24 * amp * math.sin(w - 3.6), 0))
	setBone(rig, "PecL", CFrame.Angles(0, 0, 0.12 * math.sin(w * 0.5)))
	setBone(rig, "PecR", CFrame.Angles(0, 0, -0.12 * math.sin(w * 0.5)))
	setBone(rig, "Jaw", CFrame.Angles(-jaw, 0, 0))

	local y = yOverride and (yOverride - L * 0.1) or (-L * 0.1 + lunge - sink * L * 0.7 + math.sin(now * 1.7 + sh.id) * L * 0.01)
	local k = CFrame.new(sh.pos.X, y, sh.pos.Z) * CFrame.Angles(0, sh.yaw, 0) * CFrame.Angles(pitch, 0, sh.roll)
	rig.model:PivotTo(k * rig.calib)
end

----------------------------------------------------------------- lifecycle
local function makeWake(L: number): (Part, ParticleEmitter)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Transparency = 1
	p.Size = Vector3.new(1, 0.2, 1)
	p.Parent = folder
	local e = Instance.new("ParticleEmitter")
	e.Texture = Fx.TEX.smoke
	e.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255))
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, L * 0.08), NumberSequenceKeypoint.new(1, L * 0.22) })
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
	e.Lifetime = NumberRange.new(0.8, 1.4)
	e.Rate = 40
	e.Speed = NumberRange.new(1, 3)
	e.SpreadAngle = Vector2.new(60, 10)
	e.EmissionDirection = Enum.NormalId.Top
	e.Orientation = Enum.ParticleOrientation.VelocityPerpendicular
	e.LockedToPart = false
	e.Parent = p
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(-L * 0.03, 0, 0)
	a0.Parent = p
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(L * 0.03, 0, 0)
	a1.Parent = p
	local trail = Instance.new("Trail")
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Lifetime = 1.4
	trail.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255))
	trail.Transparency = NumberSequence.new(0.25, 1)
	trail.WidthScale = NumberSequence.new(1, 3)
	trail.FaceCamera = false
	trail.Parent = p
	return p, e
end

local function create(id: number, variant: string, L: number, pos: Vector3, yaw: number): Shark
	local rig = buildRig(variant, L)
	local wake, emitter = makeWake(L)
	local sh: Shark = {
		id = id, variant = variant, L = L, rig = rig, pos = pos, yaw = yaw, targetPos = pos, targetYaw = yaw,
		lastSnap = os.clock(), state = "chase", phase = math.random() * 6, biteT = 0, sinkT = 0, roll = 0,
		wake = wake, wakeEmitter = emitter, victim = 0, alive = true,
	}
	sharks[id] = sh
	-- fin bursts out of the water
	Fx.splash(Vector3.new(pos.X, 0.5, pos.Z), math.clamp(L / 14, 0.6, 2.2))
	return sh
end

local function destroy(sh: Shark)
	sharks[sh.id] = nil
	sh.wakeEmitter.Enabled = false
	task.delay(1.5, function()
		sh.wake:Destroy()
	end)
	sh.rig.model:Destroy()
end

local function angleLerp(a: number, b: number, t: number): number
	local d = (b - a + math.pi) % (2 * math.pi) - math.pi
	return a + d * t
end

local updateDanger: (number) -> ()

----------------------------------------------------------------- your shark
-- While a shark is hunting YOU: a red ring on the water shows its circle and
-- the guide arrow points at the nearest safe spot. Obvious, not noisy.
local SEGMENTS = 28
local ringParts: { Part } = {}
for i = 1, SEGMENTS do
	local seg = Instance.new("Part")
	seg.Name = "DangerRing"
	seg.Anchored = true
	seg.CanCollide = false
	seg.CanQuery = false
	seg.CanTouch = false
	seg.CastShadow = false
	seg.Material = Enum.Material.Neon
	seg.Color = Color3.fromRGB(255, 50, 60)
	seg.Transparency = 1
	seg.Size = Vector3.new(1, 0.15, 0.6)
	seg.Parent = folder
	ringParts[i] = seg
end

function SharkView.myHunter(): any
	for id, sh in sharks do
		if id > 0 and sh.victim == player.UserId and (sh.state == "stalk" or sh.state == "chase" or sh.state == "overshoot") then
			return sh
		end
	end
	return nil
end

updateDanger = function(now: number)
	local me = SharkView.myHunter()
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not (me and hrp) then
		if ringParts[1].Transparency < 1 then
			for _, seg in ringParts do
				seg.Transparency = 1
			end
		end
		Guide.set("danger", nil)
		return
	end
	local p = hrp.Position
	local r = Vector2.new(me.pos.X - p.X, me.pos.Z - p.Z).Magnitude
	local charging = me.state == "chase"
	local pulse = 0.5 + 0.5 * math.sin(now * (charging and 18 or 6))
	-- a dashed red ring on the water at the shark's distance (spinning slowly)
	local segLen = 2 * math.pi * r / SEGMENTS * 0.6
	for i, seg in ringParts do
		local a = (i / SEGMENTS) * math.pi * 2 + now * 0.4
		seg.Size = Vector3.new(segLen, 0.15, charging and 0.9 or 0.6)
		seg.CFrame = CFrame.new(p.X + math.cos(a) * r, 0.2, p.Z + math.sin(a) * r) * CFrame.Angles(0, -a + math.pi / 2, 0)
		seg.Transparency = (charging and 0.05 or 0.3) + pulse * 0.25
	end
	local safeAt = Layout.nearestSafe(p)
	Guide.set("danger", safeAt + Vector3.new(0, 2, 0), "SAFE!")
end

RunService.RenderStepped:Connect(function(dt)
	local now = os.clock()
	for _, sh in sharks do
		if sh.extra and sh.extra.update then
			sh.extra.update(sh, dt, now)
		else
			-- extrapolate the last snapshot, then ease toward it
			local ahead = math.min(now - sh.lastSnap, 0.2)
			local spd = ({ chase = Config.Shark.chargeMult, circle = 0.3, leave = 0.7 } :: any)[sh.state] or 0
			local fwd = Vector3.new(-math.sin(sh.targetYaw), 0, -math.cos(sh.targetYaw))
			local goal = sh.targetPos + fwd * ahead * spd * (Config.zoneAt(sh.targetPos.Z) or Config.Zones[1]).sharkSpeed
			local a = 1 - math.exp(-dt * 12)
			sh.pos = sh.pos:Lerp(goal, a)
			local newYaw = angleLerp(sh.yaw, sh.targetYaw, 1 - math.exp(-dt * 10))
			local yawRate = ((newYaw - sh.yaw + math.pi) % (2 * math.pi) - math.pi) / math.max(dt, 1e-3)
			sh.roll += (math.clamp(-yawRate * 0.12, -0.4, 0.4) - sh.roll) * math.min(dt * 6, 1)
			sh.yaw = newYaw
		end
		animate(sh, dt, now)
		local fin = sh.pos + Vector3.new(-math.sin(sh.yaw), 0, -math.cos(sh.yaw)) * sh.L * 0.1
		sh.wake.CFrame = CFrame.new(fin.X, 0.15, fin.Z) * CFrame.Angles(0, sh.yaw, 0)
		sh.wakeEmitter.Enabled = sh.sinkT < 0.5 or not (sh.state == "leave" or sh.dived)
	end
	updateDanger(now)
end)

----------------------------------------------------------------- server feed
Remotes.get("Sharks").OnClientEvent:Connect(function(list)
	local seen = {}
	local now = os.clock()
	for _, row in list do
		local id, vi, x, z, yaw, st, L, victim = table.unpack(row)
		seen[id] = true
		local pos = Vector3.new(x, 0, z)
		local sh = sharks[id]
		if not sh then
			sh = create(id, VARIANTS[vi] or "GreatWhite", L, pos, yaw)
		end
		sh.targetPos = pos
		sh.targetYaw = yaw
		sh.lastSnap = now
		local state = STATE_NAMES[st] or "chase"
		if state == "leave" and sh.state ~= "leave" and not sh.dived then
			sh.sinkT = 0
		end
		sh.state = state
		sh.victim = victim
	end
	for id, sh in sharks do
		if id > 0 and not seen[id] then
			destroy(sh)
		end
	end
end)

----------------------------------------------------------------- bites
local function hideCharacter(hidden: boolean)
	local char = player.Character
	if not char then
		return
	end
	for _, d in char:GetDescendants() do
		if d:IsA("BasePart") or d:IsA("Decal") then
			(d :: any).LocalTransparencyModifier = hidden and 1 or 0
		end
	end
end

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local CHOMP_AT = 0.42 -- seconds from the start of the leap to the jaws closing

-- Everyone sees the bite: the shark bursts up out of the water, jaws wide,
-- snaps shut on the spot and arcs back down into a dive.
local function leap(sh: Shark, at: Vector3)
	local L = sh.L
	local p0 = sh.pos
	local d = flat(at - p0)
	local dir = d.Magnitude > 1 and d.Unit or Vector3.new(-math.sin(sh.yaw), 0, -math.cos(sh.yaw))
	local p1 = flat(at) - dir * L * 0.3
	local yaw = math.atan2(-dir.X, -dir.Z)
	local t0 = os.clock()
	local dur = 1.7
	local chomped, splashed = false, false
	Fx.splash(Vector3.new(p0.X, 0.5, p0.Z), math.clamp(L / 8, 1, 4))
	sh.extra = {
		update = function(s: Shark, dt: number, now: number)
			local e = s.extra :: any
			local t = now - t0
			s.yaw = angleLerp(s.yaw, yaw, math.min(dt * 14, 1))
			s.state = "chase"
			if t < CHOMP_AT then
				local k = t / CHOMP_AT
				s.pos = p0:Lerp(p1, 1 - (1 - k) ^ 2)
				e.y = math.sin(k * math.pi * 0.5) * L * 0.32
				e.pitch = 0.55 - 0.3 * k
				e.jaw = 0.95 * math.min(1, k * 2.5)
			else
				if not chomped then
					chomped = true
					Fx.splash(Vector3.new(at.X, 0.5, at.Z), math.clamp(L / 7, 1.2, 4))
					Fx.ring(Vector3.new(at.X, 0.5, at.Z), Color3.fromRGB(255, 255, 255), L * 1.4)
					Fx.sound("chomp", 0.9, 1.05, at)
				end
				local k = math.clamp((t - CHOMP_AT) / (dur - CHOMP_AT), 0, 1)
				local tc = t - CHOMP_AT
				s.pos = p1 + dir * L * 0.7 * k
				e.y = L * 0.32 * (1 - k * 1.9)
				e.pitch = 0.25 - 1.1 * k
				e.jaw = tc < 0.07 and 0.95 * (1 - tc / 0.07) or 0.04 + 0.1 * math.abs(math.sin(tc * 16))
				if k > 0.45 and not splashed then
					splashed = true
					Fx.splash(Vector3.new(s.pos.X, 0.5, s.pos.Z), math.clamp(L / 6, 1, 4))
				end
				if t >= dur then
					-- hand back to the server feed, staying under water
					s.extra = nil
					s.dived = true
					s.sinkT = 0.4
				end
			end
		end,
	}
end

----------------------------------------------------------------- the cutscene (victim only)
-- ~2.8s, three shots: low side angle as it surges in, close on the jaws for
-- the CHOMP (your pet gets pulled in), then a crane up as it dives. HUD hides,
-- letterbox bars slide in, fade to black, you wash up on the beach.
local cine = false
local bars: { Frame } = {}
local caption: TextLabel? = nil
local black: Frame? = nil

local function screenBits()
	if #bars > 0 then
		return
	end
	local screen = Fx.screen()
	for i, y in { 0, 1 } do
		bars[i] = UI.frame(screen, { Size = UDim2.fromScale(1, 0), Position = UDim2.fromScale(0, y), AnchorPoint = Vector2.new(0, y),
			BackgroundColor3 = Color3.new(0, 0, 0), ZIndex = 40, Name = "Letterbox" })
	end
	caption = UI.outlined(bars[2], "", { Size = UDim2.new(0.8, 0, 0.5, 0), Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = 41 })
	black = UI.frame(screen, { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 1, ZIndex = 45, Name = "Fade" })
end

local function setBars(on: boolean)
	screenBits()
	for _, b in bars do
		TweenService:Create(b, TweenInfo.new(0.25, Enum.EasingStyle.Quad), { Size = UDim2.fromScale(1, on and 0.11 or 0) }):Play()
	end
	if not on and caption then
		caption.Text = ""
	end
end

local function fade(to: number, time: number)
	screenBits()
	TweenService:Create(black :: Frame, TweenInfo.new(time), { BackgroundTransparency = to }):Play()
end

local function eatenCinematic(sh: Shark?, at: Vector3, carried: { r: string, m: string?, z: string?, s: number? }?)
	if cine then
		return
	end
	cine = true
	player:SetAttribute("Cinematic", true)
	local cam = Workspace.CurrentCamera
	cam.CameraType = Enum.CameraType.Scriptable
	setBars(true)
	local tint = Instance.new("ColorCorrectionEffect")
	tint.Contrast = 0.12
	tint.Saturation = 0.1
	tint.Parent = Lighting

	local L = sh and sh.L or 12
	local origin = sh and sh.pos or (at + Vector3.new(0, 0, L))
	local d = flat(at - origin)
	local dir = d.Magnitude > 1 and d.Unit or Vector3.new(0, 0, -1)
	local side = Vector3.new(dir.Z, 0, -dir.X)
	if side.X * at.X > 0 then
		side = -side -- keep the camera toward the middle of the lane, away from the walls
	end
	local up = Vector3.yAxis
	local ground = Vector3.new(at.X, 0, at.Z)

	local pet: Model? = nil
	local petStart = ground + up * 5.6
	if carried then
		pet = Creatures.build(carried.r, carried.m, 1.1, carried.z)
		pet:PivotTo(CFrame.new(petStart))
		pet.Parent = Workspace
	end

	local t0 = os.clock()
	local total = Config.Shark.eatenTime
	RunService:BindToRenderStep("SharkCinematic", Enum.RenderPriority.Camera.Value, function()
		local t = os.clock() - t0
		local head = ground + up * (L * 0.12)
		if sh and sh.rig.model.Parent then
			local e = sh.extra :: any
			head = sh.pos + Vector3.new(-math.sin(sh.yaw), 0, -math.cos(sh.yaw)) * L * 0.4 + up * ((e and e.y or 0) - L * 0.02)
		end
		local camPos, look, fov
		if t < CHOMP_AT then
			-- shot 1: low over the water, side-on; it's coming
			local k = t / CHOMP_AT
			camPos = ground + side * (L * 0.9 + 9) + up * 2.2 - dir * (L * 0.35 + 3) + dir * (k * 3)
			look = ground:Lerp(head, 0.45) + up * 1.5
			fov = 58 - 8 * k
		elseif t < 1.3 then
			-- shot 2: tight on the jaws, pushing in
			local k = (t - CHOMP_AT) / (1.3 - CHOMP_AT)
			camPos = ground + side * (L * 0.45 + 5.5 - k * 1.5) + up * (L * 0.18 + 2.5) + dir * (L * 0.12)
			look = head:Lerp(ground, 0.25)
			fov = 40
		else
			-- shot 3: crane up and back as it dives
			local k = math.clamp((t - 1.3) / (total - 1.3), 0, 1)
			local e = 1 - (1 - k) ^ 3
			camPos = ground - dir * (12 + L * 0.5) + side * 6 + up * (5 + 20 * e)
			look = ground + dir * (L * 0.4) - up
			fov = 55
		end
		cam.CFrame = CFrame.lookAt(camPos, look)
		cam.FieldOfView = fov
		local pm = pet
		if pm and pm.Parent then
			if t < CHOMP_AT then
				-- your creature panics above you
				pm:PivotTo(CFrame.new(petStart + up * math.sin(t * 20) * 0.25) * CFrame.Angles(0, t * 9, math.sin(t * 25) * 0.3))
			else
				-- ...and gets pulled into the jaws
				local k = math.clamp((t - CHOMP_AT) / 0.28, 0, 1)
				pm:PivotTo(CFrame.new(petStart:Lerp(head, k)) * CFrame.Angles(k * 4, t * 12, 0))
				pm:ScaleTo(math.max(0.05, 1 - k * 0.95))
				if k >= 1 then
					pm:Destroy()
				end
			end
		end
	end)

	task.delay(CHOMP_AT, function()
		hideCharacter(true)
		Fx.shake(5)
		Fx.flash(Color3.fromRGB(255, 40, 60), 0.35, 0.35)
		tint.TintColor = Color3.fromRGB(255, 190, 195)
		Fx.bigWord("CHOMP!", UI.C.red, 0.9)
		if caption then
			caption.Text = carried and ("The shark ate your %s!"):format(Config.fullName(carried.z, carried.r, carried.m, carried.s)) or "The shark got you!"
		end
	end)
	task.delay(total - 0.35, function()
		fade(0, 0.3)
	end)
	task.delay(total + 0.05, function()
		-- stay black until the server has washed us up on the beach
		local deadline = os.clock() + 1.2
		while os.clock() < deadline do
			local h = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if not h or (flat(h.Position) - flat(at)).Magnitude > 20 then
				break
			end
			task.wait()
		end
		RunService:UnbindFromRenderStep("SharkCinematic")
		cam.CameraType = Enum.CameraType.Custom
		cam.FieldOfView = 70
		setBars(false)
		tint:Destroy()
		hideCharacter(false)
		if pet and pet.Parent then
			pet:Destroy()
		end
		player:SetAttribute("Cinematic", false)
		fade(1, 0.45)
		cine = false
	end)
end

----------------------------------------------------------------- shark events
local function exclaim(sh: Shark)
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromScale(math.max(4, sh.L * 0.35), math.max(4, sh.L * 0.35))
	bb.StudsOffsetWorldSpace = Vector3.new(0, sh.L * 0.35 + 3, 0)
	bb.AlwaysOnTop = true
	bb.LightInfluence = 0
	bb.Adornee = sh.wake
	bb.Parent = sh.wake
	local t = UI.outlined(bb, "!", { TextColor3 = UI.C.red, Font = UI.NUMFONT })
	UI.pop(t, 2)
	task.delay(0.9, function()
		bb:Destroy()
	end)
end

Remotes.get("SharkEvent").OnClientEvent:Connect(function(kind, data)
	if kind == "charge" then
		local sh = sharks[data.id]
		if sh then
			exclaim(sh)
			Fx.sound("sharkCharge", 0.9, 1, Vector3.new(sh.pos.X, 1, sh.pos.Z))
		end
		if data.victim == player.UserId then
			-- the turn: a quick FOV punch so you feel it lock on
			Fx.shake(1.5)
			Fx.flash(Color3.fromRGB(255, 40, 60), 0.3, 0.75)
			local cam = Workspace.CurrentCamera
			if cam.CameraType == Enum.CameraType.Custom then
				cam.FieldOfView = 62
				TweenService:Create(cam, TweenInfo.new(0.4, Enum.EasingStyle.Back), { FieldOfView = 70 }):Play()
			end
		end
		return
	end
	if kind == "miss" then
		local sh = sharks[data.id]
		if sh then
			Fx.splash(Vector3.new(sh.pos.X, 0.5, sh.pos.Z), math.clamp(sh.L / 9, 1, 3))
		end
		if data.victim == player.UserId then
			Fx.bigWord("DODGED!", UI.C.sky, 0.9)
			Fx.sound("splash", 0.6, 1.3)
			Fx.sound("dodge", 0.8)
		end
		return
	end
	if kind ~= "bite" then
		return
	end
	local sh = sharks[data.id]
	local at = Vector3.new(data.px or 0, 0.5, data.pz or 0)
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if data.result == "eaten" then
		if sh then
			leap(sh, at)
		end
		if hrp and data.victim ~= player.UserId and (hrp.Position - at).Magnitude < 80 then
			task.delay(CHOMP_AT, Fx.shake, 2)
		end
		if data.victim == player.UserId then
			-- frame it where you actually are (you're held in place under the water)
			local here = hrp and Vector3.new(hrp.Position.X, 0.5, hrp.Position.Z) or at
			eatenCinematic(sh, here, data.r and { r = data.r, m = data.m, z = data.cz, s = data.cs } or nil)
		end
	elseif data.result == "shield" then
		if sh then
			sh.biteT = os.clock()
		end
		Fx.splash(at, sh and math.clamp(sh.L / 10, 0.8, 3) or 1.2)
		Fx.sound("chomp", 0.8, 1.2, at)
		if data.victim == player.UserId then
			Fx.bigWord("SHIELD!", UI.C.sky, 1)
			Fx.ring(at, UI.C.sky, 30)
			if hrp then
				local away = (hrp.Position - at) * Vector3.new(1, 0, 1)
				hrp.AssemblyLinearVelocity = (away.Magnitude > 0.1 and away.Unit or Vector3.new(0, 0, -1)) * 80 + Vector3.new(0, 45, 0)
			end
		end
	end
end)

----------------------------------------------------------------- local-only sharks
-- Practice shark (onboarding) and the warning breach use client-only ids < 0.
local localId = 0

function SharkView.spawnLocal(variant: string, L: number, pos: Vector3, yaw: number, update: (any, number, number) -> ()): any
	localId -= 1
	local sh = create(localId, variant, L, pos, yaw)
	sh.extra = { update = update }
	return sh
end

function SharkView.removeLocal(sh: any)
	if sharks[sh.id] then
		destroy(sh)
	end
end

function SharkView.biteLocal(sh: any)
	sh.biteT = os.clock()
	Fx.splash(sh.pos + Vector3.new(0, 0.5, 0), math.clamp(sh.L / 10, 0.8, 3))
end

-- the "oh no" moment: a shark leaps out of the water on the horizon
function SharkView.breach(variant: string, L: number, at: Vector3, faceYaw: number)
	local t0 = os.clock()
	local dur = 2.1
	local splashed = false
	local sh
	sh = SharkView.spawnLocal(variant, L, at, faceYaw, function(s, dt, now)
		local t = (now - t0) / dur
		if t >= 1 then
			task.defer(SharkView.removeLocal, s)
			return
		end
		s.state = "chase"
		local fwd = Vector3.new(-math.sin(faceYaw), 0, -math.cos(faceYaw))
		s.pos = at + fwd * (t * L * 1.6)
		-- override the vertical pose: leap arc + flip
		s.extra.y = math.sin(t * math.pi) * L * 1.1
		s.extra.pitch = 0.95 * math.cos(t * math.pi)
		if t > 0.85 and not splashed then
			splashed = true
			Fx.splash(s.pos + Vector3.new(0, 0.5, 0), math.clamp(L / 7, 1, 3.5))
		end
	end)
	return sh
end

function SharkView.count(): number
	local n = 0
	for id in sharks do
		if id > 0 then
			n += 1
		end
	end
	return n
end

SharkView.VARIANTS = VARIANTS
return SharkView
