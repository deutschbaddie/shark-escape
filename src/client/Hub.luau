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
local Sell = require(script.Parent.Sell)
local Guide = require(script.Parent.Guide)

local Hub = {}
local C = UI.C
local player = Players.LocalPlayer

----------------------------------------------------------------- welcome back
-- the standard popup's body parts (UI.popup): its value label and buttons
local function popupParts(win: Frame, value: string): (TextLabel?, { TextButton })
	local body = win:FindFirstChild("Body")
	local label: TextLabel? = nil
	local buttons = {}
	if body then
		for _, k in body:GetChildren() do
			if k:IsA("TextLabel") and k.Text == value then
				label = k
			elseif k:IsA("TextButton") then
				table.insert(buttons, k)
			end
		end
	end
	return label, buttons
end

local welcomeShown = false
local function welcome(amount: number)
	welcomeShown = true
	local win = Shop.popup({
		title = "Welcome Back!",
		icon = "Clock",
		color = C.blue,
		text = ("Your tank earned while you were away! (%d%% rate, up to %dh)"):format(math.floor(Config.Offline.rate * 100), Config.Offline.maxHours),
		value = "+$0",
		primary = { text = "CLAIM", color = C.green }, -- closing banks the coins (below)
		secondary = { text = "Later" },
	})
	local value, buttons = popupParts(win, "+$0")
	-- the amount counts up
	if value then
		value.Font = UI.NUMFONT
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
	end
	-- Robux 2x replaces the secondary button (it must not close: closing banks 1x)
	local prod = Config.Products.DoubleOffline
	local secondary = buttons[2]
	if prod.id ~= 0 and secondary then
		local props = { Size = secondary.Size, Position = secondary.Position, AnchorPoint = secondary.AnchorPoint }
		local parent = secondary.Parent
		secondary:Destroy()
		UI.button(parent, ("2x  R$ %d"):format(prod.price), UI.T.gold, function()
			MarketplaceService:PromptProductPurchase(player, prod.id)
		end, props)
	end
	-- closing any way still banks the coins
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
local function multText(m: number): string
	return "x" .. string.format("%g", math.floor(m * 100) / 100)
end

function Hub.confirmRebirth()
	local d = State.data
	if not d or d.speed < Config.Rebirth.speed then
		return
	end
	local now = Config.Rebirth.mult ^ d.rebirths
	local nextMult = Config.Rebirth.mult ^ (d.rebirths + 1)
	local win = Shop.popup({
		title = "Rebirth?",
		icon = "Rebirth",
		color = C.purple,
		text = "Start over for a permanent speed gain boost.",
		value = ("%s  →  %s"):format(multText(now), multText(nextMult)),
		valueColor = C.gold,
		primary = { text = "REBIRTH", color = C.green, fn = function()
			State.action("rebirth")
		end },
		secondary = { text = "Cancel" },
	})
	-- what resets / what stays, between the value and the buttons
	local body = win:FindFirstChild("Body") :: Frame
	local box = UI.inset(body, { Size = UDim2.new(1, 0, 0, 60), Position = UDim2.fromOffset(0, 104) })
	UI.label(box, "meta", "RESETS: speed, coins, rides", { Size = UDim2.new(1, -24, 0, 20), Position = UDim2.fromOffset(12, 8),
		TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = UI.light(C.red, 0.35) })
	UI.label(box, "meta", "KEEPS: tank, Index, shields, Robux items", { Size = UDim2.new(1, -24, 0, 20), Position = UDim2.fromOffset(12, 32),
		TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = C.money })
	local _, buttons = popupParts(win, "")
	if buttons[1] then
		UI.pulse(buttons[1])
	end
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
	Sell = function()
		Sell.open()
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
		if on then
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
		label.Text = nxt.name
		local can = d.coins >= nxt.price
		sub.Text = can and ("$%s  ·  +%d/s  ·  STEP ON THE PAD!"):format(UI.short(nxt.price), nxt.gain or 0)
			or ("$%s  ·  +%d speed/sec"):format(UI.short(nxt.price), nxt.gain or 0)
		sub.TextColor3 = can and C.money or C.gold
	else
		label.Text = "Every ride owned!"
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
						t.Text = (open and "%s" or "%s"):format(g:GetAttribute("ZoneName"))
						t.TextColor3 = open and C.money or C.white
					end
					if sub then
						sub.Text = open and "Unlocked!" or ("Need %s speed · you have %s"):format(UI.short(need), UI.short(d.speed))
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
