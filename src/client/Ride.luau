-- Ride controller: on the water your character stops walking and handles
-- like its ride. Each ride has its own feel (Config.RideFeel): how fast it
-- gets going, how it coasts, turns, slides, leans, bobs and hops.
-- Only drives the local character; poses for everyone live in Water.luau.
--
-- Steering is camera-relative like walking (push the stick where you want
-- to go), tuned so it never fights you:
--   carve     the nose turns toward your input; speed follows the nose (a
--             little slides out, more on low-grip rides), turns are quicker
--             when slow
--   whip      ask for the way you came while moving: brake, spin round in
--             under half a second, then launch back to full speed
--   reverse   ask for the way behind you from a stop: the ride backs up
--             (a tap = a little reverse); keep holding and it swings its
--             nose round and drives off (a J-turn)
--   latch     after a whip, small stick moves steer relative to the new
--             course, so a Follow camera swinging round (phones) can't
--             make you circle; a clearly new direction or letting go ends it

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
local roll = 0
local vy = 0
local airborne = false
local hopQueued = false
local controls: any = nil
local lastPos: Vector3? = nil

-- steering tuning (see the header)
local TURN_BOOST = 1.4 -- on top of each ride's turn rate
local SLOW_TURN = 1.7 -- turn-rate multiplier at a standstill (1 at full speed)
local CARRY = 0.85 -- share of a turn the speed follows (the rest slides out)
local WHIP_AT = math.rad(110) -- input this far off the nose = turn around
local WHIP_DONE = math.rad(25)
local WHIP_RATE = 7.5 -- rad/s at least (180 degrees in ~0.4 s)
local WHIP_SPEED = 0.35 -- brake to this share of top speed while spinning
local BRAKE = 0.2 -- seconds from full speed to a stop when braking hard
local LAUNCH = 0.6 -- seconds of double acceleration after a whip
local REVERSE_AT = math.rad(140) -- input this far off the nose from a stop = reverse
local REVERSE_SPEED = 0.45
local REVERSE_SWING = 0.4 -- hold reverse this long and the nose swings round
local LATCH_KEEP = math.rad(60) -- stick moves within this of the latched direction steer relative to it

export type Steer = { heading: number, whip: boolean, launch: number, reverse: number, latchYaw: number?, latchMv: Vector3? }
local steerState: Steer = { heading = 0, whip = false, launch = 0, reverse = 0 }

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

-- input as a flat world direction (camera relative), magnitude 0..1, plus
-- the raw stick/keys (camera space) so a whip can hold its target
local function moveInput(hum: Humanoid): (Vector3, Vector3?)
	local c = getControls()
	local mv = c and c:GetMoveVector() or Vector3.zero
	if mv.Magnitude < 0.01 then
		local md = hum.MoveDirection
		return Vector3.new(md.X, 0, md.Z), nil
	end
	local cam = Workspace.CurrentCamera
	local look = cam.CFrame.LookVector * Vector3.new(1, 0, 1)
	local right = cam.CFrame.RightVector * Vector3.new(1, 0, 1)
	if look.Magnitude < 0.01 then
		return Vector3.zero, nil
	end
	local d = right.Unit * mv.X + look.Unit * -mv.Z
	return d.Magnitude > 1 and d.Unit or d, mv
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

local function wrap(a: number): number
	return (a + math.pi) % (2 * math.pi) - math.pi
end

-- One step of steering + throttle. Pure (no instances) so
-- tools/balance/steer.py can simulate it. v = current flat velocity; returns the new flat velocity, the
-- yaw rate (for leaning) and "whip" when a turn-around just started.
function Ride.steer(st: Steer, input: Vector3, mv: Vector3?, v: Vector3, feel: Config.RideFeel, top: number, dt: number): (Vector3, number, string?)
	local m = math.min(input.Magnitude, 1)
	local fwd0 = Vector3.new(-math.sin(st.heading), 0, -math.cos(st.heading))
	local speed = v:Dot(fwd0)
	local speedK = math.clamp(speed / top, 0, 1)
	local event = nil

	-- where the stick points. After a whip the target is latched: small stick
	-- moves steer relative to it (whatever the camera does meanwhile); a new
	-- direction (over 60 degrees away) or letting go goes back to camera-relative
	local want = m > 0.05 and yawOf(input) or nil
	local nudge = st.latchMv and mv and wrap(yawOf(mv) - yawOf(st.latchMv)) or nil
	if st.latchYaw and nudge and math.abs(nudge) < LATCH_KEEP then
		want = st.latchYaw + nudge
	else
		st.latchYaw, st.latchMv = nil, nil
	end
	local off = want and math.abs(wrap(want - st.heading)) or 0

	-- modes
	if not want then
		st.whip, st.reverse = false, 0
	elseif st.whip then
		if off < WHIP_DONE then
			-- done; the target stays latched until the stick moves, so a
			-- camera swinging round behind you doesn't turn you back again
			st.whip = false
			st.launch = LAUNCH
		end
	elseif st.reverse > 0 or (off > REVERSE_AT and speed < top * 0.3) then
		if off > WHIP_AT then
			st.reverse += dt
			if st.reverse > REVERSE_SWING then -- J-turn: swing the nose round
				st.whip, st.reverse = true, 0
				st.latchYaw, st.latchMv = want, mv
				event = "whip"
			end
		else
			st.reverse = 0
		end
	elseif off > WHIP_AT then
		st.whip = true
		st.latchYaw, st.latchMv = want, mv
		event = "whip"
	end
	st.launch = math.max(st.launch - dt, 0)

	-- turn the nose
	local before = st.heading
	if want and st.reverse == 0 then
		local rate = feel.turn * TURN_BOOST * (SLOW_TURN - (SLOW_TURN - 1) * speedK)
		if st.whip then
			rate = math.max(rate * 2, WHIP_RATE)
		end
		st.heading = turnToward(st.heading, want, rate * dt)
	end
	local turned = wrap(st.heading - before)

	-- forward speed follows the nose round a carve (not while backing up)
	local flat = v
	if speed > 0 then
		flat = CFrame.Angles(0, turned * CARRY, 0) * flat
	end
	local fwd = Vector3.new(-math.sin(st.heading), 0, -math.cos(st.heading))
	local side = Vector3.new(math.cos(st.heading), 0, -math.sin(st.heading))
	local vf, vs = flat:Dot(fwd), flat:Dot(side)

	-- throttle
	local target, rate
	if st.reverse > 0 then
		target = -top * REVERSE_SPEED * m
		rate = top / math.max(feel.accel, 0.3)
	elseif st.whip then
		target = math.min(vf, top * WHIP_SPEED)
		rate = top / BRAKE
	else
		local align = want and math.clamp(math.cos(off) * 0.5 + 0.5, 0, 1) or 0
		target = top * m * align
		if vf < 0 then
			rate = top / BRAKE -- stop backing up at once
		elseif target > vf then
			rate = (top / feel.accel) * (st.launch > 0 and 2 or 1)
		else
			rate = top / feel.coast
		end
	end
	vf = approach(vf, target, rate * dt)
	vs *= math.exp(-feel.grip * dt)
	return fwd * vf + side * vs, turned / math.max(dt, 1e-3), event
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
	steerState = { heading = yawOf(look), whip = false, launch = 0, reverse = 0 }
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
	if r.hum.Health > 0 and not r.hrp.Anchored then
		r.hum:ChangeState(Enum.HumanoidStateType.Running)
	end
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
	-- teleported (gate bounce, respawn): take the new facing
	if lastPos and (pos - lastPos).Magnitude > 40 then
		steerState = { heading = yawOf(hrp.CFrame.LookVector), whip = false, launch = 0, reverse = 0 }
	end
	lastPos = pos
	local feel = Config.feel(r.char:GetAttribute("Ride") :: string?)
	local top = math.max(hum.WalkSpeed, 8)
	local t = os.clock()

	-- steering + throttle (Ride.steer)
	local input, mv = moveInput(hum)
	local flat, yawRate, event = Ride.steer(steerState, input, mv, hrp.AssemblyLinearVelocity * Vector3.new(1, 0, 1), feel, top, dt)
	local heading = steerState.heading
	local vf = flat:Dot(Vector3.new(-math.sin(heading), 0, -math.cos(heading)))
	if event == "whip" and not airborne then
		Fx.splash(Vector3.new(pos.X, 0.4, pos.Z), 1.1)
		Fx.sound("splash", 0.35, 1.25)
	end

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
	r.lv.VectorVelocity = flat + Vector3.new(0, vy, 0)

	-- attitude: lean into turns, nose up at speed, idle wobble
	local speedK = math.clamp(vf / top, 0, 1)
	-- turning left raises yaw; a positive roll leans left, so lean = +yawRate
	roll += (math.clamp(yawRate * feel.lean * (0.3 + speedK), -0.6, 0.6) - roll) * math.min(dt * 6, 1)
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
