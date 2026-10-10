-- THE HOOK on this client: carry more, earn more, but the shark wants you
-- more.
--   Fins    what you carry draws shark fins that circle you in the water
--           (player attribute "Fins" 0-3, server Sharks.luau finsTick).
--           Everyone sees everyone's. When they close in ("FinsClose") they
--           tighten and speed up, and a few seconds later one charges.
--   Haul    the dock pays cash for a trip right away (server Game.payHaul):
--           the number counts up over your tank.
--   Spill   a bitten player's haul floats free: you get pointed at it.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = game.ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Layout = require(Shared.Layout)
local Remotes = require(Shared.Remotes)
local UI = require(script.Parent.UI)
local Fx = require(script.Parent.Fx)
local Notify = require(script.Parent.Notify)
local Guide = require(script.Parent.Guide)
local State = require(script.Parent.State)
local SharkView = require(script.Parent.SharkView)
local Moments = require(script.Parent.Moments)

local Haul = {}
local player = Players.LocalPlayer
local T = UI.T
local GREEN, ORANGE, RED = Color3.fromRGB(110, 230, 120), Color3.fromRGB(255, 170, 50), Color3.fromRGB(255, 60, 70)

local spillUntil = 0
local taught, warned = false, false

local function myRoot(): BasePart?
	local char = player.Character
	return char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
end

----------------------------------------------------------------- fins
-- real (small) sharks of the zone you're in, circling you. Only for show:
-- client-local (SharkView.spawnLocal), they never hunt or bite and don't
-- count as "a shark is after you"; the charge comes from the server.
-- They swim like sharks, not like satellites: each one only ever moves
-- forward along its heading, turns at a limited rate, eases its speed up
-- and down, and steers toward a lazy, wandering orbit around you (with its
-- own radius, direction and drift). Move and they lag, sweep round and
-- catch up; they keep apart and steer clear of islands and the shore.
type Fin = { sh: any, heading: number, speed: number, side: number, seed: number }
local finsOf: { [Player]: { Fin } } = {}
local W = Config.LANE_WIDTH

local function fwdOf(yaw: number): Vector3
	return Vector3.new(-math.sin(yaw), 0, -math.cos(yaw))
end

local function yawOf(v: Vector3): number
	return math.atan2(-v.X, -v.Z)
end

local function turnToward(cur: number, want: number, maxStep: number): number
	local d = (want - cur + math.pi) % (2 * math.pi) - math.pi
	return cur + math.clamp(d, -maxStep, maxStep)
end

-- somewhere out of the way to appear: a little behind you, in the water
local function spawnPoint(center: Vector3, look: Vector3): Vector3
	for _ = 1, 8 do
		local a = math.random() * math.pi * 2
		local p = center - look * 30 + Vector3.new(math.cos(a), 0, math.sin(a)) * math.random(25, 40)
		p = Vector3.new(p.X, 0, math.max(p.Z, Config.SHORE_Z + 12))
		if not Layout.islandAt(p, 6) then
			return p
		end
	end
	return Vector3.new(center.X, 0, math.max(center.Z + 40, Config.SHORE_Z + 12))
end

local function newFin(at: Vector3, look: Vector3): Fin
	local zone = Config.zoneAtPos(at) or Config.Zones[1]
	local L = math.clamp(zone.sharkLength * 0.6, 6, 14)
	local p = spawnPoint(at, look)
	local heading = yawOf(Vector3.new(at.X - p.X, 0, at.Z - p.Z))
	local sh = SharkView.spawnLocal(zone.shark, L, p, heading, function() end)
	sh.state = "circle"
	return { sh = sh, heading = heading, speed = 10, side = math.random() < 0.5 and -1 or 1, seed = math.random() * 100 }
end

local function setFins(p: Player, n: number, at: Vector3?, look: Vector3?)
	local list = finsOf[p] or {}
	finsOf[p] = list
	while #list < n and at do
		table.insert(list, newFin(at, look or Vector3.new(0, 0, -1)))
	end
	while #list > n do
		local f = table.remove(list) :: Fin
		f.sh.state = "leave" -- (it dives away)
		task.delay(1.5, SharkView.removeLocal, f.sh)
	end
	if n == 0 then
		finsOf[p] = nil
	end
end

local function steerFin(f: Fin, list: { Fin }, center: Vector3, vel: Vector3, close: boolean, n: number, t: number, dt: number)
	local sh = f.sh
	local pos = Vector3.new(sh.pos.X, 0, sh.pos.Z)
	local toP = Vector3.new(center.X - pos.X, 0, center.Z - pos.Z)
	local dist = toP.Magnitude
	if dist > 160 then
		-- left far behind (you outran it): it slips back in out of sight
		local look = vel.Magnitude > 1 and Vector3.new(vel.X, 0, vel.Z).Unit or Vector3.new(0, 0, -1)
		pos = spawnPoint(center, look)
		f.heading, f.speed = yawOf(Vector3.new(center.X - pos.X, 0, center.Z - pos.Z)), 12
		sh.pos, sh.yaw = pos, f.heading
		return
	end
	local radial = dist > 0.01 and toP / dist or Vector3.new(0, 0, 1)
	local tangent = Vector3.new(-radial.Z, 0, radial.X) * f.side
	-- each shark keeps its own orbit, breathing in and out
	local rWant = (close and 13 or 26 - n * 2) + math.sin(t * 0.35 + f.seed) * (close and 1.5 or 5)
	local err = (dist - rWant) / rWant
	local desired = tangent + radial * math.clamp(err * 2.2, -1.2, 1.6)
	-- lazy wander so the orbit is never a perfect circle
	local wander = (math.sin(t * 0.7 + f.seed) * 0.6 + math.sin(t * 0.23 + f.seed * 2) * 0.4) * (close and 0.25 or 0.55)
	local c, sn = math.cos(wander), math.sin(wander)
	desired = Vector3.new(desired.X * c - desired.Z * sn, 0, desired.X * sn + desired.Z * c)
	-- you're on the move: they swim along with you, like sharks trailing a boat
	local flatVel = Vector3.new(vel.X, 0, vel.Z)
	local sp = flatVel.Magnitude
	if sp > 1 then
		desired += flatVel / sp * math.min(1.5, sp / 20)
	end
	-- keep apart from the others
	for _, o in list do
		if o ~= f then
			local d = Vector3.new(pos.X - o.sh.pos.X, 0, pos.Z - o.sh.pos.Z)
			local m = d.Magnitude
			if m > 0.01 and m < 12 then
				desired += d / m * (12 - m) / 12 * 1.5
			end
		end
	end
	-- look ahead: steer round islands, back from the shore and the lane edges
	local ahead = pos + fwdOf(f.heading) * 10
	local isl = Layout.islandAt(ahead, 5)
	if isl then
		local away = Vector3.new(ahead.X - isl.pos.X, 0, ahead.Z - isl.pos.Z)
		desired += (away.Magnitude > 0.01 and away.Unit or tangent) * 2
	end
	if ahead.Z < Config.SHORE_Z + 10 then
		desired += Vector3.new(0, 0, 2)
	end
	local ox = Config.originX(Config.worldAt(center))
	if math.abs(ahead.X - ox) > W / 2 - 8 then
		desired += Vector3.new(ahead.X > ox and -2 or 2, 0, 0)
	end
	-- turn (limited rate), then swim forward at an eased speed
	if desired.Magnitude > 0.01 then
		f.heading = turnToward(f.heading, yawOf(desired), ((close and 2.4 or 1.4) + math.min(1.2, sp / 100)) * dt)
	end
	local base = close and 30 or 15
	local catchUp = math.max(0, dist - rWant * 1.4)
	local want = math.min(base + catchUp + sp * 0.9, sp * 1.3 + 40)
	local accel = ((want > f.speed) and 18 or 12) + sp * 0.5
	f.speed += math.clamp(want - f.speed, -accel * dt, accel * dt)
	pos += fwdOf(f.heading) * f.speed * dt
	-- bank into the turn, like the hunting sharks do
	local yawRate = ((f.heading - sh.yaw + math.pi) % (2 * math.pi) - math.pi) / math.max(dt, 1e-3)
	sh.roll += (math.clamp(-yawRate * 0.12, -0.4, 0.4) - sh.roll) * math.min(dt * 6, 1)
	sh.pos, sh.yaw = pos, f.heading
	sh.state = "circle"
end

local function finsUpdate(dt: number)
	dt = math.min(dt, 0.1)
	local t = os.clock()
	for _, p in Players:GetPlayers() do
		local char = p.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		local n = p:GetAttribute("Fins")
		n = typeof(n) == "number" and hrp ~= nil and n or 0
		local vel = hrp and hrp.AssemblyLinearVelocity or Vector3.zero
		local look = vel.Magnitude > 1 and Vector3.new(vel.X, 0, vel.Z).Unit or Vector3.new(0, 0, -1)
		setFins(p, n, hrp and hrp.Position, look)
		local list = finsOf[p]
		if list and hrp then
			local close = p:GetAttribute("FinsClose") == true
			for _, f in list do
				steerFin(f, list, hrp.Position, vel, close, n, t, dt)
			end
		end
	end
	for p in finsOf do
		if not p.Parent then
			setFins(p, 0)
		end
	end
	-- teach it once, and warn when they close in on you
	local d = State.data
	local mine = player:GetAttribute("Fins")
	if not taught and typeof(mine) == "number" and mine > 0 and d and (d.playtime or 0) < 3600 then
		taught = true
		Notify.toast("Sharks follow your haul. Carry a lot and one charges!", ORANGE)
	end
	local close = player:GetAttribute("FinsClose") == true
	if close and not warned then
		warned = true
		Notify.banner("The sharks are closing in", { key = "fins", priority = 4, time = 3, color = RED, sub = "Get your haul to the sand!" })
		Fx.sound("sharkAlarm", 0.6, 1.15)
	elseif not close then
		warned = false
	end
end

-- the dock's payout: a number that counts up over your tank
local function payout(d: any)
	local at = Vector3.new(d.x, d.y + 19, d.z) -- (above the tank sign and the +$/s popups)
	local anchor = Instance.new("Part")
	anchor.Anchored, anchor.CanCollide, anchor.CanQuery, anchor.CanTouch = true, false, false, false
	anchor.Transparency = 1
	anchor.Size = Vector3.one
	anchor.Position = at
	anchor.Parent = Workspace
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(260, 80)
	bb.AlwaysOnTop = true
	bb.LightInfluence = 0
	bb.MaxDistance = 250
	bb.Adornee = anchor
	bb.Parent = anchor
	local amount = UI.outlined(bb, "+$0", { Size = UDim2.new(1, 0, 0, 48), TextColor3 = T.gold })
	local multi = (d.n or 1) > 1
	UI.outlined(bb, multi and ("Haul of %d · x%s"):format(d.n, ("%g"):format(d.mult or 1)) or "Brought home",
		{ Size = UDim2.new(1, 0, 0, 26), Position = UDim2.fromOffset(0, 50), TextColor3 = multi and T.white or Color3.fromRGB(200, 210, 230) })
	Fx.confetti(at - Vector3.new(0, 6, 0), multi and { T.gold, Color3.new(1, 1, 1), GREEN } or { T.gold })
	Fx.sound("deposit", 0.9, multi and 1 + math.min(d.n, 8) * 0.04 or 1)
	local total = d.coins or 0
	local t0 = os.clock()
	local dur = multi and 1.1 or 0.6
	local conn
	conn = RunService.RenderStepped:Connect(function()
		local k = math.clamp((os.clock() - t0) / dur, 0, 1)
		amount.Text = "+$" .. UI.short(math.floor(total * (1 - (1 - k) ^ 3)))
		anchor.Position = at + Vector3.new(0, k * 2, 0)
		if k >= 1 then
			conn:Disconnect()
			if multi then
				-- the finale: a gold pop over the tank, bigger for a bigger haul
				Fx.sound("coin", 0.8, 1.2)
				Fx.burst(at - Vector3.new(0, 4, 0), T.gold, 0.5 + math.min(d.n, 8) * 0.08)
				if d.n >= 3 then
					Fx.shockwave(Vector3.new(d.x, d.y + 0.5, d.z), T.gold, 30 + math.min(d.n, 8) * 5)
				end
			end
			task.delay(1.4, function()
				TweenService:Create(amount, TweenInfo.new(0.4), { TextTransparency = 1 }):Play()
				task.delay(0.5, function()
					anchor:Destroy()
				end)
			end)
		end
	end)
end

local function onSpill(d: any)
	local hrp = myRoot()
	local at = Vector3.new(d.x, 3, d.z)
	local time = d.time or Config.SPILL_TIME
	if d.why == "bonk" then
		-- bonked loose: no banner (the bonk says it), just the arrow for whoever's close
		if hrp and (hrp.Position - at).Magnitude < 140 then
			spillUntil = os.clock() + 15
			Guide.set("spill", at, d.userId == player.UserId and "Grab it back" or "Loot")
			local mine = spillUntil
			task.delay(15, function()
				if spillUntil == mine then
					Guide.set("spill", nil)
				end
			end)
		end
		return
	end
	if d.userId == player.UserId then
		-- yours: once you've washed up, go get it back
		task.delay(Config.Shark.eatenTime + 1, function()
			Notify.banner("Your haul spilled", { key = "spill", priority = 3, time = 4, color = ORANGE,
				sub = "Grab it back fast!" })
		end)
		spillUntil = os.clock() + time
		Guide.set("spill", at, "Your haul")
	elseif hrp and Config.worldAt(hrp.Position) == Config.worldAt(at) and (hrp.Position - at).Magnitude < 350 then
		Notify.toast(("%s's haul is up for grabs!"):format(tostring(d.name)), ORANGE)
		spillUntil = os.clock() + math.min(time, 20)
		Guide.set("spill", at, "Loot")
	else
		return
	end
	local mine = spillUntil
	task.delay(spillUntil - os.clock(), function()
		if spillUntil == mine then
			Guide.set("spill", nil)
		end
	end)
end

function Haul.start()
	RunService.RenderStepped:Connect(finsUpdate)
	Remotes.get("Notify").OnClientEvent:Connect(function(kind, d)
		if typeof(d) ~= "table" then
			return
		end
		if kind == "haul" then
			-- (once the catches flying into the tank have landed)
			task.delay(Moments.landing(), payout, d)
		elseif kind == "spill" then
			onSpill(d)
		elseif kind == "grab" and spillUntil > os.clock() then
			-- picked something up near the spill: the arrow's done its job
			local hrp = myRoot()
			if hrp and Layout.inWater(hrp.Position) then
				spillUntil = 0
				Guide.set("spill", nil)
			end
		end
	end)
end

return Haul
