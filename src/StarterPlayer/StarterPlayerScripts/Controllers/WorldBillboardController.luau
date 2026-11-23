--!strict
-- Covers replicated templates and client-only bowls, loyalty labels, markers and effects.
local Policy = require(game.ReplicatedStorage.Shared.Util.WorldBillboard)
local Controller = { Priority = 18 }
function Controller:Init()
	for _, instance in game:GetDescendants() do
		if instance:IsA("BillboardGui") then Policy.Apply(instance) end
	end
	game.DescendantAdded:Connect(function(instance)
		if instance:IsA("BillboardGui") then Policy.Apply(instance) end
	end)
end
return Controller

