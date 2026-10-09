-- Day and night (the shark phases: dusk = "warning", night = "hunt", dawn =
-- "clear") as a sky: the sun sets at dusk, a moonlit blue night, sunrise.

local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")

local Remotes = require(game.ReplicatedStorage.Shared.Remotes)

local Weather = {}

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
			-- sunrise: the clock runs on through dawn (not back through sunset)
			TweenService:Create(Lighting, TweenInfo.new(2.5, Enum.EasingStyle.Sine), { ClockTime = 29.5 }):Play()
			task.delay(2.6, function()
				Lighting.ClockTime = 5.5
				sky("day", 3)
			end)
		end
	end)
end

return Weather
