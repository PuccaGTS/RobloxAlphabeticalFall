--!nocheck
-- Азбучная Башня во дворе с разным освоением букв: вид издалека и вблизи.
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Services = ServerScriptService.Server.Services

return function(player, note)
	local ProfileService = require(Services.ProfileService)
	local BaseService = require(Services.BaseService)
	local MasteryRules = require(ReplicatedStorage.Shared.Logic.MasteryRules)
	local Letters = require(ReplicatedStorage.Shared.Config.Letters)
	for _ = 1, 60 do
		if ProfileService.get(player) then
			break
		end
		task.wait(0.5)
	end
	task.wait(3)
	local all = workspace:GetAttribute("ZZ_Only") == "all"
	ProfileService.update(player, function(p)
		p.base.house, p.base.roof, p.base.yard, p.base.fence = 3, 2, 2, 2
		for order, id in Letters.ordered() do
			local mastery = if all then 3 elseif order <= 6 then 3 elseif order <= 10 then 2 elseif order <= 13 then 1 else 0
			if mastery > 0 then
				local progress = MasteryRules.newProgress(os.time())
				progress.mastery = mastery
				progress.nextReview = os.time() + 86400
				p.letters[id] = progress
			end
		end
	end)
	BaseService.refresh(player)
	ProfileService.pushSnapshot(player)
	BaseService.sendHome(player)
	task.wait(5)
	local plot = BaseService.plotCFrame(BaseService.plotOf(player).index)
	local tower = (plot * CFrame.new(-16.5, 4, 14.5)).Position
	-- Башня за домом, у заднего угла: снимаем снаружи участка, со стороны угла.
	local out = ((tower - plot.Position) * Vector3.new(1, 0, 1)).Unit
	local side = Vector3.new(-out.Z, 0, out.X)
	_G.ZZ_Shot(player, "tower_far", CFrame.lookAt(tower + out * 34 + side * 8 + Vector3.new(0, 14, 0), tower + Vector3.new(0, 17, 0)), 60)
	_G.ZZ_Shot(player, "tower_near", CFrame.lookAt(tower + out * 11 + Vector3.new(0, 6, 0), tower + Vector3.new(0, 7, 0)), 65)
	_G.ZZ_Shot(player, "tower_top", CFrame.lookAt(tower + out * 13 - side * 5 + Vector3.new(0, 30, 0), tower + Vector3.new(0, 30, 0)), 65)
end
