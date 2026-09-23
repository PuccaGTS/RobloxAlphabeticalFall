--!nocheck
--[[
	Птички у фонтана: стайка клюёт на плитке, ребёнок подбегает — вспархивают
	на фонарь. Птицы клиентские: их высоту пишет зонд (метка ZZ_Track = Bird).
]]
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

return function(player, note)
	local Teleport = require(ServerScriptService.Server.World.Teleport)
	local LiveWorld = require(ReplicatedStorage.Shared.Config.LiveWorld)
	task.wait(10)
	local home = Vector3.new(LiveWorld.BIRD_HOME.X, 2, LiveWorld.BIRD_HOME.Y)
	note(`perches: {#LiveWorld.birdPerches()}`)
	-- Издалека, чтобы не спугнуть: снимок стайки на земле.
	Teleport.to(player, CFrame.new(home + Vector3.new(0, 3, 24)))
	task.wait(3)
	workspace:SetAttribute("ZZ_Track", "Bird")
	_G.ZZ_Shot(player, "birds_ground", CFrame.lookAt(home + Vector3.new(-5, 4, 9), home), 50)
	task.wait(2)
	note("--- kid runs at the flock")
	Teleport.to(player, CFrame.new(home + Vector3.new(0, 3, 1)))
	task.wait(2.5)
	local perches = LiveWorld.birdPerches()
	local lamp = perches[1]
	_G.ZZ_Shot(
		player,
		"birds_flown",
		CFrame.lookAt(home + Vector3.new(0, 8, 18), home + Vector3.new(0, 7, 0)),
		75
	)
	task.wait(3)
	workspace:SetAttribute("ZZ_Track", nil)
end
