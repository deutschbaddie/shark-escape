-- The Tank window (opens from the tank button): your whole catch.
--   status:  3 / 4 ACTIVE      +$42/s      Dead 2 / 10
--   list:    creature · rarity · $/s (bar vs your best) · EQUIP / UNEQUIP
--   footer:  [EQUIP BEST]  [+1 SLOT $400]
-- Active creatures swim in your tank and earn; the rest lie on the floor.

local Players = game:GetService("Players")

local Shared = game.ReplicatedStorage.Shared
local Config = require(Shared.Config)
local UI = require(script.Parent.UI)
local State = require(script.Parent.State)
local Shop = require(script.Parent.Shop)

local Tank = {}
local T = UI.T
local player = Players.LocalPlayer

local gui: ScreenGui
local window: Frame? = nil
local list: ScrollingFrame
local activeText: TextLabel
local incomeText: TextLabel
local deadText: TextLabel
local slotBtn: TextButton
local isOpen = false
local lastSig = ""

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
	activeText.Text = ("%d / %d"):format(d.active, d.slots)
	incomeText.Text = ("+$%s/s"):format(Config.formatRate(d.income))
	local maxDead = d.maxDead or Config.Tank.maxDead
	deadText.Text = ("%d / %d"):format(d.dead or 0, maxDead)
	deadText.TextColor3 = (d.dead or 0) >= maxDead and T.red or T.white
	if d.slotPrice then
		UI.setText(slotBtn, ("+1 SLOT  $%s"):format(UI.short(d.slotPrice)))
		slotBtn.BackgroundColor3 = d.coins >= d.slotPrice and T.green or T.navyLight
	else
		UI.setText(slotBtn, "MAX SLOTS")
		slotBtn.BackgroundColor3 = T.navyLight
	end
end

local function row(c: any, order: number, best: number, free: boolean)
	local color = Shop.rarityColor(c.r)
	local f = UI.card(list, c.e and T.green or nil, { Size = UDim2.new(1, 0, 0, 84), LayoutOrder = order,
		BackgroundColor3 = c.e and T.navyLight or UI.dark(T.navyLight, 0.2) })
	Shop.thumb(f, c, { Size = UDim2.fromOffset(68, 68), Position = UDim2.fromOffset(8, 8) })
	UI.label(f, "body", Config.fullName(c.z, c.r, c.m, c.s), { Size = UDim2.new(1, -372, 0, 26), Position = UDim2.fromOffset(88, 10),
		TextXAlignment = Enum.TextXAlignment.Left })
	UI.chip(f, c.r:upper(), color, { Size = UDim2.fromOffset(104, 24), Position = UDim2.fromOffset(88, 46) })
	UI.label(f, "meta", Config.formatKg(Config.creatureKg(c.z, c.r, c.s)), { Size = UDim2.fromOffset(80, 20), Position = UDim2.fromOffset(200, 48),
		TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = T.mute })
	-- $/s with a bar against your best creature: easy to compare
	UI.label(f, "body", ("$%s/s"):format(Config.formatRate(c.v)), { Size = UDim2.fromOffset(120, 26), Position = UDim2.new(1, -150, 0, 14), AnchorPoint = Vector2.new(1, 0),
		TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = c.e and UI.C.money or T.mute })
	local _, fill = UI.bar(f, c.e and T.green or T.mute, { Size = UDim2.fromOffset(120, 14), Position = UDim2.new(1, -150, 0, 50), AnchorPoint = Vector2.new(1, 0) })
	UI.setBar(fill, c.v / math.max(best, 1), true)
	local btn = { Size = UDim2.fromOffset(124, 56), Position = UDim2.new(1, -10, 0.5, 0), AnchorPoint = Vector2.new(1, 0.5) }
	if c.e then
		UI.button(f, "UNEQUIP", T.mute, function()
			State.action("unequip", c.id)
		end, btn)
	elseif free then
		UI.button(f, "EQUIP", T.green, function()
			State.action("equip", c.id)
		end, btn)
	else
		Shop.plate(f, "FULL", T.mute, btn)
	end
end

local function renderList(d: any)
	for _, k in list:GetChildren() do
		if k:IsA("Frame") then
			k:Destroy()
		end
	end
	local free = d.active < d.slots
	local best = 0
	for _, c in d.creatures do
		best = math.max(best, c.v)
	end
	for i, c in sorted(d) do
		row(c, i, best, free)
	end
	if #d.creatures == 0 then
		local empty = UI.inset(list, { Size = UDim2.new(1, 0, 0, 96) })
		UI.icon(empty, "Fish", { Size = UDim2.fromOffset(64, 64), Position = UDim2.new(0, 16, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5) })
		UI.label(empty, "body", "Your tank is empty", { Size = UDim2.new(1, -112, 0, 26), Position = UDim2.fromOffset(96, 20), TextXAlignment = Enum.TextXAlignment.Left })
		UI.label(empty, "meta", "Grab a creature bubble and bring it home!", { Size = UDim2.new(1, -112, 0, 20), Position = UDim2.fromOffset(96, 52),
			TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = T.mute })
	end
end

local function render(d: any?)
	if not (isOpen and window and d) then
		return
	end
	renderHeader(d)
	local sig = signature(d)
	if sig ~= lastSig then
		lastSig = sig
		renderList(d)
	end
end

-- one stat in the status strip: caption over a big value
local function stat(parent: Instance, x: number, caption: string, color: Color3?): TextLabel
	local cell = UI.frame(parent, { Size = UDim2.new(1 / 3, 0, 1, 0), Position = UDim2.fromScale(x / 3, 0), BackgroundTransparency = 1 })
	UI.label(cell, "meta", caption, { Size = UDim2.new(1, -16, 0, 18), Position = UDim2.fromOffset(8, 6), TextColor3 = T.mute })
	return UI.label(cell, "value", "", { Size = UDim2.new(1, -16, 0, 32), Position = UDim2.fromOffset(8, 24), Font = UI.NUMFONT, TextColor3 = color })
end

local function build()
	local f, body = UI.window(gui, "Your Tank", T.blue, Vector2.new(640, 470), function()
		Tank.close()
	end, "Tank")
	window = f
	local strip = UI.inset(body, { Size = UDim2.new(1, 0, 0, 64) })
	activeText = stat(strip, 0, "ACTIVE")
	incomeText = stat(strip, 1, "EARNING", UI.C.money)
	deadText = stat(strip, 2, "DEAD FISH")
	for i = 1, 2 do
		UI.frame(strip, { Size = UDim2.new(0, 2, 1, -20), Position = UDim2.new(i / 3, -1, 0, 10), BackgroundColor3 = T.line, BackgroundTransparency = 0.5 })
	end

	list = Shop.list(body, { Size = UDim2.new(1, 8, 1, -148), Position = UDim2.fromOffset(-4, 76) }, 8)

	UI.button(body, "EQUIP BEST", T.green, function()
		State.action("equipBest")
	end, { Size = UDim2.new(0.5, -6, 0, 56), Position = UDim2.new(0, 0, 1, 0), AnchorPoint = Vector2.new(0, 1) })
	slotBtn = UI.button(body, "", T.green, function()
		State.action("buySlot")
	end, { Size = UDim2.new(0.5, -6, 0, 56), Position = UDim2.new(1, 0, 1, 0), AnchorPoint = Vector2.new(1, 1) })
end

function Tank.open()
	if not gui or isOpen then
		return
	end
	isOpen = true
	lastSig = ""
	gui.Enabled = true
	build()
	render(State.data)
end

function Tank.close()
	isOpen = false
	if window then
		local w = window
		window = nil
		w:Destroy()
	end
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
	gui = Instance.new("ScreenGui")
	gui.Name = "Tank"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 9
	gui.Enabled = false
	gui.Parent = player:WaitForChild("PlayerGui")
	UI.autoScale(gui, Vector2.new(660, 480))
	State.Changed:Connect(render)
	player:GetAttributeChangedSignal("Cinematic"):Connect(function()
		if player:GetAttribute("Cinematic") then
			Tank.close()
		end
	end)
end

return Tank
