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

-- big center-screen word ("CHOMP!", "LUCKY!"). One at a time: a word that
-- arrives while another is up waits its turn (and stale ones are dropped).
local wordBusyUntil = 0
local wordQueue = 0

local function showWord(text: string, color: Color3, duration: number)
	local t = UI.outlined(Fx.screen(), text, {
		Size = UDim2.fromScale(0.8, 0.14), Position = UDim2.fromScale(0.5, 0.36), AnchorPoint = Vector2.new(0.5, 0.5),
		TextColor3 = color, ZIndex = 60, Rotation = -3,
	})
	local scale = Instance.new("UIScale")
	scale.Scale = 2.2
	scale.Parent = t
	TweenService:Create(scale, TweenInfo.new(0.3, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	task.delay(duration, function()
		UI.fade(t, false, 0.3)
		TweenService:Create(scale, TweenInfo.new(0.3), { Scale = 0.6 }):Play()
	end)
	Debris:AddItem(t, duration + 0.4)
end

Fx.wordHook = nil :: ((string, Color3?, number?) -> ())?

function Fx.bigWord(text: string, color: Color3, duration: number?)
	if Fx.wordHook then
		Fx.wordHook(text, color, duration) -- Notify's center stage (one at a time)
		return
	end
	local d = duration or 1
	local now = os.clock()
	if now >= wordBusyUntil then
		wordBusyUntil = now + d + 0.35
		showWord(text, color, d)
		return
	end
	if wordQueue >= 1 then
		return -- one waiting is enough; skip the rest
	end
	wordQueue += 1
	local at = wordBusyUntil
	wordBusyUntil = at + d + 0.35
	task.delay(at - now, function()
		wordQueue -= 1
		showWord(text, color, d)
	end)
end

Fx.folder = fxFolder
return Fx
