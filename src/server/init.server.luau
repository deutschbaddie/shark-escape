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
local Storm = require(script.Storm)
local Treasure = require(script.Treasure)

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
Storm.start()
Treasure.start()

Players.CharacterAutoLoads = true
for _, p in Players:GetPlayers() do
	if not p.Character then
		task.spawn(p.LoadCharacter, p)
	end
end
