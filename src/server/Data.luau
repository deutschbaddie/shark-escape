-- Player saves. DataStore with retries; if a load fails we never save over
-- the player's real data that session.

local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")

local Config = require(game.ReplicatedStorage.Shared.Config)

local Data = {}

-- a caught creature; e = Active (in the tank, earning). id is per profile.
export type Creature = { r: string, z: string, m: string?, id: number?, e: boolean?, s: number? } -- s = size (weight x)
export type Profile = {
	speed: number,
	coins: number,
	rides: { [string]: boolean },
	ride: string,
	creatures: { Creature },
	nextId: number,
	codes: { [string]: boolean },
	slots: number,
	rebirths: number,
	tut: number,
	shields: number,
	grabs: number,
	starter: boolean,
	starterTier: number,
	dealBought: boolean, -- the one-time 3 R$ x2 Speed deal -- how far up Config.StarterLadder you've bought
	daily: { day: number, last: number },
	groupClaim: number,
	boostUntil: number,
	luckUntil: number,
	receipts: { string },
	playtime: number,
	bestSpeed: number,
	index: { [string]: boolean }, -- "Zone:Rarity" discovered
	claimed: { [string]: boolean }, -- index rewards already taken
	lastSeen: number,
	world: number, -- the world these top-level fields belong to
	net: number, -- Config.Nets tier (shared by every world)
	lockUntil: number, -- Tank Lock (os.time): no raids until then
	quests: { day: number, ids: { string }, n: { number }, bonus: boolean },
	bonks: number,
	noodle: number,
	wr: number, -- rebirths in this world (sets this run's goal; `rebirths` is the total)
	worlds: { [string]: { [string]: any } }, -- the other worlds' progress, stashed
}

local VERSION = "SharkEscape_v1"
local store: DataStore? = nil
pcall(function()
	store = DataStoreService:GetDataStore(VERSION)
end)

function Data.default(): Profile
	return {
		speed = 0,
		coins = 0,
		rides = { Noodle = true },
		ride = "Noodle",
		creatures = {},
		nextId = 1,
		codes = {},
		slots = Config.Tank.startSlots,
		rebirths = 0,
		tut = 0,
		shields = 0,
		grabs = 0,
		starter = false,
		starterTier = 0,
		dealBought = false,
		daily = { day = 1, last = 0 }, -- next day to claim (1..7), when you last claimed
		groupClaim = 0, -- last group chest claim (os.time)
		boostUntil = 0,
		luckUntil = 0,
		receipts = {},
		playtime = 0,
		bestSpeed = 0,
		index = {},
		claimed = {},
		lastSeen = 0,
		world = 1,
		net = 1,
		lockUntil = 0,
		quests = { day = 0, ids = {}, n = {}, bonus = false }, -- today's (Quests.luau)
		bonks = 0, -- creatures knocked loose with the noodle (Top Bonkers board)
		noodle = 1, -- Config.Noodles tier bought with coins
		wr = 0,
		worlds = {},
	}
end

-- progress that belongs to one world; everything else (Robux, daily, codes,
-- shields, total rebirths, playtime) is shared
Data.PER_WORLD = { "speed", "coins", "rides", "ride", "creatures", "slots", "index", "claimed", "wr" }

-- swap the world-specific fields so the profile's top level is world `w`
function Data.enterWorld(p: Profile, w: number)
	if p.world == w then
		return
	end
	local stash = {}
	local src: any = p
	for _, k in Data.PER_WORLD do
		stash[k] = src[k]
	end
	p.worlds[tostring(p.world)] = stash
	local saved = p.worlds[tostring(w)]
	local fresh: any = Data.default()
	local target: any = p
	for _, k in Data.PER_WORLD do
		local v = saved and saved[k]
		target[k] = if v ~= nil and typeof(v) == typeof(fresh[k]) then v else fresh[k]
	end
	p.worlds[tostring(w)] = nil
	p.world = w
	p.rides.Noodle = true
end

-- a world's rebirth count, wherever its progress currently lives
function Data.worldRebirths(p: Profile, w: number): number
	if p.world == w then
		return p.wr
	end
	local saved = p.worlds[tostring(w)]
	return saved and tonumber(saved.wr) or 0
end

local function reconcile(saved: any): Profile
	local p = Data.default()
	if type(saved) == "table" then
		for k, v in saved do
			if (p :: any)[k] ~= nil and typeof(v) == typeof((p :: any)[k]) then
				(p :: any)[k] = v
			end
		end
	end
	p.rides.Noodle = true
	if type(saved) == "table" and saved.world == nil then
		p.wr = p.rebirths -- saves from before worlds: all rebirths were in Shark Beach
	end
	if p.starter and p.starterTier < 1 then
		p.starterTier = 1 -- bought the Starter Pack before the ladder existed
	end
	-- v1 saves had a fixed "tank" list: those become Active creatures
	if type(saved) == "table" and type(saved.tank) == "table" and #p.creatures == 0 then
		for _, c in saved.tank do
			if type(c) == "table" and type(c.r) == "string" then
				table.insert(p.creatures, { r = c.r, z = c.z or "Lagoon", m = c.m, id = p.nextId, e = true })
				p.nextId += 1
			end
		end
	end
	for _, c in p.creatures do -- repair ids
		if type(c.id) ~= "number" then
			c.id = p.nextId
			p.nextId += 1
		end
	end
	return p
end

-- Session lock: the save carries _lock = { job, t } naming the server that
-- owns it. Loading takes the lock (waiting a little for another server
-- that's still saving that player); saving refuses to overwrite a save
-- another server has taken since, so a fast rejoin can never be rolled back
-- by the old server's late save. Autosave (every 2 min) keeps it fresh.
local LOCK_STALE = 300 -- seconds: an older lock belongs to a dead server
local LOCK_TRIES = 6 -- ~3 s apart, then take it anyway

local function key(userId: number): string
	return "p_" .. userId
end

local function lockedByOther(saved: any): boolean
	return type(saved) == "table" and type(saved._lock) == "table" and saved._lock.job ~= game.JobId
		and os.time() - (tonumber(saved._lock.t) or 0) < LOCK_STALE
end

-- returns profile, canSave
function Data.load(userId: number): (Profile, boolean)
	if not store then
		return Data.default(), false
	end
	for attempt = 1, LOCK_TRIES do
		local saved, waiting = nil, false
		local ok, err = pcall(function()
			(store :: DataStore):UpdateAsync(key(userId), function(old)
				if lockedByOther(old) and attempt < LOCK_TRIES then
					waiting = true
					return nil -- leave it alone, try again in a moment
				end
				saved = old
				local new = type(old) == "table" and old or {}
				new._lock = { job = game.JobId, t = os.time() }
				return new
			end)
		end)
		if ok and not waiting then
			return reconcile(saved), true
		end
		if not ok then
			warn(("[Data] load failed (%d/%d) for %d: %s"):format(attempt, LOCK_TRIES, userId, tostring(err)))
			if RunService:IsStudio() then
				-- usually "API services not enabled": don't stall the join retrying
				warn("[Data] Studio: playing with a fresh profile (turn on API services in Game Settings to test saving)")
				break
			end
		end
		task.wait(3)
	end
	return Data.default(), false
end

-- release = true when the player is leaving (frees the lock for the next server)
function Data.save(userId: number, profile: Profile, release: boolean?, stillOwned: (() -> boolean)?): boolean
	profile.lastSeen = os.time()
	if not store then
		return false
	end
	for attempt = 1, 3 do
		local stolen = false
		local ok, err = pcall(function()
			(store :: DataStore):UpdateAsync(key(userId), function(old)
				if stillOwned and not stillOwned() then
					return nil -- they left meanwhile: the leave save owns it now
				end
				if lockedByOther(old) then
					stolen = true
					return nil -- another server owns this player now: never overwrite it
				end
				local out = table.clone(profile) :: any
				out._lock = if release then nil else { job = game.JobId, t = os.time() }
				return out
			end)
		end)
		if ok then
			if stolen then
				warn(("[Data] %d is playing on another server: this server's save was skipped"):format(userId))
				return false
			end
			return true
		end
		warn(("[Data] save failed (%d/3) for %d: %s"):format(attempt, userId, tostring(err)))
		if RunService:IsStudio() then
			return false
		end
		task.wait(attempt)
	end
	return false
end

return Data
