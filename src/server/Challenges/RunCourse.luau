--!nonstrict
--[[
	План забега мира букв — «Азбучный туннель» за порталом.
	См. docs/14-TUNNEL-MODE.md и docs/19-OBSTACLES.md.

	Модуль отвечает за буквы на воротах и станциях и за правила. Расстояния,
	препятствия и аттракционы раскладывает CourseLayout — он же обслуживает
	ворота с числами. Геометрию из плана строит TunnelService.

	Забег — это уровень мира букв (docs/14-TUNNEL-MODE.md § 3.3): отрезков
	столько, сколько у уровня, и у каждого отрезка своя буква — новые буквы
	ступени, потом повторение (Config/Levels).

	Раньше рядом жил «свободный забег» — «Полоса препятствий» на паде, с одной
	буквой на весь забег. Её пад занял «Пол — это лава!» (Challenges/LavaFloor):
	полосу не отличали от портала.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Letters = require(Shared.Config.Letters)
local Levels = require(Shared.Config.Levels)
local Attractions = require(Shared.Config.Attractions)
local Tunnel = require(Shared.Config.Tunnel)
local DifficultyCurve = require(Shared.Logic.DifficultyCurve)

local CourseLayout = require(script.Parent.CourseLayout)
local TrackShape = require(Shared.Logic.TrackShape)

local RunCourse = {}

-- Соль генератора секрета уровня: у него свой Random, чтобы не сдвигать ворота и препятствия.
local SECRET_SEED_SALT = 104729
-- Свой генератор у формы трассы: иначе сдвинулись бы ворота уже сохранённых забегов.
local TRACK_SEED_SALT = 15485863
local ATTRACTION_SEED_SALT = 49979687

--[[
	Отвлекающие буквы уровня: по группам из Config/Levels, каждая перемешана
	сидом забега. Повторов в одних воротах нет — две одинаковые буквы в соседних
	проёмах выглядят как ошибка игры, а не как выбор.
]]
local function levelDistractors(
	levelIndex: number,
	targetId: string,
	random: Random,
	count: number
): { string }
	local picked: { string } = {}
	for _, group in Levels.distractorGroups(levelIndex, targetId) do
		for _, id in CourseLayout.shuffled(group, random) do
			if #picked >= count then
				return picked
			end
			table.insert(picked, id)
		end
	end
	return picked
end

local function buildOpenings(random: Random, choiceCount: number, targetId: string, distractors: () -> string)
	-- Дорожки для проёмов выбираем случайно, но целевая буква обязана
	-- оказаться на одной из них.
	local lanes = CourseLayout.lanes(random)

	local openings = {}
	local targetSlot = random:NextInteger(1, choiceCount)

	for slot = 1, choiceCount do
		local letterId = if slot == targetSlot then targetId else distractors()
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
	params — блок параметров из Config/Tunnel,
]]
function RunCourse.new(id: string, params)
	local Module = {}

	Module.id = id
	Module.trains = { "recognize" }
	Module.minLetters = 2
	-- Просит у ChallengeService уровень мира букв: его выбирает не ребёнок, а пройденный путь.
	Module.usesLevel = true

	--[[
		Собирает план забега по рецепту: буквы, сложность, сид и — у уровня — его номер.

		Функция обязана быть детерминированной. На этом держится сохранка:
		вернувшийся назавтра ребёнок получает тот же самый туннель, потому что
		в профиле лежит не геометрия, а эти несколько чисел (см. Types.SavedRun).
		Ничего случайного, кроме Random.new(seed), здесь появляться не должно.

		letters — очередь повторений: из неё берётся повторение для отрезков
		после новых букв уровня.

		resumeFrom — с какой сохранки продолжаем. 0 — забег с начала.
	]]
	local function assemble(
		letters: { string },
		difficulty: number,
		seed: number,
		resumeFrom: number,
		levelIndex: number?
	)
		assert(#letters >= Module.minLetters, `{id}: нужно минимум две буквы`)

		local level = Levels.get(levelIndex)
		assert(level, `{id}: нет уровня {tostring(levelIndex)}`)

		--[[
			У уровня отрезков столько, сколько записано в нём самом: длина пути —
			часть уровня, а не настроение адаптивной сложности. Проёмов же столько,
			сколько разрешают сразу и сложность, и уровень, и дорожки.
		]]
		local gateCount = level.segments
		local choiceCount =
			math.min(DifficultyCurve.pick(params.choices, difficulty), Tunnel.LANE_COUNT, level.maxChoices)
		--[[
			Паркур уровня растёт вместе с путём (docs/19-OBSTACLES.md § 3.3): сколько
			элементов и какого ряда, решает уровень, а сложность двигает внутри его рамок.
		]]
		local obstacleCount = Levels.obstacleCount(level.index, difficulty)
		local obstacleTier =
			Levels.obstacleTier(level.index, DifficultyCurve.pick(params.obstacleTier, difficulty))
		local slowSeconds = DifficultyCurve.pick(params.missSlowSeconds, difficulty)
		local slowFactor = DifficultyCurve.pick(params.missSlowFactor, difficulty)

		local targets = Levels.targets(level.index, letters)

		local random = Random.new(seed)

		--[[
			Секрет уровня (docs/18-CONTENT-BACKLOG.md § 8): золотая буква ступени
			на постаменте в стороне от пути.
		]]
		local secretRandom = Random.new(seed + SECRET_SEED_SALT)
		local secretSegment = secretRandom:NextInteger(1, gateCount)

		-- Аттракционы: у уровня сила и число — свои (Config/Levels).
		local heat, perSegment = Levels.attractions(level.index)

		local course = CourseLayout.layout(random, {
			gateCount = gateCount,
			obstacleCount = obstacleCount,
			obstacleTier = obstacleTier,
			secretSegment = secretSegment,
			secretRandom = secretRandom,
			stations = true,
			attractions = {
				unlocked = Attractions.unlocked(level.index),
				heat = heat,
				perSegment = perSegment,
				random = Random.new(seed + ATTRACTION_SEED_SALT),
			},
			makeGate = function(index: number, gateRandom: Random)
				local targetId = targets[index]
				local target = Letters.expect(targetId)

				local picked = levelDistractors(level.index, targetId, gateRandom, choiceCount - 1)
				local taken = 0
				local openings = buildOpenings(gateRandom, #picked + 1, targetId, function()
					taken += 1
					return picked[taken]
				end)

				return {
					-- Буква отрезка живёт в самих воротах: у уровня она своя на каждом отрезке.
					targetLetter = targetId,
					targetGlyph = target.glyph,
					targetVO = target.vo.name,
					openings = openings,
				}
			end,
		})

		local gates, secret = course.gates, course.secret

		-- Станция показывает и называет букву своего отрезка — ту, что спросят ворота.
		for _, station in course.stations do
			local letter = Letters.expect(gates[station.segment].targetLetter)
			station.letterId = letter.id
			station.glyph = letter.glyph
			station.color = letter.color
			station.vo = letter.vo.name
		end

		if secret then
			local fresh = Levels.stage(level.index).letters
			local letter = Letters.expect(fresh[secretRandom:NextInteger(1, #fresh)])
			secret.letterId = letter.id
			secret.glyph = letter.glyph
		end

		--[[
			Сколько сохранок уже пройдено: столько же ворот считаются взятыми,
			и с этой точки TunnelService поставит ребёнка в туннель. Буква-цель
			на старте — буква первых невзятых ворот, а не первых вообще.
		]]
		local from = math.clamp(resumeFrom, 0, gateCount)
		local current = gates[from + 1] or gates[#gates]

		return {
			challengeId = id,
			seed = seed,
			letters = table.clone(letters),
			difficulty = difficulty,
			level = level.index,
			targetCount = gateCount,
			params = {
				resumeFrom = from,
				targetLetter = current.targetLetter,
				targetGlyph = current.targetGlyph,
				targetVO = current.targetVO,
				gates = gates,
				obstacles = course.obstacles,
				checkpoints = course.checkpoints,
				stations = course.stations,
				attractions = course.attractions,
				secret = secret,
				length = course.length,
				track = TrackShape.plan(course.runs, seed + TRACK_SEED_SALT),
				slowSeconds = slowSeconds,
				slowFactor = slowFactor,
			},
		}
	end

	--[[
		Новый забег: сид берётся из часов, дальше он живёт в профиле вместе с сохранкой.
		level — уровень мира букв; свободному забегу он не нужен, и тот его не читает.
	]]
	function Module.Build(_player: Player?, letters: { string }, difficulty: number, level: number?)
		local seed = math.floor(os.clock() * 1000) % 2 ^ 31
		return assemble(letters, difficulty, seed, 0, level)
	end

	--[[
		Восстанавливает незаконченный забег из профиля: тот же сид, те же буквы,
		та же сложность, тот же уровень — значит, тот же туннель, только начатый
		с сохранки.

		Сложность берём сохранённую, а не сегодняшнюю: иначе за ночь мог смениться
		размер плана, и ребёнок вернулся бы в туннель, похожий на свой, но другой.
		Уровень — по той же причине: пройди ребёнок следующий уровень на другом
		устройстве, эта сохранка всё равно ведёт в свой.
	]]
	function Module.Rebuild(saved)
		return assemble(saved.letters, saved.difficulty, saved.seed, saved.checkpoint, saved.level)
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

		Ворота пройдены в любом случае — и через верный проём, и через неверный:
		стена не держит, ошибка стоит только замедления. Поэтому следующая буква
		объявляется после любого ответа, если она сменилась. Иначе ребёнок,
		ошибившийся на последних воротах отрезка, бежал бы к новым воротам
		со старой буквой в голове.
	]]
	function Module.Validate(state, action)
		if typeof(action) ~= "table" then
			return { handled = false }
		end

		if action.kind == "finish" then
			return { handled = true, correct = false, silent = true, finished = true }
		end

		--[[
			Секрет уровня: коснулся золотой буквы на постаменте. Один раз за забег;
			один раз навсегда — это уже забота ProgressService, он помнит найденные.
			В пройденном до выхода отрезке секрета нет: туда ребёнок не вернётся.
		]]
		if action.kind == "secret" then
			local secret = state.spec.params.secret
			if
				not secret
				or secret.found
				or state.secretTaken
				or secret.segment <= (state.spec.params.resumeFrom or 0)
			then
				return { handled = false }
			end
			state.secretTaken = true
			return { handled = true, secret = true, letterId = secret.letterId }
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
		state.answered[action.gateIndex] = true

		local correct = opening.isTarget
		if correct then
			state.caught += 1
		else
			state.missed += 1
		end

		local nextGate = gates[action.gateIndex + 1]
		local changes = nextGate ~= nil and nextGate.targetLetter ~= gate.targetLetter
		-- Где есть станции, новую букву называет станция: два раза подряд — это шум.
		local hasStations = #(state.spec.params.stations or {}) > 0

		return {
			handled = true,
			correct = correct,
			gateIndex = action.gateIndex,
			letterId = gate.targetLetter,
			tappedLetterId = if correct then nil else opening.letterId,
			-- Новая буква следующего отрезка: её название звучит сразу после реакции.
			nextLetter = if changes then nextGate.targetLetter else nil,
			nextGlyph = if changes then nextGate.targetGlyph else nil,
			voAfter = if changes and not hasStations then { nextGate.targetVO } else nil,
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
