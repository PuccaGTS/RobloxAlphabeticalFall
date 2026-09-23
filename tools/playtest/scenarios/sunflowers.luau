--!nocheck
--[[
	Подсолнуховое поле: ребёнок встаёт слева от поля, потом справа — головы
	подсолнухов должны повернуться за ним. Поворот считает клиент: снимки
	и ZZ_Inspect (ориентация головы глазами клиента).
]]
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

return function(player, note)
	local Teleport = require(ServerScriptService.Server.World.Teleport)
	local Playground = require(ReplicatedStorage.Shared.Config.Playground)
	task.wait(10)
	local center = Playground.position(Playground.expect("sunflowers")) + Vector3.new(0, 1, 0)
	local origin = CFrame.lookAt(center, Vector3.new(0, center.Y, 0))
	local head = "Hub.Playground.Play_sunflowers.SunHead_7.Heart"
	for _, side in { -1, 1 } do
		Teleport.to(player, origin * CFrame.new(side * 14, 3, -4))
		task.wait(4)
		workspace:SetAttribute("ZZ_Inspect", head .. ";" .. side)
		_G.ZZ_Shot(
			player,
			`sunflowers_{if side < 0 then "left" else "right"}`,
			CFrame.lookAt((origin * CFrame.new(side * 4, 9, -22)).Position, center + Vector3.new(0, 5, 0)),
			60
		)
		task.wait(1)
	end
end
