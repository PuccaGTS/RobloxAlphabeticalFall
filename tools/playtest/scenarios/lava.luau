--!nocheck
--[[
	«Пол — это лава!»: пешком до пада, потом раунды. В первом раунде персонаж
	встаёт на свою букву, во втором — на чужую. Отчёт: засчитано ли верно,
	подбросило ли, кончилось ли испытание само. Снимки — арена спокойная,
	перед лавой и в лаве.
]]
local ServerScriptService = game:GetService("ServerScriptService")
local Services = ServerScriptService.Server.Services

return function(player, note)
	local ProfileService = require(Services.ProfileService)
	local ChallengeService = require(Services.ChallengeService)
	local Teleport = require(ServerScriptService.Server.World.Teleport)
	local LavaFloor = require(ServerScriptService.Server.Challenges.LavaFloor)
	for _ = 1, 60 do
		if ProfileService.get(player) and player.Character then
			break
		end
		task.wait(0.5)
	end
	task.wait(3)

	local spec
	ChallengeService.onStarted(function(p, s)
		if p == player and s.challengeId == "lava_floor" then
			spec = s
		end
	end)
	ChallengeService.onAnswer(function(p, s, result)
		if p == player and s.challengeId == "lava_floor" then
			note(
				`   answer round {result.itemIndex}: correct={result.correct} tapped={result.tappedLetterId}`
			)
		end
	end)
	ChallengeService.onFinished(function(p, s, reason)
		if p == player and s.challengeId == "lava_floor" then
			note(`   finished: {reason}`)
		end
	end)

	-- Пешком, как ребёнок: пад на площади должен запускать игру.
	local pad = workspace.Hub:FindFirstChild("Pad_lava_floor")
	if not pad then
		note("NO PAD")
		return
	end
	Teleport.to(player, Teleport.HUB)
	task.wait(2.5)
	player.Character:FindFirstChildOfClass("Humanoid"):MoveTo(pad.Position)
	for _ = 1, 30 do
		task.wait(0.5)
		if spec then
			break
		end
	end
	if not spec then
		note("NOT STARTED")
		return
	end
	note(
		`started, target {spec.params.targetLetter}, rounds {#spec.params.rounds}, seconds {spec.params.seconds}`
	)
	local stage = spec.params.stage
	local function at(seconds)
		task.wait(math.max(0, spec.params.startAt + seconds - workspace:GetServerTimeNow()))
	end
	local function tileWith(round, want)
		for index, id in spec.params.rounds[round].tiles do
			if (id == spec.params.targetLetter) == want then
				return index
			end
		end
	end
	local eye = (stage * CFrame.new(0, 22, 30)).Position
	local look = stage.Position

	-- Снимок ждёт прорисовку четыре секунды: просим его заранее.
	local own = tileWith(1, true)
	Teleport.to(player, stage * CFrame.new(LavaFloor.tileCenter(own) + Vector3.new(0, 4, 0)))
	at(LavaFloor.lavaAt(spec.params, 1) - 4.6)
	task.spawn(_G.ZZ_Shot, player, "lava_warn", CFrame.lookAt(eye, look), 70)
	at(LavaFloor.lavaAt(spec.params, 1) - 3.2)
	_G.ZZ_Shot(player, "lava_hot", CFrame.lookAt(eye, look), 70)

	at(LavaFloor.roundStart(spec.params, 2) + 1)
	local wrong = tileWith(2, false)
	Teleport.to(player, stage * CFrame.new(LavaFloor.tileCenter(wrong) + Vector3.new(0, 4, 0)))
	at(LavaFloor.lavaAt(spec.params, 2) + 0.35)
	local root = player.Character.HumanoidRootPart
	local y0 = stage:PointToObjectSpace(root.Position).Y
	task.wait(0.5)
	local y1 = stage:PointToObjectSpace(root.Position).Y
	note(string.format("   bounce: height %.1f -> %.1f", y0, y1))
	_G.ZZ_Shot(player, "lava_bounce", CFrame.lookAt(eye, look), 70)

	-- Дальше стоим вне арены: раунды не засчитываются, игра кончается сама.
	Teleport.to(player, Teleport.HUB)
	local ends = LavaFloor.duration(spec) + 3
	at(ends)
	note(`   busy at the end: {ChallengeService.isBusy(player)}`)
end
