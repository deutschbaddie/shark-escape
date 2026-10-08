-- Rides window (the coin ladder, live 3D previews) and the Robux shop.
-- Honest shop: real odds shown, unconfigured items say "Soon" instead of
-- prompting, nothing pops up on its own.
-- Also the small menu kit the other windows share (one window at a time,
-- standard popups, scrolling lists, rarity colors, creature thumbnails).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local MarketplaceService = game:GetService("MarketplaceService")

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
local RARITY = { Common = T.mute, Uncommon = T.green, Rare = T.blue, Epic = T.purple, Legendary = T.gold }
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
	local key = d.ride .. "|" .. tostring(Shop.atRideShop())
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
local function storeCard(parent: Instance, kind: string, key: string, def: any, owned: boolean?, order: number)
	local best = key == "StarterPack"
	local f = UI.card(parent, (owned and T.green) or (best and T.gold) or nil, { Size = UDim2.new(0.5, -6, 1, 0), LayoutOrder = order })
	local tile = UI.inset(f, { Size = UDim2.fromOffset(88, 88), Position = UDim2.fromOffset(10, 10) })
	UI.icon(tile, def.iconName, { Size = UDim2.new(1, -12, 1, -12), Position = UDim2.fromOffset(6, 6) })
	if best then
		UI.chip(f, "BEST VALUE", T.pink, { Size = UDim2.fromOffset(100, 24), Position = UDim2.fromOffset(10, 106), ZIndex = f.ZIndex + 2 })
	end
	-- item / benefit
	UI.label(f, "body", def.name, { Size = UDim2.new(1, -122, 0, 26), Position = UDim2.fromOffset(110, 10), TextXAlignment = Enum.TextXAlignment.Left })
	local desc = UI.label(f, "meta", def.desc, { Size = UDim2.new(1, -122, 0, 40), Position = UDim2.fromOffset(110, 38), TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top, TextWrapped = true, TextColor3 = UI.light(T.mute, 0.35) })
	desc.TextWrapped = true
	-- price + BUY
	local bottom = { Size = UDim2.fromOffset(120, 50), Position = UDim2.new(1, -10, 1, -10), AnchorPoint = Vector2.new(1, 1) }
	if owned then
		Shop.plate(f, "OWNED", T.green, bottom)
		return
	end
	UI.label(f, "value", "R$ " .. def.price, { Size = UDim2.fromOffset(110, 30), Position = UDim2.new(1, -142, 1, -20), AnchorPoint = Vector2.new(1, 1),
		TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = T.gold, Font = UI.NUMFONT })
	if def.id == 0 then
		Shop.plate(f, "SOON", T.mute, bottom)
		return
	end
	UI.button(f, "BUY", T.gold, function()
		if kind == "pass" then
			MarketplaceService:PromptGamePassPurchase(player, def.id)
		else
			MarketplaceService:PromptProductPurchase(player, def.id)
		end
	end, bottom)
end

function Shop.openStore()
	local d = State.data
	if not d then
		return
	end
	local _, body = Shop.window("Shop", T.gold, Vector2.new(760, 470), "Shop")
	local scroll = Shop.list(body, { Size = UDim2.new(1, 8, 1, 0), Position = UDim2.fromOffset(-4, 0) }, 12)
	local order = 0
	local function nextOrder(): number
		order += 1
		return order
	end
	local function section(title: string)
		UI.label(scroll, "body", title, { Size = UDim2.new(1, 0, 0, 26), LayoutOrder = nextOrder(), TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = T.gold })
	end
	-- cards two per row
	local row: Frame? = nil
	local inRow = 0
	local function add(kind: string, key: string, def: any, owned: boolean?)
		if not row or inRow == 2 then
			local r = UI.frame(scroll, { Size = UDim2.new(1, 0, 0, 142), BackgroundTransparency = 1, LayoutOrder = nextOrder() })
			local l = Instance.new("UIListLayout")
			l.FillDirection = Enum.FillDirection.Horizontal
			l.Padding = UDim.new(0, 12)
			l.SortOrder = Enum.SortOrder.LayoutOrder
			l.Parent = r
			row, inRow = r, 0
		end
		inRow += 1
		storeCard(row :: Frame, kind, key, def, owned, inRow)
	end
	local function endRow()
		row = nil
	end

	-- codes (free rewards from videos / socials)
	local codes = UI.card(scroll, T.pink, { Size = UDim2.new(1, 0, 0, 76), LayoutOrder = nextOrder() })
	UI.icon(codes, "Gift", { Size = UDim2.fromOffset(56, 56), Position = UDim2.fromOffset(10, 10) })
	UI.label(codes, "body", "CODES", { Size = UDim2.fromOffset(150, 26), Position = UDim2.fromOffset(76, 12), TextXAlignment = Enum.TextXAlignment.Left })
	UI.label(codes, "meta", "Free rewards", { Size = UDim2.fromOffset(150, 20), Position = UDim2.fromOffset(76, 40), TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = T.mute })
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

	if not d.starter then
		section("SPECIAL OFFER")
		add("product", "StarterPack", Config.Products.StarterPack)
		endRow()
	end
	section("GAME PASSES  -  YOURS FOREVER")
	for _, key in { "TwoXSpeed", "TwoXCoins", "AutoCollect", "LuckyNet", "BigTank", "VIP" } do
		add("pass", key, Config.Passes[key], d.passes[key] == true)
	end
	endRow()
	section("BOOSTS")
	for _, key in { "Shield", "SpeedBoost", "LuckPotion", "GoldenBubble" } do
		add("product", key, Config.Products[key])
	end
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
