--!nocheck
-- Воздушные змеи над лугами и белки на деревьях у площади: снимки издалека и вблизи.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

return function(player, note)
	local LiveWorld = require(ReplicatedStorage.Shared.Config.LiveWorld)
	local Teleport = require(ServerScriptService.Server.World.Teleport)
	task.wait(10)
	_G.ZZ_Shot(player, "sky_spawn", CFrame.lookAt(Vector3.new(0, 9, 44), Vector3.new(0, 30, -120)), 70)
	for index = 1, #LiveWorld.KITES do
		local stake = LiveWorld.kiteStake(index)
		local kite = stake
			+ LiveWorld.WIND.Unit * LiveWorld.KITE_REACH
			+ Vector3.new(0, LiveWorld.KITE_HEIGHT, 0)
		Teleport.to(player, CFrame.new(stake + Vector3.new(4, 3, 4)))
		task.wait(3)
		_G.ZZ_Shot(
			player,
			`sky_kite_{index}`,
			CFrame.lookAt(stake - LiveWorld.WIND.Unit * 14 + Vector3.new(0, 8, 0), kite),
			60
		)
	end
	local trees = LiveWorld.squirrelTrees()
	note(`squirrel trees {#trees}`)
	for _, tree in trees do
		note(
			string.format(
				"tree %.1f,%.1f,%.1f trunk %.1f climb %.1f",
				tree.position.X,
				tree.position.Y,
				tree.position.Z,
				tree.trunk,
				tree.climb
			)
		)
	end
	workspace:SetAttribute("ZZ_Track", "Squirrel")
	local tree = trees[2]
	Teleport.to(player, CFrame.new(tree.position + Vector3.new(24, 3, 24)))
	for shot = 1, 6 do
		task.wait(2)
		_G.ZZ_Shot(
			player,
			`sky_squirrel_{shot}`,
			CFrame.lookAt(tree.position + Vector3.new(7, 5, 7), tree.position + Vector3.new(0, 4, 0)),
			60
		)
	end
end
