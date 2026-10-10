-- Big catches: yours get a line in chat (and your own big moment on
-- screen); other players' stay their business, except a Mythic, which is
-- rare enough to tell everyone.

local Players = game:GetService("Players")

local Shared = game.ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local Notify = require(script.Parent.Notify)

local News = {}
local player = Players.LocalPlayer

function News.start()
	Remotes.get("Notify").OnClientEvent:Connect(function(kind, data)
		if kind ~= "bigCatch" or typeof(data) ~= "table" then
			return
		end
		local color = Config.rarity(data.r or "Legendary").color
		local text = ("%s caught a %s!"):format(tostring(data.by), tostring(data.name))
		local mine = data.userId == player.UserId
		if mine then
			Notify.chat(("You caught a %s!"):format(tostring(data.name)), color, data.r == "Mythic" and "MYTHIC" or "BIG CATCH", true)
		elseif data.r == "Mythic" then
			-- other players' catches stay their business, except a Mythic
			Notify.chat(text, color, "MYTHIC")
			Notify.banner(text, { key = "news", priority = 2, time = 3.5, color = color })
		end
	end)
end

return News
