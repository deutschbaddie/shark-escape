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
function V:Cross(b) return vec(self.Y * b.Z - self.Z * b.Y, self.Z * b.X - self.X * b.Z, self.X * b.Y - self.Y * b.X) end
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
