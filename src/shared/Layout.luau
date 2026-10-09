-- Deterministic map layout shared by server (builds it) and client (arrows,
-- safe-spot checks), so nothing has to be streamed or replicated to agree.

local Config = require(script.Parent.Config)

local Layout = {}

export type Island = { pos: Vector3, radius: number, zone: string, palm: boolean }

local W = Config.LANE_WIDTH

----------------------------------------------------------------- islands
Layout.Islands = {} :: { Island }
do
	local rng = Random.new(1337)
	for _, zone in Config.Zones do
		local z = zone.zStart + zone.islandEvery * 0.55
		local row = 0
		while z < zone.zEnd - 30 do
			local count = (row % 2 == 0) and 3 or 2
			for i = 1, count do
				local t = (i - 0.5) / count
				local x = Config.originX(zone.world) - W / 2 + W * t + rng:NextNumber(-16, 16)
				local jitterZ = rng:NextNumber(-12, 12)
				table.insert(Layout.Islands, {
					pos = Vector3.new(x, Config.WATER_Y, z + jitterZ),
					radius = zone.islandRadius + rng:NextNumber(-1.5, 1.5),
					zone = zone.id,
					palm = rng:NextNumber() < 0.6,
				})
			end
			row += 1
			z += zone.islandEvery
		end
	end
end

----------------------------------------------------------------- plots
-- every world has the same row of docks (your dock number is the same in
-- each); Layout.Plots = Shark Beach's, Layout.plot(i, w) any world's
Layout.WorldPlots = {} :: { { CFrame } }
for w in Config.Worlds do
	local list = {}
	local ox = Config.originX(w)
	for i = 1, Config.PLOT_COUNT do
		local x = ox + (i - (Config.PLOT_COUNT + 1) / 2) * Config.PLOT_SPACING
		-- face the ocean (+Z): LookVector points toward the water
		table.insert(list, CFrame.lookAt(Vector3.new(x, Config.BEACH_TOP, Config.PLOT_Z), Vector3.new(x, Config.BEACH_TOP, 100)))
	end
	Layout.WorldPlots[w] = list
end
Layout.Plots = Layout.WorldPlots[1]

function Layout.plot(i: number, w: number?): CFrame
	return Layout.WorldPlots[w or 1][i]
end

-- a world position -> the same spot in Shark Beach's layout (plaza checks)
function Layout.toLocal(pos: Vector3): Vector3
	return pos - Vector3.new(Config.originX(Config.worldAt(pos)), 0, 0)
end

-- where a world's built things live: Shark Beach straight in Workspace.Map,
-- other worlds in Map/World<n> (World.luau)
function Layout.worldFolder(w: number?): Instance?
	local map = workspace:FindFirstChild("Map")
	if not map or (w or 1) == 1 then
		return map
	end
	return map:FindFirstChild("World" .. w)
end

function Layout.worldFolders(): { Instance }
	local out = {}
	for w in Config.Worlds do
		local f = Layout.worldFolder(w)
		if f then
			table.insert(out, f)
		end
	end
	return out
end

-- a Shark Beach layout position -> the same spot in world w
function Layout.inWorld(pos: Vector3, w: number?): Vector3
	return pos + Vector3.new(Config.originX(w), 0, 0)
end

function Layout.tankPos(plot: CFrame): Vector3
	return (plot * CFrame.new(0, 0, 6)).Position
end
function Layout.padPos(plot: CFrame): Vector3
	return (plot * CFrame.new(-10, 0, -10)).Position
end
function Layout.spawnCFrame(plot: CFrame): CFrame
	return plot * CFrame.new(4, 3, -14)
end

----------------------------------------------------------------- plaza buildings
-- The Ride Shop is where rides are bought (the server checks you're there).
Layout.RideShop = Vector3.new(0, Config.BEACH_TOP, -88) -- pedestal
Layout.RideShopPad = Vector3.new(0, Config.BEACH_TOP, -66) -- step here to shop
Layout.RIDE_SHOP_RADIUS = 26
Layout.Huts = {
	{ kind = "Shop", title = "SHOP", color = Color3.fromRGB(255, 70, 170), pos = Vector3.new(-66, Config.BEACH_TOP, -96) },
	{ kind = "Index", title = "INDEX", color = Color3.fromRGB(255, 150, 30), pos = Vector3.new(66, Config.BEACH_TOP, -96) },
	{ kind = "Sell", title = "SELL", color = Color3.fromRGB(70, 210, 90), pos = Vector3.new(106, Config.BEACH_TOP, -96) },
}
-- three leaderboards in a row along the back wall, left of the Shop
Layout.Boards = {
	{ key = "Speed", title = "FASTEST", color = Color3.fromRGB(40, 160, 255), pos = Vector3.new(-130, Config.BEACH_TOP, -116) },
	{ key = "Rebirths", title = "REBIRTHS", color = Color3.fromRGB(70, 210, 90), pos = Vector3.new(-109, Config.BEACH_TOP, -116) },
	{ key = "Caught", title = "MOST CAUGHT", color = Color3.fromRGB(255, 150, 30), pos = Vector3.new(-88, Config.BEACH_TOP, -116) },
}
Layout.Board = Layout.Boards[2].pos -- the middle one (palms keep clear of the row)
Layout.GroupChest = Vector3.new(36, Config.BEACH_TOP, -66) -- "Join Group / Like to Claim!"
Layout.Portal = Vector3.new(-40, Config.BEACH_TOP, -72) -- to the other world (mirrors the chest)
Layout.Warp = Vector3.new(-22, Config.BEACH_TOP, -7) -- zone warp signpost on the sand
Layout.EventBoard = Vector3.new(38, Config.BEACH_TOP, -112) -- Megalodon Hour / next update countdowns

-- standing at a hut's pad (the server checks before selling)
function Layout.atHut(kind: string, pos: Vector3): boolean
	pos = Layout.toLocal(pos)
	for _, h in Layout.Huts do
		if h.kind == kind then
			local pad = h.pos + Vector3.new(0, 0, 9)
			return Vector2.new(pos.X - pad.X, pos.Z - pad.Z).Magnitude < 14 and math.abs(pos.Y - Config.BEACH_TOP) < 12
		end
	end
	return false
end

function Layout.atRideShop(pos: Vector3): boolean
	pos = Layout.toLocal(pos)
	local d = Vector2.new(pos.X - Layout.RideShopPad.X, pos.Z - (Layout.RideShopPad.Z - 8)).Magnitude
	return d < Layout.RIDE_SHOP_RADIUS and math.abs(pos.Y - Config.BEACH_TOP) < 12
end

----------------------------------------------------------------- queries
-- the sand ramp from the beach down onto the water (World.luau builds it)
Layout.RAMP_LEN = 8
-- height of the ground you ride on at z: the beach, the ramp, or the water floor
function Layout.groundY(z: number): number
	local t = math.clamp((z - Config.SHORE_Z) / Layout.RAMP_LEN, 0, 1)
	return Config.BEACH_TOP + (Config.FLOOR_TOP - Config.BEACH_TOP) * t
end

function Layout.inWater(pos: Vector3): boolean
	return pos.Z >= Config.SHORE_Z + 1
end

-- distance from p to the segment a-b on the XZ plane (swept pickups, so
-- nothing is missed at high speed between server ticks)
function Layout.segmentDist(p: Vector3, a: Vector3, b: Vector3): number
	local ab = Vector2.new(b.X - a.X, b.Z - a.Z)
	local ap = Vector2.new(p.X - a.X, p.Z - a.Z)
	local len2 = ab:Dot(ab)
	local t = len2 > 0 and math.clamp(ap:Dot(ab) / len2, 0, 1) or 0
	return (ap - ab * t).Magnitude
end

function Layout.islandAt(pos: Vector3, pad: number?): Island?
	local p = pad or 0
	for _, island in Layout.Islands do
		local d = Vector2.new(pos.X - island.pos.X, pos.Z - island.pos.Z).Magnitude
		if d <= island.radius + p then
			return island
		end
	end
	return nil
end

function Layout.isSafe(pos: Vector3): boolean
	return not Layout.inWater(pos) or Layout.islandAt(pos, 0.5) ~= nil
end

-- nearest safe point: an island or the beach straight back
function Layout.nearestSafe(pos: Vector3): (Vector3, number)
	local best = Vector3.new(pos.X, Config.BEACH_TOP, Config.SHORE_Z - 6)
	local bestD = math.max(pos.Z - Config.SHORE_Z, 0)
	for _, island in Layout.Islands do
		local d = Vector2.new(pos.X - island.pos.X, pos.Z - island.pos.Z).Magnitude - island.radius
		if d < bestD then
			bestD = d
			best = island.pos
		end
	end
	return best, bestD
end

----------------------------------------------------------------- boost rings
-- Hoops standing on the water (facing along the lane): ride through one for
-- a speed burst + a pop into the air + a little speed (server checks it).
Layout.RING_RADIUS = 5.5
Layout.RING_Y = 4.6
Layout.Rings = {} :: { Vector3 }
Layout.CHAIN_LEN = 5
Layout.Chain = {} :: { [number]: { chain: number, step: number } }
Layout.Chains = 0
do
	local rng = Random.new(4242)
	for _, zone in Config.Zones do
		local count = math.clamp(math.floor(zone.length / 110), 2, 12)
		local placed = 0
		for _ = 1, count * 6 do
			if placed >= count then
				break
			end
			local p = Vector3.new(Config.originX(zone.world) + rng:NextNumber(-W / 2 + 22, W / 2 - 22), Layout.RING_Y,
				rng:NextNumber(zone.zStart + 30, zone.zEnd - 30))
			if not Layout.islandAt(p, 10) then
				table.insert(Layout.Rings, p)
				placed += 1
			end
		end
	end
	-- slaloms: a weaving line of 5 cyan hoops in every zone past the first;
	-- hit them all in a row for a bigger bonus (Layout.Chain[i] = chain, step)
	for _, zone in Config.Zones do
		if zone.index >= 2 then
			for _ = 1, 10 do
				local x0 = Config.originX(zone.world) + rng:NextNumber(-W / 2 + 40, W / 2 - 40)
				local z0 = rng:NextNumber(zone.zStart + 40, zone.zEnd - 260)
				local pts = {}
				for k = 0, Layout.CHAIN_LEN - 1 do
					local p = Vector3.new(x0 + math.sin(k * 1.3) * 14, Layout.RING_Y, z0 + k * 45)
					if Layout.islandAt(p, 10) then
						pts = nil
						break
					end
					table.insert(pts, p)
				end
				if pts then
					Layout.Chains += 1
					for k, p in pts do
						table.insert(Layout.Rings, p)
						Layout.Chain[#Layout.Rings] = { chain = Layout.Chains, step = k }
					end
					break
				end
			end
		end
	end
end

return Layout
