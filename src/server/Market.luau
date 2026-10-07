-- Gamepasses and dev products. Receipts are verified in ProcessReceipt and
-- recorded on the profile so a retried receipt is never granted twice.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")

local Shared = game.ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Data = require(script.Parent.Data)
local Game = require(script.Parent.Game)
local Bubbles = require(script.Parent.Bubbles)

local Market = {}

local function passKeyById(id: number): string?
	for key, pass in Config.Passes do
		if pass.id == id and id ~= 0 then
			return key
		end
	end
	return nil
end

local function productKeyById(id: number): string?
	for key, prod in Config.Products do
		if prod.id == id and id ~= 0 then
			return key
		end
	end
	return nil
end

local function grantPass(s: Game.Session, key: string)
	s.passes[key] = true
	local ride = Config.ride(key)
	if ride and ride.robux then
		s.profile.ride = ride.id
		Game.attachRide(s)
	end
	if key == "BigTank" then
		Game.refreshTank(s)
	end
	s.dirty = true
end

local function loadPasses(s: Game.Session)
	for key, pass in Config.Passes do
		if pass.id ~= 0 then
			local ok, owns = pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, s.player.UserId, pass.id)
			if ok and owns then
				grantPass(s, key)
			end
		end
	end
end

local grants: { [string]: (Game.Session) -> boolean } = {
	Shield = function(s)
		s.profile.shields += 1
		return true
	end,
	SpeedBoost = function(s)
		s.profile.boostUntil = math.max(s.profile.boostUntil, os.time()) + 15 * 60
		return true
	end,
	LuckPotion = function(s)
		s.profile.luckUntil = math.max(s.profile.luckUntil, os.time()) + 10 * 60
		return true
	end,
	GoldenBubble = function(s)
		local total, roll = 0, math.random() * 100
		for _, pair in Config.GoldenBubbleOdds do
			total += pair[2]
			if roll <= total then
				Bubbles.give(s, pair[1])
				return true
			end
		end
		Bubbles.give(s, "Rare")
		return true
	end,
	StarterPack = function(s)
		-- the shop hides this after the first buy; if it's bought again anyway, still deliver it
		s.profile.starter = true
		s.profile.boostUntil = math.max(s.profile.boostUntil, os.time()) + 30 * 60
		s.profile.shields += 3
		Bubbles.give(s, "Rare")
		return true
	end,
}

MarketplaceService.ProcessReceipt = function(receipt)
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	local s = player and Game.sessions[player]
	if not s then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local rid = tostring(receipt.PurchaseId)
	if table.find(s.profile.receipts, rid) then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	local key = productKeyById(receipt.ProductId)
	local grant = key and grants[key]
	if not grant then
		warn("[Market] unknown product", receipt.ProductId)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	grant(s)
	table.insert(s.profile.receipts, rid)
	while #s.profile.receipts > 50 do
		table.remove(s.profile.receipts, 1)
	end
	-- save now so the grant survives a crash before the next autosave
	if s.canSave and not Data.save(s.player.UserId, s.profile) then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	Game.notify(s.player, "purchase", { name = Config.Products[key].name })
	s.dirty = true
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
	local s = Game.sessions[player]
	local key = passKeyById(passId)
	if s and key and purchased then
		grantPass(s, key)
		Game.notify(player, "purchase", { name = Config.Passes[key].name })
	end
end)

function Market.start()
	Game.onJoin = function(s)
		task.spawn(loadPasses, s)
	end
	for _, s in Game.sessions do
		task.spawn(loadPasses, s)
	end
end

return Market
