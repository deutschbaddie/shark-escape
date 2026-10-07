-- State      server -> client  full player state (on change)
-- Notify     server -> client  one-off juicy moments (grab, lucky, collect, buy...)
-- Action     client -> server  requests (buy ride, equip, buy slot, rebirth, tutorial)
-- Sharks     server -> all     shark snapshots (10 Hz while sharks are out)
-- SharkEvent server -> all     attack phases and bites

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NAMES = { "State", "Notify", "Action", "Sharks", "SharkEvent" }

local Remotes = {}

local folder: Folder
if RunService:IsServer() then
	folder = ReplicatedStorage:FindFirstChild("Remotes") :: Folder
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Remotes"
		for _, n in NAMES do
			local r = Instance.new("RemoteEvent")
			r.Name = n
			r.Parent = folder
		end
		folder.Parent = ReplicatedStorage
	end
else
	folder = ReplicatedStorage:WaitForChild("Remotes") :: Folder
end

function Remotes.get(name: string): RemoteEvent
	return folder:WaitForChild(name) :: RemoteEvent
end

return Remotes
