-- Core loop: +speed every second, tank income, collect pad, rides, slots,
-- rebirth, gates, the shark's bite consequences, and state sync.

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")

local Shared = game.ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Layout = require(Shared.Layout)
local Build = require(Shared.Build)
local Creatures = require(Shared.Creatures)
local Rides = require(Shared.Rides)
local Rig = require(Shared.Rig)
local Remotes = require(Shared.Remotes)
local NameTag = require(Shared.NameTag)
local Data = require(script.Parent.Data)
local World = require(script.Parent.World)

local Game = {}

export type Session = {
	player: Player,
	profile: Data.Profile,
	canSave: boolean,
	plot: World.Plot?,
	carrying: Data.Creature?,
	carryModel: Model?,
	trailModel: Model?, -- the net sack on your back with its catches
	rideModel: Model?,
	pending: number,
	lastPos: Vector3?,
	passes: { [string]: boolean },
	joinedAt: number,
	eatenUntil: number,
	fullWarned: number?,
	lastLost: any?,
	lastLostSpill: any?,
	wentOutAt: number?, -- when you last rode off the beach -- its spilled bubble (gone if Rescue is bought)
	dirty: boolean,
	inWater: boolean,
	leaderSpeed: IntValue?,
	leaderIncome: IntValue?,
	friendBoost: number, -- +coins from friends in this server (0..0.5)
	slow: boolean, -- Slow Mode on
	offline: number, -- welcome-back coins waiting to be claimed
	carryUntil: number?, -- os.clock() when the carried creature wriggles free
	carryWarned: boolean?,
	rings: { [number]: number }?, -- boost ring cooldowns
	trail: { { p: Vector3, t: number } }?, -- recent path (fastTick)
	portalAt: number?, -- last portal use
	gifts: number?, -- playtime gifts claimed this session
	bag: { Data.Creature }?, -- extra catches in your net (s.carrying is the one in your hands)
	stolen: boolean?, -- carrying a catch from water too deep for you: every shark you pass wants it
	awaySince: number?, -- lastSeen at join, until Game.welcomeBack pays the offline coins
	raidLoot: Data.Creature?, -- a creature you won in a raid, carried home in forced slow mode (anyone can bonk it loose)
}

Game.sessions = {} :: { [Player]: Session }
Game.frenzy = false -- set by Sharks while a hunt is on
Game.event = false -- set by Events during Megalodon Hour
Game.mini = nil :: string? -- the server event on now (Events: "golden" / "frenzy" / "rain")
Game.questList = nil :: ((Session) -> { any })? -- set by Quests
Game.onDawn = nil :: (() -> ())? -- set by Treasure (Sharks calls it every dawn)
-- set by Sharks: has this player used up their shelter on this island?
Game.islandExposed = nil :: ((Session, Layout.Island) -> boolean)?

local StateRemote = Remotes.get("State")
local NotifyRemote = Remotes.get("Notify")

----------------------------------------------------------------- helpers
local function root(player: Player): BasePart?
	local char = player.Character
	return char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
end
Game.root = root

local function humanoid(player: Player): Humanoid?
	local char = player.Character
	return char and char:FindFirstChildOfClass("Humanoid")
end

function Game.notify(player: Player, kind: string, data: { [string]: any }?)
	NotifyRemote:FireClient(player, kind, data or {})
	Game.track(player, kind, data or {})
end

-- listeners (Analytics, Quests): every player event passes here, plus
-- internal ones starting with "_" (join, leave, water, tut)
Game.trackers = {} :: { (Player, string, { [string]: any }) -> () }
function Game.track(player: Player, kind: string, data: { [string]: any })
	for _, fn in Game.trackers do
		task.spawn(fn, player, kind, data)
	end
end

function Game.notifyAll(kind: string, data: { [string]: any }?)
	NotifyRemote:FireAllClients(kind, data or {})
end

function Game.ownsRide(s: Session, id: string): boolean
	local ride = Config.ride(id)
	if not ride then
		return false
	end
	if ride.robux then
		return s.passes[ride.robux] == true
	end
	return s.profile.rides[id] == true
end

function Game.gain(s: Session): number
	local best = 1
	for _, ride in Config.Rides do
		if ride.gain and s.profile.rides[ride.id] then
			best = math.max(best, ride.gain)
		end
	end
	local mult = Config.Rebirth.mult ^ s.profile.rebirths * (Config.Worlds[s.profile.world] or Config.Worlds[1]).gainMult
	if s.passes.TwoXSpeed then
		mult *= 2
	end
	if s.profile.boostUntil > os.time() then
		mult *= 2
	end
	for _, ride in Config.Rides do
		if ride.robux and ride.mult and s.passes[ride.robux] then
			mult *= ride.mult
		end
	end
	return math.floor(best * mult + 0.5)
end

function Game.coinMult(s: Session): number
	local m = 1 + s.friendBoost
	if Game.event then
		m *= Config.Event.coins
	end
	if s.passes.TwoXCoins then
		m *= 2
	end
	if s.passes.VIP then
		m *= 1.1
	end
	return m
end

local function baseValue(c: Data.Creature): number
	return Config.creatureValue(c.r, c.z, c.m, c.s)
end

function Game.income(s: Session): number
	local total = 0
	for _, c in s.profile.creatures do
		if c.e then
			total += baseValue(c)
		end
	end
	return total * Game.coinMult(s)
end

function Game.activeCount(s: Session): number
	local n = 0
	for _, c in s.profile.creatures do
		if c.e then
			n += 1
		end
	end
	return n
end

function Game.maxSlots(s: Session): number
	return Config.Tank.maxSlots + (s.passes.BigTank and Config.Tank.passSlots or 0)
end

function Game.slotPrice(s: Session): number?
	local bought = s.profile.slots - Config.Tank.startSlots
	if s.profile.slots >= Config.Tank.maxSlots then
		return nil
	end
	return Config.Tank.slotPrices[bought + 1]
end

-- WalkSpeed from speed, capped while Slow Mode is on
function Game.walkSpeed(s: Session): number
	local v = Config.realSpeed(s.profile.speed)
	return (s.slow or s.raidLoot) and math.min(v, Config.SLOW_SPEED) or v
end

-- raid loot: you walk it home slowly, and it's marked so everyone can bonk it
function Game.setRaidLoot(s: Session, c: Data.Creature?)
	s.raidLoot = c
	local char = s.player.Character
	if char then
		char:SetAttribute("RaidLoot", c ~= nil or nil)
	end
	local hum = humanoid(s.player)
	if hum then
		hum.WalkSpeed = Game.walkSpeed(s)
	end
end

-- friends in this server boost your coins (social = more players)
function Game.updateFriendBoost(s: Session)
	local n = 0
	for other in Game.sessions do
		if other ~= s.player then
			local ok, friends = pcall(s.player.IsFriendsWith, s.player, other.UserId)
			if ok and friends then
				n += 1
			end
		end
	end
	local boost = math.min(n * Config.FriendBoost.per, Config.FriendBoost.max)
	if boost ~= s.friendBoost then
		s.friendBoost = boost
		if Game.refreshTank then
			Game.refreshTank(s)
		end
		s.dirty = true
	end
end

function Game.luck(s: Session): number
	local l = Config.Luck.base
	if s.passes.LuckyNet then
		l += Config.Luck.pass
	end
	if s.profile.luckUntil > os.time() then
		l += Config.Luck.potion
	end
	if Game.frenzy then
		l += Config.Shark.frenzyLuck -- the shark is out: rarer catches for the brave
	end
	if Game.event then
		l = math.min(l * Config.Event.luckMult, 0.85) -- Megalodon Hour: x3
	end
	return l
end

function Game.tankSlots(s: Session): number
	return s.profile.slots + (s.passes.BigTank and Config.Tank.passSlots or 0)
end

local function tankSlots(s: Session): number
	return s.profile.slots + (s.passes.BigTank and Config.Tank.passSlots or 0)
end

local function formatShort(n: number): string
	local units = { "", "K", "M", "B", "T", "Qa" }
	local i = 1
	while n >= 1000 and i < #units do
		n /= 1000
		i += 1
	end
	return (i == 1 and tostring(math.floor(n)) or (string.format("%.1f", n):gsub("%.0$", ""))) .. units[i]
end
Game.short = formatShort

----------------------------------------------------------------- state sync
-- worlds this player may enter (World n: unlockRebirths in the world before)
function Game.unlockedWorlds(s: Session): { [string]: boolean }
	local out = {}
	for i, w in Config.Worlds do
		local prev = Config.Worlds[i - 1]
		out[tostring(i)] = prev == nil or Data.worldRebirths(s.profile, prev.id) >= w.unlockRebirths
	end
	return out
end

function Game.push(s: Session)
	local p = s.profile
	-- everyone's client colors your wake from these (rebirth tier / VIP gold)
	s.player:SetAttribute("Rebirths", p.rebirths)
	s.player:SetAttribute("VIP", s.passes.VIP == true)
	local mult = Game.coinMult(s)
	local list = table.create(#p.creatures)
	for _, c in p.creatures do
		table.insert(list, { id = c.id, r = c.r, z = c.z, m = c.m, s = c.s, e = c.e == true, v = baseValue(c) * mult })
	end
	local rides = {}
	for _, ride in Config.Rides do
		if Game.ownsRide(s, ride.id) then
			rides[ride.id] = true
		end
	end
	local now = os.time()
	StateRemote:FireClient(s.player, {
		speed = p.speed,
		gain = Game.gain(s),
		coins = p.coins,
		pending = s.pending,
		income = Game.income(s),
		rides = rides,
		ride = p.ride,
		creatures = list,
		active = Game.activeCount(s),
		storage = tankSlots(s) + Config.Tank.maxDead,
		dead = Game.deadCount(s),
		maxDead = Config.Tank.maxDead,
		slots = tankSlots(s),
		friendBoost = s.friendBoost,
		slow = s.slow,
		slotPrice = Game.slotPrice(s),
		rebirths = p.rebirths,
		wr = p.wr,
		world = p.world,
		unlocked = Game.unlockedWorlds(s),
		tut = p.tut,
		shields = p.shields,
		carrying = s.carrying,
		bag = s.bag and #s.bag or 0,
		gifts = s.gifts or 0, -- playtime gifts claimed this session...
		session = os.clock() - s.joinedAt, -- ...and seconds played (client counts on from here)
		net = s.profile.net,
		netCap = Config.netCap(s.profile.net),
		freshLeft = s.carryUntil and math.max(0, s.carryUntil - os.clock()) or nil, -- seconds before it escapes
		passes = s.passes,
		boostLeft = math.max(0, p.boostUntil - now),
		luckLeft = math.max(0, p.luckUntil - now),
		playtime = p.playtime,
		starter = p.starter,
		starterNext = Config.StarterLadder[p.starterTier + 1], -- next pack to offer (nil = all bought)
		dealBought = p.dealBought,
		dailyDay = p.daily.day,
		quests = Game.questList and Game.questList(s) or nil,
		noodle = p.noodle, -- (Config.Noodles tier; the Golden Noodle pass is in `passes`)
		bonks = p.bonks,
		questsReset = 86400 - now % 86400, -- seconds to new quests (midnight UTC)
		dailyWait = math.max(0, p.daily.last + Config.DAILY_GAP_HOURS * 3600 - now),
		groupWait = math.max(0, p.groupClaim + Config.GroupChest.cooldownHours * 3600 - now),
		plot = s.plot and s.plot.index or 0,
		index = p.index,
		claimed = p.claimed,
		offline = s.offline,
	})
	s.dirty = false
end

----------------------------------------------------------------- rides on characters
function Game.attachRide(s: Session)
	if s.rideModel then
		s.rideModel:Destroy()
		s.rideModel = nil
	end
	local char = s.player.Character
	local hrp = root(s.player)
	local hum = humanoid(s.player)
	if not (char and hrp and hum) then
		return
	end
	local id = Game.ownsRide(s, s.profile.ride) and s.profile.ride or "Noodle"
	char:SetAttribute("Ride", id) -- clients pick the pose + handling from this
	local model = Rides.build(id)
	-- size the ride to the body (rides are modelled for the default R15 legs)
	local leg = Rig.legLength(Rig.joints(char), hrp)
	local k = leg and math.clamp(leg / Rig.REF_LEG, 0.8, 1.35) or 1
	char:SetAttribute("RideScale", k)
	if math.abs(k - 1) > 0.02 then
		model:ScaleTo(k)
	end
	local feet = hrp.CFrame * CFrame.new(0, -(hum.HipHeight + hrp.Size.Y / 2), 0)
	model:PivotTo(feet)
	Build.weldToRoot(model)
	local w = Instance.new("WeldConstraint")
	w.Part0 = hrp
	w.Part1 = model.PrimaryPart
	w.Parent = model.PrimaryPart
	model.Parent = char
	s.rideModel = model
	Game.setRideVisible(s, s.inWater)
end

function Game.setRideVisible(s: Session, visible: boolean)
	local m = s.rideModel
	if not m then
		return
	end
	for _, d in m:GetDescendants() do
		-- stud Textures/Decals draw even on an invisible part, so they hide too
		-- (otherwise the deck's studs float under you on land)
		if (d:IsA("BasePart") and d.Name ~= "Root") or d:IsA("Texture") or d:IsA("Decal") then
			if d:GetAttribute("BaseT") == nil then
				d:SetAttribute("BaseT", (d :: any).Transparency)
			end
			(d :: any).Transparency = visible and d:GetAttribute("BaseT") or 1
		elseif d:IsA("Fire") or d:IsA("Sparkles") then
			d.Enabled = visible
		end
	end
end

----------------------------------------------------------------- carrying
function Game.setCarry(s: Session, c: Data.Creature?)
	if s.carryModel then
		s.carryModel:Destroy()
		s.carryModel = nil
	end
	if c ~= s.carrying then
		-- a fresh catch only stays in your hands so long (not during the tutorial)
		s.carryUntil = (c and s.profile.tut >= 5) and os.clock() + Config.freshTime(c.z) or nil
		s.carryWarned = false
	end
	s.carrying = c
	local char = s.player.Character
	local head = char and char:FindFirstChild("Head") :: BasePart?
	if c and head then
		local m = Creatures.build(c.r, c.m, 0.85 * math.min(Config.sizeScale(c.s), 1.3), c.z)
		m:PivotTo(head.CFrame * CFrame.new(0, 2.6, 0))
		Build.weldToRoot(m)
		local w = Instance.new("WeldConstraint")
		w.Part0 = head
		w.Part1 = m.PrimaryPart
		w.Parent = m.PrimaryPart
		m.Name = "Carried"
		NameTag.attach(m.PrimaryPart :: BasePart, c, baseValue(c) * Game.coinMult(s), { height = 1.9, maxDist = 90, width = 3.4 })
		m.Parent = char
		s.carryModel = m
	end
	Game.updateTrail(s)
	s.dirty = true
end

-- THE HAUL, visible: what's in your net rides in a sack on your back. It
-- swells as it fills, the top few catches poke out of the opening, and it
-- looks like your net tier (Config.Nets: size, cloth, rim; the Mega Net
-- shines). Everyone can see who's loaded. (The catch in your hands rides
-- over your head as before.)
local SHOWN = 3
function Game.updateTrail(s: Session)
	if s.trailModel then
		s.trailModel:Destroy()
		s.trailModel = nil
	end
	local bag = s.bag
	local char = s.player.Character
	local torso = char and (char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso")) :: BasePart?
	if not (bag and #bag > 0 and char and torso) then
		return
	end
	local net = Config.Nets[math.clamp(s.profile.net, 1, #Config.Nets)]
	local fill = math.clamp(#bag / math.max(Config.netCap(s.profile.net) - 1, 1), 0, 1)
	local k = (net.size or 1) * (0.8 + 0.35 * fill)
	-- hung on the back, leaning a little away from it
	local at = torso.CFrame * CFrame.new(0, -0.05, torso.Size.Z / 2 + 0.55 * k) * CFrame.Angles(-0.12, 0, 0)
	local sack = Instance.new("Model")
	sack.Name = "Haul"
	local body = Build.ell(sack, Vector3.new(1.5, 1.6, 1.15) * k, at, net.cloth, { Name = "Sack", Material = Enum.Material.Fabric })
	-- the netting: darker cords wrapped round it
	for i, y in { -0.35, 0.05, 0.42 } do
		local w = (i == 2 and 1.0 or 0.92)
		Build.ell(sack, Vector3.new(1.52 * w, 0.09, 1.17 * w) * k, at * CFrame.new(0, y * k, 0), net.rim, { Name = "Cord", Material = Enum.Material.Fabric })
	end
	-- the rim round the opening, and a strap over your shoulder
	local top = at * CFrame.new(0, 0.72 * k, 0)
	Build.cyl(sack, 0.16, 1.05 * k, top, net.rim, { Name = "Rim", Material = net.shine and Enum.Material.Metal or Enum.Material.Fabric,
		Reflectance = net.shine and 0.25 or 0 })
	local strapFrom = top.Position
	local strapTo = (torso.CFrame * CFrame.new(-torso.Size.X * 0.3, torso.Size.Y * 0.45, -torso.Size.Z / 2 - 0.05)).Position
	local mid = (strapFrom + strapTo) / 2 + Vector3.new(0, 0.25, 0)
	Build.part(sack, Vector3.new(0.18, 0.1, (strapTo - strapFrom).Magnitude + 0.2), CFrame.lookAt(mid, strapTo), net.rim,
		{ Name = "Strap", Material = Enum.Material.Fabric })
	-- the catches poking out of the top, heads up
	local spots = { Vector3.new(-0.28, 0.82, 0.08), Vector3.new(0.26, 0.86, -0.04), Vector3.new(0, 0.95, -0.2) }
	for i = 1, math.min(#bag, SHOWN) do
		local c = bag[#bag - i + 1] -- (the newest on top)
		local m = Creatures.build(c.r, c.m, 0.42 * k, c.z)
		local p = spots[i] * k
		m:PivotTo(at * CFrame.new(p) * CFrame.Angles(math.pi / 2 - 0.35, (i - 2) * 0.6, (i - 2) * 0.25))
		Build.weldToRoot(m)
		local w = Instance.new("WeldConstraint")
		w.Part0 = body
		w.Part1 = m.PrimaryPart
		w.Parent = m.PrimaryPart
		m.Parent = sack
	end
	sack.PrimaryPart = body
	Build.ghost(sack)
	Build.weldToRoot(sack)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = torso
	weld.Part1 = body
	weld.Parent = body
	sack.Parent = char
	s.trailModel = sack
end

-- nets: room for another catch? (the one in your hands + the bag)
function Game.carryCount(s: Session): number
	return (s.carrying and 1 or 0) + (s.bag and #s.bag or 0)
end

function Game.handsFull(s: Session): boolean
	return Game.carryCount(s) >= Config.netCap(s.profile.net)
end

-- a new catch: into your hands, or into the net if your hands are full
function Game.takeCatch(s: Session, c: Data.Creature)
	if not s.carrying then
		Game.setCarry(s, c)
		return
	end
	s.bag = s.bag or {}
	table.insert(s.bag :: { Data.Creature }, c)
	Game.updateTrail(s)
	s.dirty = true
end

-- a pillar of light over your dock for a while (big catches: the server
-- sees where the brag came from)
function Game.beamDock(s: Session, color: Color3, seconds: number)
	local plot = s.plot
	if not plot then
		return
	end
	local old = plot.model:FindFirstChild("Beam")
	if old then
		old:Destroy()
	end
	local at = Layout.tankPos(plot.cf)
	local beam = Instance.new("Part")
	beam.Name = "Beam"
	beam.Anchored, beam.CanCollide, beam.CanQuery, beam.CanTouch, beam.CastShadow = true, false, false, false, false
	beam.Shape = Enum.PartType.Cylinder
	beam.Size = Vector3.new(160, 3, 3)
	beam.CFrame = CFrame.new(at + Vector3.new(0, 80, 0)) * CFrame.Angles(0, 0, math.pi / 2)
	beam.Material = Enum.Material.Neon
	beam.Color = color
	beam.Transparency = 0.45
	local light = Instance.new("PointLight")
	light.Color, light.Range, light.Brightness = color, 30, 3
	light.Parent = beam
	beam.Parent = plot.model
	task.delay(seconds, function()
		beam:Destroy()
	end)
end

-- drop everything you carry (shark bite, portal, reset)
function Game.dropAll(s: Session)
	s.bag = nil
	Game.setCarry(s, nil)
end

-- THE PAYOFF: a trip's haul pays cash at the dock right away, more per
-- creature the more you brought at once (Config.Haul)
function Game.payHaul(s: Session, haul: { Data.Creature })
	if #haul == 0 then
		return
	end
	local sum = 0
	for _, c in haul do
		sum += baseValue(c)
	end
	local mult = Config.haulMult(#haul) * (Game.mini == "frenzy" and 2 or 1) -- (Feeding Frenzy: x2)
	local coins = math.max(1, math.floor(sum * Game.coinMult(s) * Config.Haul.seconds * mult))
	s.profile.coins += coins
	s.dirty = true
	local plot = s.plot
	local at = plot and Layout.tankPos(plot.cf) or Vector3.zero
	Game.notify(s.player, "haul", { n = #haul, mult = mult, coins = coins, x = at.X, y = at.Y, z = at.Z })
end

-- set by Bubbles: a bitten player's haul floats free for anyone to grab
Game.spill = nil :: ((pos: Vector3, list: { Data.Creature }, by: Player?) -> { any })?

----------------------------------------------------------------- tank
-- Everything you catch goes in your tank. The Active ones (c.e) swim and
-- earn; the rest lie "dead" on the tank floor and earn nothing. A new catch
-- goes Active only if there's a free slot (nothing is swapped for you). At
-- most Config.Tank.maxDead dead ones: then you can't drop off a catch until
-- you sell some at the SELL hut. Equip / Unequip / Equip Best: Tank UI.

function Game.deadCount(s: Session): number
	local n = 0
	for _, c in s.profile.creatures do
		if not c.e then
			n += 1
		end
	end
	return n
end

function Game.sellValue(s: Session, c: Data.Creature): number
	return math.floor(baseValue(c) * Config.SELL_SECONDS * Game.coinMult(s))
end

local function findCreature(s: Session, id: any): Data.Creature?
	if typeof(id) ~= "number" then
		return nil
	end
	for _, c in s.profile.creatures do
		if c.id == id then
			return c
		end
	end
	return nil
end

-- the swimming showcase: Active creatures with their $/s (clients make them swim)
-- THE SHOWCASE: your best creature floats huge above your dock, spinning
-- slowly over a glowing ring, with your name; bigger as you rebirth (clients
-- spin + bob it: tag "Showcase", Water.luau). Rebuilt only when it changes.
local SHOWCASE_Y = 27
function Game.updateShowcase(s: Session)
	local plot = s.plot
	if not plot then
		return
	end
	local best, bestV = nil, -1
	for _, c in s.profile.creatures do
		local v = Config.creatureValue(c.r, c.z, c.m, c.s)
		if v > bestV then
			best, bestV = c, v
		end
	end
	local old = plot.model:FindFirstChild("Showcase")
	local key = best and ("%s|%s|%s|%s|%d"):format(best.r, best.z, tostring(best.m), tostring(best.s), math.min(s.profile.rebirths, 8)) or ""
	if old and old:GetAttribute("Key") == key then
		return
	end
	if old then
		old:Destroy()
	end
	if not best then
		return
	end
	local at = Layout.tankPos(plot.cf) + Vector3.new(0, SHOWCASE_Y, 0)
	local m = Instance.new("Model")
	m.Name = "Showcase"
	m:SetAttribute("Key", key)
	local scale = 3 + 0.3 * math.min(s.profile.rebirths, 8)
	local creature = Creatures.build(best.r, best.m, scale * math.min(Config.sizeScale(best.s), 1.3), best.z)
	creature:PivotTo(CFrame.new(at) * plot.cf.Rotation)
	creature.Parent = m
	local color = Config.rarity(best.r).color
	local ring = Build.cyl(m, 0.4, 7 + scale * 1.6, CFrame.new(at - Vector3.new(0, scale * 1.2 + 1.5, 0)), color, {
		Name = "Ring", Material = Enum.Material.Neon, Transparency = 0.35, CanCollide = false, CanQuery = false, CastShadow = false })
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = 16
	light.Brightness = 1.5
	light.Parent = ring
	NameTag.attach(ring, best, nil, { height = -2.2, maxDist = 220, width = 9 })
	m.PrimaryPart = creature.PrimaryPart
	m:SetAttribute("Owner", s.player.DisplayName)
	Build.ghost(m)
	CollectionService:AddTag(m, "Showcase")
	m.Parent = plot.model
end

function Game.refreshTank(s: Session)
	local plot = s.plot
	if not plot then
		return
	end
	Game.updateShowcase(s)
	plot.slots:ClearAllChildren()
	local mult = Game.coinMult(s)
	local base = CFrame.new(Layout.tankPos(plot.cf))
	for _, c in s.profile.creatures do
		if c.e then
			local m = Creatures.build(c.r, c.m, 0.72 * math.min(Config.sizeScale(c.s), 1.35), c.z)
			m:SetAttribute("Seed", (c.id or 1) * 7.7)
			-- what the hover card shows (TankView)
			m:SetAttribute("R", c.r)
			m:SetAttribute("Z", c.z)
			m:SetAttribute("M", c.m)
			m:SetAttribute("S", c.s or 1)
			m:SetAttribute("PerSecond", baseValue(c) * mult)
			m:PivotTo(base + Vector3.new(0, 5, 0))
			-- $/s always shows, through the glass; name + weight on hover
			NameTag.attach(m.PrimaryPart :: BasePart, c, baseValue(c) * mult, { height = 1.5, maxDist = 55, width = 2.6, moneyOnly = true, top = true })
			m.Parent = plot.slots
		end
	end
	-- the unequipped ones lie on their side on the floor, grey and still
	local box = plot.model:FindFirstChild("TankInterior", true) :: BasePart?
	local n = 0
	for _, c in s.profile.creatures do
		if not c.e and box then
			n += 1
			local m = Creatures.build(c.r, c.m, 0.72 * math.min(Config.sizeScale(c.s), 1.35), c.z)
			m:SetAttribute("Dead", true)
			m:SetAttribute("R", c.r)
			m:SetAttribute("Z", c.z)
			m:SetAttribute("M", c.m)
			m:SetAttribute("S", c.s or 1)
			m:SetAttribute("PerSecond", baseValue(c) * mult)
			for _, d in m:GetDescendants() do
				if d:IsA("BasePart") then
					d.Color = d.Color:Lerp(Color3.fromRGB(150, 150, 155), 0.45)
				end
			end
			local half = box.Size / 2
			local col, row = (n - 1) % 5, (n - 1) // 5
			local x = -half.X + 1.2 + col * (2 * half.X - 2.4) / 4
			local z = (row == 0 and -0.35 or 0.35) * half.Z
			local _, size = m:GetBoundingBox()
			local y = -half.Y + size.X / 2 + 0.05
			m:PivotTo(box.CFrame * CFrame.new(x, y, z) * CFrame.Angles(0, (c.id or n) * 1.3, math.pi / 2))
			m.Parent = plot.slots
		end
	end
	Game.updateTankSign(s)
end

-- the sign over the tank: what it earns now, and per day while you're away
function Game.updateTankSign(s: Session)
	local plot = s.plot
	if not plot then
		return
	end
	local inc = Game.income(s)
	plot.tankIncome.Text = ("$%s/s  ·  %d/%d Active"):format(Config.formatRate(inc), Game.activeCount(s), tankSlots(s))
	plot.tankOffline.Text = ("$%s / day offline"):format(formatShort(Config.offlinePerDay(inc)))
end

-- a new catch arrives at the dock
-- quiet: no deposit moment (raid loot: the spin shows it)
function Game.addCreature(s: Session, c: Data.Creature, quiet: boolean?)
	local p = s.profile
	c.id = p.nextId
	p.nextId += 1
	local value = baseValue(c)
	local mult = Game.coinMult(s)
	local info: { [string]: any } = { r = c.r, m = c.m, z = c.z, s = c.s, v = value * mult }
	c.e = Game.activeCount(s) < tankSlots(s)
	if not c.e then
		-- tank full: a better catch swaps in for the weakest swimmer (so a
		-- new Mythic never sits unequipped where Sell All could take it)
		local weakest, wv = nil, math.huge
		for _, o in p.creatures do
			if o.e and baseValue(o) < wv then
				weakest, wv = o, baseValue(o)
			end
		end
		if weakest and value > wv then
			weakest.e = false
			c.e = true
		end
	end
	info.active = c.e
	table.insert(p.creatures, c)
	if not quiet then
		Game.notify(s.player, "deposit", info)
	end
	Game.refreshTank(s)
	s.dirty = true
end

-- Equip Best: the highest earners become Active
function Game.equipBest(s: Session)
	local list = table.clone(s.profile.creatures)
	table.sort(list, function(a, b)
		return baseValue(a) > baseValue(b)
	end)
	local slots = tankSlots(s)
	for i, c in list do
		c.e = i <= slots
	end
	Game.refreshTank(s)
	s.dirty = true
end

----------------------------------------------------------------- index
-- first time you hold a creature of this rarity from this zone
function Game.discover(s: Session, c: Data.Creature)
	local key = Config.indexKey(c.z, c.r)
	if not s.profile.index[key] then
		s.profile.index[key] = true
		Game.notify(s.player, "discover", { r = c.r, z = c.z })
		s.dirty = true
	end
end

local function claimIndex(s: Session, key: string): (number, number)
	local p = s.profile
	if not p.index[key] or p.claimed[key] then
		return 0, 0
	end
	local zoneId, rarityId = key:match("^(%w+):(%w+)$")
	if not zoneId then
		return 0, 0
	end
	p.claimed[key] = true
	local coins, speed = Config.indexReward(zoneId, rarityId)
	p.coins += coins
	p.speed += speed
	return coins, speed
end

----------------------------------------------------------------- shark bites
function Game.huntable(s: Session): boolean
	local hrp = root(s.player)
	local hum = humanoid(s.player)
	if not hrp or not hum or hum.Health <= 0 then
		return false
	end
	if os.clock() < s.eatenUntil then
		return false
	end
	if s.profile.tut < 5 and os.clock() - s.joinedAt < Config.Shark.newPlayerGrace then
		return false
	end
	local pos = hrp.Position
	if not Layout.inWater(pos) then
		return false -- the beach is home: always safe
	end
	-- islands shelter you for a while each hunt (Sharks keeps the timers)
	local island = Layout.islandAt(pos, 0.5)
	if island then
		return Game.islandExposed ~= nil and Game.islandExposed(s, island)
	end
	return true
end

-- returns "shield" or "eaten"
function Game.bite(s: Session, sharkPos: Vector3): string
	local hrp = root(s.player)
	if not hrp then
		return "none"
	end
	if s.profile.shields > 0 and s.carrying then -- (only spent when there's a catch to save)
		s.profile.shields -= 1
		s.eatenUntil = os.clock() + 2.5
		Game.notify(s.player, "shield", { from = sharkPos })
		s.dirty = true
		return "shield"
	end
	s.lastLost, s.lastLostSpill = nil, nil -- (only this bite's loss can be rescued)
	if s.carrying then
		Game.notify(s.player, "lost", { r = s.carrying.r, m = s.carrying.m, z = s.carrying.z, s = s.carrying.s, extra = s.bag and #s.bag or 0 })
		s.lastLost = s.carrying -- the 9 R$ "Save Your Creature" offer can return it
		-- the whole haul spills into the water where you were bitten
		local list = { s.carrying :: Data.Creature }
		for _, c in s.bag or {} do
			table.insert(list, c)
		end
		Game.dropAll(s)
		if Game.spill then
			-- (the one in your hands is first: Rescue takes it back out of the water)
			s.lastLostSpill = Game.spill(hrp.Position, list, s.player)[1]
		end
	end
	s.eatenUntil = os.clock() + Config.Shark.eatenTime + 2.5
	hrp.Anchored = true
	-- wash up once the victim's cutscene has faded to black (+ a little for ping)
	task.delay(Config.Shark.eatenTime + 0.35, function()
		local h = root(s.player)
		if h then
			local ox = Config.originX(Config.worldAt(h.Position)) -- (wash up in your own world)
			local x = math.clamp(h.Position.X, ox - Config.LANE_WIDTH / 2 + 10, ox + Config.LANE_WIDTH / 2 - 10)
			h.Anchored = false
			h.Parent:PivotTo(CFrame.new(x, 14, Config.SHORE_Z - 4) * CFrame.Angles(0, math.pi, 0))
			local lost = s.lastLost
			Game.notify(s.player, "spat", { lost = lost and Config.fullName(lost.z, lost.r, lost.m, lost.s) or nil })
		end
	end)
	return "eaten"
end

----------------------------------------------------------------- actions
local actions: { [string]: (Session, any, any?) -> () } = {} -- (the remote only ever passes one argument)

-- other server modules add their own actions (Rewards: daily, group chest)
function Game.action(name: string, fn: (Session, any) -> ())
	actions[name] = fn
end

actions.buyRide = function(s, id)
	local ride = Config.ride(id)
	if not ride or ride.robux or s.profile.rides[id] then
		return
	end
	-- the ladder: you buy the next ride in line
	local prev = Config.Rides[ride.order - 1]
	if prev and not prev.robux and not s.profile.rides[prev.id] then
		return
	end
	if s.profile.coins < ride.price then
		return
	end
	-- rides are bought at the Ride Shop
	local hrp = root(s.player)
	if not (hrp and Layout.atRideShop(hrp.Position)) then
		Game.notify(s.player, "rideShop", {})
		return
	end
	s.profile.coins -= ride.price
	s.profile.rides[id] = true
	-- auto-ride the new one unless they're showing off a Robux ride
	local cur = Config.ride(s.profile.ride)
	if not (cur and cur.robux and Game.ownsRide(s, cur.id)) then
		s.profile.ride = id
		Game.attachRide(s)
	end
	Game.notify(s.player, "ride", { id = id, gain = Game.gain(s), price = ride.price })
	s.dirty = true
end

actions.equipRide = function(s, id)
	if typeof(id) == "string" and Game.ownsRide(s, id) then
		s.profile.ride = id
		Game.attachRide(s)
		s.dirty = true
	end
end

actions.equip = function(s, id)
	local c = findCreature(s, id)
	if c and not c.e and Game.activeCount(s) < tankSlots(s) then
		c.e = true
		Game.refreshTank(s)
		s.dirty = true
	end
end

actions.unequip = function(s, id)
	local c = findCreature(s, id)
	if c and c.e and Game.deadCount(s) >= Config.Tank.maxDead then
		Game.notify(s.player, "tankFull", { max = Config.Tank.maxDead })
	elseif c and c.e then
		c.e = false
		Game.refreshTank(s)
		s.dirty = true
	end
end

-- sell dead (unequipped) catches at the SELL hut
local function sell(s: Session, pick: (Data.Creature) -> boolean)
	local hrp = root(s.player)
	if not (hrp and Layout.atHut("Sell", hrp.Position)) then
		return
	end
	local total, count = 0, 0
	local keep = {}
	for _, c in s.profile.creatures do
		if not c.e and pick(c) then
			total += Game.sellValue(s, c)
			count += 1
		else
			table.insert(keep, c)
		end
	end
	if count == 0 then
		return
	end
	s.profile.creatures = keep
	s.profile.coins += total
	Game.notify(s.player, "sold", { coins = total, count = count })
	Game.refreshTank(s)
	s.dirty = true
end

actions.sell = function(s, id)
	sell(s, function(c)
		return c.id == id
	end)
end

-- Sell All leaves Epics and up alone (those you sell one by one, on purpose)
actions.sellAll = function(s)
	sell(s, function(c)
		return Config.rarity(c.r).index < Config.rarity("Epic").index
	end)
end

actions.equipBest = function(s)
	Game.equipBest(s)
end

actions.slowMode = function(s, on)
	s.slow = on == true
	local hum = humanoid(s.player)
	if hum then
		hum.WalkSpeed = Game.walkSpeed(s)
	end
	s.dirty = true
end

actions.code = function(s, text)
	if typeof(text) ~= "string" or #text > 30 then
		return
	end
	local key = text:upper():gsub("%s", "")
	local reward = Config.Codes[key]
	if not reward then
		Game.notify(s.player, "code", { ok = false, text = "That code doesn't exist" })
		return
	end
	if s.profile.codes[key] then
		Game.notify(s.player, "code", { ok = false, text = "You already used that code" })
		return
	end
	s.profile.codes[key] = true
	s.profile.coins += reward.coins or 0
	s.profile.speed += reward.speed or 0
	s.profile.shields += reward.shields or 0
	Game.notify(s.player, "code", { ok = true, coins = reward.coins, speed = reward.speed, shields = reward.shields })
	s.dirty = true
end

actions.buyNet = function(s)
	local nextTier = Config.Nets[s.profile.net + 1]
	if nextTier and s.profile.coins >= nextTier.price then
		s.profile.coins -= nextTier.price
		s.profile.net += 1
		Game.notify(s.player, "net", { name = nextTier.name, cap = nextTier.cap })
		Game.track(s.player, "net", { tier = s.profile.net, price = nextTier.price })
		s.dirty = true
	end
end

-- the next Noodle Bonk noodle (coins; the Golden Noodle is a game pass)
actions.buyNoodle = function(s)
	local nextTier = Config.Noodles[(s.profile.noodle or 1) + 1]
	if nextTier and not nextTier.pass and s.profile.coins >= nextTier.price then
		s.profile.coins -= nextTier.price
		s.profile.noodle += 1
		Game.notify(s.player, "noodle", { name = nextTier.name, reach = nextTier.reach, tier = s.profile.noodle, price = nextTier.price })
		s.dirty = true
	end
end

actions.buySlot = function(s)
	local price = Game.slotPrice(s)
	if price and s.profile.coins >= price then
		s.profile.coins -= price
		s.profile.slots += 1
		Game.refreshTank(s)
		Game.notify(s.player, "slot", { slots = tankSlots(s), price = price })
		s.dirty = true
	end
end

-- boost ring: the client saw you ride through ring i; pay a few seconds of
-- speed gain if you're really near it (once per ring every 25 s)
-- your recent server-side path really passes through ring p
local function rodeThrough(s: Session, p: Vector3): boolean
	local trail = s.trail or {}
	for k = 2, #trail do
		if Layout.segmentDist(p, trail[k - 1].p, trail[k].p) < Layout.RING_RADIUS + 4 then
			return true
		end
	end
	return false
end

actions.ring = function(s, i, retried)
	local p = typeof(i) == "number" and Layout.Rings[i]
	local hrp = root(s.player)
	if not (p and hrp) then
		return
	end
	if not rodeThrough(s, p) then
		-- the client can tell us before your position catches up here: look again
		if not retried then
			task.delay(0.4, function()
				if Game.sessions[s.player] == s then
					actions.ring(s, i, true)
				end
			end)
		end
		return
	end
	s.rings = s.rings or {}
	local rings = s.rings :: { [number]: number }
	if os.clock() - (rings[i] or -100) < Layout.RING_RESPAWN - 2 then
		return -- (it's gone for you until it comes back)
	end
	rings[i] = os.clock()
	local amount = math.max(1, math.floor(Game.gain(s) * 10))
	s.profile.speed += amount
	s.dirty = true
	Game.notify(s.player, "ring", { amount = amount, i = i })
end

actions.rebirth = function(s)
	local p = s.profile
	if p.speed < Config.rebirthSpeed(p.wr, p.world) then
		return
	end
	-- (evolving takes you home: not a way to beat the sharks home with a catch)
	if Game.carryCount(s) > 0 then
		Game.notify(s.player, "announce", { text = "Bring your catch home first" })
		return
	end
	p.rebirths += 1
	p.wr += 1
	p.speed = 0
	p.coins = 0
	p.rides = { Noodle = true }
	local cur = Config.ride(p.ride)
	if not (cur and cur.robux) then
		p.ride = "Noodle"
	end
	s.pending = 0
	Game.attachRide(s)
	local hrp = root(s.player)
	if hrp and s.plot then
		hrp.Parent:PivotTo(Layout.spawnCFrame(s.plot.cf))
	end
	-- evolving opens the next deep biome at the end of the sea
	local biome, biomeId
	for _, zone in Config.worldZones(p.world) do
		if zone.evolve == p.rebirths then
			biome, biomeId = zone.name, zone.id
		end
	end
	Game.notify(s.player, "rebirth", { rebirths = p.rebirths, biome = biome, zone = biomeId })
	s.dirty = true
end

actions.claimIndex = function(s, key)
	if typeof(key) ~= "string" then
		return
	end
	local coins, speed = claimIndex(s, key)
	if coins > 0 then
		Game.notify(s.player, "indexClaim", { coins = coins, speed = speed })
		s.dirty = true
	end
end

actions.claimIndexAll = function(s)
	local coins, speed = 0, 0
	for key in s.profile.index do
		local c, sp = claimIndex(s, key)
		coins += c
		speed += sp
	end
	if coins > 0 then
		Game.notify(s.player, "indexClaim", { coins = coins, speed = speed })
		s.dirty = true
	end
end

actions.claimOffline = function(s)
	if s.offline > 0 then
		s.profile.coins += s.offline
		Game.notify(s.player, "collect", { amount = s.offline })
		s.offline = 0
		s.dirty = true
	end
end

actions.tut = function(s, step)
	if typeof(step) == "number" and step > s.profile.tut and step <= 5 then
		s.profile.tut = math.floor(step)
		s.dirty = true
		Game.track(s.player, "_tut", { step = s.profile.tut })
	end
end

Remotes.get("Action").OnServerEvent:Connect(function(player, kind, arg)
	local s = Game.sessions[player]
	local fn = typeof(kind) == "string" and actions[kind]
	if s and fn then
		fn(s, arg)
	end
end)

----------------------------------------------------------------- join / leave
-- your dock number is the same in every world (reserved in all of them);
-- the sign + tank show only in the world you're in
local function dressPlot(s: Session)
	local plot = s.plot
	if plot then
		plot.signLabel.Text = s.player.DisplayName .. "'s Dock"
		plot.viewPrompt.ObjectText = s.player.DisplayName .. "'s Tank"
		plot.model:SetAttribute("Owner", s.player.UserId)
		plot.model:SetAttribute("LockUntil", s.profile.lockUntil) -- (Tank Lock: no raid prompt)
	end
end

local function emptyPlot(plot: World.Plot)
	local show = plot.model:FindFirstChild("Showcase")
	if show then
		show:Destroy()
	end
	plot.signLabel.Text = "Empty Dock"
	plot.viewPrompt.ObjectText = "Empty Dock"
	plot.padLabel.Text = "$0"
	plot.tankIncome.Text = ""
	plot.tankOffline.Text = ""
	plot.slots:ClearAllChildren()
	plot.model:SetAttribute("Owner", nil)
	plot.model:SetAttribute("LockUntil", nil)
	plot.model:SetAttribute("SafeUntil", nil) -- (the next owner starts fresh)
	plot.model:SetAttribute("RaidEnds", nil)
	plot.model:SetAttribute("Guarded", nil)
	local guard = plot.model:FindFirstChild("Guard") :: BasePart?
	if guard then
		guard.Transparency = 1
	end
end

local function claimPlot(s: Session)
	for i, plot in World.Plots do
		if not plot.owner then
			for _, list in World.WorldPlots do
				list[i].owner = s.player
			end
			s.plot = World.WorldPlots[s.profile.world][i]
			dressPlot(s)
			return
		end
	end
end

-- move a player to world w right here (the plaza portal): bank the pad,
-- drop what you carry, swap the world's progress in, dock + respawn there
function Game.switchWorld(s: Session, w: number)
	local p = s.profile
	if p.world == w or not Config.Worlds[w] then
		return
	end
	p.coins += s.pending
	s.pending = 0
	Game.dropAll(s)
	local index = s.plot and s.plot.index
	if s.plot then
		emptyPlot(s.plot)
	end
	Data.enterWorld(p, w)
	s.plot = index and World.WorldPlots[w][index] or nil
	dressPlot(s)
	Game.attachRide(s)
	Game.refreshTank(s)
	local hrp = root(s.player)
	if hrp and s.plot then
		local to = Layout.spawnCFrame(s.plot.cf)
		-- (with streaming on, load the far side before landing there)
		pcall(s.player.RequestStreamAroundAsync, s.player, to.Position, 6)
		hrp.Parent:PivotTo(to)
		hrp.AssemblyLinearVelocity = Vector3.zero
	end
	s.dirty = true
	Game.push(s)
	Game.track(s.player, "world", { world = w })
	if Game.onWorld then
		Game.onWorld(s)
	end
end

local function onCharacter(s: Session, char: Model)
	local hum = char:WaitForChild("Humanoid", 10) :: Humanoid?
	local hrp = char:WaitForChild("HumanoidRootPart", 10) :: BasePart?
	if not hum or not hrp then
		return
	end
	hum.WalkSpeed = Game.walkSpeed(s)
	hum.JumpPower = 50
	-- dying (any way) drops what you carry: a reset is never a free ride home
	hum.Died:Connect(function()
		Game.dropAll(s)
	end)
	if s.plot then
		task.defer(function()
			char:PivotTo(Layout.spawnCFrame(s.plot.cf))
		end)
	end
	s.inWater = false
	task.defer(Game.attachRide, s)
end

function Game.join(player: Player)
	local profile, canSave = Data.load(player.UserId)
	if not player.Parent then
		if canSave then
			Data.save(player.UserId, profile, true) -- (gone during the load: free the lock)
		end
		return
	end
	if not Config.Worlds[profile.world] then
		Data.enterWorld(profile, 1) -- (Candy Bay is now the deep end of the one sea)
	end
	-- one sea: your evolves are your rebirths, wherever you made them
	profile.wr = math.max(profile.wr, profile.rebirths)
	local s: Session = {
		player = player,
		profile = profile,
		canSave = canSave,
		plot = nil,
		carrying = nil,
		carryModel = nil,
		rideModel = nil,
		pending = 0,
		passes = {},
		joinedAt = os.clock(),
		eatenUntil = 0,
		dirty = true,
		inWater = false,
		offline = 0,
		friendBoost = 0,
		slow = false,
	}
	Game.sessions[player] = s
	s.awaySince = profile.lastSeen -- (Game.welcomeBack, once their passes are known)
	claimPlot(s)

	-- player list columns, like the big simulators: Money/s and Speed
	local ls = Instance.new("Folder")
	ls.Name = "leaderstats"
	local inc = Instance.new("IntValue")
	inc.Name = "Money/s"
	inc.Value = math.floor(Game.income(s))
	inc.Parent = ls
	local sp = Instance.new("IntValue")
	sp.Name = "Speed"
	sp.Value = math.floor(profile.speed)
	sp.Parent = ls
	ls.Parent = player
	s.leaderSpeed, s.leaderIncome = sp, inc
	-- friend boosts for everyone (a friend joining changes others' boost too)
	for _, other in Game.sessions do
		task.spawn(Game.updateFriendBoost, other)
	end

	player.CharacterAdded:Connect(function(char)
		onCharacter(s, char)
	end)
	player.CharacterAppearanceLoaded:Connect(function()
		Game.attachRide(s) -- body size may have changed: refit the ride
	end)
	if player.Character then
		task.spawn(onCharacter, s, player.Character)
	end
	Game.refreshTank(s)
	Game.push(s)
	Game.track(player, "_join", { new = profile.tut == 0 and #profile.creatures == 0 })
	if Game.onJoin then
		Game.onJoin(s)
	end
end

-- welcome back: the tank kept earning (slower) while you were away. Runs
-- once the player's passes are loaded (Market), so 2x Coins / VIP count.
function Game.welcomeBack(s: Session)
	local last = s.awaySince or 0
	s.awaySince = nil
	if Game.sessions[s.player] ~= s then
		return
	end
	local away = last > 0 and os.time() - last or 0
	if away >= Config.Offline.minSeconds then
		local secs = math.min(away, Config.Offline.maxHours * 3600)
		s.offline = math.floor(Game.income(s) * secs * Config.Offline.rate)
		if s.offline > 0 then
			Game.notify(s.player, "offline", { amount = s.offline, seconds = secs })
		end
	end
end

-- saves still running (leaves, autosaves): shutdown waits for them
local inflight = 0
local function trackedSave(userId: number, profile: any, release: boolean?, stillOwned: (() -> boolean)?)
	inflight += 1
	local ok = pcall(Data.save, userId, profile, release, stillOwned)
	inflight -= 1
	return ok
end

function Game.leave(player: Player)
	local s = Game.sessions[player]
	if not s then
		return
	end
	Game.sessions[player] = nil
	Game.track(player, "_leave", { minutes = (os.clock() - s.joinedAt) / 60, rebirths = s.profile.rebirths })
	s.profile.coins += s.pending + s.offline
	-- raid loot still being walked home: it's yours, into your tank (never
	-- deleted from the game by leaving mid-walk)
	local loot = s.raidLoot
	if loot then
		loot.id = s.profile.nextId
		s.profile.nextId += 1
		loot.e = false
		table.insert(s.profile.creatures, loot)
		s.raidLoot = nil
	end
	if s.plot then
		emptyPlot(s.plot)
		for _, list in World.WorldPlots do
			list[s.plot.index].owner = nil
		end
	end
	if s.canSave then
		trackedSave(player.UserId, s.profile, true)
	end
	for _, other in Game.sessions do
		task.spawn(Game.updateFriendBoost, other)
	end
end

-- wipe a player's progress back to a brand-new save (dev command /reset);
-- purchase receipts are kept so a product is never granted twice
function Game.resetProfile(s: Session)
	local receipts = s.profile.receipts
	local fresh = Data.default()
	table.clear(s.profile)
	for k, v in fresh do
		(s.profile :: any)[k] = v
	end
	s.profile.receipts = receipts
	-- the fresh save starts in Shark Beach: move the dock there
	if s.plot then
		emptyPlot(s.plot)
		s.plot = World.WorldPlots[1][s.plot.index]
		dressPlot(s)
	end
	s.pending, s.offline = 0, 0
	Game.dropAll(s)
	if s.canSave then
		Data.save(s.player.UserId, s.profile)
	end
	s.dirty = true
	Game.refreshTank(s)
	Game.push(s)
	s.player:LoadCharacter() -- respawn at the dock on the starter ride
	Game.notify(s.player, "announce", { text = "All progress reset" })
end

function Game.saveAll()
	for player, s in Game.sessions do
		if s.canSave then
			-- (stops if they leave mid-save, so it can't re-lock a released save)
			task.spawn(trackedSave, player.UserId, s.profile, false, function()
				return Game.sessions[player] == s
			end)
		end
	end
end

----------------------------------------------------------------- loops

-- every second: +speed, +coins into the tank pool
local function secondTick()
	for _, s in Game.sessions do
		local p = s.profile
		local before = p.speed
		p.speed += Game.gain(s)
		p.bestSpeed = math.max(p.bestSpeed, p.speed)
		p.playtime += 1
		local hum = humanoid(s.player)
		if hum then
			hum.WalkSpeed = Game.walkSpeed(s)
		end
		-- zone unlock moments
		for _, zone in Config.worldZones(p.world) do
			if zone.gate > 0 and before < zone.gate and p.speed >= zone.gate and (zone.evolve or 0) <= p.rebirths then
				Game.notify(s.player, "unlock", { zone = zone.id })
			end
		end
		local inc = Game.income(s)
		if inc > 0 then
			if s.passes.AutoCollect then
				p.coins += inc
			else
				s.pending += inc
			end
		end
		if s.plot then
			s.plot.padLabel.Text = "$" .. formatShort(s.pending)
			Game.updateTankSign(s)
		end
		if s.leaderSpeed then
			s.leaderSpeed.Value = math.floor(p.speed)
		end
		if s.leaderIncome then
			s.leaderIncome.Value = math.floor(inc)
		end
		Game.push(s)
	end
end

-- 8 Hz: water state, ride visibility, collect pad, deposit, gate enforcement
local function fastTick()
	for _, s in Game.sessions do
		local hrp = root(s.player)
		if not hrp then
			continue
		end
		local pos = hrp.Position
		local prev = s.lastPos
		s.lastPos = pos
		-- the last ~1.5 s of your path (rings check you really rode through)
		local trail = s.trail or {}
		s.trail = trail
		table.insert(trail, { p = pos, t = os.clock() })
		while #trail > 0 and os.clock() - trail[1].t > 1.5 do
			table.remove(trail, 1)
		end
		local from = (prev and (prev - pos).Magnitude < 120) and prev or pos
		local wet = Layout.inWater(pos) and not Layout.islandAt(pos, 0)
		if wet ~= s.inWater then
			s.inWater = wet
			if wet then
				s.wentOutAt = os.clock() -- (the escape reward needs a real trip out)
			end
			Game.setRideVisible(s, wet)
			Game.track(s.player, "_water", { wet = wet })
		end
		local plot = s.plot
		if plot then
			local pad = Layout.padPos(plot.cf)
			local function collect()
				local amount = s.pending
				s.profile.coins += amount
				s.pending = 0
				plot.padLabel.Text = "$0"
				Game.notify(s.player, "collect", { amount = amount })
				s.dirty = true
			end
			if s.pending > 0 and Layout.segmentDist(pad, from, pos) < Config.COLLECT_RADIUS and math.abs(pos.Y - pad.Y) < 8 then
				collect()
			end
			if s.carrying then
				local tank = Layout.tankPos(plot.cf)
				if Layout.segmentDist(tank, from, pos) < Config.DEPOSIT_RADIUS then
					local function full(): boolean
						return Game.activeCount(s) >= tankSlots(s) and Game.deadCount(s) >= Config.Tank.maxDead
					end
					if not full() then
						-- unload the net first, then what's in your hands
						local bag = s.bag or {}
						local haul: { Data.Creature } = {}
						while #bag > 0 and not full() do
							local c = table.remove(bag, 1) :: Data.Creature
							table.insert(haul, c)
							Game.addCreature(s, { r = c.r, z = c.z, m = c.m, s = c.s })
							Game.track(s.player, "dockDeposit", {})
						end
						if not full() then
							local c = s.carrying :: Data.Creature
							table.insert(haul, c)
							Game.setCarry(s, nil)
							Game.addCreature(s, { r = c.r, z = c.z, m = c.m, s = c.s })
							Game.track(s.player, "dockDeposit", {})
						end
						Game.updateTrail(s)
						Game.payHaul(s, haul)
						if s.pending >= 1 then
							collect() -- (dropping off at the tank collects the pad too: one stop)
						end
						s.dirty = true
					elseif os.clock() - (s.fullWarned or 0) > 4 then
						s.fullWarned = os.clock()
						Game.notify(s.player, "tankFull", { max = Config.Tank.maxDead })
					end
				end
			end
		end
		-- raid loot: done once it's out of your hands and net
		local loot = s.raidLoot
		if loot and s.carrying ~= loot and not (s.bag and table.find(s.bag, loot)) then
			Game.setRaidLoot(s, nil)
		end
		-- a carried creature doesn't wait forever: bring it home in time
		local c = s.carrying
		if c and s.carryUntil then
			if not wet and Game.activeCount(s) >= tankSlots(s) and Game.deadCount(s) >= Config.Tank.maxDead then
				s.carryUntil += 0.125 -- tank full: it waits while you sort that out on the sand
			end
			local left = s.carryUntil - os.clock()
			if left <= Config.Shark.freshWarn and not s.carryWarned then
				s.carryWarned = true
				Game.notify(s.player, "escaping", { left = math.max(0, left), r = c.r, m = c.m, z = c.z, s = c.s })
			end
			if left <= 0 and not hrp.Anchored then
				Game.notify(s.player, "escaped", { r = c.r, m = c.m, z = c.z, s = c.s })
				-- the next one from the net takes its place (with a fresh timer)
				local nextUp = s.bag and table.remove(s.bag, 1) or nil
				Game.setCarry(s, nextUp)
			end
		end
		if s.dirty then
			Game.push(s)
		end
	end
end

function Game.start()
	Players.PlayerAdded:Connect(Game.join)
	Players.PlayerRemoving:Connect(Game.leave)
	for _, p in Players:GetPlayers() do
		task.spawn(Game.join, p)
	end
	task.spawn(function()
		while true do
			task.wait(1)
			secondTick()
		end
	end)
	task.spawn(function()
		while true do
			task.wait(0.125)
			fastTick()
		end
	end)
	task.spawn(function()
		while true do
			task.wait(120)
			Game.saveAll()
		end
	end)
	game:BindToClose(function()
		-- everyone still here saves at once (not one by one), then wait for
		-- those and any leave saves already running (Roblox gives ~30 s)
		for player, s in Game.sessions do
			s.profile.coins += s.pending + s.offline
			s.pending, s.offline = 0, 0
			local loot = s.raidLoot
			if loot then
				loot.id = s.profile.nextId
				s.profile.nextId += 1
				loot.e = false
				table.insert(s.profile.creatures, loot)
				s.raidLoot = nil
			end
			if s.canSave then
				task.spawn(trackedSave, player.UserId, s.profile, true)
			end
		end
		task.wait()
		local deadline = os.clock() + 25
		while inflight > 0 and os.clock() < deadline do
			task.wait(0.2)
		end
	end)
end

Game.onJoin = nil :: ((Session) -> ())?
Game.onWorld = nil :: ((Session) -> ())? -- after a portal trip
Game.sharkAggro = nil :: ((Session, number?, string?, string?) -> ())? -- Sharks.aggro
Game.sharkOnGrab = nil :: ((Session, string) -> ())? -- Sharks.onGrab

return Game
