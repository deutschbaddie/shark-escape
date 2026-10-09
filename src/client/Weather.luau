-- Day and night (the shark phases: dusk = "warning", night = "hunt", dawn =
-- "clear") as a sky: the sun sets at dusk, a moonlit blue night, sunrise.
-- Plus the Lucky Storm, as this client sees it (server/Storm.luau starts it): a big
-- takeover, a dark blue tint with lightning flashes, rain streaks around
-- the camera and a banner counting down while catches are luckier.

local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Remotes = require(game.ReplicatedStorage.Shared.Remotes)
local Notify = require(script.Parent.Notify)
local UI = require(script.Parent.UI)

local Weather = {}

local COLOR = Color3.fromRGB(170, 120, 255)

local tint: ColorCorrectionEffect
local rain: Part
local emitter: ParticleEmitter
local running = false

local function build()
	tint = Instance.new("ColorCorrectionEffect")
	tint.Name = "StormTint"
	tint.Enabled = false
	tint.Parent = Lighting

	-- a sheet above the camera that emits fast, stretched drops downward
	rain = Instance.new("Part")
	rain.Name = "Rain"
	rain.Anchored = true
	rain.CanCollide = false
	rain.CanQuery = false
	rain.CanTouch = false
	rain.CastShadow = false
	rain.Transparency = 1
	rain.Size = Vector3.new(140, 1, 140)
	emitter = Instance.new("ParticleEmitter")
	emitter.Enabled = false
	emitter.EmissionDirection = Enum.NormalId.Bottom
	emitter.Orientation = Enum.ParticleOrientation.VelocityParallel
	emitter.Rate = 500
	emitter.Lifetime = NumberRange.new(0.9, 1.2)
	emitter.Speed = NumberRange.new(85, 100)
	emitter.Size = NumberSequence.new(0.18)
	emitter.Squash = NumberSequence.new(2.6) -- tall and thin: streaks
	emitter.Color = ColorSequence.new(Color3.fromRGB(200, 220, 255))
	emitter.Transparency = NumberSequence.new(0.35)
	emitter.LightEmission = 0.3
	emitter.Parent = rain
	rain.Parent = Workspace
end

local function setLook(on: boolean)
	local info = TweenInfo.new(on and 2.5 or 4, Enum.EasingStyle.Quad)
	tint.Enabled = true
	TweenService:Create(tint, info, on and {
		TintColor = Color3.fromRGB(175, 185, 230), Brightness = -0.06, Saturation = -0.2, Contrast = 0.08,
	} or { TintColor = Color3.new(1, 1, 1), Brightness = 0, Saturation = 0, Contrast = 0 }):Play()
	emitter.Enabled = on
end

local function flash()
	local b = tint.Brightness
	tint.Brightness = 0.35
	TweenService:Create(tint, TweenInfo.new(0.25), { Brightness = b }):Play()
end

local function left(): number
	local untilT = Workspace:GetAttribute("StormUntil")
	return typeof(untilT) == "number" and untilT - Workspace:GetServerTimeNow() or 0
end

local function run()
	if running or left() <= 0 then
		return
	end
	running = true
	Notify.takeover("LUCKY STORM!", "Rarer catches and more mutations", COLOR, 2.2)
	setLook(true)
	local nextFlash = os.clock() + 3
	while left() > 0 do
		local t = math.ceil(left())
		Notify.banner("LUCKY STORM", { key = "storm", sticky = true, priority = 3, color = COLOR,
			sub = ("Rarer catches  %d:%02d left"):format(t // 60, t % 60) })
		if os.clock() >= nextFlash then
			flash()
			nextFlash = os.clock() + 5 + math.random() * 7
		end
		task.wait(0.5)
	end
	Notify.clear("storm")
	Notify.toast("The storm passed", UI.C.white)
	setLook(false)
	running = false
end

-- the sky for each part of the day (World.luau sets the daytime values)
local SKY = {
	day = { ClockTime = 13.6, Brightness = 3.2, Ambient = Color3.fromRGB(120, 130, 150), OutdoorAmbient = Color3.fromRGB(170, 180, 200) },
	dusk = { ClockTime = 18.2, Brightness = 2.4, Ambient = Color3.fromRGB(130, 100, 120), OutdoorAmbient = Color3.fromRGB(170, 130, 140) },
	night = { ClockTime = 22.5, Brightness = 1.6, Ambient = Color3.fromRGB(70, 80, 130), OutdoorAmbient = Color3.fromRGB(90, 105, 160) },
}
local function sky(name: string, seconds: number)
	TweenService:Create(Lighting, TweenInfo.new(seconds, Enum.EasingStyle.Sine), SKY[name]):Play()
end

function Weather.start()
	Remotes.get("SharkEvent").OnClientEvent:Connect(function(kind)
		if kind == "warning" then
			sky("dusk", 4)
		elseif kind == "hunt" then
			sky("night", 3)
		elseif kind == "clear" then
			sky("day", 5)
		end
	end)
	build()
	-- keep the rain sheet over the camera
	RunService.RenderStepped:Connect(function()
		if emitter.Enabled then
			local cam = Workspace.CurrentCamera
			if cam then
				rain.CFrame = CFrame.new(cam.CFrame.Position + Vector3.new(0, 45, 0))
			end
		end
	end)
	Workspace:GetAttributeChangedSignal("StormUntil"):Connect(function()
		task.spawn(run)
	end)
	task.delay(6, run) -- joined mid-storm (after the HUD is up)
end

return Weather
