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
	{ id = "Noodle", name = "Pool Noodle", icon = "🟠", price = 0, gain = 1 },
	{ id = "Duck", name = "Rubber Duck Floatie", icon = "🦆", price = 25, gain = 2 },
	{ id = "Tube", name = "Inner Tube", icon = "🛟", price = 100, gain = 4 },
	{ id = "Boogie", name = "Boogie Board", icon = "🟥", price = 400, gain = 8 },
	{ id = "Surf", name = "Surfboard", icon = "🏄", price = 1500, gain = 15 },
	{ id = "Bathtub", name = "Bathtub", icon = "🛁", price = 5000, gain = 30 },
	{ id = "Banana", name = "Banana Boat", icon = "🍌", price = 15000, gain = 60 },
	{ id = "JetSki", name = "Jet Ski", icon = "🚤", price = 50000, gain = 120 },
	{ id = "Speedboat", name = "Speedboat", icon = "🛥️", price = 150000, gain = 250 },
	{ id = "Dolphin", name = "Dolphin", icon = "🐬", price = 500000, gain = 500 },
	{ id = "Donut", name = "Giant Donut", icon = "🍩", price = 1500000, gain = 1000 },
	{ id = "Rocket", name = "Rocket Surfboard", icon = "🚀", price = 5000000, gain = 2500 },
	-- Robux rides: never skip the ladder, they multiply it.
	{ id = "GoldDuck", name = "Golden Duck", icon = "✨", price = 0, robux = "GoldDuck", mult = 1.25 },
	{ id = "SharkBoard", name = "Shark Board", icon = "🦈", price = 0, robux = "SharkBoard", mult = 1.5 },
	{ id = "RainbowSki", name = "Rainbow Jet Ski", icon = "🌈", price = 0, robux = "RainbowSki", mult = 2 },
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

----------------------------------------------------------------- creatures
export type Rarity = { id: string, weight: number, mult: number, color: Color3, species: string, icon: string, index: number }

Config.Rarities = {
	{ id = "Common", weight = 60, mult = 1, color = Color3.fromRGB(205, 214, 224), species = "Clownfish", icon = "🐠" },
	{ id = "Uncommon", weight = 25, mult = 3, color = Color3.fromRGB(96, 214, 110), species = "Pufferfish", icon = "🐡" },
	{ id = "Rare", weight = 10, mult = 10, color = Color3.fromRGB(64, 156, 255), species = "Octopus", icon = "🐙" },
	{ id = "Epic", weight = 4, mult = 40, color = Color3.fromRGB(190, 92, 255), species = "Sea Turtle", icon = "🐢" },
	{ id = "Legendary", weight = 1, mult = 200, color = Color3.fromRGB(255, 196, 40), species = "Narwhal", icon = "🦄" },
} :: { Rarity }
for i, r in Config.Rarities do
	r.index = i
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
	{ id = "Rainbow", chance = 0.003, mult = 10, color = Color3.fromRGB(255, 120, 220) },
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
function Config.creatureValue(rarityId: string, zoneId: string, mutationId: string?): number
	local zone = Config.zoneById(zoneId)
	local m = Config.mutation(mutationId)
	return (zone and zone.value or 1) * Config.rarity(rarityId).mult * (m and m.mult or 1)
end

Config.Luck = {
	base = 0.05, -- chance a grab bumps up one rarity ("LUCKY!")
	pass = 0.15,
	potion = 0.15,
	pityGrab = 3, -- the 3rd creature you ever grab is at least Rare
}

Config.BUBBLES_PER_ZONE = 9
Config.GRAB_RADIUS = 6.5
Config.DEPOSIT_RADIUS = 15
Config.COLLECT_RADIUS = 6
Config.SELL_SECONDS = 20 -- a creature that doesn't fit sells for this many seconds of its income

----------------------------------------------------------------- tank
Config.Tank = {
	startSlots = 4,
	maxSlots = 12,
	passSlots = 4,
	-- price of slot #5, #6, ... #12
	slotPrices = { 250, 1000, 4000, 15000, 60000, 250000, 1000000, 4000000 },
}

----------------------------------------------------------------- sharks
Config.Shark = {
	cycle = 60, -- seconds between attacks
	firstAttack = 45,
	warning = 5,
	hunt = 9,
	spawnDistance = 58,
	maxHunters = 24,
	newPlayerGrace = 150, -- seconds before a brand-new player can be hunted
	eatenTime = 1.4,
}

----------------------------------------------------------------- rebirth
Config.Rebirth = { speed = 25000, mult = 1.5 }

----------------------------------------------------------------- monetization
-- Fill these in from Creator Dashboard after you create the passes/products.
-- An id of 0 hides the buy button instead of prompting a fake purchase.
Config.Passes = {
	TwoXSpeed = { id = 0, price = 399, name = "2x Speed", icon = "⚡", desc = "Double speed gain forever" },
	TwoXCoins = { id = 0, price = 199, name = "2x Coins", icon = "💰", desc = "Double coins from your tank" },
	AutoCollect = { id = 0, price = 99, name = "Auto Collect", icon = "🧲", desc = "Coins go straight to you" },
	LuckyNet = { id = 0, price = 199, name = "Lucky Net", icon = "🍀", desc = "+15% chance to upgrade rarity" },
	BigTank = { id = 0, price = 99, name = "+4 Tank Slots", icon = "🐟", desc = "Room for 4 more creatures" },
	VIP = { id = 0, price = 399, name = "VIP", icon = "👑", desc = "Gold wake, VIP tag, +10% coins" },
	GoldDuck = { id = 0, price = 99, name = "Golden Duck", icon = "✨", desc = "Ride it - x1.25 speed gain" },
	SharkBoard = { id = 0, price = 199, name = "Shark Board", icon = "🦈", desc = "Ride it - x1.5 speed gain" },
	RainbowSki = { id = 0, price = 399, name = "Rainbow Jet Ski", icon = "🌈", desc = "Ride it - x2 speed gain" },
}

Config.Products = {
	Shield = { id = 0, price = 25, name = "Shark Shield", icon = "🛡️", desc = "Survive one bite, keep your creature" },
	SpeedBoost = { id = 0, price = 49, name = "2x Speed (15 min)", icon = "⏩", desc = "Double speed gain for 15 minutes" },
	LuckPotion = { id = 0, price = 49, name = "Luck Potion (10 min)", icon = "🧪", desc = "+15% rarity upgrade chance" },
	GoldenBubble = { id = 0, price = 99, name = "Golden Bubble", icon = "🫧",
		desc = "Rare 70% · Epic 25% · Legendary 5%" },
	StarterPack = { id = 0, price = 49, name = "Starter Pack", icon = "🎁",
		desc = "Rare Octopus + 30 min 2x Speed + 3 Shields" },
	DoubleOffline = { id = 0, price = 9, name = "2x Offline Coins", icon = "⏰", desc = "Double your welcome-back coins" },
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
	local coins = math.floor(50 * v * r.mult ^ 0.75)
	local speed = math.floor(20 * v ^ 0.8 * r.index)
	return coins, speed
end

----------------------------------------------------------------- offline
-- Your tank keeps earning while you're away (at a slower rate, capped).
Config.Offline = { rate = 0.5, maxHours = 6, minSeconds = 120 }

----------------------------------------------------------------- images
-- Optional uploaded images. Empty strings fall back to built-in looks:
-- Studs: upload assets/textures/studs.png (Creator Hub > Decals) and paste
-- the rbxassetid:// here for a crisper stud texture on buttons and panels.
Config.Images = {
	Studs = "",
}

----------------------------------------------------------------- audio
-- rbxasset:// sounds ship with every Roblox client. Empty strings are slots
-- for Creator Store audio you pick and record in ASSETS.md (never invent ids).
Config.Sounds = {
	splash = "rbxasset://sounds/impact_water.mp3",
	swim = "rbxasset://sounds/action_swim.mp3",
	chomp = "rbxasset://sounds/impact_explosion_03.mp3",
	music = "",
	sharkAlarm = "",
	coin = "",
	buy = "",
	grab = "",
	legendary = "",
}

return Config
