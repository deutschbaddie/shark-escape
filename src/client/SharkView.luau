-- Draws and animates every shark on this client.
-- Real sharks: rigged .glb imports in ReplicatedStorage/Assets/Sharks, driven
-- bone-by-bone in code (swim wave, menacing jaw, bite lunge, dive, breach).
-- Missing imports fall back to a part-built shark so the game always runs.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local SharkFallback = require(Shared.SharkFallback)
local Fx = require(script.Parent.Fx)
local UI = require(script.Parent.UI)

local SharkView = {}

local player = Players.LocalPlayer
local VARIANTS = { "Baby", "Hammerhead", "Tiger", "GreatWhite", "Mecha", "Megalodon" }
local STATE_NAMES = { "chase", "circle", "leave", "bite" }
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
	local freq = chasing and 9 or (sh.state == "leave" and 5 or 6.5)
	sh.phase += dt * freq
	local w = sh.phase
	local amp = chasing and 1.25 or 1

	-- jaw
	local jaw = 0.06 + 0.04 * math.sin(now * 2.3)
	if chasing then
		jaw = 0.24 + 0.08 * math.sin(now * 3.1)
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
	if sh.state == "leave" then
		sh.sinkT = math.min(sh.sinkT + dt / 2.2, 1)
		sink = sh.sinkT
		pitch -= 0.28 * sink
	end

	local e = sh.extra
	local yOverride: number? = e and e.y
	if yOverride then
		pitch = e.pitch or 0
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

RunService.RenderStepped:Connect(function(dt)
	local now = os.clock()
	for _, sh in sharks do
		if sh.extra and sh.extra.update then
			sh.extra.update(sh, dt, now)
		else
			-- extrapolate the last snapshot, then ease toward it
			local ahead = math.min(now - sh.lastSnap, 0.2)
			local spd = sh.state == "chase" and (sh.extra and 0 or 1) or 0.6
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
		sh.wakeEmitter.Enabled = sh.state ~= "leave" or sh.sinkT < 0.5
	end
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
		if state == "leave" and sh.state ~= "leave" then
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
local eatenConn: RBXScriptConnection? = nil

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

local function eatenCinematic(sh: Shark?)
	local cam = Workspace.CurrentCamera
	Fx.bigWord("CHOMP!", UI.C.red, 1.1)
	Fx.shake(6)
	Fx.flash(Color3.fromRGB(255, 40, 60), 0.6, 0.2)
	local tint = Instance.new("ColorCorrectionEffect")
	tint.TintColor = Color3.fromRGB(255, 150, 160)
	tint.Contrast = 0.2
	tint.Parent = Lighting
	hideCharacter(true)
	if sh then
		cam.CameraType = Enum.CameraType.Scriptable
		local t0 = os.clock()
		if eatenConn then
			eatenConn:Disconnect()
		end
		eatenConn = RunService.RenderStepped:Connect(function()
			local fwd = Vector3.new(-math.sin(sh.yaw), 0, -math.cos(sh.yaw))
			local mouth = sh.pos + fwd * sh.L * 0.25 + Vector3.new(0, sh.L * 0.02, 0)
			-- inside the mouth looking out past the teeth, closing in
			local k = math.clamp((os.clock() - t0) / 0.9, 0, 1)
			cam.CFrame = CFrame.lookAt(mouth - fwd * sh.L * 0.05 * k, mouth + fwd * 10 + Vector3.new(0, 2 - k * 4, 0))
			cam.FieldOfView = 70 - k * 25
		end)
	end
	task.delay(Config.Shark.eatenTime - 0.15, function()
		Fx.flash(Color3.new(0, 0, 0), 0.4, 0)
	end)
	task.delay(Config.Shark.eatenTime, function()
		if eatenConn then
			eatenConn:Disconnect()
			eatenConn = nil
		end
		cam.CameraType = Enum.CameraType.Custom
		cam.FieldOfView = 70
		tint:Destroy()
		hideCharacter(false)
	end)
end

Remotes.get("SharkEvent").OnClientEvent:Connect(function(kind, data)
	if kind ~= "bite" then
		return
	end
	local sh = sharks[data.id]
	local at = Vector3.new(data.x, 0.5, data.z)
	if sh then
		sh.biteT = os.clock()
	end
	Fx.splash(at, sh and math.clamp(sh.L / 10, 0.8, 3) or 1.2)
	Fx.ring(at, Color3.fromRGB(255, 255, 255), sh and sh.L * 1.2 or 16)
	Fx.sound("chomp", 0.8, 1.1, at)
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if hrp and (hrp.Position - at).Magnitude < 60 then
		Fx.shake(2)
	end
	if data.victim == player.UserId then
		if data.result == "eaten" then
			eatenCinematic(sh)
		elseif data.result == "shield" then
			Fx.bigWord("🛡️ SHIELD!", UI.C.sky, 1)
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
