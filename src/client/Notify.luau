-- Every message on screen goes through here, in a clear hierarchy, so the
-- screen never piles up and the important thing is always the obvious one.
--
--   takeover  the big moment (shark incoming, new zone, new ride, legendary):
--             center stage; the HUD and every other message step aside.
--             One at a time, in order.
--   word      a punchy center word (LUCKY!, DODGED!, PTOOEY!). Shares center
--             stage with takeovers and never stacks (one waits, extras drop).
--   banner    the top-center pill. One at a time: the highest priority shows,
--             the rest wait their turn. Sticky ones (shark status, tutorial
--             step) stay until cleared and briefly give way to newer ones.
--   toast     small outlined lines under the banner. Two at most.
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

export type BannerOpts = { sub: string?, color: Color3?, priority: number?, time: number?, key: string?, sticky: boolean? }
type Banner = BannerOpts & { text: string, left: number, order: number, born: number }
type Center = { kind: string, text: string, sub: string?, color: Color3, time: number }

local gui: ScreenGui
local top: Frame
local statusLabel: TextLabel
local bannerSlot: Frame
local toastSlot: Frame
local stage: Frame

local banners: { Banner } = {}
local shownBanner: Banner? = nil
local bannerFrame: Frame? = nil
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
local function label(parent: Instance, text: string, size: number, color: Color3?, font: Enum.Font?): TextLabel
	local t = UI.outlined(parent, text, { TextScaled = false, TextSize = size, AutomaticSize = Enum.AutomaticSize.XY,
		Size = UDim2.fromOffset(0, 0), TextColor3 = color or C.white, Font = font or UI.FONT })
	local stroke = t:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Thickness = size >= 28 and 3.5 or 2.5
	end
	return t
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
	top = UI.frame(gui, { Name = "Top", Size = UDim2.fromOffset(900, 0), AutomaticSize = Enum.AutomaticSize.Y,
		Position = UDim2.new(0.5, 0, 0, 4), AnchorPoint = Vector2.new(0.5, 0), BackgroundTransparency = 1 })
	local list = Instance.new("UIListLayout")
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, 6)
	list.Parent = top
	statusLabel = label(top, "", 22, C.white)
	statusLabel.LayoutOrder = 1
	statusLabel.Visible = false
	bannerSlot = UI.frame(top, { Name = "Banner", Size = UDim2.fromOffset(0, 0), AutomaticSize = Enum.AutomaticSize.XY, BackgroundTransparency = 1, LayoutOrder = 2 })
	toastSlot = UI.frame(top, { Name = "Toasts", Size = UDim2.fromOffset(0, 0), AutomaticSize = Enum.AutomaticSize.XY, BackgroundTransparency = 1, LayoutOrder = 3 })
	local tl = Instance.new("UIListLayout")
	tl.HorizontalAlignment = Enum.HorizontalAlignment.Center
	tl.SortOrder = Enum.SortOrder.LayoutOrder
	tl.Padding = UDim.new(0, 2)
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
	statusLabel.TextColor3 = color or C.white
end

----------------------------------------------------------------- banners
local function bannerUI(b: Banner): Frame
	local f = UI.frame(bannerSlot, { Size = UDim2.fromOffset(0, 0), AutomaticSize = Enum.AutomaticSize.XY,
		BackgroundColor3 = Color3.fromRGB(24, 28, 58), BackgroundTransparency = 0.06 })
	UI.corner(f, 12)
	UI.stroke(f, C.ink, 3)
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft, pad.PaddingRight = UDim.new(0, 20), UDim.new(0, 20)
	pad.PaddingTop, pad.PaddingBottom = UDim.new(0, 5), UDim.new(0, 7)
	pad.Parent = f
	local l = Instance.new("UIListLayout")
	l.HorizontalAlignment = Enum.HorizontalAlignment.Center
	l.SortOrder = Enum.SortOrder.LayoutOrder
	l.Parent = f
	local title = label(f, b.text, 28, b.color or C.white)
	title.Name = "Title"
	title.LayoutOrder = 1
	local sub = label(f, b.sub or "", 17, Color3.fromRGB(200, 220, 255))
	sub.Name = "Sub"
	sub.LayoutOrder = 2
	sub.Visible = b.sub ~= nil
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
		UI.fade(old, false, 0.15)
		task.delay(0.16, function()
			old:Destroy()
		end)
	end
	shownBanner = want
	if want then
		local f = bannerUI(want)
		bannerFrame = f
		if old then
			f.Visible = false
			task.delay(0.16, function()
				if f.Parent then
					f.Visible = true
					UI.fade(f, true, 0.18)
					UI.pop(f, 1.08)
				end
			end)
		else
			UI.fade(f, true, 0.18)
			UI.pop(f, 1.12)
		end
	end
end

-- show (or update, same key) a top banner
function Notify.banner(text: string, opts: BannerOpts?)
	local o = opts or {}
	if o.key then
		for _, b in banners do
			if b.key == o.key then
				local changed = b.text ~= text or b.sub ~= o.sub or b.color ~= o.color
				b.text, b.sub, b.color = text, o.sub, o.color
				b.priority = o.priority or b.priority
				if not b.sticky then
					b.left = o.time or 2.4
				end
				if changed and b == shownBanner and bannerFrame then
					local f = bannerFrame :: Frame
					local t = f:FindFirstChild("Title") :: TextLabel
					local s = f:FindFirstChild("Sub") :: TextLabel
					t.Text, t.TextColor3 = text, o.color or C.white
					s.Text, s.Visible = o.sub or "", o.sub ~= nil
				end
				return
			end
		end
	end
	order += 1
	table.insert(banners, {
		text = text, sub = o.sub, color = o.color, priority = o.priority or 1, key = o.key, sticky = o.sticky,
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
local pumpToasts: () -> ()
local function showToast(item: { text: string, color: Color3 })
	toastsUp += 1
	local t = label(toastSlot, item.text, 22, item.color)
	t.LayoutOrder = -os.clock() * 100 // 1 -- newest on top
	UI.fade(t, true, 0.15)
	UI.pop(t, 1.15)
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
	local holder = UI.frame(stage, { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 })
	if big then
		-- a soft dark band behind the words so they read over anything
		local band = UI.frame(holder, { Size = UDim2.new(1, 0, 0, 190), Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.45 })
		local g = Instance.new("UIGradient")
		g.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.25, 0.2),
			NumberSequenceKeypoint.new(0.75, 0.2), NumberSequenceKeypoint.new(1, 1) })
		g.Parent = band
	end
	local title = UI.outlined(holder, item.text, { Size = UDim2.new(0.92, 0, 0, big and 104 or 84), Position = UDim2.new(0.5, 0, 0.5, big and -16 or 0),
		AnchorPoint = Vector2.new(0.5, 0.5), Font = UI.NUMFONT, TextColor3 = item.color, Rotation = big and 0 or -3 })
	local stroke = title:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Thickness = 5
	end
	local shine = Instance.new("UIGradient")
	shine.Rotation = 90
	shine.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(205, 205, 205))
	shine.Parent = title
	if big and item.sub then
		UI.outlined(holder, item.sub, { Size = UDim2.new(0.8, 0, 0, 34), Position = UDim2.new(0.5, 0, 0.5, 58), AnchorPoint = Vector2.new(0.5, 0.5) })
	end
	local scale = Instance.new("UIScale")
	scale.Scale = big and 1.9 or 2.2
	scale.Parent = holder
	UI.fade(holder, true, 0.15)
	TweenService:Create(scale, TweenInfo.new(0.32, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	task.wait(item.time)
	UI.fade(holder, false, 0.3)
	TweenService:Create(scale, TweenInfo.new(0.3, Enum.EasingStyle.Quad), { Scale = big and 0.9 or 0.7 }):Play()
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
function Notify.takeover(text: string, sub: string?, color: Color3?, time: number?)
	table.insert(centerQueue, { kind = "takeover", text = text, sub = sub, color = color or C.gold, time = time or 1.7 })
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
