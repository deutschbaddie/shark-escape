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
	DoubleOffline = function(s)
		s.profile.coins += s.offline * 2
		Game.notify(s.player, "collect", { amount = s.offline * 2 })
		s.offline = 0
		return true
	end,
	SpeedDeal = function(s)
		s.profile.dealBought = true
		s.profile.boostUntil = math.max(s.profile.boostUntil, os.time()) + 30 * 60
		return true
	end,
	Rescue = function(s)
		-- the creature the shark ate goes straight into your tank
		local c = s.lastLost
		s.lastLost = nil
		if c then
			Game.addCreature(s, { r = c.r, z = c.z, m = c.m, s = c.s })
		else
			Bubbles.give(s, "Rare") -- paid with nothing to rescue: still deliver something good
		end
		return true
	end,
	-- the starter ladder (each is offered once, in order; a repeat buy still delivers)
	StarterPack = function(s)
		s.profile.starter = true
		s.profile.starterTier = math.max(s.profile.starterTier, 1)
		s.profile.boostUntil = math.max(s.profile.boostUntil, os.time()) + 30 * 60
		s.profile.shields += 3
		Bubbles.give(s, "Rare")
		return true
	end,
	ProPack = function(s)
		s.profile.starterTier = math.max(s.profile.starterTier, 2)
		s.profile.boostUntil = math.max(s.profile.boostUntil, os.time()) + 60 * 60
		s.profile.luckUntil = math.max(s.profile.luckUntil, os.time()) + 30 * 60
		s.profile.shields += 5
		Bubbles.give(s, "Epic")
		return true
	end,
	MegaPack = function(s)
		s.profile.starterTier = math.max(s.profile.starterTier, 3)
		s.profile.boostUntil = math.max(s.profile.boostUntil, os.time()) + 120 * 60
		s.profile.luckUntil = math.max(s.profile.luckUntil, os.time()) + 60 * 60
		s.profile.shields += 10
		Bubbles.give(s, "Legendary", nil, 2.2)
		return true
	end,
}

-- speed / cash packs: Config.packAmount of your current speed gain or tank
-- income (the store card shows the same number)
for key, pack in Config.Packs do
	grants[key] = function(s)
		local p = s.profile
		local amount = Config.packAmount(key, Game.gain(s), Game.income(s))
		if pack.kind == "speed" then
			local before = p.speed
			p.speed += amount
			p.bestSpeed = math.max(p.bestSpeed, p.speed)
			for _, zone in Config.worldZones(p.world) do
				if zone.gate > 0 and before < zone.gate and p.speed >= zone.gate then
					Game.notify(s.player, "unlock", { zone = zone.id })
				end
			end
			Game.notify(s.player, "announce", { text = ("+%s Speed!"):format(Game.short(amount)) })
		else
			p.coins += amount
			Game.notify(s.player, "collect", { amount = amount })
		end
		return true
	end
end

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
