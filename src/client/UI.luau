-- Cartoon UI kit: chunky rounded cards, thick outlines, Fredoka One.

local TweenService = game:GetService("TweenService")

local UI = {}

UI.C = {
	ink = Color3.fromRGB(27, 29, 63),
	white = Color3.fromRGB(255, 255, 255),
	pink = Color3.fromRGB(255, 61, 154),
	blue = Color3.fromRGB(47, 107, 255),
	sky = Color3.fromRGB(76, 195, 255),
	green = Color3.fromRGB(64, 206, 96),
	gold = Color3.fromRGB(255, 200, 40),
	red = Color3.fromRGB(255, 64, 64),
	card = Color3.fromRGB(255, 255, 255),
	mute = Color3.fromRGB(138, 144, 184),
}
UI.FONT = Enum.Font.FredokaOne

function UI.corner(parent: Instance, r: number?)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r or 16)
	c.Parent = parent
	return c
end

function UI.stroke(parent: Instance, color: Color3?, thick: number?)
	local s = Instance.new("UIStroke")
	s.Color = color or UI.C.ink
	s.Thickness = thick or 3
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = parent
	return s
end

function UI.frame(parent: Instance, props: { [string]: any }?): Frame
	local f = Instance.new("Frame")
	f.BackgroundColor3 = UI.C.card
	f.BorderSizePixel = 0
	if props then
		for k, v in props do
			(f :: any)[k] = v
		end
	end
	f.Parent = parent
	return f
end

function UI.text(parent: Instance, text: string, props: { [string]: any }?): TextLabel
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Font = UI.FONT
	t.TextColor3 = UI.C.ink
	t.TextScaled = true
	t.Text = text
	t.Size = UDim2.fromScale(1, 1)
	if props then
		for k, v in props do
			(t :: any)[k] = v
		end
	end
	t.Parent = parent
	return t
end

-- white text with a dark outline: readable over water and sky
function UI.outlined(parent: Instance, text: string, props: { [string]: any }?): TextLabel
	local t = UI.text(parent, text, props)
	t.TextColor3 = (props and props.TextColor3) or UI.C.white
	local s = Instance.new("UIStroke")
	s.Color = UI.C.ink
	s.Thickness = 3
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	s.Parent = t
	return t
end

function UI.button(parent: Instance, text: string, color: Color3, onClick: () -> (), props: { [string]: any }?): TextButton
	local b = Instance.new("TextButton")
	b.AutoButtonColor = false
	b.BackgroundColor3 = color
	b.BorderSizePixel = 0
	b.Font = UI.FONT
	b.TextScaled = true
	b.TextColor3 = UI.C.white
	b.Text = text
	if props then
		for k, v in props do
			(b :: any)[k] = v
		end
	end
	UI.corner(b, 14)
	UI.stroke(b, UI.C.ink, 3)
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0.14, 0)
	pad.PaddingBottom = UDim.new(0.14, 0)
	pad.PaddingLeft = UDim.new(0, 8)
	pad.PaddingRight = UDim.new(0, 8)
	pad.Parent = b
	b.TextStrokeColor3 = UI.C.ink
	b.TextStrokeTransparency = 0.2
	local scale = Instance.new("UIScale")
	scale.Parent = b
	b.MouseButton1Down:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.06), { Scale = 0.92 }):Play()
	end)
	b.MouseButton1Up:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.18, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	end)
	b.MouseLeave:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.12), { Scale = 1 }):Play()
	end)
	b.Activated:Connect(onClick)
	return b
end

function UI.pop(gui: GuiObject, amount: number?)
	local scale = gui:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
	scale.Parent = gui
	scale.Scale = amount or 1.18
	TweenService:Create(scale, TweenInfo.new(0.35, Enum.EasingStyle.Back), { Scale = 1 }):Play()
end

-- endless gentle pulse (for "tap me" moments); returns a stop function
function UI.pulse(gui: GuiObject): () -> ()
	local scale = gui:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
	scale.Parent = gui
	local alive = true
	task.spawn(function()
		while alive and gui.Parent do
			TweenService:Create(scale, TweenInfo.new(0.45, Enum.EasingStyle.Sine), { Scale = 1.08 }):Play()
			task.wait(0.45)
			TweenService:Create(scale, TweenInfo.new(0.45, Enum.EasingStyle.Sine), { Scale = 1 }):Play()
			task.wait(0.45)
		end
	end)
	return function()
		alive = false
		scale.Scale = 1
	end
end

function UI.short(n: number): string
	local units = { "", "K", "M", "B", "T", "Qa", "Qi" }
	local i = 1
	while math.abs(n) >= 1000 and i < #units do
		n /= 1000
		i += 1
	end
	if i == 1 then
		return tostring(math.floor(n))
	end
	local s = string.format(n >= 100 and "%.0f" or "%.1f", n)
	s = s:gsub("%.0$", "")
	return s .. units[i]
end

function UI.time(sec: number): string
	sec = math.max(0, math.floor(sec))
	return string.format("%d:%02d", sec // 60, sec % 60)
end

return UI
