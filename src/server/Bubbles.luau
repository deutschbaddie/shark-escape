-- Creature bubbles floating in every zone. Swim into one to grab it.
-- Rarity and mutation are rolled on the server; luck can bump a grab up a tier.

local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")

local Shared = game.ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Layout = require(Shared.Layout)
local Build = require(Shared.Build)
local Creatures = require(Shared.Creatures)
local NameTag = require(Shared.NameTag)
local Game = require(script.Parent.Game)

local Bubbles = {}

type Bubble = { model: Model, pos: Vector3, r: string, m: string?, s: number, zone: Config.Zone, taken: boolean?,
	spilled: boolean?,
	extra: boolean?, -- on top of the zone's quota (spills, Bubble Rain): never respawned
	z: string } -- the creature's own zone (a spilled one keeps where it was caught)

local live: { Bubble } = {}
local byId: { [number]: Bubble } = {}
local nextBubbleId = 0
local tryGrab: (Player, Bubble) -> boolean

local folder: Folder
local rng = Random.new()

function Bubbles.rollRarity(): string
	local total = 0
	for _, r in Config.Rarities do
		total += r.weight
	end
	local roll = rng:NextNumber(0, total)
	for _, r in Config.Rarities do
		roll -= r.weight
		if roll <= 0 then
			return r.id
		end
	end
	return "Common"
end

function Bubbles.rollMutation(): string?
	if Game.mini == "golden" and rng:NextNumber() < Config.MiniEvents.goldChance then
		return "Gold" -- (Golden Tide)
	end
	local mult = 1
	for _, m in Config.Mutations do
		if rng:NextNumber() < m.chance * mult then
			return m.id
		end
	end
	-- this week's limited one (Config.limitedNow)
	local limited = Config.limitedNow()
	if rng:NextNumber() < limited.chance * mult then
		return limited.id
	end
	return nil
end

local function spot(zone: Config.Zone): Vector3
	for _ = 1, 20 do
		local zFrom, zTo = zone.zStart + 14, zone.zEnd - 14
		-- half of the lagoon's bubbles sit close to shore so the first grab is instant
		if zone.index == 1 and rng:NextNumber() < 0.5 then
			zTo = zone.zStart + 80
		end
		local ox = Config.originX(zone.world)
		local p = Vector3.new(ox + rng:NextNumber(-Config.LANE_WIDTH / 2 + 12, Config.LANE_WIDTH / 2 - 12), 3, rng:NextNumber(zFrom, zTo))
		if not Layout.islandAt(p, 5) then
			return p
		end
	end
	return Vector3.new(Config.originX(zone.world), 3, zone.zStart + zone.length / 2)
end

-- a fixed bubble: a spilled haul (exactly what it was), or Bubble Rain
-- (`rain`: rolled like any other, dropped in from the sky, gone after `life`)
type Fixed = { r: string, z: string?, m: string?, s: number?, pos: Vector3, rain: boolean?, life: number? }

-- a bubble in this zone: rolled, or a fixed one (a bitten player's spilled haul)
local function spawnBubble(zone: Config.Zone, fixed: Fixed?): Bubble
	local r = fixed and fixed.r or Bubbles.rollRarity()
	local m = if fixed then fixed.m else Bubbles.rollMutation()
	local size = fixed and fixed.s or Config.rollSize(rng)
	local rarity = Config.rarity(r)
	local pos = fixed and fixed.pos or spot(zone)
	local zid = fixed and fixed.z or zone.id -- (what it is; `zone` is where it floats)

	local model = Build.model("Bubble", folder)
	local shell = Build.ball(model, 5.6, CFrame.new(pos), rarity.color:Lerp(Color3.new(1, 1, 1), 0.45), {
		Name = "Shell", Material = Enum.Material.ForceField, CanCollide = false, CanQuery = false, CastShadow = false,
	})
	model.PrimaryPart = shell
	local creature = Creatures.build(r, m, math.min(Config.sizeScale(size), 1.3), zid)
	creature:PivotTo(CFrame.new(pos))
	creature.Parent = model
	if rarity.index >= 4 then -- Epic+ gets a sky beam you can see from the shore
		Build.cyl(model, 120, 1.4, CFrame.new(pos + Vector3.new(0, 60, 0)), rarity.color, {
			Name = "Beam", Material = Enum.Material.Neon, Transparency = 0.55, CanCollide = false, CanQuery = false, CastShadow = false,
		})
	end
	-- name + rarity tag (rare ones can be seen from further away)
	NameTag.attach(shell, { r = r, z = zid, m = m, s = size }, nil, { height = 4.4, maxDist = (rarity.index >= 3 or size >= 2) and 260 or 90, width = 6 })
	model:SetAttribute("Rarity", r)
	model:SetAttribute("Zone", zone.id)
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	CollectionService:AddTag(model, "Bubble")
	local entry: Bubble = { model = model, pos = pos, r = r, m = m, s = size, zone = zone, spilled = fixed ~= nil and not fixed.rain, extra = fixed ~= nil, z = zid }
	table.insert(live, entry)
	nextBubbleId += 1
	model:SetAttribute("BubbleId", nextBubbleId)
	byId[nextBubbleId] = entry
	model.Destroying:Connect(function()
		byId[model:GetAttribute("BubbleId") :: number] = nil
	end)
	-- hold to grab: rarer = longer hold (more risk with sharks around)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "GrabPrompt"
	prompt.ActionText = "Grab"
	prompt.ObjectText = Config.fullName(zid, r, m, size)
	prompt.HoldDuration = Config.GrabHold[r] or 0.5
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Style = Enum.ProximityPromptStyle.Custom
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.Parent = shell
	prompt.Triggered:Connect(function(player)
		tryGrab(player, entry)
	end)
	if r == "Mythic" and not fixed then -- (only a Mythic sighting is news for everyone)
		Game.notifyAll("announce", { text = ("A %s %s appeared in %s"):format(r, Config.fullName(zone.id, r, m, size), zone.name), color = rarity.color,
			news = true, big = r == "Mythic" })
	end
	if fixed and fixed.rain then
		model:SetAttribute("DropAt", Workspace:GetServerTimeNow()) -- (clients drop it in from the sky)
	end
	if fixed then
		-- spilled / rained: up for grabs a while, then it sinks
		task.delay(fixed.life or Config.SPILL_TIME, function()
			local i = table.find(live, entry)
			if i and not entry.taken then
				entry.taken = true
				table.remove(live, i)
				model:Destroy()
			end
		end)
	end
	return entry
end

-- a bitten player's haul floats free around where it happened
function Bubbles.spill(pos: Vector3, list: { any }, by: Player?, why: string?): { any }
	-- (on the sand, e.g. raid loot bonked loose: it bobs on the beach)
	local onLand = not Layout.inWater(pos)
	local zone = Config.zoneAtPos(pos) or Config.Zones[1]
	local made = {}
	for i, c in list do
		local a = (i / #list) * math.pi * 2 + rng:NextNumber(0, 0.6)
		local r = rng:NextNumber(7, 11)
		local at = Vector3.new(pos.X + math.cos(a) * r, onLand and Config.BEACH_TOP + 2.2 or 3, pos.Z + math.sin(a) * r)
		table.insert(made, spawnBubble(zone, { r = c.r, z = c.z, m = c.m, s = c.s, pos = at }))
	end
	Game.notifyAll("spill", { x = pos.X, z = pos.Z, n = #list, time = Config.SPILL_TIME, why = why,
		userId = by and by.UserId or 0, name = by and by.DisplayName or "Someone" })
	return made
end

-- Bubble Rain (Config.MiniEvents): `n` extra bubbles fall near the shore of
-- world w (its first two zones), rolled like any other, gone after `life`
function Bubbles.rain(w: number, n: number, life: number)
	local zones = Config.worldZones(w)
	for i = 1, n do
		local zone = zones[i % 2 == 0 and math.min(2, #zones) or 1]
		local ox = Config.originX(w)
		local pos
		for _ = 1, 12 do
			local p = Vector3.new(ox + rng:NextNumber(-Config.LANE_WIDTH / 2 + 14, Config.LANE_WIDTH / 2 - 14), 3,
				rng:NextNumber(zone.zStart + 12, math.min(zone.zEnd - 12, zone.zStart + 160)))
			if not Layout.islandAt(p, 5) then
				pos = p
				break
			end
		end
		if pos then
			task.delay(i * 0.12, function()
				spawnBubble(zone, { r = Bubbles.rollRarity(), m = Bubbles.rollMutation(), pos = pos, rain = true, life = life })
			end)
		end
	end
end

-- take a spilled bubble back out of the water (it was rescued with Robux)
-- (true = it was still floating, and now it's gone)
function Bubbles.unspill(entry: any): boolean
	local i = entry and table.find(live, entry)
	if i and not entry.taken then
		entry.taken = true
		table.remove(live, i)
		entry.model:Destroy()
		return true
	end
	return false
end

local function count(zone: Config.Zone): number
	local n = 0
	for _, b in live do
		if b.zone == zone and not b.extra then -- (spills / rain are extra: they don't fill the zone's quota)
			n += 1
		end
	end
	return n
end

-- tells every client to play the net scoop (client Grab.luau): from the
-- bubble, into the sack (or over the head)
local function scoop(s: Game.Session, b: Bubble, r: string)
	local char = s.player.Character
	if char then
		char:SetAttribute("GrabFrom", b.pos)
		char:SetAttribute("GrabWhat", ("%s|%s|%s|%s"):format(r, b.z, b.m or "", tostring(b.s or 1)))
		char:SetAttribute("GrabAt", Workspace:GetServerTimeNow()) -- (last: clients listen for this one)
	end
end

local function grab(s: Game.Session, b: Bubble)
	local r = b.r
	local lucky, pity = false, false
	local idx = Config.rarity(r).index
	if b.spilled then
		-- someone's spilled haul: exactly what it was, no luck / pity re-rolls
		local c = { r = r, z = b.z, m = b.m, s = b.s }
		Game.takeCatch(s, c)
		Game.discover(s, c)
		scoop(s, b, r)
		Game.notify(s.player, "grab", { r = r, m = b.m, z = b.z, s = b.s, v = Config.creatureValue(r, b.z, b.m, b.s) * Game.coinMult(s) })
		return
	end
	if idx < Config.rarity("Legendary").index and rng:NextNumber() < Game.luck(s) then -- (Mythics are never luck)
		r = Config.Rarities[idx + 1].id
		lucky = true
	end
	s.profile.grabs += 1
	if s.profile.grabs == 1 and Config.rarity(r).index < 2 then
		r = "Uncommon" -- your very first catch is a little special
	end
	if s.profile.grabs == Config.Luck.pityGrab and Config.rarity(r).index < 3 then
		r = "Rare"
		pity = true
	end
	if s.profile.grabs == Config.Luck.pityEpic and Config.rarity(r).index < 4 then
		local hadEpic = false
		for key in s.profile.index do
			if Config.rarity(key:match(":(%w+)$") or "Common").index >= 4 then
				hadEpic = true
			end
		end
		if not hadEpic then
			r = "Epic"
			pity = true
		end
	end
	local c = { r = r, z = b.z, m = b.m, s = b.s }
	Game.takeCatch(s, c) -- (your hands, or your net)
	if Game.handsFull(s) then
		Game.notify(s.player, "announce", { text = "Net full! Take your catch home" })
	end
	scoop(s, b, r)
	Game.discover(s, c)
	if Game.sharkOnGrab then
		Game.sharkOnGrab(s, r) -- the shark may notice
	end
	-- taken from water too deep for you: every shark on the way home wants it
	local where = b.zone
	if not b.spilled and (where.gate > s.profile.speed or (where.evolve or 0) > s.profile.rebirths) then
		s.stolen = true
		Game.notify(s.player, "stolen", {})
	-- a Legendary or a Mythic: its zone's shark wants it, so run it home
	elseif Config.rarity(r).index >= 5 and s.profile.tut >= 5 and Game.sharkAggro then
		Game.sharkAggro(s, Config.Shark.prizeGrudge, "prize")
	end
	-- the whole server hears about the big ones
	local idx = Config.rarity(r).index
	if idx >= 5 or (b.s or 1) >= 2 or (b.m and idx >= 4) then
		Game.notifyAll("bigCatch", { by = s.player.DisplayName, userId = s.player.UserId, name = Config.fullName(b.z, r, b.m, b.s), r = r })
		Game.beamDock(s, Config.rarity(r).color, 60) -- everyone can see whose dock it went to
	end
	Game.notify(s.player, "grab", { r = r, m = b.m, z = b.z, s = b.s, lucky = lucky, pity = pity,
		v = Config.creatureValue(r, b.z, b.m, b.s) * Game.coinMult(s) })
end

-- hold the prompt to grab (server checks you're really there)
-- (true = it's in your hands now)
tryGrab = function(player: Player, b: Bubble): boolean
	local s = Game.sessions[player]
	if not s or b.taken or Game.handsFull(s) or os.clock() < s.eatenUntil then
		return false
	end
	local hrp = Game.root(player)
	if not hrp or Vector2.new(hrp.Position.X - b.pos.X, hrp.Position.Z - b.pos.Z).Magnitude > 16 then
		return false
	end
	local i = table.find(live, b)
	if not i then
		return false
	end
	b.taken = true
	table.remove(live, i)
	b.model:Destroy()
	grab(s, b)
	local zone = b.zone
	task.delay(rng:NextNumber(3, 6), function()
		if count(zone) < Config.BUBBLES_PER_ZONE then
			spawnBubble(zone)
		end
	end)
	return true
end

-- Golden Bubble / packs / rewards: straight into your tank (a paid or won
-- creature must never be able to wriggle free, get eaten or vanish on leave)
-- with the catch moment shown on top
function Bubbles.give(s: Game.Session, r: string, zoneId: string?, size: number?)
	local zone = Config.zoneForSpeed(s.profile.speed, s.profile.world, s.profile.rebirths)
	local c = { r = r, z = zoneId or zone.id, m = Bubbles.rollMutation(), s = size or Config.rollSize(rng) }
	Game.discover(s, c)
	Game.notify(s.player, "grab", { r = c.r, m = c.m, z = c.z, s = c.s, gift = true, v = Config.creatureValue(c.r, c.z, c.m, c.s) * Game.coinMult(s) })
	Game.addCreature(s, c)
end

-- touch screens grab through this action (Prompts.luau runs the hold on
-- the button itself, which works on every phone); same checks as the prompt
Game.action("grab", function(s, id)
	local b = typeof(id) == "number" and byId[id]
	if b then
		tryGrab(s.player, b)
	end
end)

function Bubbles.start()
	Game.spill = Bubbles.spill
	folder = Instance.new("Folder")
	folder.Name = "Bubbles"
	folder.Parent = Workspace
	for _, zone in Config.Zones do
		for _ = 1, Config.BUBBLES_PER_ZONE do
			spawnBubble(zone)
		end
	end
end

return Bubbles
