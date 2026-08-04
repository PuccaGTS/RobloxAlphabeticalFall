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
	  · потолок игры 10 и он не сдвигается; умножение до 5x5.

	Генератор детерминирован: одному Random соответствует одна и та же задача.
	Это нужно и серверу с клиентом, чтобы сойтись, и тестам.
]]

local Types = require(script.Parent.Parent.Types)

local MathConfig = {}

MathConfig.MAX_NUMBER = 10 -- верхняя граница игры, «для старших» не сдвигается
MathConfig.MAX_FACTOR = 5 -- умножение только до 5x5

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
		showPips = false,
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
	local vo: string
	local lo, hi = spec.min, spec.max

	if kind == "count" or kind == "digit" then
		answer = random:NextInteger(spec.min, spec.max)
		-- Цифру называет голос, поэтому над воротами ничего не пишем.
		vo = if kind == "digit" then `num_{answer}` else `mtask_{spec.id}`
	elseif kind == "compare" then
		-- Две разные величины: спрашиваем большую или меньшую.
		local first = random:NextInteger(spec.min, spec.max)
		local second = random:NextInteger(spec.min, spec.max)
		while second == first do
			second = random:NextInteger(spec.min, spec.max)
		end
		local wantMore = random:NextInteger(0, 1) == 1
		answer = if wantMore then math.max(first, second) else math.min(first, second)
		vo = if wantMore then "mtask_compare_more" else "mtask_compare_less"
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
		vo = `mex_add_{a}_{b}`
		lo = 1
	elseif kind == "sub" then
		local a = random:NextInteger(spec.min + 1, spec.max)
		local b = random:NextInteger(1, a - 1)
		answer = a - b
		prompt = `{a} − {b}`
		vo = `mex_sub_{a}_{b}`
		lo, hi = 0, spec.max
	elseif kind == "compose" then
		-- «Сколько не хватает до пяти»: показываем часть и целое.
		local total = random:NextInteger(math.max(2, spec.min), spec.max)
		local part = random:NextInteger(1, total - 1)
		answer = total - part
		prompt = `{part} + ? = {total}`
		vo = `mex_compose_{part}_{total}`
		lo, hi = 1, spec.max
	elseif kind == "group" then
		-- «Три тарелки, на каждой по два»: считаем предметы, а не заучиваем таблицу.
		local groups = random:NextInteger(2, 5)
		local each = random:NextInteger(2, math.max(2, math.floor(spec.max / groups)))
		answer = groups * each
		vo = `mex_group_{groups}_{each}`
		lo, hi = 2, MathConfig.MAX_NUMBER
	elseif kind == "mul" then
		local a = random:NextInteger(1, MathConfig.MAX_FACTOR)
		local b = random:NextInteger(1, MathConfig.MAX_FACTOR)
		answer = a * b
		prompt = `{a} × {b}`
		vo = `mex_mul_{a}_{b}`
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
	}
end

--[[
	Все ключи озвучки, которые нужны математике. Отдельным списком, а не через
	AudioRegistry: математический мир ещё не собран, и подмешивать сотню пустых
	ключей в отчёт о недостающей озвучке по буквам сейчас только мешало бы.
	Подключить сюда реестр — когда появятся математические уровни.
]]
function Module.voKeys(): { string }
	local set: { [string]: boolean } = {}

	for value = 1, MathConfig.MAX_NUMBER do
		set[`num_{value}`] = true
	end
	set["mtask_compare_more"] = true
	set["mtask_compare_less"] = true

	for _, spec in Stages do
		if spec.kind == "count" then
			set[`mtask_{spec.id}`] = true
		elseif spec.kind == "add" then
			for a = spec.min, spec.max do
				local top = if spec.id == "plus_one" then 1 else math.max(1, spec.max - a)
				for b = 1, top do
					set[`mex_add_{a}_{b}`] = true
				end
			end
		elseif spec.kind == "sub" then
			for a = spec.min + 1, spec.max do
				for b = 1, a - 1 do
					set[`mex_sub_{a}_{b}`] = true
				end
			end
		elseif spec.kind == "compose" then
			for total = math.max(2, spec.min), spec.max do
				for part = 1, total - 1 do
					set[`mex_compose_{part}_{total}`] = true
				end
			end
		elseif spec.kind == "group" then
			for groups = 2, 5 do
				for each = 2, math.max(2, math.floor(spec.max / groups)) do
					set[`mex_group_{groups}_{each}`] = true
				end
			end
		elseif spec.kind == "mul" then
			for a = 1, MathConfig.MAX_FACTOR do
				for b = 1, MathConfig.MAX_FACTOR do
					set[`mex_mul_{a}_{b}`] = true
				end
			end
		end
	end

	local keys: { string } = {}
	for key in set do
		table.insert(keys, key)
	end
	table.sort(keys)
	return keys
end

Module.MAX_NUMBER = MathConfig.MAX_NUMBER
Module.MAX_FACTOR = MathConfig.MAX_FACTOR
Module.UNLOCK_MIN_MASTERY = MathConfig.UNLOCK_MIN_MASTERY

return Module
