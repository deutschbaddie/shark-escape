-- Creature Index: every rarity in every zone. Undiscovered ones are black
-- "???" silhouettes; each discovery has a one-time reward to claim.
--   left: zone tabs   middle: 5 cards + progress   right: details + CLAIM

local Shared = game.ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Creatures = require(Shared.Creatures)
local UI = require(script.Parent.UI)
local State = require(script.Parent.State)
local Shop = require(script.Parent.Shop)

local Index = {}
local C = UI.C

local zoneId = Config.Zones[1].id
local selected = Config.Rarities[1].id

local function count(d: any, zid: string): number
	local n = 0
	for _, r in Config.Rarities do
		if d.index[Config.indexKey(zid, r.id)] then
			n += 1
		end
	end
	return n
end

local function total(map: { [string]: boolean }): number
	local n = 0
	for _ in map do
		n += 1
	end
	return n
end

local function unclaimedCount(d: any): number
	local n = 0
	for key in d.index do
		if not d.claimed[key] then
			n += 1
		end
	end
	return n
end

function Index.open()
	local d = State.data
	if not d then
		return
	end
	local win, body = Shop.window("📖 Creature Index", C.orange, Vector2.new(820, 480))

	local tabs = UI.inset(body, { Size = UDim2.new(0, 150, 1, -68), BackgroundColor3 = C.panel2 })
	local tabList = Instance.new("UIListLayout")
	tabList.Padding = UDim.new(0, 6)
	tabList.HorizontalAlignment = Enum.HorizontalAlignment.Center
	tabList.Parent = tabs
	local tp = Instance.new("UIPadding")
	tp.PaddingTop = UDim.new(0, 6)
	tp.Parent = tabs

	local mid = UI.inset(body, { Size = UDim2.new(1, -440, 1, -68), Position = UDim2.fromOffset(160, 0) })
	local right = UI.inset(body, { Size = UDim2.new(0, 260, 1, -68), Position = UDim2.new(1, 0, 0, 0), AnchorPoint = Vector2.new(1, 0) })

	local claimAll: TextButton
	claimAll = UI.button(body, "", C.blue, function()
		State.action("claimIndexAll")
	end, { Size = UDim2.new(1, -270, 0, 56), Position = UDim2.new(0, 0, 1, 0), AnchorPoint = Vector2.new(0, 1) })

	local function render()
		d = State.data
		if not win.Parent then
			return
		end
		-- tabs
		for _, k in tabs:GetChildren() do
			if k:IsA("GuiButton") then
				k:Destroy()
			end
		end
		for i, zone in Config.Zones do
			local active = zone.id == zoneId
			local b = UI.button(tabs, ("%s  %d/%d"):format(zone.name, count(d, zone.id), #Config.Rarities), active and zone.water or C.panel, function()
				zoneId = zone.id
				render()
			end, { Size = UDim2.new(1, -12, 0, 52), LayoutOrder = i })
			if zone.gate > d.speed then
				UI.setText(b, "🔒 " .. zone.name)
			end
		end

		-- cards
		mid:ClearAllChildren()
		UI.corner(mid, 8)
		UI.stroke(mid, C.ink, 3)
		local grid = UI.frame(mid, { Size = UDim2.new(1, -16, 1, -72), Position = UDim2.fromOffset(8, 8), BackgroundTransparency = 1 })
		local layout = Instance.new("UIGridLayout")
		layout.CellSize = UDim2.new(0.33, -6, 0.5, -6)
		layout.CellPadding = UDim2.fromOffset(8, 8)
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Parent = grid
		for _, r in Config.Rarities do
			local key = Config.indexKey(zoneId, r.id)
			local found = d.index[key] == true
			local card = Instance.new("TextButton")
			card.Text = ""
			card.AutoButtonColor = false
			card.LayoutOrder = r.index
			card.BackgroundColor3 = r.color
			card.Parent = grid
			UI.corner(card, 8)
			UI.stroke(card, r.id == selected and C.white or C.ink, r.id == selected and 4 or 3)
			UI.shade(card)
			UI.studs(card, { size = 18, alpha = 0.82 })
			local model = Creatures.build(r.id, nil, 1)
			-- black light = solid silhouette for undiscovered
			Shop.viewport(card, model, {
				Size = UDim2.new(1, -8, 1, -30), Position = UDim2.fromOffset(4, 26),
				Ambient = found and Color3.fromRGB(200, 200, 210) or Color3.new(0, 0, 0),
				LightColor = found and Color3.new(1, 1, 1) or Color3.new(0, 0, 0),
				ImageTransparency = found and 0 or 0.25,
			})
			UI.outlined(card, found and r.species or "???", { Size = UDim2.new(1, -8, 0, 24), Position = UDim2.fromOffset(4, 3), ZIndex = card.ZIndex + 2 })
			if found and not d.claimed[key] then
				UI.badge(card)
			end
			card.Activated:Connect(function()
				selected = r.id
				render()
			end)
		end
		local n = count(d, zoneId)
		local _, fill, lbl = UI.bar(mid, C.green, { Size = UDim2.new(1, -16, 0, 48), Position = UDim2.new(0, 8, 1, -8), AnchorPoint = Vector2.new(0, 1) })
		fill.Size = UDim2.fromScale(math.max(n / #Config.Rarities, 0.02), 1)
		lbl.Text = ("%d/%d"):format(n, #Config.Rarities)
		lbl.Font = UI.NUMFONT

		-- details
		right:ClearAllChildren()
		UI.corner(right, 8)
		UI.stroke(right, C.ink, 3)
		local r = Config.rarity(selected)
		local key = Config.indexKey(zoneId, selected)
		local found = d.index[key] == true
		local claimed = d.claimed[key] == true
		local view = UI.frame(right, { Size = UDim2.new(1, -16, 0, 190), Position = UDim2.fromOffset(8, 8), BackgroundColor3 = Color3.fromRGB(70, 74, 86) })
		UI.corner(view, 8)
		local g = Instance.new("UIGradient")
		g.Rotation = 90
		g.Color = ColorSequence.new(Color3.fromRGB(150, 150, 160), Color3.fromRGB(60, 60, 70))
		g.Parent = view
		Shop.viewport(view, Creatures.build(selected, nil, 1), {
			Size = UDim2.new(1, 0, 1, -64),
			Ambient = found and Color3.fromRGB(200, 200, 210) or Color3.new(0, 0, 0),
			LightColor = found and Color3.new(1, 1, 1) or Color3.new(0, 0, 0),
		})
		UI.outlined(view, found and r.species or "???", { Size = UDim2.new(1, -12, 0, 28), Position = UDim2.new(0, 6, 1, -62) })
		UI.outlined(view, r.id, { Size = UDim2.new(1, -12, 0, 24), Position = UDim2.new(0, 6, 1, -32), TextColor3 = r.color })

		local rewards = UI.frame(right, { Size = UDim2.new(1, -16, 1, -214), Position = UDim2.fromOffset(8, 206), BackgroundColor3 = Color3.fromRGB(20, 70, 30) })
		UI.corner(rewards, 8)
		UI.stroke(rewards, C.green, 2)
		UI.outlined(rewards, "Rewards:", { Size = UDim2.new(1, -16, 0, 20), Position = UDim2.fromOffset(8, 4), TextXAlignment = Enum.TextXAlignment.Left })
		local coins, speed = Config.indexReward(zoneId, selected)
		for i, spec in { { "💰", UI.short(coins), C.money }, { "⚡", "+" .. UI.short(speed), C.gold } } do
			local chip = UI.frame(rewards, { Size = UDim2.fromOffset(100, 46), Position = UDim2.new(0.5, (i == 1) and -104 or 4, 0, 28), BackgroundColor3 = Color3.fromRGB(40, 44, 54) })
			UI.corner(chip, 6)
			UI.stroke(chip, C.ink, 2)
			UI.text(chip, spec[1], { Size = UDim2.fromOffset(30, 30), Position = UDim2.fromOffset(4, 8) })
			UI.outlined(chip, spec[2], { Size = UDim2.new(1, -40, 0, 26), Position = UDim2.fromOffset(36, 10), TextColor3 = spec[3] })
		end
		local btnText = claimed and "CLAIMED ✅" or (found and "CLAIM!" or "🔒 FIND IT")
		UI.button(rewards, btnText, (found and not claimed) and C.green or C.panel, function()
			if found and not claimed then
				State.action("claimIndex", key)
			end
		end, { Size = UDim2.new(1, -20, 0, 50), Position = UDim2.new(0.5, 0, 1, -8), AnchorPoint = Vector2.new(0.5, 1) })

		local all = unclaimedCount(d)
		UI.setText(claimAll, all > 0 and ("📖 CLAIM ALL (%d)!"):format(all) or "📖 Find creatures to fill your Index!")
		claimAll.BackgroundColor3 = all > 0 and C.blue or C.panel
	end

	render()
	local conn
	conn = State.Changed:Connect(function(new, prev)
		if not win.Parent then
			conn:Disconnect()
			return
		end
		if not prev or unclaimedCount(new) ~= unclaimedCount(prev) or total(new.index) ~= total(prev.index) then
			render()
		end
	end)
end

return Index
