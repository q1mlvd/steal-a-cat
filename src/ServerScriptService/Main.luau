--!strict
-- Server entry point. The only server Script: builds remotes, then starts every Service.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Network = require(ReplicatedStorage.Shared.Network)
local Loader = require(ReplicatedStorage.Shared.Loader)

Network.Setup()
Loader.Run(ServerScriptService.Services, "Server")

