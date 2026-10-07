-- Server-side shark AI. Every ~60s: 5s warning, then a hunt. Each player
-- caught in open water gets their own shark (the variant of their zone).
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

local STATE = { chase = 1, circle = 2, leave = 3, bite = 4 }

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
	timer: number,
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
	local start = p + away * Config.Shark.spawnDistance
	start = Vector3.new(math.clamp(start.X, -Config.LANE_WIDTH / 2 + 6, Config.LANE_WIDTH / 2 - 6), 0,
		math.clamp(start.Z, Config.SHORE_Z + 8, Config.OCEAN_END - 8))
	nextId += 1
	table.insert(hunters, {
		id = nextId,
		variant = zone.shark,
		length = zone.sharkLength,
		speed = zone.sharkSpeed,
		pos = start,
		yaw = yawOf(p - start),
		target = s,
		state = "chase",
		island = nil,
		angle = 0,
		timer = 0,
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

local function update(dt: number)
	for i = #hunters, 1, -1 do
		local h = hunters[i]
		h.timer += dt
		local s = h.target
		local hrp = s and Game.root(s.player)
		if h.state == "chase" then
			if not (s and hrp and Game.sessions[s.player]) then
				h.state, h.timer = "leave", 0
			elseif not Game.huntable(s) then
				local island = Layout.islandAt(hrp.Position, 1)
				if island and phase == "hunt" then
					h.state, h.island, h.timer = "circle", island, 0
					local d = h.pos - island.pos
					h.angle = math.atan2(d.Z, d.X)
				else
					h.state, h.timer = "leave", 0
				end
			else
				local to = Vector3.new(hrp.Position.X - h.pos.X, 0, hrp.Position.Z - h.pos.Z)
				local dist = to.Magnitude
				h.yaw = turnToward(h.yaw, yawOf(to), 5 * dt)
				h.pos += forward(h.yaw) * math.min(h.speed * dt, math.max(dist - 1, 0))
				pushOutOfIslands(h)
				local head = h.pos + forward(h.yaw) * h.length * 0.38
				local hd = Vector2.new(hrp.Position.X - head.X, hrp.Position.Z - head.Z).Magnitude
				if hd < math.max(3.5, h.length * 0.16) or dist < h.length * 0.3 then
					local result = Game.bite(s, h.pos)
					EventRemote:FireAllClients("bite", {
						id = h.id, victim = s.player.UserId, result = result, x = head.X, z = head.Z,
					})
					h.state, h.timer = "bite", 0
				end
			end
		elseif h.state == "circle" then
			local island = h.island :: Layout.Island
			if s and hrp and Game.huntable(s) and phase == "hunt" then
				h.state, h.timer = "chase", 0 -- they left the island!
			elseif phase ~= "hunt" or not (s and hrp) then
				h.state, h.timer = "leave", 0
			else
				local r = island.radius + h.length * 0.35 + 5
				h.angle += (h.speed * 0.3 / r) * dt
				local want = island.pos + Vector3.new(math.cos(h.angle), 0, math.sin(h.angle)) * r
				local to = want - h.pos
				h.yaw = turnToward(h.yaw, yawOf(to), 4 * dt)
				h.pos += forward(h.yaw) * math.min(h.speed * 0.45 * dt, to.Magnitude)
				h.pos = Vector3.new(h.pos.X, 0, h.pos.Z)
			end
		elseif h.state == "bite" then
			if h.timer > 0.8 then
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
