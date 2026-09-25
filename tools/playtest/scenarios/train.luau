--!nocheck
--[[
	Паровозик: твёрдое ли полотно, не задевает ли навес голову, пускает ли
	круг посадки только когда поезд у этой станции и везёт ли до следующей.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

return function(player, note)
	local Rides = require(ReplicatedStorage.Shared.Config.Rides)
	local Teleport = require(ServerScriptService.Server.World.Teleport)
	task.wait(8)
	local root = player.Character.HumanoidRootPart
	local railway = workspace.Hub.Railway

	-- Полотно: встать на эстакаду между станциями — персонаж должен остаться наверху.
	local on = Rides.trackFrame(math.rad(Rides.TRAIN.stationAngle + 20))
	Teleport.to(player, CFrame.new(on.Position + Vector3.new(0, 4, 0)))
	task.wait(4)
	note(string.format("on track: root Y %.1f (track top %.1f)", root.Position.Y, Rides.TRAIN.height))
	_G.ZZ_Shot(
		player,
		"train_track",
		CFrame.lookAt(
			on.Position + Vector3.new(0, 6, 0) - on.LookVector * 20 + on.RightVector * 6,
			on.Position
		),
		70
	)
	task.wait(5)

	-- Станция: персонаж под навесом, снимок сбоку.
	for index = 1, Rides.TRAIN.stations do
		local station = railway:FindFirstChild(`Station_{index}`)
		note(`station {index}: {station and "ok" or "MISSING"}`)
	end
	local pad = railway.Station_2.BoardPad
	Teleport.to(player, CFrame.new(pad.Position + Vector3.new(0, 3, 6)))
	task.wait(3)
	local frame = Rides.stationFrame(2)
	_G.ZZ_Shot(
		player,
		"train_station",
		CFrame.lookAt(
			pad.Position + frame.RightVector * 16 + Vector3.new(0, 3, 0),
			pad.Position + Vector3.new(0, 4, 0)
		),
		70
	)
	task.wait(5)

	-- Посадка: дождаться поезда у какой-нибудь станции, встать на её круг.
	local stoppedAt
	for _ = 1, 60 do
		local _, standing, at = Rides.trainAt(workspace:GetServerTimeNow())
		if standing and Rides.trainArrival(workspace:GetServerTimeNow(), at) == 0 then
			stoppedAt = at
			break
		end
		task.wait(1)
	end
	note(`train stopped at station {tostring(stoppedAt)}`)
	local board = railway[`Station_{stoppedAt}`].BoardPad
	Teleport.to(player, CFrame.new(board.Position + Vector3.new(0, 3, 0)))
	task.wait(2)
	note(string.format("boarded: sit %s", tostring(player.Character.Humanoid.Sit)))
	task.wait(Rides.TRAIN.dwell + Rides.trainLeg())
	local nextStation = stoppedAt % Rides.TRAIN.stations + 1
	local nextPad = railway[`Station_{nextStation}`].BoardPad
	note(
		string.format(
			"after one leg: %.0f studs from next station pad, sit %s",
			(root.Position - nextPad.Position).Magnitude,
			tostring(player.Character.Humanoid.Sit)
		)
	)
	_G.ZZ_Shot(
		player,
		"train_ride",
		CFrame.lookAt(root.Position + Vector3.new(0, 10, 0) - root.CFrame.LookVector * 22, root.Position),
		70
	)
	task.wait(6)
end
