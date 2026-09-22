--!nocheck
--[[
	Салют за уровень. Сначала настоящий путь: забег первого уровня, шаг на
	финиш — клиент должен получить «уровень пройден». Потом салют по просьбе
	стенда перед неподвижной камерой, и снимки разрывов.
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
	task.wait(3)

	ProfileService.update(player, function(p)
		p.levels = p.levels or {}
		p.levels.letters = 0
		p.runs = {}
	end)
	ChallengeService.startFor(player, "tunnel_run")
	task.wait(6)
	local model = workspace.Tunnels:FindFirstChild(`Tunnel_{player.UserId}`)
	local trigger = model and model:FindFirstChild("FinishTrigger", true)
	if trigger then
		Teleport.to(player, trigger.CFrame)
		task.wait(8)
	else
		note("NO FINISH")
	end

	-- Салют перед камерой над площадью.
	local eye = CFrame.lookAt(Vector3.new(0, 8, 60), Vector3.new(0, 30, -40))
	workspace:SetAttribute("ZZ_Fireworks", os.clock())
	_G.ZZ_Shot(player, "fireworks_1", eye, 70)
	workspace:SetAttribute("ZZ_Fireworks", os.clock())
	task.wait(0.4)
	_G.ZZ_Shot(player, "fireworks_2", eye, 70)
end
