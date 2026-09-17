--!nocheck
-- Снимки площади глазами ребёнка: от точки появления и сверху.
return function(player, note)
	task.wait(5)
	_G.ZZ_Shot(player, "spawn_view", CFrame.lookAt(Vector3.new(0, 9, 40), Vector3.new(0, 6, -10)), 70)
	_G.ZZ_Shot(player, "plaza_high", CFrame.lookAt(Vector3.new(60, 70, 110), Vector3.new(0, 0, 0)), 70)
end
