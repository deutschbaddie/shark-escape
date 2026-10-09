-- Megalodon Hour on this client: fills the plaza boards' countdowns (to
-- the event, or how long it has left; and to the next update), shows a
-- big moment when it starts and a banner while it's on.

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = game.ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Layout = require(Shared.Layout)
local Remotes = require(Shared.Remotes)
local Fx = require(script.Parent.Fx)
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

local function tick()
	local now = Workspace:GetServerTimeNow()
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
			sub = ("x3 luck · 2x coins · the boss Megalodon · %s left"):format(long(ends - now)) })
	else
		Notify.clear("event")
	end
end

function Countdown.start()
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc >= 1 then
			acc = 0
			tick()
		end
	end)
	Remotes.get("Notify").OnClientEvent:Connect(function(kind)
		if kind == "event" then
			Notify.takeover(Config.Event.name, "x3 luck, 2x coins, and the boss Megalodon surfaces soon", RED, 2.4, "Shark")
			Fx.sound("sharkAlarm", 0.9)
			Fx.shake(1)
		end
	end)
end

return Countdown
