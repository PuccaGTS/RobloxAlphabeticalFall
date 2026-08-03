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
function SyllableBridge.Build(_player: Player, letters: { string }, difficulty: number)
	local meta = Challenges.expect(SyllableBridge.id)
	local sectionCount = DifficultyCurve.pick(meta.params.sections, difficulty)
	local choiceCount = DifficultyCurve.pick(meta.params.vowelChoices, difficulty)
	local missCooldown = DifficultyCurve.pick(meta.params.missCooldown, difficulty)

	local seed = math.floor(os.clock() * 1000) % 2 ^ 31
	local random = Random.new(seed)

	--[[
		Собираем ВСЕ пары, которые реально существуют в справочнике слогов.

		Раньше пары искались случайным перебором, и это ломалось: слоги из двух гласных
		есть только для АУ, УА, ИА, АИ. Стоило очереди подсунуть, скажем, О и А —
		валидных пар не оказывалось вовсе, и испытание падало с ошибкой.
		Перечисление вместо угадывания не может не найти того, что есть.
	]]
	local function collect(leftPool: { string }, vowelPool: { string })
		local found = {}
		for _, leftId in leftPool do
			for _, vowelId in vowelPool do
				if leftId ~= vowelId then
					local syllable = Syllables.get(leftId .. vowelId)
					if syllable then
						table.insert(found, { left = leftId, vowel = vowelId, syllable = syllable })
					end
				end
			end
		end
		return found
	end

	local consonants, vowels = splitByKind(letters)

	-- Левая половинка — согласная (МА, ПУ), а на первом острове согласных нет вообще,
	-- и слог строится из двух гласных (АУ, УА). Иначе мост был бы недоступен ровно тогда,
	-- когда он нужнее всего.
	local lefts = if #consonants > 0 then consonants else vowels
	local candidates = collect(lefts, vowels)

	--[[
		Если из букв очереди слог не складывается, расширяем набор до всех гласных.
		Лучше дать ребёнку соседнюю букву того же острова, чем показать пустой мост.
	]]
	if #candidates == 0 then
		vowels = Letters.vowels()
		lefts = if #consonants > 0 then consonants else vowels
		candidates = collect(lefts, vowels)
	end

	assert(
		#candidates > 0,
		"SyllableBridge: в справочнике нет ни одного подходящего слога"
	)

	--[[
		Отдельный набор гласных для ВАРИАНТОВ ответа.

		Если в очереди была одна гласная, вариант в воротах оставался ровно один —
		и выбора не было вовсе: ребёнок тыкал единственную кнопку и «проходил» задание,
		ничего не узнав. Варианты добираем из соседних гласных, даже когда
		сам слог строится из букв очереди.
	]]
	local choicePool = table.clone(vowels)
	if #choicePool < math.max(2, choiceCount) then
		for _, id in Letters.vowels() do
			if not table.find(choicePool, id) then
				table.insert(choicePool, id)
			end
			if #choicePool >= math.max(2, choiceCount) then
				break
			end
		end
	end

	local shuffledCandidates = shuffled(candidates, random)
	local sections = {}

	for position = 1, sectionCount do
		-- Кандидатов может быть меньше, чем секций: тогда слоги повторяются,
		-- и это не беда — повторение здесь работает на нас.
		local candidate = shuffledCandidates[(position - 1) % #shuffledCandidates + 1]
		local targetVowel = candidate.vowel

		local choices = { targetVowel }
		for _, id in shuffled(choicePool, random) do
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
			index = position,
			leftId = candidate.left,
			leftGlyph = Letters.expect(candidate.left).glyph,
			targetVowel = targetVowel,
			syllableId = candidate.syllable.id,
			text = candidate.syllable.text,
			vo = candidate.syllable.vo,
			choices = choiceData,
		})
	end

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
