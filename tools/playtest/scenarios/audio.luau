--!nocheck
--[[
	Звук: музыка площади и птицы, фонтан вблизи, музыка забега букв и тропы цифр.
	Клиент сам докладывает, какие звуки загрузились (метка ZZ_AudioReport).
]]
local ServerScriptService = game:GetService("ServerScriptService")
local Services = ServerScriptService.Server.Services

return function(player, note)
	local ProfileService = require(Services.ProfileService)
	local ChallengeService = require(Services.ChallengeService)
	local Teleport = require(ServerScriptService.Server.World.Teleport)
	for _ = 1, 60 do
		if ProfileService.get(player) and player.Character then
			break
		end
		task.wait(0.5)
	end
	task.wait(10)
	workspace:SetAttribute("ZZ_AudioReport", "hub")
	task.wait(2)
	Teleport.to(player, CFrame.new(0, 5, -20))
	task.wait(4)
	workspace:SetAttribute("ZZ_AudioReport", "fountain")
	task.wait(2)

	ChallengeService.startFor(player, "tunnel_run")
	task.wait(10)
	workspace:SetAttribute("ZZ_AudioReport", "letters")
	task.wait(2)
	ChallengeService.abort(player)
	task.wait(2)
	ChallengeService.startFor(player, "math_gates")
	task.wait(10)
	workspace:SetAttribute("ZZ_AudioReport", "math")
	task.wait(2)
end
