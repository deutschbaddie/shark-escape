-- The guide beam: a glowing arc from your feet to a target plus a bouncing
-- arrow marker. Several systems can ask for it; the highest priority wins
-- (shark danger > tutorial > ride shop).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local UI = require(script.Parent.UI)

local Guide = {}
local C = UI.C
local player = Players.LocalPlayer

local PRIORITY = { "danger", "raid", "tut", "shop", "treasure" }
local requests: { [string]: { at: Vector3, label: string? } } = {}

local folder = Instance.new("Folder")
folder.Name = "Guide"
folder.Parent = Workspace

local target = Instance.new("Part")
target.Name = "GuideTarget"
target.Anchored = true
target.CanCollide = false
target.CanQuery = false
target.CanTouch = false
target.Transparency = 1
target.Size = Vector3.new(0.2, 0.2, 0.2)
target.Parent = folder

local targetAtt = Instance.new("Attachment")
targetAtt.Parent = target

local beam = Instance.new("Beam")
beam.Attachment1 = targetAtt
beam.FaceCamera = true
beam.Width0 = 1.4
beam.Width1 = 0.6
beam.Segments = 24
beam.CurveSize0 = 6
beam.CurveSize1 = -6
beam.LightEmission = 1
beam.LightInfluence = 0
beam.Color = ColorSequence.new(C.gold)
beam.Transparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0.85),
	NumberSequenceKeypoint.new(0.25, 0.15),
	NumberSequenceKeypoint.new(1, 0.1),
})
beam.Enabled = false
beam.Parent = target

local marker = Instance.new("BillboardGui")
marker.Size = UDim2.fromOffset(160, 110)
marker.StudsOffset = Vector3.new(0, 6, 0)
marker.AlwaysOnTop = true
marker.LightInfluence = 0
marker.Enabled = false
marker.Parent = target
local markerText = UI.outlined(marker, "", { Size = UDim2.new(1, 0, 0, 34), TextColor3 = C.gold })
local markerArrow = UI.icon(marker, "Arrow", { Size = UDim2.new(1, 0, 0, 64), Position = UDim2.fromOffset(0, 40) })

local feetAtt: Attachment? = nil
local function ensureFeet(): boolean
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return false
	end
	if not feetAtt or feetAtt.Parent ~= hrp then
		local a = Instance.new("Attachment")
		a.Name = "GuideFeet"
		a.Position = Vector3.new(0, -2, 0)
		a.Parent = hrp
		feetAtt = a
		beam.Attachment0 = a
	end
	return true
end

-- owner: "tut" or "shop"; at = nil clears that owner's request
function Guide.set(owner: string, at: Vector3?, label: string?)
	requests[owner] = at and { at = at, label = label } or nil
end

function Guide.active(owner: string): boolean
	return requests[owner] ~= nil
end

RunService.Heartbeat:Connect(function()
	local req = nil
	for _, owner in PRIORITY do
		if requests[owner] then
			req = requests[owner]
			break
		end
	end
	if not req or not ensureFeet() then
		beam.Enabled = false
		marker.Enabled = false
		return
	end
	target.Position = req.at
	markerText.Text = req.label or ""
	beam.Enabled = true
	marker.Enabled = true
	markerArrow.Position = UDim2.fromOffset(0, 40 - math.abs(math.sin(os.clock() * 4)) * 12)
end)

return Guide
