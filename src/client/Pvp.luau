-- Raids on this client (server: Raids.luau).
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
local RaidSpin = require(script.Parent.RaidSpin)

local Pvp = {}
local player = Players.LocalPlayer
local C = UI.C

local raidEnds = 0 -- my raid (as the raider)
local defendEnds = 0 -- my tank under raid
local defendBy = ""
local raidBoards: { [Model]: BillboardGui } = {}
local safeBoards: { [Model]: BillboardGui } = {}
local GREEN = Color3.fromRGB(110, 255, 150)
local ORANGE = Color3.fromRGB(255, 165, 60) -- raids: urgent, never scary red
local myGuard: string? = "start"
local toldOut, toldHome = false, false

----------------------------------------------------------------- raid prompts + boards
local safeSign: (Model, any) -> ()
local closeInEvolves: (any) -> boolean

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

-- is this tank's owner within raiding range of my evolves?
closeInEvolves = function(owner: any): boolean
	local p = typeof(owner) == "number" and Players:GetPlayerByUserId(owner)
	local theirs = p and p:GetAttribute("Rebirths")
	local d = State.data
	return typeof(theirs) == "number" and d ~= nil and math.abs(theirs - d.rebirths) <= Config.Raid.evolveGap
end

-- the line over a tank that says whether it can be raided
function safeSign(m: Model, owner: any)
	local why = m:GetAttribute("Guarded")
	local mine = owner == player.UserId
	local text, color
	local safeUntil = m:GetAttribute("SafeUntil")
	local d = State.data
	if typeof(owner) ~= "number" or why == "new" or (typeof(m:GetAttribute("RaidEnds")) == "number") then
		text = nil
	elseif typeof(safeUntil) == "number" and safeUntil > Workspace:GetServerTimeNow() and why ~= "home" then
		text, color = "Just raided: safe for a bit", GREEN
	elseif why == "lock" then
		text, color = "Tank Lock: safe from raids", Color3.fromRGB(255, 205, 70)
	elseif why == "home" then
		text, color = mine and "Safe from raids while you're home" or "Owner is home: safe from raids", GREEN
	elseif mine then
		text, color = "Can be raided while you're out", ORANGE
	elseif d and d.rebirths >= 1 and closeInEvolves(owner) then
		text, color = "Owner is out: you can raid", C.gold
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
			Notify.toast("Your tank can be raided now", ORANGE)
		elseif myGuard == nil and why == "home" and not toldHome then
			toldHome = true
			Notify.toast("Home: your tank is safe", GREEN)
		end
		myGuard = why
	end
end

-- a gold label over anyone walking raid loot home (everyone can bonk it),
-- and a reminder for the one carrying it
local lootLabels: { [Model]: BillboardGui } = {}
local function lootTick()
	for _, p in Players:GetPlayers() do
		local char = p.Character
		local on = char ~= nil and char:GetAttribute("RaidLoot") == true
		local label = char and lootLabels[char]
		if on and not label and p ~= player then
			local head = (char :: Model):FindFirstChild("Head") :: BasePart?
			if head then
				local bb = Instance.new("BillboardGui")
				bb.Size = UDim2.fromScale(8, 1.4)
				bb.StudsOffsetWorldSpace = Vector3.new(0, 5.6, 0)
				bb.AlwaysOnTop = true
				bb.LightInfluence = 0
				bb.MaxDistance = 160
				bb.Adornee = head
				bb.Parent = player:WaitForChild("PlayerGui")
				UI.outlined(bb, "Stolen loot: bonk it loose!", { Size = UDim2.fromScale(1, 1), TextColor3 = C.gold })
				lootLabels[char :: Model] = bb
			end
		elseif not on and label then
			label:Destroy()
			lootLabels[char :: Model] = nil
		end
	end
	for char, bb in lootLabels do
		if not char.Parent then
			bb:Destroy()
			lootLabels[char] = nil
		end
	end
	local mine = player.Character and player.Character:GetAttribute("RaidLoot") == true
	if mine then
		Notify.banner("Walk it home!", { key = "loot", sticky = true, priority = 4, compact = true, color = C.gold,
			sub = "Anyone can bonk it loose" })
	else
		Notify.clear("loot")
	end
end

local function raidTick()
	lootTick()
	local now = Workspace:GetServerTimeNow()
	for _, m in plotModels() do
		local owner = m:GetAttribute("Owner")
		local prompt = m:FindFirstChild("RaidTank", true)
		if prompt and prompt:IsA("ProximityPrompt") then
			local lock = m:GetAttribute("LockUntil")
			local d = State.data
			prompt.Enabled = typeof(owner) == "number" and owner ~= player.UserId
				and d ~= nil and d.rebirths >= 1 -- (raids come after your first evolve)
				and closeInEvolves(owner) -- (Config.Raid.evolveGap)
				and not (typeof(lock) == "number" and lock > os.time()) -- (Tank Lock)
				and m:GetAttribute("Guarded") == nil -- (owner is home)
				and not (typeof(m:GetAttribute("SafeUntil")) == "number" and m:GetAttribute("SafeUntil") > now) -- (just raided)
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
					UI.outlined(board, "", { Name = "T", Size = UDim2.fromScale(1, 1), TextColor3 = ORANGE })
					raidBoards[m] = board
				end
			end
			if board then
				local t = board:FindFirstChild("T") :: TextLabel?
				if t then
					t.Text = ("Raid %ds"):format(math.ceil(ends - now))
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
		Notify.banner(("Raiding: %ds"):format(math.ceil(left)), { key = "raid", sticky = true, priority = 4, compact = true, color = ORANGE,
			sub = "Stay by the tank!" })
	end
	local dleft = defendEnds - os.clock()
	-- (a raid that ended without word: never leave the banner up)
	if (raidEnds > 0 and left < -4) or (defendEnds > 0 and dleft < -4) then
		clearRaid()
		return
	end
	if dleft > 0 then
		-- (priority under the shark status, so a shark warning on the way home always shows)
		Notify.banner(("Get home! %ds"):format(math.ceil(dleft)), { key = "raid", sticky = true, priority = 4, compact = true, color = ORANGE,
			sub = defendBy .. " is at your tank" })
	end
end

----------------------------------------------------------------- server news
local handlers: { [string]: (any) -> () } = {}

handlers.raided = function(d)
	defendEnds = os.clock() + (d.seconds or Config.Raid.time)
	defendBy = tostring(d.by)
	Notify.takeover("Raid", ("%s is robbing your tank. Rush home!"):format(defendBy), ORANGE, 1.6)
	Notify.chat(("%s is robbing your tank!"):format(defendBy), nil, "RAID", true)
	Fx.sound("uiTakeover", 1) -- (not the shark alarm: no shark is coming)
	Guide.set("raid", Vector3.new(d.x, d.y + 2, d.z), "Your tank")
end

handlers.raidStart = function(d)
	raidEnds = os.clock() + (d.seconds or Config.Raid.time)
	Notify.toast(("Raiding %s's tank!"):format(tostring(d.name)), ORANGE)
end

-- the spin plays first (both players watch it), then the result
local function afterSpin(d: any, title: string, sub: string, fn: () -> ())
	if typeof(d.spin) == "table" and #d.spin > 0 then
		RaidSpin.play(d.spin, d.win or 1, title, sub, fn)
	else
		fn()
	end
end

handlers.raidWon = function(d)
	clearRaid()
	afterSpin(d, ("Raiding %s's tank"):format(tostring(d.from)), "Rarer ones are harder to get!", function()
		handlers.raidWonResult(d)
	end)
end

handlers.raidWonResult = function(d)
	Notify.takeover("Stolen", ("%s from %s. Walk it home!"):format(tostring(d.name), tostring(d.from)), C.gold, 1.8)
	Notify.chat(("You stole a %s from %s!"):format(tostring(d.name), tostring(d.from)), nil, "RAID", true)
	Fx.sound("legendary", 0.8)
end

handlers.raidLost = function(d)
	clearRaid()
	afterSpin(d, ("%s is taking one of yours"):format(tostring(d.by)), "Rarer ones are safer!", function()
		handlers.raidLostResult(d)
	end)
end

handlers.raidLostResult = function(d)
	Notify.takeover("Raided", ("%s is carrying your %s home. Bonk it loose!"):format(tostring(d.by), tostring(d.name)), ORANGE, 2.2)
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
		Notify.takeover("Caught", ("%s got home in time"):format(tostring(d.by)), ORANGE, 1.4)
	elseif d.why == "left" then
		Notify.toast("You left the tank: raid failed", ORANGE)
	elseif d.why == "gone" then
		Notify.toast("They left the game: raid off", C.white)
	elseif d.why == "locked" then
		Notify.toast("They locked their tank: raid failed", ORANGE)
	else
		Notify.toast("Nothing worth taking in there", C.white)
	end
end

function Pvp.start()
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
			raidTick()
		end
	end)
end

return Pvp
