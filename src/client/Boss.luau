-- The boss Megalodon on this client (server: Sharks.spawnBoss / harpoon).
-- A health bar rides above it, a banner + guide arrow point at it while it's
-- up in your world, the HARPOON button shows up in range (F on keyboard),
-- and every throw (yours or anyone's) flies as a spear from the thrower.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = game.ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local UI = require(script.Parent.UI)
local Fx = require(script.Parent.Fx)
local Notify = require(script.Parent.Notify)
local Guide = require(script.Parent.Guide)
local State = require(script.Parent.State)
local SharkView = require(script.Parent.SharkView)

local Boss = {}
local player = Players.LocalPlayer
local T = UI.T
local RED = Color3.fromRGB(255, 70, 85)

local button: TextButton
local readyAt = 0
local bar: { anchor: Part, fill: Frame, text: TextLabel }? = nil
local shownSub = ""

local function myRoot(): BasePart?
	local char = player.Character
	return char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function myWorld(): number
	local hrp = myRoot()
	return hrp and Config.worldAt(hrp.Position) or (State.data and State.data.world or 1)
end

-- the boss up in my world: its shark (client copy), hp, max
local function current(): (any, number, number)
	local w = myWorld()
	local id = Workspace:GetAttribute("BossId" .. w)
	if typeof(id) ~= "number" then
		return nil, 0, 1
	end
	return SharkView.get(id), Workspace:GetAttribute("BossHp" .. w) or 0, Workspace:GetAttribute("BossMax" .. w) or 1
end

local function buildBar(): { anchor: Part, fill: Frame, text: TextLabel }
	local anchor = Instance.new("Part")
	anchor.Name = "BossBar"
	anchor.Anchored, anchor.CanCollide, anchor.CanQuery, anchor.CanTouch = true, false, false, false
	anchor.Transparency = 1
	anchor.Size = Vector3.one
	anchor.Parent = Workspace
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(320, 46)
	bb.AlwaysOnTop = true
	bb.MaxDistance = 900
	bb.Adornee = anchor
	bb.Parent = anchor
	local text = UI.outlined(bb, "Megalodon", { Size = UDim2.new(1, 0, 0, 20), TextColor3 = RED })
	local track = UI.frame(bb, { Size = UDim2.new(1, 0, 0, 16), Position = UDim2.fromOffset(0, 26), BackgroundColor3 = T.navyDark })
	UI.corner(track, 8)
	UI.stroke(track, T.white, 2)
	local fill = UI.frame(track, { Size = UDim2.fromScale(1, 1), BackgroundColor3 = RED })
	UI.corner(fill, 8)
	return { anchor = anchor, fill = fill, text = text }
end

local function tick()
	local sh, hp, max = current()
	local hrp = myRoot()
	if not sh then
		if bar then
			bar.anchor:Destroy()
			bar = nil
		end
		button.Visible = false
		Guide.set("boss", nil)
		if shownSub ~= "" then
			shownSub = ""
			Notify.clear("boss")
		end
		return
	end
	bar = bar or buildBar()
	local b = bar :: any
	local k = math.clamp(hp / math.max(max, 1), 0, 1)
	b.anchor.Position = Vector3.new(sh.pos.X, Config.Boss.length * 0.35 + 6, sh.pos.Z)
	b.fill.Size = UDim2.fromScale(k, 1)
	local d = hrp and Vector2.new(sh.pos.X - hrp.Position.X, sh.pos.Z - hrp.Position.Z).Magnitude or math.huge
	local inRange = d <= Config.Boss.range
	button.Visible = inRange
	if inRange then
		local wait = readyAt - os.clock()
		button.BackgroundColor3 = wait > 0 and T.navyLight or RED
	end
	Guide.set("boss", not inRange and Vector3.new(sh.pos.X, 4, sh.pos.Z) or nil, "Megalodon")
	local sub = ("Harpoon it %d+ times for a Legendary · %d%% left"):format(Config.Boss.minHits, math.ceil(k * 100))
	if sub ~= shownSub then
		shownSub = sub
		Notify.banner("The Megalodon is up", { key = "boss", sticky = true, priority = 2, color = RED, sub = sub })
	end
end

local function throw()
	if not button.Visible or os.clock() < readyAt then
		return
	end
	readyAt = os.clock() + Config.Boss.cooldown
	State.action("harpoon")
end

-- a spear from the thrower to the boss
local function spear(by: number, id: number)
	local sh = SharkView.get(id)
	local from = Players:GetPlayerByUserId(by)
	local char = from and from.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not (sh and hrp) then
		return
	end
	local a = hrp.Position + Vector3.new(0, 2, 0)
	local b = Vector3.new(sh.pos.X, 3, sh.pos.Z)
	if (a - b).Magnitude > 400 then
		return
	end
	local p = Instance.new("Part")
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
	p.Size = Vector3.new(0.4, 0.4, 7)
	p.Material = Enum.Material.Metal
	p.Color = Color3.fromRGB(200, 205, 215)
	p.CFrame = CFrame.lookAt(a, b)
	p.Parent = Workspace
	local tip = Instance.new("Part")
	tip.Anchored, tip.CanCollide, tip.CanQuery, tip.CanTouch = true, false, false, false
	tip.Size = Vector3.new(0.8, 0.8, 1.4)
	tip.Material = Enum.Material.Neon
	tip.Color = RED
	tip.CFrame = p.CFrame * CFrame.new(0, 0, -3.8)
	tip.Parent = p
	local weld = Instance.new("WeldConstraint")
	weld.Part0, weld.Part1 = p, tip
	weld.Parent = p
	tip.Anchored = false
	local dur = math.clamp((a - b).Magnitude / 220, 0.12, 0.5)
	TweenService:Create(p, TweenInfo.new(dur, Enum.EasingStyle.Linear), { CFrame = CFrame.lookAt(b, b + (b - a).Unit) }):Play()
	task.delay(dur, function()
		p:Destroy()
		Fx.splash(b, 0.8)
		Fx.sparkle(b + Vector3.new(0, 4, 0), RED, 8)
		if by == player.UserId then
			Fx.sound("chomp", 0.5, 1.6, b)
		end
	end)
end

function Boss.start()
	local gui = Instance.new("ScreenGui")
	gui.Name = "Harpoon"
	gui.ResetOnSpawn = false
	gui.Parent = player:WaitForChild("PlayerGui")
	UI.autoScale(gui)
	button = UI.button(gui, "Harpoon", RED, throw, { Size = UDim2.fromOffset(190, 54), Position = UDim2.new(0.5, 105, 1, -150),
		AnchorPoint = Vector2.new(0, 1), Visible = false })
	UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and (input.KeyCode == Enum.KeyCode.F or input.KeyCode == Enum.KeyCode.ButtonX) then
			throw()
		end
	end)
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc >= 0.1 then
			acc = 0
			tick()
		end
	end)
	Remotes.get("SharkEvent").OnClientEvent:Connect(function(kind, data)
		data = data or {}
		if kind == "boss" then
			if data.world == myWorld() then
				Notify.banner("The Megalodon surfaced", { key = "bossUp", color = RED, priority = 3, time = 5,
					sub = ("Over %s. Everyone harpoon it for a Legendary"):format(tostring(data.zone)) })
				Fx.sound("sharkAlarm", 0.9)
				Fx.shake(1.2)
				Fx.edgeWarn(Vector3.new(data.x, 0, data.z), 1.5, RED)
			end
		elseif kind == "harpoon" then
			spear(data.by, data.id)
		elseif kind == "bossDown" then
			local sh = SharkView.get(data.id)
			if data.world == myWorld() then
				if sh then
					Fx.confetti(Vector3.new(sh.pos.X, 6, sh.pos.Z), { RED, T.gold, Color3.new(1, 1, 1) })
					Fx.splash(Vector3.new(sh.pos.X, 0.5, sh.pos.Z), 3)
				end
				Fx.sound("legendary", 0.9)
				Notify.banner("The Megalodon is down", { color = T.gold, priority = 3, time = 5,
					sub = ("Everyone with %d+ harpoon hits gets a Legendary"):format(Config.Boss.minHits) })
			end
		elseif kind == "bossGone" then
			if data.world == myWorld() then
				Notify.toast("The Megalodon dove back down", RED)
			end
		end
	end)
	Remotes.get("Notify").OnClientEvent:Connect(function(kind)
		if kind == "bossReward" then
			Notify.toast("Your Legendary from the Megalodon", T.gold)
		end
	end)
end

return Boss
