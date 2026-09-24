--!nocheck
--[[
	Прокат в парке (Config/Rental): ларёк, посадка с круга на каждую вещь,
	поездка (метка ZZ_Walk — клиент едет сам), снимки на ходу и высадка.
]]
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Services = ServerScriptService.Server.Services

return function(player, note)
	local ProfileService = require(Services.ProfileService)
	local RentalService = require(Services.RentalService)
	local Teleport = require(ServerScriptService.Server.World.Teleport)
	local Playground = require(ReplicatedStorage.Shared.Config.Playground)
	local Rental = require(ReplicatedStorage.Shared.Config.Rental)
	for _ = 1, 60 do
		if ProfileService.get(player) and player.Character then
			break
		end
		task.wait(0.5)
	end
	task.wait(20) -- зонд клиента слушает метки не сразу

	local stall = workspace.Hub.Playground:FindFirstChild("Play_rental")
	local spot = Playground.position(Playground.expect("rental"))
	local center = Vector3.new(spot.X, 0, spot.Z)
	local toPlaza = -center.Unit
	_G.ZZ_Shot(
		player,
		"rental_stall",
		CFrame.lookAt(center + toPlaza * 22 + Vector3.new(4, 9, 0), center + Vector3.new(0, 3, 0)),
		60
	)

	for _, vehicle in Rental.list do
		local pad = stall:FindFirstChild(`RentalPad_{vehicle.id}`)
		Teleport.to(player, CFrame.new(pad.Position + toPlaza * 6 + Vector3.new(0, 4, 0)))
		task.wait(2)
		-- Шагнуть на круг: переносом прямо на него, касание сработает у сервера.
		local root = player.Character.HumanoidRootPart
		root.CFrame = CFrame.lookAt(
			pad.Position + Vector3.new(0, 3.2, 0),
			pad.Position + Vector3.new(0, 3.2, 0) + toPlaza
		)
		task.wait(1.5)
		local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
		note(
			`{vehicle.id}: riding={player:GetAttribute("Riding")} walk={humanoid.WalkSpeed} hip={humanoid.HipHeight} model={player.Character:FindFirstChild(
				`Rental_{vehicle.id}`
			) ~= nil}`
		)
		-- Поехать по дорожке к домам и снять на ходу сбоку: снимок уходит через ~4 с,
		-- камера целится туда, где ребёнок будет к этому времени.
		Teleport.to(player, CFrame.lookAt(Vector3.new(0, 5, 70), Vector3.new(0, 5, 100)))
		task.wait(1.5)
		local from = root.Position
		workspace:SetAttribute("ZZ_Walk", "0,1,6")
		task.wait(0.2)
		local ahead = from + Vector3.new(0, 0, vehicle.speed * 4.1)
		_G.ZZ_Shot(
			player,
			`rental_ride_{vehicle.id}`,
			CFrame.lookAt(
				ahead + Vector3.new(if vehicle.id == "unicorn" then -9 else 10, 2, -3),
				ahead + Vector3.new(0, 0.5, 0)
			),
			55
		)
		task.wait(2.5)
		workspace:SetAttribute("ZZ_Walk", nil)
		if vehicle.id == "bike" then
			-- Вблизи и с кнопкой ✖: снимок ui_ оставляет интерфейс.
			local r = root.Position
			_G.ZZ_Shot(player, "ui_rental_bike", CFrame.lookAt(r + Vector3.new(7, 2, 0), r), 60)
		end
		RentalService.dismount(player)
		task.wait(1)
		note(
			`   after dismount: riding={player:GetAttribute("Riding")} walk={humanoid.WalkSpeed} hip={humanoid.HipHeight}`
		)
	end

	-- Уехал из парка — вещь возвращается сама.
	RentalService.mount(player, "scooter")
	task.wait(1)
	Teleport.to(player, CFrame.new(-2600, 260, 0))
	task.wait(2.5)
	note(`left the park: riding={player:GetAttribute("Riding")}`)
end
