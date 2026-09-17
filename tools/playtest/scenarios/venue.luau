--!nocheck
-- Перенос на поляну Пузырей напрямую: стоит ли персонаж на полу.
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Services = ServerScriptService.Server.Services

return function(player, note)
	local ProfileService = require(Services.ProfileService)
	local Teleport = require(ServerScriptService.Server.World.Teleport)
	local Venues = require(ReplicatedStorage.Shared.Config.Venues)
	for _ = 1, 60 do
		if ProfileService.get(player) then
			break
		end
		task.wait(0.5)
	end
	task.wait(3)
	local entry = Venues.entry("bubbles")
	note("server floor below entry: " .. tostring(workspace:Raycast(entry.Position, Vector3.new(0, -20, 0)) and workspace:Raycast(entry.Position, Vector3.new(0, -20, 0)).Instance:GetFullName()))
	note(">> teleport to bubbles " .. tostring(entry.Position))
	Teleport.to(player, entry)
	for i = 1, 24 do
		task.wait(0.5)
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		note(string.format("   t%.1f server pos %s anchored %s", i * 0.5, root and tostring(root.Position) or "-", root and tostring(root.Anchored) or "-"))
	end
end
