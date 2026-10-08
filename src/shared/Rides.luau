-- Hand-built rides. Root sits where the player's feet go; everything faces -Z.
-- Rides are visual only - the character stands on the hidden water floor.

local CollectionService = game:GetService("CollectionService")

local Build = require(script.Parent.Build)

local Rides = {}

local C = Color3.fromRGB
local WHITE = C(255, 255, 255)

local builders: { [string]: (Model) -> () } = {}

local function board(m: Model, len: number, wid: number, color: Color3, stripe: Color3?, y: number?)
	local yy = y or -0.3
	Build.studs(Build.part(m, Vector3.new(wid, 0.5, len - wid), CFrame.new(0, yy, 0), color))
	Build.cyl(m, 0.5, wid, CFrame.new(0, yy, -(len - wid) / 2), color)
	Build.cyl(m, 0.5, wid, CFrame.new(0, yy, (len - wid) / 2), color)
	if stripe then
		Build.part(m, Vector3.new(0.5, 0.52, len - wid * 0.6), CFrame.new(0, yy + 0.01, 0), stripe)
	end
end

builders.Noodle = function(m)
	-- two noodles, centered under the rider
	local noodle = Build.part(m, Vector3.new(8, 1.1, 1.1), CFrame.new(-0.55, -0.55, 0) * CFrame.Angles(0, math.pi / 2, 0), C(255, 128, 40))
	noodle.Shape = Enum.PartType.Cylinder
	local n2 = Build.part(m, Vector3.new(8, 1.1, 1.1), CFrame.new(0.55, -0.55, 0) * CFrame.Angles(0, math.pi / 2, 0), C(255, 72, 150))
	n2.Shape = Enum.PartType.Cylinder
end

builders.Duck = function(m)
	local yellow = C(255, 214, 40)
	Build.ring(m, 2.0, 1.2, CFrame.new(0, -0.5, 0), yellow, 12)
	Build.ball(m, 1.7, CFrame.new(0, 0.7, -2.4), yellow)
	Build.wedge(m, Vector3.new(0.9, 0.35, 0.8), CFrame.new(0, 0.55, -3.35) * CFrame.Angles(0, math.pi, 0), C(255, 140, 30))
	for _, side in { -1, 1 } do
		Build.ball(m, 0.4, CFrame.new(side * 0.45, 1.05, -3.05), C(27, 29, 63))
	end
	Build.wedge(m, Vector3.new(0.6, 0.9, 0.9), CFrame.new(0, 0, 2.3), yellow)
end

builders.Tube = function(m)
	Build.ring(m, 2.1, 1.3, CFrame.new(0, -0.5, 0), C(40, 140, 255), 12, WHITE)
end

builders.Boogie = function(m)
	board(m, 4.6, 2.6, C(230, 40, 60), WHITE)
end

builders.Surf = function(m)
	board(m, 8, 2.4, C(40, 200, 220), C(255, 200, 40))
	Build.wedge(m, Vector3.new(0.2, 0.8, 0.9), CFrame.new(0, -0.95, 3.2) * CFrame.Angles(math.pi, 0, 0), C(255, 255, 255))
end

builders.Bathtub = function(m)
	local tub = C(250, 250, 255)
	Build.part(m, Vector3.new(4, 0.5, 6.4), CFrame.new(0, -0.35, 0), tub)
	Build.part(m, Vector3.new(0.4, 1.8, 6.4), CFrame.new(-1.9, 0.3, 0), tub)
	Build.part(m, Vector3.new(0.4, 1.8, 6.4), CFrame.new(1.9, 0.3, 0), tub)
	Build.part(m, Vector3.new(4, 1.8, 0.4), CFrame.new(0, 0.3, -3), tub)
	Build.part(m, Vector3.new(4, 1.8, 0.4), CFrame.new(0, 0.3, 3), tub)
	Build.part(m, Vector3.new(3.4, 0.2, 5.8), CFrame.new(0, 0.6, 0), C(140, 220, 255), { Transparency = 0.35 })
	for _, x in { -1.6, 1.6 } do
		for _, z in { -2.6, 2.6 } do
			Build.ball(m, 0.6, CFrame.new(x, -0.7, z), C(255, 200, 60))
		end
	end
	Build.ball(m, 0.8, CFrame.new(1.2, 1.1, -2.2), C(255, 214, 40))
	for i = 1, 6 do
		Build.ball(m, 0.5 + (i % 3) * 0.2, CFrame.new((i - 3.5) * 0.6, 1.0 + (i % 2) * 0.2, 2.4), WHITE)
	end
end

builders.Banana = function(m)
	local y = C(255, 220, 30)
	local body = Build.part(m, Vector3.new(9, 1.8, 1.8), CFrame.new(0, -0.6, 0) * CFrame.Angles(0, math.pi / 2, 0), y)
	body.Shape = Enum.PartType.Cylinder
	Build.ball(m, 1.8, CFrame.new(0, -0.6, -4.5), y)
	Build.ball(m, 1.6, CFrame.new(0, -0.3, 4.4), C(110, 70, 30))
	for _, z in { -2.5, 0, 2.5 } do
		Build.part(m, Vector3.new(2.4, 0.3, 0.3), CFrame.new(0, 0.6, z), C(60, 60, 70))
	end
end

builders.JetSki = function(m)
	local body = C(230, 30, 50)
	Build.wedge(m, Vector3.new(3, 1.4, 2.6), CFrame.new(0, -0.7, -3.3) * CFrame.Angles(0, 0, 0), body)
	Build.studs(Build.part(m, Vector3.new(3, 1.4, 5), CFrame.new(0, -0.7, 0.5), body))
	Build.part(m, Vector3.new(1.4, 0.6, 3), CFrame.new(0, 0.2, 1.2), C(30, 30, 40))
	Build.part(m, Vector3.new(0.4, 2.2, 0.4), CFrame.new(0, 0.9, -1.6) * CFrame.Angles(-0.4, 0, 0), C(40, 40, 50))
	Build.part(m, Vector3.new(2.6, 0.3, 0.3), CFrame.new(0, 1.9, -2.0), C(40, 40, 50))
	Build.part(m, Vector3.new(3.05, 0.3, 4.6), CFrame.new(0, -0.3, 0.6), WHITE)
end

builders.Speedboat = function(m)
	local hull = C(250, 250, 255)
	Build.wedge(m, Vector3.new(4.4, 2, 3.4), CFrame.new(0, -0.4, -4.6), hull)
	Build.part(m, Vector3.new(4.4, 2, 6), CFrame.new(0, -0.4, 0.1), hull)
	Build.part(m, Vector3.new(4.5, 0.5, 9.4), CFrame.new(0, -0.9, -0.6), C(30, 90, 220))
	Build.part(m, Vector3.new(3.4, 1.4, 0.2), CFrame.new(0, 1.2, -2.4) * CFrame.Angles(-0.5, 0, 0), C(160, 230, 255), { Transparency = 0.4 })
	Build.part(m, Vector3.new(1.2, 2, 1.2), CFrame.new(0, -0.2, 3.6), C(40, 40, 50))
end

builders.Dolphin = function(m)
	local grey = C(120, 160, 210)
	Build.ell(m, Vector3.new(2.6, 2.2, 8), CFrame.new(0, -1.0, 0), grey)
	local belly = Build.ell(m, Vector3.new(2.2, 1.2, 6.6), CFrame.new(0, -1.6, -0.2), C(235, 244, 255))
	belly:SetAttribute("KeepColor", true)
	Build.ell(m, Vector3.new(0.9, 0.7, 2.2), CFrame.new(0, -1.1, -4.6), grey)
	Build.wedge(m, Vector3.new(0.3, 1.6, 1.8), CFrame.new(0, 0.6, 1.2), grey)
	Build.wedge(m, Vector3.new(3.4, 0.3, 1.2), CFrame.new(0, -0.9, 4.4) * CFrame.Angles(0, math.pi, 0), grey)
	for _, side in { -1, 1 } do
		Build.ball(m, 0.45, CFrame.new(side * 0.9, -0.5, -3.0), C(27, 29, 63))
	end
end

builders.Donut = function(m)
	Build.ring(m, 2.4, 1.6, CFrame.new(0, -0.7, 0), C(214, 150, 80), 14)
	Build.ring(m, 2.4, 1.0, CFrame.new(0, -0.15, 0), C(255, 120, 190), 14)
	local rng = Random.new(3)
	for i = 1, 18 do
		local a = i / 18 * math.pi * 2
		local r = 2.4 + rng:NextNumber(-0.4, 0.4)
		local cols = { C(255, 255, 255), C(255, 220, 40), C(60, 200, 255), C(120, 230, 120) }
		Build.part(m, Vector3.new(0.5, 0.15, 0.15), CFrame.new(math.cos(a) * r, 0.37, math.sin(a) * r) * CFrame.Angles(0, rng:NextNumber(0, 3), 0), cols[i % 4 + 1], { Material = Enum.Material.Neon })
	end
end

builders.Rocket = function(m)
	board(m, 8.4, 2.6, C(40, 40, 60), C(255, 60, 60))
	for _, x in { -0.8, 0.8 } do
		local t = Build.part(m, Vector3.new(2.6, 1, 1), CFrame.new(x, -0.1, 3.6) * CFrame.Angles(0, math.pi / 2, 0), C(200, 200, 210), { Material = Enum.Material.Metal })
		t.Shape = Enum.PartType.Cylinder
		local flame = Build.part(m, Vector3.new(0.4, 0.8, 0.8), CFrame.new(x, -0.1, 5.0) * CFrame.Angles(0, math.pi / 2, 0), C(255, 140, 30), { Material = Enum.Material.Neon, Shape = Enum.PartType.Cylinder })
		local fire = Instance.new("Fire")
		fire.Size = 3
		fire.Heat = 0
		fire.Color = C(255, 160, 40)
		fire.SecondaryColor = C(255, 60, 30)
		fire.Parent = flame
	end
end

builders.GoldDuck = function(m)
	builders.Duck(m)
	Build.recolor(m, C(255, 200, 50), Enum.Material.Foil)
	local sp = Instance.new("Sparkles")
	sp.SparkleColor = C(255, 230, 120)
	sp.Parent = m:FindFirstChildWhichIsA("BasePart")
end

builders.SharkBoard = function(m)
	board(m, 8, 2.6, C(106, 129, 153), C(246, 247, 249))
	Build.wedge(m, Vector3.new(0.3, 1.6, 1.8), CFrame.new(0, 0.7, 2.2), C(90, 111, 134))
	for i = 0, 5 do
		Build.wedge(m, Vector3.new(0.3, 0.45, 0.3), CFrame.new(-0.9 + i * 0.36, -0.15, -3.75) * CFrame.Angles(0, 0, math.pi), WHITE)
	end
end

builders.RainbowSki = function(m)
	builders.JetSki(m)
	m:SetAttribute("Rainbow", true)
	CollectionService:AddTag(m, "Rainbow")
end

function Rides.build(id: string): Model
	local m = Build.model("Ride_" .. id)
	Build.root(m)
	local fn = builders[id] or builders.Noodle
	fn(m)
	Build.ghost(m)
	return m
end

return Rides
