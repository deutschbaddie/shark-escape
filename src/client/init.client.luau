-- +1 Speed to Escape the Shark - client entry.

local State = require(script.State)
local Water = require(script.Water)
local HUD = require(script.HUD)
local Shop = require(script.Shop)
local Hub = require(script.Hub)
local Onboarding = require(script.Onboarding)
local Ride = require(script.Ride)
local Animals = require(script.Animals)
local Prompts = require(script.Prompts)
local Tank = require(script.Tank)
local TankView = require(script.TankView)
local Travel = require(script.Travel)
local Audio = require(script.Audio)
local Rewards = require(script.Rewards)
local Settings = require(script.Settings)
require(script.SharkView)
local Npcs = require(script.Npcs)
local Weather = require(script.Weather)
local Portal = require(script.Portal)
local Rings = require(script.Rings)
local Treasure = require(script.Treasure)
local PlayGifts = require(script.PlayGifts)
local Warp = require(script.Warp)
local News = require(script.News)
local Pvp = require(script.Pvp)
local Countdown = require(script.Countdown)
local Reel = require(script.Reel)
local Boss = require(script.Boss)
local SpeedFeel = require(script.SpeedFeel)
local Perf = require(script.Perf)
local Haul = require(script.Haul)
local Bonk = require(script.Bonk)

-- no reset button: resetting would be a free ride home (or a free raid
-- defense). Sharks spit you out instead of killing you anyway.
task.spawn(function()
	for _ = 1, 20 do
		if pcall(game:GetService("StarterGui").SetCore, game:GetService("StarterGui"), "ResetButtonCallback", false) then
			break
		end
		task.wait(0.5)
	end
end)
Water.start()
Audio.start()
Animals.start()
Npcs.start()
Weather.start()
Portal.start()
Rings.start()
Treasure.start()
PlayGifts.start()
Warp.start()
News.start()
Pvp.start()
Countdown.start()
Reel.start()
Boss.start()
SpeedFeel.start()
Perf.start()
Haul.start()
Bonk.start()
Prompts.start()
Ride.start()
Shop.start()
Tank.start()
TankView.start()
-- shops open in person: the buttons take you to the building
HUD.onRides = function()
	Travel.go("Rides")
end
HUD.onShop = function()
	Travel.go("Shop")
end
HUD.onIndex = function()
	Travel.go("Index")
end
HUD.onTank = Tank.toggle -- your collection opens anywhere
HUD.onDaily = Rewards.openDaily
HUD.atRideShop = Shop.atRideShop
HUD.onRebirth = Hub.confirmRebirth
HUD.onSettings = Settings.toggle
Settings.start()
HUD.start()
Hub.start()
Rewards.start()
State.wait()
Onboarding.start()
