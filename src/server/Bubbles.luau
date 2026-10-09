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

type Bubble = { model: Model, pos: Vector3, r: string, m: string?, s: number, zone: Config.Zone, taken: boolean? }

local live: { Bubble } = {}
local byId: { [number]: Bubble } = {}
local nextBubbleId = 0
local tryGrab: (Player, Bubble) -> ()
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
	local mult = Game.storm and Config.Storm.mutations or 1
	for _, m in Config.Mutations do
		if rng:NextNumber() < m.chance * mult then
			return m.id
		end
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

local function spawnBubble(zone: Config.Zone)
	local r = Bubbles.rollRarity()
	local m = Bubbles.rollMutation()
	local size = Config.rollSize(rng)
	local rarity = Config.rarity(r)
	local pos = spot(zone)

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
	local entry: Bubble = { model = model, pos = pos, r = r, m = m, s = size, zone = zone }
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
	if r == "Legendary" then
		Game.notifyAll("announce", { text = ("A LEGENDARY %s appeared in %s!"):format(Config.fullName(zone.id, r, m, size), zone.name), color = rarity.color })
	end
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
	Game.setCarry(s, c)
	Game.discover(s, c)
	Game.notify(s.player, "grab", { r = r, m = b.m, z = b.zone.id, s = b.s, lucky = lucky, pity = pity,
		v = Config.creatureValue(r, b.zone.id, b.m, b.s) * Game.coinMult(s) })
end

-- hold the prompt to grab (server checks you're really there)
tryGrab = function(player: Player, b: Bubble)
	local s = Game.sessions[player]
	if not s or b.taken or s.carrying or os.clock() < s.eatenUntil then
		return
	end
	local hrp = Game.root(player)
	if not hrp or Vector2.new(hrp.Position.X - b.pos.X, hrp.Position.Z - b.pos.Z).Magnitude > 16 then
		return
	end
	local i = table.find(live, b)
	if not i then
		return
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

-- touch screens grab through this action (Prompts.luau runs the hold on
-- the button itself, which works on every phone); same checks as the prompt
Game.action("grab", function(s, id)
	local b = typeof(id) == "number" and byId[id]
	if b then
		tryGrab(s.player, b)
	end
end)

function Bubbles.start()
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
