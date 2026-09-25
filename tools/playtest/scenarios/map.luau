--!nocheck
--[[
	Карта «Куда пойти?» и задания дня про парк: доска у точки появления, окно
	с картой (место из задания горит золотом), фото-зона и прокат выполняют
	свои задания по-настоящему — через ParkDone с клиента и круг проката.
]]
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Services = ServerScriptService.Server.Services

return function(player, note)
	local ProfileService = require(Services.ProfileService)
	local QuestService = require(Services.QuestService)
	local Teleport = require(ServerScriptService.Server.World.Teleport)
	local RemoteDefs = require(ReplicatedStorage.Shared.Net.RemoteDefs)
	local Base = require(ReplicatedStorage.Shared.Config.Base)
	for _ = 1, 60 do
		if ProfileService.get(player) and player.Character then
			break
		end
		task.wait(0.5)
	end
	task.wait(20) -- зонд клиента слушает метки не сразу

	note(`today: {table.concat(ProfileService.get(player).quests.list, ", ")}`)
	ProfileService.update(player, function(p)
		p.quests.list = { "letters_level", "park_photo", "park_rental" }
		p.quests.progress = {}
		p.quests.bonus = false
	end)
	QuestService.push(player)
	task.wait(1)

	local board = Base.MAP_BOARD_POSITION
	_G.ZZ_Shot(
		player,
		"map_board",
		CFrame.lookAt(Vector3.new(-8, 8, 30), Vector3.new(board.X, 6, board.Z)),
		60
	)
	task.wait(4.5)
	_G.ZZ_Shot(player, "map_spawn", CFrame.lookAt(Vector3.new(0, 9, 44), Vector3.new(0, 6, -20)), 70)
	task.wait(4.5)

	-- Встать на золотой круг перед доской: карта открывается сама.
	local pad = workspace.Hub.MapBoard.MapPad
	Teleport.to(player, CFrame.new(pad.Position + Vector3.new(0, 3.5, 0)))
	task.wait(3)
	_G.ZZ_Shot(player, "ui_map_open", CFrame.lookAt(Vector3.new(0, 9, 44), Vector3.new(0, 6, -20)), 70)
	task.wait(4.5)

	local starsBefore = ProfileService.get(player).stars
	local zone = workspace.Hub.Playground:FindFirstChild("Play_photo")
	local mark = zone and zone:FindFirstChild("PhotoMark")
	Teleport.to(player, CFrame.new(mark.Position + Vector3.new(0, 3, 0)))
	task.wait(4)
	local quests = ProfileService.get(player).quests
	note(
		`photo: progress={quests.progress.park_photo} stars +{ProfileService.get(player).stars - starsBefore}`
	)

	local stall = workspace.Hub.Playground:FindFirstChild("Play_rental")
	local rentalPad
	for _, child in stall:GetChildren() do
		if string.sub(child.Name, 1, 10) == "RentalPad_" then
			rentalPad = child
			break
		end
	end
	Teleport.to(player, CFrame.new(rentalPad.Position + Vector3.new(6, 4, 0)))
	task.wait(2)
	player.Character.HumanoidRootPart.CFrame = CFrame.new(rentalPad.Position + Vector3.new(0, 3.2, 0))
	task.wait(2)
	quests = ProfileService.get(player).quests
	note(
		`rental: riding={player:GetAttribute("Riding")} progress={quests.progress.park_rental} bonus={quests.bonus}`
	)
	-- Карта заново: фото и прокат сделаны — золотых мест на ней больше нет.
	RemoteDefs.event("OpenUI"):FireClient(player, "map")
	task.wait(1)
	_G.ZZ_Shot(player, "ui_map_quests", CFrame.lookAt(Vector3.new(0, 9, 44), Vector3.new(0, 6, -20)), 70)
	task.wait(5)
end
