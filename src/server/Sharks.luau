-- Server-side shark AI. Day and night: by day, grabbing a creature can draw
-- its zone's shark onto you for a while (a grudge: Sharks.onGrab / chum:
-- Sharks.aggro); at dusk (5 s warning) every player in open water gets their
-- own shark until dawn (the variant of their zone; deeper, sometimes two),
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
local Workspace = game:GetService("Workspace")

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
local STATE = { charge = 1, circle = 2, leave = 3, bite = 4, stalk = 5, overshoot = 6, lunge = 7, dazed = 8 }

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
	aggroUntil: number?, -- a daytime shark you drew by grabbing / chum: hunts until then
}

local hunters: { Hunter } = {}

-- the boss Megalodon (one per world at most; Megalodon Hour)
type Boss = {
	id: number,
	world: number,
	home: Vector3,
	pos: Vector3,
	yaw: number,
	state: string, -- circle / charge / bite / leave
	timer: number,
	angle: number,
	hp: number,
	maxHp: number,
	hits: { [Player]: number },
	target: Game.Session?,
	nextCharge: number,
	ends: number,
	holdFor: number,
	down: boolean?,
}
local bosses: { Boss } = {}
local thrownAt: { [Player]: number } = {}
local nextId = 0
local phase = "calm"
local phaseEnds = 0
local hunted: { [Player]: number } = {} -- hunters on each player
local closeCallAt: { [Player]: number } = {} -- last paid close call
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
-- speed or your own top speed, whichever is higher (except the first two
-- zones, Config.Shark.easyCharge, where kids can just ride home)
local function chargeSpeed(h: Hunter, s: Game.Session): number
	local cfg = Config.Shark
	local hrp = Game.root(s.player)
	local zone = hrp and Config.zoneAtPos(hrp.Position)
	local easy = zone and zone.world == 1 and cfg.easyCharge[zone.index]
	if easy then
		return math.max(Game.walkSpeed(s) * easy, cfg.easyMin)
	end
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
-- is this shark still out for blood? (night, or a daytime grudge)
local function hunting(h: Hunter): boolean
	return phase == "hunt" or (h.aggroUntil ~= nil and os.clock() < h.aggroUntil)
end

-- THE ESCAPE: you hit the sand with your shark right behind you. It snaps
-- at the shoreline (everyone sees), you get the close-call reward.
local escapedAt: { [Player]: number } = {}
local function madeIt(h: Hunter, hrp: BasePart)
	local s = h.target
	local cfg = Config.Shark
	-- only a real chase: it was charging you (or just missed a lunge), and
	-- you'd been out at sea a while, not dipping a toe in to farm it
	if not s or Layout.inWater(hrp.Position) or (h.state ~= "charge" and h.state ~= "overshoot") then
		return
	end
	if os.clock() - (s.wentOutAt or os.clock()) < cfg.escapeMinSea then
		return
	end
	if flat(h.pos - hrp.Position).Magnitude > cfg.escapeRadius or os.clock() - (escapedAt[s.player] or 0) < cfg.closeCallCooldown then
		return
	end
	escapedAt[s.player] = os.clock()
	local amount = math.max(5, math.floor(Game.gain(s) * cfg.closeCallSeconds))
	s.profile.speed += amount
	s.dirty = true
	-- the snap lands at the waterline between the shark and you
	local edge = Vector3.new(hrp.Position.X, 0, Config.SHORE_Z + 5)
	EventRemote:FireAllClients("snap", { id = h.id, victim = s.player.UserId, x = edge.X, z = edge.Z })
	Game.notify(s.player, "madeIt", { amount = amount, carried = Game.carryCount(s) })
end

local function lostTarget(h: Hunter, hrp: BasePart?)
	if hrp then
		madeIt(h, hrp)
	end
	local island = hrp and Layout.islandAt(hrp.Position, 1)
	if island and hunting(h) then
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
		-- a daytime grudge that ran out gives up (night hunters leave at dawn)
		if (h.state == "stalk" or h.state == "charge") and not hunting(h) then
			h.state, h.timer = "leave", 0
		end
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
					elseif d > h.biteRadius and d <= h.biteRadius + cfg.closeCall
						and os.clock() - (closeCallAt[(s :: Game.Session).player] or -100) > cfg.closeCallCooldown then
						-- a hair's breadth: pay the dodge (the clip-worthy moment)
						local v = s :: Game.Session
						closeCallAt[v.player] = os.clock()
						local amount = math.max(5, math.floor(Game.gain(v) * cfg.closeCallSeconds))
						v.profile.speed += amount
						v.dirty = true
						Game.notify(v.player, "closeCall", { amount = amount })
					end
				end
				if not hit then
					-- splashes down empty: it shoots on and has to come round again
					-- (or, if the hunt ended mid-air, swims off)
					h.state, h.timer = hunting(h) and "overshoot" or "leave", 0
					if alive then
						EventRemote:FireAllClients("miss", { id = h.id, victim = (s :: Game.Session).player.UserId, x = h.to.X, z = h.to.Z })
						Game.track((s :: Game.Session).player, "dodge", {})
					end
				end
			end
		elseif h.state == "dazed" then
			-- bonked on the nose: it reels back, then has to circle in again
			h.pos = clampLane(h.pos - forward(h.yaw) * h.speed * 0.25 * math.max(0, 1 - h.timer) * dt)
			if h.timer > Config.Bonk.daze then
				if alive and Game.huntable(s :: Game.Session) and hunting(h) then
					restalk(h, (hrp :: BasePart).Position, cfg.recircle / h.aggro)
				elseif alive and hunting(h) then
					lostTarget(h, hrp) -- (on an island: it circles it, like any other shark)
				else
					h.state, h.timer = "leave", 0
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
			if alive and Game.huntable(s :: Game.Session) and hunting(h) then
				-- they stepped off the island (or its shelter ran out): it was waiting
				restalk(h, (hrp :: BasePart).Position, 0.8)
			elseif not hunting(h) or not alive then
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
			h.yaw = turnToward(h.yaw, yawOf(Vector3.new(h.pos.X >= Config.originX(Config.worldAt(h.pos)) and 1 or -1, 0, 2)), 2 * dt)
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
	for _, b in bosses do
		table.insert(list, {
			b.id, VARIANT_INDEX.Megalodon, math.floor(b.pos.X * 10) / 10, math.floor(b.pos.Z * 10) / 10,
			math.floor(b.yaw * 100) / 100, STATE[b.state], Config.Boss.length, b.target and b.target.player.UserId or 0,
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

-- you took something from its waters (or got chummed): that zone's shark
-- comes for you in the day too, for Config.Shark.grudge seconds
function Sharks.aggro(s: Game.Session, seconds: number?, why: string?, by: string?): boolean
	if phase == "hunt" or not Game.huntable(s) then
		return false -- (at night it's coming anyway)
	end
	local untilT = os.clock() + (seconds or Config.Shark.grudge)
	local mine = 0
	for _, h in hunters do
		if h.target == s and h.state ~= "leave" and h.state ~= "bite" then
			h.aggroUntil = math.max(h.aggroUntil or 0, untilT)
			mine += 1
		end
	end
	if mine == 0 then
		local before = #hunters
		spawnHunter(s, false)
		if #hunters == before then
			return false -- (no shark free right now: say nothing)
		end
		hunters[#hunters].aggroUntil = untilT
	end
	local hrp = Game.root(s.player)
	local zone = hrp and Config.zoneAtPos(hrp.Position)
	Game.notify(s.player, "aggro", { shark = zone and zone.shark or "Shark", why = why, by = by })
	return true
end

-- Fins follow your haul (Config.Fins): your own carried creatures draw
-- fins (player attribute "Fins" = 0-3 for clients to draw, "FinsClose" =
-- they're closing in). At `attackAt` a shark charges after `warn` seconds.
local armedAt: { [Player]: number } = {}
local finRest: { [Player]: number } = {}

local function haulWeight(s: Game.Session): number
	local cfg = Config.Fins
	local w = 0
	if s.carrying then
		w += cfg.weight[s.carrying.r] or 1
	end
	for _, c in s.bag or {} do
		w += cfg.weight[c.r] or 1
	end
	return w * (Game.mini == "frenzy" and 2 or 1) -- (Feeding Frenzy)
end

-- (kept for the grab hook: fins are worked out from what you carry)
function Sharks.onGrab(_s: Game.Session, _rarityId: string) end

local function finsTick()
	local cfg = Config.Fins
	local now = os.clock()
	for player, s in Game.sessions do
		local hrp = Game.root(player)
		local wet = hrp ~= nil and Layout.inWater(hrp.Position) and not Layout.islandAt(hrp.Position, 0)
		local w = 0
		if wet and phase ~= "hunt" and s.profile.tut >= 5 and Game.huntable(s) and (hunted[player] or 0) == 0 then
			w = haulWeight(s)
		end
		local fins = math.clamp(math.floor(w), 0, 3)
		local close = w >= cfg.attackAt and now >= (finRest[player] or 0)
		if close then
			armedAt[player] = armedAt[player] or now
			if now - armedAt[player] >= cfg.warn then
				armedAt[player] = nil
				finRest[player] = now + cfg.rest
				Sharks.aggro(s, cfg.grudge, "fins")
				fins, close = 0, false
			end
		else
			armedAt[player] = nil
		end
		if player:GetAttribute("Fins") ~= fins then
			player:SetAttribute("Fins", fins)
		end
		if player:GetAttribute("FinsClose") ~= close then
			player:SetAttribute("FinsClose", close)
		end
	end
end

-- No walls on the sea: past your recommended speed, that zone's shark
-- hunts you the whole time you're there (day or night). You can go; you
-- just won't make it back. Renewed every sweep while you stay too deep.
local deepWarned: { [Player]: string } = {}
local function deepSweep()
	local now = os.clock()
	for player, s in Game.sessions do
		local hrp = Game.root(player)
		local zone = hrp and Layout.inWater(hrp.Position) and Config.zoneAtPos(hrp.Position)
		if not (zone and zone.gate > s.profile.speed and Game.huntable(s)) then
			deepWarned[player] = nil
			continue
		end
		local mine = false
		for _, h in hunters do
			if h.target == s and h.state ~= "leave" and h.state ~= "bite" then
				h.aggroUntil = math.max(h.aggroUntil or 0, now + 4)
				mine = true
			end
		end
		if not mine then
			local before = #hunters
			spawnHunter(s, false)
			if #hunters > before then
				hunters[#hunters].aggroUntil = now + 4
			end
		end
		if deepWarned[player] ~= zone.id then
			deepWarned[player] = zone.id
			Game.notify(player, "tooDeep", { zone = zone.id, need = zone.gate })
			Game.track(player, "gate", { zone = zone.id }) -- (analytics: GateBlocked = went in too slow)
		end
	end
end

function Sharks.phase(): (string, number)
	return phase, phaseEnds
end

----------------------------------------------------------------- the boss
Sharks.onBossDown = nil :: ((world: number, hitters: { [Player]: number }) -> ())?

local function bossAttrs(b: Boss?, w: number)
	Workspace:SetAttribute("BossId" .. w, b and not b.down and b.id or nil)
	Workspace:SetAttribute("BossHp" .. w, b and math.max(0, math.ceil(b.hp)) or nil)
	Workspace:SetAttribute("BossMax" .. w, b and b.maxHp or nil)
end

local function bossIn(w: number): Boss?
	for _, b in bosses do
		if b.world == w and not b.down then
			return b
		end
	end
	return nil
end

local function playersIn(w: number): number
	local n = 0
	for _, s in Game.sessions do
		local hrp = Game.root(s.player)
		if hrp and Config.worldAt(hrp.Position) == w then
			n += 1
		end
	end
	return n
end

-- it surfaces over Config.Boss.zone in world w (false: one's already up)
function Sharks.spawnBoss(w: number): boolean
	local cfg = Config.Boss
	if bossIn(w) then
		return false
	end
	local zones = Config.worldZones(w)
	local zone = zones[math.min(cfg.zone, #zones)]
	local home = Vector3.new(Config.originX(w), 0, (zone.zStart + zone.zEnd) / 2)
	local hp = cfg.hpBase + cfg.hpPerPlayer * math.max(1, playersIn(w))
	nextId += 1
	local b: Boss = {
		id = nextId, world = w, home = home, pos = home + Vector3.new(cfg.circle, 0, 0), yaw = 0, state = "circle",
		timer = 0, angle = 0, hp = hp, maxHp = hp, hits = {}, target = nil, nextCharge = os.clock() + cfg.chargeEvery,
		ends = os.clock() + cfg.lifetime, holdFor = 0,
	}
	table.insert(bosses, b)
	bossAttrs(b, w)
	EventRemote:FireAllClients("boss", { id = b.id, world = w, zone = zone.name, x = home.X, z = home.Z })
	return true
end

-- the nearest rider it can see (at sea, huntable, in its world)
local function bossPick(b: Boss): Game.Session?
	local best, bestD = nil, Config.Boss.sight
	for _, s in Game.sessions do
		local hrp = Game.root(s.player)
		if hrp and Config.worldAt(hrp.Position) == b.world and Game.huntable(s) then
			local d = flat(hrp.Position - b.pos).Magnitude
			if d < bestD then
				best, bestD = s, d
			end
		end
	end
	return best
end

local function bossUpdate(b: Boss, dt: number): boolean -- false: remove it
	local cfg = Config.Boss
	b.timer += dt
	if b.state == "leave" then
		b.pos += forward(b.yaw) * cfg.speed * 0.6 * dt
		return b.timer < 3
	end
	if os.clock() > b.ends and b.state ~= "bite" then
		b.state, b.timer, b.target = "leave", 0, nil
		bossAttrs(nil, b.world)
		EventRemote:FireAllClients("bossGone", { id = b.id, world = b.world })
		return true
	end
	if b.state == "bite" then
		if b.timer > b.holdFor then
			b.state, b.timer, b.target = "circle", 0, nil
			b.nextCharge = os.clock() + cfg.chargeEvery
		end
	elseif b.state == "charge" then
		local s = b.target
		local hrp = s and Game.root(s.player)
		if not (s and hrp and Game.sessions[s.player] and Game.huntable(s)) or b.timer > cfg.chargeTime then
			b.state, b.timer, b.target = "circle", 0, nil
			b.nextCharge = os.clock() + cfg.chargeEvery
		else
			local p = (hrp :: BasePart).Position
			b.yaw = turnToward(b.yaw, yawOf(flat(p - b.pos)), cfg.turn * dt)
			local spd = math.max(cfg.speed * 2, Game.walkSpeed(s :: Game.Session) * cfg.chargeMult)
			b.pos = clampLane(b.pos + forward(b.yaw) * spd * dt)
			if flat(p - b.pos).Magnitude < cfg.biteRadius then
				local victim = s :: Game.Session
				local carried = victim.carrying
				local result = Game.bite(victim, b.pos)
				EventRemote:FireAllClients("bite", {
					id = b.id, victim = victim.player.UserId, result = result, px = p.X, pz = p.Z,
					r = carried and carried.r, m = carried and carried.m, cz = carried and carried.z, cs = carried and carried.s,
				})
				b.state, b.timer = "bite", 0
				b.holdFor = result == "eaten" and Config.Shark.eatenTime or 0.8
			end
		end
	else
		-- patrol its spot; every few seconds it goes for the nearest rider
		b.angle += (cfg.speed / cfg.circle) * dt
		local want = b.home + Vector3.new(math.cos(b.angle), 0, math.sin(b.angle)) * cfg.circle
		local to = flat(want - b.pos)
		if to.Magnitude > 0.1 then
			b.yaw = turnToward(b.yaw, yawOf(to), 2.5 * dt)
		end
		b.pos += forward(b.yaw) * math.min(cfg.speed * 1.5 * dt, to.Magnitude)
		if os.clock() >= b.nextCharge then
			local s = bossPick(b)
			if s then
				b.state, b.timer, b.target = "charge", 0, s
				EventRemote:FireAllClients("charge", { id = b.id, victim = s.player.UserId })
			else
				b.nextCharge = os.clock() + 1
			end
		end
	end
	return true
end

-- a harpoon throw from this player at their world's boss
function Sharks.harpoon(s: Game.Session)
	local cfg = Config.Boss
	local hrp = Game.root(s.player)
	if not hrp or os.clock() - (thrownAt[s.player] or 0) < cfg.cooldown then
		return
	end
	local b = bossIn(Config.worldAt(hrp.Position))
	if not b or b.state == "leave" or flat(hrp.Position - b.pos).Magnitude > cfg.range then
		return
	end
	thrownAt[s.player] = os.clock()
	b.hp -= 1
	b.hits[s.player] = (b.hits[s.player] or 0) + 1
	EventRemote:FireAllClients("harpoon", { id = b.id, by = s.player.UserId })
	bossAttrs(b, b.world)
	if b.hp <= 0 then
		b.down = true
		b.state, b.timer, b.target = "leave", 0, nil
		bossAttrs(nil, b.world)
		local winners = {}
		for p, n in b.hits do
			if n >= cfg.minHits and p.Parent then
				winners[p] = n
			end
		end
		EventRemote:FireAllClients("bossDown", { id = b.id, world = b.world })
		if Sharks.onBossDown then
			Sharks.onBossDown(b.world, winners)
		end
	end
end

-- Noodle Bonk on a shark (Bonk.luau): the nearest one coming for this
-- player (or any hunting shark) whose head is in reach gets dazed.
-- true = one was hit
function Sharks.bonk(s: Game.Session, at: Vector3, reach: number): boolean
	local best, bestD = nil, math.huge
	for _, h in hunters do
		if h.state == "stalk" or h.state == "charge" or h.state == "lunge" or h.state == "overshoot" then
			local head = h.pos + forward(h.yaw) * h.length * 0.38
			local d = flat(head - at).Magnitude - h.length * 0.15
			if h.target ~= s then
				d += 4 -- (your own shark first)
			end
			if d <= reach and d < bestD then
				best, bestD = h, d
			end
		end
	end
	if not best then
		return false
	end
	local h = best :: Hunter
	if h.state == "lunge" then
		-- knocked out of the air: it flops down where it is
		h.pos = flat(h.pos)
		if h.target then
			landedAt[h.target.player] = os.clock()
		end
	end
	h.state, h.timer = "dazed", 0
	EventRemote:FireAllClients("daze", { id = h.id, seconds = Config.Bonk.daze, by = s.player.UserId })
	return true
end

function Sharks.bossUp(w: number): boolean
	return bossIn(w) ~= nil
end

function Sharks.start()
	Game.islandExposed = islandExposed
	Game.sharkAggro = Sharks.aggro
	Game.sharkOnGrab = Sharks.onGrab
	RunService.Heartbeat:Connect(update)
	RunService.Heartbeat:Connect(function(dt)
		for i = #bosses, 1, -1 do
			if not bossUpdate(bosses[i], dt) then
				table.remove(bosses, i)
			end
		end
	end)
	Game.action("harpoon", function(s)
		Sharks.harpoon(s)
	end)
	task.spawn(function()
		while true do
			task.wait(0.5)
			deepSweep()
			finsTick()
		end
	end)
	Players.PlayerRemoving:Connect(function(p)
		deepWarned[p] = nil
		closeCallAt[p] = nil
		thrownAt[p] = nil
		armedAt[p], finRest[p] = nil, nil
		escapedAt[p] = nil
		hunted[p] = nil
		landedAt[p] = nil
		shelter[p] = nil
	end)
	task.spawn(function()
		local hadSharks = false
		while true do
			local dt = task.wait(0.1)
			shelterTick(dt)
			if #hunters + #bosses > 0 or hadSharks then
				snapshot()
			end
			hadSharks = #hunters + #bosses > 0
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
			double = Game.event or rng:NextNumber() < cfg.doubleChance -- (Megalodon Hour: always two)
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
			if Game.onDawn then
				task.spawn(Game.onDawn) -- (Treasure: a chest washes up)
			end
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
