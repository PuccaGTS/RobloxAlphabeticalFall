--!nocheck
--[[
	Тир: вид на стенд с шариками, встать к прилавку (буква вверху экрана),
	«тап» по чужому шарику (мяч отскакивает) и трижды по нужному (лопается,
	задание дня про тир).
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
	task.wait(20)

	ProfileService.update(player, function(p)
		p.quests.list = { "letters_level", "park_gallery", "buy" }
		p.quests.progress = {}
	end)
	QuestService.push(player)

	local zone = workspace.Hub.Playground:FindFirstChild("Play_gallery")
	local mark = zone and zone:FindFirstChild("GalleryMark")
	if not mark then
		note("NO GALLERY")
		return
	end
	local spot = Playground.position(Playground.expect("gallery"))
	local center = Vector3.new(spot.X, 1, spot.Z)
	local toPlaza = -center.Unit
	Teleport.to(player, CFrame.new(center + toPlaza * 20 + Vector3.new(0, 4, 0)))
	task.wait(3)
	_G.ZZ_Shot(
		player,
		"gallery_stand",
		CFrame.lookAt(center + toPlaza * 22 + Vector3.new(5, 7, 0), center + Vector3.new(0, 4, 0)),
		60
	)
	task.wait(4.5)

	Teleport.to(
		player,
		CFrame.lookAt(mark.Position + Vector3.new(0, 3.2, 0), center + Vector3.new(0, 3.2, 0))
	)
	task.wait(3)
	_G.ZZ_Shot(
		player,
		"ui_gallery_on",
		CFrame.lookAt(mark.Position + toPlaza * 7 + Vector3.new(0, 5, 0), center + Vector3.new(0, 5, 0)),
		60
	)
	task.wait(4.5)

	workspace:SetAttribute("ZZ_Gallery", "wrong")
	task.wait(3)
	for index = 1, 3 do
		workspace:SetAttribute("ZZ_Gallery", nil)
		task.wait(0.2)
		workspace:SetAttribute("ZZ_Gallery", "right")
		if index == 1 then
			task.wait(0.1)
			_G.ZZ_Shot(
				player,
				"gallery_throw",
				CFrame.lookAt(
					mark.Position + toPlaza * 3 + Vector3.new(7, 5, 0),
					center + Vector3.new(0, 5, 0)
				),
				60
			)
		end
		task.wait(3.5)
	end
	note(`gallery quest progress={ProfileService.get(player).quests.progress.park_gallery}`)
end
