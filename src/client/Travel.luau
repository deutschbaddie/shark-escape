-- Getting to the buildings. Menus only open in person (step on a pad), so
-- the HUD buttons bring you there: on land you teleport onto the pad (the
-- pad opens the menu); on the water the guide arrow leads you back first.

local Players = game:GetService("Players")

local Shared = game.ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Layout = require(Shared.Layout)
local UI = require(script.Parent.UI)
local Fx = require(script.Parent.Fx)
local Guide = require(script.Parent.Guide)

local Travel = {}
local player = Players.LocalPlayer

local LABELS = { Rides = "Ride Shop", Shop = "Shop", Index = "Index" }

function Travel.padPos(kind: string): Vector3?
	if kind == "Rides" then
		return Layout.RideShopPad
	end
	for _, h in Layout.Huts do
		if h.kind == kind then
			return h.pos + Vector3.new(0, 0, 9)
		end
	end
	return nil
end

function Travel.go(kind: string)
	local pad = Travel.padPos(kind)
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
	Guide.set("shop", nil)
	Fx.splash(pos, 0.8)
	-- land on the pad facing the building (buildings face +Z, so look -Z)
	local at = pad + Vector3.new(0, Config.BEACH_TOP + 3 - pad.Y, 0)
	char:PivotTo(CFrame.lookAt(at, at - Vector3.new(0, 0, 1)))
	hrp.AssemblyLinearVelocity = Vector3.zero
	Fx.ring(pad + Vector3.new(0, 0.4, 0), UI.C.white, 18)
end

return Travel
