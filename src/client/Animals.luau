-- Brings the blocky creatures to life (client only):
--  * every model tagged "Creature" gets its marked parts animated (tails
--    swish, fins flap, tentacles sway, crabs scuttle, rays glide...)
--  * creatures in a tank swim around inside it on smooth wandering paths
-- Works in the world and in ViewportFrames (Index, Tank panel).

local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")

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
	leg = function(t, side, ph) return A(math.sin(t * 10 + ph) * 0.35, 0, 0) end,
	claw = function(t, side, ph) return A(0, side * math.abs(math.sin(t * 2.5)) * 0.35, 0) end,
	flipper = function(t, side, ph) return A(0, side * math.sin(t * 2.4 + ph) * 0.3, side * math.sin(t * 2.4 + ph) * 0.4) end,
	fluke = function(t, side, ph) return A(math.sin(t * 4 + ph) * 0.35, 0, 0) end,
	seg = function(t, side, ph) return A(0, math.sin(t * 4 - ph) * 0.28, 0) end,
	curl = function(t, side, ph) return A(math.sin(t * 2 + ph) * 0.3, 0, 0) end,
	lure = function(t, side, ph) return A(math.sin(t * 3) * 0.2, 0, math.cos(t * 2.3) * 0.15) end,
	head = function(t, side, ph) return A(math.sin(t * 1.5) * 0.08, math.sin(t * 0.9) * 0.25, 0) end,
	jaw = function(t, side, ph) return A(math.max(0, math.sin(t * 2)) * 0.35, 0, 0) end,
	bell = function(t, side, ph) return CFrame.new(0, math.sin(t * 3) * 0.08, 0) end,
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

----------------------------------------------------------------- tank swimming
-- each tank has an invisible "TankInterior" part; its Slots folder holds the
-- active creatures, which wander inside the interior box facing where they go
local function swimTanks(t: number)
	local map = Workspace:FindFirstChild("Map")
	if not map then
		return
	end
	for _, plot in map:GetChildren() do
		local slots = plot:FindFirstChild("Slots")
		local box = plot:FindFirstChild("TankInterior") :: BasePart?
		if slots and box then
			local half = box.Size / 2
			for i, m in slots:GetChildren() do
				if m:IsA("Model") then
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
