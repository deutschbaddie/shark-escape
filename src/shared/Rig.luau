-- Rider poses and fitting. Every ride stance has a pose (Motor6D transforms)
-- and an anchor: the body point that has to land on the ride (soles on a
-- board, knees over a tube's front rim, thighs on a seat...). Rig.fit runs
-- forward kinematics over the avatar's real joints, so the pose lands on the
-- ride for any body size instead of hard-coded offsets for one default rig.
-- R15 only (R6 has no Waist joint; those riders just stand on the ride).

local Rig = {}

-- what Rig.solve needs from a joint; `inst` is the real joint to pose
export type Joint = { Name: string, Part0: any, Part1: any, C0: CFrame, C1: CFrame, inst: any? }

-- R15 joint name by the body part it moves. Avatar Joint Upgrade characters
-- (the default for new games) spawn with AnimationConstraints instead of
-- Motor6Ds, so joints are found by class and named by the part they drive.
local JOINT_OF = {
	LowerTorso = "Root", UpperTorso = "Waist", Head = "Neck",
	LeftUpperArm = "LeftShoulder", LeftLowerArm = "LeftElbow", LeftHand = "LeftWrist",
	RightUpperArm = "RightShoulder", RightLowerArm = "RightElbow", RightHand = "RightWrist",
	LeftUpperLeg = "LeftHip", LeftLowerLeg = "LeftKnee", LeftFoot = "LeftAnkle",
	RightUpperLeg = "RightHip", RightLowerLeg = "RightKnee", RightFoot = "RightAnkle",
}

function Rig.isJoint(d: Instance): boolean
	return d:IsA("Motor6D") or d:IsA("AnimationConstraint")
end

-- every animatable joint in a character, Motor6D or AnimationConstraint
-- (C0/C1 are read fresh: rig attachments move when body scale changes)
function Rig.joints(char: Instance): { Joint }
	local out = {}
	for _, d in char:GetDescendants() do
		local p0, p1, c0, c1
		if d:IsA("Motor6D") then
			p0, p1, c0, c1 = d.Part0, d.Part1, d.C0, d.C1
		elseif d:IsA("AnimationConstraint") then
			local a0, a1 = d.Attachment0, d.Attachment1
			if a0 and a1 then
				p0, p1, c0, c1 = a0.Parent, a1.Parent, a0.CFrame, a1.CFrame
			end
		end
		if p0 and p1 and p0:IsA("BasePart") and p1:IsA("BasePart") then
			table.insert(out, { Name = JOINT_OF[p1.Name] or d.Name, Part0 = p0, Part1 = p1, C0 = c0, C1 = c1, inst = d })
		end
	end
	return out
end
export type PoseFn = (number, number) -> CFrame

local A = CFrame.Angles
local function hold(): CFrame
	return CFrame.new()
end

-- t = time, s = sway (0.3..1.5 with speed). Root entries are relative motion
-- only (bob/tilt): Rig.fit supplies the offset that puts the body on the ride.
-- Signs: +X on a hip/shoulder swings the limb forward, -X on a knee bends it,
-- +X on Root leans the body back.
Rig.POSES = {
	-- standing on a board: knees bent, arms out for balance
	stand = {
		Root = function(t, s) return CFrame.new(0, math.sin(t * 6) * 0.04, 0) * A(0, 0, math.sin(t * 2) * 0.05 * s) end,
		Waist = function() return A(0.12, 0.35, 0) end,
		Neck = function() return A(-0.05, -0.3, 0) end,
		LeftShoulder = function(t) return A(0, 0, -1.15 + math.sin(t * 3) * 0.08) end,
		RightShoulder = function(t) return A(0, 0, 1.15 - math.sin(t * 3) * 0.08) end,
		LeftElbow = function() return A(0.25, 0, 0) end,
		RightElbow = function() return A(0.25, 0, 0) end,
		LeftHip = function() return A(0.45, 0, -0.06) end,
		RightHip = function() return A(-0.1, 0, 0.06) end,
		LeftKnee = function() return A(-0.65, 0, 0) end,
		RightKnee = function() return A(-0.45, 0, 0) end,
		LeftAnkle = function() return A(0.2, 0, 0) end,
		RightAnkle = function() return A(0.55, 0, 0) end,
	},
	-- lounging in a ring (tube, duck, donut, bathtub): sunk into the hole,
	-- legs up over the front rim, arms resting out over the sides
	sit = {
		Root = function(t) return CFrame.new(0, math.sin(t * 3) * 0.03, 0) * A(0.3, 0, 0) end,
		Waist = function() return A(-0.12, 0, 0) end,
		Neck = function(t) return A(-0.12, math.sin(t * 0.8) * 0.15, 0) end,
		LeftShoulder = function(t) return A(0.15, 0, -0.62 + math.sin(t * 2) * 0.04) end,
		RightShoulder = function(t) return A(0.15, 0, 0.62 - math.sin(t * 2) * 0.04) end,
		LeftElbow = function() return A(0.35, 0, 0) end,
		RightElbow = function() return A(0.35, 0, 0) end,
		LeftHip = function() return A(1.75, 0, -0.22) end,
		RightHip = function() return A(1.75, 0, 0.22) end,
		LeftKnee = function(t) return A(-0.5 + math.sin(t * 2.4) * 0.08, 0, 0) end,
		RightKnee = function(t) return A(-0.5 - math.sin(t * 2.4) * 0.08, 0, 0) end,
		LeftAnkle = function() return A(0.3, 0, 0) end,
		RightAnkle = function() return A(0.3, 0, 0) end,
	},
	-- straddling a jet ski / boat / banana / dolphin: thighs on the seat,
	-- shins down to the footboards, leaning in with hands on the bar
	straddle = {
		Root = function(_, s) return A(-0.08 * s, 0, 0) end,
		Waist = function() return A(-0.18, 0, 0) end,
		Neck = function() return A(0.22, 0, 0) end,
		LeftShoulder = function(t) return A(1.2, 0, -0.16 + math.sin(t * 9) * 0.02) end,
		RightShoulder = function(t) return A(1.2, 0, 0.16 - math.sin(t * 9) * 0.02) end,
		LeftElbow = function() return A(0.3, 0, 0) end,
		RightElbow = function() return A(0.3, 0, 0) end,
		LeftHip = function() return A(1.6, 0, -0.6) end,
		RightHip = function() return A(1.6, 0, 0.6) end,
		LeftKnee = function() return A(-1.4, 0, 0) end,
		RightKnee = function() return A(-1.4, 0, 0) end,
		LeftAnkle = function() return A(0.15, 0, 0) end,
		RightAnkle = function() return A(0.15, 0, 0) end,
	},
	-- lying on a boogie board, paddling
	prone = {
		Root = function(t) return CFrame.new(0, 0, 0) * A(-1.45, 0, math.sin(t * 3) * 0.04) end,
		Waist = function() return A(0.2, 0, 0) end,
		Neck = function() return A(0.9, 0, 0) end,
		LeftShoulder = function(t) return A(2.6 + math.sin(t * 6) * 0.5, 0, -0.2) end,
		RightShoulder = function(t) return A(2.6 - math.sin(t * 6) * 0.5, 0, 0.2) end,
		LeftElbow = hold,
		RightElbow = hold,
		LeftHip = function() return A(0, 0, -0.1) end,
		RightHip = function() return A(0, 0, 0.1) end,
		LeftKnee = function(t) return A(-0.3 - math.max(0, math.sin(t * 6)) * 0.6, 0, 0) end,
		RightKnee = function(t) return A(-0.3 - math.max(0, -math.sin(t * 6)) * 0.6, 0, 0) end,
		LeftAnkle = hold,
		RightAnkle = hold,
	},
	-- floating on a pool noodle: chest-deep, forearms on the noodle, kicking
	float = {
		Root = function(t) return CFrame.new(0, math.sin(t * 2) * 0.06, 0) * A(-0.3, 0, 0) end,
		Waist = function() return A(0.05, 0, 0) end,
		Neck = function() return A(0.3, 0, 0) end,
		LeftShoulder = function() return A(0.85, 0, -0.12) end,
		RightShoulder = function() return A(0.85, 0, 0.12) end,
		LeftElbow = function() return A(1.05, 0, 0) end,
		RightElbow = function() return A(1.05, 0, 0) end,
		LeftHip = function(t) return A(-0.15 + math.sin(t * 7) * 0.35, 0, 0) end,
		RightHip = function(t) return A(-0.15 - math.sin(t * 7) * 0.35, 0, 0) end,
		LeftKnee = function() return A(-0.3, 0, 0) end,
		RightKnee = function() return A(-0.3, 0, 0) end,
		LeftAnkle = hold,
		RightAnkle = hold,
	},
} :: { [string]: { [string]: PoseFn } }

-- which body point each stance puts on the ride's fit point (Rides.FIT)
--   sole:     lowest point of the feet        -> board deck (y only)
--   knee:     knee joints                     -> top of the tube's front rim (y, z)
--   seat:     lowest point of hips + thighs   -> seat top; hip joints -> seat z
--   chest:    lowest point of torso + legs    -> board deck (y only)
--   shoulder: shoulder joints                 -> above/behind the noodle (y, z)
Rig.ANCHOR = { stand = "sole", sit = "knee", straddle = "seat", prone = "chest", float = "shoulder" }

local FEET = { "LeftFoot", "RightFoot" }
local SEAT = { "LowerTorso", "LeftUpperLeg", "RightUpperLeg" }
local BODY = { "UpperTorso", "LowerTorso", "LeftUpperLeg", "RightUpperLeg", "LeftLowerLeg", "RightLowerLeg" }

-- CFrame of every part relative to the root part, plus each joint's pivot
function Rig.solve(joints: { Joint }, root: any, tf: { [string]: CFrame }?): ({ [any]: CFrame }, { [string]: CFrame })
	local by1 = {}
	for _, j in joints do
		by1[j.Part1] = j
	end
	local cfs: { [any]: CFrame } = { [root] = CFrame.new() }
	local pivots: { [string]: CFrame } = {}
	local function solve(p: any, depth: number): CFrame?
		local c = cfs[p]
		if c then
			return c
		end
		local j = by1[p]
		if not j or depth > 16 then
			return nil
		end
		local base = solve(j.Part0, depth + 1)
		if not base then
			return nil
		end
		local pivot = base * j.C0
		pivots[j.Name] = pivot
		local out = pivot * (tf and tf[j.Name] or CFrame.new()) * j.C1:Inverse()
		cfs[p] = out
		return out
	end
	for _, j in joints do
		solve(j.Part1, 0)
	end
	return cfs, pivots
end

-- lowest corner (Y) of the named parts
local function lowest(cfs: { [any]: CFrame }, names: { string }): number?
	local low = nil
	for p, c in cfs do
		if table.find(names, p.Name) and p.Size then
			local h = p.Size / 2
			for _, sx in { -1, 1 } do
				for _, sy in { -1, 1 } do
					for _, sz in { -1, 1 } do
						local y = (c * Vector3.new(sx * h.X, sy * h.Y, sz * h.Z)).Y
						if not low or y < low then
							low = y
						end
					end
				end
			end
		end
	end
	return low
end

local function mid(pivots: { [string]: CFrame }, a: string, b: string): Vector3?
	local pa, pb = pivots[a], pivots[b]
	if not (pa and pb) then
		return nil
	end
	return (pa.Position + pb.Position) / 2
end

-- the anchor point in root-part space (z = nil when only height matters)
local function anchor(kind: string, cfs: { [any]: CFrame }, pivots: { [string]: CFrame }): (number?, number?)
	if kind == "sole" then
		return lowest(cfs, FEET), nil
	elseif kind == "chest" then
		return lowest(cfs, BODY), nil
	elseif kind == "seat" then
		local hip = mid(pivots, "LeftHip", "RightHip")
		return lowest(cfs, SEAT), hip and hip.Z
	elseif kind == "knee" then
		local k = mid(pivots, "LeftKnee", "RightKnee")
		return k and k.Y, k and k.Z
	elseif kind == "shoulder" then
		local s = mid(pivots, "LeftShoulder", "RightShoulder")
		return s and s.Y, s and s.Z
	end
	return nil, nil
end

local function rootJoint(joints: { Joint }, root: any): Joint?
	for _, j in joints do
		if j.Part0 == root then
			return j
		end
	end
	return nil
end

-- Translation to put in front of the pose's Root transform so the stance's
-- anchor lands on `target` (root-part space). nil if the rig can't be solved.
function Rig.fit(joints: { Joint }, root: any, stance: string, target: Vector3): Vector3?
	local pose = Rig.POSES[stance]
	local rj = rootJoint(joints, root)
	if not (pose and rj) then
		return nil
	end
	local tf = {}
	for name, fn in pose do
		tf[name] = fn(0, 1)
	end
	local cfs, pivots = Rig.solve(joints, root, tf)
	local y, z = anchor(Rig.ANCHOR[stance] or "sole", cfs, pivots)
	if not y then
		return nil
	end
	local d = Vector3.new(0, target.Y - y, z and (target.Z - z) or 0)
	return rj.C0.Rotation:Inverse() * d
end

-- standing leg length (hip joint to sole), used to scale rides to the body
function Rig.legLength(joints: { Joint }, root: any): number?
	local cfs, pivots = Rig.solve(joints, root, nil)
	local hip = mid(pivots, "LeftHip", "RightHip")
	local sole = lowest(cfs, FEET)
	if not (hip and sole) then
		return nil
	end
	return hip.Y - sole
end

Rig.REF_LEG = 2.0 -- leg length the rides are modelled for (default blocky R15)

return Rig
