-- THE HOOK on this client: carry more, earn more, but the shark wants you
-- more.
--   Fins    what you carry draws shark fins that circle you in the water
--           (player attribute "Fins" 0-3, server Sharks.luau finsTick).
--           Everyone sees everyone's. When they close in ("FinsClose") they
--           tighten and speed up, and a few seconds later one charges.
--   Haul    the dock pays cash for a trip right away (server Game.payHaul):
--           the number counts up over your tank.
--   Spill   a bitten player's haul floats free: you get pointed at it.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = game.ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Layout = require(Shared.Layout)
local Remotes = require(Shared.Remotes)
local UI = require(script.Parent.UI)
local Fx = require(script.Parent.Fx)
local Notify = require(script.Parent.Notify)
local Guide = require(script.Parent.Guide)
local State = require(script.Parent.State)

local Haul = {}
local player = Players.LocalPlayer
local T = UI.T
local GREEN, ORANGE, RED = Color3.fromRGB(110, 230, 120), Color3.fromRGB(255, 170, 50), Color3.fromRGB(255, 60, 70)

local spillUntil = 0
local taught, warned = false, false

local function myRoot(): BasePart?
	local char = player.Character
	return char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
end

----------------------------------------------------------------- fins
-- a dark dorsal fin cutting the water, with a ripple of foam at its base
type Fin = { fin: BasePart, foam: BasePart }
local finsOf: { [Player]: { Fin } } = {}
local finFolder = Instance.new("Folder")
finFolder.Name = "HaulFins"
finFolder.Parent = Workspace

local function newFin(): Fin
	local fin = Instance.new("WedgePart")
	fin.Anchored, fin.CanCollide, fin.CanQuery, fin.CanTouch, fin.CastShadow = true, false, false, false, false
	fin.Color = Color3.fromRGB(70, 80, 96)
	fin.Size = Vector3.new(0.45, 2.4, 2.6)
	fin.Parent = finFolder
	local foam = Instance.new("Part")
	foam.Anchored, foam.CanCollide, foam.CanQuery, foam.CanTouch, foam.CastShadow = true, false, false, false, false
	foam.Shape = Enum.PartType.Cylinder
	foam.Material = Enum.Material.SmoothPlastic
	foam.Color = Color3.new(1, 1, 1)
	foam.Transparency = 0.45
	foam.Size = Vector3.new(0.15, 3.4, 3.4)
	foam.Parent = finFolder
	return { fin = fin, foam = foam }
end

local function setFins(p: Player, n: number)
	local list = finsOf[p] or {}
	finsOf[p] = list
	while #list < n do
		local f = newFin()
		table.insert(list, f)
		local at = f.fin.Position
		Fx.splash(Vector3.new(at.X, 0.5, at.Z), 0.6)
	end
	while #list > n do
		local f = table.remove(list) :: Fin
		f.fin:Destroy()
		f.foam:Destroy()
	end
	if n == 0 then
		finsOf[p] = nil
	end
end

local function finsUpdate()
	local t = os.clock()
	for _, p in Players:GetPlayers() do
		local char = p.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		local n = p:GetAttribute("Fins")
		n = typeof(n) == "number" and hrp ~= nil and n or 0
		setFins(p, n)
		local list = finsOf[p]
		if list and hrp then
			local close = p:GetAttribute("FinsClose") == true
			local center = hrp.Position
			local r = close and 13 + math.sin(t * 3) * 1.5 or 26 - n * 2
			local speed = close and 1.6 or 0.55
			for i, f in list do
				local a = t * speed + i / #list * math.pi * 2 + p.UserId % 10
				local pos = Vector3.new(center.X + math.cos(a) * r, 0.9 + math.sin(t * 2 + i) * 0.2, center.Z + math.sin(a) * r)
				-- travelling round the circle: face along it
				local ahead = Vector3.new(-math.sin(a), 0, math.cos(a))
				f.fin.CFrame = CFrame.lookAt(pos, pos + ahead)
				f.foam.CFrame = CFrame.new(pos.X, 0.15, pos.Z) * CFrame.Angles(0, 0, math.pi / 2)
				f.fin.Color = close and Color3.fromRGB(110, 70, 80) or Color3.fromRGB(70, 80, 96)
			end
		end
	end
	for p in finsOf do
		if not p.Parent then
			setFins(p, 0)
		end
	end
	-- teach it once, and warn when they close in on you
	local d = State.data
	local mine = player:GetAttribute("Fins")
	if not taught and typeof(mine) == "number" and mine > 0 and d and (d.playtime or 0) < 3600 then
		taught = true
		Notify.toast("Fins follow your haul. Carry a lot and one charges!", ORANGE)
	end
	local close = player:GetAttribute("FinsClose") == true
	if close and not warned then
		warned = true
		Notify.banner("The fins are closing in", { key = "fins", priority = 4, time = 3, color = RED, sub = "Get your haul to the sand!" })
		Fx.sound("sharkAlarm", 0.6, 1.15)
	elseif not close then
		warned = false
	end
end

-- the dock's payout: a number that counts up over your tank
local function payout(d: any)
	local at = Vector3.new(d.x, d.y + 19, d.z) -- (above the tank sign and the +$/s popups)
	local anchor = Instance.new("Part")
	anchor.Anchored, anchor.CanCollide, anchor.CanQuery, anchor.CanTouch = true, false, false, false
	anchor.Transparency = 1
	anchor.Size = Vector3.one
	anchor.Position = at
	anchor.Parent = Workspace
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(260, 80)
	bb.AlwaysOnTop = true
	bb.LightInfluence = 0
	bb.MaxDistance = 250
	bb.Adornee = anchor
	bb.Parent = anchor
	local amount = UI.outlined(bb, "+$0", { Size = UDim2.new(1, 0, 0, 48), TextColor3 = T.gold })
	local multi = (d.n or 1) > 1
	UI.outlined(bb, multi and ("Haul of %d · x%s"):format(d.n, ("%g"):format(d.mult or 1)) or "Brought home",
		{ Size = UDim2.new(1, 0, 0, 26), Position = UDim2.fromOffset(0, 50), TextColor3 = multi and T.white or Color3.fromRGB(200, 210, 230) })
	Fx.confetti(at - Vector3.new(0, 6, 0), multi and { T.gold, Color3.new(1, 1, 1), GREEN } or { T.gold })
	Fx.sound("deposit", 0.9, multi and 1 + math.min(d.n, 8) * 0.04 or 1)
	local total = d.coins or 0
	local t0 = os.clock()
	local dur = multi and 1.1 or 0.6
	local conn
	conn = RunService.RenderStepped:Connect(function()
		local k = math.clamp((os.clock() - t0) / dur, 0, 1)
		amount.Text = "+$" .. UI.short(math.floor(total * (1 - (1 - k) ^ 3)))
		anchor.Position = at + Vector3.new(0, k * 2, 0)
		if k >= 1 then
			conn:Disconnect()
			if multi then
				Fx.sound("coin", 0.8, 1.2)
			end
			task.delay(1.4, function()
				TweenService:Create(amount, TweenInfo.new(0.4), { TextTransparency = 1 }):Play()
				task.delay(0.5, function()
					anchor:Destroy()
				end)
			end)
		end
	end)
end

local function onSpill(d: any)
	local hrp = myRoot()
	local at = Vector3.new(d.x, 3, d.z)
	local time = d.time or Config.SPILL_TIME
	if d.why == "bonk" then
		-- bonked loose: no banner (the bonk says it), just the arrow for whoever's close
		if hrp and (hrp.Position - at).Magnitude < 140 then
			spillUntil = os.clock() + 15
			Guide.set("spill", at, d.userId == player.UserId and "Grab it back" or "Loot")
			local mine = spillUntil
			task.delay(15, function()
				if spillUntil == mine then
					Guide.set("spill", nil)
				end
			end)
		end
		return
	end
	if d.userId == player.UserId then
		-- yours: once you've washed up, go get it back
		task.delay(Config.Shark.eatenTime + 1, function()
			Notify.banner("Your haul spilled", { key = "spill", priority = 3, time = 4, color = ORANGE,
				sub = "Grab it back fast!" })
		end)
		spillUntil = os.clock() + time
		Guide.set("spill", at, "Your haul")
	elseif hrp and Config.worldAt(hrp.Position) == Config.worldAt(at) and (hrp.Position - at).Magnitude < 350 then
		Notify.toast(("%s's haul is up for grabs!"):format(tostring(d.name)), ORANGE)
		spillUntil = os.clock() + math.min(time, 20)
		Guide.set("spill", at, "Loot")
	else
		return
	end
	local mine = spillUntil
	task.delay(spillUntil - os.clock(), function()
		if spillUntil == mine then
			Guide.set("spill", nil)
		end
	end)
end

function Haul.start()
	RunService.RenderStepped:Connect(finsUpdate)
	Remotes.get("Notify").OnClientEvent:Connect(function(kind, d)
		if typeof(d) ~= "table" then
			return
		end
		if kind == "haul" then
			payout(d)
		elseif kind == "spill" then
			onSpill(d)
		elseif kind == "grab" and spillUntil > os.clock() then
			-- picked something up near the spill: the arrow's done its job
			local hrp = myRoot()
			if hrp and Layout.inWater(hrp.Position) then
				spillUntil = 0
				Guide.set("spill", nil)
			end
		end
	end)
end

return Haul
