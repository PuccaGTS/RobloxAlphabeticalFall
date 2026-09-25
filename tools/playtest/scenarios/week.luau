--!nocheck
--[[
	Задание недели: строка с полоской в панели заданий, выполнение по-настоящему
	(событие уровня через QuestService), вещь-награда сразу на ребёнке,
	тост «🏆 Задание недели!» и карточки наград в витрине.
]]
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Services = ServerScriptService.Server.Services

return function(player, note)
	local ProfileService = require(Services.ProfileService)
	local QuestService = require(Services.QuestService)
	local RemoteDefs = require(ReplicatedStorage.Shared.Net.RemoteDefs)
	for _ = 1, 60 do
		if ProfileService.get(player) and player.Character then
			break
		end
		task.wait(0.5)
	end
	task.wait(10)

	local week = ProfileService.get(player).quests.week
	note(`week: {week and week.id} {week and week.have}`)
	ProfileService.update(player, function(p)
		p.quests.week = { week = p.quests.week.week, id = "week_levels", have = 3, seen = {}, done = false }
	end)
	QuestService.push(player)
	task.wait(1)
	local view = CFrame.lookAt(Vector3.new(0, 7, 38), Vector3.new(0, 5, 26))
	_G.ZZ_Shot(player, "ui_week_panel", view, 60)
	task.wait(4.5)

	local starsBefore = ProfileService.get(player).stars
	QuestService.record(player, "level:math")
	QuestService.record(player, "level:letters")
	task.wait(1)
	local profile = ProfileService.get(player)
	note(
		`after: done={profile.quests.week.done} hat={profile.equipped.hat} stars +{profile.stars - starsBefore} owns={table.find(
			profile.inventory,
			"hat_dino"
		) ~= nil}`
	)
	_G.ZZ_Shot(player, "ui_week_done", view, 60)
	task.wait(6)
	_G.ZZ_Shot(player, "week_dino", CFrame.lookAt(Vector3.new(0, 7, 33), Vector3.new(0, 6, 26)), 50)
	task.wait(4.5)

	RemoteDefs.event("OpenUI"):FireClient(player, "shop")
	task.wait(1)
	_G.ZZ_Shot(player, "ui_week_shop", view, 60)
	task.wait(5)
end
