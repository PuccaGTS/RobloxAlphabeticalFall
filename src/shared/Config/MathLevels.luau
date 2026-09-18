--!strict
--[[
	Уровни мира математики: путь, который продолжает оранжевый портал.
	Таблица — docs/17-CONTENT-PLAN.md § 2.

	Устроено как путь мира букв (Config/Levels): уровень открывается по финишу
	предыдущего, а не по статусам ступени. Раньше портал играл «самую высокую
	открытую ступень», и ступень открывалась освоением — ребёнок, который пробегал
	уровень с ошибками, возвращался в тот же туннель снова и снова и не видел,
	что путь движется. Теперь движется всегда, а ошибки возвращаются к нему
	повторениями: статусы ступеней считаются как прежде и нужны отчёту родителю.

	Номер уровня совпадает с номером ступени счёта (Config/Math). Это держится тестом.
]]

local MathConfig = require(script.Parent.Math)

export type MathLevel = {
	index: number, -- он же номер ступени счёта
	title: string, -- как уровень подписан над порталом и в итоге
	gates: number, -- сколько ворот, они же сохранки
	--[[
		Сколько проёмов в воротах самое большее. В docs/17 у поздних уровней «из 4»,
		но дорожек в туннеле три, и потолок срезает это до трёх, как у мира букв.
	]]
	maxChoices: number,
	heat: number, -- сила аттракционов пути (Config/Attractions), на ступень ниже мира букв
}

local MathLevels = {}

MathLevels.WORLD = "math"

MathLevels.all = {
	{ index = 1, title = "Полянка счёта", gates = 4, maxChoices = 2, heat = 1 },
	{ index = 2, title = "Тропа цифр", gates = 4, maxChoices = 3, heat = 1 },
	{ index = 3, title = "Ягодный лес", gates = 5, maxChoices = 3, heat = 1 },
	{ index = 4, title = "Весы", gates = 5, maxChoices = 2, heat = 2 },
	{ index = 5, title = "Мост чисел", gates = 5, maxChoices = 3, heat = 2 },
	{ index = 6, title = "Прибавляй", gates = 5, maxChoices = 3, heat = 2 },
	{ index = 7, title = "Сложение", gates = 6, maxChoices = 3, heat = 3 },
	{ index = 8, title = "Вычитание", gates = 6, maxChoices = 3, heat = 3 },
	{ index = 9, title = "Состав числа", gates = 6, maxChoices = 3, heat = 4 },
	{ index = 10, title = "Равные группы", gates = 6, maxChoices = 3, heat = 4 },
	{ index = 11, title = "Умножение", gates = 6, maxChoices = 3, heat = 4 },
} :: { MathLevel }

function MathLevels.count(): number
	return #MathLevels.all
end

function MathLevels.get(index: any): MathLevel?
	if typeof(index) ~= "number" then
		return nil
	end
	return MathLevels.all[index]
end

function MathLevels.expect(index: number): MathLevel
	local level = MathLevels.get(index)
	assert(level, `MathLevels: нет уровня {index}`)
	return level
end

-- Какой уровень играет портал: следующий за пройденными, после последнего — последний.
function MathLevels.current(cleared: any): number
	local done = if typeof(cleared) == "number" then math.floor(cleared) else 0
	return math.clamp(done + 1, 1, MathLevels.count())
end

--[[
	Сколько уровней засчитать пройденными профилю, игравшему до появления пути.
	Открытые ступени ребёнок уже заслужил — возвращать его на первую полянку
	было бы наказанием за обновление игры.
]]
function MathLevels.clearedFromMastery(masteryOfStage: (stageId: string) -> number): number
	return math.clamp(MathConfig.current(masteryOfStage) - 1, 0, MathLevels.count())
end

return MathLevels
