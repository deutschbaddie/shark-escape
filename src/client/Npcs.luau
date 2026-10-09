-- Brings the R6 shopkeepers (src/shared/Npc.luau) to life on this client:
-- breathing, arms resting on the counter, the head follows you when you're
-- close, and they wave and say their line when you walk up.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Npc = require(game:GetService("ReplicatedStorage").Shared.Npc)

local Npcs = {}
local player = Players.LocalPlayer

local LOOK_RANGE = 40 -- head follows you inside this
local GREET_RANGE = 22 -- wave + line when you come this close...
local RESET_RANGE = 34 -- ...after having been at least this far away
local WAVE_TIME = 1.8
local MAX_YAW = math.rad(70)

type Keeper = {
	model: Model,
	torso: BasePart,
	joints: { [string]: Motor6D },
	phase: number,
	yaw: number,
	waveUntil: number,
	away: boolean,
	bubble: BillboardGui?,
}

local keepers: { [Model]: Keeper } = {}

local function joints(model: Model): { [string]: Motor6D }
	local out = {}
	for _, d in model:GetDescendants() do
		if d:IsA("Motor6D") then
			out[d.Name] = d
		end
	end
	return out
end

-- their line, as outlined text over the head (no box), with the name above
local function say(k: Keeper)
	local head = k.model:FindFirstChild("Head") :: BasePart?
	local line = k.model:GetAttribute("Line")
	if not head or typeof(line) ~= "string" or line == "" then
		return
	end
	if k.bubble then
		k.bubble:Destroy()
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = "Say"
	gui.Adornee = head
	gui.Size = UDim2.fromOffset(260, 60)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 3.2, 0)
	gui.LightInfluence = 0
	gui.MaxDistance = 80
	local function text(t: string, y: number, h: number, color: Color3)
		local l = Instance.new("TextLabel")
		l.BackgroundTransparency = 1
		l.Size = UDim2.new(1, 0, 0, h)
		l.Position = UDim2.fromOffset(0, y)
		l.Font = Enum.Font.FredokaOne
		l.TextScaled = true
		l.TextColor3 = color
		l.Text = t
		l.Parent = gui
		local s = Instance.new("UIStroke")
		s.Thickness = 2.5
		s.Color = Color3.fromRGB(22, 22, 34)
		s.Parent = l
		return l
	end
	local kind = k.model:GetAttribute("Kind")
	local look = typeof(kind) == "string" and Npc.Looks[kind] or nil
	text(look and look.name or "", 0, 20, look and look.shirt or Color3.new(1, 1, 1))
	text(line, 22, 32, Color3.new(1, 1, 1))
	local scale = Instance.new("UIScale")
	scale.Scale = 0.4
	scale.Parent = gui
	gui.Parent = player:WaitForChild("PlayerGui")
	TweenService:Create(scale, TweenInfo.new(0.25, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	k.bubble = gui
	task.delay(3.2, function()
		if k.bubble == gui then
			k.bubble = nil
		end
		TweenService:Create(scale, TweenInfo.new(0.15), { Scale = 0 }):Play()
		task.wait(0.16)
		gui:Destroy()
	end)
end

local function add(model: Instance)
	if not model:IsA("Model") or keepers[model] then
		return
	end
	local torso = model:WaitForChild("Torso", 10) :: BasePart?
	if not torso then
		return
	end
	keepers[model] = {
		model = model,
		torso = torso,
		joints = joints(model),
		phase = math.random() * 10,
		yaw = 0,
		waveUntil = 0,
		away = true,
	}
end

local function remove(model: Instance)
	local k = keepers[model :: Model]
	if k and k.bubble then
		k.bubble:Destroy()
	end
	keepers[model :: Model] = nil
end

local function step(dt: number)
	local now = os.clock()
	local char = player.Character
	local me = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	for model, k in keepers do
		if not model.Parent then
			continue
		end
		local j = k.joints
		local t = now + k.phase
		local dist = me and (me.Position - k.torso.Position).Magnitude or math.huge
		if dist > 160 then
			continue -- too far to see: skip the work
		end

		-- greet once each time you walk up
		if dist > RESET_RANGE then
			k.away = true
		elseif dist < GREET_RANGE and k.away then
			k.away = false
			k.waveUntil = now + WAVE_TIME
			say(k)
		end

		-- head: follow you (yaw only), else drift around a little
		local goal = math.sin(t * 0.35) * 0.35
		if me and dist < LOOK_RANGE then
			local rel = k.torso.CFrame:PointToObjectSpace(me.Position)
			goal = math.clamp(math.atan2(-rel.X, -rel.Z), -MAX_YAW, MAX_YAW)
		end
		k.yaw += (goal - k.yaw) * math.min(dt * 6, 1)
		local breathe = math.sin(t * 1.8)
		if j.Neck then
			j.Neck.Transform = CFrame.Angles(0.04 * breathe, 0, k.yaw)
		end
		if j.RootJoint then
			j.RootJoint.Transform = CFrame.new(0, 0, 0.04 * breathe)
		end

		-- arms: resting forward on the counter, a slow sway; the right one waves
		local waving = now < k.waveUntil
		if j["Right Shoulder"] then
			j["Right Shoulder"].Transform = waving and CFrame.Angles(-2.7 + 0.4 * math.sin(now * 12), 0, 0.2)
				or CFrame.Angles(0, 0, 0.32 + 0.05 * breathe)
		end
		if j["Left Shoulder"] then
			j["Left Shoulder"].Transform = CFrame.Angles(0, 0, -0.32 - 0.05 * breathe)
		end
		if j["Right Hip"] then
			j["Right Hip"].Transform = CFrame.new()
		end
		if j["Left Hip"] then
			j["Left Hip"].Transform = CFrame.new()
		end
	end
end

function Npcs.start()
	for _, m in CollectionService:GetTagged("ShopNpc") do
		task.spawn(add, m)
	end
	CollectionService:GetInstanceAddedSignal("ShopNpc"):Connect(add)
	CollectionService:GetInstanceRemovedSignal("ShopNpc"):Connect(remove)
	RunService.PreSimulation:Connect(step)
end

return Npcs
