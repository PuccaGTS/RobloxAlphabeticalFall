--!nocheck
-- Живой мир: пруд с карпами под горбатым мостиком и радуга над парком.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

return function(player, note)
	local Decor = require(ReplicatedStorage.Shared.Config.Decor)
	task.wait(8)
	local bridge
	for _, placement in Decor.placements do
		if placement.id == Decor.POND_UNDER then
			bridge = placement
			break
		end
	end
	note("pond at " .. tostring(bridge and Vector3.new(bridge.x, 0, bridge.z)))
	if bridge then
		local center = Vector3.new(bridge.x, 1, bridge.z)
		local frame = CFrame.new(center) * CFrame.Angles(0, math.rad(bridge.rotation), 0)
		-- Персонаж рядом, иначе камера далеко от него и карпы за VISIBLE_DISTANCE не плывут.
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if root then
			root.CFrame = CFrame.new((frame * CFrame.new(0, 4, 16)).Position)
		end
		task.wait(3)
		_G.ZZ_Shot(player, "pond_side", CFrame.lookAt((frame * CFrame.new(3, 7, 15)).Position, center), 60)
		_G.ZZ_Shot(player, "pond_top", CFrame.lookAt((frame * CFrame.new(0, 16, 5)).Position, center), 60)
		for index = 1, 3 do
			_G.ZZ_Shot(player, `pond_close_{index}`, CFrame.lookAt((frame * CFrame.new(-4, 5, 9)).Position, center + Vector3.new(0, 0.5, 0)), 50)
		end
	end
	workspace:SetAttribute("ZZ_Rainbow", os.clock())
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if root then
		root.CFrame = CFrame.new(0, 5, 44)
	end
	task.wait(4)
	_G.ZZ_Shot(player, "rainbow_spawn", CFrame.lookAt(Vector3.new(0, 9, 44), Vector3.new(0, 30, -60)), 70)
	_G.ZZ_Shot(player, "rainbow_high", CFrame.lookAt(Vector3.new(60, 80, 140), Vector3.new(0, 30, -120)), 70)
end
