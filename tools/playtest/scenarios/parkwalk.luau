--!nocheck
--[[
	Прогулка новичка по парку после обучения: стрелка к паркур-горе, дошёл —
	к карусели, потом к рыбалке, в конце тост «Ты обошёл парк».
]]
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Services = ServerScriptService.Server.Services

return function(player, note)
	local ProfileService = require(Services.ProfileService)
	local Teleport = require(ServerScriptService.Server.World.Teleport)
	local Playground = require(ReplicatedStorage.Shared.Config.Playground)
	local Tutorial = require(ReplicatedStorage.Shared.Logic.Tutorial)
	for _ = 1, 60 do
		if ProfileService.get(player) and player.Character then
			break
		end
		task.wait(0.5)
	end
	task.wait(10)
	ProfileService.update(player, function(p)
		p.tutorial = { catch = true, shop = true, run = true }
	end)
	task.wait(2)
	_G.ZZ_Shot(player, "ui_walk_arrow", CFrame.lookAt(Vector3.new(0, 12, 44), Vector3.new(-40, 4, -40)), 70)
	task.wait(4.5)

	for _, spotId in { "obby", "carousel", "pond" } do
		local at = Playground.position(Playground.expect(spotId))
		local toPlaza = -Vector3.new(at.X, 0, at.Z).Unit
		Teleport.to(
			player,
			CFrame.new(at + toPlaza * (Playground.expect(spotId).radius + 2) + Vector3.new(0, 4, 0))
		)
		task.wait(2.5)
		local state = Tutorial.sanitize(ProfileService.get(player).tutorial)
		local current = Tutorial.current(state)
		note(`at {spotId}: next step {current and current.id or "всё"}`)
	end
	task.wait(0.5)
	_G.ZZ_Shot(player, "ui_walk_done", CFrame.lookAt(Vector3.new(0, 12, 44), Vector3.new(0, 4, 0)), 70)
	task.wait(5)
end
