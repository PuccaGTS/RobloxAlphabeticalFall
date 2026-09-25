--!nocheck
--[[
	Азбучная грядка у калитки: пустые лунки с росточками-подсказками, посадка
	шагом на лунку, все три стадии (время подкручено в профиле) и урожай.
]]
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Services = ServerScriptService.Server.Services

return function(player, note)
	local ProfileService = require(Services.ProfileService)
	local BaseService = require(Services.BaseService)
	local GardenService = require(Services.GardenService)
	local Teleport = require(ServerScriptService.Server.World.Teleport)
	local LetterGarden = require(ReplicatedStorage.Shared.Logic.LetterGarden)
	for _ = 1, 60 do
		if ProfileService.get(player) and player.Character and BaseService.plotOf(player) then
			break
		end
		task.wait(0.5)
	end
	task.wait(20)

	local at = GardenService.position(player)
	local home = BaseService.homeCFrame(player)
	if not at or not home then
		note("NO GARDEN")
		return
	end
	local plot = BaseService.plotOf(player).cframe
	Teleport.to(player, home)
	task.wait(3)
	local view = CFrame.lookAt((plot * CFrame.new(4, 7, -46)).Position, at + Vector3.new(0, 1, 0))
	_G.ZZ_Shot(player, "garden_empty", view, 55)
	task.wait(4.5)

	local function stepOn(index)
		local slot = plot * CFrame.new(11.5, 1, -36.5) * CFrame.new((index - 2) * 2.8, 0, 0)
		player.Character.HumanoidRootPart.CFrame = CFrame.new(slot.Position + Vector3.new(0, 4, 0))
		task.wait(1)
		player.Character.HumanoidRootPart.CFrame = home
		task.wait(0.8)
	end
	for index = 1, 3 do
		stepOn(index)
	end
	local garden = ProfileService.get(player).garden
	note(`planted: {garden.beds[1].letterId},{garden.beds[2].letterId},{garden.beds[3].letterId}`)

	-- Подкрутить время: вторая лунка — росток, третья — цветок.
	ProfileService.update(player, function(p)
		p.garden.beds[2].plantedAt -= LetterGarden.SPROUT + 5
		p.garden.beds[3].plantedAt -= LetterGarden.BLOOM + 5
	end)
	GardenService.render(player, true)
	task.wait(1.5)
	_G.ZZ_Shot(player, "garden_grown", view, 55)
	task.wait(4.5)
	_G.ZZ_Shot(
		player,
		"garden_close",
		CFrame.lookAt((plot * CFrame.new(11.5, 5, -43)).Position, at + Vector3.new(0, 1.5, 0)),
		50
	)
	task.wait(4.5)

	local starsBefore = ProfileService.get(player).stars
	stepOn(3)
	stepOn(2)
	garden = ProfileService.get(player).garden
	note(
		`after harvest: harvested={garden.harvested} bed3={garden.beds[3].letterId} stars +{ProfileService.get(
			player
		).stars - starsBefore}`
	)
	task.wait(0.5)
	_G.ZZ_Shot(player, "ui_garden_harvest", view, 55)
	task.wait(5)
end
