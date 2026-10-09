-- Player vs player, shark style:
--   Chum   throw a bucket at a rider near you: their zone's shark comes for
--          them (Config.Chum; by day; cooldown)
--   Raid   hold RAID at another player's tank while they're out at sea. It
--          takes Config.Raid.time seconds; they're alerted at once and stop
--          it by getting back to their dock. Too slow, and you take one of
--          their creatures (never their best) and carry it home.
-- Both only between players who've played a while (no new players).

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local Shared = game.ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Layout = require(Shared.Layout)
local Data = require(script.Parent.Data)
local Game = require(script.Parent.Game)
local World = require(script.Parent.World)

local Raids = {}

type Raid = { raider: Game.Session, victim: Game.Session, plot: World.Plot, ends: number }

local raids: { [Player]: Raid } = {} -- by victim
local raidedAt: { [Player]: number } = {}
local raiderAt: { [Player]: number } = {}
local chumAt: { [Player]: number } = {}
local rng = Random.new()

local function veteran(s: Game.Session, minPlaytime: number): boolean
	return s.profile.tut >= 5 and s.profile.playtime >= minPlaytime
end

local function atSea(s: Game.Session): boolean
	local hrp = Game.root(s.player)
	return hrp ~= nil and Layout.inWater(hrp.Position) and Layout.islandAt(hrp.Position, 0) == nil
end

----------------------------------------------------------------- chum
local function chum(s: Game.Session, targetId: any)
	local cfg = Config.Chum
	local now = os.clock()
	if typeof(targetId) ~= "number" or now - (chumAt[s.player] or -1e9) < cfg.cooldown then
		return
	end
	local target = Players:GetPlayerByUserId(targetId)
	local t = target and Game.sessions[target]
	local a, b = Game.root(s.player), target and Game.root(target)
	if not (t and a and b) or t == s or t.profile.world ~= s.profile.world then
		return
	end
	if not veteran(s, cfg.minPlaytime) then
		Game.notify(s.player, "announce", { text = "Chum unlocks after 5 minutes of play" })
		return
	end
	if (a.Position - b.Position).Magnitude > cfg.range or not veteran(t, cfg.minPlaytime) or not atSea(t) then
		Game.notify(s.player, "announce", { text = "They're out of reach" })
		return
	end
	if t.profile.shields > 0 then
		-- a Shark Shield eats the chum (and is used up)
		t.profile.shields -= 1
		t.dirty = true
		chumAt[s.player] = now
		Game.notify(t.player, "announce", { text = ("Your shield blocked %s's chum"):format(s.player.DisplayName) })
		Game.notify(s.player, "announce", { text = ("%s's shield blocked your chum"):format(target.DisplayName) })
		return
	end
	local ok = Game.sharkAggro and Game.sharkAggro(t, cfg.grudge, "chum", s.player.DisplayName)
	if not ok then
		Game.notify(s.player, "announce", { text = "No shark would come right now" })
		return
	end
	chumAt[s.player] = now
	Game.notify(s.player, "chumThrown", { name = target.DisplayName, cooldown = cfg.cooldown })
	Game.notifyAll("chumSplash", { x = b.Position.X, z = b.Position.Z })
	Game.track(s.player, "chum", {})
end

----------------------------------------------------------------- raids
local function tankPos(plot: World.Plot): Vector3
	return Layout.tankPos(plot.cf)
end

-- tell whoever's still here that it's over (someone left / took the portal)
local function abandon(victim: Player)
	local r = raids[victim]
	if not r then
		return
	end
	if Game.sessions[victim] then
		Game.notify(victim, "raidDefended", { by = r.raider.player.DisplayName, gaveUp = true })
	end
	if Game.sessions[r.raider.player] then
		Game.notify(r.raider.player, "raidFail", { why = "left" })
	end
end

local function endRaid(victim: Player)
	local r = raids[victim]
	if not r then
		return
	end
	raids[victim] = nil
	r.plot.model:SetAttribute("RaidEnds", nil)
	raidedAt[victim] = os.clock()
	raiderAt[r.raider.player] = os.clock()
end

local function startRaid(s: Game.Session, plotIndex: any)
	local cfg = Config.Raid
	local now = os.clock()
	if typeof(plotIndex) ~= "number" then
		return
	end
	local plots = World.WorldPlots[s.profile.world]
	local plot = plots and plots[plotIndex]
	local owner = plot and plot.owner
	local v = owner and Game.sessions[owner]
	local hrp = Game.root(s.player)
	if not (plot and v and hrp) or v == s or v.profile.world ~= s.profile.world then
		return
	end
	local function no(text: string)
		Game.notify(s.player, "announce", { text = text })
	end
	if raids[owner :: Player] then
		return no("Someone's already raiding this tank")
	end
	for _, r in raids do
		if r.raider == s then
			return
		end
	end
	if (hrp.Position - tankPos(plot)).Magnitude > cfg.stayRadius then
		return
	end
	if not veteran(s, cfg.minPlaytime) or not veteran(v, cfg.minPlaytime) then
		return no("Raids unlock after 10 minutes of play")
	end
	if now - (raiderAt[s.player] or -1e9) < cfg.raiderCooldown then
		return no("Catch your breath before the next raid")
	end
	if now - (raidedAt[owner :: Player] or -1e9) < cfg.victimCooldown then
		return no("This tank was raided recently")
	end
	if not atSea(v) then
		return no("Only while they're out at sea")
	end
	if v.profile.lockUntil > os.time() then
		return no("That tank is locked")
	end
	if #v.profile.creatures < 2 then
		return no("Nothing worth taking")
	end
	local r: Raid = { raider = s, victim = v, plot = plot, ends = now + cfg.time }
	raids[owner :: Player] = r
	plot.model:SetAttribute("RaidEnds", workspace:GetServerTimeNow() + cfg.time)
	Game.notify(v.player, "raided", { by = s.player.DisplayName, seconds = cfg.time, x = tankPos(plot).X, y = tankPos(plot).Y, z = tankPos(plot).Z })
	Game.notify(s.player, "raidStart", { name = v.player.DisplayName, seconds = cfg.time })
	Game.track(s.player, "raid", { stage = "start" })
end

-- a random creature from their tank that isn't their best (Active or not,
-- so unequipping everything from the Tank window can't dodge a raid)
local function pickLoot(v: Game.Session): Data.Creature?
	local best, bestV = nil, -1
	local pool = {}
	for _, c in v.profile.creatures do
		local val = Config.creatureValue(c.r, c.z, c.m, c.s)
		if val > bestV then
			best, bestV = c, val
		end
		table.insert(pool, c)
	end
	local i = table.find(pool, best)
	if i then
		table.remove(pool, i)
	end
	return #pool > 0 and pool[rng:NextInteger(1, #pool)] or nil
end

local function finish(r: Raid)
	local v, s = r.victim, r.raider
	endRaid(v.player)
	local c = pickLoot(v)
	if not c then
		Game.notify(s.player, "raidFail", { why = "empty" })
		return
	end
	local i = table.find(v.profile.creatures, c)
	if i then
		table.remove(v.profile.creatures, i)
	end
	Game.refreshTank(v)
	v.dirty = true
	local loot = { r = c.r, z = c.z, m = c.m, s = c.s }
	if Game.handsFull(s) then
		Game.addCreature(s, loot)
	else
		Game.takeCatch(s, loot)
	end
	s.dirty = true
	local name = Config.fullName(c.z, c.r, c.m, c.s)
	Game.notify(s.player, "raidWon", { name = name, from = v.player.DisplayName })
	Game.notify(v.player, "raidLost", { name = name, by = s.player.DisplayName })
	Game.notifyAll("raidNews", { by = s.player.DisplayName, from = v.player.DisplayName, name = name })
	Game.track(s.player, "raid", { stage = "won" })
end

local function tick()
	local cfg = Config.Raid
	local now = os.clock()
	for victim, r in raids do
		local v, s = r.victim, r.raider
		if not Game.sessions[victim] or not Game.sessions[s.player] or v.profile.world ~= s.profile.world then
			abandon(victim)
			endRaid(victim)
			continue
		end
		local tank = tankPos(r.plot)
		local owner = Game.root(victim)
		local raider = Game.root(s.player)
		if owner and (owner.Position - tank).Magnitude < cfg.defendRadius then
			-- made it home in time: the raider gets thrown off the dock
			endRaid(victim)
			if raider then
				local away = (raider.Position - tank) * Vector3.new(1, 0, 1)
				away = away.Magnitude > 0.1 and away.Unit or Vector3.new(0, 0, -1)
				raider.AssemblyLinearVelocity = away * 90 + Vector3.new(0, 55, 0)
			end
			Game.notify(victim, "raidDefended", { by = s.player.DisplayName })
			Game.notify(s.player, "raidFail", { why = "defended", by = victim.DisplayName })
			Game.track(victim, "raid", { stage = "defended" })
		elseif not raider or (raider.Position - tank).Magnitude > cfg.stayRadius + 4 then
			endRaid(victim)
			Game.notify(s.player, "raidFail", { why = "left" })
			Game.notify(victim, "raidDefended", { by = s.player.DisplayName, gaveUp = true })
		elseif now >= r.ends then
			finish(r)
		end
	end
end

function Raids.start()
	Game.action("chum", chum)
	Game.action("raid", startRaid)
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc >= 0.2 then
			acc = 0
			tick()
		end
	end)
	Players.PlayerRemoving:Connect(function(p)
		abandon(p)
		endRaid(p)
		for victim, r in raids do
			if r.raider.player == p then
				abandon(victim)
				endRaid(victim)
			end
		end
		raidedAt[p], raiderAt[p], chumAt[p] = nil, nil, nil
	end)
end

return Raids
