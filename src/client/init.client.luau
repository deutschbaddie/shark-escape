-- +1 Speed to Escape the Shark - client entry.

local State = require(script.State)
local Water = require(script.Water)
local HUD = require(script.HUD)
local Shop = require(script.Shop)
local Hub = require(script.Hub)
local Onboarding = require(script.Onboarding)
local Ride = require(script.Ride)
require(script.SharkView)

Water.start()
Ride.start()
Shop.start()
-- menus open in person: the buttons take you to the building
local Travel = require(script.Travel)
HUD.onRides = function() Travel.go("Rides") end
HUD.onShop = function() Travel.go("Shop") end
HUD.onIndex = function() Travel.go("Index") end
HUD.atRideShop = Shop.atRideShop
HUD.onRebirth = Hub.confirmRebirth
HUD.start()
Hub.start()
State.wait()
Onboarding.start()
