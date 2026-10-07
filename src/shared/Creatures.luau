-- Hand-built cartoon sea creatures. Each is ~2.4 studs long at scale 1,
-- faces -Z, and pivots at its own center.

local CollectionService = game:GetService("CollectionService")

local Config = require(script.Parent.Config)
local Build = require(script.Parent.Build)

local Creatures = {}

local WHITE = Color3.fromRGB(255, 255, 255)
local INK = Color3.fromRGB(27, 29, 63)

local function eyes(m: Model, s: number, at: Vector3, spread: number, size: number?)
	local d = (size or 0.42) * s
	for _, side in { -1, 1 } do
		local base = CFrame.new(at.X * s + side * spread * s, at.Y * s, at.Z * s)
		Build.ball(m, d, base, WHITE):SetAttribute("KeepColor", true)
		local pupil = Build.ball(m, d * 0.55, base * CFrame.new(side * d * 0.18, 0, -d * 0.3), INK)
		pupil:SetAttribute("KeepColor", true)
	end
end

local builders: { [string]: (Model, number) -> () } = {}

builders.Clownfish = function(m, s)
	local orange = Color3.fromRGB(255, 128, 32)
	Build.ell(m, Vector3.new(1.0, 1.25, 2.1) * s, CFrame.new(), orange)
	for _, z in { -0.55, 0.2 } do
		local stripe = Build.ell(m, Vector3.new(1.06, 1.18, 0.28) * s, CFrame.new(0, 0, z * s), WHITE)
		stripe:SetAttribute("KeepColor", true)
	end
	Build.wedge(m, Vector3.new(0.2, 0.9, 0.7) * s, CFrame.new(0, 0, 1.25 * s) * CFrame.Angles(0, math.pi, 0), orange)
	Build.wedge(m, Vector3.new(0.15, 0.5, 0.8) * s, CFrame.new(0, 0.7 * s, 0.1 * s) * CFrame.Angles(0, math.pi, 0), orange)
	eyes(m, s, Vector3.new(0, 0.2, -0.7), 0.36)
end

builders.Pufferfish = function(m, s)
	local yellow = Color3.fromRGB(255, 214, 64)
	Build.ball(m, 1.9 * s, CFrame.new(), yellow)
	local belly = Build.ell(m, Vector3.new(1.5, 1.0, 1.5) * s, CFrame.new(0, -0.45 * s, 0), Color3.fromRGB(255, 246, 214))
	belly:SetAttribute("KeepColor", true)
	local rng = Random.new(7)
	for _ = 1, 14 do
		local dir = rng:NextUnitVector()
		local spike = Build.wedge(m, Vector3.new(0.12, 0.42, 0.22) * s, CFrame.lookAt(dir * 0.95 * s, dir * 2 * s) * CFrame.Angles(-math.pi / 2, 0, 0), Color3.fromRGB(230, 170, 40))
		spike:SetAttribute("KeepColor", true)
	end
	Build.wedge(m, Vector3.new(0.15, 0.6, 0.5) * s, CFrame.new(0, 0, 1.05 * s) * CFrame.Angles(0, math.pi, 0), yellow)
	eyes(m, s, Vector3.new(0, 0.3, -0.8), 0.42, 0.5)
end

builders.Octopus = function(m, s)
	local purple = Color3.fromRGB(176, 90, 230)
	Build.ell(m, Vector3.new(1.7, 1.9, 1.7) * s, CFrame.new(0, 0.5 * s, 0), purple)
	for i = 1, 8 do
		local a = (i - 1) / 8 * math.pi * 2
		local out = CFrame.Angles(0, a, 0)
		Build.ell(m, Vector3.new(0.38, 0.38, 1.2) * s, out * CFrame.new(0, -0.45 * s, -0.75 * s) * CFrame.Angles(0.5, 0, 0), purple)
		Build.ball(m, 0.36 * s, out * CFrame.new(0, -0.75 * s, -1.3 * s), purple)
	end
	eyes(m, s, Vector3.new(0, 0.55, -0.72), 0.4, 0.5)
end

builders["Sea Turtle"] = function(m, s)
	local shell = Color3.fromRGB(64, 160, 92)
	local skin = Color3.fromRGB(150, 210, 120)
	Build.ell(m, Vector3.new(1.9, 0.9, 2.2) * s, CFrame.new(0, 0.15 * s, 0), shell)
	local plate = Build.ell(m, Vector3.new(1.2, 0.95, 1.4) * s, CFrame.new(0, 0.24 * s, 0), Color3.fromRGB(96, 196, 120))
	plate:SetAttribute("KeepColor", true)
	local belly = Build.ell(m, Vector3.new(1.8, 0.4, 2.1) * s, CFrame.new(0, -0.15 * s, 0), Color3.fromRGB(240, 226, 160))
	belly:SetAttribute("KeepColor", true)
	Build.ball(m, 0.8 * s, CFrame.new(0, 0.1 * s, -1.25 * s), skin)
	for _, side in { -1, 1 } do
		Build.ell(m, Vector3.new(1.1, 0.16, 0.5) * s, CFrame.new(side * 1.1 * s, 0, -0.5 * s) * CFrame.Angles(0, side * 0.5, side * -0.2), skin)
		Build.ell(m, Vector3.new(0.6, 0.14, 0.35) * s, CFrame.new(side * 0.8 * s, -0.05 * s, 0.85 * s) * CFrame.Angles(0, side * -0.5, 0), skin)
	end
	eyes(m, s, Vector3.new(0, 0.28, -1.5), 0.24, 0.26)
end

builders.Narwhal = function(m, s)
	local blue = Color3.fromRGB(150, 196, 255)
	Build.ell(m, Vector3.new(1.1, 1.0, 2.4) * s, CFrame.new(), blue)
	local belly = Build.ell(m, Vector3.new(0.9, 0.6, 2.0) * s, CFrame.new(0, -0.25 * s, 0), Color3.fromRGB(240, 248, 255))
	belly:SetAttribute("KeepColor", true)
	-- spiral tusk: stacked shrinking cylinders
	for i = 0, 4 do
		local t = i / 4
		local tusk = Build.part(m, Vector3.new(0.4 * s, (0.22 - t * 0.14) * s, (0.22 - t * 0.14) * s),
			CFrame.new(0, 0.2 * s, (-1.3 - i * 0.36) * s) * CFrame.Angles(0, math.pi / 2, 0) * CFrame.Angles(i * 0.6, 0, 0),
			Color3.fromRGB(255, 244, 214), { Shape = Enum.PartType.Cylinder })
		tusk:SetAttribute("KeepColor", true)
	end
	for _, side in { -1, 1 } do
		Build.wedge(m, Vector3.new(0.12, 0.45, 0.8) * s, CFrame.new(side * 0.4 * s, 0, 1.45 * s) * CFrame.Angles(0, math.pi, side * 1.2), blue)
	end
	eyes(m, s, Vector3.new(0, 0.12, -0.9), 0.42, 0.3)
end

-- species, rarity data -> Model (anchored, visual only)
function Creatures.build(rarityId: string, mutationId: string?, scale: number?): Model
	local rarity = Config.rarity(rarityId)
	local s = scale or 1
	local m = Build.model(rarity.species)
	Build.root(m)
	builders[rarity.species](m, s)
	m:SetAttribute("Rarity", rarityId)
	if mutationId == "Gold" then
		Build.recolor(m, Color3.fromRGB(255, 200, 50), Enum.Material.Foil)
	elseif mutationId == "Diamond" then
		Build.recolor(m, Color3.fromRGB(160, 236, 255), Enum.Material.Glass)
	elseif mutationId == "Rainbow" then
		m:SetAttribute("Rainbow", true) -- clients cycle the hue
		CollectionService:AddTag(m, "Rainbow")
	end
	if mutationId then
		m:SetAttribute("Mutation", mutationId)
	end
	Build.ghost(m)
	m.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	return m
end

function Creatures.label(rarityId: string, mutationId: string?): string
	local r = Config.rarity(rarityId)
	return (mutationId and (mutationId .. " ") or "") .. r.species
end

return Creatures
