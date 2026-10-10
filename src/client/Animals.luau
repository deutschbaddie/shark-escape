-- Brings the blocky creatures to life (client only):
--  * every model tagged "Creature" gets its marked parts animated (tails
--    swish, fins flap, tentacles sway, crabs scuttle, rays glide...)
--  * creatures in a tank swim around inside it on smooth wandering paths
-- Works in the world and in ViewportFrames (Index, Tank panel).

local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")
local Layout = require(game.ReplicatedStorage.Shared.Layout)

local Animals = {}

type Bit = { part: BasePart, rest: CFrame, hinge: Vector3, kind: string, side: number, phase: number }
type Entry = { model: Model, bits: { Bit }, scale: number, seed: number }

local entries: { [Model]: Entry } = {}

local function scan(m: Model): Entry
	local bits = {}
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			local kind = d:GetAttribute("Anim")
			local rest = d:GetAttribute("Rest")
			if typeof(kind) == "string" and typeof(rest) == "CFrame" then
				table.insert(bits, {
					part = d, rest = rest, hinge = d:GetAttribute("Hinge") or Vector3.zero, kind = kind,
					side = d:GetAttribute("Side") or 1, phase = d:GetAttribute("Phase") or 0,
				})
			end
		end
	end
	local seed = (#m.Name * 7.31 + (m:GetAttribute("Seed") or math.random() * 100)) % 100
	return { model = m, bits = bits, scale = 1, seed = seed }
end

local A = CFrame.Angles
local MOVES: { [string]: (number, number, number) -> CFrame } = {
	tail = function(t, side, ph) return A(0, math.sin(t * 8 + ph) * 0.45, 0) end,
	fin = function(t, side, ph) return A(0, 0, side * math.sin(t * 6 + ph) * 0.5) end,
	wing = function(t, side, ph) return A(0, 0, side * math.sin(t * 2.6 + ph) * 0.55) end,
	tent = function(t, side, ph) return A(math.sin(t * 3 + ph) * 0.35, 0, math.cos(t * 2.5 + ph) * 0.25) end,
	-- legs run along X from the hip: lifting the tip is a turn about Z
	leg = function(t, side, ph) return A(0, 0, side * math.sin(t * 10 + ph) * 0.3) end,
	claw = function(t, side, ph) return A(0, side * math.abs(math.sin(t * 2.5)) * 0.22, 0) end,
	flipper = function(t, side, ph) return A(0, side * math.sin(t * 2.4 + ph) * 0.3, side * math.sin(t * 2.4 + ph) * 0.4) end,
	fluke = function(t, side, ph) return A(math.sin(t * 4 + ph) * 0.35, 0, 0) end,
	seg = function(t, side, ph) return A(0, math.sin(t * 4 - ph) * 0.28, 0) end,
	curl = function(t, side, ph) return A(math.sin(t * 2 + ph) * 0.3, 0, 0) end,
	lure = function(t, side, ph) return A(math.sin(t * 3) * 0.2, 0, math.cos(t * 2.3) * 0.15) end,
	head = function(t, side, ph) return A(math.sin(t * 1.5) * 0.08, math.sin(t * 0.9) * 0.25, 0) end,
	jaw = function(t, side, ph) return A(math.max(0, math.sin(t * 2)) * 0.35, 0, 0) end,
	bell = function(t, side, ph) return CFrame.new(0, math.sin(t * 3) * 0.08, 0) end,
	-- Mythics
	palm = function(t, side, ph) return A(math.sin(t * 1.6 + ph) * 0.1, 0, math.cos(t * 1.3 + ph) * 0.12) end,
	lid = function(t, side, ph) return A(math.max(0, math.sin(t * 1.1)) * 0.7, 0, 0) end, -- (peeks at the gold)
	gill = function(t, side, ph) return A(0, 0, side * math.sin(t * 5 + ph) * 0.22) end,
	stalk = function(t, side, ph) return A(math.sin(t * 2 + ph) * 0.15, 0, math.cos(t * 1.7 + ph) * 0.2) end,
	punch = function(t, side, ph)
		local k = (t * 0.45 + ph) % 1 -- a snap every ~2 s
		return A(k < 0.12 and math.sin(k / 0.12 * math.pi) * 1.1 or 0, 0, 0)
	end,
	neck = function(t, side, ph) return A(math.sin(t * 1.8 + ph) * 0.12, math.sin(t * 1.2 + ph) * 0.16, 0) end,
	orbit = function(t, side, ph) return A(0, t * 0.9 * side, 0) end,
	flap = function(t, side, ph) return A(0, 0, side * math.sin(t * 3 + ph) * 0.6) end,
	crest = function(t, side, ph) return A(math.sin(t * 3 + ph) * 0.12, 0, 0) end,
	gallop = function(t, side, ph) return A(math.sin(t * 4 + ph) * 0.55, 0, 0) end,
	mane = function(t, side, ph) return A(0, math.sin(t * 3 - ph) * 0.18, 0) end,
}

local function animate(e: Entry, t: number)
	local root = e.model.PrimaryPart
	if not root or not root.Anchored then
		return -- carried creatures are welded; leave them be
	end
	local sc = e.model:GetScale()
	local rootCF = root.CFrame
	local tt = t + e.seed
	for _, b in e.bits do
		local move = MOVES[b.kind]
		if move and b.part.Parent then
			local hinge = b.hinge * sc
			local rest = b.rest.Rotation + b.rest.Position * sc
			b.part.CFrame = rootCF * CFrame.new(hinge) * move(tt, b.side, b.phase) * CFrame.new(-hinge) * rest
		end
	end
end

----------------------------------------------------------------- auras
-- Mythics sparkle and glow; deep-biome creatures carry a little of their
-- biome with them (Creatures.luau sets the model's Aura attribute)
local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"
local MYTHIC = Color3.fromRGB(255, 60, 110)
local AURAS: { [string]: { [string]: any } } = {
	mythic = { Color = ColorSequence.new(MYTHIC, Color3.fromRGB(255, 220, 120)), Rate = 7, Size = NumberSequence.new(0.55, 0),
		Lifetime = NumberRange.new(0.9, 1.5), Speed = NumberRange.new(1, 2.5), Acceleration = Vector3.new(0, 0.8, 0) },
	snow = { Color = ColorSequence.new(Color3.fromRGB(240, 250, 255)), Rate = 3, Size = NumberSequence.new(0.22, 0.1),
		Lifetime = NumberRange.new(1.4, 2), Speed = NumberRange.new(0.4, 1), Acceleration = Vector3.new(0, -0.8, 0) },
	embers = { Color = ColorSequence.new(Color3.fromRGB(255, 200, 80), Color3.fromRGB(255, 80, 20)), Rate = 4, Size = NumberSequence.new(0.25, 0),
		Lifetime = NumberRange.new(0.8, 1.3), Speed = NumberRange.new(0.5, 1.2), Acceleration = Vector3.new(0, 2.5, 0) },
	fizz = { Color = ColorSequence.new(Color3.fromRGB(230, 250, 255)), Rate = 4, Size = NumberSequence.new(0.18, 0.28),
		Lifetime = NumberRange.new(0.8, 1.2), Speed = NumberRange.new(0.3, 0.8), Acceleration = Vector3.new(0, 3, 0) },
	sugar = { Color = ColorSequence.new(Color3.fromRGB(255, 140, 230), Color3.fromRGB(140, 255, 240)), Rate = 4, Size = NumberSequence.new(0.3, 0),
		Lifetime = NumberRange.new(0.8, 1.3), Speed = NumberRange.new(0.5, 1.5), Acceleration = Vector3.zero },
}

local function addAura(m: Model)
	local def = AURAS[m:GetAttribute("Aura") :: any]
	local root = m.PrimaryPart
	if not def or not root or root:FindFirstChild("Aura") or not m:IsDescendantOf(Workspace) then
		return -- (viewports don't draw particles)
	end
	local e = Instance.new("ParticleEmitter")
	e.Name = "Aura"
	e.Texture = SPARKLE
	e.LightEmission = 1
	e.SpreadAngle = Vector2.new(180, 180)
	e.Transparency = NumberSequence.new(0.2, 1)
	for k, v in def do
		(e :: any)[k] = v
	end
	e.Parent = root
	if m:GetAttribute("Aura") == "mythic" then
		local light = Instance.new("PointLight")
		light.Color = MYTHIC
		light.Range = 9
		light.Brightness = 1.4
		light.Parent = root
	end
end

----------------------------------------------------------------- tank swimming
-- each tank has an invisible "TankInterior" part; its Slots folder holds the
-- active creatures, which wander inside the interior box facing where they go
local function swimTanks(t: number)
	for _, plot in (function()
		local all = {}
		for _, map in Layout.worldFolders() do
			for _, p in map:GetChildren() do
				table.insert(all, p)
			end
		end
		return all
	end)() do
		local slots = plot:FindFirstChild("Slots")
		local box = plot:FindFirstChild("TankInterior") :: BasePart?
		if slots and box then
			local half = box.Size / 2
			for i, m in slots:GetChildren() do
				if m:IsA("Model") and not m:GetAttribute("Dead") then -- dead ones lie still on the floor
					local seed = (m:GetAttribute("Seed") or i) :: number
					local function at(time: number): Vector3
						return Vector3.new(
							math.sin(time * (0.23 + (seed % 7) * 0.02) + seed) * (half.X - 1.4),
							math.sin(time * (0.31 + (seed % 5) * 0.03) + seed * 1.7) * (half.Y - 1.1),
							math.sin(time * (0.19 + (seed % 3) * 0.04) + seed * 2.3) * (half.Z - 1.1)
						)
					end
					local p0, p1 = at(t), at(t + 0.15)
					local dir = p1 - p0
					local look = dir.Magnitude > 0.01 and dir.Unit or Vector3.new(0, 0, -1)
					local worldPos = box.CFrame:PointToWorldSpace(p0)
					local worldLook = box.CFrame:VectorToWorldSpace(Vector3.new(look.X, look.Y * 0.4, look.Z))
					m:PivotTo(CFrame.lookAt(worldPos, worldPos + worldLook))
				end
			end
		end
	end
end

function Animals.start()
	local function add(m: Instance)
		if m:IsA("Model") and not entries[m] then
			entries[m] = scan(m)
			addAura(m :: Model)
		end
	end
	for _, m in CollectionService:GetTagged("Creature") do
		add(m)
	end
	CollectionService:GetInstanceAddedSignal("Creature"):Connect(function(m)
		task.defer(add, m) -- parts are all there by the next frame
	end)
	CollectionService:GetInstanceRemovedSignal("Creature"):Connect(function(m)
		entries[m :: Model] = nil
	end)
	RunService.RenderStepped:Connect(function()
		local t = os.clock()
		swimTanks(t)
		local cam = Workspace.CurrentCamera.CFrame.Position
		for m, e in entries do
			if not m.Parent then
				entries[m] = nil
				continue
			end
			if m:GetAttribute("Dead") then
				continue
			end
			local root = m.PrimaryPart
			-- world creatures only animate near the camera; viewport ones always
			local inWorld = m:IsDescendantOf(Workspace)
			if root and (not inWorld or (root.Position - cam).Magnitude < 150) then
				animate(e, t)
			end
		end
	end)
end

return Animals
