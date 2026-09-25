--!nonstrict
--[[
	Обучение первых минут на сервере: отмечает сделанные шаги и говорит голосом,
	что делать дальше. Шаги и правила — Logic/Tutorial, стрелку рисует клиент
	(TutorialController) по срезу профиля.

	Сервис ничего не запирает и никуда не телепортирует. Обучение — это подсказка,
	а не рельсы: ребёнок может пойти куда угодно, и сделанное вне очереди
	засчитается само.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Playground = require(Shared.Config.Playground)
local Tutorial = require(Shared.Logic.Tutorial)
local RemoteDefs = require(Shared.Net.RemoteDefs)

local ProfileService = require(script.Parent.ProfileService)
local ChallengeService = require(script.Parent.ChallengeService)
local ShopService = require(script.Parent.ShopService)

local TutorialService = {}

--[[
	Пауза перед голосом следующего шага. За финишем испытания звучат итог
	и звон награды, за покупкой — щелчок; подсказка поверх них не слышна.
]]
local NEXT_STEP_DELAY = 3

local function stateOf(profile): Tutorial.State
	return Tutorial.sanitize(profile.tutorial)
end

local function announce(player: Player)
	local profile = ProfileService.get(player)
	if not profile then
		return
	end
	local step = Tutorial.current(stateOf(profile))
	if step and step.vo then
		RemoteDefs.event("PlayVO"):FireClient(player, step.vo, false)
	end
end

function TutorialService.complete(player: Player, event: string)
	local closed = ProfileService.update(player, function(profile)
		local state = stateOf(profile)
		local stepId = Tutorial.complete(state, event)
		profile.tutorial = state
		return stepId
	end)
	if not closed then
		return
	end

	print(`[Tutorial] {player.Name}: шаг «{closed}» сделан`)
	-- Дошёл до места прогулки: звон и картинка места, следующая стрелка сразу.
	local walked = table.find(Tutorial.WALK, closed)
	if walked then
		RemoteDefs.event("PlaySfx"):FireClient(player, "reward")
		RemoteDefs.event("OpenUI"):FireClient(player, "walk", { step = walked, total = #Tutorial.WALK })
		return
	end
	task.delay(NEXT_STEP_DELAY, announce, player)
end

-- Где место прогулки: середина места парка, из цели шага "spot:<id>".
local function walkSpot(step: Tutorial.Step): (Vector3?, number)
	local id = string.match(step.target, "^spot:(.+)$")
	if not id then
		return nil, 0
	end
	local spot = Playground.expect(id)
	return Playground.position(spot), spot.radius
end

-- Для родительского режима: «пропустить обучение» для второго ребёнка в семье.
function TutorialService.skip(player: Player)
	ProfileService.update(player, function(profile)
		profile.tutorial = Tutorial.finished()
	end)
end

function TutorialService.start()
	--[[
		Засчитывается любой конец испытания, кроме брошенного. Тайм-аут тоже:
		ребёнок, не поймавший пять букв за отведённое время, всё равно поймал
		сколько-то и получил звёздочки, и держать его на первом шаге незачем.
	]]
	ChallengeService.onFinished(function(player: Player, spec: any, reason: string)
		if reason == "completed" or reason == "timeout" then
			TutorialService.complete(player, spec.challengeId)
		end
	end)

	ShopService.onPurchase(function(player: Player)
		TutorialService.complete(player, "purchase")
	end)

	-- Прогулка: дошёл до места парка — шаг сделан. Проверяем два раза в секунду.
	task.spawn(function()
		while true do
			task.wait(0.5)
			for _, player in Players:GetPlayers() do
				local profile = ProfileService.get(player)
				local step = profile and Tutorial.current(stateOf(profile))
				local center, radius = nil, 0
				if step then
					center, radius = walkSpot(step)
				end
				local character = player.Character
				local root = character and character:FindFirstChild("HumanoidRootPart")
				if center and root and step then
					local flat = (root.Position - center) * Vector3.new(1, 0, 1)
					if flat.Magnitude < radius + 4 then
						TutorialService.complete(player, `arrive:{string.sub(step.target, 6)}`)
					end
				end
			end
		end
	end)

	--[[
		Приветствие — только совсем новичку. Вернувшийся посреди обучения
		ребёнок уже знает, кто такая Азбука; ему стрелка покажет, что осталось,
		а голос шага прозвучит, когда он этот шаг сменит.
	]]
	Players.PlayerAdded:Connect(function(player: Player)
		task.spawn(function()
			local profile = ProfileService.waitFor(player, 20)
			if profile and Tutorial.isFresh(stateOf(profile)) then
				-- Дать клиенту подняться: реплика, пришедшая раньше контроллера звука, теряется.
				task.wait(2)
				announce(player)
			end
		end)
	end)
end

return TutorialService
