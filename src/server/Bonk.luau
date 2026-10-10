-- Noodle Bonk (Config.Bonk / Config.Noodles). One button, two uses:
--   a shark coming for you  -> dazed for a moment (Sharks.bonk)
--   a rider in reach         -> everything they carry spills out as bubbles
--                               anyone can grab, and they get knocked
-- Only at sea; new players can only bonk sharks and can't be bonked. The
-- swing itself is seen by everyone (character attribute "BonkAt": clients
-- animate it, client Bonk.luau).

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local Shared = game.ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Layout = require(Shared.Layout)
local Game = require(script.Parent.Game)
local Sharks = require(script.Parent.Sharks)
local Bubbles = require(script.Parent.Bubbles)

local Bonk = {}

local swungAt: { [Player]: number } = {}
local sharkAt: { [Player]: number } = {}
local bonkedAt: { [Player]: number } = {}
local scored: { [string]: number } = {} -- bonker>victim: last time it counted for Top Bonkers

-- the noodle this player swings (and its tier, for its color)
function Bonk.noodle(s: Game.Session): (any, number)
	for i, n in Config.Noodles do
		if n.pass and s.passes[n.pass] then
			return n, i
		end
	end
	local i = math.clamp(s.profile.noodle or 1, 1, #Config.Noodles)
	return Config.Noodles[i], i
end

local function atSea(s: Game.Session): BasePart?
	local hrp = Game.root(s.player)
	if hrp and Layout.inWater(hrp.Position) and not Layout.islandAt(hrp.Position, 0) and not hrp.Anchored then
		return hrp
	end
	return nil
end

-- someone walking raid loot home on the sand: fair game for anyone
local function lootCarrier(t: Game.Session): BasePart?
	local hrp = t.raidLoot and Game.root(t.player)
	return hrp and not hrp.Anchored and hrp or nil
end

-- can this player take part in rider bonks yet?
local function brawler(s: Game.Session): boolean
	return s.profile.tut >= 5 and s.profile.playtime >= Config.Bonk.protect
end

-- the rider this swing lands on: in reach, in front of you (or right next to
-- you), at sea, fair game; loaded riders first
local function pick(s: Game.Session, hrp: BasePart, reach: number, sea: boolean): (Game.Session?, BasePart?)
	local look = hrp.CFrame.LookVector * Vector3.new(1, 0, 1)
	local best, bestRoot, bestScore = nil, nil, -math.huge
	for _, t in Game.sessions do
		local troot = t ~= s and (lootCarrier(t) or (sea and atSea(t)))
		-- (only riders with something to knock loose: no bonking empty-handed kids around)
		if troot and (Game.carryCount(t) > 0 or t.raidLoot ~= nil) and (brawler(t) or t.raidLoot ~= nil) and os.clock() >= t.eatenUntil and os.clock() - (bonkedAt[t.player] or -1e9) >= Config.Bonk.immune
			and Config.worldAt(troot.Position) == Config.worldAt(hrp.Position) then
			local rel = (troot.Position - hrp.Position) * Vector3.new(1, 0, 1)
			local d = rel.Magnitude
			local front = d < 5 or (look.Magnitude > 0.1 and rel.Unit:Dot(look.Unit) > -0.1)
			if d <= reach and front then
				local score = Game.carryCount(t) * 100 - d
				if score > bestScore then
					best, bestRoot, bestScore = t, troot, score
				end
			end
		end
	end
	return best, bestRoot
end

-- everything they carry spills loose (the net and the hands)
local function popLoot(t: Game.Session): { any }
	local out = {}
	local bag = t.bag
	if bag and #bag > 0 then
		for _, c in bag do
			table.insert(out, c)
		end
		table.clear(bag)
		Game.updateTrail(t)
		t.dirty = true
	end
	local c = t.carrying
	if c then
		table.insert(out, c)
		Game.setCarry(t, nil)
	end
	return out
end

local function swing(s: Game.Session)
	local cfg = Config.Bonk
	local now = os.clock()
	local noodle, tier = Bonk.noodle(s)
	if s.profile.tut < 5 or now - (swungAt[s.player] or -1e9) < noodle.cooldown - 0.2 then
		return
	end
	-- at sea, or on the sand near someone carrying raid loot
	local seaRoot = atSea(s)
	local hrp = seaRoot or Game.root(s.player)
	if not hrp or now < s.eatenUntil then
		return
	end
	if not seaRoot then
		local near = false
		for _, t in Game.sessions do
			local lr = t ~= s and lootCarrier(t)
			if lr and (lr.Position - hrp.Position).Magnitude <= noodle.reach + 6 then
				near = true
			end
		end
		if not near then
			return
		end
	end
	swungAt[s.player] = now
	local char = s.player.Character
	if char then
		char:SetAttribute("Noodle", tier)
		char:SetAttribute("BonkAt", Workspace:GetServerTimeNow()) -- (everyone sees the swing)
	end

	-- 1) a shark coming at you: dazed
	if seaRoot and now - (sharkAt[s.player] or -1e9) >= cfg.sharkCooldown and Sharks.bonk(s, hrp.Position, noodle.reach + 2) then
		sharkAt[s.player] = now
		Game.notify(s.player, "bonkShark", { cooldown = cfg.sharkCooldown })
		return
	end

	-- 2) a rider
	if not brawler(s) and seaRoot then
		return
	end
	local t, troot = pick(s, hrp, noodle.reach, seaRoot ~= nil)
	if not (t and troot) then
		return
	end
	bonkedAt[t.player] = now
	local at = troot.Position
	-- a shield is only spent saving a haul worth it (Epic or better), so a
	-- pack of bonkers can't burn through someone's shields
	local precious = false
	for _, c in { t.carrying, table.unpack(t.bag or {}) } do
		if c and Config.rarity(c.r).index >= Config.rarity("Epic").index then
			precious = true
		end
	end
	if t.profile.shields > 0 and precious then
		t.profile.shields -= 1
		t.dirty = true
		Game.notifyAll("bonkHit", { x = at.X, y = at.Y, z = at.Z, by = s.player.UserId, target = t.player.UserId, shield = true })
		Game.notify(t.player, "bonked", { x = hrp.Position.X, z = hrp.Position.Z, by = s.player.DisplayName, shield = true })
		return
	end
	local loot = popLoot(t)
	local c = loot[1]
	Game.notifyAll("bonkHit", { x = at.X, y = at.Y, z = at.Z, by = s.player.UserId, target = t.player.UserId, loot = c ~= nil })
	Game.notify(t.player, "bonked", { x = hrp.Position.X, z = hrp.Position.Z, by = s.player.DisplayName,
		lost = c and Config.fullName(c.z, c.r, c.m, c.s) or nil, n = #loot })
	if c then
		-- they splash out all around them (a scramble)
		Bubbles.spill(at, loot, t.player, "bonk")
		-- the board counts each rider once a minute (no two friends farming it)
		local key = s.player.UserId .. ">" .. t.player.UserId
		if now - (scored[key] or -1e9) >= 60 then
			scored[key] = now
			s.profile.bonks += 1
		end
		s.dirty = true
		Game.notify(s.player, "bonkedLoot", { name = Config.fullName(c.z, c.r, c.m, c.s), target = t.player.DisplayName, n = #loot })
	end
end

function Bonk.start()
	Game.action("bonk", swing)
	Players.PlayerRemoving:Connect(function(p)
		swungAt[p], sharkAt[p], bonkedAt[p] = nil, nil, nil
	end)
end

return Bonk
