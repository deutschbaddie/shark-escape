-- Free rewards that bring players back:
--   Daily Rewards  a 7-day streak (claim every 20h; miss 48h and it restarts).
--                  Day 7 is a Huge Legendary.
--   Group chest    the CLAIM chest in the plaza: join the group (and like the
--                  game) to open it every 12h for cash + a 2x speed boost.
-- The server checks group membership itself; clients only ask.

local Shared = game.ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Game = require(script.Parent.Game)
local Bubbles = require(script.Parent.Bubbles)

local Rewards = {}

local function addBoost(p: any, field: string, minutes: number)
	local now = os.time()
	p[field] = math.max(p[field], now) + minutes * 60
end

local function grant(s: Game.Session, r: { [string]: any }): string
	local p = s.profile
	if r.kind == "coins" then
		local amount = math.max(r.min or 0, math.floor(Game.income(s) * (r.seconds or 60)))
		p.coins += amount
		return ("+$%s"):format(Game.short(amount))
	elseif r.kind == "shield" then
		p.shields += r.amount or 1
		return ("+%d Shark Shield"):format(r.amount or 1)
	elseif r.kind == "boost" then
		addBoost(p, "boostUntil", r.minutes or 15)
		return ("2x Speed for %d min"):format(r.minutes or 15)
	elseif r.kind == "luck" then
		addBoost(p, "luckUntil", r.minutes or 15)
		return ("Luck Potion for %d min"):format(r.minutes or 15)
	elseif r.kind == "creature" then
		Bubbles.give(s, r.rarity or "Epic", nil, r.size)
		return r.label or "a creature"
	end
	return ""
end

local function claimDaily(s: Game.Session)
	local p = s.profile
	local now = os.time()
	local d = p.daily
	if d.last > 0 and now - d.last < Config.DAILY_GAP_HOURS * 3600 then
		Game.notify(s.player, "daily", { ok = false, wait = d.last + Config.DAILY_GAP_HOURS * 3600 - now })
		return
	end
	if d.last > 0 and now - d.last > Config.DAILY_RESET_HOURS * 3600 then
		d.day = 1 -- missed a day: the streak starts over
	end
	local day = math.clamp(d.day, 1, #Config.Daily)
	local what = grant(s, Config.Daily[day])
	d.last = now
	d.day = day % #Config.Daily + 1
	s.dirty = true
	Game.notify(s.player, "daily", { ok = true, day = day, text = what })
	Game.push(s)
end

local function inGroup(player: Player): boolean
	if Config.GroupId == 0 then
		return true -- no group yet: the chest only asks for a like
	end
	local ok, yes = pcall(player.IsInGroup, player, Config.GroupId)
	return ok and yes == true
end

local function claimGroup(s: Game.Session)
	local p = s.profile
	local now = os.time()
	local ready = p.groupClaim + Config.GroupChest.cooldownHours * 3600
	if now < ready then
		Game.notify(s.player, "groupChest", { ok = false, reason = "wait", wait = ready - now })
		return
	end
	if not inGroup(s.player) then
		Game.notify(s.player, "groupChest", { ok = false, reason = "group" })
		return
	end
	local cfg = Config.GroupChest
	local coins = math.max(cfg.minCoins, math.floor(Game.income(s) * cfg.incomeSeconds))
	p.coins += coins
	addBoost(p, "boostUntil", cfg.boostMinutes)
	p.groupClaim = now
	s.dirty = true
	Game.notify(s.player, "groupChest", { ok = true, coins = coins, minutes = cfg.boostMinutes })
	Game.push(s)
end

-- playtime gifts (Config.PlayGifts): the next one, once you've played long
-- enough this session
local function claimGift(s: Game.Session)
	local i = (s.gifts or 0) + 1
	local g = Config.PlayGifts[i]
	if not g or (os.clock() - s.joinedAt) / 60 < g.at then
		return
	end
	s.gifts = i
	local what = grant(s, g)
	s.dirty = true
	Game.notify(s.player, "gift", { i = i, text = what, last = i == #Config.PlayGifts })
	Game.track(s.player, "gift", { i = i })
	Game.push(s)
end

function Rewards.start()
	Game.action("claimGift", claimGift)
	Game.action("claimDaily", claimDaily)
	Game.action("claimGroup", claimGroup)
end

return Rewards
