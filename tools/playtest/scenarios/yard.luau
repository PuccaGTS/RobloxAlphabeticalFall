--!nocheck
--[[
	Весь двор разом: все категории дома на уровне ZZ_ONLY (по умолчанию 4),
	снимки спереди, сзади и крупно по наборам — огород, площадка, живность,
	транспорт, мебель и декор.
]]
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Services = ServerScriptService.Server.Services

return function(player, note)
	local BaseService = require(Services.BaseService)
	local ProfileService = require(Services.ProfileService)
	local Base = require(ReplicatedStorage.Shared.Config.Base)
	for _ = 1, 60 do
		if ProfileService.get(player) then
			break
		end
		task.wait(0.5)
	end
	task.wait(3)
	local level = tonumber(workspace:GetAttribute("ZZ_Only")) or 4
	ProfileService.update(player, function(p)
		for _, id in Base.ids() do
			p.base[id] = level
		end
	end)
	BaseService.refresh(player)
	ProfileService.pushSnapshot(player)
	BaseService.sendHome(player)
	task.wait(5)
	local home = BaseService.plotCFrame(BaseService.plotOf(player).index)
	local function shot(name, eye, look)
		_G.ZZ_Shot(player, name, CFrame.lookAt((home * eye).Position, (home * look).Position), 60)
		task.wait(5)
	end
	shot("yard_front", CFrame.new(18, 22, -58), CFrame.new(0, 4, 0))
	shot("yard_back", CFrame.new(-10, 26, 62), CFrame.new(0, 2, 10))
	for _, id in { "garden", "playground", "pets", "transport" } do
		local spots = Base.expect(id).spots
		if spots then
			local sum = Vector3.zero
			for _, spot in spots do
				sum += Vector3.new(spot.x, 0, spot.z)
			end
			local center = sum / #spots
			local side = if center.X > 0 then 1 else -1
			shot(
				`yard_{id}`,
				CFrame.new(center.X - side * 16, 12, center.Z - 14),
				CFrame.new(center.X, 1.5, center.Z)
			)
		end
	end
	shot("yard_terrace", CFrame.new(10, 8, -30), CFrame.new(0, 2, -12))
	note("yard done")
end
