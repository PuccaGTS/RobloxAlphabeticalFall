--!nocheck
--[[
	Рыбалка у пруда: общий вид с камышами и мостками, рыбки с буквами, встать
	на круг рыбака — удочка в руке и буква вверху экрана; «тап» по чужой рыбке
	(удирает) и три раза по нужной (летит в ведро, задание дня про пруд).
]]
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Services = ServerScriptService.Server.Services

return function(player, note)
	local ProfileService = require(Services.ProfileService)
	local QuestService = require(Services.QuestService)
	local Teleport = require(ServerScriptService.Server.World.Teleport)
	local Playground = require(ReplicatedStorage.Shared.Config.Playground)
	for _ = 1, 60 do
		if ProfileService.get(player) and player.Character then
			break
		end
		task.wait(0.5)
	end
	task.wait(20) -- зонд клиента слушает метки не сразу

	ProfileService.update(player, function(p)
		p.quests.list = { "letters_level", "park_pond", "buy" }
		p.quests.progress = {}
	end)
	QuestService.push(player)

	local zone = workspace.Hub.Playground:FindFirstChild("Play_pond")
	local mark = zone and zone:FindFirstChild("FishingMark")
	if not mark then
		note("NO POND")
		return
	end
	local spot = Playground.position(Playground.expect("pond"))
	local center = Vector3.new(spot.X, 1, spot.Z)
	local toPlaza = -center.Unit
	Teleport.to(player, CFrame.new(center + toPlaza * 26 + Vector3.new(0, 4, 0)))
	task.wait(3)
	_G.ZZ_Shot(
		player,
		"fishing_pond",
		CFrame.lookAt(center + toPlaza * 24 + Vector3.new(8, 12, 0), center + Vector3.new(0, 1, 0)),
		60
	)
	task.wait(4.5)

	-- На круг рыбака лицом к пруду.
	Teleport.to(
		player,
		CFrame.lookAt(mark.Position + Vector3.new(0, 3.2, 0), center + Vector3.new(0, 3.2, 0))
	)
	task.wait(3)
	_G.ZZ_Shot(
		player,
		"ui_fishing_on",
		CFrame.lookAt(mark.Position - toPlaza * -7 + Vector3.new(0, 7, 0), center + Vector3.new(0, 0, 0)),
		60
	)
	task.wait(4.5)

	workspace:SetAttribute("ZZ_Fish", "wrong")
	task.wait(3.5)
	for index = 1, 3 do
		workspace:SetAttribute("ZZ_Fish", nil)
		task.wait(0.2)
		workspace:SetAttribute("ZZ_Fish", "right")
		if index == 1 then
			task.wait(0.3)
			_G.ZZ_Shot(
				player,
				"fishing_catch",
				CFrame.lookAt(mark.Position + toPlaza * 6 + Vector3.new(6, 6, 0), center),
				60
			)
		end
		task.wait(4)
	end
	local quests = ProfileService.get(player).quests
	note(`pond quest progress={quests.progress.park_pond}`)
end
