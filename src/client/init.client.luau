-- +1 Speed to Escape the Shark - client entry.
-- TODO: Onboarding.luau (arrows, practice shark) is not written yet.

local State = require(script.State)
local Water = require(script.Water)
local HUD = require(script.HUD)
local Shop = require(script.Shop)
require(script.SharkView)

Water.start()
Shop.start()
HUD.onRides = Shop.openRides
HUD.onShop = Shop.openStore
HUD.start()
State.wait()
