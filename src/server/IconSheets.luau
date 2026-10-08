-- Resolves the icon sheet ids in Config.Icons. Asset Manager / Toolbox
-- uploads often give a *decal* id; ImageLabels need the *image* id inside
-- it. Load the decal (works for your own uploads) and publish the real
-- image id as a ReplicatedStorage attribute for clients (UI.icon).

local InsertService = game:GetService("InsertService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local IconSheets = {}

local function resolve(raw: any): string?
	local digits = tostring(raw or ""):match("%d+")
	if not digits then
		return nil
	end
	local ok, model = pcall(InsertService.LoadAsset, InsertService, tonumber(digits))
	if ok and model then
		local decal = model:FindFirstChildWhichIsA("Decal", true)
		local tex = decal and decal.Texture
		model:Destroy()
		if tex and tex ~= "" then
			return tex
		end
	end
	return "rbxassetid://" .. digits -- already an image id
end

function IconSheets.start()
	-- single icons: same decal -> image fix, published as "Icon_<Name>"
	for name, raw in Config.Icons.ids do
		if tostring(raw):match("%d+") then
			task.spawn(function()
				local id = resolve(raw)
				if id then
					ReplicatedStorage:SetAttribute("Icon_" .. name, id)
				end
			end)
		end
	end
	for _, which in { "A", "B" } do
		task.spawn(function()
			local id = resolve(Config.Icons["Sheet" .. which])
			if id then
				ReplicatedStorage:SetAttribute("IconSheet" .. which, id)
			end
		end)
	end
end

return IconSheets
