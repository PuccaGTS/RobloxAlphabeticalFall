--!nocheck
-- Первые 20 секунд: где персонаж, жив ли, выдалась ли панель разработчика.
return function(player, note)
	for _ = 1, 40 do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		note(
			string.format(
				"pos %s hp %s DevTools=%s",
				root and tostring(root.Position) or "-",
				humanoid and tostring(humanoid.Health) or "-",
				tostring(player:GetAttribute("DevTools"))
			)
		)
		task.wait(0.5)
	end
end
