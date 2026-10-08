-- Getting to the buildings. Menus only open in person (step on a pad), so
-- the HUD buttons bring you there: on land you land right in front of the
-- pad, facing it, and walk in (the pad opens the menu); on the water the
-- guide arrow leads you back first.

local Players = game:GetService("Players")

local Shared = game.ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Layout = require(Shared.Layout)
local UI = require(script.Parent.UI)
local Fx = require(script.Parent.Fx)
local Guide = require(script.Parent.Guide)

local Travel = {}
local player = Players.LocalPlayer

local LABELS = { Rides = "Ride Shop", Shop = "Shop", Index = "Index", Sell = "Sell" }

-- the pad's centre and radius (World.luau builds them: huts 13 wide, Ride Shop 15)
function Travel.padPos(kind: string): (Vector3?, number)
	if kind == "Rides" then
		return Layout.RideShopPad, 7.5
	end
	for _, h in Layout.Huts do
		if h.kind == kind then
			return h.pos + Vector3.new(0, 0, 9), 6.5
		end
	end
	return nil, 0
end

function Travel.go(kind: string)
	local pad, radius = Travel.padPos(kind)
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not (pad and hrp) or hrp.Anchored then
		return
	end
	local pos = hrp.Position
	if Layout.inWater(pos) and not Layout.islandAt(pos, 0) then
		Guide.set("shop", pad + Vector3.new(0, 1, 0), LABELS[kind])
		Fx.bigWord("🏝️ GET TO LAND FIRST!", UI.C.sky, 1.1)
		return
	end
	Fx.splash(pos, 0.8)
	-- land a few steps in front of the pad, facing the building (buildings
	-- face +Z, so look -Z): one short walk in opens it
	local at = pad + Vector3.new(0, Config.BEACH_TOP + 3 - pad.Y, radius + 5)
	char:PivotTo(CFrame.lookAt(at, at - Vector3.new(0, 0, 1)))
	hrp.AssemblyLinearVelocity = Vector3.zero
	Fx.ring(at - Vector3.new(0, 2.6, 0), UI.C.white, 12)
	-- a little arrow onto the pad until you step on it
	Guide.set("shop", pad + Vector3.new(0, 1, 0), "Walk in!")
	task.spawn(function()
		local t0 = os.clock()
		while os.clock() - t0 < 8 do
			task.wait(0.1)
			local h = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if not h or Vector2.new(h.Position.X - pad.X, h.Position.Z - pad.Z).Magnitude < radius then
				break
			end
		end
		if Guide.active("shop") then
			Guide.set("shop", nil)
		end
	end)
end

return Travel
