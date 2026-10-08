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
require(script.SharkView)

Water.start()
Audio.start()
Animals.start()
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
HUD.start()
Hub.start()
Rewards.start()
State.wait()
Onboarding.start()
