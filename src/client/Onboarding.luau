-- First-session guide. One step at a time, each with a 3D arrow:
--   0  swim out and grab a bubble
--   1  bring it back to your dock
--   2  step on the pad to collect coins
--   3  shark drill: a harmless practice shark chases you back to safety
--   4  buy your first ride (finger on the NEXT RIDE button)
--   5  done (server stops the new-player shark grace)
-- The step is saved on the server (profile.tut); the client only advances it.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")

local Shared = game.ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Layout = require(Shared.Layout)
local Remotes = require(Shared.Remotes)
local UI = require(script.Parent.UI)
local Fx = require(script.Parent.Fx)
local State = require(script.Parent.State)
local Water = require(script.Parent.Water)
local HUD = require(script.Parent.HUD)
local SharkView = require(script.Parent.SharkView)

local Onboarding = {}
local C = UI.C
local player = Players.LocalPlayer

local DONE = 5
local step = -1 -- local copy, never behind the server

----------------------------------------------------------------- guide arrow
-- A beam from your feet to the target plus a bouncing marker above it.
local guideFolder = Instance.new("Folder")
guideFolder.Name = "Guide"
guideFolder.Parent = Workspace

local target = Instance.new("Part")
target.Name = "GuideTarget"
target.Anchored = true
target.CanCollide = false
target.CanQuery = false
target.CanTouch = false
target.Transparency = 1
target.Size = Vector3.new(0.2, 0.2, 0.2)
target.Parent = guideFolder

local targetAtt = Instance.new("Attachment")
targetAtt.Parent = target

local beam = Instance.new("Beam")
beam.Attachment1 = targetAtt
beam.FaceCamera = true
beam.Width0 = 1.4
beam.Width1 = 0.6
beam.Segments = 24
beam.CurveSize0 = 6
beam.CurveSize1 = -6
beam.LightEmission = 1
beam.LightInfluence = 0
beam.Color = ColorSequence.new(C.gold)
beam.Transparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0.85),
	NumberSequenceKeypoint.new(0.25, 0.15),
	NumberSequenceKeypoint.new(1, 0.1),
})
beam.Enabled = false
beam.Parent = target

local marker = Instance.new("BillboardGui")
marker.Size = UDim2.fromOffset(150, 110)
marker.StudsOffset = Vector3.new(0, 6, 0)
marker.AlwaysOnTop = true
marker.LightInfluence = 0
marker.Enabled = false
marker.Parent = target
local markerText = UI.outlined(marker, "", { Size = UDim2.new(1, 0, 0, 34), TextColor3 = C.gold })
local markerArrow = UI.outlined(marker, "⬇️", { Size = UDim2.new(1, 0, 0, 64), Position = UDim2.fromOffset(0, 40) })

local feetAtt: Attachment? = nil
local function ensureFeet()
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return
	end
	if not feetAtt or feetAtt.Parent ~= hrp then
		local a = Instance.new("Attachment")
		a.Name = "GuideFeet"
		a.Position = Vector3.new(0, -2, 0)
		a.Parent = hrp
		feetAtt = a
		beam.Attachment0 = a
	end
end

local function point(at: Vector3?, label: string?)
	if not at then
		beam.Enabled = false
		marker.Enabled = false
		return
	end
	ensureFeet()
	target.Position = at
	markerText.Text = label or ""
	beam.Enabled = feetAtt ~= nil
	marker.Enabled = true
end

----------------------------------------------------------------- finger on the ride button
local finger: TextLabel? = nil
local function showFinger(on: boolean)
	if on and not finger then
		finger = UI.outlined(HUD.rideButton(), "👇", {
			Size = UDim2.fromOffset(64, 64), Position = UDim2.new(0.5, 0, 0, -4), AnchorPoint = Vector2.new(0.5, 1), ZIndex = 5,
		})
	elseif not on and finger then
		finger:Destroy()
		finger = nil
	end
end

----------------------------------------------------------------- helpers
local function myRoot(): BasePart?
	local char = player.Character
	return char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function myPlot(): CFrame?
	local d = State.data
	return d and d.plot > 0 and Layout.Plots[d.plot] or nil
end

local function nearestBubble(pos: Vector3): Vector3?
	local best, bestD = nil, math.huge
	for _, b in CollectionService:GetTagged("Bubble") do
		local shell = b:IsA("Model") and b.PrimaryPart
		-- only bubbles in zones you can actually swim into
		local zone = shell and Config.zoneById(b:GetAttribute("Zone"))
		if shell and zone and zone.gate <= (State.data and State.data.speed or 0) then
			local d = (shell.Position - pos).Magnitude
			if d < bestD then
				best, bestD = shell.Position, d
			end
		end
	end
	return best
end

local function advance(to: number)
	if to > step then
		step = to
		State.action("tut", to)
	end
end

----------------------------------------------------------------- shark drill (step 3)
-- A slow, client-only Baby shark. It can't hurt you; getting caught just
-- restarts the drill. Paused while a real attack is happening.
local drill = {
	state = "idle", -- idle | chase | leave | pause
	shark = nil :: any,
	t = 0,
	realAttack = false,
}

local function drillEnd(result: string)
	local sh = drill.shark
	if sh then
		sh.state = "leave"
		task.delay(2.5, SharkView.removeLocal, sh)
	end
	drill.shark = nil
	drill.state = result == "abort" and "idle" or "leave"
	drill.t = os.clock()
	Water.setSafeGlow(drill.realAttack)
end

local function drillStart(pos: Vector3)
	local zone = Config.zoneAt(pos.Z) or Config.Zones[1]
	local from = Vector3.new(
		math.clamp(pos.X + math.random(-20, 20), -Config.LANE_WIDTH / 2 + 6, Config.LANE_WIDTH / 2 - 6),
		0,
		math.min(pos.Z + 45, Config.OCEAN_END - 8)
	)
	local yaw = math.atan2(-(pos.X - from.X), -(pos.Z - from.Z))
	drill.state = "chase"
	drill.t = os.clock()
	Water.setSafeGlow(true)
	Fx.bigWord("🦈 SHARK DRILL!", C.red, 1.2)
	Fx.shake(1)
	drill.shark = SharkView.spawnLocal(zone.shark, zone.sharkLength, from, yaw, function(sh, dt)
		if sh.state ~= "chase" then
			-- swim off and sink (SharkView animates the dive)
			sh.pos += Vector3.new(-math.sin(sh.yaw), 0, -math.cos(sh.yaw)) * 14 * dt
			return
		end
		local hrp = myRoot()
		if not hrp then
			return
		end
		local to = Vector3.new(hrp.Position.X - sh.pos.X, 0, hrp.Position.Z - sh.pos.Z)
		local want = math.atan2(-to.X, -to.Z)
		local d = (want - sh.yaw + math.pi) % (2 * math.pi) - math.pi
		sh.yaw += math.clamp(d, -4 * dt, 4 * dt)
		-- always slower than you, so escaping is about reacting, not stats
		local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		local speed = math.max((hum and hum.WalkSpeed or 16) * 0.6, 9)
		sh.pos += Vector3.new(-math.sin(sh.yaw), 0, -math.cos(sh.yaw)) * math.min(speed * dt, math.max(to.Magnitude - 1, 0))
	end)
end

local function drillTick(pos: Vector3): (Vector3?, string?, string?)
	if drill.realAttack then
		if drill.shark then
			drillEnd("abort")
		end
		return nil, nil, nil
	end
	local safe = Layout.isSafe(pos)
	if drill.state == "idle" then
		if not safe then
			drillStart(pos)
		else
			-- lead them a little way into the water
			local plot = myPlot()
			local x = plot and plot.Position.X or pos.X
			return Vector3.new(x, 1, Config.SHORE_Z + 30), "Swim out!", "🦈 Shark drill! Swim out into the water..."
		end
	end
	if drill.state == "chase" then
		local sh = drill.shark
		if safe then
			drillEnd("safe")
			Fx.bigWord("✅ SAFE!", C.green, 1.2)
			HUD.toast("Sharks attack every minute. Sand and islands are always safe!", C.green, 4.5)
			advance(4)
			return nil, nil, nil
		end
		if sh then
			local head = sh.pos + Vector3.new(-math.sin(sh.yaw), 0, -math.cos(sh.yaw)) * sh.L * 0.38
			if Vector2.new(pos.X - head.X, pos.Z - head.Z).Magnitude < 3.5 then
				SharkView.biteLocal(sh)
				Fx.bigWord("CHOMP! (just practice)", C.red, 1.1)
				Fx.shake(3)
				HUD.toast("In a real attack you'd lose what you're carrying. Try again!", C.red, 3.5)
				drillEnd("caught")
				drill.state = "pause"
				return nil, nil, nil
			end
		end
		local safeAt = Layout.nearestSafe(pos)
		return safeAt + Vector3.new(0, 2, 0), "SAFE!", "🦈 GET TO THE SAND OR AN ISLAND!"
	end
	if drill.state == "pause" and os.clock() - drill.t > 3 then
		drill.state = "idle"
	end
	return nil, nil, nil
end

Remotes.get("SharkEvent").OnClientEvent:Connect(function(kind)
	if kind == "warning" or kind == "hunt" then
		drill.realAttack = true
	elseif kind == "clear" then
		drill.realAttack = false
	end
end)

----------------------------------------------------------------- per-frame
local function update()
	local d = State.data
	local hrp = myRoot()
	if not d or step >= DONE or not hrp then
		point(nil)
		showFinger(false)
		HUD.hint(nil)
		return
	end
	local pos = hrp.Position
	local plot = myPlot()
	local at, label, hint = nil, nil, nil

	if step == 0 then
		if d.carrying then
			advance(1)
		else
			at, label = nearestBubble(pos), "Grab it!"
			hint = "🫧 Swim out and grab a creature bubble!"
		end
	end
	if step == 1 then
		if not d.carrying and #d.tank > 0 then
			advance(2)
		elseif not d.carrying then
			-- a shark ate it on the way back: go grab another
			at, label = nearestBubble(pos), "Grab it!"
			hint = "🫧 Grab another bubble!"
		elseif plot then
			at, label = Layout.tankPos(plot) + Vector3.new(0, 4, 0), "Your dock"
			hint = "🏠 Bring it back to your dock!"
		end
	end
	if step == 2 and plot then
		at, label = Layout.padPos(plot), "Collect!"
		hint = "💰 Your tank makes coins. Step on the green pad!"
	end
	if step == 3 then
		at, label, hint = drillTick(pos)
	end
	if step == 4 then
		local nxt = HUD.nextRide(d)
		if not nxt or nxt.order > 2 then
			advance(5)
		elseif d.coins >= nxt.price then
			hint = ("%s Buy the %s for more speed!"):format(nxt.icon, nxt.name)
		else
			-- not enough yet: keep them on the loop that earns coins
			if d.carrying then
				at, label = plot and Layout.tankPos(plot) + Vector3.new(0, 4, 0), "Your dock"
			elseif d.pending >= 1 and plot then
				at, label = Layout.padPos(plot), "Collect!"
			else
				at, label = nearestBubble(pos), "Grab it!"
			end
			hint = ("💰 %s / %s coins for the %s"):format(UI.short(d.coins), UI.short(nxt.price), nxt.name)
		end
		showFinger(nxt ~= nil and d.coins >= nxt.price)
	else
		showFinger(false)
	end

	point(at, label)
	HUD.hint(hint)
end

----------------------------------------------------------------- start
function Onboarding.start()
	local d = State.wait()
	step = d.tut
	-- returning players who already did the basics skip ahead
	if step < DONE and d.rides.Duck then
		advance(DONE)
	end
	if step >= DONE then
		return
	end

	State.Changed:Connect(function(data)
		if data.tut > step then
			step = data.tut
		end
	end)
	Remotes.get("Notify").OnClientEvent:Connect(function(kind)
		if kind == "collect" and step == 2 then
			advance(3)
		elseif kind == "ride" and step == 4 then
			advance(5)
		end
	end)

	local conn
	conn = RunService.Heartbeat:Connect(function()
		update()
		local t = os.clock()
		markerArrow.Position = UDim2.fromOffset(0, 40 + math.abs(math.sin(t * 4)) * -12)
		if finger then
			finger.Position = UDim2.new(0.5, 0, 0, -4 - math.abs(math.sin(t * 5)) * 10)
		end
		if step >= DONE then
			conn:Disconnect()
			point(nil)
			showFinger(false)
			HUD.hint(nil)
			if drill.shark then
				drillEnd("abort")
			end
			Fx.bigWord("🎉 YOU'RE READY!", C.gold, 1.4)
			HUD.toast("Unlock deeper zones for better creatures. Watch for sharks!", C.blue, 5)
			Fx.confetti(myRoot() and (myRoot() :: BasePart).Position or Vector3.zero)
		end
	end)
end

return Onboarding
