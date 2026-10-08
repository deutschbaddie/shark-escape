-- Minimal Roblox stand-ins so shared modules can run in the plain Luau CLI.
local V = {}
V.__index = V
local function vec(x, y, z) return setmetatable({ X = x or 0, Y = y or 0, Z = z or 0 }, V) end
V.__add = function(a, b) return vec(a.X + b.X, a.Y + b.Y, a.Z + b.Z) end
V.__sub = function(a, b) return vec(a.X - b.X, a.Y - b.Y, a.Z - b.Z) end
V.__unm = function(a) return vec(-a.X, -a.Y, -a.Z) end
V.__mul = function(a, b)
	if type(a) == "number" then a, b = b, a end
	if type(b) == "number" then return vec(a.X * b, a.Y * b, a.Z * b) end
	return vec(a.X * b.X, a.Y * b.Y, a.Z * b.Z)
end
V.__div = function(a, b) return vec(a.X / b, a.Y / b, a.Z / b) end
V.__index = function(t, k)
	if k == "Magnitude" then return math.sqrt(t.X * t.X + t.Y * t.Y + t.Z * t.Z) end
	if k == "Unit" then local m = math.sqrt(t.X * t.X + t.Y * t.Y + t.Z * t.Z); return vec(t.X / m, t.Y / m, t.Z / m) end
	return V[k]
end
function V:Dot(b) return self.X * b.X + self.Y * b.Y + self.Z * b.Z end
function V:Lerp(b, t) return self + (b - self) * t end
Vector3 = { new = vec, zero = vec(0, 0, 0), yAxis = vec(0, 1, 0), xAxis = vec(1, 0, 0) }
Vector2 = { new = function(x, y) return { X = x, Y = y } end, zero = { X = 0, Y = 0 } }

local C = {}
local function cf(p, r) -- r = 3x3 rows
	return setmetatable({ p = p, r = r or { { 1, 0, 0 }, { 0, 1, 0 }, { 0, 0, 1 } } }, C)
end
local function mm(a, b)
	local o = {}
	for i = 1, 3 do
		o[i] = {}
		for j = 1, 3 do
			o[i][j] = a[i][1] * b[1][j] + a[i][2] * b[2][j] + a[i][3] * b[3][j]
		end
	end
	return o
end
local function mv(r, v) return vec(r[1][1] * v.X + r[1][2] * v.Y + r[1][3] * v.Z, r[2][1] * v.X + r[2][2] * v.Y + r[2][3] * v.Z, r[3][1] * v.X + r[3][2] * v.Y + r[3][3] * v.Z) end
C.__mul = function(a, b)
	if getmetatable(b) == C then return cf(a.p + mv(a.r, b.p), mm(a.r, b.r)) end
	return a.p + mv(a.r, b)
end
C.__add = function(a, v) return cf(a.p + v, a.r) end
function C.Inverse(a)
	local t = { { a.r[1][1], a.r[2][1], a.r[3][1] }, { a.r[1][2], a.r[2][2], a.r[3][2] }, { a.r[1][3], a.r[2][3], a.r[3][3] } }
	return cf(-mv(t, a.p), t)
end
C.__index = function(t, k)
	if k == "Position" then return t.p end
	if k == "Rotation" then return cf(vec(0, 0, 0), t.r) end
	return C[k]
end
local function rx(a) return { { 1, 0, 0 }, { 0, math.cos(a), -math.sin(a) }, { 0, math.sin(a), math.cos(a) } } end
local function ry(a) return { { math.cos(a), 0, math.sin(a) }, { 0, 1, 0 }, { -math.sin(a), 0, math.cos(a) } } end
local function rz(a) return { { math.cos(a), -math.sin(a), 0 }, { math.sin(a), math.cos(a), 0 }, { 0, 0, 1 } } end
CFrame = {
	new = function(x, y, z)
		if type(x) == "table" then return cf(x) end
		return cf(vec(x or 0, y or 0, z or 0))
	end,
	Angles = function(a, b, c) return cf(vec(0, 0, 0), mm(mm(rx(a), ry(b)), rz(c))) end,
	identity = cf(vec(0, 0, 0)),
	lookAt = function(at, target)
		local f = (target - at).Unit
		local r = vec(-f.Z, 0, f.X) -- right = forward x up
		local rm = r.Magnitude
		r = rm > 1e-6 and r / rm or vec(1, 0, 0)
		local u = vec(r.Y * f.Z - r.Z * f.Y, r.Z * f.X - r.X * f.Z, r.X * f.Y - r.Y * f.X)
		-- columns: right, up, back (-forward)
		return cf(at, { { r.X, u.X, -f.X }, { r.Y, u.Y, -f.Y }, { r.Z, u.Z, -f.Z } })
	end,
}

local Col = {}
Col.__index = Col
local function col(r, g, b) return setmetatable({ R = r, G = g, B = b }, Col) end
function Col:Lerp(o, t) return col(self.R + (o.R - self.R) * t, self.G + (o.G - self.G) * t, self.B + (o.B - self.B) * t) end
function Col:ToHSV()
	local r, g, b = self.R, self.G, self.B
	local mx, mn = math.max(r, g, b), math.min(r, g, b)
	local d = mx - mn
	local h = 0
	if d > 0 then
		if mx == r then h = ((g - b) / d) % 6 elseif mx == g then h = (b - r) / d + 2 else h = (r - g) / d + 4 end
		h /= 6
	end
	return h, mx > 0 and d / mx or 0, mx
end
local function hsv(h, s, v)
	local i = math.floor(h * 6) % 6
	local f = h * 6 - math.floor(h * 6)
	local p, q, t = v * (1 - s), v * (1 - f * s), v * (1 - (1 - f) * s)
	local m = { { v, t, p }, { q, v, p }, { p, v, t }, { p, q, v }, { t, p, v }, { v, p, q } }
	local c = m[i + 1]
	return col(c[1], c[2], c[3])
end
Color3 = { new = col, fromRGB = function(r, g, b) return col(r / 255, g / 255, b / 255) end, fromHSV = hsv }

local function enumProxy(name)
	return setmetatable({}, { __index = function(_, k) return { Name = k, EnumType = name, Value = 0 } end })
end
Enum = setmetatable({}, { __index = function(_, k) return enumProxy(k) end })
NumberSequence = { new = function() return {} end }
ColorSequence = { new = function() return {} end }

PARTS = {}
local Inst = {}
local DUMMY_SIGNAL = { Connect = function() return { Disconnect = function() end } end, Once = function() return { Disconnect = function() end } end }
Inst.__index = function(t, k)
	if Inst[k] then return Inst[k] end
	local v = rawget(t, "_p")[k]
	if v == nil and (k == "Ended" or k == "Destroying" or k == "Changed") then
		return DUMMY_SIGNAL
	end
	return v
end
Inst.__newindex = function(t, k, v)
	local p = rawget(t, "_p")
	if k == "Parent" then
		local old = p.Parent
		if old then
			for i, c in old._kids do if c == t then table.remove(old._kids, i) break end end
		end
		if v then table.insert(v._kids, t) end
	end
	p[k] = v
end
function Inst:Play() end
function Inst:Stop() end
function Inst:Pause() end
function Inst:Resume() end
function Inst:SetAttribute(k, v) rawget(self, "_p")._attr[k] = v end
function Inst:GetAttribute(k) return rawget(self, "_p")._attr[k] end
function Inst:GetDescendants()
	local out = {}
	local function walk(n) for _, c in n._kids do table.insert(out, c); walk(c) end end
	walk(self)
	return out
end
function Inst:GetChildren() return table.clone(self._kids) end
function Inst:FindFirstChildWhichIsA(c) for _, k in self._kids do if k:IsA(c) then return k end end return nil end
function Inst:FindFirstChild(n) for _, k in self._kids do if k.Name == n then return k end end return nil end
function Inst:IsA(c) return self.ClassName == c or (c == "BasePart" and (self.ClassName == "Part" or self.ClassName == "WedgePart")) end
Instance = {
	new = function(class)
		local t = setmetatable({ _p = { ClassName = class, _attr = {}, _kids = {}, Transparency = 0, Material = { Name = "SmoothPlastic" } } }, Inst)
		rawget(t, "_p")._kids = {}
		if class == "Part" or class == "WedgePart" then table.insert(PARTS, t) end
		return t
	end,
}
-- _kids lives in _p; expose
Inst._kids = nil
setmetatable(Inst, nil)

game = { GetService = function(_, name) return { AddTag = function() end, GetTagged = function() return {} end } end }
Random = {
	new = function(seed)
		local x = (seed or 1) * 7919 % 2147483647
		local function nxt() x = x * 48271 % 2147483647 return x / 2147483647 end
		return {
			NextNumber = function(_, a, b) return (a or 0) + nxt() * ((b or 1) - (a or 0)) end,
			NextInteger = function(_, a, b) return a + math.floor(nxt() * (b - a + 1)) end,
		}
	end,
}
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
	Text = "", TextScaled = false, TextSize = 14, Rotation = 0, Enabled = true, Thickness = 1,
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
		or class == "ScrollingFrame" or class == "ViewportFrame" or class == "Folder" or class == "Highlight" or class == "BindableEvent" or class == "Sound" or class:match("SoundEffect$") or class == "SoundGroup" then
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

VIEWPORT = Vector2.new(1600, 900)
workspace.CurrentCamera.ViewportSize = VIEWPORT
TOUCH = false
MODULES = {}
local LOADED = {}
SHARED = setmetatable({}, { __index = function(_, k) return "mod:" .. k end })
CLIENT = setmetatable({}, { __index = function(_, k) return "cmod:" .. k end })
game.ReplicatedStorage = game:GetService("ReplicatedStorage")
rawset(game.ReplicatedStorage, "Shared", SHARED)
function require(x)
	if LOADED[x] == nil then
		local f = MODULES[x]
		assert(f, "no module " .. tostring(x))
		LOADED[x] = f()
	end
	return LOADED[x]
end
-- task: coroutines that run until their first wait (no time passes)
task = {
	spawn = function(f, ...) local co = coroutine.create(f); coroutine.resume(co, ...); return co end,
	delay = function() end,
	defer = function() end,
	wait = function() if coroutine.isyieldable() then coroutine.yield() end return 0 end,
}
MODULES['mod:Config'] = function()
local script = { Parent = SHARED }
-- Every tunable number in the game lives here. Balance numbers are starting
-- guesses from the REVEX ladder - tune them by playtesting, not by feel.

local Config = {}

----------------------------------------------------------------- world
Config.LANE_WIDTH = 288 -- playable ocean width (studs)
Config.SHORE_Z = 0 -- water starts here; ocean runs toward +Z
Config.WATER_Y = 0 -- terrain water surface
Config.FLOOR_TOP = 0.15 -- hidden floor players ride on (just above the surface)
Config.BEACH_TOP = 2
Config.PLOT_COUNT = 8
Config.PLOT_SPACING = 36
Config.PLOT_Z = -34

----------------------------------------------------------------- speed
-- Displayed speed climbs forever; real WalkSpeed follows a capped curve so
-- physics never breaks. 0 -> 16, 100 -> 58, 1K -> 106, 25K -> 279.
function Config.realSpeed(speed: number): number
	return math.min(16 + 9 * math.max(speed, 0) ^ (1 / 3), 320)
end

----------------------------------------------------------------- zones
type Zone = {
	id: string,
	name: string,
	gate: number,
	length: number,
	depth: number,
	shark: string,
	sharkLength: number,
	sharkSpeed: number,
	value: number,
	islandEvery: number,
	islandRadius: number,
	water: Color3,
	clarity: number,
	floor: Enum.Material,
	floorColor: Color3,
	tint: Color3,
	zStart: number,
	zEnd: number,
	index: number,
}

Config.Zones = {
	{ id = "Lagoon", name = "Lagoon", gate = 0, length = 260, depth = 7, shark = "Baby", sharkLength = 8,
		sharkSpeed = 44, value = 1, islandEvery = 70, islandRadius = 11,
		water = Color3.fromRGB(40, 222, 226), clarity = 0.92, floor = Enum.Material.Sand,
		floorColor = Color3.fromRGB(255, 240, 196), tint = Color3.fromRGB(255, 255, 255) },
	{ id = "Reef", name = "Coral Reef", gate = 100, length = 400, depth = 12, shark = "Hammerhead", sharkLength = 12,
		sharkSpeed = 80, value = 5, islandEvery = 95, islandRadius = 10,
		water = Color3.fromRGB(26, 196, 222), clarity = 0.85, floor = Enum.Material.Sandstone,
		floorColor = Color3.fromRGB(246, 214, 170), tint = Color3.fromRGB(255, 250, 252) },
	{ id = "Kelp", name = "Kelp Forest", gate = 500, length = 560, depth = 18, shark = "Tiger", sharkLength = 14,
		sharkSpeed = 102, value = 25, islandEvery = 120, islandRadius = 9,
		water = Color3.fromRGB(24, 170, 170), clarity = 0.72, floor = Enum.Material.Mud,
		floorColor = Color3.fromRGB(92, 128, 80), tint = Color3.fromRGB(244, 255, 246) },
	{ id = "Shipwreck", name = "Shipwreck Bay", gate = 1000, length = 720, depth = 26, shark = "GreatWhite", sharkLength = 18,
		sharkSpeed = 140, value = 120, islandEvery = 150, islandRadius = 9,
		water = Color3.fromRGB(20, 132, 190), clarity = 0.6, floor = Enum.Material.Ground,
		floorColor = Color3.fromRGB(110, 96, 78), tint = Color3.fromRGB(240, 248, 255) },
	{ id = "Deep", name = "Deep Blue", gate = 5000, length = 1000, depth = 48, shark = "Mecha", sharkLength = 22,
		sharkSpeed = 215, value = 600, islandEvery = 210, islandRadius = 8,
		water = Color3.fromRGB(16, 84, 170), clarity = 0.45, floor = Enum.Material.Slate,
		floorColor = Color3.fromRGB(46, 58, 84), tint = Color3.fromRGB(228, 238, 255) },
	{ id = "Abyss", name = "The Abyss", gate = 25000, length = 1400, depth = 80, shark = "Megalodon", sharkLength = 40,
		sharkSpeed = 300, value = 3000, islandEvery = 300, islandRadius = 8,
		water = Color3.fromRGB(28, 34, 92), clarity = 0.3, floor = Enum.Material.Basalt,
		floorColor = Color3.fromRGB(30, 26, 46), tint = Color3.fromRGB(236, 226, 255) },
} :: { Zone }

do
	local z = Config.SHORE_Z
	for i, zone in Config.Zones do
		zone.index = i
		zone.zStart = z
		zone.zEnd = z + zone.length
		z = zone.zEnd
	end
end
Config.OCEAN_END = Config.Zones[#Config.Zones].zEnd

function Config.zoneAt(z: number): Zone?
	if z < Config.SHORE_Z then
		return nil
	end
	for _, zone in Config.Zones do
		if z < zone.zEnd then
			return zone
		end
	end
	return Config.Zones[#Config.Zones]
end

function Config.zoneById(id: string): Zone?
	for _, zone in Config.Zones do
		if zone.id == id then
			return zone
		end
	end
	return nil
end

-- the furthest zone this speed is allowed into
function Config.zoneForSpeed(speed: number): Zone
	local best = Config.Zones[1]
	for _, zone in Config.Zones do
		if speed >= zone.gate then
			best = zone
		end
	end
	return best
end

function Config.nextGate(speed: number): Zone?
	for _, zone in Config.Zones do
		if speed < zone.gate then
			return zone
		end
	end
	return nil
end

----------------------------------------------------------------- rides
-- No levels. Every ride is a named item; owning a better one raises your
-- speed gain. The best coin ride you own sets your base +speed/sec.
type Ride = {
	id: string,
	name: string,
	icon: string,
	price: number,
	gain: number?,
	robux: string?,
	mult: number?,
	order: number,
}

Config.Rides = {
	{ id = "Noodle", name = "Pool Noodle", icon = "", price = 0, gain = 1 },
	{ id = "Duck", name = "Rubber Duck Floatie", icon = "", price = 30, gain = 2 },
	{ id = "Tube", name = "Inner Tube", icon = "", price = 150, gain = 3 },
	{ id = "Boogie", name = "Boogie Board", icon = "", price = 600, gain = 4 },
	{ id = "Surf", name = "Surfboard", icon = "", price = 2000, gain = 5 },
	{ id = "Bathtub", name = "Bathtub", icon = "", price = 7000, gain = 7 },
	{ id = "Banana", name = "Banana Boat", icon = "", price = 24000, gain = 9 },
	{ id = "JetSki", name = "Jet Ski", icon = "", price = 80000, gain = 12 },
	{ id = "Speedboat", name = "Speedboat", icon = "", price = 270000, gain = 16 },
	{ id = "Dolphin", name = "Dolphin", icon = "", price = 900000, gain = 22 },
	{ id = "Donut", name = "Giant Donut", icon = "", price = 3000000, gain = 30 },
	{ id = "Rocket", name = "Rocket Surfboard", icon = "", price = 10000000, gain = 40 },
	-- Robux rides: never skip the ladder, they multiply it.
	{ id = "GoldDuck", name = "Golden Duck", icon = "", price = 0, robux = "GoldDuck", mult = 1.25 },
	{ id = "SharkBoard", name = "Shark Board", icon = "", price = 0, robux = "SharkBoard", mult = 1.5 },
	{ id = "RainbowSki", name = "Rainbow Jet Ski", icon = "", price = 0, robux = "RainbowSki", mult = 2 },
} :: { Ride }

for i, ride in Config.Rides do
	ride.order = i
end

function Config.ride(id: string): Ride?
	for _, ride in Config.Rides do
		if ride.id == id then
			return ride
		end
	end
	return nil
end

-- How each ride handles on the water (client ride controller):
--   stance   pose: stand / sit / straddle / prone / float
--   accel    seconds to reach top speed      coast  seconds to drift to a stop
--   turn     turn rate (rad/s)               grip   how fast sideways slide dies
--   lean     roll into turns                 plane  nose-up at speed
--   bob      bob height (studs), bobSpeed    wobble idle side-to-side yaw
--   porpoise dolphin-style dive arcs         hop    jump velocity
type RideFeel = {
	stance: string, accel: number, coast: number, turn: number, grip: number, lean: number,
	bob: number, bobSpeed: number, plane: number?, wobble: number?, porpoise: boolean?, hop: number?,
}
Config.RideFeel = {
	Noodle = { stance = "float", accel = 1.0, coast = 1.4, turn = 2.8, grip = 3, lean = 0.1, bob = 0.3, bobSpeed = 2.0, wobble = 0.06 },
	Duck = { stance = "sit", accel = 0.9, coast = 1.2, turn = 3.0, grip = 3.5, lean = 0.12, bob = 0.45, bobSpeed = 3.2, wobble = 0.1 },
	Tube = { stance = "sit", accel = 0.9, coast = 1.8, turn = 2.4, grip = 1.6, lean = 0.08, bob = 0.35, bobSpeed = 2.4, wobble = 0.25 },
	Boogie = { stance = "prone", accel = 0.8, coast = 1.2, turn = 3.4, grip = 4, lean = 0.3, bob = 0.2, bobSpeed = 3 },
	Surf = { stance = "stand", accel = 0.7, coast = 1.5, turn = 3.2, grip = 4.5, lean = 0.55, bob = 0.15, bobSpeed = 2.5, plane = 0.05 },
	Bathtub = { stance = "sit", accel = 1.4, coast = 2.2, turn = 1.8, grip = 2.2, lean = 0.06, bob = 0.25, bobSpeed = 1.6, wobble = 0.12 },
	Banana = { stance = "straddle", accel = 0.9, coast = 1.4, turn = 2.0, grip = 3, lean = 0.2, bob = 0.35, bobSpeed = 2.8 },
	JetSki = { stance = "straddle", accel = 0.45, coast = 1.0, turn = 4.2, grip = 2.2, lean = 0.6, bob = 0.18, bobSpeed = 4, plane = 0.12 },
	Speedboat = { stance = "straddle", accel = 0.6, coast = 1.3, turn = 2.6, grip = 3.5, lean = 0.25, bob = 0.12, bobSpeed = 3, plane = 0.18 },
	Dolphin = { stance = "straddle", accel = 0.5, coast = 1.2, turn = 4.6, grip = 5, lean = 0.4, bob = 1.1, bobSpeed = 3.4, porpoise = true, hop = 40 },
	Donut = { stance = "sit", accel = 0.8, coast = 2.0, turn = 3.0, grip = 1.2, lean = 0.1, bob = 0.4, bobSpeed = 2.6, wobble = 0.35 },
	Rocket = { stance = "stand", accel = 0.3, coast = 0.9, turn = 3.0, grip = 5, lean = 0.45, bob = 0.1, bobSpeed = 6, plane = 0.1 },
} :: { [string]: RideFeel }
Config.RideFeel.GoldDuck = Config.RideFeel.Duck
Config.RideFeel.SharkBoard = { stance = "stand", accel = 0.6, coast = 1.4, turn = 3.6, grip = 4.5, lean = 0.6, bob = 0.15, bobSpeed = 2.5, plane = 0.06 }
Config.RideFeel.RainbowSki = Config.RideFeel.JetSki

function Config.feel(rideId: string?): RideFeel
	return Config.RideFeel[rideId or "Noodle"] or Config.RideFeel.Noodle
end

----------------------------------------------------------------- creatures
type Rarity = { id: string, weight: number, mult: number, color: Color3, species: string, icon: string, index: number }

Config.Rarities = {
	{ id = "Common", weight = 60, mult = 1, color = Color3.fromRGB(205, 214, 224), species = "Clownfish", icon = "" },
	{ id = "Uncommon", weight = 25, mult = 2.5, color = Color3.fromRGB(96, 214, 110), species = "Pufferfish", icon = "" },
	{ id = "Rare", weight = 10, mult = 6, color = Color3.fromRGB(64, 156, 255), species = "Octopus", icon = "" },
	{ id = "Epic", weight = 4, mult = 25, color = Color3.fromRGB(190, 92, 255), species = "Sea Turtle", icon = "" },
	{ id = "Legendary", weight = 1, mult = 120, color = Color3.fromRGB(255, 196, 40), species = "Narwhal", icon = "" },
} :: { Rarity }
for i, r in Config.Rarities do
	r.index = i
end

-- Every zone has its own 5 creatures (one per rarity): 30 to collect.
-- kind = which blocky builder (Creatures.luau); c1/c2/c3 = colors; flags
-- tweak the build (glow, bill, lure, horn, shell...).
type Species = {
	name: string, kind: string, icon: string, c1: Color3, c2: Color3, c3: Color3?,
	glow: boolean?, bill: boolean?, lure: boolean?, horn: boolean?, shell: boolean?, long: boolean?,
	ghost: boolean?, horns: boolean?, size: number?,
}
local RGB = Color3.fromRGB
Config.Species = {
	Lagoon = {
		Common = { name = "Clownfish", kind = "fish", icon = "", c1 = RGB(255, 128, 32), c2 = RGB(255, 255, 255), c3 = RGB(30, 30, 40) },
		Uncommon = { name = "Hermit Crab", kind = "crab", icon = "", c1 = RGB(255, 110, 80), c2 = RGB(240, 200, 150), shell = true },
		Rare = { name = "Pufferfish", kind = "puffer", icon = "", c1 = RGB(255, 214, 64), c2 = RGB(255, 245, 210) },
		Epic = { name = "Sea Turtle", kind = "turtle", icon = "", c1 = RGB(70, 170, 90), c2 = RGB(150, 110, 60) },
		Legendary = { name = "Narwhal", kind = "whale", icon = "", c1 = RGB(150, 190, 230), c2 = RGB(240, 248, 255), horn = true },
	},
	Reef = {
		Common = { name = "Blue Tang", kind = "fish", icon = "", c1 = RGB(40, 110, 230), c2 = RGB(25, 30, 60), c3 = RGB(255, 220, 40) },
		Uncommon = { name = "Seahorse", kind = "seahorse", icon = "", c1 = RGB(255, 150, 60), c2 = RGB(255, 210, 120) },
		Rare = { name = "Octopus", kind = "ceph", icon = "", c1 = RGB(235, 80, 120), c2 = RGB(255, 170, 190) },
		Epic = { name = "Manta Ray", kind = "ray", icon = "", c1 = RGB(40, 60, 100), c2 = RGB(235, 240, 250) },
		Legendary = { name = "Coral Dragon", kind = "serpent", icon = "", c1 = RGB(255, 110, 150), c2 = RGB(255, 220, 120), horns = true },
	},
	Kelp = {
		Common = { name = "Parrotfish", kind = "fish", icon = "", c1 = RGB(70, 210, 150), c2 = RGB(255, 120, 200), c3 = RGB(255, 230, 90) },
		Uncommon = { name = "Spider Crab", kind = "crab", icon = "", c1 = RGB(200, 70, 50), c2 = RGB(255, 170, 120), long = true },
		Rare = { name = "Jellyfish", kind = "jelly", icon = "", c1 = RGB(255, 140, 220), c2 = RGB(255, 220, 245), glow = true },
		Epic = { name = "Squid", kind = "ceph", icon = "", c1 = RGB(240, 150, 120), c2 = RGB(255, 210, 190), long = true },
		Legendary = { name = "Sea Dragon", kind = "serpent", icon = "", c1 = RGB(90, 180, 70), c2 = RGB(220, 240, 120) },
	},
	Shipwreck = {
		Common = { name = "Moray Eel", kind = "serpent", icon = "", c1 = RGB(120, 140, 60), c2 = RGB(220, 210, 120), size = 0.8 },
		Uncommon = { name = "Lobster", kind = "crab", icon = "", c1 = RGB(220, 40, 40), c2 = RGB(255, 140, 110), long = true, shell = false },
		Rare = { name = "Swordfish", kind = "fish", icon = "", c1 = RGB(70, 90, 150), c2 = RGB(220, 230, 245), c3 = RGB(30, 40, 70), bill = true },
		Epic = { name = "Ghost Octopus", kind = "ceph", icon = "", c1 = RGB(210, 240, 255), c2 = RGB(150, 220, 255), ghost = true },
		Legendary = { name = "Orca", kind = "whale", icon = "", c1 = RGB(25, 28, 40), c2 = RGB(255, 255, 255), size = 1.05 },
	},
	Deep = {
		Common = { name = "Lanternfish", kind = "fish", icon = "", c1 = RGB(40, 50, 90), c2 = RGB(80, 230, 255), c3 = RGB(20, 20, 40), glow = true },
		Uncommon = { name = "Anglerfish", kind = "fish", icon = "", c1 = RGB(70, 50, 80), c2 = RGB(255, 240, 120), c3 = RGB(30, 20, 40), lure = true },
		Rare = { name = "Giant Squid", kind = "ceph", icon = "", c1 = RGB(180, 40, 50), c2 = RGB(255, 120, 110), long = true },
		Epic = { name = "Moon Ray", kind = "ray", icon = "", c1 = RGB(60, 70, 140), c2 = RGB(160, 220, 255), glow = true },
		Legendary = { name = "Leviathan", kind = "serpent", icon = "", c1 = RGB(30, 90, 140), c2 = RGB(90, 230, 255), horns = true, glow = true, size = 1.2 },
	},
	Abyss = {
		Common = { name = "Glowfish", kind = "fish", icon = "", c1 = RGB(90, 255, 200), c2 = RGB(20, 40, 60), c3 = RGB(20, 20, 30), glow = true },
		Uncommon = { name = "Abyss Jelly", kind = "jelly", icon = "", c1 = RGB(140, 90, 255), c2 = RGB(220, 200, 255), glow = true },
		Rare = { name = "Vampire Squid", kind = "ceph", icon = "", c1 = RGB(90, 20, 40), c2 = RGB(255, 60, 90), glow = true },
		Epic = { name = "Megalodon Pup", kind = "whale", icon = "", c1 = RGB(110, 130, 160), c2 = RGB(235, 240, 250), fin = true },
		Legendary = { name = "Kraken", kind = "ceph", icon = "", c1 = RGB(60, 20, 70), c2 = RGB(255, 80, 200), glow = true, size = 1.12 },
	},
} :: any

function Config.species(zoneId: string?, rarityId: string): Species
	local z = Config.Species[zoneId or "Lagoon"] or Config.Species.Lagoon
	return z[rarityId] or z.Common
end

-- "Gold Clownfish", "Octopus"...
function Config.creatureName(zoneId: string?, rarityId: string, mutationId: string?): string
	return (mutationId and (mutationId .. " ") or "") .. Config.species(zoneId, rarityId).name
end

function Config.rarity(id: string): Rarity
	for _, r in Config.Rarities do
		if r.id == id then
			return r
		end
	end
	return Config.Rarities[1]
end

type Mutation = { id: string, chance: number, mult: number, color: Color3 }
Config.Mutations = {
	{ id = "Rainbow", chance = 0.003, mult = 6, color = Color3.fromRGB(255, 120, 220) },
	{ id = "Diamond", chance = 0.01, mult = 5, color = Color3.fromRGB(150, 236, 255) },
	{ id = "Gold", chance = 0.03, mult = 2, color = Color3.fromRGB(255, 205, 60) },
} :: { Mutation }

function Config.mutation(id: string?): Mutation?
	for _, m in Config.Mutations do
		if m.id == id then
			return m
		end
	end
	return nil
end

-- coins per second for one creature
function Config.creatureValue(rarityId: string, zoneId: string, mutationId: string?, size: number?): number
	local zone = Config.zoneById(zoneId)
	local m = Config.mutation(mutationId)
	return (zone and zone.value or 1) * Config.rarity(rarityId).mult * (m and m.mult or 1) * Config.sizeValue(size)
end

----------------------------------------------------------------- size + weight
-- Every catch has a size: most are close to 1x, some are Big, a rare few are
-- Huge. Weight = the species' usual weight x size. Bigger ones earn a bit
-- more (x size^0.5) and look bigger in your tank.
Config.KIND_KG = {
	fish = 2, puffer = 1.6, crab = 3, turtle = 48, whale = 900, seahorse = 0.4,
	ceph = 14, ray = 36, serpent = 180, jelly = 0.8,
}

function Config.rollSize(rng: Random): number
	local x = rng:NextNumber()
	local s
	if x < 0.008 then
		s = rng:NextNumber(2.0, 3.0) -- Huge
	elseif x < 0.05 then
		s = rng:NextNumber(1.4, 1.9) -- Big
	else
		s = 0.75 + (rng:NextNumber() + rng:NextNumber()) / 2 * 0.55 -- 0.75..1.3, mostly ~1
	end
	return math.floor(s * 100 + 0.5) / 100
end

function Config.sizeLabel(size: number?): string?
	local s = size or 1
	return s >= 2 and "Huge" or s >= 1.4 and "Big" or nil
end

function Config.sizeValue(size: number?): number
	return math.sqrt(size or 1)
end

-- how much bigger it looks (volume grows with weight)
function Config.sizeScale(size: number?): number
	return (size or 1) ^ (1 / 3)
end

function Config.creatureKg(zoneId: string?, rarityId: string, size: number?): number
	local sp = Config.species(zoneId, rarityId)
	local zone = Config.zoneById(zoneId or "Lagoon")
	local base = (Config.KIND_KG[sp.kind] or 2) * (sp.size or 1)
	base *= 1 + ((zone and zone.index or 1) - 1) * 0.6
	base *= 1 + (Config.rarity(rarityId).index - 1) * 0.25
	return base * (size or 1)
end

function Config.formatKg(kg: number): string
	if kg >= 1000 then
		return ("%.1f t"):format(kg / 1000)
	elseif kg >= 100 then
		return ("%d kg"):format(math.floor(kg + 0.5))
	end
	return ("%.1f kg"):format(kg)
end

-- "Huge Gold Octopus"
function Config.fullName(zoneId: string?, rarityId: string, mutationId: string?, size: number?): string
	local label = Config.sizeLabel(size)
	return (label and (label .. " ") or "") .. Config.creatureName(zoneId, rarityId, mutationId)
end

Config.Luck = {
	base = 0.05, -- chance a grab bumps up one rarity ("LUCKY!")
	pass = 0.15,
	potion = 0.15,
	pityGrab = 5, -- the 5th creature you ever grab is at least Rare
	pityEpic = 30, -- and the 30th is at least Epic (if you've never had one)
}

Config.BUBBLES_PER_ZONE = 9
Config.GRAB_RADIUS = 6.5
Config.DEPOSIT_RADIUS = 15
Config.COLLECT_RADIUS = 6
Config.SELL_SECONDS = 20 -- a creature that doesn't fit sells for this many seconds of its income

----------------------------------------------------------------- tank
-- Your tank: everything you catch is kept (up to `storage`); the best ones
-- are Active and earn money. "+1 EQUIP" buys another active slot.
Config.Tank = {
	startSlots = 4,
	maxSlots = 12,
	passSlots = 4,
	-- price of active slot #5, #6, ... #12
	slotPrices = { 400, 2000, 8000, 30000, 120000, 500000, 2000000, 8000000 },
	maxDead = 10, -- unequipped catches lie "dead" on the tank floor (no income); past this you must sell some
}

-- hold time (seconds) on the grab prompt: rarer = longer = riskier
Config.GrabHold = { Common = 0.35, Uncommon = 0.55, Rare = 0.8, Epic = 1.1, Legendary = 1.5 }

-- +10% coins per friend in your server (max +50%)
Config.FriendBoost = { per = 0.1, max = 0.5 }

-- Slow Mode caps your speed so precise grabs are easy at high speed
Config.SLOW_SPEED = 26

-- Codes (case-insensitive, once per player). Edit freely.
Config.Codes = {
	SHARK = { coins = 250, speed = 50 },
	RELEASE = { coins = 1000, speed = 100 },
	CHOMP = { shields = 1 },
}

----------------------------------------------------------------- sharks
Config.Shark = {
	cycle = 80, -- seconds between attacks (calm time is most of it)
	firstAttack = 70,
	warning = 5, -- "SHARK INCOMING" countdown: time to get to sand
	hunt = 22,
	spawnDistance = 46,
	-- a hunting shark circles you once (a tightening spiral), then charges.
	-- The charge is always faster than you: reach sand / an island, or swerve
	-- at the last second (it turns slowly at full speed) and it overshoots.
	stalk = 2.6, -- seconds of circling before the first charge
	recircle = 1.3, -- after a miss
	stalkRadius = 24,
	stalkEnd = 13,
	chargeMult = 1.35, -- charge speed vs the zone's shark speed...
	chargeVsPlayer = 1.22, -- ...and never slower than this x your top speed
	chargeRadius = 26, -- turning circle while charging (studs): same feel at any speed
	chargeGiveUp = 4,
	maxHunters = 24,
	newPlayerGrace = 150, -- seconds before a brand-new player can be hunted
	eatenTime = 3.0, -- length of the bite cutscene before you wash up
	frenzyLuck = 0.3, -- extra chance to bump a grab up a rarity while it hunts
}

----------------------------------------------------------------- rebirth
Config.Rebirth = { speed = 25000, mult = 1.5 }

----------------------------------------------------------------- monetization
-- Fill these in from Creator Dashboard after you create the passes/products.
-- An id of 0 hides the buy button instead of prompting a fake purchase.
Config.Passes = {
	TwoXSpeed = { iconName = "X2Speed", id = 0, price = 399, name = "2x Speed", icon = "", desc = "Double speed gain forever" },
	TwoXCoins = { iconName = "X2Coins", id = 0, price = 199, name = "2x Coins", icon = "", desc = "Double coins from your tank" },
	AutoCollect = { iconName = "Magnet", id = 0, price = 99, name = "Auto Collect", icon = "", desc = "Coins go straight to you" },
	LuckyNet = { iconName = "Clover", id = 0, price = 199, name = "Lucky Net", icon = "", desc = "+15% chance to upgrade rarity" },
	BigTank = { iconName = "BigTank", id = 0, price = 99, name = "+4 Tank Slots", icon = "", desc = "Room for 4 more creatures" },
	VIP = { iconName = "Crown", id = 0, price = 399, name = "VIP", icon = "", desc = "Gold wake, VIP tag, +10% coins" },
	GoldDuck = { iconName = "GoldDuck", id = 0, price = 99, name = "Golden Duck", icon = "", desc = "Ride it - x1.25 speed gain" },
	SharkBoard = { iconName = "SharkBoard", id = 0, price = 199, name = "Shark Board", icon = "", desc = "Ride it - x1.5 speed gain" },
	RainbowSki = { iconName = "RainbowSki", id = 0, price = 399, name = "Rainbow Jet Ski", icon = "", desc = "Ride it - x2 speed gain" },
}

Config.Products = {
	Shield = { iconName = "Shield", id = 0, price = 25, name = "Shark Shield", icon = "", desc = "Survive one bite, keep your creature" },
	SpeedBoost = { iconName = "Boost", id = 0, price = 49, name = "2x Speed (15 min)", icon = "", desc = "Double speed gain for 15 minutes" },
	LuckPotion = { iconName = "Potion", id = 0, price = 49, name = "Luck Potion (10 min)", icon = "", desc = "+15% rarity upgrade chance" },
	GoldenBubble = { iconName = "GoldBubble", id = 0, price = 99, name = "Golden Bubble", icon = "",
		desc = "Rare 70% · Epic 25% · Legendary 5%" },
	StarterPack = { iconName = "Gift", id = 0, price = 49, name = "Starter Pack", icon = "",
		desc = "A Rare creature + 30 min 2x Speed + 3 Shields" },
	DoubleOffline = { iconName = "Clock", id = 0, price = 25, name = "2x Offline Coins", icon = "", desc = "Double your welcome-back coins" },
}

Config.GoldenBubbleOdds = { { "Rare", 70 }, { "Epic", 25 }, { "Legendary", 5 } }
Config.SHOP_UNLOCK_SECONDS = 300 -- no Robux prompts or offers in the first 5 minutes

----------------------------------------------------------------- index
-- Every rarity in every zone is one Index entry. Discovering one unlocks a
-- one-time reward; deeper zones and rarer creatures pay more.
function Config.indexKey(zoneId: string, rarityId: string): string
	return zoneId .. ":" .. rarityId
end

function Config.indexReward(zoneId: string, rarityId: string): (number, number)
	local zone = Config.zoneById(zoneId)
	local r = Config.rarity(rarityId)
	local v = zone and zone.value or 1
	local coins = math.floor(5 * v * r.mult ^ 0.7)
	local speed = math.floor((5 + (zone and zone.gate or 0) * 0.02) * r.index)
	return coins, speed
end

----------------------------------------------------------------- offline
-- Your tank keeps earning while you're away (at a slower rate, capped).
Config.Offline = { rate = 0.1, maxHours = 8, minSeconds = 120 }

-- what your tank makes per day while you're offline
function Config.offlinePerDay(income: number): number
	return income * Config.Offline.rate * 86400
end

----------------------------------------------------------------- images
-- Stud texture: "Studs" by aetoreous (public domain). Decal 6927295857,
-- image 6927295847. The image is a 4x4 grid of studs.
Config.Images = {
	Studs = "rbxassetid://6927295847",
	StudsWorldTile = 8, -- studs of world space one image tile covers on parts
}

-- Custom icons. Upload each PNG from assets/icons/single/ (Asset Manager >
-- Import) and paste its id next to its name in `ids` ("rbxassetid://123" or
-- just the number). Order of use: ids[name] > sheet > emoji fallback.
-- (The two sheets in assets/icons work too; leave them "" when using singles.)
Config.Icons = {
	ids = {
		-- HUD (upload these first)
		Sneaker = "", Cash = "", Shop = "", Index = "", Rides = "", Tank = "", Rebirth = "", Shark = "",
		-- popups, shop cards, guide
		Arrow = "", Clock = "", MoneyBag = "", Gift = "", Speed = "", Coins = "",
		X2Speed = "", X2Coins = "", Magnet = "", Clover = "", BigTank = "", Crown = "",
		GoldDuck = "", SharkBoard = "", RainbowSki = "", Shield = "", Boost = "", Potion = "", GoldBubble = "",
		Lock = "", Trophy = "", Sparkle = "", Chest = "", Fin = "", Fish = "", Island = "",
	},
	SheetA = "",
	SheetB = "",
	cells = {
		Speed = { "A", 1 }, Coins = { "A", 2 }, Rides = { "A", 3 }, Index = { "A", 4 },
		Shop = { "A", 5 }, Rebirth = { "A", 6 }, Shark = { "A", 7 }, Tank = { "A", 8 },
		Shield = { "A", 9 }, Boost = { "A", 10 }, Potion = { "A", 11 }, Lock = { "A", 12 },
		Gift = { "A", 13 }, Clock = { "A", 14 }, Trophy = { "A", 15 }, Sparkle = { "A", 16 },
		X2Speed = { "B", 1 }, X2Coins = { "B", 2 }, Magnet = { "B", 3 }, Clover = { "B", 4 },
		BigTank = { "B", 5 }, Crown = { "B", 6 }, GoldDuck = { "B", 7 }, SharkBoard = { "B", 8 },
		RainbowSki = { "B", 9 }, GoldBubble = { "B", 10 }, Chest = { "B", 11 }, Fin = { "B", 12 },
		Arrow = { "B", 13 }, MoneyBag = { "B", 14 }, Fish = { "B", 15 }, Island = { "B", 16 },
		Sneaker = { "A", 1 }, Cash = { "B", 14 },
	},
}

----------------------------------------------------------------- audio
-- rbxasset:// sounds ship with every Roblox client. Empty strings are slots
-- for Creator Store audio you pick and record in ASSETS.md (never invent ids).
----------------------------------------------------------------- group chest + daily rewards
-- Your Roblox group's id. 0 = no group yet: the chest then only asks for a
-- like (favorite) and still pays out, so it works before the group exists.
Config.GroupId = 902411651
Config.GroupChest = { cooldownHours = 12, incomeSeconds = 180, minCoins = 150, boostMinutes = 10 }

-- 7-day streak (claim once every 20h; miss 48h and it starts over at day 1)
Config.Daily = {
	{ kind = "boost", minutes = 10, label = "2x Speed 10 min", icon = "Boost" },
	{ kind = "shield", amount = 1, label = "Shark Shield", icon = "Shield" },
	{ kind = "coins", seconds = 120, min = 100, label = "Bag of Cash", icon = "Cash" },
	{ kind = "luck", minutes = 15, label = "Luck Potion", icon = "Potion" },
	{ kind = "coins", seconds = 600, min = 500, label = "Big Cash", icon = "Cash" },
	{ kind = "creature", rarity = "Epic", label = "Epic Creature", icon = "GoldBubble" },
	{ kind = "creature", rarity = "Legendary", size = 2.2, label = "Huge Legendary", icon = "Crown", limited = true },
} :: { { [string]: any } }
Config.DAILY_GAP_HOURS, Config.DAILY_RESET_HOURS = 20, 48

Config.Sounds = {
	-- music (Audio.luau). One track for the whole game; give a place its own
	-- track by filling its slot (the hunt slot, if empty, ducks the main track)
	music = "rbxassetid://1846088038",
	musicBeach = "",
	musicOcean = "",
	musicDeep = "",
	musicHunt = "",
}

-- 1) The Roblox id of every uploaded sound file (upload them exactly as they
--    are; the names are the file names). Paste the number, with or without
--    "rbxassetid://". Empty = that sound uses its built-in fallback or is
--    silent. Sources and licenses: ASSETS.md.
Config.SoundFiles = {
	["mixkit-soap-bubble-sound-2925"] = "rbxassetid://91161037960580",
	["mixkit-explainer-video-pops-whoosh-light-pop-3005"] = "rbxassetid://132051161428247",
	["mixkit-boing-hit-sound-2894"] = "rbxassetid://81137746729164",
	["mixkit-dry-pop-up-notification-alert-2356"] = "rbxassetid://130268760790939",
	["mixkit-movie-whoosh-impact-presentation-2903"] = "rbxassetid://93945704934482",
	["mixkit-water-bubble-1317"] = "rbxassetid://109536715402499",
	["mixkit-sea-water-splash-1198"] = "rbxassetid://78768880176281",
	["mixkit-fairy-magic-sparkle-871"] = "rbxassetid://124096247708665",
	["mixkit-successful-horns-fanfare-722"] = "rbxassetid://116467160770080",
	["mixkit-melodic-bonus-collect-1938"] = "rbxassetid://114365963704853",
	["mixkit-page-forward-single-chime-1107"] = "rbxassetid://93383166774303",
	["mixkit-liquid-bubble-3000"] = "rbxassetid://78767914886421",
	["mixkit-clinking-coins-1993"] = "rbxassetid://133067320326955",
	["mixkit-money-bag-drop-1989"] = "rbxassetid://94615652928279",
	["184438__capslok__cash-register-fake"] = "rbxassetid://128288863011143",
	["mixkit-unlock-new-item-game-notification-254"] = "rbxassetid://90531968965473",
	["mixkit-achievement-completed-2068"] = "rbxassetid://94011401770356",
	["mixkit-facility-alarm-sound-999"] = "rbxassetid://119351650727606",
	["mixkit-aggressive-beast-roar-13"] = "rbxassetid://133338904418165",
	["528962__steenish__crunch"] = "rbxassetid://114947460738011",
	["445118__breviceps__cartoon-splat"] = "rbxassetid://87181834248801",
	["mixkit-arrow-whoosh-1491"] = "rbxassetid://97268804826952",
	["350917__csaszi__rubber-duck-csg"] = "rbxassetid://105370668810111",
	["456151__jfournier18__dolphin-noise"] = "rbxassetid://96059363771818",
	["mixkit-sea-swimming-loop-1181"] = "rbxassetid://131576493971250",
	["188199__splicesound__paddle-boat-on-water-2"] = "rbxassetid://79089636097979",
	["443870__eardeer__water_flow_dam_close_loop"] = "rbxassetid://123327977782557",
	["mixkit-deep-water-bubbles-1321"] = "rbxassetid://76938595911508",
	["454199__kyles__speed-boat-outboard-motor-medium-high-gear-waves-splash"] = "rbxassetid://117099041120300",
	["212441__wjauch__jetski"] = "rbxassetid://103155995162396",
	["171106__qubodup__rocket-flight-loop"] = "rbxassetid://128168593084712",
	["mixkit-sea-waves-loop-1196"] = "rbxassetid://110907888719466",
	["seagulls_distant"] = "rbxassetid://94208672690861",
}

-- 2) What every game sound plays. All editing happens in the game with
--    Roblox's own sound settings and effects, so files never need re-uploading:
--      from/to   play only that part of the file (seconds)
--      loop      loop just that part (points picked where the waveform lines up)
--      gain      loudness match between files (measured from the files), times
--                the volume the game asks for
--      pitch     playback speed (lower = deeper and slower)
--      eq        { low, mid, high } in dB (EqualizerSoundEffect)
--      fade      fade out over the last N seconds
--      layers    other entries played with it at the same time
--      every     ride loops only: { entry, min gap s, max gap s, volume } now and then
--      fallback  entry to use while this one's file has no id
type SoundSlot = {
	file: string, from: number?, to: number?, loop: { number }?, gain: number?, pitch: number?,
	eq: { number }?, fade: number?, layers: { string }?, every: { any }?, fallback: string?,
}
local F = {
	soap = "mixkit-soap-bubble-sound-2925", pop = "mixkit-explainer-video-pops-whoosh-light-pop-3005",
	boing = "mixkit-boing-hit-sound-2894", dryPop = "mixkit-dry-pop-up-notification-alert-2356",
	whoosh = "mixkit-movie-whoosh-impact-presentation-2903", bubble = "mixkit-water-bubble-1317",
	splash = "mixkit-sea-water-splash-1198", sparkle = "mixkit-fairy-magic-sparkle-871",
	fanfare = "mixkit-successful-horns-fanfare-722", bonus = "mixkit-melodic-bonus-collect-1938",
	chime = "mixkit-page-forward-single-chime-1107", liquid = "mixkit-liquid-bubble-3000",
	coins = "mixkit-clinking-coins-1993", bag = "mixkit-money-bag-drop-1989",
	register = "184438__capslok__cash-register-fake", unlock = "mixkit-unlock-new-item-game-notification-254",
	achieve = "mixkit-achievement-completed-2068", alarm = "mixkit-facility-alarm-sound-999",
	roar = "mixkit-aggressive-beast-roar-13", crunch = "528962__steenish__crunch",
	splat = "445118__breviceps__cartoon-splat", arrow = "mixkit-arrow-whoosh-1491",
	duck = "350917__csaszi__rubber-duck-csg", dolphin = "456151__jfournier18__dolphin-noise",
	swim = "mixkit-sea-swimming-loop-1181", paddle = "188199__splicesound__paddle-boat-on-water-2",
	flow = "443870__eardeer__water_flow_dam_close_loop", deep = "mixkit-deep-water-bubbles-1321",
	boat = "454199__kyles__speed-boat-outboard-motor-medium-high-gear-waves-splash", jetski = "212441__wjauch__jetski",
	rocket = "171106__qubodup__rocket-flight-loop", waves = "mixkit-sea-waves-loop-1196", gulls = "seagulls_distant",
}
Config.SoundSlots = {
	-- UI
	uiClick = { file = F.soap, from = 0, to = 0.13, gain = 0.45 },
	uiOpen = { file = F.pop, gain = 0.4 },
	uiClose = { file = F.pop, pitch = 0.8, gain = 0.4 }, -- the open pop, lower
	uiError = { file = F.boing, from = 0, to = 0.5, gain = 0.21, fade = 0.1 },
	uiToast = { file = F.dryPop, gain = 0.81 },
	uiTakeover = { file = F.arrow, from = 0.1, to = 0.5, pitch = 0.85, gain = 0.44 }, -- a quick swoosh
	-- catching + money
	grab = { file = F.bubble, gain = 1.06, layers = { "grabSplash" } },
	grabSplash = { file = F.splash, from = 0.45, to = 1.0, gain = 0.46, fade = 0.15 },
	grabRare = { file = F.sparkle, gain = 0.69 },
	legendary = { file = F.fanfare, gain = 0.69 },
	lucky = { file = F.bonus, gain = 0.56 },
	discover = { file = F.chime, gain = 0.61 },
	deposit = { file = F.liquid, from = 0, to = 0.6, gain = 0.43 },
	coin = { file = F.coins, from = 0.03, to = 0.75, gain = 0.73 },
	collect = { file = F.bag, from = 0.08, to = 0.5, gain = 1.1, fallback = "coin" },
	buy = { file = F.register, from = 0.05, to = 1.6, gain = 1.75, fade = 0.3 },
	-- progression
	rideNew = { file = F.unlock, gain = 0.95 },
	zoneUnlock = { file = F.achieve, gain = 2.39 },
	rebirth = { file = F.achieve, pitch = 0.84, gain = 2.39, layers = { "rebirthWhoosh" } },
	rebirthWhoosh = { file = F.whoosh, from = 0.1, to = 2.6, gain = 0.23, fade = 0.5 },
	-- shark
	sharkAlarm = { file = F.alarm, from = 0, to = 2.0, gain = 0.58, fade = 0.25 },
	sharkCharge = { file = F.roar, pitch = 0.78, eq = { 2, 0, -10 }, gain = 0.42, layers = { "chargeSplash" } },
	chargeSplash = { file = F.splash, from = 0.45, to = 1.3, gain = 0.56, fade = 0.2 },
	chomp = { file = F.crunch, pitch = 0.8, gain = 1.27, layers = { "chompSplat" } },
	chompSplat = { file = F.splat, pitch = 0.85, gain = 0.21 },
	dodge = { file = F.arrow, from = 0.1, to = 0.5, gain = 0.44 },
	spat = { file = F.splat, gain = 0.46 },
	splash = { file = F.splash, from = 0.45, to = 1.3, gain = 1.12, fade = 0.2 },
	-- rides (3D loops; pitch and volume follow speed)
	duckSqueak = { file = F.duck, from = 0.08, to = 0.66, gain = 0.82 },
	dolphinCall = { file = F.dolphin, from = 0.43, to = 2.58, gain = 0.31 },
	rideSplash = { file = F.swim, loop = { 2.782, 8.443 }, gain = 0.72 },
	rideKick = { file = F.swim, loop = { 1.426, 4.198 }, pitch = 1.12, gain = 0.72 },
	rideDuck = { file = F.paddle, loop = { 40.008, 43.98 }, gain = 0.73, every = { "duckSqueak", 5, 10, 0.3 } },
	rideSurf = { file = F.flow, loop = { 9.95, 14.215 }, eq = { -6, 0, 2 }, gain = 0.36 },
	rideBubbles = { file = F.deep, loop = { 0, 1.12 }, gain = 0.33 },
	rideMotor = { file = F.boat, loop = { 2.015, 4.801 }, pitch = 0.82, gain = 0.48 },
	rideJetSki = { file = F.jetski, loop = { 7.476, 9.306 }, gain = 0.74 },
	rideBoat = { file = F.boat, loop = { 5.548, 8.76 }, gain = 0.42 },
	rideDolphin = { file = F.swim, loop = { 2.782, 8.443 }, pitch = 1.05, gain = 0.72, every = { "dolphinCall", 4, 8, 0.45 } },
	rideRocket = { file = F.rocket, gain = 2.9 }, -- already a seamless loop
	-- ambience
	ambWaves = { file = F.waves, gain = 0.67 }, -- open-sea bed (a seamless loop)
	ambShore = { file = F.waves, loop = { 25.95, 36.203 }, pitch = 1.08, eq = { -8, 0, 2 }, gain = 0.79 }, -- small waves on the sand
	ambGulls = { file = F.gulls, loop = { 0.036, 29.93 }, gain = 25 }, -- a very quiet recording
	ambTank = { file = F.deep, loop = { 0, 2.4 }, pitch = 0.7, eq = { 0, 0, -8 }, gain = 0.26 }, -- a bloop every few seconds
} :: { [string]: SoundSlot }

-- which loop each ride plays, and its base pitch
Config.RideSound = {
	Noodle = { "rideSplash", 1.0 }, Tube = { "rideSplash", 0.95 }, Donut = { "rideSplash", 0.9 },
	Duck = { "rideDuck", 1.0 }, GoldDuck = { "rideDuck", 1.08 },
	Boogie = { "rideKick", 1.0 },
	Surf = { "rideSurf", 1.0 }, SharkBoard = { "rideSurf", 0.92 },
	Bathtub = { "rideBubbles", 1.0 },
	Banana = { "rideMotor", 1.0 },
	JetSki = { "rideJetSki", 1.0 }, RainbowSki = { "rideJetSki", 1.12 },
	Speedboat = { "rideBoat", 1.0 },
	Dolphin = { "rideDolphin", 1.0 },
	Rocket = { "rideRocket", 1.0 },
} :: { [string]: { any } }

return Config

end
MODULES['mod:Build'] = function()
local script = { Parent = SHARED }
-- Tiny part-building kit for the cartoon low-poly stud look.
-- One visual family: Plastic/SmoothPlastic, bright colors, studs on tops.

local Config = require(script.Parent.Config)

local Build = {}

type Props = { [string]: any }

local function apply(inst: Instance, props: Props?)
	if props then
		for k, v in props do
			(inst :: any)[k] = v
		end
	end
end

function Build.part(parent: Instance?, size: Vector3, cf: CFrame, color: Color3, props: Props?): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	apply(p, props)
	p.Parent = parent
	return p
end

-- Stud texture on the given faces (default: top), tinted to the part's
-- color so one white stud image works on every color. Falls back to the
-- classic stud surface if no texture is configured.
local ALL_FACES = { Enum.NormalId.Top, Enum.NormalId.Front, Enum.NormalId.Back, Enum.NormalId.Left, Enum.NormalId.Right }
Build.ALL_FACES = ALL_FACES

function Build.studs(p: BasePart, faces: { Enum.NormalId }?): BasePart
	local img = Config.Images.Studs
	if img == "" then
		p.Material = Enum.Material.Plastic
		for _, face in faces or { Enum.NormalId.Top } do
			(p :: any)[face.Name .. "Surface"] = Enum.SurfaceType.Studs
		end
		return p
	end
	p.Material = Enum.Material.SmoothPlastic
	local tile = Config.Images.StudsWorldTile
	for _, face in faces or { Enum.NormalId.Top } do
		local t = Instance.new("Texture")
		t.Name = "Studs"
		t.Texture = img
		t.Face = face
		t.StudsPerTileU = tile
		t.StudsPerTileV = tile
		t.Color3 = p.Color
		t.Parent = p
	end
	return p
end

function Build.wedge(parent: Instance?, size: Vector3, cf: CFrame, color: Color3, props: Props?): WedgePart
	local p = Instance.new("WedgePart")
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	apply(p, props)
	p.Parent = parent
	return p
end

function Build.ball(parent: Instance?, d: number, cf: CFrame, color: Color3, props: Props?): Part
	local p = Build.part(parent, Vector3.new(d, d, d), cf, color, props)
	p.Shape = Enum.PartType.Ball
	return p
end

-- vertical cylinder (Roblox cylinders run along X, so rotate onto Y)
function Build.cyl(parent: Instance?, height: number, d: number, cf: CFrame, color: Color3, props: Props?): Part
	local p = Build.part(parent, Vector3.new(height, d, d), cf * CFrame.Angles(0, 0, math.pi / 2), color, props)
	p.Shape = Enum.PartType.Cylinder
	return p
end

-- squashable ellipsoid
function Build.ell(parent: Instance?, size: Vector3, cf: CFrame, color: Color3, props: Props?): Part
	local p = Build.part(parent, size, cf, color, props)
	local m = Instance.new("SpecialMesh")
	m.MeshType = Enum.MeshType.Sphere
	m.Parent = p
	return p
end

-- ring of blocks (inner tubes, floaties, donuts)
function Build.ring(parent: Instance?, radius: number, thick: number, cf: CFrame, color: Color3, segments: number?, alt: Color3?): { BasePart }
	local n = segments or 10
	local parts = {}
	local segLen = 2 * math.pi * radius / n * 1.08
	for i = 1, n do
		local a = (i - 1) / n * 2 * math.pi
		local c = (alt and i % 2 == 0) and alt or color
		local seg = Build.part(parent, Vector3.new(segLen, thick, thick),
			cf * CFrame.Angles(0, a, 0) * CFrame.new(0, 0, -radius), c)
		table.insert(parts, seg)
	end
	return parts
end

function Build.model(name: string, parent: Instance?): Model
	local m = Instance.new("Model")
	m.Name = name
	m.Parent = parent
	return m
end

-- invisible root that a model pivots/welds around
function Build.root(model: Model, cf: CFrame?): Part
	local r = Build.part(model, Vector3.new(0.4, 0.4, 0.4), cf or CFrame.new(), Color3.new(1, 1, 1), {
		Name = "Root", Transparency = 1, CanCollide = false, CanQuery = false, CanTouch = false,
	})
	model.PrimaryPart = r
	return r
end

-- make every part visual-only
function Build.ghost(model: Instance)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.Massless = true
			d.CastShadow = false
		end
	end
end

-- unanchor and weld everything to the root so the model can ride a character
function Build.weldToRoot(model: Model)
	local root = model.PrimaryPart
	assert(root, "model needs a PrimaryPart")
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d ~= root then
			local w = Instance.new("WeldConstraint")
			w.Part0 = root
			w.Part1 = d
			w.Parent = d
			d.Anchored = false
		end
	end
	root.Anchored = false
end

function Build.recolor(model: Instance, color: Color3, material: Enum.Material?)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d.Transparency < 1 and not d:GetAttribute("KeepColor") then
			d.Color = color
			if material then
				d.Material = material
			end
			for _, t in d:GetChildren() do
				if t:IsA("Texture") then
					t.Color3 = color
				end
			end
		end
	end
end

return Build

end
MODULES['mod:Layout'] = function()
local script = { Parent = SHARED }
-- Deterministic map layout shared by server (builds it) and client (arrows,
-- safe-spot checks), so nothing has to be streamed or replicated to agree.

local Config = require(script.Parent.Config)

local Layout = {}

type Island = { pos: Vector3, radius: number, zone: string, palm: boolean }

local W = Config.LANE_WIDTH

----------------------------------------------------------------- islands
Layout.Islands = {} :: { Island }
do
	local rng = Random.new(1337)
	for _, zone in Config.Zones do
		local z = zone.zStart + zone.islandEvery * 0.55
		local row = 0
		while z < zone.zEnd - 30 do
			local count = (row % 2 == 0) and 3 or 2
			for i = 1, count do
				local t = (i - 0.5) / count
				local x = -W / 2 + W * t + rng:NextNumber(-16, 16)
				local jitterZ = rng:NextNumber(-12, 12)
				table.insert(Layout.Islands, {
					pos = Vector3.new(x, Config.WATER_Y, z + jitterZ),
					radius = zone.islandRadius + rng:NextNumber(-1.5, 1.5),
					zone = zone.id,
					palm = rng:NextNumber() < 0.6,
				})
			end
			row += 1
			z += zone.islandEvery
		end
	end
end

----------------------------------------------------------------- plots
Layout.Plots = {} :: { CFrame }
for i = 1, Config.PLOT_COUNT do
	local x = (i - (Config.PLOT_COUNT + 1) / 2) * Config.PLOT_SPACING
	-- face the ocean (+Z): LookVector points toward the water
	table.insert(Layout.Plots, CFrame.lookAt(Vector3.new(x, Config.BEACH_TOP, Config.PLOT_Z), Vector3.new(x, Config.BEACH_TOP, 100)))
end

function Layout.tankPos(plot: CFrame): Vector3
	return (plot * CFrame.new(0, 0, 6)).Position
end
function Layout.padPos(plot: CFrame): Vector3
	return (plot * CFrame.new(-10, 0, -10)).Position
end
function Layout.spawnCFrame(plot: CFrame): CFrame
	return plot * CFrame.new(4, 3, -14)
end

----------------------------------------------------------------- plaza buildings
-- The Ride Shop is where rides are bought (the server checks you're there).
Layout.RideShop = Vector3.new(0, Config.BEACH_TOP, -88) -- pedestal
Layout.RideShopPad = Vector3.new(0, Config.BEACH_TOP, -66) -- step here to shop
Layout.RIDE_SHOP_RADIUS = 26
Layout.Huts = {
	{ kind = "Shop", title = "SHOP", color = Color3.fromRGB(255, 70, 170), pos = Vector3.new(-66, Config.BEACH_TOP, -96) },
	{ kind = "Index", title = "INDEX", color = Color3.fromRGB(255, 150, 30), pos = Vector3.new(66, Config.BEACH_TOP, -96) },
	{ kind = "Sell", title = "SELL", color = Color3.fromRGB(70, 210, 90), pos = Vector3.new(106, Config.BEACH_TOP, -96) },
}
Layout.Board = Vector3.new(-112, Config.BEACH_TOP, -114)
Layout.GroupChest = Vector3.new(36, Config.BEACH_TOP, -66) -- "Join Group / Like to Claim!"

-- standing at a hut's pad (the server checks before selling)
function Layout.atHut(kind: string, pos: Vector3): boolean
	for _, h in Layout.Huts do
		if h.kind == kind then
			local pad = h.pos + Vector3.new(0, 0, 9)
			return Vector2.new(pos.X - pad.X, pos.Z - pad.Z).Magnitude < 14 and math.abs(pos.Y - Config.BEACH_TOP) < 12
		end
	end
	return false
end

function Layout.atRideShop(pos: Vector3): boolean
	local d = Vector2.new(pos.X - Layout.RideShopPad.X, pos.Z - (Layout.RideShopPad.Z - 8)).Magnitude
	return d < Layout.RIDE_SHOP_RADIUS and math.abs(pos.Y - Config.BEACH_TOP) < 12
end

----------------------------------------------------------------- queries
-- the sand ramp from the beach down onto the water (World.luau builds it)
Layout.RAMP_LEN = 8
-- height of the ground you ride on at z: the beach, the ramp, or the water floor
function Layout.groundY(z: number): number
	local t = math.clamp((z - Config.SHORE_Z) / Layout.RAMP_LEN, 0, 1)
	return Config.BEACH_TOP + (Config.FLOOR_TOP - Config.BEACH_TOP) * t
end

function Layout.inWater(pos: Vector3): boolean
	return pos.Z >= Config.SHORE_Z + 1
end

-- distance from p to the segment a-b on the XZ plane (swept pickups, so
-- nothing is missed at high speed between server ticks)
function Layout.segmentDist(p: Vector3, a: Vector3, b: Vector3): number
	local ab = Vector2.new(b.X - a.X, b.Z - a.Z)
	local ap = Vector2.new(p.X - a.X, p.Z - a.Z)
	local len2 = ab:Dot(ab)
	local t = len2 > 0 and math.clamp(ap:Dot(ab) / len2, 0, 1) or 0
	return (ap - ab * t).Magnitude
end

function Layout.islandAt(pos: Vector3, pad: number?): Island?
	local p = pad or 0
	for _, island in Layout.Islands do
		local d = Vector2.new(pos.X - island.pos.X, pos.Z - island.pos.Z).Magnitude
		if d <= island.radius + p then
			return island
		end
	end
	return nil
end

function Layout.isSafe(pos: Vector3): boolean
	return not Layout.inWater(pos) or Layout.islandAt(pos, 0.5) ~= nil
end

-- nearest safe point: an island or the beach straight back
function Layout.nearestSafe(pos: Vector3): (Vector3, number)
	local best = Vector3.new(pos.X, Config.BEACH_TOP, Config.SHORE_Z - 6)
	local bestD = math.max(pos.Z - Config.SHORE_Z, 0)
	for _, island in Layout.Islands do
		local d = Vector2.new(pos.X - island.pos.X, pos.Z - island.pos.Z).Magnitude - island.radius
		if d < bestD then
			bestD = d
			best = island.pos
		end
	end
	return best, bestD
end

return Layout

end
MODULES['cmod:UI'] = function()
local script = { Parent = CLIENT }
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
	local function paint(c: Color3)
		busy = true
		face.BackgroundColor3 = c
		b.BackgroundColor3 = UI.dark(c, 0.38)
		stroke.Color = UI.dark(c, 0.5)
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
	end)
	local function up()
		TweenService:Create(face, TweenInfo.new(0.12, Enum.EasingStyle.Back), { Position = UDim2.fromOffset(0, 0) }):Play()
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
	local state = on
	local function set(v: boolean)
		state = v
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
	UI.stroke(f, UI.T.white, 2)
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
	UI.stroke(f, UI.dark(color, 0.35), UI.S.cta)
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

end
MODULES['cmod:Sounds'] = function()
local script = { Parent = CLIENT }
-- Builds Sounds from Config.SoundSlots: which uploaded file, which part of it
-- (PlaybackRegion / LoopRegion), pitch, EQ and a loudness gain, so every edit
-- happens in the game and the files never need re-uploading. While a file has
-- no id yet, the slot falls back (spec.fallback, then Config.Sounds built-ins).

local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Shared = game.ReplicatedStorage.Shared
local Config = require(Shared.Config)

local Sounds = {}

-- mixer groups (future volume settings can turn these)
local groups: { [string]: SoundGroup } = {}
function Sounds.group(name: string): SoundGroup
	local g = groups[name]
	if not g then
		g = Instance.new("SoundGroup")
		g.Name = name
		g.Volume = 1
		g.Parent = SoundService
		groups[name] = g
	end
	return g
end

local function asId(v: any): string
	if typeof(v) ~= "string" or v == "" then
		return ""
	end
	return v:match("^%d+$") and ("rbxassetid://" .. v) or v
end

-- the slot to use (following fallbacks) and its sound id; "" = silent
function Sounds.resolve(name: string): (Config.SoundSlot?, string)
	local seen = 0
	local key: string? = name
	while key and seen < 4 do
		seen += 1
		local spec = Config.SoundSlots[key]
		if spec then
			local id = asId(Config.SoundFiles[spec.file])
			if id ~= "" then
				return spec, id
			end
			local builtin = asId(Config.Sounds[key])
			if builtin ~= "" then
				return nil, builtin
			end
			key = spec.fallback
		else
			return nil, asId(Config.Sounds[key])
		end
	end
	return nil, ""
end

function Sounds.has(name: string): boolean
	local _, id = Sounds.resolve(name)
	return id ~= ""
end

-- A configured Sound (not playing). Its "Gain" and "Pitch" attributes hold
-- the slot's values so code that animates Volume / PlaybackSpeed can keep them.
function Sounds.make(name: string, volume: number?, pitch: number?, parent: Instance?, looped: boolean?, group: string?): Sound?
	local spec, id = Sounds.resolve(name)
	if id == "" then
		return nil
	end
	local s = Instance.new("Sound")
	s.Name = name
	s.SoundId = id
	local gain = spec and spec.gain or 1
	local basePitch = spec and spec.pitch or 1
	s:SetAttribute("Gain", gain)
	s:SetAttribute("Pitch", basePitch)
	s.Volume = math.min((volume or 0.6) * gain, 10)
	s.PlaybackSpeed = (pitch or 1) * basePitch
	s.Looped = looped == true
	if spec then
		if spec.loop then
			s.PlaybackRegionsEnabled = true
			s.PlaybackRegion = NumberRange.new(spec.loop[1], spec.loop[2])
			s.LoopRegion = NumberRange.new(spec.loop[1], spec.loop[2])
		elseif spec.from or spec.to then
			s.PlaybackRegionsEnabled = true
			s.PlaybackRegion = NumberRange.new(spec.from or 0, spec.to or 600)
		end
		if spec.eq then
			local eq = Instance.new("EqualizerSoundEffect")
			eq.LowGain = spec.eq[1] or 0
			eq.MidGain = spec.eq[2] or 0
			eq.HighGain = spec.eq[3] or 0
			eq.Parent = s
		end
	end
	if group then
		s.SoundGroup = Sounds.group(group)
	end
	s.Parent = parent or SoundService
	return s
end

-- set a made Sound's volume, keeping its slot gain
function Sounds.setVolume(s: Sound, volume: number)
	s.Volume = math.min(volume * ((s:GetAttribute("Gain") :: number?) or 1), 10)
end

-- a random start inside a loop (so several copies don't play in step)
function Sounds.randomStart(s: Sound)
	if s.PlaybackRegionsEnabled then
		local r = s.LoopRegion
		s.TimePosition = r.Min + math.random() * math.max(r.Max - r.Min, 0)
	end
end

-- play a one-shot (plus its layers) and clean up; returns the main Sound
function Sounds.play(name: string, volume: number?, pitch: number?, parent: Instance?, group: string?): Sound?
	local s = Sounds.make(name, volume, pitch, parent, false, group)
	if not s then
		return nil
	end
	local spec = Sounds.resolve(name)
	s:Play()
	local length = 6
	if spec and spec.to then
		length = (spec.to - (spec.from or 0)) / math.max(s.PlaybackSpeed, 0.05)
	end
	if spec and spec.fade and spec.to then
		local fade = spec.fade / math.max(s.PlaybackSpeed, 0.05)
		task.delay(math.max(length - fade, 0), function()
			if s.Parent then
				TweenService:Create(s, TweenInfo.new(fade), { Volume = 0 }):Play()
			end
		end)
	end
	task.delay(math.max(length, 0.2) + 0.5, function()
		if s.IsPlaying and not spec then
			return -- unknown length (built-in fallback): let Ended clean it
		end
		s:Destroy()
	end)
	s.Ended:Once(function()
		task.defer(function()
			s:Destroy()
		end)
	end)
	if spec and spec.layers then
		for _, layer in spec.layers do
			Sounds.play(layer, volume, pitch, parent, group)
		end
	end
	return s
end

return Sounds

end
MODULES['cmod:Fx'] = function()
local script = { Parent = CLIENT }
-- Juice: sounds, 3D bursts, number popups, camera shake, screen flashes.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local Debris = game:GetService("Debris")
local Workspace = game:GetService("Workspace")

local UI = require(script.Parent.UI)
local Sounds = require(script.Parent.Sounds)

local Fx = {}

local player = Players.LocalPlayer
local fxFolder = Instance.new("Folder")
fxFolder.Name = "LocalFx"
fxFolder.Parent = Workspace

Fx.TEX = {
	sparkle = "rbxasset://textures/particles/sparkles_main.dds",
	smoke = "rbxasset://textures/particles/smoke_main.dds",
}

----------------------------------------------------------------- sound
-- one-shot by slot name (Config.SoundSlots via Sounds.luau). `at` makes it
-- 3D: a world position, or a part/attachment it follows (a rider's root)
local UI_SOUNDS = { uiClick = true, uiOpen = true, uiClose = true, uiError = true, uiToast = true, uiTakeover = true }
function Fx.sound(name: string, volume: number?, pitch: number?, at: (Vector3 | Instance)?)
	if not Sounds.has(name) then
		return
	end
	local group = UI_SOUNDS[name] and "UI" or "Effects"
	if typeof(at) == "Vector3" then
		local a = Instance.new("Attachment")
		a.WorldPosition = at
		a.Parent = Workspace.Terrain
		local s = Sounds.play(name, volume, pitch, a, group)
		if s then
			s.RollOffMode = Enum.RollOffMode.InverseTapered
			s.RollOffMinDistance = 12
			s.RollOffMaxDistance = 300
		end
		Debris:AddItem(a, 8)
	elseif typeof(at) == "Instance" then
		local s = Sounds.play(name, volume, pitch, at, group)
		if s then
			s.RollOffMode = Enum.RollOffMode.InverseTapered
			s.RollOffMinDistance = 12
			s.RollOffMaxDistance = 200
		end
	else
		Sounds.play(name, volume, pitch, SoundService, group)
	end
end

----------------------------------------------------------------- 3D bursts
local function emitterAt(pos: Vector3, props: { [string]: any }, count: number, life: number?)
	local a = Instance.new("Attachment")
	a.WorldPosition = pos
	a.Parent = Workspace.Terrain
	local e = Instance.new("ParticleEmitter")
	e.Enabled = false
	for k, v in props do
		(e :: any)[k] = v
	end
	e.Parent = a
	e:Emit(count)
	Debris:AddItem(a, life or 3)
	return e
end

function Fx.splash(pos: Vector3, size: number?)
	local s = size or 1
	emitterAt(pos, {
		Texture = Fx.TEX.smoke,
		Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(180, 240, 255)),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.5 * s), NumberSequenceKeypoint.new(1, 4 * s) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) }),
		Lifetime = NumberRange.new(0.6, 1.1),
		Speed = NumberRange.new(14 * s, 30 * s),
		SpreadAngle = Vector2.new(35, 35),
		EmissionDirection = Enum.NormalId.Top,
		Acceleration = Vector3.new(0, -60, 0),
		Drag = 2,
		LightEmission = 0.3,
	}, math.floor(28 * s))
	emitterAt(pos, {
		Texture = Fx.TEX.sparkle,
		Color = ColorSequence.new(Color3.fromRGB(200, 250, 255)),
		Size = NumberSequence.new(0.6 * s, 0),
		Lifetime = NumberRange.new(0.5, 0.9),
		Speed = NumberRange.new(20 * s, 40 * s),
		SpreadAngle = Vector2.new(50, 50),
		EmissionDirection = Enum.NormalId.Top,
		Acceleration = Vector3.new(0, -80, 0),
		LightEmission = 1,
	}, math.floor(30 * s))
end

function Fx.confetti(pos: Vector3, colors: { Color3 }?)
	local cols = colors or { UI.C.pink, UI.C.gold, UI.C.sky, UI.C.green }
	for _, c in cols do
		emitterAt(pos, {
			Texture = "",
			Color = ColorSequence.new(c),
			Size = NumberSequence.new(0.35),
			Lifetime = NumberRange.new(1.2, 2),
			Speed = NumberRange.new(25, 45),
			SpreadAngle = Vector2.new(60, 60),
			EmissionDirection = Enum.NormalId.Top,
			Acceleration = Vector3.new(0, -50, 0),
			Rotation = NumberRange.new(0, 360),
			RotSpeed = NumberRange.new(-300, 300),
			Drag = 1.5,
		}, 18)
	end
end

function Fx.sparkle(pos: Vector3, color: Color3, count: number?)
	emitterAt(pos, {
		Texture = Fx.TEX.sparkle,
		Color = ColorSequence.new(color),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.2), NumberSequenceKeypoint.new(1, 0) }),
		Lifetime = NumberRange.new(0.6, 1.2),
		Speed = NumberRange.new(8, 20),
		SpreadAngle = Vector2.new(180, 180),
		LightEmission = 1,
		Drag = 3,
	}, count or 30)
end

-- shockwave ring on the water
function Fx.ring(pos: Vector3, color: Color3, maxSize: number)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CastShadow = false
	p.Shape = Enum.PartType.Cylinder
	p.Material = Enum.Material.Neon
	p.Color = color
	p.Size = Vector3.new(0.2, 2, 2)
	p.CFrame = CFrame.new(pos) * CFrame.Angles(0, 0, math.pi / 2)
	p.Transparency = 0.2
	p.Parent = fxFolder
	TweenService:Create(p, TweenInfo.new(0.6, Enum.EasingStyle.Quad), { Size = Vector3.new(0.2, maxSize, maxSize), Transparency = 1 }):Play()
	Debris:AddItem(p, 0.7)
end

----------------------------------------------------------------- popups
function Fx.popup3D(pos: Vector3, text: string, color: Color3?, big: boolean?)
	local a = Instance.new("Attachment")
	a.WorldPosition = pos
	a.Parent = Workspace.Terrain
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(big and 320 or 200, big and 80 or 50)
	bb.AlwaysOnTop = true
	bb.LightInfluence = 0
	bb.Adornee = a
	bb.Parent = a
	local t = UI.outlined(bb, text, { TextColor3 = color or UI.C.gold })
	local scale = Instance.new("UIScale")
	scale.Scale = 0.3
	scale.Parent = t
	TweenService:Create(scale, TweenInfo.new(0.35, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	TweenService:Create(bb, TweenInfo.new(1.2, Enum.EasingStyle.Quad), { StudsOffsetWorldSpace = Vector3.new(0, 5, 0) }):Play()
	task.delay(0.8, function()
		UI.fade(t, false, 0.4) -- text and its outline together
	end)
	Debris:AddItem(a, 1.4)
end

----------------------------------------------------------------- camera
local shakeAmount = 0
RunService:BindToRenderStep("FxShake", Enum.RenderPriority.Camera.Value + 1, function(dt)
	if shakeAmount > 0.01 then
		local cam = Workspace.CurrentCamera
		local a = shakeAmount
		cam.CFrame = cam.CFrame * CFrame.Angles(math.rad((math.random() - 0.5) * a), math.rad((math.random() - 0.5) * a), 0)
		shakeAmount *= math.exp(-dt * 6)
	end
end)

function Fx.shake(amount: number)
	shakeAmount = math.max(shakeAmount, amount)
end

----------------------------------------------------------------- screen
local screen: ScreenGui
function Fx.screen(): ScreenGui
	if not screen then
		screen = Instance.new("ScreenGui")
		screen.Name = "FxScreen"
		screen.IgnoreGuiInset = true
		screen.ResetOnSpawn = false
		screen.DisplayOrder = 20
		screen.Parent = player:WaitForChild("PlayerGui")
	end
	return screen
end

function Fx.flash(color: Color3, duration: number?, startT: number?)
	local f = UI.frame(Fx.screen(), {
		Size = UDim2.fromScale(1, 1), BackgroundColor3 = color, BackgroundTransparency = startT or 0.3, ZIndex = 50,
	})
	TweenService:Create(f, TweenInfo.new(duration or 0.5), { BackgroundTransparency = 1 }):Play()
	Debris:AddItem(f, (duration or 0.5) + 0.1)
end

-- big center-screen word ("CHOMP!", "LUCKY!"). One at a time: a word that
-- arrives while another is up waits its turn (and stale ones are dropped).
local wordBusyUntil = 0
local wordQueue = 0

local function showWord(text: string, color: Color3, duration: number)
	local t = UI.outlined(Fx.screen(), text, {
		Size = UDim2.fromScale(0.8, 0.14), Position = UDim2.fromScale(0.5, 0.36), AnchorPoint = Vector2.new(0.5, 0.5),
		TextColor3 = color, ZIndex = 60, Rotation = -3,
	})
	local scale = Instance.new("UIScale")
	scale.Scale = 2.2
	scale.Parent = t
	TweenService:Create(scale, TweenInfo.new(0.3, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	task.delay(duration, function()
		UI.fade(t, false, 0.3)
		TweenService:Create(scale, TweenInfo.new(0.3), { Scale = 0.6 }):Play()
	end)
	Debris:AddItem(t, duration + 0.4)
end

Fx.wordHook = nil :: ((string, Color3?, number?) -> ())?

function Fx.bigWord(text: string, color: Color3, duration: number?)
	if Fx.wordHook then
		Fx.wordHook(text, color, duration) -- Notify's center stage (one at a time)
		return
	end
	local d = duration or 1
	local now = os.clock()
	if now >= wordBusyUntil then
		wordBusyUntil = now + d + 0.35
		showWord(text, color, d)
		return
	end
	if wordQueue >= 1 then
		return -- one waiting is enough; skip the rest
	end
	wordQueue += 1
	local at = wordBusyUntil
	wordBusyUntil = at + d + 0.35
	task.delay(at - now, function()
		wordQueue -= 1
		showWord(text, color, d)
	end)
end

Fx.folder = fxFolder
return Fx

end
MODULES['cmod:Notify'] = function()
local script = { Parent = CLIENT }
-- Every message on screen goes through here, in a clear hierarchy, so the
-- screen never piles up and the important thing is always the obvious one.
--
--   takeover  the big moment (shark incoming, new zone, new ride, legendary):
--             center stage; the HUD and every other message step aside.
--             One at a time, in order.
--   word      a punchy center word (LUCKY!, DODGED!, PTOOEY!). Shares center
--             stage with takeovers and never stacks (one waits, extras drop).
--   banner    the top-center title (plain outlined text, like "🌴 Lagoon 🌴").
--             One at a time: the highest priority shows,
--             the rest wait their turn. Sticky ones (shark status, tutorial
--             step) stay until cleared and briefly give way to newer ones.
--   toast     small outlined lines under the banner. Two at most.
--   status    the quiet line at the very top (distance at sea, $/day offline).
-- Timers pause while something bigger is up, so nothing is missed.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local UI = require(script.Parent.UI)
local Fx = require(script.Parent.Fx)

local Notify = {}
Notify.onTakeover = nil :: ((boolean) -> ())?

local player = Players.LocalPlayer
local C = UI.C

type BannerOpts = { sub: string?, color: Color3?, priority: number?, time: number?, key: string?, sticky: boolean?, big: boolean? }
type Banner = BannerOpts & { text: string, left: number, order: number, born: number }
type Center = { kind: string, text: string, sub: string?, color: Color3, time: number }

local gui: ScreenGui
local top: Frame
local statusLabel: TextLabel
local bannerSlot: Frame
local toastSlot: Frame
local stage: Frame

local banners: { Banner } = {}
local shownBanner: Banner? = nil
local bannerFrame: Frame? = nil
local order = 0

local toastQueue: { { text: string, color: Color3 } } = {}
local toastsUp = 0

local centerQueue: { Center } = {}
local centerBusy = false
local takeoverOn = false

local function suppressed(): boolean
	return takeoverOn or player:GetAttribute("Cinematic") == true or player:GetAttribute("ViewingTank") == true
end

----------------------------------------------------------------- build
-- Every line is plain outlined text (no pill, no box), in a fixed-height row
-- that the text scales to fit: long lines shrink instead of getting cut off.
local WIDTH = 1000
local function label(parent: Instance, text: string, height: number, color: Color3?, font: Enum.Font?): TextLabel
	local t = UI.outlined(parent, text, { TextScaled = true, Size = UDim2.fromOffset(WIDTH, height),
		TextColor3 = color or C.white, Font = font or UI.FONT })
	local stroke = t:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Thickness = height >= 50 and 4.5 or (height >= 36 and 3.5 or 2.5)
	end
	return t
end

local function build()
	gui = Instance.new("ScreenGui")
	gui.Name = "Notify"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 5
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = player:WaitForChild("PlayerGui")
	UI.autoScale(gui)

	-- top column: status, banner, toasts (each collapses when empty)
	top = UI.frame(gui, { Name = "Top", Size = UDim2.fromOffset(WIDTH, 0), AutomaticSize = Enum.AutomaticSize.Y,
		Position = UDim2.new(0.5, 0, 0, 4), AnchorPoint = Vector2.new(0.5, 0), BackgroundTransparency = 1 })
	local list = Instance.new("UIListLayout")
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, 6)
	list.Parent = top
	statusLabel = label(top, "", 24, C.white)
	statusLabel.LayoutOrder = 1
	statusLabel.Visible = false
	bannerSlot = UI.frame(top, { Name = "Banner", Size = UDim2.fromOffset(WIDTH, 0), BackgroundTransparency = 1, LayoutOrder = 2, Visible = false })
	toastSlot = UI.frame(top, { Name = "Toasts", Size = UDim2.fromOffset(WIDTH, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = 3 })
	local tl = Instance.new("UIListLayout")
	tl.HorizontalAlignment = Enum.HorizontalAlignment.Center
	tl.SortOrder = Enum.SortOrder.LayoutOrder
	tl.Padding = UDim.new(0, 2)
	tl.Parent = toastSlot

	-- center stage: takeovers and words
	stage = UI.frame(gui, { Name = "Stage", Size = UDim2.new(1, 0, 0, 230), Position = UDim2.fromScale(0.5, 0.38), AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1 })
end

----------------------------------------------------------------- status line
function Notify.status(text: string?, color: Color3?)
	local show = text ~= nil and text ~= ""
	statusLabel.Visible = show and not suppressed()
	if show and statusLabel.Text ~= text then
		statusLabel.Text = text :: string
	end
	statusLabel.TextColor3 = color or C.white
end

----------------------------------------------------------------- banners
local function bannerHeights(b: Banner): (number, number)
	local title = b.big and 64 or 46
	return title, b.sub and 26 or 0
end

local function bannerUI(b: Banner): Frame
	local th, sh = bannerHeights(b)
	bannerSlot.Size = UDim2.fromOffset(WIDTH, th + sh)
	local f = UI.frame(bannerSlot, { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 })
	local title = label(f, b.text, th, b.color or C.white)
	title.Name = "Title"
	local sub = label(f, b.sub or "", 26, Color3.fromRGB(235, 242, 255))
	sub.Name = "Sub"
	sub.Position = UDim2.fromOffset(0, th)
	sub.Visible = b.sub ~= nil
	return f
end

local function pickBanner(): Banner?
	local best: Banner? = nil
	for _, b in banners do
		local p = b.priority or 1
		-- a sticky banner steps aside for a fresh transient one of equal priority
		local bp = best and (best.priority or 1) or -1
		if not best or p > bp or (p == bp and (best.sticky and not b.sticky)) then
			best = b
		end
	end
	return best
end

local function swapBanner()
	local want = if suppressed() then nil else pickBanner()
	if want == shownBanner then
		return
	end
	local old = bannerFrame
	if old then
		bannerFrame = nil
		UI.fade(old, false, 0.15)
		task.delay(0.16, function()
			old:Destroy()
		end)
	end
	shownBanner = want
	bannerSlot.Visible = want ~= nil
	if want then
		local f = bannerUI(want)
		bannerFrame = f
		if old then
			f.Visible = false
			task.delay(0.16, function()
				if f.Parent then
					f.Visible = true
					UI.fade(f, true, 0.18)
					UI.pop(f, 1.08)
				end
			end)
		else
			UI.fade(f, true, 0.18)
			UI.pop(f, 1.12)
		end
	end
end

-- show (or update, same key) a top banner
function Notify.banner(text: string, opts: BannerOpts?)
	local o = opts or {}
	if o.key then
		for _, b in banners do
			if b.key == o.key then
				local changed = b.text ~= text or b.sub ~= o.sub or b.color ~= o.color
				local resized = (b.sub == nil) ~= (o.sub == nil)
				b.text, b.sub, b.color = text, o.sub, o.color
				b.priority = o.priority or b.priority
				if not b.sticky then
					b.left = o.time or 2.4
				end
				if changed and b == shownBanner and bannerFrame then
					local f = bannerFrame :: Frame
					local t = f:FindFirstChild("Title") :: TextLabel
					local s = f:FindFirstChild("Sub") :: TextLabel
					t.Text, t.TextColor3 = text, o.color or C.white
					s.Text, s.Visible = o.sub or "", o.sub ~= nil
					if resized then
						local th, sh = bannerHeights(b)
						bannerSlot.Size = UDim2.fromOffset(WIDTH, th + sh)
					end
				end
				return
			end
		end
	end
	order += 1
	table.insert(banners, {
		text = text, sub = o.sub, color = o.color, priority = o.priority or 1, key = o.key, sticky = o.sticky, big = o.big,
		left = o.time or 2.4, order = order, born = os.clock(),
	})
	swapBanner()
end

function Notify.clear(key: string)
	for i = #banners, 1, -1 do
		if banners[i].key == key then
			table.remove(banners, i)
		end
	end
	swapBanner()
end

----------------------------------------------------------------- toasts
local pumpToasts: () -> ()
local function showToast(item: { text: string, color: Color3 })
	toastsUp += 1
	Fx.sound("uiToast", 0.3)
	local t = label(toastSlot, item.text, 28, item.color)
	t.LayoutOrder = -os.clock() * 100 // 1 -- newest on top
	UI.fade(t, true, 0.15)
	UI.pop(t, 1.15)
	task.spawn(function()
		local left = 2.6
		while left > 0 do
			local dt = RunService.Heartbeat:Wait()
			if not suppressed() then
				left -= dt
			end
			t.Visible = not suppressed()
		end
		UI.fade(t, false, 0.25)
		task.wait(0.26)
		t:Destroy()
		toastsUp -= 1
		pumpToasts()
	end)
end

pumpToasts = function()
	while toastsUp < 2 and #toastQueue > 0 and not suppressed() do
		showToast(table.remove(toastQueue, 1) :: any)
	end
end

function Notify.toast(text: string, color: Color3?)
	for _, q in toastQueue do
		if q.text == text then
			return
		end
	end
	table.insert(toastQueue, { text = text, color = color or C.white })
	while #toastQueue > 3 do
		table.remove(toastQueue, 1) -- stale news goes first
	end
	pumpToasts()
end

----------------------------------------------------------------- center stage
local runCenter: () -> ()

local function setTakeover(on: boolean)
	if takeoverOn == on then
		return
	end
	takeoverOn = on
	if Notify.onTakeover then
		Notify.onTakeover(on)
	end
	statusLabel.Visible = statusLabel.Visible and not on
	swapBanner()
	if not on then
		pumpToasts()
	end
end

local function playCenter(item: Center)
	local big = item.kind == "takeover"
	if big then
		Fx.sound("uiTakeover", 0.7)
	end
	local holder = UI.frame(stage, { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 })
	if big then
		-- a soft dark band behind the words so they read over anything
		local band = UI.frame(holder, { Size = UDim2.new(1, 0, 0, 190), Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.45 })
		local g = Instance.new("UIGradient")
		g.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.25, 0.2),
			NumberSequenceKeypoint.new(0.75, 0.2), NumberSequenceKeypoint.new(1, 1) })
		g.Parent = band
	end
	local title = UI.outlined(holder, item.text, { Size = UDim2.new(0.92, 0, 0, big and 104 or 84), Position = UDim2.new(0.5, 0, 0.5, big and -16 or 0),
		AnchorPoint = Vector2.new(0.5, 0.5), Font = UI.NUMFONT, TextColor3 = item.color, Rotation = big and 0 or -3 })
	local stroke = title:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Thickness = 5
	end
	local shine = Instance.new("UIGradient")
	shine.Rotation = 90
	shine.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(205, 205, 205))
	shine.Parent = title
	if big and item.sub then
		UI.outlined(holder, item.sub, { Size = UDim2.new(0.8, 0, 0, 34), Position = UDim2.new(0.5, 0, 0.5, 58), AnchorPoint = Vector2.new(0.5, 0.5) })
	end
	local scale = Instance.new("UIScale")
	scale.Scale = big and 1.9 or 2.2
	scale.Parent = holder
	UI.fade(holder, true, 0.15)
	TweenService:Create(scale, TweenInfo.new(0.32, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	task.wait(item.time)
	UI.fade(holder, false, 0.3)
	TweenService:Create(scale, TweenInfo.new(0.3, Enum.EasingStyle.Quad), { Scale = big and 0.9 or 0.7 }):Play()
	task.wait(0.3)
	holder:Destroy()
end

runCenter = function()
	if centerBusy then
		return
	end
	centerBusy = true
	task.spawn(function()
		while #centerQueue > 0 do
			-- takeovers jump ahead of waiting words
			local idx = 1
			for i, it in centerQueue do
				if it.kind == "takeover" then
					idx = i
					break
				end
			end
			local item = table.remove(centerQueue, idx) :: Center
			if item.kind == "takeover" then
				setTakeover(true)
			end
			playCenter(item)
			local more = false
			for _, it in centerQueue do
				if it.kind == "takeover" then
					more = true
				end
			end
			if not more then
				setTakeover(false)
			end
			task.wait(0.12)
		end
		centerBusy = false
	end)
end

-- the big moment: center stage, everything else steps aside
function Notify.takeover(text: string, sub: string?, color: Color3?, time: number?)
	table.insert(centerQueue, { kind = "takeover", text = text, sub = sub, color = color or C.gold, time = time or 1.7 })
	runCenter()
end

-- a punchy center word; one waits, extra ones are dropped
function Notify.word(text: string, color: Color3?, time: number?)
	local waiting = 0
	for _, it in centerQueue do
		if it.kind == "word" then
			waiting += 1
		end
	end
	if waiting >= 1 and centerBusy then
		return
	end
	table.insert(centerQueue, { kind = "word", text = text, color = color or C.gold, time = time or 0.9 })
	runCenter()
end

----------------------------------------------------------------- tick
function Notify.start()
	build()
	-- Fx.bigWord (used everywhere for punch words) lands on center stage
	Fx.wordHook = Notify.word
	RunService.Heartbeat:Connect(function(dt)
		-- news that waited too long behind something more important is stale
		for i = #banners, 1, -1 do
			local b = banners[i]
			if not b.sticky and b ~= shownBanner and os.clock() - b.born > 5 then
				table.remove(banners, i)
			end
		end
		if suppressed() then
			if shownBanner then
				swapBanner()
			end
			return
		end
		local b = shownBanner
		if b and not b.sticky then
			b.left -= dt
			if b.left <= 0 then
				local i = table.find(banners, b)
				if i then
					table.remove(banners, i)
				end
				swapBanner()
			end
		elseif b and b.sticky then
			-- a transient banner that arrived later gets its turn
			swapBanner()
		elseif not b and #banners > 0 then
			swapBanner()
		end
	end)
	local function refresh()
		swapBanner()
		statusLabel.Visible = statusLabel.Visible and not suppressed()
		pumpToasts()
	end
	player:GetAttributeChangedSignal("Cinematic"):Connect(refresh)
	player:GetAttributeChangedSignal("ViewingTank"):Connect(refresh)
end

return Notify

end
MODULES['cmod:Guide'] = function()
local script = { Parent = CLIENT }
-- The guide beam: a glowing arc from your feet to a target plus a bouncing
-- arrow marker. Several systems can ask for it; the highest priority wins
-- (shark danger > tutorial > ride shop).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local UI = require(script.Parent.UI)

local Guide = {}
local C = UI.C
local player = Players.LocalPlayer

local PRIORITY = { "danger", "tut", "shop" }
local requests: { [string]: { at: Vector3, label: string? } } = {}

local folder = Instance.new("Folder")
folder.Name = "Guide"
folder.Parent = Workspace

local target = Instance.new("Part")
target.Name = "GuideTarget"
target.Anchored = true
target.CanCollide = false
target.CanQuery = false
target.CanTouch = false
target.Transparency = 1
target.Size = Vector3.new(0.2, 0.2, 0.2)
target.Parent = folder

local targetAtt = Instance.new("Attachment")
targetAtt.Parent = target

local beam = Instance.new("Beam")
beam.Attachment1 = targetAtt
beam.FaceCamera = true
beam.Width0 = 1.4
beam.Width1 = 0.6
beam.Segments = 24
beam.CurveSize0 = 6
beam.CurveSize1 = -6
beam.LightEmission = 1
beam.LightInfluence = 0
beam.Color = ColorSequence.new(C.gold)
beam.Transparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0.85),
	NumberSequenceKeypoint.new(0.25, 0.15),
	NumberSequenceKeypoint.new(1, 0.1),
})
beam.Enabled = false
beam.Parent = target

local marker = Instance.new("BillboardGui")
marker.Size = UDim2.fromOffset(160, 110)
marker.StudsOffset = Vector3.new(0, 6, 0)
marker.AlwaysOnTop = true
marker.LightInfluence = 0
marker.Enabled = false
marker.Parent = target
local markerText = UI.outlined(marker, "", { Size = UDim2.new(1, 0, 0, 34), TextColor3 = C.gold })
local markerArrow = UI.icon(marker, "Arrow", { Size = UDim2.new(1, 0, 0, 64), Position = UDim2.fromOffset(0, 40) })

local feetAtt: Attachment? = nil
local function ensureFeet(): boolean
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return false
	end
	if not feetAtt or feetAtt.Parent ~= hrp then
		local a = Instance.new("Attachment")
		a.Name = "GuideFeet"
		a.Position = Vector3.new(0, -2, 0)
		a.Parent = hrp
		feetAtt = a
		beam.Attachment0 = a
	end
	return true
end

-- owner: "tut" or "shop"; at = nil clears that owner's request
function Guide.set(owner: string, at: Vector3?, label: string?)
	requests[owner] = at and { at = at, label = label } or nil
end

function Guide.active(owner: string): boolean
	return requests[owner] ~= nil
end

RunService.Heartbeat:Connect(function()
	local req = nil
	for _, owner in PRIORITY do
		if requests[owner] then
			req = requests[owner]
			break
		end
	end
	if not req or not ensureFeet() then
		beam.Enabled = false
		marker.Enabled = false
		return
	end
	target.Position = req.at
	markerText.Text = req.label or ""
	beam.Enabled = true
	marker.Enabled = true
	markerArrow.Position = UDim2.fromOffset(0, 40 - math.abs(math.sin(os.clock() * 4)) * 12)
end)

return Guide

end
MODULES['cmod:Travel'] = function()
local script = { Parent = CLIENT }
-- Getting to the buildings. Menus only open in person (step on a pad), so
-- the HUD buttons bring you there: on land you land right in front of the
-- pad, facing it, and walk in (the pad opens the menu); on the water the
-- guide arrow leads you back first.

local Players = game:GetService("Players")

local Shared = game.ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Layout = require(Shared.Layout)
local UI = require(script.Parent.UI)
local Fx = require(script.Parent.Fx)
local Guide = require(script.Parent.Guide)

local Travel = {}
local player = Players.LocalPlayer

local LABELS = { Rides = "Ride Shop", Shop = "Shop", Index = "Index", Sell = "Sell" }

-- the pad's centre and radius (World.luau builds them: huts 13 wide, Ride Shop 15)
function Travel.padPos(kind: string): (Vector3?, number)
	if kind == "Rides" then
		return Layout.RideShopPad, 7.5
	end
	for _, h in Layout.Huts do
		if h.kind == kind then
			return h.pos + Vector3.new(0, 0, 9), 6.5
		end
	end
	return nil, 0
end

function Travel.go(kind: string)
	local pad, radius = Travel.padPos(kind)
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not (pad and hrp) or hrp.Anchored then
		return
	end
	local pos = hrp.Position
	if Layout.inWater(pos) and not Layout.islandAt(pos, 0) then
		Guide.set("shop", pad + Vector3.new(0, 1, 0), LABELS[kind])
		Fx.bigWord("GET TO LAND FIRST!", UI.C.sky, 1.1)
		return
	end
	Fx.splash(pos, 0.8)
	-- land a few steps in front of the pad, facing the building (buildings
	-- face +Z, so look -Z): one short walk in opens it
	local at = pad + Vector3.new(0, Config.BEACH_TOP + 3 - pad.Y, radius + 5)
	char:PivotTo(CFrame.lookAt(at, at - Vector3.new(0, 0, 1)))
	hrp.AssemblyLinearVelocity = Vector3.zero
	Fx.ring(at - Vector3.new(0, 2.6, 0), UI.C.white, 12)
	-- a little arrow onto the pad until you step on it
	Guide.set("shop", pad + Vector3.new(0, 1, 0), "Walk in!")
	task.spawn(function()
		local t0 = os.clock()
		while os.clock() - t0 < 8 do
			task.wait(0.1)
			local h = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if not h or Vector2.new(h.Position.X - pad.X, h.Position.Z - pad.Z).Magnitude < radius then
				break
			end
		end
		if Guide.active("shop") then
			Guide.set("shop", nil)
		end
	end)
end

return Travel

end
MODULES['cmod:Prompts'] = function()
local script = { Parent = CLIENT }
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

-- fires (prompt) when the local player triggers any prompt: real triggers
-- and touch holds finished on the button (see build). Listen here, not to
-- ProximityPromptService, so phones always work.
local triggeredEvent = Instance.new("BindableEvent")
Prompts.Triggered = triggeredEvent.Event
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
		key.Text = "TAP"
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

end
MODULES['cmod:HUD'] = function()
local script = { Parent = CLIENT }
-- The always-on screen in the Steal-an-Egg style: small, bright, studded,
-- one obvious next thing.
--   left:          Shop / Index / Rides buttons + the Slow Mode box
--   right:         small squares: Tank, Rebirth, offers and active boosts
--                  (time left above the square)
--   bottom-left:   speed (sneaker) and money, Friend Boost
--   bottom-center: +speed/s and tank $/s, zone goal bar, next ride button
--   bottom-right:  next shark attack
-- Every message goes through Notify: one hierarchy, nothing piles up.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local MarketplaceService = game:GetService("MarketplaceService")

local Shared = game.ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Layout = require(Shared.Layout)
local Remotes = require(Shared.Remotes)
local UI = require(script.Parent.UI)
local Fx = require(script.Parent.Fx)
local State = require(script.Parent.State)
local Water = require(script.Parent.Water)
local SharkView = require(script.Parent.SharkView)
local Travel = require(script.Parent.Travel)
local Guide = require(script.Parent.Guide)
local Notify = require(script.Parent.Notify)

local HUD = {}
local C = UI.C
local player = Players.LocalPlayer

local gui: ScreenGui
local speedLabel: TextLabel
local coinsLabel: TextLabel
local gainLabel: TextLabel
local tankLabel: TextLabel
local friendLabel: TextLabel
local goalFill: Frame
local goalText: TextLabel
local rideBtn: TextButton
local ridePrice: TextLabel
local rideFill: Frame
local carryChip: TextLabel
local vignette: Frame
local menuButtons: { [string]: TextButton } = {}
local boostSquares: { [string]: { holder: Frame, button: TextButton, timer: TextLabel } } = {}
local timerPill: Frame
local timerLabel: TextLabel
local stopRidePulse: (() -> ())? = nil
local setSlow: ((boolean) -> ())? = nil

HUD.onRides = nil :: (() -> ())?
HUD.onShop = nil :: (() -> ())?
HUD.onIndex = nil :: (() -> ())?
HUD.atRideShop = nil :: (() -> boolean)?
HUD.onRebirth = nil :: (() -> ())?
HUD.onTank = nil :: (() -> ())?
HUD.onDaily = nil :: (() -> ())?
HUD.takeover = false

function HUD.goToRideShop()
	Travel.go("Rides")
end

local function call(fn: (() -> ())?)
	if fn then
		fn()
	end
end

----------------------------------------------------------------- build
local function square(parent: Instance, icon: string, color: Color3, order: number, onClick: () -> ()): TextButton
	return UI.iconButton(parent, icon, "", color, onClick, { Size = UDim2.fromOffset(62, 62), LayoutOrder = order })
end

-- a square with a little timer over it (active boosts, like the reference potion)
local function timedSquare(parent: Instance, key: string, icon: string, color: Color3, order: number)
	local holder = UI.frame(parent, { Name = key, Size = UDim2.fromOffset(66, 84), BackgroundTransparency = 1, LayoutOrder = order, Visible = false })
	local timer = UI.outlined(holder, "", { Size = UDim2.new(1, 16, 0, 18), Position = UDim2.new(0.5, 0, 0, 0), AnchorPoint = Vector2.new(0.5, 0), TextColor3 = C.orange })
	local b = UI.iconButton(holder, icon, "", color, function()
		call(HUD.onShop)
	end, { Size = UDim2.fromOffset(62, 62), Position = UDim2.new(0.5, 0, 1, 0), AnchorPoint = Vector2.new(0.5, 1) })
	boostSquares[key] = { holder = holder, button = b, timer = timer }
end

local function build()
	gui = Instance.new("ScreenGui")
	gui.Name = "HUD"
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = player:WaitForChild("PlayerGui")
	UI.autoScale(gui)

	-- left: menu buttons + Slow Mode
	local menu = UI.frame(gui, { Name = "Menu", Size = UDim2.fromOffset(180, 250), Position = UDim2.new(0, 10, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5), BackgroundTransparency = 1 })
	local list = Instance.new("UIListLayout")
	list.Padding = UDim.new(0, 8)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.VerticalAlignment = Enum.VerticalAlignment.Center
	list.Parent = menu
	local size = UDim2.fromOffset(170, 56)
	menuButtons.Shop = UI.wideButton(menu, "Shop", "Shop", C.green, function()
		UI.clearBadge(menuButtons.Shop)
		call(HUD.onShop)
	end, { Size = size, LayoutOrder = 1, Visible = false })
	menuButtons.Index = UI.wideButton(menu, "Index", "Index", C.index, function()
		call(HUD.onIndex)
	end, { Size = size, LayoutOrder = 2 })
	menuButtons.Rides = UI.wideButton(menu, "Rides", "Rides", C.orange, function()
		call(HUD.onRides)
	end, { Size = size, LayoutOrder = 3 })
	local _, set = UI.toggle(menu, "Slow Mode", false, function(on)
		State.action("slowMode", on)
	end, { LayoutOrder = 4 })
	setSlow = set

	-- right: small squares
	local right = UI.frame(gui, { Name = "Right", Size = UDim2.fromOffset(70, 420), Position = UDim2.new(1, -10, 0.5, 0), AnchorPoint = Vector2.new(1, 0.5), BackgroundTransparency = 1 })
	local rl = Instance.new("UIListLayout")
	rl.Padding = UDim.new(0, 8)
	rl.HorizontalAlignment = Enum.HorizontalAlignment.Right
	rl.VerticalAlignment = Enum.VerticalAlignment.Center
	rl.SortOrder = Enum.SortOrder.LayoutOrder
	rl.Parent = right
	menuButtons.Daily = square(right, "Gift", C.pink, 0, function()
		call(HUD.onDaily)
	end)
	menuButtons.Tank = square(right, "Tank", C.orange, 1, function()
		call(HUD.onTank)
	end)
	menuButtons.Rebirth = square(right, "Rebirth", C.green, 2, function()
		call(HUD.onRebirth)
	end)
	menuButtons.Rebirth.Visible = false
	menuButtons.Offer = square(right, "X2Speed", C.red, 3, function() end)
	menuButtons.Offer.Visible = false
	timedSquare(right, "Shield", "Shield", C.sky, 4)
	timedSquare(right, "Boost", "Boost", C.purple, 5)
	timedSquare(right, "Luck", "Potion", C.green, 6)

	-- bottom-left: speed + money (the font's own $), friend boost
	local stats = UI.frame(gui, { Name = "Stats", Size = UDim2.fromOffset(250, 124), Position = UDim2.new(0, 12, 1, -8), AnchorPoint = Vector2.new(0, 1), BackgroundTransparency = 1 })
	UI.icon(stats, "Sneaker", { Size = UDim2.fromOffset(46, 46), Position = UDim2.fromOffset(0, 0) })
	speedLabel = UI.outlined(stats, "0", { Size = UDim2.fromOffset(196, 42), Position = UDim2.fromOffset(52, 3), TextXAlignment = Enum.TextXAlignment.Left, Font = UI.NUMFONT })
	local sg = Instance.new("UIGradient")
	sg.Color = ColorSequence.new(Color3.fromRGB(255, 214, 60), Color3.fromRGB(255, 120, 20))
	sg.Rotation = 90
	sg.Parent = speedLabel
	coinsLabel = UI.outlined(stats, "$0", { Size = UDim2.fromOffset(246, 42), Position = UDim2.fromOffset(2, 50), TextXAlignment = Enum.TextXAlignment.Left, Font = UI.NUMFONT, TextColor3 = C.money })
	friendLabel = UI.outlined(stats, "Friend Boost +0%", { Size = UDim2.fromOffset(170, 20), Position = UDim2.fromOffset(3, 99), TextXAlignment = Enum.TextXAlignment.Left })
	local invite = UI.button(stats, "+", C.green, function()
		pcall(function()
			game:GetService("SocialService"):PromptGameInvite(player)
		end)
	end, { Size = UDim2.fromOffset(28, 28), Position = UDim2.fromOffset(178, 95) })
	invite.Name = "Invite"
	local il = invite:FindFirstChild("Label") :: TextLabel
	il.Size = UDim2.new(1, -4, 1, -4)

	-- bottom-center: gain line, goal bar, next ride
	local bottom = UI.frame(gui, { Name = "Bottom", Size = UDim2.fromOffset(380, 120), Position = UDim2.new(0.5, 0, 1, -8), AnchorPoint = Vector2.new(0.5, 1), BackgroundTransparency = 1 })
	gainLabel = UI.outlined(bottom, "+1 SPEED/S", { Size = UDim2.fromOffset(186, 20), Position = UDim2.fromOffset(2, 0), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = C.gold })
	tankLabel = UI.outlined(bottom, "", { Size = UDim2.fromOffset(186, 20), Position = UDim2.new(1, -2, 0, 0), AnchorPoint = Vector2.new(1, 0), TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = C.money })
	local _, gf, gl = UI.bar(bottom, C.blue, { Size = UDim2.new(1, 0, 0, 32), Position = UDim2.fromOffset(0, 24) })
	goalFill, goalText = gf, gl
	goalText.TextXAlignment = Enum.TextXAlignment.Left
	rideBtn = UI.button(bottom, "", C.gold, function()
		local d = State.data
		local nxt = d and HUD.nextRide(d)
		if nxt and d.coins >= nxt.price and HUD.atRideShop and HUD.atRideShop() then
			State.action("buyRide", nxt.id)
		else
			HUD.goToRideShop()
		end
	end, { Size = UDim2.new(1, 0, 0, 56), Position = UDim2.fromOffset(0, 64) })
	local rlab = rideBtn:FindFirstChild("Label") :: TextLabel
	rlab.Size = UDim2.new(1, -16, 0, 25)
	rlab.Position = UDim2.new(0.5, 0, 0, 4)
	rlab.AnchorPoint = Vector2.new(0.5, 0)
	ridePrice = UI.outlined(rideBtn, "", { Size = UDim2.new(1, -16, 0, 18), Position = UDim2.new(0.5, 0, 0, 29), AnchorPoint = Vector2.new(0.5, 0), ZIndex = rideBtn.ZIndex + 1 })
	local rb = UI.frame(rideBtn, { Size = UDim2.new(1, -20, 0, 4), Position = UDim2.new(0, 10, 1, -8), BackgroundColor3 = Color3.fromRGB(0, 0, 0), BackgroundTransparency = 0.5, ZIndex = rideBtn.ZIndex + 1 })
	UI.corner(rb, 2)
	rideFill = UI.frame(rb, { Size = UDim2.fromScale(0, 1), BackgroundColor3 = C.white, ZIndex = rb.ZIndex + 1 })
	UI.corner(rideFill, 2)

	carryChip = UI.outlined(gui, "", { Size = UDim2.fromOffset(520, 24), Position = UDim2.new(0.5, 0, 1, -136), AnchorPoint = Vector2.new(0.5, 1), Visible = false })

	-- bottom-right: next shark attack ("in 1m 40s" over a soft fade)
	timerPill = UI.frame(gui, { Name = "Timer", Size = UDim2.fromOffset(250, 58), Position = UDim2.new(1, 0, 1, 0), AnchorPoint = Vector2.new(1, 1),
		BackgroundColor3 = Color3.fromRGB(0, 0, 0), BackgroundTransparency = 0.45 })
	local fade = Instance.new("UIGradient")
	fade.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.35, 0.35), NumberSequenceKeypoint.new(1, 0.25) })
	fade.Parent = timerPill
	UI.icon(timerPill, "Shark", { Size = UDim2.fromOffset(46, 46), Position = UDim2.new(0, 46, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5) })
	timerLabel = UI.outlined(timerPill, "", { Size = UDim2.new(1, -108, 0, 34), Position = UDim2.new(0, 98, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5), TextXAlignment = Enum.TextXAlignment.Left, Font = UI.NUMFONT })

	-- shark alert vignette
	vignette = UI.frame(Fx.screen(), { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Name = "Vignette", ZIndex = 2 })
	for _, spec in { { UDim2.new(1, 0, 0.22, 0), UDim2.fromScale(0, 0), 90 }, { UDim2.new(1, 0, 0.22, 0), UDim2.fromScale(0, 0.78), -90 },
		{ UDim2.new(0.16, 0, 1, 0), UDim2.fromScale(0, 0), 0 }, { UDim2.new(0.16, 0, 1, 0), UDim2.fromScale(0.84, 0), 180 } } do
		local f = UI.frame(vignette, { Size = spec[1], Position = spec[2], BackgroundColor3 = Color3.fromRGB(255, 30, 50), BackgroundTransparency = 0 })
		local g = Instance.new("UIGradient")
		g.Rotation = spec[3]
		g.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(1, 1) })
		g.Parent = f
	end
	vignette.Visible = false

	-- touch screens: the thumbstick and jump button own the bottom corners,
	-- so the numbers go top-left and the timer top-right
	if UI.TOUCH then
		stats.AnchorPoint = Vector2.new(0, 0)
		stats.Position = UDim2.fromOffset(12, 4)
		timerPill.AnchorPoint = Vector2.new(1, 0)
		timerPill.Position = UDim2.new(1, 0, 0, 4)
		menu.Position = UDim2.new(0, 10, 0.5, 20)
		right.Position = UDim2.new(1, -10, 0.46, 0)
		right.Size = UDim2.fromOffset(70, 330)
		bottom.Position = UDim2.new(0.5, 0, 1, -6)
		carryChip.Position = UDim2.new(0.5, 0, 1, -132)
	end
end

----------------------------------------------------------------- helpers
function HUD.nextRide(d: any): Config.Ride?
	for _, ride in Config.Rides do
		if not ride.robux and not d.rides[ride.id] then
			return ride
		end
	end
	return nil
end

-- kept for other modules: plain toast / tutorial hint
function HUD.toast(text: string, color: Color3?, _duration: number?)
	Notify.toast(text, color)
end

function HUD.hint(text: string?)
	if text then
		Notify.banner(text, { key = "tut", sticky = true, priority = 3 })
	else
		Notify.clear("tut")
	end
end

function HUD.pulseRide(on: boolean)
	if on and not stopRidePulse then
		stopRidePulse = UI.pulse(rideBtn)
	elseif not on and stopRidePulse then
		stopRidePulse()
		stopRidePulse = nil
	end
end

function HUD.rideButton(): GuiObject
	return rideBtn
end

function HUD.menuButton(name: string): GuiObject?
	return menuButtons[name]
end

local function unclaimed(d: any): number
	local n = 0
	for key in d.index do
		if not d.claimed[key] then
			n += 1
		end
	end
	return n
end

-- the best pass you don't own yet, as a red square (only once the shop is open)
local function updateOffer(d: any)
	local want: string? = nil
	if d.playtime >= Config.SHOP_UNLOCK_SECONDS then
		for _, key in { "TwoXSpeed", "TwoXCoins", "AutoCollect" } do
			local pass = Config.Passes[key]
			if pass.id ~= 0 and not d.passes[key] then
				want = key
				break
			end
		end
	end
	local b = menuButtons.Offer
	b.Visible = want ~= nil
	if want and b:GetAttribute("Key") ~= want then
		b:SetAttribute("Key", want)
		local pass = Config.Passes[want]
		local old = b:FindFirstChild("Icon")
		if old then
			old:Destroy()
		end
		UI.icon(b, pass.iconName or "X2Speed", { Size = UDim2.fromScale(0.74, 0.74), Position = UDim2.fromScale(0.5, 0.47), AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = b.ZIndex + 1 })
		UI.badge(b, "R$")
	end
end

local function offerClicked()
	local key = menuButtons.Offer:GetAttribute("Key")
	local pass = key and Config.Passes[key]
	if pass and pass.id ~= 0 then
		MarketplaceService:PromptGamePassPurchase(player, pass.id)
	end
end

----------------------------------------------------------------- render state
local lastSlow = false
local shopShown = false
local function render(d: any)
	speedLabel.Text = UI.short(d.speed)
	coinsLabel.Text = "$" .. UI.short(d.coins)
	local mult = Config.Rebirth.mult ^ d.rebirths
	gainLabel.Text = mult > 1 and ("+%s SPEED/S (x%s)"):format(UI.short(d.gain), string.format("%g", math.floor(mult * 100 + 0.5) / 100))
		or ("+%s SPEED/S"):format(UI.short(d.gain))
	tankLabel.Text = ("%d/%d Active  +$%s/s"):format(d.active, d.slots, UI.short(d.income))
	friendLabel.Text = ("Friend Boost +%d%%"):format(math.floor(d.friendBoost * 100 + 0.5))
	if setSlow and d.slow ~= lastSlow then
		lastSlow = d.slow
		setSlow(d.slow)
	end
	-- "!" on the Tank when a stored creature would earn more than an active one
	local minActive, bestStored = math.huge, 0
	for _, c in d.creatures do
		if c.e then
			minActive = math.min(minActive, c.v)
		else
			bestStored = math.max(bestStored, c.v)
		end
	end
	if bestStored > 0 and (d.active < d.slots or bestStored > minActive) then
		UI.badge(menuButtons.Tank)
	else
		UI.clearBadge(menuButtons.Tank)
	end
	-- daily reward waiting
	if (d.dailyWait or 1) <= 0 then
		UI.badge(menuButtons.Daily)
	else
		UI.clearBadge(menuButtons.Daily)
	end
	-- boosts: square + time left
	local function boost(key: string, on: boolean, timerText: string?, badge: string?)
		local sq = boostSquares[key]
		sq.holder.Visible = on
		sq.timer.Text = timerText or ""
		sq.holder.Size = UDim2.fromOffset(66, timerText and 84 or 62) -- no empty gap when there's no timer
		if badge then
			UI.badge(sq.button, badge)
		end
	end
	boost("Shield", d.shields > 0, nil, tostring(d.shields))
	boost("Boost", d.boostLeft > 0, UI.timeWords(d.boostLeft))
	boost("Luck", d.luckLeft > 0, UI.timeWords(d.luckLeft))

	-- goal: next zone gate, or rebirth
	local gate = Config.nextGate(d.speed)
	if gate then
		local prevGate = 0
		for _, z in Config.Zones do
			if z.gate <= d.speed then
				prevGate = z.gate
			end
		end
		goalText.Text = ("%s   %s / %s"):format(gate.name, UI.short(d.speed), UI.short(gate.gate))
		goalFill.Size = UDim2.fromScale(math.clamp((d.speed - prevGate) / (gate.gate - prevGate), 0.02, 1), 1)
		goalFill.BackgroundColor3 = C.blue
	else
		local ready = d.speed >= Config.Rebirth.speed
		goalText.Text = ready and "REBIRTH READY!" or ("Rebirth at %s speed"):format(UI.short(Config.Rebirth.speed))
		goalFill.Size = UDim2.fromScale(math.clamp(d.speed / Config.Rebirth.speed, 0.02, 1), 1)
		goalFill.BackgroundColor3 = C.green
	end
	menuButtons.Rebirth.Visible = d.speed >= Config.Rebirth.speed
	local shopOpen = d.playtime >= Config.SHOP_UNLOCK_SECONDS or d.rides.Duck == true
	if shopOpen and not menuButtons.Shop.Visible then
		menuButtons.Shop.Visible = true
		if not shopShown then
			shopShown = true
			UI.badge(menuButtons.Shop)
		end
	end
	local n = unclaimed(d)
	if n > 0 then
		UI.badge(menuButtons.Index, tostring(n))
	else
		UI.clearBadge(menuButtons.Index)
	end

	-- next ride
	local nxt = HUD.nextRide(d)
	rideBtn.Visible = nxt ~= nil
	if nxt then
		local afford = d.coins >= nxt.price
		local here = HUD.atRideShop and HUD.atRideShop()
		UI.setText(rideBtn, afford and (here and ("BUY %s!"):format(nxt.name:upper()) or ("GET %s!"):format(nxt.name:upper())) or nxt.name)
		ridePrice.Text = ("+%d speed/s  ·  $%s"):format(nxt.gain or 0, UI.short(nxt.price))
		rideFill.Size = UDim2.fromScale(math.clamp(d.coins / nxt.price, 0, 1), 1)
		rideBtn.BackgroundColor3 = afford and C.green or C.gold
		HUD.pulseRide(afford)
		if afford then
			UI.badge(menuButtons.Rides)
		else
			UI.clearBadge(menuButtons.Rides)
		end
	end

	-- carrying
	if d.carrying then
		local r = Config.rarity(d.carrying.r)
		carryChip.Visible = true
		carryChip.TextColor3 = r.color
		carryChip.Text = ("%s → bring it home to your tank!"):format(Config.fullName(d.carrying.z, d.carrying.r, d.carrying.m, d.carrying.s))
	else
		carryChip.Visible = false
	end
	updateOffer(d)
end

----------------------------------------------------------------- per-frame: status line, zone titles, shark state, timer
local phase = "calm"
local phaseEnds = os.clock() + Config.Shark.firstAttack
local lastZone: string? = nil
local quietTitlesUntil = 0 -- no "Shark Beach" title right after you wash up
local menuOpen = false

-- one emoji either side of each zone's title (all widely supported)
local ZONE_EMOJI = { Lagoon = "", Reef = "", Kelp = "", Shipwreck = "", Deep = "", Abyss = "" }

local function myPos(): Vector3?
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	return hrp and hrp.Position
end

local function atMyDock(pos: Vector3?): boolean
	local d = State.data
	if not (d and pos and d.plot > 0) then
		return false
	end
	local tank = Layout.tankPos(Layout.Plots[d.plot])
	return Vector2.new(pos.X - tank.X, pos.Z - tank.Z).Magnitude < 26 and not Layout.inWater(pos)
end

local function statusLine(pos: Vector3?)
	local d = State.data
	if not (d and pos) then
		Notify.status(nil)
		return
	end
	if menuOpen or atMyDock(pos) then
		-- what the tank earns while you're away (shown when you open the menu to leave)
		Notify.status(d.income > 0 and ("Your tank earns $%s / day while you're offline"):format(UI.short(Config.offlinePerDay(d.income)))
			or "Put creatures in your tank to earn while you're offline", Color3.fromRGB(190, 225, 255))
	elseif Layout.inWater(pos) then
		local zone = Config.zoneAt(pos.Z)
		Notify.status(("%s · %d m"):format(zone and zone.name or "Lagoon", math.floor((pos.Z - Config.SHORE_Z) / 3.5)), C.white)
	else
		Notify.status(nil)
	end
end

local function sharkLine(pos: Vector3)
	local safe = Layout.isSafe(pos)
	local left = math.max(0, math.ceil(phaseEnds - os.clock()))
	local text, sub, color
	if phase == "warning" then
		if safe then
			text, sub, color = ("Shark attack in %d"):format(left), "You're safe here", C.green
		else
			text, sub, color = ("SHARK ATTACK IN %d!"):format(left), "Get to sand or an island", C.red
		end
	else
		local mine = SharkView.myHunter()
		if mine and mine.state == "chase" then
			text, sub, color = "IT'S CHARGING!", "Swerve at the last second, or reach sand!", C.red
		elseif mine and mine.state == "overshoot" then
			text, sub, color = "IT MISSED! IT'S TURNING BACK", "Now's your chance: get to sand or an island", C.gold
		elseif mine and mine.state == "stalk" then
			text, sub, color = "A SHARK IS CIRCLING YOU!", "Follow the arrow to safety", C.red
		elseif safe then
			text, sub, color = ("Safe here · sharks leave in %d"):format(left), nil, C.green
		else
			text, sub, color = "SHARKS ARE HUNTING!", "Catches are luckier right now... if you dare", C.gold
		end
	end
	Notify.banner(text, { key = "shark", sticky = true, priority = 5, sub = sub, color = color })
	vignette.Visible = not safe and not player:GetAttribute("Cinematic")
end

local function frame()
	local pos = myPos()
	statusLine(pos)
	if pos then
		local zone = Config.zoneAt(pos.Z)
		local id = zone and zone.id or "Beach"
		if id ~= lastZone then
			if lastZone ~= nil and os.clock() > quietTitlesUntil then
				if zone then
					local e = ZONE_EMOJI[zone.id] or ""
					Notify.banner(("%s %s %s"):format(e, zone.name, e), { key = "zone", priority = 2, time = 2.4, big = true,
						color = zone.water:Lerp(Color3.new(1, 1, 1), 0.35), sub = ("%s waters"):format((zone.shark:gsub("(%l)(%u)", "%1 %2"))) })
				else
					Notify.banner("Shark Beach ", { key = "zone", priority = 2, time = 2, big = true, color = Color3.fromRGB(255, 220, 120), sub = "Sand is always safe" })
				end
			end
			lastZone = id
		end
		if phase ~= "calm" then
			sharkLine(pos)
		end
	end
	local left = math.max(0, phaseEnds - os.clock())
	if phase == "calm" then
		timerLabel.Text = "in " .. UI.timeWords(left)
		timerLabel.TextColor3 = left < 10 and C.gold or C.white
		timerPill.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	else
		timerLabel.Text = (phase == "warning" and "COMING " or "HUNTING ") .. math.ceil(left)
		timerLabel.TextColor3 = C.white
		timerPill.BackgroundColor3 = C.red
	end
end

----------------------------------------------------------------- notifications
local handlers: { [string]: (any) -> () } = {}

local newDiscovery = false -- "discover" arrives just before "grab"; one toast says both

handlers.grab = function(d)
	local r = Config.rarity(d.r)
	local name = Config.fullName(d.z, d.r, d.m, d.s)
	local pos = myPos()
	if pos then
		Fx.sparkle(pos + Vector3.new(0, 3, 0), r.color, 20 + r.index * 12)
		Fx.popup3D(pos + Vector3.new(0, 5, 0), ("+$%s/s"):format(UI.short(d.v)), r.color)
	end
	Fx.sound("grab", 0.6, 1 + r.index * 0.05)
	-- the bigger the catch, the bigger the moment
	if r.index >= 5 then
		Notify.takeover("LEGENDARY!", name, r.color, 1.8)
		Fx.shake(1.5)
		Fx.sound("legendary", 0.8)
	elseif d.lucky then
		Notify.word("LUCKY " .. d.r:upper() .. "!", C.green, 1)
		Fx.sound("lucky", 0.7)
	elseif d.pity or r.index >= 3 then
		Notify.word(d.r:upper() .. "!", r.color, 1)
		Fx.sound("grabRare", 0.6, 1 + r.index * 0.04)
	end
	local note = newDiscovery and "  · NEW!" or ""
	newDiscovery = false
	Notify.toast(("%s  +$%s/s%s"):format(name, UI.short(d.v), note), r.color)
end

handlers.discover = function()
	newDiscovery = true
	Fx.sound("discover", 0.55)
	UI.pop(menuButtons.Index, 1.3)
end

handlers.indexClaim = function(d)
	Notify.word("CLAIMED!", C.orange, 0.9)
	Notify.toast(("+$%s  +%s speed"):format(UI.short(d.coins), UI.short(d.speed)), C.green)
	UI.pop(coinsLabel, 1.3)
	UI.pop(speedLabel, 1.3)
	Fx.sound("coin", 0.7)
end

handlers.deposit = function(d)
	local r = Config.rarity(d.r)
	local data = State.data
	if not (data and data.plot > 0) then
		return
	end
	-- everything is shown right at the tank, where it happens
	local tank = Layout.tankPos(Layout.Plots[data.plot])
	Fx.sparkle(tank + Vector3.new(0, 6, 0), r.color, 40)
	Fx.sound("deposit", 0.7, 1, tank)
	if d.active then
		Fx.popup3D(tank + Vector3.new(0, 11, 0), ("+$%s/s"):format(UI.short(d.v)), C.money, true)
	else
		Fx.popup3D(tank + Vector3.new(0, 11, 0), "Not equipped", Color3.fromRGB(170, 170, 180), true)
	end
end

handlers.code = function(d)
	if d.ok then
		local bits = {}
		if d.coins then
			table.insert(bits, "+$" .. UI.short(d.coins))
		end
		if d.speed then
			table.insert(bits, ("+%s speed"):format(UI.short(d.speed)))
		end
		if d.shields then
			table.insert(bits, ("+%d shield"):format(d.shields))
		end
		Notify.word("CODE REDEEMED!", C.green, 1)
		Notify.toast(table.concat(bits, "  "), C.green)
		Fx.sound("coin", 0.7)
	else
		Notify.toast("" .. tostring(d.text), C.red)
		Fx.sound("uiError", 0.6)
	end
end

handlers.tankFull = function(d)
	Notify.banner(("Tank full! %d dead fish"):format(d.max or 10), { key = "tankFull", priority = 2, time = 4, color = C.red,
		sub = "Sell some at the SELL hut, or equip them" })
	Fx.sound("uiError", 0.6)
	local pad = Travel.padPos("Sell")
	if pad then
		Guide.set("shop", pad + Vector3.new(0, 1, 0), "Sell") -- an arrow, no teleport
	end
end

handlers.sold = function(d)
	Notify.word(("SOLD %d!"):format(d.count), C.green, 0.9)
	Notify.toast("+$" .. UI.short(d.coins), C.money)
	Fx.sound("buy", 0.7)
	UI.pop(coinsLabel, 1.3)
end

handlers.collect = function(d)
	local pos = myPos()
	if pos then
		Fx.confetti(pos, { C.money, C.gold })
		Fx.popup3D(pos + Vector3.new(0, 5, 0), "+$" .. UI.short(d.amount), C.money, true)
	end
	Fx.sound("collect", 0.7)
	UI.pop(coinsLabel, 1.35)
end

handlers.ride = function(d)
	local ride = Config.ride(d.id)
	local pos = myPos()
	if pos then
		Fx.confetti(pos)
		Fx.splash(Vector3.new(pos.X, 0.5, pos.Z), 1.2)
	end
	Fx.sound("buy", 0.8)
	Fx.sound("rideNew", 0.8)
	Notify.takeover("NEW RIDE!", ("%s · +%s speed every second"):format(ride and ride.name or "", UI.short(d.gain)), C.gold, 1.6)
	UI.pop(gainLabel, 1.5)
end

handlers.rideShop = function()
	HUD.goToRideShop()
end

handlers.slot = function(d)
	Notify.toast(("Your tank now holds %d!"):format(d.slots), C.green)
end

handlers.unlock = function(d)
	local zone = Config.zoneById(d.zone)
	if zone then
		Notify.takeover(zone.name:upper() .. "!", "New zone unlocked · rarer creatures, bigger sharks", C.gold, 1.8)
		Fx.sound("zoneUnlock", 0.8)
		local pos = myPos()
		if pos then
			Fx.confetti(pos)
		end
	end
end

handlers.gate = function(d)
	Notify.word(("NEED %s SPEED"):format(UI.short(d.need)), C.red, 1)
	Fx.sound("uiError", 0.6)
	Fx.shake(1)
end

handlers.lost = function()
	-- the bite cutscene shows this (your creature gets eaten on screen)
end

handlers.spat = function()
	quietTitlesUntil = os.clock() + 3
	local pos = myPos()
	if pos then
		Fx.splash(Vector3.new(pos.X, 0.5, pos.Z + 4), 1.6)
	end
	-- the shark spits you back toward the beach
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if hrp then
		hrp.AssemblyLinearVelocity = Vector3.new(0, 60, -55)
	end
	Notify.word("PTOOEY!", C.sky, 1)
	Fx.sound("spat", 0.8)
	local d = State.data
	if d and d.playtime >= Config.SHOP_UNLOCK_SECONDS and Config.Products.Shield.id ~= 0 then
		local b = UI.button(gui, "Shield next time  R$" .. Config.Products.Shield.price, C.sky, function()
			MarketplaceService:PromptProductPurchase(player, Config.Products.Shield.id)
		end, { Size = UDim2.fromOffset(260, 44), Position = UDim2.new(0.5, 0, 1, -168), AnchorPoint = Vector2.new(0.5, 1) })
		task.delay(6, function()
			b:Destroy()
		end)
	end
end

handlers.shield = function()
	Notify.toast("Your shield blocked the bite!", C.sky)
end

handlers.rebirth = function(d)
	Fx.flash(Color3.new(1, 1, 1), 0.8, 0)
	Fx.sound("rebirth", 0.8)
	Notify.takeover("REBIRTH!", ("Permanent x%s speed gain"):format(tostring(Config.Rebirth.mult ^ d.rebirths)), C.green, 2)
end

handlers.purchase = function(d)
	Notify.takeover("THANK YOU!", d.name .. " is yours!", C.pink, 1.6)
	local pos = myPos()
	if pos then
		Fx.confetti(pos)
	end
end

handlers.announce = function(d)
	Notify.toast(d.text, d.color or C.gold)
end

----------------------------------------------------------------- shark phases
local function myZone(): Config.Zone?
	local pos = myPos()
	return pos and Config.zoneAt(pos.Z)
end

local function onPhase(kind: string, data: any)
	if kind == "warning" then
		phase, phaseEnds = "warning", os.clock() + (data.duration or 5)
		local pos = myPos()
		local exposed = pos ~= nil and not Layout.isSafe(pos)
		Notify.takeover("SHARK INCOMING!", exposed and "Get to sand or an island!" or "Stay on the sand and you're safe", C.red, 1.4)
		Water.setSafeGlow(true)
		Fx.sound("sharkAlarm", 0.8)
		-- the horizon breach: a shark leaps where you can see it
		local zone = myZone()
		if zone and pos then
			local cam = Workspace.CurrentCamera
			local look = cam.CFrame.LookVector * Vector3.new(1, 0, 1)
			local dir = look.Magnitude > 0.1 and look.Unit or Vector3.new(0, 0, 1)
			local at = pos + dir * math.max(70, zone.sharkLength * 4)
			local side = Vector3.new(dir.Z, 0, -dir.X)
			SharkView.breach(zone.shark, zone.sharkLength, at - side * zone.sharkLength * 0.8, math.atan2(-side.X, -side.Z))
		end
		task.spawn(function()
			while phase == "warning" do
				for _, f in vignette:GetChildren() do
					if f:IsA("Frame") then
						f.BackgroundTransparency = 0.3 + 0.4 * (0.5 + 0.5 * math.sin(os.clock() * 10))
					end
				end
				task.wait()
			end
		end)
	elseif kind == "hunt" then
		phase, phaseEnds = "hunt", os.clock() + (data.duration or Config.Shark.hunt)
		Water.setSafeGlow(true)
	elseif kind == "clear" then
		local was = phase ~= "calm"
		phase, phaseEnds = "calm", os.clock() + (data.next or Config.Shark.cycle)
		vignette.Visible = false
		Water.setSafeGlow(false)
		Notify.clear("shark")
		if was then
			Notify.toast("The sharks are gone. Back to the water!", C.green)
		end
	end
end

----------------------------------------------------------------- start
function HUD.start()
	Notify.start()
	build()
	menuButtons.Offer.Activated:Connect(offerClicked)
	State.Changed:Connect(render)
	if State.data then
		render(State.data)
	end
	RunService.Heartbeat:Connect(frame)
	-- opening the Roblox menu (usually to leave): show what the tank earns offline
	local GuiService = game:GetService("GuiService")
	GuiService.MenuOpened:Connect(function()
		menuOpen = true
	end)
	GuiService.MenuClosed:Connect(function()
		menuOpen = false
	end)
	-- big moments, cutscenes and the tank view get the screen to themselves
	local function refreshVisible()
		local cine = player:GetAttribute("Cinematic") == true
		local viewing = player:GetAttribute("ViewingTank") == true
		gui.Enabled = not cine and not viewing and not HUD.takeover
		if cine then
			vignette.Visible = false
		end
	end
	Notify.onTakeover = function(on)
		HUD.takeover = on
		refreshVisible()
	end
	player:GetAttributeChangedSignal("Cinematic"):Connect(refreshVisible)
	player:GetAttributeChangedSignal("ViewingTank"):Connect(refreshVisible)
	Remotes.get("Notify").OnClientEvent:Connect(function(kind, data)
		local fn = handlers[kind]
		if fn then
			fn(data)
		end
	end)
	Remotes.get("SharkEvent").OnClientEvent:Connect(function(kind, data)
		if kind == "warning" or kind == "hunt" or kind == "clear" then
			onPhase(kind, data or {})
		end
	end)
end

return HUD

end
MODULES['cmod:Rewards'] = function()
local script = { Parent = CLIENT }
-- Daily Rewards window + the group chest (client side; the server decides).
--   Daily:  a 7-day calendar (days 1-6 in a grid, Day 7 the big Limited one).
--           Opens by itself once per session when a reward is ready (after
--           the tutorial), or from the gift square on the HUD.
--   Chest:  "Join Group & Like to Claim!". Pressing E asks the server; if
--           you're not in the group yet it shows Roblox's join prompt and
--           the favorite (like) prompt, then you press E again.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = game.ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local UI = require(script.Parent.UI)
local Fx = require(script.Parent.Fx)
local State = require(script.Parent.State)
local Notify = require(script.Parent.Notify)

local Rewards = {}
local player = Players.LocalPlayer
local C = UI.C

local gui: ScreenGui
local window: Frame? = nil
local dailyReadyAt = math.huge
local groupReadyAt = 0
local autoOpened = false
local askedLike = false

----------------------------------------------------------------- daily window
local function close()
	if window then
		window:Destroy()
		window = nil
	end
end

local function tile(parent: Instance, day: number, state: string, size: UDim2, pos: UDim2)
	local r = Config.Daily[day]
	local limited = r.limited == true
	local f = UI.frame(parent, { Size = size, Position = pos, BackgroundColor3 = limited and C.purple or C.gold })
	UI.corner(f, 10)
	UI.stroke(f, C.ink, 3)
	UI.shade(f)
	UI.studs(f, { size = 18, alpha = 0.86 })
	if limited then
		UI.rainbow(f)
	end
	-- "DAY n" tab across the top
	local tab = UI.frame(f, { Size = UDim2.new(1, -16, 0, 34), Position = UDim2.new(0.5, 0, 0, -8), AnchorPoint = Vector2.new(0.5, 0),
		BackgroundColor3 = state == "today" and C.green or C.orange, ZIndex = f.ZIndex + 2 })
	UI.corner(tab, 8)
	UI.stroke(tab, C.ink, 3)
	UI.outlined(tab, ("DAY %d"):format(day), { Size = UDim2.new(1, -8, 1, -6), Position = UDim2.fromOffset(4, 3), Font = UI.NUMFONT, ZIndex = tab.ZIndex + 1 })
	if limited then
		UI.outlined(f, "Limited!", { Size = UDim2.new(1, -16, 0, 30), Position = UDim2.fromOffset(8, 34), TextColor3 = C.gold, ZIndex = f.ZIndex + 2 })
	end
	UI.icon(f, r.icon or "Gift", { Size = UDim2.new(1, -24, limited and 0.45 or 0.42, 0), Position = UDim2.fromScale(0.5, limited and 0.52 or 0.56),
		AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = f.ZIndex + 2 })
	UI.outlined(f, r.label, { Size = UDim2.new(1, -12, 0, limited and 40 or 24), Position = UDim2.new(0.5, 0, 1, -8), AnchorPoint = Vector2.new(0.5, 1),
		ZIndex = f.ZIndex + 2 })
	if state == "claimed" then
		local dim = UI.frame(f, { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.45, ZIndex = f.ZIndex + 3 })
		UI.corner(dim, 10)
		UI.outlined(dim, "✓", { Size = UDim2.fromScale(0.7, 0.7), Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5),
			TextColor3 = C.green, ZIndex = dim.ZIndex + 1 })
	elseif state == "today" then
		UI.pulse(f)
	end
end

function Rewards.openDaily()
	close()
	local d = State.data
	if not d then
		return
	end
	local f, body = UI.window(gui, "Daily Rewards", C.orange, Vector2.new(640, 500), close, "Gift")
	window = f
	local nextDay = d.dailyDay or 1
	local ready = os.clock() >= dailyReadyAt
	local function state(day: number): string
		if day < nextDay then
			return "claimed"
		elseif day == nextDay then
			return ready and "today" or "next"
		end
		return "later"
	end
	-- days 1-6: 3 x 2 grid; day 7: tall on the right
	local grid = UI.frame(body, { Size = UDim2.new(1, 0, 1, -76), BackgroundTransparency = 1 })
	local cw, ch, gap = 134, 152, 12
	for day = 1, 6 do
		local col, row = (day - 1) % 3, (day - 1) // 3
		tile(grid, day, state(day), UDim2.fromOffset(cw, ch), UDim2.fromOffset(col * (cw + gap) + 4, row * (ch + gap) + 10))
	end
	tile(grid, 7, state(7), UDim2.fromOffset(cw + 24, ch * 2 + gap), UDim2.fromOffset(3 * (cw + gap) + 4, 10))
	-- claim button / time to the next one
	if ready then
		UI.button(body, "CLAIM YOUR REWARD", C.green, function()
			State.action("claimDaily")
		end, { Size = UDim2.fromOffset(330, 58), Position = UDim2.new(0.5, 0, 1, -4), AnchorPoint = Vector2.new(0.5, 1) })
	else
		local left = math.max(0, dailyReadyAt - os.clock())
		local t = UI.outlined(body, "Next reward in " .. UI.timeWords(left), { Size = UDim2.fromOffset(420, 36), Position = UDim2.new(0.5, 0, 1, -14),
			AnchorPoint = Vector2.new(0.5, 1), TextColor3 = C.gold })
		task.spawn(function()
			while t.Parent do
				t.Text = "Next reward in " .. UI.timeWords(math.max(0, dailyReadyAt - os.clock()))
				task.wait(1)
			end
		end)
	end
end

function Rewards.dailyReady(): boolean
	return os.clock() >= dailyReadyAt
end

----------------------------------------------------------------- group chest
-- while Roblox's favorite prompt is open it covers the middle of the screen,
-- so the chest reward waits until it's closed
local likeOpenUntil = 0
local function promptLike()
	-- the favorite button for this game ("like"); Roblox shows its own prompt
	local ok = pcall(function()
		local aes = game:GetService("AvatarEditorService")
		aes.PromptSetFavoriteCompleted:Once(function()
			likeOpenUntil = 0
		end)
		aes:PromptSetFavorite(game.PlaceId, Enum.AvatarItemType.Asset, true)
	end)
	if ok then
		likeOpenUntil = os.clock() + 20
	end
end

local function promptGroup()
	if Config.GroupId == 0 then
		return
	end
	task.spawn(function()
		pcall(function()
			(game:GetService("GroupService") :: any):PromptJoinAsync(Config.GroupId)
		end)
	end)
end

local function chestSign()
	local map = Workspace:FindFirstChild("Map")
	local chest = map and map:FindFirstChild("GroupChest")
	local anchor = chest and chest:FindFirstChild("Sign")
	if not anchor then
		return
	end
	local left = groupReadyAt - os.clock()
	for _, bb in anchor:GetChildren() do
		local title = bb:FindFirstChild("Title") :: TextLabel?
		local sub = bb:FindFirstChild("Sub") :: TextLabel?
		if title then
			title.Text = left > 0 and "CLAIMED" or "CLAIM"
		end
		if sub then
			sub.Text = left > 0 and ("Next chest in " .. UI.timeWords(left))
				or (Config.GroupId ~= 0 and "Join Group & Like To Claim!" or "Like The Game To Claim!")
		end
	end
end

----------------------------------------------------------------- start
function Rewards.start()
	gui = Instance.new("ScreenGui")
	gui.Name = "Rewards"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 9
	gui.Parent = player:WaitForChild("PlayerGui")
	UI.autoScale(gui, Vector2.new(660, 520))

	local function onState(d: any)
		local wasReady = os.clock() >= dailyReadyAt
		dailyReadyAt = os.clock() + (d.dailyWait or 0)
		groupReadyAt = os.clock() + (d.groupWait or 0)
		if window and wasReady ~= (os.clock() >= dailyReadyAt) then
			Rewards.openDaily() -- just claimed: redraw with the day ticked off
		end
		-- a reward waiting: open the calendar once per session (after the tutorial)
		if not autoOpened and d.tut >= 5 and (d.dailyWait or 1) <= 0 and not player:GetAttribute("Cinematic") then
			autoOpened = true
			task.delay(2, Rewards.openDaily)
		end
	end
	State.Changed:Connect(onState)
	if State.data then
		onState(State.data)
	end

	require(script.Parent.Prompts).Triggered:Connect(function(prompt)
		if prompt.Name ~= "GroupChest" then
			return
		end
		if not askedLike then
			askedLike = true
			promptLike()
		end
		State.action("claimGroup")
	end)

	Remotes.get("Notify").OnClientEvent:Connect(function(kind, data)
		if kind == "daily" then
			if data.ok then
				Notify.takeover(("DAY %d!"):format(data.day), data.text, C.gold, 1.6)
				Fx.sound("buy", 0.8)
				Fx.confetti((player.Character and player.Character:GetPivot().Position) or Vector3.zero)
			else
				Notify.toast("Next daily reward in " .. UI.timeWords(data.wait or 0), C.gold)
			end
		elseif kind == "groupChest" then
			if data.ok then
				while os.clock() < likeOpenUntil do
					task.wait(0.2)
				end
				task.wait(0.3)
				Notify.takeover("CHEST CLAIMED!", ("+$%s · 2x speed for %d min"):format(UI.short(data.coins), data.minutes), C.gold, 1.6)
				Fx.sound("buy", 0.8)
				Fx.confetti((player.Character and player.Character:GetPivot().Position) or Vector3.zero)
			elseif data.reason == "group" then
				Notify.banner("Join the group to open the chest!", { key = "chest", priority = 2, time = 3.5, color = C.gold,
					sub = "Then press E on the chest again" })
				promptGroup()
			elseif data.reason == "wait" then
				Notify.toast("The chest refills in " .. UI.timeWords(data.wait or 0), C.gold)
			end
		end
	end)

	RunService.Heartbeat:Connect(function()
		chestSign()
	end)
end

return Rewards

end

local sig = function() return { Connect = function() end } end
MODULES["mod:Remotes"] = function() return { get = function() return { OnClientEvent = sig(), FireServer = function() end } end } end
SAMPLE = {
	speed = 866, coins = 12500, gain = 5, rebirths = 0, income = 255, active = 4, slots = 4, friendBoost = 0, slow = false,
	creatures = { { e = true, v = 60 }, { e = true, v = 70 }, { e = false, v = 90 } }, shields = 1, boostLeft = 0, luckLeft = 600,
	index = { a = true }, claimed = {}, rides = { Noodle = true, Duck = true, Tube = true, Boogie = true, Surf = true },
	playtime = 900, passes = {}, plot = 1, pending = 0, carrying = { r = "Rare", z = "Reef", s = 2.2 },
	dailyDay = 3, dailyWait = 0, groupWait = 0, tut = 5,
}
MODULES["cmod:State"] = function() return { data = SAMPLE, Changed = sig(), action = function() end, wait = function() return SAMPLE end } end
MODULES["cmod:Water"] = function() return { setSafeGlow = function() end } end
MODULES["cmod:SharkView"] = function() return { myHunter = function() return nil end, breach = function() end } end
MODULES["cmod:Travel"] = function() return { go = function() end } end
local HUD = require("cmod:HUD")
local Notify = require("cmod:Notify")
HUD.start()

Notify.status("Coral Reef · 340 m")
Notify.banner("🦈 SHARK ATTACK IN 4!", { key = "shark", sticky = true, priority = 5, sub = "Get to sand or an island", color = Color3.fromRGB(235, 40, 40) })
Notify.takeover("SHARK INCOMING!", "Get to sand or an island!", Color3.fromRGB(235, 40, 40), 1.4)

-- dump every visible ScreenGui under PlayerGui
local out = {}
local function enc(v)
	local t = type(v)
	if t == "table" and v.X and type(v.X) == "table" then return { v.X.Scale, v.X.Offset, v.Y.Scale, v.Y.Offset } end
	if t == "table" and v.R then return { v.R, v.G, v.B } end
	if t == "table" and v.X then return { v.X, v.Y } end
	if t == "table" and v.Scale then return { v.Scale, v.Offset } end
	if t == "table" and v.Name and v.EnumType then return v.Name end
	if t == "string" or t == "number" or t == "boolean" then return v end
	return nil
end
local KEYS = { "ClassName", "Name", "Visible", "Enabled", "Size", "Position", "AnchorPoint", "BackgroundTransparency", "BackgroundColor3",
	"Text", "TextScaled", "TextSize", "TextColor3", "TextXAlignment", "TextYAlignment", "TextTransparency", "LayoutOrder", "ZIndex",
	"Padding", "FillDirection", "HorizontalAlignment", "VerticalAlignment", "SortOrder", "Scale", "AutomaticSize", "CornerRadius",
	"Thickness", "Color", "ApplyStrokeMode", "PaddingLeft", "PaddingRight", "PaddingTop", "PaddingBottom", "Image", "Rotation", "DisplayOrder" }
local function walk(n)
	local p = rawget(n, "_p")
	local o = {}
	for _, k in KEYS do
		local v = p[k]
		if v ~= nil then o[k] = enc(v) end
	end
	o.kids = {}
	for _, c in p._kids do table.insert(o.kids, walk(c)) end
	return o
end
for _, g in GUI_ROOTS do
	if rawget(g, "_p").Parent ~= nil then
		table.insert(out, walk(g))
	end
end
-- tiny JSON encoder
local function j(v)
	local t = type(v)
	if t == "table" then
		if #v > 0 or next(v) == nil then
			local parts = {}
			for _, x in v do table.insert(parts, j(x)) end
			return "[" .. table.concat(parts, ",") .. "]"
		end
		local parts = {}
		for k, x in v do table.insert(parts, string.format("%q", k) .. ":" .. j(x)) end
		return "{" .. table.concat(parts, ",") .. "}"
	elseif t == "string" then
		return (string.format("%q", v):gsub("\\\n", "\\n"))
	elseif t == "boolean" then
		return tostring(v)
	end
	return tostring(v)
end
print("JSON" .. j(out))
