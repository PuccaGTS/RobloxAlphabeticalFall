--!nocheck
--[[
	Буквята-игрушки (assets/models/pets): все пять видов за хозяином, мордочкой
	вперёд, и скин на игрушке. Снимки спереди от персонажа — видно мордочки.
]]
return function(player, note)
	task.wait(8)
	local root = player.Character.HumanoidRootPart
	root.Anchored = true
	root.CFrame = CFrame.new(0, 4, 40)
	local pairs = {
		{ "a", "b", nil, "cat_bunny" },
		{ "v", "g", nil, "bear_bird" },
		{ "d", "a", "skin_gold", "frog_cat_gold" },
		{ "b", "g", "skin_rainbow", "bunny_bird_rainbow" },
		{ "d", "b", nil, "frog_bunny" },
	}
	if workspace:GetAttribute("ZZ_Only") then
		pairs = { pairs[5] }
	end
	for _, set in pairs do
		player:SetAttribute("PetSkin", set[3])
		player:SetAttribute("PetLetter", set[1])
		player:SetAttribute("PetLetter2", set[2])
		task.wait(3)
		local eye = root.CFrame * CFrame.new(0, 3.5, -11)
		_G.ZZ_Shot(
			player,
			"pets_" .. set[4],
			CFrame.lookAt(eye.Position, (root.CFrame * CFrame.new(0, 1.5, 2)).Position),
			60
		)
		note("shot " .. set[4])
		task.wait(6)
	end
end
