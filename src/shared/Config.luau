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
	world: number?, -- which world (set below)
	aggro: number?, -- shark aggression (1 = normal): >1 circles less, lunges from further
	zStart: number,
	zEnd: number,
	index: number,
}

local OCEAN_ZONES = {
	{ id = "Lagoon", name = "Lagoon", gate = 0, length = 260, depth = 7, shark = "Baby", sharkLength = 8,
		sharkSpeed = 44, value = 1, islandEvery = 70, islandRadius = 11,
		water = Color3.fromRGB(40, 222, 226), clarity = 0.92, floor = Enum.Material.Sand,
		floorColor = Color3.fromRGB(255, 240, 196), tint = Color3.fromRGB(255, 255, 255), aggro = 0.85 },
	{ id = "Reef", name = "Coral Reef", gate = 100, length = 400, depth = 12, shark = "Hammerhead", sharkLength = 12,
		sharkSpeed = 80, value = 5, islandEvery = 95, islandRadius = 10,
		water = Color3.fromRGB(26, 196, 222), clarity = 0.85, floor = Enum.Material.Sandstone,
		floorColor = Color3.fromRGB(246, 214, 170), tint = Color3.fromRGB(255, 250, 252), aggro = 1.3 },
	{ id = "Kelp", name = "Kelp Forest", gate = 350, length = 560, depth = 18, shark = "Tiger", sharkLength = 14,
		sharkSpeed = 102, value = 25, islandEvery = 120, islandRadius = 9,
		water = Color3.fromRGB(24, 170, 170), clarity = 0.72, floor = Enum.Material.Mud,
		floorColor = Color3.fromRGB(92, 128, 80), tint = Color3.fromRGB(244, 255, 246), aggro = 1.25 },
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
	-- past the Abyss: each rebirth's goal is one zone further (Config.rebirthSpeed)
	{ id = "Frozen", name = "Frozen Sea", gate = 60000, length = 1500, depth = 40, shark = "Frost", sharkLength = 28,
		sharkSpeed = 320, value = 15000, islandEvery = 260, islandRadius = 9, aggro = 1.1,
		water = Color3.fromRGB(150, 215, 245), clarity = 0.55, floor = Enum.Material.Glacier,
		floorColor = Color3.fromRGB(205, 235, 250), tint = Color3.fromRGB(235, 248, 255) },
	{ id = "Volcano", name = "Volcano Vents", gate = 150000, length = 1600, depth = 50, shark = "Magma", sharkLength = 30,
		sharkSpeed = 340, value = 75000, islandEvery = 280, islandRadius = 8, aggro = 1.15,
		water = Color3.fromRGB(150, 60, 50), clarity = 0.35, floor = Enum.Material.CrackedLava,
		floorColor = Color3.fromRGB(45, 30, 30), tint = Color3.fromRGB(255, 232, 220) },
	{ id = "Atlantis", name = "Lost City", gate = 350000, length = 1800, depth = 60, shark = "King", sharkLength = 34,
		sharkSpeed = 360, value = 375000, islandEvery = 300, islandRadius = 8, aggro = 1.2,
		water = Color3.fromRGB(40, 190, 170), clarity = 0.5, floor = Enum.Material.Limestone,
		floorColor = Color3.fromRGB(235, 225, 200), tint = Color3.fromRGB(240, 255, 250) },
} :: { Zone }

-- World 2: Candy Bay. Same game, sweeter sea: every zone pays 4x its
-- Shark Beach twin, speed gain is x2.5 (on top of your rebirths), and gates
-- / rebirth goals are x4.
local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end
local CANDY_ZONES = {
	{ id = "Soda", name = "Soda Shallows", gate = 0, length = 260, depth = 7, shark = "Gummy", sharkLength = 8,
		sharkSpeed = 60, value = 4, islandEvery = 70, islandRadius = 11, aggro = 0.9,
		water = rgb(120, 230, 255), clarity = 0.9, floor = Enum.Material.Sand,
		floorColor = rgb(255, 214, 236), tint = rgb(255, 250, 255) },
	{ id = "Gumdrop", name = "Gumdrop Reef", gate = 400, length = 400, depth = 12, shark = "Jelly", sharkLength = 12,
		sharkSpeed = 95, value = 20, islandEvery = 95, islandRadius = 10, aggro = 1.3,
		water = rgb(255, 140, 210), clarity = 0.8, floor = Enum.Material.Snow,
		floorColor = rgb(255, 190, 230), tint = rgb(255, 245, 252) },
	{ id = "Lolly", name = "Lollipop Lagoon", gate = 2000, length = 560, depth = 18, shark = "Licorice", sharkLength = 14,
		sharkSpeed = 120, value = 100, islandEvery = 120, islandRadius = 9, aggro = 1.25,
		water = rgb(190, 130, 255), clarity = 0.7, floor = Enum.Material.Pavement,
		floorColor = rgb(225, 200, 255), tint = rgb(250, 245, 255) },
	{ id = "Cane", name = "Candy Cane Cove", gate = 4000, length = 720, depth = 26, shark = "Peppermint", sharkLength = 18,
		sharkSpeed = 160, value = 480, islandEvery = 150, islandRadius = 9,
		water = rgb(255, 110, 130), clarity = 0.6, floor = Enum.Material.Salt,
		floorColor = rgb(255, 235, 235), tint = rgb(255, 245, 245) },
	{ id = "Choco", name = "Chocolate Deep", gate = 20000, length = 1000, depth = 48, shark = "Fudge", sharkLength = 22,
		sharkSpeed = 230, value = 2400, islandEvery = 210, islandRadius = 8,
		water = rgb(120, 70, 40), clarity = 0.4, floor = Enum.Material.Asphalt,
		floorColor = rgb(90, 55, 35), tint = rgb(255, 240, 228) },
	{ id = "Sugar", name = "Sugar Abyss", gate = 100000, length = 1400, depth = 80, shark = "SugarKing", sharkLength = 40,
		sharkSpeed = 320, value = 12000, islandEvery = 300, islandRadius = 8, aggro = 1.1,
		water = rgb(70, 30, 100), clarity = 0.3, floor = Enum.Material.Rock,
		floorColor = rgb(60, 30, 80), tint = rgb(250, 235, 255) },
} :: { Zone }

----------------------------------------------------------------- worlds
-- Both worlds live in this one place: World 2 is a full copy of the beach +
-- ocean, WORLD_GAP studs off to the side (+X), far enough that neither can
-- see the other. Everything along the lane (zones, the shore ramp) works in
-- Z as before; X picks the world. The plaza portal swaps you between them.
export type World = {
	id: number, name: string, zones: { Zone }, gainMult: number, rebirthSteps: { number },
	unlockRebirths: number, color: Color3, ox: number, oceanEnd: number,
}
Config.WORLD_GAP = 12000
Config.Worlds = {
	{ id = 1, name = "Shark Beach", zones = OCEAN_ZONES, gainMult = 1,
		rebirthSteps = { 5000, 25000, 60000, 150000, 350000 }, unlockRebirths = 0, color = rgb(40, 170, 255) },
	{ id = 2, name = "Candy Bay", zones = CANDY_ZONES, gainMult = 2.5,
		rebirthSteps = { 20000, 100000, 240000, 600000, 1400000 }, unlockRebirths = 3, color = rgb(255, 110, 200) },
} :: { World }

-- every zone of every world (ids are unique across worlds)
Config.Zones = {} :: { Zone }
for w, world in Config.Worlds do
	world.ox = (w - 1) * Config.WORLD_GAP
	local z = Config.SHORE_Z
	for i, zone in world.zones do
		zone.world = w
		zone.index = i
		zone.zStart = z
		zone.zEnd = z + zone.length
		z = zone.zEnd
		table.insert(Config.Zones, zone)
	end
	world.oceanEnd = z
end
Config.OCEAN_END = Config.Worlds[1].oceanEnd

-- which world a position is in (by X)
function Config.worldAt(pos: Vector3): number
	return math.clamp(math.floor((pos.X + Config.WORLD_GAP / 2) / Config.WORLD_GAP) + 1, 1, #Config.Worlds)
end

function Config.originX(w: number?): number
	return (Config.Worlds[w or 1] or Config.Worlds[1]).ox
end

function Config.worldZones(w: number?): { Zone }
	return (Config.Worlds[w or 1] or Config.Worlds[1]).zones
end

function Config.oceanEnd(w: number?): number
	return (Config.Worlds[w or 1] or Config.Worlds[1]).oceanEnd
end

function Config.zoneAt(z: number, w: number?): Zone?
	if z < Config.SHORE_Z then
		return nil
	end
	local zones = Config.worldZones(w)
	for _, zone in zones do
		if z < zone.zEnd then
			return zone
		end
	end
	return zones[#zones]
end

function Config.zoneAtPos(pos: Vector3): Zone?
	return Config.zoneAt(pos.Z, Config.worldAt(pos))
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
function Config.zoneForSpeed(speed: number, w: number?): Zone
	local zones = Config.worldZones(w)
	local best = zones[1]
	for _, zone in zones do
		if speed >= zone.gate then
			best = zone
		end
	end
	return best
end

function Config.nextGate(speed: number, w: number?): Zone?
	for _, zone in Config.worldZones(w) do
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
	{ id = "Tube", name = "Inner Tube", icon = "", price = 300, gain = 3 },
	{ id = "Boogie", name = "Boogie Board", icon = "", price = 2500, gain = 4 },
	{ id = "Surf", name = "Surfboard", icon = "", price = 10000, gain = 5 },
	{ id = "Bathtub", name = "Bathtub", icon = "", price = 40000, gain = 7 },
	{ id = "Banana", name = "Banana Boat", icon = "", price = 160000, gain = 9 },
	{ id = "JetSki", name = "Jet Ski", icon = "", price = 600000, gain = 12 },
	{ id = "Speedboat", name = "Speedboat", icon = "", price = 2400000, gain = 16 },
	{ id = "Dolphin", name = "Dolphin", icon = "", price = 9000000, gain = 22 },
	{ id = "Donut", name = "Giant Donut", icon = "", price = 70000000, gain = 30 },
	{ id = "Rocket", name = "Rocket Surfboard", icon = "", price = 200000000, gain = 40 },
	-- past the Abyss
	{ id = "Hover", name = "Hover Board", icon = "", price = 900000000, gain = 55 },
	{ id = "LavaSki", name = "Lava Jet", icon = "", price = 4000000000, gain = 75 },
	{ id = "Comet", name = "Golden Comet", icon = "", price = 18000000000, gain = 100 },
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
Config.RideFeel.Hover = { stance = "stand", accel = 0.25, coast = 1.1, turn = 3.6, grip = 5.5, lean = 0.5, bob = 0.3, bobSpeed = 1.6, plane = 0.12 }
Config.RideFeel.LavaSki = { stance = "straddle", accel = 0.3, coast = 1.0, turn = 4.4, grip = 3, lean = 0.6, bob = 0.16, bobSpeed = 4, plane = 0.14 }
Config.RideFeel.Comet = { stance = "stand", accel = 0.2, coast = 0.9, turn = 3.4, grip = 5.5, lean = 0.5, bob = 0.12, bobSpeed = 6, plane = 0.12 }

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
	Frozen = {
		Common = { name = "Ice Cod", kind = "fish", icon = "", c1 = RGB(170, 210, 240), c2 = RGB(245, 250, 255), c3 = RGB(60, 90, 130) },
		Uncommon = { name = "Snow Crab", kind = "crab", icon = "", c1 = RGB(240, 140, 120), c2 = RGB(255, 245, 240), long = true },
		Rare = { name = "Frost Jelly", kind = "jelly", icon = "", c1 = RGB(150, 230, 255), c2 = RGB(235, 250, 255), glow = true },
		Epic = { name = "Walrus Ray", kind = "ray", icon = "", c1 = RGB(110, 150, 190), c2 = RGB(240, 248, 255) },
		Legendary = { name = "Ice Narwhal", kind = "whale", icon = "", c1 = RGB(200, 235, 255), c2 = RGB(255, 255, 255), horn = true, glow = true, size = 1.1 },
	},
	Volcano = {
		Common = { name = "Ember Fish", kind = "fish", icon = "", c1 = RGB(255, 90, 30), c2 = RGB(255, 210, 60), c3 = RGB(40, 20, 20) },
		Uncommon = { name = "Lava Crab", kind = "crab", icon = "", c1 = RGB(60, 40, 40), c2 = RGB(255, 120, 30), shell = true },
		Rare = { name = "Magma Puffer", kind = "puffer", icon = "", c1 = RGB(255, 110, 40), c2 = RGB(255, 220, 120), glow = true },
		Epic = { name = "Cinder Squid", kind = "ceph", icon = "", c1 = RGB(50, 30, 35), c2 = RGB(255, 100, 40), glow = true, long = true },
		Legendary = { name = "Fire Serpent", kind = "serpent", icon = "", c1 = RGB(255, 70, 20), c2 = RGB(255, 210, 60), horns = true, glow = true, size = 1.2 },
	},
	Atlantis = {
		Common = { name = "Gold Tetra", kind = "fish", icon = "", c1 = RGB(255, 205, 60), c2 = RGB(255, 245, 200), c3 = RGB(40, 120, 120) },
		Uncommon = { name = "Royal Seahorse", kind = "seahorse", icon = "", c1 = RGB(120, 220, 210), c2 = RGB(255, 215, 90) },
		Rare = { name = "Pearl Turtle", kind = "turtle", icon = "", c1 = RGB(235, 240, 245), c2 = RGB(200, 170, 220) },
		Epic = { name = "Temple Ray", kind = "ray", icon = "", c1 = RGB(30, 140, 130), c2 = RGB(255, 215, 90), glow = true },
		Legendary = { name = "Poseidon Whale", kind = "whale", icon = "", c1 = RGB(40, 170, 160), c2 = RGB(255, 225, 120), horn = true, glow = true, size = 1.25 },
	},
	-- Candy Bay (World 2)
	Soda = {
		Common = { name = "Fizz Fish", kind = "fish", icon = "", c1 = RGB(120, 220, 255), c2 = RGB(255, 255, 255), c3 = RGB(255, 90, 160) },
		Uncommon = { name = "Taffy Crab", kind = "crab", icon = "", c1 = RGB(255, 150, 200), c2 = RGB(255, 235, 245), shell = true },
		Rare = { name = "Bubblegum Puffer", kind = "puffer", icon = "", c1 = RGB(255, 130, 200), c2 = RGB(255, 225, 240) },
		Epic = { name = "Mint Turtle", kind = "turtle", icon = "", c1 = RGB(120, 230, 180), c2 = RGB(255, 255, 255) },
		Legendary = { name = "Cotton Candy Whale", kind = "whale", icon = "", c1 = RGB(255, 170, 225), c2 = RGB(170, 220, 255), horn = true },
	},
	Gumdrop = {
		Common = { name = "Gummy Fish", kind = "fish", icon = "", c1 = RGB(255, 80, 80), c2 = RGB(255, 200, 60), c3 = RGB(80, 200, 90) },
		Uncommon = { name = "Jelly Bean Horse", kind = "seahorse", icon = "", c1 = RGB(170, 90, 255), c2 = RGB(255, 210, 120) },
		Rare = { name = "Gumdrop Octopus", kind = "ceph", icon = "", c1 = RGB(80, 220, 120), c2 = RGB(200, 255, 200) },
		Epic = { name = "Sour Ray", kind = "ray", icon = "", c1 = RGB(255, 230, 60), c2 = RGB(120, 255, 120), glow = true },
		Legendary = { name = "Gummy Dragon", kind = "serpent", icon = "", c1 = RGB(255, 80, 120), c2 = RGB(255, 220, 90), horns = true },
	},
	Lolly = {
		Common = { name = "Swirl Fish", kind = "fish", icon = "", c1 = RGB(255, 120, 220), c2 = RGB(255, 255, 255), c3 = RGB(120, 90, 255) },
		Uncommon = { name = "Rock Candy Crab", kind = "crab", icon = "", c1 = RGB(150, 210, 255), c2 = RGB(240, 250, 255), long = true },
		Rare = { name = "Jelly Jelly", kind = "jelly", icon = "", c1 = RGB(255, 160, 80), c2 = RGB(255, 230, 190), glow = true },
		Epic = { name = "Lollipop Squid", kind = "ceph", icon = "", c1 = RGB(255, 80, 160), c2 = RGB(255, 210, 240), long = true },
		Legendary = { name = "Rainbow Serpent", kind = "serpent", icon = "", c1 = RGB(120, 120, 255), c2 = RGB(255, 140, 220), glow = true },
	},
	Cane = {
		Common = { name = "Peppermint Eel", kind = "serpent", icon = "", c1 = RGB(240, 40, 60), c2 = RGB(255, 255, 255), size = 0.8 },
		Uncommon = { name = "Licorice Lobster", kind = "crab", icon = "", c1 = RGB(30, 25, 30), c2 = RGB(220, 40, 60), long = true, shell = false },
		Rare = { name = "Cane Swordfish", kind = "fish", icon = "", c1 = RGB(255, 255, 255), c2 = RGB(240, 40, 60), c3 = RGB(60, 160, 80), bill = true },
		Epic = { name = "Frosting Octopus", kind = "ceph", icon = "", c1 = RGB(255, 245, 250), c2 = RGB(255, 170, 200), ghost = true },
		Legendary = { name = "Candy Orca", kind = "whale", icon = "", c1 = RGB(220, 30, 60), c2 = RGB(255, 255, 255), size = 1.05 },
	},
	Choco = {
		Common = { name = "Cocoa Fish", kind = "fish", icon = "", c1 = RGB(110, 65, 40), c2 = RGB(255, 225, 180), c3 = RGB(60, 35, 20) },
		Uncommon = { name = "Truffle Angler", kind = "fish", icon = "", c1 = RGB(80, 45, 30), c2 = RGB(255, 210, 80), c3 = RGB(40, 25, 15), lure = true },
		Rare = { name = "Fudge Squid", kind = "ceph", icon = "", c1 = RGB(130, 75, 45), c2 = RGB(230, 170, 120), long = true },
		Epic = { name = "Caramel Ray", kind = "ray", icon = "", c1 = RGB(200, 120, 50), c2 = RGB(255, 220, 150), glow = true },
		Legendary = { name = "Chocolate Leviathan", kind = "serpent", icon = "", c1 = RGB(90, 50, 30), c2 = RGB(255, 200, 120), horns = true, size = 1.2 },
	},
	Sugar = {
		Common = { name = "Sprinkle Fish", kind = "fish", icon = "", c1 = RGB(255, 120, 230), c2 = RGB(60, 30, 90), c3 = RGB(120, 255, 230), glow = true },
		Uncommon = { name = "Sugar Jelly", kind = "jelly", icon = "", c1 = RGB(200, 140, 255), c2 = RGB(255, 230, 255), glow = true },
		Rare = { name = "Candy Vampire Squid", kind = "ceph", icon = "", c1 = RGB(120, 20, 80), c2 = RGB(255, 90, 200), glow = true },
		Epic = { name = "Gummy Megalodon", kind = "whale", icon = "", c1 = RGB(255, 100, 180), c2 = RGB(255, 230, 245), fin = true },
		Legendary = { name = "Sugar Kraken", kind = "ceph", icon = "", c1 = RGB(255, 60, 200), c2 = RGB(120, 255, 240), glow = true, size = 1.15 },
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

-- Limited catches: one limited mutation a week (Monday 00:00 UTC to the
-- next), taking turns in this order. It can only be caught during its week;
-- the ones you caught keep it forever. `material` is its look.
export type Limited = Mutation & { material: Enum.Material }
Config.Limited = {
	{ id = "Spooky", chance = 0.02, mult = 4, color = Color3.fromRGB(170, 110, 255), material = Enum.Material.ForceField },
	{ id = "Toxic", chance = 0.02, mult = 4, color = Color3.fromRGB(120, 255, 90), material = Enum.Material.Neon },
	{ id = "Molten", chance = 0.02, mult = 4, color = Color3.fromRGB(255, 110, 40), material = Enum.Material.CrackedLava },
	{ id = "Frozen", chance = 0.02, mult = 4, color = Color3.fromRGB(200, 240, 255), material = Enum.Material.Ice },
	{ id = "Galaxy", chance = 0.02, mult = 4, color = Color3.fromRGB(90, 70, 200), material = Enum.Material.Glass },
} :: { Limited }

local WEEK = 7 * 86400
local MONDAY = 4 * 86400 -- (1 Jan 1970 was a Thursday)

-- this week's limited mutation and when it ends (unix UTC)
function Config.limitedNow(now: number?): (Limited, number)
	local t = (now or os.time()) - MONDAY
	local week = t // WEEK
	return Config.Limited[week % #Config.Limited + 1], MONDAY + (week + 1) * WEEK
end

function Config.mutation(id: string?): Mutation?
	for _, m in Config.Mutations do
		if m.id == id then
			return m
		end
	end
	for _, m in Config.Limited do
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

-- $/s and other small rates: whole numbers from 10 up (K/M/B...), one
-- decimal under 10 ("2.5"), two under 1 ("0.25") so a slow fish never says 0
function Config.formatRate(n: number): string
	if n >= 10 or n <= 0 then
		local units = { "", "K", "M", "B", "T", "Qa", "Qi" }
		local i = 1
		while n >= 1000 and i < #units do
			n /= 1000
			i += 1
		end
		if i == 1 then
			return tostring(math.max(math.floor(n), 0))
		end
		local s = string.format(n >= 100 and "%.0f" or "%.1f", n):gsub("%.0$", "")
		return s .. units[i]
	end
	local s = string.format(n < 1 and "%.2f" or "%.1f", n)
	s = s:gsub("0+$", ""):gsub("%.$", "")
	return s
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

-- Megalodon Hour: a weekly event at a fixed time (UTC) so players know when
-- to show up. x3 luck, two sharks every night, double coins, the boss. The
-- plaza board counts down to it. Admins can start one now with /event.
Config.Event = {
	name = "Megalodon Hour",
	weekday = 7, -- os.date wday: 1 Sunday .. 7 Saturday
	hour = 19, -- UTC (3 pm US Eastern, noon Pacific)
	minutes = 60,
	luckMult = 3, -- x3 luck
	coins = 2,
}

-- The boss Megalodon (Megalodon Hour): it surfaces mid-sea in each world
-- with players and the whole server fights it with harpoons (the HARPOON
-- button shows up in range). It circles and charges riders; everyone who
-- landed `minHits` gets a Legendary when it goes down.
Config.Boss = {
	length = 80,
	hpBase = 40,
	hpPerPlayer = 90, -- per player in that world
	range = 95, -- harpoon reach
	cooldown = 0.8, -- between throws
	minHits = 3,
	lifetime = 300, -- seconds before it gives up and dives
	every = 1200, -- one more surfaces this long after the last one (during the event)
	zone = 2, -- it lives over this zone (reachable for everyone)
	circle = 55, -- the radius it patrols around its spot
	speed = 30,
	sight = 160, -- it charges riders this close
	chargeEvery = 6,
	chargeTime = 2.4,
	chargeMult = 1.05, -- vs the target's top speed: turn hard to dodge it
	turn = 1.6, -- radians / second while charging
	biteRadius = 12,
	reward = "Legendary",
}
-- the next update's release (unix time, UTC). 0 hides the board line
Config.NextUpdate = 0
-- the next like goal: the plaza board and the codes card say "a new code
-- at 1K likes". When it's reached, add the code to Config.Codes and raise
-- this. 0 hides it.
Config.LikeGoal = 1000

-- Chum: throw a bucket at a nearby rider and their zone's shark comes for
-- them (by day; at night the sharks are out anyway)
Config.Chum = { range = 90, cooldown = 45, grudge = 18, minPlaytime = 300 }

-- Raids: hold the RAID prompt at another player's tank while they're out at
-- sea; after `time` seconds you take one of their creatures (never their
-- best). They're alerted at once and stop it by getting back to their dock.
Config.Raid = {
	time = 35, -- long: the owner has time to rush home from deep water
	defendRadius = 28, -- the owner this close to their own tank stops it
	stayRadius = 16, -- the raider has to stay this close to the tank
	victimCooldown = 240, -- a raided player is safe from raids this long
	raiderCooldown = 60, -- after a raid (won or lost)
	minPlaytime = 600, -- both players need 10 min played (no new players)
}

-- Nets: how many creatures you can carry home in one trip (bought with
-- coins in the Tank window; kept through rebirths and across worlds). A
-- shark bite loses the whole haul, so a big net is a big risk too.
Config.Nets = {
	{ name = "Bare Hands", cap = 2, price = 0 },
	{ name = "Small Net", cap = 3, price = 300 }, -- (an early goal at ~3 min that feeds the haul)
	{ name = "Big Net", cap = 5, price = 8000 },
	{ name = "Trawl Net", cap = 8, price = 2500000 },
	{ name = "Mega Net", cap = 12, price = 150000000 },
}
function Config.netCap(tier: number?): number
	local n = Config.Nets[math.clamp(tier or 1, 1, #Config.Nets)]
	return n.cap
end

-- Server events (server Events.luau, client Countdown.luau): every `every`
-- seconds one of these runs for `length` seconds, taking turns. The HUD
-- counts down to the next one. (Not during Megalodon Hour.)
Config.MiniEvents = {
	first = 360, -- the first one this long after the server starts
	every = 900,
	length = 120,
	goldChance = 0.35, -- Golden Tide: chance any bubble is Gold
	rain = 14, -- Bubble Rain: extra bubbles per world
	list = {
		{ id = "golden", name = "Golden Tide", desc = "Any bubble can be Gold!", color = Color3.fromRGB(255, 200, 40) },
		{ id = "frenzy", name = "Feeding Frenzy", desc = "Hauls pay x2. Sharks get hungry fast!", color = Color3.fromRGB(255, 80, 90) },
		{ id = "rain", name = "Bubble Rain", desc = "Bubbles near the shore!", color = Color3.fromRGB(110, 210, 255) },
	},
}

-- what players call each shark ("Baby" alone reads oddly on the HUD)
local SHARK_NAMES = {
	Baby = "Baby Shark", Hammerhead = "Hammerhead", Tiger = "Tiger Shark", GreatWhite = "Great White",
	Mecha = "Mecha Shark", Megalodon = "Megalodon", Frost = "Frost Shark", Magma = "Magma Shark", King = "King Shark",
	Gummy = "Gummy Shark", Jelly = "Jelly Shark", Licorice = "Licorice Shark", Peppermint = "Peppermint Shark",
	Fudge = "Fudge Shark", SugarKing = "Sugar King",
}
function Config.sharkName(variant: string?): string
	return SHARK_NAMES[variant or ""] or "Shark"
end

-- Noodle Bonk (server Bonk.luau, client Bonk.luau): one button, two uses.
-- Bonk a rider and the last creature they carry pops out as a bubble anyone
-- can grab. Bonk a shark that's coming for you and it's dazed for a moment.
-- Only at sea. Players in the guide or in their first `protect` seconds can't
-- bonk riders or be bonked (sharks, yes). After a bonk you're safe for
-- `immune` seconds. A Shark Shield blocks one bonk.
Config.Bonk = {
	sharkCooldown = 8, -- between shark bonks
	daze = 1.6, -- seconds a bonked shark is dazed
	immune = 4,
	protect = 600, -- playtime (s) before riders can bonk / be bonked
	knock = 70, -- how hard you get knocked (studs/s)
}
-- the noodle you swing: better ones reach further and swing sooner (coins,
-- in the Ride Shop window; the Golden Noodle is a game pass)
Config.Noodles = {
	{ name = "Foam Noodle", reach = 11, cooldown = 2.6, price = 0, color = Color3.fromRGB(255, 120, 200) },
	{ name = "Super Noodle", reach = 13, cooldown = 2.2, price = 5000, color = Color3.fromRGB(80, 200, 255) },
	{ name = "Mega Noodle", reach = 15, cooldown = 1.8, price = 250000, color = Color3.fromRGB(150, 90, 255) },
	{ name = "Golden Noodle", reach = 16, cooldown = 1.8, price = 0, pass = "GoldenNoodle", color = Color3.fromRGB(255, 200, 40) },
}

-- THE HOOK: carry more, earn more, but the shark wants you more.
-- Haul: what you bring home in one trip pays cash at the dock right away
-- (`seconds` of its $/s), x1.25 for every creature after the first, up
-- to x3. The tank still earns from them after that.
Config.Haul = { seconds = 20, step = 0.25, max = 3 }
-- bitten: your haul spills into the water as bubbles anyone can grab for
-- this long (seconds)
Config.SPILL_TIME = 40
function Config.haulMult(n: number): number
	return math.min(1 + Config.Haul.step * math.max(0, n - 1), Config.Haul.max)
end

-- Shark hunger: every zone has a bar everyone in it can see. Each grab
-- fills it (rarer = more, night = double); when it's full the shark goes
-- for whoever in that zone is carrying the most. It calms down slowly.
Config.Hunger = {
	fill = { Common = 14, Uncommon = 20, Rare = 30, Epic = 45, Legendary = 70 },
	night = 2,
	decay = 1.2, -- per second
	after = 15, -- where the bar drops to once the shark has gone for someone
	grudge = 22, -- seconds that shark hunts its pick
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
-- Day and night: by day the sea is calm, but grabbing a creature can draw
-- its zone's shark onto you (a grudge, below). At dusk (warning) everyone
-- in open water gets hunted until dawn; night catches are luckier (frenzy).
-- Dawn sends every shark home: a clean slate.
Config.Shark = {
	cycle = 130, -- average day (HUD fallback; real days are random)
	firstAttack = 150, -- the first night falls this long after the server starts
	warning = 6, -- dusk: time to get to sand
	hunt = 50, -- average night (HUD fallback)
	calmMin = 110, calmMax = 150, -- day length
	huntMin = 40, huntMax = 58, -- night length
	-- grudges: by day, a grab draws the zone's shark with this chance (x the
	-- zone's aggro, + per extra creature in your net); it hunts you this long
	grudge = 22,
	-- close call: a lunge that lands this close without biting pays you
	closeCall = 4,
	closeCallSeconds = 8, -- seconds of your speed gain
	closeCallCooldown = 15,
	escapeRadius = 40, -- reach the sand with your shark this close: you made it
	escapeMinSea = 8, -- ...after at least this long out at sea
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
	-- the first zones (Shark Beach) are kinder: the charge only matches you
	-- (Lagoon) or just beats you (Coral Reef), so riding straight home works
	easyCharge = { 1.0, 1.08 }, -- x your top speed, by zone index
	easyMin = 24, -- (never slower than this)
	chargeRadius = 26, -- turning circle while charging (studs): same feel at any speed
	chargeGiveUp = 4,
	lungeRange = 22, -- commits to the leap this close (studs)...
	lungeRangeMax = 32, -- ...a bit further when you're fast
	lungeMinCharge = 0.5, -- seconds of charging ("IT'S CHARGING!") before it can leap
	lungeLead = 1.0, -- aims at your velocity x flight time x this
	lungeHop = 3, -- this high above the water at landing = you hopped over it
	lungeGap = 1.4, -- two sharks on you: the second waits this long after a landing
	maxHunters = 24,
	newPlayerGrace = 300, -- seconds a player still in the first-session guide can't be hunted
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
-- Each rebirth asks for more speed (Config.Worlds rebirthSteps): in Shark
-- Beach the first at Deep Blue (~15-18 min, to teach the loop early), then
-- The Abyss, Frozen Sea, Volcano Vents, Lost City, then x2 each.
Config.Rebirth = { speed = 25000, mult = 1.5 }
function Config.rebirthSpeed(rebirths: number?, w: number?): number
	local n = (rebirths or 0) + 1
	local steps = (Config.Worlds[w or 1] or Config.Worlds[1]).rebirthSteps
	if n <= #steps then
		return steps[n]
	end
	return steps[#steps] * 2 ^ (n - #steps)
end

-- your wake color shows how many times you've rebirthed (VIP: gold)
Config.WakeTiers = {
	{ at = 1, color = Color3.fromRGB(90, 230, 255), name = "Cyan" },
	{ at = 2, color = Color3.fromRGB(110, 255, 120), name = "Green" },
	{ at = 3, color = Color3.fromRGB(190, 110, 255), name = "Purple" },
	{ at = 5, color = Color3.fromRGB(255, 90, 160), name = "Pink" },
	{ at = 8, color = Color3.fromRGB(255, 70, 60), name = "Red" },
}
Config.VIP_WAKE = Color3.fromRGB(255, 205, 50)
function Config.wakeColor(rebirths: number, vip: boolean?): Color3?
	if vip then
		return Config.VIP_WAKE
	end
	local c = nil
	for _, t in Config.WakeTiers do
		if rebirths >= t.at then
			c = t.color
		end
	end
	return c
end

----------------------------------------------------------------- monetization
-- Fill these in from Creator Dashboard after you create the passes/products.
-- An id of 0 hides the buy button instead of prompting a fake purchase.
Config.Passes = {
	TwoXSpeed = { iconName = "X2Speed", id = 2023244258, price = 399, name = "2x Speed", icon = "", desc = "Double speed gain forever" },
	TwoXCoins = { iconName = "X2Coins", id = 2022860257, price = 199, name = "2x Coins", icon = "", desc = "Double coins from your tank" },
	AutoCollect = { iconName = "Magnet", id = 2022200258, price = 99, name = "Auto Collect", icon = "", desc = "Coins go straight to you" },
	LuckyNet = { iconName = "Clover", id = 2022830256, price = 199, name = "Lucky Net", icon = "", desc = "+15% chance to upgrade rarity" },
	BigTank = { iconName = "TankPlus", id = 2023304253, price = 99, name = "+4 Tank Slots", icon = "", desc = "Room for 4 more creatures" },
	VIP = { iconName = "Crown", id = 2022614262, price = 399, name = "VIP", icon = "", desc = "Gold wake, VIP tag, +10% coins" },
	GoldDuck = { iconName = "GoldDuck", id = 2022776256, price = 99, name = "Golden Duck", icon = "", desc = "Ride it - x1.25 speed gain" },
	SharkBoard = { iconName = "SharkBoard", id = 2023016262, price = 199, name = "Shark Board", icon = "", desc = "Ride it - x1.5 speed gain" },
	RainbowSki = { iconName = "RainbowSki", id = 2023094256, price = 399, name = "Rainbow Jet Ski", icon = "", desc = "Ride it - x2 speed gain" },
	-- (needs its game pass id: create it on the Creator Dashboard)
	GoldenNoodle = { iconName = "Crown", id = 0, price = 149, name = "Golden Noodle", icon = "", desc = "A shiny bonk noodle: the longest reach" },
}

Config.Products = {
	-- tiny-price items: turn non-payers into payers (the first purchase is the hard one)
	SpeedDeal = { iconName = "X2Speed", id = 3717313757, price = 3, name = "x2 Speed Deal", icon = "", desc = "2x Speed for 30 minutes. One time only!" },
	Rescue = { iconName = "Shield", id = 3717313850, price = 9, name = "Save Your Creature", icon = "", desc = "Get back the creature the shark just ate" },
	SpeedPack0 = { iconName = "SpeedPack0", id = 3717313910, price = 9, name = "Mini Speed Pack", icon = "", desc = "3 minutes of your speed gain" },
	MoneyPack0 = { iconName = "MoneyPack0", id = 3717314065, price = 9, name = "Mini Cash Pack", icon = "", desc = "3 minutes of your tank income" },
	Shield = { iconName = "Shield", id = 3717314118, price = 9, name = "Shark Shield", icon = "", desc = "Survive one bite (or one chum), keep your creature" },
	-- id 0 = shows SOON until you create the product and paste its id here
	TankLock = { iconName = "Lock", id = 0, price = 29, name = "Tank Lock", icon = "", desc = "No one can raid your tank for 30 minutes" },
	SpeedBoost = { iconName = "Boost", id = 3717315209, price = 49, name = "2x Speed (15 min)", icon = "", desc = "Double speed gain for 15 minutes" },
	LuckPotion = { iconName = "Potion", id = 3717315275, price = 49, name = "Luck Potion (10 min)", icon = "", desc = "+15% rarity upgrade chance" },
	GoldenBubble = { iconName = "GoldBubble", id = 3717315347, price = 99, name = "Golden Bubble", icon = "",
		desc = "Rare 70% · Epic 25% · Legendary 5%" },
	-- the starter ladder: each pack unlocks the next, bigger one (Config.StarterLadder)
	StarterPack = { iconName = "StarterPack", id = 3717314528, price = 49, name = "Starter Pack", icon = "",
		desc = "A Rare creature + 30 min 2x Speed + 3 Shields" },
	ProPack = { iconName = "ProPack", id = 3717314630, price = 149, name = "Pro Pack", icon = "",
		desc = "An Epic creature + 1 hour 2x Speed + 30 min Luck + 5 Shields" },
	MegaPack = { iconName = "MegaPack", id = 3717314693, price = 399, name = "Mega Pack", icon = "",
		desc = "A HUGE Legendary + 2 hours 2x Speed + 1 hour Luck + 10 Shields" },
	DoubleOffline = { iconName = "Clock", id = 3717315407, price = 25, name = "2x Offline Coins", icon = "", desc = "Double your welcome-back coins" },
	-- speed / cash packs: they scale with you (Config.packAmount), so they're always worth it
	SpeedPack1 = { iconName = "SpeedPack1", id = 3717314735, price = 49, name = "Small Speed Pack", icon = "", desc = "10 minutes of your speed gain" },
	SpeedPack2 = { iconName = "SpeedPack2", id = 3717314814, price = 149, name = "Speed Pack", icon = "", desc = "40 minutes of your speed gain" },
	SpeedPack3 = { iconName = "SpeedPack3", id = 3717314870, price = 399, name = "Big Speed Pack", icon = "", desc = "2 hours of your speed gain" },
	SpeedPack4 = { iconName = "SpeedPack4", id = 3717314918, price = 999, name = "Mega Speed Pack", icon = "", desc = "6 hours of your speed gain" },
	MoneyPack1 = { iconName = "MoneyPack1", id = 0, price = 49, name = "Small Cash Pack", icon = "", desc = "10 minutes of your tank income" },
	MoneyPack2 = { iconName = "MoneyPack2", id = 3717314992, price = 149, name = "Cash Pack", icon = "", desc = "40 minutes of your tank income" },
	MoneyPack3 = { iconName = "MoneyPack3", id = 3717315022, price = 399, name = "Big Cash Pack", icon = "", desc = "2 hours of your tank income" },
	MoneyPack4 = { iconName = "MoneyPack4", id = 3717315078, price = 999, name = "Mega Cash Pack", icon = "", desc = "6 hours of your tank income" },
}

-- What a speed / cash pack gives: your current speed gain per second (or tank
-- income per second) times `seconds`, never less than `min` (so a brand-new
-- player still gets a good jump). The store shows this live and the server
-- grants exactly this (Market.luau), both through Config.packAmount.
Config.Packs = {
	SpeedPack0 = { kind = "speed", seconds = 180, min = 300 },
	MoneyPack0 = { kind = "money", seconds = 180, min = 300 },
	SpeedPack1 = { kind = "speed", seconds = 600, min = 1000 },
	SpeedPack2 = { kind = "speed", seconds = 2400, min = 4000 },
	SpeedPack3 = { kind = "speed", seconds = 7200, min = 12000 },
	SpeedPack4 = { kind = "speed", seconds = 21600, min = 36000 },
	MoneyPack1 = { kind = "money", seconds = 600, min = 1000 },
	MoneyPack2 = { kind = "money", seconds = 2400, min = 5000 },
	MoneyPack3 = { kind = "money", seconds = 7200, min = 20000 },
	MoneyPack4 = { kind = "money", seconds = 21600, min = 75000 },
}

-- gain = speed gained per second, income = tank coins per second (as in the
-- player's state: Game.gain / Game.income)
function Config.packAmount(key: string, gain: number, income: number): number
	local pack = Config.Packs[key]
	if not pack then
		return 0
	end
	local rate = if pack.kind == "speed" then gain else income
	return math.floor(math.max(pack.min, (rate or 0) * pack.seconds))
end

-- one-time packs, offered in order: buy one and the next appears
Config.StarterLadder = { "StarterPack", "ProPack", "MegaPack" }

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
Config.Offline = { rate = 0.07, maxHours = 4, minSeconds = 120 }

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
-- The developer's UI kit (assets/ui_kit): 9-slice images for buttons, cards,
-- bars, toggles, badges and effects. w/h = the uploaded image size (used for
-- slicing). UI.luau falls back to its drawn look for anything without an id.
Config.Kit = {
	PanelMenu = { id = "rbxassetid://86407415608931", w = 512, h = 310 },
	PanelPopup = { id = "rbxassetid://124968295027814", w = 512, h = 117 },
	CardLocked = { id = "rbxassetid://138368726702771", w = 512, h = 498 },
	CardGrey = { id = "rbxassetid://99124840776319", w = 512, h = 495 },
	CardPurple = { id = "rbxassetid://138561045733258", w = 512, h = 486 },
	CardBlue = { id = "rbxassetid://130934708732331", w = 512, h = 503 },
	CardGold = { id = "rbxassetid://122479184125880", w = 512, h = 494 },
	CardGreen = { id = "rbxassetid://84536826013310", w = 512, h = 505 },
	CardSelected = { id = "rbxassetid://121902630364655", w = 512, h = 493 },
	CardEquipped = { id = "rbxassetid://94933674611199", w = 512, h = 477 },
	ToggleOff = { id = "rbxassetid://104354054328611", w = 512, h = 183 },
	ToggleOn = { id = "rbxassetid://124323752238473", w = 512, h = 194 },
	Close = { id = "rbxassetid://82082566287960", w = 512, h = 508 },
	Back = { id = "rbxassetid://113932505345415", w = 509, h = 512 },
	TabInactive = { id = "rbxassetid://131530321556916", w = 512, h = 98 },
	TabActive = { id = "rbxassetid://98676322107939", w = 512, h = 114 },
	EffectZoneBurst = { id = "rbxassetid://87420411417479", w = 512, h = 496 },
	EffectRewardRays = { id = "rbxassetid://131379887484641", w = 512, h = 478 },
	EffectBubbles = { id = "rbxassetid://90057041822173", w = 512, h = 302 },
	EffectSparkles = { id = "rbxassetid://102323567543084", w = 512, h = 413 },
	ButtonGrey = { id = "rbxassetid://105065289729825", w = 512, h = 112 },
	ButtonGreyPressed = { id = "rbxassetid://89345083222166", w = 512, h = 125 },
	ButtonRed = { id = "rbxassetid://137771606195636", w = 512, h = 120 },
	ButtonRedPressed = { id = "rbxassetid://138626143208303", w = 512, h = 125 },
	ButtonGold = { id = "rbxassetid://136922192565282", w = 512, h = 132 },
	ButtonGoldPressed = { id = "rbxassetid://123682030833023", w = 512, h = 137 },
	ButtonGreen = { id = "rbxassetid://130916740925094", w = 512, h = 122 },
	ButtonGreenPressed = { id = "rbxassetid://82578261474976", w = 512, h = 125 },
	ButtonBlue = { id = "rbxassetid://114186125759699", w = 512, h = 117 },
	ButtonBluePressed = { id = "rbxassetid://82380426359616", w = 512, h = 123 },
	BadgeNotification = { id = "rbxassetid://104923338230172", w = 510, h = 503 },
	BadgeCheck = { id = "rbxassetid://106980880592248", w = 507, h = 512 },
	BadgeNew = { id = "rbxassetid://111813341820235", w = 512, h = 180 },
	BarTrack = { id = "rbxassetid://72096804616395", w = 512, h = 76 },
	BarFillPurple = { id = "rbxassetid://116232031876966", w = 512, h = 75 },
	BarFillGreen = { id = "rbxassetid://122223832969955", w = 512, h = 73 },
	BarFillCyan = { id = "rbxassetid://128454183380371", w = 512, h = 64 },
	BarFillGold = { id = "rbxassetid://75446511564002", w = 512, h = 73 },
	Tooltip = { id = "rbxassetid://74111069902095", w = 512, h = 137 },
}

Config.Icons = {
	-- one uploaded image per icon (assets/icons/ui/<Name>.png): paste each id
	ids = {
		Arrow = "rbxassetid://120389045886461",
		BigTank = "rbxassetid://70515101896590",
		Boost = "rbxassetid://126747451394770",
		Cash = "rbxassetid://135314404622025",
		Chest = "rbxassetid://125652638824235",
		Clock = "rbxassetid://90068540904379",
		Clover = "rbxassetid://80704029971621",
		Coral = "rbxassetid://120134315569016",
		Crown = "rbxassetid://79408293523885",
		Fin = "rbxassetid://117904235635367",
		Fish = "rbxassetid://103949935402764",
		Friends = "rbxassetid://113135754984947",
		Gift = "rbxassetid://125898866230512",
		GoldBubble = "rbxassetid://102263305140243",
		GoldDuck = "rbxassetid://135406763809368",
		Index = "rbxassetid://74081454119630",
		Island = "rbxassetid://127695776632387",
		Lock = "rbxassetid://123647043975113",
		Magnet = "rbxassetid://91206212643847",
		MegaPack = "rbxassetid://121111499132247",
		MoneyBag = "rbxassetid://130956795640089",
		Potion = "rbxassetid://117649365771126",
		ProPack = "rbxassetid://74393775524490",
		RainbowSki = "rbxassetid://91156299597105",
		Rebirth = "rbxassetid://128632615426066",
		Rides = "rbxassetid://103491500818363",
		Settings = "rbxassetid://94120245784614",
		Shark = "rbxassetid://102641933929845",
		SharkBoard = "rbxassetid://88558989876227",
		Shield = "rbxassetid://123185396520462",
		Shop = "rbxassetid://82496220854201",
		Sneaker = "rbxassetid://116257421291270",
		Sparkle = "rbxassetid://118244330167351",
		StarCoin = "rbxassetid://101545195141785",
		StarterPack = "rbxassetid://126843834331589",
		StoreX2Coins = "rbxassetid://134452634708302",
		StoreX2Speed = "rbxassetid://73182085126666",
		Tank = "rbxassetid://73749574923923",
		TankPlus = "rbxassetid://131372938386364",
		Trophy = "rbxassetid://126371306790201",
		X2Coins = "rbxassetid://90247318649842",
		X2Speed = "rbxassetid://112413892397932",
		ZoneAnchor = "rbxassetid://131596298325895",
		ZoneKelp = "rbxassetid://98223045791974",
		ZonePalm = "rbxassetid://135810028246938",
		ZoneSquid = "rbxassetid://85731802908612",
		ZoneWhale = "rbxassetid://84781196572945",
		Speed = "rbxassetid://126986288562777",
		Coins = "rbxassetid://105800729762887",
	},
	-- names the game asks for that share another icon's art
	alias = {
		BigTankPass = "TankPlus",
		SpeedPack0 = "Sneaker", SpeedPack1 = "Sneaker", SpeedPack2 = "Sneaker", SpeedPack3 = "Sneaker", SpeedPack4 = "Sneaker",
		MoneyPack0 = "Cash", MoneyPack1 = "Cash", MoneyPack2 = "MoneyBag", MoneyPack3 = "MoneyBag", MoneyPack4 = "Chest",
		Lagoon = "ZonePalm", Reef = "Coral", Kelp = "ZoneKelp", Shipwreck = "ZoneAnchor", Deep = "ZoneWhale", Abyss = "ZoneSquid",
		-- (no art yet for these: upload ZoneIce / ZoneVolcano / ZoneTemple and add them to ids)
		Frozen = "ZoneWhale", Volcano = "ZoneSquid", Atlantis = "Crown",
		Soda = "ZonePalm", Gumdrop = "Coral", Lolly = "ZoneKelp", Cane = "ZoneAnchor", Choco = "ZoneWhale", Sugar = "ZoneSquid",
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

-- Daily quests: 3 a day (new ones at midnight UTC), picked from this pool.
-- Each pays cash when done (income-scaled); all 3 add a Luck Potion.
-- `vet` = only for players who can chum (Config.Chum.minPlaytime).
Config.Quests = {
	perDay = 3,
	coinSeconds = 180,
	minCoins = 300,
	bonus = { kind = "luck", minutes = 15 },
	pool = {
		{ id = "rares", text = "Catch %d Rares or better", goal = 3 },
		{ id = "home", text = "Bring %d creatures home", goal = 15 },
		{ id = "close", text = "Escape a shark %d times", goal = 2 },
		{ id = "dodge", text = "Dodge %d shark lunges", goal = 3 },
		{ id = "rings", text = "Ride through %d boost rings", goal = 5 },
		{ id = "night", text = "Catch %d creatures at night", goal = 5 },
		{ id = "chum", text = "Chum %d riders", goal = 2, vet = true },
		{ id = "bonk", text = "Bonk loot loose %d times", goal = 2, vet = true },
		{ id = "daze", text = "Daze %d sharks with your noodle", goal = 2 },
	},
}

-- Playtime gifts: free, every session, the longer you stay the better
-- (at = minutes played this session). The HUD gift square counts down.
Config.PlayGifts = {
	{ at = 3, kind = "coins", seconds = 45, min = 60, label = "Bag of Cash", icon = "Cash" },
	{ at = 8, kind = "boost", minutes = 5, label = "2x Speed 5 min", icon = "Boost" },
	{ at = 15, kind = "shield", amount = 1, label = "Shark Shield", icon = "Shield" },
	{ at = 25, kind = "luck", minutes = 10, label = "Luck Potion", icon = "Potion" },
	{ at = 40, kind = "creature", rarity = "Epic", label = "Epic Creature", icon = "GoldBubble" },
	{ at = 60, kind = "creature", rarity = "Legendary", label = "Legendary Creature", icon = "Crown" },
} :: { { [string]: any } }

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
	wander: number?, -- ride loops: how far the pitch drifts (+-, default 0.03) so a loop never sounds stuck
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
	-- (a short loop: quieter, and its pitch wanders more so it doesn't nag)
	rideKick = { file = F.swim, loop = { 1.426, 4.198 }, pitch = 1.12, gain = 0.42, wander = 0.08 },
	rideDuck = { file = F.paddle, loop = { 40.008, 43.98 }, gain = 0.73, every = { "duckSqueak", 5, 10, 0.3 } },
	rideSurf = { file = F.flow, loop = { 9.95, 14.215 }, eq = { -6, 0, 2 }, gain = 0.36 },
	rideBubbles = { file = F.deep, loop = { 0, 1.12 }, gain = 0.33 },
	-- the Bathtub: a soft paddling loop with a quiet bubble now and then (the
	-- bubble loop on its own was a constant glug)
	rideTub = { file = F.swim, loop = { 2.782, 8.443 }, pitch = 0.88, gain = 0.5, every = { "tubBubble", 6, 11, 0.22 } },
	tubBubble = { file = F.deep, from = 0, to = 0.6, pitch = 1.25, gain = 0.3, fade = 0.2 },
	rideMotor = { file = F.boat, loop = { 2.015, 4.801 }, pitch = 0.82, gain = 0.48 },
	rideJetSki = { file = F.jetski, loop = { 7.476, 9.306 }, gain = 0.74 },
	rideBoat = { file = F.boat, loop = { 5.548, 8.76 }, gain = 0.42 },
	rideDolphin = { file = F.swim, loop = { 2.782, 8.443 }, pitch = 1.05, gain = 0.72, every = { "dolphinCall", 4, 8, 0.45 } },
	rideRocket = { file = F.rocket, gain = 2.9 }, -- already a seamless loop
	-- ambience
	ambWaves = { file = F.waves, gain = 0.2 }, -- open-sea bed (a seamless loop; quiet: it's always on)
	ambShore = { file = F.waves, loop = { 25.95, 36.203 }, pitch = 1.08, eq = { -8, 0, 2 }, gain = 0.22 }, -- small waves on the sand (many emitters overlap: keep low)
	ambGulls = { file = F.gulls, loop = { 0.036, 29.93 }, gain = 25 }, -- a very quiet recording
	ambTank = { file = F.deep, loop = { 0, 2.4 }, pitch = 0.7, eq = { 0, 0, -8 }, gain = 0.26 }, -- a bloop every few seconds
} :: { [string]: SoundSlot }

-- which loop each ride plays, and its base pitch
Config.RideSound = {
	Noodle = { "rideSplash", 1.0 }, Tube = { "rideSplash", 0.95 }, Donut = { "rideSplash", 0.9 },
	Duck = { "rideDuck", 1.0 }, GoldDuck = { "rideDuck", 1.08 },
	Boogie = { "rideKick", 1.0 },
	Surf = { "rideSurf", 1.0 }, SharkBoard = { "rideSurf", 0.92 },
	Bathtub = { "rideTub", 1.0 },
	Banana = { "rideMotor", 1.0 },
	JetSki = { "rideJetSki", 1.0 }, RainbowSki = { "rideJetSki", 1.12 },
	Speedboat = { "rideBoat", 1.0 },
	Dolphin = { "rideDolphin", 1.0 },
	Rocket = { "rideRocket", 1.0 },
} :: { [string]: { any } }

return Config
