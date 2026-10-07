-- Small world-side client bits:
--  * Welcome Back popup (tank coins earned while you were away)
--  * shop hut pads: step on the glowing pad to open Rides / Index / Shop
--  * huts get a clean outline when you're close (only when it helps)
--  * gates you've unlocked fade out and say so

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local MarketplaceService = game:GetService("MarketplaceService")
local TweenService = game:GetService("TweenService")

local Shared = game.ReplicatedStorage.Shared
local Config = require(Shared.Config)
local UI = require(script.Parent.UI)
local Fx = require(script.Parent.Fx)
local State = require(script.Parent.State)
local Shop = require(script.Parent.Shop)
local Index = require(script.Parent.Index)

local Hub = {}
local C = UI.C
local player = Players.LocalPlayer

----------------------------------------------------------------- welcome back
local welcomeShown = false
local function welcome(amount: number)
	welcomeShown = true
	local win, body = Shop.window("⏰ Welcome Back!", C.blue, Vector2.new(560, 360))
	UI.outlined(body, "Your tank earned while you were away:", { Size = UDim2.new(1, -20, 0, 32), Position = UDim2.fromOffset(10, 6) })
	-- sunburst behind the number
	local burst = UI.frame(body, { Size = UDim2.fromOffset(150, 150), Position = UDim2.new(0.5, 0, 0, 112), AnchorPoint = Vector2.new(0.5, 0.5), BackgroundTransparency = 1 })
	for i = 0, 7 do
		UI.frame(burst, { Size = UDim2.new(0, 14, 1, 0), Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5), Rotation = i * 22.5,
			BackgroundColor3 = C.gold, BackgroundTransparency = 0.6 })
	end
	task.spawn(function()
		while burst.Parent do
			burst.Rotation += 0.6
			task.wait()
		end
	end)
	UI.text(body, "💰", { Size = UDim2.fromOffset(80, 80), Position = UDim2.new(0.5, 0, 0, 112), AnchorPoint = Vector2.new(0.5, 0.5) })
	UI.outlined(body, "+" .. UI.commas(amount), { Size = UDim2.new(1, -40, 0, 56), Position = UDim2.new(0.5, 0, 0, 196), AnchorPoint = Vector2.new(0.5, 0.5), Font = UI.NUMFONT, TextColor3 = C.money })
	local prod = Config.Products.DoubleOffline
	local claimX = 0.5
	if prod.id ~= 0 then
		claimX = 0.72
		local dbl = UI.button(body, ("2x  +%s"):format(UI.short(amount * 2)), C.pink, function()
			MarketplaceService:PromptProductPurchase(player, prod.id)
		end, { Size = UDim2.fromOffset(230, 64), Position = UDim2.new(0.28, 0, 1, -4), AnchorPoint = Vector2.new(0.5, 1) })
		UI.rainbow(dbl)
		UI.outlined(dbl, "R$" .. prod.price, { Size = UDim2.fromOffset(60, 22), Position = UDim2.new(1, 4, 0, -10), AnchorPoint = Vector2.new(1, 0), TextColor3 = C.money, ZIndex = dbl.ZIndex + 3 })
	end
	UI.button(body, "Claim!", C.green, function()
		State.action("claimOffline")
		Shop.close()
	end, { Size = UDim2.fromOffset(200, 64), Position = UDim2.new(claimX, 0, 1, -4), AnchorPoint = Vector2.new(0.5, 1) })
	-- closing with X still banks the coins
	win.Destroying:Connect(function()
		if State.data and State.data.offline > 0 then
			State.action("claimOffline")
		end
	end)
	-- closes itself once the coins are claimed (button or 2x purchase)
	local conn
	conn = State.Changed:Connect(function(d)
		if d.offline <= 0 or not win.Parent then
			conn:Disconnect()
			if win.Parent then
				Shop.close()
			end
		end
	end)
end

----------------------------------------------------------------- pads + outlines
local inside: { [Instance]: boolean } = {}
local highlights: { [Instance]: Highlight } = {}

local opens = {
	Rides = function()
		Shop.openRides()
	end,
	Shop = function()
		Shop.openStore()
	end,
	Index = function()
		Index.open()
	end,
}

local function padTick()
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hrp then
		return
	end
	local pos = hrp.Position
	for _, hut in CollectionService:GetTagged("ShopPad") do
		local px, pz = hut:GetAttribute("PadX"), hut:GetAttribute("PadZ")
		if typeof(px) ~= "number" or typeof(pz) ~= "number" then
			continue
		end
		local dist = Vector2.new(pos.X - px, pos.Z - pz).Magnitude
		local on = dist < 7 and pos.Y < Config.BEACH_TOP + 8
		if on and not inside[hut] then
			local fn = opens[hut:GetAttribute("Kind")]
			if fn and State.data then
				fn()
				Fx.ring(Vector3.new(px, Config.BEACH_TOP + 0.4, pz), C.white, 16)
			end
		end
		inside[hut] = on
		-- outline when close
		local near = dist < 34
		local h = highlights[hut]
		if near and not h then
			h = Instance.new("Highlight")
			h.FillTransparency = 1
			h.OutlineColor = C.white
			h.OutlineTransparency = 1
			h.DepthMode = Enum.HighlightDepthMode.Occluded
			h.Adornee = hut
			h.Parent = hut
			highlights[hut] = h
			TweenService:Create(h, TweenInfo.new(0.25), { OutlineTransparency = 0 }):Play()
		elseif not near and h then
			highlights[hut] = nil
			h:Destroy()
		end
	end
end

----------------------------------------------------------------- gates
local function gateTick()
	local d = State.data
	if not d then
		return
	end
	for _, g in CollectionService:GetTagged("Gate") do
		local need = g:GetAttribute("Gate")
		local wall = g:FindFirstChild("Wall") :: BasePart?
		if typeof(need) == "number" and wall then
			local open = d.speed >= need
			wall.LocalTransparencyModifier = open and 1 or 0
			local banner = g:FindFirstChild("Banner")
			if banner then
				for _, sg in banner:GetChildren() do
					local t = sg:FindFirstChild("Text") :: TextLabel?
					if t then
						t.Text = open and ("🔓 %s"):format(g:GetAttribute("ZoneName")) or ("🔒 %s  ⚡%s"):format(g:GetAttribute("ZoneName"), UI.short(need))
						t.TextColor3 = open and C.money or C.white
					end
				end
			end
		end
	end
end

function Hub.start()
	State.Changed:Connect(function(d)
		if not welcomeShown and d.offline and d.offline > 0 then
			task.delay(1.5, function()
				if State.data and State.data.offline > 0 then
					welcome(State.data.offline)
				end
			end)
			welcomeShown = true
		end
	end)
	task.spawn(function()
		local t = 0
		while true do
			task.wait(0.2)
			padTick()
			t += 1
			if t % 5 == 0 then
				gateTick()
			end
		end
	end)
end

return Hub
