-- Chum and raids on this client (server: Raids.luau).
--   Chum: a red CHUM button shows up when another rider is near you at sea;
--         tap it and their zone's shark comes for them. Then a cooldown.
--   Raid: other players' docks get a RAID prompt (hold F). While a raid is
--         on, a red countdown hangs over that tank for everyone; the owner
--         gets an alarm and the guide arrow home; the raider a countdown.
--         While an owner is home (or has a Tank Lock) the server shows a
--         shield over their tank ("Guarded"); here a sign under it says so,
--         and you get one heads-up when you leave the beach / come home.

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
local safeBoards: { [Model]: BillboardGui } = {}
local GREEN = Color3.fromRGB(110, 255, 150)
local myGuard: string? = "start"
local toldOut, toldHome = false, false

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
	UI.hideInCutscenes(gui)
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
local safeSign: (Model, any) -> ()

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

local function clearRaid()
	raidEnds, defendEnds = 0, 0
	Notify.clear("raid")
	Guide.set("raid", nil)
end

-- the line over a tank that says whether it can be raided
function safeSign(m: Model, owner: any)
	local why = m:GetAttribute("Guarded")
	local mine = owner == player.UserId
	local text, color
	if typeof(owner) ~= "number" or why == "new" or (typeof(m:GetAttribute("RaidEnds")) == "number") then
		text = nil
	elseif why == "lock" then
		text, color = "Tank Lock: safe from raids", Color3.fromRGB(255, 205, 70)
	elseif why == "home" then
		text, color = mine and "Safe from raids while you're home" or "Owner is home: safe from raids", GREEN
	elseif mine then
		text, color = "Can be raided while you're out", RED
	end
	local board = safeBoards[m]
	if not text then
		if board then
			board:Destroy()
			safeBoards[m] = nil
		end
	else
		if not board then
			local anchor = m:FindFirstChild("TankSign", true) :: BasePart?
			if not anchor then
				return
			end
			board = Instance.new("BillboardGui")
			board.Size = UDim2.fromScale(11, 1.5)
			board.StudsOffsetWorldSpace = Vector3.new(0, 4.6, 0)
			board.LightInfluence = 0
			board.MaxDistance = 130
			board.Adornee = anchor
			board.Parent = player:WaitForChild("PlayerGui")
			UI.outlined(board, "", { Name = "T", Size = UDim2.fromScale(1, 1) })
			safeBoards[m] = board
		end
		local t = (board :: BillboardGui):FindFirstChild("T") :: TextLabel?
		if t then
			t.Text = text
			t.TextColor3 = color
		end
	end
	-- my own tank: one heads-up each way per session
	if mine and why ~= myGuard then
		if myGuard == "home" and why == nil and not toldOut then
			toldOut = true
			Notify.toast("Your tank can be raided now", RED)
		elseif myGuard == nil and why == "home" and not toldHome then
			toldHome = true
			Notify.toast("Home: your tank is safe", GREEN)
		end
		myGuard = why
	end
end

local function raidTick()
	local now = Workspace:GetServerTimeNow()
	for _, m in plotModels() do
		local owner = m:GetAttribute("Owner")
		local prompt = m:FindFirstChild("RaidTank", true)
		if prompt and prompt:IsA("ProximityPrompt") then
			local lock = m:GetAttribute("LockUntil")
			local d = State.data
			prompt.Enabled = typeof(owner) == "number" and owner ~= player.UserId
				and d ~= nil and d.rebirths >= 1 -- (raids come after your first rebirth)
				and not (typeof(lock) == "number" and lock > os.time()) -- (Tank Lock)
				and m:GetAttribute("Guarded") == nil -- (owner is home)
		end
		safeSign(m, owner)
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
			sub = "Stay by the tank!" })
	end
	local dleft = defendEnds - os.clock()
	-- (a raid that ended without word: never leave the banner up)
	if (raidEnds > 0 and left < -4) or (defendEnds > 0 and dleft < -4) then
		clearRaid()
		return
	end
	if dleft > 0 then
		Notify.banner(("Your tank is being raided, %d"):format(math.ceil(dleft)), { key = "raid", sticky = true, priority = 6, color = RED,
			sub = defendBy .. " is robbing you. Rush home!" })
	end
end

----------------------------------------------------------------- server news
local handlers: { [string]: (any) -> () } = {}

handlers.chumThrown = function(d)
	chumReadyAt = os.clock() + (d.cooldown or Config.Chum.cooldown)
	Notify.toast(("Chummed %s!"):format(tostring(d.name)), RED)
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
	Notify.takeover("Raid", ("%s is robbing your tank. Rush home!"):format(defendBy), RED, 1.6)
	Notify.chat(("%s is robbing your tank!"):format(defendBy), nil, "RAID", true)
	Fx.sound("sharkAlarm", 1)
	Guide.set("raid", Vector3.new(d.x, d.y + 2, d.z), "Your tank")
end

handlers.raidStart = function(d)
	raidEnds = os.clock() + (d.seconds or Config.Raid.time)
	Notify.toast(("Raiding %s's tank!"):format(tostring(d.name)), RED)
end

handlers.raidWon = function(d)
	clearRaid()
	Notify.takeover("Stolen", ("%s from %s. Get it home!"):format(tostring(d.name), tostring(d.from)), C.gold, 1.8)
	Notify.chat(("You stole a %s from %s!"):format(tostring(d.name), tostring(d.from)), nil, "RAID", true)
	Fx.sound("legendary", 0.8)
end

handlers.raidLost = function(d)
	clearRaid()
	Notify.takeover("Robbed", ("%s stole your %s"):format(tostring(d.by), tostring(d.name)), RED, 2)
	Notify.chat(("%s stole your %s"):format(tostring(d.by), tostring(d.name)), nil, "RAID", true)
end

handlers.raidDefended = function(d)
	clearRaid()
	if d.locked then
		Notify.toast("Tank Lock on: the raid is off", C.green)
	elseif d.gaveUp then
		Notify.toast(("%s gave up the raid"):format(tostring(d.by)), C.green)
	else
		Notify.takeover("Defended", ("%s got thrown off!"):format(tostring(d.by)), C.green, 1.6)
		Notify.chat(("You stopped %s's raid!"):format(tostring(d.by)), nil, "RAID", true)
		Fx.sound("dodge", 0.9)
	end
end

handlers.raidFail = function(d)
	clearRaid()
	if d.why == "defended" then
		Notify.takeover("Caught", ("%s got home in time"):format(tostring(d.by)), RED, 1.4)
	elseif d.why == "left" then
		Notify.toast("You left the tank: raid failed", RED)
	elseif d.why == "locked" then
		Notify.toast("They locked their tank: raid failed", RED)
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
