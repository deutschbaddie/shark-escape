-- The moments: what the game's events look like. Small ones play during
-- play and never take the camera; the big rare ones are short cutscenes
-- (Cine.luau, land only, skippable). All built from the Fx toolkit, scaled
-- by what earned them.
--   every trip     grab pop (by rarity), your catches flying into the tank
--                  one by one before the haul pays, close-call outline
--   now and then   new ride reveal, a new best creature lit up over your
--                  dock, a new zone's color wash
--   rare           Mythic reveal when it lands in your tank, evolve, the
--                  Megalodon breaching
-- (The escape snap and bonk hits live in SharkView / Bonk, using the same
-- toolkit.)

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = game.ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Layout = require(Shared.Layout)
local Remotes = require(Shared.Remotes)
local Creatures = require(Shared.Creatures)
local Rides = require(Shared.Rides)
local UI = require(script.Parent.UI)
local Fx = require(script.Parent.Fx)
local Cine = require(script.Parent.Cine)
local Shop = require(script.Parent.Shop)
local State = require(script.Parent.State)
local SharkView = require(script.Parent.SharkView)

local Moments = {}
local player = Players.LocalPlayer
local UP = Vector3.yAxis
local GOLD = UI.C.gold
local GREEN = Color3.fromRGB(110, 255, 140)
local RED = Color3.fromRGB(255, 70, 85)

local function root(): BasePart?
	local char = player.Character
	return char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function myTank(): Vector3?
	local d = State.data
	if not (d and d.plot > 0) then
		return nil
	end
	return Layout.tankPos(Layout.plot(d.plot, d.world))
end

----------------------------------------------------------------- grab
-- the pop scales with rarity; Legendary and up mark the spot with a pillar
local GRAB_POWER = { 0.3, 0.4, 0.6, 0.75, 1, 1.3 }
function Moments.grab(d: any)
	local hrp = root()
	if not hrp then
		return
	end
	local r = Config.rarity(d.r)
	local i = r.index
	local at = hrp.Position + UP * 3
	Fx.burst(at, r.color, GRAB_POWER[i] or 0.5)
	if i >= 3 then
		Fx.punch(i >= 5 and 7 or 3)
	end
	if i >= 5 then
		local water = Vector3.new(at.X, Config.WATER_Y + 0.5, at.Z)
		Fx.impactFrame(i >= 6 and 1 or 0.7)
		Fx.shockwave(water, r.color, i >= 6 and 70 or 50)
		Fx.pillar(water, r.color, 90, 1.6)
	end
	if i >= 6 then
		Fx.wash(r.color, 1.4, 0.3)
	end
end

----------------------------------------------------------------- home: the haul flies in
-- Each catch you bring home flies from you into the tank, one after the
-- other, and lands with a pop and a rising coin tick. The haul's payout
-- (Haul.luau) waits for the last one, so the money counts up on the landing.
local FLY, GAP = 0.5, 0.13
local landAt = 0 -- when the last catch in the air lands
local batchAt, batchN = 0, 0

-- seconds until everything in the air has landed (0 if nothing is)
function Moments.landing(): number
	return math.max(0, landAt - os.clock())
end

local mythicReveal: (d: any, tank: Vector3) -> ()

function Moments.deposit(d: any)
	local tank = myTank()
	if not tank then
		return
	end
	local now = os.clock()
	if now - batchAt > 0.1 then
		batchAt, batchN = now, 0
	end
	local i = batchN
	batchN += 1
	local r = Config.rarity(d.r)
	local top = tank + UP * 6
	local hrp = root()
	local far = not hrp or (hrp.Position - tank).Magnitude > 120 -- (a gift that came from afar: it just lands)
	local launch = i * GAP
	landAt = math.max(landAt, now + launch + (far and 0 or FLY))

	local function landed()
		Fx.splash(top, 0.45)
		Fx.burst(top, r.color, 0.3 + r.index * 0.07)
		Fx.sound("coin", 0.55, 1 + i * 0.07, top)
		local side = (i % 2 == 0) and 1 or -1
		if d.active then
			Fx.popup3D(top + Vector3.new(side * math.min(i, 3), 5, 0), ("+$%s/s"):format(Config.formatRate(d.v)), UI.C.money, i == 0)
		elseif i == 0 then
			Fx.popup3D(top + UP * 5, "Not equipped", Color3.fromRGB(170, 170, 180), true)
		end
		if r.id == "Mythic" then
			mythicReveal(d, tank)
		elseif r.index >= 5 then
			Fx.pillar(tank, r.color, 70, 2.2)
			Fx.sound("legendary", 0.6, 1, tank)
		end
	end
	task.delay(launch, function()
		local h = root()
		if far or not h then
			landed()
		else
			Fx.sound("deposit", 0.5, 1.1 + i * 0.05, h.Position)
			Fx.fly(h.Position + UP * 3, top, r.color, FLY, landed)
		end
	end)
end

----------------------------------------------------------------- Mythic reveal
-- It rises out of your tank, huge, the world dims, a hit of light, and the
-- camera circles it once. ~4 s. At sea (it can't play) the tank gets the
-- pillar instead.
mythicReveal = function(d: any, tank: Vector3)
	local r = Config.rarity(d.r)
	local color = r.color
	local hrp = root()
	local toMe = hrp and flat(hrp.Position - tank) or Vector3.zero
	local dir = toMe.Magnitude > 1 and toMe.Unit or Vector3.new(0, 0, -1)
	-- (a little off to one side, so you're not standing in the shot)
	dir = (CFrame.Angles(0, 0.6, 0) * CFrame.new(dir)).Position
	local base = tank + UP * 2
	local center = tank + UP * 15
	local yaw0 = math.atan2(dir.X, dir.Z)
	local model: Model? = nil
	local aura: ParticleEmitter? = nil
	local spin: RBXScriptConnection? = nil
	local t0 = 0

	local function cleanup()
		if spin then
			spin:Disconnect()
		end
		if model then
			local m = model
			Fx.burst(m:GetPivot().Position, color, 0.6)
			m:Destroy()
		end
	end

	local played = Cine.play({
		time = 4.3,
		title = Config.fullName(d.z, d.r, d.m, d.s),
		sub = "A Mythic! It's in your tank",
		color = color,
		captionAt = 1.4,
		shot = function(t)
			if t < 1.3 then
				-- low by the tank, looking up as it rises
				local k = Cine.ease(t / 1.3)
				return CFrame.lookAt(tank + dir * 22 + UP * 3, base:Lerp(center, k) + UP * 2), 58 - 12 * k
			end
			-- then one slow turn around it
			local k = Cine.ease((t - 1.3) / 3)
			return CFrame.lookAt(Cine.orbit(center, 24 - 4 * k, 2 + 4 * k, yaw0 + k * 1.7), center), 46
		end,
		beats = {
			{ at = 0, fn = function()
				Fx.wash(Color3.fromRGB(70, 80, 140), 4.3, 0.35)
				Fx.sound("legendary", 0.8)
				local ok, m = pcall(Creatures.build, d.r, d.m, 2.6, d.z)
				if not ok then
					return
				end
				model = m
				m:PivotTo(CFrame.new(base))
				m.Parent = Workspace
				local att = Instance.new("Attachment")
				att.Parent = m.PrimaryPart
				local e = Instance.new("ParticleEmitter")
				e.Texture = Fx.tex("Star")
				e.Color = ColorSequence.new(Color3.new(1, 1, 1), color)
				e.LightEmission = 1
				e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.3, 1.2), NumberSequenceKeypoint.new(1, 0) })
				e.Lifetime = NumberRange.new(0.8, 1.4)
				e.Speed = NumberRange.new(4, 9)
				e.SpreadAngle = Vector2.new(180, 180)
				e.Rate = Fx.count(24)
				e.Enabled = false
				e.Parent = att
				aura = e
				t0 = os.clock()
				spin = RunService.RenderStepped:Connect(function()
					local t = os.clock() - t0
					local k = Cine.ease(t / 1.25)
					m:PivotTo(CFrame.new(base:Lerp(center, k) + UP * math.sin(t * 2) * 0.5) * CFrame.Angles(0, yaw0 + math.pi + t * 0.6, 0))
				end)
			end },
			{ at = 0.15, fn = function()
				Fx.pillar(tank, color, 110, 4)
			end },
			{ at = 1.25, fn = function()
				Fx.impactFrame(1)
				Fx.burst(center, color, 1.4)
				Fx.shockwave(tank + UP * 0.5, color, 80, 0.8)
				Fx.shake(1)
				Fx.sound("discover", 0.9)
				if aura then
					aura.Enabled = true
				end
			end },
			{ at = 2.6, fn = function()
				Fx.wave(center, color, 40)
			end },
		},
		onEnd = cleanup,
	})
	if not played then
		Fx.pillar(tank, color, 110, 3)
		Fx.burst(tank + UP * 8, color, 1.2)
		Fx.sound("legendary", 0.8, 1, tank)
	end
end

----------------------------------------------------------------- close call
function Moments.closeCall()
	local char = player.Character
	local hrp = root()
	if char and hrp then
		Fx.outline(char, Color3.new(1, 1, 1), 0.6)
		Fx.burst(hrp.Position + UP * 2, Color3.fromRGB(200, 240, 255), 0.55)
	end
end

----------------------------------------------------------------- new ride
-- The ride on a turntable in front of you, the camera sweeping round it.
-- Returns true if the cutscene played (it shows the name, so the HUD
-- skips its own title).
function Moments.ride(d: any): boolean
	local ride = Config.ride(d.id)
	local hrp = root()
	if not (ride and hrp and Cine.canPlay()) then
		local h = root()
		if h then
			Fx.burst(h.Position + UP * 2, GOLD, 0.8)
		end
		return false
	end
	-- the spot: ahead of where the camera looks, pulled in if a wall's there
	local cam = Workspace.CurrentCamera
	local look = flat(cam.CFrame.LookVector)
	look = look.Magnitude > 0.1 and look.Unit or flat(hrp.CFrame.LookVector).Unit
	local params = RaycastParams.new()
	params.FilterDescendantsInstances = { player.Character :: Instance, Fx.folder }
	params.FilterType = Enum.RaycastFilterType.Exclude
	local dist = 9
	local hit = Workspace:Raycast(hrp.Position, look * (dist + 4), params)
	if hit then
		dist = math.max(4, hit.Distance - 4)
	end
	local feet = hrp.Position - UP * 2.8
	local spot = feet + look * dist
	local center = spot + UP * 2.5
	local yaw0 = math.atan2(-look.X, -look.Z) -- (your side of it: the sweep goes round the far side, you behind it)
	local model: Model? = nil
	local spin: RBXScriptConnection? = nil
	local reopen = Shop.isOpen() -- (the cutscene closes the shop: open it again after, to keep shopping)

	return Cine.play({
		time = 2.6,
		title = ride.name,
		sub = ("New ride · +%s speed/s"):format(UI.short(d.gain or 0)),
		color = GOLD,
		captionAt = 0.5,
		shot = function(t)
			local k = Cine.ease(t / 2.6)
			return CFrame.lookAt(Cine.orbit(center, 12 - 2.5 * k, 2.5 + 1.5 * k, yaw0 + 1.3 + k * 1.5), center), 50 - 6 * k
		end,
		beats = {
			{ at = 0, fn = function()
				local ok, m = pcall(Rides.build, d.id)
				if not ok then
					return
				end
				model = m
				m.Parent = Workspace
				local t0 = os.clock()
				spin = RunService.RenderStepped:Connect(function()
					local t = os.clock() - t0
					local rise = 1 - (1 - math.clamp(t / 0.45, 0, 1)) ^ 3
					m:PivotTo(CFrame.new(spot + UP * (0.5 + rise * 1.5)) * CFrame.Angles(0, t * 1.2, 0))
					m:ScaleTo(math.max(0.05, rise))
				end)
				Fx.shockwave(spot + UP * 0.2, GOLD, 22)
				Fx.sound("rideNew", 0.8)
			end },
			{ at = 0.35, fn = function()
				Fx.burst(center, GOLD, 0.9)
				Fx.sound("buy", 0.8)
			end },
			{ at = 1.4, fn = function()
				Fx.burst(center + UP * 2, Color3.new(1, 1, 1), 0.35)
			end },
		},
		onEnd = function()
			if spin then
				spin:Disconnect()
			end
			if model then
				Fx.burst(model:GetPivot().Position, GOLD, 0.5)
				model:Destroy()
			end
			if reopen and Shop.atRideShop() then
				Shop.openRides()
			end
		end,
	})
end

----------------------------------------------------------------- new zone
-- at sea, so no camera: the view takes on the biome's color, and a whoosh
function Moments.unlock(zone: any)
	local hrp = root()
	local color = (zone.water or GREEN):Lerp(Color3.new(1, 1, 1), 0.35)
	Fx.wash(color, 1.8, 0.35)
	Fx.punch(-8, 0.6)
	if hrp then
		Fx.burst(hrp.Position + UP * 3, GREEN, 0.7)
	end
end

----------------------------------------------------------------- evolve
-- On land: you light up and a pillar of light lifts off you, then the
-- camera rises behind you and looks out to sea, where a beacon goes up over
-- the biome that just opened. At sea: the pillar and the beacon, no camera.
-- (The server has just moved you to your dock: give that a moment to land.)
-- `title` shows the HUD's own title when the cutscene can't play.
local function evolve(d: any, title: () -> ())
	local hrp = root()
	if not hrp then
		title()
		return
	end
	local char = player.Character :: Model
	local zone = d.zone and Config.zoneById(d.zone)
	local gate = zone and Vector3.new(Config.originX(zone.world), Config.WATER_Y, zone.zStart) or nil
	local function beacon()
		if gate and zone then
			Fx.pillar(gate, GREEN, 500, 7, 40)
			Fx.gateWave(zone.zStart, Config.originX(zone.world), Config.LANE_WIDTH, GREEN)
		end
	end
	local function lightUp()
		local h = root()
		if h then
			Fx.pillar(h.Position - UP * 3, GREEN, 120, 2.6, 7)
			Fx.outline(char, GREEN, 1.4)
		end
	end
	local P = hrp.Position
	local seaDir = gate and flat(gate - P) or Vector3.zero
	seaDir = seaDir.Magnitude > 1 and seaDir.Unit or Vector3.new(0, 0, 1)
	local face = flat(hrp.CFrame.LookVector)
	face = face.Magnitude > 0.1 and face.Unit or -seaDir
	local total = gate and 3.8 or 2.2

	local played = Cine.play({
		time = total,
		title = "You evolved",
		sub = d.biome and ("%s is open"):format(d.biome) or ("x%s speed for good"):format(tostring(Config.Rebirth.mult ^ (d.rebirths or 1))),
		color = GREEN,
		captionAt = 1,
		shot = function(t)
			if t < 1.2 or not gate then
				-- in front of you, low, pushing in
				local k = Cine.ease(t / 1.2)
				return CFrame.lookAt(P + face * (11 - 3 * k) + UP * (0.5 + k), P + UP * (1 + k)), 55 - 8 * k
			end
			-- crane up behind you, turning to look far out to sea
			local k = Cine.ease((t - 1.2) / (total - 1.2))
			local camPos = P - seaDir * (10 + 6 * k) + UP * (4 + 26 * k)
			local look = (P + UP * 2):Lerp(gate + UP * 120, k)
			return CFrame.lookAt(camPos, look), 55 - 27 * k
		end,
		beats = {
			{ at = 0.15, fn = lightUp, keep = true },
			{ at = 0.15, fn = function()
				Fx.sound("rebirthWhoosh", 0.8)
			end },
			{ at = 1, fn = function()
				Fx.impactFrame(0.9)
				Fx.flash(Color3.new(1, 1, 1), 0.5, 0.3)
				Fx.shockwave(P - UP * 2.5, GREEN, 60)
				Fx.burst(P + UP * 2, GREEN, 1.2)
				Fx.confetti(P)
			end },
			{ at = 1.3, fn = beacon, keep = true },
		},
	})
	if not played then
		Fx.flash(Color3.new(1, 1, 1), 0.8, 0)
		lightUp()
		Fx.burst(P + UP * 3, GREEN, 1)
		beacon()
		title()
	end
end

function Moments.evolve(d: any, title: () -> ())
	task.delay(0.25, evolve, d, title)
end

----------------------------------------------------------------- the Megalodon surfaces
-- It breaches at its spot: everyone near sees the leap (the real one hides
-- for the moment so there's only one), and on land the camera cuts to it.
local function hideShark(id: number, hidden: boolean)
	local sh = SharkView.get(id)
	local model = sh and sh.rig and sh.rig.model
	if not model then
		return
	end
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") then
			p.LocalTransparencyModifier = hidden and 1 or 0
		end
	end
end

local function bossBreach(data: any)
	local at = Vector3.new(data.x, Config.WATER_Y, data.z)
	local hrp = root()
	if not hrp then
		return
	end
	local L = Config.Boss.length
	local shore = Vector3.new(0, 0, -1) -- (the beach is toward -Z)
	local near = (hrp.Position - at).Magnitude < 700
	local function leap()
		hideShark(data.id, true)
		SharkView.breach("Megalodon", L, at - shore * L * 0.6, 0)
		Fx.sound("sharkCharge", 1, 0.8, at)
		task.delay(1.1, function()
			Fx.impactFrame(0.8)
		end)
		task.delay(1.85, function()
			Fx.spray(at + shore * L * 0.7, 40, 34)
			Fx.shockwave(at, RED, 160, 0.9)
			Fx.sound("chargeSplash", 1, 0.8, at)
			local h = root()
			Fx.shake(h and (h.Position - at).Magnitude < 250 and 2.5 or 1)
		end)
		task.delay(2.3, function()
			hideShark(data.id, false)
		end)
	end
	local cam = at + shore * (L * 1.6) + UP * 10 + Vector3.new(L * 0.5, 0, 0)
	local played = Cine.play({
		time = 3.4,
		title = "The Megalodon",
		sub = "Harpoon it for a Legendary!",
		color = RED,
		captionAt = 1.6,
		shot = function(t)
			local k = Cine.ease(t / 3.4)
			return CFrame.lookAt(cam + UP * 4 * k - shore * 8 * k, at + UP * (L * 0.45)), 54 - 8 * k
		end,
		beats = {
			{ at = 0, fn = function()
				Fx.wash(Color3.fromRGB(90, 70, 110), 3.4, 0.35)
			end },
			{ at = 0.3, fn = leap, keep = true },
		},
	})
	if not played and near then
		Fx.wash(Color3.fromRGB(90, 70, 110), 2.4, 0.25)
		leap()
	end
end

----------------------------------------------------------------- new best creature
-- your best creature changed: a beam of light drops onto your dock showcase
local bestValue: number? = nil
local function onShowcase(m: Instance)
	if m:GetAttribute("OwnerId") ~= player.UserId then
		return
	end
	-- Key = rarity|zone|mutation|size|evolves (Game.updateShowcase)
	local r, z, mu, sz = tostring(m:GetAttribute("Key") or ""):match("^([^|]*)|([^|]*)|([^|]*)|([^|]*)|")
	if not r then
		return
	end
	local value = Config.creatureValue(r, z, mu ~= "nil" and mu or nil, tonumber(sz))
	local before = bestValue
	bestValue = value
	-- only when it went up (not the first one after joining, an evolve
	-- resizing it, or losing your best to a raid)
	if before == nil or value <= before then
		return
	end
	task.delay(Moments.landing() + 0.3, function()
		if not (m:IsA("Model") and m.Parent) then
			return
		end
		local pos = m:GetPivot().Position
		local color = Config.rarity(r).color
		local hrp = root()
		if hrp and (hrp.Position - pos).Magnitude > 400 then
			return
		end
		Fx.pillar(pos - UP * 26, color, 160, 2.4, 9)
		Fx.burst(pos, color, 1)
		Fx.popup3D(pos + UP * 9, "New best!", color, true)
		Fx.sound("discover", 0.7, 1, pos)
	end)
end

function Moments.start()
	for _, m in CollectionService:GetTagged("Showcase") do
		onShowcase(m)
	end
	CollectionService:GetInstanceAddedSignal("Showcase"):Connect(onShowcase)
	Remotes.get("SharkEvent").OnClientEvent:Connect(function(kind, data)
		if kind == "boss" and typeof(data) == "table" then
			local hrp = root()
			local w = hrp and Config.worldAt(hrp.Position) or (State.data and State.data.world or 1)
			if data.world == w then
				bossBreach(data)
			end
		end
	end)
end

return Moments
