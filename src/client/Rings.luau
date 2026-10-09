-- Boost rings (Layout.Rings, built by World.luau): ride through one and you
-- get a burst of speed and a pop into the air (Ride.burst) right away; the
-- server pays some speed gain (Game actions.ring). The ring bursts and is
-- gone (for you) until it fades back in Layout.RING_RESPAWN seconds later.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = game.ReplicatedStorage.Shared
local Layout = require(Shared.Layout)
local Remotes = require(Shared.Remotes)
local UI = require(script.Parent.UI)
local Fx = require(script.Parent.Fx)
local State = require(script.Parent.State)
local Ride = require(script.Parent.Ride)

local Rings = {}
local player = Players.LocalPlayer

local GOLD = Color3.fromRGB(255, 210, 50)
local lastPos: Vector3? = nil
local cooldown: { [number]: number } = {}

local function ringModel(i: number): Model?
	local map = Workspace:FindFirstChild("Map")
	local folder = map and map:FindFirstChild("Rings")
	return folder and folder:FindFirstChild("Ring" .. i) :: Model?
end

-- the hoop bursts: flashes white, swells and fades out; back in a minute
local function pop(i: number)
	local m = ringModel(i)
	if not m then
		return
	end
	for _, p in m:GetChildren() do
		if p:IsA("BasePart") then
			local base = p:GetAttribute("BaseColor") or p.Color
			p:SetAttribute("BaseColor", base)
			p.Color = Color3.new(1, 1, 1)
			TweenService:Create(p, TweenInfo.new(0.35, Enum.EasingStyle.Quad), { Transparency = 1 }):Play()
		end
	end
	task.delay(Layout.RING_RESPAWN, function()
		for _, p in m:GetChildren() do
			if p:IsA("BasePart") then
				p.Color = p:GetAttribute("BaseColor") or p.Color
				TweenService:Create(p, TweenInfo.new(1.2), { Transparency = 0 }):Play()
			end
		end
	end)
end

local function passed(i: number, at: Vector3)
	local now = os.clock()
	if now - (cooldown[i] or -1e9) < Layout.RING_RESPAWN then
		return -- (gone for now)
	end
	cooldown[i] = now
	Ride.burst(1.6, 26)
	pop(i)
	Fx.ring(at, GOLD, Layout.RING_RADIUS * 3)
	Fx.sparkle(at, GOLD, 24)
	Fx.sound("rideKick", 0.7, 1.15)
	Fx.shake(0.4)
	State.action("ring", i)
end

local function step()
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hrp then
		lastPos = nil
		return
	end
	local pos = hrp.Position
	local prev = lastPos
	lastPos = pos
	if not prev or not Ride.isRiding() or (pos - prev).Magnitude > 60 then
		return
	end
	local R = Layout.RING_RADIUS + 0.6
	for i, r in Layout.Rings do
		local a, b = prev.Z - r.Z, pos.Z - r.Z
		-- crossed the hoop's plane this frame, inside the hoop
		if (a < 0) ~= (b < 0) and math.abs(a) < 40 then
			local k = math.abs(a) / math.max(math.abs(a) + math.abs(b), 1e-3)
			local x = prev.X + (pos.X - prev.X) * k
			local y = prev.Y + (pos.Y - prev.Y) * k
			if Vector2.new(x - r.X, y - r.Y).Magnitude < R then
				passed(i, r)
			end
		end
	end
end

function Rings.start()
	RunService.Heartbeat:Connect(step)
	Remotes.get("Notify").OnClientEvent:Connect(function(kind, data)
		if kind == "ring" and typeof(data) == "table" and typeof(data.amount) == "number" then
			local r = Layout.Rings[data.i]
			if r then
				Fx.popup3D(r + Vector3.new(0, Layout.RING_RADIUS + 2, 0), ("+%s speed"):format(UI.short(data.amount)), GOLD, true)
			end
		end
	end)
end

return Rings
