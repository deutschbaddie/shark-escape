-- Looking at tank creatures:
--  * hover one (or tap it on a phone / tablet) to outline it and see its card:
--    name, mutation + rarity, weight and $/s. Works on every dock's tank.
--  * "View Tank" (the prompt on the back of each tank) frames the tank in a
--    calm close-up; drag to look around, scroll / pinch to zoom, X or walk
--    away to leave. The HUD steps aside while you watch.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local GuiService = game:GetService("GuiService")
local Workspace = game:GetService("Workspace")

local Shared = game.ReplicatedStorage.Shared
local Config = require(Shared.Config)
local UI = require(script.Parent.UI)

local TankView = {}
local player = Players.LocalPlayer
local C = UI.C
local T = UI.T

-- rarity accents (same as the menus): Common plain, then green, blue, purple, gold
local RARITY = { Common = T.mute, Uncommon = T.green, Rare = T.blue, Epic = T.purple, Legendary = T.gold }
local function rarityColor(id: string): Color3
	return RARITY[id] or T.mute
end

----------------------------------------------------------------- picking
local function slotsFolders(): { Instance }
	local out = {}
	local map = Workspace:FindFirstChild("Map")
	if map then
		for _, plot in map:GetChildren() do
			local slots = plot:FindFirstChild("Slots")
			if slots then
				table.insert(out, slots)
			end
		end
	end
	return out
end

-- the tank creature under a viewport point (closest to the camera wins)
local function pick(at: Vector2, slack: number?): Model?
	local cam = Workspace.CurrentCamera
	local half = math.tan(math.rad(cam.FieldOfView) / 2)
	local best, bestDepth = nil, math.huge
	for _, slots in slotsFolders() do
		for _, m in slots:GetChildren() do
			if m:IsA("Model") and m.PrimaryPart then
				local cf, size = m:GetBoundingBox()
				local p, onScreen = cam:WorldToViewportPoint(cf.Position)
				if onScreen and p.Z > 0 and p.Z < 90 then
					local radius = size.Magnitude * 0.42 / (p.Z * half) * (cam.ViewportSize.Y / 2)
					if (Vector2.new(p.X, p.Y) - at).Magnitude < math.max(radius, slack or 22) and p.Z < bestDepth then
						best, bestDepth = m, p.Z
					end
				end
			end
		end
	end
	return best
end

----------------------------------------------------------------- the card
local shown: Model? = nil
local outline: Highlight? = nil
local card: BillboardGui? = nil
local pinnedUntil = 0

local function line(parent: Instance, text: string, size: number, color: Color3, order: number): TextLabel
	local t = UI.outlined(parent, text, { TextScaled = false, TextSize = size, AutomaticSize = Enum.AutomaticSize.XY,
		Size = UDim2.fromOffset(0, 0), TextColor3 = color, LayoutOrder = order })
	return t
end

-- a small rounded tag that hugs its text (rarity, mutation)
local function tag(parent: Instance, text: string, color: Color3, order: number): Frame
	local f = UI.frame(parent, { Size = UDim2.fromOffset(0, 24), AutomaticSize = Enum.AutomaticSize.X, BackgroundColor3 = color, LayoutOrder = order })
	UI.corner(f, 12)
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft, pad.PaddingRight = UDim.new(0, 10), UDim.new(0, 10)
	pad.Parent = f
	UI.outlined(f, text:upper(), { TextScaled = false, TextSize = UI.TYPE.meta[1], AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 24), Font = UI.TYPE.meta[2], StrokeColor = UI.dark(color, 0.55) })
	return f
end

local function hide()
	if outline then
		outline:Destroy()
		outline = nil
	end
	if card then
		card:Destroy()
		card = nil
	end
	shown = nil
end

local function show(m: Model)
	if shown == m then
		return
	end
	hide()
	shown = m
	local r = (m:GetAttribute("R") :: string?) or "Common"
	local z = m:GetAttribute("Z") :: string?
	local mut = m:GetAttribute("M") :: string?
	local s = (m:GetAttribute("S") :: number?) or 1
	local perSecond = (m:GetAttribute("PerSecond") :: number?) or 0

	local hl = Instance.new("Highlight")
	hl.FillTransparency = 1
	hl.OutlineColor = Color3.new(1, 1, 1)
	hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	hl.Adornee = m
	hl.Parent = m
	outline = hl

	local bb = Instance.new("BillboardGui")
	bb.Name = "InspectCard"
	bb.AlwaysOnTop = true
	bb.LightInfluence = 0
	bb.Size = UDim2.fromOffset(300, 140)
	bb.StudsOffsetWorldSpace = Vector3.new(0, m:GetExtentsSize().Y * 0.5 + 1.2, 0)
	bb.Adornee = m.PrimaryPart
	bb.Parent = player:WaitForChild("PlayerGui")
	local box = UI.frame(bb, { Size = UDim2.fromOffset(0, 0), AutomaticSize = Enum.AutomaticSize.XY, Position = UDim2.fromScale(0.5, 1),
		AnchorPoint = Vector2.new(0.5, 1), BackgroundColor3 = T.navy, BackgroundTransparency = 0.05 })
	UI.corner(box, UI.R.card)
	UI.stroke(box, r == "Common" and T.line or rarityColor(r), UI.S.card)
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft, pad.PaddingRight = UDim.new(0, 16), UDim.new(0, 16)
	pad.PaddingTop, pad.PaddingBottom = UDim.new(0, 8), UDim.new(0, 10)
	pad.Parent = box
	local list = Instance.new("UIListLayout")
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, 4)
	list.Parent = box
	local sizeLabel = Config.sizeLabel(s)
	local name = line(box, (sizeLabel and (sizeLabel .. " ") or "") .. Config.species(z, r).name, UI.TYPE.body[1] + 2, T.white, 1)
	name.Font = UI.TYPE.body[2]
	-- rarity (+ mutation) chips
	local chips = UI.frame(box, { Size = UDim2.fromOffset(0, 24), AutomaticSize = Enum.AutomaticSize.X, BackgroundTransparency = 1, LayoutOrder = 2 })
	local cl = Instance.new("UIListLayout")
	cl.FillDirection = Enum.FillDirection.Horizontal
	cl.Padding = UDim.new(0, 6)
	cl.SortOrder = Enum.SortOrder.LayoutOrder
	cl.Parent = chips
	tag(chips, r, rarityColor(r), 1)
	if mut then
		tag(chips, mut, (Config.mutation(mut) :: any).color, 2)
	end
	line(box, Config.formatKg(Config.creatureKg(z, r, s)), UI.TYPE.meta[1], T.mute, 3)
	if m:GetAttribute("Dead") then
		-- not earning: dimmed $/s
		line(box, ("$%s/s  ·  not equipped"):format(UI.short(perSecond)), UI.TYPE.meta[1] + 2, UI.dark(T.mute, 0.25), 4)
	else
		line(box, ("$%s/s"):format(UI.short(perSecond)), UI.TYPE.body[1], C.money, 4)
	end
	card = bb
	UI.fade(box, true, 0.12)
end

----------------------------------------------------------------- tank camera
local viewing = false
local viewGui: ScreenGui? = nil
local yaw, pitch, dist = 0, 0.12, 15
local dragging = false
local conns: { RBXScriptConnection } = {}

local function closeView()
	if not viewing then
		return
	end
	viewing = false
	for _, c in conns do
		c:Disconnect()
	end
	table.clear(conns)
	RunService:UnbindFromRenderStep("TankView")
	local cam = Workspace.CurrentCamera
	cam.CameraType = Enum.CameraType.Custom
	cam.FieldOfView = 70
	if viewGui then
		viewGui:Destroy()
		viewGui = nil
	end
	player:SetAttribute("ViewingTank", false)
	ProximityPromptService.Enabled = true
end

local function openView(plotIndex: number, title: string)
	local map = Workspace:FindFirstChild("Map")
	local plot = map and map:FindFirstChild("Plot" .. plotIndex)
	local box = plot and plot:FindFirstChild("TankInterior") :: BasePart?
	if not box or viewing or player:GetAttribute("Cinematic") then
		return
	end
	viewing = true
	player:SetAttribute("ViewingTank", true)
	ProximityPromptService.Enabled = false -- no prompt bubbles floating over the view
	yaw, pitch, dist = 0, 0.12, 15

	-- overlay: title, what it earns, how to leave
	local g = Instance.new("ScreenGui")
	g.Name = "TankView"
	g.ResetOnSpawn = false
	g.DisplayOrder = 8
	g.Parent = player:WaitForChild("PlayerGui")
	UI.autoScale(g)
	viewGui = g
	local perSecond, n = 0, 0
	local slots = plot:FindFirstChild("Slots")
	if slots then
		for _, m in slots:GetChildren() do
			if not m:GetAttribute("Dead") then
				perSecond += (m:GetAttribute("PerSecond") :: number?) or 0
				n += 1
			end
		end
	end
	-- title pill at the top, hint pill at the bottom, X to leave
	local top = UI.frame(g, { Size = UDim2.fromOffset(460, 76), Position = UDim2.new(0.5, 0, 0, 10), AnchorPoint = Vector2.new(0.5, 0),
		BackgroundColor3 = T.navy, BackgroundTransparency = 0.08 })
	UI.corner(top, UI.R.panel)
	UI.stroke(top, T.line, UI.S.subtle)
	UI.label(top, "value", title, { Size = UDim2.new(1, -32, 0, 34), Position = UDim2.fromOffset(16, 6), TextColor3 = T.gold })
	UI.label(top, "body", n > 0 and ("$%s/s  ·  %d swimming"):format(UI.short(perSecond), n) or "Empty for now", { Size = UDim2.new(1, -32, 0, 24),
		Position = UDim2.fromOffset(16, 42), TextColor3 = n > 0 and C.money or T.mute })
	local hint = UI.frame(g, { Size = UDim2.fromOffset(620, 40), Position = UDim2.new(0.5, 0, 1, -12), AnchorPoint = Vector2.new(0.5, 1),
		BackgroundColor3 = T.navy, BackgroundTransparency = 0.15 })
	UI.corner(hint, 20)
	UI.label(hint, "meta", UI.TOUCH and "Tap a creature to see its name and weight" or "Hover a creature to see its name and weight  ·  drag to look around",
		{ Size = UDim2.new(1, -32, 1, -14), Position = UDim2.fromOffset(16, 7), TextColor3 = UI.light(T.mute, 0.4) })
	UI.button(g, "X", T.red, closeView, { Size = UDim2.fromOffset(56, 56), Position = UDim2.new(1, -12, 0, 10), AnchorPoint = Vector2.new(1, 0) })

	local cam = Workspace.CurrentCamera
	local startCF = cam.CFrame
	cam.CameraType = Enum.CameraType.Scriptable
	local t0 = os.clock()
	local moveTime = 0
	RunService:BindToRenderStep("TankView", Enum.RenderPriority.Camera.Value + 2, function(dt)
		local center = box.Position
		-- behind the back glass (the plaza side), with a slow drift
		local drift = math.sin((os.clock() - t0) * 0.35) * 0.08
		local back = box.CFrame.LookVector * -1
		local dir = (CFrame.Angles(0, yaw + drift, 0) * back)
		local want = CFrame.lookAt(center + dir * dist + Vector3.new(0, math.sin(pitch) * dist, 0), center)
		local k = math.clamp((os.clock() - t0) / 0.6, 0, 1)
		local ease = 1 - (1 - k) ^ 3
		cam.CFrame = startCF:Lerp(want, ease)
		cam.FieldOfView = 70 + (48 - 70) * ease
		-- walking away closes the view
		local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if hum and hum.MoveDirection.Magnitude > 0.1 then
			moveTime += dt
			if moveTime > 0.2 then
				closeView()
			end
		else
			moveTime = 0
		end
	end)
	table.insert(conns, UserInputService.InputBegan:Connect(function(input, processed)
		if input.KeyCode == Enum.KeyCode.Escape or input.KeyCode == Enum.KeyCode.Backspace or input.KeyCode == Enum.KeyCode.ButtonB then
			closeView()
		elseif not processed and (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) then
			dragging = true
		end
	end))
	table.insert(conns, UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end))
	table.insert(conns, UserInputService.InputChanged:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseWheel then
			dist = math.clamp(dist - input.Position.Z * 1.2, 9, 22)
		elseif dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			yaw = math.clamp(yaw - input.Delta.X * 0.006, -0.75, 0.75)
			pitch = math.clamp(pitch + input.Delta.Y * 0.004, -0.05, 0.5)
		end
	end))
	table.insert(conns, UserInputService.TouchPinch:Connect(function(_, scale, _, state)
		if state == Enum.UserInputState.Change then
			dist = math.clamp(dist / math.clamp(scale, 0.9, 1.1), 9, 22)
		end
	end))
	table.insert(conns, player:GetAttributeChangedSignal("Cinematic"):Connect(closeView))
end

----------------------------------------------------------------- start
function TankView.start()
	-- hover (mouse) / tap (touch)
	local lastPick = 0
	RunService.RenderStepped:Connect(function()
		if shown and not shown.Parent then
			hide()
		end
		if UI.TOUCH or os.clock() - lastPick < 0.05 then
			if UI.TOUCH and shown and os.clock() > pinnedUntil then
				hide()
			end
			return
		end
		lastPick = os.clock()
		local m = pick(UserInputService:GetMouseLocation())
		if m then
			show(m)
		elseif shown then
			hide()
		end
	end)
	UserInputService.TouchTap:Connect(function(positions, processed)
		if processed or #positions == 0 then
			return
		end
		local m = pick(positions[1] + GuiService:GetGuiInset(), 40) -- fingers are bigger than cursors
		if m then
			show(m)
			pinnedUntil = os.clock() + 5
		else
			hide()
		end
	end)
	require(script.Parent.Prompts).Triggered:Connect(function(prompt)
		if prompt.Name == "ViewTank" then
			openView(prompt:GetAttribute("Plot") :: number, prompt.ObjectText)
		end
	end)
end

return TankView
