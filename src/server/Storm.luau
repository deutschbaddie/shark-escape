-- Lucky Storm: every so often the sky goes dark for everyone in the server
-- and catches get much luckier (rarer creatures, more mutations). The
-- server sets Workspace "StormUntil" (server time); clients draw the rain.

local Workspace = game:GetService("Workspace")

local Shared = game.ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Game = require(script.Parent.Game)

local Storm = {}

local rng = Random.new()
local endsAt = 0

-- start one now (also the admin /storm command)
function Storm.begin()
	local cfg = Config.Storm
	endsAt = Workspace:GetServerTimeNow() + cfg.duration
	Game.storm = true
	Workspace:SetAttribute("StormUntil", endsAt)
	task.delay(cfg.duration, function()
		if Workspace:GetServerTimeNow() >= endsAt - 0.5 then
			Game.storm = false
			Workspace:SetAttribute("StormUntil", nil)
		end
	end)
end

function Storm.start()
	task.spawn(function()
		while true do
			task.wait(rng:NextNumber(Config.Storm.every[1], Config.Storm.every[2]))
			if not Game.storm then
				Storm.begin()
			end
		end
	end)
end

return Storm
