--!nocheck
-- Картинки к буквам: карточка знакомства (с интерфейсом) и Башня во дворе.
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Services = ServerScriptService.Server.Services

return function(player, note)
	local ProfileService = require(Services.ProfileService)
	local BaseService = require(Services.BaseService)
	local RemoteDefs = require(ReplicatedStorage.Shared.Net.RemoteDefs)
	for _ = 1, 60 do
		if ProfileService.get(player) then
			break
		end
		task.wait(0.5)
	end
	task.wait(4)
	for _, id in { "a", "yu", "shch" } do
		-- Снимок ждёт 4 секунды после камеры, карточка живёт 4: зовём её посреди ожидания.
		task.delay(2.8, function()
			RemoteDefs.event("PetGranted"):FireClient(player, id, {})
		end)
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		local at = root and root.Position or Vector3.new(0, 5, 40)
		_G.ZZ_Shot(player, `ui_intro_{id}`, CFrame.lookAt(at + Vector3.new(0, 6, 14), at), 70)
		task.wait(5)
	end

	-- Башня: участок выдан при входе, камера сбоку от неё.
	local plot = BaseService.plotOf(player)
	note("plot " .. tostring(plot and plot.index))
	if plot then
		local tower = (plot.cframe * CFrame.new(-13, 4, 13)).Position
		local middle = plot.cframe.Position
		BaseService.sendHome(player)
		task.wait(4)
		local away = (middle - tower) * Vector3.new(1, 0, 1)
		local eye = tower + away.Unit * 20 + Vector3.new(0, 14, 0)
		_G.ZZ_Shot(player, "tower_front", CFrame.lookAt(eye, tower + Vector3.new(0, 14, 0)), 70)
		_G.ZZ_Shot(
			player,
			"tower_close",
			CFrame.lookAt(tower + away.Unit * 9 + Vector3.new(0, 5, 0), tower + Vector3.new(0, 5, 0)),
			70
		)
	end
	_G.ZZ_Shot(player, "portals_far", CFrame.lookAt(Vector3.new(0, 40, 125), Vector3.new(0, 20, -6)), 70)
end
