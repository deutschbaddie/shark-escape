-- The little floating tag over a creature (Steal-a-Brainrot style):
--   Octopus          (white)
--   Gold · Rare      (rarity color)
--   $120/s           (green, optional)
-- Sized in studs so it shrinks with distance; hidden when far away.

local Config = require(script.Parent.Config)

local NameTag = {}

local INK = Color3.fromRGB(22, 22, 34)

local function short(n: number): string
	local units = { "", "K", "M", "B", "T", "Qa" }
	local i = 1
	while n >= 1000 and i < #units do
		n /= 1000
		i += 1
	end
	return (i == 1 and tostring(math.floor(n)) or (string.format("%.1f", n):gsub("%.0$", ""))) .. units[i]
end

local function line(parent: Instance, text: string, color: Color3, order: number, h: number)
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Size = UDim2.fromScale(1, h)
	t.LayoutOrder = order
	t.Font = Enum.Font.FredokaOne
	t.TextScaled = true
	t.Text = text
	t.TextColor3 = color
	t.Parent = parent
	local s = Instance.new("UIStroke")
	s.Color = INK
	s.Thickness = 2
	s.Parent = t
	return t
end

-- c = { r, z, m }; perSecond = income to show (nil = no money line)
function NameTag.attach(part: BasePart, c: { r: string, z: string?, m: string? }, perSecond: number?, opts: { height: number?, maxDist: number?, width: number? }?): BillboardGui
	local o = opts or {}
	local rarity = Config.rarity(c.r)
	local lines = perSecond and 3 or 2
	local w = o.width or 3.6
	local bb = Instance.new("BillboardGui")
	bb.Name = "NameTag"
	bb.Size = UDim2.fromScale(w, w * 0.2 * lines)
	bb.StudsOffsetWorldSpace = Vector3.new(0, o.height or 1.6, 0)
	bb.MaxDistance = o.maxDist or 60
	bb.LightInfluence = 0
	bb.Parent = part
	local list = Instance.new("UIListLayout")
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.VerticalAlignment = Enum.VerticalAlignment.Bottom
	list.Parent = bb
	local each = 1 / lines
	line(bb, Config.species(c.z, c.r).name, Color3.new(1, 1, 1), 1, each * 1.08)
	line(bb, (c.m and (c.m .. " · ") or "") .. rarity.id, c.m and (Config.mutation(c.m) :: any).color or rarity.color, 2, each * 0.86)
	if perSecond then
		line(bb, "$" .. short(perSecond) .. "/s", Color3.fromRGB(130, 255, 90), 3, each * 1.0)
	end
	return bb
end

return NameTag
