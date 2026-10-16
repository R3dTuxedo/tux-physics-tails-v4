--!strict
-- Tux Physics Tails | Client bootstrap
-- Put this LocalScript inside StarterPlayer > StarterPlayerScripts.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Tails = require(ReplicatedStorage:WaitForChild("TuxPhysicsTails"))

Tails.Start()
