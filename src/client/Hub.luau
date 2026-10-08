-- Small world-side client bits:
--  * Welcome Back popup (tank coins earned while you were away)
--  * shop hut pads: step on the glowing pad to open Rides / Index / Shop
--  * huts get a clean outline when you're close (only when it helps)
--  * gates you've unlocked fade out and say so

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local MarketplaceService = game:GetService("MarketplaceService")
local TweenService = game:GetService("TweenService")

local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

local Shared = game.ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Layout = require(Shared.Layout)
local Build = require(Shared.Build)
local Rides = require(Shared.Rides)
local UI = require(script.Parent.UI)
local Fx = require(script.Parent.Fx)
local State = require(script.Parent.State)
local Shop = require(script.Parent.Shop)
local Index = require(script.Parent.Index)
local Guide = require(script.Parent.Guide)

local Hub = {}
local C = UI.C
local player = Players.LocalPlayer

----------------------------------------------------------------- welcome back
local welcomeShown = false
local function welcome(amount: number)
	welcomeShown = true
	local win, body = Shop.window("Welcome Back!", C.blue, Vector2.new(520, 340), "Clock")
	UI.outlined(body, "Your tank earned while you were away!", { Size = UDim2.new(1, -20, 0, 28), Position = UDim2.fromOffset(10, 4) })
	-- the amount, counting up on a dark card
	local card = UI.inset(body, { Size = UDim2.new(1, -40, 0, 108), Position = UDim2.new(0.5, 0, 0, 42), AnchorPoint = Vector2.new(0.5, 0) })
	UI.icon(card, "Cash", { Size = UDim2.fromOffset(84, 84), Position = UDim2.new(0, 16, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5) })
	local value = UI.outlined(card, "+$0", { Size = UDim2.new(1, -124, 0, 70), Position = UDim2.new(0, 112, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5),
		Font = UI.NUMFONT, TextColor3 = C.money, TextXAlignment = Enum.TextXAlignment.Left })
	UI.pop(card, 0.8)
	task.spawn(function()
		local t0 = os.clock()
		while value.Parent and os.clock() - t0 < 0.9 do
			local k = (os.clock() - t0) / 0.9
			value.Text = "+$" .. UI.commas(amount * (1 - (1 - k) ^ 3))
			task.wait()
		end
		value.Text = "+$" .. UI.commas(amount)
		Fx.sound("coin", 0.6)
	end)
	UI.outlined(body, ("Offline your tank earns %d%% (up to %dh)"):format(math.floor(Config.Offline.rate * 100), Config.Offline.maxHours),
		{ Size = UDim2.new(1, -40, 0, 20), Position = UDim2.new(0.5, 0, 0, 158), AnchorPoint = Vector2.new(0.5, 0), TextColor3 = Color3.fromRGB(190, 200, 220) })
	local prod = Config.Products.DoubleOffline
	local claimX = 0.5
	if prod.id ~= 0 then
		claimX = 0.73
		local dbl = UI.button(body, ("2x  +$%s"):format(UI.short(amount * 2)), C.pink, function()
			MarketplaceService:PromptProductPurchase(player, prod.id)
		end, { Size = UDim2.fromOffset(210, 56), Position = UDim2.new(0.27, 0, 1, -2), AnchorPoint = Vector2.new(0.5, 1) })
		UI.rainbow(dbl)
		UI.outlined(dbl, "R$" .. prod.price, { Size = UDim2.fromOffset(60, 22), Position = UDim2.new(1, 4, 0, -12), AnchorPoint = Vector2.new(1, 0), TextColor3 = C.money, ZIndex = dbl.ZIndex + 3 })
	end
	UI.button(body, "Claim!", C.green, function()
		State.action("claimOffline")
		Shop.close()
	end, { Size = UDim2.fromOffset(200, 56), Position = UDim2.new(claimX, 0, 1, -2), AnchorPoint = Vector2.new(0.5, 1) })
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

----------------------------------------------------------------- rebirth confirm
-- rebirth wipes progress, so it always asks first and says exactly what happens
function Hub.confirmRebirth()
	local d = State.data
	if not d or d.speed < Config.Rebirth.speed then
		return
	end
	local now = Config.Rebirth.mult ^ d.rebirths
	local nextMult = Config.Rebirth.mult ^ (d.rebirths + 1)
	local _, body = Shop.window("Rebirth?", C.green, Vector2.new(580, 360), "Rebirth")
	UI.outlined(body, ("Speed gain  x%s  →  x%s  forever!"):format(string.format("%g", math.floor(now * 100) / 100), string.format("%g", math.floor(nextMult * 100) / 100)),
		{ Size = UDim2.new(1, -20, 0, 44), Position = UDim2.fromOffset(10, 6), TextColor3 = C.money })
	local lines = UI.inset(body, { Size = UDim2.new(1, -20, 0, 130), Position = UDim2.fromOffset(10, 60) })
	UI.outlined(lines, "❌ Resets: speed, coins and rides", { Size = UDim2.new(1, -24, 0, 34), Position = UDim2.fromOffset(12, 14), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Color3.fromRGB(255, 140, 140) })
	UI.outlined(lines, "✅ Keeps: your tank, Index, shields and Robux items", { Size = UDim2.new(1, -24, 0, 34), Position = UDim2.fromOffset(12, 64), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = C.money })
	UI.button(body, "Not yet", C.panel, function()
		Shop.close()
	end, { Size = UDim2.fromOffset(190, 62), Position = UDim2.new(0.27, 0, 1, -4), AnchorPoint = Vector2.new(0.5, 1) })
	local go = UI.button(body, "REBIRTH!", C.green, function()
		State.action("rebirth")
		Shop.close()
	end, { Size = UDim2.fromOffset(230, 62), Position = UDim2.new(0.72, 0, 1, -4), AnchorPoint = Vector2.new(0.5, 1) })
	UI.pulse(go)
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
		if on and hut:GetAttribute("Kind") == "Rides" then
			Guide.set("shop", nil) -- arrived
		end
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

----------------------------------------------------------------- ride shop showcase
-- your next ride spins on the pedestal with its price and perk
local showcase: Model? = nil
local showcaseId: string? = nil
local showcaseLabel: TextLabel? = nil
local showcaseSub: TextLabel? = nil

local function nextRide(d: any): Config.Ride?
	for _, ride in Config.Rides do
		if not ride.robux and not d.rides[ride.id] then
			return ride
		end
	end
	return nil
end

local function updateShowcase()
	local d = State.data
	local map = Workspace:FindFirstChild("Map")
	local shop = map and map:FindFirstChild("RideShop")
	local pedestal = shop and shop:FindFirstChild("Pedestal") :: BasePart?
	if not (d and pedestal) then
		return
	end
	local nxt = nextRide(d)
	local id = nxt and nxt.id or nil
	if id ~= showcaseId then
		showcaseId = id
		if showcase then
			showcase:Destroy()
			showcase = nil
		end
		if nxt then
			local m = Rides.build(nxt.id)
			Build.ghost(m)
			m:ScaleTo(1.7)
			m.Parent = Workspace
			showcase = m
		end
	end
	if not showcaseLabel then
		local bb = Instance.new("BillboardGui")
		bb.Size = UDim2.fromScale(14, 4.4)
		bb.StudsOffsetWorldSpace = Vector3.new(0, 9.5, 0)
		bb.MaxDistance = 120
		bb.LightInfluence = 0
		bb.Parent = pedestal
		showcaseLabel = UI.outlined(bb, "", { Size = UDim2.fromScale(1, 0.55) })
		showcaseSub = UI.outlined(bb, "", { Size = UDim2.fromScale(1, 0.42), Position = UDim2.fromScale(0, 0.58), TextColor3 = C.gold })
	end
	local label, sub = showcaseLabel :: TextLabel, showcaseSub :: TextLabel
	if nxt then
		label.Text = ("%s %s"):format(nxt.icon, nxt.name)
		local can = d.coins >= nxt.price
		sub.Text = can and ("$%s  ·  +%d/s  ·  STEP ON THE PAD!"):format(UI.short(nxt.price), nxt.gain or 0)
			or ("$%s  ·  +%d speed/sec"):format(UI.short(nxt.price), nxt.gain or 0)
		sub.TextColor3 = can and C.money or C.gold
	else
		label.Text = "🏆 Every ride owned!"
		sub.Text = "Rebirth for a permanent boost"
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
			for _, tex in wall:GetChildren() do
				if tex:IsA("Texture") then
					tex.Transparency = open and 1 or 0
				end
			end
			local banner = g:FindFirstChild("Banner")
			if banner then
				for _, sg in banner:GetChildren() do
					local t = sg:FindFirstChild("Text") :: TextLabel?
					local sub = sg:FindFirstChild("Sub") :: TextLabel?
					if t then
						t.Text = (open and "🔓 %s" or "🔒 %s"):format(g:GetAttribute("ZoneName"))
						t.TextColor3 = open and C.money or C.white
					end
					if sub then
						sub.Text = open and "Unlocked!" or ("Need ⚡%s speed · you have %s"):format(UI.short(need), UI.short(d.speed))
						sub.TextColor3 = open and C.money or C.gold
					end
				end
			end
		end
	end
end

function Hub.start()
	RunService.RenderStepped:Connect(function()
		local m = showcase
		if m and m.Parent then
			local base = Layout.RideShop + Vector3.new(0, 5.4, 0)
			m:PivotTo(CFrame.new(base + Vector3.new(0, math.sin(os.clock() * 2) * 0.3, 0)) * CFrame.Angles(0, os.clock() * 0.9, 0))
		end
	end)
	State.Changed:Connect(updateShowcase)
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
