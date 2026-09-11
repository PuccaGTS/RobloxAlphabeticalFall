--!nonstrict
--[[
	Испытание «Пузыри». См. docs/03-CHALLENGES.md § 5.

	Перед ребёнком всплывают пузыри с буквами. Голос называет букву — нужно
	лопнуть все пузыри с ней. Пузыри не пропадают: доплыв доверху, пузырь
	снова появляется внизу, и так, пока его не лопнут. Поэтому спешить незачем
	вовсе — это самое спокойное занятие в игре, и оно для этого и нужно.

	Лопнул не тот — пузырь превращается в рыбку и уплывает. Это «мимо»,
	а не наказание: короткая пауза, название той буквы и снова цель.

	Отвлекающие буквы — сначала похожие по начертанию на цель (Ш рядом с Щ,
	Б рядом с В): медленные пузыри — лучшее место, чтобы их различать.

	Контракт тот же, что у Буквопада: Build → Validate → Finish, позиции и состав
	генерирует сервер, клиент (BubblesController) только рисует.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Letters = require(Shared.Config.Letters)
local Challenges = require(Shared.Config.Challenges)
local DifficultyCurve = require(Shared.Logic.DifficultyCurve)

local Bubbles = {}

Bubbles.id = "bubbles"
Bubbles.trains = { "recognize" }
Bubbles.minLetters = 2

-- Сколько колонок пузырей и какой высоты столб, в котором они плывут.
Bubbles.COLUMNS = 6
Bubbles.HEIGHT = 22

local function shuffled(list: { any }, random: Random): { any }
	local copy = table.clone(list)
	for i = #copy, 2, -1 do
		local j = random:NextInteger(1, i)
		copy[i], copy[j] = copy[j], copy[i]
	end
	return copy
end

--[[
	Отвлекающие буквы по убыванию пользы: похожие по начертанию из доступных,
	потом остальные доступные. Буквы, которых ребёнок ещё не видел, сюда
	не попадают: letters — это очередь и все открытые буквы (ChallengeService).
]]
local function distractorPool(letters: { string }, targetId: string): { string }
	local target = Letters.expect(targetId)
	local available: { [string]: boolean } = {}
	for _, id in letters do
		available[id] = true
	end

	local pool: { string } = {}
	for _, id in target.confusableWith do
		if available[id] then
			table.insert(pool, id)
		end
	end
	for _, id in letters do
		if id ~= targetId and not table.find(pool, id) then
			table.insert(pool, id)
		end
	end
	if #pool == 0 then
		for _, id in Letters.ordered() do
			if id ~= targetId then
				table.insert(pool, id)
			end
		end
	end
	return pool
end

--[[
	Строит задание. seed передаётся тестам; в игре он берётся из часов.

	Пузыри раскладываются по колонкам и фазам так, чтобы в одной колонке
	они шли друг за другом с равным шагом и никогда не слипались.
]]
function Bubbles.Build(_player: Player?, letters: { string }, difficulty: number, _track: any, seed: number?)
	assert(#letters >= Bubbles.minLetters, "Bubbles: нужно минимум две буквы")

	local meta = Challenges.expect(Bubbles.id)
	local total = DifficultyCurve.pick(meta.params.totalBubbles, difficulty)
	local targetCount = math.min(DifficultyCurve.pick(meta.params.targetCount, difficulty), total - 1)
	local riseSpeed = DifficultyCurve.pick(meta.params.riseSpeed, difficulty)
	local missCooldown = DifficultyCurve.pick(meta.params.missCooldown, difficulty)

	local runSeed = seed or math.floor(os.clock() * 1000) % 2 ^ 31
	local random = Random.new(runSeed)

	local targetId = letters[1]
	local pool = distractorPool(letters, targetId)

	local flags: { boolean } = {}
	for index = 1, total do
		table.insert(flags, index <= targetCount)
	end
	flags = shuffled(flags, random)

	local perColumn = math.ceil(total / Bubbles.COLUMNS)
	local items = {}
	for index, isTarget in flags do
		local column = (index - 1) % Bubbles.COLUMNS + 1
		local row = (index - 1) // Bubbles.COLUMNS
		-- Колонки сдвинуты друг относительно друга: пузыри не всплывают шеренгой.
		local phase = (row / perColumn + (column - 1) / (Bubbles.COLUMNS * perColumn)) % 1
		table.insert(items, {
			index = index,
			letterId = if isTarget then targetId else pool[random:NextInteger(1, #pool)],
			isTarget = isTarget,
			column = column,
			phase = phase,
		})
	end

	local target = Letters.expect(targetId)
	return {
		challengeId = Bubbles.id,
		seed = runSeed,
		letters = letters,
		difficulty = difficulty,
		targetCount = targetCount,
		params = {
			targetLetter = targetId,
			targetGlyph = target.glyph,
			targetVO = target.vo.name,
			items = items,
			columns = Bubbles.COLUMNS,
			height = Bubbles.HEIGHT,
			riseSpeed = riseSpeed,
			missCooldown = missCooldown,
		},
	}
end

--[[
	Клиент присылает «лопнул пузырь #N». Пузыри не исчезают сами, поэтому
	по времени проверять нечего: лопнуть можно любой ещё не лопнутый.
]]
function Bubbles.Validate(state, action)
	if typeof(action) ~= "table" or typeof(action.itemIndex) ~= "number" then
		return { handled = false }
	end

	local item = state.spec.params.items[action.itemIndex]
	if not item or state.answered[action.itemIndex] then
		return { handled = false }
	end

	local now = os.clock()
	if state.blockedUntil and now < state.blockedUntil then
		return { handled = false, blocked = true }
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

	-- Время реакции — от прошлого лопнутого пузыря: от старта оно росло бы весь раунд.
	local since = state.lastPopAt or state.startedAt
	state.lastPopAt = now

	return {
		handled = true,
		correct = correct,
		cooldown = cooldown,
		itemIndex = action.itemIndex,
		letterId = state.spec.params.targetLetter,
		tappedLetterId = item.letterId,
		reactionMs = math.max(0, math.floor((now - since) * 1000)),
		finished = state.caught >= state.spec.targetCount,
	}
end

function Bubbles.Finish(state)
	local targetCount = state.spec.targetCount
	local caught = state.caught

	local stars = 1
	if caught >= targetCount and state.missed == 0 then
		stars = 3
	elseif caught >= targetCount then
		stars = 2
	end

	return {
		challengeId = Bubbles.id,
		stars = stars,
		caught = caught,
		targetCount = targetCount,
		wrongTaps = state.missed,
	}
end

-- Пузыри не кончаются сами: держим испытание столько, сколько разрешает конфиг.
function Bubbles.duration(_spec): number
	return Challenges.expect(Bubbles.id).maxSeconds
end

return Bubbles
