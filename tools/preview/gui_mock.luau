-- GUI stand-ins so the real client UI code (UI.luau, HUD.luau, Notify.luau)
-- can build its ScreenGuis in the plain Luau CLI. Only layout-relevant
-- properties matter; everything else is accepted and ignored.
-- Loaded after mock.luau (Vector3/CFrame/Color3/Enum/Instance basics).

local function signal()
	return { Connect = function() return { Disconnect = function() end } end, Once = function() end,
		-- waiting on a signal parks the coroutine for good (no time passes in the preview)
		Wait = function() if coroutine.isyieldable() then coroutine.yield() end return 0 end }
end

UDim = { new = function(s, o) return { Scale = s or 0, Offset = o or 0 } end }
local U2 = {}
U2.__index = U2
local function udim2(xs, xo, ys, yo)
	return setmetatable({ X = { Scale = xs or 0, Offset = xo or 0 }, Y = { Scale = ys or 0, Offset = yo or 0 } }, U2)
end
U2.__add = function(a, b) return udim2(a.X.Scale + b.X.Scale, a.X.Offset + b.X.Offset, a.Y.Scale + b.Y.Scale, a.Y.Offset + b.Y.Offset) end
UDim2 = {
	new = udim2,
	fromOffset = function(x, y) return udim2(0, x or 0, 0, y or 0) end,
	fromScale = function(x, y) return udim2(x or 0, 0, y or 0, 0) end,
}
Vector2 = { new = function(x, y) return setmetatable({ X = x or 0, Y = y or 0 }, {
	__add = function(a, b) return Vector2.new(a.X + b.X, a.Y + b.Y) end,
	__sub = function(a, b) return Vector2.new(a.X - b.X, a.Y - b.Y) end,
	__index = function(t, k) if k == "Magnitude" then return math.sqrt(t.X * t.X + t.Y * t.Y) end return nil end,
}) end }
Vector2.zero = Vector2.new(0, 0)
Rect = { new = function(a, b, c, d) return { Min = Vector2.new(a, b), Max = Vector2.new(c, d) } end }
NumberSequenceKeypoint = { new = function(t, v) return { Time = t, Value = v } end }
ColorSequenceKeypoint = { new = function(t, v) return { Time = t, Value = v } end }
NumberSequence = { new = function(...) return { ... } end }
ColorSequence = { new = function(...) return { ... } end }
TweenInfo = { new = function() return {} end }
NumberRange = { new = function() return {} end }

-- generic GUI instance: any property can be set; signals on demand
GUI_ROOTS = {}
local G = {}
local SIGNALS = { Activated = true, MouseButton1Down = true, MouseButton1Up = true, MouseEnter = true, MouseLeave = true,
	InputBegan = true, InputEnded = true, InputChanged = true, Changed = true, AncestryChanged = true, DescendantAdded = true, Destroying = true, Ended = true, Event = true }
function G:Play() end
function G:Stop() end
function G:Pause() end
function G:Resume() end
G.__index = function(t, k)
	local p = rawget(t, "_p")
	if p[k] ~= nil then
		return p[k]
	end
	if G[k] then
		return G[k]
	end
	if SIGNALS[k] then
		return signal()
	end
	if k == "AbsoluteSize" then
		-- a ScreenGui with CoreUISafeInsets: the screen minus the Roblox top bar
		if p.ClassName == "ScreenGui" then
			return Vector2.new(VIEWPORT.X, VIEWPORT.Y - 58)
		end
		return Vector2.new(0, 0)
	end
	return nil
end
G.__newindex = function(t, k, v)
	local p = rawget(t, "_p")
	if k == "Parent" then
		local old = p.Parent
		if old then
			local kids = rawget(old, "_p")._kids
			for i, c in kids do
				if c == t then
					table.remove(kids, i)
					break
				end
			end
		end
		if v then
			table.insert(rawget(v, "_p")._kids, t)
		end
	end
	p[k] = v
end
function G:GetChildren() return table.clone(rawget(self, "_p")._kids) end
function G:GetDescendants()
	local out = {}
	local function walk(n) for _, c in rawget(n, "_p")._kids do table.insert(out, c); walk(c) end end
	walk(self)
	return out
end
function G:FindFirstChild(n) for _, c in rawget(self, "_p")._kids do if c.Name == n then return c end end return nil end
function G:FindFirstChildOfClass(cl) for _, c in rawget(self, "_p")._kids do if c.ClassName == cl then return c end end return nil end
function G:FindFirstChildWhichIsA(cl) return self:FindFirstChildOfClass(cl) end
function G:WaitForChild(n) return self:FindFirstChild(n) end
function G:IsA(cl)
	local c = self.ClassName
	if cl == c then return true end
	if cl == "GuiObject" then return c ~= "ScreenGui" and not c:match("^UI") end
	if cl == "GuiButton" then return c == "TextButton" or c == "ImageButton" end
	return false
end
function G:Destroy() self.Parent = nil end
function G:ClearAllChildren() for _, c in self:GetChildren() do c.Parent = nil end end
function G:SetAttribute(k, v) rawget(self, "_p")._attr[k] = v end
function G:GetAttribute(k) return rawget(self, "_p")._attr[k] end
function G:GetPropertyChangedSignal() return signal() end
function G:GetAttributeChangedSignal() return signal() end
function G:IsDescendantOf() return false end
function G:FindFirstAncestorOfClass() return nil end

local DEFAULTS = {
	BackgroundTransparency = 0, Visible = true, Position = UDim2.new(0, 0, 0, 0), Size = UDim2.new(0, 100, 0, 100),
	AnchorPoint = Vector2.new(0, 0), ZIndex = 1, LayoutOrder = 0, TextTransparency = 0, ImageTransparency = 0, Transparency = 0,
	Text = "", TextBounds = Vector2.new(140, 20), TextScaled = false, TextSize = 14, Rotation = 0, Enabled = true, Thickness = 1,
}
local function newGui(class)
	local p = { ClassName = class, Name = class, _kids = {}, _attr = {} }
	for k, v in DEFAULTS do
		p[k] = v
	end
	return setmetatable({ _p = p }, G)
end

local oldNew = Instance.new
Instance.new = function(class)
	if class:match("^UI") or class:match("Gui$") or class:match("Label$") or class:match("Button$") or class == "Frame"
		or class == "ScrollingFrame" or class == "ViewportFrame" or class == "TextBox" or class == "Folder" or class == "Highlight" or class == "BindableEvent" or class == "Sound" or class:match("SoundEffect$") or class == "SoundGroup" then
		local g = newGui(class)
		if class == "ScreenGui" then
			table.insert(GUI_ROOTS, g)
		end
		return g
	end
	return oldNew(class)
end

-- services
local playerGui = newGui("PlayerGui")
local localPlayer = newGui("Player")
localPlayer.Name = "Player"
localPlayer.UserId = 1
localPlayer.DisplayName = "Tufferson"
playerGui.Name = "PlayerGui"
playerGui.Parent = localPlayer
VIEWPORT = Vector2.new(1600, 900)
TOUCH = false
local camera = { ViewportSize = VIEWPORT, GetPropertyChangedSignal = function() return signal() end, CFrame = CFrame.new(), FieldOfView = 70 }
workspace = newGui("Workspace")
workspace.CurrentCamera = camera
local services = {
	Players = { LocalPlayer = localPlayer, PlayerAdded = signal(), PlayerRemoving = signal(), GetPlayers = function() return {} end },
	-- tweens jump straight to their goal (the preview shows the settled screen)
	TweenService = { Create = function(_, inst, _, goal)
		return { Play = function() for k, v in goal or {} do inst[k] = v end end, Completed = signal(), Cancel = function() end }
	end },
	RunService = { Heartbeat = signal(), RenderStepped = signal(), PreSimulation = signal(), Stepped = signal(),
		BindToRenderStep = function() end, UnbindFromRenderStep = function() end, IsStudio = function() return true end },
	UserInputService = setmetatable({}, { __index = function(_, k)
		if k == "TouchEnabled" then return TOUCH end
		if k == "KeyboardEnabled" then return not TOUCH end
		return signal()
	end }),
	Workspace = workspace,
	MarketplaceService = {},
	GuiService = { MenuOpened = signal(), MenuClosed = signal(), GetGuiInset = function() return Vector2.new(0, 36) end },
	SoundService = Instance.new("Folder"),
	Debris = { AddItem = function() end },
	Lighting = { FindFirstChild = function() return nil end, FindFirstChildOfClass = function() return nil end },
	CollectionService = { AddTag = function() end, GetTagged = function() return {} end, GetInstanceAddedSignal = function() return signal() end,
		GetInstanceRemovedSignal = function() return signal() end },
	ReplicatedStorage = setmetatable({ GetAttribute = function() return nil end, GetAttributeChangedSignal = function() return signal() end },
		{ __index = function(_, k) return nil end }),
	ProximityPromptService = { PromptShown = signal(), PromptHidden = signal(), PromptTriggered = signal() },
	SocialService = {},
}
game = { GetService = function(_, name) return services[name] or {} end }
