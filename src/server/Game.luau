-- Core loop: +speed every second, tank income, collect pad, rides, slots,
-- rebirth, gates, the shark's bite consequences, and state sync.

local Players = game:GetService("Players")

local Shared = game.ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Layout = require(Shared.Layout)
local Build = require(Shared.Build)
local Creatures = require(Shared.Creatures)
local Rides = require(Shared.Rides)
local Remotes = require(Shared.Remotes)
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
	leaderRebirths: IntValue?,
	offline: number, -- welcome-back coins waiting to be claimed
}

Game.sessions = {} :: { [Player]: Session }

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
	local m = 1
	if s.passes.TwoXCoins then
		m *= 2
	end
	if s.passes.VIP then
		m *= 1.1
	end
	return m
end

function Game.income(s: Session): number
	local total = 0
	for _, c in s.profile.tank do
		total += Config.creatureValue(c.r, c.z, c.m)
	end
	return total * Game.coinMult(s)
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

function Game.luck(s: Session): number
	local l = Config.Luck.base
	if s.passes.LuckyNet then
		l += Config.Luck.pass
	end
	if s.profile.luckUntil > os.time() then
		l += Config.Luck.potion
	end
	return l
end

local function tankSlots(s: Session): number
	return s.profile.slots + (s.passes.BigTank and Config.Tank.passSlots or 0)
end

----------------------------------------------------------------- state sync
function Game.push(s: Session)
	local p = s.profile
	local tank = {}
	for _, c in p.tank do
		table.insert(tank, { r = c.r, z = c.z, m = c.m, v = Config.creatureValue(c.r, c.z, c.m) * Game.coinMult(s) })
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
		tank = tank,
		slots = tankSlots(s),
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
		if d:IsA("BasePart") and d.Name ~= "Root" then
			if d:GetAttribute("BaseT") == nil then
				d:SetAttribute("BaseT", d.Transparency)
			end
			d.Transparency = visible and d:GetAttribute("BaseT") or 1
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
		local m = Creatures.build(c.r, c.m, 0.85)
		m:PivotTo(head.CFrame * CFrame.new(0, 2.6, 0))
		Build.weldToRoot(m)
		local w = Instance.new("WeldConstraint")
		w.Part0 = head
		w.Part1 = m.PrimaryPart
		w.Parent = m.PrimaryPart
		m.Name = "Carried"
		m.Parent = char
		s.carryModel = m
	end
	s.dirty = true
end

----------------------------------------------------------------- tank
function Game.refreshTank(s: Session)
	local plot = s.plot
	if not plot then
		return
	end
	plot.slots:ClearAllChildren()
	local tcf = CFrame.new(Layout.tankPos(plot.cf)) * plot.cf.Rotation * CFrame.new(0, 0.5, 0)
	for i, c in s.profile.tank do
		local col = (i - 1) % 8
		local row = math.floor((i - 1) / 8)
		local m = Creatures.build(c.r, c.m, 0.62)
		m:PivotTo(tcf * CFrame.new(-6.3 + col * 1.8, 3.1 + row * 2.6, 0) * CFrame.Angles(0, math.pi / 2, 0))
		m:SetAttribute("Swim", true)
		m.Parent = plot.slots
	end
end

local function weakestIndex(tank: { Data.Creature }): (number?, number)
	local idx, val = nil, math.huge
	for i, c in tank do
		local v = Config.creatureValue(c.r, c.z, c.m)
		if v < val then
			idx, val = i, v
		end
	end
	return idx, val
end

-- put a creature in the tank; if full, it replaces the weakest (or sells)
function Game.addToTank(s: Session, c: Data.Creature)
	local value = Config.creatureValue(c.r, c.z, c.m)
	local tank = s.profile.tank
	if #tank < tankSlots(s) then
		table.insert(tank, c)
		Game.notify(s.player, "deposit", { r = c.r, m = c.m, z = c.z, v = value * Game.coinMult(s) })
	else
		local wi, wv = weakestIndex(tank)
		if wi and value > wv then
			local old = tank[wi]
			local sold = math.floor(wv * Config.SELL_SECONDS)
			s.profile.coins += sold
			tank[wi] = c
			Game.notify(s.player, "deposit", { r = c.r, m = c.m, z = c.z, v = value * Game.coinMult(s), replaced = old.r, sold = sold })
		else
			local sold = math.floor(value * Config.SELL_SECONDS)
			s.profile.coins += sold
			Game.notify(s.player, "sold", { r = c.r, m = c.m, sold = sold })
		end
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
	s.eatenUntil = os.clock() + Config.Shark.eatenTime + 2
	hrp.Anchored = true
	task.delay(Config.Shark.eatenTime, function()
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

actions.equip = function(s, id)
	if typeof(id) == "string" and Game.ownsRide(s, id) then
		s.profile.ride = id
		Game.attachRide(s)
		s.dirty = true
	end
end

actions.buySlot = function(s)
	local price = Game.slotPrice(s)
	local hrp = root(s.player)
	if not (hrp and Layout.atRideShop(hrp.Position)) then
		Game.notify(s.player, "rideShop", {})
		return
	end
	if price and s.profile.coins >= price then
		s.profile.coins -= price
		s.profile.slots += 1
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
	hum.WalkSpeed = Config.realSpeed(s.profile.speed)
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

	local ls = Instance.new("Folder")
	ls.Name = "leaderstats"
	local sp = Instance.new("IntValue")
	sp.Name = "Speed"
	sp.Value = math.floor(profile.speed)
	sp.Parent = ls
	local rb = Instance.new("IntValue")
	rb.Name = "Rebirths"
	rb.Value = profile.rebirths
	rb.Parent = ls
	ls.Parent = player
	s.leaderSpeed, s.leaderRebirths = sp, rb

	player.CharacterAdded:Connect(function(char)
		onCharacter(s, char)
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
		s.plot.padLabel.Text = "$0"
		s.plot.slots:ClearAllChildren()
		s.plot.model:SetAttribute("Owner", nil)
	end
	if s.canSave then
		Data.save(player.UserId, s.profile)
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
local function formatShort(n: number): string
	local units = { "", "K", "M", "B", "T", "Qa" }
	local i = 1
	while n >= 1000 and i < #units do
		n /= 1000
		i += 1
	end
	return (i == 1 and tostring(math.floor(n)) or (string.format("%.1f", n):gsub("%.0$", ""))) .. units[i]
end

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
			hum.WalkSpeed = Config.realSpeed(p.speed)
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
		end
		if s.leaderSpeed then
			s.leaderSpeed.Value = math.floor(p.speed)
		end
		if s.leaderRebirths then
			s.leaderRebirths.Value = p.rebirths
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
					Game.addToTank(s, c)
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
