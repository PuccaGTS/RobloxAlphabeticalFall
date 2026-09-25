--!strict
--[[
	Уровни мира букв: путь, который продолжает портал. См. docs/14-TUNNEL-MODE.md § 3.3
	и docs/17-CONTENT-PLAN.md § 1.

	Уровень — это ступень алфавита, разложенная на отрезки пути:

	  [паркур] → [ворота] → [🚩 сохранка] → [паркур] → [ворота] → [🚩] → … → ФИНИШ

	На каждом отрезке ворота спрашивают одну букву. Первые три отрезка — три новые
	буквы ступени по алфавиту, остальные — повторение уже открытых. Буква держится
	весь отрезок, а не меняется от ворот к воротам: ребёнок успевает с ней освоиться,
	и правило «одна буква за раз» сохраняется, просто теперь оно про отрезок, а не
	про весь забег.

	Уровень открывается, когда пройден предыдущий, — по финишу, а не по статусам
	букв. Статусы требуют успехов в двух разных испытаниях, и ребёнок, которому
	нравится только портал, упёрся бы в первый уровень навсегда. Тупика быть
	не должно ни при каких условиях. Ступени алфавита при этом живут как жили:
	пады площади и Башня по-прежнему открывают буквы по освоению.

	Номер уровня совпадает с номером ступени: одиннадцать ступеней — одиннадцать
	уровней. Это держится тестом.
]]

local Types = require(script.Parent.Parent.Types)
local DifficultyCurve = require(script.Parent.Parent.Logic.DifficultyCurve)
local Letters = require(script.Parent.Letters)
local Stages = require(script.Parent.Stages)
local MathConfig = require(script.Parent.Math)

export type Level = {
	index: number, -- он же номер ступени алфавита
	segments: number, -- сколько отрезков, они же сохранки и ворота
	--[[
		Сколько проёмов в воротах самое большее. Точное число решает адаптивная
		сложность, уровень только ограничивает сверху: на первом уровне выбор
		из двух, каким бы уверенным ни был ребёнок.

		В docs/17 для поздних уровней написано «из 4», но дорожек три
		(docs/14-TUNNEL-MODE.md § 5), и четвёртому проёму негде встать.
	]]
	maxChoices: number,
	--[[
		Паркур уровня (docs/19-OBSTACLES.md § 3.3): сколько элементов на отрезке
		и до какого ряда. Мелкие элементы — связка между станцией буквы
		и аттракционом, их два-шесть, а не шесть-четырнадцать, как было.
	]]
	obstacles: { number }, -- { меньше, больше }: точное число добавляет сложность
	maxTier: number,
	--[[
		Аттракционы уровня (Config/Attractions): жар от 1 до 5 и сколько их
		на отрезке. Мелких элементов стало втрое меньше, чем было: на первой
		живой проверке их назвали «вообще не вызывают трудностей», а отрезок —
		«бежать очень много». Трудность теперь несут аттракционы во всю ширину
		трассы, а мелочь только связывает их.
	]]
	heat: number,
	attractions: number,
}

local Levels = {}

--[[
	Раскладка после проверки 24.09.2026: «первые полосы однообразные, скучные,
	долго бежать, препятствий никаких — можно просто бежать прямо», «А-Б-В и Г-Д-Е
	абсолютно одинаковые». Поэтому:
	  · первые уровни короче: три отрезка — по одному на каждую новую букву;
	  · на каждом отрезке два аттракциона во всю ширину трассы, а не один:
	    бежать прямо нельзя, между станцией и воротами всегда есть где упасть;
	  · жар с двух: островки на первом уровне уже требуют прыжка, а не шага;
	  · мелких элементов меньше — их обходят соседней дорожкой, трудности они
	    не дают, только удлиняют путь;
	  · новые аттракционы открываются почти на каждом уровне (Config/Attractions),
	    и самый новый встречает первым — уровни не похожи друг на друга.
]]
Levels.all = {
	{ index = 1, segments = 3, maxChoices = 2, obstacles = { 1, 2 }, maxTier = 1, heat = 2, attractions = 2 },
	{ index = 2, segments = 3, maxChoices = 3, obstacles = { 1, 2 }, maxTier = 1, heat = 2, attractions = 2 },
	{ index = 3, segments = 3, maxChoices = 3, obstacles = { 1, 2 }, maxTier = 1, heat = 3, attractions = 2 },
	{ index = 4, segments = 4, maxChoices = 3, obstacles = { 1, 2 }, maxTier = 1, heat = 3, attractions = 2 },
	{ index = 5, segments = 4, maxChoices = 3, obstacles = { 1, 3 }, maxTier = 2, heat = 3, attractions = 2 },
	{ index = 6, segments = 4, maxChoices = 3, obstacles = { 1, 3 }, maxTier = 2, heat = 4, attractions = 2 },
	{ index = 7, segments = 4, maxChoices = 3, obstacles = { 2, 3 }, maxTier = 3, heat = 4, attractions = 2 },
	{ index = 8, segments = 5, maxChoices = 3, obstacles = { 2, 3 }, maxTier = 3, heat = 4, attractions = 2 },
	{ index = 9, segments = 5, maxChoices = 3, obstacles = { 2, 4 }, maxTier = 3, heat = 5, attractions = 2 },
	{
		index = 10,
		segments = 5,
		maxChoices = 3,
		obstacles = { 2, 4 },
		maxTier = 3,
		heat = 5,
		attractions = 3,
	},
	{
		index = 11,
		segments = 5,
		maxChoices = 3,
		obstacles = { 2, 4 },
		maxTier = 3,
		heat = 5,
		attractions = 3,
	},
} :: { Level }

-- Сколько элементов добавляет адаптивная сложность к нижней границе уровня.
Levels.OBSTACLE_BONUS = { 0, 0, 1, 1, 2 }

--[[
	До какого уровня похожие по начертанию буквы (Б/В, И/Й, Е/Ё) не встают в одни
	ворота (docs/02-LEARNING.md § 6). Первые четыре уровня — это первая играбельная
	версия (docs/17-CONTENT-PLAN.md § 6): там ребёнок только знакомится с буквами,
	и путать его парой рано. Дальше пара в воротах — это уже тренировка различения.
]]
Levels.CONFUSABLES_APART_UNTIL = 4

-- Мир, чей путь описывают эти уровни. Ключ в Profile.levels.
Levels.WORLD = "letters"
-- Ключ пути мира математики (Config/MathLevels): его уровни — ступени счёта.
Levels.MATH_WORLD = "math"

function Levels.count(): number
	return #Levels.all
end

function Levels.get(index: any): Level?
	if typeof(index) ~= "number" then
		return nil
	end
	return Levels.all[index]
end

function Levels.expect(index: number): Level
	local level = Levels.get(index)
	assert(level, `Levels: нет уровня {index}`)
	return level
end

--[[
	Сколько элементов паркура на отрезке уровня. Нижняя граница — от уровня,
	надбавка — от адаптивной сложности, и выше верхней границы не бывает:
	уверенный ребёнок на первом уровне получит два барьера, а не шесть.
]]
function Levels.obstacleCount(index: number, difficulty: number): number
	local level = Levels.expect(index)
	local bonus = DifficultyCurve.pick(Levels.OBSTACLE_BONUS, difficulty)
	return math.clamp(level.obstacles[1] + bonus, level.obstacles[1], level.obstacles[2])
end

-- Какие аттракционы и какой силы встают на уровне (Config/Attractions).
function Levels.attractions(index: number): (number, number)
	local level = Levels.expect(index)
	return level.heat, level.attractions
end

-- До какого ряда элементы: сложность разрешает, уровень ограничивает.
function Levels.obstacleTier(index: number, difficultyTier: number): number
	return math.min(difficultyTier, Levels.expect(index).maxTier)
end

function Levels.stage(index: number): Types.Stage
	return Stages.expect(Levels.expect(index).index)
end

--[[
	Какой уровень играет портал, если пройдено cleared уровней подряд.

	Следующий за пройденным, а когда пройдены все — последний: путь закончился,
	и портал возвращает на него для повторения, а не выбрасывает ребёнка в пустоту
	(docs/14-TUNNEL-MODE.md § 3.2).
]]
function Levels.current(cleared: any): number
	local done = if typeof(cleared) == "number" then math.floor(cleared) else 0
	return math.clamp(done + 1, 1, Levels.count())
end

--[[
	Буква каждого отрезка, по порядку.

	Сначала новые буквы ступени по алфавиту, потом повторение: буквы из очереди
	планировщика, стоящие на более ранних ступенях, в том порядке, в каком
	их просит очередь. На первом уровне повторять нечего, и по кругу идут
	его же три буквы.

	queue — очередь повторений из рецепта забега. Функция детерминирована:
	одна и та же очередь даёт одни и те же буквы, на этом держится сохранка.
]]
function Levels.targets(index: number, queue: { string }): { string }
	local level = Levels.expect(index)
	local fresh = Levels.stage(index).letters

	local review: { string } = {}
	local seen: { [string]: boolean } = {}
	for _, id in queue do
		local letter = Letters.get(id)
		if letter and letter.stage < level.index and not seen[id] then
			seen[id] = true
			table.insert(review, id)
		end
	end
	if #review == 0 then
		review = fresh
	end

	local targets: { string } = {}
	for segment = 1, level.segments do
		if segment <= #fresh then
			table.insert(targets, fresh[segment])
		else
			table.insert(targets, review[(segment - #fresh - 1) % #review + 1])
		end
	end
	return targets
end

--[[
	Кем можно окружить букву в воротах, по убыванию желательности.

	  1. Буквы той же ступени: ворота предлагают выбор, не подмешивая чужих ступеней
	     (docs/02-LEARNING.md § 2).
	  2. Остальные открытые на этом уровне буквы — если своих не хватило.
	  3. Похожие по начертанию — на первых уровнях только в крайнем случае.

	Порядок внутри групп не случайный: перемешивает забег своим сидом.
	Буквы дальше ступени уровня сюда не попадают никогда — их ребёнок ещё не видел.
]]
function Levels.distractorGroups(index: number, targetId: string): { { string } }
	local level = Levels.expect(index)
	local target = Letters.expect(targetId)
	local apart = level.index <= Levels.CONFUSABLES_APART_UNTIL

	local sameStage: { string } = {}
	local rest: { string } = {}
	local confusable: { string } = {}

	for _, id in Letters.ordered() do
		local letter = Letters.expect(id)
		if id ~= targetId and letter.stage <= level.index then
			if apart and table.find(target.confusableWith, id) then
				table.insert(confusable, id)
			elseif letter.stage == target.stage then
				table.insert(sameStage, id)
			else
				table.insert(rest, id)
			end
		end
	end

	return { sameStage, rest, confusable }
end

--[[
	Сколько уровней пройдено в каждом мире — то, что лежит в Profile.levels.
	Из DataStore может прийти что угодно: чужие ключи, дроби, отрицательные
	и слишком большие числа. Всё это приводится к целому от нуля до числа уровней.
]]
function Levels.sanitize(raw: any): { [string]: number }
	-- Путь мира математики лежит рядом, под своим ключом (Config/MathLevels).
	local caps = { [Levels.WORLD] = Levels.count(), [Levels.MATH_WORLD] = MathConfig.count() }
	local clean: { [string]: number } = {}
	for world in caps do
		clean[world] = 0
	end
	if typeof(raw) ~= "table" then
		return clean
	end

	for world, cap in caps do
		local value = raw[world]
		if typeof(value) == "number" and value == value then
			clean[world] = math.clamp(math.floor(value), 0, cap)
		end
	end
	return clean
end

return Levels
