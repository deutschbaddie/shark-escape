-- Every tunable number in the game lives here. Balance numbers are starting
-- guesses from the REVEX ladder - tune them by playtesting, not by feel.

local Config = {}

----------------------------------------------------------------- world
Config.LANE_WIDTH = 288 -- playable ocean width (studs)
Config.SHORE_Z = 0 -- water starts here; ocean runs toward +Z
Config.WATER_Y = 0 -- terrain water surface
Config.FLOOR_TOP = 0.15 -- hidden floor players ride on (just above the surface)
Config.BEACH_TOP = 2
Config.PLOT_COUNT = 8
Config.PLOT_SPACING = 36
Config.PLOT_Z = -34

----------------------------------------------------------------- speed
-- Displayed speed climbs forever; real WalkSpeed follows a capped curve so
-- physics never breaks. 0 -> 16, 100 -> 58, 1K -> 106, 25K -> 279.
function Config.realSpeed(speed: number): number
	return math.min(16 + 9 * math.max(speed, 0) ^ (1 / 3), 320)
end

----------------------------------------------------------------- zones
export type Zone = {
	id: string,
	name: string,
	gate: number,
	length: number,
	depth: number,
	shark: string,
	sharkLength: number,
	sharkSpeed: number,
	value: number,
	islandEvery: number,
	islandRadius: number,
	water: Color3,
	clarity: number,
	floor: Enum.Material,
	floorColor: Color3,
	tint: Color3,
	zStart: number,
	zEnd: number,
	index: number,
}

Config.Zones = {
	{ id = "Lagoon", name = "Lagoon", gate = 0, length = 260, depth = 7, shark = "Baby", sharkLength = 8,
		sharkSpeed = 44, value = 1, islandEvery = 70, islandRadius = 11,
		water = Color3.fromRGB(40, 222, 226), clarity = 0.92, floor = Enum.Material.Sand,
		floorColor = Color3.fromRGB(255, 240, 196), tint = Color3.fromRGB(255, 255, 255) },
	{ id = "Reef", name = "Coral Reef", gate = 100, length = 400, depth = 12, shark = "Hammerhead", sharkLength = 12,
		sharkSpeed = 80, value = 5, islandEvery = 95, islandRadius = 10,
		water = Color3.fromRGB(26, 196, 222), clarity = 0.85, floor = Enum.Material.Sandstone,
		floorColor = Color3.fromRGB(246, 214, 170), tint = Color3.fromRGB(255, 250, 252) },
	{ id = "Kelp", name = "Kelp Forest", gate = 500, length = 560, depth = 18, shark = "Tiger", sharkLength = 14,
		sharkSpeed = 102, value = 25, islandEvery = 120, islandRadius = 9,
		water = Color3.fromRGB(24, 170, 170), clarity = 0.72, floor = Enum.Material.Mud,
		floorColor = Color3.fromRGB(92, 128, 80), tint = Color3.fromRGB(244, 255, 246) },
	{ id = "Shipwreck", name = "Shipwreck Bay", gate = 1000, length = 720, depth = 26, shark = "GreatWhite", sharkLength = 18,
		sharkSpeed = 140, value = 120, islandEvery = 150, islandRadius = 9,
		water = Color3.fromRGB(20, 132, 190), clarity = 0.6, floor = Enum.Material.Ground,
		floorColor = Color3.fromRGB(110, 96, 78), tint = Color3.fromRGB(240, 248, 255) },
	{ id = "Deep", name = "Deep Blue", gate = 5000, length = 1000, depth = 48, shark = "Mecha", sharkLength = 22,
		sharkSpeed = 215, value = 600, islandEvery = 210, islandRadius = 8,
		water = Color3.fromRGB(16, 84, 170), clarity = 0.45, floor = Enum.Material.Slate,
		floorColor = Color3.fromRGB(46, 58, 84), tint = Color3.fromRGB(228, 238, 255) },
	{ id = "Abyss", name = "The Abyss", gate = 25000, length = 1400, depth = 80, shark = "Megalodon", sharkLength = 40,
		sharkSpeed = 300, value = 3000, islandEvery = 300, islandRadius = 8,
		water = Color3.fromRGB(28, 34, 92), clarity = 0.3, floor = Enum.Material.Basalt,
		floorColor = Color3.fromRGB(30, 26, 46), tint = Color3.fromRGB(236, 226, 255) },
} :: { Zone }

do
	local z = Config.SHORE_Z
	for i, zone in Config.Zones do
		zone.index = i
		zone.zStart = z
		zone.zEnd = z + zone.length
		z = zone.zEnd
	end
end
Config.OCEAN_END = Config.Zones[#Config.Zones].zEnd

function Config.zoneAt(z: number): Zone?
	if z < Config.SHORE_Z then
		return nil
	end
	for _, zone in Config.Zones do
		if z < zone.zEnd then
			return zone
		end
	end
	return Config.Zones[#Config.Zones]
end

function Config.zoneById(id: string): Zone?
	for _, zone in Config.Zones do
		if zone.id == id then
			return zone
		end
	end
	return nil
end

-- the furthest zone this speed is allowed into
function Config.zoneForSpeed(speed: number): Zone
	local best = Config.Zones[1]
	for _, zone in Config.Zones do
		if speed >= zone.gate then
			best = zone
		end
	end
	return best
end

function Config.nextGate(speed: number): Zone?
	for _, zone in Config.Zones do
		if speed < zone.gate then
			return zone
		end
	end
	return nil
end

----------------------------------------------------------------- rides
-- No levels. Every ride is a named item; owning a better one raises your
-- speed gain. The best coin ride you own sets your base +speed/sec.
export type Ride = {
	id: string,
	name: string,
	icon: string,
	price: number,
	gain: number?,
	robux: string?,
	mult: number?,
	order: number,
}

Config.Rides = {
	{ id = "Noodle", name = "Pool Noodle", icon = "", price = 0, gain = 1 },
	{ id = "Duck", name = "Rubber Duck Floatie", icon = "", price = 30, gain = 2 },
	{ id = "Tube", name = "Inner Tube", icon = "", price = 150, gain = 3 },
	{ id = "Boogie", name = "Boogie Board", icon = "", price = 600, gain = 4 },
	{ id = "Surf", name = "Surfboard", icon = "", price = 2000, gain = 5 },
	{ id = "Bathtub", name = "Bathtub", icon = "", price = 7000, gain = 7 },
	{ id = "Banana", name = "Banana Boat", icon = "", price = 24000, gain = 9 },
	{ id = "JetSki", name = "Jet Ski", icon = "", price = 80000, gain = 12 },
	{ id = "Speedboat", name = "Speedboat", icon = "", price = 270000, gain = 16 },
	{ id = "Dolphin", name = "Dolphin", icon = "", price = 900000, gain = 22 },
	{ id = "Donut", name = "Giant Donut", icon = "", price = 3000000, gain = 30 },
	{ id = "Rocket", name = "Rocket Surfboard", icon = "", price = 10000000, gain = 40 },
	-- Robux rides: never skip the ladder, they multiply it.
	{ id = "GoldDuck", name = "Golden Duck", icon = "", price = 0, robux = "GoldDuck", mult = 1.25 },
	{ id = "SharkBoard", name = "Shark Board", icon = "", price = 0, robux = "SharkBoard", mult = 1.5 },
	{ id = "RainbowSki", name = "Rainbow Jet Ski", icon = "", price = 0, robux = "RainbowSki", mult = 2 },
} :: { Ride }

for i, ride in Config.Rides do
	ride.order = i
end

function Config.ride(id: string): Ride?
	for _, ride in Config.Rides do
		if ride.id == id then
			return ride
		end
	end
	return nil
end

-- How each ride handles on the water (client ride controller):
--   stance   pose: stand / sit / straddle / prone / float
--   accel    seconds to reach top speed      coast  seconds to drift to a stop
--   turn     turn rate (rad/s)               grip   how fast sideways slide dies
--   lean     roll into turns                 plane  nose-up at speed
--   bob      bob height (studs), bobSpeed    wobble idle side-to-side yaw
--   porpoise dolphin-style dive arcs         hop    jump velocity
export type RideFeel = {
	stance: string, accel: number, coast: number, turn: number, grip: number, lean: number,
	bob: number, bobSpeed: number, plane: number?, wobble: number?, porpoise: boolean?, hop: number?,
}
Config.RideFeel = {
	Noodle = { stance = "float", accel = 1.0, coast = 1.4, turn = 2.8, grip = 3, lean = 0.1, bob = 0.3, bobSpeed = 2.0, wobble = 0.06 },
	Duck = { stance = "sit", accel = 0.9, coast = 1.2, turn = 3.0, grip = 3.5, lean = 0.12, bob = 0.45, bobSpeed = 3.2, wobble = 0.1 },
	Tube = { stance = "sit", accel = 0.9, coast = 1.8, turn = 2.4, grip = 1.6, lean = 0.08, bob = 0.35, bobSpeed = 2.4, wobble = 0.25 },
	Boogie = { stance = "prone", accel = 0.8, coast = 1.2, turn = 3.4, grip = 4, lean = 0.3, bob = 0.2, bobSpeed = 3 },
	Surf = { stance = "stand", accel = 0.7, coast = 1.5, turn = 3.2, grip = 4.5, lean = 0.55, bob = 0.15, bobSpeed = 2.5, plane = 0.05 },
	Bathtub = { stance = "sit", accel = 1.4, coast = 2.2, turn = 1.8, grip = 2.2, lean = 0.06, bob = 0.25, bobSpeed = 1.6, wobble = 0.12 },
	Banana = { stance = "straddle", accel = 0.9, coast = 1.4, turn = 2.0, grip = 3, lean = 0.2, bob = 0.35, bobSpeed = 2.8 },
	JetSki = { stance = "straddle", accel = 0.45, coast = 1.0, turn = 4.2, grip = 2.2, lean = 0.6, bob = 0.18, bobSpeed = 4, plane = 0.12 },
	Speedboat = { stance = "straddle", accel = 0.6, coast = 1.3, turn = 2.6, grip = 3.5, lean = 0.25, bob = 0.12, bobSpeed = 3, plane = 0.18 },
	Dolphin = { stance = "straddle", accel = 0.5, coast = 1.2, turn = 4.6, grip = 5, lean = 0.4, bob = 1.1, bobSpeed = 3.4, porpoise = true, hop = 40 },
	Donut = { stance = "sit", accel = 0.8, coast = 2.0, turn = 3.0, grip = 1.2, lean = 0.1, bob = 0.4, bobSpeed = 2.6, wobble = 0.35 },
	Rocket = { stance = "stand", accel = 0.3, coast = 0.9, turn = 3.0, grip = 5, lean = 0.45, bob = 0.1, bobSpeed = 6, plane = 0.1 },
} :: { [string]: RideFeel }
Config.RideFeel.GoldDuck = Config.RideFeel.Duck
Config.RideFeel.SharkBoard = { stance = "stand", accel = 0.6, coast = 1.4, turn = 3.6, grip = 4.5, lean = 0.6, bob = 0.15, bobSpeed = 2.5, plane = 0.06 }
Config.RideFeel.RainbowSki = Config.RideFeel.JetSki

function Config.feel(rideId: string?): RideFeel
	return Config.RideFeel[rideId or "Noodle"] or Config.RideFeel.Noodle
end

----------------------------------------------------------------- creatures
export type Rarity = { id: string, weight: number, mult: number, color: Color3, species: string, icon: string, index: number }

Config.Rarities = {
	{ id = "Common", weight = 60, mult = 1, color = Color3.fromRGB(205, 214, 224), species = "Clownfish", icon = "" },
	{ id = "Uncommon", weight = 25, mult = 2.5, color = Color3.fromRGB(96, 214, 110), species = "Pufferfish", icon = "" },
	{ id = "Rare", weight = 10, mult = 6, color = Color3.fromRGB(64, 156, 255), species = "Octopus", icon = "" },
	{ id = "Epic", weight = 4, mult = 25, color = Color3.fromRGB(190, 92, 255), species = "Sea Turtle", icon = "" },
	{ id = "Legendary", weight = 1, mult = 120, color = Color3.fromRGB(255, 196, 40), species = "Narwhal", icon = "" },
} :: { Rarity }
for i, r in Config.Rarities do
	r.index = i
end

-- Every zone has its own 5 creatures (one per rarity): 30 to collect.
-- kind = which blocky builder (Creatures.luau); c1/c2/c3 = colors; flags
-- tweak the build (glow, bill, lure, horn, shell...).
export type Species = {
	name: string, kind: string, icon: string, c1: Color3, c2: Color3, c3: Color3?,
	glow: boolean?, bill: boolean?, lure: boolean?, horn: boolean?, shell: boolean?, long: boolean?,
	ghost: boolean?, horns: boolean?, size: number?,
}
local RGB = Color3.fromRGB
Config.Species = {
	Lagoon = {
		Common = { name = "Clownfish", kind = "fish", icon = "", c1 = RGB(255, 128, 32), c2 = RGB(255, 255, 255), c3 = RGB(30, 30, 40) },
		Uncommon = { name = "Hermit Crab", kind = "crab", icon = "", c1 = RGB(255, 110, 80), c2 = RGB(240, 200, 150), shell = true },
		Rare = { name = "Pufferfish", kind = "puffer", icon = "", c1 = RGB(255, 214, 64), c2 = RGB(255, 245, 210) },
		Epic = { name = "Sea Turtle", kind = "turtle", icon = "", c1 = RGB(70, 170, 90), c2 = RGB(150, 110, 60) },
		Legendary = { name = "Narwhal", kind = "whale", icon = "", c1 = RGB(150, 190, 230), c2 = RGB(240, 248, 255), horn = true },
	},
	Reef = {
		Common = { name = "Blue Tang", kind = "fish", icon = "", c1 = RGB(40, 110, 230), c2 = RGB(25, 30, 60), c3 = RGB(255, 220, 40) },
		Uncommon = { name = "Seahorse", kind = "seahorse", icon = "", c1 = RGB(255, 150, 60), c2 = RGB(255, 210, 120) },
		Rare = { name = "Octopus", kind = "ceph", icon = "", c1 = RGB(235, 80, 120), c2 = RGB(255, 170, 190) },
		Epic = { name = "Manta Ray", kind = "ray", icon = "", c1 = RGB(40, 60, 100), c2 = RGB(235, 240, 250) },
		Legendary = { name = "Coral Dragon", kind = "serpent", icon = "", c1 = RGB(255, 110, 150), c2 = RGB(255, 220, 120), horns = true },
	},
	Kelp = {
		Common = { name = "Parrotfish", kind = "fish", icon = "", c1 = RGB(70, 210, 150), c2 = RGB(255, 120, 200), c3 = RGB(255, 230, 90) },
		Uncommon = { name = "Spider Crab", kind = "crab", icon = "", c1 = RGB(200, 70, 50), c2 = RGB(255, 170, 120), long = true },
		Rare = { name = "Jellyfish", kind = "jelly", icon = "", c1 = RGB(255, 140, 220), c2 = RGB(255, 220, 245), glow = true },
		Epic = { name = "Squid", kind = "ceph", icon = "", c1 = RGB(240, 150, 120), c2 = RGB(255, 210, 190), long = true },
		Legendary = { name = "Sea Dragon", kind = "serpent", icon = "", c1 = RGB(90, 180, 70), c2 = RGB(220, 240, 120) },
	},
	Shipwreck = {
		Common = { name = "Moray Eel", kind = "serpent", icon = "", c1 = RGB(120, 140, 60), c2 = RGB(220, 210, 120), size = 0.8 },
		Uncommon = { name = "Lobster", kind = "crab", icon = "", c1 = RGB(220, 40, 40), c2 = RGB(255, 140, 110), long = true, shell = false },
		Rare = { name = "Swordfish", kind = "fish", icon = "", c1 = RGB(70, 90, 150), c2 = RGB(220, 230, 245), c3 = RGB(30, 40, 70), bill = true },
		Epic = { name = "Ghost Octopus", kind = "ceph", icon = "", c1 = RGB(210, 240, 255), c2 = RGB(150, 220, 255), ghost = true },
		Legendary = { name = "Orca", kind = "whale", icon = "", c1 = RGB(25, 28, 40), c2 = RGB(255, 255, 255), size = 1.05 },
	},
	Deep = {
		Common = { name = "Lanternfish", kind = "fish", icon = "", c1 = RGB(40, 50, 90), c2 = RGB(80, 230, 255), c3 = RGB(20, 20, 40), glow = true },
		Uncommon = { name = "Anglerfish", kind = "fish", icon = "", c1 = RGB(70, 50, 80), c2 = RGB(255, 240, 120), c3 = RGB(30, 20, 40), lure = true },
		Rare = { name = "Giant Squid", kind = "ceph", icon = "", c1 = RGB(180, 40, 50), c2 = RGB(255, 120, 110), long = true },
		Epic = { name = "Moon Ray", kind = "ray", icon = "", c1 = RGB(60, 70, 140), c2 = RGB(160, 220, 255), glow = true },
		Legendary = { name = "Leviathan", kind = "serpent", icon = "", c1 = RGB(30, 90, 140), c2 = RGB(90, 230, 255), horns = true, glow = true, size = 1.2 },
	},
	Abyss = {
		Common = { name = "Glowfish", kind = "fish", icon = "", c1 = RGB(90, 255, 200), c2 = RGB(20, 40, 60), c3 = RGB(20, 20, 30), glow = true },
		Uncommon = { name = "Abyss Jelly", kind = "jelly", icon = "", c1 = RGB(140, 90, 255), c2 = RGB(220, 200, 255), glow = true },
		Rare = { name = "Vampire Squid", kind = "ceph", icon = "", c1 = RGB(90, 20, 40), c2 = RGB(255, 60, 90), glow = true },
		Epic = { name = "Megalodon Pup", kind = "whale", icon = "", c1 = RGB(110, 130, 160), c2 = RGB(235, 240, 250), fin = true },
		Legendary = { name = "Kraken", kind = "ceph", icon = "", c1 = RGB(60, 20, 70), c2 = RGB(255, 80, 200), glow = true, size = 1.12 },
	},
} :: any

function Config.species(zoneId: string?, rarityId: string): Species
	local z = Config.Species[zoneId or "Lagoon"] or Config.Species.Lagoon
	return z[rarityId] or z.Common
end

-- "Gold Clownfish", "Octopus"...
function Config.creatureName(zoneId: string?, rarityId: string, mutationId: string?): string
	return (mutationId and (mutationId .. " ") or "") .. Config.species(zoneId, rarityId).name
end

function Config.rarity(id: string): Rarity
	for _, r in Config.Rarities do
		if r.id == id then
			return r
		end
	end
	return Config.Rarities[1]
end

export type Mutation = { id: string, chance: number, mult: number, color: Color3 }
Config.Mutations = {
	{ id = "Rainbow", chance = 0.003, mult = 6, color = Color3.fromRGB(255, 120, 220) },
	{ id = "Diamond", chance = 0.01, mult = 5, color = Color3.fromRGB(150, 236, 255) },
	{ id = "Gold", chance = 0.03, mult = 2, color = Color3.fromRGB(255, 205, 60) },
} :: { Mutation }

function Config.mutation(id: string?): Mutation?
	for _, m in Config.Mutations do
		if m.id == id then
			return m
		end
	end
	return nil
end

-- coins per second for one creature
function Config.creatureValue(rarityId: string, zoneId: string, mutationId: string?, size: number?): number
	local zone = Config.zoneById(zoneId)
	local m = Config.mutation(mutationId)
	return (zone and zone.value or 1) * Config.rarity(rarityId).mult * (m and m.mult or 1) * Config.sizeValue(size)
end

----------------------------------------------------------------- size + weight
-- Every catch has a size: most are close to 1x, some are Big, a rare few are
-- Huge. Weight = the species' usual weight x size. Bigger ones earn a bit
-- more (x size^0.5) and look bigger in your tank.
Config.KIND_KG = {
	fish = 2, puffer = 1.6, crab = 3, turtle = 48, whale = 900, seahorse = 0.4,
	ceph = 14, ray = 36, serpent = 180, jelly = 0.8,
}

function Config.rollSize(rng: Random): number
	local x = rng:NextNumber()
	local s
	if x < 0.008 then
		s = rng:NextNumber(2.0, 3.0) -- Huge
	elseif x < 0.05 then
		s = rng:NextNumber(1.4, 1.9) -- Big
	else
		s = 0.75 + (rng:NextNumber() + rng:NextNumber()) / 2 * 0.55 -- 0.75..1.3, mostly ~1
	end
	return math.floor(s * 100 + 0.5) / 100
end

function Config.sizeLabel(size: number?): string?
	local s = size or 1
	return s >= 2 and "Huge" or s >= 1.4 and "Big" or nil
end

function Config.sizeValue(size: number?): number
	return math.sqrt(size or 1)
end

-- how much bigger it looks (volume grows with weight)
function Config.sizeScale(size: number?): number
	return (size or 1) ^ (1 / 3)
end

function Config.creatureKg(zoneId: string?, rarityId: string, size: number?): number
	local sp = Config.species(zoneId, rarityId)
	local zone = Config.zoneById(zoneId or "Lagoon")
	local base = (Config.KIND_KG[sp.kind] or 2) * (sp.size or 1)
	base *= 1 + ((zone and zone.index or 1) - 1) * 0.6
	base *= 1 + (Config.rarity(rarityId).index - 1) * 0.25
	return base * (size or 1)
end

function Config.formatKg(kg: number): string
	if kg >= 1000 then
		return ("%.1f t"):format(kg / 1000)
	elseif kg >= 100 then
		return ("%d kg"):format(math.floor(kg + 0.5))
	end
	return ("%.1f kg"):format(kg)
end

-- "Huge Gold Octopus"
function Config.fullName(zoneId: string?, rarityId: string, mutationId: string?, size: number?): string
	local label = Config.sizeLabel(size)
	return (label and (label .. " ") or "") .. Config.creatureName(zoneId, rarityId, mutationId)
end

Config.Luck = {
	base = 0.05, -- chance a grab bumps up one rarity ("LUCKY!")
	pass = 0.15,
	potion = 0.15,
	pityGrab = 5, -- the 5th creature you ever grab is at least Rare
	pityEpic = 30, -- and the 30th is at least Epic (if you've never had one)
}

Config.BUBBLES_PER_ZONE = 9
Config.GRAB_RADIUS = 6.5
Config.DEPOSIT_RADIUS = 15
Config.COLLECT_RADIUS = 6
Config.SELL_SECONDS = 20 -- a creature that doesn't fit sells for this many seconds of its income

----------------------------------------------------------------- tank
-- Your tank: everything you catch is kept (up to `storage`); the best ones
-- are Active and earn money. "+1 EQUIP" buys another active slot.
Config.Tank = {
	startSlots = 4,
	maxSlots = 12,
	passSlots = 4,
	-- price of active slot #5, #6, ... #12
	slotPrices = { 400, 2000, 8000, 30000, 120000, 500000, 2000000, 8000000 },
	maxDead = 10, -- unequipped catches lie "dead" on the tank floor (no income); past this you must sell some
}

-- hold time (seconds) on the grab prompt: rarer = longer = riskier
Config.GrabHold = { Common = 0.35, Uncommon = 0.55, Rare = 0.8, Epic = 1.1, Legendary = 1.5 }

-- +10% coins per friend in your server (max +50%)
Config.FriendBoost = { per = 0.1, max = 0.5 }

-- Slow Mode caps your speed so precise grabs are easy at high speed
Config.SLOW_SPEED = 26

-- Codes (case-insensitive, once per player). Edit freely.
Config.Codes = {
	SHARK = { coins = 250, speed = 50 },
	RELEASE = { coins = 1000, speed = 100 },
	CHOMP = { shields = 1 },
}

----------------------------------------------------------------- sharks
Config.Shark = {
	cycle = 80, -- average seconds between attacks (HUD fallback; real gaps are random)
	firstAttack = 70,
	warning = 5, -- "SHARK INCOMING" countdown: time to get to sand
	hunt = 22, -- average hunt (HUD fallback)
	-- randomized so hunts can't be timed to the second
	calmMin = 50, calmMax = 92, -- calm between the end of a hunt and the next warning
	huntMin = 18, huntMax = 28,
	doubleChance = 0.25, -- two sharks at once (zones from doubleFromZone out)
	doubleFromZone = 3,
	spawnDistance = 46,
	-- a hunting shark circles you once (a tightening spiral), charges, then
	-- LUNGES: it leaps out of the water at where you'll be (your velocity x
	-- the flight time). A red ring marks the landing spot the moment it
	-- jumps: hold course and it lands on you; whip, turn hard or hop and it
	-- splashes down empty ("DODGED!") and has to come round again.
	stalk = 2.6, -- seconds of circling before the first charge
	recircle = 1.3, -- after a miss
	stalkRadius = 24,
	stalkEnd = 13,
	chargeMult = 1.35, -- charge speed vs the zone's shark speed...
	chargeVsPlayer = 1.22, -- ...and never slower than this x your top speed
	chargeRadius = 26, -- turning circle while charging (studs): same feel at any speed
	chargeGiveUp = 4,
	lungeRange = 22, -- commits to the leap this close (studs)...
	lungeRangeMax = 32, -- ...a bit further when you're fast
	lungeMinCharge = 0.5, -- seconds of charging ("IT'S CHARGING!") before it can leap
	lungeLead = 1.0, -- aims at your velocity x flight time x this
	lungeHop = 3, -- this high above the water at landing = you hopped over it
	lungeGap = 1.4, -- two sharks on you: the second waits this long after a landing
	maxHunters = 24,
	newPlayerGrace = 150, -- seconds before a brand-new player can be hunted
	eatenTime = 3.0, -- length of the bite cutscene before you wash up
	frenzyLuck = 0.3, -- extra chance to bump a grab up a rarity while it hunts
	-- islands are shelter, not a bunker: each island covers you this long per
	-- hunt (a different island = a fresh timer), then the shark can reach you
	islandShelter = 9,
	islandWarn = 3, -- "Island sinking! Move!" this many seconds before
	-- a carried creature wriggles free if you take too long to bring it home
	freshBase = 45, -- seconds (Lagoon)...
	freshPerZone = 3, -- ...+ this per zone deeper (Abyss: 60)
	freshWarn = 10,
}

-- lunge tuning for a player whose top speed is `speed`, vs a shark of length
-- L: flight time (s), bite radius (studs), commit range (studs). Slow players
-- get a longer flight and a tighter bite so a late swerve still works.
function Config.lunge(speed: number, L: number): (number, number, number)
	local k = math.clamp((speed - 16) / 234, 0, 1)
	local time = 1.0 - 0.2 * k
	local radius = math.clamp(L * 0.35, 5, 7.5) * (0.85 + 0.15 * k)
	local range = math.clamp(Config.Shark.lungeRange + speed * 0.04, Config.Shark.lungeRange, Config.Shark.lungeRangeMax)
	return time, radius, range
end

-- how far a rider going `speed` (changing at `accel` studs/s^2, capped at 0
-- and `top`) travels in `time`: where the lunge aims along your course
function Config.lungeTravel(speed: number, accel: number, top: number, time: number): number
	local goal = accel >= 0 and math.max(top, speed) or 0
	if math.abs(accel) < 1e-3 then
		return speed * time
	end
	local reach = math.clamp((goal - speed) / accel, 0, time)
	return speed * reach + 0.5 * accel * reach * reach + goal * (time - reach)
end

-- how long a carried creature stays in your hands from zone zoneId
function Config.freshTime(zoneId: string?): number
	local zone = zoneId and Config.zoneById(zoneId)
	return Config.Shark.freshBase + (zone and zone.index - 1 or 0) * Config.Shark.freshPerZone
end

----------------------------------------------------------------- rebirth
Config.Rebirth = { speed = 25000, mult = 1.5 }

----------------------------------------------------------------- monetization
-- Fill these in from Creator Dashboard after you create the passes/products.
-- An id of 0 hides the buy button instead of prompting a fake purchase.
Config.Passes = {
	TwoXSpeed = { iconName = "X2Speed", id = 0, price = 399, name = "2x Speed", icon = "", desc = "Double speed gain forever" },
	TwoXCoins = { iconName = "X2Coins", id = 0, price = 199, name = "2x Coins", icon = "", desc = "Double coins from your tank" },
	AutoCollect = { iconName = "Magnet", id = 0, price = 99, name = "Auto Collect", icon = "", desc = "Coins go straight to you" },
	LuckyNet = { iconName = "Clover", id = 0, price = 199, name = "Lucky Net", icon = "", desc = "+15% chance to upgrade rarity" },
	BigTank = { iconName = "BigTank", id = 0, price = 99, name = "+4 Tank Slots", icon = "", desc = "Room for 4 more creatures" },
	VIP = { iconName = "Crown", id = 0, price = 399, name = "VIP", icon = "", desc = "Gold wake, VIP tag, +10% coins" },
	GoldDuck = { iconName = "GoldDuck", id = 0, price = 99, name = "Golden Duck", icon = "", desc = "Ride it - x1.25 speed gain" },
	SharkBoard = { iconName = "SharkBoard", id = 0, price = 199, name = "Shark Board", icon = "", desc = "Ride it - x1.5 speed gain" },
	RainbowSki = { iconName = "RainbowSki", id = 0, price = 399, name = "Rainbow Jet Ski", icon = "", desc = "Ride it - x2 speed gain" },
}

Config.Products = {
	Shield = { iconName = "Shield", id = 0, price = 25, name = "Shark Shield", icon = "", desc = "Survive one bite, keep your creature" },
	SpeedBoost = { iconName = "Boost", id = 0, price = 49, name = "2x Speed (15 min)", icon = "", desc = "Double speed gain for 15 minutes" },
	LuckPotion = { iconName = "Potion", id = 0, price = 49, name = "Luck Potion (10 min)", icon = "", desc = "+15% rarity upgrade chance" },
	GoldenBubble = { iconName = "GoldBubble", id = 0, price = 99, name = "Golden Bubble", icon = "",
		desc = "Rare 70% · Epic 25% · Legendary 5%" },
	StarterPack = { iconName = "Gift", id = 0, price = 49, name = "Starter Pack", icon = "",
		desc = "A Rare creature + 30 min 2x Speed + 3 Shields" },
	DoubleOffline = { iconName = "Clock", id = 0, price = 25, name = "2x Offline Coins", icon = "", desc = "Double your welcome-back coins" },
}

Config.GoldenBubbleOdds = { { "Rare", 70 }, { "Epic", 25 }, { "Legendary", 5 } }
Config.SHOP_UNLOCK_SECONDS = 300 -- no Robux prompts or offers in the first 5 minutes

----------------------------------------------------------------- index
-- Every rarity in every zone is one Index entry. Discovering one unlocks a
-- one-time reward; deeper zones and rarer creatures pay more.
function Config.indexKey(zoneId: string, rarityId: string): string
	return zoneId .. ":" .. rarityId
end

function Config.indexReward(zoneId: string, rarityId: string): (number, number)
	local zone = Config.zoneById(zoneId)
	local r = Config.rarity(rarityId)
	local v = zone and zone.value or 1
	local coins = math.floor(5 * v * r.mult ^ 0.7)
	local speed = math.floor((5 + (zone and zone.gate or 0) * 0.02) * r.index)
	return coins, speed
end

----------------------------------------------------------------- offline
-- Your tank keeps earning while you're away (at a slower rate, capped).
Config.Offline = { rate = 0.1, maxHours = 8, minSeconds = 120 }

-- what your tank makes per day while you're offline
function Config.offlinePerDay(income: number): number
	return income * Config.Offline.rate * 86400
end

----------------------------------------------------------------- images
-- Stud texture: "Studs" by aetoreous (public domain). Decal 6927295857,
-- image 6927295847. The image is a 4x4 grid of studs.
Config.Images = {
	Studs = "rbxassetid://6927295847",
	StudsWorldTile = 8, -- studs of world space one image tile covers on parts
}

-- Custom icons. Upload each PNG from assets/icons/single/ (Asset Manager >
-- Import) and paste its id next to its name in `ids` ("rbxassetid://123" or
-- just the number). Order of use: ids[name] > sheet > emoji fallback.
-- (The two sheets in assets/icons work too; leave them "" when using singles.)
Config.Icons = {
	ids = {
		-- HUD (upload these first)
		Sneaker = "", Cash = "", Shop = "", Index = "", Rides = "", Tank = "", Rebirth = "", Shark = "",
		-- popups, shop cards, guide
		Arrow = "", Clock = "", MoneyBag = "", Gift = "", Speed = "", Coins = "",
		X2Speed = "", X2Coins = "", Magnet = "", Clover = "", BigTank = "", Crown = "",
		GoldDuck = "", SharkBoard = "", RainbowSki = "", Shield = "", Boost = "", Potion = "", GoldBubble = "",
		Lock = "", Trophy = "", Sparkle = "", Chest = "", Fin = "", Fish = "", Island = "",
		-- new HUD icons (upload as single images)
		Friends = "", Coral = "", Settings = "",
	},
	SheetA = "",
	SheetB = "",
	cells = {
		Speed = { "A", 1 }, Coins = { "A", 2 }, Rides = { "A", 3 }, Index = { "A", 4 },
		Shop = { "A", 5 }, Rebirth = { "A", 6 }, Shark = { "A", 7 }, Tank = { "A", 8 },
		Shield = { "A", 9 }, Boost = { "A", 10 }, Potion = { "A", 11 }, Lock = { "A", 12 },
		Gift = { "A", 13 }, Clock = { "A", 14 }, Trophy = { "A", 15 }, Sparkle = { "A", 16 },
		X2Speed = { "B", 1 }, X2Coins = { "B", 2 }, Magnet = { "B", 3 }, Clover = { "B", 4 },
		BigTank = { "B", 5 }, Crown = { "B", 6 }, GoldDuck = { "B", 7 }, SharkBoard = { "B", 8 },
		RainbowSki = { "B", 9 }, GoldBubble = { "B", 10 }, Chest = { "B", 11 }, Fin = { "B", 12 },
		Arrow = { "B", 13 }, MoneyBag = { "B", 14 }, Fish = { "B", 15 }, Island = { "B", 16 },
		Sneaker = { "A", 1 }, Cash = { "B", 14 },
	},
}

----------------------------------------------------------------- audio
-- rbxasset:// sounds ship with every Roblox client. Empty strings are slots
-- for Creator Store audio you pick and record in ASSETS.md (never invent ids).
----------------------------------------------------------------- group chest + daily rewards
-- Your Roblox group's id. 0 = no group yet: the chest then only asks for a
-- like (favorite) and still pays out, so it works before the group exists.
Config.GroupId = 902411651
Config.GroupChest = { cooldownHours = 12, incomeSeconds = 180, minCoins = 150, boostMinutes = 10 }

-- 7-day streak (claim once every 20h; miss 48h and it starts over at day 1)
Config.Daily = {
	{ kind = "boost", minutes = 10, label = "2x Speed 10 min", icon = "Boost" },
	{ kind = "shield", amount = 1, label = "Shark Shield", icon = "Shield" },
	{ kind = "coins", seconds = 120, min = 100, label = "Bag of Cash", icon = "Cash" },
	{ kind = "luck", minutes = 15, label = "Luck Potion", icon = "Potion" },
	{ kind = "coins", seconds = 600, min = 500, label = "Big Cash", icon = "Cash" },
	{ kind = "creature", rarity = "Epic", label = "Epic Creature", icon = "GoldBubble" },
	{ kind = "creature", rarity = "Legendary", size = 2.2, label = "Huge Legendary", icon = "Crown", limited = true },
} :: { { [string]: any } }
Config.DAILY_GAP_HOURS, Config.DAILY_RESET_HOURS = 20, 48

Config.Sounds = {
	-- music (Audio.luau). One track for the whole game; give a place its own
	-- track by filling its slot (the hunt slot, if empty, ducks the main track)
	music = "rbxassetid://1846088038",
	musicBeach = "",
	musicOcean = "",
	musicDeep = "",
	musicHunt = "",
}

-- 1) The Roblox id of every uploaded sound file (upload them exactly as they
--    are; the names are the file names). Paste the number, with or without
--    "rbxassetid://". Empty = that sound uses its built-in fallback or is
--    silent. Sources and licenses: ASSETS.md.
Config.SoundFiles = {
	["mixkit-soap-bubble-sound-2925"] = "rbxassetid://91161037960580",
	["mixkit-explainer-video-pops-whoosh-light-pop-3005"] = "rbxassetid://132051161428247",
	["mixkit-boing-hit-sound-2894"] = "rbxassetid://81137746729164",
	["mixkit-dry-pop-up-notification-alert-2356"] = "rbxassetid://130268760790939",
	["mixkit-movie-whoosh-impact-presentation-2903"] = "rbxassetid://93945704934482",
	["mixkit-water-bubble-1317"] = "rbxassetid://109536715402499",
	["mixkit-sea-water-splash-1198"] = "rbxassetid://78768880176281",
	["mixkit-fairy-magic-sparkle-871"] = "rbxassetid://124096247708665",
	["mixkit-successful-horns-fanfare-722"] = "rbxassetid://116467160770080",
	["mixkit-melodic-bonus-collect-1938"] = "rbxassetid://114365963704853",
	["mixkit-page-forward-single-chime-1107"] = "rbxassetid://93383166774303",
	["mixkit-liquid-bubble-3000"] = "rbxassetid://78767914886421",
	["mixkit-clinking-coins-1993"] = "rbxassetid://133067320326955",
	["mixkit-money-bag-drop-1989"] = "rbxassetid://94615652928279",
	["184438__capslok__cash-register-fake"] = "rbxassetid://128288863011143",
	["mixkit-unlock-new-item-game-notification-254"] = "rbxassetid://90531968965473",
	["mixkit-achievement-completed-2068"] = "rbxassetid://94011401770356",
	["mixkit-facility-alarm-sound-999"] = "rbxassetid://119351650727606",
	["mixkit-aggressive-beast-roar-13"] = "rbxassetid://133338904418165",
	["528962__steenish__crunch"] = "rbxassetid://114947460738011",
	["445118__breviceps__cartoon-splat"] = "rbxassetid://87181834248801",
	["mixkit-arrow-whoosh-1491"] = "rbxassetid://97268804826952",
	["350917__csaszi__rubber-duck-csg"] = "rbxassetid://105370668810111",
	["456151__jfournier18__dolphin-noise"] = "rbxassetid://96059363771818",
	["mixkit-sea-swimming-loop-1181"] = "rbxassetid://131576493971250",
	["188199__splicesound__paddle-boat-on-water-2"] = "rbxassetid://79089636097979",
	["443870__eardeer__water_flow_dam_close_loop"] = "rbxassetid://123327977782557",
	["mixkit-deep-water-bubbles-1321"] = "rbxassetid://76938595911508",
	["454199__kyles__speed-boat-outboard-motor-medium-high-gear-waves-splash"] = "rbxassetid://117099041120300",
	["212441__wjauch__jetski"] = "rbxassetid://103155995162396",
	["171106__qubodup__rocket-flight-loop"] = "rbxassetid://128168593084712",
	["mixkit-sea-waves-loop-1196"] = "rbxassetid://110907888719466",
	["seagulls_distant"] = "rbxassetid://94208672690861",
}

-- 2) What every game sound plays. All editing happens in the game with
--    Roblox's own sound settings and effects, so files never need re-uploading:
--      from/to   play only that part of the file (seconds)
--      loop      loop just that part (points picked where the waveform lines up)
--      gain      loudness match between files (measured from the files), times
--                the volume the game asks for
--      pitch     playback speed (lower = deeper and slower)
--      eq        { low, mid, high } in dB (EqualizerSoundEffect)
--      fade      fade out over the last N seconds
--      layers    other entries played with it at the same time
--      every     ride loops only: { entry, min gap s, max gap s, volume } now and then
--      fallback  entry to use while this one's file has no id
export type SoundSlot = {
	file: string, from: number?, to: number?, loop: { number }?, gain: number?, pitch: number?,
	eq: { number }?, fade: number?, layers: { string }?, every: { any }?, fallback: string?,
}
local F = {
	soap = "mixkit-soap-bubble-sound-2925", pop = "mixkit-explainer-video-pops-whoosh-light-pop-3005",
	boing = "mixkit-boing-hit-sound-2894", dryPop = "mixkit-dry-pop-up-notification-alert-2356",
	whoosh = "mixkit-movie-whoosh-impact-presentation-2903", bubble = "mixkit-water-bubble-1317",
	splash = "mixkit-sea-water-splash-1198", sparkle = "mixkit-fairy-magic-sparkle-871",
	fanfare = "mixkit-successful-horns-fanfare-722", bonus = "mixkit-melodic-bonus-collect-1938",
	chime = "mixkit-page-forward-single-chime-1107", liquid = "mixkit-liquid-bubble-3000",
	coins = "mixkit-clinking-coins-1993", bag = "mixkit-money-bag-drop-1989",
	register = "184438__capslok__cash-register-fake", unlock = "mixkit-unlock-new-item-game-notification-254",
	achieve = "mixkit-achievement-completed-2068", alarm = "mixkit-facility-alarm-sound-999",
	roar = "mixkit-aggressive-beast-roar-13", crunch = "528962__steenish__crunch",
	splat = "445118__breviceps__cartoon-splat", arrow = "mixkit-arrow-whoosh-1491",
	duck = "350917__csaszi__rubber-duck-csg", dolphin = "456151__jfournier18__dolphin-noise",
	swim = "mixkit-sea-swimming-loop-1181", paddle = "188199__splicesound__paddle-boat-on-water-2",
	flow = "443870__eardeer__water_flow_dam_close_loop", deep = "mixkit-deep-water-bubbles-1321",
	boat = "454199__kyles__speed-boat-outboard-motor-medium-high-gear-waves-splash", jetski = "212441__wjauch__jetski",
	rocket = "171106__qubodup__rocket-flight-loop", waves = "mixkit-sea-waves-loop-1196", gulls = "seagulls_distant",
}
Config.SoundSlots = {
	-- UI
	uiClick = { file = F.soap, from = 0, to = 0.13, gain = 0.45 },
	uiOpen = { file = F.pop, gain = 0.4 },
	uiClose = { file = F.pop, pitch = 0.8, gain = 0.4 }, -- the open pop, lower
	uiError = { file = F.boing, from = 0, to = 0.5, gain = 0.21, fade = 0.1 },
	uiToast = { file = F.dryPop, gain = 0.81 },
	uiTakeover = { file = F.arrow, from = 0.1, to = 0.5, pitch = 0.85, gain = 0.44 }, -- a quick swoosh
	-- catching + money
	grab = { file = F.bubble, gain = 1.06, layers = { "grabSplash" } },
	grabSplash = { file = F.splash, from = 0.45, to = 1.0, gain = 0.46, fade = 0.15 },
	grabRare = { file = F.sparkle, gain = 0.69 },
	legendary = { file = F.fanfare, gain = 0.69 },
	lucky = { file = F.bonus, gain = 0.56 },
	discover = { file = F.chime, gain = 0.61 },
	deposit = { file = F.liquid, from = 0, to = 0.6, gain = 0.43 },
	coin = { file = F.coins, from = 0.03, to = 0.75, gain = 0.73 },
	collect = { file = F.bag, from = 0.08, to = 0.5, gain = 1.1, fallback = "coin" },
	buy = { file = F.register, from = 0.05, to = 1.6, gain = 1.75, fade = 0.3 },
	-- progression
	rideNew = { file = F.unlock, gain = 0.95 },
	zoneUnlock = { file = F.achieve, gain = 2.39 },
	rebirth = { file = F.achieve, pitch = 0.84, gain = 2.39, layers = { "rebirthWhoosh" } },
	rebirthWhoosh = { file = F.whoosh, from = 0.1, to = 2.6, gain = 0.23, fade = 0.5 },
	-- shark
	sharkAlarm = { file = F.alarm, from = 0, to = 2.0, gain = 0.58, fade = 0.25 },
	sharkCharge = { file = F.roar, pitch = 0.78, eq = { 2, 0, -10 }, gain = 0.42, layers = { "chargeSplash" } },
	chargeSplash = { file = F.splash, from = 0.45, to = 1.3, gain = 0.56, fade = 0.2 },
	chomp = { file = F.crunch, pitch = 0.8, gain = 1.27, layers = { "chompSplat" } },
	chompSplat = { file = F.splat, pitch = 0.85, gain = 0.21 },
	dodge = { file = F.arrow, from = 0.1, to = 0.5, gain = 0.44 },
	spat = { file = F.splat, gain = 0.46 },
	splash = { file = F.splash, from = 0.45, to = 1.3, gain = 1.12, fade = 0.2 },
	-- rides (3D loops; pitch and volume follow speed)
	duckSqueak = { file = F.duck, from = 0.08, to = 0.66, gain = 0.82 },
	dolphinCall = { file = F.dolphin, from = 0.43, to = 2.58, gain = 0.31 },
	rideSplash = { file = F.swim, loop = { 2.782, 8.443 }, gain = 0.72 },
	rideKick = { file = F.swim, loop = { 1.426, 4.198 }, pitch = 1.12, gain = 0.72 },
	rideDuck = { file = F.paddle, loop = { 40.008, 43.98 }, gain = 0.73, every = { "duckSqueak", 5, 10, 0.3 } },
	rideSurf = { file = F.flow, loop = { 9.95, 14.215 }, eq = { -6, 0, 2 }, gain = 0.36 },
	rideBubbles = { file = F.deep, loop = { 0, 1.12 }, gain = 0.33 },
	rideMotor = { file = F.boat, loop = { 2.015, 4.801 }, pitch = 0.82, gain = 0.48 },
	rideJetSki = { file = F.jetski, loop = { 7.476, 9.306 }, gain = 0.74 },
	rideBoat = { file = F.boat, loop = { 5.548, 8.76 }, gain = 0.42 },
	rideDolphin = { file = F.swim, loop = { 2.782, 8.443 }, pitch = 1.05, gain = 0.72, every = { "dolphinCall", 4, 8, 0.45 } },
	rideRocket = { file = F.rocket, gain = 2.9 }, -- already a seamless loop
	-- ambience
	ambWaves = { file = F.waves, gain = 0.67 }, -- open-sea bed (a seamless loop)
	ambShore = { file = F.waves, loop = { 25.95, 36.203 }, pitch = 1.08, eq = { -8, 0, 2 }, gain = 0.79 }, -- small waves on the sand
	ambGulls = { file = F.gulls, loop = { 0.036, 29.93 }, gain = 25 }, -- a very quiet recording
	ambTank = { file = F.deep, loop = { 0, 2.4 }, pitch = 0.7, eq = { 0, 0, -8 }, gain = 0.26 }, -- a bloop every few seconds
} :: { [string]: SoundSlot }

-- which loop each ride plays, and its base pitch
Config.RideSound = {
	Noodle = { "rideSplash", 1.0 }, Tube = { "rideSplash", 0.95 }, Donut = { "rideSplash", 0.9 },
	Duck = { "rideDuck", 1.0 }, GoldDuck = { "rideDuck", 1.08 },
	Boogie = { "rideKick", 1.0 },
	Surf = { "rideSurf", 1.0 }, SharkBoard = { "rideSurf", 0.92 },
	Bathtub = { "rideBubbles", 1.0 },
	Banana = { "rideMotor", 1.0 },
	JetSki = { "rideJetSki", 1.0 }, RainbowSki = { "rideJetSki", 1.12 },
	Speedboat = { "rideBoat", 1.0 },
	Dolphin = { "rideDolphin", 1.0 },
	Rocket = { "rideRocket", 1.0 },
} :: { [string]: { any } }

return Config
