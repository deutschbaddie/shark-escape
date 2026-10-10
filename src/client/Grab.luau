-- The net scoop (server: Bubbles scoop() sets the character attributes
-- GrabFrom / GrabWhat / GrabAt). Everyone sees everyone's:
--   the arm  reaches out low to the side with a lean in (the hand net dips
--            to the water), sweeps up and back over the shoulder, then
--            drops back; layered over the ride pose (Water.overlays)
--   the net  a little hand net pops into the hand for the scoop: a pole
--            and a mesh hoop
--   the catch  a copy of the creature leaves the bubble as the net comes
--            up, arcs over and drops into the sack on your back (or above
--            your head, where your first catch rides), with a splash and
--            a sparkle where it lands

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = game.ReplicatedStorage.Shared
local Creatures = require(Shared.Creatures)
local Build = require(Shared.Build)
local Fx = require(script.Parent.Fx)
local Water = require(script.Parent.Water)

local Grab = {}

local DUR = 0.6
local REACH, SWEEP = 0.35, 0.6 -- (fractions of DUR: the dip ends, the sweep ends)

type Pose = { sh: number, shOut: number, el: number, wPitch: number, wYaw: number }
local DIP: Pose = { sh = 0.75, shOut = 1.0, el = 0.2, wPitch = -0.25, wYaw = -0.3 }
local UP: Pose = { sh = 2.5, shOut = 0.35, el = 0.9, wPitch = 0.12, wYaw = 0.15 }

local function outCubic(k: number): number
	return 1 - (1 - k) ^ 3
end

local function pose(u: number): Pose
	if u < REACH then
		local k = outCubic(u / REACH)
		return { sh = DIP.sh * k, shOut = DIP.shOut * k, el = DIP.el * k, wPitch = DIP.wPitch * k, wYaw = DIP.wYaw * k }
	elseif u < SWEEP then
		local k = outCubic((u - REACH) / (SWEEP - REACH))
		local f = {} :: any
		for key, a in DIP :: any do
			f[key] = a + ((UP :: any)[key] - a) * k
		end
		return f
	end
	local back = 1 - outCubic((u - SWEEP) / (1 - SWEEP))
	return { sh = UP.sh * back, shOut = UP.shOut * back, el = UP.el * back, wPitch = UP.wPitch * back, wYaw = UP.wYaw * back }
end

type Scoop = { start: number, parts: { BasePart } }
local scoops: { [Model]: Scoop } = {}

table.insert(Water.overlays, function(char)
	local sc = scoops[char]
	if not sc then
		return nil
	end
	local u = (os.clock() - sc.start) / DUR
	if u >= 1 then
		return nil
	end
	local f = pose(u)
	return {
		RightShoulder = CFrame.Angles(f.sh, 0, f.shOut),
		RightElbow = CFrame.Angles(f.el, 0, 0),
		Waist = CFrame.Angles(f.wPitch, f.wYaw, 0),
	}
end)

local function part(color: Color3, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
	p.Material = Enum.Material.SmoothPlastic
	p.Color = color
	p.Shape = shape or Enum.PartType.Block
	p.Size = Vector3.one * 0.1
	p.Parent = Workspace
	return p
end

-- the hand net: pole, rim, mesh
local POLE, HOOP = 2.0, 1.25
local function updateNets()
	local now = os.clock()
	for char, sc in scoops do
		local u = (now - sc.start) / DUR
		if u >= 1.1 or not char.Parent then
			for _, p in sc.parts do
				p:Destroy()
			end
			scoops[char] = nil
			continue
		end
		local hand = (char:FindFirstChild("RightHand") or char:FindFirstChild("Right Arm")) :: BasePart?
		if not hand then
			continue
		end
		local s = math.clamp(u / 0.1, 0, 1) * math.clamp((1.1 - u) / 0.15, 0, 1) -- (pops in, shrinks away)
		local grip = hand.CFrame * CFrame.new(0, hand.Name == "Right Arm" and -1 or -0.15, 0)
		local pole, rim, mesh = sc.parts[1], sc.parts[2], sc.parts[3]
		pole.Size = Vector3.new(POLE * s, 0.14, 0.14)
		pole.CFrame = grip * CFrame.new(0, -POLE / 2 * s, 0) * CFrame.Angles(0, 0, math.pi / 2)
		-- the hoop past the pole's end, its face square to the sweep
		local hoop = grip * CFrame.new(0, -(POLE + HOOP / 2) * s, 0) * CFrame.Angles(0, math.pi / 2, 0)
		rim.Size = Vector3.new(0.08, HOOP * s, HOOP * s)
		rim.CFrame = hoop
		mesh.Size = Vector3.new(0.1, HOOP * 0.88 * s, HOOP * 0.88 * s)
		mesh.CFrame = hoop
	end
end

-- a copy of the catch flies from the bubble into the sack (or over the head)
local function fly(char: Model, from: Vector3, what: string)
	local r, z, m, size = string.match(what, "^([^|]*)|([^|]*)|([^|]*)|([^|]*)$")
	if not r then
		return
	end
	local ok, model = pcall(Creatures.build, r, m ~= "" and m or nil, 0.6 * math.min(tonumber(size) or 1, 1.3), z)
	if not ok or not model then
		return
	end
	Build.ghost(model)
	model.Parent = Workspace
	local t0 = os.clock()
	local dur = 0.42
	Fx.splash(Vector3.new(from.X, 0.5, from.Z), 0.7)
	local conn
	conn = RunService.RenderStepped:Connect(function()
		local k = math.clamp((os.clock() - t0) / dur, 0, 1)
		local sack = char:FindFirstChild("Haul")
		local body = sack and sack:FindFirstChild("Sack") :: BasePart?
		local head = char:FindFirstChild("Head") :: BasePart?
		local to = body and (body.Position + Vector3.new(0, 1, 0)) or (head and head.Position + Vector3.new(0, 2.6, 0)) or from
		local e = outCubic(k)
		local p = from:Lerp(to, e) + Vector3.new(0, math.sin(k * math.pi) * 5, 0)
		model:PivotTo(CFrame.new(p) * CFrame.Angles(k * 5, k * 3, 0))
		if k >= 1 or not char.Parent then
			conn:Disconnect()
			model:Destroy()
			if char.Parent then
				Fx.sparkle(to, Color3.fromRGB(255, 240, 160), 10)
			end
		end
	end)
end

local function play(char: Model)
	local old = scoops[char]
	if old then
		for _, p in old.parts do
			p:Destroy()
		end
	end
	local pole = part(Color3.fromRGB(150, 105, 60), Enum.PartType.Cylinder)
	local rim = part(Color3.fromRGB(60, 70, 90), Enum.PartType.Cylinder)
	local mesh = part(Color3.fromRGB(235, 245, 255), Enum.PartType.Cylinder)
	mesh.Transparency = 0.55
	scoops[char] = { start = os.clock(), parts = { pole, rim, mesh } }
	local from = char:GetAttribute("GrabFrom")
	local what = char:GetAttribute("GrabWhat")
	if typeof(from) == "Vector3" and typeof(what) == "string" then
		-- the catch leaves the water as the net comes up
		task.delay(DUR * REACH, fly, char, from, what)
	end
end

local function watch(char: Model)
	char:GetAttributeChangedSignal("GrabAt"):Connect(function()
		play(char)
	end)
end

local function track(p: Player)
	if p.Character then
		watch(p.Character)
	end
	p.CharacterAdded:Connect(watch)
end

function Grab.start()
	for _, p in Players:GetPlayers() do
		track(p)
	end
	Players.PlayerAdded:Connect(track)
	RunService.RenderStepped:Connect(updateNets)
end

return Grab
