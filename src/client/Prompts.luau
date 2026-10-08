-- Custom look for every ProximityPrompt (Style = Custom): a dark circle with
-- the key ("E", a gamepad button, or tap on touch), a white ring that fills
-- while you hold, the object name in grey and the action in bold white, and
-- a clean white outline around the thing you're about to use.
--
-- Grab prompts also teach (Onboarding sets Prompts.setTeach):
--   "tap"   the very first grab: no hold at all (local HoldDuration 0) and a
--           big pulsing "TAP!" / "PRESS E!"
--   "hold"  until your first held grab: "HOLD!" over a pulsing ghost ring;
--           letting go too early says "KEEP HOLDING!"

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local State = require(script.Parent.State)

local Prompts = {}
local player = Players.LocalPlayer

Prompts.teach = nil :: string?
local origHold: { [ProximityPrompt]: number } = setmetatable({}, { __mode = "k" }) :: any
local GOLD = Color3.fromRGB(255, 214, 64)
local RED = Color3.fromRGB(255, 92, 92)

local INK = Color3.fromRGB(22, 22, 34)
local GAMEPAD = {
	ButtonX = "X", ButtonY = "Y", ButtonA = "A", ButtonB = "B",
	ButtonL1 = "LB", ButtonR1 = "RB", ButtonL2 = "LT", ButtonR2 = "RT",
}

local function stroke(parent: Instance, thick: number, color: Color3?)
	local s = Instance.new("UIStroke")
	s.Thickness = thick
	s.Color = color or INK
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	s.Parent = parent
	return s
end

local function corner(parent: Instance, scale: number?, px: number?)
	local c = Instance.new("UICorner")
	c.CornerRadius = scale and UDim.new(scale, 0) or UDim.new(0, px or 8)
	c.Parent = parent
end

-- a ring that fills clockwise from the top: two clipped halves whose stroke
-- gradients rotate (no images needed). A Border stroke draws OUTSIDE its
-- frame, so the ring is inset by the stroke width: the whole circle stays
-- inside the clipping halves (otherwise only the diagonals show).
local RING = 4
local function radial(parent: GuiObject): (number) -> ()
	local halves = {}
	for i, spec in { { pos = UDim2.fromScale(0.5, 0), ring = UDim2.new(-1, RING, 0, RING) }, { pos = UDim2.fromScale(0, 0), ring = UDim2.fromOffset(RING, RING) } } do
		local clip = Instance.new("Frame")
		clip.BackgroundTransparency = 1
		clip.ClipsDescendants = true
		clip.Size = UDim2.fromScale(0.5, 1)
		clip.Position = spec.pos
		clip.ZIndex = parent.ZIndex + 1
		clip.Parent = parent
		local ring = Instance.new("Frame")
		ring.BackgroundTransparency = 1
		ring.Size = UDim2.new(2, -2 * RING, 1, -2 * RING)
		ring.Position = spec.ring
		ring.ZIndex = clip.ZIndex
		ring.Parent = clip
		corner(ring, 0.5)
		local s = Instance.new("UIStroke")
		s.Thickness = RING
		s.Color = Color3.new(1, 1, 1)
		s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		s.Parent = ring
		local g = Instance.new("UIGradient")
		g.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.499, 0),
			NumberSequenceKeypoint.new(0.5, 1), NumberSequenceKeypoint.new(1, 1),
		})
		g.Parent = s
		halves[i] = g
	end
	local function set(p: number)
		p = math.clamp(p, 0, 1)
		halves[1].Rotation = 180 * math.clamp(p * 2, 0, 1) -- right half: 0..50%
		halves[2].Rotation = 180 + 180 * math.clamp((p - 0.5) * 2, 0, 1) -- left half: 50..100%
	end
	set(0)
	return set
end

local function modelOf(prompt: ProximityPrompt): Instance?
	local p = prompt.Parent
	if not p then
		return nil
	end
	return p:FindFirstAncestorOfClass("Model") or p
end

-- the first grab is a tap; afterwards grabs need their real hold again
local function applyTeach(p: ProximityPrompt)
	if p.Name ~= "GrabPrompt" then
		return
	end
	if Prompts.teach == "tap" then
		if origHold[p] == nil then
			origHold[p] = p.HoldDuration
		end
		p.HoldDuration = 0
	elseif origHold[p] ~= nil then
		p.HoldDuration = origHold[p]
		origHold[p] = nil
	end
end

function Prompts.setTeach(mode: string?)
	if Prompts.teach == mode then
		return
	end
	Prompts.teach = mode
	local folder = Workspace:FindFirstChild("Bubbles")
	if folder then
		for _, p in folder:GetDescendants() do
			if p:IsA("ProximityPrompt") then
				applyTeach(p)
			end
		end
	end
end

local function build(prompt: ProximityPrompt, inputType: Enum.ProximityPromptInputType): () -> ()
	local touch = inputType == Enum.ProximityPromptInputType.Touch
	local teach = prompt.Name == "GrabPrompt" and Prompts.teach or nil
	local top = teach and 40 or 0 -- room for the TAP!/HOLD! hint above
	local gui = Instance.new("BillboardGui")
	gui.Name = "Prompt"
	gui.AlwaysOnTop = true
	gui.Size = UDim2.fromOffset(250, 72 + top)
	gui.SizeOffset = Vector2.new(0.36, 0)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 1, 0)
	gui.LightInfluence = 0
	gui.Adornee = prompt.Parent :: any
	gui.Parent = player:WaitForChild("PlayerGui")

	local scale = Instance.new("UIScale")
	scale.Scale = 0.6
	scale.Parent = gui
	TweenService:Create(scale, TweenInfo.new(0.18, Enum.EasingStyle.Back), { Scale = 1 }):Play()

	local circle = Instance.new(touch and "TextButton" or "Frame") :: GuiObject
	circle.Name = "Circle"
	circle.Size = UDim2.fromOffset(64, 64)
	circle.Position = UDim2.fromOffset(4, 4 + top)
	circle.BackgroundColor3 = Color3.fromRGB(40, 40, 48)
	circle.BackgroundTransparency = 0.3
	circle.BorderSizePixel = 0
	if circle:IsA("TextButton") then
		circle.Text = ""
		circle.AutoButtonColor = false
	end
	circle.Parent = gui
	corner(circle, 0.5)
	local setRing = radial(circle)

	local key = Instance.new("TextLabel")
	key.Size = UDim2.fromOffset(34, 34)
	key.AnchorPoint = Vector2.new(0.5, 0.5)
	key.Position = UDim2.fromScale(0.5, 0.5)
	key.BackgroundColor3 = Color3.fromRGB(30, 30, 36)
	key.BackgroundTransparency = 0.4
	key.Font = Enum.Font.GothamBold
	key.TextColor3 = Color3.new(1, 1, 1)
	key.TextScaled = true
	key.ZIndex = circle.ZIndex + 2
	if touch then
		key.Text = "👆"
	elseif inputType == Enum.ProximityPromptInputType.Gamepad then
		key.Text = GAMEPAD[prompt.GamepadKeyCode.Name] or prompt.GamepadKeyCode.Name
	else
		key.Text = prompt.KeyboardKeyCode.Name
	end
	key.Parent = circle
	corner(key, nil, 8)
	local ks = Instance.new("UIStroke")
	ks.Thickness = 2.5
	ks.Color = Color3.new(1, 1, 1)
	ks.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	ks.Parent = key
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 5)
	pad.PaddingBottom = UDim.new(0, 5)
	pad.PaddingLeft = UDim.new(0, 5)
	pad.PaddingRight = UDim.new(0, 5)
	pad.Parent = key

	local object = Instance.new("TextLabel")
	object.BackgroundTransparency = 1
	object.Size = UDim2.new(1, -82, 0, 22)
	object.Position = UDim2.fromOffset(80, 8 + top)
	object.Font = Enum.Font.GothamBold
	object.TextColor3 = Color3.fromRGB(205, 205, 210)
	object.TextScaled = true
	object.TextXAlignment = Enum.TextXAlignment.Left
	object.Text = prompt.ObjectText
	object.Parent = gui
	stroke(object, 1.5)

	local action = Instance.new("TextLabel")
	action.BackgroundTransparency = 1
	action.Size = UDim2.new(1, -82, 0, 32)
	action.Position = UDim2.fromOffset(80, 30 + top)
	action.Font = Enum.Font.GothamBlack
	action.TextColor3 = Color3.new(1, 1, 1)
	action.TextScaled = true
	action.TextXAlignment = Enum.TextXAlignment.Left
	action.Text = prompt.ActionText
	action.Parent = gui
	stroke(action, 2.5)

	-- tutorial hint over the button, and a ghost ring showing where to hold
	local hint: TextLabel? = nil
	local ghost: UIStroke? = nil
	local hintScale: UIScale? = nil
	local idleText = ""
	if teach then
		idleText = teach == "tap" and (touch and "TAP!" or ("PRESS " .. key.Text .. "!")) or "HOLD!"
		local h = Instance.new("TextLabel")
		h.BackgroundTransparency = 1
		h.Size = UDim2.fromOffset(240, 36)
		h.Position = UDim2.fromOffset(0, 0)
		h.Font = Enum.Font.GothamBlack
		h.TextColor3 = GOLD
		h.TextScaled = true
		h.TextXAlignment = Enum.TextXAlignment.Left
		h.Text = idleText
		h.Parent = gui
		stroke(h, 3)
		hintScale = Instance.new("UIScale")
		hintScale.Parent = h
		hint = h
		action.Text = teach == "tap" and (touch and "Tap to grab" or "Press to grab") or "Hold to grab"
		if teach == "hold" then
			local g = Instance.new("Frame")
			g.BackgroundTransparency = 1
			g.Size = UDim2.new(1, -2 * RING, 1, -2 * RING)
			g.Position = UDim2.fromOffset(RING, RING)
			g.ZIndex = circle.ZIndex
			g.Parent = circle
			corner(g, 0.5)
			ghost = stroke(g, RING, Color3.new(1, 1, 1))
			ghost.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		end
	end
	local warnUntil = 0

	-- outline what you're about to use
	local target = modelOf(prompt)
	local hl: Highlight? = nil
	if target then
		hl = Instance.new("Highlight")
		hl.FillTransparency = 1
		hl.OutlineColor = Color3.new(1, 1, 1)
		hl.OutlineTransparency = 0
		hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		hl.Adornee = target
		hl.Parent = target -- local-only child; removed when the prompt hides
	end

	-- hold progress
	local holding = false
	local holdStart = 0
	local conns = {}
	table.insert(conns, prompt.PromptButtonHoldBegan:Connect(function()
		holding = true
		holdStart = os.clock()
	end))
	table.insert(conns, prompt.PromptButtonHoldEnded:Connect(function()
		-- let go before it filled: say so (Triggered comes first when it did)
		if holding and hint and prompt.HoldDuration > 0 and os.clock() - holdStart < prompt.HoldDuration then
			warnUntil = os.clock() + 1.2
		end
		holding = false
		setRing(0)
	end))
	table.insert(conns, prompt.Triggered:Connect(function()
		holding = false
		setRing(1)
		scale.Scale = 1.15
		TweenService:Create(scale, TweenInfo.new(0.2, Enum.EasingStyle.Back), { Scale = 1 }):Play()
		-- first held grab done: no more hold lessons
		if teach == "hold" and prompt.HoldDuration > 0 then
			Prompts.setTeach(nil)
		end
	end))
	table.insert(conns, RunService.RenderStepped:Connect(function()
		if holding then
			local dur = math.max(prompt.HoldDuration, 0.01)
			setRing((os.clock() - holdStart) / dur)
		end
		if hint and hintScale then
			local pulse = 0.5 + 0.5 * math.sin(os.clock() * 7)
			local warn = os.clock() < warnUntil
			hint.Text = warn and "KEEP HOLDING!" or (holding and "KEEP HOLDING..." or idleText)
			hint.TextColor3 = warn and RED or GOLD
			hintScale.Scale = holding and 1 or 1 + 0.12 * pulse
			if ghost then
				ghost.Transparency = holding and 1 or 0.35 + 0.45 * pulse
			end
		end
	end))
	if circle:IsA("TextButton") then
		-- touch: press and hold the circle
		table.insert(conns, circle.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
				prompt:InputHoldBegin()
			end
		end))
		table.insert(conns, circle.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
				prompt:InputHoldEnd()
			end
		end))
	end

	return function()
		for _, c in conns do
			c:Disconnect()
		end
		if hl then
			hl:Destroy()
		end
		gui:Destroy()
	end
end

-- grab prompts hide while your hands are full
local function syncGrabPrompts()
	local d = State.data
	local busy = d ~= nil and d.carrying ~= nil
	local folder = Workspace:FindFirstChild("Bubbles")
	if not folder then
		return
	end
	for _, p in folder:GetDescendants() do
		if p:IsA("ProximityPrompt") and p.Name == "GrabPrompt" then
			p.Enabled = not busy
		end
	end
end

function Prompts.start()
	local open: { [ProximityPrompt]: () -> () } = {}
	ProximityPromptService.PromptShown:Connect(function(prompt, inputType)
		if prompt.Style ~= Enum.ProximityPromptStyle.Custom then
			return
		end
		if open[prompt] then
			open[prompt]()
		end
		applyTeach(prompt)
		open[prompt] = build(prompt, inputType)
	end)
	ProximityPromptService.PromptHidden:Connect(function(prompt)
		local close = open[prompt]
		if close then
			open[prompt] = nil
			close()
		end
	end)
	State.Changed:Connect(syncGrabPrompts)
	task.spawn(function()
		while true do
			task.wait(0.5)
			syncGrabPrompts()
		end
	end)
end

return Prompts
