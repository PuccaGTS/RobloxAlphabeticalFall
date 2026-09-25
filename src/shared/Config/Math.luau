--!strict
--[[
	Математика: ступени и генератор задач. Реализует docs/16-MATH.md § 2 и § 4.

	Задачи ГЕНЕРИРУЮТСЯ, а не пишутся руками: на ступень и диапазон генератор выдаёт
	пример и правдоподобные неверные варианты. Неверный вариант — всегда соседнее
	число, а не случайное: ошибка ребёнка должна быть осмысленной, иначе он
	угадывает, а не считает.

	Три правила доки, которые здесь зашиты в данные:
	  · сначала количество, потом цифра — showPips на ранних ступенях;
	  · считаем предметы, а не абстракции — у ступеней есть objects;
	  · читаемый потолок игры 10 и он не сдвигается; умножение — единственное
	    исключение (до 5x5) и оно всегда показано группами предметов.

	Генератор детерминирован: одному Random соответствует одна и та же задача.
	Это нужно и серверу с клиентом, чтобы сойтись, и тестам.

	ОЗВУЧКА СОБИРАЕТСЯ ИЗ КУСКОВ. Задача несёт не один ключ, а короткую цепочку:
	«Сколько будет» + «два» + «плюс» + «два». Причина ровно та же, по которой
	инструкция к испытанию заканчивается на «вот эту букву:» и продолжается
	названием буквы (docs/05-AUDIO-VO.md § 2): отдельная запись на каждый пример
	дала бы под три сотни реплик только по математике, а именно объём записи
	однажды уже сменил концепцию игры. Кусков двадцать: десять чисел, семь
	зачинов и три связки — и ими покрываются все одиннадцать ступеней.
]]

local Types = require(script.Parent.Parent.Types)

local MathConfig = {}

MathConfig.MAX_NUMBER = 10 -- верхняя граница игры, «для старших» не сдвигается
MathConfig.MAX_FACTOR = 5 -- умножение только до 5x5
-- Наибольший ответ во всей игре: он бывает только на ступени умножения,
-- и там задача обязана показывать группы предметов, а не одно число.
MathConfig.MAX_ANSWER = MathConfig.MAX_FACTOR * MathConfig.MAX_FACTOR

-- Ступень открывается, когда предыдущая освоена. Доля из docs/16-MATH.md § 2
-- относится к набору букв острова; у математики ступень — один объект прогресса,
-- поэтому здесь это статус «изученная» и выше.
MathConfig.UNLOCK_MIN_MASTERY = 2

local Stages: { Types.MathStage } = {
	{
		stage = 1,
		id = "count_group",
		title = "Узнавание количества",
		kind = "count",
		min = 1,
		max = 3,
		showPips = true,
		objects = "ball",
		choices = 2,
	},
	{
		stage = 2,
		id = "digit_small",
		title = "Цифры 1–5",
		kind = "digit",
		min = 1,
		max = 5,
		showPips = true,
		objects = nil,
		choices = 3,
	},
	{
		stage = 3,
		id = "count_objects",
		title = "Счёт предметов",
		kind = "count",
		min = 1,
		max = 5,
		showPips = true,
		objects = "berry",
		choices = 3,
	},
	{
		stage = 4,
		id = "compare",
		title = "Больше и меньше",
		kind = "compare",
		min = 1,
		max = 5,
		showPips = true,
		objects = "apple",
		choices = 2,
	},
	{
		stage = 5,
		id = "digit_big",
		title = "Цифры 6–10",
		kind = "digit",
		min = 6,
		max = 10,
		showPips = false, -- к этой ступени значок уже опирается на понятое количество
		objects = nil,
		choices = 3,
	},
	{
		stage = 6,
		id = "plus_one",
		title = "Прибавить один",
		kind = "add",
		min = 1,
		max = 9, -- +1 не должен выйти за десять
		showPips = false,
		objects = "berry",
		choices = 3,
	},
	{
		stage = 7,
		id = "add",
		title = "Сложение",
		kind = "add",
		min = 1,
		max = 5, -- сумма не больше пяти
		showPips = false,
		objects = "berry",
		choices = 3,
	},
	{
		stage = 8,
		id = "sub",
		title = "Вычитание",
		kind = "sub",
		min = 1,
		max = 5,
		showPips = false,
		objects = "apple",
		choices = 3,
	},
	{
		stage = 9,
		id = "compose",
		title = "Состав числа",
		kind = "compose",
		min = 2,
		max = 10,
		showPips = false,
		objects = nil,
		choices = 3,
	},
	{
		stage = 10,
		id = "groups",
		title = "Равные группы",
		kind = "group",
		min = 2,
		max = 10,
		showPips = true, -- ребёнок должен видеть, из чего складывается результат
		objects = "apple",
		choices = 3,
	},
	{
		stage = 11,
		id = "mul",
		title = "Умножение",
		kind = "mul",
		min = 1,
		max = 5,
		--[[
			Группы показываем обязательно. Это единственная ступень, где ответ
			выходит за десяток (до 25), а двузначных чисел ребёнок ещё не читает:
			он считает предметы на тарелках. См. docs/16-MATH.md § 1, правило 3.
		]]
		showPips = true,
		objects = "apple",
		choices = 3,
	},
}

local byStage: { [number]: Types.MathStage } = {}
for _, stage in Stages do
	assert(byStage[stage.stage] == nil, `Math: дубликат ступени {stage.stage}`)
	byStage[stage.stage] = stage
end

local Module = {}

Module.all = Stages

function Module.get(stage: number): Types.MathStage?
	return byStage[stage]
end

function Module.expect(stage: number): Types.MathStage
	local found = byStage[stage]
	assert(found, `Math: нет ступени {stage}`)
	return found
end

function Module.count(): number
	return #Stages
end

-- Ступень по её строковому id: под ним прогресс лежит в профиле («digit_small»).
function Module.byId(id: string): Types.MathStage?
	for _, stage in Stages do
		if stage.id == id then
			return stage
		end
	end
	return nil
end

--[[
	Открыта ли ступень. Первая открыта всегда; дальше нужна предыдущая,
	доведённая хотя бы до «изученной».

	Умножение и равные группы ничего не блокируют по замыслу доки: игра считается
	пройденной и без них, поэтому проверять их открытость выше по цепочке некому.
]]
function Module.isUnlocked(stage: number, masteryOfStage: (stageId: string) -> number): boolean
	if byStage[stage] == nil then
		return false
	end
	if stage <= 1 then
		return true
	end
	local prev = byStage[stage - 1]
	if prev == nil then
		return false
	end
	return masteryOfStage(prev.id) >= MathConfig.UNLOCK_MIN_MASTERY
end

--[[
	Ступень, которую играет портал: самая высокая из открытых подряд.
	Считается одинаково на сервере (какие задачи строить) и на клиенте
	(что написать над порталом), поэтому живёт здесь, а не в сервисе.
]]
function Module.current(masteryOfStage: (stageId: string) -> number): number
	local highest = 1
	for stage = 2, #Stages do
		if not Module.isUnlocked(stage, masteryOfStage) then
			break
		end
		highest = stage
	end
	return highest
end

-- ─────────────────────────── генератор ───────────────────────────

local function shuffled(list: { number }, random: Random): { number }
	local copy = table.clone(list)
	for i = #copy, 2, -1 do
		local j = random:NextInteger(1, i)
		copy[i], copy[j] = copy[j], copy[i]
	end
	return copy
end

--[[
	Собирает варианты ответа: верный плюс соседние числа.

	Сначала берём ближайших соседей (±1, потом ±2, ±3) — на них ребёнок ошибается
	осмысленно, просчитавшись на единицу. Случайные далёкие числа сюда не попадают:
	они превращают ворота в угадайку, потому что неверный вариант видно сразу.
]]
local function buildAnswers(answer: number, lo: number, hi: number, count: number, random: Random): { number }
	local neighbours: { number } = {}
	for distance = 1, 3 do
		for _, value in { answer - distance, answer + distance } do
			if value >= lo and value <= hi and value ~= answer then
				table.insert(neighbours, value)
			end
		end
	end

	-- Если соседей не хватило (узкий диапазон), добираем чем есть из диапазона.
	local used: { [number]: boolean } = { [answer] = true }
	local picked: { number } = {}
	for _, value in neighbours do
		if not used[value] then
			used[value] = true
			table.insert(picked, value)
		end
	end
	if #picked < count - 1 then
		for value = lo, hi do
			if not used[value] then
				used[value] = true
				table.insert(picked, value)
			end
		end
	end

	local wanted = math.min(count, #picked + 1)
	local result: { number } = {}
	for index = 1, wanted - 1 do
		table.insert(result, picked[index])
	end
	table.insert(result, answer)
	return shuffled(result, random)
end

--[[
	Одна задача ступени. choices можно передать, чтобы сузить или расширить ворота
	под текущую сложность; по умолчанию берётся значение ступени.
]]
function Module.generate(stage: number, random: Random, choices: number?): Types.MathTask
	local spec = Module.expect(stage)
	local count = math.max(2, choices or spec.choices)

	local kind = spec.kind
	local answer: number
	local prompt = ""
	local vo: { string }
	-- Равные группы: сколько тарелок и по сколько на каждой. Их рисуют над воротами,
	-- и по ним же собирается фраза «два по три».
	local groups: number? = nil
	local each: number? = nil
	local lo, hi = spec.min, spec.max

	if kind == "count" or kind == "digit" then
		answer = random:NextInteger(spec.min, spec.max)
		--[[
			Число называет голос, а над воротами не пишем ничего: увидев «3» на щите,
			ребёнок нашёл бы такую же цифру в проёме, ничего не посчитав.
		]]
		vo = if kind == "digit" then { "mtask_digit", `num_{answer}` } else { "mtask_where", `num_{answer}` }
	elseif kind == "compare" then
		-- Две разные величины: спрашиваем большую или меньшую.
		local first = random:NextInteger(spec.min, spec.max)
		local second = random:NextInteger(spec.min, spec.max)
		while second == first do
			second = random:NextInteger(spec.min, spec.max)
		end
		local wantMore = random:NextInteger(0, 1) == 1
		answer = if wantMore then math.max(first, second) else math.min(first, second)
		vo = if wantMore then { "mtask_more" } else { "mtask_less" }
		-- Варианты здесь не соседи, а ровно те две величины, что лежат на чашах.
		local pair = shuffled({ first, second }, random)
		return {
			id = `s{stage}_cmp_{first}_{second}_{if wantMore then "m" else "l"}`,
			stage = stage,
			kind = kind,
			prompt = "",
			vo = vo,
			answer = answer,
			answers = pair,
			objects = spec.objects,
			showPips = spec.showPips,
		}
	elseif kind == "add" then
		local a: number
		local b: number
		if spec.id == "plus_one" then
			-- spec.max уже подобран так, чтобы +1 не вышло за десять
			a = random:NextInteger(spec.min, spec.max)
			b = 1
			hi = math.min(MathConfig.MAX_NUMBER, spec.max + 1)
		else
			-- Верх ступени — это предел СУММЫ, поэтому первое слагаемое
			-- обязано оставить место хотя бы для единицы.
			a = random:NextInteger(spec.min, math.max(spec.min, spec.max - 1))
			b = random:NextInteger(1, spec.max - a)
			hi = spec.max
		end
		answer = a + b
		prompt = `{a} + {b}`
		vo = { "mtask_howmuch", `num_{a}`, "mop_plus", `num_{b}` }
		lo = 1
	elseif kind == "sub" then
		local a = random:NextInteger(spec.min + 1, spec.max)
		local b = random:NextInteger(1, a - 1)
		answer = a - b
		prompt = `{a} − {b}`
		vo = { "mtask_howmuch", `num_{a}`, "mop_minus", `num_{b}` }
		lo, hi = 0, spec.max
	elseif kind == "compose" then
		-- «Сколько не хватает до пяти»: показываем часть и целое.
		local total = random:NextInteger(math.max(2, spec.min), spec.max)
		local part = random:NextInteger(1, total - 1)
		answer = total - part
		prompt = `{part} + ? = {total}`
		vo = { "mtask_missing", `num_{total}` }
		lo, hi = 1, spec.max
	elseif kind == "group" then
		-- «Три тарелки, на каждой по два»: считаем предметы, а не заучиваем таблицу.
		groups = random:NextInteger(2, 5)
		each = random:NextInteger(2, math.max(2, math.floor(spec.max / (groups :: number))))
		answer = (groups :: number) * (each :: number)
		-- Пример словами не пишем: тарелки с предметами и есть условие задачи.
		-- Сначала условие, потом вопрос: «Три по два. Сколько всего?»
		vo = { `num_{groups}`, "mop_by", `num_{each}`, "mtask_total" }
		lo, hi = 2, MathConfig.MAX_NUMBER
	elseif kind == "mul" then
		local a = random:NextInteger(1, MathConfig.MAX_FACTOR)
		local b = random:NextInteger(1, MathConfig.MAX_FACTOR)
		answer = a * b
		prompt = `{a} × {b}`
		--[[
			Умножение звучит как равные группы, а не как таблица: «два по три».
			Тарелки при этом рисуются те же самые — это то самое условие, ради
			которого умножению вообще разрешили выйти за десяток.
		]]
		groups, each = a, b
		vo = { `num_{a}`, "mop_by", `num_{b}`, "mtask_total" }
		lo, hi = 1, MathConfig.MAX_FACTOR * MathConfig.MAX_FACTOR
	else
		error(`Math: неизвестный вид задачи "{kind}"`)
	end

	return {
		id = `s{stage}_{kind}_{answer}_{random:NextInteger(1, 1000000)}`,
		stage = stage,
		kind = kind,
		prompt = prompt,
		vo = vo,
		answer = answer,
		answers = buildAnswers(answer, lo, hi, count, random),
		objects = spec.objects,
		showPips = spec.showPips,
		groups = groups,
		each = each,
	}
end

--[[
	Куски, из которых собирается любая математическая фраза, и что они значат.
	Здесь же и текст для субтитров: реплики короткие, и держать их рядом с ключом
	дешевле, чем заводить отдельный словарь.
]]
local PHRASES: { [string]: string } = {
	mtask_where = "Беги туда, где", -- + число
	mtask_digit = "Беги на цифру", -- + число
	mtask_more = "Беги туда, где больше",
	mtask_less = "Беги туда, где меньше",
	mtask_howmuch = "Сколько будет", -- + число + связка + число
	--[[
		Падежи — цена сборки фразы из кусков. «Сколько не хватает до пять» звучало бы
		сломанно, а записывать десять чисел ещё и в родительном падеже — это лишний
		десяток реплик ради одной ступени. Поэтому формулировка подобрана так,
		чтобы число вставало в именительном: «...чтобы стало пять».
	]]
	mtask_missing = "Сколько не хватает, чтобы стало", -- + число
	mtask_total = "Сколько всего", -- + число + «по» + число
	mop_plus = "плюс",
	mop_minus = "минус",
	mop_by = "по", -- «два по три»: равные группы и умножение
	-- «Ягодная поляна»: сбор предметов по счёту (Challenges/BerryCount).
	mtask_collect = "Собери ягод:", -- + число
	mtask_collect_that = "Собери столько ягод и отнеси в корзинку.", -- после примера
	mtask_fill = "Доложи ягод, чтобы в корзинке стало", -- + число
}

Module.PHRASES = PHRASES

--[[
	Озвучка математики — только числа от одного до десяти (docs/05-AUDIO-VO.md § 1:
	минимум голоса). Задача целиком видна на воротах и подписью; куски фраз
	(«Сколько будет», «плюс») собирают подпись, но голосом не звучат.
]]
function Module.voKeys(): { string }
	local keys: { string } = {}
	for value = 1, MathConfig.MAX_NUMBER do
		table.insert(keys, `num_{value}`)
	end
	return keys
end

-- Всё, из чего складывается подпись задачи: числа и куски фраз («Сколько будет», «плюс»).
function Module.captionKeys(): { string }
	local keys = Module.voKeys()
	for key in PHRASES do
		table.insert(keys, key)
	end
	table.sort(keys)
	return keys
end

-- Текст задачи словами: для субтитров и для родительского режима.
function Module.spell(task: Types.MathTask): string
	local words: { string } = {}
	for _, key in task.vo do
		local number = string.match(key, "^num_(%d+)$")
		table.insert(words, if number then number else PHRASES[key] or key)
	end
	return table.concat(words, " ")
end

Module.MAX_NUMBER = MathConfig.MAX_NUMBER
Module.MAX_FACTOR = MathConfig.MAX_FACTOR
Module.MAX_ANSWER = MathConfig.MAX_ANSWER
Module.UNLOCK_MIN_MASTERY = MathConfig.UNLOCK_MIN_MASTERY

return Module
