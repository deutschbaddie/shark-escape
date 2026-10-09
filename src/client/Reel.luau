-- Legendary reel (server: Bubbles "reel"): a timing bar above the HUD. A
-- marker sweeps back and forth; hit REEL (tap, click, Space or E) while
-- it's inside the green band. 3 good hits lands the Legendary; 2 misses or
-- running out of time and it slips away. Its shark is charging meanwhile.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = game.ReplicatedStorage.Shared
local Remotes = require(Shared.Remotes)
local UI = require(script.Parent.UI)
local Fx = require(script.Parent.Fx)
local Notify = require(script.Parent.Notify)
local State = require(script.Parent.State)

local Reel = {}
local player = Players.LocalPlayer
local T = UI.T

local HITS, MISSES = 3, 2
local active = false

local function play(seconds: number, name: string)
	if active then
		return
	end
	active = true
	local gui = Instance.new("ScreenGui")
	gui.Name = "Reel"
	gui.ResetOnSpawn = false
	gui.Parent = player:WaitForChild("PlayerGui")
	UI.autoScale(gui)
	local panel = UI.frame(gui, { Size = UDim2.fromOffset(420, 112), Position = UDim2.new(0.5, 0, 1, -215), AnchorPoint = Vector2.new(0.5, 1),
		BackgroundTransparency = 1 })
	UI.outlined(panel, ("Reel in the %s"):format(name), { Size = UDim2.new(0.75, 0, 0, 26), TextColor3 = T.gold,
		TextXAlignment = Enum.TextXAlignment.Left })
	local track = UI.frame(panel, { Size = UDim2.new(1, 0, 0, 30), Position = UDim2.fromOffset(0, 34), BackgroundColor3 = T.navyDark })
	UI.corner(track, 15)
	UI.stroke(track, T.white, 2)
	local band = UI.frame(track, { Size = UDim2.fromScale(0.22, 1), BackgroundColor3 = T.green, BackgroundTransparency = 0.15 })
	UI.corner(band, 15)
	local marker = UI.frame(track, { Size = UDim2.new(0, 8, 1, 10), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0, 0.5),
		BackgroundColor3 = T.white, ZIndex = track.ZIndex + 3 })
	UI.corner(marker, 4)
	local status = UI.label(panel, "body", "", { Size = UDim2.new(0.25, 0, 0, 26), Position = UDim2.fromScale(0.75, 0),
		TextXAlignment = Enum.TextXAlignment.Right })
	local hits, misses = 0, 0
	local t0 = os.clock()
	local speed = 1.1 -- sweeps per second (gets faster each hit)
	local phase = 0
	local done = false

	local function newBand()
		band.Position = UDim2.fromScale(0.1 + math.random() * 0.68, 0)
	end
	newBand()

	local function finish(ok: boolean)
		if done then
			return
		end
		done = true
		State.action("reel", ok)
		gui:Destroy()
		active = false
	end

	local function where(): number
		return 0.5 - 0.5 * math.cos(phase * math.pi)
	end

	local function hit()
		if done then
			return
		end
		local x = where()
		local a = band.Position.X.Scale
		if x >= a and x <= a + band.Size.X.Scale then
			hits += 1
			speed += 0.35
			Fx.sound("uiClick", 0.8, 1 + hits * 0.15)
			if hits >= HITS then
				finish(true)
				return
			end
			newBand()
		else
			misses += 1
			Fx.sound("uiError", 0.6)
			Fx.shake(0.4)
			if misses >= MISSES then
				finish(false)
				return
			end
		end
	end

	UI.button(panel, "Reel", T.green, hit, { Size = UDim2.fromOffset(170, 44), Position = UDim2.new(0.5, 0, 1, 0), AnchorPoint = Vector2.new(0.5, 1) })
	local conns = {}
	conns[#conns + 1] = UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and (input.KeyCode == Enum.KeyCode.Space or input.KeyCode == Enum.KeyCode.E or input.KeyCode == Enum.KeyCode.ButtonA) then
			hit()
		end
	end)
	conns[#conns + 1] = RunService.RenderStepped:Connect(function(dt)
		if done then
			for _, c in conns do
				c:Disconnect()
			end
			return
		end
		phase += dt * speed
		marker.Position = UDim2.fromScale(where(), 0.5)
		local left = seconds - (os.clock() - t0)
		status.Text = ("%d / %d · %ds"):format(hits, HITS, math.max(0, math.ceil(left)))
		if left <= 0 then
			finish(false)
		end
	end)
	-- bitten mid-reel: it's gone
	conns[#conns + 1] = Remotes.get("Notify").OnClientEvent:Connect(function(kind)
		if kind == "lost" or kind == "spat" then
			finish(false)
		end
	end)
end

Reel.play = play -- (the UI preview opens it directly)

function Reel.start()
	Remotes.get("Notify").OnClientEvent:Connect(function(kind, data)
		if kind == "reel" and typeof(data) == "table" then
			play(data.time or 7, tostring(data.name))
		elseif kind == "slipped" and typeof(data) == "table" then
			Notify.toast(("The %s slipped away"):format(tostring(data.name)), T.red)
		end
	end)
end

return Reel
