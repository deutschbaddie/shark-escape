-- Tiny part-building kit for the cartoon low-poly stud look.
-- One visual family: Plastic/SmoothPlastic, bright colors, studs on tops.

local Config = require(script.Parent.Config)

local Build = {}

export type Props = { [string]: any }

local function apply(inst: Instance, props: Props?)
	if props then
		for k, v in props do
			(inst :: any)[k] = v
		end
	end
end

function Build.part(parent: Instance?, size: Vector3, cf: CFrame, color: Color3, props: Props?): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	apply(p, props)
	p.Parent = parent
	return p
end

-- Stud texture on the given faces (default: top), tinted to the part's
-- color so one white stud image works on every color. Falls back to the
-- classic stud surface if no texture is configured.
local ALL_FACES = { Enum.NormalId.Top, Enum.NormalId.Front, Enum.NormalId.Back, Enum.NormalId.Left, Enum.NormalId.Right }
Build.ALL_FACES = ALL_FACES

function Build.studs(p: BasePart, faces: { Enum.NormalId }?): BasePart
	local img = Config.Images.Studs
	if img == "" then
		p.Material = Enum.Material.Plastic
		for _, face in faces or { Enum.NormalId.Top } do
			(p :: any)[face.Name .. "Surface"] = Enum.SurfaceType.Studs
		end
		return p
	end
	p.Material = Enum.Material.SmoothPlastic
	local tile = Config.Images.StudsWorldTile
	for _, face in faces or { Enum.NormalId.Top } do
		local t = Instance.new("Texture")
		t.Name = "Studs"
		t.Texture = img
		t.Face = face
		t.StudsPerTileU = tile
		t.StudsPerTileV = tile
		t.Color3 = p.Color
		t.Parent = p
	end
	return p
end

function Build.wedge(parent: Instance?, size: Vector3, cf: CFrame, color: Color3, props: Props?): WedgePart
	local p = Instance.new("WedgePart")
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	apply(p, props)
	p.Parent = parent
	return p
end

function Build.ball(parent: Instance?, d: number, cf: CFrame, color: Color3, props: Props?): Part
	local p = Build.part(parent, Vector3.new(d, d, d), cf, color, props)
	p.Shape = Enum.PartType.Ball
	return p
end

-- vertical cylinder (Roblox cylinders run along X, so rotate onto Y)
function Build.cyl(parent: Instance?, height: number, d: number, cf: CFrame, color: Color3, props: Props?): Part
	local p = Build.part(parent, Vector3.new(height, d, d), cf * CFrame.Angles(0, 0, math.pi / 2), color, props)
	p.Shape = Enum.PartType.Cylinder
	return p
end

-- squashable ellipsoid
function Build.ell(parent: Instance?, size: Vector3, cf: CFrame, color: Color3, props: Props?): Part
	local p = Build.part(parent, size, cf, color, props)
	local m = Instance.new("SpecialMesh")
	m.MeshType = Enum.MeshType.Sphere
	m.Parent = p
	return p
end

-- ring of blocks (inner tubes, floaties, donuts)
function Build.ring(parent: Instance?, radius: number, thick: number, cf: CFrame, color: Color3, segments: number?, alt: Color3?): { BasePart }
	local n = segments or 10
	local parts = {}
	local segLen = 2 * math.pi * radius / n * 1.08
	for i = 1, n do
		local a = (i - 1) / n * 2 * math.pi
		local c = (alt and i % 2 == 0) and alt or color
		local seg = Build.part(parent, Vector3.new(segLen, thick, thick),
			cf * CFrame.Angles(0, a, 0) * CFrame.new(0, 0, -radius), c)
		table.insert(parts, seg)
	end
	return parts
end

function Build.model(name: string, parent: Instance?): Model
	local m = Instance.new("Model")
	m.Name = name
	m.Parent = parent
	return m
end

-- invisible root that a model pivots/welds around
function Build.root(model: Model, cf: CFrame?): Part
	local r = Build.part(model, Vector3.new(0.4, 0.4, 0.4), cf or CFrame.new(), Color3.new(1, 1, 1), {
		Name = "Root", Transparency = 1, CanCollide = false, CanQuery = false, CanTouch = false,
	})
	model.PrimaryPart = r
	return r
end

-- make every part visual-only
function Build.ghost(model: Instance)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.Massless = true
			d.CastShadow = false
		end
	end
end

-- unanchor and weld everything to the root so the model can ride a character
function Build.weldToRoot(model: Model)
	local root = model.PrimaryPart
	assert(root, "model needs a PrimaryPart")
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d ~= root then
			local w = Instance.new("WeldConstraint")
			w.Part0 = root
			w.Part1 = d
			w.Parent = d
			d.Anchored = false
		end
	end
	root.Anchored = false
end

function Build.recolor(model: Instance, color: Color3, material: Enum.Material?)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d.Transparency < 1 and not d:GetAttribute("KeepColor") then
			d.Color = color
			if material then
				d.Material = material
			end
		end
	end
end

return Build
