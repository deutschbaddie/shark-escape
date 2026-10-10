-- The plaza boards (Layout.Boards): global top 10 for best speed, rebirths,
-- creatures caught and Top Bonkers (loot knocked loose), from OrderedDataStores. The players in this server
-- show right away, so a board is never empty while the global list loads
-- (or when DataStores are off in Studio).

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")

local Game = require(script.Parent.Game)
local World = require(script.Parent.World)

local Leaderboard = {}

-- board key -> its store and the profile value it ranks
local BOARDS = {
	Speed = { store = "BestSpeed_v1", value = function(p: any): number
		return p.bestSpeed
	end },
	Rebirths = { store = "Rebirths_v1", value = function(p: any): number
		return p.rebirths
	end },
	Caught = { store = "Caught_v1", value = function(p: any): number
		return p.grabs
	end },
	Bonks = { store = "Bonks_v1", value = function(p: any): number
		return p.bonks -- creatures knocked loose with the noodle
	end },
}

local stores: { [string]: OrderedDataStore } = {}
for key, b in BOARDS do
	pcall(function()
		stores[key] = DataStoreService:GetOrderedDataStore(b.store)
	end)
end

-- last value written per board+player, so unchanged values aren't re-sent
local written: { [string]: number } = {}

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

local fill: (SurfaceGui, { { id: number, value: number } }) -> ()

local function render(key: string, rows: { { id: number, value: number } })
	for _, board in World.boards[key] or {} do
		fill(board, rows)
	end
end

function fill(board: SurfaceGui, rows: { { id: number, value: number } })
	for i = 1, 10 do
		local row = board:FindFirstChild("Row" .. i)
		local r = rows[i]
		if row then
			-- FindFirstChild: row.Name would be the row's own Name property
			(row:FindFirstChild("Rank") :: TextLabel).Text = r and ("#" .. i) or ""
			(row:FindFirstChild("Name") :: TextLabel).Text = r and nameOf(r.id) or ""
			(row:FindFirstChild("Value") :: TextLabel).Text = r and Game.short(r.value) or ""
		end
	end
end

-- this server's players, best first
local function local_(key: string): { { id: number, value: number } }
	local rows = {}
	for _, s in Game.sessions do
		local v = math.floor(BOARDS[key].value(s.profile))
		if v > 0 then
			table.insert(rows, { id = s.player.UserId, value = v })
		end
	end
	table.sort(rows, function(a, b)
		return a.value > b.value
	end)
	return rows
end

local function refresh(key: string)
	render(key, local_(key))
	local store = stores[key]
	if not store then
		return
	end
	for _, s in Game.sessions do
		local v = math.floor(BOARDS[key].value(s.profile))
		local id = key .. s.player.UserId
		if v > 0 and written[id] ~= v then
			if pcall(store.SetAsync, store, tostring(s.player.UserId), v) then
				written[id] = v
			end
		end
	end
	local ok, pages = pcall(store.GetSortedAsync, store, false, 10)
	if not ok or not pages then
		return
	end
	local rows = {}
	for _, e in pages:GetCurrentPage() do
		table.insert(rows, { id = tonumber(e.key) or 0, value = e.value })
	end
	if #rows > 0 then
		render(key, rows)
	end
end

function Leaderboard.start()
	for key in BOARDS do
		task.spawn(function()
			task.wait(3)
			while true do
				refresh(key)
				task.wait(90)
			end
		end)
	end
	-- someone new joined: put them on the boards now, not in 90 s
	Players.PlayerAdded:Connect(function()
		task.wait(8)
		for key in BOARDS do
			render(key, local_(key))
		end
	end)
end

return Leaderboard
