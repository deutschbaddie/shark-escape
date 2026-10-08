-- Builds Sounds from Config.SoundSlots: which uploaded file, which part of it
-- (PlaybackRegion / LoopRegion), pitch, EQ and a loudness gain, so every edit
-- happens in the game and the files never need re-uploading. While a file has
-- no id yet, the slot falls back (spec.fallback, then Config.Sounds built-ins).

local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Shared = game.ReplicatedStorage.Shared
local Config = require(Shared.Config)

local Sounds = {}

-- mixer groups (future volume settings can turn these)
local groups: { [string]: SoundGroup } = {}
function Sounds.group(name: string): SoundGroup
	local g = groups[name]
	if not g then
		g = Instance.new("SoundGroup")
		g.Name = name
		g.Volume = 1
		g.Parent = SoundService
		groups[name] = g
	end
	return g
end

local function asId(v: any): string
	if typeof(v) ~= "string" or v == "" then
		return ""
	end
	return v:match("^%d+$") and ("rbxassetid://" .. v) or v
end

-- the slot to use (following fallbacks) and its sound id; "" = silent
function Sounds.resolve(name: string): (Config.SoundSlot?, string)
	local seen = 0
	local key: string? = name
	while key and seen < 4 do
		seen += 1
		local spec = Config.SoundSlots[key]
		if spec then
			local id = asId(Config.SoundFiles[spec.file])
			if id ~= "" then
				return spec, id
			end
			local builtin = asId(Config.Sounds[key])
			if builtin ~= "" then
				return nil, builtin
			end
			key = spec.fallback
		else
			return nil, asId(Config.Sounds[key])
		end
	end
	return nil, ""
end

function Sounds.has(name: string): boolean
	local _, id = Sounds.resolve(name)
	return id ~= ""
end

-- A configured Sound (not playing). Its "Gain" and "Pitch" attributes hold
-- the slot's values so code that animates Volume / PlaybackSpeed can keep them.
function Sounds.make(name: string, volume: number?, pitch: number?, parent: Instance?, looped: boolean?, group: string?): Sound?
	local spec, id = Sounds.resolve(name)
	if id == "" then
		return nil
	end
	local s = Instance.new("Sound")
	s.Name = name
	s.SoundId = id
	local gain = spec and spec.gain or 1
	local basePitch = spec and spec.pitch or 1
	s:SetAttribute("Gain", gain)
	s:SetAttribute("Pitch", basePitch)
	s.Volume = math.min((volume or 0.6) * gain, 10)
	s.PlaybackSpeed = (pitch or 1) * basePitch
	s.Looped = looped == true
	if spec then
		if spec.loop then
			s.PlaybackRegionsEnabled = true
			s.PlaybackRegion = NumberRange.new(spec.loop[1], spec.loop[2])
			s.LoopRegion = NumberRange.new(spec.loop[1], spec.loop[2])
		elseif spec.from or spec.to then
			s.PlaybackRegionsEnabled = true
			s.PlaybackRegion = NumberRange.new(spec.from or 0, spec.to or 600)
		end
		if spec.eq then
			local eq = Instance.new("EqualizerSoundEffect")
			eq.LowGain = spec.eq[1] or 0
			eq.MidGain = spec.eq[2] or 0
			eq.HighGain = spec.eq[3] or 0
			eq.Parent = s
		end
	end
	if group then
		s.SoundGroup = Sounds.group(group)
	end
	s.Parent = parent or SoundService
	return s
end

-- set a made Sound's volume, keeping its slot gain
function Sounds.setVolume(s: Sound, volume: number)
	s.Volume = math.min(volume * ((s:GetAttribute("Gain") :: number?) or 1), 10)
end

-- a random start inside a loop (so several copies don't play in step)
function Sounds.randomStart(s: Sound)
	if s.PlaybackRegionsEnabled then
		local r = s.LoopRegion
		s.TimePosition = r.Min + math.random() * math.max(r.Max - r.Min, 0)
	end
end

-- play a one-shot (plus its layers) and clean up; returns the main Sound
function Sounds.play(name: string, volume: number?, pitch: number?, parent: Instance?, group: string?): Sound?
	local s = Sounds.make(name, volume, pitch, parent, false, group)
	if not s then
		return nil
	end
	local spec = Sounds.resolve(name)
	s:Play()
	local length = 6
	if spec and spec.to then
		length = (spec.to - (spec.from or 0)) / math.max(s.PlaybackSpeed, 0.05)
	end
	if spec and spec.fade and spec.to then
		local fade = spec.fade / math.max(s.PlaybackSpeed, 0.05)
		task.delay(math.max(length - fade, 0), function()
			if s.Parent then
				TweenService:Create(s, TweenInfo.new(fade), { Volume = 0 }):Play()
			end
		end)
	end
	task.delay(math.max(length, 0.2) + 0.5, function()
		if s.IsPlaying and not spec then
			return -- unknown length (built-in fallback): let Ended clean it
		end
		s:Destroy()
	end)
	s.Ended:Once(function()
		task.defer(function()
			s:Destroy()
		end)
	end)
	if spec and spec.layers then
		for _, layer in spec.layers do
			Sounds.play(layer, volume, pitch, parent, group)
		end
	end
	return s
end

return Sounds
