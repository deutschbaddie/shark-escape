-- Chum and raids on this client (server: Raids.luau).
--   Chum: a red CHUM button shows up when another rider is near you at sea;
--         tap it and their zone's shark comes for them. Then a cooldown.
--   Raid: other players' docks get a RAID prompt (hold F). While a raid is
--         on, a red countdown hangs over that tank for everyone; the owner
--         gets an alarm and the guide arrow home; the raider a countdown.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
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
local Prompts = require(script.Parent.Prompts)

local Pvp = {}
local player = Players.LocalPlayer
local C = UI.C
local RED = Color3.fromRGB(235, 55, 70)

local chumBtn: TextButton
local chumTarget: Player? = nil
local chumReadyAt = 0
local raidEnds = 0 -- my raid (as the raider)
local defendEnds = 0 -- my tank under raid
local defendBy = ""
local raidBoards: { [Model]: BillboardGui } = {}

local function myRoot(): BasePart?
	local char = player.Character
	return char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function atSea(pos: Vector3): boolean
	return Layout.inWater(pos) and Layout.islandAt(pos, 0) == nil
end

----------------------------------------------------------------- chum button
local function buildChum()
	local gui = Instance.new("ScreenGui")
	gui.Name = "Chum"
	gui.ResetOnSpawn = false
	gui.Parent = player:WaitForChild("PlayerGui")
	UI.autoScale(gui)
	chumBtn = UI.button(gui, "CHUM", RED, function()
		if chumTarget and os.clock() >= chumReadyAt then
			State.action("chum", chumTarget.UserId)
		end
	end, { Size = UDim2.fromOffset(190, 54), Position = UDim2.new(0.5, 0, 1, -150), AnchorPoint = Vector2.new(0.5, 1), Visible = false })
end

-- the nearest other rider at sea in reach, in your world
local function pickTarget(): Player?
	local me = myRoot()
	if not me then
		return nil
	end
	local best, bestD = nil, Config.Chum.range
	for _, p in Players:GetPlayers() do
		local char = p ~= player and p.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if hrp and atSea(hrp.Position) and Config.worldAt(hrp.Position) == Config.worldAt(me.Position) then
			local d = (hrp.Position - me.Position).Magnitude
			if d < bestD then
				best, bestD = p, d
			end
		end
	end
	return best
end

local function chumTick()
	chumTarget = pickTarget()
	local wait = chumReadyAt - os.clock()
	chumBtn.Visible = chumTarget ~= nil
	if chumTarget then
		if wait > 0 then
			UI.setText(chumBtn, ("CHUM  %ds"):format(math.ceil(wait)))
			chumBtn.BackgroundColor3 = UI.T.navyLight
		else
			UI.setText(chumBtn, "CHUM " .. chumTarget.DisplayName)
			chumBtn.BackgroundColor3 = RED
		end
	end
end

----------------------------------------------------------------- raid prompts + boards
local function plotModels(): { Model }
	local out = {}
	for _, map in Layout.worldFolders() do
		for _, m in map:GetChildren() do
			if m:IsA("Model") and m.Name:match("^Plot%d+$") then
				table.insert(out, m)
			end
		end
	end
	return out
end

local function raidTick()
	local now = Workspace:GetServerTimeNow()
	for _, m in plotModels() do
		local owner = m:GetAttribute("Owner")
		local prompt = m:FindFirstChild("RaidTank", true)
		if prompt and prompt:IsA("ProximityPrompt") then
			prompt.Enabled = typeof(owner) == "number" and owner ~= player.UserId
		end
		-- a red countdown over a tank being raided (everyone sees it)
		local ends = m:GetAttribute("RaidEnds")
		local board = raidBoards[m]
		if typeof(ends) == "number" and ends > now then
			if not board then
				local anchor = m:FindFirstChild("TankSign", true) :: BasePart?
				if anchor then
					board = Instance.new("BillboardGui")
					board.Size = UDim2.fromScale(10, 2.4)
					board.StudsOffsetWorldSpace = Vector3.new(0, 5.5, 0)
					board.AlwaysOnTop = true
					board.LightInfluence = 0
					board.MaxDistance = 300
					board.Adornee = anchor
					board.Parent = player:WaitForChild("PlayerGui")
					UI.outlined(board, "", { Name = "T", Size = UDim2.fromScale(1, 1), TextColor3 = RED })
					raidBoards[m] = board
				end
			end
			if board then
				local t = board:FindFirstChild("T") :: TextLabel?
				if t then
					t.Text = ("RAID %d"):format(math.ceil(ends - now))
				end
			end
		elseif board then
			board:Destroy()
			raidBoards[m] = nil
		end
	end
	-- my own countdowns
	local left = raidEnds - os.clock()
	if left > 0 then
		Notify.banner(("RAIDING... %d"):format(math.ceil(left)), { key = "raid", sticky = true, priority = 6, color = RED,
			sub = "Stay by the tank! If they get home first, you're thrown off" })
	end
	local dleft = defendEnds - os.clock()
	if dleft > 0 then
		Notify.banner(("YOUR TANK IS BEING RAIDED! %d"):format(math.ceil(dleft)), { key = "raid", sticky = true, priority = 6, color = RED,
			sub = defendBy .. " is stealing from you. Get back to your dock!" })
	end
end

local function clearRaid()
	raidEnds, defendEnds = 0, 0
	Notify.clear("raid")
	Guide.set("raid", nil)
end

----------------------------------------------------------------- server news
local handlers: { [string]: (any) -> () } = {}

handlers.chumThrown = function(d)
	chumReadyAt = os.clock() + (d.cooldown or Config.Chum.cooldown)
	Notify.toast(("Chummed %s! The shark is on its way"):format(tostring(d.name)), RED)
	Fx.sound("splash", 0.8, 0.8)
end

handlers.chumSplash = function(d)
	local pos = Vector3.new(d.x, 0.5, d.z)
	Fx.splash(pos, 1.6)
	Fx.ring(pos, RED, 22)
end

handlers.raided = function(d)
	defendEnds = os.clock() + (d.seconds or Config.Raid.time)
	defendBy = tostring(d.by)
	Notify.takeover("RAID!", ("%s is robbing your tank. Rush home!"):format(defendBy), RED, 1.6)
	Fx.sound("sharkAlarm", 1)
	Guide.set("raid", Vector3.new(d.x, d.y + 2, d.z), "Your tank")
end

handlers.raidStart = function(d)
	raidEnds = os.clock() + (d.seconds or Config.Raid.time)
	Notify.toast(("Raiding %s's tank. They've been warned!"):format(tostring(d.name)), RED)
end

handlers.raidWon = function(d)
	clearRaid()
	Notify.takeover("STOLEN!", ("%s from %s. Get it home!"):format(tostring(d.name), tostring(d.from)), C.gold, 1.8)
	Fx.sound("legendary", 0.8)
end

handlers.raidLost = function(d)
	clearRaid()
	Notify.takeover("ROBBED!", ("%s stole your %s"):format(tostring(d.by), tostring(d.name)), RED, 2)
end

handlers.raidDefended = function(d)
	clearRaid()
	if d.gaveUp then
		Notify.toast(("%s gave up the raid"):format(tostring(d.by)), C.green)
	else
		Notify.takeover("DEFENDED!", ("You got home in time. %s got thrown off!"):format(tostring(d.by)), C.green, 1.6)
		Fx.sound("dodge", 0.9)
	end
end

handlers.raidFail = function(d)
	clearRaid()
	if d.why == "defended" then
		Notify.takeover("CAUGHT!", ("%s got home in time"):format(tostring(d.by)), RED, 1.4)
	elseif d.why == "left" then
		Notify.toast("You left the tank: raid failed", RED)
	else
		Notify.toast("Nothing worth taking in there", C.white)
	end
end

handlers.raidNews = function(d)
	if d.by ~= player.DisplayName and d.from ~= player.DisplayName then
		Notify.toast(("%s raided %s's tank!"):format(tostring(d.by), tostring(d.from)), RED)
	end
end

function Pvp.start()
	buildChum()
	Prompts.Triggered:Connect(function(prompt)
		if prompt.Name == "RaidTank" then
			State.action("raid", prompt:GetAttribute("Plot"))
		end
	end)
	Remotes.get("Notify").OnClientEvent:Connect(function(kind, data)
		local fn = handlers[kind]
		if fn and typeof(data) == "table" then
			fn(data)
		end
	end)
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc >= 0.25 then
			acc = 0
			chumTick()
			raidTick()
		end
	end)
end

return Pvp
