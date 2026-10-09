-- Every message on screen goes through here, in a clear hierarchy, so the
-- screen never piles up and the important thing is always the obvious one.
--
--   takeover  the big moment (shark incoming, new zone, new ride, legendary):
--             center stage; the HUD and every other message step aside.
--             One at a time, in order.
--   word      a punchy center word (LUCKY!, DODGED!, PTOOEY!). Shares center
--             stage with takeovers and never stacks (one waits, extras drop).
--   banner    the top-center message. A compact navy card (tutorial step
--             with its "1/5" chip, shark status, tank full...) or, for
--             `big` ones (zone titles), plain hero text. One at a time: the
--             highest priority shows, the rest wait their turn. Sticky ones
--             (shark status, tutorial step) stay until cleared and briefly
--             give way to newer ones. `compact` folds a card to one slim line.
--   toast     small navy pills with an accent edge under the banner. Two at most.
--   status    the quiet line at the very top (distance at sea, $/day offline).
-- Timers pause while something bigger is up, so nothing is missed.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local UI = require(script.Parent.UI)
local Fx = require(script.Parent.Fx)

local Notify = {}
Notify.onTakeover = nil :: ((boolean) -> ())?

local player = Players.LocalPlayer
local C = UI.C
local T = UI.T
local SP = UI.SP

export type BannerOpts = {
	sub: string?,
	color: Color3?,
	priority: number?,
	time: number?,
	key: string?,
	sticky: boolean?,
	big: boolean?,
	step: string?, -- tutorial step chip ("1/5")
	compact: boolean?, -- fold the card to one slim line
	icon: string?, -- UI.icon name shown on the card's left
}
type Banner = BannerOpts & { text: string, left: number, order: number, born: number }
type Center = { kind: string, text: string, sub: string?, color: Color3, time: number, icon: string? }

local gui: ScreenGui
local top: Frame
local statusLabel: TextLabel
local bannerSlot: Frame
local toastSlot: Frame
local stage: Frame

local banners: { Banner } = {}
local shownBanner: Banner? = nil
local bannerFrame: Frame? = nil
local bannerRefresh: ((Banner) -> ())? = nil
local order = 0

local toastQueue: { { text: string, color: Color3 } } = {}
local toastsUp = 0

local centerQueue: { Center } = {}
local centerBusy = false
local takeoverOn = false

local function suppressed(): boolean
	return takeoverOn or player:GetAttribute("Cinematic") == true or player:GetAttribute("ViewingTank") == true
end

----------------------------------------------------------------- build
-- The top column stays inside the middle of the screen, clear of the
-- resource pills (left) and the shark widget (right).
local WIDTH = 760
local SUB_COLOR = Color3.fromRGB(225, 235, 255)

-- plain hero text in a fixed-height row the text scales to fit (big titles)
local function label(parent: Instance, text: string, height: number, color: Color3?): TextLabel
	local t = UI.outlined(parent, text, { TextScaled = true, Size = UDim2.fromOffset(WIDTH, height), TextColor3 = color or C.white, Font = UI.TYPE.hero[2] })
	local stroke = t:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Thickness = height >= 50 and 3.5 or (height >= 30 and 2.5 or UI.S.text)
	end
	return t
end

-- one line of text that sizes its own width (cards, toasts)
local function line(parent: Instance, text: string, size: number, color: Color3?, order_: number?): TextLabel
	return UI.outlined(parent, text, { TextScaled = false, TextSize = size, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, size + 4),
		TextColor3 = color or C.white, Font = UI.TYPE.body[2], TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = order_ or 0 })
end

local function hlist(parent: Instance, gap: number): UIListLayout
	local l = Instance.new("UIListLayout")
	l.FillDirection = Enum.FillDirection.Horizontal
	l.VerticalAlignment = Enum.VerticalAlignment.Center
	l.SortOrder = Enum.SortOrder.LayoutOrder
	l.Padding = UDim.new(0, gap)
	l.Parent = parent
	return l
end


local function build()
	gui = Instance.new("ScreenGui")
	gui.Name = "Notify"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 5
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = player:WaitForChild("PlayerGui")
	UI.autoScale(gui)

	-- top column: status, banner, toasts (each collapses when empty)
	top = UI.frame(gui, { Name = "Top", Size = UDim2.fromOffset(WIDTH, 0), AutomaticSize = Enum.AutomaticSize.Y,
		Position = UDim2.new(0.5, 0, 0, SP[2]), AnchorPoint = Vector2.new(0.5, 0), BackgroundTransparency = 1 })
	local list = Instance.new("UIListLayout")
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, SP[2] - 2)
	list.Parent = top
	statusLabel = UI.label(top, "meta", "", { Size = UDim2.fromOffset(WIDTH, 20), LayoutOrder = 1, Visible = false, TextColor3 = T.mute })
	local sc = statusLabel:FindFirstChildOfClass("UITextSizeConstraint")
	if sc then
		sc.MaxTextSize = 20 -- small, but still readable on a phone
	end
	bannerSlot = UI.frame(top, { Name = "Banner", Size = UDim2.fromOffset(WIDTH, 0), BackgroundTransparency = 1, LayoutOrder = 2, Visible = false })
	toastSlot = UI.frame(top, { Name = "Toasts", Size = UDim2.fromOffset(WIDTH, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = 3 })
	local tl = Instance.new("UIListLayout")
	tl.HorizontalAlignment = Enum.HorizontalAlignment.Center
	tl.SortOrder = Enum.SortOrder.LayoutOrder
	tl.Padding = UDim.new(0, SP[1])
	tl.Parent = toastSlot

	-- center stage: takeovers and words
	stage = UI.frame(gui, { Name = "Stage", Size = UDim2.new(1, 0, 0, 230), Position = UDim2.fromScale(0.5, 0.38), AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1 })
end

----------------------------------------------------------------- status line
function Notify.status(text: string?, color: Color3?)
	local show = text ~= nil and text ~= ""
	statusLabel.Visible = show and not suppressed()
	if show and statusLabel.Text ~= text then
		statusLabel.Text = text :: string
	end
	-- quiet: the given color, pulled toward the muted tone
	statusLabel.TextColor3 = (color or C.white):Lerp(T.mute, 0.35)
end

----------------------------------------------------------------- banners
local function cardHeight(b: Banner): number
	return b.sub and 66 or 42 -- plain text: title 40 + sub 24
end

local function slotHeight(b: Banner): number
	if b.big then
		return 52 + (b.sub and 26 or 0)
	end
	return cardHeight(b)
end

-- zone titles: plain hero text over the world, no box
local function bigBanner(b: Banner): (Frame, (Banner) -> ())
	local f = UI.frame(bannerSlot, { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 })
	local title = label(f, b.text, 52, b.color or C.white)
	title.Name = "Title"
	local sub = label(f, b.sub or "", 26, SUB_COLOR)
	sub.Name = "Sub"
	sub.Position = UDim2.fromOffset(0, 52)
	return f, function(nb: Banner)
		title.Text, title.TextColor3 = nb.text, nb.color or C.white
		sub.Text, sub.Visible = nb.sub or "", nb.sub ~= nil
	end
end

-- every other banner (tutorial, shark status...): text only, no box, no
-- step counter. Title in the message color (gold for the tutorial), sub below.
local function plainBanner(b: Banner): (Frame, (Banner) -> ())
	local f = UI.frame(bannerSlot, { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 })
	local title = label(f, b.text, 40, b.color or C.gold)
	local sub = label(f, b.sub or "", 24, SUB_COLOR)
	sub.Position = UDim2.fromOffset(0, 40)
	return f, function(nb: Banner)
		title.Text, title.TextColor3 = nb.text, nb.color or C.gold
		sub.Text, sub.Visible = nb.sub or "", nb.sub ~= nil
	end
end


local function bannerUI(b: Banner): Frame
	bannerSlot.Size = UDim2.fromOffset(WIDTH, slotHeight(b))
	local f, refresh
	if b.big then
		f, refresh = bigBanner(b)
	else
		f, refresh = plainBanner(b)
	end
	bannerRefresh = refresh
	return f
end

local function pickBanner(): Banner?
	local best: Banner? = nil
	for _, b in banners do
		local p = b.priority or 1
		-- a sticky banner steps aside for a fresh transient one of equal priority
		local bp = best and (best.priority or 1) or -1
		if not best or p > bp or (p == bp and (best.sticky and not b.sticky)) then
			best = b
		end
	end
	return best
end

local function swapBanner()
	local want = if suppressed() then nil else pickBanner()
	if want == shownBanner then
		return
	end
	local old = bannerFrame
	if old then
		bannerFrame = nil
		bannerRefresh = nil
		UI.fade(old, false, 0.15)
		task.delay(0.16, function()
			old:Destroy()
		end)
	end
	shownBanner = want
	bannerSlot.Visible = want ~= nil
	if want then
		local f = bannerUI(want)
		bannerFrame = f
		if old then
			f.Visible = false
			task.delay(0.16, function()
				if f.Parent then
					f.Visible = true
					UI.fade(f, true, 0.18)
					UI.pop(f, 1.06)
				end
			end)
		else
			UI.fade(f, true, 0.18)
			UI.pop(f, 1.1)
		end
	end
end

-- show (or update, same key) a top banner
function Notify.banner(text: string, opts: BannerOpts?)
	local o = opts or {}
	if o.key then
		for _, b in banners do
			if b.key == o.key then
				local changed = b.text ~= text or b.sub ~= o.sub or b.color ~= o.color or b.step ~= o.step or b.compact ~= o.compact
				b.text, b.sub, b.color, b.step, b.compact = text, o.sub, o.color, o.step, o.compact
				b.icon = o.icon or b.icon
				b.priority = o.priority or b.priority
				if not b.sticky then
					b.left = o.time or 2.4
				end
				if changed and b == shownBanner and bannerFrame and bannerRefresh then
					bannerRefresh(b)
					if b.big then
						bannerSlot.Size = UDim2.fromOffset(WIDTH, slotHeight(b))
					end
				end
				return
			end
		end
	end
	order += 1
	table.insert(banners, {
		text = text, sub = o.sub, color = o.color, priority = o.priority or 1, key = o.key, sticky = o.sticky, big = o.big,
		step = o.step, compact = o.compact, icon = o.icon,
		left = o.time or 2.4, order = order, born = os.clock(),
	})
	swapBanner()
end

function Notify.clear(key: string)
	for i = #banners, 1, -1 do
		if banners[i].key == key then
			table.remove(banners, i)
		end
	end
	swapBanner()
end

----------------------------------------------------------------- toasts
-- a small navy pill; the accent edge carries the message's color
local function toastUI(text: string, color: Color3): Frame
	-- text only (no box or outline box), in the message's color
	local f = UI.frame(toastSlot, { Name = "Toast", Size = UDim2.fromOffset(0, 30), AutomaticSize = Enum.AutomaticSize.X, BackgroundTransparency = 1 })
	hlist(f, SP[2])
	line(f, text, 22, UI.light(color, 0.35), 2)
	return f
end

local pumpToasts: () -> ()
local function showToast(item: { text: string, color: Color3 })
	toastsUp += 1
	Fx.sound("uiToast", 0.3)
	local t = toastUI(item.text, item.color)
	t.LayoutOrder = -os.clock() * 100 // 1 -- newest on top
	UI.fade(t, true, 0.15)
	UI.pop(t, 1.1)
	task.spawn(function()
		local left = 2.6
		while left > 0 do
			local dt = RunService.Heartbeat:Wait()
			if not suppressed() then
				left -= dt
			end
			t.Visible = not suppressed()
		end
		UI.fade(t, false, 0.25)
		task.wait(0.26)
		t:Destroy()
		toastsUp -= 1
		pumpToasts()
	end)
end

pumpToasts = function()
	while toastsUp < 2 and #toastQueue > 0 and not suppressed() do
		showToast(table.remove(toastQueue, 1) :: any)
	end
end

function Notify.toast(text: string, color: Color3?)
	for _, q in toastQueue do
		if q.text == text then
			return
		end
	end
	table.insert(toastQueue, { text = text, color = color or C.white })
	while #toastQueue > 3 do
		table.remove(toastQueue, 1) -- stale news goes first
	end
	pumpToasts()
end

----------------------------------------------------------------- center stage
local runCenter: () -> ()

local function setTakeover(on: boolean)
	if takeoverOn == on then
		return
	end
	takeoverOn = on
	if Notify.onTakeover then
		Notify.onTakeover(on)
	end
	statusLabel.Visible = statusLabel.Visible and not on
	swapBanner()
	if not on then
		pumpToasts()
	end
end

local function playCenter(item: Center)
	local big = item.kind == "takeover"
	if big then
		Fx.sound("uiTakeover", 0.7)
	end
	local holder = UI.frame(stage, { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 })
	if big then
		-- a soft navy band behind the words so they read over anything,
		-- with thin lines in the moment's color
		local band = UI.frame(holder, { Name = "Band", Size = UDim2.new(1, 0, 0, 180), Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = T.navyDark, BackgroundTransparency = 0.3 })
		local fade = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.25, 0), NumberSequenceKeypoint.new(0.75, 0),
			NumberSequenceKeypoint.new(1, 1) })
		local g = Instance.new("UIGradient")
		g.Transparency = fade
		g.Parent = band
		for _, y in { 0, 1 } do
			local edge = UI.frame(band, { Size = UDim2.new(1, 0, 0, 4), Position = UDim2.fromScale(0, y), AnchorPoint = Vector2.new(0, y), BackgroundColor3 = item.color })
			local eg = Instance.new("UIGradient")
			eg.Transparency = fade
			eg.Parent = edge
		end
	end
	local title = UI.outlined(holder, item.text, { Size = UDim2.new(0.8, 0, 0, big and 96 or 80), Position = UDim2.new(0.5, 0, 0.5, big and -16 or 0),
		AnchorPoint = Vector2.new(0.5, 0.5), Font = UI.TYPE.hero[2], TextColor3 = item.color, Rotation = big and 0 or -3, StrokeColor = T.navyDark })
	local stroke = title:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Thickness = 4
	end
	local shine = Instance.new("UIGradient")
	shine.Rotation = 90
	shine.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(210, 210, 210))
	shine.Parent = title
	if big and item.icon then
		UI.icon(holder, item.icon, { Size = UDim2.fromOffset(110, 110), Position = UDim2.new(0.1, 0, 0.5, -16), AnchorPoint = Vector2.new(0.5, 0.5), Rotation = -8 })
	end
	if big and item.sub then
		UI.label(holder, "body", item.sub, { Size = UDim2.new(0.7, 0, 0, 30), Position = UDim2.new(0.5, 0, 0.5, 52), AnchorPoint = Vector2.new(0.5, 0.5),
			TextColor3 = SUB_COLOR })
	end
	local scale = Instance.new("UIScale")
	scale.Scale = big and 1.6 or 2
	scale.Parent = holder
	UI.fade(holder, true, 0.15)
	TweenService:Create(scale, TweenInfo.new(0.3, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	task.wait(item.time)
	UI.fade(holder, false, 0.3)
	TweenService:Create(scale, TweenInfo.new(0.3, Enum.EasingStyle.Quad), { Scale = big and 0.92 or 0.7 }):Play()
	task.wait(0.3)
	holder:Destroy()
end

runCenter = function()
	if centerBusy then
		return
	end
	centerBusy = true
	task.spawn(function()
		while #centerQueue > 0 do
			-- takeovers jump ahead of waiting words
			local idx = 1
			for i, it in centerQueue do
				if it.kind == "takeover" then
					idx = i
					break
				end
			end
			local item = table.remove(centerQueue, idx) :: Center
			if item.kind == "takeover" then
				setTakeover(true)
			end
			playCenter(item)
			local more = false
			for _, it in centerQueue do
				if it.kind == "takeover" then
					more = true
				end
			end
			if not more then
				setTakeover(false)
			end
			task.wait(0.12)
		end
		centerBusy = false
	end)
end

-- the big moment: center stage, everything else steps aside
-- (icon: an optional UI.icon name shown beside the title)
function Notify.takeover(text: string, sub: string?, color: Color3?, time: number?, icon: string?)
	table.insert(centerQueue, { kind = "takeover", text = text, sub = sub, color = color or C.gold, time = time or 1.7, icon = icon })
	runCenter()
end

-- a punchy center word; one waits, extra ones are dropped
function Notify.word(text: string, color: Color3?, time: number?)
	local waiting = 0
	for _, it in centerQueue do
		if it.kind == "word" then
			waiting += 1
		end
	end
	if waiting >= 1 and centerBusy then
		return
	end
	table.insert(centerQueue, { kind = "word", text = text, color = color or C.gold, time = time or 0.9 })
	runCenter()
end

----------------------------------------------------------------- tick
function Notify.start()
	build()
	-- Fx.bigWord (used everywhere for punch words) lands on center stage
	Fx.wordHook = Notify.word
	RunService.Heartbeat:Connect(function(dt)
		-- news that waited too long behind something more important is stale
		for i = #banners, 1, -1 do
			local b = banners[i]
			if not b.sticky and b ~= shownBanner and os.clock() - b.born > 5 then
				table.remove(banners, i)
			end
		end
		if suppressed() then
			if shownBanner then
				swapBanner()
			end
			return
		end
		local b = shownBanner
		if b and not b.sticky then
			b.left -= dt
			if b.left <= 0 then
				local i = table.find(banners, b)
				if i then
					table.remove(banners, i)
				end
				swapBanner()
			end
		elseif b and b.sticky then
			-- a transient banner that arrived later gets its turn
			swapBanner()
		elseif not b and #banners > 0 then
			swapBanner()
		end
	end)
	local function refresh()
		swapBanner()
		statusLabel.Visible = statusLabel.Visible and not suppressed()
		pumpToasts()
	end
	player:GetAttributeChangedSignal("Cinematic"):Connect(refresh)
	player:GetAttributeChangedSignal("ViewingTank"):Connect(refresh)
end

return Notify
