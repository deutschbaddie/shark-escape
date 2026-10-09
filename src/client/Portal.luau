-- The plaza portal to the other world (World.luau builds it, the server
-- teleports: Game actions.portal). Here: the sign says if it's open for
-- you, the prompt asks the server, and the trip gets its moment.

local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")

local Shared = game.ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local State = require(script.Parent.State)
local Notify = require(script.Parent.Notify)
local Prompts = require(script.Parent.Prompts)
local Fx = require(script.Parent.Fx)

local Portal = {}

local function portalModel(): Model?
	local map = Workspace:FindFirstChild("Map")
	return map and map:FindFirstChild("Portal") :: Model?
end

-- "OPEN" or how many rebirths it still takes, on the sign and the prompt
local function refresh()
	local d = State.data
	local m = portalModel()
	if not (d and m) then
		return
	end
	local target = m:GetAttribute("Target")
	local w = typeof(target) == "number" and Config.Worlds[target] or nil
	if not w then
		return
	end
	local open = d.unlocked and d.unlocked[tostring(w.id)] == true
	local text
	if open then
		text = w.placeId ~= 0 and "OPEN! Step in" or "Opens soon!"
	else
		local need = math.max(1, w.unlockRebirths - (d.wr or 0))
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
	local prompt = m:FindFirstChild("Portal", true) :: ProximityPrompt?
	if prompt then
		prompt.ActionText = open and "Enter" or "Locked"
	end
end

function Portal.start()
	-- Candy Bay looks sweeter: a light pink, extra-saturated grade
	if Config.WORLD == 2 then
		local cc = Instance.new("ColorCorrectionEffect")
		cc.Name = "WorldGrade"
		cc.TintColor = Color3.fromRGB(255, 238, 250)
		cc.Saturation = 0.15
		cc.Parent = game:GetService("Lighting")
	end
	State.Changed:Connect(refresh)
	task.spawn(function()
		while not portalModel() do
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
		-- the trip: a takeover, then the screen floods with the world's color
		local m = portalModel()
		local target = m and m:GetAttribute("Target")
		local w = typeof(target) == "number" and Config.Worlds[target] or nil
		local color = w and w.color or Color3.new(1, 1, 1)
		Notify.takeover(("TO %s!"):format(tostring(data.name):upper()), "Hold on tight...", color, 2.5)
		local f = Instance.new("Frame")
		f.Size = UDim2.fromScale(1, 1)
		f.BackgroundColor3 = color
		f.BackgroundTransparency = 1
		f.ZIndex = 80
		f.Parent = Fx.screen()
		TweenService:Create(f, TweenInfo.new(1.6, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { BackgroundTransparency = 0 }):Play()
		task.delay(12, function()
			f:Destroy() -- still here: the teleport didn't happen
		end)
	end)
end

return Portal
