-- Player saves. DataStore with retries; if a load fails we never save over
-- the player's real data that session.

local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")

local Config = require(game.ReplicatedStorage.Shared.Config)

local Data = {}

export type Creature = { r: string, z: string, m: string? }
export type Profile = {
	speed: number,
	coins: number,
	rides: { [string]: boolean },
	ride: string,
	tank: { Creature },
	slots: number,
	rebirths: number,
	tut: number,
	shields: number,
	grabs: number,
	starter: boolean,
	boostUntil: number,
	luckUntil: number,
	receipts: { string },
	playtime: number,
	bestSpeed: number,
	index: { [string]: boolean }, -- "Zone:Rarity" discovered
	claimed: { [string]: boolean }, -- index rewards already taken
	lastSeen: number,
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
		tank = {},
		slots = Config.Tank.startSlots,
		rebirths = 0,
		tut = 0,
		shields = 0,
		grabs = 0,
		starter = false,
		boostUntil = 0,
		luckUntil = 0,
		receipts = {},
		playtime = 0,
		bestSpeed = 0,
		index = {},
		claimed = {},
		lastSeen = 0,
	}
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
	return p
end

-- returns profile, canSave
function Data.load(userId: number): (Profile, boolean)
	if not store then
		return Data.default(), false
	end
	for attempt = 1, 3 do
		local ok, result = pcall(function()
			return (store :: DataStore):GetAsync("p_" .. userId)
		end)
		if ok then
			return reconcile(result), true
		end
		warn(("[Data] load failed (%d/3) for %d: %s"):format(attempt, userId, tostring(result)))
		if RunService:IsStudio() then
			-- usually "API services not enabled": don't stall the join retrying
			warn("[Data] Studio: playing with a fresh profile (turn on API services in Game Settings to test saving)")
			break
		end
		task.wait(attempt)
	end
	return Data.default(), false
end

function Data.save(userId: number, profile: Profile): boolean
	profile.lastSeen = os.time()
	if not store then
		return false
	end
	for attempt = 1, 3 do
		local ok, err = pcall(function()
			(store :: DataStore):UpdateAsync("p_" .. userId, function()
				return profile
			end)
		end)
		if ok then
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
