--!nocheck
-- Снимки площади и парка глазами ребёнка: от точки появления, по сторонам, сверху.
return function(player, note)
	task.wait(6)
	local views = {
		{ "spawn_view", Vector3.new(0, 9, 44), Vector3.new(0, 6, -20) },
		{ "look_left", Vector3.new(-10, 9, 30), Vector3.new(-90, 4, 10) },
		{ "look_right", Vector3.new(10, 9, 30), Vector3.new(90, 4, 10) },
		{ "look_back", Vector3.new(0, 9, 10), Vector3.new(0, 4, 100) },
		{ "behind_portals", Vector3.new(0, 14, -40), Vector3.new(0, 4, -110) },
		{ "obby", Vector3.new(-50, 20, -60), Vector3.new(-87, 8, -97) },
		{ "plaza_high", Vector3.new(60, 80, 120), Vector3.new(0, 0, -20) },
	}
	for _, view in views do
		_G.ZZ_Shot(player, view[1], CFrame.lookAt(view[2], view[3]), 70)
	end
end
