-- Dev chat commands for the game's developers only.
--   /reset   wipe your own progress back to a brand-new save
--   /storm   start a Lucky Storm now (to test it)
--   /event   start a 15 min Megalodon Hour now

local Players = game:GetService("Players")
local TextChatService = game:GetService("TextChatService")

local Game = require(script.Parent.Game)
local Storm = require(script.Parent.Storm)
local Events = require(script.Parent.Events)

local Admin = {}

local ADMINS = { sickleedge = true, nottufferson = true } -- usernames, lower case

local last: { [Player]: number } = {}

-- admins only, once per message (the command and Chatted can both fire)
local function allowed(player: Player): boolean
	if not ADMINS[player.Name:lower()] or os.clock() - (last[player] or 0) < 2 then
		return false
	end
	last[player] = os.clock()
	return true
end

local COMMANDS: { [string]: (Player) -> () } = {
	reset = function(player)
		local s = Game.sessions[player]
		if s then
			Game.resetProfile(s)
		end
	end,
	storm = function()
		Storm.begin()
	end,
	event = function()
		Events.force(15) -- a 15 min Megalodon Hour now ("admin abuse")
	end,
}

local function run(player: Player, name: string)
	if COMMANDS[name] and allowed(player) then
		COMMANDS[name](player)
	end
end

function Admin.start()
	-- TextChatService commands (also hide "/reset" etc. from chat)
	for name in COMMANDS do
		local cmd = Instance.new("TextChatCommand")
		cmd.Name = name:sub(1, 1):upper() .. name:sub(2) .. "Command"
		cmd.PrimaryAlias = "/" .. name
		cmd.Parent = TextChatService
		cmd.Triggered:Connect(function(source)
			local player = Players:GetPlayerByUserId(source.UserId)
			if player then
				run(player, name)
			end
		end)
	end
	-- legacy chat fallback
	local function watch(player: Player)
		player.Chatted:Connect(function(msg)
			local name = msg:lower():match("^%s*/(%a+)%s*$")
			if name then
				run(player, name)
			end
		end)
	end
	for _, p in Players:GetPlayers() do
		watch(p)
	end
	Players.PlayerAdded:Connect(watch)
	Players.PlayerRemoving:Connect(function(p)
		last[p] = nil
	end)
end

return Admin
