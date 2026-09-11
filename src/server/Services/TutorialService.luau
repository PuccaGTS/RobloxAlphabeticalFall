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
	task.delay(NEXT_STEP_DELAY, announce, player)
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
