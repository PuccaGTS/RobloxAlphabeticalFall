--!nocheck
--[[
	Вечер в парке (Config/Evening): площадь в золотой час, на закате, в сумерках
	и утром; дом с горящими окнами; светлячки у клумбы. Время круга задаёт метка
	EveningAt — клиент берёт её вместо серверных часов.
]]
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")
local Services = ServerScriptService.Server.Services

return function(player, note)
	local BaseService = require(Services.BaseService)
	local ProfileService = require(Services.ProfileService)
	local Teleport = require(ServerScriptService.Server.World.Teleport)
	local Decor = require(ReplicatedStorage.Shared.Config.Decor)
	for _ = 1, 60 do
		if ProfileService.get(player) then
			break
		end
		task.wait(0.5)
	end
	task.wait(3)
	-- Свой дом, чтобы было чему светиться окнами.
	ProfileService.update(player, function(p)
		p.base.house, p.base.roof, p.base.yard, p.base.fence = 3, 3, 2, 3
	end)
	BaseService.refresh(player)

	local plaza = CFrame.lookAt(Vector3.new(0, 14, 70), Vector3.new(0, 18, -60))
	local lawn = CFrame.lookAt(Vector3.new(60, 22, 150), Vector3.new(-40, 10, 0))
	Teleport.to(player, CFrame.new(0, 5, 60))
	task.wait(3)
	for _, spec in
		{ { 300, "day" }, { 512, "golden" }, { 548, "sunset" }, { 640, "evening" }, { 704, "dawn" } }
	do
		workspace:SetAttribute("EveningAt", spec[1])
		task.wait(1.5)
		_G.ZZ_Shot(player, `eve_{spec[2]}_plaza`, plaza, 70)
		if spec[2] == "sunset" or spec[2] == "evening" then
			_G.ZZ_Shot(player, `eve_{spec[2]}_lawn`, lawn, 70)
		end
	end

	-- Сумерки у дома: окна горят, у фонарей свет.
	workspace:SetAttribute("EveningAt", 640)
	BaseService.sendHome(player)
	task.wait(4)
	local home = BaseService.plotCFrame(BaseService.plotOf(player).index)
	_G.ZZ_Shot(
		player,
		"eve_evening_house",
		CFrame.lookAt((home * CFrame.new(10, 10, -48)).Position, (home * CFrame.new(0, 6, 0)).Position),
		60
	)
	-- Светлячки у первой клумбы.
	for _, placement in Decor.placements do
		if placement.id == "flower_bed" then
			local at = Vector3.new(placement.x, Decor.groundY(placement.x, placement.z), placement.z)
			Teleport.to(player, CFrame.new(at + Vector3.new(14, 4, 14)))
			task.wait(6)
			_G.ZZ_Shot(
				player,
				"eve_fireflies",
				CFrame.lookAt(at + Vector3.new(9, 5, 9), at + Vector3.new(0, 3, 0)),
				60
			)
			break
		end
	end
	note(`server Lighting ClockTime {Lighting.ClockTime}`)
	workspace:SetAttribute("EveningAt", nil)
end
