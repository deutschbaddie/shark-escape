-- Rides window (the coin ladder, live 3D previews) and the Robux shop.
-- Honest shop: real odds shown, unconfigured items say "Soon" instead of
-- prompting, nothing pops up on its own.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local MarketplaceService = game:GetService("MarketplaceService")

local Shared = game.ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Rides = require(Shared.Rides)
local Layout = require(Shared.Layout)
local UI = require(script.Parent.UI)
local State = require(script.Parent.State)
local Travel = require(script.Parent.Travel)

local Shop = {}
local C = UI.C
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
	local f, body = UI.window(gui, title, color, size or Vector2.new(700, 470), closeAll, iconName)
	open = f
	return f, body
end

local function window(title: string, color: Color3, iconName: string?): (Frame, ScrollingFrame)
	local f, body = Shop.window(title, color, nil, iconName)
	local scroll = Instance.new("ScrollingFrame")
	scroll.Size = UDim2.fromScale(1, 1)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 8
	scroll.ScrollBarImageColor3 = C.white
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.CanvasSize = UDim2.new()
	scroll.Parent = body
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 6)
	pad.PaddingBottom = UDim.new(0, 6)
	pad.Parent = scroll
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.fromOffset(200, 222)
	grid.CellPadding = UDim2.fromOffset(12, 12)
	grid.HorizontalAlignment = Enum.HorizontalAlignment.Center
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = scroll
	return f, scroll
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

local function viewport(parent: Instance, model: Model)
	Shop.viewport(parent, model)
end

-- colored studded card
local function item(scroll: Instance, order: number, color: Color3?): Frame
	local f = UI.frame(scroll, { LayoutOrder = order, BackgroundColor3 = color or C.sky })
	UI.corner(f, 10)
	UI.stroke(f, C.ink, 3)
	UI.shade(f)
	UI.studs(f, { size = 22, alpha = 0.85 })
	return f
end

----------------------------------------------------------------- rides
-- what the rides window shows that can change: next ride + what you can afford
local function ridesKey(d: any): string
	local key = d.ride .. "|" .. #d.tank .. "|" .. d.slots .. "|" .. tostring(d.slotPrice and d.coins >= d.slotPrice)
	for _, ride in Config.Rides do
		if d.rides[ride.id] then
			key ..= ride.id
		elseif not ride.robux then
			return key .. ">" .. ride.id .. tostring(d.coins >= ride.price)
		end
	end
	return key
end

function Shop.openRides()
	local d = State.data
	if not d then
		return
	end
	local _, scroll = window("Rides", C.sky, "Rides")
	local function refresh()
		if not open then
			return
		end
		for _, k in scroll:GetChildren() do
			if k:IsA("Frame") then
				k:Destroy()
			end
		end
		table.clear(spinners)
		d = State.data
		-- tank slot card first
		local slotCard = item(scroll, 0, C.blue)
		UI.icon(slotCard, "BigTank", { Size = UDim2.fromOffset(96, 96), Position = UDim2.new(0.5, 0, 0, 8), AnchorPoint = Vector2.new(0.5, 0) })
		UI.outlined(slotCard, ("Tank %d / %d"):format(#d.tank, d.slots), { Size = UDim2.new(1, -16, 0, 28), Position = UDim2.fromOffset(8, 104) })
		UI.outlined(slotCard, "More room = more coins", { Size = UDim2.new(1, -16, 0, 18), Position = UDim2.fromOffset(8, 136), TextColor3 = C.gold })
		if d.slotPrice then
			local can = d.coins >= d.slotPrice
			UI.button(slotCard, ("+1 SLOT  $%s"):format(UI.short(d.slotPrice)), can and C.green or C.gold, function()
				State.action("buySlot")
			end, { Size = UDim2.new(1, -16, 0, 44), Position = UDim2.new(0, 8, 1, -52) })
		end
		local foundNext = false
		for _, ride in Config.Rides do
			local owned = d.rides[ride.id] == true
			local f = item(scroll, ride.order, ride.robux and C.pink or (owned and C.green or C.sky))
			viewport(f, Rides.build(ride.id))
			UI.outlined(f, ride.icon .. " " .. ride.name, { Size = UDim2.new(1, -12, 0, 24), Position = UDim2.fromOffset(6, 112) })
			local perk = ride.robux and ("x%s speed gain"):format(tostring(ride.mult)) or ("+%d speed / sec"):format(ride.gain or 0)
			UI.outlined(f, perk, { Size = UDim2.new(1, -12, 0, 20), Position = UDim2.fromOffset(6, 138), TextColor3 = C.gold })
			local btnText, btnColor, onClick = "", C.panel, function() end
			if owned then
				if d.ride == ride.id then
					btnText, btnColor = "RIDING ✅", C.panel
				else
					btnText, btnColor = "RIDE", C.sky
					onClick = function()
						State.action("equip", ride.id)
					end
				end
			elseif ride.robux then
				local pass = Config.Passes[ride.robux]
				if pass and pass.id ~= 0 then
					btnText, btnColor = "R$ " .. pass.price, C.pink
					onClick = function()
						MarketplaceService:PromptGamePassPurchase(player, pass.id)
					end
				else
					btnText = "Soon"
				end
			elseif not foundNext then
				foundNext = true
				local can = d.coins >= ride.price
				if can and not Shop.atRideShop() then
					btnText, btnColor = "📍 GO TO SHOP", C.sky
					onClick = function()
						Shop.goToRideShop()
					end
				else
					btnText = (can and "BUY  $" or "$") .. UI.short(ride.price)
					btnColor = can and C.green or C.gold
					onClick = function()
						State.action("buyRide", ride.id)
					end
				end
			else
				btnText = "🔒 $" .. UI.short(ride.price)
			end
			UI.button(f, btnText, btnColor, onClick, { Size = UDim2.new(1, -16, 0, 44), Position = UDim2.new(0, 8, 1, -52) })
		end
	end
	refresh()
	local conn
	conn = State.Changed:Connect(function(new, prev)
		if not open then
			conn:Disconnect()
			return
		end
		-- only rebuild when something visible changed
		if not prev or ridesKey(new) ~= ridesKey(prev) then
			refresh()
		end
	end)
end

----------------------------------------------------------------- robux shop
local function priceButton(parent: Instance, kind: string, key: string, def: any)
	if def.id == 0 then
		UI.button(parent, "Soon", C.panel, function() end, { Size = UDim2.new(1, -16, 0, 44), Position = UDim2.new(0, 8, 1, -52) })
		return
	end
	UI.button(parent, "R$ " .. def.price, C.green, function()
		if kind == "pass" then
			MarketplaceService:PromptGamePassPurchase(player, def.id)
		else
			MarketplaceService:PromptProductPurchase(player, def.id)
		end
	end, { Size = UDim2.new(1, -16, 0, 44), Position = UDim2.new(0, 8, 1, -52) })
end

function Shop.openStore()
	local d = State.data
	if not d then
		return
	end
	local _, scroll = window("Shop", C.pink, "Shop")
	local order = 0
	local function add(kind: string, key: string, def: any, owned: boolean?)
		order += 1
		local f = item(scroll, order, key == "StarterPack" and C.gold or (kind == "pass" and C.purple or C.blue))
		UI.icon(f, def.iconName, { Size = UDim2.fromOffset(88, 88), Position = UDim2.new(0.5, 0, 0, 4), AnchorPoint = Vector2.new(0.5, 0) })
		UI.outlined(f, def.name, { Size = UDim2.new(1, -12, 0, 26), Position = UDim2.fromOffset(6, 92) })
		UI.outlined(f, def.desc, { Size = UDim2.new(1, -16, 0, 40), Position = UDim2.fromOffset(8, 122), TextWrapped = true, TextColor3 = Color3.fromRGB(230, 236, 255) })
		if owned then
			UI.button(f, "OWNED ✅", C.panel, function() end, { Size = UDim2.new(1, -16, 0, 44), Position = UDim2.new(0, 8, 1, -52) })
		else
			priceButton(f, kind, key, def)
		end
	end
	if not d.starter then
		add("product", "StarterPack", Config.Products.StarterPack)
	end
	for _, key in { "TwoXSpeed", "TwoXCoins", "AutoCollect", "LuckyNet", "BigTank", "VIP" } do
		add("pass", key, Config.Passes[key], d.passes[key] == true)
	end
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
	local scale = Instance.new("UIScale")
	scale.Parent = gui
	local function rescale()
		local v = workspace.CurrentCamera.ViewportSize
		scale.Scale = math.clamp(math.min(v.X / 780, v.Y / 540), 0.5, 1.2)
	end
	rescale()
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(rescale)
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
