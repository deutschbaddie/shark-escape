-- The SELL hut (right of the Index): sell the dead fish lying on your tank
-- floor (unequipped catches) to make room for better ones. You can keep at
-- most Config.Tank.maxDead; past that you can't drop off a new catch.

local Players = game:GetService("Players")

local Shared = game.ReplicatedStorage.Shared
local Config = require(Shared.Config)
local UI = require(script.Parent.UI)
local State = require(script.Parent.State)
local Shop = require(script.Parent.Shop)

local Sell = {}
local T = UI.T
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
	local maxDead = d.maxDead or Config.Tank.maxDead
	local f, body = UI.window(gui :: ScreenGui, "Sell Fish", T.green, Vector2.new(600, 470), close, "Cash")
	window = f
	local full = #list >= maxDead

	-- status: how full the floor is
	local strip = UI.inset(body, { Size = UDim2.new(1, 0, 0, 64) })
	UI.label(strip, "meta", "DEAD FISH", { Size = UDim2.fromOffset(120, 18), Position = UDim2.fromOffset(12, 6), TextColor3 = T.mute })
	UI.label(strip, "value", ("%d / %d"):format(#list, maxDead), { Size = UDim2.fromOffset(120, 32), Position = UDim2.fromOffset(12, 24), Font = UI.NUMFONT,
		TextColor3 = full and T.red or T.white })
	UI.frame(strip, { Size = UDim2.new(0, 2, 1, -20), Position = UDim2.fromOffset(144, 10), BackgroundColor3 = T.line, BackgroundTransparency = 0.5 })
	UI.label(strip, "body", full and "Your tank floor is full! Sell some to drop off new catches."
		or "Unequipped fish don't earn. Sell them to make room for better ones!", {
		Size = UDim2.new(1, -172, 1, -16), Position = UDim2.fromOffset(160, 8), TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = full and UI.light(T.red, 0.4) or T.mute })

	local scroll = Shop.list(body, { Size = UDim2.new(1, 8, 1, -148), Position = UDim2.fromOffset(-4, 76) }, 8)
	local total = 0
	for i, c in list do
		total += price(c)
		local row = UI.card(scroll, nil, { Size = UDim2.new(1, 0, 0, 80), LayoutOrder = i })
		Shop.thumb(row, c, { Size = UDim2.fromOffset(64, 64), Position = UDim2.fromOffset(8, 8) })
		UI.label(row, "body", Config.fullName(c.z, c.r, c.m, c.s), { Size = UDim2.new(1, -250, 0, 26), Position = UDim2.fromOffset(84, 10),
			TextXAlignment = Enum.TextXAlignment.Left })
		UI.chip(row, c.r:upper(), Shop.rarityColor(c.r), { Size = UDim2.fromOffset(104, 24), Position = UDim2.fromOffset(84, 44) })
		UI.label(row, "meta", ("$%s/s if equipped"):format(UI.short(c.v)), { Size = UDim2.new(1, -366, 0, 20), Position = UDim2.fromOffset(196, 46),
			TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = T.mute })
		UI.button(row, "SELL  $" .. UI.short(price(c)), T.green, function()
			State.action("sell", c.id)
		end, { Size = UDim2.fromOffset(150, 56), Position = UDim2.new(1, -10, 0.5, 0), AnchorPoint = Vector2.new(1, 0.5) })
	end
	local footer = { Size = UDim2.new(1, 0, 0, 56), Position = UDim2.new(0, 0, 1, 0), AnchorPoint = Vector2.new(0, 1) }
	if #list == 0 then
		local empty = UI.inset(scroll, { Size = UDim2.new(1, 0, 0, 80) })
		UI.label(empty, "body", "No dead fish. Your tank is all swimmers!", { Size = UDim2.new(1, -32, 0, 26), Position = UDim2.fromOffset(16, 27) })
		Shop.plate(body, "NOTHING TO SELL", T.mute, footer)
	else
		UI.button(body, ("SELL ALL  +$%s"):format(UI.short(total)), T.green, function()
			State.action("sellAll")
		end, footer)
	end
end

function Sell.open()
	if not gui then
		local g = Instance.new("ScreenGui")
		g.Name = "Sell"
		g.ResetOnSpawn = false
		g.DisplayOrder = 9
		g.Parent = player:WaitForChild("PlayerGui")
		UI.autoScale(g, Vector2.new(620, 480))
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
