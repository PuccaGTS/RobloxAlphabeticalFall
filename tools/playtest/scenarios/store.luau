--!nocheck
-- Снимки для страницы игры: настоящие кадры Play без интерфейса.
-- Запуск: ZZ_WINDOW=2300x1320 python tools/playtest/run.py store
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Services = ServerScriptService.Server.Services

return function(player, note)
	local ProfileService = require(Services.ProfileService)
	local ChallengeService = require(Services.ChallengeService)
	local BaseService = require(Services.BaseService)
	local PetService = require(Services.PetService)
	local Teleport = require(ServerScriptService.Server.World.Teleport)
	local Venues = require(ReplicatedStorage.Shared.Config.Venues)
	local Decor = require(ReplicatedStorage.Shared.Config.Decor)
	local MasteryRules = require(ReplicatedStorage.Shared.Logic.MasteryRules)
	local RemoteDefs = require(ReplicatedStorage.Shared.Net.RemoteDefs)
	for _ = 1, 60 do
		if ProfileService.get(player) then
			break
		end
		task.wait(0.5)
	end
	task.wait(4)

	-- Двор достроен, пара буквят: на витрине дом, а не шалаш.
	ProfileService.update(player, function(p)
		for _, id in { "house", "roof", "yard", "fence", "furniture", "decor", "garden", "playground", "pets", "transport" } do
			p.base[id] = 4
		end
		for _, id in { "a", "b", "v" } do
			local progress = MasteryRules.newProgress(os.time())
			progress.mastery = MasteryRules.MASTERED
			progress.reviewStep = 3
			progress.nextReview = os.time() + 86400
			p.letters[id] = progress
		end
	end)
	BaseService.refresh(player)
	PetService.grant(player, "a")
	PetService.grant(player, "b")
	workspace:SetAttribute("ZZ_Rainbow", os.clock())

	-- Первый снимок растягивает окно: он пробный.
	_G.ZZ_Shot(player, "store_warmup", CFrame.lookAt(Vector3.new(0, 9, 44), Vector3.new(0, 12, -20)), 70)
	_G.ZZ_Shot(player, "store_plaza", CFrame.lookAt(Vector3.new(26, 42, 118), Vector3.new(0, 22, -40)), 60)

	for _, placement in Decor.placements do
		if placement.id == Decor.POND_UNDER then
			local frame = CFrame.new(placement.x, 1, placement.z) * CFrame.Angles(0, math.rad(placement.rotation), 0)
			-- Персонаж за камерой: карпы плывут, только когда камера рядом, а в кадре он не нужен.
			local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			if root then
				root.CFrame = frame * CFrame.new(-12, 3, 24)
			end
			task.wait(3)
			for index = 1, 3 do
				_G.ZZ_Shot(player, `store_pond_{index}`, CFrame.lookAt((frame * CFrame.new(-6, 7, 13)).Position, (frame * CFrame.new(0.5, 0.5, 0)).Position), 55)
			end
			break
		end
	end

	local function venueShot(id, name, offset, lookUp, extra)
		ChallengeService.abort(player)
		task.wait(1.2)
		Teleport.to(player, Venues.entry(id))
		task.wait(2.5)
		ChallengeService.startFor(player, id, extra)
		task.wait(4.5)
		local entry = Venues.entry(id)
		_G.ZZ_Shot(player, name, CFrame.lookAt((entry * offset).Position, Venues.center(id) + Vector3.new(0, lookUp, 0)), 60)
	end
	venueShot("letter_rain", "store_rain", CFrame.new(6, 9, 14), 6)
	venueShot("bubbles", "store_bubbles", CFrame.new(4, 5, 6), 9)
	-- Зеркало: таблички смотрят на вход, камера над плечом ребёнка.
	ChallengeService.abort(player)
	task.wait(1.2)
	Teleport.to(player, Venues.entry("mirror"))
	task.wait(2.5)
	ChallengeService.startFor(player, "mirror", { focus = "ya" })
	task.wait(3)
	local origin = Venues.stage("mirror") * CFrame.new(0, 4.5, 0) * CFrame.Angles(0, math.pi, 0)
	_G.ZZ_Shot(player, "store_mirror", CFrame.lookAt(origin.Position + origin.LookVector * 15 + Vector3.new(0, 2.5, 0), origin.Position), 55)
	ChallengeService.abort(player)
	task.wait(1.2)

	-- Карточка знакомства с интерфейсом: зовём её посреди ожидания снимка.
	BaseService.sendHome(player)
	task.wait(4)
	task.delay(2.8, function()
		RemoteDefs.event("PetGranted"):FireClient(player, "ya", {})
	end)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if root then
		_G.ZZ_Shot(player, "ui_store_intro", CFrame.lookAt((root.CFrame * CFrame.new(6, 6, 16)).Position, root.Position + Vector3.new(0, 2, 0)), 60)
	end
end
