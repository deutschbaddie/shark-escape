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
				local x = -W / 2 + W * t + rng:NextNumber(-16, 16)
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
Layout.Plots = {} :: { CFrame }
for i = 1, Config.PLOT_COUNT do
	local x = (i - (Config.PLOT_COUNT + 1) / 2) * Config.PLOT_SPACING
	-- face the ocean (+Z): LookVector points toward the water
	table.insert(Layout.Plots, CFrame.lookAt(Vector3.new(x, Config.BEACH_TOP, Config.PLOT_Z), Vector3.new(x, Config.BEACH_TOP, 100)))
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

----------------------------------------------------------------- queries
function Layout.inWater(pos: Vector3): boolean
	return pos.Z >= Config.SHORE_Z + 1
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

return Layout
