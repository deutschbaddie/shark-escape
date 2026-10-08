-- First-session guide. One step at a time, each with a 3D arrow:
--   0  swim out and grab a bubble
--   1  bring it back to your dock
--   2  step on the pad to collect coins
--   3  shark drill: a harmless practice shark chases you back to safety
--   4  buy your first ride at the Ride Shop
--   5  done (server stops the new-player shark grace)
-- The step is saved on the server (profile.tut); the client only advances it.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
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
local Guide = require(script.Parent.Guide)

local Onboarding = {}
local C = UI.C
local player = Players.LocalPlayer

local DONE = 5
local step = -1 -- local copy, never behind the server

local function point(at: Vector3?, label: string?)
	Guide.set("tut", at, label)
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
		hint = "Your tank makes cash. Step on the green pad!"
	end
	if step == 3 then
		at, label, hint = drillTick(pos)
	end
	if step == 4 then
		local nxt = HUD.nextRide(d)
		if not nxt or nxt.order > 2 then
			advance(5)
		elseif d.coins >= nxt.price then
			at, label = Layout.RideShopPad + Vector3.new(0, 1, 0), "Ride Shop"
			hint = ("%s Buy the %s at the Ride Shop!"):format(nxt.icon, nxt.name)
		else
			-- not enough yet: keep them on the loop that earns coins
			if d.carrying then
				at, label = plot and Layout.tankPos(plot) + Vector3.new(0, 4, 0), "Your dock"
			elseif d.pending >= 1 and plot then
				at, label = Layout.padPos(plot), "Collect!"
			else
				at, label = nearestBubble(pos), "Grab it!"
			end
			hint = ("$%s / $%s for the %s"):format(UI.short(d.coins), UI.short(nxt.price), nxt.name)
		end
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
		if step >= DONE then
			conn:Disconnect()
			point(nil)
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
