--!nocheck
--[[
	Зимняя полянка: общий вид, снеговик, ёлка. И коньки: толкнуть ребёнка
	на лёд и на снег одинаково и сравнить, сколько он проедет сам после толчка.
]]
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

return function(player, note)
	local Teleport = require(ServerScriptService.Server.World.Teleport)
	local Playground = require(ReplicatedStorage.Shared.Config.Playground)
	task.wait(10)
	local zone = workspace.Hub.Playground:FindFirstChild("Play_winter")
	local ice = zone and zone:FindFirstChild("Ice")
	if not ice then
		note("NO WINTER")
		return
	end
	local origin = CFrame.lookAt(
		Vector3.new(ice.Position.X, ice.Position.Y, ice.Position.Z),
		Vector3.new(0, ice.Position.Y, 0)
	)
	-- Сначала подойти: стриминг отдаёт полянку только рядом.
	Teleport.to(player, origin * CFrame.new(0, 4, -26))
	task.wait(3)
	_G.ZZ_Shot(
		player,
		"winter_view",
		CFrame.lookAt((origin * CFrame.new(-6, 12, -38)).Position, origin.Position),
		65
	)
	task.wait(1)
	_G.ZZ_Shot(
		player,
		"winter_snowman",
		CFrame.lookAt((origin * CFrame.new(-10, 5, -16)).Position, (origin * CFrame.new(-13, 4, -7)).Position),
		60
	)
	task.wait(1)
	_G.ZZ_Shot(
		player,
		"winter_tree",
		CFrame.lookAt((origin * CFrame.new(4, 7, -8)).Position, (origin * CFrame.new(12, 8, 8)).Position),
		65
	)

	local function push(from: CFrame, direction: Vector3, label: string)
		Teleport.to(player, from)
		local root = player.Character.HumanoidRootPart
		for _ = 1, 40 do
			if not root.Anchored then
				break
			end
			task.wait(0.1)
		end
		task.wait(0.8)
		local attachment = Instance.new("Attachment")
		attachment.Parent = root
		local shove = Instance.new("LinearVelocity")
		shove.Attachment0 = attachment
		shove.MaxForce = 1e6
		shove.VectorVelocity = direction * 18
		shove.Parent = root
		task.wait(0.4)
		shove:Destroy()
		attachment:Destroy()
		local released = root.Position
		task.wait(1.5)
		local glided = ((root.Position - released) * Vector3.new(1, 0, 1)).Magnitude
		note(string.format("%s: after the push rolled on %.1f studs", label, glided))
		return glided
	end

	-- Со снега у входа на каток — внутрь, на лёд.
	local R = Playground.ICE_RADIUS
	push(origin * CFrame.new(0, 3.5, -R + 3), origin.LookVector * -1, "ice")
	_G.ZZ_Shot(
		player,
		"winter_skate",
		CFrame.lookAt((origin * CFrame.new(-10, 6, -16)).Position, ice.Position),
		65
	)
	task.wait(1.5)
	-- То же по снегу: вбок от катка.
	push(origin * CFrame.new(-16, 3.5, -12), origin.RightVector * -1, "snow")
end
