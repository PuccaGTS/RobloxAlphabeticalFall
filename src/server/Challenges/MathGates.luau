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
local Tunnel = require(Shared.Config.Tunnel)
local DifficultyCurve = require(Shared.Logic.DifficultyCurve)

local CourseLayout = require(script.Parent.CourseLayout)

local MathGates = {}

MathGates.id = "math_gates"
MathGates.trains = { "count" }
-- Буквы этому испытанию не нужны: оно про числа, и очередь повторений по алфавиту
-- к нему отношения не имеет.
MathGates.minLetters = 0
-- Просит у ChallengeService открытую ступень счёта: её ребёнок не выбирает.
MathGates.usesMathStage = true

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
	Собирает забег по рецепту: ступень, сложность и сид.

	Как и в буквенном туннеле, функция обязана быть детерминированной — на этом
	держится сохранка. Ступень входит в рецепт наравне с сидом: за ночь ребёнок мог
	открыть следующую, и без неё он вернулся бы в туннель, похожий на свой,
	но с другими задачами.
]]
local function assemble(stage: number, difficulty: number, seed: number, resumeFrom: number)
	local spec = MathConfig.expect(stage)

	local gateCount = DifficultyCurve.pick(Tunnel.MATH_PARAMS.gates, difficulty)
	--[[
		Проёмов столько, сколько разрешают И сложность, И ступень, И дорожки.
		Ступень здесь главнее сложности: на «узнавании количества» вариантов два,
		и подниматься до трёх ей нельзя, каким бы сильным ни был ребёнок.
	]]
	local choiceCount = math.min(
		DifficultyCurve.pick(Tunnel.MATH_PARAMS.choices, difficulty),
		spec.choices,
		Tunnel.LANE_COUNT
	)
	local obstacleCount = DifficultyCurve.pick(Tunnel.MATH_PARAMS.obstacles, difficulty)
	local obstacleTier = DifficultyCurve.pick(Tunnel.MATH_PARAMS.obstacleTier, difficulty)
	local slowSeconds = DifficultyCurve.pick(Tunnel.MATH_PARAMS.missSlowSeconds, difficulty)
	local slowFactor = DifficultyCurve.pick(Tunnel.MATH_PARAMS.missSlowFactor, difficulty)

	local random = Random.new(seed)

	local gates, obstacles, checkpoints, length = CourseLayout.layout(random, {
		gateCount = gateCount,
		obstacleCount = obstacleCount,
		obstacleTier = obstacleTier,
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
			-- Задача первых невзятых ворот: её произносит сервер сразу после инструкции.
			taskVO = if firstGate then firstGate.vo else nil,
			taskPrompt = if firstGate then firstGate.prompt else "",
			gates = gates,
			obstacles = obstacles,
			checkpoints = checkpoints,
			length = length,
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
