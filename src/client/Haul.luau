-- THE HOOK on this client: carry more, earn more, but the shark wants you
-- more.
--   Hunger  a bar over the bottom HUD while you're at sea: your zone's shark
--           (Workspace "Hunger_<zone id>", server Sharks.luau). Every grab
--           fills it; full = it goes for whoever there carries the most.
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

local panel: Frame
local fill: Frame
local label: TextLabel
local spillUntil = 0
local taught = false -- the one line that explains the bar (newer players, once a session)

local function myRoot(): BasePart?
	local char = player.Character
	return char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function sharkName(id: string): string
	return (id:gsub("(%l)(%u)", "%1 %2"))
end

local function build()
	local gui = Instance.new("ScreenGui")
	gui.Name = "Hunger"
	gui.ResetOnSpawn = false
	gui.Parent = player:WaitForChild("PlayerGui")
	UI.autoScale(gui)
	panel = UI.frame(gui, { Size = UDim2.fromOffset(320, 30), Position = UDim2.new(0.5, 0, 1, -196), AnchorPoint = Vector2.new(0.5, 1),
		BackgroundTransparency = 1, Visible = false })
	UI.icon(panel, "Shark", { Size = UDim2.fromOffset(34, 34), Position = UDim2.new(0, 0, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5) })
	local track = UI.frame(panel, { Size = UDim2.new(1, -42, 0, 24), Position = UDim2.new(0, 42, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5),
		BackgroundColor3 = T.navyDark })
	UI.corner(track, 12)
	UI.stroke(track, T.white, 2)
	fill = UI.frame(track, { Size = UDim2.fromScale(0, 1), BackgroundColor3 = GREEN })
	UI.corner(fill, 12)
	label = UI.outlined(track, "", { Size = UDim2.new(1, -12, 1, -4), Position = UDim2.fromOffset(6, 2), ZIndex = track.ZIndex + 3,
		TextXAlignment = Enum.TextXAlignment.Left })
end

local function tick()
	local hrp = myRoot()
	local pos = hrp and hrp.Position
	local zone = pos and Layout.inWater(pos) and Config.zoneAtPos(pos)
	if not zone then
		panel.Visible = false
		return
	end
	local v = Workspace:GetAttribute("Hunger_" .. zone.id)
	v = typeof(v) == "number" and v or 0
	local d = State.data
	if d and d.tut < 5 then
		panel.Visible = false -- (not during the first-session guide: one thing at a time)
		return
	end
	panel.Visible = true
	if not taught and d and d.tut >= 5 and (d.playtime or 0) < 3600 then
		taught = true
		Notify.banner("Shark hunger", { key = "hungerTip", priority = 3, time = 4.5, color = ORANGE,
			sub = "Grabs fill it. Full = it hunts the biggest haul" })
	end
	local k = math.clamp(v / 100, 0, 1)
	fill.Size = UDim2.fromScale(k, 1)
	local color = k < 0.5 and GREEN:Lerp(ORANGE, k * 2) or ORANGE:Lerp(RED, (k - 0.5) * 2)
	if k >= 0.85 then
		color = color:Lerp(Color3.new(1, 1, 1), 0.25 + 0.25 * math.sin(os.clock() * 12))
	end
	fill.BackgroundColor3 = color
	label.Text = k >= 1 and ("%s is hunting the biggest haul"):format(sharkName(zone.shark))
		or ("%s hunger"):format(sharkName(zone.shark))
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

-- (the UI preview: the bar as it looks at sea)
function Haul.preview(v: number)
	panel.Visible = true
	fill.Size = UDim2.fromScale(v / 100, 1)
	fill.BackgroundColor3 = ORANGE
	label.Text = "Great White hunger"
end

function Haul.start()
	build()
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc >= 0.1 then
			acc = 0
			tick()
		end
	end)
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
