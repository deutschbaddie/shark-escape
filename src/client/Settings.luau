-- The Settings panel (the gear beside the shark timer on the HUD):
--   Slow Mode   caps your speed so the water is easier to steer (server action)
--   Music       the Music sound group on / off
--   Sounds      effects, UI clicks and ambience on / off
--   Fewer details  side stud textures off (Perf.luau; on by default on phones)
-- Music / Sounds are this session's choice (SoundGroup volume 0 or 1).

local Players = game:GetService("Players")

local UI = require(script.Parent.UI)
local State = require(script.Parent.State)
local Sounds = require(script.Parent.Sounds)
local Perf = require(script.Parent.Perf)

local Settings = {}
local T = UI.T
local SP = UI.SP
local player = Players.LocalPlayer

local gui: ScreenGui
local win: Frame? = nil
local setSlow: ((boolean) -> ())? = nil
local prefs = { music = true, sounds = true }

local SOUND_GROUPS = { "Effects", "UI", "Ambience" }

local function applySound()
	Sounds.group("Music").Volume = prefs.music and 1 or 0
	for _, name in SOUND_GROUPS do
		Sounds.group(name).Volume = prefs.sounds and 1 or 0
	end
end

function Settings.close()
	if win then
		win:Destroy()
		win = nil
		setSlow = nil
	end
end

function Settings.open()
	if win then
		return
	end
	local f, body = UI.window(gui, "Settings", T.blue, Vector2.new(440, 420), Settings.close, "Settings")
	win = f
	local list = Instance.new("UIListLayout")
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, SP[3])
	list.Parent = body

	local function row(order: number, caption: string, hint: string, on: boolean, onChange: (boolean) -> ()): (boolean) -> ()
		local card = UI.card(body, nil, { Size = UDim2.new(1, 0, 0, 66), LayoutOrder = order })
		local _, set = UI.toggle(card, caption, on, onChange, { Size = UDim2.new(1, -SP[4] * 2, 0, 40), Position = UDim2.fromOffset(SP[4], SP[1]) })
		UI.label(card, "meta", hint, { Size = UDim2.new(1, -120, 0, 18), Position = UDim2.new(0, SP[4], 1, -SP[1]), AnchorPoint = Vector2.new(0, 1),
			TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = T.mute })
		return set
	end

	local d = State.data
	setSlow = row(1, "Slow Mode", "Caps your speed: easier to steer", d ~= nil and d.slow == true, function(on)
		State.action("slowMode", on)
	end)
	row(2, "Music", "Background music", prefs.music, function(on)
		prefs.music = on
		applySound()
	end)
	row(3, "Sounds", "Effects, clicks and ambience", prefs.sounds, function(on)
		prefs.sounds = on
		applySound()
	end)
	row(4, "Fewer details", "Runs smoother on phones", Perf.enabled(), Perf.set)
end

function Settings.toggle()
	if win then
		Settings.close()
	else
		Settings.open()
	end
end

function Settings.start()
	gui = Instance.new("ScreenGui")
	gui.Name = "Settings"
	UI.hideInCutscenes(gui)
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 8
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = player:WaitForChild("PlayerGui")
	UI.autoScale(gui, Vector2.new(460, 440))
	applySound()
	local lastSlow: boolean? = nil
	-- keep the Slow Mode switch in step with the server
	State.Changed:Connect(function(data)
		local on = data.slow == true
		if setSlow and on ~= lastSlow then
			setSlow(on)
		end
		lastSlow = on
	end)
end

return Settings
