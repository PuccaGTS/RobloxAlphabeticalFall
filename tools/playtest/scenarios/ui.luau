--!nocheck
--[[
	Окна глазами ребёнка: панель заданий дня, тост за выполненное, экран итогов
	занятия с крестиком, магазин поверх HUD. Снимки ui_*.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Services = ServerScriptService.Server.Services

return function(player, note)
	local ProfileService = require(Services.ProfileService)
	local QuestService = require(Services.QuestService)
	local Quests = require(ReplicatedStorage.Shared.Logic.Quests)
	local RemoteDefs = require(ReplicatedStorage.Shared.Net.RemoteDefs)
	for _ = 1, 60 do
		if ProfileService.get(player) and player.Character then
			break
		end
		task.wait(0.5)
	end
	task.wait(8)
	local view = CFrame.lookAt(Vector3.new(0, 9, 44), Vector3.new(0, 6, -20))

	local profile = ProfileService.get(player)
	note(`quests today: {table.concat(profile.quests.list, ", ")}`)
	_G.ZZ_Shot(player, "ui_hub", view, 70)
	task.wait(4.5)

	-- Второе задание (не уровень) выполнить по-настоящему: через событие игры.
	local second = Quests.get(profile.quests.list[2])
	local challengeId = second and string.match(second.event, "^challenge:(.+)$")
	if challengeId then
		QuestService.record(player, "finished", challengeId)
	elseif second then
		QuestService.record(player, second.event)
	end
	note(
		`after record: stars {ProfileService.get(player).stars} progress {second and ProfileService.get(
			player
		).quests.progress[second.id]}`
	)
	task.wait(0.3)
	_G.ZZ_Shot(player, "ui_quest_done", view, 70)
	task.wait(4.5)

	RemoteDefs.event("ChallengeEnd"):FireClient(player, {
		challengeId = "letter_rain",
		stars = 3,
		caught = 5,
		targetCount = 5,
		stars_awarded = 57,
		reason = "completed",
	})
	task.wait(0.2)
	_G.ZZ_Shot(player, "ui_result", view, 70)
	task.wait(5)

	RemoteDefs.event("OpenUI"):FireClient(player, "shop")
	task.wait(0.3)
	_G.ZZ_Shot(player, "ui_shop", view, 70)
	task.wait(5)
end
