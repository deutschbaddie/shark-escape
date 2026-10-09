-- Treasure chests (server/Treasure.luau) as this player sees them: a banner
-- and the guide arrow when one washes up in your world, the prize moment
-- if you get there first, and a note when someone else beats you to it.

local Players = game:GetService("Players")

local Shared = game.ReplicatedStorage.Shared
local Remotes = require(Shared.Remotes)
local UI = require(script.Parent.UI)
local Fx = require(script.Parent.Fx)
local Notify = require(script.Parent.Notify)
local Guide = require(script.Parent.Guide)
local State = require(script.Parent.State)

local Treasure = {}
local player = Players.LocalPlayer

local GOLD = Color3.fromRGB(255, 200, 40)
local liveWorld: number? = nil -- the world with a chest waiting

local function myWorld(): number
	local d = State.data
	return d and d.world or 1
end

local function clear()
	Guide.set("treasure", nil)
	Notify.clear("treasure")
end

function Treasure.start()
	Remotes.get("Notify").OnClientEvent:Connect(function(kind, data)
		if kind ~= "treasure" or typeof(data) ~= "table" then
			return
		end
		if data.kind == "spawn" then
			liveWorld = data.world
			if data.world ~= myWorld() then
				return
			end
			local at = Vector3.new(data.x, data.y + 3, data.z)
			Guide.set("treasure", at, "Treasure")
			Notify.banner("TREASURE CHEST!", { key = "treasure", color = GOLD, priority = 2, time = data.quiet and 3 or 6,
				sub = ("Washed up in %s. First one there wins it!"):format(tostring(data.zone)) })
			if not data.quiet then
				Fx.sound("discover", 0.8)
			end
		elseif data.kind == "won" then
			liveWorld = nil
			clear()
			local pos = Vector3.new(data.x, data.y, data.z)
			Fx.confetti(pos + Vector3.new(0, 3, 0), { GOLD, Color3.new(1, 1, 1), Color3.fromRGB(255, 120, 60) })
			Fx.sound("legendary", 0.8)
			local sub = ("+$%s  +%s speed"):format(UI.short(data.coins), UI.short(data.speed))
			if data.creature then
				sub ..= ("  +%s creature!"):format(tostring(data.creature))
			end
			Notify.takeover("TREASURE!", sub, GOLD, 2)
		elseif data.kind == "claimed" or data.kind == "gone" then
			if data.world == liveWorld then
				liveWorld = nil
			end
			if data.world == myWorld() then
				clear()
				if data.kind == "claimed" and data.userId ~= player.UserId then
					Notify.toast(("%s found the treasure"):format(tostring(data.by)), GOLD)
				end
			end
		end
	end)
	-- through the portal: the other world's chest isn't yours to chase
	State.Changed:Connect(function(d)
		if liveWorld and d.world ~= liveWorld then
			Guide.set("treasure", nil)
		end
	end)
end

return Treasure
