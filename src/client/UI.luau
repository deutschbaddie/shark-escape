-- Cartoon UI kit in the classic simulator look: studded, gradient-lit buttons
-- with a thick dark outline, bold outlined text, dark panels with a bright
-- studded header bar and a red X.

local TweenService = game:GetService("TweenService")

local Config = require(game.ReplicatedStorage.Shared.Config)

local UI = {}
-- sound hooks (set by Audio.luau)
UI.onClick = nil :: (() -> ())?
UI.onOpen = nil :: (() -> ())?
UI.onClose = nil :: (() -> ())?

UI.C = {
	ink = Color3.fromRGB(22, 22, 34),
	white = Color3.fromRGB(255, 255, 255),
	pink = Color3.fromRGB(255, 70, 170),
	blue = Color3.fromRGB(30, 120, 255),
	sky = Color3.fromRGB(40, 200, 255),
	index = Color3.fromRGB(35, 165, 255),
	green = Color3.fromRGB(78, 206, 48),
	money = Color3.fromRGB(120, 255, 70),
	gold = Color3.fromRGB(255, 196, 30),
	orange = Color3.fromRGB(255, 130, 30),
	red = Color3.fromRGB(235, 40, 40),
	purple = Color3.fromRGB(160, 80, 255),
	panel = Color3.fromRGB(48, 50, 60),
	panel2 = Color3.fromRGB(32, 34, 42),
	card = Color3.fromRGB(255, 255, 255),
	mute = Color3.fromRGB(130, 136, 150),
}
UI.FONT = Enum.Font.FredokaOne
UI.NUMFONT = Enum.Font.LuckiestGuy

local function apply(inst: Instance, props: { [string]: any }?)
	if props then
		for k, v in props do
			(inst :: any)[k] = v
		end
	end
end

-- One scale for every screen: everything is designed on a 1280x720 canvas
-- and scaled so that canvas always fits the device (phone, tablet, PC, TV).
-- Phones get a little extra so thumbs can hit things. The ScreenGui keeps
-- the notch/topbar-safe area.
UI.BASE = Vector2.new(1280, 720)
local UserInputService = game:GetService("UserInputService")
UI.TOUCH = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
-- `fit` (design units) = the biggest window this gui shows: the scale is
-- capped so it always fits on screen (phones get the boost only if it fits)
function UI.autoScale(gui: ScreenGui, fit: Vector2?): UIScale
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	local scale = Instance.new("UIScale")
	scale.Parent = gui
	local function rescale()
		local v = gui.AbsoluteSize
		if v.X < 2 or v.Y < 2 then
			v = workspace.CurrentCamera.ViewportSize
		end
		local k = math.min(v.X / UI.BASE.X, v.Y / UI.BASE.Y)
		if UI.TOUCH and v.Y < 600 then
			k *= 1.4 -- phones: bigger touch targets and readable text (the layout leaves room)
		end
		if fit then
			k = math.min(k, v.X * 0.96 / fit.X, v.Y * 0.94 / fit.Y)
		end
		scale.Scale = math.clamp(k, 0.4, 1.6)
	end
	rescale()
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(rescale)
	local cam = workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(rescale)
	gui.Destroying:Connect(function()
		cam:Disconnect()
	end)
	return scale
end

function UI.corner(parent: Instance, r: number?)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r or 10)
	c.Parent = parent
	return c
end

function UI.stroke(parent: Instance, color: Color3?, thick: number?)
	local s = Instance.new("UIStroke")
	s.Color = color or UI.C.ink
	s.Thickness = thick or 3
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.LineJoinMode = Enum.LineJoinMode.Round
	s.Parent = parent
	return s
end

-- light top, darker bottom: makes flat colors read as chunky plastic
function UI.shade(parent: Instance, rotation: number?)
	local g = Instance.new("UIGradient")
	g.Rotation = rotation or 90
	g.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
		ColorSequenceKeypoint.new(0.55, Color3.fromRGB(235, 235, 235)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(175, 175, 175)),
	})
	g.Parent = parent
	return g
end

-- Stud overlay. Uses a tiled image if Config.Images.Studs is set, otherwise
-- draws soft circles (capped so big panels stay cheap).
function UI.studs(parent: GuiObject, opts: { size: number?, alpha: number?, z: number? }?)
	local o = opts or {}
	local size = o.size or 22
	local alpha = o.alpha or 0.78
	local holder = Instance.new("Frame")
	holder.Name = "Studs"
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.fromScale(1, 1)
	holder.ClipsDescendants = true
	holder.ZIndex = o.z or parent.ZIndex
	holder.Parent = parent
	if Config.Images.Studs ~= "" then
		local img = Instance.new("ImageLabel")
		img.BackgroundTransparency = 1
		img.Size = UDim2.fromScale(1, 1)
		img.Image = Config.Images.Studs
		img.ScaleType = Enum.ScaleType.Tile
		img.TileSize = UDim2.fromOffset(size * 4, size * 4) -- the image is a 4x4 grid of studs
		img.ImageTransparency = alpha
		img.ZIndex = holder.ZIndex
		img.Parent = holder
		return holder
	end
	local function draw()
		holder:ClearAllChildren()
		local abs = parent.AbsoluteSize
		if abs.X < 4 or abs.Y < 4 then
			return
		end
		local step = size
		while (abs.X / step) * (abs.Y / step) > 90 do
			step *= 1.25
		end
		local d = step * 0.5
		for y = step / 2, abs.Y, step do
			for x = step / 2, abs.X, step do
				local s = Instance.new("Frame")
				s.BorderSizePixel = 0
				s.Size = UDim2.fromOffset(d, d)
				s.AnchorPoint = Vector2.new(0.5, 0.5)
				s.Position = UDim2.fromOffset(x, y)
				s.BackgroundColor3 = Color3.new(1, 1, 1)
				s.BackgroundTransparency = alpha
				s.ZIndex = holder.ZIndex
				local c = Instance.new("UICorner")
				c.CornerRadius = UDim.new(0.5, 0)
				c.Parent = s
				local g = Instance.new("UIGradient")
				g.Rotation = 90
				g.Transparency = NumberSequence.new(0, 0.7)
				g.Parent = s
				s.Parent = holder
			end
		end
	end
	local last = Vector2.zero
	parent:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		local now = parent.AbsoluteSize
		if (now - last).Magnitude > 6 then
			last = now
			draw()
		end
	end)
	task.defer(draw)
	return holder
end

function UI.frame(parent: Instance, props: { [string]: any }?): Frame
	local f = Instance.new("Frame")
	f.BackgroundColor3 = UI.C.card
	f.BorderSizePixel = 0
	apply(f, props)
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
	apply(t, props)
	t.Parent = parent
	return t
end

-- white text with a thick dark outline: readable over anything
function UI.outlined(parent: Instance, text: string, props: { [string]: any }?): TextLabel
	local t = UI.text(parent, text, props)
	t.TextColor3 = (props and props.TextColor3) or UI.C.white
	local s = Instance.new("UIStroke")
	s.Color = UI.C.ink
	s.Thickness = (props and props.TextSize and props.TextSize > 30) and 4 or 3
	s.LineJoinMode = Enum.LineJoinMode.Round
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	s.Parent = t
	return t
end

-- press feedback for anything clickable
local function squish(b: GuiButton)
	local scale = Instance.new("UIScale")
	scale.Parent = b
	b.MouseButton1Down:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.06), { Scale = 0.92 }):Play()
	end)
	b.MouseButton1Up:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.2, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	end)
	b.MouseEnter:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.12), { Scale = 1.05 }):Play()
	end)
	b.MouseLeave:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.12), { Scale = 1 }):Play()
	end)
end

-- The chunky studded button. Text lives in a child "Label" (UI.setText).
function UI.button(parent: Instance, text: string, color: Color3, onClick: () -> (), props: { [string]: any }?): TextButton
	local b = Instance.new("TextButton")
	b.AutoButtonColor = false
	b.BackgroundColor3 = color
	b.BorderSizePixel = 0
	b.Text = ""
	b.Size = UDim2.fromOffset(160, 50)
	apply(b, props)
	UI.corner(b, 10)
	UI.stroke(b, UI.C.ink, 3)
	UI.shade(b)
	UI.studs(b, { size = 20, alpha = 0.82 })
	-- bottom lip
	local lip = UI.frame(b, { Name = "Lip", Size = UDim2.new(1, 0, 0, 6), Position = UDim2.fromScale(0, 1), AnchorPoint = Vector2.new(0, 1),
		BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.72 })
	UI.corner(lip, 10)
	UI.outlined(b, text, { Name = "Label", Size = UDim2.new(1, -14, 1, -14), Position = UDim2.new(0.5, 0, 0.5, -2), AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = b.ZIndex + 1 })
	squish(b)
	b.Activated:Connect(function(...)
		if UI.onClick then
			UI.onClick()
		end
		onClick(...)
	end)
	b.Parent = parent
	return b
end

function UI.setText(b: GuiObject, text: string)
	local l = b:FindFirstChild("Label") :: TextLabel?
	if l then
		l.Text = text
	end
end

function UI.recolor(b: GuiObject, color: Color3)
	b.BackgroundColor3 = color
end

-- One of the game's icons by name (Config.Icons). Draws from the uploaded
-- sheet when its id is set, otherwise falls back to the emoji.
-- Sheet ids can be typed as 123, "123" or "rbxassetid://123". If it was a
-- decal id, the server swaps in the real image id (IconSheets.luau) via a
-- ReplicatedStorage attribute; existing icons update when it arrives.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local sheetImages: { [string]: { ImageLabel } } = { A = {}, B = {} }

local function sheetId(which: string): string
	local resolved = ReplicatedStorage:GetAttribute("IconSheet" .. which)
	if typeof(resolved) == "string" and resolved ~= "" then
		return resolved
	end
	local raw = tostring(Config.Icons["Sheet" .. which] or "")
	local digits = raw:match("%d+")
	return digits and ("rbxassetid://" .. digits) or ""
end

for _, which in { "A", "B" } do
	ReplicatedStorage:GetAttributeChangedSignal("IconSheet" .. which):Connect(function()
		local id = sheetId(which)
		for _, img in sheetImages[which] do
			if img.Parent then
				img.Image = id
			end
		end
	end)
end

-- A fish tank drawn from frames: the Tank icon until an image is uploaded
local function drawTank(): Frame
	local f = Instance.new("Frame")
	f.BackgroundTransparency = 1
	local box = UI.frame(f, { Size = UDim2.fromScale(0.92, 0.72), Position = UDim2.fromScale(0.5, 0.95), AnchorPoint = Vector2.new(0.5, 1),
		BackgroundColor3 = Color3.fromRGB(70, 190, 255) })
	UI.corner(box, 5)
	UI.stroke(box, UI.C.ink, 2.5)
	local g = Instance.new("UIGradient")
	g.Rotation = 90
	g.Color = ColorSequence.new(Color3.fromRGB(120, 225, 255), Color3.fromRGB(30, 120, 230))
	g.Parent = box
	UI.frame(box, { Size = UDim2.new(1, 0, 0.16, 0), Position = UDim2.fromScale(0, 0.84), BackgroundColor3 = Color3.fromRGB(255, 214, 120) })
	-- fish: body + tail + eye
	local fish = UI.frame(box, { Size = UDim2.fromScale(0.42, 0.34), Position = UDim2.fromScale(0.44, 0.4), AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = Color3.fromRGB(255, 140, 30) })
	UI.corner(fish, 100)
	UI.stroke(fish, UI.C.ink, 1.5)
	local tail = UI.frame(box, { Size = UDim2.fromScale(0.16, 0.24), Position = UDim2.fromScale(0.72, 0.4), AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = Color3.fromRGB(255, 140, 30), Rotation = 45 })
	UI.stroke(tail, UI.C.ink, 1.5)
	UI.frame(fish, { Size = UDim2.fromScale(0.16, 0.26), Position = UDim2.fromScale(0.22, 0.3), BackgroundColor3 = UI.C.ink })
	for i, p in { Vector2.new(0.22, 0.2), Vector2.new(0.3, 0.08) } do
		local b = UI.frame(box, { Size = UDim2.fromScale(i == 1 and 0.1 or 0.07, i == 1 and 0.13 or 0.09), Position = UDim2.fromScale(p.X, p.Y),
			BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.2 })
		UI.corner(b, 100)
	end
	-- lid
	local lid = UI.frame(f, { Size = UDim2.fromScale(1, 0.14), Position = UDim2.fromScale(0.5, 0.2), AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = Color3.fromRGB(60, 64, 80) })
	UI.corner(lid, 4)
	UI.stroke(lid, UI.C.ink, 2.5)
	return f
end

function UI.icon(parent: Instance, name: string, props: { [string]: any }?): GuiObject
	local icons = Config.Icons
	local single = tostring(icons.ids and icons.ids[name] or ""):match("%d+")
	local cell = icons.cells[name]
	local sheet = cell and sheetId(cell[1]) or ""
	local obj: GuiObject
	if single then
		local img = Instance.new("ImageLabel")
		img.BackgroundTransparency = 1
		local function apply()
			-- the server swaps in the real image id if a decal id was pasted
			local resolved = ReplicatedStorage:GetAttribute("Icon_" .. name)
			img.Image = typeof(resolved) == "string" and resolved or ("rbxassetid://" .. single)
		end
		apply()
		ReplicatedStorage:GetAttributeChangedSignal("Icon_" .. name):Connect(apply)
		img.ScaleType = Enum.ScaleType.Fit
		obj = img
	elseif name == "Tank" and sheet == "" then
		obj = drawTank()
	elseif cell and sheet ~= "" then
		local img = Instance.new("ImageLabel")
		img.BackgroundTransparency = 1
		img.Image = sheet
		img.ImageRectSize = Vector2.new(256, 256)
		img.ImageRectOffset = Vector2.new(((cell[2] - 1) % 4) * 256, math.floor((cell[2] - 1) / 4) * 256)
		img.ScaleType = Enum.ScaleType.Fit
		table.insert(sheetImages[cell[1]], img)
		obj = img
	else
		-- no image yet (upload the icon sheets): leave the spot empty, never an emoji
		local f = Instance.new("Frame")
		f.BackgroundTransparency = 1
		obj = f
	end
	obj.Name = "Icon"
	obj.Size = UDim2.fromScale(1, 1)
	apply(obj, props)
	obj.Parent = parent
	return obj
end

-- square icon button with a caption (left-side menu); icon is an icon name
function UI.iconButton(parent: Instance, icon: string, caption: string, color: Color3, onClick: () -> (), props: { [string]: any }?): TextButton
	local b = UI.button(parent, "", color, onClick, props)
	if caption == "" then
		-- icon only (the small Steal-an-Egg squares)
		UI.icon(b, icon, { Size = UDim2.fromScale(0.74, 0.74), Position = UDim2.fromScale(0.5, 0.47), AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = b.ZIndex + 1 })
		return b
	end
	UI.icon(b, icon, { Size = UDim2.fromScale(0.74, 0.62), Position = UDim2.fromScale(0.5, 0.02), AnchorPoint = Vector2.new(0.5, 0), ZIndex = b.ZIndex + 1 })
	local l = b:FindFirstChild("Label") :: TextLabel
	l.Text = caption
	l.Size = UDim2.new(1, -6, 0.3, 0)
	l.Position = UDim2.new(0.5, 0, 1, -6)
	l.AnchorPoint = Vector2.new(0.5, 1)
	return b
end

-- wide menu button: icon on the left, big label (the "🛒 Shop" style)
function UI.wideButton(parent: Instance, icon: string, caption: string, color: Color3, onClick: () -> (), props: { [string]: any }?): TextButton
	local b = UI.button(parent, caption, color, onClick, props)
	UI.icon(b, icon, { Size = UDim2.new(0.3, 0, 1, -12), Position = UDim2.new(0, 8, 0.5, -2), AnchorPoint = Vector2.new(0, 0.5), ZIndex = b.ZIndex + 1 })
	local l = b:FindFirstChild("Label") :: TextLabel
	l.Size = UDim2.new(0.66, -14, 0.56, 0)
	l.Position = UDim2.new(0.34, 6, 0.5, -2)
	l.AnchorPoint = Vector2.new(0, 0.5)
	l.TextXAlignment = Enum.TextXAlignment.Left
	return b
end

-- square on/off box with a caption to its right (Slow Mode). returns setter
function UI.toggle(parent: Instance, caption: string, on: boolean, onChange: (boolean) -> (), props: { [string]: any }?): (Frame, (boolean) -> ())
	local holder = UI.frame(parent, { Size = UDim2.fromOffset(172, 40), BackgroundTransparency = 1 })
	apply(holder, props)
	local box = Instance.new("TextButton")
	box.AutoButtonColor = false
	box.Text = ""
	box.Size = UDim2.fromOffset(40, 40)
	box.BorderSizePixel = 0
	box.Parent = holder
	UI.corner(box, 8)
	UI.stroke(box, UI.C.ink, 3)
	UI.shade(box)
	local tick = UI.outlined(box, "✓", { Size = UDim2.new(1, -8, 1, -8), Position = UDim2.fromOffset(4, 3) })
	local label = UI.outlined(holder, caption, { Size = UDim2.new(1, -48, 0, 24), Position = UDim2.new(0, 48, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5), TextXAlignment = Enum.TextXAlignment.Left })
	local state = on
	local function set(v: boolean)
		state = v
		box.BackgroundColor3 = v and UI.C.green or Color3.fromRGB(150, 156, 166)
		tick.Visible = v
		label.TextColor3 = v and UI.C.white or Color3.fromRGB(225, 228, 235)
	end
	set(on)
	squish(box)
	box.Activated:Connect(function()
		set(not state)
		onChange(state)
	end)
	return holder, set
end

-- red "!" bubble on a button's corner
function UI.badge(b: GuiObject, text: string?): Frame
	local old = b:FindFirstChild("Badge")
	if old then
		local t = old:FindFirstChildOfClass("TextLabel")
		if t and t.Text == (text or "!") then
			return old :: Frame
		end
		old:Destroy()
	end
	local f = UI.frame(b, { Name = "Badge", Size = UDim2.fromOffset(24, 24), Position = UDim2.new(1, 6, 0, -7), AnchorPoint = Vector2.new(1, 0),
		BackgroundColor3 = UI.C.red, ZIndex = b.ZIndex + 3 })
	UI.corner(f, 12)
	UI.stroke(f, UI.C.white, 2.5)
	UI.outlined(f, text or "!", { Size = UDim2.new(1, -6, 1, -6), Position = UDim2.fromOffset(3, 3), ZIndex = f.ZIndex + 1 })
	UI.pop(f, 1.5)
	return f
end

function UI.clearBadge(b: GuiObject)
	local old = b:FindFirstChild("Badge")
	if old then
		old:Destroy()
	end
end

-- dark panel with a studded color header, title and red X.
-- returns (frame, body, closeButton)
function UI.window(parent: Instance, title: string, color: Color3, size: Vector2, onClose: () -> (), iconName: string?): (Frame, Frame, TextButton)
	local f = UI.frame(parent, { Name = "Window", Size = UDim2.fromOffset(size.X, size.Y), Position = UDim2.fromScale(0.5, 0.52),
		AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = UI.C.panel })
	UI.corner(f, 12)
	UI.stroke(f, UI.C.ink, 5)
	UI.studs(f, { size = 26, alpha = 0.94 })
	local head = UI.frame(f, { Name = "Head", Size = UDim2.new(1, -12, 0, 62), Position = UDim2.fromOffset(6, 6), BackgroundColor3 = color, ClipsDescendants = true })
	UI.corner(head, 8)
	UI.stroke(head, UI.C.ink, 3)
	UI.shade(head)
	UI.studs(head, { size = 18, alpha = 0.8 })
	-- diagonal shine stripes
	for i, x in { 0.55, 0.64 } do
		UI.frame(head, { Size = UDim2.new(0, i == 1 and 46 or 22, 2.4, 0), Position = UDim2.fromScale(x, -0.7), Rotation = 35,
			BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.72 })
	end
	local tx = 18
	if iconName then
		UI.icon(head, iconName, { Size = UDim2.fromOffset(58, 58), Position = UDim2.fromOffset(10, 2), ZIndex = head.ZIndex + 2 })
		tx = 74
	end
	UI.outlined(head, title, { Name = "Title", Size = UDim2.new(1, -96 - tx, 0, 46), Position = UDim2.fromOffset(tx, 8), TextXAlignment = Enum.TextXAlignment.Left })
	local x = UI.button(f, "X", UI.C.red, function()
		if UI.onClose then
			UI.onClose()
		end
		onClose()
	end, { Name = "Close", Size = UDim2.fromOffset(62, 62), Position = UDim2.new(1, -6, 0, 6), AnchorPoint = Vector2.new(1, 0) })
	if UI.onOpen then
		UI.onOpen()
	end
	local body = UI.frame(f, { Name = "Body", Size = UDim2.new(1, -24, 1, -86), Position = UDim2.fromOffset(12, 76), BackgroundTransparency = 1 })
	UI.pop(f, 0.85)
	return f, body, x
end

-- inset darker panel inside a window
function UI.inset(parent: Instance, props: { [string]: any }?): Frame
	local f = UI.frame(parent, { BackgroundColor3 = UI.C.panel2 })
	apply(f, props)
	UI.corner(f, 8)
	UI.stroke(f, UI.C.ink, 3)
	return f
end

-- studded progress bar; returns (back, fill, label)
function UI.bar(parent: Instance, color: Color3, props: { [string]: any }?): (Frame, Frame, TextLabel)
	local back = UI.frame(parent, { BackgroundColor3 = Color3.fromRGB(20, 22, 30) })
	apply(back, props)
	UI.corner(back, 8)
	UI.stroke(back, UI.C.ink, 3)
	local fill = UI.frame(back, { Name = "Fill", Size = UDim2.fromScale(0, 1), BackgroundColor3 = color })
	UI.corner(fill, 8)
	UI.shade(fill)
	UI.studs(fill, { size = 16, alpha = 0.8 })
	local label = UI.outlined(back, "", { Size = UDim2.new(1, -16, 1, -8), Position = UDim2.fromOffset(8, 4), ZIndex = back.ZIndex + 2 })
	return back, fill, label
end

function UI.pop(gui: GuiObject, amount: number?)
	local scale = gui:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
	scale.Parent = gui
	scale.Scale = amount or 1.18
	TweenService:Create(scale, TweenInfo.new(0.35, Enum.EasingStyle.Back), { Scale = 1 }):Play()
end

-- Fade a whole piece of UI in or out: text, images, backgrounds AND their
-- outlines (UIStroke), so nothing lingers. Remembers each part's own look.
local baseLook: { [Instance]: { [string]: number } } = setmetatable({}, { __mode = "k" }) :: any
local FADE_PROPS = {
	TextLabel = { "TextTransparency", "BackgroundTransparency", "TextStrokeTransparency" },
	TextButton = { "TextTransparency", "BackgroundTransparency", "TextStrokeTransparency" },
	ImageLabel = { "ImageTransparency", "BackgroundTransparency" },
	ImageButton = { "ImageTransparency", "BackgroundTransparency" },
	Frame = { "BackgroundTransparency" },
	UIStroke = { "Transparency" },
}
function UI.fade(root: Instance, visible: boolean, time: number?)
	local info = TweenInfo.new(time or 0.25, Enum.EasingStyle.Quad)
	local all = root:GetDescendants()
	table.insert(all, root)
	for _, inst in all do
		local props = FADE_PROPS[inst.ClassName]
		if props then
			local base = baseLook[inst]
			if not base then
				base = {}
				for _, k in props do
					base[k] = (inst :: any)[k]
				end
				baseLook[inst] = base
			end
			local goal = {}
			for _, k in props do
				goal[k] = visible and base[k] or 1
			end
			if visible then
				for _, k in props do
					(inst :: any)[k] = 1
				end
			end
			TweenService:Create(inst, info, goal):Play()
		end
	end
end

-- endless gentle pulse (for "tap me" moments); returns a stop function
function UI.pulse(gui: GuiObject): () -> ()
	local scale = gui:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
	scale.Parent = gui
	local alive = true
	task.spawn(function()
		while alive and gui.Parent do
			TweenService:Create(scale, TweenInfo.new(0.45, Enum.EasingStyle.Sine), { Scale = 1.07 }):Play()
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

-- slow rainbow sweep for premium buttons
function UI.rainbow(gui: GuiObject)
	local old = gui:FindFirstChildOfClass("UIGradient")
	if old then
		old:Destroy()
	end
	gui.BackgroundColor3 = Color3.new(1, 1, 1)
	local g = Instance.new("UIGradient")
	local keys = {}
	for i = 0, 6 do
		table.insert(keys, ColorSequenceKeypoint.new(i / 6, Color3.fromHSV(i / 6, 0.75, 1)))
	end
	g.Color = ColorSequence.new(keys)
	g.Parent = gui
	task.spawn(function()
		while gui.Parent do
			g.Offset = Vector2.new(math.sin(os.clock()) * 0.3, 0)
			task.wait(0.05)
		end
	end)
	return g
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

function UI.commas(n: number): string
	local s = tostring(math.floor(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	return (out:gsub("^,", ""))
end

-- "1m 40s", "45s", "2h 5m"
function UI.timeWords(sec: number): string
	sec = math.max(0, math.floor(sec))
	if sec >= 3600 then
		return ("%dh %dm"):format(sec // 3600, (sec % 3600) // 60)
	elseif sec >= 60 then
		return ("%dm %ds"):format(sec // 60, sec % 60)
	end
	return ("%ds"):format(sec)
end

function UI.time(sec: number): string
	sec = math.max(0, math.floor(sec))
	return string.format("%d:%02d", sec // 60, sec % 60)
end

return UI
