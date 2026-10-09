-- The always-on screen in the Steal-an-Egg style: small, bright, studded,
-- one obvious next thing.
--   left:          Shop (red, opens the Robux store) with the promo button
--                  under it (best current offer), Index / Rides, Slow Mode
--   right:         small squares: Tank, Rebirth, offers and active boosts
--                  (time left above the square)
--   bottom-left:   speed (sneaker) and money, Friend Boost
--   bottom-center: +speed/s and tank $/s, zone goal bar, next ride button
--   bottom-right:  time to nightfall / dawn
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
local PlayGifts = require(script.Parent.PlayGifts)
local State = require(script.Parent.State)
local Water = require(script.Parent.Water)
local SharkView = require(script.Parent.SharkView)
local Travel = require(script.Parent.Travel)
local Guide = require(script.Parent.Guide)
local Notify = require(script.Parent.Notify)
local Shop = require(script.Parent.Shop)

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
local updatePromo: ((any) -> ())? = nil

HUD.onRides = nil :: (() -> ())?
HUD.onShop = nil :: (() -> ())?
HUD.onIndex = nil :: (() -> ())?
HUD.atRideShop = nil :: (() -> boolean)?
HUD.onRebirth = nil :: (() -> ())?
HUD.onTank = nil :: (() -> ())?
HUD.onSettings = nil :: (() -> ())? -- desktop keeps Slow Mode on the left; settings live on mobile
HUD.onDaily = nil :: (() -> ())?
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
	local holder = UI.frame(parent, { Name = key, Size = UDim2.fromOffset(66, 62), BackgroundTransparency = 1, LayoutOrder = order, Visible = false })
	-- the time left sits on the button's bottom edge, so it reads as part of it
	local timer = UI.outlined(holder, "", { Size = UDim2.new(1, 8, 0, 18), Position = UDim2.new(0.5, 0, 1, 4), AnchorPoint = Vector2.new(0.5, 1), TextColor3 = C.white, ZIndex = 20 })
	local b = UI.iconButton(holder, icon, "", color, function()
		Shop.openStore("Boosts")
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
	local menu = UI.frame(gui, { Name = "Menu", Size = UDim2.fromOffset(180, 340), Position = UDim2.new(0, 10, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5), BackgroundTransparency = 1 })
	local list = Instance.new("UIListLayout")
	list.Padding = UDim.new(0, 8)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.VerticalAlignment = Enum.VerticalAlignment.Center
	list.Parent = menu
	local size = UDim2.fromOffset(170, 56)
	-- the Robux store opens anywhere (the Shop hut opens the same window)
	menuButtons.Shop = UI.wideButton(menu, "Shop", "Shop", C.red, function()
		UI.clearBadge(menuButtons.Shop)
		Shop.openStore()
	end, { Size = size, LayoutOrder = 1, Visible = false })
	-- the best current offer, right under Shop ("x2 Speed / ONLY 399 R$")
	local promo, update = Shop.promo(menu, { Size = UDim2.fromOffset(170, 62), LayoutOrder = 2 })
	menuButtons.Promo = promo
	updatePromo = update
	menuButtons.Index = UI.wideButton(menu, "Index", "Index", C.index, function()
		call(HUD.onIndex)
	end, { Size = size, LayoutOrder = 4 })
	menuButtons.Rides = UI.wideButton(menu, "Rides", "Rides", C.orange, function()
		call(HUD.onRides)
	end, { Size = size, LayoutOrder = 5 })
	local _, set = UI.toggle(menu, "Slow Mode", false, function(on)
		State.action("slowMode", on)
	end, { LayoutOrder = 6, Size = UDim2.fromOffset(196, 40) })
	setSlow = set

	-- right: small squares
	local right = UI.frame(gui, { Name = "Right", Size = UDim2.fromOffset(70, 420), Position = UDim2.new(1, -10, 0.5, 0), AnchorPoint = Vector2.new(1, 0.5), BackgroundTransparency = 1 })
	local rl = Instance.new("UIListLayout")
	rl.Padding = UDim.new(0, 8)
	rl.HorizontalAlignment = Enum.HorizontalAlignment.Right
	rl.VerticalAlignment = Enum.VerticalAlignment.Center
	rl.SortOrder = Enum.SortOrder.LayoutOrder
	rl.Parent = right
	menuButtons.Daily = square(right, "Gift", C.pink, 0, function()
		call(HUD.onDaily)
	end)
	menuButtons.Tank = square(right, "Tank", C.orange, 1, function()
		call(HUD.onTank)
	end)
	menuButtons.Rebirth = square(right, "Rebirth", C.green, 2, function()
		call(HUD.onRebirth)
	end)
	menuButtons.Rebirth.Visible = false
	PlayGifts.square(right, 62, 3) -- free playtime gifts
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
	end, { Size = UDim2.fromOffset(28, 28), Position = UDim2.fromOffset(178, 95) })
	invite.Name = "Invite"
	-- the + sits right after the text, whatever its length
	local function placeInvite()
		invite.Position = UDim2.fromOffset(3 + friendLabel.TextBounds.X + 8, 95)
	end
	friendLabel:GetPropertyChangedSignal("TextBounds"):Connect(placeInvite)
	placeInvite()
	local il = invite:FindFirstChild("Label") :: TextLabel
	il.Size = UDim2.new(1, -4, 1, -4)

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
	rlab.Size = UDim2.new(1, -16, 0, 25)
	rlab.Position = UDim2.new(0.5, 0, 0, 4)
	rlab.AnchorPoint = Vector2.new(0.5, 0)
	ridePrice = UI.outlined(rideBtn, "", { Size = UDim2.new(1, -16, 0, 18), Position = UDim2.new(0.5, 0, 0, 29), AnchorPoint = Vector2.new(0.5, 0), ZIndex = rideBtn.ZIndex + 1 })
	local rb = UI.frame(rideBtn, { Size = UDim2.new(1, -20, 0, 4), Position = UDim2.new(0, 10, 1, -8), BackgroundColor3 = Color3.fromRGB(0, 0, 0), BackgroundTransparency = 0.5, ZIndex = rideBtn.ZIndex + 1 })
	UI.corner(rb, 2)
	rideFill = UI.frame(rb, { Size = UDim2.fromScale(0, 1), BackgroundColor3 = C.white, ZIndex = rb.ZIndex + 1 })
	UI.corner(rideFill, 2)

	carryChip = UI.outlined(gui, "", { Size = UDim2.fromOffset(520, 24), Position = UDim2.new(0.5, 0, 1, -136), AnchorPoint = Vector2.new(0.5, 1), Visible = false })

	-- bottom-right: time to nightfall ("night 1m 40s") or dawn, over a soft fade
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

----------------------------------------------------------------- render state
local lastSlow = false
local shopShown = false
local function render(d: any)
	speedLabel.Text = UI.short(d.speed)
	coinsLabel.Text = "$" .. UI.short(d.coins)
	local mult = Config.Rebirth.mult ^ d.rebirths
	gainLabel.Text = mult > 1 and ("+%s SPEED/S (x%s)"):format(UI.short(d.gain), string.format("%g", math.floor(mult * 100 + 0.5) / 100))
		or ("+%s SPEED/S"):format(UI.short(d.gain))
	tankLabel.Text = ("%d/%d Active  +$%s/s"):format(d.active, d.slots, Config.formatRate(d.income))
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
	-- daily reward waiting
	if (d.dailyWait or 1) <= 0 then
		UI.badge(menuButtons.Daily)
	else
		UI.clearBadge(menuButtons.Daily)
	end
	-- boosts: square + time left
	local function boost(key: string, on: boolean, timerText: string?, badge: string?)
		local sq = boostSquares[key]
		sq.holder.Visible = on
		sq.timer.Text = timerText or ""
		sq.holder.Size = UDim2.fromOffset(66, 62)
		if badge then
			UI.badge(sq.button, badge)
		end
	end
	boost("Shield", d.shields > 0, nil, tostring(d.shields))
	boost("Boost", d.boostLeft > 0, UI.timeWords(d.boostLeft))
	boost("Luck", d.luckLeft > 0, UI.timeWords(d.luckLeft))

	-- goal: the next zone gate up to this run's rebirth target, then rebirth
	local target = Config.rebirthSpeed(d.wr or d.rebirths, d.world)
	local gate = Config.nextGate(d.speed, d.world)
	if gate and gate.gate > target then
		gate = nil
	end
	if gate then
		goalText.Text = ("%s   %s / %s"):format(gate.name, UI.short(d.speed), UI.short(gate.gate))
		goalFill.Size = UDim2.fromScale(math.clamp(d.speed / gate.gate, 0.06, 1), 1) -- fill matches the numbers; never a sliver
		goalFill.BackgroundColor3 = C.blue
	else
		local ready = d.speed >= target
		goalText.Text = ready and "REBIRTH READY!" or ("Rebirth at %s speed"):format(UI.short(target))
		goalFill.Size = UDim2.fromScale(math.clamp(d.speed / target, 0.06, 1), 1)
		goalFill.BackgroundColor3 = C.green
	end
	menuButtons.Rebirth.Visible = d.speed >= target
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
		UI.setText(rideBtn, afford and (here and ("BUY %s!"):format(nxt.name:upper()) or ("GET %s!"):format(nxt.name:upper())) or nxt.name)
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
		carryChip.Visible = true
		carryChip.TextColor3 = r.color
		local extra = (d.bag or 0) > 0 and (" +%d in net"):format(d.bag) or ""
		carryChip.Text = ("%s%s → bring it home to your tank!"):format(Config.fullName(d.carrying.z, d.carrying.r, d.carrying.m, d.carrying.s), extra)
	else
		carryChip.Visible = false
	end
	-- the promo under Shop: only once the shop is open (Config.SHOP_UNLOCK_SECONDS)
	if updatePromo then
		updatePromo(d)
	end
end

----------------------------------------------------------------- per-frame: status line, zone titles, shark state, timer
local phase = "calm"
local phaseEnds = os.clock() + Config.Shark.firstAttack
local grudgeShown = false -- the shark banner is up for a daytime grudge
local lastZone: string? = nil
local quietTitlesUntil = 0 -- no "Shark Beach" title right after you wash up
local menuOpen = false

-- one emoji either side of each zone's title (all widely supported)
local ZONE_EMOJI = { Lagoon = "", Reef = "", Kelp = "", Shipwreck = "", Deep = "", Abyss = "" }

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
	local tank = Layout.tankPos(Layout.plot(d.plot, d.world))
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
		Notify.status(d.income > 0 and ("Your tank earns $%s / day while you're offline"):format(UI.short(Config.offlinePerDay(d.income)))
			or "Put creatures in your tank to earn while you're offline", Color3.fromRGB(190, 225, 255))
	elseif Layout.inWater(pos) then
		local zone = Config.zoneAtPos(pos)
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
			text, sub, color = ("Night falls in %d"):format(left), "You're safe here", C.green
		else
			text, sub, color = ("NIGHT FALLS IN %d!"):format(left), "Get to sand or an island", C.red
		end
	else
		local mine = SharkView.myHunter()
		if mine and mine.state == "lunge" then
			text, sub, color = "IT'S JUMPING! SWERVE!", "Turn hard, now!", C.red
		elseif mine and mine.state == "chase" then
			text, sub, color = "IT'S CHARGING!", "Swerve at the last second, or reach sand!", C.red
		elseif mine and mine.state == "overshoot" then
			text, sub, color = "IT MISSED! IT'S TURNING BACK", "Now's your chance: get to sand or an island", C.gold
		elseif mine and mine.state == "stalk" then
			text, sub, color = "A SHARK IS CIRCLING YOU!", "Follow the arrow to safety", C.red
		elseif safe then
			text, sub, color = (phase == "calm" and "Safe here · it will give up soon" or ("Safe here · dawn in %d"):format(left)), Layout.inWater(pos) and "Islands only shelter you for a few seconds" or nil, C.green
		else
			if phase == "calm" then
				text, sub, color = "A SHARK IS AFTER YOU!", "You took from its waters: get to sand or an island", C.red
			else
				text, sub, color = "NIGHT: SHARKS HUNT EVERYONE", "Night catches are luckier... if you dare", C.gold
			end
		end
	end
	Notify.banner(text, { key = "shark", sticky = true, priority = 5, sub = sub, color = color })
	vignette.Visible = not safe and not player:GetAttribute("Cinematic")
end

local function frame()
	local pos = myPos()
	statusLine(pos)
	if pos then
		local zone = Config.zoneAtPos(pos)
		local id = zone and zone.id or "Beach"
		if id ~= lastZone then
			if lastZone ~= nil and os.clock() > quietTitlesUntil then
				if zone then
					local e = ZONE_EMOJI[zone.id] or ""
					Notify.banner(("%s %s %s"):format(e, zone.name, e), { key = "zone", priority = 2, time = 2.4, big = true,
						color = zone.water:Lerp(Color3.new(1, 1, 1), 0.35), sub = ("%s waters"):format((zone.shark:gsub("(%l)(%u)", "%1 %2"))) })
				else
					Notify.banner("Shark Beach ", { key = "zone", priority = 2, time = 2, big = true, color = Color3.fromRGB(255, 220, 120), sub = "Sand is always safe" })
				end
			end
			lastZone = id
		end
		-- night, or a daytime grudge (a shark you drew by grabbing / chum)
		if phase ~= "calm" or SharkView.myHunter() then
			sharkLine(pos)
			grudgeShown = phase == "calm"
		elseif grudgeShown then
			grudgeShown = false
			Notify.clear("shark")
			vignette.Visible = false
		end
	end
	local left = math.max(0, phaseEnds - os.clock())
	if phase == "calm" then
		timerLabel.Text = "night " .. UI.timeWords(left)
		timerLabel.TextColor3 = left < 10 and C.gold or C.white
		timerPill.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	else
		timerLabel.Text = (phase == "warning" and "DUSK " or "DAWN ") .. math.ceil(left)
		timerLabel.TextColor3 = C.white
		timerPill.BackgroundColor3 = C.red
	end
end

----------------------------------------------------------------- notifications
local handlers: { [string]: (any) -> () } = {}

local newDiscovery = false -- "discover" arrives just before "grab"; one toast says both

handlers.grab = function(d)
	local r = Config.rarity(d.r)
	local name = Config.fullName(d.z, d.r, d.m, d.s)
	local pos = myPos()
	if pos then
		Fx.sparkle(pos + Vector3.new(0, 3, 0), r.color, 20 + r.index * 12)
		Fx.popup3D(pos + Vector3.new(0, 5, 0), ("+$%s/s"):format(Config.formatRate(d.v)), r.color)
	end
	Fx.sound("grab", 0.6, 1 + r.index * 0.05)
	-- the bigger the catch, the bigger the moment
	if r.index >= 5 then
		Notify.takeover("LEGENDARY!", name, r.color, 1.8)
		Fx.shake(1.5)
		Fx.sound("legendary", 0.8)
	elseif d.lucky then
		Notify.word("LUCKY " .. d.r:upper() .. "!", C.green, 1)
		Fx.sound("lucky", 0.7)
	elseif d.pity or r.index >= 3 then
		Notify.word(d.r:upper() .. "!", r.color, 1)
		Fx.sound("grabRare", 0.6, 1 + r.index * 0.04)
	end
	local note = newDiscovery and "  · NEW!" or ""
	newDiscovery = false
	Notify.toast(("%s  +$%s/s%s"):format(name, UI.short(d.v), note), r.color)
end

handlers.discover = function()
	newDiscovery = true
	Fx.sound("discover", 0.55)
	UI.pop(menuButtons.Index, 1.3)
end

handlers.indexClaim = function(d)
	Notify.word("CLAIMED!", C.orange, 0.9)
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
	local tank = Layout.tankPos(Layout.plot(data.plot, State.data and State.data.world))
	Fx.sparkle(tank + Vector3.new(0, 6, 0), r.color, 40)
	Fx.sound("deposit", 0.7, 1, tank)
	if d.active then
		Fx.popup3D(tank + Vector3.new(0, 11, 0), ("+$%s/s"):format(Config.formatRate(d.v)), C.money, true)
	else
		Fx.popup3D(tank + Vector3.new(0, 11, 0), "Not equipped", Color3.fromRGB(170, 170, 180), true)
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
		Notify.word("CODE REDEEMED!", C.green, 1)
		Notify.toast(table.concat(bits, "  "), C.green)
		Fx.sound("coin", 0.7)
	else
		Notify.toast("" .. tostring(d.text), C.red)
		Fx.sound("uiError", 0.6)
	end
end

handlers.tankFull = function(d)
	Notify.banner(("Tank full! %d dead fish"):format(d.max or 10), { key = "tankFull", priority = 2, time = 4, color = C.red,
		sub = "Sell some at the SELL hut, or equip them" })
	Fx.sound("uiError", 0.6)
	local pad = Travel.padPos("Sell")
	if pad then
		Guide.set("shop", pad + Vector3.new(0, 1, 0), "Sell") -- an arrow, no teleport
	end
end

handlers.sold = function(d)
	Notify.word(("SOLD %d!"):format(d.count), C.green, 0.9)
	Notify.toast("+$" .. UI.short(d.coins), C.money)
	Fx.sound("buy", 0.7)
	UI.pop(coinsLabel, 1.3)
end

handlers.collect = function(d)
	local pos = myPos()
	if pos then
		Fx.confetti(pos, { C.money, C.gold })
		Fx.popup3D(pos + Vector3.new(0, 5, 0), "+$" .. UI.short(d.amount), C.money, true)
	end
	Fx.sound("collect", 0.7)
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
	Fx.sound("rideNew", 0.8)
	Notify.takeover("NEW RIDE!", ("%s · +%s speed every second"):format(ride and ride.name or "", UI.short(d.gain)), C.gold, 1.6)
	UI.pop(gainLabel, 1.5)
end

handlers.rideShop = function()
	HUD.goToRideShop()
end

handlers.aggro = function(d)
	local name = tostring(d.shark or "Shark"):gsub("(%l)(%u)", "%1 %2")
	if d.why == "chum" then
		Notify.takeover("CHUMMED!", ("%s threw chum at you. The %s is coming!"):format(tostring(d.by or "Someone"), name), C.red, 1.4, "Shark")
	else
		Notify.banner(("THE %s NOTICED YOU!"):format(name:upper()), { key = "aggro", priority = 4, time = 2.2, color = C.red,
			sub = "Get to sand or an island" })
	end
	Fx.sound("sharkAlarm", 0.7)
	Fx.shake(0.5)
end

handlers.closeCall = function(d)
	Notify.takeover("CLOSE CALL!", ("+%s speed"):format(UI.short(d.amount or 0)), C.gold, 1.1)
	Fx.sound("dodge", 0.9)
	Fx.flash(Color3.new(1, 1, 1), 0.25, 0.5)
end

handlers.net = function(d)
	Notify.takeover(d.name:upper() .. "!", ("Carry %d creatures per trip. A bite loses them all!"):format(d.cap), C.blue, 1.8)
	Fx.sound("buy", 0.8)
end

handlers.slot = function(d)
	Notify.toast(("Your tank now holds %d!"):format(d.slots), C.green)
end

handlers.unlock = function(d)
	local zone = Config.zoneById(d.zone)
	if zone then
		Notify.takeover(zone.name:upper() .. "!", "New zone unlocked · rarer creatures, bigger sharks", C.gold, 1.8)
		Fx.sound("zoneUnlock", 0.8)
		local pos = myPos()
		if pos then
			Fx.confetti(pos)
		end
	end
end

handlers.gate = function(d)
	Notify.word(("NEED %s SPEED"):format(UI.short(d.need)), C.red, 1)
	Fx.sound("uiError", 0.6)
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
	Fx.jaws() -- the jaws snap shut over the screen, then spit you out
	Fx.sound("spat", 0.8)
	local d = State.data
	if d and d.playtime >= Config.SHOP_UNLOCK_SECONDS and Config.Products.Shield.id ~= 0 then
		local b = UI.button(gui, "Shield next time  R$" .. Config.Products.Shield.price, C.sky, function()
			MarketplaceService:PromptProductPurchase(player, Config.Products.Shield.id)
		end, { Size = UDim2.fromOffset(260, 44), Position = UDim2.new(0.5, 0, 1, -168), AnchorPoint = Vector2.new(0.5, 1) })
		task.delay(6, function()
			b:Destroy()
		end)
	end
end

handlers.shield = function()
	Notify.toast("Your shield blocked the bite!", C.sky)
end

handlers.rebirth = function(d)
	Fx.flash(Color3.new(1, 1, 1), 0.8, 0)
	Fx.sound("rebirth", 0.8)
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
	return pos and Config.zoneAtPos(pos)
end

local function onPhase(kind: string, data: any)
	if kind == "warning" then
		phase, phaseEnds = "warning", os.clock() + (data.duration or 5)
		local pos = myPos()
		local exposed = pos ~= nil and not Layout.isSafe(pos)
		Notify.takeover("NIGHT FALLS!", exposed and "Sharks hunt everyone till dawn: get to sand or an island!" or "Stay on the sand and you're safe till dawn", C.red, 1.4)
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
			Notify.toast("Dawn! The sharks are gone. Back to the water!", C.green)
		end
	end
end

----------------------------------------------------------------- start
function HUD.start()
	Notify.start()
	build()
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
