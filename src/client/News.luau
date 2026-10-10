-- Server-wide news: someone caught a Legendary, a Huge one or a mutated
-- Epic. Everyone gets a line in chat (bragging rights); only a Mythic also
-- takes a spot on everyone's screen, so other players' news never crowds
-- out your own.

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
		Notify.chat(text, color)
		-- (the catcher gets their own big moment; everyone else just sees the
		-- chat line, except for a Mythic: rare enough to share the screen)
		if data.userId ~= player.UserId and data.r == "Mythic" then
			Notify.banner(text, { key = "news", priority = 2, time = 3.5, color = color })
		end
	end)
end

return News
