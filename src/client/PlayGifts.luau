-- Playtime gifts (Config.PlayGifts; server: Rewards claimGift). The HUDs put
-- our square in their right column (PlayGifts.square): it counts down to the
-- next free gift, then bounces with CLAIM! and a badge until you tap it.

local RunService = game:GetService("RunService")

local Shared = game.ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local UI = require(script.Parent.UI)
local Fx = require(script.Parent.Fx)
local State = require(script.Parent.State)
local Notify = require(script.Parent.Notify)

local PlayGifts = {}

local holder: GuiObject? = nil
local button: GuiButton? = nil
local timer: TextLabel? = nil
local scale: UIScale? = nil
local pushed = { session = 0, at = 0 } -- server seconds played, and our clock then
local readyTold = 0 -- last gift we announced as ready

local function played(): number
	return pushed.session + (os.clock() - pushed.at)
end

-- a square with a time chip under it (same look as the HUD's boost squares)
function PlayGifts.square(parent: Instance, size: number, order: number): GuiObject
	local h = UI.frame(parent, { Name = "PlayGift", Size = UDim2.fromOffset(size + 4, size + 10), BackgroundTransparency = 1, LayoutOrder = order })
	local b = UI.iconButton(h, "Chest", "", UI.C.gold, function()
		State.action("claimGift")
	end, { Size = UDim2.fromOffset(size, size), Position = UDim2.new(0.5, 0, 0, 0), AnchorPoint = Vector2.new(0.5, 0) })
	local t = UI.outlined(h, "", { Size = UDim2.new(1, 16, 0, 18), Position = UDim2.new(0.5, 0, 1, 2), AnchorPoint = Vector2.new(0.5, 1),
		TextColor3 = UI.C.white, ZIndex = 20 })
	local s = Instance.new("UIScale")
	s.Parent = b
	holder, button, timer, scale = h, b, t, s
	return h
end

local function tick()
	local d = State.data
	if not (d and holder and timer and button) then
		return
	end
	local i = (d.gifts or 0) + 1
	local g = Config.PlayGifts[i]
	holder.Visible = g ~= nil and d.tut >= 5 -- (not during the first-session guide: fewer buttons)
	if not g then
		return
	end
	local left = g.at * 60 - played()
	if left > 0 then
		timer.Text = UI.timeWords(left)
		timer.TextColor3 = UI.C.white
		UI.clearBadge(button)
		if scale then
			scale.Scale = 1
		end
	else
		timer.Text = "Claim"
		timer.TextColor3 = UI.C.gold
		UI.badge(button)
		if scale then
			scale.Scale = 1 + 0.08 * math.abs(math.sin(os.clock() * 4))
		end
		if readyTold < i then
			readyTold = i
			Notify.toast(("Free gift ready: %s!"):format(g.label), UI.C.gold)
		end
	end
end

function PlayGifts.start()
	State.Changed:Connect(function(d)
		if typeof(d.session) == "number" then
			pushed.session, pushed.at = d.session, os.clock()
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
	Remotes.get("Notify").OnClientEvent:Connect(function(kind, data)
		if kind == "gift" and typeof(data) == "table" then
			Notify.takeover("Free gift", tostring(data.text), UI.C.gold, 1.6)
			Fx.sound("discover", 0.8)
			if data.last then
				Notify.toast("That's every gift this session. Thanks for playing!", UI.C.gold)
			end
		end
	end)
end

return PlayGifts
