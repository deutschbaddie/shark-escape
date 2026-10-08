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
local Notify = require(script.Parent.Notify)
local Prompts = require(script.Parent.Prompts)

local Onboarding = {}
local C = UI.C
local player = Players.LocalPlayer

local DONE = 5
-- the first grab is a tap (Prompts "tap"); after that grabs need a hold
local TAP_HINT = UI.TOUCH and "Swim to a bubble and TAP the button" or "Swim to a bubble and press E"
local HOLD_HINT = UI.TOUCH and "Swim to a bubble and HOLD the button" or "Swim to a bubble and HOLD E"
local step = -1 -- local copy, never behind the server

-- the tutorial banner: "STEP 2 of 5 · Bring it home" + what to do
local function tutBanner(title: string?, sub: string?, color: Color3?)
	if not title then
		Notify.clear("tut")
		return
	end
	Notify.banner(("STEP %d of %d · %s"):format(math.clamp(step + 1, 1, DONE), DONE, title), { key = "tut", sticky = true, priority = 3, sub = sub, color = color })
end

-- a quick "nice!" between steps
local CHEERS = { [1] = "NICE CATCH!", [2] = "IN THE TANK!", [3] = "CHA-CHING!", [4] = "SAFE!", [5] = "NEW RIDE!" }

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

local function advance(to: number, quiet: boolean?)
	if to > step then
		local cheer = CHEERS[to]
		step = to
		State.action("tut", to)
		if to == 1 then
			Prompts.setTeach("hold") -- the first grab was a tap; now learn to hold
		elseif to >= DONE then
			Prompts.setTeach(nil)
		end
		if cheer and to < DONE and not quiet then
			Notify.word(cheer, C.green, 0.8)
			Fx.sound("coin", 0.5, 1.2)
		end
	end
end

----------------------------------------------------------------- shark drill (step 3)
-- A slow, client-only Baby shark. It can't hurt you. Caught once: try again
-- with an even slower shark and the arrow pointing straight at the sand.
-- Caught twice: move on ("You'll get it next time!"), no endless retries.
-- Paused while a real attack is happening.
local drill = {
	state = "idle", -- idle | chase | leave | pause
	shark = nil :: any,
	t = 0,
	angle = 0,
	realAttack = false,
	catches = 0,
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
	drill.angle = math.atan2(from.Z - pos.Z, from.X - pos.X)
	drill.state = "chase"
	drill.t = os.clock()
	Water.setSafeGlow(true)
	Fx.bigWord("SHARK DRILL!", C.red, 1.2)
	Fx.shake(1)
	drill.shark = SharkView.spawnLocal(zone.shark, zone.sharkLength, from, yaw, function(sh, dt)
		if sh.state == "leave" then
			-- swim off and sink (SharkView animates the dive)
			sh.pos += Vector3.new(-math.sin(sh.yaw), 0, -math.cos(sh.yaw)) * 14 * dt
			return
		end
		local hrp = myRoot()
		if not hrp then
			return
		end
		local p = hrp.Position
		local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		local retry = drill.catches > 0
		local speed = math.max((hum and hum.WalkSpeed or 16) * (retry and 0.7 or 0.9), 10)
		local t = os.clock() - drill.t
		local to
		if t < 3.5 then
			-- like a real one: circle first (a tightening spiral)...
			drill.angle = (drill.angle or 0) + dt * 1.1
			local r = 26 - 10 * (t / 3.5)
			local goal = Vector3.new(p.X + math.cos(drill.angle) * r, 0, p.Z + math.sin(drill.angle) * r)
			to = Vector3.new(goal.X - sh.pos.X, 0, goal.Z - sh.pos.Z)
			sh.state = "stalk"
		else
			-- ...then charge: a touch slower than you and slow to turn, so
			-- heading for sand or swerving late both work (like the real one)
			to = Vector3.new(p.X - sh.pos.X, 0, p.Z - sh.pos.Z)
			sh.state = "chase"
		end
		if to.Magnitude > 0.1 then
			local want = math.atan2(-to.X, -to.Z)
			local d = (want - sh.yaw + math.pi) % (2 * math.pi) - math.pi
			local turn = sh.state == "chase" and (retry and 1.7 or 2.3) or 5
			sh.yaw += math.clamp(d, -turn * dt, turn * dt)
		end
		local pace = sh.state == "chase" and speed or speed * 1.3
		sh.pos += Vector3.new(-math.sin(sh.yaw), 0, -math.cos(sh.yaw)) * math.min(pace * dt, math.max(to.Magnitude - 1, 0))
	end)
end

local function drillTick(pos: Vector3): (Vector3?, string?, string?, string?)
	if drill.realAttack then
		if drill.shark then
			drillEnd("abort")
		end
		return nil, nil, "Shark drill", "Wait for the real sharks to leave..."
	end
	local safe = Layout.isSafe(pos)
	if drill.state == "idle" then
		if not safe then
			drillStart(pos)
		else
			-- lead them a little way into the water
			local plot = myPlot()
			local x = plot and plot.Position.X or pos.X
			return Vector3.new(x, 1, Config.SHORE_Z + 30), "Swim out!", "Shark drill!", "Swim out into the water... (it's just practice)"
		end
	end
	if drill.state == "chase" then
		local sh = drill.shark
		if safe then
			drillEnd("safe")
			Notify.toast("Sharks attack every minute or so. Sand and islands are always safe!", C.green)
			advance(4)
			return nil, nil, nil, nil
		end
		if sh then
			local head = sh.pos + Vector3.new(-math.sin(sh.yaw), 0, -math.cos(sh.yaw)) * sh.L * 0.38
			if Vector2.new(pos.X - head.X, pos.Z - head.Z).Magnitude < 3.5 then
				SharkView.biteLocal(sh)
				Fx.shake(3)
				drill.catches += 1
				drillEnd("caught")
				if drill.catches >= 2 then
					-- don't loop on failure: they've seen it, move on
					Notify.word("You'll get it next time!", C.gold, 1.2)
					Notify.toast("Sand and islands are always safe from sharks!", C.green)
					advance(4, true)
					return nil, nil, nil, nil
				end
				Notify.word("CHOMP! (just practice)", C.red, 1)
				Notify.toast("A real shark eats what you're carrying. Try again: it'll be slower!", C.red)
				drill.state = "pause"
				return nil, nil, "Shark drill", "Try again in a moment..."
			end
		end
		-- second try: the arrow points straight back at the sand
		local circling = drill.shark and drill.shark.state == "stalk"
		if drill.catches > 0 then
			local sand = Vector3.new(pos.X, Config.BEACH_TOP + 2, Config.SHORE_Z - 6)
			if circling then
				return sand, "SAND!", "It's circling you!", "Swim straight back to the SAND!"
			end
			return sand, "SAND!", "IT'S CHARGING!", "Swim straight back to the SAND!", C.red
		end
		local safeAt = Layout.nearestSafe(pos)
		if circling then
			return safeAt + Vector3.new(0, 2, 0), "SAFE!", "It's circling you!", "Get to SAND or an ISLAND (follow the arrow)"
		end
		return safeAt + Vector3.new(0, 2, 0), "SAFE!", "IT'S CHARGING!", "Keep going, or swerve at the last second!", C.red
	end
	if drill.state == "pause" and os.clock() - drill.t > 3 then
		drill.state = "idle"
	end
	return nil, nil, "Shark drill", "Try again in a moment..."
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
		tutBanner(nil)
		return
	end
	local pos = hrp.Position
	local plot = myPlot()
	local at, label, title, sub, color = nil, nil, nil, nil, nil

	if step == 0 then
		if d.carrying then
			advance(1)
		else
			at, label = nearestBubble(pos), "Grab it!"
			title, sub = "Grab a sea creature", TAP_HINT
		end
	end
	if step == 1 then
		if not d.carrying and #d.creatures > 0 then
			advance(2)
		elseif not d.carrying then
			-- a shark ate it on the way back: go grab another
			at, label = nearestBubble(pos), "Grab it!"
			title, sub = "Grab a sea creature", HOLD_HINT
		elseif plot then
			at, label = Layout.tankPos(plot) + Vector3.new(0, 4, 0), "Your tank"
			title, sub = "Bring it home", "Follow the arrow to your tank. It earns cash every second!"
		end
	end
	if step == 2 and plot then
		at, label = Layout.padPos(plot), "Collect!"
		title, sub = "Collect your cash", "Step on the green pad next to your tank"
	end
	if step == 3 then
		at, label, title, sub, color = drillTick(pos)
	end
	if step == 4 then
		local nxt = HUD.nextRide(d)
		if not nxt or nxt.order > 2 then
			advance(5)
		elseif d.coins >= nxt.price then
			at, label = Layout.RideShopPad + Vector3.new(0, 1, 0), "Ride Shop"
			title, sub = ("Get the %s"):format(nxt.name), ("Walk onto the Ride Shop pad · +%d speed every second!"):format(nxt.gain or 0)
			HUD.pulseRide(true)
		else
			-- not enough yet: keep them on the loop that earns cash
			if d.carrying then
				at, label = plot and Layout.tankPos(plot) + Vector3.new(0, 4, 0), "Your tank"
			elseif d.pending >= 1 and plot then
				at, label = Layout.padPos(plot), "Collect!"
			else
				at, label = nearestBubble(pos), "Grab it!"
			end
			title = ("Save up for the %s"):format(nxt.name)
			sub = ("$%s / $%s · grab creatures, collect cash"):format(UI.short(d.coins), UI.short(nxt.price))
		end
	end

	point(at, label)
	tutBanner(title, sub, color)
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
	Prompts.setTeach(step == 0 and "tap" or "hold")

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

	-- first time here: one big hello, then step 1
	if step == 0 and #d.creatures == 0 then
		Notify.takeover("+1 SPEED TO ESCAPE THE SHARK", "Catch sea creatures · get faster · don't get eaten", C.gold, 2.2)
	end

	local conn
	conn = RunService.Heartbeat:Connect(function()
		update()
		if step >= DONE then
			conn:Disconnect()
			point(nil)
			tutBanner(nil)
			Prompts.setTeach(nil) -- also when the server finished the tutorial
			if drill.shark then
				drillEnd("abort")
			end
			Notify.takeover("YOU'RE READY!", "Faster rides → deeper zones → rarer creatures", C.gold, 2)
			Fx.confetti(myRoot() and (myRoot() :: BasePart).Position or Vector3.zero)
		end
	end)
end

return Onboarding
