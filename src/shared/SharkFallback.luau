-- Part-built stand-in used until the rigged .glb sharks are imported into
-- ReplicatedStorage/Assets/Sharks. Same names as the real rig's key bones
-- (Head, Jaw, Tail) so the animator can drive both.

local Build = require(script.Parent.Build)

local SharkFallback = {}
local C = Color3.fromRGB

local COLORS = {
	Baby = { C(108, 196, 245), C(255, 246, 227) },
	Hammerhead = { C(142, 154, 116), C(241, 238, 226) },
	Tiger = { C(148, 137, 108), C(245, 239, 221) },
	GreatWhite = { C(106, 129, 153), C(246, 247, 249) },
	Mecha = { C(155, 166, 179), C(221, 227, 234) },
	Megalodon = { C(61, 73, 88), C(200, 206, 215) },
}

function SharkFallback.build(variant: string, length: number): Model
	local L = length
	local back, belly = table.unpack(COLORS[variant] or COLORS.GreatWhite)
	local m = Build.model("Shark_" .. variant)
	local body = Build.ell(m, Vector3.new(L * 0.26, L * 0.28, L * 0.62), CFrame.new(0, 0, -L * 0.05), back, { Name = "Body" })
	m.PrimaryPart = body
	Build.ell(m, Vector3.new(L * 0.22, L * 0.12, L * 0.5), CFrame.new(0, -L * 0.08, -L * 0.07), belly)
	local head = Build.ell(m, Vector3.new(L * 0.22, L * 0.2, L * 0.3), CFrame.new(0, L * 0.01, -L * 0.33), back, { Name = "Head" })
	local jaw = Build.ell(m, Vector3.new(L * 0.18, L * 0.07, L * 0.22), CFrame.new(0, -L * 0.07, -L * 0.33), belly, { Name = "Jaw" })
	Build.wedge(m, Vector3.new(L * 0.04, L * 0.22, L * 0.16), CFrame.new(0, L * 0.22, -L * 0.02) * CFrame.Angles(0, math.pi, 0), back)
	local tail = Build.wedge(m, Vector3.new(L * 0.04, L * 0.36, L * 0.16), CFrame.new(0, L * 0.04, L * 0.38), back, { Name = "Tail" })
	for _, side in { -1, 1 } do
		Build.wedge(m, Vector3.new(L * 0.2, L * 0.02, L * 0.14), CFrame.new(side * L * 0.16, -L * 0.08, -L * 0.1) * CFrame.Angles(0, math.pi, side * 0.4), back)
		Build.ball(m, L * 0.045, CFrame.new(side * L * 0.085, L * 0.06, -L * 0.4), C(255, 255, 255))
	end
	-- rest offsets so the animator can swing tail/jaw around the body
	for _, p in { head, jaw, tail } do
		p:SetAttribute("Rest", body.CFrame:ToObjectSpace(p.CFrame))
	end
	Build.ghost(m)
	m:SetAttribute("Fallback", true)
	return m
end

return SharkFallback
