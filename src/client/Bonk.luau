-- Noodle Bonk on this client (server: Bonk.luau, Config.Bonk / Noodles).
--   The button   "Bonk" at sea (Q on keyboard, Y on a gamepad), with a
--                cooldown sweep; it glows when a shark is charging you and a
--                bonk would land.
--   The swing    procedural, layered on top of whatever ride pose you're in
--                (Water.overlays): a wind-up over the shoulder with a lean
--                back, a fast overhead whack with a lean in, then a springy
--                settle. A foam noodle appears in the hand for the swing; its
--                tip lags behind (trails back on the wind-up, whips forward
--                on the hit, wobbles after). Everyone sees everyone's swing
--                (character attribute "BonkAt").
--   The hit      a burst of little stars, a ring and a squeak where it lands;
--                the one who got bonked is shoved, popped up and spun round
--                (Ride.knock).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = game.ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Layout = require(Shared.Layout)
local Remotes = require(Shared.Remotes)
local UI = require(script.Parent.UI)
local Fx = require(script.Parent.Fx)
local Notify = require(script.Parent.Notify)
local State = require(script.Parent.State)
local Water = require(script.Parent.Water)
local Ride = require(script.Parent.Ride)
local SharkView = require(script.Parent.SharkView)

local Bonk = {}
local player = Players.LocalPlayer
local T = UI.T

local DUR = 0.5 -- the whole swing
local WIND, HIT = 0.28, 0.42 -- (fractions of DUR: wind-up ends, the whack lands)
local LA, LB, THICK = 2.6, 2.8, 0.75 -- noodle: grip half, tip half, thickness

type Swing = { start: number, parts: { BasePart }, color: Color3 }
local swings: { [Model]: Swing } = {}

local button: TextButton
local cover: Frame
local readyAt, sharkReadyAt = 0, 0
local stopPulse: (() -> ())? = nil
local taught = false
local pressedAt = -10

----------------------------------------------------------------- the move
local function lerp(a: number, b: number, k: number): number
	return a + (b - a) * k
end

local function outCubic(k: number): number
	return 1 - (1 - k) ^ 3
end

-- the pose of the swing at fraction u: shoulder / elbow / waist / off-arm
-- angles, and how far the noodle tip bends (+ = trailing back)
type Pose = { sh: number, shOut: number, el: number, wPitch: number, wYaw: number, off: number, bend: number }
local WOUND: Pose = { sh = 2.75, shOut = -0.3, el = 1.15, wPitch = 0.2, wYaw = -0.45, off = 0.6, bend = 0.55 }
local STRUCK: Pose = { sh = 1.3, shOut = 0.05, el = 0.12, wPitch = -0.34, wYaw = 0.38, off = -0.2, bend = -0.95 }

local function pose(u: number): Pose
	if u < WIND then
		local k = outCubic(u / WIND)
		return { sh = WOUND.sh * k, shOut = WOUND.shOut * k, el = WOUND.el * k, wPitch = WOUND.wPitch * k,
			wYaw = WOUND.wYaw * k, off = WOUND.off * k, bend = WOUND.bend * k }
	elseif u < HIT then
		local k = ((u - WIND) / (HIT - WIND)) ^ 2 -- accelerating into the hit
		local f = {} :: any
		for key, a in WOUND :: any do
			f[key] = lerp(a, (STRUCK :: any)[key], k)
		end
		return f
	end
	-- the settle: ease back to the ride pose with a springy wobble
	local r = (u - HIT) / (1 - HIT)
	local back = 1 - outCubic(r)
	local wob = math.sin(r * math.pi * 3) * (1 - r) ^ 2
	return { sh = STRUCK.sh * back + wob * 0.15, shOut = STRUCK.shOut * back, el = STRUCK.el * back + wob * 0.1,
		wPitch = STRUCK.wPitch * back - wob * 0.06, wYaw = STRUCK.wYaw * back, off = STRUCK.off * back,
		bend = STRUCK.bend * back * math.cos(r * math.pi * 4) }
end

local function noodleColor(char: Model): Color3
	local tier = char:GetAttribute("Noodle")
	local n = Config.Noodles[typeof(tier) == "number" and tier or 1] or Config.Noodles[1]
	return n.color
end

local function part(color: Color3): Part
	local p = Instance.new("Part")
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
	p.Shape = Enum.PartType.Cylinder
	p.Material = Enum.Material.SmoothPlastic
	p.Color = color
	p.Size = Vector3.new(0.1, 0.1, 0.1)
	p.Parent = Workspace
	return p
end

local function play(char: Model)
	local old = swings[char]
	if old then
		for _, p in old.parts do
			p:Destroy()
		end
	end
	local color = noodleColor(char)
	local grip = part(color)
	local tip = part(color:Lerp(Color3.new(1, 1, 1), 0.15))
	local cap = part(color:Lerp(Color3.new(1, 1, 1), 0.35)) -- (the end cap catches the light)
	cap.Shape = Enum.PartType.Ball
	swings[char] = { start = os.clock(), parts = { grip, tip, cap }, color = color }
	local hrp = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local at = hrp and hrp.Position
	if char == player.Character then
		Fx.sound("rebirthWhoosh", 0.35, 2.2)
	elseif at then
		Fx.sound("rebirthWhoosh", 0.3, 2.2, at)
	end
end

-- the swing on the joints (Water layers it over the ride pose each frame)
table.insert(Water.overlays, function(char)
	local sw = swings[char]
	if not sw then
		return nil
	end
	local u = (os.clock() - sw.start) / DUR
	if u >= 1 then
		return nil
	end
	local f = pose(u)
	return {
		RightShoulder = CFrame.Angles(f.sh, 0, f.shOut),
		RightElbow = CFrame.Angles(f.el, 0, 0),
		Waist = CFrame.Angles(f.wPitch, f.wYaw, 0),
		LeftShoulder = CFrame.Angles(f.off, 0, -f.off * 0.4), -- (the other arm swings up for balance)
	}
end)

-- the noodle follows the hand (after the joints have moved this frame)
local function updateNoodles()
	local now = os.clock()
	for char, sw in swings do
		local u = (now - sw.start) / DUR
		if u >= 1.15 or not char.Parent then
			for _, p in sw.parts do
				p:Destroy()
			end
			swings[char] = nil
			continue
		end
		local hand = (char:FindFirstChild("RightHand") or char:FindFirstChild("Right Arm")) :: BasePart?
		if not hand then
			continue
		end
		local grip = hand.CFrame * CFrame.new(0, hand.Name == "Right Arm" and -1 or -0.15, 0)
		-- pops into the hand, shrinks away after
		local s = math.clamp(u / 0.08, 0, 1) * math.clamp((1.15 - u) / 0.15, 0, 1)
		local f = pose(math.min(u, 0.999))
		local th = THICK * s
		local g, t, cap = sw.parts[1], sw.parts[2], sw.parts[3]
		local up = CFrame.Angles(0, 0, math.pi / 2) -- (cylinders run along X: stand them on the arm's line)
		g.Size = Vector3.new(LA * s, th, th)
		g.CFrame = grip * CFrame.new(0, -LA / 2 * s, 0) * up
		local joint = grip * CFrame.new(0, -LA * s, 0) * CFrame.Angles(f.bend, 0, 0)
		t.Size = Vector3.new(LB * s, th * 0.95, th * 0.95)
		t.CFrame = joint * CFrame.new(0, -LB / 2 * s, 0) * up
		cap.Size = Vector3.one * th * 1.05
		cap.CFrame = joint * CFrame.new(0, -LB * s, 0)
	end
end

----------------------------------------------------------------- hits
local STAR = Color3.fromRGB(255, 225, 80)

-- the impact: a white ring, little stars flying out, a squeak
local function impact(at: Vector3, shield: boolean)
	Fx.ring(at, shield and Color3.fromRGB(120, 210, 255) or Color3.new(1, 1, 1), 16)
	Fx.sparkle(at + Vector3.new(0, 2, 0), shield and Color3.fromRGB(120, 210, 255) or STAR, 22)
	Fx.sound(shield and "dodge" or "duckSqueak", 0.9, 0.9 + math.random() * 0.35, at)
	for i = 1, 6 do
		local p = Instance.new("Part")
		p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
		p.Material = Enum.Material.Neon
		p.Color = i % 2 == 0 and Color3.new(1, 1, 1) or STAR
		p.Size = Vector3.one * 0.7
		p.Parent = Workspace
		local a = i / 6 * math.pi * 2
		local dir = Vector3.new(math.cos(a), 0.6 + math.random() * 0.5, math.sin(a))
		local from = at + Vector3.new(0, 2.5, 0)
		local t0 = os.clock()
		local conn
		conn = RunService.RenderStepped:Connect(function()
			local t = os.clock() - t0
			if t > 0.45 then
				conn:Disconnect()
				p:Destroy()
				return
			end
			local k = t / 0.45
			p.CFrame = CFrame.new(from + dir * 7 * outCubic(k) - Vector3.new(0, 6 * k * k, 0)) * CFrame.Angles(t * 12, t * 9, 0)
			p.Size = Vector3.one * 0.7 * (1 - k)
		end)
	end
end

----------------------------------------------------------------- the button
local function myRoot(): BasePart?
	local char = player.Character
	return char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function atSea(): boolean
	local hrp = myRoot()
	return hrp ~= nil and Layout.inWater(hrp.Position) and not Layout.islandAt(hrp.Position, 0) and not hrp.Anchored
end

-- someone carrying raid loot within a swing of me (on the sand too)
local function lootNear(reach: number): boolean
	local me = myRoot()
	if not me then
		return false
	end
	for _, p in Players:GetPlayers() do
		local char = p ~= player and p.Character
		local hrp = char and char:GetAttribute("RaidLoot") and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if hrp and (hrp.Position - me.Position).Magnitude <= reach + 6 then
			return true
		end
	end
	return false
end

local function myNoodle(): any
	local d = State.data
	for _, n in Config.Noodles do
		if n.pass and d and d.passes and d.passes[n.pass] then
			return n
		end
	end
	return Config.Noodles[math.clamp(d and d.noodle or 1, 1, #Config.Noodles)]
end

local function press()
	local d = State.data
	if not (d and d.tut >= 5 and (atSea() or lootNear(myNoodle().reach))) or os.clock() < readyAt then
		return
	end
	readyAt = os.clock() + myNoodle().cooldown
	pressedAt = os.clock()
	local char = player.Character
	if char then
		play(char) -- (right away: the server's "BonkAt" for us is skipped)
	end
	State.action("bonk")
end

local function buildButton()
	local gui = Instance.new("ScreenGui")
	gui.Name = "Bonk"
	UI.hideInCutscenes(gui)
	gui.ResetOnSpawn = false
	gui.Parent = player:WaitForChild("PlayerGui")
	UI.autoScale(gui)
	button = UI.button(gui, UI.TOUCH and "Bonk" or "Bonk  [Q]", T.pink, press, {
		Size = UDim2.fromOffset(150, 62), Position = UDim2.new(1, -24, 1, -168), AnchorPoint = Vector2.new(1, 1), Visible = false })
	cover = UI.frame(button, { Name = "Cooldown", Size = UDim2.fromScale(1, 0), Position = UDim2.fromScale(0, 1), AnchorPoint = Vector2.new(0, 1),
		BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.45, ZIndex = button.ZIndex + 5 })
	UI.corner(cover, UI.R.button)
end

-- a shark charging me that a bonk would reach right now
local function sharkInReach(): boolean
	local me = SharkView.myHunter()
	local hrp = myRoot()
	if not (me and hrp) or me.state ~= "chase" and me.state ~= "lunge" then
		return false
	end
	local head = me.pos + Vector3.new(-math.sin(me.yaw), 0, -math.cos(me.yaw)) * me.L * 0.38
	return Vector2.new(head.X - hrp.Position.X, head.Z - hrp.Position.Z).Magnitude <= myNoodle().reach + 6
end

local function tick()
	local d = State.data
	local loot = d ~= nil and lootNear(myNoodle().reach)
	local show = d ~= nil and d.tut >= 5 and (atSea() or loot)
	button.Visible = show
	if not show then
		if stopPulse then
			stopPulse()
			stopPulse = nil
		end
		return
	end
	local cd = myNoodle().cooldown
	local left = math.max(0, readyAt - os.clock())
	cover.Size = UDim2.fromScale(1, math.clamp(left / cd, 0, 1))
	-- a shark charging and in reach: the button glows (that's the lesson)
	local glow = left <= 0 and ((os.clock() >= sharkReadyAt and sharkInReach()) or loot)
	button.BackgroundColor3 = glow and T.gold or T.pink
	if glow and not stopPulse then
		stopPulse = UI.pulse(button)
		if not taught and (d.playtime or 0) < 3600 then
			taught = true
			Notify.toast(UI.TOUCH and "Tap Bonk to daze it!" or "Press Q to daze it!", T.gold)
		end
	elseif not glow and stopPulse then
		stopPulse()
		stopPulse = nil
	end
end

----------------------------------------------------------------- start
local function watch(char: Model)
	char:GetAttributeChangedSignal("BonkAt"):Connect(function()
		if char == player.Character and os.clock() - pressedAt < 1.5 then
			return -- (we already played it on the press; laggy echoes too)
		end
		play(char)
	end)
end

local function track(p: Player)
	if p.Character then
		watch(p.Character)
	end
	p.CharacterAdded:Connect(watch)
end

function Bonk.start()
	buildButton()
	for _, p in Players:GetPlayers() do
		track(p)
	end
	Players.PlayerAdded:Connect(track)
	RunService.RenderStepped:Connect(updateNoodles)
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc >= 0.1 then
			acc = 0
			tick()
		end
	end)
	UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and (input.KeyCode == Enum.KeyCode.Q or input.KeyCode == Enum.KeyCode.ButtonY) then
			press()
		end
	end)
	Remotes.get("Notify").OnClientEvent:Connect(function(kind, d)
		if typeof(d) ~= "table" then
			return
		end
		if kind == "bonkHit" then
			impact(Vector3.new(d.x, d.y, d.z), d.shield == true)
		elseif kind == "bonked" then
			-- you got bonked: shoved, popped up, spun round
			Ride.knock(Vector3.new(d.x, 0, d.z), d.shield and Config.Bonk.knock * 0.4 or Config.Bonk.knock)
			Fx.shake(1.4)
			if d.shield then
				Notify.toast("Your shield blocked a bonk", Color3.fromRGB(120, 210, 255))
			elseif d.lost then
				Notify.toast((d.n or 1) > 1 and ("Bonked! Your %d creatures spilled"):format(d.n) or ("Bonked! Your %s popped out"):format(tostring(d.lost)),
					Color3.fromRGB(255, 120, 200))
			else
				Notify.toast(("Bonked by %s!"):format(tostring(d.by)), Color3.fromRGB(255, 120, 200))
			end
		elseif kind == "bonkedLoot" then
			Notify.toast((d.n or 1) > 1 and ("%d creatures spilled! Grab them!"):format(d.n) or ("Knocked loose: %s! Grab it!"):format(tostring(d.name)), T.gold)
		elseif kind == "bonkShark" then
			sharkReadyAt = os.clock() + (d.cooldown or Config.Bonk.sharkCooldown)
			Notify.toast("Shark dazed! Go!", T.gold)
			Fx.nearMiss()
		end
	end)
end

return Bonk
