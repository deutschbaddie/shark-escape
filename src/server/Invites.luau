-- Friend invites: someone who joins from your invite (the "+" on the
-- Friends pill: SocialService:PromptGameInvite) gets a Rare, and so do you.
-- Roblox puts the inviter in the join data (ReferredByPlayerId). If the
-- inviter is in another server (or offline), their reward waits in a
-- DataStore and is handed over the next time they join. Once per new
-- player; at most MAX_REWARDS for any inviter.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")

local Shared = game.ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Game = require(script.Parent.Game)

local Invites = {}

local MAX_REWARDS = 10
local NEW_FOR = 600 -- seconds of playtime: only brand-new players count as invited

local store: DataStore? = nil
pcall(function()
	store = DataStoreService:GetDataStore("Invites_v1")
end)

-- a Rare from the Coral Reef, straight into the tank (no hands: it never
-- gets in the way of the first-session guide)
local function giveRare(s: Game.Session)
	local zones = Config.worldZones(1)
	Game.addCreature(s, { r = "Rare", z = (zones[2] or zones[1]).id, s = 1 })
	s.dirty = true
	Game.push(s)
end

local function rewardInviter(s: Game.Session, count: number, friend: string?)
	local p = s.profile
	local n = math.min(count, MAX_REWARDS - p.inviteRewards)
	if n <= 0 then
		return
	end
	for _ = 1, n do
		giveRare(s)
	end
	p.inviteRewards += n
	Game.notify(s.player, "inviteReward", { kind = "inviter", n = n, friend = friend })
end

local function onJoin(s: Game.Session)
	local player, p = s.player, s.profile
	-- 1) were they invited?
	local ok, jd = pcall(player.GetJoinData, player)
	local ref = ok and typeof(jd) == "table" and tonumber(jd.ReferredByPlayerId) or 0
	if ref and ref ~= 0 and ref ~= player.UserId and p.referredBy == 0 and p.playtime < NEW_FOR then
		p.referredBy = ref
		giveRare(s)
		local inviter = Players:GetPlayerByUserId(ref)
		Game.notify(player, "inviteReward", { kind = "invited", friend = inviter and inviter.DisplayName or nil })
		local is = inviter and Game.sessions[inviter]
		if is then
			rewardInviter(is, 1, player.DisplayName)
		elseif store then
			local st = store :: DataStore
			pcall(st.IncrementAsync, st, tostring(ref), 1)
		end
	end
	-- 2) friends they invited joined while they were away
	if store then
		local st = store :: DataStore
		local pending = 0
		pcall(st.UpdateAsync, st, tostring(player.UserId), function(old)
			pending = tonumber(old) or 0
			return pending > 0 and 0 or nil
		end)
		if pending > 0 and Game.sessions[player] == s then
			rewardInviter(s, pending, nil)
		end
	end
end

function Invites.start()
	table.insert(Game.trackers, function(player, kind)
		if kind == "_join" then
			local s = Game.sessions[player]
			if s then
				onJoin(s)
			end
		end
	end)
end

return Invites
