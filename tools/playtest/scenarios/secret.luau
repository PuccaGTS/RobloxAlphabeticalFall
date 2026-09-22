--!nocheck
--[[
	Тайный сад: вид с площади (только стена кустов), вход сзади, проход сквозь
	занавес листвы, сундук внутри и фонарик светлячков на ребёнке.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

return function(player, note)
	local Playground = require(ReplicatedStorage.Shared.Config.Playground)
	local Teleport = require(ServerScriptService.Server.World.Teleport)
	local ProfileService = require(ServerScriptService.Server.Services.ProfileService)
	task.wait(10)
	local root = player.Character.HumanoidRootPart
	local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
	local spot = Playground.expect("secret")
	local center = Playground.position(spot)
	local away = (center * Vector3.new(1, 0, 1)).Unit
	local radius = Playground.SECRET_RADIUS

	_G.ZZ_Shot(
		player,
		"secret_from_plaza",
		CFrame.lookAt(center * 0.72 + Vector3.new(0, 7, 0), center + Vector3.new(0, 4, 0)),
		60
	)

	-- Снаружи у входа: дальняя от площади сторона.
	local outside = center + away * (radius + 6) + Vector3.new(0, 3, 0)
	Teleport.to(player, CFrame.lookAt(outside, center + Vector3.new(0, 3, 0)))
	task.wait(3)
	_G.ZZ_Shot(
		player,
		"secret_entrance",
		CFrame.lookAt(center + away * (radius + 14) + Vector3.new(0, 7, 0), center + Vector3.new(0, 3, 0)),
		60
	)

	-- Пройти сквозь занавес пешком.
	humanoid:MoveTo(center + Vector3.new(0, 3, 0))
	task.wait(3)
	local inside = ((root.Position - center) * Vector3.new(1, 0, 1)).Magnitude
	note(string.format("walked through curtain: %.1f from centre (wall at %.1f)", inside, radius))
	_G.ZZ_Shot(
		player,
		"secret_inside",
		CFrame.lookAt(
			center + away * (radius - 2) + Vector3.new(0, 7, 0),
			center - away * radius + Vector3.new(0, 1, 0)
		),
		70
	)

	-- Сундук: коснуться.
	local chest = workspace:FindFirstChild("Chest_chest_secret", true)
		or workspace:FindFirstChild("chest_secret", true)
	if not chest then
		note("NO SECRET CHEST")
		return
	end
	Teleport.to(player, CFrame.new(chest:GetPivot().Position + Vector3.new(0, 3, 0)))
	local profile = ProfileService.get(player)
	local waited = 0
	while not table.find(profile.inventory, "back_firefly_jar") and waited < 15 do
		task.wait(0.5)
		waited += 0.5
		profile = ProfileService.get(player)
	end
	note(`jar in inventory: {table.find(profile.inventory, "back_firefly_jar") ~= nil} after {waited} s`)
	task.wait(2)
	_G.ZZ_Shot(
		player,
		"secret_jar",
		CFrame.lookAt(
			root.Position + root.CFrame.LookVector * -7 + Vector3.new(2, 3, 0),
			root.Position + Vector3.new(0, 1, 0)
		),
		60
	)
	_G.ZZ_Shot(
		player,
		"secret_jar_front",
		CFrame.lookAt(
			root.Position + root.CFrame.LookVector * 7 + Vector3.new(-2, 2, 0),
			root.Position + Vector3.new(0, 1, 0)
		),
		60
	)
end
