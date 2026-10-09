-- Server-wide news: someone caught a Legendary, a Huge one or a mutated
-- Epic. Everyone sees a banner and a line in chat, so big catches get
-- bragged about (and chased).

local Players = game:GetService("Players")
local TextChatService = game:GetService("TextChatService")

local Shared = game.ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local Notify = require(script.Parent.Notify)

local News = {}
local player = Players.LocalPlayer

local function chat(text: string, color: Color3)
	pcall(function()
		local channels = TextChatService:FindFirstChild("TextChannels")
		local system = channels and channels:FindFirstChild("RBXSystem") :: TextChannel?
		if system then
			system:DisplaySystemMessage(("<font color=\"#%s\"><b>%s</b></font>"):format(color:ToHex(), text))
		end
	end)
end

function News.start()
	Remotes.get("Notify").OnClientEvent:Connect(function(kind, data)
		if kind ~= "bigCatch" or typeof(data) ~= "table" then
			return
		end
		local color = Config.rarity(data.r or "Legendary").color
		local text = ("%s caught a %s!"):format(tostring(data.by), tostring(data.name))
		chat(text, color)
		if data.userId ~= player.UserId then -- (the catcher gets their own big moment)
			Notify.banner(text, { key = "news", priority = 2, time = 3.5, color = color })
		end
	end)
end

return News
