-- Custom look for every ProximityPrompt (Style = Custom), Steal an Egg
-- style: a see-through grey circle holding a white outlined key square
-- ("E", a gamepad button, or TAP on touch), a white ring that fills while
-- you hold, the object name small in grey above the action in bold white,
-- and a clean white outline around the thing you're about to use.
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
local UI = require(script.Parent.UI)

local Prompts = {}
local player = Players.LocalPlayer

Prompts.teach = nil :: string?

-- fires (prompt) when the local player triggers any prompt: real triggers
-- and touch holds finished on the button (see build). Listen here, not to
-- ProximityPromptService, so phones always work.
local triggeredEvent = Instance.new("BindableEvent")
Prompts.Triggered = triggeredEvent.Event
local GOLD = UI.T.gold
local RED = UI.light(UI.T.red, 0.2)

local INK = Color3.fromRGB(40, 40, 46)
local FONT = Enum.Font.BuilderSansBold
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
		s.Color = Color3.new(1, 1, 1) -- white fill ring around the grey circle
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

-- the first grab is a tap; afterwards grabs need their real hold again (the
-- server's value is kept in a client-only attribute on the prompt itself)
local function applyTeach(p: ProximityPrompt)
	if p.Name ~= "GrabPrompt" then
		return
	end
	local base = p:GetAttribute("BaseHold") :: number?
	if Prompts.teach == "tap" then
		if base == nil then
			p:SetAttribute("BaseHold", p.HoldDuration)
		end
		p.HoldDuration = 0
	elseif base ~= nil then
		p.HoldDuration = base
		p:SetAttribute("BaseHold", nil)
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
	gui.Size = UDim2.fromOffset(230, 64 + top)
	gui.SizeOffset = Vector2.new(0.36, 0)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 1, 0)
	gui.LightInfluence = 0
	gui.Adornee = prompt.Parent :: any
	gui.Parent = player:WaitForChild("PlayerGui")

	local scale = Instance.new("UIScale")
	scale.Scale = 0.6
	scale.Parent = gui
	TweenService:Create(scale, TweenInfo.new(0.18, Enum.EasingStyle.Back), { Scale = 1 }):Play()

	-- the navy pill everything sits on
	local pill = Instance.new("Frame")
	pill.Name = "Pill"
	pill.Size = UDim2.new(1, 0, 0, 72)
	pill.Position = UDim2.fromOffset(0, top)
	pill.BackgroundColor3 = UI.T.navy
	pill.BackgroundTransparency = 1 -- no box: just the white key and outlined text (Steal an Egg style)
	pill.BorderSizePixel = 0
	pill.Parent = gui
	corner(pill, 0.5)
	local ps = Instance.new("UIStroke")
	ps.Thickness = 0
	ps.Enabled = false
	ps.Color = UI.T.line
	ps.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	ps.Parent = pill

	local circle = Instance.new(touch and "TextButton" or "Frame") :: GuiObject
	circle.Name = "Circle"
	circle.Size = UDim2.fromOffset(60, 60)
	circle.Position = UDim2.fromOffset(2, 2 + top)
	circle.BackgroundColor3 = Color3.fromRGB(150, 150, 150) -- see-through grey disc
	circle.BackgroundTransparency = 0.45
	circle.ZIndex = 2
	circle.BorderSizePixel = 0
	if circle:IsA("TextButton") then
		circle.Text = ""
		circle.AutoButtonColor = false
	end
	circle.Parent = gui
	corner(circle, 0.5)
	local cs = Instance.new("UIStroke")
	cs.Thickness = 0
	cs.Enabled = false
	cs.Color = INK
	cs.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	cs.Parent = circle
	local setRing = radial(circle)

	local key = Instance.new("TextLabel")
	key.Size = UDim2.fromOffset(32, 32)
	key.AnchorPoint = Vector2.new(0.5, 0.5)
	key.Position = UDim2.fromScale(0.5, 0.5)
	-- the key: a white outlined rounded square with a white letter
	key.BackgroundColor3 = UI.T.white
	key.BackgroundTransparency = 1
	key.Font = FONT
	key.TextColor3 = Color3.new(1, 1, 1)
	key.TextScaled = true
	key.ZIndex = circle.ZIndex + 2
	if touch then
		key.Text = "TAP"
	elseif inputType == Enum.ProximityPromptInputType.Gamepad then
		key.Text = GAMEPAD[prompt.GamepadKeyCode.Name] or prompt.GamepadKeyCode.Name
	else
		key.Text = prompt.KeyboardKeyCode.Name
	end
	key.Parent = circle
	corner(key, nil, 7)
	local ks = Instance.new("UIStroke")
	ks.Thickness = 3
	ks.Color = Color3.new(1, 1, 1)
	ks.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	ks.Parent = key
	local pad = Instance.new("UIPadding")
	local inset = touch and 8 or 7
	pad.PaddingTop = UDim.new(0, inset)
	pad.PaddingBottom = UDim.new(0, inset)
	pad.PaddingLeft = UDim.new(0, touch and 3 or inset)
	pad.PaddingRight = UDim.new(0, touch and 3 or inset)
	pad.Parent = key

	local object = Instance.new("TextLabel")
	object.BackgroundTransparency = 1
	object.Size = UDim2.new(1, -74, 0, 20)
	object.Position = UDim2.fromOffset(70, 9 + top)
	object.Font = FONT
	object.TextColor3 = Color3.fromRGB(200, 200, 200)
	object.ZIndex = 2
	object.TextScaled = true
	object.TextXAlignment = Enum.TextXAlignment.Left
	object.Text = prompt.ObjectText
	object.Parent = gui
	stroke(object, 1.5, Color3.fromRGB(70, 70, 76))

	local action = Instance.new("TextLabel")
	action.BackgroundTransparency = 1
	action.Size = UDim2.new(1, -74, 0, 28)
	action.Position = UDim2.fromOffset(70, 28 + top)
	action.Font = FONT
	action.TextColor3 = UI.T.white
	action.ZIndex = 2
	action.TextScaled = true
	action.TextXAlignment = Enum.TextXAlignment.Left
	action.Text = prompt.ActionText
	action.Parent = gui
	if prompt.ObjectText == "" then
		action.Position = UDim2.fromOffset(70, 18 + top) -- no object name: center the action
	end
	stroke(action, 2, INK)

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
		h.Font = UI.FONT
		h.TextColor3 = GOLD
		h.TextScaled = true
		h.TextXAlignment = Enum.TextXAlignment.Left
		h.Text = idleText
		h.Parent = gui
		stroke(h, UI.S.cta)
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
	if touch then
		-- Touch: the hold runs on the button itself (prompt:InputHoldBegin is
		-- unreliable on some phones). A big invisible hit area covers the whole
		-- card; when the ring fills we trigger: grabs go straight to the server,
		-- everything else fires Prompts.Triggered locally.
		gui.Active = true
		local hit = Instance.new("TextButton")
		hit.Name = "Hit"
		hit.Text = ""
		hit.BackgroundTransparency = 1
		hit.Size = UDim2.new(1, 16, 1, 16)
		hit.Position = UDim2.fromOffset(-8, -8)
		hit.ZIndex = 10
		hit.Parent = gui
		local touchHolding, touchStart, done = false, 0, false
		local function finish()
			done = true
			touchHolding = false
			setRing(1)
			scale.Scale = 1.15
			TweenService:Create(scale, TweenInfo.new(0.2, Enum.EasingStyle.Back), { Scale = 1 }):Play()
			if prompt.Name == "GrabPrompt" then
				local model = prompt:FindFirstAncestorOfClass("Model")
				local id = model and model:GetAttribute("BubbleId")
				if id then
					State.action("grab", id)
				end
				if teach == "hold" and prompt.HoldDuration > 0 then
					Prompts.setTeach(nil)
				end
			end
			triggeredEvent:Fire(prompt)
		end
		local function press()
			if done then
				return
			end
			touchHolding, touchStart = true, os.clock()
			holding, holdStart = true, touchStart
			if prompt.HoldDuration <= 0 then
				finish()
			end
		end
		local function release()
			if touchHolding and not done and hint and prompt.HoldDuration > 0 then
				warnUntil = os.clock() + 1.2
			end
			touchHolding, holding = false, false
			if not done then
				setRing(0)
			end
		end
		table.insert(conns, hit.MouseButton1Down:Connect(press))
		table.insert(conns, hit.MouseButton1Up:Connect(release))
		table.insert(conns, hit.MouseLeave:Connect(release))
		table.insert(conns, hit.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.Touch then
				release()
			end
		end))
		table.insert(conns, RunService.Heartbeat:Connect(function()
			if touchHolding and not done and os.clock() - touchStart >= prompt.HoldDuration then
				finish()
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
	-- (hidden only when your net is full too)
	local busy = d ~= nil and d.carrying ~= nil and (d.bag or 0) + 1 >= (d.netCap or 1)
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
	ProximityPromptService.PromptTriggered:Connect(function(prompt, who)
		if who == player then
			triggeredEvent:Fire(prompt)
		end
	end)
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
