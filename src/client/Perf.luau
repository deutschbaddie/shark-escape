-- "Fewer details" (Settings): on by default on phones. The stud texture
-- on every face of every brick (Build.studs) is the biggest draw-call cost
-- on cheap phones, so this keeps the studs on top faces (like real bricks)
-- and puts the side ones away. Switching it off puts them back.

local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Perf = {}

local on = false
local stashed: { [Texture]: Instance } = {} -- side stud textures we took off, and their part

local function side(d: Instance): boolean
	return d:IsA("Texture") and d.Name == "Studs" and d.Face ~= Enum.NormalId.Top
end

local function stash(d: Instance)
	if on and side(d) and d.Parent then
		local parent = d.Parent :: Instance
		task.defer(function() -- (not while it's still being parented)
			if d.Parent == parent then
				stashed[d :: Texture] = parent
				d.Parent = nil
			end
		end)
	end
end

function Perf.enabled(): boolean
	return on
end

function Perf.set(enabled: boolean)
	if enabled == on then
		return
	end
	on = enabled
	if on then
		for _, d in Workspace:GetDescendants() do
			stash(d)
		end
	else
		for t, parent in stashed do
			if parent.Parent then
				t.Parent = parent
			end
		end
		table.clear(stashed)
	end
end

function Perf.start()
	Workspace.DescendantAdded:Connect(stash)
	-- phones start with it on
	local phone = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	Perf.set(phone)
end

return Perf
