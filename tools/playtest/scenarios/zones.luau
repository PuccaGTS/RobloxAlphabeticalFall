--!nocheck
--[[
	Звуковые зоны (Config/Ambient.zoneAt): у корабля играет только морская песня,
	у лебедей — только их вальс, на площади — ни одной песни мест.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

return function(player, note)
	local Playground = require(ReplicatedStorage.Shared.Config.Playground)
	local Rides = require(ReplicatedStorage.Shared.Config.Rides)
	local Teleport = require(ServerScriptService.Server.World.Teleport)
	task.wait(22) -- зонд клиента слушает метки не сразу

	local songs = {
		"AmbientSounds.Ambient_amb_ship_shanty",
		"AmbientSounds.Ambient_amb_swan_dance",
		"AmbientSounds.Ambient_amb_carousel",
		"AmbientSounds.Ambient_amb_carnival",
	}
	local function check(label, at)
		Teleport.to(player, CFrame.new(at + Vector3.new(0, 4, 0)))
		task.wait(5)
		note(`--- {label}`)
		workspace:SetAttribute("ZZ_Inspect", table.concat(songs, ";") .. ";" .. label)
		task.wait(3)
	end

	local ship = Playground.position(Playground.expect(Rides.SHIP.spot))
	local toPlaza = (-ship * Vector3.new(1, 0, 1)).Unit
	check("ship", ship + toPlaza * 14)
	local lake = Playground.position(Playground.expect(Rides.SWANS.spot))
	check("lake", lake + (-lake * Vector3.new(1, 0, 1)).Unit * 34)
	check("plaza", Vector3.new(0, 0, 30))
end
