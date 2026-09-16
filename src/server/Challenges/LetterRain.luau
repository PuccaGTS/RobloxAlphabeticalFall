--!nonstrict
--[[
	Испытание «Буквопад» — ядро MVP. См. docs/03-CHALLENGES.md § 1.

	Голос называет букву («Лови вот эту букву! Буква М»), с неба падают буквы,
	ребёнок ловит нужную. Провалить нельзя: промах по чужой букве ничего не отнимает,
	счётчик не падает, испытание просто идёт дальше.

	Контракт модуля испытания: Build → Validate (много раз) → Finish.
	Позиции и состав букв генерирует СЕРВЕР, клиент их только рисует.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Letters = require(Shared.Config.Letters)
local Challenges = require(Shared.Config.Challenges)
local DifficultyCurve = require(Shared.Logic.DifficultyCurve)

local LetterRain = {}

LetterRain.id = "letter_rain"
LetterRain.trains = { "recognize" }
LetterRain.minLetters = 2

local FALL_HEIGHT = 24 -- studs, с какой высоты падают буквы: из облака над полем
local LANES = 5
-- Запас по времени на сетевую задержку: клиентский тап может прийти чуть позже,
-- чем буква «долетела» по расчётам сервера.
local TAP_GRACE_BEFORE = 0.25
local TAP_GRACE_AFTER = 0.6

local function shuffled(list: { any }, random: Random): { any }
	local copy = table.clone(list)
	for i = #copy, 2, -1 do
		local j = random:NextInteger(1, i)
		copy[i], copy[j] = copy[j], copy[i]
	end
	return copy
end

--[[
	Строит задание.
	letters — очередь от планировщика повторений: первая буква становится целью,
	остальные идут в отвлекающие.
]]
function LetterRain.Build(_player: Player, letters: { string }, difficulty: number)
	assert(#letters >= LetterRain.minLetters, "LetterRain: нужно минимум две буквы")

	local meta = Challenges.expect(LetterRain.id)
	local targetCount = DifficultyCurve.pick(meta.params.targetCount, difficulty)
	local distractorsPerTarget = DifficultyCurve.pick(meta.params.distractors, difficulty)
	local fallSpeed = DifficultyCurve.pick(meta.params.fallSpeed, difficulty)
	local spawnInterval = DifficultyCurve.pick(meta.params.spawnInterval, difficulty)
	local hintAfterSec = DifficultyCurve.pick(meta.params.hintAfterSec, difficulty)
	local missCooldown = DifficultyCurve.pick(meta.params.missCooldown, difficulty)
	local restTime = DifficultyCurve.pick(meta.params.restTime, difficulty)

	local targetId = letters[1]
	local distractorPool: { string } = {}
	for index = 2, #letters do
		table.insert(distractorPool, letters[index])
	end
	if #distractorPool == 0 then
		-- страховка: цель обязана хоть с чем-то контрастировать
		for _, id in Letters.ordered() do
			if id ~= targetId then
				table.insert(distractorPool, id)
			end
		end
	end

	local seed = math.floor(os.clock() * 1000) % 2 ^ 31
	local random = Random.new(seed)

	local total = targetCount * (distractorsPerTarget + 1)
	local flags: { boolean } = {}
	for index = 1, total do
		table.insert(flags, index <= targetCount)
	end
	flags = shuffled(flags, random)

	-- Первая буква всегда целевая: ребёнок должен сразу увидеть, что от него хотят.
	if not flags[1] then
		for index = 2, #flags do
			if flags[index] then
				flags[1], flags[index] = true, false
				break
			end
		end
	end

	local items = {}
	local lastLane = 0
	for index, isTarget in flags do
		local lane = random:NextInteger(1, LANES)
		if lane == lastLane then
			lane = (lane % LANES) + 1
		end
		lastLane = lane

		table.insert(items, {
			index = index,
			letterId = if isTarget then targetId else distractorPool[random:NextInteger(1, #distractorPool)],
			isTarget = isTarget,
			spawnAt = (index - 1) * spawnInterval,
			lane = lane,
		})
	end

	return {
		challengeId = LetterRain.id,
		seed = seed,
		letters = letters,
		difficulty = difficulty,
		targetCount = targetCount,
		params = {
			targetLetter = targetId,
			targetGlyph = Letters.expect(targetId).glyph,
			targetVO = Letters.expect(targetId).vo.name,
			items = items,
			fallSpeed = fallSpeed,
			fallHeight = FALL_HEIGHT,
			lanes = LANES,
			hintAfterSec = hintAfterSec,
			missCooldown = missCooldown,
			flightTime = FALL_HEIGHT / fallSpeed,
			--[[
				Сколько буква лежит на траве после приземления. Ловят её теперь
				не щелчком в воздухе, а ногами: ребёнок видит тень, бежит к месту
				и подхватывает букву у земли. Без этой паузы до дальней буквы
				было бы не добежать.
			]]
			restTime = restTime,
		},
	}
end

--[[
	Проверяет действие клиента.

	Клиент присылает только «я тапнул по объекту #N». Верно это или нет и когда именно
	буква была на экране — считает сервер по собственному времени старта.
]]
function LetterRain.Validate(state, action)
	if typeof(action) ~= "table" or typeof(action.itemIndex) ~= "number" then
		return { handled = false }
	end

	local items = state.spec.params.items
	local item = items[action.itemIndex]
	if not item or state.answered[action.itemIndex] then
		return { handled = false }
	end

	local now = os.clock()

	-- «Сачок опущен» после промаха: ловить нельзя, пока не отзвучит подсказка.
	-- Это единственная плата за ошибку — временем, а не прогрессом.
	if state.blockedUntil and now < state.blockedUntil then
		return { handled = false, blocked = true }
	end

	local elapsed = now - state.startedAt
	local flightTime = state.spec.params.flightTime
	local appearedAt = item.spawnAt
	local goneAt = item.spawnAt + flightTime + (state.spec.params.restTime or 0)

	if elapsed < appearedAt - TAP_GRACE_BEFORE or elapsed > goneAt + TAP_GRACE_AFTER then
		-- буква ещё не появилась или уже упала: тап устарел, но это не ошибка ребёнка
		return { handled = false }
	end

	state.answered[action.itemIndex] = true

	local correct = item.isTarget
	local cooldown = 0
	if correct then
		state.caught += 1
	else
		state.missed += 1
		cooldown = state.spec.params.missCooldown
		state.blockedUntil = now + cooldown
	end

	return {
		handled = true,
		correct = correct,
		cooldown = cooldown,
		itemIndex = action.itemIndex,
		-- Ответ засчитывается ЦЕЛЕВОЙ букве: испытание проверяет, узнаёт ли ребёнок именно её.
		letterId = state.spec.params.targetLetter,
		tappedLetterId = item.letterId,
		reactionMs = math.max(0, math.floor((elapsed - appearedAt) * 1000)),
		finished = state.caught >= state.spec.targetCount,
	}
end

--[[
	Итог. Звёзды считаем щедро: три — за чистый проход, но и худший результат
	даёт звезду и награду. Ребёнку нельзя уйти с пустыми руками.
]]
function LetterRain.Finish(state)
	local targetCount = state.spec.targetCount
	local caught = state.caught

	local stars = 1
	if caught >= targetCount and state.missed == 0 then
		stars = 3
	elseif caught >= math.ceil(targetCount * 0.8) then
		stars = 2
	end

	return {
		challengeId = LetterRain.id,
		stars = stars,
		caught = caught,
		targetCount = targetCount,
		wrongTaps = state.missed,
	}
end

-- Сколько всего длится задание, если ребёнок ничего не ловит.
function LetterRain.duration(spec): number
	local items = spec.params.items
	local last = items[#items]
	return last.spawnAt + spec.params.flightTime + (spec.params.restTime or 0) + 2
end

return LetterRain
