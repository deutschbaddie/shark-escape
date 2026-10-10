-- The raid spin (server: Raids.luau finish): when a raid lands, a strip of
-- the owner's creatures rolls past a center marker and slows to a stop on
-- the one that's taken. Each card shows the creature, its rarity and its
-- real chance of being picked ("1%"). Both players watch the same roll: the
-- raider hoping for the rare ones, the owner hoping it lands on a Common.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = game.ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Creatures = require(Shared.Creatures)
local UI = require(script.Parent.UI)
local Fx = require(script.Parent.Fx)

local RaidSpin = {}
local player = Players.LocalPlayer
local T = UI.T

local CARD_W, CARD_H, GAP = 112, 156, 10
local STEP = CARD_W + GAP
local CARDS = 36 -- cards in the strip
local WIN_AT = 31 -- the winner's slot (plenty of roll before it)
local SPIN_TIME = 4.2

local gui: ScreenGui? = nil
RaidSpin.settled = false -- (the UI preview: show the strip already stopped)

local function chanceText(p: number): string
	local pct = p * 100
	if pct >= 10 then
		return ("%d%%"):format(math.floor(pct + 0.5))
	elseif pct >= 1 then
		return (("%.1f%%"):format(pct):gsub("%.0%%", "%%"))
	end
	return ("%.1f%%"):format(math.max(pct, 0.1))
end

-- one card: rarity chip, the creature, its name, its chance
local function card(parent: Instance, item: any, x: number): Frame
	local rarity = Config.rarity(item.r)
	local f = UI.card(parent, rarity.color, { Size = UDim2.fromOffset(CARD_W, CARD_H), Position = UDim2.fromOffset(x, 0) })
	UI.chip(f, item.r:upper(), rarity.color, { Size = UDim2.new(1, -12, 0, 20), Position = UDim2.fromOffset(6, 6) })
	local vf = Instance.new("ViewportFrame")
	vf.Size = UDim2.new(1, -12, 0, 72)
	vf.Position = UDim2.fromOffset(6, 30)
	vf.BackgroundTransparency = 1
	vf.Ambient = Color3.fromRGB(200, 200, 210)
	vf.LightDirection = Vector3.new(-1, -2, -1)
	vf.Parent = f
	local cam = Instance.new("Camera")
	cam.FieldOfView = 40
	cam.Parent = vf
	vf.CurrentCamera = cam
	local ok, model = pcall(Creatures.build, item.r, item.m, 1, item.z)
	if ok and model then
		model:PivotTo(CFrame.new())
		model.Parent = vf
		local _, size = model:GetBoundingBox()
		local r = math.max(size.X, size.Y, size.Z)
		cam.CFrame = CFrame.lookAt(Vector3.new(r * 0.9, r * 0.6, -r * 1.3), Vector3.new(0, -0.2, 0))
	end
	UI.label(f, "meta", Config.species(item.z, item.r).name, { Size = UDim2.new(1, -10, 0, 18), Position = UDim2.fromOffset(5, 104) })
	UI.label(f, "value", chanceText(item.p or 0), { Size = UDim2.new(1, -10, 0, 26), Position = UDim2.fromOffset(5, 124),
		TextColor3 = UI.light(rarity.color, 0.3) })
	return f
end

-- weighted pick from the shown items (fills the strip around the winner)
local function sample(items: { any }, rng: Random): any
	local total = 0
	for _, it in items do
		total += it.p or 0
	end
	local roll = rng:NextNumber(0, total)
	for _, it in items do
		roll -= it.p or 0
		if roll <= 0 then
			return it
		end
	end
	return items[#items]
end

-- items: { r, z, m, s, p }, win: index of the winner in items,
-- title / sub: the header (raider: "Raiding Sam's tank"; owner: "Sam is
-- taking one of yours"), done: after the result has shown
function RaidSpin.play(items: { any }, win: number, title: string, sub: string, done: (() -> ())?)
	local winner = items[win]
	if not winner then
		if done then
			done()
		end
		return
	end
	if gui then
		gui:Destroy()
	end
	local g = Instance.new("ScreenGui")
	g.Name = "RaidSpin"
	g.ResetOnSpawn = false
	g.DisplayOrder = 15
	g.Parent = player:WaitForChild("PlayerGui")
	UI.autoScale(g, Vector2.new(720, 300))
	UI.hideInCutscenes(g)
	gui = g

	local W = 690
	local panel = UI.frame(g, { Size = UDim2.fromOffset(W, 262), Position = UDim2.fromScale(0.5, 0.42), AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = T.navy, BackgroundTransparency = 0.08 })
	UI.corner(panel, UI.R.card)
	UI.stroke(panel, T.line, UI.S.card)
	UI.label(panel, "value", title, { Size = UDim2.new(1, -20, 0, 30), Position = UDim2.fromOffset(10, 8), TextColor3 = T.gold })
	UI.label(panel, "body", sub, { Size = UDim2.new(1, -20, 0, 22), Position = UDim2.fromOffset(10, 37), TextColor3 = UI.light(T.mute, 0.3) })

	-- the window the strip rolls through
	local window = UI.inset(panel, { Size = UDim2.new(1, -20, 0, CARD_H + 16), Position = UDim2.fromOffset(10, 64), ClipsDescendants = true })
	local strip = UI.frame(window, { Size = UDim2.fromOffset(CARDS * STEP, CARD_H), Position = UDim2.fromOffset(0, 8), BackgroundTransparency = 1 })
	local rng = Random.new()
	local winCard: Frame? = nil
	for i = 1, CARDS do
		local item = (i == WIN_AT) and winner or sample(items, rng)
		local c = card(strip, item, (i - 1) * STEP)
		if i == WIN_AT then
			winCard = c
		end
	end
	-- the marker: a gold line down the middle with a notch top and bottom
	local mid = (W - 20) / 2
	UI.frame(window, { Size = UDim2.new(0, 4, 1, 0), Position = UDim2.fromOffset(mid - 2, 0), BackgroundColor3 = T.gold, ZIndex = 20 })
	for _, top in { true, false } do
		local n = UI.frame(window, { Size = UDim2.fromOffset(16, 16), Position = UDim2.new(0, mid, top and 0 or 1, 0), AnchorPoint = Vector2.new(0.5, 0.5),
			Rotation = 45, BackgroundColor3 = T.gold, ZIndex = 20 })
		UI.corner(n, 3)
	end

	-- roll: fast, then a long ease out onto the winner (landing a little off
	-- its middle, so it feels like it could have tipped either way)
	local jitter = rng:NextNumber(-0.32, 0.32) * CARD_W
	local endX = mid - ((WIN_AT - 1) * STEP + CARD_W / 2) + jitter
	local startX = mid - CARD_W / 2 - STEP * 2
	strip.Position = UDim2.fromOffset(RaidSpin.settled and endX or startX, 8)
	UI.fade(panel, true, 0.2)
	local t0 = os.clock()
	local lastSlot = -1
	local conn
	conn = RunService.RenderStepped:Connect(function()
		local k = math.clamp((os.clock() - t0) / SPIN_TIME, 0, 1)
		local e = 1 - (1 - k) ^ 4 -- (quartic ease out)
		local x = startX + (endX - startX) * e
		strip.Position = UDim2.fromOffset(x, 8)
		-- a tick each time a card passes the marker, rising as it slows
		local slot = math.floor((mid - x) / STEP)
		if slot ~= lastSlot then
			lastSlot = slot
			Fx.sound("uiClick", 0.25, 0.9 + k * 0.5)
		end
		if k >= 1 then
			conn:Disconnect()
			-- the result: the winning card pops and glows in its rarity color
			local rarity = Config.rarity(winner.r)
			if winCard then
				UI.pop(winCard, 1.15)
				local st = winCard:FindFirstChild("Accent") :: UIStroke?
				if st then
					st.Thickness = 4
				end
			end
			Fx.sound(rarity.index >= 5 and "legendary" or (rarity.index >= 3 and "grabRare" or "grab"), 0.8)
			task.delay(1.6, function()
				UI.fade(panel, false, 0.3)
				task.delay(0.32, function()
					if gui == g then
						gui = nil
					end
					g:Destroy()
					if done then
						done()
					end
				end)
			end)
		end
	end)
end

return RaidSpin
