-- The SELL hut (right of the Index): sell the dead fish lying on your tank
-- floor (unequipped catches) to make room for better ones. You can keep at
-- most Config.Tank.maxDead; past that you can't drop off a new catch.

local Players = game:GetService("Players")

local Shared = game.ReplicatedStorage.Shared
local Config = require(Shared.Config)
local UI = require(script.Parent.UI)
local State = require(script.Parent.State)

local Sell = {}
local C = UI.C
local player = Players.LocalPlayer

local gui: ScreenGui? = nil
local window: Frame? = nil
local conn: RBXScriptConnection? = nil

local function close()
	if conn then
		conn:Disconnect()
		conn = nil
	end
	if window then
		window:Destroy()
		window = nil
	end
end

local function dead(d: any): { any }
	local out = {}
	for _, c in d.creatures do
		if not c.e then
			table.insert(out, c)
		end
	end
	table.sort(out, function(a, b)
		return a.v < b.v -- weakest first: the ones you most want gone
	end)
	return out
end

local function price(c: any): number
	return math.floor(c.v * Config.SELL_SECONDS)
end

local function render()
	local d = State.data
	if not (gui and d) then
		return
	end
	if window then
		window:Destroy()
	end
	local list = dead(d)
	local f, body = UI.window(gui :: ScreenGui, "Sell Fish", C.green, Vector2.new(520, 470), close, "Cash")
	window = f
	local full = #list >= (d.maxDead or Config.Tank.maxDead)
	UI.outlined(body, ("Dead fish: %d/%d"):format(#list, d.maxDead or Config.Tank.maxDead), {
		Size = UDim2.new(1, -20, 0, 30), Position = UDim2.fromOffset(10, 4), TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = full and C.red or C.white })
	UI.outlined(body, "Unequipped catches don't earn. Sell them to make room for better ones!", {
		Size = UDim2.new(1, -20, 0, 20), Position = UDim2.fromOffset(10, 34), TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Color3.fromRGB(200, 200, 210) })
	local scroll = Instance.new("ScrollingFrame")
	scroll.Size = UDim2.new(1, -16, 1, -136)
	scroll.Position = UDim2.fromOffset(8, 60)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 7
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.CanvasSize = UDim2.new()
	scroll.Parent = body
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = scroll
	local total = 0
	for i, c in list do
		total += price(c)
		local row = UI.frame(scroll, { Size = UDim2.new(1, -12, 0, 56), LayoutOrder = i, BackgroundColor3 = Color3.fromRGB(44, 46, 56) })
		UI.corner(row, 8)
		UI.stroke(row, C.ink, 2)
		UI.outlined(row, Config.fullName(c.z, c.r, c.m, c.s), { Size = UDim2.new(1, -170, 0, 26), Position = UDim2.fromOffset(12, 4),
			TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Config.rarity(c.r).color })
		UI.outlined(row, ("$%s/s if equipped"):format(UI.short(c.v)), { Size = UDim2.new(1, -170, 0, 20), Position = UDim2.fromOffset(12, 31),
			TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Color3.fromRGB(150, 160, 150) })
		UI.button(row, "Sell $" .. UI.short(price(c)), C.green, function()
			State.action("sell", c.id)
		end, { Size = UDim2.fromOffset(140, 44), Position = UDim2.new(1, -6, 0.5, 0), AnchorPoint = Vector2.new(1, 0.5) })
	end
	if #list == 0 then
		UI.outlined(scroll, "No dead fish. Your tank is all swimmers!", { Size = UDim2.new(1, -12, 0, 40) })
	else
		UI.button(body, ("SELL ALL  +$%s"):format(UI.short(total)), C.green, function()
			State.action("sellAll")
		end, { Size = UDim2.fromOffset(300, 56), Position = UDim2.new(0.5, 0, 1, -6), AnchorPoint = Vector2.new(0.5, 1) })
	end
end

function Sell.open()
	if not gui then
		local g = Instance.new("ScreenGui")
		g.Name = "Sell"
		g.ResetOnSpawn = false
		g.DisplayOrder = 9
		g.Parent = player:WaitForChild("PlayerGui")
		UI.autoScale(g, Vector2.new(540, 490))
		gui = g
	end
	render()
	if not conn then
		local last = ""
		conn = State.Changed:Connect(function(d)
			local sig = {}
			for _, c in d.creatures do
				table.insert(sig, c.id .. (c.e and "e" or "d"))
			end
			local s = table.concat(sig, ",")
			if s ~= last and window then
				last = s
				render()
			end
		end)
	end
end

return Sell
