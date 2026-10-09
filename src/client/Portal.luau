-- The plaza portals between the worlds (World.luau builds one in each
-- world; the server moves you: Game actions.portal). Here: each sign says
-- if it's open for you, the prompt asks the server, the trip gets a flash
-- of the new world's color, and Candy Bay gets its pink grade.

local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")

local Shared = game.ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Layout = require(Shared.Layout)
local Remotes = require(Shared.Remotes)
local State = require(script.Parent.State)
local Notify = require(script.Parent.Notify)
local Prompts = require(script.Parent.Prompts)
local Fx = require(script.Parent.Fx)

local Portal = {}

local grade: ColorCorrectionEffect? = nil

-- "OPEN" or how many rebirths it still takes, on each sign and prompt
local function refresh()
	local d = State.data
	if not d then
		return
	end
	for _, map in Layout.worldFolders() do
		local m = map:FindFirstChild("Portal")
		local target = m and m:GetAttribute("Target")
		local w = typeof(target) == "number" and Config.Worlds[target] or nil
		if not (m and w) then
			continue
		end
		local open = d.unlocked and d.unlocked[tostring(w.id)] == true
		local text
		if open then
			text = "OPEN! Step in"
		else
			local need = math.max(1, w.unlockRebirths - (d.world == 1 and d.wr or 0))
			text = ("Rebirth %d more time%s to unlock"):format(need, need == 1 and "" or "s")
		end
		local sign = m:FindFirstChild("Sign", true)
		if sign then
			for _, bb in sign:GetChildren() do
				local sub = bb:FindFirstChild("Sub")
				if sub and sub:IsA("TextLabel") then
					sub.Text = text
				end
			end
		end
		local prompt = m:FindFirstChild("Portal", true)
		if prompt and prompt:IsA("ProximityPrompt") then
			prompt.ActionText = open and "Enter" or "Locked"
		end
	end
	-- Candy Bay looks sweeter: a light pink, extra-saturated grade
	local candy = d.world == 2
	if candy and not grade then
		grade = Instance.new("ColorCorrectionEffect")
		grade.Name = "WorldGrade"
		grade.TintColor = Color3.fromRGB(255, 238, 250)
		grade.Saturation = 0.15
		grade.Parent = Lighting
	elseif not candy and grade then
		grade:Destroy()
		grade = nil
	end
end

function Portal.start()
	State.Changed:Connect(refresh)
	task.spawn(function()
		while #Layout.worldFolders() < #Config.Worlds do
			task.wait(1)
		end
		refresh()
	end)
	Prompts.Triggered:Connect(function(prompt)
		if prompt.Name == "Portal" then
			State.action("portal")
		end
	end)
	Remotes.get("Notify").OnClientEvent:Connect(function(kind, data)
		if kind ~= "portal" then
			return
		end
		-- the trip: the screen floods with the new world's color while the
		-- server moves you (0.9 s), then clears on the other side
		local w = Config.Worlds[data.world]
		local color = w and w.color or Color3.new(1, 1, 1)
		local f = Instance.new("Frame")
		f.Size = UDim2.fromScale(1, 1)
		f.BackgroundColor3 = color
		f.BackgroundTransparency = 1
		f.ZIndex = 80
		f.Parent = Fx.screen()
		TweenService:Create(f, TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { BackgroundTransparency = 0 }):Play()
		task.delay(1.3, function()
			TweenService:Create(f, TweenInfo.new(0.8, Enum.EasingStyle.Quad), { BackgroundTransparency = 1 }):Play()
			Notify.takeover(("WELCOME TO %s!"):format(tostring(data.name):upper()), "A whole new sea to catch", color, 2.2)
			task.delay(0.85, function()
				f:Destroy()
			end)
		end)
	end)
end

return Portal
