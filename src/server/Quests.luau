-- Daily quests (Config.Quests): 3 a day, new ones at midnight UTC, picked
-- the same way all day for a player (seeded by user id + day). Progress
-- comes from the events every system already sends (Game.trackers): grabs,
-- deposits, close calls, dodges, rings, chum. A done quest pays at once;
-- all 3 add a Luck Potion. The client shows them in the Daily window.

local Shared = game.ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Game = require(script.Parent.Game)

local Quests = {}

type Quest = { id: string, text: string, goal: number, vet: boolean? }

local function def(id: string): Quest?
	for _, q in Config.Quests.pool do
		if q.id == id then
			return q :: any
		end
	end
	return nil
end

local function today(): number
	return os.time() // 86400
end

-- today's quests for this save (rolled once a day)
local function ensure(s: Game.Session): any
	local p = s.profile
	local q = p.quests
	if type(q) ~= "table" or q.day ~= today() or type(q.ids) ~= "table" or type(q.n) ~= "table" then
		local canChum = p.tut >= 5 and p.playtime >= Config.Chum.minPlaytime
		local pool = {}
		for _, d in Config.Quests.pool do
			if not d.vet or canChum then
				table.insert(pool, d.id)
			end
		end
		local rng = Random.new(s.player.UserId + today() * 7919)
		local ids = {}
		for _ = 1, math.min(Config.Quests.perDay, #pool) do
			table.insert(ids, table.remove(pool, rng:NextInteger(1, #pool)))
		end
		q = { day = today(), ids = ids, n = table.create(#ids, 0), bonus = false }
		p.quests = q
		s.dirty = true
	end
	return q
end

-- for the client: { { text, n, goal } }
function Quests.list(s: Game.Session): { any }
	local q = ensure(s)
	local out = {}
	for i, id in q.ids do
		local d = def(id)
		if d then
			table.insert(out, { text = d.text:format(d.goal), n = math.min(q.n[i] or 0, d.goal), goal = d.goal })
		end
	end
	return out
end

local function progress(s: Game.Session, id: string, amount: number)
	local q = ensure(s)
	local i = table.find(q.ids, id)
	local d = def(id)
	if not (i and d) or (q.n[i] or 0) >= d.goal then
		return
	end
	q.n[i] = math.min(d.goal, (q.n[i] or 0) + amount)
	s.dirty = true
	if q.n[i] < d.goal then
		Game.push(s)
		return
	end
	local coins = math.max(Config.Quests.minCoins, math.floor(Game.income(s) * Config.Quests.coinSeconds))
	s.profile.coins += coins
	local all = true
	for j, other in q.ids do
		local od = def(other)
		if od and (q.n[j] or 0) < od.goal then
			all = false
		end
	end
	local bonus = all and not q.bonus
	if bonus then
		q.bonus = true
		local b = Config.Quests.bonus
		s.profile.luckUntil = math.max(s.profile.luckUntil, os.time()) + b.minutes * 60
	end
	Game.notify(s.player, "quest", { id = id, text = d.text:format(d.goal), coins = coins, bonus = bonus and Config.Quests.bonus.minutes or nil })
	Game.push(s)
end

local ON: { [string]: (Game.Session, any) -> () } = {
	grab = function(s, d)
		if d.gift then
			return
		end
		if Config.rarity(d.r).index >= 3 then
			progress(s, "rares", 1)
		end
		if Game.frenzy then
			progress(s, "night", 1)
		end
	end,
	deposit = function(s)
		progress(s, "home", 1)
	end,
	closeCall = function(s)
		progress(s, "close", 1)
	end,
	dodge = function(s)
		progress(s, "dodge", 1)
	end,
	ring = function(s)
		progress(s, "rings", 1)
	end,
	chumThrown = function(s)
		progress(s, "chum", 1)
	end,
}

function Quests.start()
	Game.questList = Quests.list
	table.insert(Game.trackers, function(player, kind, data)
		local fn = ON[kind]
		local s = Game.sessions[player]
		if fn and s then
			fn(s, data)
		end
	end)
end

return Quests
