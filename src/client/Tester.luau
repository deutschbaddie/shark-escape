-- The cutscene + effects tester (dev only): an admin types /srctest (server
-- Admin.luau checks the name) and this panel opens. Every button plays one
-- moment right here with sample data, only on your screen: nothing is
-- saved, given or sent to the server.
-- Cutscenes only take the camera on land (like in the game); at sea you see
-- their in-place version, which is worth testing too.

local Players = game:GetService("Players")

local Shared = game.ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Layout = require(Shared.Layout)
local Remotes = require(Shared.Remotes)
local UI = require(script.Parent.UI)
local Fx = require(script.Parent.Fx)
local Notify = require(script.Parent.Notify)
local Moments = require(script.Parent.Moments)
local Cine = require(script.Parent.Cine)
local SharkView = require(script.Parent.SharkView)

local Tester = {}
local player = Players.LocalPlayer
local T = UI.T

local gui: ScreenGui? = nil

local function root(): BasePart?
	local char = player.Character
	return char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
end

-- a cutscene button: say so when it can't take the camera here
local function cutscene(fn: () -> ())
	return function()
		if not Cine.canPlay() then
			Notify.toast("At sea: this is the in-place version. Stand on land for the cutscene", T.gold)
		end
		fn()
	end
end

local function mythicZone(): string
	local first = Config.worldZones(1)[1]
	return first and first.id or "Lagoon" -- (every zone has a Mythic)
end

local TESTS: { { any } } = { -- { section, label, color, play }
	-- cutscenes
	{ "cut", "Mythic reveal", Config.rarity("Mythic").color, cutscene(function()
		Moments.deposit({ r = "Mythic", z = mythicZone(), v = 1000, active = true })
	end) },
	{ "cut", "New ride", T.gold, cutscene(function()
		Moments.ride({ id = "Duck", gain = 5 })
	end) },
	{ "cut", "Evolve", T.green, cutscene(function()
		Moments.evolve({ rebirths = 1, biome = "The Abyss", zone = "Abyss" }, function() end)
	end) },
	{ "cut", "Megalodon", T.red, cutscene(function()
		local zones = Config.worldZones(1)
		local zone = zones[Config.Boss.zone] or zones[1]
		Moments.boss({ id = -1, world = 1, x = Config.originX(1), z = zone.zStart + zone.length / 2 })
	end) },
	{ "cut", "Shark bite", T.blue, function()
		SharkView.testEaten()
	end },
	-- everyday moments
	{ "fx", "Grab: Common", Config.rarity("Common").color, function()
		Moments.grab({ r = "Common", z = "Reef" })
	end },
	{ "fx", "Grab: Rare", Config.rarity("Rare").color, function()
		Moments.grab({ r = "Rare", z = "Reef" })
	end },
	{ "fx", "Grab: Legendary", Config.rarity("Legendary").color, function()
		Moments.grab({ r = "Legendary", z = "Reef" })
	end },
	{ "fx", "Grab: Mythic", Config.rarity("Mythic").color, function()
		Moments.grab({ r = "Mythic", z = "Reef" })
	end },
	{ "fx", "Haul of 4", UI.C.money, function()
		for _, r in { "Common", "Uncommon", "Rare", "Epic" } do
			Moments.deposit({ r = r, z = "Reef", v = 10, active = true })
		end
	end },
	{ "fx", "Escape snap", T.gold, function()
		local hrp = root()
		if hrp then
			Fx.escapeSnap(Vector3.new(hrp.Position.X, Config.WATER_Y + 0.5, hrp.Position.Z + 6))
		end
	end },
	{ "fx", "Close call", UI.C.sky, function()
		Fx.nearMiss()
		Moments.closeCall()
	end },
	{ "fx", "New best", T.purple, function()
		if not Moments.testBest() then
			Notify.toast("No showcase over your dock yet", T.gold)
		end
	end },
	{ "fx", "New zone", T.green, function()
		local zone = Config.zoneById("Kelp")
		if zone then
			Moments.unlock(zone)
		end
	end },
	{ "fx", "Bonk hit", T.pink, function()
		local hrp = root()
		if hrp then
			local at = hrp.Position + hrp.CFrame.LookVector * 6
			Fx.glow(at, Color3.fromRGB(255, 225, 80), 9, 0.2)
			Fx.wave(at, Color3.new(1, 1, 1), 16)
			Fx.sparkle(at, Color3.fromRGB(255, 225, 80), 22)
			Fx.impactFrame(0.7)
			Fx.shake(1.4)
		end
	end },
}

Tester.TESTS = TESTS

local function close()
	if gui then
		gui:Destroy()
		gui = nil
	end
end

function Tester.open()
	if gui then
		return
	end
	local g = Instance.new("ScreenGui")
	g.Name = "Tester"
	g.ResetOnSpawn = false
	g.DisplayOrder = 12
	g.Parent = player:WaitForChild("PlayerGui")
	UI.hideInCutscenes(g) -- (out of the way while a cutscene plays; back after)
	UI.autoScale(g, Vector2.new(560, 470))
	gui = g
	local _, body = UI.window(g, "Cutscene Tester", T.purple, Vector2.new(540, 450), close)
	local where = root()
	local onLand = where and not Layout.inWater(where.Position)
	UI.label(body, "meta", onLand and "Only you see these. Tap to play." or "At sea: cutscenes play their in-place version here.",
		{ Size = UDim2.new(1, 0, 0, 18), TextColor3 = T.mute })
	local y = 26
	for _, section in { { "cut", "CUTSCENES" }, { "fx", "EFFECTS" } } do
		UI.label(body, "meta", section[2], { Size = UDim2.new(1, 0, 0, 18), Position = UDim2.fromOffset(0, y), TextColor3 = T.gold,
			TextXAlignment = Enum.TextXAlignment.Left })
		y += 22
		local i = 0
		for _, t in TESTS do
			if t[1] == section[1] then
				local col, row = i % 3, i // 3
				UI.button(body, t[2], t[3], t[4], { Size = UDim2.new(1 / 3, -6, 0, 40), Position = UDim2.new(col / 3, 3, 0, y + row * 46) })
				i += 1
			end
		end
		y += math.ceil(i / 3) * 46 + 8
	end
end

function Tester.start()
	Remotes.get("Notify").OnClientEvent:Connect(function(kind)
		if kind == "srctest" then
			Tester.open()
		end
	end)
end

return Tester
