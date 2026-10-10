-- Daily Rewards window + the group chest (client side; the server decides).
--   Daily:  a 7-day calendar (days 1-6 in a grid, Day 7 the big Limited one)
--           and today's 3 quests under it (server: Quests.luau).
--           Opens by itself once per session when a reward is ready (after
--           the tutorial), or from the gift square on the HUD.
--   Chest:  "Join Group & Like to Claim!". Pressing E asks the server; if
--           you're not in the group yet it shows Roblox's join prompt and
--           the favorite (like) prompt, then you press E again.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Layout = require(game.ReplicatedStorage.Shared.Layout)

local Shared = game.ReplicatedStorage.Shared
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local UI = require(script.Parent.UI)
local Fx = require(script.Parent.Fx)
local State = require(script.Parent.State)
local Notify = require(script.Parent.Notify)
local Shop = require(script.Parent.Shop)

local Rewards = {}
local player = Players.LocalPlayer
local C = UI.C

local gui: ScreenGui
local window: Frame? = nil
local dailyReadyAt = math.huge
local groupReadyAt = 0
local autoOpened = false
local waitForTrip: boolean? = nil -- new player: no calendar until their first trip after the guide
local askedLike = false

----------------------------------------------------------------- daily window
local T = UI.T
local revealDay, revealAt = 0, -math.huge

local questsRow: (Instance, number, any) -> ()

local function close()
	if window then
		window:Destroy()
		window = nil
	end
end

-- a check mark from two rounded bars (no glyph or image needed)
local function check(parent: Instance, size: number, z: number)
	local box = UI.frame(parent, { Name = "Check", Size = UDim2.fromOffset(size, size), Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1, ZIndex = z })
	for _, leg in { { 0.34, 0.62, 0.18, 0.42, -45 }, { 0.6, 0.47, 0.18, 0.8, 40 } } do
		local bar = UI.frame(box, { Size = UDim2.fromScale(leg[3], leg[4]), Position = UDim2.fromScale(leg[1], leg[2]), AnchorPoint = Vector2.new(0.5, 0.5),
			Rotation = leg[5], BackgroundColor3 = T.green, ZIndex = z })
		UI.corner(bar, 100)
		UI.stroke(bar, UI.dark(T.green, 0.55), UI.S.card)
	end
	return box
end

-- the claimed tile pops and sparkles, and its reward floats up
local function reveal(day: number)
	local body = window and window:FindFirstChild("Body")
	local tile = body and body:FindFirstChild("Day" .. day, true) :: Frame?
	if not tile then
		return
	end
	UI.pop(tile, 1.25)
	-- sparkles burst from the tile's middle (children of the tile: it never clips)
	local parent = tile
	local center = UDim2.fromScale(0.5, 0.5)
	for i = 1, 10 do
		local a = (i / 10) * math.pi * 2
		local sp = UI.frame(parent, { Size = UDim2.fromOffset(12, 12), Position = center, AnchorPoint = Vector2.new(0.5, 0.5), Rotation = 45,
			BackgroundColor3 = i % 2 == 0 and T.gold or T.white, ZIndex = tile.ZIndex + 10 })
		UI.corner(sp, 3)
		local dist = 80 + (i % 3) * 18
		TweenService:Create(sp, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Position = center + UDim2.fromOffset(math.cos(a) * dist, math.sin(a) * dist), BackgroundTransparency = 1, Rotation = 225,
			Size = UDim2.fromOffset(4, 4) }):Play()
		task.delay(0.65, function()
			sp:Destroy()
		end)
	end
	local text = UI.label(parent, "value", Config.Daily[day].label, { Size = UDim2.fromOffset(260, 36), Position = center, AnchorPoint = Vector2.new(0.5, 0.5),
		TextColor3 = T.gold, ZIndex = tile.ZIndex + 11 })
	UI.pop(text, 0.6)
	TweenService:Create(text, TweenInfo.new(1.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Position = center - UDim2.fromOffset(0, 70) }):Play()
	task.delay(0.8, function()
		if text.Parent then
			UI.fade(text, false, 0.3)
		end
	end)
	task.delay(1.2, function()
		text:Destroy()
	end)
end

local function tile(parent: Instance, day: number, state: string, size: UDim2, pos: UDim2)
	local r = Config.Daily[day]
	local big = r.limited == true
	local today = state == "today"
	local accent = (today and T.green) or (big and state ~= "claimed" and T.gold) or nil
	local bg = (state == "claimed" and T.navyDark) or (today and UI.light(T.navyLight, 0.12)) or (big and UI.dark(T.purple, 0.45)) or T.navyLight
	local f = UI.card(parent, accent, { Name = "Day" .. day, Size = size, Position = pos, BackgroundColor3 = bg })
	if today then
		(f:FindFirstChild("Accent") :: UIStroke).Thickness = 5 -- extra thick edge: this is the one
		UI.chip(f, "TODAY", T.green, { Size = UDim2.new(1, -16, 0, 28), Position = UDim2.fromOffset(8, 8) })
	else
		UI.label(f, "body", ("DAY %d"):format(day), { Size = UDim2.new(1, -16, 0, 26), Position = UDim2.fromOffset(8, 8),
			TextColor3 = state == "claimed" and T.mute or T.white })
	end
	if big then
		UI.chip(f, "BIG PRIZE", T.gold, { Size = UDim2.fromOffset(130, 26), Position = UDim2.new(0.5, 0, 0, 42), AnchorPoint = Vector2.new(0.5, 0) })
	end
	local iconSize = big and 132 or 60
	local ic = UI.icon(f, r.icon or "Gift", { Size = UDim2.fromOffset(iconSize, iconSize), Position = UDim2.new(0.5, 0, 0.5, big and 6 or 2), AnchorPoint = Vector2.new(0.5, 0.5) })
	if state == "claimed" and ic:IsA("ImageLabel") then
		ic.ImageTransparency = 0.6
	end
	UI.label(f, big and "value" or "body", r.label, { Size = UDim2.new(1, -16, 0, big and 32 or 22), Position = UDim2.new(0, 8, 1, -10), AnchorPoint = Vector2.new(0, 1),
		TextColor3 = (state == "claimed" or state == "later") and T.mute or (big and T.gold or T.white) })
	if state == "claimed" then
		check(f, big and 96 or 60, f.ZIndex + 3)
	elseif state == "next" then
		-- not ready yet: count down on the tile itself
		local t = UI.label(f, "meta", "", { Size = UDim2.new(1, -16, 0, 18), Position = UDim2.new(0, 8, 1, big and -46 or -36), AnchorPoint = Vector2.new(0, 1),
			TextColor3 = T.gold })
		task.spawn(function()
			while t.Parent do
				t.Text = "in " .. UI.timeWords(math.max(0, dailyReadyAt - os.clock()))
				task.wait(1)
			end
		end)
	elseif today then
		-- the whole tile claims too
		local hit = Instance.new("TextButton")
		hit.Text = ""
		hit.BackgroundTransparency = 1
		hit.Size = UDim2.fromScale(1, 1)
		hit.ZIndex = f.ZIndex + 5
		hit.Parent = f
		hit.Activated:Connect(function()
			State.action("claimDaily")
		end)
		-- it glows in place (the edge brightens and the icon bobs inside the
		-- tile; the tile itself never grows over its neighbours)
		local edge = f:FindFirstChild("Accent") :: UIStroke?
		local icScale = Instance.new("UIScale")
		icScale.Parent = ic
		task.spawn(function()
			local info = TweenInfo.new(0.6, Enum.EasingStyle.Sine)
			while f.Parent do
				if edge then
					TweenService:Create(edge, info, { Color = UI.light(T.green, 0.45) }):Play()
				end
				TweenService:Create(icScale, info, { Scale = 1.12 }):Play()
				task.wait(0.6)
				if edge then
					TweenService:Create(edge, info, { Color = T.green }):Play()
				end
				TweenService:Create(icScale, info, { Scale = 1 }):Play()
				task.wait(0.6)
			end
		end)
	end
end

-- today's quests: three cards with a progress bar each
function questsRow(parent: Instance, y: number, d: any)
	local list = d.quests or {}
	if #list == 0 then
		return
	end
	UI.label(parent, "body", ("Today's quests · new ones in %s"):format(UI.timeWords(d.questsReset or 0)),
		{ Size = UDim2.new(1, 0, 0, 24), Position = UDim2.fromOffset(0, y), TextXAlignment = Enum.TextXAlignment.Left })
	local gap = 12
	for i, q in list do
		local done = q.n >= q.goal
		local card = UI.card(parent, done and T.green or T.navyLight, { Size = UDim2.new(1 / #list, -gap * (#list - 1) / #list, 0, 78),
			Position = UDim2.new((i - 1) / #list, (i - 1) * gap / #list, 0, y + 28) })
		UI.label(card, "body", q.text, { Size = UDim2.new(1, -16, 0, 40), Position = UDim2.fromOffset(8, 4), TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top })
		local track = UI.frame(card, { Size = UDim2.new(1, -20, 0, 20), Position = UDim2.new(0, 10, 1, -26), BackgroundColor3 = T.navyDark })
		UI.corner(track, 10)
		UI.corner(UI.frame(track, { Size = UDim2.fromScale(math.clamp(q.n / q.goal, 0, 1), 1), BackgroundColor3 = done and T.gold or T.green }), 10)
		UI.label(track, "meta", done and "Done" or ("%d / %d"):format(q.n, q.goal), { Size = UDim2.fromScale(1, 1), ZIndex = track.ZIndex + 2 })
	end
end

function Rewards.openDaily()
	close()
	local d = State.data
	if not d then
		return
	end
	local f, body = UI.window(gui, "Daily Rewards", T.pink, Vector2.new(720, 556), close, "Gift")
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
	local cw, ch, gap = 140, 124, 10
	for day = 1, 6 do
		local col, row = (day - 1) % 3, (day - 1) // 3
		tile(body, day, state(day), UDim2.fromOffset(cw, ch), UDim2.fromOffset(col * (cw + gap), row * (ch + gap)))
	end
	tile(body, 7, state(7), UDim2.new(1, -3 * (cw + gap), 0, ch * 2 + gap), UDim2.fromOffset(3 * (cw + gap), 0))
	questsRow(body, ch * 2 + gap * 2, d)
	-- claim button / time to the next one
	local footer = { Size = UDim2.fromOffset(380, 58), Position = UDim2.new(0.5, 0, 1, 0), AnchorPoint = Vector2.new(0.5, 1) }
	if ready then
		UI.button(body, ("CLAIM DAY %d"):format(math.min(nextDay, #Config.Daily)), T.green, function()
			State.action("claimDaily")
		end, footer)
	else
		local p = Shop.plate(body, "", T.gold, footer)
		local t = p:FindFirstChild("Label") :: TextLabel
		task.spawn(function()
			while t.Parent do
				t.Text = "Next reward in " .. UI.timeWords(math.max(0, dailyReadyAt - os.clock()))
				task.wait(1)
			end
		end)
	end
	if revealDay > 0 and os.clock() - revealAt < 0.6 then
		reveal(revealDay)
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

local paintChest: (Instance, number) -> ()

local function chestSign()
	local left = groupReadyAt - os.clock()
	for _, map in Layout.worldFolders() do -- (one chest in each world)
		local chest = map:FindFirstChild("GroupChest")
		local anchor = chest and chest:FindFirstChild("Sign")
		if anchor then
			paintChest(anchor, left)
		end
	end
end

function paintChest(anchor: Instance, left: number)
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
	UI.autoScale(gui, Vector2.new(740, 566))

	local function onState(d: any)
		local wasReady = os.clock() >= dailyReadyAt
		dailyReadyAt = os.clock() + (d.dailyWait or 0)
		groupReadyAt = os.clock() + (d.groupWait or 0)
		if window and wasReady ~= (os.clock() >= dailyReadyAt) then
			Rewards.openDaily() -- just claimed: redraw with the day ticked off
		end
		-- a reward waiting: open the calendar once per session (after the
		-- tutorial; for a brand-new player, after their first trip home on
		-- their own, not the second the guide ends)
		if waitForTrip == nil then
			waitForTrip = d.tut < 5
		end
		if not autoOpened and not waitForTrip and d.tut >= 5 and (d.dailyWait or 1) <= 0 and not player:GetAttribute("Cinematic") then
			autoOpened = true
			task.delay(2, Rewards.openDaily)
		end
	end
	State.Changed:Connect(onState)
	if State.data then
		onState(State.data)
	end

	require(script.Parent.Prompts).Triggered:Connect(function(prompt)
		if prompt.Name ~= "GroupChest" then
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
				revealDay, revealAt = data.day, os.clock()
				reveal(data.day)
				Notify.takeover(("Day %d"):format(data.day), data.text, C.gold, 1.6)
				Fx.sound("buy", 0.8)
				Fx.confetti((player.Character and player.Character:GetPivot().Position) or Vector3.zero)
			else
				Notify.toast("Next daily reward in " .. UI.timeWords(data.wait or 0), C.gold)
			end
		elseif kind == "inviteReward" then
			local title, sub
			if data.kind == "invited" then
				title, sub = "A gift from your friend", data.friend and ("%s invited you: a Rare is in your tank!"):format(tostring(data.friend))
					or "You were invited: a Rare is in your tank!"
			elseif (data.n or 1) > 1 then
				title, sub = "Your friends joined!", ("+%d Rares in your tank"):format(data.n)
			else
				title, sub = ("%s joined!"):format(tostring(data.friend or "Your friend")), "Thanks for the invite: +1 Rare in your tank"
			end
			Notify.banner(title, { key = "invite", priority = 3, time = 4, color = C.gold, sub = sub })
			Fx.sound("legendary", 0.7)
			Fx.confetti((player.Character and player.Character:GetPivot().Position) or Vector3.zero)
		elseif kind == "haul" then
			local d = State.data
			if waitForTrip and d and d.tut >= 5 then
				waitForTrip = false
				task.delay(2, function()
					if State.data then
						onState(State.data)
					end
				end)
			end
		elseif kind == "quest" then
			local sub = ("+$%s"):format(UI.short(data.coins or 0))
			if data.bonus then
				sub ..= (" · all 3 done: Luck Potion %d min"):format(data.bonus)
			end
			Notify.banner(("Quest done: %s"):format(tostring(data.text)), { color = C.gold, priority = 2, time = 3.5, sub = sub })
			Fx.sound("coin", 0.8)
		elseif kind == "groupChest" then
			if data.ok then
				while os.clock() < likeOpenUntil do
					task.wait(0.2)
				end
				task.wait(0.3)
				Notify.takeover("Chest claimed", ("+$%s · 2x speed for %d min"):format(UI.short(data.coins), data.minutes), C.gold, 1.6)
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
