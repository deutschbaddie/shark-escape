-- Funnels and events for the Creator Dashboard (Analytics -> Funnels /
-- Economy / Custom events). ANALYTICS.md explains every funnel, what a good
-- number looks like and what to change when a step drops.
--
--   Onboarding (once per new player)  Joined -> In the water -> First catch ->
--     In the tank -> First cash -> Shark drill -> First ride -> Coral Reef
--   Zones (every rebirth run)         Lagoon -> Coral Reef -> ... -> Lost City -> Rebirth
--   Rides (every rebirth run)         Pool Noodle -> Rubber Duck -> ... -> Golden Comet
--   Store (every Robux prompt)        Prompted -> Bought
--   Economy  coins in (tank cash, Index, chest, codes) and out (rides, tank slots)
--   Custom   SharkEaten, GateBlocked, Rebirth, DailyClaim, GroupChest, SessionMinutes

local AnalyticsService = game:GetService("AnalyticsService")
local HttpService = game:GetService("HttpService")
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")

local Shared = game.ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Game = require(script.Parent.Game)

local Analytics = {}

local F1 = Enum.AnalyticsCustomFieldKeys.CustomField01.Name
local F2 = Enum.AnalyticsCustomFieldKeys.CustomField02.Name

local function call(method: string, ...: any)
	local ok, err = pcall((AnalyticsService :: any)[method], AnalyticsService, ...)
	if not ok then
		warn("[Analytics]", method, err)
	end
end

----------------------------------------------------------------- onboarding
local ONBOARDING = { "Joined", "In the water", "First catch", "In the tank", "First cash", "Shark drill", "First ride", "Coral Reef" }
local newPlayers: { [Player]: number } = {} -- last onboarding step logged

local function onboard(player: Player, step: number)
	local last = newPlayers[player]
	if not last or step <= last then
		return
	end
	-- log any skipped steps too, so the funnel stays in order
	for i = last + 1, step do
		call("LogOnboardingFunnelStepEvent", player, i, ONBOARDING[i])
	end
	newPlayers[player] = step
	if step >= #ONBOARDING then
		newPlayers[player] = nil
	end
end

----------------------------------------------------------------- per-run funnels
local function runId(player: Player): string
	local s = Game.sessions[player]
	return ("%d-%d"):format(player.UserId, s and s.profile.rebirths or 0)
end

local function zonesStep(player: Player, index: number)
	local zone = Config.Zones[index]
	call("LogFunnelStepEvent", player, "Zones", runId(player), index, zone and zone.name or ("Zone " .. index))
end

local function ridesStep(player: Player, rideId: string)
	local ride = Config.ride(rideId)
	if ride and not ride.robux and ride.order then
		call("LogFunnelStepEvent", player, "Rides", runId(player), ride.order, ride.name)
	end
end

local function runStart(player: Player)
	zonesStep(player, 1)
	ridesStep(player, "Noodle")
end

----------------------------------------------------------------- economy
local function coins(player: Player, source: boolean, amount: number, kind: string, sku: string?)
	local s = Game.sessions[player]
	if not s or amount <= 0 then
		return
	end
	local flow = source and Enum.AnalyticsEconomyFlowType.Source or Enum.AnalyticsEconomyFlowType.Sink
	call("LogEconomyEvent", player, flow, "Coins", math.floor(amount), math.floor(s.profile.coins), kind, sku)
end
local T = Enum.AnalyticsEconomyTransactionType

----------------------------------------------------------------- events
local handlers: { [string]: (Player, { [string]: any }) -> () } = {}

handlers._join = function(player, d)
	if d.new then
		newPlayers[player] = 0
		onboard(player, 1)
	end
	runStart(player)
end
handlers._leave = function(player, d)
	call("LogCustomEvent", player, "SessionMinutes", math.floor(d.minutes * 10) / 10, { [F1] = newPlayers[player] and "new" or "returning" })
	newPlayers[player] = nil
end
handlers._water = function(player, d)
	if d.wet then
		onboard(player, 2)
	end
end
handlers._tut = function(player, d)
	if d.step >= 4 then
		onboard(player, 6) -- drill done (or skipped after two catches)
	end
end
handlers.grab = function(player)
	onboard(player, 3)
end
handlers.deposit = function(player)
	onboard(player, 4)
end
handlers.collect = function(player, d)
	onboard(player, 5)
	coins(player, true, d.amount or 0, T.Gameplay.Name, "TankCash")
end
handlers.ride = function(player, d)
	onboard(player, 7)
	ridesStep(player, d.id)
	coins(player, false, d.price or 0, T.Shop.Name, d.id)
end
handlers.unlock = function(player, d)
	local zone = Config.zoneById(d.zone)
	if zone then
		zonesStep(player, zone.index)
		if zone.index == 2 then
			onboard(player, 8)
		end
	end
end
handlers.rebirth = function(player, d)
	-- close the old run, then start the next one
	local s = Game.sessions[player]
	call("LogFunnelStepEvent", player, "Zones", ("%d-%d"):format(player.UserId, (d.rebirths or 1) - 1), #Config.Zones + 1, "Rebirth")
	call("LogCustomEvent", player, "Rebirth", d.rebirths or 0)
	if s then
		runStart(player)
	end
end
handlers.slot = function(player, d)
	coins(player, false, d.price or 0, T.Shop.Name, "TankSlot")
end
handlers.indexClaim = function(player, d)
	coins(player, true, d.coins or 0, T.Gameplay.Name, "IndexReward")
end
handlers.groupChest = function(player, d)
	if d.ok then
		coins(player, true, d.coins or 0, T.TimedReward.Name, "GroupChest")
		call("LogCustomEvent", player, "GroupChest", 1)
	end
end
handlers.daily = function(player, d)
	if d.ok then
		call("LogCustomEvent", player, "DailyClaim", d.day or 0)
	end
end
handlers.code = function(player, d)
	if d.ok then
		coins(player, true, d.coins or 0, T.Gameplay.Name, "Code")
	end
end
handlers.spat = function(player)
	local s = Game.sessions[player]
	local zone = s and s.lastPos and Config.zoneAt(s.lastPos.Z)
	call("LogCustomEvent", player, "SharkEaten", 1, { [F1] = zone and zone.name or "?" })
end
handlers.gate = function(player, d)
	local zone = Config.zoneById(d.zone)
	call("LogCustomEvent", player, "GateBlocked", 1, { [F1] = zone and zone.name or tostring(d.zone) })
end

----------------------------------------------------------------- store
local function storeName(isPass: boolean, id: number): string?
	for key, item in (isPass and Config.Passes or Config.Products) :: any do
		if item.id == id and id ~= 0 then
			return key
		end
	end
	return nil
end

local function store(player: Player?, isPass: boolean, id: number, bought: boolean)
	local key = player and storeName(isPass, id)
	if not (player and key) then
		return
	end
	local session = HttpService:GenerateGUID(false)
	local fields = { [F1] = key, [F2] = isPass and "Pass" or "Product" }
	call("LogFunnelStepEvent", player, "Store", session, 1, "Prompted", fields)
	if bought then
		call("LogFunnelStepEvent", player, "Store", session, 2, "Bought", fields)
	end
end

function Analytics.start()
	Game.onTrack = function(player, kind, data)
		local fn = handlers[kind]
		if fn then
			fn(player, data)
		end
	end
	MarketplaceService.PromptProductPurchaseFinished:Connect(function(userId, productId, bought)
		store(Players:GetPlayerByUserId(userId), false, productId, bought)
	end)
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, bought)
		store(player, true, passId, bought)
	end)
	Players.PlayerRemoving:Connect(function(player)
		task.defer(function()
			newPlayers[player] = nil
		end)
	end)
end

return Analytics
