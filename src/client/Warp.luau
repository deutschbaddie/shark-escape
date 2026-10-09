-- Zone warp: the signpost on the sand opens this menu; pick any zone you've
-- unlocked in this world and the server drops you at its start (Game
-- actions.warp). Saves the long ride out once the ocean gets big.

local Shared = game.ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local UI = require(script.Parent.UI)
local Fx = require(script.Parent.Fx)
local State = require(script.Parent.State)
local Prompts = require(script.Parent.Prompts)
local Shop = require(script.Parent.Shop)

local Warp = {}
local T = UI.T

function Warp.open()
	local d = State.data
	if not d then
		return
	end
	local _, body = Shop.window("Zone Warp", T.blue, Vector2.new(560, 470), "Island")
	local list = Shop.list(body, { Size = UDim2.new(1, 8, 1, 0), Position = UDim2.fromOffset(-4, 0) }, 8)
	for i, zone in Config.worldZones(d.world) do
		local open = d.speed >= zone.gate
		local color = open and zone.water:Lerp(T.navy, 0.35) or UI.dark(T.navyLight, 0.3)
		local b = UI.button(list, "", color, function()
			if open then
				State.action("warp", zone.id)
				Shop.closeAll()
			end
		end, { Size = UDim2.new(1, -8, 0, 58), LayoutOrder = i })
		UI.icon(b, zone.id, { Size = UDim2.fromOffset(44, 44), Position = UDim2.new(0, 10, 0.5, 0), AnchorPoint = Vector2.new(0, 0.5), ZIndex = b.ZIndex + 2 })
		local l = b:FindFirstChild("Label") :: TextLabel
		l.Text = zone.name
		l.TextXAlignment = Enum.TextXAlignment.Left
		l.Size = UDim2.new(0.6, 0, 0.55, 0)
		l.Position = UDim2.new(0, 64, 0.5, 0)
		l.AnchorPoint = Vector2.new(0, 0.5)
		UI.label(b, "meta", open and "WARP" or ("%s speed"):format(UI.short(zone.gate)), {
			Size = UDim2.new(0.3, -12, 0.5, 0), Position = UDim2.new(1, -12, 0.5, 0), AnchorPoint = Vector2.new(1, 0.5),
			TextXAlignment = Enum.TextXAlignment.Right, ZIndex = b.ZIndex + 2, TextColor3 = open and T.white or T.mute })
	end
end

function Warp.start()
	Prompts.Triggered:Connect(function(prompt)
		if prompt.Name == "Warp" then
			Warp.open()
		end
	end)
	Remotes.get("Notify").OnClientEvent:Connect(function(kind, data)
		if kind == "warped" and typeof(data) == "table" then
			local zone = Config.zoneById(data.zone)
			Fx.flash(Color3.new(1, 1, 1), 0.4, 0.2)
			Fx.sound("rideKick", 0.6, 0.9)
			if zone then
				Fx.bigWord(zone.name:upper(), zone.water:Lerp(Color3.new(1, 1, 1), 0.4), 1)
			end
		end
	end)
end

return Warp
