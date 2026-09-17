--!nocheck
-- «Зеркало» с буквами, нарисованными штрихами: снимок табличек для нескольких букв.
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Services = ServerScriptService.Server.Services

return function(player, note)
	local ProfileService = require(Services.ProfileService)
	local ChallengeService = require(Services.ChallengeService)
	local Teleport = require(ServerScriptService.Server.World.Teleport)
	local Venues = require(ReplicatedStorage.Shared.Config.Venues)
	for _ = 1, 60 do
		if ProfileService.get(player) then
			break
		end
		task.wait(0.5)
	end
	task.wait(3)
	Teleport.to(player, Venues.entry("mirror"))
	task.wait(3)

	local only = workspace:GetAttribute("ZZ_Only")
	local letters = if only then string.split(only, ",") else { "r", "z", "yu", "ya", "b" }
	local origin = Venues.stage("mirror") * CFrame.new(0, 4.5, 0) * CFrame.Angles(0, math.pi, 0)
	for _, letterId in letters do
		ChallengeService.abort(player)
		task.wait(1.2)
		ChallengeService.startFor(player, "mirror", { focus = letterId })
		task.wait(2)
		note(`mirror {letterId} busy={ChallengeService.isBusy(player)}`)
		local eye = origin.Position + origin.LookVector * 17 + Vector3.new(0, 1.5, 0)
		_G.ZZ_Shot(player, `mirror_{letterId}`, CFrame.lookAt(eye, origin.Position), 60)
		local eye2 = origin.Position - origin.LookVector * 17 + Vector3.new(0, 1.5, 0)
		_G.ZZ_Shot(player, `mirror_{letterId}_back`, CFrame.lookAt(eye2, origin.Position), 60)
	end
	ChallengeService.abort(player)
end
