--!strict
-- Client entry point. The only client script: starts every Controller.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

if not game:IsLoaded() then
	game.Loaded:Wait()
end

local Loader = require(ReplicatedStorage.Shared.Loader)

Loader.Run(script.Parent:WaitForChild("Controllers"), "Client")

