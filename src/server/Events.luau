-- Megalodon Hour (Config.Event): every week at the same time (and whenever
-- an admin types /event). While it's on: luckier catches, double coins, and
-- two sharks every night. Workspace "EventEnds" (server time) tells clients.

local Workspace = game:GetService("Workspace")

local Shared = game.ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Game = require(script.Parent.Game)

local Events = {}

local forcedUntil = 0

-- the scheduled window this week: start, end (unix UTC)
function Events.window(now: number): (number, number)
	local cfg = Config.Event
	local t = os.date("!*t", now)
	local startToday = now - (t.hour * 3600 + t.min * 60 + t.sec) + cfg.hour * 3600
	local days = (cfg.weekday - t.wday) % 7
	local start = startToday + days * 86400
	if start + cfg.minutes * 60 <= now then
		start += 7 * 86400 -- this week's already over: next week
	end
	return start, start + cfg.minutes * 60
end

function Events.active(): boolean
	local now = os.time()
	local a, b = Events.window(now)
	return (now >= a and now < b) or now < forcedUntil
end

-- admin: start one right now
function Events.force(minutes: number)
	forcedUntil = os.time() + minutes * 60
end

function Events.start()
	task.spawn(function()
		local was = false
		while true do
			local on = Events.active()
			Game.event = on
			-- when it ends: the weekly window if we're in it, else the forced one
			local now = os.time()
			local a, b = Events.window(now)
			local ends = (now >= a and now < b) and math.max(b, forcedUntil) or forcedUntil
			Workspace:SetAttribute("EventEnds", on and (Workspace:GetServerTimeNow() + (ends - now)) or nil)
			if on ~= was then
				was = on
				if on then
					Game.notifyAll("event", { name = Config.Event.name })
				end
			end
			-- the next start, for the plaza board
			local a = Events.window(os.time())
			Workspace:SetAttribute("EventNext", Workspace:GetServerTimeNow() + (a - os.time()))
			task.wait(5)
		end
	end)
end

return Events
