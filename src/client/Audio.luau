-- Music, ambience, ride and UI sounds. Every id lives in Config.Sounds; an
-- empty id is simply silent until you upload one (ASSETS.md lists them all).
--   music     beach (on land) / ocean (at sea) / deep (Deep Blue and the
--             Abyss) / hunt (shark warning + hunt). One track at a time,
--             crossfaded.
--   ambience  waves everywhere (louder at sea), gulls near the beach
--   rides     every rider's ride hums/splashes in 3D; pitch and volume follow
--             speed (Config.RideSound picks the loop per ride)
--   UI        button clicks, windows opening/closing (UI.onClick / onOpen /
--             onClose hooks); toasts and big moments play from Notify

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Shared = game.ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Layout = require(Shared.Layout)
local Remotes = require(Shared.Remotes)
local UI = require(script.Parent.UI)
local Fx = require(script.Parent.Fx)

local Audio = {}
local player = Players.LocalPlayer

local MUSIC_VOLUME = 0.32
local FADE = 1.6

local function id(key: string): string
	local v = Config.Sounds[key]
	return typeof(v) == "string" and v or ""
end

local function loop(key: string, volume: number, parent: Instance?): Sound?
	if id(key) == "" then
		return nil
	end
	local s = Instance.new("Sound")
	s.Name = key
	s.SoundId = id(key)
	s.Looped = true
	s.Volume = volume
	s.Parent = parent or SoundService
	s:Play()
	return s
end

----------------------------------------------------------------- music
local tracks: { [string]: Sound } = {}
local current: string? = nil

local function fadeTo(s: Sound, volume: number)
	TweenService:Create(s, TweenInfo.new(FADE, Enum.EasingStyle.Sine), { Volume = volume }):Play()
end

local function playMusic(key: string?)
	-- fall back to a track you do have (deep -> ocean, hunt -> ocean)
	if key and id(key) == "" then
		key = (key == "musicDeep" or key == "musicHunt") and "musicOcean" or key
		if key and id(key) == "" then
			key = nil
		end
	end
	if key == current then
		return
	end
	if current and tracks[current] then
		fadeTo(tracks[current], 0)
	end
	current = key
	if key then
		local s = tracks[key]
		if not s then
			s = loop(key, 0)
			if not s then
				return
			end
			tracks[key] = s
		end
		if not s.IsPlaying then
			s:Play()
		end
		fadeTo(s, MUSIC_VOLUME)
	end
end

----------------------------------------------------------------- rides (3D)
local rideLoops: { [Model]: { sound: Sound, key: string } } = {}

local function updateRides()
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
			local s = loop(key, 0, hrp)
			if not s then
				continue
			end
			s.RollOffMaxDistance = 140
			s.RollOffMinDistance = 12
			entry = { sound = s, key = key }
			rideLoops[char] = entry
		end
		local pos = hrp.Position
		local wet = Layout.inWater(pos) and not Layout.islandAt(pos, 0)
		local speed = (hrp.AssemblyLinearVelocity * Vector3.new(1, 0, 1)).Magnitude
		local k = math.clamp(speed / 160, 0, 1)
		local mine = p == player
		local vol = wet and ((mine and 0.25 or 0.18) + k * (mine and 0.35 or 0.25)) or 0
		entry.sound.Volume += (vol - entry.sound.Volume) * 0.15
		entry.sound.PlaybackSpeed = (spec and spec[2] or 1) * (0.85 + k * 0.45)
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

	-- ambience
	local waves = loop("ambWaves", 0.2)
	local gulls = loop("ambGulls", 0)

	local phase = "calm"
	Remotes.get("SharkEvent").OnClientEvent:Connect(function(kind)
		if kind == "warning" or kind == "hunt" then
			phase = kind
		elseif kind == "clear" then
			phase = "calm"
		end
	end)

	local wasWet = false
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		updateRides()
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
		if phase ~= "calm" then
			playMusic("musicHunt")
		elseif wet and zone and zone.index >= 5 then
			playMusic("musicDeep")
		elseif wet then
			playMusic("musicOcean")
		else
			playMusic("musicBeach")
		end
		if waves then
			waves.Volume = wet and 0.28 or 0.14
		end
		if gulls then
			gulls.Volume = (pos.Z < 80) and 0.22 or 0
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
