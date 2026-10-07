-- Creature bubbles floating in every zone. Swim into one to grab it.
-- Rarity and mutation are rolled on the server; luck can bump a grab up a tier.

local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")

local Shared = game.ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Layout = require(Shared.Layout)
local Build = require(Shared.Build)
local Creatures = require(Shared.Creatures)
local Game = require(script.Parent.Game)

local Bubbles = {}

type Bubble = { model: Model, pos: Vector3, r: string, m: string?, zone: Config.Zone }

local live: { Bubble } = {}
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
	for _, m in Config.Mutations do
		if rng:NextNumber() < m.chance then
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
		local p = Vector3.new(rng:NextNumber(-Config.LANE_WIDTH / 2 + 12, Config.LANE_WIDTH / 2 - 12), 3, rng:NextNumber(zFrom, zTo))
		if not Layout.islandAt(p, 5) then
			return p
		end
	end
	return Vector3.new(0, 3, zone.zStart + zone.length / 2)
end

local function spawnBubble(zone: Config.Zone)
	local r = Bubbles.rollRarity()
	local m = Bubbles.rollMutation()
	local rarity = Config.rarity(r)
	local pos = spot(zone)

	local model = Build.model("Bubble", folder)
	local shell = Build.ball(model, 5.6, CFrame.new(pos), rarity.color:Lerp(Color3.new(1, 1, 1), 0.45), {
		Name = "Shell", Material = Enum.Material.ForceField, CanCollide = false, CanQuery = false, CastShadow = false,
	})
	model.PrimaryPart = shell
	local creature = Creatures.build(r, m, 1)
	creature:PivotTo(CFrame.new(pos))
	creature.Parent = model
	if rarity.index >= 4 then -- Epic+ gets a sky beam you can see from the shore
		Build.cyl(model, 120, 1.4, CFrame.new(pos + Vector3.new(0, 60, 0)), rarity.color, {
			Name = "Beam", Material = Enum.Material.Neon, Transparency = 0.55, CanCollide = false, CanQuery = false, CastShadow = false,
		})
	end
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(160, 40)
	bb.StudsOffset = Vector3.new(0, 4.6, 0)
	bb.MaxDistance = rarity.index >= 3 and 260 or 90
	bb.LightInfluence = 0
	bb.Parent = shell
	local t = Instance.new("TextLabel")
	t.Size = UDim2.fromScale(1, 1)
	t.BackgroundTransparency = 1
	t.Font = Enum.Font.FredokaOne
	t.TextScaled = true
	t.TextColor3 = rarity.color
	t.TextStrokeTransparency = 0.1
	t.TextStrokeColor3 = Color3.fromRGB(27, 29, 63)
	t.Text = (m and (m .. " ") or "") .. r
	t.Parent = bb
	model:SetAttribute("Rarity", r)
	model:SetAttribute("Zone", zone.id)
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	CollectionService:AddTag(model, "Bubble")
	table.insert(live, { model = model, pos = pos, r = r, m = m, zone = zone })
	if r == "Legendary" then
		Game.notifyAll("announce", { text = ("A LEGENDARY %s appeared in %s!"):format(rarity.species, zone.name), color = rarity.color })
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
	local c = { r = r, z = b.zone.id, m = b.m }
	Game.setCarry(s, c)
	Game.notify(s.player, "grab", { r = r, m = b.m, z = b.zone.id, lucky = lucky, pity = pity,
		v = Config.creatureValue(r, b.zone.id, b.m) * Game.coinMult(s) })
end

local function tick()
	for _, s in Game.sessions do
		if s.carrying or os.clock() < s.eatenUntil then
			continue
		end
		local hrp = Game.root(s.player)
		if not hrp then
			continue
		end
		local pos = hrp.Position
		for i, b in live do
			if Vector2.new(pos.X - b.pos.X, pos.Z - b.pos.Z).Magnitude < Config.GRAB_RADIUS and math.abs(pos.Y - b.pos.Y) < 9 then
				table.remove(live, i)
				b.model:Destroy()
				grab(s, b)
				local zone = b.zone
				task.delay(rng:NextNumber(3, 6), function()
					if count(zone) < Config.BUBBLES_PER_ZONE then
						spawnBubble(zone)
					end
				end)
				break
			end
		end
	end
end

-- Golden Bubble / Starter Pack: straight into your hands (or your tank)
function Bubbles.give(s: Game.Session, r: string, zoneId: string?)
	local zone = Config.zoneForSpeed(s.profile.speed)
	local c = { r = r, z = zoneId or zone.id, m = Bubbles.rollMutation() }
	if s.carrying then
		Game.addToTank(s, c)
	else
		Game.setCarry(s, c)
		Game.notify(s.player, "grab", { r = c.r, m = c.m, z = c.z, gift = true, v = Config.creatureValue(c.r, c.z, c.m) * Game.coinMult(s) })
	end
end

function Bubbles.start()
	folder = Instance.new("Folder")
	folder.Name = "Bubbles"
	folder.Parent = Workspace
	for _, zone in Config.Zones do
		for _ = 1, Config.BUBBLES_PER_ZONE do
			spawnBubble(zone)
		end
	end
	task.spawn(function()
		while true do
			task.wait(0.1)
			tick()
		end
	end)
end

return Bubbles
