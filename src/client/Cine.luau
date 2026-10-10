-- Cutscenes: short camera moments for the rare big things (a Mythic coming
-- home, an evolve, the Megalodon surfacing, a new ride). The rules that keep
-- them a treat and never a problem:
--   * only on land (never take the camera while you're steering at sea)
--   * one at a time, and never over the shark cutscene or the tank view
--   * 2-4 s, and a tap / click / key skips the rest
--   * the HUD hides (the "Cinematic" attribute), letterbox bars slide in and
--     a calm caption sits in the bottom bar; controls pause, then come back
-- A cutscene is a `shot(t)` function giving the camera CFrame and FOV for
-- time t, plus `beats`: things that happen at set times (a burst, a sound).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = game.ReplicatedStorage.Shared
local Layout = require(Shared.Layout)
local UI = require(script.Parent.UI)
local Fx = require(script.Parent.Fx)

local Cine = {}
local player = Players.LocalPlayer

local BAR = 0.085 -- letterbox bar height (share of the screen)
local playing = false
local ui: { bars: { Frame }, title: TextLabel, sub: TextLabel, dip: Frame }? = nil
local controls: any = nil

local function getControls(): any
	if controls == nil then
		local ok, mod = pcall(function()
			return require(player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule"))
		end)
		controls = ok and mod and mod:GetControls() or false
	end
	return controls or nil
end

local function bits()
	if ui then
		return ui
	end
	local screen = Fx.screen()
	local bars = {}
	for i, y in { 0, 1 } do
		bars[i] = UI.frame(screen, { Name = "CineBar", Size = UDim2.fromScale(1, 0), Position = UDim2.fromScale(0, y), AnchorPoint = Vector2.new(0, y),
			BackgroundColor3 = Color3.new(0, 0, 0), ZIndex = 42 })
	end
	local title = UI.label(bars[2], "value", "", { Size = UDim2.new(0.9, 0, 0.5, 0), Position = UDim2.fromScale(0.5, 0.12),
		AnchorPoint = Vector2.new(0.5, 0), ZIndex = 43, TextTransparency = 1 })
	local sub = UI.label(bars[2], "body", "", { Size = UDim2.new(0.9, 0, 0.32, 0), Position = UDim2.fromScale(0.5, 0.6),
		AnchorPoint = Vector2.new(0.5, 0), ZIndex = 43, TextTransparency = 1, TextColor3 = Color3.fromRGB(215, 225, 240) })
	local dip = UI.frame(screen, { Name = "CineDip", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 1, ZIndex = 44 })
	ui = { bars = bars, title = title, sub = sub, dip = dip }
	return ui :: any
end

local function root(): BasePart?
	local char = player.Character
	return char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
end

-- may a cutscene take the camera right now?
function Cine.canPlay(): boolean
	if playing or player:GetAttribute("Cinematic") or player:GetAttribute("ViewingTank") then
		return false
	end
	local hrp = root()
	if not hrp then
		return false
	end
	return not Layout.inWater(hrp.Position) or Layout.islandAt(hrp.Position, 0) ~= nil
end

function Cine.playing(): boolean
	return playing
end

export type Opts = {
	time: number,
	shot: (t: number) -> (CFrame, number),
	beats: { { at: number, fn: () -> (), keep: boolean? } }?, -- keep: still runs if skipped
	title: string?,
	sub: string?,
	color: Color3?,
	captionAt: number?,
	onEnd: (() -> ())?,
}

-- returns false (and does nothing) when a cutscene can't play now
function Cine.play(o: Opts): boolean
	if not Cine.canPlay() then
		return false
	end
	playing = true
	local u = bits()
	local cam = Workspace.CurrentCamera
	local fov = cam.FieldOfView
	player:SetAttribute("Cinematic", true)
	cam.CameraType = Enum.CameraType.Scriptable
	local c = getControls()
	if c then
		c:Disable()
	end
	for _, b in u.bars do
		TweenService:Create(b, TweenInfo.new(0.22, Enum.EasingStyle.Quad), { Size = UDim2.fromScale(1, BAR) }):Play()
	end
	u.title.Text = o.title or ""
	u.title.TextColor3 = o.color or UI.T.gold
	u.sub.Text = o.sub or ""
	u.title.TextTransparency, u.sub.TextTransparency = 1, 1

	local beats = table.clone(o.beats or {})
	local t0 = os.clock()
	local done = false
	local inputConn: RBXScriptConnection? = nil
	local captionShown = false

	local function finish()
		if done then
			return
		end
		done = true
		RunService:UnbindFromRenderStep("Cine")
		if inputConn then
			inputConn:Disconnect()
		end
		-- a short dip to black hides the cut back to the game camera
		u.dip.BackgroundTransparency = 0.15
		cam.CameraType = Enum.CameraType.Custom
		cam.FieldOfView = fov
		local cc = getControls()
		if cc then
			cc:Enable()
		end
		TweenService:Create(u.dip, TweenInfo.new(0.35, Enum.EasingStyle.Quad), { BackgroundTransparency = 1 }):Play()
		for _, b in u.bars do
			TweenService:Create(b, TweenInfo.new(0.25, Enum.EasingStyle.Quad), { Size = UDim2.fromScale(1, 0) }):Play()
		end
		u.title.TextTransparency, u.sub.TextTransparency = 1, 1
		player:SetAttribute("Cinematic", false)
		playing = false
		if o.onEnd then
			task.spawn(o.onEnd)
		end
	end

	RunService:BindToRenderStep("Cine", Enum.RenderPriority.Camera.Value, function()
		local t = os.clock() - t0
		-- something else took over (the shark got you after all): bow out
		if cam.CameraType ~= Enum.CameraType.Scriptable then
			finish()
			return
		end
		local cf, f = o.shot(math.min(t, o.time))
		cam.CFrame = cf
		cam.FieldOfView = f
		for i = #beats, 1, -1 do
			if t >= beats[i].at then
				local b = table.remove(beats, i) :: any
				task.spawn(b.fn)
			end
		end
		if not captionShown and t >= (o.captionAt or o.time * 0.3) then
			captionShown = true
			TweenService:Create(u.title, TweenInfo.new(0.3), { TextTransparency = 0 }):Play()
			TweenService:Create(u.sub, TweenInfo.new(0.3), { TextTransparency = 0 }):Play()
		end
		if t >= o.time then
			finish()
		end
	end)
	-- skip: any tap, click or key once it's had a moment to land
	inputConn = UserInputService.InputBegan:Connect(function(input)
		if os.clock() - t0 < 0.6 then
			return
		end
		local kind = input.UserInputType
		if kind == Enum.UserInputType.Touch or kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Keyboard
			or kind == Enum.UserInputType.Gamepad1 then
			-- the beats that matter after it (keep) still run now
			for _, b in beats do
				if b.keep then
					task.spawn(b.fn)
				end
			end
			table.clear(beats)
			finish()
		end
	end)
	return true
end

-- camera helpers for shots
function Cine.ease(k: number): number
	k = math.clamp(k, 0, 1)
	return k * k * (3 - 2 * k)
end

-- a point on a circle around `center` (radius r, height h, angle a)
function Cine.orbit(center: Vector3, r: number, h: number, a: number): Vector3
	return center + Vector3.new(math.sin(a) * r, h, math.cos(a) * r)
end

return Cine
