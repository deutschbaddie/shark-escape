-- Juice: sounds, 3D bursts, number popups, camera shake, screen flashes.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local Debris = game:GetService("Debris")
local Workspace = game:GetService("Workspace")

local UI = require(script.Parent.UI)
local Sounds = require(script.Parent.Sounds)

local Fx = {}

local player = Players.LocalPlayer
local fxFolder = Instance.new("Folder")
fxFolder.Name = "LocalFx"
fxFolder.Parent = Workspace

Fx.TEX = {
	sparkle = "rbxasset://textures/particles/sparkles_main.dds",
	smoke = "rbxasset://textures/particles/smoke_main.dds",
}

----------------------------------------------------------------- sound
-- one-shot by slot name (Config.SoundSlots via Sounds.luau). `at` makes it
-- 3D: a world position, or a part/attachment it follows (a rider's root)
local UI_SOUNDS = { uiClick = true, uiOpen = true, uiClose = true, uiError = true, uiToast = true, uiTakeover = true }
function Fx.sound(name: string, volume: number?, pitch: number?, at: (Vector3 | Instance)?)
	if not Sounds.has(name) then
		return
	end
	local group = UI_SOUNDS[name] and "UI" or "Effects"
	if typeof(at) == "Vector3" then
		local a = Instance.new("Attachment")
		a.WorldPosition = at
		a.Parent = Workspace.Terrain
		local s = Sounds.play(name, volume, pitch, a, group)
		if s then
			s.RollOffMode = Enum.RollOffMode.InverseTapered
			s.RollOffMinDistance = 12
			s.RollOffMaxDistance = 300
		end
		Debris:AddItem(a, 8)
	elseif typeof(at) == "Instance" then
		local s = Sounds.play(name, volume, pitch, at, group)
		if s then
			s.RollOffMode = Enum.RollOffMode.InverseTapered
			s.RollOffMinDistance = 12
			s.RollOffMaxDistance = 200
		end
	else
		Sounds.play(name, volume, pitch, SoundService, group)
	end
end

----------------------------------------------------------------- 3D bursts
local function emitterAt(pos: Vector3, props: { [string]: any }, count: number, life: number?)
	local a = Instance.new("Attachment")
	a.WorldPosition = pos
	a.Parent = Workspace.Terrain
	local e = Instance.new("ParticleEmitter")
	e.Enabled = false
	for k, v in props do
		(e :: any)[k] = v
	end
	e.Parent = a
	e:Emit(count)
	Debris:AddItem(a, life or 3)
	return e
end

function Fx.splash(pos: Vector3, size: number?)
	local s = size or 1
	emitterAt(pos, {
		Texture = Fx.TEX.smoke,
		Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(180, 240, 255)),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.5 * s), NumberSequenceKeypoint.new(1, 4 * s) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) }),
		Lifetime = NumberRange.new(0.6, 1.1),
		Speed = NumberRange.new(14 * s, 30 * s),
		SpreadAngle = Vector2.new(35, 35),
		EmissionDirection = Enum.NormalId.Top,
		Acceleration = Vector3.new(0, -60, 0),
		Drag = 2,
		LightEmission = 0.3,
	}, math.floor(28 * s))
	emitterAt(pos, {
		Texture = Fx.TEX.sparkle,
		Color = ColorSequence.new(Color3.fromRGB(200, 250, 255)),
		Size = NumberSequence.new(0.6 * s, 0),
		Lifetime = NumberRange.new(0.5, 0.9),
		Speed = NumberRange.new(20 * s, 40 * s),
		SpreadAngle = Vector2.new(50, 50),
		EmissionDirection = Enum.NormalId.Top,
		Acceleration = Vector3.new(0, -80, 0),
		LightEmission = 1,
	}, math.floor(30 * s))
end

function Fx.confetti(pos: Vector3, colors: { Color3 }?)
	local cols = colors or { UI.C.pink, UI.C.gold, UI.C.sky, UI.C.green }
	for _, c in cols do
		emitterAt(pos, {
			Texture = "",
			Color = ColorSequence.new(c),
			Size = NumberSequence.new(0.35),
			Lifetime = NumberRange.new(1.2, 2),
			Speed = NumberRange.new(25, 45),
			SpreadAngle = Vector2.new(60, 60),
			EmissionDirection = Enum.NormalId.Top,
			Acceleration = Vector3.new(0, -50, 0),
			Rotation = NumberRange.new(0, 360),
			RotSpeed = NumberRange.new(-300, 300),
			Drag = 1.5,
		}, 18)
	end
end

function Fx.sparkle(pos: Vector3, color: Color3, count: number?)
	emitterAt(pos, {
		Texture = Fx.TEX.sparkle,
		Color = ColorSequence.new(color),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.2), NumberSequenceKeypoint.new(1, 0) }),
		Lifetime = NumberRange.new(0.6, 1.2),
		Speed = NumberRange.new(8, 20),
		SpreadAngle = Vector2.new(180, 180),
		LightEmission = 1,
		Drag = 3,
	}, count or 30)
end

-- shockwave ring on the water
function Fx.ring(pos: Vector3, color: Color3, maxSize: number)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CastShadow = false
	p.Shape = Enum.PartType.Cylinder
	p.Material = Enum.Material.Neon
	p.Color = color
	p.Size = Vector3.new(0.2, 2, 2)
	p.CFrame = CFrame.new(pos) * CFrame.Angles(0, 0, math.pi / 2)
	p.Transparency = 0.2
	p.Parent = fxFolder
	TweenService:Create(p, TweenInfo.new(0.6, Enum.EasingStyle.Quad), { Size = Vector3.new(0.2, maxSize, maxSize), Transparency = 1 }):Play()
	Debris:AddItem(p, 0.7)
end

----------------------------------------------------------------- popups
function Fx.popup3D(pos: Vector3, text: string, color: Color3?, big: boolean?)
	local a = Instance.new("Attachment")
	a.WorldPosition = pos
	a.Parent = Workspace.Terrain
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(big and 320 or 200, big and 80 or 50)
	bb.AlwaysOnTop = true
	bb.LightInfluence = 0
	bb.Adornee = a
	bb.Parent = a
	local t = UI.outlined(bb, text, { TextColor3 = color or UI.C.gold })
	local scale = Instance.new("UIScale")
	scale.Scale = 0.3
	scale.Parent = t
	TweenService:Create(scale, TweenInfo.new(0.35, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	TweenService:Create(bb, TweenInfo.new(1.2, Enum.EasingStyle.Quad), { StudsOffsetWorldSpace = Vector3.new(0, 5, 0) }):Play()
	task.delay(0.8, function()
		UI.fade(t, false, 0.4) -- text and its outline together
	end)
	Debris:AddItem(a, 1.4)
end

----------------------------------------------------------------- camera
local shakeAmount = 0
RunService:BindToRenderStep("FxShake", Enum.RenderPriority.Camera.Value + 1, function(dt)
	if shakeAmount > 0.01 then
		local cam = Workspace.CurrentCamera
		local a = shakeAmount
		cam.CFrame = cam.CFrame * CFrame.Angles(math.rad((math.random() - 0.5) * a), math.rad((math.random() - 0.5) * a), 0)
		shakeAmount *= math.exp(-dt * 6)
	end
end)

function Fx.shake(amount: number)
	shakeAmount = math.max(shakeAmount, amount)
end

----------------------------------------------------------------- screen
local screen: ScreenGui
function Fx.screen(): ScreenGui
	if not screen then
		screen = Instance.new("ScreenGui")
		screen.Name = "FxScreen"
		screen.IgnoreGuiInset = true
		screen.ResetOnSpawn = false
		screen.DisplayOrder = 20
		screen.Parent = player:WaitForChild("PlayerGui")
	end
	return screen
end

function Fx.flash(color: Color3, duration: number?, startT: number?)
	local f = UI.frame(Fx.screen(), {
		Size = UDim2.fromScale(1, 1), BackgroundColor3 = color, BackgroundTransparency = startT or 0.3, ZIndex = 50,
	})
	TweenService:Create(f, TweenInfo.new(duration or 0.5), { BackgroundTransparency = 1 }):Play()
	Debris:AddItem(f, (duration or 0.5) + 0.1)
end

-- The shark's jaws snap shut over the whole screen, hold, then fling open:
-- the "spat out" moment. Blocky stepped teeth (the game's stud look) that
-- interlock when closed. onClosed runs while the screen is covered.
-- `color`: the biting shark's (Config.biteColor), bright, never blood red
local TOOTH = Color3.fromRGB(252, 250, 242)
local TEETH, TOOTH_H = 10, 54
function Fx.jaws(onClosed: (() -> ())?, color: Color3?)
	local GUM = color or Color3.fromRGB(60, 170, 255)
	local GUM_EDGE = GUM:Lerp(Color3.new(0, 0, 0), 0.25)
	local root = UI.frame(Fx.screen(), { Name = "Jaws", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 55 })
	local jaws = {}
	for i, top in { true, false } do
		-- the jaw: gums filling half the screen; teeth hang off its inner edge
		local jaw = UI.frame(root, { Size = UDim2.fromScale(1.2, 0.5), AnchorPoint = Vector2.new(0.5, top and 1 or 0),
			Position = UDim2.new(0.5, 0, top and 0 or 1, top and -TOOTH_H or TOOTH_H), BackgroundColor3 = GUM, ZIndex = 55 })
		UI.frame(jaw, { Size = UDim2.new(1, 0, 0, 10), Position = UDim2.fromScale(0, top and 1 or 0), AnchorPoint = Vector2.new(0, top and 1 or 0),
			BackgroundColor3 = GUM_EDGE, ZIndex = 56 })
		for t = 0, TEETH do
			-- bottom row sits half a tooth over, so the rows interlock
			local x = (t + (i == 2 and 0.5 or 0)) / TEETH
			local tooth = UI.frame(jaw, { Size = UDim2.new(1 / TEETH * 0.72, 0, 0, TOOTH_H), AnchorPoint = Vector2.new(0.5, top and 0 or 1),
				Position = UDim2.new(x * (1 / 1.2) + 0.1 / 1.2 * 1, 0, top and 1 or 0, 0), BackgroundTransparency = 1, ZIndex = 57 })
			for step, w in { 1, 0.68, 0.36 } do
				UI.frame(tooth, { Size = UDim2.new(w, 0, 1 / 3, 0), AnchorPoint = Vector2.new(0.5, top and 0 or 1),
					Position = UDim2.fromScale(0.5, top and (step - 1) / 3 or 1 - (step - 1) / 3), BackgroundColor3 = TOOTH, ZIndex = 57 })
			end
		end
		jaws[i] = jaw
	end
	-- snap shut (teeth meet in the middle)
	local shut = TweenInfo.new(0.13, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	TweenService:Create(jaws[1], shut, { Position = UDim2.new(0.5, 0, 0.5, -TOOTH_H / 2) }):Play()
	TweenService:Create(jaws[2], shut, { Position = UDim2.new(0.5, 0, 0.5, TOOTH_H / 2) }):Play()
	task.delay(0.13, function()
		Fx.shake(1.6)
		if onClosed then
			onClosed()
		end
	end)
	-- then spit: the jaws fling open past the screen edges
	task.delay(0.42, function()
		local open = TweenInfo.new(0.32, Enum.EasingStyle.Back, Enum.EasingDirection.In)
		TweenService:Create(jaws[1], open, { Position = UDim2.new(0.5, 0, 0, -TOOTH_H) }):Play()
		TweenService:Create(jaws[2], open, { Position = UDim2.new(0.5, 0, 1, TOOTH_H) }):Play()
	end)
	Debris:AddItem(root, 0.9)
end

-- Near miss: the world drains of color, blurs and the view punches in for a
-- moment, then snaps back (time "slows" without slowing the game)
-- a zone opens up: columns of light rise out of the water across the whole
-- zone line, in a wave from the middle out (the physical "you can go now")
function Fx.gateWave(z: number, originX: number, width: number, color: Color3)
	local folder = Instance.new("Folder")
	folder.Name = "GateWave"
	folder.Parent = Workspace
	local n = math.floor(width / 10)
	for i = 0, n do
		local x = originX - width / 2 + i * (width / n)
		local delay = math.abs(x - originX) / (width / 2) * 0.6
		task.delay(delay, function()
			local p = Instance.new("Part")
			p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
			p.Material = Enum.Material.Neon
			p.Color = color
			p.Transparency = 0.2
			p.Size = Vector3.new(2.2, 0.2, 2.2)
			p.CFrame = CFrame.new(x, 0.2, z)
			p.Parent = folder
			TweenService:Create(p, TweenInfo.new(0.5, Enum.EasingStyle.Quad), { Size = Vector3.new(2.2, 26, 2.2), CFrame = CFrame.new(x, 13, z) }):Play()
			task.delay(0.6, function()
				TweenService:Create(p, TweenInfo.new(0.9), { Transparency = 1 }):Play()
			end)
			if i % 3 == 0 then
				Fx.splash(Vector3.new(x, 0.5, z), 0.8)
			end
		end)
	end
	Debris:AddItem(folder, 2.6)
end

function Fx.nearMiss()
	local Lighting = game:GetService("Lighting")
	local cam = Workspace.CurrentCamera
	local blur = Instance.new("BlurEffect")
	blur.Size = 0
	blur.Parent = Lighting
	local cc = Instance.new("ColorCorrectionEffect")
	cc.Parent = Lighting
	local into = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local out = TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	TweenService:Create(blur, into, { Size = 10 }):Play()
	TweenService:Create(cc, into, { Saturation = -0.75, Contrast = 0.15 }):Play()
	local fov = cam and cam.FieldOfView
	if cam and fov then
		TweenService:Create(cam, into, { FieldOfView = fov - 10 }):Play()
	end
	task.delay(0.35, function()
		TweenService:Create(blur, out, { Size = 0 }):Play()
		TweenService:Create(cc, out, { Saturation = 0, Contrast = 0 }):Play()
		if cam and fov then
			TweenService:Create(cam, out, { FieldOfView = fov }):Play()
		end
		task.wait(0.75)
		blur:Destroy()
		cc:Destroy()
	end)
end

-- Danger glow on the screen edge the threat comes from (a lunging shark):
-- pulses for `dur` seconds, so you know which way to swerve without words.
function Fx.edgeWarn(from: Vector3, dur: number, color: Color3?)
	local cam = Workspace.CurrentCamera
	if not cam then
		return
	end
	local rel = cam.CFrame:PointToObjectSpace(from)
	local ang = math.atan2(rel.X, -rel.Z) -- 0 ahead, + right, +-pi behind
	local side = math.abs(ang) < math.rad(40) and "top" or math.abs(ang) > math.rad(140) and "bottom" or (ang > 0 and "right" or "left")
	local horiz = side == "left" or side == "right"
	local f = UI.frame(Fx.screen(), {
		Name = "EdgeWarn",
		Size = horiz and UDim2.fromScale(0.22, 1) or UDim2.fromScale(1, 0.26),
		Position = UDim2.fromScale(side == "right" and 1 or 0, side == "bottom" and 1 or 0),
		AnchorPoint = Vector2.new(side == "right" and 1 or 0, side == "bottom" and 1 or 0),
		BackgroundColor3 = color or Color3.fromRGB(255, 50, 60), BackgroundTransparency = 1, ZIndex = 50,
	})
	local g = Instance.new("UIGradient")
	g.Rotation = ({ left = 0, right = 180, top = 90, bottom = 270 })[side]
	g.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) })
	g.Parent = f
	local pulses = math.max(2, math.floor(dur / 0.3))
	local each = dur / pulses
	task.spawn(function()
		for _ = 1, pulses do
			TweenService:Create(f, TweenInfo.new(each * 0.35, Enum.EasingStyle.Quad), { BackgroundTransparency = 0.15 }):Play()
			task.wait(each * 0.35)
			TweenService:Create(f, TweenInfo.new(each * 0.65, Enum.EasingStyle.Quad), { BackgroundTransparency = 0.75 }):Play()
			task.wait(each * 0.65)
		end
		TweenService:Create(f, TweenInfo.new(0.2), { BackgroundTransparency = 1 }):Play()
		task.wait(0.22)
		f:Destroy()
	end)
end

Fx.wordHook = nil :: ((string, Color3?, number?) -> ())?

-- (old name) a small moment: a plain toast via Notify. Never a big word.
function Fx.bigWord(text: string, color: Color3, duration: number?)
	if Fx.wordHook then
		Fx.wordHook(text, color, duration)
	end
end

Fx.folder = fxFolder
return Fx
