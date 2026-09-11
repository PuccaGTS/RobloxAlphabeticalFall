--!nonstrict
--[[
	Испытание «Алфавитная лестница». См. docs/03-CHALLENGES.md § 2.

	Ребёнок поднимается по лестнице: на каждой ступени стоит уже знакомая буква,
	а выше лежат несколько плит. Надо выбрать ту, что идёт следующей по алфавиту.

	Это единственное испытание, которое спрашивает «что дальше», а не «где эта».
	Оно и делает игру азбукой, а не набором карточек: порядок букв — это то,
	ради чего алфавит вообще существует.

	Контракт модуля испытания: Build → Validate (много раз) → Finish.

	На этом месте раньше стоял «Мост слогов». Ритм у лестницы тот же — одна секция
	за раз, выбор из нескольких плит, — но слогов и звуков в ней нет.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Letters = require(Shared.Config.Letters)
local Challenges = require(Shared.Config.Challenges)
local DifficultyCurve = require(Shared.Logic.DifficultyCurve)

local AlphabetLadder = {}

AlphabetLadder.id = "alphabet_ladder"
AlphabetLadder.trains = { "order", "name" }
AlphabetLadder.minLetters = 2

local function shuffled(list: { any }, random: Random): { any }
	local copy = table.clone(list)
	for i = #copy, 2, -1 do
		local j = random:NextInteger(1, i)
		copy[i], copy[j] = copy[j], copy[i]
	end
	return copy
end

--[[
	Буквы, доступные игроку, в алфавитном порядке и без повторов.

	Порядок здесь не украшение: лестница поднимается по соседним буквам,
	и «соседние» имеет смысл только в отсортированном списке.
]]
local function orderedPool(letters: { string }): { string }
	local seen: { [string]: boolean } = {}
	local pool: { string } = {}
	for _, id in letters do
		if not seen[id] and Letters.get(id) then
			seen[id] = true
			table.insert(pool, id)
		end
	end
	table.sort(pool, function(a: string, b: string): boolean
		return Letters.expect(a).order < Letters.expect(b).order
	end)
	return pool
end

--[[
	Собирает ступени лестницы.

	Подъём идёт подряд: А → Б → В → Г. Случайные пары («после Ж идёт З, а теперь
	после Б идёт В») ломают ровно то, чему испытание учит, — ощущение линии,
	по которой буквы стоят.
]]
function AlphabetLadder.Build(_player: Player, letters: { string }, difficulty: number)
	local meta = Challenges.expect(AlphabetLadder.id)
	local requestedRungs = DifficultyCurve.pick(meta.params.rungs, difficulty)
	local choiceCount = DifficultyCurve.pick(meta.params.choices, difficulty)
	local missCooldown = DifficultyCurve.pick(meta.params.missCooldown, difficulty)
	local hintAfterSec = DifficultyCurve.pick(meta.params.hintAfterSec, difficulty)

	local pool = orderedPool(letters)
	assert(#pool >= AlphabetLadder.minLetters, "AlphabetLadder: нужно минимум две буквы")

	-- Ступеней не больше, чем есть переходов между доступными буквами.
	local rungs = math.min(requestedRungs, #pool - 1)

	local seed = math.floor(os.clock() * 1000) % 2 ^ 31
	local random = Random.new(seed)

	--[[
		С какой буквы начинаем подъём.

		Первая буква очереди повторений — та, которую сегодня стоит показать, —
		берётся за начало, но только если сверху над ней хватает букв на всю лестницу.
		Иначе отступаем вниз: лучше начать раньше, чем оборвать лестницу на середине.
	]]
	local start = table.find(pool, letters[1]) or 1
	start = math.min(start, #pool - rungs)
	start = math.max(start, 1)

	local sections = {}
	for position = 1, rungs do
		local fromId = pool[start + position - 1]
		local targetId = pool[start + position]

		local choices = { targetId }
		for _, id in shuffled(pool, random) do
			if #choices >= choiceCount then
				break
			end
			-- Буква, с которой поднимаемся, в вариантах не нужна: она уже под ногами.
			if id ~= targetId and id ~= fromId then
				table.insert(choices, id)
			end
		end

		--[[
			Выбор из одного варианта — не выбор: ребёнок тыкает единственную плиту
			и «проходит» ступень, ничего не узнав. Если доступных букв так мало,
			что вариантов не набралось, вторым ставим ту, с которой поднимаемся.
		]]
		if #choices < 2 then
			table.insert(choices, fromId)
		end
		choices = shuffled(choices, random)

		local choiceData = {}
		for _, id in choices do
			table.insert(choiceData, { letterId = id, glyph = Letters.expect(id).glyph })
		end

		table.insert(sections, {
			index = position,
			fromId = fromId,
			fromGlyph = Letters.expect(fromId).glyph,
			targetId = targetId,
			targetGlyph = Letters.expect(targetId).glyph,
			targetVO = Letters.expect(targetId).vo.name,
			choices = choiceData,
		})
	end

	return {
		challengeId = AlphabetLadder.id,
		seed = seed,
		letters = letters,
		difficulty = difficulty,
		targetCount = #sections,
		params = {
			-- Цель забега — первая буква, которую предстоит назвать: с неё начинается
			-- знакомство, если ребёнок видит её впервые.
			targetLetter = sections[1] and sections[1].targetId,
			sections = sections,
			missCooldown = missCooldown,
			hintAfterSec = hintAfterSec,
		},
	}
end

--[[
	Проверяет выбор плиты. Ответ засчитывается ЦЕЛЕВОЙ букве — той, которую
	ребёнок должен был вспомнить: именно её он сейчас узнаёт и называет.
]]
function AlphabetLadder.Validate(state, action)
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

	-- клиент мог отстать на ступень: принимаем ответ только для текущей
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

	local correct = action.letterId == section.targetId
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
		letterId = section.targetId,
		tappedLetterId = if correct then nil else action.letterId,
		-- Название взятой буквы: клиент произносит её в момент, когда плита встаёт на место.
		stepVO = if correct then section.targetVO else nil,
		stepGlyph = if correct then section.targetGlyph else nil,
		reactionMs = math.max(0, math.floor(elapsed * 1000)),
		finished = correct and current >= #sections,
	}
end

function AlphabetLadder.Finish(state)
	local total = state.spec.targetCount
	local climbed = state.caught

	local stars = 1
	if climbed >= total and state.missed == 0 then
		stars = 3
	elseif climbed >= math.ceil(total * 0.6) then
		stars = 2
	end

	return {
		challengeId = AlphabetLadder.id,
		stars = stars,
		caught = climbed,
		targetCount = total,
		wrongTaps = state.missed,
	}
end

-- Ребёнка здесь не торопим: на каждую ступень с запасом времени.
function AlphabetLadder.duration(spec): number
	return #spec.params.sections * 25 + 15
end

return AlphabetLadder
