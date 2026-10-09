-- Server-side shark AI. Every minute or so (randomized: 50-92 s of calm,
-- then a 5 s warning and an 18-28 s hunt) each player in open water gets
-- their own shark (the variant of their zone; in deeper zones sometimes two),
-- which hunts like a real one:
--   stalk     - circles you once in a tightening spiral (get to sand!)
--   charge    - closes in, always faster than you, but turns slowly
--   lunge     - commits: leaps out of the water at where you'll be (your
--               velocity x the flight time). Clients get the landing spot at
--               once (red ring) and see the arc. Hold course and it lands on
--               you; whip / turn hard / hop and it splashes down empty
--   overshoot - it missed: carries on, circles back for another go
--   bite      - CHOMP (clients play the leap; the victim gets a cutscene)
-- Reach the beach and it circles there / leaves. Islands only shelter you
-- for Config.Shark.islandShelter seconds per hunt each: then the shark can
-- reach you there too, so you island-hop. While it hunts, grabs are luckier
-- (Game.frenzy): worth the risk.
-- The server owns positions, landings and bites; clients only draw and animate.

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local Shared = game.ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Layout = require(Shared.Layout)
local Remotes = require(Shared.Remotes)
local Game = require(script.Parent.Game)

local Sharks = {}

local SharkRemote = Remotes.get("Sharks")
local EventRemote = Remotes.get("SharkEvent")

local VARIANTS = { "Baby", "Hammerhead", "Tiger", "GreatWhite", "Mecha", "Megalodon", "Frost", "Magma", "King", "Gummy", "Jelly", "Licorice", "Peppermint", "Fudge", "SugarKing" }
local VARIANT_INDEX = {}
for i, v in VARIANTS do
	VARIANT_INDEX[v] = i
end

-- wire codes (SharkView.STATE_NAMES must match)
local STATE = { charge = 1, circle = 2, leave = 3, bite = 4, stalk = 5, overshoot = 6, lunge = 7 }

type Hunter = {
	id: number,
	aggro: number, -- the zone's shark aggression (Config zone.aggro)
	variant: string,
	length: number,
	speed: number,
	pos: Vector3,
	yaw: number,
	target: Game.Session?,
	state: string,
	island: Layout.Island?,
	angle: number,
	radius: number,
	stalkTime: number,
	timer: number,
	holdFor: number,
	-- lunge
	from: Vector3,
	to: Vector3,
	flight: number,
	biteRadius: number,
	baseY: number,
	-- the target's speed trend (for aiming the lunge)
	lastSpd: number,
	lastSpdAt: number,
	accel: number,
}

local hunters: { Hunter } = {}
local nextId = 0
local phase = "calm"
local phaseEnds = 0
local hunted: { [Player]: number } = {} -- hunters on each player
local landedAt: { [Player]: number } = {} -- last lunge landing on them
local double = false -- this hunt sends two sharks at players in deeper zones
local rng = Random.new()

-- island shelter this hunt: seconds left per island, and the one you're on
type Shelter = { left: { [Layout.Island]: number }, on: Layout.Island? }
local shelter: { [Player]: Shelter } = {}

local function forward(yaw: number): Vector3
	return Vector3.new(-math.sin(yaw), 0, -math.cos(yaw))
end

local function yawOf(dir: Vector3): number
	return math.atan2(-dir.X, -dir.Z)
end

local function turnToward(yaw: number, want: number, maxStep: number): number
	local d = (want - yaw + math.pi) % (2 * math.pi) - math.pi
	return yaw + math.clamp(d, -maxStep, maxStep)
end

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function clampLane(p: Vector3): Vector3
	local w = Config.worldAt(p) -- (each world's lane sits at its own X)
	local ox = Config.originX(w)
	return Vector3.new(math.clamp(p.X, ox - Config.LANE_WIDTH / 2 + 6, ox + Config.LANE_WIDTH / 2 - 6), 0,
		math.clamp(p.Z, Config.SHORE_Z + 6, Config.oceanEnd(w) - 8))
end

-- the charge never loses a straight race: faster than the zone's shark
-- speed or your own top speed, whichever is higher
local function chargeSpeed(h: Hunter, s: Game.Session): number
	local cfg = Config.Shark
	return math.max(h.speed * cfg.chargeMult, Game.walkSpeed(s) * cfg.chargeVsPlayer)
end

local function restalk(h: Hunter, p: Vector3, time: number)
	local rel = flat(h.pos - p)
	h.state, h.timer = "stalk", 0
	h.stalkTime = time
	h.angle = math.atan2(rel.Z, rel.X)
	h.radius = rel.Magnitude
end

local function spawnHunter(s: Game.Session, second: boolean)
	if #hunters >= Config.Shark.maxHunters then
		return
	end
	local hrp = Game.root(s.player)
	if not hrp then
		return
	end
	local p = hrp.Position
	local zone = Config.zoneAtPos(p) or Config.Zones[1]
	-- the second shark comes from the other flank and strikes later
	local a = second and math.rad(math.random(60, 100) * (math.random() < 0.5 and -1 or 1)) or math.rad(math.random(-55, 55))
	local away = Vector3.new(math.sin(a), 0, math.cos(a)) -- from deeper water
	local start = clampLane(p + away * Config.Shark.spawnDistance)
	local rel = flat(start - p)
	nextId += 1
	table.insert(hunters, {
		id = nextId,
		variant = zone.shark,
		aggro = zone.aggro or 1,
		length = zone.sharkLength,
		speed = zone.sharkSpeed,
		pos = start,
		yaw = yawOf(-rel),
		target = s,
		state = "stalk",
		island = nil,
		angle = math.atan2(rel.Z, rel.X),
		radius = rel.Magnitude,
		-- aggressive zones circle less before the first charge
		stalkTime = Config.Shark.stalk / (zone.aggro or 1) + (second and 1.8 or 0),
		timer = 0,
		holdFor = 0,
		from = start,
		to = start,
		flight = 1,
		biteRadius = 5,
		baseY = p.Y,
		lastSpd = 0,
		lastSpdAt = 0,
		accel = 0,
	})
	hunted[s.player] = (hunted[s.player] or 0) + 1
end

local function pushOutOfIslands(h: Hunter)
	local pad = h.length * 0.25 + 3
	for _, island in Layout.Islands do
		local d = Vector3.new(h.pos.X - island.pos.X, 0, h.pos.Z - island.pos.Z)
		local min = island.radius + pad
		if d.Magnitude < min and d.Magnitude > 0.01 then
			h.pos = Vector3.new(island.pos.X, 0, island.pos.Z) + d.Unit * min
		end
	end
	if h.pos.Z < Config.SHORE_Z + 4 then
		h.pos = Vector3.new(h.pos.X, 0, Config.SHORE_Z + 4)
	end
end

-- target got to safety: circle their island while the hunt lasts, else leave
local function lostTarget(h: Hunter, hrp: BasePart?)
	local island = hrp and Layout.islandAt(hrp.Position, 1)
	if island and phase == "hunt" then
		h.state, h.island, h.timer = "circle", island, 0
		local d = h.pos - island.pos
		h.angle = math.atan2(d.Z, d.X)
	else
		h.state, h.timer = "leave", 0
	end
end

-- another shark is in the air at this player, or just landed: wait your turn
local function lungeClear(h: Hunter, s: Game.Session): boolean
	if os.clock() - (landedAt[s.player] or 0) < Config.Shark.lungeGap then
		return false
	end
	for _, o in hunters do
		if o ~= h and o.target == s and o.state == "lunge" then
			return false
		end
	end
	return true
end

-- the leap: aim where the target will be after the flight if they hold course
local function startLunge(h: Hunter, s: Game.Session, hrp: BasePart)
	local cfg = Config.Shark
	local top = Game.walkSpeed(s)
	local flight, radius = Config.lunge(top, h.length)
	local p = flat(hrp.Position)
	local vel = flat(hrp.AssemblyLinearVelocity)
	local spd = math.min(vel.Magnitude, top * 1.25)
	local land = p
	if spd > 2 then
		local feel = Config.feel(s.profile.ride)
		local acc = math.clamp(h.accel, -top / feel.coast * 1.3, top / feel.accel * 2)
		land = p + vel.Unit * Config.lungeTravel(spd, acc, top, flight * cfg.lungeLead)
	end
	land = clampLane(land)
	h.state, h.timer = "lunge", 0
	h.from, h.to, h.flight, h.biteRadius = h.pos, land, flight, radius
	h.baseY = hrp.Position.Y
	local dir = flat(land - h.pos)
	if dir.Magnitude > 1 then
		h.yaw = yawOf(dir)
	end
	EventRemote:FireAllClients("lunge", {
		id = h.id, victim = s.player.UserId, x = h.pos.X, z = h.pos.Z, lx = land.X, lz = land.Z, t = flight, r = radius,
	})
end

local function doBite(h: Hunter, victim: Game.Session, p: Vector3)
	local carried = victim.carrying
	local result = Game.bite(victim, h.pos)
	EventRemote:FireAllClients("bite", {
		id = h.id, victim = victim.player.UserId, result = result, px = p.X, pz = p.Z,
		r = carried and carried.r, m = carried and carried.m, cz = carried and carried.z, cs = carried and carried.s,
	})
	h.state, h.timer = "bite", 0
	h.holdFor = result == "eaten" and Config.Shark.eatenTime or 0.8
end

local function update(dt: number)
	local cfg = Config.Shark
	for i = #hunters, 1, -1 do
		local h = hunters[i]
		h.timer += dt
		local s = h.target
		local hrp = s and Game.root(s.player)
		local alive = s ~= nil and hrp ~= nil and Game.sessions[s.player] ~= nil

		if h.state == "stalk" then
			if not alive then
				h.state, h.timer = "leave", 0
			elseif not Game.huntable(s :: Game.Session) then
				lostTarget(h, hrp)
			else
				-- a tightening spiral around the target, keeping pace if they run
				local p = (hrp :: BasePart).Position
				local k = math.clamp(h.timer / h.stalkTime, 0, 1)
				local want = cfg.stalkRadius + (cfg.stalkEnd - cfg.stalkRadius) * k
				h.radius += (want - h.radius) * math.min(dt * 1.5, 1)
				h.angle += (h.speed * 0.55 / math.max(h.radius, 8)) * dt
				local goal = Vector3.new(p.X + math.cos(h.angle) * h.radius, 0, p.Z + math.sin(h.angle) * h.radius)
				local to = flat(goal - h.pos)
				local maxStep = math.max(h.speed * 1.4, chargeSpeed(h, s :: Game.Session)) * dt
				local move = to.Magnitude > maxStep and to.Unit * maxStep or to
				if move.Magnitude > 0.05 then
					h.yaw = turnToward(h.yaw, yawOf(move), 6 * dt)
				end
				h.pos = clampLane(h.pos + move)
				pushOutOfIslands(h)
				if h.timer >= h.stalkTime then
					h.state, h.timer = "charge", 0
					h.lastSpd, h.lastSpdAt, h.accel = flat((hrp :: BasePart).AssemblyLinearVelocity).Magnitude, os.clock(), 0
					EventRemote:FireAllClients("charge", { id = h.id, victim = (s :: Game.Session).player.UserId })
				end
			end
		elseif h.state == "charge" then
			if not alive then
				h.state, h.timer = "leave", 0
			elseif not Game.huntable(s :: Game.Session) then
				lostTarget(h, hrp)
			else
				local victim = s :: Game.Session
				local root = hrp :: BasePart
				local p = root.Position
				local to = flat(p - h.pos)
				local dist = to.Magnitude
				-- full speed with a wide turning circle
				local spd = chargeSpeed(h, victim)
				local turn = spd / cfg.chargeRadius
				h.yaw = turnToward(h.yaw, yawOf(to), (dist > 40 and turn * 2 or turn) * dt)
				h.pos = clampLane(h.pos + forward(h.yaw) * spd * dt)
				pushOutOfIslands(h)
				-- watch how their speed is changing (speeding up / coasting) to aim the leap
				local now = os.clock()
				if now - h.lastSpdAt >= 0.15 then
					local vNow = flat(root.AssemblyLinearVelocity).Magnitude
					local a = (vNow - h.lastSpd) / (now - h.lastSpdAt)
					h.accel = h.accel + (a - h.accel) * 0.6
					h.lastSpd, h.lastSpdAt = vNow, now
				end
				local _, _, range = Config.lunge(Game.walkSpeed(victim), h.length)
				range *= h.aggro -- and leap from further out
				if h.timer >= cfg.lungeMinCharge / h.aggro and dist < range and lungeClear(h, victim) then
					startLunge(h, victim, root)
				elseif h.timer > cfg.chargeGiveUp then
					restalk(h, p, cfg.recircle / h.aggro)
				end
			end
		elseif h.state == "lunge" then
			-- in the air: the server only needs the landing spot and time
			local k = math.clamp(h.timer / h.flight, 0, 1)
			h.pos = h.from:Lerp(h.to, k)
			if h.timer >= h.flight then
				local hit = false
				if alive then
					landedAt[(s :: Game.Session).player] = os.clock()
				end
				if alive and Game.huntable(s :: Game.Session) then
					local p = (hrp :: BasePart).Position
					local d = Vector2.new(p.X - h.to.X, p.Z - h.to.Z).Magnitude
					local wet = Layout.inWater(p) and not Layout.islandAt(p, 0)
					local hopped = wet and p.Y - h.baseY > cfg.lungeHop
					if d <= h.biteRadius and not hopped then
						hit = true
						doBite(h, s :: Game.Session, p)
					end
				end
				if not hit then
					-- splashes down empty: it shoots on and has to come round again
					-- (or, if the hunt ended mid-air, swims off)
					h.state, h.timer = phase == "hunt" and "overshoot" or "leave", 0
					if alive then
						EventRemote:FireAllClients("miss", { id = h.id, victim = (s :: Game.Session).player.UserId, x = h.to.X, z = h.to.Z })
					end
				end
			end
		elseif h.state == "overshoot" then
			-- carry on past, braking, then circle back for another go
			local fwd = forward(h.yaw)
			local k = math.clamp(1 - h.timer / 0.7, 0.25, 1)
			h.pos = clampLane(h.pos + fwd * h.speed * k * dt)
			pushOutOfIslands(h)
			if h.timer > 0.7 then
				if alive and Game.huntable(s :: Game.Session) then
					restalk(h, (hrp :: BasePart).Position, cfg.recircle / h.aggro)
				elseif alive then
					lostTarget(h, hrp)
				else
					h.state, h.timer = "leave", 0
				end
			end
		elseif h.state == "circle" then
			local island = h.island :: Layout.Island
			if alive and Game.huntable(s :: Game.Session) and phase == "hunt" then
				-- they stepped off the island (or its shelter ran out): it was waiting
				restalk(h, (hrp :: BasePart).Position, 0.8)
			elseif phase ~= "hunt" or not alive then
				h.state, h.timer = "leave", 0
			else
				local r = island.radius + h.length * 0.35 + 5
				h.angle += (h.speed * 0.3 / r) * dt
				local want = island.pos + Vector3.new(math.cos(h.angle), 0, math.sin(h.angle)) * r
				local to = flat(want - h.pos)
				h.yaw = turnToward(h.yaw, yawOf(to), 4 * dt)
				h.pos += forward(h.yaw) * math.min(h.speed * 0.45 * dt, to.Magnitude)
				h.pos = flat(h.pos)
			end
		elseif h.state == "bite" then
			if h.timer > h.holdFor then
				h.state, h.timer = "leave", 0
			end
		elseif h.state == "leave" then
			h.yaw = turnToward(h.yaw, yawOf(Vector3.new(h.pos.X >= 0 and 1 or -1, 0, 2)), 2 * dt)
			h.pos += forward(h.yaw) * h.speed * 0.7 * dt
			if h.timer > 3 then
				if h.target then
					local pl = h.target.player
					local n = (hunted[pl] or 1) - 1
					hunted[pl] = n > 0 and n or nil
				end
				table.remove(hunters, i)
			end
		end
	end
end

local function snapshot()
	local list = table.create(#hunters)
	for _, h in hunters do
		table.insert(list, {
			h.id, VARIANT_INDEX[h.variant], math.floor(h.pos.X * 10) / 10, math.floor(h.pos.Z * 10) / 10,
			math.floor(h.yaw * 100) / 100, STATE[h.state], h.length, h.target and h.target.player.UserId or 0,
		})
	end
	SharkRemote:FireAllClients(list)
end

local function huntSweep()
	local cfg = Config.Shark
	for _, s in Game.sessions do
		if Game.huntable(s) then
			local n = hunted[s.player] or 0
			local hrp = Game.root(s.player)
			local want = (double and hrp and (Config.zoneAtPos(hrp.Position) or Config.Zones[1]).index >= cfg.doubleFromZone) and 2 or 1
			if n < want then
				spawnHunter(s, n > 0)
			end
		end
	end
end

-- islands are shelter for a while, not for the whole hunt: each one you
-- stand on counts down (a different island = a fresh timer)
local function shelterTick(dt: number)
	if phase ~= "hunt" then
		return
	end
	local cfg = Config.Shark
	for player, s in Game.sessions do
		local hrp = Game.root(player)
		if not hrp or os.clock() < s.eatenUntil then
			continue
		end
		if s.profile.tut < 5 and os.clock() - s.joinedAt < cfg.newPlayerGrace then
			continue -- brand-new players: islands stay fully safe
		end
		local pos = hrp.Position
		local island = Layout.inWater(pos) and Layout.islandAt(pos, 0.5) or nil
		local st = shelter[player]
		if not st then
			st = { left = {}, on = nil }
			shelter[player] = st
		end
		if island ~= st.on then
			st.on = island
			if island then
				local left = st.left[island] or cfg.islandShelter
				Game.notify(player, "shelter", { i = table.find(Layout.Islands, island), left = left, max = cfg.islandShelter })
			end
		end
		if island then
			local left = st.left[island] or cfg.islandShelter
			if left > 0 then
				left -= dt
				st.left[island] = left
				if left <= 0 then
					Game.notify(player, "shelterOut", { i = table.find(Layout.Islands, island) })
				end
			end
		end
	end
end

-- Game.huntable asks this for a player standing on an island
local function islandExposed(s: Game.Session, island: Layout.Island): boolean
	if phase ~= "hunt" then
		return false
	end
	local st = shelter[s.player]
	local left = st and st.left[island]
	return left ~= nil and left <= 0
end

function Sharks.phase(): (string, number)
	return phase, phaseEnds
end

function Sharks.start()
	Game.islandExposed = islandExposed
	RunService.Heartbeat:Connect(update)
	Players.PlayerRemoving:Connect(function(p)
		hunted[p] = nil
		landedAt[p] = nil
		shelter[p] = nil
	end)
	task.spawn(function()
		local hadSharks = false
		while true do
			local dt = task.wait(0.1)
			shelterTick(dt)
			if #hunters > 0 or hadSharks then
				snapshot()
			end
			hadSharks = #hunters > 0
		end
	end)
	task.spawn(function()
		local cfg = Config.Shark
		phaseEnds = os.clock() + cfg.firstAttack - cfg.warning
		task.wait(cfg.firstAttack - cfg.warning)
		while true do
			phase, phaseEnds = "warning", os.clock() + cfg.warning
			EventRemote:FireAllClients("warning", { duration = cfg.warning })
			task.wait(cfg.warning)
			-- random length (and sometimes two sharks) so a hunt can't be timed
			local huntLen = rng:NextInteger(cfg.huntMin, cfg.huntMax)
			double = rng:NextNumber() < cfg.doubleChance
			table.clear(shelter)
			phase, phaseEnds = "hunt", os.clock() + huntLen
			Game.frenzy = true
			EventRemote:FireAllClients("hunt", { duration = huntLen, double = double or nil, doubleFrom = cfg.doubleFromZone })
			while os.clock() < phaseEnds do
				huntSweep()
				task.wait(0.4)
			end
			local calm = rng:NextInteger(cfg.calmMin, cfg.calmMax)
			phase, phaseEnds = "calm", os.clock() + calm
			Game.frenzy = false
			double = false
			table.clear(shelter)
			for _, h in hunters do
				if h.state ~= "bite" and h.state ~= "lunge" then
					h.state, h.timer = "leave", 0
				end
			end
			EventRemote:FireAllClients("clear", { next = calm })
			task.wait(calm)
		end
	end)
	-- late joiners learn the current phase
	Players.PlayerAdded:Connect(function(p)
		task.wait(3)
		if phase ~= "calm" then
			EventRemote:FireClient(p, phase, { duration = math.max(0, phaseEnds - os.clock()) })
		else
			EventRemote:FireClient(p, "clear", { next = math.max(0, phaseEnds - os.clock()) })
		end
	end)
end

Sharks.VARIANTS = VARIANTS
return Sharks
