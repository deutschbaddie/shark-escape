-- Dev chat commands for the game's developers only.
--   /reset   wipe your own progress back to a brand-new save

local Players = game:GetService("Players")
local TextChatService = game:GetService("TextChatService")

local Game = require(script.Parent.Game)

local Admin = {}

local ADMINS = { sickleedge = true, nottufferson = true } -- usernames, lower case

local last: { [Player]: number } = {}

local function reset(player: Player)
	if not ADMINS[player.Name:lower()] then
		return
	end
	if os.clock() - (last[player] or 0) < 2 then
		return -- the command and Chatted can both fire for one message
	end
	last[player] = os.clock()
	local s = Game.sessions[player]
	if s then
		Game.resetProfile(s)
	end
end

function Admin.start()
	-- TextChatService command (also hides "/reset" from chat)
	local cmd = Instance.new("TextChatCommand")
	cmd.Name = "ResetCommand"
	cmd.PrimaryAlias = "/reset"
	cmd.Parent = TextChatService
	cmd.Triggered:Connect(function(source)
		local player = Players:GetPlayerByUserId(source.UserId)
		if player then
			reset(player)
		end
	end)
	-- legacy chat fallback
	local function watch(player: Player)
		player.Chatted:Connect(function(msg)
			if msg:lower():match("^%s*/reset%s*$") then
				reset(player)
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
