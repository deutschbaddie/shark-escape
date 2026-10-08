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
local UserInputService = game:GetService("UserInputService")
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
local Travel = require(script.Parent.Travel)

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
HUD.atRideShop = nil :: (() -> boolean)?
HUD.onRebirth = nil :: (() -> ())?
HUD.onTank = nil :: (() -> ())?

function HUD.goToRideShop()
	Travel.go("Rides")
end

local function call(fn: (() -> ())?)
	if fn then
		fn()
	end
end

----------------------------------------------------------------- build
local friendLabel: TextLabel
local setSlow: ((boolean) -> ())? = nil
local leaveBanner: Frame

local function build()
	gui = Instance.new("ScreenGui")
	gui.Name = "HUD"
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = player:WaitForChild("PlayerGui")
	UI.autoScale(gui)

	-- left: wide menu buttons + Slow Mode (the classic simulator column)
	local menu = UI.frame(gui, { Name = "Menu", Size = UDim2.fromOffset(250, 300), Position = UDim2.new(0, 12, 0.46, 0), AnchorPoint = Vector2.new(0, 0.5), BackgroundTransparency = 1 })
	local list = Instance.new("UIListLayout")
	list.Padding = UDim.new(0, 10)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = menu
	menuButtons.Shop = UI.wideButton(menu, "Shop", "Shop", C.green, function()
		UI.clearBadge(menuButtons.Shop)
		call(HUD.onShop)
	end, { Size = UDim2.fromOffset(210, 72), LayoutOrder = 1, Visible = false })
	menuButtons.Index = UI.wideButton(menu, "Index", "Index", C.blue, function()
		call(HUD.onIndex)
	end, { Size = UDim2.fromOffset(210, 72), LayoutOrder = 2 })
	menuButtons.Rides = UI.wideButton(menu, "Rides", "Rides", C.orange, function()
		call(HUD.onRides)
	end, { Size = UDim2.fromOffset(210, 72), LayoutOrder = 3 })
	local _, set = UI.toggle(menu, "Slow Mode", false, function(on)
		State.action("slowMode", on)
	end, { LayoutOrder = 4 })
	setSlow = set

	-- right: square buttons (Tank, Rebirth)
	local right = UI.frame(gui, { Size = UDim2.fromOffset(92, 200), Position = UDim2.new(1, -12, 0.46, 0), AnchorPoint = Vector2.new(1, 0.5), BackgroundTransparency = 1 })
	local rl = Instance.new("UIListLayout")
	rl.Padding = UDim.new(0, 10)
	rl.HorizontalAlignment = Enum.HorizontalAlignment.Right
	rl.SortOrder = Enum.SortOrder.LayoutOrder
	rl.Parent = right
	menuButtons.Tank = UI.iconButton(right, "Tank", "Tank", C.orange, function()
		call(HUD.onTank)
	end, { Size = UDim2.fromOffset(88, 88), LayoutOrder = 1 })
	menuButtons.Rebirth = UI.iconButton(right, "Rebirth", "Rebirth", C.green, function()
		call(HUD.onRebirth)
	end, { Size = UDim2.fromOffset(88, 88), LayoutOrder = 2, Visible = false })

	-- bottom-left: the two big numbers + friend boost
	local stats = UI.frame(gui, { Name = "Stats", Size = UDim2.fromOffset(250, 150), Position = UDim2.new(0, 10, 1, -8), AnchorPoint = Vector2.new(0, 1), BackgroundTransparency = 1 })
	UI.icon(stats, "Sneaker", { Size = UDim2.fromOffset(64, 64), Position = UDim2.fromOffset(0, 0) })
	speedLabel = UI.outlined(stats, "0", { Size = UDim2.fromOffset(180, 54), Position = UDim2.fromOffset(68, 6), TextXAlignment = Enum.TextXAlignment.Left, Font = UI.NUMFONT })
	local sg = Instance.new("UIGradient")
	sg.Color = ColorSequence.new(Color3.fromRGB(255, 214, 60), Color3.fromRGB(255, 120, 20))
	sg.Rotation = 90
	sg.Parent = speedLabel
	UI.icon(stats, "Cash", { Size = UDim2.fromOffset(64, 64), Position = UDim2.fromOffset(0, 60) })
	coinsLabel = UI.outlined(stats, "$0", { Size = UDim2.fromOffset(180, 54), Position = UDim2.fromOffset(68, 66), TextXAlignment = Enum.TextXAlignment.Left, Font = UI.NUMFONT, TextColor3 = C.money })
	friendLabel = UI.outlined(stats, "Friend Boost +0%", { Size = UDim2.fromOffset(190, 24), Position = UDim2.fromOffset(4, 124), TextXAlignment = Enum.TextXAlignment.Left })
	local invite = UI.button(stats, "+", C.green, function()
		pcall(function()
			game:GetService("SocialService"):PromptGameInvite(player)
		end)
	end, { Size = UDim2.fromOffset(32, 32), Position = UDim2.fromOffset(200, 120) })
	invite.Name = "Invite"
	extrasLabel = UI.outlined(gui, "", { Size = UDim2.fromOffset(240, 22), Position = UDim2.new(0, 14, 1, -162), AnchorPoint = Vector2.new(0, 1), TextXAlignment = Enum.TextXAlignment.Left })

	-- bottom-center: gain line, goal bar, next ride
	local bottom = UI.frame(gui, { Name = "Bottom", Size = UDim2.fromOffset(440, 150), Position = UDim2.new(0.5, 0, 1, -10), AnchorPoint = Vector2.new(0.5, 1), BackgroundTransparency = 1 })
	gainLabel = UI.outlined(bottom, "+1 SPEED/S", { Size = UDim2.fromOffset(220, 28), Position = UDim2.fromOffset(4, 0), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = C.gold })
	tankLabel = UI.outlined(bottom, "", { Size = UDim2.fromOffset(220, 28), Position = UDim2.new(1, -4, 0, 0), AnchorPoint = Vector2.new(1, 0), TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = C.money })
	local _, gf, gl = UI.bar(bottom, C.blue, { Size = UDim2.new(1, 0, 0, 46), Position = UDim2.fromOffset(0, 32) })
	goalFill, goalText = gf, gl
	goalText.TextXAlignment = Enum.TextXAlignment.Left
	rideBtn = UI.button(bottom, "", C.gold, function()
		local d = State.data
		local nxt = d and HUD.nextRide(d)
		if nxt and d.coins >= nxt.price and HUD.atRideShop and HUD.atRideShop() then
			State.action("buyRide", nxt.id)
		else
			HUD.goToRideShop()
		end
	end, { Size = UDim2.new(1, 0, 0, 62), Position = UDim2.fromOffset(0, 88) })
	local rlab = rideBtn:FindFirstChild("Label") :: TextLabel
	rlab.Size = UDim2.new(1, -16, 0, 30)
	rlab.Position = UDim2.new(0.5, 0, 0, 6)
	rlab.AnchorPoint = Vector2.new(0.5, 0)
	ridePrice = UI.outlined(rideBtn, "", { Size = UDim2.new(1, -16, 0, 18), Position = UDim2.new(0.5, 0, 0, 34), AnchorPoint = Vector2.new(0.5, 0), ZIndex = rideBtn.ZIndex + 1 })
	local rb = UI.frame(rideBtn, { Size = UDim2.new(1, -20, 0, 5), Position = UDim2.new(0, 10, 1, -9), BackgroundColor3 = Color3.fromRGB(0, 0, 0), BackgroundTransparency = 0.5, ZIndex = rideBtn.ZIndex + 1 })
	UI.corner(rb, 3)
	rideFill = UI.frame(rb, { Size = UDim2.fromScale(0, 1), BackgroundColor3 = C.white, ZIndex = rb.ZIndex + 1 })
	UI.corner(rideFill, 3)

	carryChip = UI.outlined(gui, "", { Size = UDim2.fromOffset(460, 28), Position = UDim2.new(0.5, 0, 1, -168), AnchorPoint = Vector2.new(0.5, 1), Visible = false })

	-- bottom-right: shark timer (icon + "in 1m 40s" over a soft dark fade)
	timerPill = UI.frame(gui, { Size = UDim2.fromOffset(300, 70), Position = UDim2.new(1, 0, 1, 0), AnchorPoint = Vector2.new(1, 1),
		BackgroundColor3 = Color3.fromRGB(0, 0, 0), BackgroundTransparency = 0.4 })
	local fade = Instance.new("UIGradient")
	fade.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.35, 0.3), NumberSequenceKeypoint.new(1, 0.2) })
	fade.Parent = timerPill
	UI.icon(timerPill, "Shark", { Size = UDim2.fromOffset(62, 62), Position = UDim2.new(0, 46, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5) })
	timerLabel = UI.outlined(timerPill, "", { Size = UDim2.new(1, -124, 0, 44), Position = UDim2.new(0, 112, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5), TextXAlignment = Enum.TextXAlignment.Left, Font = UI.NUMFONT })

	-- top-center
	distLabel = UI.outlined(gui, "", { Size = UDim2.fromOffset(300, 56), Position = UDim2.new(0.5, 0, 0, 76), AnchorPoint = Vector2.new(0.5, 0), Font = UI.NUMFONT, TextColor3 = C.gold, Visible = false })
	zoneTitle = UI.outlined(gui, "", { Size = UDim2.fromOffset(620, 90), Position = UDim2.new(0.5, 0, 0.3, 0), AnchorPoint = Vector2.new(0.5, 0.5), TextColor3 = Color3.fromRGB(70, 230, 230), Visible = false })
	hintLabel = UI.outlined(gui, "", { Size = UDim2.fromOffset(520, 34), Position = UDim2.new(0.5, 0, 0, 136), AnchorPoint = Vector2.new(0.5, 0), Visible = false })
	alertLabel = UI.outlined(gui, "", { Size = UDim2.fromOffset(600, 50), Position = UDim2.new(0.5, 0, 0, 136), AnchorPoint = Vector2.new(0.5, 0), Visible = false, TextColor3 = C.red })

	-- "you earn $X/day offline" banner (at your dock, and when you open the menu to leave)
	leaveBanner = UI.frame(gui, { Size = UDim2.fromOffset(560, 54), Position = UDim2.new(0.5, 0, 0, 8), AnchorPoint = Vector2.new(0.5, 0),
		BackgroundColor3 = Color3.fromRGB(30, 34, 60), Visible = false })
	UI.corner(leaveBanner, 12)
	UI.stroke(leaveBanner, C.ink, 3)
	UI.shade(leaveBanner)
	UI.outlined(leaveBanner, "", { Name = "Text", Size = UDim2.new(1, -20, 1, -12), Position = UDim2.fromOffset(10, 6), TextColor3 = Color3.fromRGB(190, 225, 255) })

	-- toasts
	toastHolder = UI.frame(gui, { Size = UDim2.fromOffset(460, 200), Position = UDim2.new(0.5, 0, 0, 190), AnchorPoint = Vector2.new(0.5, 0), BackgroundTransparency = 1 })
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

	-- touch screens: the thumbstick and jump button own the bottom corners
	if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		stats.AnchorPoint = Vector2.new(0, 0)
		stats.Position = UDim2.fromOffset(10, 4)
		extrasLabel.AnchorPoint = Vector2.new(0, 0)
		extrasLabel.Position = UDim2.fromOffset(14, 156)
		menu.Position = UDim2.new(0, 12, 0.5, 0)
		timerPill.AnchorPoint = Vector2.new(1, 0)
		timerPill.Position = UDim2.new(1, 0, 0, 60)
	end
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

-- Toasts queue up: at most 2 on screen, spaced out, duplicates dropped,
-- held back during cutscenes. Keeps the screen readable when a lot happens.
local toastQueue: { { text: string, color: Color3?, duration: number? } } = {}
local toastsShown = 0
local lastToastAt = 0
local pumpToasts: () -> ()

local function showToast(item: { text: string, color: Color3?, duration: number? })
	toastsShown += 1
	lastToastAt = os.clock()
	local t = UI.frame(toastHolder, { Size = UDim2.fromOffset(420, 38), BackgroundColor3 = item.color or C.panel })
	UI.corner(t, 10)
	UI.stroke(t, C.ink, 3)
	UI.shade(t)
	local label = UI.outlined(t, item.text, { Size = UDim2.new(1, -16, 1, -10), Position = UDim2.fromOffset(8, 5) })
	UI.pop(t, 1.15)
	task.delay(item.duration or 3, function()
		TweenService:Create(t, TweenInfo.new(0.3), { BackgroundTransparency = 1 }):Play()
		TweenService:Create(label, TweenInfo.new(0.3), { TextTransparency = 1 }):Play()
		task.wait(0.3)
		t:Destroy()
		toastsShown -= 1
		pumpToasts()
	end)
end

pumpToasts = function()
	if #toastQueue == 0 or toastsShown >= 2 or player:GetAttribute("Cinematic") then
		return
	end
	local wait = 0.45 - (os.clock() - lastToastAt)
	if wait > 0 then
		task.delay(wait, pumpToasts)
		return
	end
	showToast(table.remove(toastQueue, 1) :: any)
	if #toastQueue > 0 then
		task.delay(0.45, pumpToasts)
	end
end

function HUD.toast(text: string, color: Color3?, duration: number?)
	for _, q in toastQueue do
		if q.text == text then
			return
		end
	end
	table.insert(toastQueue, { text = text, color = color, duration = duration })
	while #toastQueue > 3 do
		table.remove(toastQueue, 1) -- stale news goes first
	end
	pumpToasts()
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
local lastSlow = false
local shopShown = false
local function render(d: any)
	speedLabel.Text = UI.short(d.speed)
	if math.floor(d.speed) ~= lastSpeed then
		lastSpeed = math.floor(d.speed)
	end
	coinsLabel.Text = "$" .. UI.short(d.coins)
	local mult = Config.Rebirth.mult ^ d.rebirths
	gainLabel.Text = mult > 1 and ("+%s SPEED/S  (x%s)"):format(UI.short(d.gain), string.format("%g", math.floor(mult * 100 + 0.5) / 100))
		or ("+%s SPEED/S"):format(UI.short(d.gain))
	tankLabel.Text = ("🐟 %d/%d  +$%s/s"):format(d.active, d.slots, UI.short(d.income))
	friendLabel.Text = ("Friend Boost +%d%%"):format(math.floor(d.friendBoost * 100 + 0.5))
	if setSlow and d.slow ~= lastSlow then
		lastSlow = d.slow
		setSlow(d.slow)
	end
	-- "!" on the Tank when a stored creature would earn more than an active one
	local minActive, bestStored = math.huge, 0
	for _, c in d.creatures do
		if c.e then
			minActive = math.min(minActive, c.v)
		else
			bestStored = math.max(bestStored, c.v)
		end
	end
	if bestStored > 0 and (d.active < d.slots or bestStored > minActive) then
		UI.badge(menuButtons.Tank)
	else
		UI.clearBadge(menuButtons.Tank)
	end
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
		local here = HUD.atRideShop and HUD.atRideShop()
		UI.setText(rideBtn, afford and (here and ("%s BUY %s!"):format(nxt.icon, nxt.name:upper()) or ("%s GET %s!"):format(nxt.icon, nxt.name:upper())) or ("%s %s"):format(nxt.icon, nxt.name))
		ridePrice.Text = ("+%d/s  ·  $%s"):format(nxt.gain or 0, UI.short(nxt.price))
		rideFill.Size = UDim2.fromScale(math.clamp(d.coins / nxt.price, 0, 1), 1)
		rideBtn.BackgroundColor3 = afford and C.green or C.gold
		HUD.pulseRide(afford)
		if afford then
			UI.badge(menuButtons.Rides)
		else
			UI.clearBadge(menuButtons.Rides)
		end
	end

	-- carrying
	if d.carrying then
		local r = Config.rarity(d.carrying.r)
		local sp = Config.species(d.carrying.z, d.carrying.r)
		carryChip.Visible = true
		carryChip.TextColor3 = r.color
		carryChip.Text = ("%s %s → bring it to your dock! 🏠"):format(sp.icon, Config.creatureName(d.carrying.z, d.carrying.r, d.carrying.m))
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

local menuOpen = false
local function updateLeaveBanner(pos: Vector3?)
	local d = State.data
	local atDock = false
	if d and pos and d.plot > 0 then
		local tank = Layout.tankPos(Layout.Plots[d.plot])
		atDock = Vector2.new(pos.X - tank.X, pos.Z - tank.Z).Magnitude < 26 and not Layout.inWater(pos)
	end
	local show = d ~= nil and (menuOpen or atDock) and not player:GetAttribute("Cinematic")
	leaveBanner.Visible = show
	if show then
		local text = leaveBanner:FindFirstChild("Text") :: TextLabel
		text.Text = d.income > 0 and ("💤 Your tank earns $%s / day while you're offline!"):format(UI.short(Config.offlinePerDay(d.income)))
			or "💤 Put creatures in your tank to earn while you're offline!"
	end
end

local function frame()
	local pos = myPos()
	updateLeaveBanner(pos)
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
	-- during a hunt: one clear line about YOUR situation
	if phase == "hunt" and pos then
		local safe = Layout.isSafe(pos)
		local mine = SharkView.myHunter()
		local text, color
		if mine and mine.state == "chase" then
			text, color = "🦈 IT'S CHARGING! GET TO SAND!", C.red
		elseif mine then
			text, color = "🦈 A SHARK IS CIRCLING YOU! FOLLOW THE ARROW!", C.red
		elseif safe then
			text, color = "🏝️ You're safe here. Wait it out!", C.green
		else
			text, color = "🦈 SHARKS ARE HUNTING! GET TO SAND!", C.red
		end
		if alertLabel.Text ~= text then
			alertLabel.Visible = true
			alertLabel.Text = text
			alertLabel.TextColor3 = color
			UI.pop(alertLabel, 1.15)
		end
		vignette.Visible = not safe
	end
	local left = math.max(0, phaseEnds - os.clock())
	if phase == "calm" then
		timerLabel.Text = "in " .. UI.timeWords(left)
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

local newDiscovery = false -- "discover" arrives just before "grab"; one toast says both

handlers.grab = function(d)
	local r = Config.rarity(d.r)
	local sp = Config.species(d.z, d.r)
	local pos = myPos()
	if pos then
		Fx.sparkle(pos + Vector3.new(0, 3, 0), r.color, 20 + r.index * 12)
		Fx.popup3D(pos + Vector3.new(0, 5, 0), ("+%s/s"):format(UI.short(d.v)), r.color)
	end
	Fx.sound("grab", 0.6, 1 + r.index * 0.05)
	if d.lucky then
		Fx.bigWord("🍀 LUCKY! " .. d.r:upper(), C.green, 1.2)
	elseif d.pity then
		Fx.bigWord(("✨ %s %s!"):format(d.r:upper(), sp.name:upper()), r.color, 1.2)
	elseif r.index >= 3 then
		Fx.bigWord(d.r:upper() .. "!", r.color, 1.1)
	end
	if r.index >= 4 then
		Fx.shake(1.5)
		Fx.sound("legendary", 0.8)
	end
	local note = ""
	if newDiscovery then
		note = "  📖 NEW!"
	end
	newDiscovery = false
	HUD.toast(("%s %s  +$%s/s%s"):format(sp.icon, Config.creatureName(d.z, d.r, d.m), UI.short(d.v), note), r.color)
end

handlers.discover = function(d)
	newDiscovery = true
	UI.pop(menuButtons.Index, 1.3)
end

handlers.indexClaim = function(d)
	Fx.bigWord("📖 CLAIMED!", C.orange, 1)
	HUD.toast(("+$%s  +⚡%s"):format(UI.short(d.coins), UI.short(d.speed)), C.green, 3)
	UI.pop(coinsLabel, 1.3)
	UI.pop(speedLabel, 1.3)
	Fx.sound("coin", 0.7)
end

handlers.deposit = function(d)
	local r = Config.rarity(d.r)
	local data = State.data
	if not (data and data.plot > 0) then
		return
	end
	-- everything is shown right at the tank, where it happens
	local tank = Layout.tankPos(Layout.Plots[data.plot])
	Fx.sparkle(tank + Vector3.new(0, 6, 0), r.color, 40)
	if d.active then
		Fx.popup3D(tank + Vector3.new(0, 11, 0), ("+$%s/s"):format(UI.short(d.v)), C.money, true)
	else
		Fx.popup3D(tank + Vector3.new(0, 11, 0), "📦 Stored", C.sky, true)
	end
	if d.swapped then
		task.delay(0.7, function()
			Fx.popup3D(tank + Vector3.new(0, 14, 0), ("↻ %s → storage"):format(d.swapped), C.sky, false)
		end)
	end
	if d.sold then
		task.delay(1.2, function()
			Fx.popup3D(tank + Vector3.new(0, 15, 0), ("Storage full · sold %s +$%s"):format(d.soldName or "", UI.short(d.sold)), C.gold, false)
		end)
	end
end

handlers.code = function(d)
	if d.ok then
		local bits = {}
		if d.coins then
			table.insert(bits, "+$" .. UI.short(d.coins))
		end
		if d.speed then
			table.insert(bits, "+⚡" .. UI.short(d.speed))
		end
		if d.shields then
			table.insert(bits, "+🛡️" .. d.shields)
		end
		Fx.bigWord("🎟️ CODE REDEEMED!", C.green, 1.1)
		HUD.toast(table.concat(bits, "  "), C.green, 3)
		Fx.sound("coin", 0.7)
	else
		HUD.toast("❌ " .. tostring(d.text), C.red, 2.5)
	end
end

handlers.collect = function(d)
	local pos = myPos()
	if pos then
		Fx.confetti(pos, { C.money, C.gold })
		Fx.popup3D(pos + Vector3.new(0, 5, 0), "+$" .. UI.short(d.amount), C.money, true)
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

handlers.rideShop = function()
	HUD.goToRideShop()
end

handlers.slot = function(d)
	HUD.toast(("🐟 Tank now holds %d!"):format(d.slots), C.green)
end

handlers.unlock = function(d)
	local zone = Config.zoneById(d.zone)
	if zone then
		Fx.bigWord("🔓 " .. zone.name:upper() .. "!", C.gold, 1.6)
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

handlers.lost = function()
	-- the bite cutscene shows this (your creature gets eaten on screen)
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
				alertLabel.Text = ("🦈 SHARK INCOMING IN %d! GET TO SAND!"):format(left)
				local p = myPos()
				vignette.Visible = p ~= nil and not Layout.isSafe(p)
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
		setAlert("🦈 SHARKS ARE HUNTING! GET TO SAND!")
		Water.setSafeGlow(true)
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
	-- opening the Roblox menu (usually to leave): remind what the tank earns offline
	local GuiService = game:GetService("GuiService")
	GuiService.MenuOpened:Connect(function()
		menuOpen = true
	end)
	GuiService.MenuClosed:Connect(function()
		menuOpen = false
	end)
	player:GetAttributeChangedSignal("Cinematic"):Connect(function()
		local on = player:GetAttribute("Cinematic") == true
		gui.Enabled = not on
		if on then
			vignette.Visible = false
		else
			pumpToasts()
		end
	end)
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
