-- Player vs player, shark style:
--   Raid   hold RAID at another player's tank while they're out at sea (in
--          the water or on an island: anywhere off the beach). While the
--          owner is home a shield shimmers over the tank (plot attribute
--          "Guarded" = "home" / "lock" / "new"; client Pvp.luau signs). It
--          takes Config.Raid.time seconds; they're alerted at once and stop
--          it by getting back to their dock. The further out they are, the
--          longer the raid takes, so the race home is always winnable (too
--          far out to make it back = can't be raided). Too slow, and a spin
--          picks one of their creatures (rarer = less likely: a Mythic is a
--          long shot), and you walk it home in forced slow mode while anyone,
--          the owner too, can bonk it loose. After a raid the tank is safe a while, and
--          you can't keep picking on the same player.
-- Raids: after your first evolve
-- (raider and owner both), between players within a couple of evolves.

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
-- cooldowns by UserId, so leaving and rejoining doesn't reset them
local raidedAt: { [number]: number } = {}
local raiderAt: { [number]: number } = {}
local pairAt: { [string]: number } = {} -- "raider:victim": last raid between them
local rng = Random.new()

local function veteran(s: Game.Session, minPlaytime: number): boolean
	return s.profile.tut >= 5 and s.profile.playtime >= minPlaytime
end

-- raids are for players past their first rebirth (raider and owner both):
-- new players learn the sea first
local function raider(s: Game.Session): boolean
	return veteran(s, Config.Raid.minPlaytime) and s.profile.rebirths >= 1
end

-- on the beach / plaza / their dock (not in the water, not on an island)
local function home(s: Game.Session): boolean
	local hrp = Game.root(s.player)
	return hrp == nil or not Layout.inWater(hrp.Position)
end

-- why this tank can't be raided right now (nil = it can)
local function guardedBy(s: Game.Session): string?
	if not raider(s) then
		return "new" -- (raids aren't a thing for them yet: no shield shown)
	elseif s.profile.lockUntil > os.time() then
		return "lock"
	elseif home(s) then
		return "home"
	end
	return nil
end

-- the shield over each tank, from its owner's state
local function updateGuards()
	for _, s in Game.sessions do
		local plot = s.plot
		if plot then
			local why = guardedBy(s)
			if raids[s.player] then
				why = nil -- (mid-raid: they're on their way)
			end
			if plot.model:GetAttribute("Guarded") ~= why then
				plot.model:SetAttribute("Guarded", why)
				local dome = plot.model:FindFirstChild("Guard", true) :: BasePart?
				if dome then
					dome.Transparency = (why == "home" or why == "lock") and 0.15 or 1
					dome.Color = why == "lock" and Color3.fromRGB(255, 200, 60) or Color3.fromRGB(90, 255, 140)
				end
			end
		end
	end
end

----------------------------------------------------------------- raids
local function tankPos(plot: World.Plot): Vector3
	return Layout.tankPos(plot.cf)
end

-- tell whoever's still here that it's over (someone left the game)
local function abandon(victim: Player)
	local r = raids[victim]
	if not r then
		return
	end
	if Game.sessions[victim] then
		Game.notify(victim, "raidDefended", { by = r.raider.player.DisplayName, gaveUp = true })
	end
	if Game.sessions[r.raider.player] then
		Game.notify(r.raider.player, "raidFail", { why = "gone" })
	end
end

local function endRaid(victim: Player)
	local r = raids[victim]
	if not r then
		return
	end
	raids[victim] = nil
	r.plot.model:SetAttribute("RaidEnds", nil)
	-- the tank is safe for a while (clients hide the prompt and say so)
	r.plot.model:SetAttribute("SafeUntil", workspace:GetServerTimeNow() + Config.Raid.victimCooldown)
	raidedAt[victim.UserId] = os.clock()
	raiderAt[r.raider.player.UserId] = os.clock()
	pairAt[r.raider.player.UserId .. ":" .. victim.UserId] = os.clock()
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
			return no("You're already raiding")
		end
	end
	if (hrp.Position - tankPos(plot)).Magnitude > cfg.stayRadius then
		return no("Get closer to the tank")
	end
	if not raider(s) then
		return no("Raids unlock after you evolve")
	elseif not raider(v) then
		return no("They're too new to raid")
	elseif math.abs(s.profile.rebirths - v.profile.rebirths) > cfg.evolveGap then
		return no("Too far apart in evolves to raid")
	end
	if now - (raiderAt[s.player.UserId] or -1e9) < cfg.raiderCooldown then
		return no("Catch your breath before the next raid")
	end
	if now - (raidedAt[(owner :: Player).UserId] or -1e9) < cfg.victimCooldown then
		return no("This tank was raided recently")
	end
	if now - (pairAt[s.player.UserId .. ":" .. (owner :: Player).UserId] or -1e9) < cfg.pairCooldown then
		return no("Give them a break: raid someone else")
	end
	if v.profile.lockUntil > os.time() then
		return no("That tank is locked")
	end
	if home(v) then
		return no("They're home: tank is safe")
	end
	if #v.profile.creatures < 2 then
		return no("Nothing worth taking")
	end
	-- the further out they are, the longer it takes: the race home is
	-- always winnable (time to get back at full speed, plus some slack)
	local vr = Game.root(v.player)
	local away = vr and (vr.Position - tankPos(plot)).Magnitude or 0
	local secs = math.max(cfg.time, away / Config.realSpeed(v.profile.speed) * 1.3 + 10)
	if secs > cfg.maxTime then
		return no("They're too far out to race back")
	end
	secs = math.ceil(secs)
	local r: Raid = { raider = s, victim = v, plot = plot, ends = now + secs }
	raids[owner :: Player] = r
	plot.model:SetAttribute("RaidEnds", workspace:GetServerTimeNow() + secs)
	Game.notify(v.player, "raided", { by = s.player.DisplayName, seconds = secs, x = tankPos(plot).X, y = tankPos(plot).Y, z = tankPos(plot).Z })
	Game.notify(s.player, "raidStart", { name = v.player.DisplayName, seconds = secs })
	Game.track(s.player, "raid", { stage = "start" })
end

-- the prize: any creature in their tank (Active or not, so unequipping
-- everything from the Tank window can't dodge a raid), weighted by rarity
-- (Config.Raid.lootWeight): a Mythic can go, but it's a long shot. Also the
-- spin both players watch: up to SPIN_SHOWN of their creatures, each with
-- its real chance, and which one won.
local SPIN_SHOWN = 12
local function pickLoot(v: Game.Session): (Data.Creature?, { any }, number)
	local weights = Config.Raid.lootWeight
	local all, total = {}, 0
	for _, c in v.profile.creatures do
		local w = weights[c.r] or 1
		table.insert(all, { c = c, w = w })
		total += w
	end
	if total <= 0 then
		return nil, {}, 0
	end
	local roll = rng:NextNumber(0, total)
	local win = all[#all]
	for _, e in all do
		roll -= e.w
		if roll <= 0 then
			win = e
			break
		end
	end
	-- what the spin shows: the winner plus others (all of them if few)
	local shown = { win }
	local rest = {}
	for _, e in all do
		if e ~= win then
			table.insert(rest, e)
		end
	end
	while #shown < SPIN_SHOWN and #rest > 0 do
		table.insert(shown, table.remove(rest, rng:NextInteger(1, #rest)))
	end
	local items = {}
	for _, e in shown do
		table.insert(items, { r = e.c.r, z = e.c.z, m = e.c.m, s = e.c.s, p = e.w / total })
	end
	return win.c, items, 1
end

local function finish(r: Raid)
	local v, s = r.victim, r.raider
	endRaid(v.player)
	local c, spin, winAt = pickLoot(v)
	if #v.profile.creatures < 2 then
		c = nil -- (they sold down to their last one mid-raid: never take that)
	end
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
	-- now get it home: in your hands, in forced slow mode, and anyone can
	-- bonk it loose (the owner too: their way to win it back)
	local loot = { r = c.r, z = c.z, m = c.m, s = c.s }
	if Game.handsFull(s) then
		Game.addCreature(s, loot, true) -- (net full: it goes straight in)
	else
		-- in your hands, or your net if your hands are busy: walked home either way
		local inHands = not s.carrying
		Game.takeCatch(s, loot)
		if inHands then
			s.carryUntil = nil -- (no wriggling free: the danger is other players)
		end
		Game.setRaidLoot(s, loot)
	end
	s.dirty = true
	local name = Config.fullName(c.z, c.r, c.m, c.s)
	Game.notify(s.player, "raidWon", { name = name, from = v.player.DisplayName, spin = spin, win = winAt })
	Game.notify(v.player, "raidLost", { name = name, by = s.player.DisplayName, safe = Config.Raid.victimCooldown, spin = spin, win = winAt })
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
		if v.profile.lockUntil > os.time() then
			-- they bought a Tank Lock mid-raid: it's off
			endRaid(victim)
			Game.notify(victim, "raidDefended", { by = s.player.DisplayName, locked = true })
			Game.notify(s.player, "raidFail", { why = "locked" })
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
	Game.action("raid", startRaid)
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc >= 0.2 then
			acc = 0
			tick()
			updateGuards()
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
	end)
end

return Raids
