--!nonstrict
--[[
	Испытание «Весы». См. docs/16-MATH.md § 3.3.

	На левой чаше лежат камни. Перед весами — несколько кучек камней, и ребёнок
	выбирает ту, что уравновесит весы. Верная кучка — весы выровнялись. Неверная —
	весы качнулись в сторону тяжёлой чаши и вернулись: никто не упал, ничего
	не отнято, после паузы можно выбрать снова.

	Учит равенству — «столько же» — самому важному понятию перед арифметикой.

	Почему выбор из кучек, а не «клади камни по одному, пока не выровняется»:
	по одному ребёнок просто смотрит на наклон и останавливается, когда весы
	ровные, — считать для этого не нужно. Кучку же надо сравнить с чашей до того,
	как выбрал, и это и есть счёт.

	Цифр на камнях нет: цифра превратила бы задание в поиск такого же значка
	(docs/16-MATH.md § 1, правило 1 — сначала количество). Число звучит голосом
	после верного ответа: «три» — и ребёнок слышит, сколько он только что насчитал.

	Ответ засчитывается ступени счёта. Пока ребёнок на ступенях до «больше/меньше»
	включительно — его текущей: там он и учится видеть количество. Дальше — ступени
	«больше/меньше»: сложение весы не тренируют, а равенство — это она.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MathConfig = require(Shared.Config.Math)
local Challenges = require(Shared.Config.Challenges)
local DifficultyCurve = require(Shared.Logic.DifficultyCurve)

local Scales = {}

Scales.id = "scales"
Scales.trains = { "count" }
Scales.minLetters = 0
Scales.usesMathStage = true

-- Ступень, на которую уходят ответы, когда ребёнок дорос выше неё.
Scales.EQUALITY_STAGE_ID = "compare"
-- Меньше трёх камней — нечего сравнивать; больше десяти — не сосчитать взглядом.
Scales.MIN_STONES = 3

local function shuffled(list: { any }, random: Random): { any }
	local copy = table.clone(list)
	for i = #copy, 2, -1 do
		local j = random:NextInteger(1, i)
		copy[i], copy[j] = copy[j], copy[i]
	end
	return copy
end

-- Какой ступени засчитываются ответы и сколько камней она позволяет.
function Scales.topicFor(stage: number): (string, number)
	local spec = MathConfig.get(stage) or MathConfig.expect(1)
	local equality = MathConfig.byId(Scales.EQUALITY_STAGE_ID)
	local topic = if equality and spec.stage > equality.stage then equality.id else spec.id
	local cap = math.clamp(spec.max, Scales.MIN_STONES, MathConfig.MAX_NUMBER)
	return topic, cap
end

--[[
	Неверные кучки — соседние количества: на один и на два больше или меньше.
	Ошибка должна быть осмысленной (docs/16-MATH.md § 4): три против четырёх
	учит считать, три против девяти — только смотреть на размер.
]]
function Scales.choicesFor(left: number, count: number, maxStones: number, random: Random): { number }
	local values = { left }
	for _, delta in shuffled({ -1, 1, -2, 2 }, random) do
		if #values >= count then
			break
		end
		local value = left + delta
		if value >= 1 and value <= maxStones and not table.find(values, value) then
			table.insert(values, value)
		end
	end
	return shuffled(values, random)
end

function Scales.Build(
	_player: Player?,
	_letters: { string },
	difficulty: number,
	stage: number?,
	seed: number?
)
	local meta = Challenges.expect(Scales.id)
	local roundCount = DifficultyCurve.pick(meta.params.rounds, difficulty)
	local choiceCount = DifficultyCurve.pick(meta.params.choices, difficulty)
	local missCooldown = DifficultyCurve.pick(meta.params.missCooldown, difficulty)
	local topic, cap = Scales.topicFor(stage or 1)
	local maxStones = math.min(DifficultyCurve.pick(meta.params.maxStones, difficulty), cap)

	local runSeed = seed or math.floor(os.clock() * 1000) % 2 ^ 31
	local random = Random.new(runSeed)

	local rounds = {}
	local previous = 0
	for index = 1, roundCount do
		-- Два раза подряд одно и то же количество — повтор, а не задание.
		local left = random:NextInteger(1, maxStones)
		if left == previous then
			left = left % maxStones + 1
		end
		previous = left

		local choices = Scales.choicesFor(left, choiceCount, maxStones, random)
		table.insert(rounds, {
			index = index,
			left = left,
			choices = choices,
			correctSlot = table.find(choices, left),
		})
	end

	return {
		challengeId = Scales.id,
		seed = runSeed,
		letters = {},
		difficulty = difficulty,
		stage = stage,
		targetCount = roundCount,
		params = {
			rounds = rounds,
			mathStageId = topic,
			missCooldown = missCooldown,
		},
	}
end

--[[
	Клиент присылает «выбрал кучку slot в раунде round». Как в Зеркале, отвечать
	можно только на текущий раунд, а промах не сдвигает его.
]]
function Scales.Validate(state, action)
	if typeof(action) ~= "table" or typeof(action.round) ~= "number" or typeof(action.slot) ~= "number" then
		return { handled = false }
	end

	state.round = state.round or 1
	local round = state.spec.params.rounds[state.round]
	if not round or action.round ~= state.round or not round.choices[action.slot] then
		return { handled = false }
	end

	local now = os.clock()
	if state.blockedUntil and now < state.blockedUntil then
		return { handled = false, blocked = true }
	end

	local value = round.choices[action.slot]
	local correct = action.slot == round.correctSlot
	local since = state.roundStartedAt or state.startedAt
	local cooldown = 0

	if correct then
		state.caught += 1
		state.round += 1
		state.roundStartedAt = now
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
		topic = "math",
		topicId = state.spec.params.mathStageId,
		-- Сколько камней легло на правую чашу: по нему клиент наклоняет весы.
		tappedValue = value,
		-- Верно — голос называет количество, которое ребёнок только что уравнял.
		stepVO = if correct then `num_{round.left}` else nil,
		reactionMs = math.max(0, math.floor((now - since) * 1000)),
		finished = state.round > #state.spec.params.rounds,
	}
end

function Scales.Finish(state)
	local total = state.spec.targetCount
	local stars = 1
	if state.caught >= total and state.missed == 0 then
		stars = 3
	elseif state.caught >= total then
		stars = 2
	end
	return {
		challengeId = Scales.id,
		stars = stars,
		caught = state.caught,
		targetCount = total,
		wrongTaps = state.missed,
	}
end

function Scales.duration(_spec): number
	return Challenges.expect(Scales.id).maxSeconds
end

return Scales
