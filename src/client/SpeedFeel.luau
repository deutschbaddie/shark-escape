-- Speed you can feel: while you move fast the camera widens and thin
-- streaks fly past the edges of the screen. Past the speed cap
-- (Config.realSpeed tops out at 320) the stat still grows, so the feel does
-- too: more streaks, a gold tint, a little more FOV ("overdrive").
-- It never fights other camera effects: if something else changed the FOV
-- (a charge punch, a near miss, a cutscene) it waits until that's done.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = game.ReplicatedStorage.Shared
local Config = require(Shared.Config)
local State = require(script.Parent.State)

local SpeedFeel = {}
local player = Players.LocalPlayer

local BASE_FOV = 70
local MAX_CAP = Config.realSpeed(math.huge) -- 320
local CAP_STAT = ((MAX_CAP - 16) / 9) ^ 3 -- the speed stat where you hit the cap
local STREAKS = 18

local lastSet: number? = nil
local streaks: { { f: Frame, a: number, t: number, len: number } } = {}

local function build(): ScreenGui
	local gui = Instance.new("ScreenGui")
	gui.Name = "SpeedFeel"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ScreenInsets = Enum.ScreenInsets.None
	gui.DisplayOrder = -5 -- under every HUD
	gui.Parent = player:WaitForChild("PlayerGui")
	for i = 1, STREAKS do
		local f = Instance.new("Frame")
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.BorderSizePixel = 0
		f.BackgroundColor3 = Color3.new(1, 1, 1)
		f.BackgroundTransparency = 1
		f.Parent = gui
		streaks[i] = { f = f, a = math.random() * math.pi * 2, t = math.random(), len = 0 }
	end
	return gui
end

local function busy(): boolean
	return player:GetAttribute("Cinematic") == true or player:GetAttribute("ViewingTank") == true
end

function SpeedFeel.start()
	build()
	local feel = 0
	RunService.RenderStepped:Connect(function(dt)
		local cam = Workspace.CurrentCamera
		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		local v = hrp and hrp.AssemblyLinearVelocity * Vector3.new(1, 0, 1) or Vector3.zero
		local d = State.data
		-- 0 below ~90 studs/s, 1 at the cap
		local want = busy() and 0 or math.clamp((v.Magnitude - 90) / (MAX_CAP - 90), 0, 1)
		feel += (want - feel) * math.min(dt * 3, 1)
		local over = (d and d.speed and d.speed > CAP_STAT) and math.clamp(math.log10(d.speed / CAP_STAT), 0, 1) or 0
		over *= feel

		-- FOV: only when nobody else is driving it
		if cam and cam.CameraType == Enum.CameraType.Custom and not busy() then
			local fov = cam.FieldOfView
			local free = lastSet == nil or math.abs(fov - lastSet) < 0.2 or math.abs(fov - BASE_FOV) < 0.2
			if free then
				local target = BASE_FOV + feel * 12 + over * 6
				local nextFov = fov + (target - fov) * math.min(dt * 4, 1)
				cam.FieldOfView = nextFov
				lastSet = nextFov
			end
		end

		-- streaks: thin lines flying outward from the middle of the screen
		local size = cam and cam.ViewportSize or Vector2.new(1280, 720)
		local active = math.floor(STREAKS * (0.35 + 0.65 * over) + 0.5)
		local color = Color3.new(1, 1, 1):Lerp(Color3.fromRGB(255, 210, 90), over)
		for i, s in streaks do
			local on = feel > 0.02 and i <= active
			s.t += dt * (1.6 + feel * 2.4)
			if s.t >= 1 then
				s.t -= 1
				s.a = math.random() * math.pi * 2
				s.len = 60 + math.random() * 120
			end
			if not on then
				s.f.BackgroundTransparency = 1
				continue
			end
			-- from 45% of the way out to beyond the edge
			local r = (0.45 + s.t * 0.7) * size.Magnitude * 0.5
			local dir = Vector2.new(math.cos(s.a), math.sin(s.a))
			local at = size / 2 + dir * r
			s.f.Position = UDim2.fromOffset(at.X, at.Y)
			s.f.Size = UDim2.fromOffset(s.len * (0.6 + feel), 2)
			s.f.Rotation = math.deg(s.a)
			s.f.BackgroundColor3 = color
			s.f.BackgroundTransparency = 1 - (0.08 + 0.3 * feel) * math.sin(s.t * math.pi)
		end
	end)
end

return SpeedFeel
