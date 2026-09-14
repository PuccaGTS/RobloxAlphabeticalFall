--!nonstrict
--[[
	Испытание «Зеркало». См. docs/03-CHALLENGES.md § 6.

	Голос называет букву, перед ребёнком несколько её вариантов: один написан
	правильно, остальные — перевёрнуты, лежат на боку или отражены. Надо найти
	правильную. Лечит классическую дошкольную беду — зеркальное написание.

	Отразить текст в Roblox нечем: интерфейс умеет поворачивать надпись,
	но не отражать её. Поэтому неправильные варианты трёх видов:
	  · rotate — вверх ногами (поворот на 180°);
	  · lying  — на боку (поворот на 90°);
	  · mirror — отражение, но только там, где для него есть готовый знак,
	    выглядящий ровно как отражённая буква: Я ↔ R, И ↔ N, Э ↔ Є.
	    Это как раз главные зеркальные путаницы дошкольников.

	Буквы, которые от поворота не меняются (О, Х, Н, Ж, И, Ф), получают только
	те варианты, где разница видна. Раунд, в котором «неправильный» вариант
	неотличим от правильного, был бы нечестным — это держится тестом.

	Ответ засчитывается названной букве: испытание учит её начертанию.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Letters = require(Shared.Config.Letters)
local Challenges = require(Shared.Config.Challenges)
local DifficultyCurve = require(Shared.Logic.DifficultyCurve)

local Mirror = {}

Mirror.id = "mirror"
Mirror.trains = { "shape", "recognize" }
Mirror.minLetters = 1
--[[
	Раунды идут по кругу списка букв. Задание по одной букве (буква дня) получает
	от ChallengeService только её, и все раунды — про неё.
]]
Mirror.focusAlone = true

-- Буквы, которые после поворота на 180° выглядят так же, как были.
Mirror.ROTATE_SAME = { zh = true, n = true, o = true, h = true, i = true, f = true }
-- Буквы, которые на боку неотличимы от себя (круг и крест).
Mirror.LYING_SAME = { o = true, h = true }
-- Готовые знаки, выглядящие как отражённая буква.
Mirror.MIRROR_GLYPH = { ya = "R", i = "N", e = "Є" }

local function shuffled(list: { any }, random: Random): { any }
	local copy = table.clone(list)
	for i = #copy, 2, -1 do
		local j = random:NextInteger(1, i)
		copy[i], copy[j] = copy[j], copy[i]
	end
	return copy
end

--[[
	Какие неправильные варианты у буквы честные — то есть заметно отличаются
	от правильной. Порядок: отражение первым, если оно есть: ради него
	испытание и придумано.
]]
function Mirror.wrongKinds(letterId: string): { string }
	local kinds: { string } = {}
	if Mirror.MIRROR_GLYPH[letterId] then
		table.insert(kinds, "mirror")
	end
	if not Mirror.ROTATE_SAME[letterId] then
		table.insert(kinds, "rotate")
	end
	if not Mirror.LYING_SAME[letterId] then
		table.insert(kinds, "lying")
	end
	return kinds
end

local function variantOf(letterId: string, kind: string, random: Random)
	local letter = Letters.expect(letterId)
	if kind == "mirror" then
		return { kind = kind, glyph = Mirror.MIRROR_GLYPH[letterId], rotation = 0 }
	elseif kind == "rotate" then
		return { kind = kind, glyph = letter.glyph, rotation = 180 }
	elseif kind == "lying" then
		return {
			kind = kind,
			glyph = letter.glyph,
			rotation = if random:NextInteger(1, 2) == 1 then 90 else -90,
		}
	end
	return { kind = "true", glyph = letter.glyph, rotation = 0 }
end

--[[
	Строит задание: раунды по буквам из очереди повторений.

	Первая буква — та, которую просит планировщик; дальше остальные, у которых
	есть хоть один честный неправильный вариант. Если открытых букв меньше,
	чем раундов, они идут по кругу. Зеркальные путаницы (Я, И, Э) из доступных
	ставятся вперёд очереди: ради них испытание и существует.
]]
function Mirror.Build(_player: Player?, letters: { string }, difficulty: number, _track: any, seed: number?)
	assert(#letters >= Mirror.minLetters, "Mirror: нужна хотя бы одна буква")

	local meta = Challenges.expect(Mirror.id)
	local roundCount = DifficultyCurve.pick(meta.params.rounds, difficulty)
	local variantCount = DifficultyCurve.pick(meta.params.variants, difficulty)
	local missCooldown = DifficultyCurve.pick(meta.params.missCooldown, difficulty)

	local runSeed = seed or math.floor(os.clock() * 1000) % 2 ^ 31
	local random = Random.new(runSeed)

	local eligible: { string } = {}
	local function add(id: string)
		if Letters.get(id) and #Mirror.wrongKinds(id) > 0 and not table.find(eligible, id) then
			table.insert(eligible, id)
		end
	end
	add(letters[1])
	for _, id in letters do
		if Mirror.MIRROR_GLYPH[id] then
			add(id)
		end
	end
	for _, id in letters do
		add(id)
	end
	-- Страховка: открыты только О и Х — у них честных вариантов нет вовсе.
	if #eligible == 0 then
		add("a")
	end

	local rounds = {}
	for index = 1, roundCount do
		local letterId = eligible[(index - 1) % #eligible + 1]
		local letter = Letters.expect(letterId)

		local kinds = shuffled(Mirror.wrongKinds(letterId), random)
		-- Отражение, если оно есть, в раунде обязательно: оно главное.
		table.sort(kinds, function(a, b)
			return a == "mirror" and b ~= "mirror"
		end)

		local variants = { variantOf(letterId, "true", random) }
		for slot = 1, math.min(variantCount - 1, #kinds) do
			table.insert(variants, variantOf(letterId, kinds[slot], random))
		end
		variants = shuffled(variants, random)

		local correctSlot = 0
		for slot, variant in variants do
			if variant.kind == "true" then
				correctSlot = slot
			end
		end

		table.insert(rounds, {
			index = index,
			letterId = letterId,
			vo = letter.vo.name,
			color = letter.color,
			variants = variants,
			correctSlot = correctSlot,
		})
	end

	return {
		challengeId = Mirror.id,
		seed = runSeed,
		letters = letters,
		difficulty = difficulty,
		targetCount = roundCount,
		params = {
			rounds = rounds,
			missCooldown = missCooldown,
			-- Название буквы первого раунда звучит сразу за инструкцией.
			taskVO = { rounds[1].vo },
		},
	}
end

--[[
	Клиент присылает «выбрал вариант slot в раунде round». Раунд обязан быть
	текущим: ответить на прошлый или будущий нельзя. Промах не сдвигает раунд —
	варианты остаются, и после паузы можно выбрать снова.
]]
function Mirror.Validate(state, action)
	if typeof(action) ~= "table" or typeof(action.round) ~= "number" or typeof(action.slot) ~= "number" then
		return { handled = false }
	end

	state.round = state.round or 1
	local round = state.spec.params.rounds[state.round]
	if not round or action.round ~= state.round or not round.variants[action.slot] then
		return { handled = false }
	end

	local now = os.clock()
	if state.blockedUntil and now < state.blockedUntil then
		return { handled = false, blocked = true }
	end

	local correct = action.slot == round.correctSlot
	local since = state.roundStartedAt or state.startedAt
	local cooldown = 0
	local nextRound = nil

	if correct then
		state.caught += 1
		state.round += 1
		state.roundStartedAt = now
		nextRound = state.spec.params.rounds[state.round]
	else
		state.missed += 1
		cooldown = state.spec.params.missCooldown
		state.blockedUntil = now + cooldown
	end

	return {
		handled = true,
		correct = correct,
		cooldown = cooldown,
		sectionIndex = round.index,
		letterId = round.letterId,
		-- Взятая буква называется сама: правильное начертание и имя — вместе.
		stepVO = if correct then round.vo else nil,
		-- Следующий раунд: его букву голос назовёт после похвалы.
		voAfter = if nextRound then { nextRound.vo } else nil,
		reactionMs = math.max(0, math.floor((now - since) * 1000)),
		finished = state.round > #state.spec.params.rounds,
	}
end

function Mirror.Finish(state)
	local total = state.spec.targetCount
	local stars = 1
	if state.caught >= total and state.missed == 0 then
		stars = 3
	elseif state.caught >= total then
		stars = 2
	end
	return {
		challengeId = Mirror.id,
		stars = stars,
		caught = state.caught,
		targetCount = total,
		wrongTaps = state.missed,
	}
end

function Mirror.duration(_spec): number
	return Challenges.expect(Mirror.id).maxSeconds
end

return Mirror
