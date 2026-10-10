-- Treasure chests: every dawn (the reward for surviving the night) a
-- glowing chest washes up somewhere in each world's ocean (only zones
-- someone there can reach) with a beam of light over it. Everyone in that world gets told; the first rider to reach
-- it wins coins, speed and maybe a rare creature. Unclaimed, it sinks.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = game.ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Layout = require(Shared.Layout)
local Build = require(Shared.Build)
local Game = require(script.Parent.Game)
local Bubbles = require(script.Parent.Bubbles)

local Treasure = {}

local LIFE = 100 -- seconds before an unclaimed chest sinks
local REACH = 9 -- studs from the chest to claim it
local CREATURE_CHANCE = 0.3
local PRIZES = { { "Rare", 60 }, { "Epic", 30 }, { "Legendary", 10 } }

type Chest = { model: Model, pos: Vector3, zone: Config.Zone, expires: number }

local rng = Random.new()
local active: { [number]: Chest } = {}
local folder: Folder

local C = Color3.fromRGB

local function build(pos: Vector3): Model
	local m = Build.model("Treasure", folder)
	local wood, dark, gold = C(150, 95, 50), C(105, 62, 30), C(255, 200, 40)
	local base = CFrame.new(pos)
	Build.studs(Build.part(m, Vector3.new(4.4, 2.4, 3.2), base * CFrame.new(0, 1.2, 0), wood), Build.ALL_FACES)
	Build.part(m, Vector3.new(4.5, 1.1, 3.3), base * CFrame.new(0, 2.95, 0), dark)
	for _, x in { -1.6, 0, 1.6 } do
		Build.part(m, Vector3.new(0.35, 3.6, 3.4), base * CFrame.new(x, 1.95, 0), gold, { Material = Enum.Material.Metal })
	end
	Build.part(m, Vector3.new(0.7, 0.8, 0.3), base * CFrame.new(0, 2.3, -1.72), gold, { Material = Enum.Material.Neon })
	-- the beam: seen from far away
	local beam = Build.cyl(m, 90, 2.2, base * CFrame.new(0, 45, 0), gold, {
		Name = "Beam", Material = Enum.Material.Neon, Transparency = 0.55, CastShadow = false,
	})
	local light = Instance.new("PointLight")
	light.Color = gold
	light.Range = 24
	light.Brightness = 3
	light.Parent = beam
	local sparkles = Instance.new("Sparkles")
	sparkles.SparkleColor = gold
	sparkles.Parent = m:FindFirstChildWhichIsA("BasePart")
	Build.ghost(m)
	return m
end

-- a spot in a zone somebody in world w can reach (nil: nobody's there)
local function pickSpot(w: number): (Vector3?, Config.Zone?)
	local deepest = 0
	for _, s in Game.sessions do
		if s.profile.world == w then
			deepest = math.max(deepest, Config.zoneForSpeed(s.profile.speed, w, s.profile.rebirths).index)
		end
	end
	if deepest == 0 then
		return nil, nil
	end
	local zone = Config.worldZones(w)[rng:NextInteger(1, deepest)]
	local ox = Config.originX(w)
	for _ = 1, 30 do
		local p = Vector3.new(ox + rng:NextNumber(-Config.LANE_WIDTH / 2 + 20, Config.LANE_WIDTH / 2 - 20), 0.6,
			rng:NextNumber(zone.zStart + 30, zone.zEnd - 30))
		if not Layout.islandAt(p, 6) then
			return p, zone
		end
	end
	return nil, nil
end

local function remove(w: number)
	local c = active[w]
	if c then
		c.model:Destroy()
		active[w] = nil
	end
end

local function spawn(w: number)
	if active[w] then
		return
	end
	local pos, zone = pickSpot(w)
	if not (pos and zone) then
		return
	end
	active[w] = { model = build(pos), pos = pos, zone = zone, expires = os.clock() + LIFE }
	Game.notifyAll("treasure", { kind = "spawn", world = w, x = pos.X, y = pos.Y, z = pos.Z, zone = zone.name })
end

local function rollPrize(): string
	local total = 0
	for _, p in PRIZES do
		total += p[2]
	end
	local roll = rng:NextNumber(0, total)
	for _, p in PRIZES do
		roll -= p[2]
		if roll <= 0 then
			return p[1]
		end
	end
	return PRIZES[1][1]
end

local function claim(w: number, s: Game.Session)
	local c = active[w]
	if not c then
		return
	end
	remove(w)
	local p = s.profile
	local coins = math.max(250, math.floor(Game.income(s) * 90))
	local speed = math.max(10, math.floor(Game.gain(s) * 15))
	p.coins += coins
	p.speed += speed
	local creature = nil
	if rng:NextNumber() < CREATURE_CHANCE then
		creature = rollPrize()
		Bubbles.give(s, creature, c.zone.id)
	end
	s.dirty = true
	Game.notify(s.player, "treasure", { kind = "won", coins = coins, speed = speed, creature = creature, world = w, x = c.pos.X, y = c.pos.Y, z = c.pos.Z })
	Game.notifyAll("treasure", { kind = "claimed", world = w, by = s.player.DisplayName, userId = s.player.UserId })
	Game.track(s.player, "treasure", { coins = coins })
end

-- tell someone who joins (or arrives through the portal) about a live chest
function Treasure.tell(player: Player)
	for w, c in active do
		Game.notify(player, "treasure", { kind = "spawn", world = w, x = c.pos.X, y = c.pos.Y, z = c.pos.Z, zone = c.zone.name, quiet = true })
	end
end

function Treasure.start()
	folder = Instance.new("Folder")
	folder.Name = "Treasure"
	folder.Parent = Workspace
	Game.onDawn = function()
		task.wait(3) -- (once the sun is up)
		for w in Config.Worlds do
			spawn(w)
		end
	end
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < 0.2 then
			return
		end
		acc = 0
		local now = os.clock()
		for w, c in active do
			if now >= c.expires then
				remove(w)
				Game.notifyAll("treasure", { kind = "gone", world = w })
				continue
			end
			for _, s in Game.sessions do
				local char = s.player.Character
				local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
				if hrp and s.profile.world == w and (hrp.Position - c.pos).Magnitude < REACH then
					claim(w, s)
					break
				end
			end
		end
	end)
	Players.PlayerAdded:Connect(function(player)
		task.wait(10)
		Treasure.tell(player)
	end)
end

return Treasure
