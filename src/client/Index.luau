-- Creature Index: every rarity in every zone. Undiscovered ones are dark
-- "???" silhouettes; each discovery has a one-time reward to claim.
--   top:    Collected n / 30 + completion bar        [CLAIM ALL (n)]
--   tabs:   one per zone (n/5 found)
--   cards:  the zone's 5 creatures: rarity, model, name, reward, CLAIM

local Shared = game.ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Creatures = require(Shared.Creatures)
local UI = require(script.Parent.UI)
local State = require(script.Parent.State)
local Shop = require(script.Parent.Shop)

local Index = {}
local T = UI.T

local zoneId = Config.Zones[1].id

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

-- one creature: rarity chip, model (silhouette until found), name, reward, CLAIM
local function card(parent: Instance, d: any, r: any)
	local key = Config.indexKey(zoneId, r.id)
	local found = d.index[key] == true
	local claimed = d.claimed[key] == true
	local color = Shop.rarityColor(r.id)
	local accent = found and r.id ~= "Common" and color or nil
	local f = UI.card(parent, accent, { Size = UDim2.new(1 / #Config.Rarities, -10, 1, 0), LayoutOrder = r.index,
		BackgroundColor3 = found and T.navyLight or UI.dark(T.navyLight, 0.25) })
	UI.chip(f, r.id:upper(), found and color or UI.dark(color, 0.45), { Size = UDim2.new(1, -16, 0, 24), Position = UDim2.fromOffset(8, 8) })
	local tile = UI.inset(f, { Size = UDim2.new(1, -16, 0, 84), Position = UDim2.fromOffset(8, 40) })
	-- black light = solid silhouette for undiscovered
	Shop.viewport(tile, Creatures.build(r.id, nil, 1, zoneId), {
		Size = UDim2.new(1, -4, 1, -4), Position = UDim2.fromOffset(2, 2),
		Ambient = found and Color3.fromRGB(200, 200, 210) or Color3.new(0, 0, 0),
		LightColor = found and Color3.new(1, 1, 1) or Color3.new(0, 0, 0),
		ImageTransparency = found and 0 or 0.3,
	})
	UI.label(f, "body", found and Config.species(zoneId, r.id).name or "???", { Size = UDim2.new(1, -16, 0, 24), Position = UDim2.fromOffset(8, 128),
		TextColor3 = found and T.white or T.mute })
	local coins, speed = Config.indexReward(zoneId, r.id)
	UI.label(f, "meta", ("+$%s  +%s Speed"):format(UI.short(coins), UI.short(speed)), { Size = UDim2.new(1, -16, 0, 18), Position = UDim2.fromOffset(8, 154),
		TextColor3 = claimed and T.mute or UI.C.money })
	local bottom = { Size = UDim2.new(1, -16, 0, 48), Position = UDim2.new(0, 8, 1, -8), AnchorPoint = Vector2.new(0, 1) }
	if found and not claimed then
		UI.button(f, "CLAIM", T.green, function()
			State.action("claimIndex", key)
		end, bottom)
		UI.badge(f)
	elseif claimed then
		Shop.plate(f, "CLAIMED", T.mute, bottom)
	else
		Shop.plate(f, "NOT FOUND", UI.dark(T.mute, 0.2), bottom)
	end
end

function Index.open()
	local d = State.data
	if not d then
		return
	end
	local win, body = Shop.window("Index", T.blue, Vector2.new(780, 470), "Index")
	-- the world you're in (each world has its own Index)
	local zones = Config.worldZones(d.world)
	if not table.find(zones, Config.zoneById(zoneId)) then
		zoneId = zones[1].id
	end
	local allCount = #zones * #Config.Rarities

	local function render()
		d = State.data
		if not win.Parent then
			return
		end
		body:ClearAllChildren()

		-- progress: Collected n / 30
		local strip = UI.inset(body, { Size = UDim2.new(1, -216, 0, 56) })
		local n = total(d.index)
		UI.label(strip, "body", "Collected", { Size = UDim2.fromOffset(110, 22), Position = UDim2.new(0, 14, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5),
			TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = T.mute })
		UI.label(strip, "value", ("%d / %d"):format(n, allCount), { Size = UDim2.fromOffset(110, 32), Position = UDim2.new(0, 124, 0.5, 0),
			AnchorPoint = Vector2.new(0, 0.5), TextXAlignment = Enum.TextXAlignment.Left, Font = UI.NUMFONT })
		local _, fill, pct = UI.bar(strip, T.blue, { Size = UDim2.new(1, -262, 0, 26), Position = UDim2.new(0, 248, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5) })
		UI.setBar(fill, n / allCount, true)
		pct.Text = ("%d%%"):format(math.floor(n / allCount * 100))

		local all = unclaimedCount(d)
		local claimProps = { Size = UDim2.fromOffset(204, 56), Position = UDim2.new(1, 0, 0, 0), AnchorPoint = Vector2.new(1, 0) }
		if all > 0 then
			UI.button(body, ("CLAIM ALL (%d)"):format(all), T.green, function()
				State.action("claimIndexAll")
			end, claimProps)
		else
			Shop.plate(body, n > 0 and "ALL CLAIMED" or "FIND CREATURES", T.mute, claimProps)
		end

		-- zone tabs
		-- (a sideways-scrolling row: 9 zones don't fit at a readable width)
		local tabs = Instance.new("ScrollingFrame")
		tabs.Size = UDim2.new(1, 0, 0, 62)
		tabs.Position = UDim2.fromOffset(0, 66)
		tabs.BackgroundTransparency = 1
		tabs.BorderSizePixel = 0
		tabs.ScrollingDirection = Enum.ScrollingDirection.X
		tabs.AutomaticCanvasSize = Enum.AutomaticSize.X
		tabs.CanvasSize = UDim2.new()
		tabs.ScrollBarThickness = 4
		tabs.ScrollBarImageColor3 = T.mute
		tabs.ElasticBehavior = Enum.ElasticBehavior.Never
		tabs.Parent = body
		local tl = Instance.new("UIListLayout")
		tl.FillDirection = Enum.FillDirection.Horizontal
		tl.Padding = UDim.new(0, 8)
		tl.SortOrder = Enum.SortOrder.LayoutOrder
		tl.Parent = tabs
		for i, zone in zones do
			local active = zone.id == zoneId
			local evolveNeed = zone.evolve or 0
			local reached = d.speed >= zone.gate and (d.rebirths or 0) >= evolveNeed
			local color = active and T.blue or (reached and T.navyLight or UI.dark(T.navyLight, 0.3))
			local b = UI.button(tabs, zone.name, color, function()
				zoneId = zone.id
				render()
			end, { Size = UDim2.fromOffset(132, 56), LayoutOrder = i })
			local l = b:FindFirstChild("Label") :: TextLabel
			l.Size = UDim2.new(1, -12, 0, 22)
			l.Position = UDim2.new(0.5, 0, 0, 5)
			l.AnchorPoint = Vector2.new(0.5, 0)
			local c = count(d, zone.id)
			UI.label(b, "meta", reached and ("%d / %d"):format(c, #Config.Rarities)
				or ((d.rebirths or 0) < evolveNeed and ("Needs evolve %d"):format(evolveNeed))
				or ("%s speed"):format(UI.short(zone.gate)), {
				Size = UDim2.new(1, -12, 0, 17), Position = UDim2.new(0.5, 0, 0, 28), AnchorPoint = Vector2.new(0.5, 0), ZIndex = b.ZIndex + 1,
				TextColor3 = (c == #Config.Rarities and UI.C.money) or (active and T.white) or T.mute })
			if active then
				tabs.CanvasPosition = Vector2.new(math.max(0, (i - 3) * 140), 0) -- keep the open tab in view
			end
		end

		-- the zone's creatures
		local row = UI.frame(body, { Size = UDim2.new(1, 0, 1, -136), Position = UDim2.fromOffset(0, 136), BackgroundTransparency = 1 })
		local rl = Instance.new("UIListLayout")
		rl.FillDirection = Enum.FillDirection.Horizontal
		rl.Padding = UDim.new(0, 12)
		rl.SortOrder = Enum.SortOrder.LayoutOrder
		rl.Parent = row
		for _, r in Config.Rarities do
			card(row, d, r)
		end
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
