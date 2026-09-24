--!nocheck
--[[
	Корабль-качели: общий вид с дорожки, посадка на стоянке и раскачка —
	сервер смотрит, сидит ли ребёнок, как высоко и далеко его носит и
	возвращает ли корабль к кругу посадки.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

return function(player, note)
	local Rides = require(ReplicatedStorage.Shared.Config.Rides)
	local Playground = require(ReplicatedStorage.Shared.Config.Playground)
	local Teleport = require(ServerScriptService.Server.World.Teleport)
	task.wait(8)
	local root = player.Character.HumanoidRootPart
	local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
	local spot = Playground.position(Playground.expect("ship"))
	local zone = workspace.Hub.Playground:FindFirstChild("Play_ship")
	local pad = zone and zone:FindFirstChild("BoardPad")
	if not pad then
		note("NO SHIP")
		return
	end
	local inward = (-spot * Vector3.new(1, 0, 1)).Unit
	local side = Vector3.new(-inward.Z, 0, inward.X)
	local view =
		CFrame.lookAt(spot + inward * 34 + side * 6 + Vector3.new(0, 12, 0), spot + Vector3.new(0, 8, 0))
	Teleport.to(player, CFrame.new(spot + inward * 30 + Vector3.new(0, 4, 0)))
	task.wait(3)

	-- Дождаться стоянки: круг посадки зелёный только тогда.
	local cycle = Rides.shipCycle()
	local function phase()
		return workspace:GetServerTimeNow() % cycle
	end
	-- Снимок уходит через ~4 с: целимся в середину раскачки заранее.
	while math.abs(phase() - (Rides.SHIP.dwell + 14 - 4.1)) > 0.1 do
		task.wait(0.05)
	end
	_G.ZZ_Shot(player, "ship_swing", view, 60)
	while phase() > 1 do
		task.wait(0.1)
	end
	Teleport.to(player, CFrame.new(pad.Position + Vector3.new(0, 3, 0)))
	task.wait(2)
	_G.ZZ_Shot(player, "ship_rest", view, 60)
	note(
		string.format(
			"ship: sit=%s at phase %.1f (dwell %d)",
			tostring(humanoid.Sit),
			phase(),
			Rides.SHIP.dwell
		)
	)
	local low, high, spread = math.huge, -math.huge, 0
	local centre = spot + Vector3.new(0, 0, 0)
	while phase() < Rides.SHIP.dwell do
		task.wait(0.1)
	end
	local rideEnd = os.clock() + Rides.SHIP.ride
	local shot = false
	while os.clock() < rideEnd do
		task.wait(0.1)
		low = math.min(low, root.Position.Y)
		high = math.max(high, root.Position.Y)
		spread = math.max(spread, ((root.Position - centre) * Vector3.new(1, 0, 1)).Magnitude)
		if not shot and os.clock() > rideEnd - Rides.SHIP.ride + 10 then
			shot = true
			_G.ZZ_Shot(player, "ship_ride", view, 60)
		end
	end
	note(
		string.format(
			"ship: rider height %.1f..%.1f, farthest from centre %.1f, sit=%s",
			low,
			high,
			spread,
			tostring(humanoid.Sit)
		)
	)
	task.wait(3)
	note(
		string.format(
			"ship: after ride sit=%s, from pad %.1f",
			tostring(humanoid.Sit),
			((root.Position - pad.Position) * Vector3.new(1, 0, 1)).Magnitude
		)
	)
end
