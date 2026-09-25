--!nonstrict
--[[
	Испытание «Ворота с числами» — вход в мир математики. См. docs/16-MATH.md § 3.1.

	Устройство то же, что у «Азбучного туннеля»: коридор, стена с проёмами, над
	каждым проёмом ответ, мимо выбора не пробежать. Отличие одно, и оно
	принципиальное: у КАЖДЫХ ворот своя задача. Буква на весь забег одна, потому
	что с ней ребёнок знакомится; счёт же тренируется разными примерами подряд,
	и один пример на пять ворот не научил бы ничему.

	Отсюда и вторая особенность: задание звучит перед каждыми воротами. Голос
	называет следующий пример сразу, как пройдены предыдущие ворота, — до них
	остаётся целый отрезок, то есть больше трёх секунд на решение, как и требует
	docs/16-MATH.md § 3.1.

	Задачи НЕ пишутся руками и не хранятся: их выдаёт генератор Config/Math по сиду.
	Поэтому забег воспроизводится из рецепта до последней задачи, и сохранка
	работает так же, как в буквенном туннеле.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MathConfig = require(Shared.Config.Math)
local MathLevels = require(Shared.Config.MathLevels)
local Attractions = require(Shared.Config.Attractions)
local Tunnel = require(Shared.Config.Tunnel)
local DifficultyCurve = require(Shared.Logic.DifficultyCurve)

local CourseLayout = require(script.Parent.CourseLayout)
local TrackShape = require(Shared.Logic.TrackShape)

-- Свой генератор у формы трассы: ворота и препятствия по старому сиду не сдвигаются.
local TRACK_SEED_SALT = 15485863
local SPECIAL_SEED_SALT = 32452843
local ATTRACTION_SEED_SALT = 49979687
local Scales = require(script.Parent.Scales)

local MathGates = {}

MathGates.id = "math_gates"
MathGates.trains = { "count" }
-- Буквы этому испытанию не нужны: оно про числа, и очередь повторений по алфавиту
-- к нему отношения не имеет.
MathGates.minLetters = 0
--[[
	Просит у ChallengeService уровень пути мира математики (Config/MathLevels):
	его ребёнок не выбирает, портал продолжает путь. Номер уровня — номер ступени счёта.
]]
MathGates.usesMathLevel = true

--[[
	Цвет числа. Он не несёт смысла — числа не различаются цветом, как буквы, —
	но одинаково серые проёмы ребёнок перестаёт различать глазами. Палитра
	повторяется по кругу: одно и то же число всегда одного цвета.
]]
local PALETTE = {
	Color3.fromRGB(240, 150, 120),
	Color3.fromRGB(130, 195, 235),
	Color3.fromRGB(160, 210, 140),
	Color3.fromRGB(235, 195, 110),
	Color3.fromRGB(195, 160, 230),
}

local function colorFor(value: number): Color3
	return PALETTE[value % #PALETTE + 1]
end

--[[
	Проёмы одних ворот: по проёму на вариант ответа.

	Точки под числом рисуются, пока ступень их просит (docs/16-MATH.md § 1,
	правило 1: сначала количество, потом значок). Больше десяти точек не рисуем
	никогда — их уже не сосчитать взглядом, а ответ выше десяти бывает только
	в умножении, где количество показано тарелками над воротами.
]]
local function buildOpenings(task, random: Random)
	local lanes = CourseLayout.lanes(random)
	local openings = {}

	for slot, value in task.answers do
		table.insert(openings, {
			lane = lanes[slot],
			value = value,
			glyph = tostring(value),
			color = colorFor(value),
			pips = if task.showPips and value <= MathConfig.MAX_NUMBER then value else 0,
			objects = task.objects,
			isTarget = value == task.answer,
		})
	end

	return openings
end

--[[
	Весы особого участка: два раунда «положи столько же». Камней не больше, чем
	позволяет ступень (Scales.topicFor) и чем считается взглядом на бегу.
	Неверные кучки — соседние количества, как у занятия «Весы».
]]
local function buildBalance(special, stage: number, choiceCount: number, random: Random)
	local _, cap = Scales.topicFor(stage)
	local maxStones = math.min(cap, Tunnel.BALANCE_MAX_STONES)
	local rounds = {}
	local previous = 0
	for index = 1, Tunnel.BALANCE_ROUNDS do
		local left = random:NextInteger(1, maxStones)
		if left == previous then
			left = left % maxStones + 1
		end
		previous = left

		local counts = Scales.choicesFor(left, math.max(2, choiceCount), maxStones, random)
		local lanes = CourseLayout.lanes(random)
		local choices = {}
		for slot, count in counts do
			table.insert(choices, { count = count, lane = lanes[slot] })
		end
		table.insert(rounds, { index = index, left = left, choices = choices })
	end
	return { segment = special.segment, z = special.z, rounds = rounds }
end

--[[
	Собирает забег по рецепту: ступень, сложность и сид.

	Как и в буквенном туннеле, функция обязана быть детерминированной — на этом
	держится сохранка. Ступень входит в рецепт наравне с сидом: за ночь ребёнок мог
	открыть следующую, и без неё он вернулся бы в туннель, похожий на свой,
	но с другими задачами.
]]
local function assemble(stage: number, difficulty: number, seed: number, resumeFrom: number)
	local spec = MathConfig.expect(stage)
	local level = MathLevels.expect(stage)

	-- Ворот столько, сколько сохранок у уровня в плане пути (docs/17-CONTENT-PLAN.md § 2).
	local gateCount = level.gates
	--[[
		Проёмов столько, сколько разрешают И сложность, И ступень, И уровень, И дорожки.
		Ступень здесь главнее сложности: на «узнавании количества» вариантов два,
		и подниматься до трёх ей нельзя, каким бы сильным ни был ребёнок.
	]]
	local choiceCount = math.min(
		DifficultyCurve.pick(Tunnel.MATH_PARAMS.choices, difficulty),
		spec.choices,
		level.maxChoices,
		Tunnel.LANE_COUNT
	)
	local obstacleCount = DifficultyCurve.pick(Tunnel.MATH_PARAMS.obstacles, difficulty)
	local obstacleTier = DifficultyCurve.pick(Tunnel.MATH_PARAMS.obstacleTier, difficulty)
	local slowSeconds = DifficultyCurve.pick(Tunnel.MATH_PARAMS.missSlowSeconds, difficulty)
	local slowFactor = DifficultyCurve.pick(Tunnel.MATH_PARAMS.missSlowFactor, difficulty)

	local random = Random.new(seed)

	--[[
		Особый участок пути математики — весы перед воротами одного из средних
		отрезков, как лестница у мира букв. Свой генератор: ворота и препятствия
		уже сохранённых забегов от него не сдвигаются.
	]]
	local specialRandom = if gateCount >= 3 then Random.new(seed + SPECIAL_SEED_SALT) else nil
	local specialSegment = if specialRandom then specialRandom:NextInteger(2, gateCount - 1) else nil

	--[[
		Аттракционы — те же, что у мира букв, но по одному на отрезок: счёт на бегу
		тяжелее узнавания буквы, и паркура здесь меньше (Config/MathLevels).
	]]
	local course = CourseLayout.layout(random, {
		gateCount = gateCount,
		obstacleCount = obstacleCount,
		obstacleTier = obstacleTier,
		specialSegment = specialSegment,
		attractions = {
			unlocked = Attractions.unlocked(level.index),
			heat = level.heat,
			perSegment = 1,
			random = Random.new(seed + ATTRACTION_SEED_SALT),
		},
		makeGate = function(_index: number, gateRandom: Random)
			local task = MathConfig.generate(stage, gateRandom, choiceCount)
			return {
				taskId = task.id,
				kind = task.kind,
				prompt = task.prompt,
				vo = task.vo,
				subtitle = MathConfig.spell(task),
				-- Равные группы и умножение показывают тарелки с предметами:
				-- ребёнок считает их, а не читает незнакомое двузначное число.
				groups = task.groups,
				each = task.each,
				objects = task.objects,
				answer = task.answer,
				openings = buildOpenings(task, gateRandom),
			}
		end,
	})

	local gates, special = course.gates, course.special
	local from = math.clamp(resumeFrom, 0, gateCount)
	local firstGate = gates[from + 1]

	return {
		challengeId = MathGates.id,
		seed = seed,
		letters = {}, -- букв в этом забеге нет вовсе
		difficulty = difficulty,
		stage = stage,
		targetCount = gateCount,
		params = {
			resumeFrom = from,
			mathStage = stage,
			mathStageId = spec.id,
			-- Уровень пути: по финишу ChallengeService засчитает его пройденным.
			mathLevel = level.index,
			mathLevelTitle = level.title,
			-- Задача первых невзятых ворот: её произносит сервер сразу после инструкции.
			taskVO = if firstGate then firstGate.vo else nil,
			taskPrompt = if firstGate then firstGate.prompt else "",
			gates = gates,
			obstacles = course.obstacles,
			checkpoints = course.checkpoints,
			attractions = course.attractions,
			length = course.length,
			-- Та же форма трассы, что у мира букв: горки и виражи на пробежках.
			track = TrackShape.plan(course.runs, seed + TRACK_SEED_SALT),
			balance = if special and specialRandom
				then buildBalance(special, stage, math.min(choiceCount, Tunnel.LANE_COUNT), specialRandom)
				else nil,
			slowSeconds = slowSeconds,
			slowFactor = slowFactor,
		},
	}
end

-- Новый забег: сид из часов, ступень — самая высокая открытая у этого ребёнка.
function MathGates.Build(_player: Player?, _letters: { string }, difficulty: number, stage: number?)
	local seed = math.floor(os.clock() * 1000) % 2 ^ 31
	return assemble(stage or 1, difficulty, seed, 0)
end

function MathGates.Rebuild(saved)
	return assemble(saved.stage or 1, saved.difficulty, saved.seed, saved.checkpoint)
end

-- Пройденные до выхода ворота засчитываются взятыми: решать их второй раз незачем.
function MathGates.Resume(state)
	local from = state.spec.params.resumeFrom or 0
	for index = 1, from do
		state.answered[index] = true
	end
	state.caught = from
end

--[[
	Проверяет прохождение ворот.

	Действие приходит от серверного триггера в туннеле, а не от клиента: клиент
	о выборе даже не знает, он просто бежит.

	Любой ответ ведёт за собой задачу следующих ворот — она произносится сразу,
	чтобы отрезок пути ушёл на решение.

	Именно любой, а не только верный. Стена не держит: через неверный проём
	ребёнок пробегает так же, как через верный, и эти ворота второй раз уже
	не спрашиваются. Раньше после ошибки повторялась та же задача — и ребёнок
	бежал к следующим воротам, где спрашивали уже другое, с чужим примером
	в голове и на экране. Подсказкой к ошибке служит число, в которое он вбежал:
	его называет клиент («это четыре»), и это не стоит ни одной новой записи.
]]
function MathGates.Validate(state, action)
	if typeof(action) ~= "table" then
		return { handled = false }
	end

	if action.kind == "finish" then
		return { handled = true, correct = false, silent = true, finished = true }
	end

	--[[
		Кучка на весах особого участка. Раунды по порядку, ошибка стоит короткой
		паузы; путь не закрывается — сервис туннеля подсвечивает верную кучку.
		В статистику освоения не идёт: считать учат ворота и занятие «Весы».
	]]
	if action.kind == "balance" then
		local balance = state.spec.params.balance
		if
			not balance
			or balance.segment <= (state.spec.params.resumeFrom or 0)
			or typeof(action.round) ~= "number"
			or typeof(action.slot) ~= "number"
		then
			return { handled = false }
		end
		local expected = (state.balanceRound or 0) + 1
		local round = balance.rounds[expected]
		if action.round ~= expected or not round then
			return { handled = false }
		end
		local choice = round.choices[action.slot]
		if not choice then
			return { handled = false }
		end
		local now = os.clock()
		if state.balanceBlockedUntil and now < state.balanceBlockedUntil then
			return { handled = false }
		end

		local correct = choice.count == round.left
		if correct then
			state.balanceRound = expected
		else
			state.balanceBlockedUntil = now + Tunnel.SPECIAL_MISS_SECONDS
		end
		return {
			handled = true,
			balance = true,
			correct = correct,
			round = expected,
			slot = action.slot,
			value = round.left,
			tappedValue = choice.count,
			cooldown = if correct then 0 else Tunnel.SPECIAL_MISS_SECONDS,
		}
	end

	if action.kind ~= "gate" or typeof(action.gateIndex) ~= "number" then
		return { handled = false }
	end

	local gates = state.spec.params.gates
	local gate = gates[action.gateIndex]
	if not gate then
		return { handled = false }
	end

	state.answered = state.answered or {}
	if state.answered[action.gateIndex] then
		return { handled = false }
	end
	state.answered[action.gateIndex] = true

	local opening
	for _, candidate in gate.openings do
		if candidate.lane == action.lane then
			opening = candidate
			break
		end
	end
	if not opening then
		return { handled = false }
	end

	local correct = opening.isTarget
	if correct then
		state.caught += 1
	else
		state.missed += 1
	end

	local following = gates[action.gateIndex + 1]

	return {
		handled = true,
		correct = correct,
		gateIndex = action.gateIndex,
		--[[
			Осваивается не буква, а ступень счёта: её id и уходит в прогресс.
			Правила освоения при этом те же самые — см. ProgressService.applyMathAnswer.
		]]
		topic = "math",
		topicId = state.spec.params.mathStageId,
		tappedValue = if correct then nil else opening.value,
		--[[
			Что произнести после реакции: задача следующих ворот. Реплика собирается
			из нескольких кусков, поэтому уходит цепочкой, а не одним ключом.
		]]
		voAfter = if following then following.vo else nil,
		nextPrompt = if following then following.prompt else "",
		cooldown = if correct then 0 else state.spec.params.slowSeconds,
		slowFactor = state.spec.params.slowFactor,
		reactionMs = math.max(0, math.floor((os.clock() - (state.gateStartedAt or state.startedAt)) * 1000)),
		finished = false, -- забег кончается на финишной черте, а не на последних воротах
	}
end

function MathGates.Finish(state)
	local total = state.spec.targetCount
	local passed = state.caught

	local stars = 1
	if passed >= total and state.missed == 0 then
		stars = 3
	elseif passed >= math.ceil(total * 0.6) then
		stars = 2
	end

	return {
		challengeId = MathGates.id,
		stars = stars,
		caught = passed,
		targetCount = total,
		wrongTaps = state.missed,
	}
end

-- Времени с запасом: ребёнок бежит сам и может остановиться подумать у каждых ворот.
function MathGates.duration(spec): number
	return spec.targetCount * 45 + 60
end

return MathGates
