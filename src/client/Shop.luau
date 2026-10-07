-- Rides window (the coin ladder, live 3D previews) and the Robux shop.
-- Honest shop: real odds shown, unconfigured items say "Soon" instead of
-- prompting, nothing pops up on its own.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local MarketplaceService = game:GetService("MarketplaceService")

local Shared = game.ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Rides = require(Shared.Rides)
local UI = require(script.Parent.UI)
local State = require(script.Parent.State)

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

local function window(title: string, color: Color3): (Frame, ScrollingFrame)
	closeAll()
	local f = UI.frame(gui, { Size = UDim2.fromOffset(660, 440), Position = UDim2.fromScale(0.5, 0.52), AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = Color3.fromRGB(240, 246, 255) })
	UI.corner(f, 24)
	UI.stroke(f, C.ink, 4)
	UI.pop(f, 0.85)
	local head = UI.frame(f, { Size = UDim2.new(1, 0, 0, 58), BackgroundColor3 = color })
	UI.corner(head, 24)
	UI.outlined(head, title, { Size = UDim2.new(1, -120, 1, -12), Position = UDim2.fromOffset(20, 6), TextXAlignment = Enum.TextXAlignment.Left })
	UI.button(head, "X", C.red, closeAll, { Size = UDim2.fromOffset(48, 48), Position = UDim2.new(1, -54, 0, 5) })
	local scroll = Instance.new("ScrollingFrame")
	scroll.Size = UDim2.new(1, -24, 1, -74)
	scroll.Position = UDim2.fromOffset(12, 66)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 8
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.CanvasSize = UDim2.new()
	scroll.Parent = f
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.fromOffset(196, 214)
	grid.CellPadding = UDim2.fromOffset(10, 10)
	grid.HorizontalAlignment = Enum.HorizontalAlignment.Center
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = scroll
	open = f
	return f, scroll
end

local function viewport(parent: Instance, model: Model)
	local vf = Instance.new("ViewportFrame")
	vf.Size = UDim2.new(1, -12, 0, 104)
	vf.Position = UDim2.fromOffset(6, 6)
	vf.BackgroundColor3 = Color3.fromRGB(170, 228, 255)
	vf.Ambient = Color3.fromRGB(200, 200, 210)
	vf.LightDirection = Vector3.new(-1, -2, -1)
	vf.Parent = parent
	UI.corner(vf, 14)
	local cam = Instance.new("Camera")
	cam.FieldOfView = 40
	cam.Parent = vf
	vf.CurrentCamera = cam
	model:PivotTo(CFrame.new())
	model.Parent = vf
	local _, size = model:GetBoundingBox()
	local r = math.max(size.X, size.Y, size.Z)
	cam.CFrame = CFrame.lookAt(Vector3.new(r * 0.9, r * 0.7, -r * 1.3), Vector3.new(0, -0.3, 0))
	table.insert(spinners, model)
end

local function item(scroll: Instance, order: number, color: Color3?): Frame
	local f = UI.frame(scroll, { LayoutOrder = order, BackgroundColor3 = color or C.white })
	UI.corner(f, 18)
	UI.stroke(f, C.ink, 3)
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
	local _, scroll = window("🛟 RIDES - faster ride = more speed/sec", C.sky)
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
		local slotCard = item(scroll, 0, Color3.fromRGB(220, 244, 255))
		UI.text(slotCard, "🐟", { Size = UDim2.new(1, 0, 0, 80), Position = UDim2.fromOffset(0, 14) })
		UI.text(slotCard, ("Tank %d / %d"):format(#d.tank, d.slots), { Size = UDim2.new(1, -16, 0, 28), Position = UDim2.fromOffset(8, 104) })
		UI.text(slotCard, "More room = more coins", { Size = UDim2.new(1, -16, 0, 18), Position = UDim2.fromOffset(8, 134), TextColor3 = C.mute })
		if d.slotPrice then
			local can = d.coins >= d.slotPrice
			UI.button(slotCard, ("+1 SLOT  💰%s"):format(UI.short(d.slotPrice)), can and C.green or C.mute, function()
				State.action("buySlot")
			end, { Size = UDim2.new(1, -16, 0, 44), Position = UDim2.new(0, 8, 1, -52) })
		end
		local foundNext = false
		for _, ride in Config.Rides do
			local owned = d.rides[ride.id] == true
			local f = item(scroll, ride.order, ride.robux and Color3.fromRGB(255, 236, 248) or C.white)
			viewport(f, Rides.build(ride.id))
			UI.text(f, ride.icon .. " " .. ride.name, { Size = UDim2.new(1, -12, 0, 24), Position = UDim2.fromOffset(6, 112) })
			local perk = ride.robux and ("x%s speed gain"):format(tostring(ride.mult)) or ("+%d speed / sec"):format(ride.gain or 0)
			UI.text(f, perk, { Size = UDim2.new(1, -12, 0, 18), Position = UDim2.fromOffset(6, 138), TextColor3 = C.blue })
			local btnText, btnColor, onClick = "", C.mute, function() end
			if owned then
				if d.ride == ride.id then
					btnText, btnColor = "RIDING ✅", C.blue
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
				btnText = (can and "BUY  💰" or "💰") .. UI.short(ride.price)
				btnColor = can and C.green or C.mute
				onClick = function()
					State.action("buyRide", ride.id)
				end
			else
				btnText = "🔒 💰" .. UI.short(ride.price)
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
		UI.button(parent, "Soon", C.mute, function() end, { Size = UDim2.new(1, -16, 0, 44), Position = UDim2.new(0, 8, 1, -52) })
		return
	end
	UI.button(parent, "R$ " .. def.price, C.pink, function()
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
	local _, scroll = window("🛒 SHOP", C.pink)
	local order = 0
	local function add(kind: string, key: string, def: any, owned: boolean?)
		order += 1
		local f = item(scroll, order, key == "StarterPack" and Color3.fromRGB(255, 244, 200) or C.white)
		UI.text(f, def.icon, { Size = UDim2.new(1, 0, 0, 70), Position = UDim2.fromOffset(0, 14) })
		UI.text(f, def.name, { Size = UDim2.new(1, -12, 0, 26), Position = UDim2.fromOffset(6, 92) })
		UI.text(f, def.desc, { Size = UDim2.new(1, -16, 0, 40), Position = UDim2.fromOffset(8, 120), TextColor3 = C.mute, TextWrapped = true })
		if owned then
			UI.button(f, "OWNED ✅", C.blue, function() end, { Size = UDim2.new(1, -16, 0, 44), Position = UDim2.new(0, 8, 1, -52) })
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
		scale.Scale = math.clamp(math.min(v.X / 720, v.Y / 500), 0.5, 1.2)
	end
	rescale()
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(rescale)
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
return Shop
