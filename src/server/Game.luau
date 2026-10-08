-- Core loop: +speed every second, tank income, collect pad, rides, slots,
-- rebirth, gates, the shark's bite consequences, and state sync.

local Players = game:GetService("Players")

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
	rideModel: Model?,
	pending: number,
	lastPos: Vector3?,
	passes: { [string]: boolean },
	joinedAt: number,
	eatenUntil: number,
	dirty: boolean,
	inWater: boolean,
	leaderSpeed: IntValue?,
	leaderIncome: IntValue?,
	friendBoost: number, -- +coins from friends in this server (0..0.5)
	slow: boolean, -- Slow Mode on
	offline: number, -- welcome-back coins waiting to be claimed
}

Game.sessions = {} :: { [Player]: Session }
Game.frenzy = false -- set by Sharks while a hunt is on

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
	local mult = Config.Rebirth.mult ^ s.profile.rebirths
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
	return s.slow and math.min(v, Config.SLOW_SPEED) or v
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

----------------------------------------------------------------- state sync
function Game.push(s: Session)
	local p = s.profile
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
		storage = Config.Tank.storage,
		slots = tankSlots(s),
		friendBoost = s.friendBoost,
		slow = s.slow,
		slotPrice = Game.slotPrice(s),
		rebirths = p.rebirths,
		tut = p.tut,
		shields = p.shields,
		carrying = s.carrying,
		passes = s.passes,
		boostLeft = math.max(0, p.boostUntil - now),
		luckLeft = math.max(0, p.luckUntil - now),
		playtime = p.playtime,
		starter = p.starter,
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
	local joints = {}
	for _, d in char:GetDescendants() do
		if d:IsA("Motor6D") and d.Part0 and d.Part1 then
			table.insert(joints, d)
		end
	end
	local leg = Rig.legLength(joints :: any, hrp)
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
		NameTag.attach(m.PrimaryPart :: BasePart, c, nil, { height = 1.9, maxDist = 90, width = 3.4 })
		m.Parent = char
		s.carryModel = m
	end
	s.dirty = true
end

----------------------------------------------------------------- tank
-- Everything you catch is kept (up to Config.Tank.storage). The Active ones
-- (c.e) swim in your tank and earn; the rest wait in storage. New catches
-- go Active if there's room, or swap in for your weakest Active one if
-- they're better. Players can Equip / Unequip / Equip Best from the Tank UI.

local function weakestActive(s: Session): Data.Creature?
	local best, val = nil, math.huge
	for _, c in s.profile.creatures do
		if c.e and baseValue(c) < val then
			best, val = c, baseValue(c)
		end
	end
	return best
end

local function weakestStored(s: Session): (number?, Data.Creature?)
	local idx, best, val = nil, nil, math.huge
	for i, c in s.profile.creatures do
		if not c.e and baseValue(c) < val then
			idx, best, val = i, c, baseValue(c)
		end
	end
	return idx, best
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
function Game.refreshTank(s: Session)
	local plot = s.plot
	if not plot then
		return
	end
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
	Game.updateTankSign(s)
end

-- the sign over the tank: what it earns now, and per day while you're away
function Game.updateTankSign(s: Session)
	local plot = s.plot
	if not plot then
		return
	end
	local inc = Game.income(s)
	plot.tankIncome.Text = ("$%s/s  ·  %d/%d Active"):format(formatShort(inc), Game.activeCount(s), tankSlots(s))
	plot.tankOffline.Text = ("💤 $%s / day offline"):format(formatShort(Config.offlinePerDay(inc)))
end

-- a new catch arrives at the dock
function Game.addCreature(s: Session, c: Data.Creature)
	local p = s.profile
	c.id = p.nextId
	p.nextId += 1
	local value = baseValue(c)
	local mult = Game.coinMult(s)
	local info: { [string]: any } = { r = c.r, m = c.m, z = c.z, s = c.s, v = value * mult }
	if Game.activeCount(s) < tankSlots(s) then
		c.e = true
	else
		local weak = weakestActive(s)
		if weak and value > baseValue(weak) then
			weak.e = false
			c.e = true
			info.swapped = Config.fullName(weak.z, weak.r, weak.m, weak.s)
		else
			c.e = false
		end
	end
	info.active = c.e
	table.insert(p.creatures, c)
	-- storage full? the weakest stored creature is sold
	if #p.creatures > Config.Tank.storage then
		local idx, worst = weakestStored(s)
		if idx and worst then
			local sold = math.floor(baseValue(worst) * Config.SELL_SECONDS * mult)
			p.coins += sold
			table.remove(p.creatures, idx)
			info.sold = sold
			info.soldName = Config.fullName(worst.z, worst.r, worst.m, worst.s)
		end
	end
	Game.notify(s.player, "deposit", info)
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
	return not Layout.isSafe(hrp.Position)
end

-- returns "shield" or "eaten"
function Game.bite(s: Session, sharkPos: Vector3): string
	local hrp = root(s.player)
	if not hrp then
		return "none"
	end
	if s.profile.shields > 0 then
		s.profile.shields -= 1
		s.eatenUntil = os.clock() + 2.5
		Game.notify(s.player, "shield", { from = sharkPos })
		s.dirty = true
		return "shield"
	end
	if s.carrying then
		Game.notify(s.player, "lost", { r = s.carrying.r, m = s.carrying.m })
		Game.setCarry(s, nil)
	end
	s.eatenUntil = os.clock() + Config.Shark.eatenTime + 2.5
	hrp.Anchored = true
	-- wash up once the victim's cutscene has faded to black (+ a little for ping)
	task.delay(Config.Shark.eatenTime + 0.35, function()
		local h = root(s.player)
		if h then
			local x = math.clamp(h.Position.X, -Config.LANE_WIDTH / 2 + 10, Config.LANE_WIDTH / 2 - 10)
			h.Anchored = false
			h.Parent:PivotTo(CFrame.new(x, 14, Config.SHORE_Z - 4) * CFrame.Angles(0, math.pi, 0))
			Game.notify(s.player, "spat", {})
		end
	end)
	return "eaten"
end

----------------------------------------------------------------- actions
local actions: { [string]: (Session, any) -> () } = {}

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
	Game.notify(s.player, "ride", { id = id, gain = Game.gain(s) })
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
	if c and c.e then
		c.e = false
		Game.refreshTank(s)
		s.dirty = true
	end
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

actions.buySlot = function(s)
	local price = Game.slotPrice(s)
	if price and s.profile.coins >= price then
		s.profile.coins -= price
		s.profile.slots += 1
		Game.equipBest(s)
		Game.notify(s.player, "slot", { slots = tankSlots(s) })
		s.dirty = true
	end
end

actions.rebirth = function(s)
	local p = s.profile
	if p.speed < Config.Rebirth.speed then
		return
	end
	p.rebirths += 1
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
	Game.notifyAll("announce", { text = ("%s REBIRTHED! (x%s speed)"):format(s.player.DisplayName, tostring(Config.Rebirth.mult ^ p.rebirths)) })
	Game.notify(s.player, "rebirth", { rebirths = p.rebirths })
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
local function claimPlot(s: Session)
	for _, plot in World.Plots do
		if not plot.owner then
			plot.owner = s.player
			s.plot = plot
			plot.signLabel.Text = s.player.DisplayName .. "'s Dock"
			plot.viewPrompt.ObjectText = s.player.DisplayName .. "'s Tank"
			plot.model:SetAttribute("Owner", s.player.UserId)
			return
		end
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
	if s.plot then
		task.defer(function()
			char:PivotTo(Layout.spawnCFrame(s.plot.cf))
		end)
	end
	s.inWater = false
	task.defer(Game.attachRide, s)
	if s.carrying then
		local c = s.carrying
		task.defer(Game.setCarry, s, c)
	end
end

function Game.join(player: Player)
	local profile, canSave = Data.load(player.UserId)
	if not player.Parent then
		return
	end
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
	-- welcome back: the tank kept earning (slower) while you were away
	local away = profile.lastSeen > 0 and os.time() - profile.lastSeen or 0
	if away >= Config.Offline.minSeconds then
		local secs = math.min(away, Config.Offline.maxHours * 3600)
		s.offline = math.floor(Game.income(s) * secs * Config.Offline.rate)
		if s.offline > 0 then
			Game.notify(player, "offline", { amount = s.offline, seconds = secs })
		end
	end
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
	if Game.onJoin then
		Game.onJoin(s)
	end
end

function Game.leave(player: Player)
	local s = Game.sessions[player]
	if not s then
		return
	end
	Game.sessions[player] = nil
	s.profile.coins += s.pending + s.offline
	if s.plot then
		s.plot.owner = nil
		s.plot.signLabel.Text = "Empty Dock"
		s.plot.viewPrompt.ObjectText = "Empty Dock"
		s.plot.padLabel.Text = "$0"
		s.plot.tankIncome.Text = ""
		s.plot.tankOffline.Text = ""
		s.plot.slots:ClearAllChildren()
		s.plot.model:SetAttribute("Owner", nil)
	end
	if s.canSave then
		Data.save(player.UserId, s.profile)
	end
	for _, other in Game.sessions do
		task.spawn(Game.updateFriendBoost, other)
	end
end

function Game.saveAll()
	for player, s in Game.sessions do
		if s.canSave then
			task.spawn(Data.save, player.UserId, s.profile)
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
		for _, zone in Config.Zones do
			if zone.gate > 0 and before < zone.gate and p.speed >= zone.gate then
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
		local from = (prev and (prev - pos).Magnitude < 120) and prev or pos
		local wet = Layout.inWater(pos) and not Layout.islandAt(pos, 0)
		if wet ~= s.inWater then
			s.inWater = wet
			Game.setRideVisible(s, wet)
		end
		local plot = s.plot
		if plot then
			local pad = Layout.padPos(plot.cf)
			if s.pending > 0 and Layout.segmentDist(pad, from, pos) < Config.COLLECT_RADIUS and math.abs(pos.Y - pad.Y) < 8 then
				local amount = s.pending
				s.profile.coins += amount
				s.pending = 0
				plot.padLabel.Text = "$0"
				Game.notify(s.player, "collect", { amount = amount })
				s.dirty = true
			end
			if s.carrying then
				local tank = Layout.tankPos(plot.cf)
				if Layout.segmentDist(tank, from, pos) < Config.DEPOSIT_RADIUS then
					local c = s.carrying :: Data.Creature
					Game.setCarry(s, nil)
					Game.addCreature(s, { r = c.r, z = c.z, m = c.m, s = c.s })
				end
			end
		end
		-- hard gates: past a wall you haven't unlocked? back to the shore
		local zone = Config.zoneAt(pos.Z)
		if zone and zone.gate > s.profile.speed and pos.Z > zone.zStart + 2 and not hrp.Anchored then
			-- bounce back to just before the gate, facing home (not all the way to the beach)
			local back = Vector3.new(pos.X, pos.Y, zone.zStart - 14)
			hrp.Parent:PivotTo(CFrame.lookAt(back, back - Vector3.new(0, 0, 1)))
			hrp.AssemblyLinearVelocity = Vector3.new(0, 30, -40)
			Game.notify(s.player, "gate", { need = zone.gate, zone = zone.id })
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
		for player, s in Game.sessions do
			s.profile.coins += s.pending + s.offline
			s.pending, s.offline = 0, 0
			if s.canSave then
				Data.save(player.UserId, s.profile)
			end
		end
	end)
end

Game.onJoin = nil :: ((Session) -> ())?

return Game
