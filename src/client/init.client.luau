-- +1 Speed to Escape the Shark - client entry.

local State = require(script.State)
local Water = require(script.Water)
local HUD = require(script.HUD)
local Shop = require(script.Shop)
local Index = require(script.Index)
local Hub = require(script.Hub)
local Onboarding = require(script.Onboarding)
require(script.SharkView)

Water.start()
Shop.start()
HUD.onRides = Shop.openRides
HUD.onShop = Shop.openStore
HUD.onIndex = Index.open
HUD.start()
Hub.start()
State.wait()
Onboarding.start()
