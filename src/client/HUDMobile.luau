-- The always-on screen. Small, bright, one obvious next thing, built from the
-- design system in UI.luau (tokens, pills, nav buttons, cards, bars).
--   top-left:      resource pills: Speed (red), Cash (green), Friend Boost
--                  (+ invite) with the Settings gear; under them the nav
--                  buttons, Index (blue) and Rides (orange), and beside those
--                  Shop (red, the Robux store) with the promo under it
--   top-right:     shark event widget ("Shark in 57s", "HUNTING 12s")
--   right:         square buttons: Gift, Tank; Rebirth and
--                  the timed boosts (time left on a chip) in columns beside
--   bottom-center: the progression card: next zone + bar, tank stats and
--                  the next ride with its price / BUY button
-- Mobile: the left column stays above the thumbstick, the right column above
-- the jump button, and the bottom card is centered and narrow enough to sit
-- between them. Every message goes through Notify: one hierarchy.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
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
local Guide = require(script.Parent.Guide)
local Notify = require(script.Parent.Notify)
local Shop = require(script.Parent.Shop)

local HUD = {}
local C = UI.C
local T = UI.T
local SP = UI.SP
local player = Players.LocalPlayer

local gui: ScreenGui
local uiScale: UIScale
local speedPill: Frame
local speedLabel: TextLabel
local cashPill: Frame
local coinsLabel: TextLabel
local gainLabel: TextLabel
local tankLabel: TextLabel
local incomeLabel: TextLabel
local friendLabel: TextLabel
local progress: Frame -- the bottom card
local zoneLabel: TextLabel
local goalTrack: Frame
local goalFill: Frame
local goalText: TextLabel
local rideRow: TextButton
local rideName: TextLabel
local rideGain: TextLabel
local rideBtn: TextButton -- the price / BUY button
local rideFill: Frame
local rideTrack: Frame
local carryChip: Frame
local carryLabel: TextLabel
local vignette: Frame
local menuButtons: { [string]: TextButton } = {}
local boostSquares: { [string]: { holder: Frame, button: TextButton, timer: TextLabel, chip: Frame } } = {}
local timerPill: Frame
local timerLabel: TextLabel
local stopRidePulse: (() -> ())? = nil
local boostCol: Frame
local extraCol: Frame
local updatePromo: ((any) -> ())? = nil

HUD.onRides = nil :: (() -> ())?
HUD.onShop = nil :: (() -> ())?
HUD.onIndex = nil :: (() -> ())?
HUD.atRideShop = nil :: (() -> boolean)?
HUD.onRebirth = nil :: (() -> ())?
HUD.onTank = nil :: (() -> ())?
HUD.onDaily = nil :: (() -> ())?
HUD.onSettings = nil :: (() -> ())?
HUD.takeover = false

function HUD.goToRideShop()
	Travel.go("Rides")
end

local function call(fn: (() -> ())?)
	if fn then
		fn()
	end
end

-- sizes on the 1280x720 design canvas
local SQ = 60 -- right-side squares
local COL_W = 190 -- left column (pills + nav)
local NAV_H = 54
local STORE_W = 156 -- Shop + promo column beside the nav (narrow: clear of the centered messages)
local TIMER_W = 250 -- shark widget
local CARD_W = 600 -- bottom progression card
local CARD_H = 146
local CARD_H_NO_RIDE = 86

----------------------------------------------------------------- small local helpers
local function list(parent: Instance, horizontal: boolean?, gap: number?): UIListLayout
	local l = Instance.new("UIListLayout")
	l.FillDirection = horizontal and Enum.FillDirection.Horizontal or Enum.FillDirection.Vertical
	l.SortOrder = Enum.SortOrder.LayoutOrder
	l.Padding = UDim.new(0, gap or SP[2])
	l.Parent = parent
	return l
end

local function tween(inst: Instance, time: number, goal: { [string]: any }, style: Enum.EasingStyle?, dir: Enum.EasingDirection?)
	local t = TweenService:Create(inst, TweenInfo.new(time, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), goal)
	t:Play()
	return t
end

-- recolor a UI.bar fill (keeps its gradient in step with the color)
local function paintFill(fill: Frame, color: Color3)
	if fill.BackgroundColor3 == color then
		return
	end
	fill.BackgroundColor3 = color
	local g = fill:FindFirstChildOfClass("UIGradient")
	if g then
		g.Color = ColorSequence.new(UI.light(color, 0.3), UI.dark(color, 0.08))
	end
end

-- "+1 Speed" / "+$5": a short float off the side of a pill
local lastFloat: { [string]: number } = {}
local function floatText(anchor: GuiObject, key: string, text: string, color: Color3)
	local now = os.clock()
	if now - (lastFloat[key] or 0) < 0.6 then
		return
	end
	lastFloat[key] = now
	local l = UI.label(anchor, "body", text, { Name = "Float", Size = UDim2.fromOffset(120, 24), Position = UDim2.new(1, SP[2], 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = color, ZIndex = anchor.ZIndex + 5,
		Rotation = -6 })
	UI.pop(l, 1.3)
	tween(l, 0.8, { Position = UDim2.new(1, SP[2] + 10, 0.5, -26) })
	UI.fade(l, false, 0.8)
	task.delay(0.85, function()
		l:Destroy()
	end)
end

-- canvas (design units) point of a screen point
local function toCanvas(v: Vector2): Vector2
	local s = uiScale and uiScale.Scale or 1
	local o = gui.AbsolutePosition
	return Vector2.new((v.X - o.X) / s, (v.Y - o.Y) / s)
end

-- a caught creature flies from you into the Tank button
local function flyToTank(color: Color3)
	local tank = menuButtons.Tank
	if not (tank and tank.Visible and gui.Enabled) then
		return
	end
	local from = Vector2.new(0, 0)
	local ok = pcall(function()
		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		local cam = Workspace.CurrentCamera
		if hrp and cam then
			local p = cam:WorldToViewportPoint(hrp.Position + Vector3.new(0, 2, 0))
			from = toCanvas(Vector2.new(p.X, p.Y))
		else
			error("no character")
		end
	end)
	if not ok then
		from = toCanvas(gui.AbsolutePosition + gui.AbsoluteSize * Vector2.new(0.5, 0.55))
	end
	local to = toCanvas(tank.AbsolutePosition + tank.AbsoluteSize * 0.5)
	local dot = UI.frame(gui, { Name = "Fly", Size = UDim2.fromOffset(30, 30), Position = UDim2.fromOffset(from.X, from.Y), AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = color, ZIndex = 20 })
	UI.corner(dot, 15)
	UI.stroke(dot, T.white, UI.S.card)
	UI.pop(dot, 1.6)
	tween(dot, 0.55, { Position = UDim2.fromOffset(to.X, to.Y), Size = UDim2.fromOffset(14, 14) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	task.delay(0.56, function()
		dot:Destroy()
		UI.pop(tank, 1.18)
	end)
end

----------------------------------------------------------------- build
local function square(parent: Instance, icon: string, color: Color3, order: number, onClick: () -> ()): TextButton
	return UI.iconButton(parent, icon, "", color, onClick, { Size = UDim2.fromOffset(SQ, SQ), LayoutOrder = order })
end

-- a square with its time left on a small chip over its bottom edge (active boosts)
local function timedSquare(parent: Instance, key: string, icon: string, color: Color3, order: number)
	local holder = UI.frame(parent, { Name = key, Size = UDim2.fromOffset(SQ, SQ + SP[2]), BackgroundTransparency = 1, LayoutOrder = order, Visible = false })
	local b = UI.iconButton(holder, icon, "", color, function()
		Shop.openStore("Boosts")
	end, { Size = UDim2.fromOffset(SQ, SQ) })
	local chip = UI.frame(holder, { Name = "Time", Size = UDim2.fromOffset(SQ + 10, 24), Position = UDim2.new(0.5, 0, 1, 0), AnchorPoint = Vector2.new(0.5, 1),
		BackgroundColor3 = T.navyDark, ZIndex = 6 })
	UI.corner(chip, UI.R.chip)
	UI.stroke(chip, UI.dark(color, 0.2), UI.S.subtle)
	local timer = UI.label(chip, "body", "", { Size = UDim2.new(1, -6, 1, -4), Position = UDim2.fromOffset(3, 2), ZIndex = 7 })
	boostSquares[key] = { holder = holder, button = b, timer = timer, chip = chip }
end

local function column(parent: Instance, order: number, align: Enum.VerticalAlignment): Frame
	local f = UI.frame(parent, { Name = "Col" .. order, Size = UDim2.new(0, SQ + 4, 1, 0), BackgroundTransparency = 1, LayoutOrder = order })
	local l = list(f, false, SP[3])
	l.HorizontalAlignment = Enum.HorizontalAlignment.Center
	l.VerticalAlignment = align
	return f
end

local function rideClicked()
	local d = State.data
	local nxt = d and HUD.nextRide(d)
	if nxt and d.coins >= nxt.price and HUD.atRideShop and HUD.atRideShop() then
		State.action("buyRide", nxt.id)
	else
		HUD.goToRideShop()
	end
end

local function buildLeft()
	-- one column under the Roblox top bar: pills, then the two nav buttons
	local left = UI.frame(gui, { Name = "Left", Size = UDim2.fromOffset(COL_W + SP[2] + STORE_W, 300), Position = UDim2.fromOffset(SP[2] + 6, SP[2]),
		BackgroundTransparency = 1 })
	list(left, false, SP[2])

	-- speed: the number that matters most
	local sp, spv = UI.pill(left, "Sneaker", T.red, { Name = "Speed", Size = UDim2.fromOffset(COL_W, 44), LayoutOrder = 1 })
	speedPill, speedLabel = sp, spv
	speedLabel.TextColor3 = UI.light(T.gold, 0.25)
	speedLabel.Size = UDim2.new(1, -112, 1, -10)
	-- what you gain every second, small on the right of the pill
	gainLabel = UI.label(sp, "body", "+1/s", { Name = "Gain", Size = UDim2.new(0, 60, 0, 20), Position = UDim2.new(1, -12, 0.5, -2),
		AnchorPoint = Vector2.new(1, 0.5), TextXAlignment = Enum.TextXAlignment.Right, ZIndex = sp.ZIndex + 2, StrokeColor = UI.dark(T.red, 0.6) })

	local cp, cpv = UI.pill(left, "Cash", T.green, { Name = "Cash", Size = UDim2.fromOffset(COL_W, 44), LayoutOrder = 2 })
	cashPill, coinsLabel = cp, cpv
	coinsLabel.TextColor3 = UI.light(T.gold, 0.55)

	-- friend boost (+ invite)
	local fp, fpv = UI.pill(left, "Friends", T.navyLight, { Name = "Friends", Size = UDim2.fromOffset(COL_W, 34), LayoutOrder = 3 })
	friendLabel = fpv
	friendLabel.Size = UDim2.new(1, -72, 1, -8)
	friendLabel.Position = UDim2.new(0, 36, 0.5, -2)
	local fi = fp:FindFirstChild("Icon") :: GuiObject
	fi.Position = UDim2.new(0, -6, 0.5, -2)
	local invite = UI.button(fp, "+", T.green, function()
		pcall(function()
			game:GetService("SocialService"):PromptGameInvite(player)
		end)
	end, { Name = "Invite", Size = UDim2.fromOffset(28, 28), Position = UDim2.new(1, 2, 0.5, -1), AnchorPoint = Vector2.new(1, 0.5), ZIndex = fp.ZIndex + 3 })
	local il = invite:FindFirstChild("Label") :: TextLabel
	il.Size = UDim2.new(1, -4, 1, -8)

	-- navigation: Index and Rides, the same size and build; beside them the
	-- red Shop (the Robux store) with the promo under it. Two short columns
	-- keep everything above the thumbstick.
	local nav = UI.frame(left, { Name = "Nav", Size = UDim2.fromOffset(COL_W + SP[2] + STORE_W, NAV_H * 2 + SP[2] + SP[1]), BackgroundTransparency = 1,
		LayoutOrder = 4 })
	-- a little air between the resources and the buttons
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, SP[1])
	pad.Parent = nav
	local navCol = UI.frame(nav, { Name = "Places", Size = UDim2.fromOffset(COL_W, NAV_H * 2 + SP[2]), BackgroundTransparency = 1 })
	list(navCol, false, SP[2])
	menuButtons.Index = UI.navButton(navCol, "Index", "Index", T.blue, function()
		call(HUD.onIndex)
	end, { Size = UDim2.fromOffset(COL_W, NAV_H), LayoutOrder = 1 })
	menuButtons.Rides = UI.navButton(navCol, "Rides", "Rides", T.orange, function()
		call(HUD.onRides)
	end, { Size = UDim2.fromOffset(COL_W, NAV_H), LayoutOrder = 2 })
	local storeCol = UI.frame(nav, { Name = "Store", Size = UDim2.fromOffset(STORE_W, NAV_H * 2 + SP[2]), Position = UDim2.fromOffset(COL_W + SP[2], 0),
		BackgroundTransparency = 1 })
	list(storeCol, false, SP[2])
	menuButtons.Shop = UI.navButton(storeCol, "Shop", "Shop", T.red, function()
		UI.clearBadge(menuButtons.Shop)
		Shop.openStore()
	end, { Size = UDim2.fromOffset(STORE_W, NAV_H), LayoutOrder = 1, Visible = false })
	local promo, update = Shop.promo(storeCol, { Size = UDim2.fromOffset(STORE_W, NAV_H), LayoutOrder = 2 })
	menuButtons.Promo = promo
	updatePromo = update
end

local function buildRight()
	-- shark timer (the classic one): "in 1m 40s" over a soft dark fade, top-right
	timerPill = UI.frame(gui, { Name = "Timer", Size = UDim2.fromOffset(TIMER_W, 58), Position = UDim2.new(1, 0, 0, 4), AnchorPoint = Vector2.new(1, 0),
		BackgroundColor3 = Color3.fromRGB(0, 0, 0), BackgroundTransparency = 0.45 })
	local fade = Instance.new("UIGradient")
	fade.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.35, 0.35), NumberSequenceKeypoint.new(1, 0.25) })
	fade.Parent = timerPill
	UI.icon(timerPill, "Shark", { Size = UDim2.fromOffset(46, 46), Position = UDim2.new(0, 46, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5) })
	timerLabel = UI.outlined(timerPill, "", { Size = UDim2.new(1, -108, 0, 34), Position = UDim2.new(0, 98, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5),
		TextXAlignment = Enum.TextXAlignment.Left, Font = UI.NUMFONT })

	-- settings: a small gear tucked beside the shark widget
	menuButtons.Settings = UI.iconButton(gui, "Settings", "", T.navyLight, function()
		call(HUD.onSettings)
	end, { Name = "Settings", Size = UDim2.fromOffset(38, 38), Position = UDim2.new(1, -(SP[2] + 6 + TIMER_W + SP[2]), 0, SP[2] + 6), AnchorPoint = Vector2.new(1, 0) })

	-- square buttons: main column (Gift, Tank, Shop) on the edge, extras beside it
	local right = UI.frame(gui, { Name = "Right", Size = UDim2.fromOffset((SQ + 4) * 3 + SP[3] * 2, 300), BackgroundTransparency = 1,
		Position = UDim2.new(1, -(SP[2] + 6), 0.5, 0), AnchorPoint = Vector2.new(1, 0.5) })
	local rl = list(right, true, SP[3])
	rl.HorizontalAlignment = Enum.HorizontalAlignment.Right
	local align = UI.TOUCH and Enum.VerticalAlignment.Top or Enum.VerticalAlignment.Center
	local boosts = column(right, 1, align)
	local extra = column(right, 2, align)
	local main = column(right, 3, align)
	boostCol, extraCol = boosts, extra
	menuButtons.Daily = square(main, "Gift", T.pink, 1, function()
		call(HUD.onDaily)
	end)
	menuButtons.Tank = square(main, "Tank", T.blue, 2, function()
		call(HUD.onTank)
	end)
	menuButtons.Rebirth = square(extra, "Rebirth", T.purple, 1, function()
		call(HUD.onRebirth)
	end)
	menuButtons.Rebirth.Visible = false
	timedSquare(boosts, "Shield", "Shield", C.sky, 1)
	timedSquare(boosts, "Boost", "Boost", T.purple, 2)
	timedSquare(boosts, "Luck", "Potion", T.green, 3)

	if UI.TOUCH then
		-- stay clear of the jump button: hang from under the shark widget
		right.AnchorPoint = Vector2.new(1, 0)
		right.Position = UDim2.new(1, -(SP[2] + 6), 0, 50 + SP[2] + SP[4])
		right.Size = UDim2.fromOffset((SQ + 4) * 3 + SP[3] * 2, SQ * 3 + SP[3] * 2 + SP[2])
	end
end

local function buildBottom()
	-- the progression card: next zone, bar, tank stats, next ride
	progress = UI.card(gui, UI.dark(T.blue, 0.15), { Name = "Progress", Size = UDim2.fromOffset(CARD_W, CARD_H), Position = UDim2.new(0.5, 0, 1, -SP[2]),
		AnchorPoint = Vector2.new(0.5, 1), BackgroundColor3 = T.navy, BackgroundTransparency = 1 })
	-- no panel behind it (Steal an Egg style): just the outlined text, bar and ride button
	local accent = progress:FindFirstChild("Accent")
	if accent then
		accent:Destroy()
	end
	UI.icon(progress, "Coral", { Name = "ZoneIcon", Size = UDim2.fromOffset(54, 54), Position = UDim2.fromOffset(4, -10), ZIndex = progress.ZIndex + 3 })
	zoneLabel = UI.label(progress, "hero", "", { Name = "Zone", Size = UDim2.new(0.5, -60, 0, 32), Position = UDim2.fromOffset(62, SP[2] - 2),
		TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = T.white })
	local zc = zoneLabel:FindFirstChildOfClass("UITextSizeConstraint")
	if zc then
		zc.MaxTextSize = 28
	end
	incomeLabel = UI.label(progress, "body", "", { Name = "Income", Size = UDim2.fromOffset(110, 24), Position = UDim2.new(1, -SP[3], 0, SP[2] + 2),
		AnchorPoint = Vector2.new(1, 0), TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = C.money })
	tankLabel = UI.label(progress, "body", "", { Name = "Active", Size = UDim2.fromOffset(110, 20), Position = UDim2.new(1, -(SP[3] + 116), 0, SP[2] + 4),
		AnchorPoint = Vector2.new(1, 0), TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = T.mute })
	local back, gf, gl = UI.bar(progress, T.blue, { Name = "Goal", Size = UDim2.new(1, -(62 + SP[3]), 0, 28), Position = UDim2.fromOffset(62, 44) })
	goalTrack, goalFill, goalText = back, gf, gl

	-- the next ride: a gold slab with the price / BUY button on its right
	rideRow = UI.button(progress, "", T.gold, rideClicked, { Name = "Ride", Size = UDim2.new(1, -SP[3] * 2, 0, 62), Position = UDim2.new(0.5, 0, 1, -SP[2]),
		AnchorPoint = Vector2.new(0.5, 1) })
	local face = rideRow:FindFirstChild("Face") :: Frame
	UI.icon(face, "Rides", { Name = "RideIcon", Size = UDim2.fromOffset(58, 58), Position = UDim2.new(0, SP[1], 0.5, -2), AnchorPoint = Vector2.new(0, 0.5),
		ZIndex = rideRow.ZIndex + 2 })
	rideName = UI.label(face, "body", "", { Name = "RideName", Size = UDim2.new(1, -(72 + 150), 0, 26), Position = UDim2.fromOffset(70, 5),
		TextXAlignment = Enum.TextXAlignment.Left, ZIndex = rideRow.ZIndex + 2, StrokeColor = UI.dark(T.gold, 0.6) })
	UI.icon(face, "Sneaker", { Size = UDim2.fromOffset(20, 20), Position = UDim2.fromOffset(70, 33), ZIndex = rideRow.ZIndex + 2 })
	rideGain = UI.label(face, "body", "", { Name = "RideGain", Size = UDim2.new(1, -(96 + 150), 0, 20), Position = UDim2.fromOffset(94, 33),
		TextXAlignment = Enum.TextXAlignment.Left, ZIndex = rideRow.ZIndex + 2, StrokeColor = UI.dark(T.gold, 0.6) })
	rideBtn = UI.button(face, "", T.green, rideClicked, { Name = "Price", Size = UDim2.fromOffset(136, 46), Position = UDim2.new(1, -SP[2], 0.5, 0),
		AnchorPoint = Vector2.new(1, 0.5), ZIndex = rideRow.ZIndex + 3 })
	local pface = rideBtn:FindFirstChild("Face") :: Frame
	UI.icon(pface, "Cash", { Size = UDim2.fromOffset(30, 30), Position = UDim2.new(0, SP[2], 0.5, 0), AnchorPoint = Vector2.new(0, 0.5), ZIndex = rideBtn.ZIndex + 2 })
	local plab = rideBtn:FindFirstChild("Label") :: TextLabel
	plab.Size = UDim2.new(1, -52, 1, -18)
	plab.Position = UDim2.new(0, 42, 0.5, -3)
	plab.AnchorPoint = Vector2.new(0, 0.5)
	-- how close you are to affording it
	local rb = UI.frame(pface, { Size = UDim2.new(1, -20, 0, 4), Position = UDim2.new(0, 10, 1, -6), BackgroundColor3 = T.navyDark, BackgroundTransparency = 0.5,
		ZIndex = rideBtn.ZIndex + 2 })
	UI.corner(rb, 2)
	rideTrack = rb
	rideFill = UI.frame(rb, { Size = UDim2.fromScale(0, 1), BackgroundColor3 = T.white, ZIndex = rideBtn.ZIndex + 3 })
	UI.corner(rideFill, 2)

	-- carrying: a small pill above the card
	carryChip = UI.frame(gui, { Name = "Carry", Size = UDim2.fromOffset(0, 30), AutomaticSize = Enum.AutomaticSize.X, Position = UDim2.new(0.5, 0, 1, -(CARD_H + SP[2] * 2)),
		AnchorPoint = Vector2.new(0.5, 1), BackgroundColor3 = T.navyDark, BackgroundTransparency = 1, Visible = false })
	UI.corner(carryChip, 15)
	local cs = UI.stroke(carryChip, T.gold, UI.S.card)
	cs.Enabled = false -- text only
	cs.Name = "Accent"
	local cpad = Instance.new("UIPadding")
	cpad.PaddingLeft = UDim.new(0, SP[3])
	cpad.PaddingRight = UDim.new(0, SP[3])
	cpad.Parent = carryChip
	carryLabel = UI.outlined(carryChip, "", { Size = UDim2.fromOffset(0, 30), AutomaticSize = Enum.AutomaticSize.X, TextScaled = false, TextSize = 20, TextColor3 = T.gold })
end

local function build()
	gui = Instance.new("ScreenGui")
	gui.Name = "HUD"
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = player:WaitForChild("PlayerGui")
	uiScale = UI.autoScale(gui)

	buildLeft()
	buildRight()
	buildBottom()

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

-- the tutorial asks for attention on the buy button (stops when you can't afford it)
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
local shopShown = false
local lastSpeed: number? = nil
local lastCoins: number? = nil
local lastAfford = false
local lastDaily = false
local lastRide: string? = nil
local function render(d: any)
	-- resources (+ a little float when they go up)
	if lastSpeed and d.speed > lastSpeed then
		floatText(speedPill, "speed", ("+%s Speed"):format(UI.short(d.speed - lastSpeed)), UI.light(T.gold, 0.2))
	end
	if lastCoins and d.coins > lastCoins then
		floatText(cashPill, "cash", "+$" .. UI.short(d.coins - lastCoins), C.money)
	end
	lastSpeed, lastCoins = d.speed, d.coins
	speedLabel.Text = UI.short(d.speed)
	coinsLabel.Text = "$" .. UI.short(d.coins)
	local mult = Config.Rebirth.mult ^ d.rebirths
	gainLabel.Text = mult > 1 and ("+%s/s x%s"):format(UI.short(d.gain), string.format("%g", math.floor(mult * 100 + 0.5) / 100))
		or ("+%s/s"):format(UI.short(d.gain))
	tankLabel.Text = ("%d/%d Active"):format(d.active, d.slots)
	incomeLabel.Text = ("+$%s/s"):format(Config.formatRate(d.income))
	friendLabel.Text = ("Friends +%d%%"):format(math.floor(d.friendBoost * 100 + 0.5))

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
	-- daily reward waiting: one pop when it becomes ready
	local dailyReady = (d.dailyWait or 1) <= 0
	if dailyReady then
		UI.badge(menuButtons.Daily)
		if not lastDaily then
			UI.pop(menuButtons.Daily, 1.2)
		end
	else
		UI.clearBadge(menuButtons.Daily)
	end
	lastDaily = dailyReady
	-- boosts: square + time left
	local function boost(key: string, on: boolean, timerText: string?, badge: string?)
		local sq = boostSquares[key]
		sq.holder.Visible = on
		sq.timer.Text = timerText or ""
		sq.chip.Visible = timerText ~= nil
		sq.holder.Size = UDim2.fromOffset(SQ, timerText and SQ + SP[2] or SQ) -- no empty gap when there's no timer
		if badge then
			UI.badge(sq.button, badge)
		end
	end
	boost("Shield", d.shields > 0, nil, tostring(d.shields))
	boost("Boost", d.boostLeft > 0, UI.timeWords(d.boostLeft))
	boost("Luck", d.luckLeft > 0, UI.timeWords(d.luckLeft))
	-- empty side columns fold away so the squares sit together
	boostCol.Visible = d.shields > 0 or d.boostLeft > 0 or d.luckLeft > 0

	-- goal: next zone gate, or rebirth
	local gate = Config.nextGate(d.speed)
	local frac
	if gate then
		local prevGate = 0
		for _, z in Config.Zones do
			if z.gate <= d.speed then
				prevGate = z.gate
			end
		end
		zoneLabel.Text = gate.name
		local zi = progress:FindFirstChild("ZoneIcon")
		if zi and zi:GetAttribute("Zone") ~= gate.id then
			local props = { Name = "ZoneIcon", Size = zi.Size, Position = zi.Position, ZIndex = zi.ZIndex }
			zi:Destroy()
			UI.icon(progress, gate.id, props):SetAttribute("Zone", gate.id)
		end
		goalText.Text = ("%s / %s"):format(UI.short(d.speed), UI.short(gate.gate))
		frac = math.clamp((d.speed - prevGate) / (gate.gate - prevGate), 0.02, 1)
		paintFill(goalFill, T.blue)
	else
		local ready = d.speed >= Config.Rebirth.speed
		zoneLabel.Text = "Rebirth"
		goalText.Text = ready and "REBIRTH READY!" or ("%s / %s"):format(UI.short(d.speed), UI.short(Config.Rebirth.speed))
		frac = math.clamp(d.speed / Config.Rebirth.speed, 0.02, 1)
		paintFill(goalFill, T.green)
	end
	UI.setBar(goalFill, frac)
	-- almost there: the bar's edge and number turn gold
	local near = frac >= 0.85
	local edge = goalTrack:FindFirstChildOfClass("UIStroke")
	if edge then
		edge.Color = near and T.gold or T.navyDark
	end
	goalText.TextColor3 = near and UI.light(T.gold, 0.3) or T.white

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
	rideRow.Visible = nxt ~= nil
	local h = nxt and CARD_H or CARD_H_NO_RIDE
	progress.Size = UDim2.fromOffset(CARD_W, h)
	carryChip.Position = UDim2.new(0.5, 0, 1, -(h + SP[2] * 2))
	if nxt then
		local afford = d.coins >= nxt.price
		local here = HUD.atRideShop and HUD.atRideShop()
		rideName.Text = nxt.name
		rideGain.Text = ("+%d speed/s"):format(nxt.gain or 0)
		UI.setText(rideBtn, afford and (here and "BUY" or "GET") or ("$" .. UI.short(nxt.price)))
		rideFill.Size = UDim2.fromScale(math.clamp(d.coins / nxt.price, 0, 1), 1)
		rideTrack.Visible = not afford
		if afford and (not lastAfford or lastRide ~= nxt.id) then
			UI.pop(rideBtn, 1.15) -- one pulse when it becomes affordable
		end
		if not afford then
			HUD.pulseRide(false)
		end
		lastAfford, lastRide = afford, nxt.id
		if afford then
			UI.badge(menuButtons.Rides)
		else
			UI.clearBadge(menuButtons.Rides)
		end
	else
		HUD.pulseRide(false)
		UI.clearBadge(menuButtons.Rides)
	end

	-- carrying
	if d.carrying then
		local r = Config.rarity(d.carrying.r)
		carryChip.Visible = true
		carryLabel.TextColor3 = r.color
		local accent = carryChip:FindFirstChild("Accent") :: UIStroke
		accent.Color = r.color
		carryLabel.Text = ("%s: bring it home to your tank!"):format(Config.fullName(d.carrying.z, d.carrying.r, d.carrying.m, d.carrying.s))
	else
		carryChip.Visible = false
	end
	-- the promo beside the nav: only once the shop is open (Config.SHOP_UNLOCK_SECONDS)
	if updatePromo then
		updatePromo(d)
	end
	extraCol.Visible = menuButtons.Rebirth.Visible
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
		Notify.status(d.income > 0 and ("Your tank earns $%s / day while you're offline"):format(UI.short(Config.offlinePerDay(d.income)))
			or "Put creatures in your tank to earn while you're offline", Color3.fromRGB(190, 225, 255))
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
			text, sub, color = ("Shark attack in %d"):format(left), "You're safe here", C.green
		else
			text, sub, color = ("SHARK ATTACK IN %d!"):format(left), "Get to sand or an island", C.red
		end
	else
		local mine = SharkView.myHunter()
		if mine and mine.state == "lunge" then
			text, sub, color = "IT'S JUMPING! SWERVE!", "Turn hard, now!", C.red
		elseif mine and mine.state == "chase" then
			text, sub, color = "IT'S CHARGING!", "Swerve late, or reach sand!", C.red
		elseif mine and mine.state == "overshoot" then
			text, sub, color = "IT MISSED!", "Now: get to sand or an island", C.gold
		elseif mine and mine.state == "stalk" then
			text, sub, color = "A SHARK IS CIRCLING YOU!", "Follow the arrow to safety", C.red
		elseif safe then
			local onIsland = Layout.inWater(pos)
			text, sub, color = ("Safe here · sharks leave in %d"):format(left), onIsland and "Islands only shelter you for a few seconds" or nil, C.green
		else
			text, sub, color = "SHARKS ARE HUNTING!", "Catches are luckier now... if you dare", C.gold
		end
	end
	Notify.banner(text, { key = "shark", sticky = true, priority = 5, sub = sub, color = color, icon = "Shark" })
	vignette.Visible = not safe and not player:GetAttribute("Cinematic")
end

-- the classic shark timer
local function updateTimer()
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

local function frame()
	local pos = myPos()
	statusLine(pos)
	if pos then
		local zone = Config.zoneAt(pos.Z)
		local id = zone and zone.id or "Beach"
		if id ~= lastZone then
			if lastZone ~= nil and os.clock() > quietTitlesUntil then
				if zone then
					Notify.banner(zone.name, { key = "zone", priority = 2, time = 2.4, big = true,
						color = zone.water:Lerp(Color3.new(1, 1, 1), 0.35), sub = ("%s waters"):format((zone.shark:gsub("(%l)(%u)", "%1 %2"))) })
				else
					Notify.banner("Shark Beach", { key = "zone", priority = 2, time = 2, big = true, color = Color3.fromRGB(255, 220, 120), sub = "Sand is always safe" })
				end
			end
			lastZone = id
		end
		if phase ~= "calm" then
			sharkLine(pos)
		end
	end
	updateTimer()
end

----------------------------------------------------------------- unlock moment on the progress card (UI only)
local function unlockBurst()
	local flash = UI.frame(progress, { Name = "Flash", Size = UDim2.fromScale(1, 1), BackgroundColor3 = T.white, BackgroundTransparency = 0.2, ZIndex = 30 })
	UI.corner(flash, UI.R.card)
	tween(flash, 0.5, { BackgroundTransparency = 1 })
	UI.pop(progress, 1.08)
	local colors = { T.gold, T.blue, T.white, T.green }
	for i = 1, 14 do
		local a = (i / 14) * math.pi * 2 + math.random() * 0.3
		local s = math.random(8, 14)
		local bit = UI.frame(progress, { Size = UDim2.fromOffset(s, s), Position = UDim2.new(0.5, 0, 0, 58), AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = colors[i % #colors + 1], Rotation = math.random(0, 90), ZIndex = 31 })
		UI.corner(bit, 3)
		local dist = math.random(110, 220)
		tween(bit, 0.6, { Position = UDim2.new(0.5, math.cos(a) * dist, 0, 58 + math.sin(a) * dist * 0.45), Rotation = bit.Rotation + 180,
			BackgroundTransparency = 1 })
	end
	task.delay(0.65, function()
		flash:Destroy()
		for _, c in progress:GetChildren() do
			if c:IsA("Frame") and c.ZIndex == 31 then
				c:Destroy()
			end
		end
	end)
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
	flyToTank(r.color)
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
	local b = menuButtons.Index
	UI.pop(b, 1.2)
	local old = b:FindFirstChild("New")
	if old then
		old:Destroy()
	end
	local chip = UI.chip(b, "NEW!", T.gold, { Name = "New", Size = UDim2.fromOffset(54, 22), Position = UDim2.new(1, 4, 1, -2), AnchorPoint = Vector2.new(1, 0.5),
		ZIndex = b.ZIndex + 6, Rotation = -6 })
	for _, c in chip:GetDescendants() do
		if c:IsA("GuiObject") then
			c.ZIndex = b.ZIndex + 7
		end
	end
	UI.pop(chip, 1.5)
	task.delay(5, function()
		if chip.Parent then
			UI.fade(chip, false, 0.3)
			task.wait(0.32)
			chip:Destroy()
		end
	end)
end

handlers.indexClaim = function(d)
	Notify.word("CLAIMED!", C.orange, 0.9)
	Notify.toast(("+$%s  +%s speed"):format(UI.short(d.coins), UI.short(d.speed)), C.green)
	UI.pop(cashPill, 1.15)
	UI.pop(speedPill, 1.15)
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
		Notify.toast(tostring(d.text), C.red)
		Fx.sound("uiError", 0.6)
	end
end

handlers.tankFull = function(d)
	Notify.banner(("Tank full! %d dead fish"):format(d.max or 10), { key = "tankFull", priority = 2, time = 4, color = C.red,
		sub = "Sell some at the SELL hut, or equip them", icon = "Tank" })
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
	UI.pop(cashPill, 1.15)
end

handlers.collect = function(d)
	local pos = myPos()
	if pos then
		Fx.confetti(pos, { C.money, C.gold })
		Fx.popup3D(pos + Vector3.new(0, 5, 0), "+$" .. UI.short(d.amount), C.money, true)
	end
	Fx.sound("collect", 0.7)
	UI.pop(cashPill, 1.15)
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
	Notify.takeover("NEW RIDE!", ("%s · +%s speed every second"):format(ride and ride.name or "", UI.short(d.gain)), C.gold, 1.6, "Rides")
	UI.pop(speedPill, 1.15)
end

handlers.rideShop = function()
	HUD.goToRideShop()
end

handlers.slot = function(d)
	Notify.toast(("Your tank now holds %d!"):format(d.slots), C.green)
end

handlers.unlock = function(d)
	local zone = Config.zoneById(d.zone)
	if zone then
		Notify.takeover(zone.name:upper() .. "!", "New zone unlocked · rarer creatures, bigger sharks", C.gold, 1.8, zone.id)
		Fx.sound("zoneUnlock", 0.8)
		local pos = myPos()
		if pos then
			Fx.confetti(pos)
		end
		unlockBurst()
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
	Notify.word("PTOOEY!", C.sky, 1)
	Fx.sound("spat", 0.8)
	local d = State.data
	if d and d.playtime >= Config.SHOP_UNLOCK_SECONDS and Config.Products.Shield.id ~= 0 then
		local b = UI.button(gui, "Shield next time  R$" .. Config.Products.Shield.price, C.sky, function()
			MarketplaceService:PromptProductPurchase(player, Config.Products.Shield.id)
		end, { Size = UDim2.fromOffset(260, 44), Position = UDim2.new(0.5, 0, 1, -(progress.Size.Y.Offset + SP[2] * 2 + 40)), AnchorPoint = Vector2.new(0.5, 1) })
		UI.pop(b, 1.15)
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
	Notify.takeover("REBIRTH!", ("Permanent x%s speed gain"):format(tostring(Config.Rebirth.mult ^ d.rebirths)), C.green, 2, "Rebirth")
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
		Notify.takeover("SHARK INCOMING!", exposed and "Get to sand or an island!" or "Stay on the sand and you're safe", C.red, 1.4, "Shark")
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
			Notify.toast("The sharks are gone. Back to the water!", C.green)
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
	updateTimer()
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
