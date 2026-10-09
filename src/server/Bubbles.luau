-- Creature bubbles floating in every zone. Swim into one to grab it.
-- Rarity and mutation are rolled on the server; luck can bump a grab up a tier.

local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
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
	reservedBy: Player?, reservedUntil: number?, spilled: boolean? }

local live: { Bubble } = {}
local byId: { [number]: Bubble } = {}
local nextBubbleId = 0
local tryGrab: (Player, Bubble, boolean?, boolean?) -> boolean

-- Legendary reel: grabbing a Legendary starts a timing minigame on the
-- client (Reel.luau) while its zone's shark charges you. Land it and it's
-- yours; fumble (or take too long) and it slips back into the water.
local REEL_TIME = 7 -- seconds the client gets
local REEL_MIN = 1.2 -- faster than this isn't a real reel
local reels: { [Player]: { b: Bubble, started: number } } = {}
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

type Fixed = { r: string, m: string?, s: number?, pos: Vector3 }

-- a bubble in this zone: rolled, or a fixed one (a bitten player's spilled haul)
local function spawnBubble(zone: Config.Zone, fixed: Fixed?)
	local r = fixed and fixed.r or Bubbles.rollRarity()
	local m = if fixed then fixed.m else Bubbles.rollMutation()
	local size = fixed and fixed.s or Config.rollSize(rng)
	local rarity = Config.rarity(r)
	local pos = fixed and fixed.pos or spot(zone)

	local model = Build.model("Bubble", folder)
	local shell = Build.ball(model, 5.6, CFrame.new(pos), rarity.color:Lerp(Color3.new(1, 1, 1), 0.45), {
		Name = "Shell", Material = Enum.Material.ForceField, CanCollide = false, CanQuery = false, CastShadow = false,
	})
	model.PrimaryPart = shell
	local creature = Creatures.build(r, m, math.min(Config.sizeScale(size), 1.3), zone.id)
	creature:PivotTo(CFrame.new(pos))
	creature.Parent = model
	if rarity.index >= 4 then -- Epic+ gets a sky beam you can see from the shore
		Build.cyl(model, 120, 1.4, CFrame.new(pos + Vector3.new(0, 60, 0)), rarity.color, {
			Name = "Beam", Material = Enum.Material.Neon, Transparency = 0.55, CanCollide = false, CanQuery = false, CastShadow = false,
		})
	end
	-- name + rarity tag (rare ones can be seen from further away)
	NameTag.attach(shell, { r = r, z = zone.id, m = m, s = size }, nil, { height = 4.4, maxDist = (rarity.index >= 3 or size >= 2) and 260 or 90, width = 6 })
	model:SetAttribute("Rarity", r)
	model:SetAttribute("Zone", zone.id)
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	CollectionService:AddTag(model, "Bubble")
	local entry: Bubble = { model = model, pos = pos, r = r, m = m, s = size, zone = zone, spilled = fixed ~= nil }
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
	prompt.ObjectText = Config.fullName(zone.id, r, m, size)
	prompt.HoldDuration = Config.GrabHold[r] or 0.5
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Style = Enum.ProximityPromptStyle.Custom
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.Parent = shell
	prompt.Triggered:Connect(function(player)
		tryGrab(player, entry)
	end)
	if r == "Legendary" and not fixed then
		Game.notifyAll("announce", { text = ("A Legendary %s appeared in %s"):format(Config.fullName(zone.id, r, m, size), zone.name), color = rarity.color })
	end
	if fixed then
		-- spilled: up for grabs a while, then it sinks
		task.delay(Config.SPILL_TIME, function()
			local i = table.find(live, entry)
			if i and not entry.taken then
				entry.taken = true
				table.remove(live, i)
				model:Destroy()
			end
		end)
	end
end

-- a bitten player's haul floats free around where it happened
function Bubbles.spill(pos: Vector3, list: { any }, by: Player?)
	local zone = Config.zoneAtPos(pos)
	if not zone then
		return
	end
	for i, c in list do
		local a = (i / #list) * math.pi * 2 + rng:NextNumber(0, 0.6)
		local r = rng:NextNumber(7, 11)
		local at = Vector3.new(pos.X + math.cos(a) * r, 3, pos.Z + math.sin(a) * r)
		spawnBubble(zone, { r = c.r, m = c.m, s = c.s, pos = at })
	end
	Game.notifyAll("spill", { x = pos.X, z = pos.Z, n = #list, time = Config.SPILL_TIME,
		userId = by and by.UserId or 0, name = by and by.DisplayName or "Someone" })
end

local function count(zone: Config.Zone): number
	local n = 0
	for _, b in live do
		if b.zone == zone then
			n += 1
		end
	end
	return n
end

local function grab(s: Game.Session, b: Bubble)
	local r = b.r
	local lucky, pity = false, false
	local idx = Config.rarity(r).index
	if idx < #Config.Rarities and rng:NextNumber() < Game.luck(s) then
		r = Config.Rarities[idx + 1].id
		lucky = true
	end
	s.profile.grabs += 1
	if s.profile.grabs == Config.Luck.pityGrab and Config.rarity(r).index < 3 then
		r = "Rare"
		pity = true
	end
	if s.profile.grabs == Config.Luck.pityEpic and Config.rarity(r).index < 4 then
		local hadEpic = false
		for key in s.profile.index do
			if key:match(":Epic$") or key:match(":Legendary$") then
				hadEpic = true
			end
		end
		if not hadEpic then
			r = "Epic"
			pity = true
		end
	end
	local c = { r = r, z = b.zone.id, m = b.m, s = b.s }
	Game.takeCatch(s, c) -- (your hands, or your net)
	Game.discover(s, c)
	if Game.sharkOnGrab then
		Game.sharkOnGrab(s, r) -- the shark may notice
	end
	-- the whole server hears about the big ones
	local idx = Config.rarity(r).index
	if idx >= 5 or (b.s or 1) >= 2 or (b.m and idx >= 4) then
		Game.notifyAll("bigCatch", { by = s.player.DisplayName, userId = s.player.UserId, name = Config.fullName(b.zone.id, r, b.m, b.s), r = r })
		Game.beamDock(s, Config.rarity(r).color, 60) -- everyone can see whose dock it went to
	end
	Game.notify(s.player, "grab", { r = r, m = b.m, z = b.zone.id, s = b.s, lucky = lucky, pity = pity,
		v = Config.creatureValue(r, b.zone.id, b.m, b.s) * Game.coinMult(s) })
end

-- hold the prompt to grab (server checks you're really there)
-- swept = the ride-over sweep already checked your path passed through it;
-- reeled = you just won the Legendary reel for it
-- (true = it's in your hands now)
tryGrab = function(player: Player, b: Bubble, swept: boolean?, reeled: boolean?): boolean
	local s = Game.sessions[player]
	if not s or b.taken or Game.handsFull(s) or os.clock() < s.eatenUntil then
		return false
	end
	local hrp = Game.root(player)
	local reach = reeled and 40 or 16 -- (you drift a little while reeling)
	if not hrp or (not swept and Vector2.new(hrp.Position.X - b.pos.X, hrp.Position.Z - b.pos.Z).Magnitude > reach) then
		return false
	end
	if b.reservedBy and b.reservedBy ~= player and os.clock() < (b.reservedUntil or 0) then
		return false -- someone's reeling this one in
	end
	if not reeled and Config.rarity(b.r).index >= 5 and s.profile.tut >= 5 then
		local old = reels[player]
		if old and os.clock() - old.started <= REEL_TIME + 2 then
			return false
		elseif old then
			-- a reel the client never answered: let it go
			reels[player] = nil
			if old.b.reservedBy == player then
				old.b.reservedBy, old.b.reservedUntil = nil, nil
			end
		end
		b.reservedBy, b.reservedUntil = player, os.clock() + REEL_TIME + 2
		reels[player] = { b = b, started = os.clock() }
		Game.notify(player, "reel", { time = REEL_TIME, name = Config.fullName(b.zone.id, b.r, b.m, b.s) })
		if Game.sharkAggro then
			Game.sharkAggro(s, REEL_TIME + 6, "reel")
		end
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

-- Golden Bubble / Starter Pack: straight into your hands (or your tank)
function Bubbles.give(s: Game.Session, r: string, zoneId: string?, size: number?)
	local zone = Config.zoneForSpeed(s.profile.speed, s.profile.world)
	local c = { r = r, z = zoneId or zone.id, m = Bubbles.rollMutation(), s = size or Config.rollSize(rng) }
	Game.discover(s, c)
	if s.carrying then
		Game.addCreature(s, c)
	else
		Game.setCarry(s, c)
		Game.notify(s.player, "grab", { r = c.r, m = c.m, z = c.z, s = c.s, gift = true, v = Config.creatureValue(c.r, c.z, c.m, c.s) * Game.coinMult(s) })
	end
end

-- the reel's result from the client
Game.action("reel", function(s, ok)
	local r = reels[s.player]
	if not r then
		return
	end
	reels[s.player] = nil
	local b = r.b
	local took = os.clock() - r.started
	if b.reservedBy == s.player then
		b.reservedBy, b.reservedUntil = nil, nil
	end
	if ok == true and took >= REEL_MIN and took <= REEL_TIME + 2 and not b.taken and tryGrab(s.player, b, false, true) then
		Game.track(s.player, "reelWon", {})
	else
		Game.notify(s.player, "slipped", { name = Config.fullName(b.zone.id, b.r, b.m, b.s) })
	end
end)

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
	-- ride-over grabs: Common..Rare are scooped up just by riding through
	-- them (swept from your last spot, so speed can't skip them); Epic and
	-- Legendary still want a hold (the tense moment). Not in the tutorial,
	-- which teaches the prompt.
	local last: { [Player]: Vector3 } = {}
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < 0.1 then
			return
		end
		acc = 0
		for player, s in Game.sessions do
			local hrp = Game.root(player)
			if not hrp or s.profile.tut < 5 or hrp.Anchored then
				last[player] = nil
				continue
			end
			local pos = hrp.Position
			local from = last[player] or pos
			last[player] = pos
			-- (a jump longer than your speed allows is a teleport, not a ride)
			if not Layout.inWater(pos) or reels[player] or Game.handsFull(s) or (pos - from).Magnitude > Game.walkSpeed(s) * 0.1 * 2.5 + 8 then
				continue
			end
			for i = #live, 1, -1 do
				local b = live[i]
				if b and Config.rarity(b.r).index <= Config.RIDE_GRAB_MAX
					and Layout.segmentDist(b.pos, from, pos) < Config.GRAB_RADIUS and math.abs(pos.Y - b.pos.Y) < 10 then
					tryGrab(player, b, true)
					if Game.handsFull(s) then
						break
					end
				end
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(p)
		last[p] = nil
		local r = reels[p]
		if r then
			if r.b.reservedBy == p then
				r.b.reservedBy, r.b.reservedUntil = nil, nil
			end
			reels[p] = nil
		end
	end)
end

return Bubbles
