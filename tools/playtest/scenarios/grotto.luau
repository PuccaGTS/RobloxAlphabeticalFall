--!nocheck
--[[
	Грот с кристаллами: вход под водопадом, проход пешком сквозь завесу
	(зонд ведёт персонажа, как джойстик), вид внутри, касание кристалла,
	сундук у дальней стены и кристальная корона на ребёнке.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

return function(player, note)
	local Playground = require(ReplicatedStorage.Shared.Config.Playground)
	local Teleport = require(ServerScriptService.Server.World.Teleport)
	local ProfileService = require(ServerScriptService.Server.Services.ProfileService)
	task.wait(22) -- зонд клиента слушает метки ZZ_* только через ~20 с после входа
	local root = player.Character.HumanoidRootPart
	local spec = Playground.GROTTO
	local zone = workspace.Hub.Playground:FindFirstChild("Play_grotto")
	if not zone then
		note("NO GROTTO")
		return
	end
	local floor = zone:FindFirstChild("GrottoFloor")
	local centre = floor.Position
	local toPlaza = (-centre * Vector3.new(1, 0, 1)).Unit
	local function settle()
		for _ = 1, 40 do
			if not root.Anchored then
				break
			end
			task.wait(0.1)
		end
		task.wait(0.5)
	end

	local outside = centre + toPlaza * (spec.radius + 10) + Vector3.new(0, 3, 0)
	Teleport.to(player, CFrame.lookAt(outside, centre + Vector3.new(0, 3, 0)))
	settle()
	_G.ZZ_Shot(
		player,
		"grotto_entrance",
		CFrame.lookAt(
			centre + toPlaza * (spec.radius + 24) + Vector3.new(6, 9, 0),
			centre + Vector3.new(0, 5, 0)
		),
		60
	)
	task.wait(4.5)

	-- Сквозь завесу водопада пешком.
	local dir = -toPlaza
	workspace:SetAttribute("ZZ_Walk", string.format("%.3f,%.3f,1.1", dir.X, dir.Z))
	task.wait(2)
	local inside = ((root.Position - centre) * Vector3.new(1, 0, 1)).Magnitude
	note(string.format("grotto: walked in, %.1f from centre (walls at %.1f)", inside, spec.radius))
	_G.ZZ_Shot(
		player,
		"grotto_inside",
		CFrame.lookAt(
			centre + toPlaza * (spec.radius - 1.5) + Vector3.new(0, 6, 0),
			centre - toPlaza * spec.radius
		),
		70
	)
	task.wait(4.5)

	-- Кристалл: встать рядом и шагнуть в него.
	local crystal = zone:FindFirstChild("Crystal_3")
	if crystal then
		local toward = ((crystal.Position - centre) * Vector3.new(1, 0, 1)).Unit
		Teleport.to(player, CFrame.new(crystal.Position - toward * 4 + Vector3.new(0, 1.5, 0)))
		settle()
		workspace:SetAttribute("ZZ_Walk", nil)
		task.wait(0.2)
		workspace:SetAttribute("ZZ_Walk", string.format("%.3f,%.3f,0.8", toward.X, toward.Z))
		task.wait(0.3)
		_G.ZZ_Shot(
			player,
			"grotto_crystal",
			CFrame.lookAt(root.Position - toward * 8 + Vector3.new(0, 4, 0), crystal.Position),
			70
		)
		task.wait(4.5)
	end

	-- Сундук у дальней стены.
	local chest = workspace:FindFirstChild("Chest_chest_grotto", true)
		or workspace:FindFirstChild("chest_grotto", true)
	if not chest then
		note("NO GROTTO CHEST")
		return
	end
	Teleport.to(player, CFrame.new(chest:GetPivot().Position + Vector3.new(0, 3, 0)))
	local waited = 0
	local profile = ProfileService.get(player)
	while not table.find(profile.inventory, "hat_crystal") and waited < 15 do
		task.wait(0.5)
		waited += 0.5
		profile = ProfileService.get(player)
	end
	note(`crystal crown in inventory: {table.find(profile.inventory, "hat_crystal") ~= nil} after {waited} s`)
	task.wait(2)
	_G.ZZ_Shot(
		player,
		"grotto_crown",
		CFrame.lookAt(
			root.Position + root.CFrame.LookVector * 6 + Vector3.new(-1.5, 2, 0),
			root.Position + Vector3.new(0, 1.5, 0)
		),
		60
	)
end
