--!nocheck
--[[
	Брызгалки: общий вид в разные такты хореографии (струя бежит по кругу,
	все разом, вполсилы) и ребёнок под опрокинутым ведром — с него должно капать.
]]
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

return function(player, note)
	local Teleport = require(ServerScriptService.Server.World.Teleport)
	local Playground = require(ReplicatedStorage.Shared.Config.Playground)
	task.wait(10)
	local zone = workspace.Hub.Playground:FindFirstChild("Play_splash")
	local floor = zone and zone:FindFirstChild("SplashFloor")
	local bucket = zone and zone:FindFirstChild("SplashBucket")
	if not floor or not bucket then
		note("NO SPLASH")
		return
	end
	local center = floor.Position
	local origin = CFrame.lookAt(center, Vector3.new(0, center.Y, 0))
	Teleport.to(player, origin * CFrame.new(3, 4, -20))
	task.wait(3)

	-- Снимок уходит примерно через секунду после команды: целимся в такт заранее.
	local function waitFor(moment, every)
		while true do
			local t = workspace:GetServerTimeNow() % every
			local wait = (moment - 1 - t) % every
			if wait < 0.2 or wait > every - 0.5 then
				return
			end
			task.wait(math.min(wait, 2))
		end
	end
	local eye = CFrame.lookAt((origin * CFrame.new(-8, 10, -24)).Position, center + Vector3.new(0, 3, 0))
	for _, moment in { 2, 5, 9.5, 13 } do
		waitFor(moment, Playground.SPLASH_CYCLE)
		_G.ZZ_Shot(player, `splash_{math.floor(moment)}`, eye, 60)
		note(string.format("shot at cycle %.1f", workspace:GetServerTimeNow() % Playground.SPLASH_CYCLE))
	end

	-- Под ведро: встать туда, куда оно льёт, и дождаться опрокидывания.
	local dump = bucket:GetAttribute("Dump")
	Teleport.to(player, CFrame.new(dump + Vector3.new(0, 3, 0)))
	waitFor(1, Playground.SPLASH_BUCKET_EVERY)
	workspace:SetAttribute(
		"ZZ_Inspect",
		"Hub.Playground.Play_splash.SplashCurtain_1;Hub.Playground.Play_splash.SplashBucket.BucketBody;Hub.Playground.Play_splash.SplashBucket.BucketSpill;Hub.Playground.Play_splash.SplashJet_0"
	)
	-- Снимок уходит секунды через четыре после команды: ждём, чтобы ведро было опрокинуто.
	waitFor(Playground.SPLASH_BUCKET_EVERY - 3, Playground.SPLASH_BUCKET_EVERY)
	-- Сбоку от плоскости, в которой ведро наклоняется: со стороны площади.
	_G.ZZ_Shot(
		player,
		"splash_bucket",
		CFrame.lookAt(dump + origin.LookVector * 18 + Vector3.new(0, 9, 0), dump + Vector3.new(-2, 7, 0)),
		65
	)
	task.wait(2.5)
	_G.ZZ_Shot(
		player,
		"splash_wet",
		CFrame.lookAt(dump + origin.LookVector * 9 + Vector3.new(0, 3, 0), dump + Vector3.new(0, 3, 0)),
		55
	)
end
