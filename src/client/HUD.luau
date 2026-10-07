-- The always-on screen. Rule: one obvious next thing to do, big and tappable.
--   top-center: SPEED (the title stat) + next zone goal bar
--   top-left:   coins, shields, timers
--   bottom:     NEXT RIDE button (one tap buys when affordable)
--   right:      Rides / Shop / Rebirth

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
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

local HUD = {}
local C = UI.C
local player = Players.LocalPlayer

local gui: ScreenGui
local speedLabel: TextLabel
local gainLabel: TextLabel
local coinsLabel: TextLabel
local extrasLabel: TextLabel
local goalFill: Frame
local goalText: TextLabel
local goalCard: Frame
local rideBtn: TextButton
local rideIcon: TextLabel
local rideName: TextLabel
local rideSub: TextLabel
local rideFill: Frame
local carryChip: TextLabel
local hintLabel: TextLabel
local toastHolder: Frame
local alertLabel: TextLabel
local vignette: Frame
local buttons: Frame
local shopBtn: TextButton
local rebirthBtn: TextButton
local stopRidePulse: (() -> ())? = nil

HUD.onRides = nil :: (() -> ())?
HUD.onShop = nil :: (() -> ())?

----------------------------------------------------------------- build
local function card(parent: Instance, size: UDim2, pos: UDim2, anchor: Vector2?): Frame
	local f = UI.frame(parent, { Size = size, Position = pos, AnchorPoint = anchor or Vector2.zero })
	UI.corner(f, 18)
	UI.stroke(f, C.ink, 3)
	return f
end

local function progressBar(parent: Instance, color: Color3): (Frame, Frame)
	local back = UI.frame(parent, { Size = UDim2.new(1, -16, 0, 12), Position = UDim2.new(0, 8, 1, -18), BackgroundColor3 = Color3.fromRGB(226, 232, 250) })
	UI.corner(back, 6)
	local fill = UI.frame(back, { Size = UDim2.fromScale(0, 1), BackgroundColor3 = color })
	UI.corner(fill, 6)
	return back, fill
end

local function build()
	gui = Instance.new("ScreenGui")
	gui.Name = "HUD"
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = player:WaitForChild("PlayerGui")
	local scale = Instance.new("UIScale")
	scale.Parent = gui
	local function rescale()
		local v = Workspace.CurrentCamera.ViewportSize
		scale.Scale = math.clamp(math.min(v.X / 900, v.Y / 520), 0.62, 1.25)
	end
	rescale()
	Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(rescale)

	-- SPEED
	local sp = card(gui, UDim2.fromOffset(280, 78), UDim2.new(0.5, 0, 0, 6), Vector2.new(0.5, 0))
	sp.BackgroundColor3 = C.blue
	speedLabel = UI.outlined(sp, "⚡ 0", { Size = UDim2.new(1, -16, 0, 50), Position = UDim2.fromOffset(8, 2) })
	gainLabel = UI.outlined(sp, "+1 SPEED / SEC", { Size = UDim2.new(1, -16, 0, 20), Position = UDim2.new(0, 8, 1, -24), TextColor3 = C.gold })

	-- goal bar
	goalCard = card(gui, UDim2.fromOffset(300, 52), UDim2.new(0.5, 0, 0, 92), Vector2.new(0.5, 0))
	goalText = UI.text(goalCard, "", { Size = UDim2.new(1, -16, 0, 24), Position = UDim2.fromOffset(8, 4) })
	local _, gf = progressBar(goalCard, C.pink)
	goalFill = gf

	-- coins + extras
	local cc = card(gui, UDim2.fromOffset(176, 50), UDim2.fromOffset(12, 6))
	cc.BackgroundColor3 = C.gold
	coinsLabel = UI.outlined(cc, "💰 0", { Size = UDim2.new(1, -16, 1, -10), Position = UDim2.fromOffset(8, 5) })
	extrasLabel = UI.outlined(gui, "", { Size = UDim2.fromOffset(240, 26), Position = UDim2.fromOffset(14, 62), TextXAlignment = Enum.TextXAlignment.Left })

	-- next ride: the one big button
	rideBtn = UI.button(gui, "", C.blue, function()
		local d = State.data
		local nxt = d and HUD.nextRide(d)
		if nxt and d.coins >= nxt.price then
			State.action("buyRide", nxt.id)
		elseif HUD.onRides then
			HUD.onRides()
		end
	end, { Size = UDim2.fromOffset(320, 84), Position = UDim2.new(0.5, 0, 1, -14), AnchorPoint = Vector2.new(0.5, 1) })
	rideBtn:FindFirstChildOfClass("UIPadding"):Destroy()
	rideIcon = UI.text(rideBtn, "🦆", { Size = UDim2.fromOffset(64, 64), Position = UDim2.fromOffset(8, 10) })
	rideName = UI.outlined(rideBtn, "", { Size = UDim2.new(1, -90, 0, 30), Position = UDim2.fromOffset(80, 8), TextXAlignment = Enum.TextXAlignment.Left })
	rideSub = UI.outlined(rideBtn, "", { Size = UDim2.new(1, -90, 0, 20), Position = UDim2.fromOffset(80, 38), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = C.gold })
	local rb = UI.frame(rideBtn, { Size = UDim2.new(1, -96, 0, 10), Position = UDim2.new(0, 80, 1, -18), BackgroundColor3 = Color3.fromRGB(20, 40, 120) })
	UI.corner(rb, 5)
	rideFill = UI.frame(rb, { Size = UDim2.fromScale(0, 1), BackgroundColor3 = C.gold })
	UI.corner(rideFill, 5)

	carryChip = UI.outlined(gui, "", { Size = UDim2.fromOffset(420, 30), Position = UDim2.new(0.5, 0, 1, -106), AnchorPoint = Vector2.new(0.5, 1), Visible = false })
	hintLabel = UI.outlined(gui, "", { Size = UDim2.fromOffset(520, 44), Position = UDim2.new(0.5, 0, 0, 152), AnchorPoint = Vector2.new(0.5, 0), Visible = false, TextColor3 = C.white })

	-- side buttons
	buttons = UI.frame(gui, { Size = UDim2.fromOffset(84, 260), Position = UDim2.new(1, -10, 0.5, -40), AnchorPoint = Vector2.new(1, 0.5), BackgroundTransparency = 1 })
	local list = Instance.new("UIListLayout")
	list.Padding = UDim.new(0, 10)
	list.HorizontalAlignment = Enum.HorizontalAlignment.Right
	list.Parent = buttons
	UI.button(buttons, "🛟\nRides", C.sky, function()
		if HUD.onRides then
			HUD.onRides()
		end
	end, { Size = UDim2.fromOffset(78, 78), LayoutOrder = 1 })
	shopBtn = UI.button(buttons, "🛒\nShop", C.pink, function()
		if HUD.onShop then
			HUD.onShop()
		end
	end, { Size = UDim2.fromOffset(78, 78), LayoutOrder = 2, Visible = false })
	rebirthBtn = UI.button(buttons, "🔁\nRebirth", C.green, function()
		State.action("rebirth")
	end, { Size = UDim2.fromOffset(78, 78), LayoutOrder = 3, Visible = false })

	-- toasts
	toastHolder = UI.frame(gui, { Size = UDim2.fromOffset(460, 200), Position = UDim2.new(0.5, 0, 0, 200), AnchorPoint = Vector2.new(0.5, 0), BackgroundTransparency = 1 })
	local tl = Instance.new("UIListLayout")
	tl.Padding = UDim.new(0, 6)
	tl.HorizontalAlignment = Enum.HorizontalAlignment.Center
	tl.Parent = toastHolder

	-- shark alert
	vignette = UI.frame(Fx.screen(), { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Name = "Vignette", ZIndex = 2 })
	for i, spec in { { UDim2.new(1, 0, 0.22, 0), UDim2.fromScale(0, 0), 90 }, { UDim2.new(1, 0, 0.22, 0), UDim2.fromScale(0, 0.78), -90 },
		{ UDim2.new(0.16, 0, 1, 0), UDim2.fromScale(0, 0), 0 }, { UDim2.new(0.16, 0, 1, 0), UDim2.fromScale(0.84, 0), 180 } } do
		local f = UI.frame(vignette, { Size = spec[1], Position = spec[2], BackgroundColor3 = Color3.fromRGB(255, 30, 50), BackgroundTransparency = 0 })
		local g = Instance.new("UIGradient")
		g.Rotation = spec[3]
		g.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(1, 1) })
		g.Parent = f
	end
	vignette.Visible = false
	alertLabel = UI.outlined(gui, "", { Size = UDim2.fromOffset(560, 60), Position = UDim2.new(0.5, 0, 0, 152), AnchorPoint = Vector2.new(0.5, 0), Visible = false, TextColor3 = C.red })
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

function HUD.toast(text: string, color: Color3?, duration: number?)
	local t = UI.frame(toastHolder, { Size = UDim2.fromOffset(440, 40), BackgroundColor3 = color or C.ink })
	UI.corner(t, 12)
	UI.stroke(t, C.ink, 2)
	UI.outlined(t, text, { Size = UDim2.new(1, -16, 1, -8), Position = UDim2.fromOffset(8, 4) })
	UI.pop(t, 1.25)
	task.delay(duration or 2.6, function()
		TweenService:Create(t, TweenInfo.new(0.25), { BackgroundTransparency = 1 }):Play()
		task.wait(0.25)
		t:Destroy()
	end)
	local kids = toastHolder:GetChildren()
	local frames = {}
	for _, k in kids do
		if k:IsA("Frame") then
			table.insert(frames, k)
		end
	end
	if #frames > 3 then
		frames[1]:Destroy()
	end
end

function HUD.hint(text: string?)
	hintLabel.Visible = text ~= nil and not alertLabel.Visible
	if text and hintLabel.Text ~= text then
		hintLabel.Text = text
		UI.pop(hintLabel, 1.2)
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

----------------------------------------------------------------- render state
local lastSpeed = -1
local function render(d: any)
	speedLabel.Text = "⚡ " .. UI.short(d.speed)
	if math.floor(d.speed) ~= lastSpeed then
		if lastSpeed >= 0 then
			UI.pop(speedLabel, 1.08)
		end
		lastSpeed = math.floor(d.speed)
	end
	gainLabel.Text = ("+%s SPEED / SEC"):format(UI.short(d.gain))
	coinsLabel.Text = "💰 " .. UI.short(d.coins)
	local extras = {}
	if d.shields > 0 then
		table.insert(extras, "🛡️" .. d.shields)
	end
	if d.boostLeft > 0 then
		table.insert(extras, "⏩" .. UI.time(d.boostLeft))
	end
	if d.luckLeft > 0 then
		table.insert(extras, "🧪" .. UI.time(d.luckLeft))
	end
	table.insert(extras, ("🐟%d/%d"):format(#d.tank, d.slots))
	extrasLabel.Text = table.concat(extras, "  ")

	-- goal: next zone gate, or rebirth
	local gate = Config.nextGate(d.speed)
	if gate then
		local prevGate = 0
		for _, z in Config.Zones do
			if z.gate <= d.speed then
				prevGate = z.gate
			end
		end
		goalText.Text = ("🔒 %s  %s / %s"):format(gate.name, UI.short(d.speed), UI.short(gate.gate))
		goalFill.Size = UDim2.fromScale(math.clamp((d.speed - prevGate) / (gate.gate - prevGate), 0, 1), 1)
		goalFill.BackgroundColor3 = C.pink
	else
		local ready = d.speed >= Config.Rebirth.speed
		goalText.Text = ready and "🔁 REBIRTH READY!" or "🏆 Every zone unlocked!"
		goalFill.Size = UDim2.fromScale(1, 1)
		goalFill.BackgroundColor3 = C.green
	end
	rebirthBtn.Visible = d.speed >= Config.Rebirth.speed
	shopBtn.Visible = d.playtime >= Config.SHOP_UNLOCK_SECONDS or d.rides.Duck == true

	-- next ride
	local nxt = HUD.nextRide(d)
	rideBtn.Visible = nxt ~= nil
	if nxt then
		local afford = d.coins >= nxt.price
		rideIcon.Text = nxt.icon
		rideName.Text = afford and ("TAP TO BUY " .. nxt.name:upper() .. "!") or ("Next: " .. nxt.name)
		rideSub.Text = ("+%d speed/sec  ·  💰 %s / %s"):format(nxt.gain or 0, UI.short(math.min(d.coins, nxt.price)), UI.short(nxt.price))
		rideFill.Size = UDim2.fromScale(math.clamp(d.coins / nxt.price, 0, 1), 1)
		rideBtn.BackgroundColor3 = afford and C.green or C.blue
		HUD.pulseRide(afford)
	end

	-- carrying
	if d.carrying then
		local r = Config.rarity(d.carrying.r)
		carryChip.Visible = true
		carryChip.TextColor3 = r.color
		carryChip.Text = ("%s %s%s → bring it to your dock! 🏠"):format(r.icon, d.carrying.m and (d.carrying.m .. " ") or "", r.species)
	else
		carryChip.Visible = false
	end
end

----------------------------------------------------------------- notifications
local handlers: { [string]: (any) -> () } = {}

local function myPos(): Vector3?
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	return hrp and hrp.Position
end

handlers.grab = function(d)
	local r = Config.rarity(d.r)
	local pos = myPos()
	if pos then
		Fx.sparkle(pos + Vector3.new(0, 3, 0), r.color, 20 + r.index * 12)
		Fx.popup3D(pos + Vector3.new(0, 5, 0), ("+%s/s"):format(UI.short(d.v)), r.color)
	end
	Fx.sound("grab", 0.6, 1 + r.index * 0.05)
	if d.lucky then
		Fx.bigWord("🍀 LUCKY! " .. d.r:upper(), C.green, 1.2)
	elseif d.pity then
		Fx.bigWord("✨ RARE " .. r.species:upper() .. "!", r.color, 1.2)
	elseif r.index >= 3 then
		Fx.bigWord(d.r:upper() .. "!", r.color, 1.1)
	end
	if r.index >= 4 then
		Fx.shake(1.5)
		Fx.sound("legendary", 0.8)
	end
	HUD.toast(("%s Got %s%s! (+%s/s)"):format(r.icon, d.m and (d.m .. " ") or "", r.species, UI.short(d.v)), r.color)
end

handlers.deposit = function(d)
	local r = Config.rarity(d.r)
	local data = State.data
	if data and data.plot > 0 then
		local tank = Layout.tankPos(Layout.Plots[data.plot])
		Fx.sparkle(tank + Vector3.new(0, 5, 0), r.color, 40)
		Fx.popup3D(tank + Vector3.new(0, 10, 0), ("+%s 💰/s"):format(UI.short(d.v)), C.gold, true)
	end
	if d.replaced then
		HUD.toast(("Swapped out a %s (+%s 💰)"):format(Config.rarity(d.replaced).species, UI.short(d.sold or 0)), C.blue)
	end
end

handlers.sold = function(d)
	HUD.toast(("Tank full! Sold %s for %s 💰"):format(Config.rarity(d.r).species, UI.short(d.sold)), C.blue)
end

handlers.collect = function(d)
	local pos = myPos()
	if pos then
		Fx.confetti(pos, { C.gold, Color3.fromRGB(255, 240, 150) })
		Fx.popup3D(pos + Vector3.new(0, 5, 0), "+" .. UI.short(d.amount) .. " 💰", C.gold, true)
	end
	Fx.sound("coin", 0.7)
	UI.pop(coinsLabel, 1.3)
end

handlers.ride = function(d)
	local ride = Config.ride(d.id)
	local pos = myPos()
	if pos then
		Fx.confetti(pos)
		Fx.splash(Vector3.new(pos.X, 0.5, pos.Z), 1.2)
	end
	Fx.sound("buy", 0.8)
	Fx.bigWord(("%s NEW RIDE!"):format(ride and ride.icon or ""), C.gold, 1.2)
	HUD.toast(("Now gaining +%s speed every second!"):format(UI.short(d.gain)), C.green)
	UI.pop(gainLabel, 1.5)
end

handlers.slot = function(d)
	HUD.toast(("🐟 Tank now holds %d!"):format(d.slots), C.green)
end

handlers.unlock = function(d)
	local zone = Config.zoneById(d.zone)
	if zone then
		Fx.bigWord("🔓 " .. zone.name:upper() .. "!", C.gold, 1.6)
		HUD.toast(("%s unlocked - %s sharks live there!"):format(zone.name, zone.shark), C.pink, 3.5)
		local pos = myPos()
		if pos then
			Fx.confetti(pos)
		end
	end
end

handlers.gate = function(d)
	Fx.bigWord(("🔒 NEED %s SPEED"):format(UI.short(d.need)), C.red, 1.2)
	Fx.shake(1)
end

handlers.lost = function(d)
	HUD.toast(("💔 The shark ate your %s!"):format(Config.rarity(d.r).species), C.red, 3)
end

handlers.spat = function()
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
	Fx.bigWord("PTOOEY!", C.sky, 1)
	local d = State.data
	if d and d.playtime >= Config.SHOP_UNLOCK_SECONDS and Config.Products.Shield.id ~= 0 then
		local b = UI.button(gui, "🛡️ Shield next time  R$" .. Config.Products.Shield.price, C.sky, function()
			MarketplaceService:PromptProductPurchase(player, Config.Products.Shield.id)
		end, { Size = UDim2.fromOffset(300, 48), Position = UDim2.new(0.5, 0, 1, -112), AnchorPoint = Vector2.new(0.5, 1) })
		task.delay(6, function()
			b:Destroy()
		end)
	end
end

handlers.shield = function()
	HUD.toast("🛡️ Your shield blocked the bite!", C.sky)
end

handlers.rebirth = function(d)
	Fx.bigWord("🔁 REBIRTH!", C.green, 1.6)
	Fx.flash(Color3.new(1, 1, 1), 0.8, 0)
	HUD.toast(("Permanent x%s speed gain!"):format(tostring(Config.Rebirth.mult ^ d.rebirths)), C.green, 4)
end

handlers.purchase = function(d)
	Fx.bigWord("🎉 THANK YOU!", C.pink, 1.2)
	HUD.toast(d.name .. " is yours!", C.pink, 3)
	local pos = myPos()
	if pos then
		Fx.confetti(pos)
	end
end

handlers.announce = function(d)
	HUD.toast(d.text, d.color or C.ink, 4)
end

----------------------------------------------------------------- shark phases
local alertToken = 0
local function setAlert(text: string?, color: Color3?)
	alertToken += 1
	alertLabel.Visible = text ~= nil
	if text then
		alertLabel.Text = text
		alertLabel.TextColor3 = color or C.red
		UI.pop(alertLabel, 1.3)
		hintLabel.Visible = false
	end
end

local function myZone(): Config.Zone?
	local pos = myPos()
	return pos and Config.zoneAt(pos.Z)
end

local function onPhase(kind: string, data: any)
	if kind == "warning" then
		local token
		setAlert("🦈 SHARK ATTACK IN 5!")
		token = alertToken
		vignette.Visible = true
		Water.setSafeGlow(true)
		Fx.sound("sharkAlarm", 0.8)
		-- the horizon breach: a shark leaps where you can see it
		local zone = myZone()
		local pos = myPos()
		if zone and pos then
			local cam = Workspace.CurrentCamera
			local look = cam.CFrame.LookVector * Vector3.new(1, 0, 1)
			local dir = look.Magnitude > 0.1 and look.Unit or Vector3.new(0, 0, 1)
			local at = pos + dir * math.max(70, zone.sharkLength * 4)
			local side = Vector3.new(dir.Z, 0, -dir.X)
			SharkView.breach(zone.shark, zone.sharkLength, at - side * zone.sharkLength * 0.8, math.atan2(-side.X, -side.Z))
		end
		task.spawn(function()
			local t0 = os.clock()
			while alertToken == token and os.clock() - t0 < (data.duration or 5) do
				local left = math.ceil((data.duration or 5) - (os.clock() - t0))
				alertLabel.Text = ("🦈 SHARK ATTACK IN %d! GET ON SAND!"):format(left)
				vignette.BackgroundTransparency = 1
				for _, f in vignette:GetChildren() do
					if f:IsA("Frame") then
						f.BackgroundTransparency = 0.3 + 0.4 * (0.5 + 0.5 * math.sin(os.clock() * 10))
					end
				end
				task.wait()
			end
		end)
	elseif kind == "hunt" then
		setAlert("🦈 SHARKS ARE HUNTING! STAY ON SAND!")
		vignette.Visible = true
		Water.setSafeGlow(true)
		Fx.shake(1)
	elseif kind == "clear" then
		local wasOn = vignette.Visible
		vignette.Visible = false
		Water.setSafeGlow(false)
		if wasOn then
			setAlert("✅ SAFE! Sharks are gone", C.green)
			local token = alertToken
			task.delay(2, function()
				if alertToken == token then
					setAlert(nil)
				end
			end)
		else
			setAlert(nil)
		end
	end
end

----------------------------------------------------------------- start
function HUD.start()
	build()
	State.Changed:Connect(render)
	if State.data then
		render(State.data)
	end
	Remotes.get("Notify").OnClientEvent:Connect(function(kind, data)
		local fn = handlers[kind]
		if fn then
			fn(data)
		end
	end)
	Remotes.get("SharkEvent").OnClientEvent:Connect(function(kind, data)
		if kind ~= "bite" then
			onPhase(kind, data or {})
		end
	end)
end

return HUD
