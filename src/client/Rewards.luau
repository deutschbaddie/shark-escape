-- Daily Rewards window + the group chest (client side; the server decides).
--   Daily:  a 7-day calendar (days 1-6 in a grid, Day 7 the big Limited one).
--           Opens by itself once per session when a reward is ready (after
--           the tutorial), or from the gift square on the HUD.
--   Chest:  "Join Group & Like to Claim!". Pressing E asks the server; if
--           you're not in the group yet it shows Roblox's join prompt and
--           the favorite (like) prompt, then you press E again.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ProximityPromptService = game:GetService("ProximityPromptService")

local Shared = game.ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local UI = require(script.Parent.UI)
local Fx = require(script.Parent.Fx)
local State = require(script.Parent.State)
local Notify = require(script.Parent.Notify)

local Rewards = {}
local player = Players.LocalPlayer
local C = UI.C

local gui: ScreenGui
local window: Frame? = nil
local dailyReadyAt = math.huge
local groupReadyAt = 0
local autoOpened = false
local askedLike = false

----------------------------------------------------------------- daily window
local function close()
	if window then
		window:Destroy()
		window = nil
	end
end

local function tile(parent: Instance, day: number, state: string, size: UDim2, pos: UDim2)
	local r = Config.Daily[day]
	local limited = r.limited == true
	local f = UI.frame(parent, { Size = size, Position = pos, BackgroundColor3 = limited and C.purple or C.gold })
	UI.corner(f, 10)
	UI.stroke(f, C.ink, 3)
	UI.shade(f)
	UI.studs(f, { size = 18, alpha = 0.86 })
	if limited then
		UI.rainbow(f)
	end
	-- "DAY n" tab across the top
	local tab = UI.frame(f, { Size = UDim2.new(1, -16, 0, 34), Position = UDim2.new(0.5, 0, 0, -8), AnchorPoint = Vector2.new(0.5, 0),
		BackgroundColor3 = state == "today" and C.green or C.orange, ZIndex = f.ZIndex + 2 })
	UI.corner(tab, 8)
	UI.stroke(tab, C.ink, 3)
	UI.outlined(tab, ("DAY %d"):format(day), { Size = UDim2.new(1, -8, 1, -6), Position = UDim2.fromOffset(4, 3), Font = UI.NUMFONT, ZIndex = tab.ZIndex + 1 })
	if limited then
		UI.outlined(f, "Limited!", { Size = UDim2.new(1, -16, 0, 30), Position = UDim2.fromOffset(8, 34), TextColor3 = C.gold, ZIndex = f.ZIndex + 2 })
	end
	UI.icon(f, r.icon or "Gift", { Size = UDim2.new(1, -24, limited and 0.45 or 0.42, 0), Position = UDim2.fromScale(0.5, limited and 0.52 or 0.56),
		AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = f.ZIndex + 2 })
	UI.outlined(f, r.label, { Size = UDim2.new(1, -12, 0, limited and 40 or 24), Position = UDim2.new(0.5, 0, 1, -8), AnchorPoint = Vector2.new(0.5, 1),
		ZIndex = f.ZIndex + 2 })
	if state == "claimed" then
		local dim = UI.frame(f, { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.45, ZIndex = f.ZIndex + 3 })
		UI.corner(dim, 10)
		UI.outlined(dim, "✓", { Size = UDim2.fromScale(0.7, 0.7), Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5),
			TextColor3 = C.green, ZIndex = dim.ZIndex + 1 })
	elseif state == "today" then
		UI.pulse(f)
	end
end

function Rewards.openDaily()
	close()
	local d = State.data
	if not d then
		return
	end
	local f, body = UI.window(gui, "Daily Rewards", C.orange, Vector2.new(640, 500), close, "Gift")
	window = f
	local nextDay = d.dailyDay or 1
	local ready = os.clock() >= dailyReadyAt
	local function state(day: number): string
		if day < nextDay then
			return "claimed"
		elseif day == nextDay then
			return ready and "today" or "next"
		end
		return "later"
	end
	-- days 1-6: 3 x 2 grid; day 7: tall on the right
	local grid = UI.frame(body, { Size = UDim2.new(1, 0, 1, -76), BackgroundTransparency = 1 })
	local cw, ch, gap = 134, 152, 12
	for day = 1, 6 do
		local col, row = (day - 1) % 3, (day - 1) // 3
		tile(grid, day, state(day), UDim2.fromOffset(cw, ch), UDim2.fromOffset(col * (cw + gap) + 4, row * (ch + gap) + 10))
	end
	tile(grid, 7, state(7), UDim2.fromOffset(cw + 24, ch * 2 + gap), UDim2.fromOffset(3 * (cw + gap) + 4, 10))
	-- claim button / time to the next one
	if ready then
		UI.button(body, "CLAIM YOUR REWARD", C.green, function()
			State.action("claimDaily")
		end, { Size = UDim2.fromOffset(330, 58), Position = UDim2.new(0.5, 0, 1, -4), AnchorPoint = Vector2.new(0.5, 1) })
	else
		local left = math.max(0, dailyReadyAt - os.clock())
		local t = UI.outlined(body, "Next reward in " .. UI.timeWords(left), { Size = UDim2.fromOffset(420, 36), Position = UDim2.new(0.5, 0, 1, -14),
			AnchorPoint = Vector2.new(0.5, 1), TextColor3 = C.gold })
		task.spawn(function()
			while t.Parent do
				t.Text = "Next reward in " .. UI.timeWords(math.max(0, dailyReadyAt - os.clock()))
				task.wait(1)
			end
		end)
	end
end

function Rewards.dailyReady(): boolean
	return os.clock() >= dailyReadyAt
end

----------------------------------------------------------------- group chest
-- while Roblox's favorite prompt is open it covers the middle of the screen,
-- so the chest reward waits until it's closed
local likeOpenUntil = 0
local function promptLike()
	-- the favorite button for this game ("like"); Roblox shows its own prompt
	local ok = pcall(function()
		local aes = game:GetService("AvatarEditorService")
		aes.PromptSetFavoriteCompleted:Once(function()
			likeOpenUntil = 0
		end)
		aes:PromptSetFavorite(game.PlaceId, Enum.AvatarItemType.Asset, true)
	end)
	if ok then
		likeOpenUntil = os.clock() + 20
	end
end

local function promptGroup()
	if Config.GroupId == 0 then
		return
	end
	task.spawn(function()
		pcall(function()
			(game:GetService("GroupService") :: any):PromptJoinAsync(Config.GroupId)
		end)
	end)
end

local function chestSign()
	local map = Workspace:FindFirstChild("Map")
	local chest = map and map:FindFirstChild("GroupChest")
	local anchor = chest and chest:FindFirstChild("Sign")
	if not anchor then
		return
	end
	local left = groupReadyAt - os.clock()
	for _, bb in anchor:GetChildren() do
		local title = bb:FindFirstChild("Title") :: TextLabel?
		local sub = bb:FindFirstChild("Sub") :: TextLabel?
		if title then
			title.Text = left > 0 and "CLAIMED" or "CLAIM"
		end
		if sub then
			sub.Text = left > 0 and ("Next chest in " .. UI.timeWords(left))
				or (Config.GroupId ~= 0 and "Join Group & Like To Claim!" or "Like The Game To Claim!")
		end
	end
end

----------------------------------------------------------------- start
function Rewards.start()
	gui = Instance.new("ScreenGui")
	gui.Name = "Rewards"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 9
	gui.Parent = player:WaitForChild("PlayerGui")
	UI.autoScale(gui, Vector2.new(660, 520))

	local function onState(d: any)
		local wasReady = os.clock() >= dailyReadyAt
		dailyReadyAt = os.clock() + (d.dailyWait or 0)
		groupReadyAt = os.clock() + (d.groupWait or 0)
		if window and wasReady ~= (os.clock() >= dailyReadyAt) then
			Rewards.openDaily() -- just claimed: redraw with the day ticked off
		end
		-- a reward waiting: open the calendar once per session (after the tutorial)
		if not autoOpened and d.tut >= 5 and (d.dailyWait or 1) <= 0 and not player:GetAttribute("Cinematic") then
			autoOpened = true
			task.delay(2, Rewards.openDaily)
		end
	end
	State.Changed:Connect(onState)
	if State.data then
		onState(State.data)
	end

	ProximityPromptService.PromptTriggered:Connect(function(prompt, who)
		if who ~= player or prompt.Name ~= "GroupChest" then
			return
		end
		if not askedLike then
			askedLike = true
			promptLike()
		end
		State.action("claimGroup")
	end)

	Remotes.get("Notify").OnClientEvent:Connect(function(kind, data)
		if kind == "daily" then
			if data.ok then
				Notify.takeover(("DAY %d!"):format(data.day), data.text, C.gold, 1.6)
				Fx.sound("buy", 0.8)
				Fx.confetti((player.Character and player.Character:GetPivot().Position) or Vector3.zero)
			else
				Notify.toast("Next daily reward in " .. UI.timeWords(data.wait or 0), C.gold)
			end
		elseif kind == "groupChest" then
			if data.ok then
				while os.clock() < likeOpenUntil do
					task.wait(0.2)
				end
				task.wait(0.3)
				Notify.takeover("CHEST CLAIMED!", ("+$%s · 2x speed for %d min"):format(UI.short(data.coins), data.minutes), C.gold, 1.6)
				Fx.sound("buy", 0.8)
				Fx.confetti((player.Character and player.Character:GetPivot().Position) or Vector3.zero)
			elseif data.reason == "group" then
				Notify.banner("Join the group to open the chest!", { key = "chest", priority = 2, time = 3.5, color = C.gold,
					sub = "Then press E on the chest again" })
				promptGroup()
			elseif data.reason == "wait" then
				Notify.toast("The chest refills in " .. UI.timeWords(data.wait or 0), C.gold)
			end
		end
	end)

	RunService.Heartbeat:Connect(function()
		chestSign()
	end)
end

return Rewards
