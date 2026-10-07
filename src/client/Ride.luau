-- Ride controller: on the water your character stops walking and handles
-- like its ride. Each ride has its own feel (Config.RideFeel): how fast it
-- gets going, how it coasts, turns, slides, leans, bobs and hops.
-- Only drives the local character; poses for everyone live in Water.luau.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = game.ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Layout = require(Shared.Layout)
local Fx = require(script.Parent.Fx)

local Ride = {}
local player = Players.LocalPlayer

local GRAVITY = 110

type Rig = {
	char: Model,
	hrp: BasePart,
	hum: Humanoid,
	att: Attachment,
	lv: LinearVelocity,
	ao: AlignOrientation,
}

local rig: Rig? = nil
local active = false
local heading = 0
local roll = 0
local vy = 0
local airborne = false
local hopQueued = false
local controls: any = nil

local function getControls()
	if controls then
		return controls
	end
	local ok, mod = pcall(function()
		return require(player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule"))
	end)
	if ok and mod then
		controls = mod:GetControls()
	end
	return controls
end

-- input as a flat world direction (camera relative), magnitude 0..1
local function moveInput(hum: Humanoid): Vector3
	local c = getControls()
	local mv = c and c:GetMoveVector() or Vector3.zero
	if mv.Magnitude < 0.01 then
		local md = hum.MoveDirection
		return Vector3.new(md.X, 0, md.Z)
	end
	local cam = Workspace.CurrentCamera
	local look = cam.CFrame.LookVector * Vector3.new(1, 0, 1)
	local right = cam.CFrame.RightVector * Vector3.new(1, 0, 1)
	if look.Magnitude < 0.01 then
		return Vector3.zero
	end
	local d = right.Unit * mv.X + look.Unit * -mv.Z
	return d.Magnitude > 1 and d.Unit or d
end

local function yawOf(v: Vector3): number
	return math.atan2(-v.X, -v.Z)
end

local function turnToward(a: number, b: number, step: number): number
	local d = (b - a + math.pi) % (2 * math.pi) - math.pi
	return a + math.clamp(d, -step, step)
end

local function approach(v: number, target: number, step: number): number
	if v < target then
		return math.min(v + step, target)
	end
	return math.max(v - step, target)
end

----------------------------------------------------------------- animation on/off
local function setAnimate(char: Model, on: boolean)
	local animate = char:FindFirstChild("Animate")
	if animate and animate:IsA("LocalScript") then
		animate.Enabled = on
	end
	if not on then
		local hum = char:FindFirstChildOfClass("Humanoid")
		local animator = hum and hum:FindFirstChildOfClass("Animator")
		if animator then
			for _, track in animator:GetPlayingAnimationTracks() do
				track:Stop(0.1)
			end
		end
	end
end

----------------------------------------------------------------- enter / exit
local function build(char: Model): Rig?
	local hrp = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hrp or not hum then
		return nil
	end
	local att = Instance.new("Attachment")
	att.Name = "RideAttachment"
	att.Parent = hrp
	local lv = Instance.new("LinearVelocity")
	lv.Attachment0 = att
	lv.RelativeTo = Enum.ActuatorRelativeTo.World
	lv.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	lv.ForceLimitsEnabled = true
	lv.MaxForce = 0
	lv.Enabled = false
	lv.Parent = hrp
	local ao = Instance.new("AlignOrientation")
	ao.Mode = Enum.OrientationAlignmentMode.OneAttachment
	ao.Attachment0 = att
	ao.Responsiveness = 35
	ao.MaxTorque = math.huge
	ao.Enabled = false
	ao.Parent = hrp
	return { char = char, hrp = hrp, hum = hum, att = att, lv = lv, ao = ao }
end

local function enter(r: Rig)
	active = true
	local look = r.hrp.CFrame.LookVector
	heading = yawOf(look)
	roll, vy, airborne = 0, 0, false
	r.hum.PlatformStand = true
	r.lv.MaxForce = r.hrp.AssemblyMass * 900
	r.lv.Enabled = true
	r.ao.Enabled = true
	setAnimate(r.char, false)
end

local function exit(r: Rig)
	active = false
	r.lv.Enabled = false
	r.ao.Enabled = false
	r.hum.PlatformStand = false
	setAnimate(r.char, true)
	r.hum:ChangeState(Enum.HumanoidStateType.Running)
end

----------------------------------------------------------------- per frame
local function rest(r: Rig): number
	-- HRP height when standing on the water floor
	return Config.FLOOR_TOP + r.hum.HipHeight + r.hrp.Size.Y / 2
end

local function step(dt: number)
	local r = rig
	if not r or not r.hrp.Parent then
		return
	end
	local hrp, hum = r.hrp, r.hum
	local pos = hrp.Position
	local wet = Layout.inWater(pos) and not Layout.islandAt(pos, 0) and hum.Health > 0 and not hrp.Anchored
	if wet ~= active then
		if wet then
			enter(r)
		else
			exit(r)
		end
	end
	if not active then
		return
	end
	local feel = Config.feel(r.char:GetAttribute("Ride") :: string?)
	local top = math.max(hum.WalkSpeed, 8)
	local t = os.clock()

	-- steering: the ride turns toward your input at its own rate
	local input = moveInput(hum)
	local m = math.min(input.Magnitude, 1)
	local before = heading
	if m > 0.05 then
		heading = turnToward(heading, yawOf(input), feel.turn * dt)
	end
	local yawRate = ((heading - before + math.pi) % (2 * math.pi) - math.pi) / math.max(dt, 1e-3)
	local fwd = Vector3.new(-math.sin(heading), 0, -math.cos(heading))
	local side = Vector3.new(math.cos(heading), 0, -math.sin(heading))

	-- throttle along the nose, slide sideways until grip catches it
	local v = hrp.AssemblyLinearVelocity
	local vf = v:Dot(fwd)
	local vs = v:Dot(side)
	local align = m > 0.05 and math.clamp(input.Unit:Dot(fwd) * 0.5 + 0.5, 0, 1) or 0
	local target = top * m * align
	local rate = (target > vf) and (top / feel.accel) or (top / feel.coast)
	vf = approach(vf, target, rate * dt)
	vs *= math.exp(-feel.grip * dt)

	-- height: bob on the surface, or fall back down after a hop
	local base = rest(r)
	local bob = math.sin(t * feel.bobSpeed) * feel.bob
	local porpoise = 0
	if feel.porpoise and vf > top * 0.4 then
		porpoise = math.max(0, math.sin(t * feel.bobSpeed)) * feel.bob * 1.4
	end
	local targetY = base + bob * 0.5 + porpoise
	if hopQueued and not airborne then
		airborne = true
		vy = feel.hop or 28
		Fx.splash(Vector3.new(pos.X, 0.4, pos.Z), 0.8)
	end
	hopQueued = false
	if airborne then
		vy -= GRAVITY * dt
		if pos.Y <= targetY and vy < 0 then
			airborne = false
			Fx.splash(Vector3.new(pos.X, 0.4, pos.Z), 1)
		end
	else
		vy = (targetY - pos.Y) * 10
	end
	r.lv.VectorVelocity = fwd * vf + side * vs + Vector3.new(0, vy, 0)

	-- attitude: lean into turns, nose up at speed, idle wobble
	local speedK = math.clamp(vf / top, 0, 1)
	roll += (math.clamp(-yawRate * feel.lean * (0.3 + speedK), -0.6, 0.6) - roll) * math.min(dt * 6, 1)
	local pitch = (feel.plane or 0) * speedK * 2.2 + math.cos(t * feel.bobSpeed) * feel.bob * 0.05
	if feel.porpoise then
		pitch += math.cos(t * feel.bobSpeed) * porpoise * 0.25
	end
	if airborne then
		pitch += math.clamp(vy / 80, -0.4, 0.4)
	end
	local wobble = (feel.wobble or 0) * math.sin(t * 1.3) * (1 - speedK * 0.6)
	r.ao.CFrame = CFrame.Angles(0, heading + wobble, 0) * CFrame.Angles(pitch, 0, roll)
end

----------------------------------------------------------------- setup
local function onCharacter(char: Model)
	if rig then
		rig.att:Destroy()
		rig.lv:Destroy()
		rig.ao:Destroy()
	end
	rig = nil
	active = false
	char:WaitForChild("HumanoidRootPart", 10)
	char:WaitForChild("Humanoid", 10)
	rig = build(char)
end

function Ride.isRiding(): boolean
	return active
end

function Ride.start()
	if player.Character then
		task.spawn(onCharacter, player.Character)
	end
	player.CharacterAdded:Connect(onCharacter)
	UserInputService.JumpRequest:Connect(function()
		if active then
			hopQueued = true
		end
	end)
	RunService.PreSimulation:Connect(step)
end

return Ride
