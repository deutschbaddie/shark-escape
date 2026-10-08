-- The Tank panel (opens from the tank button): your whole catch.
--   header:  "4/4 Active"  [+1 EQUIP [$1K]]      storage count
--   list:    thumbnail · name ($/s) · Equip / Unequip
--   footer:  Equip Best
-- Active creatures swim in your tank and earn; the rest wait in storage.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Shared = game.ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Creatures = require(Shared.Creatures)
local UI = require(script.Parent.UI)
local State = require(script.Parent.State)

local Tank = {}
local C = UI.C
local player = Players.LocalPlayer

local gui: ScreenGui
local panel: Frame
local list: ScrollingFrame
local headerTitle: TextLabel
local headerSub: TextLabel
local equipBtn: TextButton
local isOpen = false
local lastSig = ""

local TAN = Color3.fromRGB(214, 160, 110)

local function thumb(parent: Instance, c: any)
	local holder = UI.frame(parent, { Size = UDim2.fromOffset(62, 62), Position = UDim2.fromOffset(7, 7), BackgroundColor3 = Color3.fromRGB(70, 74, 86) })
	UI.corner(holder, 8)
	-- light rays behind the creature, like a reveal card
	local g = Instance.new("UIGradient")
	g.Color = ColorSequence.new(Color3.fromRGB(235, 235, 240), Color3.fromRGB(120, 124, 136))
	g.Rotation = 90
	g.Parent = holder
	local vf = Instance.new("ViewportFrame")
	vf.Size = UDim2.fromScale(1, 1)
	vf.BackgroundTransparency = 1
	vf.Ambient = Color3.fromRGB(200, 200, 210)
	vf.LightDirection = Vector3.new(-1, -2, -1)
	vf.Parent = holder
	local cam = Instance.new("Camera")
	cam.FieldOfView = 38
	cam.Parent = vf
	vf.CurrentCamera = cam
	local m = Creatures.build(c.r, c.m, 1, c.z)
	m:PivotTo(CFrame.new())
	m.Parent = vf
	local _, size = m:GetBoundingBox()
	local r = math.max(size.X, size.Y, size.Z)
	cam.CFrame = CFrame.lookAt(Vector3.new(r * 1.0, r * 0.55, -r * 1.25), Vector3.zero)
end

local function signature(d: any): string
	local parts = { tostring(d.slots), tostring(d.friendBoost) }
	for _, c in d.creatures do
		table.insert(parts, c.id .. (c.e and "e" or "s"))
	end
	return table.concat(parts, ",")
end

local function sorted(d: any): { any }
	local out = table.clone(d.creatures)
	table.sort(out, function(a, b)
		if a.e ~= b.e then
			return a.e
		end
		return a.v > b.v
	end)
	return out
end

local function renderHeader(d: any)
	headerTitle.Text = ("%d/%d Active"):format(d.active, d.slots)
	headerSub.Text = ("%d/%d caught  ·  +$%s/s"):format(#d.creatures, d.storage, UI.short(d.income))
	if d.slotPrice then
		UI.setText(equipBtn, ("+1 EQUIP [$%s]"):format(UI.short(d.slotPrice)))
		equipBtn.BackgroundColor3 = d.coins >= d.slotPrice and C.green or Color3.fromRGB(110, 120, 110)
	else
		UI.setText(equipBtn, "MAX EQUIPS")
		equipBtn.BackgroundColor3 = Color3.fromRGB(110, 120, 110)
	end
end

local function renderList(d: any)
	for _, k in list:GetChildren() do
		if k:IsA("Frame") then
			k:Destroy()
		end
	end
	local free = d.active < d.slots
	for i, c in sorted(d) do
		local rarity = Config.rarity(c.r)
		local row = UI.frame(list, { Size = UDim2.new(1, -12, 0, 76), LayoutOrder = i, BackgroundColor3 = Color3.fromRGB(44, 46, 56) })
		UI.corner(row, 8)
		UI.stroke(row, C.ink, 2)
		thumb(row, c)
		local name = UI.outlined(row, Config.fullName(c.z, c.r, c.m, c.s), {
			Size = UDim2.new(1, -200, 0, 30), Position = UDim2.fromOffset(78, 9), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = rarity.color,
		})
		name.TextScaled = true
		UI.outlined(row, ("($%s/s)  ·  %s"):format(UI.short(c.v), Config.formatKg(Config.creatureKg(c.z, c.r, c.s))), {
			Size = UDim2.new(1, -200, 0, 24), Position = UDim2.fromOffset(78, 40), TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = c.e and C.money or Color3.fromRGB(190, 190, 200),
		})
		if c.e then
			UI.button(row, "Unequip", C.red, function()
				State.action("unequip", c.id)
			end, { Size = UDim2.fromOffset(112, 50), Position = UDim2.new(1, -8, 0.5, 0), AnchorPoint = Vector2.new(1, 0.5) })
		else
			UI.button(row, "Equip", free and C.green or Color3.fromRGB(110, 120, 110), function()
				if free then
					State.action("equip", c.id)
				end
			end, { Size = UDim2.fromOffset(112, 50), Position = UDim2.new(1, -8, 0.5, 0), AnchorPoint = Vector2.new(1, 0.5) })
		end
	end
	if #d.creatures == 0 then
		local empty = UI.frame(list, { Size = UDim2.new(1, -12, 0, 90), BackgroundTransparency = 1 })
		UI.outlined(empty, "Grab a creature bubble and bring it home!", { Size = UDim2.new(1, -20, 0, 30), Position = UDim2.fromOffset(10, 30) })
	end
end

local function render(d: any?)
	if not (isOpen and d) then
		return
	end
	renderHeader(d)
	local sig = signature(d)
	if sig ~= lastSig then
		lastSig = sig
		renderList(d)
	end
end

local function build()
	gui = Instance.new("ScreenGui")
	gui.Name = "Tank"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 9
	gui.Enabled = false
	gui.Parent = player:WaitForChild("PlayerGui")
	UI.autoScale(gui, Vector2.new(520, 500))

	panel = UI.frame(gui, { Size = UDim2.fromOffset(400, 380), Position = UDim2.new(1, -116, 0.46, 0), AnchorPoint = Vector2.new(1, 0.5),
		BackgroundColor3 = UI.C.panel })
	UI.corner(panel, 10)
	UI.stroke(panel, C.ink, 4)
	UI.studs(panel, { size = 26, alpha = 0.94 })

	local head = UI.frame(panel, { Size = UDim2.new(1, -12, 0, 64), Position = UDim2.fromOffset(6, 6), BackgroundColor3 = TAN })
	UI.corner(head, 8)
	UI.stroke(head, C.ink, 3)
	UI.shade(head)
	UI.studs(head, { size = 18, alpha = 0.8 })
	headerTitle = UI.outlined(head, "", { Size = UDim2.new(0.45, 0, 0, 34), Position = UDim2.fromOffset(12, 6), TextXAlignment = Enum.TextXAlignment.Left })
	headerSub = UI.outlined(head, "", { Size = UDim2.new(0.5, 0, 0, 18), Position = UDim2.fromOffset(12, 40), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Color3.fromRGB(255, 240, 200) })
	equipBtn = UI.button(head, "", C.green, function()
		State.action("buySlot")
	end, { Size = UDim2.fromOffset(196, 48), Position = UDim2.new(1, -8, 0.5, 0), AnchorPoint = Vector2.new(1, 0.5) })

	list = Instance.new("ScrollingFrame")
	list.Size = UDim2.new(1, -16, 1, -84)
	list.Position = UDim2.fromOffset(8, 78)
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.ScrollBarThickness = 7
	list.ScrollBarImageColor3 = Color3.fromRGB(200, 200, 210)
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.CanvasSize = UDim2.new()
	list.Parent = panel
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = list
	local lp = Instance.new("UIPadding")
	lp.PaddingTop = UDim.new(0, 4)
	lp.PaddingLeft = UDim.new(0, 4)
	lp.Parent = list

	UI.button(gui, "Equip Best", C.green, function()
		State.action("equipBest")
	end, { Size = UDim2.fromOffset(230, 58), Position = UDim2.new(1, -116, 0.46, 200), AnchorPoint = Vector2.new(1, 0) })

	-- the red ">" tab closes it
	local tab = UI.button(gui, ">", C.red, function()
		Tank.close()
	end, { Size = UDim2.fromOffset(48, 60), Position = UDim2.new(1, -116 - 400 - 4, 0.46, 0), AnchorPoint = Vector2.new(1, 0.5) })
	tab.Name = "CloseTab"
end

function Tank.open()
	if not gui then
		return
	end
	isOpen = true
	lastSig = ""
	gui.Enabled = true
	panel.Position = UDim2.new(1, 300, 0.46, 0)
	TweenService:Create(panel, TweenInfo.new(0.25, Enum.EasingStyle.Back), { Position = UDim2.new(1, -116, 0.46, 0) }):Play()
	render(State.data)
end

function Tank.close()
	isOpen = false
	if gui then
		gui.Enabled = false
	end
end

function Tank.toggle()
	if isOpen then
		Tank.close()
	else
		Tank.open()
	end
end

function Tank.start()
	build()
	State.Changed:Connect(render)
	player:GetAttributeChangedSignal("Cinematic"):Connect(function()
		if player:GetAttribute("Cinematic") then
			Tank.close()
		end
	end)
end

return Tank
