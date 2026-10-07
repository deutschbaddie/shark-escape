-- The always-on screen, simulator style. One obvious next thing, big and tappable.
--   left:          square menu buttons (Rides, Shop, Index, Rebirth) with "!" badges
--   bottom-left:   big SPEED and COINS numbers
--   bottom-center: +speed/sec, the zone goal bar, NEXT RIDE and +1 SLOT buttons
--   bottom-right:  shark timer
--   top-center:    offer banner (when the shop is open), distance, zone titles, alerts

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local MarketplaceService = game:GetService("MarketplaceService")

local Shared = game.ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Layout = require(Shared.Layout)
local Remotes = require(Shared.Remotes)
local UI = require(script.Parent.UI)
local Fx = require(script.Parent.Fx)
local State = require(script.Parent.State)
local Water = require(script.Parent.Water)
local SharkView = require(script.Parent.SharkView)

local HUD = {}
local C = UI.C
local player = Players.LocalPlayer

local gui: ScreenGui
local speedLabel: TextLabel
local coinsLabel: TextLabel
local gainLabel: TextLabel
local tankLabel: TextLabel
local extrasLabel: TextLabel
local goalFill: Frame
local goalText: TextLabel
local rideBtn: TextButton
local ridePrice: TextLabel
local rideFill: Frame
local slotBtn: TextButton
local carryChip: TextLabel
local hintLabel: TextLabel
local toastHolder: Frame
local alertLabel: TextLabel
local vignette: Frame
local menuButtons: { [string]: TextButton } = {}
local timerPill: Frame
local timerLabel: TextLabel
local distLabel: TextLabel
local zoneTitle: TextLabel
local promo: TextButton?
local stopRidePulse: (() -> ())? = nil

HUD.onRides = nil :: (() -> ())?
HUD.onShop = nil :: (() -> ())?
HUD.onIndex = nil :: (() -> ())?

local function call(fn: (() -> ())?)
	if fn then
		fn()
	end
end

----------------------------------------------------------------- build
local function build()
	gui = Instance.new("ScreenGui")
	gui.Name = "HUD"
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = player:WaitForChild("PlayerGui")
	local scale = Instance.new("UIScale")
	scale.Parent = gui
	local function rescale()
		local v = Workspace.CurrentCamera.ViewportSize
		scale.Scale = math.clamp(math.min(v.X / 960, v.Y / 560), 0.55, 1.3)
	end
	rescale()
	Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(rescale)

	-- left menu: 2-wide grid of square buttons
	local menu = UI.frame(gui, { Name = "Menu", Size = UDim2.fromOffset(184, 190), Position = UDim2.new(0, 14, 0.5, -10), AnchorPoint = Vector2.new(0, 0.5), BackgroundTransparency = 1 })
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.fromOffset(86, 86)
	grid.CellPadding = UDim2.fromOffset(10, 10)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = menu
	menuButtons.Rides = UI.iconButton(menu, "🛟", "Rides", C.sky, function()
		call(HUD.onRides)
	end, { LayoutOrder = 1 })
	menuButtons.Index = UI.iconButton(menu, "📖", "Index", C.orange, function()
		call(HUD.onIndex)
	end, { LayoutOrder = 2 })
	menuButtons.Shop = UI.iconButton(menu, "🛒", "Shop", C.pink, function()
		UI.clearBadge(menuButtons.Shop)
		call(HUD.onShop)
	end, { LayoutOrder = 3, Visible = false })
	menuButtons.Rebirth = UI.iconButton(menu, "🔁", "Rebirth", C.green, function()
		State.action("rebirth")
	end, { LayoutOrder = 4, Visible = false })

	-- bottom-left: the two big numbers
	local stats = UI.frame(gui, { Size = UDim2.fromOffset(300, 120), Position = UDim2.new(0, 14, 1, -10), AnchorPoint = Vector2.new(0, 1), BackgroundTransparency = 1 })
	UI.text(stats, "⚡", { Size = UDim2.fromOffset(52, 52), Position = UDim2.fromOffset(0, 4) })
	speedLabel = UI.outlined(stats, "0", { Size = UDim2.fromOffset(240, 52), Position = UDim2.fromOffset(58, 4), TextXAlignment = Enum.TextXAlignment.Left, Font = UI.NUMFONT })
	UI.text(stats, "💰", { Size = UDim2.fromOffset(52, 52), Position = UDim2.fromOffset(0, 62) })
	coinsLabel = UI.outlined(stats, "0", { Size = UDim2.fromOffset(240, 52), Position = UDim2.fromOffset(58, 62), TextXAlignment = Enum.TextXAlignment.Left, Font = UI.NUMFONT, TextColor3 = C.money })
	extrasLabel = UI.outlined(gui, "", { Size = UDim2.fromOffset(280, 24), Position = UDim2.new(0, 16, 1, -134), AnchorPoint = Vector2.new(0, 1), TextXAlignment = Enum.TextXAlignment.Left })

	-- bottom-center: gain line, goal bar, buttons
	local bottom = UI.frame(gui, { Name = "Bottom", Size = UDim2.fromOffset(470, 150), Position = UDim2.new(0.5, 0, 1, -10), AnchorPoint = Vector2.new(0.5, 1), BackgroundTransparency = 1 })
	gainLabel = UI.outlined(bottom, "⚡ +1 SPEED/S", { Size = UDim2.fromOffset(240, 28), Position = UDim2.fromOffset(4, 0), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = C.gold })
	tankLabel = UI.outlined(bottom, "", { Size = UDim2.fromOffset(220, 28), Position = UDim2.new(1, -4, 0, 0), AnchorPoint = Vector2.new(1, 0), TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = C.gold })
	local _, gf, gl = UI.bar(bottom, C.blue, { Size = UDim2.new(1, 0, 0, 46), Position = UDim2.fromOffset(0, 32) })
	goalFill, goalText = gf, gl
	goalText.TextXAlignment = Enum.TextXAlignment.Left
	rideBtn = UI.button(bottom, "", C.gold, function()
		local d = State.data
		local nxt = d and HUD.nextRide(d)
		if nxt and d.coins >= nxt.price then
			State.action("buyRide", nxt.id)
		else
			call(HUD.onRides)
		end
	end, { Size = UDim2.new(0.66, -5, 0, 62), Position = UDim2.fromOffset(0, 88) })
	local rl = rideBtn:FindFirstChild("Label") :: TextLabel
	rl.Size = UDim2.new(1, -16, 0, 30)
	rl.Position = UDim2.new(0.5, 0, 0, 6)
	rl.AnchorPoint = Vector2.new(0.5, 0)
	ridePrice = UI.outlined(rideBtn, "", { Size = UDim2.new(1, -16, 0, 18), Position = UDim2.new(0.5, 0, 0, 34), AnchorPoint = Vector2.new(0.5, 0), ZIndex = rideBtn.ZIndex + 1 })
	local rb = UI.frame(rideBtn, { Size = UDim2.new(1, -20, 0, 5), Position = UDim2.new(0, 10, 1, -9), BackgroundColor3 = Color3.fromRGB(0, 0, 0), BackgroundTransparency = 0.5, ZIndex = rideBtn.ZIndex + 1 })
	UI.corner(rb, 3)
	rideFill = UI.frame(rb, { Size = UDim2.fromScale(0, 1), BackgroundColor3 = C.white, ZIndex = rb.ZIndex + 1 })
	UI.corner(rideFill, 3)
	slotBtn = UI.button(bottom, "", C.sky, function()
		local d = State.data
		if d and d.slotPrice and d.coins >= d.slotPrice then
			State.action("buySlot")
		else
			call(HUD.onRides)
		end
	end, { Size = UDim2.new(0.34, -5, 0, 62), Position = UDim2.new(1, 0, 0, 88), AnchorPoint = Vector2.new(1, 0) })

	carryChip = UI.outlined(gui, "", { Size = UDim2.fromOffset(460, 28), Position = UDim2.new(0.5, 0, 1, -168), AnchorPoint = Vector2.new(0.5, 1), Visible = false })

	-- bottom-right: shark timer pill
	timerPill = UI.frame(gui, { Size = UDim2.fromOffset(190, 48), Position = UDim2.new(1, -14, 1, -12), AnchorPoint = Vector2.new(1, 1),
		BackgroundColor3 = Color3.fromRGB(0, 0, 0), BackgroundTransparency = 0.55 })
	UI.corner(timerPill, 24)
	UI.text(timerPill, "🦈", { Size = UDim2.fromOffset(40, 40), Position = UDim2.fromOffset(8, 4) })
	timerLabel = UI.outlined(timerPill, "", { Size = UDim2.new(1, -60, 1, -12), Position = UDim2.fromOffset(52, 6), TextXAlignment = Enum.TextXAlignment.Left, Font = UI.NUMFONT })

	-- top-center
	distLabel = UI.outlined(gui, "", { Size = UDim2.fromOffset(300, 56), Position = UDim2.new(0.5, 0, 0, 76), AnchorPoint = Vector2.new(0.5, 0), Font = UI.NUMFONT, TextColor3 = C.gold, Visible = false })
	zoneTitle = UI.outlined(gui, "", { Size = UDim2.fromOffset(620, 90), Position = UDim2.new(0.5, 0, 0.3, 0), AnchorPoint = Vector2.new(0.5, 0.5), TextColor3 = Color3.fromRGB(70, 230, 230), Visible = false })
	hintLabel = UI.outlined(gui, "", { Size = UDim2.fromOffset(560, 40), Position = UDim2.new(0.5, 0, 0, 136), AnchorPoint = Vector2.new(0.5, 0), Visible = false })
	alertLabel = UI.outlined(gui, "", { Size = UDim2.fromOffset(600, 56), Position = UDim2.new(0.5, 0, 0, 136), AnchorPoint = Vector2.new(0.5, 0), Visible = false, TextColor3 = C.red })

	-- toasts
	toastHolder = UI.frame(gui, { Size = UDim2.fromOffset(460, 200), Position = UDim2.new(0.5, 0, 0, 196), AnchorPoint = Vector2.new(0.5, 0), BackgroundTransparency = 1 })
	local tl = Instance.new("UIListLayout")
	tl.Padding = UDim.new(0, 6)
	tl.HorizontalAlignment = Enum.HorizontalAlignment.Center
	tl.Parent = toastHolder

	-- shark alert vignette
	vignette = UI.frame(Fx.screen(), { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Name = "Vignette", ZIndex = 2 })
	for _, spec in { { UDim2.new(1, 0, 0.22, 0), UDim2.fromScale(0, 0), 90 }, { UDim2.new(1, 0, 0.22, 0), UDim2.fromScale(0, 0.78), -90 },
		{ UDim2.new(0.16, 0, 1, 0), UDim2.fromScale(0, 0), 0 }, { UDim2.new(0.16, 0, 1, 0), UDim2.fromScale(0.84, 0), 180 } } do
		local f = UI.frame(vignette, { Size = spec[1], Position = spec[2], BackgroundColor3 = Color3.fromRGB(255, 30, 50), BackgroundTransparency = 0 })
		local g = Instance.new("UIGradient")
		g.Rotation = spec[3]
		g.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(1, 1) })
		g.Parent = f
	end
	vignette.Visible = false
end

-- top banner offer: the best pass you don't own yet (only once the shop is open)
local function updatePromo(d: any)
	local want: string? = nil
	if d.playtime >= Config.SHOP_UNLOCK_SECONDS then
		for _, key in { "TwoXSpeed", "TwoXCoins", "AutoCollect" } do
			local pass = Config.Passes[key]
			if pass.id ~= 0 and not d.passes[key] then
				want = key
				break
			end
		end
	end
	if not want then
		if promo then
			promo:Destroy()
			promo = nil
		end
		return
	end
	if promo and promo:GetAttribute("Key") == want then
		return
	end
	if promo then
		promo:Destroy()
	end
	local pass = Config.Passes[want]
	local b = UI.button(gui, ("%s %s"):format(pass.icon, pass.name:upper()), C.red, function()
		MarketplaceService:PromptGamePassPurchase(player, pass.id)
	end, { Size = UDim2.fromOffset(250, 64), Position = UDim2.new(0.5, 0, 0, 6), AnchorPoint = Vector2.new(0.5, 0) })
	b:SetAttribute("Key", want)
	local l = b:FindFirstChild("Label") :: TextLabel
	l.Size = UDim2.new(1, -16, 0, 32)
	l.Position = UDim2.new(0.5, 0, 0, 5)
	l.AnchorPoint = Vector2.new(0.5, 0)
	UI.outlined(b, ("ONLY R$%d"):format(pass.price), { Size = UDim2.new(1, -16, 0, 20), Position = UDim2.new(0.5, 0, 1, -10), AnchorPoint = Vector2.new(0.5, 1), TextColor3 = C.gold, ZIndex = b.ZIndex + 1 })
	promo = b
end

----------------------------------------------------------------- helpers
function HUD.nextRide(d: any): Config.Ride?
	for _, ride in Config.Rides do
		if not ride.robux and not d.rides[ride.id] then
			return ride
		end
	end
	return nil
end

function HUD.toast(text: string, color: Color3?, duration: number?)
	local t = UI.frame(toastHolder, { Size = UDim2.fromOffset(440, 40), BackgroundColor3 = color or C.panel })
	UI.corner(t, 10)
	UI.stroke(t, C.ink, 3)
	UI.shade(t)
	UI.outlined(t, text, { Size = UDim2.new(1, -16, 1, -10), Position = UDim2.fromOffset(8, 5) })
	UI.pop(t, 1.2)
	task.delay(duration or 2.6, function()
		TweenService:Create(t, TweenInfo.new(0.25), { BackgroundTransparency = 1 }):Play()
		task.wait(0.25)
		t:Destroy()
	end)
	local frames = {}
	for _, k in toastHolder:GetChildren() do
		if k:IsA("Frame") then
			table.insert(frames, k)
		end
	end
	if #frames > 3 then
		frames[1]:Destroy()
	end
end

function HUD.hint(text: string?)
	hintLabel.Visible = text ~= nil and not alertLabel.Visible
	if text and hintLabel.Text ~= text then
		hintLabel.Text = text
		UI.pop(hintLabel, 1.2)
	end
end

function HUD.pulseRide(on: boolean)
	if on and not stopRidePulse then
		stopRidePulse = UI.pulse(rideBtn)
	elseif not on and stopRidePulse then
		stopRidePulse()
		stopRidePulse = nil
	end
end

function HUD.rideButton(): GuiObject
	return rideBtn
end

function HUD.menuButton(name: string): GuiObject?
	return menuButtons[name]
end

local function unclaimed(d: any): number
	local n = 0
	for key in d.index do
		if not d.claimed[key] then
			n += 1
		end
	end
	return n
end

----------------------------------------------------------------- render state
local lastSpeed = -1
local shopShown = false
local function render(d: any)
	speedLabel.Text = UI.short(d.speed)
	if math.floor(d.speed) ~= lastSpeed then
		lastSpeed = math.floor(d.speed)
	end
	coinsLabel.Text = UI.short(d.coins)
	local mult = Config.Rebirth.mult ^ d.rebirths
	gainLabel.Text = ("⚡ +%s SPEED/S"):format(UI.short(d.gain))
	tankLabel.Text = mult > 1 and ("x%s Rebirth"):format(string.format("%g", math.floor(mult * 100 + 0.5) / 100)) or ("🐟 %d/%d Tank"):format(#d.tank, d.slots)
	local extras = {}
	if d.shields > 0 then
		table.insert(extras, "🛡️" .. d.shields)
	end
	if d.boostLeft > 0 then
		table.insert(extras, "⏩" .. UI.time(d.boostLeft))
	end
	if d.luckLeft > 0 then
		table.insert(extras, "🧪" .. UI.time(d.luckLeft))
	end
	if d.income > 0 then
		table.insert(extras, ("💰+%s/s"):format(UI.short(d.income)))
	end
	extrasLabel.Text = table.concat(extras, "   ")

	-- goal: next zone gate, or rebirth
	local gate = Config.nextGate(d.speed)
	if gate then
		local prevGate = 0
		for _, z in Config.Zones do
			if z.gate <= d.speed then
				prevGate = z.gate
			end
		end
		goalText.Text = ("🔒 %s   %s / %s"):format(gate.name, UI.short(d.speed), UI.short(gate.gate))
		goalFill.Size = UDim2.fromScale(math.clamp((d.speed - prevGate) / (gate.gate - prevGate), 0.02, 1), 1)
		goalFill.BackgroundColor3 = C.blue
	else
		local ready = d.speed >= Config.Rebirth.speed
		goalText.Text = ready and "🔁 REBIRTH READY!" or ("🔁 Rebirth at ⚡%s"):format(UI.short(Config.Rebirth.speed))
		goalFill.Size = UDim2.fromScale(math.clamp(d.speed / Config.Rebirth.speed, 0.02, 1), 1)
		goalFill.BackgroundColor3 = C.green
	end
	menuButtons.Rebirth.Visible = d.speed >= Config.Rebirth.speed
	local shopOpen = d.playtime >= Config.SHOP_UNLOCK_SECONDS or d.rides.Duck == true
	if shopOpen and not menuButtons.Shop.Visible then
		menuButtons.Shop.Visible = true
		if not shopShown then
			shopShown = true
			UI.badge(menuButtons.Shop)
		end
	end
	local n = unclaimed(d)
	if n > 0 then
		UI.badge(menuButtons.Index, tostring(n))
	else
		UI.clearBadge(menuButtons.Index)
	end

	-- next ride
	local nxt = HUD.nextRide(d)
	rideBtn.Visible = nxt ~= nil
	if nxt then
		local afford = d.coins >= nxt.price
		UI.setText(rideBtn, afford and ("%s BUY %s!"):format(nxt.icon, nxt.name:upper()) or ("%s %s"):format(nxt.icon, nxt.name))
		ridePrice.Text = ("+%d/s  ·  💰 %s"):format(nxt.gain or 0, UI.short(nxt.price))
		rideFill.Size = UDim2.fromScale(math.clamp(d.coins / nxt.price, 0, 1), 1)
		rideBtn.BackgroundColor3 = afford and C.green or C.gold
		HUD.pulseRide(afford)
		if afford then
			UI.badge(menuButtons.Rides)
		else
			UI.clearBadge(menuButtons.Rides)
		end
	end
	if d.slotPrice then
		slotBtn.Visible = true
		UI.setText(slotBtn, ("🐟 +1 SLOT\n💰 %s"):format(UI.short(d.slotPrice)))
		slotBtn.BackgroundColor3 = d.coins >= d.slotPrice and C.green or C.sky
	else
		slotBtn.Visible = false
	end

	-- carrying
	if d.carrying then
		local r = Config.rarity(d.carrying.r)
		carryChip.Visible = true
		carryChip.TextColor3 = r.color
		carryChip.Text = ("%s %s%s → bring it to your dock! 🏠"):format(r.icon, d.carrying.m and (d.carrying.m .. " ") or "", r.species)
	else
		carryChip.Visible = false
	end
	updatePromo(d)
end

----------------------------------------------------------------- per-frame: distance, zone titles, shark timer
local phase = "calm"
local phaseEnds = os.clock() + Config.Shark.firstAttack
local lastZone: string? = nil
local titleToken = 0

local function myPos(): Vector3?
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	return hrp and hrp.Position
end

local function showZoneTitle(name: string, color: Color3)
	titleToken += 1
	local token = titleToken
	zoneTitle.Text = "🌴 " .. name .. " 🌴"
	zoneTitle.TextColor3 = color
	zoneTitle.Visible = true
	zoneTitle.TextTransparency = 0
	UI.pop(zoneTitle, 1.6)
	task.delay(2.4, function()
		if titleToken == token then
			TweenService:Create(zoneTitle, TweenInfo.new(0.5), { TextTransparency = 1 }):Play()
			task.wait(0.5)
			if titleToken == token then
				zoneTitle.Visible = false
			end
		end
	end)
end

local function frame()
	local pos = myPos()
	if pos then
		local wet = Layout.inWater(pos)
		distLabel.Visible = wet and not alertLabel.Visible
		if wet then
			distLabel.Text = ("%d m"):format(math.floor((pos.Z - Config.SHORE_Z) / 3.5))
		end
		local zone = Config.zoneAt(pos.Z)
		local id = zone and zone.id or "Beach"
		if id ~= lastZone then
			if lastZone ~= nil then
				if zone then
					showZoneTitle(zone.name, zone.water:Lerp(Color3.new(1, 1, 1), 0.35))
				else
					showZoneTitle("Shark Beach", Color3.fromRGB(255, 220, 120))
				end
			end
			lastZone = id
		end
	end
	local left = math.max(0, phaseEnds - os.clock())
	if phase == "calm" then
		timerLabel.Text = "in " .. UI.time(left)
		timerLabel.TextColor3 = left < 10 and C.gold or C.white
		timerPill.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	else
		timerLabel.Text = (phase == "warning" and "COMING " or "HUNTING ") .. math.ceil(left)
		timerLabel.TextColor3 = C.white
		timerPill.BackgroundColor3 = C.red
	end
end

----------------------------------------------------------------- notifications
local handlers: { [string]: (any) -> () } = {}

handlers.grab = function(d)
	local r = Config.rarity(d.r)
	local pos = myPos()
	if pos then
		Fx.sparkle(pos + Vector3.new(0, 3, 0), r.color, 20 + r.index * 12)
		Fx.popup3D(pos + Vector3.new(0, 5, 0), ("+%s/s"):format(UI.short(d.v)), r.color)
	end
	Fx.sound("grab", 0.6, 1 + r.index * 0.05)
	if d.lucky then
		Fx.bigWord("🍀 LUCKY! " .. d.r:upper(), C.green, 1.2)
	elseif d.pity then
		Fx.bigWord("✨ RARE " .. r.species:upper() .. "!", r.color, 1.2)
	elseif r.index >= 3 then
		Fx.bigWord(d.r:upper() .. "!", r.color, 1.1)
	end
	if r.index >= 4 then
		Fx.shake(1.5)
		Fx.sound("legendary", 0.8)
	end
	HUD.toast(("%s Got %s%s! (+%s/s)"):format(r.icon, d.m and (d.m .. " ") or "", r.species, UI.short(d.v)), r.color)
end

handlers.discover = function(d)
	local r = Config.rarity(d.r)
	local zone = Config.zoneById(d.z)
	HUD.toast(("📖 NEW! %s %s added to your Index"):format(zone and zone.name or "", r.species), C.orange, 3)
	UI.pop(menuButtons.Index, 1.3)
end

handlers.indexClaim = function(d)
	Fx.bigWord("📖 CLAIMED!", C.orange, 1)
	HUD.toast(("+💰%s  +⚡%s"):format(UI.short(d.coins), UI.short(d.speed)), C.green, 3)
	UI.pop(coinsLabel, 1.3)
	UI.pop(speedLabel, 1.3)
	Fx.sound("coin", 0.7)
end

handlers.deposit = function(d)
	local r = Config.rarity(d.r)
	local data = State.data
	if data and data.plot > 0 then
		local tank = Layout.tankPos(Layout.Plots[data.plot])
		Fx.sparkle(tank + Vector3.new(0, 5, 0), r.color, 40)
		Fx.popup3D(tank + Vector3.new(0, 10, 0), ("+%s 💰/s"):format(UI.short(d.v)), C.money, true)
	end
	if d.replaced then
		HUD.toast(("Swapped out a %s (+%s 💰)"):format(Config.rarity(d.replaced).species, UI.short(d.sold or 0)), C.blue)
	end
end

handlers.sold = function(d)
	HUD.toast(("Tank full! Sold %s for %s 💰"):format(Config.rarity(d.r).species, UI.short(d.sold)), C.blue)
end

handlers.collect = function(d)
	local pos = myPos()
	if pos then
		Fx.confetti(pos, { C.money, C.gold })
		Fx.popup3D(pos + Vector3.new(0, 5, 0), "+" .. UI.short(d.amount) .. " 💰", C.money, true)
	end
	Fx.sound("coin", 0.7)
	UI.pop(coinsLabel, 1.35)
end

handlers.ride = function(d)
	local ride = Config.ride(d.id)
	local pos = myPos()
	if pos then
		Fx.confetti(pos)
		Fx.splash(Vector3.new(pos.X, 0.5, pos.Z), 1.2)
	end
	Fx.sound("buy", 0.8)
	Fx.bigWord(("%s NEW RIDE!"):format(ride and ride.icon or ""), C.gold, 1.2)
	HUD.toast(("Now gaining +%s speed every second!"):format(UI.short(d.gain)), C.green)
	UI.pop(gainLabel, 1.5)
end

handlers.slot = function(d)
	HUD.toast(("🐟 Tank now holds %d!"):format(d.slots), C.green)
end

handlers.unlock = function(d)
	local zone = Config.zoneById(d.zone)
	if zone then
		Fx.bigWord("🔓 " .. zone.name:upper() .. "!", C.gold, 1.6)
		HUD.toast(("%s unlocked - %s sharks live there!"):format(zone.name, zone.shark), C.pink, 3.5)
		local pos = myPos()
		if pos then
			Fx.confetti(pos)
		end
	end
end

handlers.gate = function(d)
	Fx.bigWord(("🔒 NEED ⚡%s"):format(UI.short(d.need)), C.red, 1.2)
	Fx.shake(1)
end

handlers.lost = function(d)
	HUD.toast(("💔 The shark ate your %s!"):format(Config.rarity(d.r).species), C.red, 3)
end

handlers.spat = function()
	local pos = myPos()
	if pos then
		Fx.splash(Vector3.new(pos.X, 0.5, pos.Z + 4), 1.6)
	end
	-- the shark spits you back toward the beach
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if hrp then
		hrp.AssemblyLinearVelocity = Vector3.new(0, 60, -55)
	end
	Fx.bigWord("PTOOEY!", C.sky, 1)
	local d = State.data
	if d and d.playtime >= Config.SHOP_UNLOCK_SECONDS and Config.Products.Shield.id ~= 0 then
		local b = UI.button(gui, "🛡️ Shield next time  R$" .. Config.Products.Shield.price, C.sky, function()
			MarketplaceService:PromptProductPurchase(player, Config.Products.Shield.id)
		end, { Size = UDim2.fromOffset(300, 50), Position = UDim2.new(0.5, 0, 1, -176), AnchorPoint = Vector2.new(0.5, 1) })
		task.delay(6, function()
			b:Destroy()
		end)
	end
end

handlers.shield = function()
	HUD.toast("🛡️ Your shield blocked the bite!", C.sky)
end

handlers.rebirth = function(d)
	Fx.bigWord("🔁 REBIRTH!", C.green, 1.6)
	Fx.flash(Color3.new(1, 1, 1), 0.8, 0)
	HUD.toast(("Permanent x%s speed gain!"):format(tostring(Config.Rebirth.mult ^ d.rebirths)), C.green, 4)
end

handlers.purchase = function(d)
	Fx.bigWord("🎉 THANK YOU!", C.pink, 1.2)
	HUD.toast(d.name .. " is yours!", C.pink, 3)
	local pos = myPos()
	if pos then
		Fx.confetti(pos)
	end
end

handlers.announce = function(d)
	HUD.toast(d.text, d.color or C.panel, 4)
end

----------------------------------------------------------------- shark phases
local alertToken = 0
local function setAlert(text: string?, color: Color3?)
	alertToken += 1
	alertLabel.Visible = text ~= nil
	if text then
		alertLabel.Text = text
		alertLabel.TextColor3 = color or C.red
		UI.pop(alertLabel, 1.3)
		hintLabel.Visible = false
	end
end

local function myZone(): Config.Zone?
	local pos = myPos()
	return pos and Config.zoneAt(pos.Z)
end

local function onPhase(kind: string, data: any)
	if kind == "warning" then
		phase, phaseEnds = "warning", os.clock() + (data.duration or 5)
		setAlert("🦈 SHARK ATTACK IN 5!")
		local token = alertToken
		vignette.Visible = true
		Water.setSafeGlow(true)
		Fx.sound("sharkAlarm", 0.8)
		-- the horizon breach: a shark leaps where you can see it
		local zone = myZone()
		local pos = myPos()
		if zone and pos then
			local cam = Workspace.CurrentCamera
			local look = cam.CFrame.LookVector * Vector3.new(1, 0, 1)
			local dir = look.Magnitude > 0.1 and look.Unit or Vector3.new(0, 0, 1)
			local at = pos + dir * math.max(70, zone.sharkLength * 4)
			local side = Vector3.new(dir.Z, 0, -dir.X)
			SharkView.breach(zone.shark, zone.sharkLength, at - side * zone.sharkLength * 0.8, math.atan2(-side.X, -side.Z))
		end
		task.spawn(function()
			local t0 = os.clock()
			while alertToken == token and os.clock() - t0 < (data.duration or 5) do
				local left = math.ceil((data.duration or 5) - (os.clock() - t0))
				alertLabel.Text = ("🦈 SHARK ATTACK IN %d! GET ON SAND!"):format(left)
				for _, f in vignette:GetChildren() do
					if f:IsA("Frame") then
						f.BackgroundTransparency = 0.3 + 0.4 * (0.5 + 0.5 * math.sin(os.clock() * 10))
					end
				end
				task.wait()
			end
		end)
	elseif kind == "hunt" then
		phase, phaseEnds = "hunt", os.clock() + (data.duration or Config.Shark.hunt)
		setAlert("🦈 SHARKS ARE HUNTING! STAY ON SAND!")
		vignette.Visible = true
		Water.setSafeGlow(true)
		Fx.shake(1)
	elseif kind == "clear" then
		phase, phaseEnds = "calm", os.clock() + (data.next or Config.Shark.cycle)
		local wasOn = vignette.Visible
		vignette.Visible = false
		Water.setSafeGlow(false)
		if wasOn then
			setAlert("✅ SAFE! Sharks are gone", C.green)
			local token = alertToken
			task.delay(2, function()
				if alertToken == token then
					setAlert(nil)
				end
			end)
		else
			setAlert(nil)
		end
	end
end

----------------------------------------------------------------- start
function HUD.start()
	build()
	State.Changed:Connect(render)
	if State.data then
		render(State.data)
	end
	RunService.Heartbeat:Connect(frame)
	Remotes.get("Notify").OnClientEvent:Connect(function(kind, data)
		local fn = handlers[kind]
		if fn then
			fn(data)
		end
	end)
	Remotes.get("SharkEvent").OnClientEvent:Connect(function(kind, data)
		if kind ~= "bite" then
			onPhase(kind, data or {})
		end
	end)
end

return HUD
