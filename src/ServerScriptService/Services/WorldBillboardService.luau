--!strict
local Policy = require(game.ReplicatedStorage.Shared.Util.WorldBillboard)
local Service = { Priority = 19 }
function Service:Init()
	for _, instance in game:GetDescendants() do
		if instance:IsA("BillboardGui") then Policy.Apply(instance) end
	end
	game.DescendantAdded:Connect(function(instance)
		if instance:IsA("BillboardGui") then Policy.Apply(instance) end
	end)
end
return Service

