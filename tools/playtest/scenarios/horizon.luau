--!nocheck
-- Горизонт и небо: с площади, от домов к краю мира и с высоты птичьего полёта.
return function(player, note)
	task.wait(8)
	local horizon = workspace.Hub:FindFirstChild("Horizon")
	note(`horizon parts {horizon and #horizon:GetDescendants() or 0}`)
	local views = {
		{ "hz_spawn", Vector3.new(0, 9, 44), Vector3.new(0, 20, -300) },
		{ "hz_plaza_side", Vector3.new(40, 12, 0), Vector3.new(600, 40, 100) },
		{ "hz_from_houses", Vector3.new(0, 10, 300), Vector3.new(0, 30, 900) },
		{ "hz_high_out", Vector3.new(0, 70, 150), Vector3.new(0, 70, 1000) },
		{ "hz_diag", Vector3.new(200, 45, -200), Vector3.new(900, 90, -900) },
		{ "hz_top", Vector3.new(0, 420, 520), Vector3.new(0, 0, -150) },
	}
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	for _, view in views do
		-- Персонаж стоит на площади: камера далеко от него, но в кадр он не лезет.
		if root then
			root.Anchored = true
			root.CFrame = CFrame.new(0, 4, 30)
		end
		task.wait(1.5)
		_G.ZZ_Shot(player, view[1], CFrame.lookAt(view[2], view[3]), 70)
	end
end
