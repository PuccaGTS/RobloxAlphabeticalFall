--!strict
--[[
	Постройки, которые нельзя купить — только заработать учёбой.
	См. docs/17-CONTENT-PLAN.md § 5, «Что открывается только обучением».

	  · флаг за каждый пройденный уровень мира букв;
	  · Азбучная арка над калиткой — за 10 букв подряд от А;
	  · Шпиль Азбуки — за все 33 буквы в статусе «освоенная»;
	  · флаг с цифрой за каждый пройденный уровень мира математики;
	  · комната буквы в доме — за каждую освоенную букву, и комната цифры —
	    за каждую освоенную ступень счёта (docs/15-HOME-BASE.md § 5);
	  · Шпиль Счёта — за девять базовых ступеней счёта в статусе «освоенная».
	    Равные группы и умножение сюда не входят: они необязательные и ничего
	    не блокируют (docs/16-MATH.md § 2), и шпиль за них был бы наградой
	    не за счёт, а за раннее умножение.

	Они стоят на участке рядом с купленным домом, и по двору сразу видно:
	ребёнок в игру играл или ребёнок в ней учился. Звёздочками их не получить
	никак — иначе они перестали бы значить хоть что-то.

	Ничего из этого не хранится отдельно: всё выводится из того, что уже лежит
	в профиле (пройденные уровни и статусы букв). Две записи об одном и том же
	рано или поздно разошлись бы.

	Чистая логика без Roblox API — покрыта тестами.
]]

local Letters = require(script.Parent.Parent.Config.Letters)
local Levels = require(script.Parent.Parent.Config.Levels)
local MathConfig = require(script.Parent.Parent.Config.Math)
local MasteryRules = require(script.Parent.MasteryRules)

local Awards = {}

Awards.ARCH_IN_ORDER = 10
-- Сколько первых ступеней счёта нужно освоить для Шпиля Счёта (docs/17-CONTENT-PLAN.md § 5).
Awards.COUNT_SPIRE_STAGES = 9

export type Earned = {
	flags: number, -- сколько уровней пройдено: флаги с первого по этот
	arch: boolean,
	spire: boolean,
	mathFlags: number, -- то же для пути мира математики
	countSpire: boolean,
	--[[
		Комнаты дома: буквы и ступени счёта в статусе «освоенная», по порядку.
		Не число, а сами id: на полке стоит именно та буква, которую ребёнок
		выучил, а не «сколько-то первых».
	]]
	letterRooms: { string },
	mathRooms: { string },
}

-- Статус буквы или ступени счёта: у обоих прогресс устроен одинаково.
local function masteryOf(letters: any, letterId: string): number
	if typeof(letters) ~= "table" then
		return 0
	end
	local progress = letters[letterId]
	if typeof(progress) ~= "table" or typeof(progress.mastery) ~= "number" then
		return 0
	end
	return progress.mastery
end

--[[
	Сколько букв ребёнок знает ПОДРЯД от начала алфавита — хотя бы «изученными».
	Азбука — последовательность: «знает А, Б, В, Г» проверяемо дома,
	а «знает четыре буквы где-то в середине» — нет. Этим же числом живёт
	отчёт родителя (Logic/ParentReport).
]]
function Awards.lettersInOrder(letters: any): number
	local count = 0
	for _, letterId in Letters.ordered() do
		if masteryOf(letters, letterId) < MasteryRules.LEARNED then
			break
		end
		count += 1
	end
	return count
end

function Awards.of(profile: any): Earned
	local letters = if typeof(profile) == "table" then profile.letters else nil
	local levels = if typeof(profile) == "table" then profile.levels else nil

	local allMastered = true
	for _, letterId in Letters.ordered() do
		if masteryOf(letters, letterId) < MasteryRules.MASTERED then
			allMastered = false
			break
		end
	end

	local math_ = if typeof(profile) == "table" then profile.math else nil
	local countMastered = true
	for stage = 1, Awards.COUNT_SPIRE_STAGES do
		local spec = MathConfig.get(stage)
		if not spec or masteryOf(math_, spec.id) < MasteryRules.MASTERED then
			countMastered = false
			break
		end
	end

	--[[
		Комнаты открываются по одной, за каждую освоенную букву и ступень счёта.
		Порядок — алфавитный и по ступеням: полка растёт слева направо,
		и ребёнок видит, докуда он дошёл.
	]]
	local letterRooms: { string } = {}
	for _, letterId in Letters.ordered() do
		if masteryOf(letters, letterId) >= MasteryRules.MASTERED then
			table.insert(letterRooms, letterId)
		end
	end

	local mathRooms: { string } = {}
	for stage = 1, MathConfig.count() do
		local spec = MathConfig.get(stage)
		if spec and masteryOf(math_, spec.id) >= MasteryRules.MASTERED then
			table.insert(mathRooms, spec.id)
		end
	end

	local cleared = Levels.sanitize(levels)
	return {
		flags = cleared[Levels.WORLD],
		arch = Awards.lettersInOrder(letters) >= Awards.ARCH_IN_ORDER,
		spire = allMastered,
		mathFlags = cleared[Levels.MATH_WORLD],
		countSpire = countMastered,
		letterRooms = letterRooms,
		mathRooms = mathRooms,
	}
end

return Awards
