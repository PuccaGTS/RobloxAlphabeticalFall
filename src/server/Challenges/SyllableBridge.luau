--!nonstrict
--[[
	Испытание «Мост слогов» — главное в игре. См. docs/03-CHALLENGES.md § 5.

	Через пропасть надо построить мост: слева платформа с согласной, справа гласные.
	Ребёнок приставляет гласную — половинки соединяются, и звучит СЛИТНЫЙ слог.

	Это момент, ради которого игра существует: здесь ребёнок впервые читает.
	Поэтому два правила соблюдаются жёстко:
	  1. Слог озвучивается ОДНИМ записанным файлом (blend_ma), а не склейкой «м»+«а».
	     Склейка учит побуквенному чтению — ровно тому, что мы лечим.
	  2. Слог не может появиться раньше, чем обе его буквы стали доступны игроку.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Letters = require(Shared.Config.Letters)
local Syllables = require(Shared.Config.Syllables)
local Challenges = require(Shared.Config.Challenges)
local DifficultyCurve = require(Shared.Logic.DifficultyCurve)

local SyllableBridge = {}

SyllableBridge.id = "syllable_bridge"
SyllableBridge.trains = { "letter_to_sound", "blend" }
SyllableBridge.minLetters = 2

local function splitByKind(letterIds: { string }): ({ string }, { string })
	local consonants: { string } = {}
	local vowels: { string } = {}
	for _, id in letterIds do
		local letter = Letters.get(id)
		if letter then
			if letter.kind == "vowel" then
				table.insert(vowels, id)
			elseif letter.kind == "consonant" or letter.kind == "hissing" then
				table.insert(consonants, id)
			end
		end
	end
	return consonants, vowels
end

local function shuffled(list: { any }, random: Random): { any }
	local copy = table.clone(list)
	for i = #copy, 2, -1 do
		local j = random:NextInteger(1, i)
		copy[i], copy[j] = copy[j], copy[i]
	end
	return copy
end

--[[
	Собирает секции моста. Каждая секция — один слог: согласная слева,
	несколько гласных на выбор справа.
]]
function SyllableBridge.Build(player: Player, letters: { string }, difficulty: number)
	local meta = Challenges.expect(SyllableBridge.id)
	local sectionCount = DifficultyCurve.pick(meta.params.sections, difficulty)
	local choiceCount = DifficultyCurve.pick(meta.params.vowelChoices, difficulty)
	local missCooldown = DifficultyCurve.pick(meta.params.missCooldown, difficulty)

	local consonants, vowels = splitByKind(letters)

	-- Если гласных из очереди не хватает, добираем из уже пройденных островов:
	-- без гласной слог не построить в принципе.
	if #vowels < 2 then
		for _, id in Letters.vowels() do
			if not table.find(vowels, id) then
				table.insert(vowels, id)
			end
			if #vowels >= math.max(2, choiceCount) then
				break
			end
		end
	end

	assert(#vowels >= 1, "SyllableBridge: нужна хотя бы одна гласная")

	local seed = math.floor(os.clock() * 1000) % 2 ^ 31
	local random = Random.new(seed)

	--[[
		Левая половинка моста. Обычно это согласная (МА, ПУ), но на первом острове
		согласных ещё нет вообще — там слоги строятся из двух гласных (АУ, УА).
		Без этой ветки мост был бы недоступен, пока ребёнок не дойдёт до второго острова,
		то есть ровно тогда, когда он больше всего нужен.
	]]
	local lefts = if #consonants > 0 then consonants else vowels

	local sections = {}
	local index = 0
	local guard = 0

	while #sections < sectionCount and guard < sectionCount * 20 do
		guard += 1

		local leftId = lefts[(index % #lefts) + 1]
		local targetVowel = vowels[random:NextInteger(1, #vowels)]

		-- Ищем слог в справочнике: часть сочетаний запрещена методикой (ЖЫ, ШЫ и т.п.),
		-- а из двух гласных существуют только осмысленные пары.
		local syllableId = if leftId ~= targetVowel then leftId .. targetVowel else nil
		local syllable = if syllableId then Syllables.get(syllableId) else nil

		if syllable then
			index += 1

			local choices = { targetVowel }
			for _, id in shuffled(vowels, random) do
				if #choices >= choiceCount then
					break
				end
				if id ~= targetVowel then
					table.insert(choices, id)
				end
			end
			choices = shuffled(choices, random)

			local choiceData = {}
			for _, id in choices do
				table.insert(choiceData, { letterId = id, glyph = Letters.expect(id).glyph })
			end

			table.insert(sections, {
				index = #sections + 1,
				leftId = leftId,
				leftGlyph = Letters.expect(leftId).glyph,
				targetVowel = targetVowel,
				syllableId = syllableId,
				text = syllable.text,
				vo = syllable.vo,
				choices = choiceData,
			})
		else
			index += 1
		end
	end

	assert(#sections > 0, "SyllableBridge: не удалось собрать ни одной секции")

	return {
		challengeId = SyllableBridge.id,
		seed = seed,
		letters = letters,
		difficulty = difficulty,
		targetCount = #sections,
		params = {
			sections = sections,
			missCooldown = missCooldown,
			hintAfterSec = DifficultyCurve.pick(meta.params.hintAfterSec, difficulty),
		},
	}
end

--[[
	Проверяет выбор гласной. Ответ засчитывается ГЛАСНОЙ: именно её ребёнок
	опознаёт на слух, когда голос говорит «приставь А».
]]
function SyllableBridge.Validate(state, action)
	if typeof(action) ~= "table" or typeof(action.letterId) ~= "string" then
		return { handled = false }
	end

	local now = os.clock()
	if state.blockedUntil and now < state.blockedUntil then
		return { handled = false, blocked = true }
	end

	local sections = state.spec.params.sections
	local current = (state.section or 0) + 1
	local section = sections[current]
	if not section then
		return { handled = false }
	end

	-- клиент мог отстать на секцию: принимаем ответ только для текущей
	if typeof(action.sectionIndex) == "number" and action.sectionIndex ~= current then
		return { handled = false }
	end

	local isChoice = false
	for _, choice in section.choices do
		if choice.letterId == action.letterId then
			isChoice = true
			break
		end
	end
	if not isChoice then
		return { handled = false }
	end

	local correct = action.letterId == section.targetVowel
	local cooldown = 0

	if correct then
		state.section = current
		state.caught += 1
	else
		state.missed += 1
		cooldown = state.spec.params.missCooldown
		state.blockedUntil = now + cooldown
	end

	local elapsed = now - (state.sectionStartedAt or state.startedAt)
	state.sectionStartedAt = now

	return {
		handled = true,
		correct = correct,
		cooldown = cooldown,
		sectionIndex = current,
		letterId = section.targetVowel,
		tappedLetterId = if correct then nil else action.letterId,
		-- слитная запись слога: её клиент проигрывает в момент соединения половинок
		syllableVO = if correct then section.vo else nil,
		syllableId = if correct then section.syllableId else nil,
		syllableText = if correct then section.text else nil,
		reactionMs = math.max(0, math.floor(elapsed * 1000)),
		finished = correct and current >= #sections,
	}
end

function SyllableBridge.Finish(state)
	local total = state.spec.targetCount
	local built = state.caught

	local stars = 1
	if built >= total and state.missed == 0 then
		stars = 3
	elseif built >= math.ceil(total * 0.6) then
		stars = 2
	end

	return {
		challengeId = SyllableBridge.id,
		stars = stars,
		caught = built,
		targetCount = total,
		wrongTaps = state.missed,
	}
end

-- Ребёнка здесь не торопим: на каждую секцию с запасом времени.
function SyllableBridge.duration(spec): number
	return #spec.params.sections * 25 + 15
end

return SyllableBridge
