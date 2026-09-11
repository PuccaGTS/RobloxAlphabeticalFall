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

	Забег бывает двух видов:
	  · уровень мира букв (docs/14-TUNNEL-MODE.md § 3.3) — «Азбучный туннель»
	    за порталом. Отрезков столько, сколько у уровня, и у каждого отрезка
	    своя буква: новые буквы ступени, потом повторение (Config/Levels);
	  · свободный забег — «Полоса препятствий» на паде. Буква одна на весь
	    забег, первая из очереди повторений.
	Правила ворот у них одни и те же; разница только в том, откуда берутся буквы.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Letters = require(Shared.Config.Letters)
local Levels = require(Shared.Config.Levels)
local Tunnel = require(Shared.Config.Tunnel)
local DifficultyCurve = require(Shared.Logic.DifficultyCurve)

local CourseLayout = require(script.Parent.CourseLayout)

local RunCourse = {}

-- Соль генератора рядов букв: у них свой Random, чтобы не сдвигать ворота и препятствия.
local ROW_SEED_SALT = 7919

--[[
	Ряд букв на дорожке перед воротами: буква этого отрезка и одна отвлекающая —
	из тех же ворот, чтобы на дорожке не появлялось букв, которых ребёнок
	на этом отрезке и не видит. Двух плиток хватает: ряд — не задача, а «монетка»,
	и ребёнок должен успеть свернуть к нужной на бегу.
]]
local function makeRow(gate, _random: Random)
	local target = Letters.expect(gate.targetLetter)
	local items = {
		{ letterId = target.id, glyph = target.glyph, color = target.color, isTarget = true },
	}
	for _, opening in gate.openings do
		if not opening.isTarget and opening.letterId ~= target.id then
			local other = Letters.expect(opening.letterId)
			table.insert(
				items,
				{ letterId = other.id, glyph = other.glyph, color = other.color, isTarget = false }
			)
			break
		end
	end
	return items
end

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
	options.levels — забег идёт по уровням мира букв (Config/Levels).
]]
function RunCourse.new(id: string, params, options: { levels: boolean? }?)
	local Module = {}
	local usesLevels = options ~= nil and options.levels == true

	Module.id = id
	Module.trains = { "recognize" }
	Module.minLetters = 2
	-- Просит у ChallengeService уровень мира букв: его выбирает не ребёнок, а пройденный путь.
	Module.usesLevel = usesLevels

	--[[
		Собирает план забега по рецепту: буквы, сложность, сид и — у уровня — его номер.

		Функция обязана быть детерминированной. На этом держится сохранка:
		вернувшийся назавтра ребёнок получает тот же самый туннель, потому что
		в профиле лежит не геометрия, а эти несколько чисел (см. Types.SavedRun).
		Ничего случайного, кроме Random.new(seed), здесь появляться не должно.

		letters — очередь повторений. У свободного забега первая буква становится
		целью на весь забег; у уровня из очереди берётся повторение для отрезков
		после новых букв.

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

		local level = if usesLevels then Levels.get(levelIndex) else nil
		assert(level or not usesLevels, `{id}: нет уровня {tostring(levelIndex)}`)

		--[[
			У уровня отрезков столько, сколько записано в нём самом: длина пути —
			часть уровня, а не настроение адаптивной сложности. Проёмов же столько,
			сколько разрешают сразу и сложность, и уровень, и дорожки.
		]]
		local gateCount = if level then level.segments else DifficultyCurve.pick(params.gates, difficulty)
		local choiceCount = math.min(DifficultyCurve.pick(params.choices, difficulty), Tunnel.LANE_COUNT)
		if level then
			choiceCount = math.min(choiceCount, level.maxChoices)
		end
		--[[
			Паркур уровня растёт вместе с путём (docs/19-OBSTACLES.md § 3.3): сколько
			элементов и какого ряда, решает уровень, а сложность двигает внутри его рамок.
			Свободный забег (полоса препятствий на паде) живёт по одной сложности.
		]]
		local obstacleCount = if level
			then Levels.obstacleCount(level.index, difficulty)
			else DifficultyCurve.pick(params.obstacles, difficulty)
		local obstacleTier = DifficultyCurve.pick(params.obstacleTier, difficulty)
		if level then
			obstacleTier = Levels.obstacleTier(level.index, obstacleTier)
		end
		local slowSeconds = DifficultyCurve.pick(params.missSlowSeconds, difficulty)
		local slowFactor = DifficultyCurve.pick(params.missSlowFactor, difficulty)

		local targets: { string }
		if level then
			targets = Levels.targets(level.index, letters)
		else
			targets = table.create(gateCount, letters[1])
		end

		-- Отвлекающие буквы свободного забега: остаток очереди, а если его нет — весь алфавит.
		local distractorPool: { string } = {}
		for index = 2, #letters do
			if letters[index] ~= letters[1] then
				table.insert(distractorPool, letters[index])
			end
		end
		if #distractorPool == 0 then
			for _, other in Letters.ordered() do
				if other ~= letters[1] then
					table.insert(distractorPool, other)
				end
			end
		end

		local random = Random.new(seed)

		local gates, obstacles, checkpoints, length, rows = CourseLayout.layout(random, {
			gateCount = gateCount,
			obstacleCount = obstacleCount,
			obstacleTier = obstacleTier,
			rowsPerSegment = if params.collect then DifficultyCurve.pick(params.collect, difficulty) else 0,
			rowRandom = Random.new(seed + ROW_SEED_SALT),
			makeRow = makeRow,
			makeGate = function(index: number, gateRandom: Random)
				local targetId = targets[index]
				local target = Letters.expect(targetId)

				local openings
				if level then
					local picked = levelDistractors(level.index, targetId, gateRandom, choiceCount - 1)
					local taken = 0
					openings = buildOpenings(gateRandom, #picked + 1, targetId, function()
						taken += 1
						return picked[taken]
					end)
				else
					openings = buildOpenings(gateRandom, choiceCount, targetId, function()
						return distractorPool[gateRandom:NextInteger(1, #distractorPool)]
					end)
				end

				return {
					-- Буква отрезка живёт в самих воротах: у уровня она своя на каждом отрезке.
					targetLetter = targetId,
					targetGlyph = target.glyph,
					targetVO = target.vo.name,
					openings = openings,
				}
			end,
		})

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
			level = if level then level.index else nil,
			targetCount = gateCount,
			params = {
				resumeFrom = from,
				targetLetter = current.targetLetter,
				targetGlyph = current.targetGlyph,
				targetVO = current.targetVO,
				gates = gates,
				obstacles = obstacles,
				checkpoints = checkpoints,
				rows = rows,
				length = length,
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
			Буква на дорожке. Засчитывается только буква своего отрезка и только
			один раз; отвлекающая плитка триггера не имеет вовсе, и пробежать сквозь
			неё ничего не стоит. Ряды пройденных до выхода отрезков не собираются:
			их «монетки» уже взяты или упущены тогда.

			Это не ответ: в статистику освоения подбор не идёт. Пробежать по букве
			можно и случайно, а отчёт родителю должен знать только решения в воротах.
		]]
		if action.kind == "collect" then
			local row = (state.spec.params.rows or {})[action.row]
			local item = row and row.items[action.slot]
			if not item or not item.isTarget or row.segment <= (state.spec.params.resumeFrom or 0) then
				return { handled = false }
			end
			state.collected = state.collected or {}
			if state.collected[row.index] then
				return { handled = false }
			end
			state.collected[row.index] = true
			return {
				handled = true,
				collect = true,
				letterId = item.letterId,
				row = row.index,
				slot = action.slot,
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

		return {
			handled = true,
			correct = correct,
			gateIndex = action.gateIndex,
			letterId = gate.targetLetter,
			tappedLetterId = if correct then nil else opening.letterId,
			-- Новая буква следующего отрезка: её название звучит сразу после реакции.
			nextLetter = if changes then nextGate.targetLetter else nil,
			nextGlyph = if changes then nextGate.targetGlyph else nil,
			voAfter = if changes then { nextGate.targetVO } else nil,
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
