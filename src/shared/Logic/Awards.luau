--!strict
--[[
	Постройки, которые нельзя купить — только заработать учёбой.
	См. docs/17-CONTENT-PLAN.md § 5, «Что открывается только обучением».

	  · флаг за каждый пройденный уровень мира букв;
	  · Азбучная арка над калиткой — за 10 букв подряд от А;
	  · Шпиль Азбуки — за все 33 буквы в статусе «освоенная».

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
local MasteryRules = require(script.Parent.MasteryRules)

local Awards = {}

Awards.ARCH_IN_ORDER = 10

export type Earned = {
	flags: number, -- сколько уровней пройдено: флаги с первого по этот
	arch: boolean,
	spire: boolean,
}

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

	return {
		flags = Levels.sanitize(levels)[Levels.WORLD],
		arch = Awards.lettersInOrder(letters) >= Awards.ARCH_IN_ORDER,
		spire = allMastered,
	}
end

return Awards
