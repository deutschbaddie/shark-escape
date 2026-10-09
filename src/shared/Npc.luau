-- Classic R6 shopkeepers: a real R6 rig (Humanoid + the six standard
-- Motor6Ds) so it reads as a Roblox character, dressed with simple part
-- hats and gear. Only the root is anchored; the client animates the joints
-- (src/client/Npcs.luau) through Motor6D.Transform.

local CollectionService = game:GetService("CollectionService")

local Npc = {}

local function C(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

export type Look = {
	name: string,
	skin: Color3,
	shirt: Color3,
	pants: Color3,
	hat: string?, -- "cap" | "explorer" | "fisher" | "visor"
	hatColor: Color3?,
	glasses: boolean?,
	apron: Color3?,
	line: string?, -- what they say when you walk up
}

-- the shops' keepers, by building kind
Npc.Looks = {
	Shop = { name = "Sunny", skin = C(255, 204, 153), shirt = C(255, 70, 170), pants = C(255, 255, 255), hat = "cap", hatColor = C(255, 70, 170),
		line = "Best deals on the beach!" },
	Index = { name = "Professor Reef", skin = C(204, 142, 105), shirt = C(255, 150, 30), pants = C(110, 80, 50), hat = "explorer", hatColor = C(220, 190, 130),
		glasses = true, line = "Catch every creature!" },
	Sell = { name = "Old Hank", skin = C(234, 184, 146), shirt = C(70, 210, 90), pants = C(60, 70, 110), hat = "fisher", hatColor = C(255, 205, 40),
		apron = C(240, 240, 240), line = "Got fish to sell?" },
	Rides = { name = "Kai", skin = C(160, 110, 80), shirt = C(40, 170, 255), pants = C(255, 255, 255), hat = "visor", hatColor = C(255, 196, 30),
		glasses = true, line = "Faster rides in stock!" },
} :: { [string]: Look }

local function part(parent: Instance, name: string, size: Vector3, color: Color3): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.Parent = parent
	return p
end

local function motor(name: string, p0: BasePart, p1: BasePart, c0: CFrame, c1: CFrame)
	local m = Instance.new("Motor6D")
	m.Name = name
	m.Part0 = p0
	m.Part1 = p1
	m.C0 = c0
	m.C1 = c1
	m.Parent = p0
end

-- a gear piece stuck to a limb (welded, so it follows the animation)
local function gear(model: Model, to: BasePart, name: string, size: Vector3, offset: CFrame, color: Color3, shape: Enum.PartType?): Part
	local p = part(model, name, size, color)
	if shape then
		p.Shape = shape
	end
	p.CFrame = to.CFrame * offset
	local w = Instance.new("WeldConstraint")
	w.Part0 = to
	w.Part1 = p
	w.Parent = p
	return p
end

-- standard R6 joint frames
local R = CFrame.new(0, 0, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0)
local RS0, RS1 = CFrame.new(1, 0.5, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0), CFrame.new(-0.5, 0.5, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0)
local LS0, LS1 = CFrame.new(-1, 0.5, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0), CFrame.new(0.5, 0.5, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0)
local RH0, RH1 = CFrame.new(1, -1, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0), CFrame.new(0.5, 1, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0)
local LH0, LH1 = CFrame.new(-1, -1, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0), CFrame.new(-0.5, 1, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0)

-- feet = the ground point it stands on; it faces cf's look direction
function Npc.build(parent: Instance, kind: string, feet: CFrame): Model?
	local look = Npc.Looks[kind]
	if not look then
		return nil
	end
	local m = Instance.new("Model")
	m.Name = "NPC_" .. kind

	local root = part(m, "HumanoidRootPart", Vector3.new(2, 2, 1), look.shirt)
	root.Transparency = 1
	root.Anchored = true
	root.CFrame = feet * CFrame.new(0, 3, 0)
	local torso = part(m, "Torso", Vector3.new(2, 2, 1), look.shirt)
	local head = part(m, "Head", Vector3.new(2, 1, 1), look.skin)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Head
	mesh.Scale = Vector3.new(1.25, 1.25, 1.25)
	mesh.Parent = head
	local face = Instance.new("Decal")
	face.Name = "face"
	face.Texture = "rbxasset://textures/face.png"
	face.Face = Enum.NormalId.Front
	face.Parent = head
	local ra = part(m, "Right Arm", Vector3.new(1, 2, 1), look.skin)
	local la = part(m, "Left Arm", Vector3.new(1, 2, 1), look.skin)
	local rl = part(m, "Right Leg", Vector3.new(1, 2, 1), look.pants)
	local ll = part(m, "Left Leg", Vector3.new(1, 2, 1), look.pants)

	motor("RootJoint", root, torso, R, R)
	motor("Neck", torso, head, CFrame.new(0, 1, 0) * R, CFrame.new(0, -0.5, 0) * R)
	motor("Right Shoulder", torso, ra, RS0, RS1)
	motor("Left Shoulder", torso, la, LS0, LS1)
	motor("Right Hip", torso, rl, RH0, RH1)
	motor("Left Hip", torso, ll, LH0, LH1)
	-- place every limb where its joint puts it (before the welds below)
	torso.CFrame = root.CFrame
	head.CFrame = torso.CFrame * CFrame.new(0, 1.5, 0)
	ra.CFrame = torso.CFrame * CFrame.new(1.5, 0, 0)
	la.CFrame = torso.CFrame * CFrame.new(-1.5, 0, 0)
	rl.CFrame = torso.CFrame * CFrame.new(0.5, -2, 0)
	ll.CFrame = torso.CFrame * CFrame.new(-0.5, -2, 0)

	-- short sleeves: shirt-colored tops on the arms
	for _, arm in { ra, la } do
		gear(m, arm, "Sleeve", Vector3.new(1.05, 0.8, 1.05), CFrame.new(0, 0.6, 0), look.shirt)
	end
	if look.apron then
		gear(m, torso, "Apron", Vector3.new(1.5, 1.7, 0.1), CFrame.new(0, -0.15, -0.53), look.apron)
	end
	if look.glasses then
		gear(m, head, "Glasses", Vector3.new(1.3, 0.28, 0.12), CFrame.new(0, 0.12, -0.62), C(25, 25, 32))
	end
	local hc = look.hatColor or C(255, 255, 255)
	if look.hat == "cap" then
		gear(m, head, "Cap", Vector3.new(1.3, 0.45, 1.3), CFrame.new(0, 0.62, 0), hc)
		gear(m, head, "Brim", Vector3.new(1.2, 0.12, 0.7), CFrame.new(0, 0.42, -0.85), hc)
	elseif look.hat == "explorer" then
		gear(m, head, "HatTop", Vector3.new(0.6, 1.25, 1.25), CFrame.new(0, 0.75, 0) * CFrame.Angles(0, 0, math.rad(90)), hc, Enum.PartType.Cylinder)
		gear(m, head, "HatBrim", Vector3.new(0.12, 2, 2), CFrame.new(0, 0.5, 0) * CFrame.Angles(0, 0, math.rad(90)), hc, Enum.PartType.Cylinder)
		gear(m, head, "HatBand", Vector3.new(0.18, 1.28, 1.28), CFrame.new(0, 0.6, 0) * CFrame.Angles(0, 0, math.rad(90)), C(110, 80, 50), Enum.PartType.Cylinder)
	elseif look.hat == "fisher" then
		gear(m, head, "HatTop", Vector3.new(0.5, 1.3, 1.3), CFrame.new(0, 0.72, 0) * CFrame.Angles(0, 0, math.rad(90)), hc, Enum.PartType.Cylinder)
		gear(m, head, "HatBrim", Vector3.new(0.12, 1.8, 1.8), CFrame.new(0, 0.5, 0.05) * CFrame.Angles(math.rad(-8), 0, math.rad(90)), hc, Enum.PartType.Cylinder)
	elseif look.hat == "visor" then
		gear(m, head, "Visor", Vector3.new(1.32, 0.2, 1.32), CFrame.new(0, 0.48, 0), hc)
		gear(m, head, "VisorBrim", Vector3.new(1.2, 0.1, 0.75), CFrame.new(0, 0.44, -0.9), hc)
	end

	-- solid body (players bump into it instead of walking through); the hats
	-- and gear stay non-colliding
	for _, p in { root, torso, rl, ll } do
		p.CanCollide = true
	end

	local hum = Instance.new("Humanoid")
	hum.RigType = Enum.HumanoidRigType.R6
	hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	hum.BreakJointsOnDeath = false
	hum.Parent = m
	m.PrimaryPart = root
	m:SetAttribute("Kind", kind)
	m:SetAttribute("Line", look.line or "")
	m.Parent = parent
	CollectionService:AddTag(m, "ShopNpc")
	return m
end

return Npc
