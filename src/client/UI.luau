-- The game's design system. Every screen builds from these tokens and
-- components, so the whole UI reads as one game:
--   colors   by meaning (UI.T.role): blue = progression / places / Index,
--            orange = rides + speed upgrades, green = money / success,
--            pink = rewards + gifts, red = danger / sharks, gold = rare /
--            premium, navy = panels. Each has a darker shade for depth.
--   shape    rounded everything (UI.R), chunky buttons with a darker base
--            under the face (depth instead of heavy black outlines),
--            strokes only where they help (UI.S)
--   space    4 / 8 / 12 / 16 / 24 / 32 (UI.SP)
--   type     4 levels (UI.TYPE): hero, value, body, meta
--   motion   hover 1.04, press 0.95, 0.08 to 0.18 s; bars tween; pops spring
-- Components: button, iconButton, wideButton, navButton, pill, card, window
-- (with a dimmed backdrop), popup (title / text / primary + secondary),
-- bar + setBar, lockedState, badge, toggle, chip.

local TweenService = game:GetService("TweenService")

local Config = require(game.ReplicatedStorage.Shared.Config)

local UI = {}
-- sound hooks (set by Audio.luau)
UI.onClick = nil :: (() -> ())?
UI.onOpen = nil :: (() -> ())?
UI.onClose = nil :: (() -> ())?
UI.onHover = nil :: (() -> ())?

local RGB = Color3.fromRGB
-- design tokens: change these and the whole game follows
UI.T = {
	navy = RGB(24, 34, 74), -- panels
	navyDark = RGB(14, 20, 48), -- panel depth / tracks / text outline
	navyLight = RGB(40, 56, 112), -- cards on panels
	line = RGB(70, 100, 190), -- subtle panel border
	blue = RGB(36, 140, 255),
	orange = RGB(255, 150, 30),
	green = RGB(70, 200, 60),
	pink = RGB(240, 70, 170),
	red = RGB(235, 50, 60),
	gold = RGB(255, 200, 40),
	purple = RGB(150, 85, 255),
	white = RGB(255, 255, 255),
	mute = RGB(150, 165, 205),
	shadow = 0.55, -- drop shadow transparency
}
-- radius: large panels, cards, buttons, small chips
UI.R = { panel = 18, card = 14, button = 12, chip = 8 }
-- strokes: big CTAs, cards, subtle containers, text
UI.S = { cta = 3, card = 2, subtle = 1.5, text = 2 }
UI.SP = { 4, 8, 12, 16, 24, 32 }
-- type levels: { size, font }
UI.TYPE = {
	hero = { 34, Enum.Font.FredokaOne },
	value = { 28, Enum.Font.FredokaOne },
	body = { 20, Enum.Font.FredokaOne },
	meta = { 15, Enum.Font.FredokaOne },
}

-- darker / lighter shade of a color (for depth, borders, gradients)
function UI.dark(c: Color3, k: number?): Color3
	local h, s, v = c:ToHSV()
	return Color3.fromHSV(h, math.min(s * 1.05, 1), v * (1 - (k or 0.32)))
end
function UI.light(c: Color3, k: number?): Color3
	return c:Lerp(Color3.new(1, 1, 1), k or 0.25)
end

-- legacy names used around the game, mapped onto the tokens
UI.C = {
	ink = UI.T.navyDark,
	white = UI.T.white,
	pink = UI.T.pink,
	blue = UI.T.blue,
	sky = RGB(40, 200, 255),
	index = UI.T.blue,
	green = UI.T.green,
	money = RGB(120, 255, 90),
	gold = UI.T.gold,
	orange = UI.T.orange,
	red = UI.T.red,
	purple = UI.T.purple,
	panel = UI.T.navy,
	panel2 = UI.T.navyDark,
	card = UI.T.white,
	mute = UI.T.mute,
}
UI.FONT = Enum.Font.FredokaOne
UI.NUMFONT = Enum.Font.LuckiestGuy

local function apply(inst: Instance, props: { [string]: any }?)
	if props then
		for k, v in props do
			if k ~= "Kit" then
				(inst :: any)[k] = v
			end
		end
	end
end

----------------------------------------------------------------- UI kit art
-- The developer's kit (Config.Kit): 9-slice images. Every component uses
-- them when present and falls back to the drawn look otherwise.
local KIT = (Config :: any).Kit or {}
function UI.hasKit(name: string?): boolean
	local k = name and KIT[name]
	return k ~= nil and typeof(k.id) == "string" and k.id ~= ""
end

-- corner = share of the image's short side that stays unstretched;
-- fitShare / fitMax = how big those corners draw on the element
local function slicer(img: ImageLabel, owner: GuiObject, name: string, corner: number, fitShare: number, fitMax: number)
	local k = KIT[name]
	local c = math.max(1, math.floor(math.min(k.w, k.h) * corner))
	img.Image = k.id
	img.ScaleType = Enum.ScaleType.Slice
	img.SliceCenter = Rect.new(c, c, k.w - c, k.h - c)
	local function fit()
		local a = owner.AbsoluteSize
		local short = math.min(a.X, a.Y)
		if short > 0 then
			img.SliceScale = math.clamp(math.min(short * fitShare, fitMax) / c, 0.02, 2)
		end
	end
	fit()
	return fit
end

-- how each kind of art slices: { corner share, drawn corner share of the
-- element's short side, max drawn corner px }
local SKIN_SPEC = {
	Button = { 0.46, 0.5, 999 }, Bar = { 0.46, 0.5, 999 }, Toggle = { 0.46, 0.5, 999 },
	Card = { 0.2, 0.18, 34 }, Panel = { 0.16, 0.12, 40 }, Tab = { 0.4, 0.5, 999 }, Tooltip = { 0.4, 0.5, 999 },
}
local function spec(name: string): { number }
	for prefix, s in SKIN_SPEC do
		if name:sub(1, #prefix) == prefix then
			return s
		end
	end
	return { 0.3, 0.3, 40 }
end
-- a 9-slice skin that fills `owner` (nil without the art)
function UI.skin(owner: GuiObject, name: string, z: number?): ImageLabel?
	if not UI.hasKit(name) then
		return nil
	end
	local img = Instance.new("ImageLabel")
	img.Name = "Skin"
	img.BackgroundTransparency = 1
	img.Size = UDim2.fromScale(1, 1)
	img.ZIndex = z or owner.ZIndex
	local sp = spec(name)
	local current = name
	local fit = slicer(img, owner, name, sp[1], sp[2], sp[3])
	owner:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		local s2 = spec(current)
		slicer(img, owner, current, s2[1], s2[2], s2[3])
	end)
	img:SetAttribute("Kit", name)
	img:GetAttributeChangedSignal("Kit"):Connect(function()
		current = img:GetAttribute("Kit") :: string
	end)
	img.Parent = owner
	local _ = fit
	return img
end
function UI.setSkin(img: ImageLabel?, owner: GuiObject, name: string)
	if img and UI.hasKit(name) then
		local sp = spec(name)
		img:SetAttribute("Kit", name)
		slicer(img, owner, name, sp[1], sp[2], sp[3])
	end
end

-- turn a drawn "X" button into the kit's round close button
function UI.kitClose(x: GuiObject)
	if not UI.hasKit("Close") then
		return
	end
	for _, d in x:GetChildren() do
		if d:IsA("GuiObject") then
			d.Visible = false
		end
	end
	x.BackgroundTransparency = 1
	local st = x:FindFirstChild("Edge")
	if st and st:IsA("UIStroke") then
		st.Enabled = false
	end
	UI.kitImage(x, "Close", { Size = UDim2.new(1, 10, 1, 10), Position = UDim2.fromOffset(-5, -5), ZIndex = x.ZIndex + 1 })
	x:GetPropertyChangedSignal("BackgroundTransparency"):Connect(function()
		x.BackgroundTransparency = 1
	end)
end

-- the kit's green check badge (claimed / owned), or a drawn tick
function UI.check(parent: Instance, props: { [string]: any }?): GuiObject
	return UI.kitImage(parent, "BadgeCheck", props) or UI.outlined(parent, "✓", props)
end

-- which kit color a UI color maps to (nil = keep the drawn look)
function UI.kitColor(c: Color3): string?
	local h, s, v = c:ToHSV()
	if v < 0.45 or s < 0.25 then
		return "Grey"
	elseif h < 0.035 or h > 0.93 then
		return "Red"
	elseif h < 0.17 then
		return "Gold"
	elseif h < 0.45 then
		return "Green"
	elseif h < 0.7 then
		return "Blue"
	elseif h < 0.82 then
		return "Purple"
	end
	return nil -- pinks keep the drawn look
end

-- a plain (unsliced) kit image: effects, badges, close/back buttons
function UI.kitImage(parent: Instance, name: string, props: { [string]: any }?): ImageLabel?
	if not UI.hasKit(name) then
		return nil
	end
	local img = Instance.new("ImageLabel")
	img.Name = name
	img.BackgroundTransparency = 1
	img.Image = KIT[name].id
	img.ScaleType = Enum.ScaleType.Fit
	img.Size = UDim2.fromScale(1, 1)
	apply(img, props)
	img.Parent = parent
	return img
end

-- a reward glow behind something (rays / burst turn slowly; sparkles,
-- bubbles stay); cancelled with its parent
function UI.effect(parent: GuiObject, name: string, size: number, props: { [string]: any }?): ImageLabel?
	local img = UI.kitImage(parent, name, { Size = UDim2.fromOffset(size, size), Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5),
		ZIndex = math.max(parent.ZIndex - 1, 1) })
	if not img then
		return nil
	end
	apply(img, props)
	if name == "EffectRewardRays" or name == "EffectZoneBurst" then
		local t = TweenService:Create(img, TweenInfo.new(10, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1), { Rotation = 360 })
		t:Play()
		img.Destroying:Connect(function()
			t:Cancel()
		end)
	end
	return img
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
	-- the redesign dropped stud textures from the UI (cleaner, less noise);
	-- kept as a no-op so older calls still work
	local holder = Instance.new("Frame")
	holder.Name = "Studs"
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.fromScale(1, 1)
	holder.ZIndex = (opts and opts.z) or parent.ZIndex
	holder.Parent = parent
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
	if props and (props.StrokeColor or props.StrokeThickness) then
		props = table.clone(props)
		props.StrokeColor = nil
		props.StrokeThickness = nil
	end
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
	s.Color = (props and props.StrokeColor) or UI.T.navyDark
	s.Thickness = (props and props.StrokeThickness) or UI.S.text
	s.LineJoinMode = Enum.LineJoinMode.Round
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	s.Parent = t
	return t
end

-- text at one of the 4 type levels (UI.TYPE): hero, value, body, meta
function UI.label(parent: Instance, level: string, text: string, props: { [string]: any }?): TextLabel
	local ty = UI.TYPE[level] or UI.TYPE.body
	local t = UI.outlined(parent, text, props)
	t.Font = ty[2]
	if not (props and props.TextScaled ~= nil) then
		t.TextScaled = true
		local c = Instance.new("UITextSizeConstraint")
		c.MaxTextSize = ty[1]
		c.MinTextSize = 9
		c.Parent = t
	end
	return t
end

-- press feedback for anything clickable: hover 1.04, press 0.95, quick spring
local function squish(b: GuiButton)
	local scale = b:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
	scale.Parent = b
	local hover = false
	b.MouseButton1Down:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.07, Enum.EasingStyle.Quad), { Scale = 0.95 }):Play()
	end)
	b.MouseButton1Up:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.16, Enum.EasingStyle.Back), { Scale = hover and 1.04 or 1 }):Play()
	end)
	b.MouseEnter:Connect(function()
		hover = true
		if not UI.TOUCH then
			TweenService:Create(scale, TweenInfo.new(0.1), { Scale = 1.04 }):Play()
			if UI.onHover then
				UI.onHover()
			end
		end
	end)
	b.MouseLeave:Connect(function()
		hover = false
		TweenService:Create(scale, TweenInfo.new(0.1), { Scale = 1 }):Play()
	end)
end
UI.squish = squish

-- The chunky studded button. Text lives in a child "Label" (UI.setText).
function UI.button(parent: Instance, text: string, color: Color3, onClick: () -> (), props: { [string]: any }?): TextButton
	-- the button is its darker base; the "Face" sits on top, leaving a depth
	-- lip at the bottom. Setting b.BackgroundColor3 recolors the whole thing.
	local b = Instance.new("TextButton")
	b.AutoButtonColor = false
	b.BorderSizePixel = 0
	b.Text = ""
	b.Size = UDim2.fromOffset(160, 50)
	apply(b, props)
	UI.corner(b, UI.R.button)
	local face = Instance.new("Frame")
	face.Name = "Face"
	face.BorderSizePixel = 0
	face.Size = UDim2.new(1, 0, 1, -5)
	face.ZIndex = b.ZIndex
	face.Parent = b
	UI.corner(face, UI.R.button)
	local g = Instance.new("UIGradient")
	g.Rotation = 90
	g.Color = ColorSequence.new(RGB(255, 255, 255), RGB(214, 214, 214))
	g.Parent = face
	-- soft top shine
	local shine = UI.frame(face, { Name = "Shine", Size = UDim2.new(1, -10, 0.38, 0), Position = UDim2.fromOffset(5, 3),
		BackgroundColor3 = RGB(255, 255, 255), BackgroundTransparency = 0.82, ZIndex = b.ZIndex })
	UI.corner(shine, UI.R.button - 4)
	local stroke = UI.stroke(b, color, UI.S.cta)
	stroke.Name = "Edge"
	local busy = false
	local skin: ImageLabel? = nil
	local kitName: string? = nil
	local baseTransparency = b.BackgroundTransparency
	local function paint(c: Color3)
		busy = true
		face.BackgroundColor3 = c
		b.BackgroundColor3 = UI.dark(c, 0.38)
		stroke.Color = UI.dark(c, 0.5)
		-- the kit's button art for this color, if uploaded
		local kc = UI.kitColor(c)
		kitName = kc and UI.hasKit("Button" .. kc) and ("Button" .. kc) or nil
		if kitName then
			skin = skin or UI.skin(b, kitName, b.ZIndex)
			UI.setSkin(skin, b, kitName)
		end
		local drawn = kitName == nil
		if skin then
			skin.Visible = not drawn
		end
		b.BackgroundTransparency = drawn and baseTransparency or 1
		face.BackgroundTransparency = drawn and 0 or 1
		shine.Visible = drawn
		stroke.Enabled = drawn
		busy = false
	end
	paint(color)
	b:GetPropertyChangedSignal("BackgroundColor3"):Connect(function()
		if not busy then
			paint(b.BackgroundColor3)
		end
	end)
	UI.outlined(b, text, { Name = "Label", Size = UDim2.new(1, -16, 1, -17), Position = UDim2.new(0.5, 0, 0.5, -3), AnchorPoint = Vector2.new(0.5, 0.5),
		ZIndex = b.ZIndex + 1, StrokeColor = UI.dark(color, 0.55) })
	-- press: the face sinks onto its base
	b.MouseButton1Down:Connect(function()
		TweenService:Create(face, TweenInfo.new(0.06), { Position = UDim2.fromOffset(0, 3) }):Play()
		if kitName and UI.hasKit(kitName .. "Pressed") then
			UI.setSkin(skin, b, kitName .. "Pressed")
		end
	end)
	local function up()
		TweenService:Create(face, TweenInfo.new(0.12, Enum.EasingStyle.Back), { Position = UDim2.fromOffset(0, 0) }):Play()
		if kitName then
			UI.setSkin(skin, b, kitName)
		end
	end
	b.MouseButton1Up:Connect(up)
	b.MouseLeave:Connect(up)
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
	b.BackgroundColor3 = color -- buttons repaint face, base and edge from this
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
	-- an alias uses another icon's art, unless this name has its own image
	local own = tostring(icons.ids and icons.ids[name] or ""):match("%d+")
	if not own and icons.alias and icons.alias[name] then
		name = icons.alias[name]
	end
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
	local face = b:FindFirstChild("Face") :: Frame
	if caption == "" then
		-- icon-only square (Gift, Tank...)
		UI.icon(face, icon, { Size = UDim2.fromScale(0.78, 0.78), Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = b.ZIndex + 1 })
		return b
	end
	UI.icon(face, icon, { Size = UDim2.fromScale(0.72, 0.6), Position = UDim2.fromScale(0.5, 0.04), AnchorPoint = Vector2.new(0.5, 0), ZIndex = b.ZIndex + 1 })
	local l = b:FindFirstChild("Label") :: TextLabel
	l.Text = caption
	l.Size = UDim2.new(1, -6, 0.28, 0)
	l.Position = UDim2.new(0.5, 0, 1, -8)
	l.AnchorPoint = Vector2.new(0.5, 1)
	return b
end

-- wide menu button: icon on the left, big label (the "🛒 Shop" style)
function UI.wideButton(parent: Instance, icon: string, caption: string, color: Color3, onClick: () -> (), props: { [string]: any }?): TextButton
	-- navigation button: big icon breaking out on the left, bold label
	local b = UI.button(parent, caption, color, onClick, props)
	UI.icon(b, icon, { Size = UDim2.new(0, 0, 1, 6), Position = UDim2.new(0, 6, 0.5, -4), AnchorPoint = Vector2.new(0, 0.5), ZIndex = b.ZIndex + 2,
		SizeConstraint = Enum.SizeConstraint.RelativeYY })
	local ic = b:FindFirstChild("Icon") :: GuiObject
	ic.Size = UDim2.fromScale(1.05, 1.05)
	local l = b:FindFirstChild("Label") :: TextLabel
	l.Size = UDim2.new(1, -86, 0.58, 0)
	l.Position = UDim2.new(0, 78, 0.5, -3)
	l.AnchorPoint = Vector2.new(0, 0.5)
	l.TextXAlignment = Enum.TextXAlignment.Left
	return b
end
UI.navButton = UI.wideButton

-- square on/off box with a caption to its right (Slow Mode). returns setter
function UI.toggle(parent: Instance, caption: string, on: boolean, onChange: (boolean) -> (), props: { [string]: any }?): (Frame, (boolean) -> ())
	-- a pill switch with its caption (settings rows)
	local holder = UI.frame(parent, { Size = UDim2.fromOffset(260, 44), BackgroundTransparency = 1 })
	apply(holder, props)
	local label = UI.label(holder, "body", caption, { Size = UDim2.new(1, -92, 0, 26), Position = UDim2.new(0, 0, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5),
		TextXAlignment = Enum.TextXAlignment.Left })
	local track = Instance.new("TextButton")
	track.AutoButtonColor = false
	track.Text = ""
	track.Size = UDim2.fromOffset(76, 40)
	track.Position = UDim2.new(1, 0, 0.5, 0)
	track.AnchorPoint = Vector2.new(1, 0.5)
	track.BorderSizePixel = 0
	track.Parent = holder
	UI.corner(track, 20)
	UI.stroke(track, UI.T.navyDark, UI.S.card)
	local knob = UI.frame(track, { Size = UDim2.fromOffset(32, 32), Position = UDim2.new(0, 4, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5), BackgroundColor3 = UI.T.white })
	UI.corner(knob, 16)
	-- kit art: the whole switch is one image per state
	local art = UI.hasKit("ToggleOn") and UI.hasKit("ToggleOff")
	local artImg: ImageLabel? = nil
	if art then
		track.BackgroundTransparency = 1
		local st = track:FindFirstChildOfClass("UIStroke")
		if st then
			st.Enabled = false
		end
		knob.Visible = false
		artImg = UI.kitImage(track, "ToggleOff", { Size = UDim2.new(1, 8, 1, 8), Position = UDim2.fromOffset(-4, -4), ZIndex = track.ZIndex + 1 })
	end
	local state = on
	local function set(v: boolean)
		state = v
		if artImg then
			artImg.Image = (Config :: any).Kit[v and "ToggleOn" or "ToggleOff"].id
		end
		track.BackgroundColor3 = v and UI.T.green or UI.T.navyLight
		TweenService:Create(knob, TweenInfo.new(0.12), { Position = v and UDim2.new(1, -36, 0.5, 0) or UDim2.new(0, 4, 0.5, 0) }):Play()
		label.TextColor3 = v and UI.T.white or UI.T.mute
	end
	set(on)
	squish(track)
	track.Activated:Connect(function()
		if UI.onClick then
			UI.onClick()
		end
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
	local f = UI.frame(b, { Name = "Badge", Size = UDim2.fromOffset(26, 26), Position = UDim2.new(1, 8, 0, -8), AnchorPoint = Vector2.new(1, 0),
		BackgroundColor3 = UI.T.red, ZIndex = b.ZIndex + 4 })
	UI.corner(f, 13)
	local bs = UI.stroke(f, UI.T.white, 2)
	if UI.kitImage(f, "BadgeNotification", { Size = UDim2.fromScale(1.3, 1.3), Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5),
		ZIndex = f.ZIndex }) then
		f.BackgroundTransparency = 1
		bs.Enabled = false
	end
	UI.outlined(f, text or "!", { Size = UDim2.new(1, -8, 1, -8), Position = UDim2.fromOffset(4, 4), ZIndex = f.ZIndex + 1, StrokeColor = UI.dark(UI.T.red, 0.5) })
	UI.pop(f, 1.5) -- one pop when it appears, no endless bounce
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
	-- dimmed backdrop: focus on the menu, tap outside to close
	local dim = Instance.new("TextButton")
	dim.Name = "Backdrop"
	dim.Text = ""
	dim.AutoButtonColor = false
	dim.BorderSizePixel = 0
	dim.BackgroundColor3 = RGB(0, 0, 0)
	dim.BackgroundTransparency = 1
	dim.Size = UDim2.fromScale(4, 4)
	dim.Position = UDim2.fromScale(0.5, 0.5)
	dim.AnchorPoint = Vector2.new(0.5, 0.5)
	dim.ZIndex = 0
	dim.Parent = parent
	TweenService:Create(dim, TweenInfo.new(0.18), { BackgroundTransparency = 0.5 }):Play()
	local function close()
		if UI.onClose then
			UI.onClose()
		end
		onClose()
	end
	dim.Activated:Connect(close)

	local f = UI.frame(parent, { Name = "Window", Size = UDim2.fromOffset(size.X, size.Y), Position = UDim2.fromScale(0.5, 0.52),
		AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = UI.T.navy })
	f.Destroying:Connect(function()
		dim:Destroy()
	end)
	UI.corner(f, UI.R.panel)
	local wst = UI.stroke(f, UI.dark(color, 0.35), UI.S.cta)
	if UI.skin(f, "PanelMenu", f.ZIndex) then
		f.BackgroundTransparency = 1
		wst.Enabled = false
	end
	local g = Instance.new("UIGradient")
	g.Rotation = 90
	g.Color = ColorSequence.new(RGB(255, 255, 255), RGB(200, 205, 225))
	g.Parent = f
	-- header band in the menu's color
	local head = UI.frame(f, { Name = "Head", Size = UDim2.new(1, 0, 0, 66), BackgroundColor3 = color })
	UI.corner(head, UI.R.panel)
	UI.frame(head, { Name = "Square", Size = UDim2.new(1, 0, 0, 18), Position = UDim2.new(0, 0, 1, -18), BackgroundColor3 = color, BorderSizePixel = 0 })
	local hg = Instance.new("UIGradient")
	hg.Rotation = 90
	hg.Color = ColorSequence.new(UI.light(color, 0.18), UI.dark(color, 0.12))
	hg.Parent = head
	local tx = 20
	if iconName then
		UI.icon(head, iconName, { Size = UDim2.fromOffset(64, 64), Position = UDim2.fromOffset(8, -6), ZIndex = head.ZIndex + 2 })
		tx = 80
	end
	UI.label(head, "hero", title:upper(), { Name = "Title", Size = UDim2.new(1, -90 - tx, 0, 40), Position = UDim2.fromOffset(tx, 13),
		TextXAlignment = Enum.TextXAlignment.Left, StrokeColor = UI.dark(color, 0.55) })
	local x = UI.button(f, "X", UI.T.red, close, { Name = "Close", Size = UDim2.fromOffset(52, 52), Position = UDim2.new(1, -10, 0, 7),
		AnchorPoint = Vector2.new(1, 0), ZIndex = head.ZIndex + 3 })
	UI.kitClose(x)
	if UI.onOpen then
		UI.onOpen()
	end
	local body = UI.frame(f, { Name = "Body", Size = UDim2.new(1, -32, 1, -98), Position = UDim2.fromOffset(16, 82), BackgroundTransparency = 1 })
	UI.pop(f, 0.9)
	return f, body, x
end

-- inset darker panel inside a window
function UI.inset(parent: Instance, props: { [string]: any }?): Frame
	-- a recessed area inside a panel (lists, stats)
	local f = UI.frame(parent, { BackgroundColor3 = UI.T.navyDark, BackgroundTransparency = 0.25 })
	apply(f, props)
	UI.corner(f, UI.R.card)
	return f
end

-- a raised card on a panel; accent colors its edge (rarity, equipped...)
function UI.card(parent: Instance, accent: Color3?, props: { [string]: any }?): Frame
	local f = UI.frame(parent, { BackgroundColor3 = UI.T.navyLight })
	apply(f, props)
	UI.corner(f, UI.R.card)
	local st = UI.stroke(f, accent or UI.T.line, accent and UI.S.cta or UI.S.subtle)
	st.Name = "Accent"
	-- kit art: a card per accent color (or props.Kit, e.g. "CardEquipped")
	local kc = accent and UI.kitColor(accent) or "Blue"
	local name = (props and props.Kit) or ("Card" .. (kc or "Blue"))
	if UI.skin(f, name, f.ZIndex) then
		f.BackgroundTransparency = 1
		st.Enabled = false
		return f
	end
	local g = Instance.new("UIGradient")
	g.Rotation = 90
	g.Color = ColorSequence.new(RGB(255, 255, 255), RGB(190, 196, 220))
	g.Parent = f
	return f
end

-- compact resource pill: [icon] value  (speed, cash, friend boost)
function UI.pill(parent: Instance, icon: string, color: Color3, props: { [string]: any }?): (Frame, TextLabel)
	local f = UI.frame(parent, { Size = UDim2.fromOffset(190, 46), BackgroundColor3 = UI.dark(color, 0.45) })
	apply(f, props)
	UI.corner(f, 23)
	UI.stroke(f, UI.dark(color, 0.6), UI.S.card)
	local face = UI.frame(f, { Name = "Face", Size = UDim2.new(1, 0, 1, -4), BackgroundColor3 = color })
	UI.corner(face, 23)
	local g = Instance.new("UIGradient")
	g.Rotation = 90
	g.Color = ColorSequence.new(UI.light(color, 0.2), UI.dark(color, 0.1))
	g.Parent = face
	UI.icon(f, icon, { Size = UDim2.new(0, 0, 1, 14), SizeConstraint = Enum.SizeConstraint.RelativeYY, Position = UDim2.new(0, -10, 0.5, -2),
		AnchorPoint = Vector2.new(0, 0.5), ZIndex = f.ZIndex + 2 })
	local ic = f:FindFirstChild("Icon") :: GuiObject
	ic.Size = UDim2.fromScale(1.3, 1.3)
	local value = UI.label(f, "value", "", { Name = "Value", Size = UDim2.new(1, -66, 1, -12), Position = UDim2.new(0, 54, 0.5, -2),
		AnchorPoint = Vector2.new(0, 0.5), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = f.ZIndex + 2, StrokeColor = UI.dark(color, 0.6) })
	return f, value
end

-- small rounded tag ("RARE", "EQUIPPED", "NEW!")
function UI.chip(parent: Instance, text: string, color: Color3, props: { [string]: any }?): Frame
	local f = UI.frame(parent, { Size = UDim2.fromOffset(96, 24), BackgroundColor3 = color })
	apply(f, props)
	UI.corner(f, 12)
	if text == "NEW!" and UI.kitImage(f, "BadgeNew", { Size = UDim2.new(1, 8, 1, 8), Position = UDim2.fromOffset(-4, -4), ZIndex = f.ZIndex }) then
		f.BackgroundTransparency = 1
		return f -- the art already says NEW!
	end
	UI.label(f, "meta", text, { Size = UDim2.new(1, -12, 1, -6), Position = UDim2.fromOffset(6, 3), StrokeColor = UI.dark(color, 0.55) })
	return f
end

-- standard confirmation popup: TITLE / text / [PRIMARY] [secondary]
-- opts = { title, text, value?, color, primary = { text, color, fn }, secondary = { text, fn }? }
function UI.popup(parent: Instance, opts: { [string]: any }): Frame
	local f: Frame
	local function close()
		if f and f.Parent then
			f:Destroy()
		end
	end
	local color = opts.color or UI.T.blue
	local body
	f, body = UI.window(parent, opts.title or "", color, Vector2.new(460, opts.value and 330 or 290), close, opts.icon)
	UI.label(body, "body", opts.text or "", { Size = UDim2.new(1, 0, 0, 56), TextWrapped = true, TextColor3 = UI.T.white })
	if opts.value then
		UI.label(body, "value", opts.value, { Size = UDim2.new(1, 0, 0, 40), Position = UDim2.fromOffset(0, 62), TextColor3 = opts.valueColor or UI.C.money })
	end
	local p = opts.primary or {}
	UI.button(body, p.text or "OK", p.color or UI.T.green, function()
		close()
		if p.fn then
			p.fn()
		end
	end, { Size = UDim2.new(0.62, -6, 0, 62), Position = UDim2.new(0, 0, 1, 0), AnchorPoint = Vector2.new(0, 1) })
	local sec = opts.secondary or { text = "Cancel" }
	UI.button(body, sec.text or "Cancel", UI.T.navyLight, function()
		close()
		if sec.fn then
			sec.fn()
		end
	end, { Size = UDim2.new(0.38, -6, 0, 54), Position = UDim2.new(1, 0, 1, -4), AnchorPoint = Vector2.new(1, 1) })
	return f
end

-- studded progress bar; returns (back, fill, label)
function UI.bar(parent: Instance, color: Color3, props: { [string]: any }?): (Frame, Frame, TextLabel)
	-- track, fill (gradient + shine), centered label; move it with UI.setBar
	local back = UI.frame(parent, { BackgroundColor3 = UI.T.navyDark })
	apply(back, props)
	UI.corner(back, 100)
	UI.stroke(back, UI.T.navyDark, UI.S.card)
	local fill = UI.frame(back, { Name = "Fill", Size = UDim2.fromScale(0, 1), BackgroundColor3 = color })
	UI.corner(fill, 100)
	local g = Instance.new("UIGradient")
	g.Rotation = 90
	g.Color = ColorSequence.new(UI.light(color, 0.3), UI.dark(color, 0.08))
	g.Parent = fill
	local shine = UI.frame(fill, { Name = "Shine", Size = UDim2.new(1, -8, 0.34, 0), Position = UDim2.fromOffset(4, 2), BackgroundColor3 = RGB(255, 255, 255),
		BackgroundTransparency = 0.7 })
	UI.corner(shine, 100)
	local label = UI.label(back, "body", "", { Size = UDim2.new(1, -16, 1, -6), Position = UDim2.fromOffset(8, 3), ZIndex = back.ZIndex + 2 })
	-- kit art: track + a colored fill (follows the fill's color when it changes)
	if UI.skin(back, "BarTrack", back.ZIndex) then
		back.BackgroundTransparency = 1
		local bst = back:FindFirstChildOfClass("UIStroke")
		if bst then
			bst.Enabled = false
		end
		local FILL = { Blue = "BarFillCyan", Gold = "BarFillGold", Green = "BarFillGreen", Purple = "BarFillPurple" }
		local fskin: ImageLabel? = nil
		local function paintFill()
			local name = FILL[UI.kitColor(fill.BackgroundColor3) or ""]
			if name and UI.hasKit(name) then
				fskin = fskin or UI.skin(fill, name, fill.ZIndex)
				UI.setSkin(fskin, fill, name)
				if fskin then
					fskin.Visible = true
				end
				fill.BackgroundTransparency = 1
				shine.Visible = false
			else
				if fskin then
					fskin.Visible = false
				end
				fill.BackgroundTransparency = 0
				shine.Visible = true
			end
		end
		paintFill()
		fill:GetPropertyChangedSignal("BackgroundColor3"):Connect(paintFill)
	end
	return back, fill, label
end

-- tween a bar's fill (never snaps); a quick flash when it grows
function UI.setBar(fill: Frame, frac: number, instant: boolean?)
	frac = math.clamp(frac, 0, 1)
	local goal = UDim2.fromScale(frac, 1)
	if instant then
		fill.Size = goal
		return
	end
	local grew = frac > fill.Size.X.Scale + 0.001
	TweenService:Create(fill, TweenInfo.new(0.35, Enum.EasingStyle.Quad), { Size = goal }):Play()
	local shine = fill:FindFirstChild("Shine") :: Frame?
	if grew and shine then
		shine.BackgroundTransparency = 0.25
		TweenService:Create(shine, TweenInfo.new(0.4), { BackgroundTransparency = 0.7 }):Play()
	end
end

-- locked content that still looks worth reaching: name, goal, progress
-- returns (frame, setProgress(current, need))
function UI.lockedState(parent: Instance, title: string, goal: string, color: Color3, props: { [string]: any }?): (Frame, (number, number) -> ())
	local f = UI.card(parent, UI.dark(color, 0.1), props)
	UI.icon(f, "Lock", { Size = UDim2.fromOffset(38, 38), Position = UDim2.fromOffset(10, 8), ZIndex = f.ZIndex + 1 })
	UI.label(f, "body", title, { Size = UDim2.new(1, -64, 0, 24), Position = UDim2.fromOffset(56, 8), TextXAlignment = Enum.TextXAlignment.Left })
	UI.label(f, "meta", goal, { Size = UDim2.new(1, -64, 0, 18), Position = UDim2.fromOffset(56, 32), TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = UI.T.mute })
	local _, fill, label = UI.bar(f, color, { Size = UDim2.new(1, -20, 0, 22), Position = UDim2.new(0, 10, 1, -30) })
	return f, function(cur: number, need: number)
		UI.setBar(fill, need > 0 and cur / need or 1)
		label.Text = ("%s / %s"):format(UI.short(cur), UI.short(need))
	end
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
