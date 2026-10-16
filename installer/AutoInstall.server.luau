--!strict
-- Tux Physics Tails | Safe, one-time model installer
-- Embedded inside the public RBXM. This is not part of the Rojo source tree.
-- Import the model into Workspace to run the installer on the server.

local RunService = game:GetService("RunService")
if not RunService:IsServer() then
	return
end

local package = script.Parent
if package == nil or not package:IsA("Model") then
	return
end

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local scriptsDestination = StarterPlayer:FindFirstChildOfClass("StarterPlayerScripts")

local sharedFolder = package:FindFirstChild("ReplicatedStorage") :: Folder
local clientFolder = package:FindFirstChild("StarterPlayerScripts") :: Folder
local engine = if sharedFolder then sharedFolder:FindFirstChild("TuxPhysicsTails") else nil
local client = if clientFolder then clientFolder:FindFirstChild("TuxPhysicsTailsClient") else nil

if scriptsDestination == nil
	or engine == nil or not engine:IsA("ModuleScript")
	or client == nil or not client:IsA("LocalScript") then
	warn("[TuxPhysicsTails] The installation model is incomplete; no changes were made. See README.md.")
	return
end

-- Never replace a developer's existing installation or other scripts.
if ReplicatedStorage:FindFirstChild("TuxPhysicsTails") ~= nil
	or scriptsDestination:FindFirstChild("TuxPhysicsTailsClient") ~= nil then
	warn("[TuxPhysicsTails] Installation skipped: a matching script already exists. Unpack/update manually.")
	return
end

engine.Parent = ReplicatedStorage
client.Parent = scriptsDestination
print("[TuxPhysicsTails] Installed to ReplicatedStorage and StarterPlayerScripts.")
package:Destroy()
