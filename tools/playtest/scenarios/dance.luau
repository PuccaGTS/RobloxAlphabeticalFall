--!nocheck
-- Танцы: персонаж танцует и машет, буквята радуются. Снимок сразу после начала жеста.
return function(player, note)
	task.wait(25) -- клиентский зонд подключает метку не сразу
	local root = player.Character.HumanoidRootPart
	local eye = root.Position + root.CFrame.LookVector * 10 + Vector3.new(0, 3, 0)
	for _, id in { "dance", "dance2", "wave" } do
		workspace:SetAttribute("ZZ_Emote", id)
		task.wait(1.5)
		_G.ZZ_Shot(player, `dance_{id}`, CFrame.lookAt(eye, root.Position), 60)
		task.wait(1)
	end
end
