-- Latest player state from the server + change signal.

local Shared = game.ReplicatedStorage.Shared
local Remotes = require(Shared.Remotes)

local State = {}

State.data = nil :: any
local changed = Instance.new("BindableEvent")
State.Changed = changed.Event
State.joinedAt = os.clock()

Remotes.get("State").OnClientEvent:Connect(function(data)
	local prev = State.data
	State.data = data
	changed:Fire(data, prev)
end)

function State.wait(): any
	while not State.data do
		State.Changed:Wait()
	end
	return State.data
end

function State.action(kind: string, arg: any?)
	Remotes.get("Action"):FireServer(kind, arg)
end

return State
