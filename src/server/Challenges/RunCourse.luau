--!nonstrict
--[[
	Общий план забега: и «Азбучный туннель», и «Полоса препятствий».
	См. docs/14-TUNNEL-MODE.md и docs/19-OBSTACLES.md.

	Оба режима — это один и тот же коридор с воротами и препятствиями, отличаются
	они только пропорциями: в туннеле ворота часто и препятствий мало, на полосе
	наоборот. Держать под это два похожих модуля значило бы чинить каждую ошибку
	дважды, поэтому здесь фабрика, а рядом — две тонкие обёртки.

	Модуль отвечает за буквы на воротах и за правила. Расстояния и препятствия
	раскладывает CourseLayout — он же обслуживает ворота с числами. Геометрию
	из плана строит TunnelService.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Letters = require(Shared.Config.Letters)
local Tunnel = require(Shared.Config.Tunnel)
local DifficultyCurve = require(Shared.Logic.DifficultyCurve)

local CourseLayout = require(script.Parent.CourseLayout)

local RunCourse = {}

local function buildOpenings(random: Random, choiceCount: number, targetId: string, pool: { string })
	-- Дорожки для проёмов выбираем случайно, но целевая буква обязана
	-- оказаться на одной из них.
	local lanes = CourseLayout.lanes(random)

	local openings = {}
	local targetSlot = random:NextInteger(1, choiceCount)

	for slot = 1, choiceCount do
		local letterId = if slot == targetSlot then targetId else pool[random:NextInteger(1, #pool)]
		local letter = Letters.expect(letterId)

		table.insert(openings, {
			lane = lanes[slot],
			letterId = letterId,
			glyph = letter.glyph,
			-- Цвет кладём в план, а не ищем по букве в TunnelService: ворота с числами
			-- буквы не знают, а строит те и другие один и тот же код.
			color = letter.color,
			isTarget = slot == targetSlot,
		})
	end

	return openings
end

--[[
	Создаёт модуль испытания-забега.

	id — идентификатор испытания (он же ключ в Config/Challenges),
	params — блок параметров из Config/Tunnel.
]]
function RunCourse.new(id: string, params)
	local Module = {}

	Module.id = id
	Module.trains = { "recognize" }
	Module.minLetters = 2

	--[[
		Собирает план забега по рецепту: буквы, сложность и сид.

		Функция обязана быть детерминированной. На этом держится сохранка:
		вернувшийся назавтра ребёнок получает тот же самый туннель, потому что
		в профиле лежит не геометрия, а эти три числа (см. Types.SavedRun).
		Ничего случайного, кроме Random.new(seed), здесь появляться не должно.

		letters — очередь повторений. Первая буква становится главной целью забега:
		один забег — одна буква, чтобы ребёнок успел с ней освоиться.

		resumeFrom — с какой сохранки продолжаем. 0 — забег с начала.
	]]
	local function assemble(letters: { string }, difficulty: number, seed: number, resumeFrom: number)
		assert(#letters >= Module.minLetters, `{id}: нужно минимум две буквы`)

		local gateCount = DifficultyCurve.pick(params.gates, difficulty)
		local choiceCount = math.min(DifficultyCurve.pick(params.choices, difficulty), Tunnel.LANE_COUNT)
		local obstacleCount = DifficultyCurve.pick(params.obstacles, difficulty)
		local obstacleTier = DifficultyCurve.pick(params.obstacleTier, difficulty)
		local slowSeconds = DifficultyCurve.pick(params.missSlowSeconds, difficulty)
		local slowFactor = DifficultyCurve.pick(params.missSlowFactor, difficulty)

		local targetId = letters[1]

		local distractorPool: { string } = {}
		for index = 2, #letters do
			table.insert(distractorPool, letters[index])
		end
		if #distractorPool == 0 then
			for _, other in Letters.ordered() do
				if other ~= targetId then
					table.insert(distractorPool, other)
				end
			end
		end

		local random = Random.new(seed)

		local gates, obstacles, checkpoints, length = CourseLayout.layout(random, {
			gateCount = gateCount,
			obstacleCount = obstacleCount,
			obstacleTier = obstacleTier,
			makeGate = function(_index: number, gateRandom: Random)
				return { openings = buildOpenings(gateRandom, choiceCount, targetId, distractorPool) }
			end,
		})

		return {
			challengeId = id,
			seed = seed,
			letters = table.clone(letters),
			difficulty = difficulty,
			targetCount = gateCount,
			params = {
				-- Сколько сохранок уже пройдено: столько же ворот считаются взятыми,
				-- и с этой точки TunnelService поставит ребёнка в туннель.
				resumeFrom = math.clamp(resumeFrom, 0, gateCount),
				targetLetter = targetId,
				targetGlyph = Letters.expect(targetId).glyph,
				targetVO = Letters.expect(targetId).vo.name,
				gates = gates,
				obstacles = obstacles,
				checkpoints = checkpoints,
				length = length,
				slowSeconds = slowSeconds,
				slowFactor = slowFactor,
			},
		}
	end

	-- Новый забег: сид берётся из часов, дальше он живёт в профиле вместе с сохранкой.
	function Module.Build(_player: Player?, letters: { string }, difficulty: number)
		local seed = math.floor(os.clock() * 1000) % 2 ^ 31
		return assemble(letters, difficulty, seed, 0)
	end

	--[[
		Восстанавливает незаконченный забег из профиля: тот же сид, те же буквы,
		та же сложность — значит, тот же туннель, только начатый с сохранки.

		Сложность берём сохранённую, а не сегодняшнюю: иначе за ночь мог смениться
		размер плана, и ребёнок вернулся бы в туннель, похожий на свой, но другой.
	]]
	function Module.Rebuild(saved)
		return assemble(saved.letters, saved.difficulty, saved.seed, saved.checkpoint)
	end

	--[[
		Пройденные до выхода ворота засчитываются взятыми: ребёнок их уже решил,
		и просить решить те же ворота второй раз значит отнять сделанное.

		Награда за них при этом уже начислена тогда же — повторно она не идёт:
		звёздочки платятся за ответ, а ответов на этом отрезке больше не будет.
	]]
	function Module.Resume(state)
		local from = state.spec.params.resumeFrom or 0
		for index = 1, from do
			state.answered[index] = true
		end
		state.caught = from
	end

	--[[
		Проверяет прохождение ворот.

		Действие приходит НЕ от клиента, а от серверного триггера в туннеле
		(TunnelService ловит касание проёма). Клиенту здесь верить не нужно вовсе.

		Падения и сохранки сюда не попадают: они про геометрию, а не про буквы,
		и живут целиком в TunnelService. Обучающий прогресс от них не зависит.
	]]
	function Module.Validate(state, action)
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

		-- Одни ворота засчитываются один раз: ребёнок может потоптаться в проёме.
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

		return {
			handled = true,
			correct = correct,
			gateIndex = action.gateIndex,
			letterId = state.spec.params.targetLetter,
			tappedLetterId = if correct then nil else opening.letterId,
			cooldown = if correct then 0 else state.spec.params.slowSeconds,
			slowFactor = state.spec.params.slowFactor,
			reactionMs = math.max(
				0,
				math.floor((os.clock() - (state.gateStartedAt or state.startedAt)) * 1000)
			),
			finished = false, -- забег заканчивается на финишной черте, а не на последних воротах
		}
	end

	function Module.Finish(state)
		local total = state.spec.targetCount
		local passed = state.caught

		local stars = 1
		if passed >= total and state.missed == 0 then
			stars = 3
		elseif passed >= math.ceil(total * 0.6) then
			stars = 2
		end

		return {
			challengeId = id,
			stars = stars,
			caught = passed,
			targetCount = total,
			wrongTaps = state.missed,
		}
	end

	-- Времени с запасом: ребёнок бежит сам и может остановиться подумать у каждых ворот.
	function Module.duration(spec): number
		return spec.targetCount * 45 + 60
	end

	return Module
end

return RunCourse
