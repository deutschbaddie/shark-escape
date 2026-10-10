-- Megalodon Hour on this client: fills the plaza boards' countdowns (to
-- the event, or how long it has left; and to the next update), shows a
-- big moment when it starts and a banner while it's on.
-- Plus the server events (Config.MiniEvents): a pill by the shark timer
-- ("Golden Tide in 4:12", then "Golden Tide · 1:05" while it's on) and each
-- one's start: Golden Tide washes the screen gold, Feeding Frenzy pulses red
-- at the edges, Bubble Rain drops bubbles out of the sky (Water.luau).

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = game.ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Layout = require(Shared.Layout)
local Remotes = require(Shared.Remotes)
local Fx = require(script.Parent.Fx)
local UI = require(script.Parent.UI)
local Notify = require(script.Parent.Notify)

local Countdown = {}
local RED = Color3.fromRGB(255, 90, 100)

-- 2d 4h / 3h 12m / 12m 05s
local function long(sec: number): string
	sec = math.max(0, math.floor(sec))
	local d, h, m, s = sec // 86400, (sec // 3600) % 24, (sec // 60) % 60, sec % 60
	if d > 0 then
		return ("%dd %dh"):format(d, h)
	elseif h > 0 then
		return ("%dh %02dm"):format(h, m)
	end
	return ("%dm %02ds"):format(m, s)
end

----------------------------------------------------------------- server events
local pill: Frame
local pillText: TextLabel
local players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")
local grade: ColorCorrectionEffect? = nil

local function miniDef(id: any): any
	for _, d in Config.MiniEvents.list do
		if d.id == id then
			return d
		end
	end
	return nil
end

local function buildPill()
	local gui = Instance.new("ScreenGui")
	gui.Name = "NextEvent"
	UI.hideInCutscenes(gui)
	gui.ResetOnSpawn = false
	gui.Parent = players.LocalPlayer:WaitForChild("PlayerGui")
	UI.autoScale(gui)
	-- phones: left of the settings gear (shark timer top-right); desktop:
	-- over the shark timer (bottom-right)
	local props = UI.TOUCH and { Size = UDim2.fromOffset(200, 38), Position = UDim2.new(1, -318, 0, 14), AnchorPoint = Vector2.new(1, 0) }
		or { Size = UDim2.fromOffset(250, 36), Position = UDim2.new(1, 0, 1, -66), AnchorPoint = Vector2.new(1, 1) }
	props.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	props.BackgroundTransparency = 0.45
	props.Visible = false
	pill = UI.frame(gui, props)
	UI.corner(pill, 19)
	pillText = UI.outlined(pill, "", { Size = UDim2.new(1, -16, 1, -6), Position = UDim2.fromOffset(8, 3), TextColor3 = Color3.new(1, 1, 1) })
end

local function miniTick(now: number)
	local live = Workspace:GetAttribute("MiniEvent")
	local ends = Workspace:GetAttribute("MiniEnds")
	local nextAt = Workspace:GetAttribute("MiniNext")
	local def = miniDef(live)
	if def and typeof(ends) == "number" then
		pill.Visible = true
		pillText.Text = ("%s · %s"):format(def.name, long(ends - now))
		pillText.TextColor3 = def.color
		return
	end
	def = miniDef(Workspace:GetAttribute("MiniNextId"))
	if def and typeof(nextAt) == "number" and nextAt > now then
		pill.Visible = true
		pillText.Text = ("%s in %s"):format(def.name, long(nextAt - now))
		pillText.TextColor3 = Color3.new(1, 1, 1)
	else
		pill.Visible = false
	end
end

-- each event's start, as a feeling
local function miniStart(id: string)
	local def = miniDef(id)
	if not def then
		return
	end
	Notify.banner(def.name, { key = "mini", priority = 3, time = 4, color = def.color, sub = def.desc })
	Notify.chat(("%s! %s"):format(def.name, def.desc), nil, "EVENT", true)
	Fx.sound("discover", 0.9)
	if id == "golden" then
		-- a warm gold wash that eases off to a gentle tint for the event
		Fx.flash(def.color, 0.6, 0.55)
		if not grade then
			grade = Instance.new("ColorCorrectionEffect")
			grade.Name = "GoldenTide"
			grade.Parent = Lighting
		end
		local g = grade :: ColorCorrectionEffect
		g.TintColor = Color3.new(1, 1, 1)
		TweenService:Create(g, TweenInfo.new(2.5, Enum.EasingStyle.Sine), { TintColor = Color3.fromRGB(255, 240, 205), Saturation = 0.1 }):Play()
	elseif id == "frenzy" then
		Fx.sound("sharkAlarm", 0.8)
		Fx.shake(0.8)
		-- the edges pulse red for a few beats
		local hrp = players.LocalPlayer.Character and players.LocalPlayer.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		for i = 0, 2 do
			task.delay(i * 0.6, function()
				Fx.edgeWarn(hrp and hrp.Position + Vector3.new(0, 0, 60) or Vector3.zero, 0.5, def.color)
			end)
		end
	elseif id == "rain" then
		Fx.shake(0.4)
	end
end

local function miniEnd(id: string)
	local def = miniDef(id)
	if grade then
		local g = grade
		grade = nil
		TweenService:Create(g, TweenInfo.new(2), { TintColor = Color3.new(1, 1, 1), Saturation = 0 }):Play()
		task.delay(2.1, function()
			g:Destroy()
		end)
	end
	if def then
		Notify.toast(("%s is over"):format(def.name), Color3.new(1, 1, 1))
	end
end

local function tick()
	local now = Workspace:GetServerTimeNow()
	miniTick(now)
	local ends = Workspace:GetAttribute("EventEnds")
	local nextAt = Workspace:GetAttribute("EventNext")
	local live = typeof(ends) == "number" and ends > now
	local timeText = live and ("Live now · %s left"):format(long(ends - now))
		or (typeof(nextAt) == "number" and ("starts in %s"):format(long(nextAt - now)) or "")
	local limited, limitedEnds = Config.limitedNow()
	local limitedText = ("This week only: %s catches · %s left"):format(limited.id, long(limitedEnds - os.time()))
	local updateText = Config.NextUpdate > os.time() and ("Next update in %s"):format(long(Config.NextUpdate - os.time())) or ""
	for _, map in Layout.worldFolders() do
		local board = map:FindFirstChild("EventBoard")
		local sg = board and board:FindFirstChild("Countdown", true)
		if sg then
			local t = sg:FindFirstChild("Time") :: TextLabel?
			local u = sg:FindFirstChild("Update") :: TextLabel?
			local l = sg:FindFirstChild("Limited") :: TextLabel?
			if l then
				l.Text = limitedText
				l.TextColor3 = limited.color
			end
			if t then
				t.Text = timeText
				t.TextColor3 = live and RED or Color3.new(1, 1, 1)
			end
			if u then
				u.Text = updateText
			end
		end
	end
	if live then
		Notify.banner(Config.Event.name, { key = "event", sticky = true, priority = 1, color = RED,
			sub = ("x3 luck · 2x cash · boss · %s left"):format(long(ends - now)) })
	else
		Notify.clear("event")
	end
end

-- (the UI preview: the pill as it looks before an event)
function Countdown.preview()
	buildPill()
	pill.Visible = true
	pillText.Text = "Golden Tide in 4m 12s"
end

function Countdown.start()
	buildPill()
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc >= 1 then
			acc = 0
			tick()
		end
	end)
	Remotes.get("Notify").OnClientEvent:Connect(function(kind, data)
		if kind == "miniEvent" and typeof(data) == "table" then
			miniStart(data.id)
		elseif kind == "miniEventEnd" and typeof(data) == "table" then
			miniEnd(data.id)
		end
		if kind == "event" then
			Notify.takeover(Config.Event.name, "x3 luck, 2x cash, and a boss!", RED, 2.4, "Shark")
			Notify.chat(("%s! x3 luck, 2x cash, and a boss"):format(Config.Event.name), nil, "EVENT", true)
			Fx.sound("sharkAlarm", 0.9)
			Fx.shake(1)
		end
	end)
end

return Countdown
