-- +1 Speed to Escape the Shark - server entry.

local Players = game:GetService("Players")

-- hold spawns until the beach exists
Players.CharacterAutoLoads = false

local World = require(script.World)
local Game = require(script.Game)
local Bubbles = require(script.Bubbles)
local Sharks = require(script.Sharks)
local Market = require(script.Market)
local Leaderboard = require(script.Leaderboard)
local IconSheets = require(script.IconSheets)
local Rewards = require(script.Rewards)
local Admin = require(script.Admin)
local Analytics = require(script.Analytics)
local Treasure = require(script.Treasure)
local Raids = require(script.Raids)
local Events = require(script.Events)
local Quests = require(script.Quests)
local Bonk = require(script.Bonk)

World.build()
Analytics.start()
Market.start()
Game.start()
Bubbles.start()
Sharks.start()
Leaderboard.start()
IconSheets.start()
Rewards.start()
Admin.start()
Treasure.start()
Raids.start()
Events.start()
Quests.start()
Bonk.start()

Players.CharacterAutoLoads = true
for _, p in Players:GetPlayers() do
	if not p.Character then
		task.spawn(p.LoadCharacter, p)
	end
end
