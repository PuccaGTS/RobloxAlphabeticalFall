--!strict
--[[
	Адаптивная сложность. Чистая логика, покрыта тестами.
	Формализует docs/02-LEARNING.md § 7.

	Правила:
	  3 ошибки подряд  → на уровень вниз (и включаем автоподсказку)
	  5 успехов подряд → на уровень вверх

	Потолок фиксирован: игра никогда не разгоняется настолько, чтобы пятилетний не успевал.
]]

local DifficultyCurve = {}

DifficultyCurve.MIN_LEVEL = 1
DifficultyCurve.MAX_LEVEL = 5
DifficultyCurve.DEFAULT_LEVEL = 2

DifficultyCurve.WRONG_TO_DEMOTE = 3
DifficultyCurve.CORRECT_TO_PROMOTE = 5

export type Streaks = {
	correctInRow: number,
	wrongInRow: number,
}

export type Adjustment = {
	level: number,
	streaks: Streaks,
	changed: number, -- -1 вниз, 0 без изменений, +1 вверх
	forceHints: boolean, -- показывать подсказку автоматически
}

function DifficultyCurve.newStreaks(): Streaks
	return { correctInRow = 0, wrongInRow = 0 }
end

function DifficultyCurve.clamp(level: number): number
	return math.clamp(level, DifficultyCurve.MIN_LEVEL, DifficultyCurve.MAX_LEVEL)
end

function DifficultyCurve.apply(level: number, streaks: Streaks, correct: boolean): Adjustment
	local nextStreaks: Streaks = {
		correctInRow = if correct then streaks.correctInRow + 1 else 0,
		wrongInRow = if correct then 0 else streaks.wrongInRow + 1,
	}

	local nextLevel = level
	local changed = 0
	local forceHints = false

	if nextStreaks.wrongInRow >= DifficultyCurve.WRONG_TO_DEMOTE then
		nextLevel = DifficultyCurve.clamp(level - 1)
		nextStreaks.wrongInRow = 0
		forceHints = true
		changed = if nextLevel < level then -1 else 0
	elseif nextStreaks.correctInRow >= DifficultyCurve.CORRECT_TO_PROMOTE then
		nextLevel = DifficultyCurve.clamp(level + 1)
		nextStreaks.correctInRow = 0
		changed = if nextLevel > level then 1 else 0
	end

	return {
		level = nextLevel,
		streaks = nextStreaks,
		changed = changed,
		forceHints = forceHints,
	}
end

-- Достаёт значение параметра испытания для уровня сложности с зажимом по краям.
function DifficultyCurve.pick<T>(values: { T }, level: number): T
	local index = math.clamp(level, 1, #values)
	return values[index]
end

return DifficultyCurve
