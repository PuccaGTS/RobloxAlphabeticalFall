--!nocheck
--[[
	Катания: колесо обозрения и паровозик. Снимки, потом посадка в кабинку
	и в вагончик — сервер смотрит, куда едет персонаж.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

return function(player, note)
	local Rides = require(ReplicatedStorage.Shared.Config.Rides)
	local Playground = require(ReplicatedStorage.Shared.Config.Playground)
	local Teleport = require(ServerScriptService.Server.World.Teleport)
	task.wait(8)
	local root = player.Character.HumanoidRootPart

	local spot = Playground.expect("ferris")
	local center = Playground.position(spot)
	_G.ZZ_Shot(player, "ride_spawn", CFrame.lookAt(Vector3.new(0, 9, 44), Vector3.new(0, 16, -60)), 70)
	_G.ZZ_Shot(
		player,
		"ride_wheel",
		CFrame.lookAt(Vector3.new(-25, 12, -70), center + Vector3.new(0, 18, 0)),
		60
	)
	_G.ZZ_Shot(player, "ride_overview", CFrame.lookAt(Vector3.new(120, 90, 160), Vector3.new(0, 0, -60)), 70)

	-- Колесо: встать на посадочный круг.
	local pad = workspace.Hub.Playground.Play_ferris.BoardPad
	Teleport.to(player, CFrame.new(pad.Position + Vector3.new(0, 3, 0)))
	local top = 0
	for step = 1, 24 do
		task.wait(1)
		top = math.max(top, root.Position.Y)
		if step == 11 then
			_G.ZZ_Shot(
				player,
				"ride_wheel_top",
				CFrame.lookAt(
					root.Position + Vector3.new(4, 3, 10),
					root.Position + Vector3.new(-40, -10, -100)
				),
				70
			)
		end
	end
	note(string.format("wheel ride: highest root Y %.1f", top))
	task.wait(24)
	note(string.format("wheel after lap: root %s", tostring(root.Position)))

	-- Поезд: дождаться стоянки и встать на круг станции.
	local board = workspace.Hub.Railway.Station.BoardPad
	for _ = 1, 140 do
		local _, standing = Rides.trainAt(workspace:GetServerTimeNow())
		if standing then
			break
		end
		task.wait(1)
	end
	_G.ZZ_Shot(
		player,
		"ride_station",
		CFrame.lookAt(board.Position + Vector3.new(-18, 8, 18), board.Position),
		70
	)
	Teleport.to(player, CFrame.new(board.Position + Vector3.new(0, 3, 0)))
	local start = root.Position
	task.wait(20)
	note(
		string.format(
			"train ride: moved %.0f studs, root %s",
			(root.Position - start).Magnitude,
			tostring(root.Position)
		)
	)
	_G.ZZ_Shot(
		player,
		"ride_train",
		CFrame.lookAt(root.Position + Vector3.new(0, 10, 0) - root.CFrame.LookVector * 22, root.Position),
		70
	)
end
