-- The "FASTEST" board in the plaza: global top 10 best speeds from an
-- OrderedDataStore, falling back to the players in this server.

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")

local Game = require(script.Parent.Game)
local World = require(script.Parent.World)

local Leaderboard = {}

local store: OrderedDataStore? = nil
pcall(function()
	store = DataStoreService:GetOrderedDataStore("BestSpeed_v1")
end)

local names: { [number]: string } = {}
local function nameOf(userId: number): string
	if names[userId] then
		return names[userId]
	end
	local p = Players:GetPlayerByUserId(userId)
	if p then
		names[userId] = p.DisplayName
		return p.DisplayName
	end
	local ok, n = pcall(Players.GetNameFromUserIdAsync, Players, userId)
	names[userId] = ok and n or "Player"
	return names[userId]
end

local function short(n: number): string
	local units = { "", "K", "M", "B", "T", "Qa" }
	local i = 1
	while n >= 1000 and i < #units do
		n /= 1000
		i += 1
	end
	return (i == 1 and tostring(math.floor(n)) or (string.format("%.1f", n):gsub("%.0$", ""))) .. units[i]
end

local function render(rows: { { id: number, value: number } })
	local board = World.board
	if not board then
		return
	end
	for i = 1, 10 do
		local row = board:FindFirstChild("Row" .. i)
		local r = rows[i]
		if row then
			-- FindFirstChild: row.Name would be the row's own Name property
			(row:FindFirstChild("Rank") :: TextLabel).Text = r and ("#" .. i) or ""
			(row:FindFirstChild("Name") :: TextLabel).Text = r and nameOf(r.id) or ""
			(row:FindFirstChild("Value") :: TextLabel).Text = r and ("⚡ " .. short(r.value)) or ""
		end
	end
end

local function refresh()
	-- push everyone's best first
	if store then
		for _, s in Game.sessions do
			pcall(function()
				(store :: OrderedDataStore):SetAsync(tostring(s.player.UserId), math.floor(s.profile.bestSpeed))
			end)
		end
		local ok, pages = pcall(function()
			return (store :: OrderedDataStore):GetSortedAsync(false, 10)
		end)
		if ok and pages then
			local rows = {}
			for _, e in pages:GetCurrentPage() do
				table.insert(rows, { id = tonumber(e.key) or 0, value = e.value })
			end
			if #rows > 0 then
				render(rows)
				return
			end
		end
	end
	local rows = {}
	for _, s in Game.sessions do
		table.insert(rows, { id = s.player.UserId, value = s.profile.bestSpeed })
	end
	table.sort(rows, function(a, b)
		return a.value > b.value
	end)
	render(rows)
end

function Leaderboard.start()
	task.spawn(function()
		task.wait(5)
		while true do
			refresh()
			task.wait(90)
		end
	end)
end

return Leaderboard
