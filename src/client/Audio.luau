-- Music and the 3D soundscape. Every sound is a slot in Config.SoundSlots
-- (file + the part of it to play, pitch, EQ, loudness), built by Sounds.luau.
--   music     one main track (Config.Sounds.music) with optional tracks per
--             place (beach / ocean / deep / hunt). Same id = it just keeps
--             playing; a hunt with no hunt track ducks the music instead.
--   3D world  small waves lapping all along the shoreline (swelling with the
--             foam you see), waves around the islands nearest you, gulls over
--             the beach and the nearest palm island, a bubbling tank at every
--             dock. Volume and panning come from where you are.
--   open sea  a soft wave bed (2D) that rises as you head out
--   rides     every rider's ride loops in 3D on their body; pitch and volume
--             follow speed; some rides add a call now and then (dolphin
--             clicks, duck squeaks)
--   UI        clicks, windows opening/closing (UI.onClick / onOpen / onClose)

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = game.ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Layout = require(Shared.Layout)
local Remotes = require(Shared.Remotes)
local UI = require(script.Parent.UI)
local Fx = require(script.Parent.Fx)
local Sounds = require(script.Parent.Sounds)

local Audio = {}
local player = Players.LocalPlayer

local MUSIC_VOLUME = 0.3
local HUNT_DUCK = 0.45 -- music level during a hunt when there's no hunt track
local FADE = 1.6
local SHORE_Y = 1.5
local SHORE_Z = 9 -- the foam line
local ISLAND_EMITTERS = 3

local function point(pos: Vector3): Attachment
	local a = Instance.new("Attachment")
	a.Name = "SoundPoint"
	a.WorldPosition = pos
	a.Parent = Workspace.Terrain
	return a
end

-- a looping 3D emitter at a world point
local function emitter(slot: string, pos: Vector3, minD: number, maxD: number, pitch: number?): (Sound?, Attachment)
	local a = point(pos)
	local s = Sounds.make(slot, 0, pitch, a, true, "Ambience")
	if s then
		s.RollOffMode = Enum.RollOffMode.InverseTapered
		s.RollOffMinDistance = minD
		s.RollOffMaxDistance = maxD
		Sounds.randomStart(s)
		s:Play()
	end
	return s, a
end

-- ease a looping sound's volume toward a target (keeps its slot gain)
local function ease(s: Sound?, target: number, k: number)
	if not s then
		return
	end
	local gain = (s:GetAttribute("Gain") :: number?) or 1
	local cur = s.Volume / gain
	Sounds.setVolume(s, cur + (target - cur) * k)
end

----------------------------------------------------------------- music
local tracks: { [string]: Sound } = {}
local currentId = ""
local currentLevel = -1

local function musicId(slot: string): string
	local v = Config.Sounds[slot]
	if typeof(v) == "string" and v ~= "" then
		return v
	end
	local main = Config.Sounds.music
	return typeof(main) == "string" and main or ""
end

local function setMusic(id: string, level: number)
	if id == currentId and level == currentLevel then
		return
	end
	currentLevel = level
	if id ~= currentId then
		local old = tracks[currentId]
		if old then
			TweenService:Create(old, TweenInfo.new(FADE, Enum.EasingStyle.Sine), { Volume = 0 }):Play()
			local was = currentId
			task.delay(FADE, function()
				if currentId ~= was and old.Parent then
					old:Pause()
				end
			end)
		end
		currentId = id
		if id == "" then
			return
		end
		local s = tracks[id]
		if not s then
			s = Instance.new("Sound")
			s.Name = "Music"
			s.SoundId = id
			s.Looped = true
			s.Volume = 0
			s.SoundGroup = Sounds.group("Music")
			s.Parent = SoundService
			tracks[id] = s
		end
		if s.IsPaused then
			s:Resume()
		elseif not s.IsPlaying then
			s:Play()
		end
	end
	local s = tracks[id]
	if s then
		TweenService:Create(s, TweenInfo.new(FADE, Enum.EasingStyle.Sine), { Volume = MUSIC_VOLUME * level }):Play()
	end
end

----------------------------------------------------------------- 3D world
type Shore = { s: Sound }
local shore: { Shore } = {}
type IslandEmitter = { s: Sound?, a: Attachment, island: Layout.Island?, level: number }
local islandEmitters: { IslandEmitter } = {}
local gulls: { Sound } = {}
local islandGull: { s: Sound?, a: Attachment }? = nil
local tanks: { Sound } = {}

local function buildWorld()
	-- small waves all along the waterline
	local w = Config.LANE_WIDTH
	local x = -w / 2 + 24
	while x <= w / 2 - 24 do
		local s = emitter("ambShore", Vector3.new(x, SHORE_Y, SHORE_Z), 14, 120, 0.95 + math.random() * 0.1)
		if s then
			table.insert(shore, { s = s })
		end
		x += 48
	end
	-- waves around the nearest islands (a small pool that follows you)
	for _ = 1, ISLAND_EMITTERS do
		local s, a = emitter("ambShore", Vector3.new(0, -500, 0), 10, 90, 1.05 + math.random() * 0.1)
		table.insert(islandEmitters, { s = s, a = a, island = nil, level = 0 })
	end
	-- gulls over the beach, and one on the nearest palm island
	for _, pos in { Vector3.new(-80, 24, -24), Vector3.new(70, 28, -46) } do
		local s = emitter("ambGulls", pos, 20, 220)
		if s then
			table.insert(gulls, s)
		end
	end
	local gs, ga = emitter("ambGulls", Vector3.new(0, -500, 0), 16, 160, 1.08)
	islandGull = { s = gs, a = ga }
	-- every dock's tank bubbles quietly
	for _, plot in Layout.Plots do
		local s = emitter("ambTank", Layout.tankPos(plot) + Vector3.new(0, 3, 0), 6, 45, 0.9 + math.random() * 0.2)
		if s then
			table.insert(tanks, s)
		end
	end
end

local function nearestIslands(pos: Vector3, n: number, palmOnly: boolean?): { Layout.Island }
	local list = {}
	for _, island in Layout.Islands do
		if not palmOnly or island.palm then
			local d = Vector2.new(pos.X - island.pos.X, pos.Z - island.pos.Z).Magnitude - island.radius
			table.insert(list, { island = island, d = d })
		end
	end
	table.sort(list, function(a, b)
		return a.d < b.d
	end)
	local out = {}
	for i = 1, math.min(n, #list) do
		out[i] = list[i].island
	end
	return out
end

local function retarget(listener: Vector3)
	-- keep emitters already on a near island; move the rest to the new ones
	local want = nearestIslands(listener, ISLAND_EMITTERS)
	local taken = {}
	for _, e in islandEmitters do
		if e.island and table.find(want, e.island) then
			taken[e.island] = true
		end
	end
	for _, e in islandEmitters do
		if not (e.island and table.find(want, e.island)) then
			for _, island in want do
				if not taken[island] then
					taken[island] = true
					e.island = island
					e.a.WorldPosition = Vector3.new(island.pos.X, SHORE_Y, island.pos.Z)
					e.level = 0 -- fade in where it lands
					if e.s then
						e.s.RollOffMinDistance = island.radius + 4
						e.s.RollOffMaxDistance = island.radius + 80
						Sounds.setVolume(e.s, 0)
					end
					break
				end
			end
		end
	end
	if islandGull then
		local palm = nearestIslands(listener, 1, true)[1]
		if palm then
			islandGull.a.WorldPosition = Vector3.new(palm.pos.X, 22, palm.pos.Z)
		end
	end
end

----------------------------------------------------------------- rides (3D)
type RideLoop = { sound: Sound, key: string, nextCall: number }
local rideLoops: { [Model]: RideLoop } = {}

local function updateRides(now: number)
	for _, p in Players:GetPlayers() do
		local char = p.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not (char and hrp) then
			continue
		end
		local rideId = (char:GetAttribute("Ride") :: string?) or "Noodle"
		local spec = Config.RideSound[rideId]
		local key = spec and spec[1] or "rideSplash"
		local entry = rideLoops[char]
		if entry and entry.key ~= key then
			entry.sound:Destroy()
			rideLoops[char] = nil
			entry = nil
		end
		if not entry then
			local s = Sounds.make(key, 0, 1, hrp, true, "Effects")
			if not s then
				continue
			end
			s.RollOffMode = Enum.RollOffMode.InverseTapered
			s.RollOffMinDistance = 12
			s.RollOffMaxDistance = 140
			Sounds.randomStart(s)
			s:Play()
			entry = { sound = s, key = key, nextCall = now + 3 }
			rideLoops[char] = entry
		end
		local pos = hrp.Position
		local wet = Layout.inWater(pos) and not Layout.islandAt(pos, 0)
		local speed = (hrp.AssemblyLinearVelocity * Vector3.new(1, 0, 1)).Magnitude
		local k = math.clamp(speed / 160, 0, 1)
		local mine = p == player
		local vol = wet and ((mine and 0.25 or 0.18) + k * (mine and 0.35 or 0.25)) or 0
		ease(entry.sound, vol, 0.15)
		local base = (entry.sound:GetAttribute("Pitch") :: number?) or 1
		entry.sound.PlaybackSpeed = base * (spec and spec[2] or 1) * (0.85 + k * 0.45)
		-- a call now and then (dolphin clicks, duck squeaks), from the rider
		local slot = Config.SoundSlots[key]
		local every = slot and slot.every
		if every and wet and now >= entry.nextCall then
			entry.nextCall = now + every[2] + math.random() * (every[3] - every[2])
			Fx.sound(every[1], (every[4] or 0.4) * (mine and 1 or 0.8), (spec and spec[2] or 1) * (0.95 + math.random() * 0.1), hrp)
		end
	end
	for char, entry in rideLoops do
		if not char.Parent then
			entry.sound:Destroy()
			rideLoops[char] = nil
		end
	end
end

----------------------------------------------------------------- start
function Audio.start()
	-- UI hooks
	UI.onClick = function()
		Fx.sound("uiClick", 0.5)
	end
	UI.onOpen = function()
		Fx.sound("uiOpen", 0.5)
	end
	UI.onClose = function()
		Fx.sound("uiClose", 0.45)
	end

	buildWorld()
	local bed = Sounds.make("ambWaves", 0, 1, SoundService, true, "Ambience")
	if bed then
		Sounds.randomStart(bed)
		bed:Play()
	end

	local phase = "calm"
	Remotes.get("SharkEvent").OnClientEvent:Connect(function(kind)
		if kind == "warning" or kind == "hunt" then
			phase = kind
		elseif kind == "clear" then
			phase = "calm"
		end
	end)

	local wasWet = false
	local acc, retargetAcc = 0, 1
	RunService.Heartbeat:Connect(function(dt)
		local now = os.clock()
		updateRides(now)

		-- shore waves swell with the foam line (Water.luau pulses it on sin(t * 1.6))
		local swell = 0.5 + 0.5 * math.sin(now * 1.6)
		for _, e in shore do
			Sounds.setVolume(e.s, 0.5 * (0.55 + 0.45 * swell))
		end
		for _, e in islandEmitters do
			e.level = math.min(e.level + dt * 0.5, 1)
			if e.s then
				Sounds.setVolume(e.s, 0.35 * e.level * (0.6 + 0.4 * swell))
			end
		end

		local cam = Workspace.CurrentCamera
		local listener = cam and cam.Focus.Position or Vector3.zero
		retargetAcc += dt
		if retargetAcc >= 0.5 then
			retargetAcc = 0
			retarget(listener)
		end

		acc += dt
		if acc < 0.4 then
			return
		end
		acc = 0
		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not hrp then
			return
		end
		local pos = hrp.Position
		local wet = Layout.inWater(pos)
		local zone = Config.zoneAt(pos.Z)

		-- music by place; a hunt without its own track ducks the music
		if phase ~= "calm" then
			local hunt = Config.Sounds.musicHunt
			local has = typeof(hunt) == "string" and hunt ~= ""
			setMusic(musicId("musicHunt"), has and 1 or HUNT_DUCK)
		elseif wet and zone and zone.index >= 5 then
			setMusic(musicId("musicDeep"), 1)
		elseif wet then
			setMusic(musicId("musicOcean"), 1)
		else
			setMusic(musicId("musicBeach"), 1)
		end

		-- the open-sea bed rises as you head out (the shore is 3D)
		if bed then
			local out = math.clamp((pos.Z - 40) / 160, 0, 1)
			ease(bed, wet and (0.08 + 0.16 * out) or 0.03, 0.5)
		end
		for _, s in gulls do
			Sounds.setVolume(s, 0.3)
		end
		if islandGull and islandGull.s then
			Sounds.setVolume(islandGull.s, wet and 0.22 or 0)
		end
		for _, s in tanks do
			Sounds.setVolume(s, 0.3)
		end

		-- rubber duck squeak as you hop in
		if wet and not wasWet then
			local ride = char and char:GetAttribute("Ride")
			if ride == "Duck" or ride == "GoldDuck" then
				Fx.sound("duckSqueak", 0.6, ride == "GoldDuck" and 1.15 or 1)
			end
		end
		wasWet = wet
	end)
end

return Audio
