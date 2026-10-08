-- Server-side shark AI. Every ~90s: an 8s warning, then a hunt. Each player
-- still in open water gets their own shark (the variant of their zone),
-- which hunts like a real one:
--   stalk  - circles you in a tightening spiral (time to reach sand!)
--   charge - lines up and lunges
--   bite   - CHOMP (clients play the leap; the victim gets a cutscene)
-- Reach an island or the beach at any point and it circles you, then leaves.
-- The server owns positions and bites; clients only draw and animate.

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

local VARIANTS = { "Baby", "Hammerhead", "Tiger", "GreatWhite", "Mecha", "Megalodon" }
local VARIANT_INDEX = {}
for i, v in VARIANTS do
	VARIANT_INDEX[v] = i
end

-- wire codes (SharkView.STATE_NAMES must match)
local STATE = { charge = 1, circle = 2, leave = 3, bite = 4, stalk = 5 }

type Hunter = {
	id: number,
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
}

local hunters: { Hunter } = {}
local nextId = 0
local phase = "calm"
local phaseEnds = 0
local hunted: { [Player]: boolean } = {}

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
	return Vector3.new(math.clamp(p.X, -Config.LANE_WIDTH / 2 + 6, Config.LANE_WIDTH / 2 - 6), 0,
		math.clamp(p.Z, Config.SHORE_Z + 6, Config.OCEAN_END - 8))
end

local function spawnHunter(s: Game.Session)
	if #hunters >= Config.Shark.maxHunters then
		return
	end
	local hrp = Game.root(s.player)
	if not hrp then
		return
	end
	local p = hrp.Position
	local zone = Config.zoneAt(p.Z) or Config.Zones[1]
	local a = math.rad(math.random(-55, 55))
	local away = Vector3.new(math.sin(a), 0, math.cos(a)) -- from deeper water
	local start = clampLane(p + away * Config.Shark.spawnDistance)
	local rel = flat(start - p)
	nextId += 1
	table.insert(hunters, {
		id = nextId,
		variant = zone.shark,
		length = zone.sharkLength,
		speed = zone.sharkSpeed,
		pos = start,
		yaw = yawOf(-rel),
		target = s,
		state = "stalk",
		island = nil,
		angle = math.atan2(rel.Z, rel.X),
		radius = rel.Magnitude,
		stalkTime = Config.Shark.stalk,
		timer = 0,
		holdFor = 0,
	})
	hunted[s.player] = true
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
				h.angle += (h.speed * 0.42 / math.max(h.radius, 8)) * dt
				local goal = Vector3.new(p.X + math.cos(h.angle) * h.radius, 0, p.Z + math.sin(h.angle) * h.radius)
				local to = flat(goal - h.pos)
				local maxStep = h.speed * 1.4 * dt
				local move = to.Magnitude > maxStep and to.Unit * maxStep or to
				if move.Magnitude > 0.05 then
					h.yaw = turnToward(h.yaw, yawOf(move), 6 * dt)
				end
				h.pos = clampLane(h.pos + move)
				pushOutOfIslands(h)
				if h.timer >= h.stalkTime then
					h.state, h.timer = "charge", 0
					EventRemote:FireAllClients("charge", { id = h.id, victim = (s :: Game.Session).player.UserId })
				end
			end
		elseif h.state == "charge" then
			if not alive then
				h.state, h.timer = "leave", 0
			elseif not Game.huntable(s :: Game.Session) then
				lostTarget(h, hrp)
			else
				local p = (hrp :: BasePart).Position
				local to = flat(p - h.pos)
				local dist = to.Magnitude
				h.yaw = turnToward(h.yaw, yawOf(to), 5 * dt)
				h.pos += forward(h.yaw) * math.min(h.speed * cfg.chargeMult * dt, math.max(dist - 1, 0))
				pushOutOfIslands(h)
				local head = h.pos + forward(h.yaw) * h.length * 0.38
				local hd = Vector2.new(p.X - head.X, p.Z - head.Z).Magnitude
				if hd < math.max(3.5, h.length * 0.16) or dist < h.length * 0.3 then
					local victim = s :: Game.Session
					local carried = victim.carrying
					local result = Game.bite(victim, h.pos)
					EventRemote:FireAllClients("bite", {
						id = h.id, victim = victim.player.UserId, result = result, x = p.X, z = p.Z,
						r = carried and carried.r, m = carried and carried.m, z = carried and carried.z,
					})
					h.state, h.timer = "bite", 0
					h.holdFor = result == "eaten" and cfg.eatenTime or 0.8
				elseif h.timer > cfg.chargeGiveUp then
					-- they're outrunning it: back to circling for a moment
					local rel = flat(h.pos - p)
					h.state, h.timer = "stalk", 0
					h.stalkTime = cfg.stalk * 0.5
					h.angle = math.atan2(rel.Z, rel.X)
					h.radius = rel.Magnitude
				end
			end
		elseif h.state == "circle" then
			local island = h.island :: Layout.Island
			if alive and Game.huntable(s :: Game.Session) and phase == "hunt" then
				-- they left the island! start over
				local rel = flat(h.pos - (hrp :: BasePart).Position)
				h.state, h.timer = "stalk", 0
				h.stalkTime = cfg.stalk * 0.6
				h.angle = math.atan2(rel.Z, rel.X)
				h.radius = rel.Magnitude
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
					hunted[h.target.player] = nil
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
	for _, s in Game.sessions do
		if not hunted[s.player] and Game.huntable(s) then
			spawnHunter(s)
		end
	end
end

function Sharks.phase(): (string, number)
	return phase, phaseEnds
end

function Sharks.start()
	RunService.Heartbeat:Connect(update)
	Players.PlayerRemoving:Connect(function(p)
		hunted[p] = nil
	end)
	task.spawn(function()
		local hadSharks = false
		while true do
			task.wait(0.1)
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
			phase, phaseEnds = "hunt", os.clock() + cfg.hunt
			EventRemote:FireAllClients("hunt", { duration = cfg.hunt })
			while os.clock() < phaseEnds do
				huntSweep()
				task.wait(0.4)
			end
			phase, phaseEnds = "calm", os.clock() + cfg.cycle - cfg.warning - cfg.hunt
			for _, h in hunters do
				if h.state ~= "bite" then
					h.state, h.timer = "leave", 0
				end
			end
			EventRemote:FireAllClients("clear", { next = cfg.cycle - cfg.warning - cfg.hunt })
			task.wait(cfg.cycle - cfg.warning - cfg.hunt)
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
