--!nocheck
--[[
	Картинки: подойти к мольберту, снимок загадки, встать на чужую букву
	(счёт не растёт), потом на верную (растёт, картинка меняется).
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

return function(player, note)
	local Playground = require(ReplicatedStorage.Shared.Config.Playground)
	local Teleport = require(ServerScriptService.Server.World.Teleport)
	task.wait(22) -- зонд клиента слушает метки не сразу
	local spot = Playground.expect("pictures")
	local center = Playground.position(spot)
	local toPlaza = (-center * Vector3.new(1, 0, 1)).Unit
	local stand = center + toPlaza * 10
	Teleport.to(player, CFrame.lookAt(stand + Vector3.new(0, 4, 0), center + Vector3.new(0, 4, 0)))
	task.wait(4)
	_G.ZZ_Shot(
		player,
		"pictures_riddle",
		CFrame.lookAt(center + toPlaza * 18 + Vector3.new(0, 9, 0), center + Vector3.new(0, 3, 0)),
		60
	)
	task.wait(5)
	for _, want in { "wrong", "right", "right", "right" } do
		workspace:SetAttribute("ZZ_Pictures", nil)
		task.wait(0.2)
		workspace:SetAttribute("ZZ_Pictures", want)
		task.wait(5)
	end
	_G.ZZ_Shot(
		player,
		"pictures_after",
		CFrame.lookAt(center + toPlaza * 18 + Vector3.new(0, 9, 0), center + Vector3.new(0, 3, 0)),
		60
	)
	task.wait(5)
end
