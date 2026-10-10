-- Rides window (the coin ladder, live 3D previews), the Robux store and the
-- HUD promo button.
-- Honest shop: real odds shown, unconfigured items say "Soon" instead of
-- prompting, nothing pops up on its own.
-- Also the small menu kit the other windows share (one window at a time,
-- standard popups, scrolling lists, rarity colors, creature thumbnails).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local MarketplaceService = game:GetService("MarketplaceService")
local TweenService = game:GetService("TweenService")

local Shared = game.ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Rides = require(Shared.Rides)
local Creatures = require(Shared.Creatures)
local Layout = require(Shared.Layout)
local UI = require(script.Parent.UI)
local State = require(script.Parent.State)
local Travel = require(script.Parent.Travel)

local Shop = {}
local T = UI.T
local player = Players.LocalPlayer

local gui: ScreenGui
local open: Frame? = nil
local spinners: { Model } = {}

local function closeAll()
	if open then
		open:Destroy()
		open = nil
	end
	table.clear(spinners)
end

Shop.closeAll = closeAll

-- one window at a time; Index and popups share this
function Shop.window(title: string, color: Color3, size: Vector2?, iconName: string?): (Frame, Frame)
	closeAll()
	local f, body = UI.window(gui, title, color, size or Vector2.new(760, 470), closeAll, iconName)
	open = f
	return f, body
end

-- the standard confirmation popup (UI.popup), sharing the one-window rule
function Shop.popup(opts: { [string]: any }): Frame
	closeAll()
	local f = UI.popup(gui, opts)
	open = f
	return f
end

----------------------------------------------------------------- menu kit
-- rarity accents: Common plain, Uncommon green, Rare blue, Epic purple, Legendary gold
local RARITY = { Common = T.mute, Uncommon = T.green, Rare = T.blue, Epic = T.purple, Legendary = T.gold,
	Mythic = Config.rarity("Mythic").color }
function Shop.rarityColor(id: string?): Color3
	return RARITY[id or ""] or T.mute
end

-- vertical scrolling list: thin light scrollbar, grows with its content and
-- leaves room at the bottom so the last card is never clipped
function Shop.list(parent: Instance, props: { [string]: any }?, gap: number?): ScrollingFrame
	local scroll = Instance.new("ScrollingFrame")
	scroll.Size = UDim2.fromScale(1, 1)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 6
	scroll.ScrollBarImageColor3 = T.white
	scroll.ScrollBarImageTransparency = 0.45
	scroll.ScrollingDirection = Enum.ScrollingDirection.Y
	scroll.VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.CanvasSize = UDim2.new()
	if props then
		for k, v in props do
			(scroll :: any)[k] = v
		end
	end
	scroll.Parent = parent
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 4)
	pad.PaddingBottom = UDim.new(0, 16)
	pad.PaddingLeft = UDim.new(0, 4)
	pad.PaddingRight = UDim.new(0, 8)
	pad.Parent = scroll
	if gap then
		local layout = Instance.new("UIListLayout")
		layout.Padding = UDim.new(0, gap)
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Parent = scroll
	end
	return scroll
end

-- a flat, non-clickable plate where a button would be (OWNED, SOON, RIDING)
function Shop.plate(parent: Instance, text: string, color: Color3, props: { [string]: any }?): Frame
	local f = UI.frame(parent, { BackgroundColor3 = T.navyDark, BackgroundTransparency = 0.2, Size = UDim2.fromOffset(160, 48) })
	if props then
		for k, v in props do
			(f :: any)[k] = v
		end
	end
	UI.corner(f, UI.R.button)
	UI.label(f, "body", text, { Name = "Label", Size = UDim2.new(1, -16, 1, -16), Position = UDim2.fromOffset(8, 8), TextColor3 = color })
	return f
end

-- a creature on a dark rounded tile (Tank, Sell)
function Shop.thumb(parent: Instance, c: any, props: { [string]: any }?): Frame
	local tile = UI.inset(parent, { Size = UDim2.fromOffset(64, 64) })
	if props then
		for k, v in props do
			(tile :: any)[k] = v
		end
	end
	Shop.viewport(tile, Creatures.build(c.r, c.m, 1, c.z), { Size = UDim2.new(1, -4, 1, -4), Position = UDim2.fromOffset(2, 2) }, false)
	return tile
end

function Shop.viewport(parent: Instance, model: Model, props: { [string]: any }?, spin: boolean?): ViewportFrame
	local vf = Instance.new("ViewportFrame")
	vf.Size = UDim2.new(1, -12, 0, 104)
	vf.Position = UDim2.fromOffset(6, 6)
	vf.BackgroundTransparency = 1
	vf.Ambient = Color3.fromRGB(200, 200, 210)
	vf.LightDirection = Vector3.new(-1, -2, -1)
	if props then
		for k, v in props do
			(vf :: any)[k] = v
		end
	end
	vf.Parent = parent
	local cam = Instance.new("Camera")
	cam.FieldOfView = 40
	cam.Parent = vf
	vf.CurrentCamera = cam
	model:PivotTo(CFrame.new())
	model.Parent = vf
	local _, size = model:GetBoundingBox()
	local r = math.max(size.X, size.Y, size.Z)
	cam.CFrame = CFrame.lookAt(Vector3.new(r * 0.9, r * 0.7, -r * 1.3), Vector3.new(0, -0.3, 0))
	if spin ~= false then
		table.insert(spinners, model)
	end
	return vf
end

-- a model on a dark tile, filling it
local function stage(parent: Instance, model: Model, props: { [string]: any }, dim: boolean?): Frame
	local tile = UI.inset(parent, props)
	Shop.viewport(tile, model, { Size = UDim2.new(1, -8, 1, -8), Position = UDim2.fromOffset(4, 4), ImageTransparency = dim and 0.35 or 0 })
	return tile
end

----------------------------------------------------------------- rides
local ORANGE_TEXT = UI.light(T.orange, 0.35)

-- what the rides window shows that can change: next ride + what you can afford
local function ridesKey(d: any): string
	local nn = Config.Noodles[(d.noodle or 1) + 1]
	local key = d.ride .. "|" .. tostring(Shop.atRideShop()) .. "|n" .. tostring(d.noodle) .. tostring(nn and d.coins >= nn.price)
		.. tostring(d.passes and d.passes.GoldenNoodle)
	for _, ride in Config.Rides do
		if d.rides[ride.id] then
			key ..= ride.id
		elseif not ride.robux then
			return key .. ">" .. ride.id .. tostring(d.coins >= ride.price)
		end
	end
	return key
end

local function perkText(ride: any): string
	if ride.robux then
		return ("x%s Speed gain"):format(tostring(ride.mult))
	end
	return ("+%d Speed/s"):format(ride.gain or 0)
end

-- the buy action for the next coin ride: BUY / GO TO SHOP / NEED $X
local function buyButton(parent: Instance, ride: any, d: any, props: { [string]: any }): TextButton
	local can = d.coins >= ride.price
	if can and not Shop.atRideShop() then
		return UI.button(parent, "GO TO SHOP", T.blue, function()
			Shop.goToRideShop()
		end, props)
	end
	local text = can and ("BUY  $" .. UI.short(ride.price)) or ("NEED $" .. UI.short(ride.price - d.coins))
	return UI.button(parent, text, can and T.green or T.navyLight, function()
		State.action("buyRide", ride.id)
	end, props)
end

function Shop.openRides()
	local d = State.data
	if not d then
		return
	end
	local _, body = Shop.window("Rides", T.orange, Vector2.new(760, 470), "Rides")
	-- coin progress bars update live (no rebuild while you earn)
	local progress: { { fill: Frame, label: TextLabel, price: number } } = {}
	local function track(fill: Frame, label: TextLabel, price: number)
		table.insert(progress, { fill = fill, label = label, price = price })
	end
	local function updateProgress(instant: boolean?)
		local coins = State.data and State.data.coins or 0
		for _, p in progress do
			UI.setBar(p.fill, coins / math.max(p.price, 1), instant)
			p.label.Text = ("$%s / $%s"):format(UI.short(math.min(coins, p.price)), UI.short(p.price))
		end
	end

	local function refresh()
		if not open then
			return
		end
		body:ClearAllChildren()
		table.clear(spinners)
		table.clear(progress)
		d = State.data
		local nextRide: any = nil
		for _, ride in Config.Rides do
			if not ride.robux and not d.rides[ride.id] then
				nextRide = ride
				break
			end
		end

		-- featured: the ride you're saving for (or the one you're riding)
		local hero = nextRide or Config.ride(d.ride) or Config.Rides[1]
		local isNext = hero == nextRide
		local accent = isNext and T.orange or T.green
		local feat = UI.card(body, accent, { Name = "Featured", Size = UDim2.new(1, 0, 0, 140) })
		stage(feat, Rides.build(hero.id), { Size = UDim2.fromOffset(160, 116), Position = UDim2.fromOffset(12, 12) })
		UI.chip(feat, isNext and "NEXT RIDE" or "EQUIPPED", accent, { Size = UDim2.fromOffset(120, 26), Position = UDim2.fromOffset(188, 14) })
		UI.label(feat, "value", hero.name, { Size = UDim2.new(1, -428, 0, 34), Position = UDim2.fromOffset(188, 44), TextXAlignment = Enum.TextXAlignment.Left })
		UI.label(feat, "body", perkText(hero), { Size = UDim2.new(1, -428, 0, 24), Position = UDim2.fromOffset(188, 80), TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = ORANGE_TEXT })
		local btnProps = { Size = UDim2.fromOffset(212, 68), Position = UDim2.new(1, -16, 0.5, 0), AnchorPoint = Vector2.new(1, 0.5) }
		if isNext then
			local _, fill, label = UI.bar(feat, d.coins >= hero.price and T.green or T.orange,
				{ Size = UDim2.new(1, -428, 0, 24), Position = UDim2.fromOffset(188, 108) })
			track(fill, label, hero.price)
			buyButton(feat, hero, d, btnProps)
		else
			UI.label(feat, "body", "Every coin ride owned!", { Size = UDim2.new(1, -428, 0, 22), Position = UDim2.fromOffset(188, 108),
				TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = T.mute })
			Shop.plate(feat, "RIDING", T.green, btnProps)
		end

		-- every ride
		local scroll = Shop.list(body, { Size = UDim2.new(1, 8, 1, -152), Position = UDim2.fromOffset(-4, 152) })
		local grid = Instance.new("UIGridLayout")
		grid.CellSize = UDim2.new(1 / 3, -8, 0, 204)
		grid.CellPadding = UDim2.fromOffset(12, 12)
		grid.SortOrder = Enum.SortOrder.LayoutOrder
		grid.Parent = scroll
		-- first: your bonk noodle (and the next one up)
		do
			local golden = d.passes and d.passes.GoldenNoodle
			local tier = Config.Noodles[math.clamp(d.noodle or 1, 1, #Config.Noodles)]
			local now = golden and Config.Noodles[#Config.Noodles] or tier
			local nn = not golden and Config.Noodles[(d.noodle or 1) + 1] or nil
			if nn and nn.pass then
				nn = nil
			end
			local f = UI.card(scroll, T.pink, { LayoutOrder = -2 })
			stage(f, Rides.noodle(now.color), { Size = UDim2.new(1, -16, 0, 92), Position = UDim2.fromOffset(8, 8) })
			UI.chip(f, "BONK NOODLE", T.pink, { Size = UDim2.fromOffset(130, 24), Position = UDim2.fromOffset(14, 14), ZIndex = f.ZIndex + 2 })
			UI.label(f, "body", now.name, { Size = UDim2.new(1, -20, 0, 24), Position = UDim2.fromOffset(10, 104), TextXAlignment = Enum.TextXAlignment.Left })
			UI.label(f, "meta", nn and ("Next: reach %d · every %gs"):format(nn.reach, nn.cooldown) or ("Reach %d · every %gs"):format(now.reach, now.cooldown),
				{ Size = UDim2.new(1, -20, 0, 20), Position = UDim2.fromOffset(10, 128), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = ORANGE_TEXT })
			local bottom = { Size = UDim2.new(1, -16, 0, 48), Position = UDim2.new(0, 8, 1, -8), AnchorPoint = Vector2.new(0, 1) }
			if nn then
				UI.button(f, ("UPGRADE $%s"):format(UI.short(nn.price)), d.coins >= nn.price and T.green or T.navyLight, function()
					State.action("buyNoodle")
				end, bottom)
			else
				Shop.plate(f, "MAX", T.mute, bottom)
			end
			-- the Golden Noodle (game pass)
			local gp = Config.Passes.GoldenNoodle
			if gp and not golden then
				local g = UI.card(scroll, T.gold, { LayoutOrder = -1 })
				local gold = Config.Noodles[#Config.Noodles]
				stage(g, Rides.noodle(gold.color), { Size = UDim2.new(1, -16, 0, 92), Position = UDim2.fromOffset(8, 8) })
				UI.chip(g, "PREMIUM", T.gold, { Size = UDim2.fromOffset(100, 24), Position = UDim2.fromOffset(14, 14), ZIndex = g.ZIndex + 2 })
				UI.label(g, "body", gold.name, { Size = UDim2.new(1, -20, 0, 24), Position = UDim2.fromOffset(10, 104), TextXAlignment = Enum.TextXAlignment.Left })
				UI.label(g, "meta", ("Reach %d · every %gs · shiny"):format(gold.reach, gold.cooldown),
					{ Size = UDim2.new(1, -20, 0, 20), Position = UDim2.fromOffset(10, 128), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = T.gold })
				if gp.id ~= 0 then
					UI.button(g, "R$ " .. gp.price, T.gold, function()
						MarketplaceService:PromptGamePassPurchase(player, gp.id)
					end, bottom)
				else
					Shop.plate(g, "SOON", T.mute, bottom)
				end
			end
		end
		for _, ride in Config.Rides do
			local owned = d.rides[ride.id] == true
			local equipped = d.ride == ride.id
			local pass = ride.robux and Config.Passes[ride.robux]
			local locked = not owned and not ride.robux and ride ~= nextRide
			local cardAccent = (equipped and T.green) or (ride.robux and T.gold) or (ride == nextRide and T.orange) or nil
			local f = UI.card(scroll, cardAccent, { LayoutOrder = ride.order })
			stage(f, Rides.build(ride.id), { Size = UDim2.new(1, -16, 0, 92), Position = UDim2.fromOffset(8, 8) }, locked)
			local chip = (equipped and { "EQUIPPED", T.green }) or (ride.robux and not owned and { "PREMIUM", T.gold })
				or (ride == nextRide and { "NEXT", T.orange }) or nil
			if chip then
				UI.chip(f, chip[1], chip[2], { Size = UDim2.fromOffset(100, 24), Position = UDim2.fromOffset(14, 14), ZIndex = f.ZIndex + 2 })
			end
			if locked then
				UI.icon(f, "Lock", { Size = UDim2.fromOffset(30, 30), Position = UDim2.new(1, -14, 0, 14), AnchorPoint = Vector2.new(1, 0), ZIndex = f.ZIndex + 2 })
			end
			UI.label(f, "body", ride.name, { Size = UDim2.new(1, -20, 0, 24), Position = UDim2.fromOffset(10, 104), TextXAlignment = Enum.TextXAlignment.Left })
			UI.label(f, "meta", perkText(ride), { Size = UDim2.new(1, -20, 0, 20), Position = UDim2.fromOffset(10, 128), TextXAlignment = Enum.TextXAlignment.Left,
				TextColor3 = ride.robux and T.gold or ORANGE_TEXT })
			local bottom = { Size = UDim2.new(1, -16, 0, 48), Position = UDim2.new(0, 8, 1, -8), AnchorPoint = Vector2.new(0, 1) }
			if equipped then
				Shop.plate(f, "RIDING", T.green, bottom)
			elseif owned then
				UI.button(f, "EQUIP", T.orange, function()
					State.action("equipRide", ride.id)
				end, bottom)
			elseif pass then
				if pass.id ~= 0 then
					UI.button(f, "R$ " .. pass.price, T.gold, function()
						MarketplaceService:PromptGamePassPurchase(player, pass.id)
					end, bottom)
				else
					Shop.plate(f, "SOON", T.mute, bottom)
				end
			elseif ride == nextRide then
				buyButton(f, ride, d, bottom)
			else
				-- locked: what it costs and how close you are
				UI.label(f, "meta", "Requires $" .. UI.short(ride.price), { Size = UDim2.new(1, -20, 0, 18), Position = UDim2.new(0, 10, 1, -50),
					TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = T.mute })
				local _, fill, label = UI.bar(f, T.orange, { Size = UDim2.new(1, -20, 0, 24), Position = UDim2.new(0, 10, 1, -10), AnchorPoint = Vector2.new(0, 1) })
				track(fill, label, ride.price)
			end
		end
		updateProgress(true)
	end
	refresh()
	local conn
	conn = State.Changed:Connect(function(new, prev)
		if not open then
			conn:Disconnect()
			return
		end
		-- only rebuild when something visible changed; bars just slide
		if not prev or ridesKey(new) ~= ridesKey(prev) then
			refresh()
		else
			updateProgress()
		end
	end)
end

----------------------------------------------------------------- robux shop
-- The store in the Steal-an-Egg format, in our style: one wide window of
-- sections (FEATURED banners, then grids of big product cards: art on a soft
-- glow, the value in big outlined text, the price) and a category bar beside
-- it that scrolls to each section. Speed / cash packs show what they give you
-- right now (Config.packAmount, the same formula the server grants).
-- Items without an id yet show SOON instead of prompting.

local STORE = Vector2.new(800, 480)
local SIDE_W = 100 -- category bar, outside the window on its right
local GAP = 12
local BANNER_H = 164
local CATEGORIES = {
	{ id = "Featured", icon = "Sparkle", color = T.pink },
	{ id = "Speed", icon = "Sneaker", color = T.orange },
	{ id = "Money", icon = "Cash", color = T.green },
	{ id = "Passes", icon = "Crown", color = T.purple },
	{ id = "Boosts", icon = "Potion", color = T.blue },
}
local PASSES = { "AutoCollect", "LuckyNet", "BigTank", "VIP", "GoldDuck", "SharkBoard", "RainbowSki" }
local BOOSTS = { "Rescue", "Shield", "TankLock", "SpeedBoost", "LuckPotion", "GoldenBubble", "DoubleOffline" }
local SPEED_TEXT = UI.light(T.gold, 0.2)
local MONEY_TEXT = UI.C.money

local function phoneLayout(): boolean
	return UI.TOUCH and workspace.CurrentCamera.ViewportSize.Y < 600
end

-- the art for a store item: its own icon once uploaded, else a stand-in
-- (speed / cash packs borrow the Speed and MoneyBag art)
local function art(key: string, def: any): string
	local own = tostring(Config.Icons.ids[def.iconName] or ""):match("%d+")
	local pack = Config.Packs[key]
	if own or not pack then
		return def.iconName
	end
	return pack.kind == "speed" and "Speed" or "MoneyBag"
end

-- soft radial glow behind product art: stacked translucent discs
local function glow(parent: Instance, color: Color3, size: number, props: { [string]: any })
	local holder = UI.frame(parent, { Name = "Glow", Size = UDim2.fromOffset(size, size), BackgroundTransparency = 1 })
	for k, v in props do
		(holder :: any)[k] = v
	end
	for _, s in { 1, 0.84, 0.68, 0.52, 0.36 } do
		local disc = UI.frame(holder, { Size = UDim2.fromScale(s, s), Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = color, BackgroundTransparency = 0.88, ZIndex = holder.ZIndex })
		UI.corner(disc, size)
	end
	return holder
end

-- big outlined text (past the type scale's caps: "x1 > x2", hero values)
local function bigText(parent: Instance, text: string, max: number, props: { [string]: any }): TextLabel
	local l = UI.label(parent, "hero", text, props)
	local c = l:FindFirstChildOfClass("UITextSizeConstraint")
	if c then
		c.MaxTextSize = max
	end
	local s = l:FindFirstChildOfClass("UIStroke")
	if s then
		s.Thickness = 3
	end
	return l
end

function Shop.buy(kind: string, def: any)
	if def.id == 0 then
		return
	end
	if kind == "pass" then
		MarketplaceService:PromptGamePassPurchase(player, def.id)
	else
		MarketplaceService:PromptProductPurchase(player, def.id)
	end
end

-- green "R$ 79" (gold for passes), or a flat OWNED / SOON plate
local function priceButton(parent: Instance, kind: string, def: any, owned: boolean, props: { [string]: any }): GuiObject
	if owned then
		return Shop.plate(parent, "OWNED", T.green, props)
	elseif def.id == 0 then
		return Shop.plate(parent, "SOON", T.mute, props)
	end
	local b = UI.button(parent, "R$ " .. def.price, kind == "pass" and T.gold or T.green, function()
		Shop.buy(kind, def)
	end, props)
	local l = b:FindFirstChild("Label") :: TextLabel
	l.Font = UI.NUMFONT
	return b
end

-- the one offer the HUD promotes (after Config.SHOP_UNLOCK_SECONDS): the next
-- starter-ladder pack, else 2x Speed, else 2x Cash. Returns key, kind.
function Shop.offer(d: any): (string?, string?)
	if not d or d.playtime < Config.SHOP_UNLOCK_SECONDS then
		return nil, nil
	end
	-- the 3 R$ deal first: the cheapest possible first purchase
	if not d.dealBought and Config.Products.SpeedDeal.id ~= 0 then
		return "SpeedDeal", "product"
	end
	if d.starterNext and Config.Products[d.starterNext] then
		return d.starterNext, "product"
	end
	for _, key in { "TwoXSpeed", "TwoXCoins" } do
		if not d.passes[key] then
			return key, "pass"
		end
	end
	return nil, nil
end
local OFFER_TITLE = { TwoXSpeed = "x2 Speed", TwoXCoins = "x2 Cash", SpeedDeal = "x2 Speed" }

-- The HUD promo under the Shop button: the offer's art glowing over a cyan
-- button, "x2 Speed" and "ONLY 399 R$" on it. A tap prompts the purchase (or
-- opens the store while the item has no id). Returns the button and
-- update(d) for each state change.
function Shop.promo(parent: Instance, props: { [string]: any }): (TextButton, (any) -> ())
	local b: TextButton
	b = UI.button(parent, "", UI.C.sky, function()
		local key, kind = b:GetAttribute("Key"), b:GetAttribute("Kind")
		local def = key and (if kind == "pass" then Config.Passes[key] else Config.Products[key])
		if def and def.id ~= 0 then
			Shop.buy(kind, def)
		else
			Shop.openStore("Featured")
		end
	end, props)
	b.Name = "Promo"
	b.Visible = false
	local face = b:FindFirstChild("Face") :: Frame
	local h = b.Size.Y.Offset
	-- icon on the left inside the button (like Index / Rides), title and
	-- price stacked to its right: nothing hangs over the buttons around it
	local textX = math.floor(h * 0.95)
	local label = b:FindFirstChild("Label") :: TextLabel
	label.AnchorPoint = Vector2.new(0, 0)
	label.Size = UDim2.new(1, -textX - 8, 0.52, 0)
	label.Position = UDim2.new(0, textX, 0.06, 0)
	local sub = UI.outlined(b, "", { Name = "Sub", Size = UDim2.new(1, -textX - 8, 0.34, 0), Position = UDim2.new(0, textX, 0.58, 0),
		TextColor3 = T.gold, ZIndex = b.ZIndex + 2 })
	local function update(d: any)
		local key, kind = Shop.offer(d)
		-- (new players get 10 minutes to fall for the game before any offer)
		b.Visible = key ~= nil and (d.playtime or 0) >= 600
		if not key then
			b:SetAttribute("Key", nil)
			return
		end
		local def = if kind == "pass" then Config.Passes[key] else Config.Products[key]
		if b:GetAttribute("Key") == key then
			return
		end
		b:SetAttribute("Key", key)
		b:SetAttribute("Kind", kind)
		local old = face:FindFirstChild("Icon")
		if old then
			old:Destroy()
		end
		UI.icon(face, art(key, def), { Size = UDim2.fromOffset(h * 0.8, h * 0.8), Position = UDim2.new(0, math.floor(h * 0.08), 0.5, 0), AnchorPoint = Vector2.new(0, 0.5),
			ZIndex = b.ZIndex + 1 })
		UI.setText(b, OFFER_TITLE[key] or def.name)
		sub.Text = ("ONLY %d R$"):format(def.price)
		UI.pop(b, 1.12)
	end
	return b, update
end

-- the codes row (free rewards from videos / socials)
local function codesCard(parent: Instance, y: number, h: number)
	local codes = UI.card(parent, T.pink, { Name = "Codes", Size = UDim2.new(1, 0, 0, h), Position = UDim2.fromOffset(0, y) })
	UI.icon(codes, "Gift", { Size = UDim2.fromOffset(56, 56), Position = UDim2.new(0, 10, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5) })
	UI.label(codes, "body", "CODES", { Size = UDim2.fromOffset(150, 26), Position = UDim2.new(0, 76, 0.5, -14), AnchorPoint = Vector2.new(0, 0.5),
		TextXAlignment = Enum.TextXAlignment.Left })
	UI.label(codes, "meta", Config.LikeGoal > 0 and ("New code at %s likes"):format(UI.short(Config.LikeGoal)) or "Free rewards", { Size = UDim2.fromOffset(150, 20), Position = UDim2.new(0, 76, 0.5, 12), AnchorPoint = Vector2.new(0, 0.5),
		TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = T.mute })
	local box = Instance.new("TextBox")
	box.Size = UDim2.new(1, -404, 0, 48)
	box.Position = UDim2.new(0, 236, 0.5, 0)
	box.AnchorPoint = Vector2.new(0, 0.5)
	box.BackgroundColor3 = T.navyDark
	box.PlaceholderText = "Enter code"
	box.PlaceholderColor3 = T.mute
	box.Text = ""
	box.Font = UI.FONT
	box.TextScaled = true
	box.TextColor3 = T.white
	box.ClearTextOnFocus = false
	box.Parent = codes
	UI.corner(box, UI.R.button)
	UI.stroke(box, T.line, UI.S.subtle)
	local bl = Instance.new("UITextSizeConstraint")
	bl.MaxTextSize = UI.TYPE.body[1]
	bl.Parent = box
	local bp = Instance.new("UIPadding")
	bp.PaddingLeft, bp.PaddingRight = UDim.new(0, 12), UDim.new(0, 12)
	bp.PaddingTop, bp.PaddingBottom = UDim.new(0, 10), UDim.new(0, 10)
	bp.Parent = box
	UI.button(codes, "REDEEM", T.green, function()
		if box.Text ~= "" then
			State.action("code", box.Text)
			box.Text = ""
		end
	end, { Size = UDim2.fromOffset(144, 52), Position = UDim2.new(1, -10, 0.5, 0), AnchorPoint = Vector2.new(1, 0.5) })
end

-- what the store shows that can change (rebuild when it does; pack values just update)
local function storeKey(d: any): string
	local key = tostring(d.starterNext) .. "|" .. tostring((d.offline or 0) > 0) .. "|" .. tostring(d.dealBought)
	for _, k in { "TwoXSpeed", "TwoXCoins", table.unpack(PASSES) } do
		if d.passes[k] then
			key ..= "|" .. k
		end
	end
	return key
end

-- live value of a card ("+150K SPEED", "+$2.3M", or the item's name)
local function cardValue(key: string, def: any, d: any): (string, Color3)
	local pack = Config.Packs[key]
	if pack then
		local n = Config.packAmount(key, d.gain or 0, d.income or 0)
		if pack.kind == "speed" then
			return ("+%s SPEED"):format(UI.short(n)), SPEED_TEXT
		end
		return "+$" .. UI.short(n), MONEY_TEXT
	elseif key == "DoubleOffline" and (d.offline or 0) > 0 then
		return "+$" .. UI.short(d.offline * 2), MONEY_TEXT
	end
	return def.name, T.white
end

function Shop.openStore(section: string?)
	local d = State.data
	if not d then
		return
	end
	local phone = phoneLayout()
	local cols = phone and 2 or 3
	local cardH = 218
	local win, body = Shop.window("Shop", T.gold, STORE, "Shop")
	-- the window and its category bar are centered together
	win.Position = UDim2.new(0.5, -(SIDE_W + GAP) / 2, 0.52, 0)
	local viewH = STORE.Y - 98 -- the body's height (UI.window)

	local scroll: ScrollingFrame? = nil
	local offsets: { [string]: number } = {}
	local values: { { label: TextLabel, key: string, def: any } } = {}
	local entries: { [string]: { label: TextLabel, icon: GuiObject } } = {}
	local canvasH = 0

	local function maxScroll(): number
		return math.max(0, canvasH - viewH)
	end
	local current = ""
	local function highlight()
		if not scroll then
			return
		end
		local y = scroll.CanvasPosition.Y + 40
		local at = "Featured"
		for _, cat in CATEGORIES do
			if offsets[cat.id] and offsets[cat.id] <= y then
				at = cat.id
			end
		end
		if scroll.CanvasPosition.Y >= maxScroll() - 2 then
			at = CATEGORIES[#CATEGORIES].id -- scrolled to the end: the last section
		end
		if at == current then
			return
		end
		current = at
		for id, e in entries do
			e.label.TextColor3 = id == at and T.gold or T.white
			e.icon.Size = id == at and UDim2.fromOffset(60, 60) or UDim2.fromOffset(50, 50)
		end
	end
	local function jump(id: string, instant: boolean?)
		local y = offsets[id]
		if not (scroll and y) then
			return
		end
		local goal = Vector2.new(0, math.min(y, maxScroll()))
		if instant then
			scroll.CanvasPosition = goal
		else
			TweenService:Create(scroll, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CanvasPosition = goal }):Play()
		end
		highlight()
	end

	-- category bar: icon + outlined label, no box
	local side = UI.frame(win, { Name = "Categories", Size = UDim2.fromOffset(SIDE_W, STORE.Y - 20), Position = UDim2.new(1, GAP, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5), BackgroundTransparency = 1 })
	local sl = Instance.new("UIListLayout")
	sl.Padding = UDim.new(0, 4)
	sl.HorizontalAlignment = Enum.HorizontalAlignment.Center
	sl.VerticalAlignment = Enum.VerticalAlignment.Center
	sl.SortOrder = Enum.SortOrder.LayoutOrder
	sl.Parent = side
	for i, cat in CATEGORIES do
		local b = Instance.new("TextButton")
		b.Name = cat.id
		b.Text = ""
		b.AutoButtonColor = false
		b.BackgroundTransparency = 1
		b.Size = UDim2.fromOffset(SIDE_W, 82)
		b.LayoutOrder = i
		b.Parent = side
		UI.squish(b)
		local icon = UI.icon(b, cat.icon, { Size = UDim2.fromOffset(50, 50), Position = UDim2.new(0.5, 0, 0, 30), AnchorPoint = Vector2.new(0.5, 0.5) })
		local label = UI.label(b, "body", cat.id, { Size = UDim2.new(1, 0, 0, 24), Position = UDim2.new(0.5, 0, 1, -2), AnchorPoint = Vector2.new(0.5, 1),
			StrokeThickness = 3, ZIndex = b.ZIndex + 1 })
		entries[cat.id] = { label = label, icon = icon }
		b.Activated:Connect(function()
			if UI.onClick then
				UI.onClick()
			end
			jump(cat.id)
		end)
	end

	local function build()
		local keep = scroll and scroll.CanvasPosition
		body:ClearAllChildren()
		table.clear(values)
		table.clear(offsets)
		d = State.data
		local sc = Shop.list(body, { Size = UDim2.new(1, 8, 1, 0), Position = UDim2.fromOffset(-4, 0), AutomaticCanvasSize = Enum.AutomaticSize.None })
		scroll = sc
		local y = 0

		local function header(cat: any)
			offsets[cat.id] = y
			local h = UI.frame(sc, { Name = cat.id, Size = UDim2.new(1, 0, 0, 36), Position = UDim2.fromOffset(0, y), BackgroundTransparency = 1 })
			UI.icon(h, cat.icon, { Size = UDim2.fromOffset(36, 36), Position = UDim2.fromOffset(0, 0) })
			UI.label(h, "value", cat.id:upper(), { Size = UDim2.new(0, 220, 0, 30), Position = UDim2.fromOffset(44, 3), TextXAlignment = Enum.TextXAlignment.Left,
				TextColor3 = UI.light(cat.color, 0.25) })
			UI.frame(h, { Name = "Rule", Size = UDim2.new(1, -230, 0, 3), Position = UDim2.new(1, 0, 0.5, 0), AnchorPoint = Vector2.new(1, 0.5),
				BackgroundColor3 = cat.color, BackgroundTransparency = 0.55 })
			y += 36 + 8
		end

		-- full-width banner: title on top, art left, price right; returns the middle area
		local function banner(color: Color3, title: string, iconName: string, kind: string, def: any, owned: boolean): Frame
			local f = UI.card(sc, color, { Size = UDim2.new(1, 0, 0, BANNER_H), Position = UDim2.fromOffset(0, y), BackgroundColor3 = T.navyLight:Lerp(color, 0.32) })
			bigText(f, title, 40, { Size = UDim2.new(1, -24, 0, 40), Position = UDim2.fromOffset(12, 8), TextColor3 = UI.light(color, 0.35),
				StrokeColor = UI.dark(color, 0.7), ZIndex = f.ZIndex + 2 })
			glow(f, UI.light(color, 0.5), 136, { Position = UDim2.fromOffset(96, 96), AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = f.ZIndex })
			UI.icon(f, iconName, { Size = UDim2.fromOffset(112, 112), Position = UDim2.fromOffset(96, 100), AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = f.ZIndex + 1 })
			priceButton(f, kind, def, owned, { Size = UDim2.fromOffset(176, 64), Position = UDim2.new(1, -16, 0, 100), AnchorPoint = Vector2.new(1, 0.5),
				ZIndex = f.ZIndex + 2 })
			y += BANNER_H + GAP
			return UI.frame(f, { Name = "Middle", Size = UDim2.new(1, -(180 + 208), 0, BANNER_H - 60), Position = UDim2.fromOffset(180, 52),
				BackgroundTransparency = 1, ZIndex = f.ZIndex + 1 })
		end

		-- "x1 > x2" for the doubling passes
		local function doubling(key: string, title: string, color: Color3)
			local def = Config.Passes[key]
			local owned = d.passes[key] == true
			local mid = banner(color, title, art(key, def), "pass", def, owned)
			local z = mid.ZIndex
			bigText(mid, "x1", 76, { Size = UDim2.fromScale(0.4, 0.92), Position = UDim2.fromScale(0, 0.04), Font = UI.NUMFONT, ZIndex = z,
				TextXAlignment = Enum.TextXAlignment.Right })
			bigText(mid, ">", 56, { Size = UDim2.fromScale(0.2, 0.7), Position = UDim2.fromScale(0.4, 0.15), Font = UI.NUMFONT, ZIndex = z })
			bigText(mid, "x2", 76, { Size = UDim2.fromScale(0.4, 0.92), Position = UDim2.fromScale(0.6, 0.04), Font = UI.NUMFONT, ZIndex = z,
				TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = T.gold, StrokeColor = UI.dark(T.gold, 0.65) })
		end

		-- a grid of product cards, cols per row
		local function grid(name: string, items: { { any } }, color: Color3)
			local rows = math.ceil(#items / cols)
			local h = rows * cardH + (rows - 1) * GAP
			local holder = UI.frame(sc, { Name = name, Size = UDim2.new(1, 0, 0, h), Position = UDim2.fromOffset(0, y), BackgroundTransparency = 1 })
			local g = Instance.new("UIGridLayout")
			g.CellSize = UDim2.new(1 / cols, -GAP * (cols - 1) / cols, 0, cardH)
			g.CellPadding = UDim2.fromOffset(GAP, GAP)
			g.SortOrder = Enum.SortOrder.LayoutOrder
			g.Parent = holder
			for i, it in items do
				local kind, key = it[1], it[2]
				local def = if kind == "pass" then Config.Passes[key] else Config.Products[key]
				local owned = kind == "pass" and d.passes[key] == true
				-- a bright card in the section's color, like the reference's blue tiles
				local f = UI.card(holder, owned and T.green or UI.dark(color, 0.45), { Name = key, LayoutOrder = i, BackgroundColor3 = UI.dark(color, 0.08) })
				glow(f, T.white, 112, { Position = UDim2.new(0.5, 0, 0, 58), AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = f.ZIndex })
				UI.icon(f, art(key, def), { Size = UDim2.fromOffset(96, 96), Position = UDim2.new(0.5, 0, 0, 56), AnchorPoint = Vector2.new(0.5, 0.5),
					ZIndex = f.ZIndex + 1 })
				local text = cardValue(key, def, d)
				local value = bigText(f, text, phone and 36 or 32, { Name = "Value", Size = UDim2.new(1, -16, 0, 34), Position = UDim2.fromOffset(8, 100),
					StrokeColor = UI.dark(color, 0.7), ZIndex = f.ZIndex + 2 })
				table.insert(values, { label = value, key = key, def = def })
				UI.label(f, phone and "body" or "meta", def.desc, { Size = UDim2.new(1, -16, 0, 20), Position = UDim2.fromOffset(8, 134),
					StrokeColor = UI.dark(color, 0.7), ZIndex = f.ZIndex + 2 })
				local bottom = { Size = UDim2.new(1, -16, 0, 50), Position = UDim2.new(0.5, 0, 1, -8), AnchorPoint = Vector2.new(0.5, 1), ZIndex = f.ZIndex + 2 }
				if key == "DoubleOffline" and def.id ~= 0 and (d.offline or 0) <= 0 then
					Shop.plate(f, "NONE WAITING", T.mute, bottom) -- only doubles welcome-back coins you haven't claimed
				else
					priceButton(f, kind, def, owned, bottom)
				end
			end
			y += h + GAP + 8
		end

		-- FEATURED: the next starter pack, the doubling passes, codes
		header(CATEGORIES[1])
		local packKey = d.starterNext
		local pack = packKey and Config.Products[packKey]
		if pack then
			local mid = banner(T.pink, pack.name:upper(), art(packKey, pack), "product", pack, false)
			local lines = Instance.new("UIGridLayout")
			lines.CellSize = UDim2.new(0.5, -6, 0, 30)
			lines.CellPadding = UDim2.fromOffset(12, 4)
			lines.VerticalAlignment = Enum.VerticalAlignment.Center
			lines.SortOrder = Enum.SortOrder.LayoutOrder
			lines.Parent = mid
			local i = 0
			for part in (pack.desc .. " + "):gmatch("(.-)%s*%+%s+") do
				i += 1
				local row = UI.frame(mid, { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, LayoutOrder = i, ZIndex = mid.ZIndex })
				local dot = UI.frame(row, { Size = UDim2.fromOffset(10, 10), Position = UDim2.new(0, 2, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5),
					BackgroundColor3 = T.gold, ZIndex = mid.ZIndex })
				UI.corner(dot, 5)
				UI.label(row, "body", part, { Size = UDim2.new(1, -18, 1, -4), Position = UDim2.fromOffset(18, 2), TextXAlignment = Enum.TextXAlignment.Left,
					ZIndex = mid.ZIndex })
			end
		end
		if not d.dealBought then
			local deal = Config.Products.SpeedDeal
			local mid = banner(T.orange, "ONLY 3 R$ DEAL", art("SpeedDeal", deal), "product", deal, false)
			UI.label(mid, "hero", "x2 SPEED FOR 30 MIN", { Size = UDim2.new(1, -20, 0, 40), Position = UDim2.fromOffset(10, 10), ZIndex = mid.ZIndex,
				TextColor3 = T.gold })
			UI.label(mid, "body", "One time only!", { Size = UDim2.new(1, -20, 0, 26), Position = UDim2.fromOffset(10, 52), ZIndex = mid.ZIndex })
		end
		doubling("TwoXSpeed", "DOUBLE YOUR SPEED", T.blue)
		doubling("TwoXCoins", "DOUBLE YOUR CASH", T.green)
		codesCard(sc, y, 76)
		y += 76 + GAP + 8

		header(CATEGORIES[2])
		grid("SpeedPacks", { { "product", "SpeedPack0" }, { "product", "SpeedPack1" }, { "product", "SpeedPack2" }, { "product", "SpeedPack3" }, { "product", "SpeedPack4" } }, CATEGORIES[2].color)
		header(CATEGORIES[3])
		grid("MoneyPacks", { { "product", "MoneyPack0" }, { "product", "MoneyPack1" }, { "product", "MoneyPack2" }, { "product", "MoneyPack3" }, { "product", "MoneyPack4" } }, CATEGORIES[3].color)
		header(CATEGORIES[4])
		local passes = {}
		for _, key in PASSES do
			table.insert(passes, { "pass", key })
		end
		grid("Passes", passes, CATEGORIES[4].color)
		header(CATEGORIES[5])
		local boosts = {}
		for _, key in BOOSTS do
			table.insert(boosts, { "product", key })
		end
		grid("Boosts", boosts, CATEGORIES[5].color)

		canvasH = y + 20 -- + the list's padding
		sc.CanvasSize = UDim2.fromOffset(0, canvasH)
		sc.CanvasPosition = Vector2.new(0, keep and math.min(keep.Y, maxScroll()) or 0)
		sc:GetPropertyChangedSignal("CanvasPosition"):Connect(highlight)
		current = ""
		highlight()
	end
	build()
	if section then
		jump(section, true)
	end

	local lastKey = storeKey(d)
	local conn
	conn = State.Changed:Connect(function(new)
		if open ~= win then
			conn:Disconnect()
			return
		end
		local key = storeKey(new)
		if key ~= lastKey then
			lastKey = key
			build()
			return
		end
		-- pack amounts follow your speed gain and income live
		for _, v in values do
			local text = cardValue(v.key, v.def, new)
			v.label.Text = text
		end
	end)
end

function Shop.start()
	gui = Instance.new("ScreenGui")
	gui.Name = "Shop"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 10
	gui.Parent = player:WaitForChild("PlayerGui")
	UI.autoScale(gui, Vector2.new(800, 480)) -- Index is the widest window (780 x 470)
	-- the bite cutscene owns the screen
	player:GetAttributeChangedSignal("Cinematic"):Connect(function()
		if player:GetAttribute("Cinematic") then
			closeAll()
		end
	end)
	RunService.RenderStepped:Connect(function()
		local t = os.clock()
		for _, m in spinners do
			if m.Parent then
				m:PivotTo(CFrame.Angles(0, t * 0.8, 0))
			end
		end
	end)
end

Shop.close = closeAll

function Shop.atRideShop(): boolean
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	return hrp ~= nil and Layout.atRideShop(hrp.Position)
end

-- close menus and point the guide beam at the Ride Shop
function Shop.goToRideShop()
	closeAll()
	Travel.go("Rides")
end
function Shop.isOpen(): boolean
	return open ~= nil and open.Parent ~= nil
end
return Shop
