-- The always-on screen in the Steal-an-Egg style: small, bright, studded,
-- one obvious next thing.
--   left:          Shop / Index / Rides buttons + the Slow Mode box
--   right:         small squares: Tank, Rebirth, offers and active boosts
--                  (time left above the square)
--   bottom-left:   speed (sneaker) and money, Friend Boost
--   bottom-center: +speed/s and tank $/s, zone goal bar, next ride button
--   bottom-right:  next shark attack
-- Every message goes through Notify: one hierarchy, nothing piles up.

local Players = game:GetService("Players")
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
local Travel = require(script.Parent.Travel)
local Notify = require(script.Parent.Notify)

local HUD = {}
local C = UI.C
local player = Players.LocalPlayer

local gui: ScreenGui
local speedLabel: TextLabel
local coinsLabel: TextLabel
local gainLabel: TextLabel
local tankLabel: TextLabel
local friendLabel: TextLabel
local goalFill: Frame
local goalText: TextLabel
local rideBtn: TextButton
local ridePrice: TextLabel
local rideFill: Frame
local carryChip: TextLabel
local vignette: Frame
local menuButtons: { [string]: TextButton } = {}
local boostSquares: { [string]: { holder: Frame, button: TextButton, timer: TextLabel } } = {}
local timerPill: Frame
local timerLabel: TextLabel
local stopRidePulse: (() -> ())? = nil
local setSlow: ((boolean) -> ())? = nil

HUD.onRides = nil :: (() -> ())?
HUD.onShop = nil :: (() -> ())?
HUD.onIndex = nil :: (() -> ())?
HUD.atRideShop = nil :: (() -> boolean)?
HUD.onRebirth = nil :: (() -> ())?
HUD.onTank = nil :: (() -> ())?
HUD.takeover = false

function HUD.goToRideShop()
	Travel.go("Rides")
end

local function call(fn: (() -> ())?)
	if fn then
		fn()
	end
end

----------------------------------------------------------------- build
local function square(parent: Instance, icon: string, color: Color3, order: number, onClick: () -> ()): TextButton
	return UI.iconButton(parent, icon, "", color, onClick, { Size = UDim2.fromOffset(62, 62), LayoutOrder = order })
end

-- a square with a little timer over it (active boosts, like the reference potion)
local function timedSquare(parent: Instance, key: string, icon: string, color: Color3, order: number)
	local holder = UI.frame(parent, { Name = key, Size = UDim2.fromOffset(66, 84), BackgroundTransparency = 1, LayoutOrder = order, Visible = false })
	local timer = UI.outlined(holder, "", { Size = UDim2.new(1, 16, 0, 18), Position = UDim2.new(0.5, 0, 0, 0), AnchorPoint = Vector2.new(0.5, 0), TextColor3 = C.orange })
	local b = UI.iconButton(holder, icon, "", color, function()
		call(HUD.onShop)
	end, { Size = UDim2.fromOffset(62, 62), Position = UDim2.new(0.5, 0, 1, 0), AnchorPoint = Vector2.new(0.5, 1) })
	boostSquares[key] = { holder = holder, button = b, timer = timer }
end

local function build()
	gui = Instance.new("ScreenGui")
	gui.Name = "HUD"
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = player:WaitForChild("PlayerGui")
	UI.autoScale(gui)

	-- left: menu buttons + Slow Mode
	local menu = UI.frame(gui, { Name = "Menu", Size = UDim2.fromOffset(180, 250), Position = UDim2.new(0, 10, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5), BackgroundTransparency = 1 })
	local list = Instance.new("UIListLayout")
	list.Padding = UDim.new(0, 8)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.VerticalAlignment = Enum.VerticalAlignment.Center
	list.Parent = menu
	local size = UDim2.fromOffset(170, 56)
	menuButtons.Shop = UI.wideButton(menu, "Shop", "Shop", C.green, function()
		UI.clearBadge(menuButtons.Shop)
		call(HUD.onShop)
	end, { Size = size, LayoutOrder = 1, Visible = false })
	menuButtons.Index = UI.wideButton(menu, "Index", "Index", C.index, function()
		call(HUD.onIndex)
	end, { Size = size, LayoutOrder = 2 })
	menuButtons.Rides = UI.wideButton(menu, "Rides", "Rides", C.orange, function()
		call(HUD.onRides)
	end, { Size = size, LayoutOrder = 3 })
	local _, set = UI.toggle(menu, "Slow Mode", false, function(on)
		State.action("slowMode", on)
	end, { LayoutOrder = 4 })
	setSlow = set

	-- right: small squares
	local right = UI.frame(gui, { Name = "Right", Size = UDim2.fromOffset(70, 420), Position = UDim2.new(1, -10, 0.5, 0), AnchorPoint = Vector2.new(1, 0.5), BackgroundTransparency = 1 })
	local rl = Instance.new("UIListLayout")
	rl.Padding = UDim.new(0, 8)
	rl.HorizontalAlignment = Enum.HorizontalAlignment.Right
	rl.VerticalAlignment = Enum.VerticalAlignment.Center
	rl.SortOrder = Enum.SortOrder.LayoutOrder
	rl.Parent = right
	menuButtons.Tank = square(right, "Tank", C.orange, 1, function()
		call(HUD.onTank)
	end)
	menuButtons.Rebirth = square(right, "Rebirth", C.green, 2, function()
		call(HUD.onRebirth)
	end)
	menuButtons.Rebirth.Visible = false
	menuButtons.Offer = square(right, "X2Speed", C.red, 3, function() end)
	menuButtons.Offer.Visible = false
	timedSquare(right, "Shield", "Shield", C.sky, 4)
	timedSquare(right, "Boost", "Boost", C.purple, 5)
	timedSquare(right, "Luck", "Potion", C.green, 6)

	-- bottom-left: speed + money (the font's own $), friend boost
	local stats = UI.frame(gui, { Name = "Stats", Size = UDim2.fromOffset(250, 124), Position = UDim2.new(0, 12, 1, -8), AnchorPoint = Vector2.new(0, 1), BackgroundTransparency = 1 })
	UI.icon(stats, "Sneaker", { Size = UDim2.fromOffset(46, 46), Position = UDim2.fromOffset(0, 0) })
	speedLabel = UI.outlined(stats, "0", { Size = UDim2.fromOffset(196, 42), Position = UDim2.fromOffset(52, 3), TextXAlignment = Enum.TextXAlignment.Left, Font = UI.NUMFONT })
	local sg = Instance.new("UIGradient")
	sg.Color = ColorSequence.new(Color3.fromRGB(255, 214, 60), Color3.fromRGB(255, 120, 20))
	sg.Rotation = 90
	sg.Parent = speedLabel
	coinsLabel = UI.outlined(stats, "$0", { Size = UDim2.fromOffset(246, 42), Position = UDim2.fromOffset(2, 50), TextXAlignment = Enum.TextXAlignment.Left, Font = UI.NUMFONT, TextColor3 = C.money })
	friendLabel = UI.outlined(stats, "Friend Boost +0%", { Size = UDim2.fromOffset(170, 20), Position = UDim2.fromOffset(3, 99), TextXAlignment = Enum.TextXAlignment.Left })
	local invite = UI.button(stats, "+", C.green, function()
		pcall(function()
			game:GetService("SocialService"):PromptGameInvite(player)
		end)
	end, { Size = UDim2.fromOffset(26, 26), Position = UDim2.fromOffset(178, 96) })
	invite.Name = "Invite"

	-- bottom-center: gain line, goal bar, next ride
	local bottom = UI.frame(gui, { Name = "Bottom", Size = UDim2.fromOffset(380, 120), Position = UDim2.new(0.5, 0, 1, -8), AnchorPoint = Vector2.new(0.5, 1), BackgroundTransparency = 1 })
	gainLabel = UI.outlined(bottom, "+1 SPEED/S", { Size = UDim2.fromOffset(186, 20), Position = UDim2.fromOffset(2, 0), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = C.gold })
	tankLabel = UI.outlined(bottom, "", { Size = UDim2.fromOffset(186, 20), Position = UDim2.new(1, -2, 0, 0), AnchorPoint = Vector2.new(1, 0), TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = C.money })
	local _, gf, gl = UI.bar(bottom, C.blue, { Size = UDim2.new(1, 0, 0, 32), Position = UDim2.fromOffset(0, 24) })
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
	end, { Size = UDim2.new(1, 0, 0, 56), Position = UDim2.fromOffset(0, 64) })
	local rlab = rideBtn:FindFirstChild("Label") :: TextLabel
	rlab.Size = UDim2.new(1, -16, 0, 26)
	rlab.Position = UDim2.new(0.5, 0, 0, 5)
	rlab.AnchorPoint = Vector2.new(0.5, 0)
	ridePrice = UI.outlined(rideBtn, "", { Size = UDim2.new(1, -16, 0, 15), Position = UDim2.new(0.5, 0, 0, 31), AnchorPoint = Vector2.new(0.5, 0), ZIndex = rideBtn.ZIndex + 1 })
	local rb = UI.frame(rideBtn, { Size = UDim2.new(1, -20, 0, 4), Position = UDim2.new(0, 10, 1, -8), BackgroundColor3 = Color3.fromRGB(0, 0, 0), BackgroundTransparency = 0.5, ZIndex = rideBtn.ZIndex + 1 })
	UI.corner(rb, 2)
	rideFill = UI.frame(rb, { Size = UDim2.fromScale(0, 1), BackgroundColor3 = C.white, ZIndex = rb.ZIndex + 1 })
	UI.corner(rideFill, 2)

	carryChip = UI.outlined(gui, "", { Size = UDim2.fromOffset(520, 24), Position = UDim2.new(0.5, 0, 1, -136), AnchorPoint = Vector2.new(0.5, 1), Visible = false })

	-- bottom-right: next shark attack ("in 1m 40s" over a soft fade)
	timerPill = UI.frame(gui, { Name = "Timer", Size = UDim2.fromOffset(250, 58), Position = UDim2.new(1, 0, 1, 0), AnchorPoint = Vector2.new(1, 1),
		BackgroundColor3 = Color3.fromRGB(0, 0, 0), BackgroundTransparency = 0.45 })
	local fade = Instance.new("UIGradient")
	fade.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.35, 0.35), NumberSequenceKeypoint.new(1, 0.25) })
	fade.Parent = timerPill
	UI.icon(timerPill, "Shark", { Size = UDim2.fromOffset(46, 46), Position = UDim2.new(0, 46, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5) })
	timerLabel = UI.outlined(timerPill, "", { Size = UDim2.new(1, -108, 0, 34), Position = UDim2.new(0, 98, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5), TextXAlignment = Enum.TextXAlignment.Left, Font = UI.NUMFONT })

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

	-- touch screens: the thumbstick and jump button own the bottom corners,
	-- so the numbers go top-left and the timer top-right
	if UI.TOUCH then
		stats.AnchorPoint = Vector2.new(0, 0)
		stats.Position = UDim2.fromOffset(12, 4)
		timerPill.AnchorPoint = Vector2.new(1, 0)
		timerPill.Position = UDim2.new(1, 0, 0, 4)
		menu.Position = UDim2.new(0, 10, 0.5, 20)
		right.Position = UDim2.new(1, -10, 0.46, 0)
		right.Size = UDim2.fromOffset(70, 330)
		bottom.Position = UDim2.new(0.5, 0, 1, -6)
		carryChip.Position = UDim2.new(0.5, 0, 1, -132)
	end
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

-- kept for other modules: plain toast / tutorial hint
function HUD.toast(text: string, color: Color3?, _duration: number?)
	Notify.toast(text, color)
end

function HUD.hint(text: string?)
	if text then
		Notify.banner(text, { key = "tut", sticky = true, priority = 3 })
	else
		Notify.clear("tut")
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

-- the best pass you don't own yet, as a red square (only once the shop is open)
local function updateOffer(d: any)
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
	local b = menuButtons.Offer
	b.Visible = want ~= nil
	if want and b:GetAttribute("Key") ~= want then
		b:SetAttribute("Key", want)
		local pass = Config.Passes[want]
		local old = b:FindFirstChild("Icon")
		if old then
			old:Destroy()
		end
		UI.icon(b, pass.iconName or "X2Speed", { Size = UDim2.fromScale(0.74, 0.74), Position = UDim2.fromScale(0.5, 0.47), AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = b.ZIndex + 1 })
		UI.badge(b, "R$")
	end
end

local function offerClicked()
	local key = menuButtons.Offer:GetAttribute("Key")
	local pass = key and Config.Passes[key]
	if pass and pass.id ~= 0 then
		MarketplaceService:PromptGamePassPurchase(player, pass.id)
	end
end

----------------------------------------------------------------- render state
local lastSlow = false
local shopShown = false
local function render(d: any)
	speedLabel.Text = UI.short(d.speed)
	coinsLabel.Text = "$" .. UI.short(d.coins)
	local mult = Config.Rebirth.mult ^ d.rebirths
	gainLabel.Text = mult > 1 and ("+%s SPEED/S (x%s)"):format(UI.short(d.gain), string.format("%g", math.floor(mult * 100 + 0.5) / 100))
		or ("+%s SPEED/S"):format(UI.short(d.gain))
	tankLabel.Text = ("%d/%d Active  +$%s/s"):format(d.active, d.slots, UI.short(d.income))
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
	-- boosts: square + time left
	local function boost(key: string, on: boolean, timerText: string?, badge: string?)
		local sq = boostSquares[key]
		sq.holder.Visible = on
		sq.timer.Text = timerText or ""
		if badge then
			UI.badge(sq.button, badge)
		end
	end
	boost("Shield", d.shields > 0, nil, tostring(d.shields))
	boost("Boost", d.boostLeft > 0, UI.timeWords(d.boostLeft))
	boost("Luck", d.luckLeft > 0, UI.timeWords(d.luckLeft))

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
		goalText.Text = ready and "🔁 REBIRTH READY!" or ("🔁 Rebirth at %s speed"):format(UI.short(Config.Rebirth.speed))
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
		ridePrice.Text = ("+%d speed/s  ·  $%s"):format(nxt.gain or 0, UI.short(nxt.price))
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
		carryChip.Text = ("%s %s → bring it home to your tank!"):format(sp.icon, Config.creatureName(d.carrying.z, d.carrying.r, d.carrying.m))
	else
		carryChip.Visible = false
	end
	updateOffer(d)
end

----------------------------------------------------------------- per-frame: status line, zone titles, shark state, timer
local phase = "calm"
local phaseEnds = os.clock() + Config.Shark.firstAttack
local lastZone: string? = nil
local quietTitlesUntil = 0 -- no "Shark Beach" title right after you wash up
local menuOpen = false

local function myPos(): Vector3?
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	return hrp and hrp.Position
end

local function atMyDock(pos: Vector3?): boolean
	local d = State.data
	if not (d and pos and d.plot > 0) then
		return false
	end
	local tank = Layout.tankPos(Layout.Plots[d.plot])
	return Vector2.new(pos.X - tank.X, pos.Z - tank.Z).Magnitude < 26 and not Layout.inWater(pos)
end

local function statusLine(pos: Vector3?)
	local d = State.data
	if not (d and pos) then
		Notify.status(nil)
		return
	end
	if menuOpen or atMyDock(pos) then
		-- what the tank earns while you're away (shown when you open the menu to leave)
		Notify.status(d.income > 0 and ("💤 Your tank earns $%s / day while you're offline"):format(UI.short(Config.offlinePerDay(d.income)))
			or "💤 Put creatures in your tank to earn while you're offline", Color3.fromRGB(190, 225, 255))
	elseif Layout.inWater(pos) then
		local zone = Config.zoneAt(pos.Z)
		Notify.status(("%s · %d m"):format(zone and zone.name or "Lagoon", math.floor((pos.Z - Config.SHORE_Z) / 3.5)), C.white)
	else
		Notify.status(nil)
	end
end

local function sharkLine(pos: Vector3)
	local safe = Layout.isSafe(pos)
	local left = math.max(0, math.ceil(phaseEnds - os.clock()))
	local text, sub, color
	if phase == "warning" then
		if safe then
			text, sub, color = ("🦈 Shark attack in %d"):format(left), "You're safe here", C.green
		else
			text, sub, color = ("🦈 SHARK ATTACK IN %d!"):format(left), "Get to sand or an island", C.red
		end
	else
		local mine = SharkView.myHunter()
		if mine and mine.state == "chase" then
			text, sub, color = "🦈 IT'S CHARGING!", "Swerve at the last second, or reach sand!", C.red
		elseif mine and mine.state == "stalk" then
			text, sub, color = "🦈 A SHARK IS CIRCLING YOU!", "Follow the arrow to safety", C.red
		elseif safe then
			text, sub, color = ("🏝️ Safe here · sharks leave in %d"):format(left), nil, C.green
		else
			text, sub, color = "🦈 SHARKS ARE HUNTING!", "Catches are luckier right now... if you dare", C.gold
		end
	end
	Notify.banner(text, { key = "shark", sticky = true, priority = 5, sub = sub, color = color })
	vignette.Visible = not safe and not player:GetAttribute("Cinematic")
end

local function frame()
	local pos = myPos()
	statusLine(pos)
	if pos then
		local zone = Config.zoneAt(pos.Z)
		local id = zone and zone.id or "Beach"
		if id ~= lastZone then
			if lastZone ~= nil and os.clock() > quietTitlesUntil then
				if zone then
					Notify.banner(zone.name, { key = "zone", priority = 2, time = 2.2, color = zone.water:Lerp(Color3.new(1, 1, 1), 0.45),
						sub = ("🦈 %s waters"):format((zone.shark:gsub("(%l)(%u)", "%1 %2"))) })
				else
					Notify.banner("Shark Beach", { key = "zone", priority = 2, time = 1.8, color = Color3.fromRGB(255, 220, 120), sub = "Sand is always safe" })
				end
			end
			lastZone = id
		end
		if phase ~= "calm" then
			sharkLine(pos)
		end
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
	local name = Config.creatureName(d.z, d.r, d.m)
	local pos = myPos()
	if pos then
		Fx.sparkle(pos + Vector3.new(0, 3, 0), r.color, 20 + r.index * 12)
		Fx.popup3D(pos + Vector3.new(0, 5, 0), ("+$%s/s"):format(UI.short(d.v)), r.color)
	end
	Fx.sound("grab", 0.6, 1 + r.index * 0.05)
	-- the bigger the catch, the bigger the moment
	if r.index >= 5 then
		Notify.takeover("LEGENDARY!", ("%s %s"):format(sp.icon, name), r.color, 1.8)
		Fx.shake(1.5)
		Fx.sound("legendary", 0.8)
	elseif d.lucky then
		Notify.word("🍀 LUCKY " .. d.r:upper() .. "!", C.green, 1)
	elseif d.pity or r.index >= 3 then
		Notify.word(d.r:upper() .. "!", r.color, 1)
		if r.index >= 4 then
			Fx.sound("legendary", 0.6)
		end
	end
	local note = newDiscovery and "  · NEW!" or ""
	newDiscovery = false
	Notify.toast(("%s %s  +$%s/s%s"):format(sp.icon, name, UI.short(d.v), note), r.color)
end

handlers.discover = function()
	newDiscovery = true
	UI.pop(menuButtons.Index, 1.3)
end

handlers.indexClaim = function(d)
	Notify.word("📖 CLAIMED!", C.orange, 0.9)
	Notify.toast(("+$%s  +%s speed"):format(UI.short(d.coins), UI.short(d.speed)), C.green)
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
			table.insert(bits, ("+%s speed"):format(UI.short(d.speed)))
		end
		if d.shields then
			table.insert(bits, ("+%d shield"):format(d.shields))
		end
		Notify.word("🎟️ CODE REDEEMED!", C.green, 1)
		Notify.toast(table.concat(bits, "  "), C.green)
		Fx.sound("coin", 0.7)
	else
		Notify.toast("❌ " .. tostring(d.text), C.red)
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
	Notify.takeover("NEW RIDE!", ("%s %s · +%s speed every second"):format(ride and ride.icon or "", ride and ride.name or "", UI.short(d.gain)), C.gold, 1.6)
	UI.pop(gainLabel, 1.5)
end

handlers.rideShop = function()
	HUD.goToRideShop()
end

handlers.slot = function(d)
	Notify.toast(("🐟 Your tank now holds %d!"):format(d.slots), C.green)
end

handlers.unlock = function(d)
	local zone = Config.zoneById(d.zone)
	if zone then
		Notify.takeover(zone.name:upper() .. "!", "New zone unlocked · rarer creatures, bigger sharks", C.gold, 1.8)
		local pos = myPos()
		if pos then
			Fx.confetti(pos)
		end
	end
end

handlers.gate = function(d)
	Notify.word(("🔒 NEED %s SPEED"):format(UI.short(d.need)), C.red, 1)
	Fx.shake(1)
end

handlers.lost = function()
	-- the bite cutscene shows this (your creature gets eaten on screen)
end

handlers.spat = function()
	quietTitlesUntil = os.clock() + 3
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
	Notify.word("PTOOEY!", C.sky, 1)
	local d = State.data
	if d and d.playtime >= Config.SHOP_UNLOCK_SECONDS and Config.Products.Shield.id ~= 0 then
		local b = UI.button(gui, "🛡️ Shield next time  R$" .. Config.Products.Shield.price, C.sky, function()
			MarketplaceService:PromptProductPurchase(player, Config.Products.Shield.id)
		end, { Size = UDim2.fromOffset(260, 44), Position = UDim2.new(0.5, 0, 1, -168), AnchorPoint = Vector2.new(0.5, 1) })
		task.delay(6, function()
			b:Destroy()
		end)
	end
end

handlers.shield = function()
	Notify.toast("🛡️ Your shield blocked the bite!", C.sky)
end

handlers.rebirth = function(d)
	Fx.flash(Color3.new(1, 1, 1), 0.8, 0)
	Notify.takeover("REBIRTH!", ("Permanent x%s speed gain"):format(tostring(Config.Rebirth.mult ^ d.rebirths)), C.green, 2)
end

handlers.purchase = function(d)
	Notify.takeover("THANK YOU!", d.name .. " is yours!", C.pink, 1.6)
	local pos = myPos()
	if pos then
		Fx.confetti(pos)
	end
end

handlers.announce = function(d)
	Notify.toast(d.text, d.color or C.gold)
end

----------------------------------------------------------------- shark phases
local function myZone(): Config.Zone?
	local pos = myPos()
	return pos and Config.zoneAt(pos.Z)
end

local function onPhase(kind: string, data: any)
	if kind == "warning" then
		phase, phaseEnds = "warning", os.clock() + (data.duration or 5)
		local pos = myPos()
		local exposed = pos ~= nil and not Layout.isSafe(pos)
		Notify.takeover("SHARK INCOMING!", exposed and "Get to sand or an island!" or "Stay on the sand and you're safe", C.red, 1.4)
		Water.setSafeGlow(true)
		Fx.sound("sharkAlarm", 0.8)
		-- the horizon breach: a shark leaps where you can see it
		local zone = myZone()
		if zone and pos then
			local cam = Workspace.CurrentCamera
			local look = cam.CFrame.LookVector * Vector3.new(1, 0, 1)
			local dir = look.Magnitude > 0.1 and look.Unit or Vector3.new(0, 0, 1)
			local at = pos + dir * math.max(70, zone.sharkLength * 4)
			local side = Vector3.new(dir.Z, 0, -dir.X)
			SharkView.breach(zone.shark, zone.sharkLength, at - side * zone.sharkLength * 0.8, math.atan2(-side.X, -side.Z))
		end
		task.spawn(function()
			while phase == "warning" do
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
		Water.setSafeGlow(true)
	elseif kind == "clear" then
		local was = phase ~= "calm"
		phase, phaseEnds = "calm", os.clock() + (data.next or Config.Shark.cycle)
		vignette.Visible = false
		Water.setSafeGlow(false)
		Notify.clear("shark")
		if was then
			Notify.toast("✅ The sharks are gone. Back to the water!", C.green)
		end
	end
end

----------------------------------------------------------------- start
function HUD.start()
	Notify.start()
	build()
	menuButtons.Offer.Activated:Connect(offerClicked)
	State.Changed:Connect(render)
	if State.data then
		render(State.data)
	end
	RunService.Heartbeat:Connect(frame)
	-- opening the Roblox menu (usually to leave): show what the tank earns offline
	local GuiService = game:GetService("GuiService")
	GuiService.MenuOpened:Connect(function()
		menuOpen = true
	end)
	GuiService.MenuClosed:Connect(function()
		menuOpen = false
	end)
	-- big moments, cutscenes and the tank view get the screen to themselves
	local function refreshVisible()
		local cine = player:GetAttribute("Cinematic") == true
		local viewing = player:GetAttribute("ViewingTank") == true
		gui.Enabled = not cine and not viewing and not HUD.takeover
		if cine then
			vignette.Visible = false
		end
	end
	Notify.onTakeover = function(on)
		HUD.takeover = on
		refreshVisible()
	end
	player:GetAttributeChangedSignal("Cinematic"):Connect(refreshVisible)
	player:GetAttributeChangedSignal("ViewingTank"):Connect(refreshVisible)
	Remotes.get("Notify").OnClientEvent:Connect(function(kind, data)
		local fn = handlers[kind]
		if fn then
			fn(data)
		end
	end)
	Remotes.get("SharkEvent").OnClientEvent:Connect(function(kind, data)
		if kind == "warning" or kind == "hunt" or kind == "clear" then
			onPhase(kind, data or {})
		end
	end)
end

return HUD
