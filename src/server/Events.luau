-- Megalodon Hour (Config.Event): every week at the same time (and whenever
-- an admin types /event). While it's on: x3 luck, double coins, two sharks
-- every night, and the boss Megalodon (Sharks.spawnBoss) surfaces in each
-- world with players, again every Config.Boss.every seconds. Everyone who
-- harpooned it enough gets a Legendary. Workspace "EventEnds" (server time)
-- tells clients.

local Workspace = game:GetService("Workspace")

local Shared = game.ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Game = require(script.Parent.Game)
local Sharks = require(script.Parent.Sharks)
local Bubbles = require(script.Parent.Bubbles)

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

-- the boss in every world someone's in
local lastBoss = 0
function Events.spawnBosses()
	lastBoss = os.clock()
	local seen = {}
	for _, s in Game.sessions do
		local w = s.profile.world or 1
		if not seen[w] then
			seen[w] = true
			Sharks.spawnBoss(w)
		end
	end
end

local function bossDown(_world: number, winners: { [Player]: number })
	for p in winners do
		local s = Game.sessions[p]
		if s then
			Bubbles.give(s, Config.Boss.reward)
			Game.notify(p, "bossReward", { r = Config.Boss.reward })
		end
	end
end

-- the server events (Config.MiniEvents): one every 15 min, taking turns
local miniIndex = 0
local function runMini(def: any)
	local cfg = Config.MiniEvents
	Game.mini = def.id
	Workspace:SetAttribute("MiniEvent", def.id)
	Workspace:SetAttribute("MiniEnds", Workspace:GetServerTimeNow() + cfg.length)
	Game.notifyAll("miniEvent", { id = def.id, length = cfg.length })
	if def.id == "rain" then
		for w in Config.Worlds do
			Bubbles.rain(w, cfg.rain, cfg.length)
		end
	end
	task.wait(cfg.length)
	Game.mini = nil
	Workspace:SetAttribute("MiniEvent", nil)
	Workspace:SetAttribute("MiniEnds", nil)
	Game.notifyAll("miniEventEnd", { id = def.id })
end

function Events.forceMini(id: string?)
	for i, def in Config.MiniEvents.list do
		if def.id == id or (id == nil and i == miniIndex % #Config.MiniEvents.list + 1) then
			if not Game.mini then
				if id == nil then
					miniIndex += 1 -- (the rotation moves on)
				end
				task.spawn(runMini, def)
			end
			return
		end
	end
end

local function miniLoop()
	local cfg = Config.MiniEvents
	local wait = cfg.first
	while true do
		local nextDef = cfg.list[miniIndex % #cfg.list + 1]
		Workspace:SetAttribute("MiniNext", Workspace:GetServerTimeNow() + wait)
		Workspace:SetAttribute("MiniNextId", nextDef.id)
		task.wait(wait)
		if Game.event or Game.mini then
			wait = 60 -- (Megalodon Hour, or an admin's /mini, is on: try again after it)
			continue
		end
		miniIndex += 1
		Workspace:SetAttribute("MiniNext", nil)
		runMini(nextDef)
		wait = cfg.every - cfg.length
	end
end

function Events.start()
	Sharks.onBossDown = bossDown
	task.spawn(miniLoop)
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
					lastBoss = os.clock()
					task.delay(20, Events.spawnBosses) -- a moment to get in the water
				end
			elseif on and os.clock() - lastBoss > Config.Boss.every then
				Events.spawnBosses()
			end
			-- the next start, for the plaza board
			local a = Events.window(os.time())
			Workspace:SetAttribute("EventNext", Workspace:GetServerTimeNow() + (a - os.time()))
			task.wait(5)
		end
	end)
end

return Events
