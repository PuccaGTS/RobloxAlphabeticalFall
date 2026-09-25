--!strict
--[[
	Секреты уровней мира букв: какие найдены и куда за ними идти.

	На уровне три золотые буквы на постаментах, по одной на новую букву ступени
	(Challenges/RunCourse). Найденные хранятся в stages[уровень].chests как
	"secret_1".."secret_3" — поле заведено под сундуки ещё в первой версии
	профиля. До трёх секретов был один, и он записан как "secret": он считается
	первым, так что ничего найденного не пропадает и миграция не нужна.

	Пад «Охота за секретами» у портала (WorldService) ведёт на самый ранний
	уровень, где найдено не всё, — туда, где есть что искать.

	Чистая логика без Roblox API — покрыта тестами.
]]

local Levels = require(script.Parent.Parent.Config.Levels)
local Tunnel = require(script.Parent.Parent.Config.Tunnel)

local Secrets = {}

local LEGACY = "secret"

function Secrets.idOf(index: number): string
	return `secret_{index}`
end

-- Сколько секретов спрятано на уровне: по одному на отрезок, не больше Tunnel.SECRETS.
function Secrets.perLevel(level: number): number
	local info = Levels.get(level)
	return if info then math.min(Tunnel.SECRETS, info.segments) else 0
end

function Secrets.isFound(chests: any, index: number): boolean
	if typeof(chests) ~= "table" then
		return false
	end
	if table.find(chests, Secrets.idOf(index)) then
		return true
	end
	return index == 1 and table.find(chests, LEGACY) ~= nil
end

function Secrets.foundCount(chests: any, level: number): number
	local count = 0
	for index = 1, Secrets.perLevel(level) do
		if Secrets.isFound(chests, index) then
			count += 1
		end
	end
	return count
end

-- Сколько найдено на каждом уровне, списком от первого до последнего (для среза профиля).
function Secrets.counts(stages: any): { number }
	local counts: { number } = {}
	for level = 1, Levels.count() do
		local state = typeof(stages) == "table" and stages[level] or nil
		counts[level] = Secrets.foundCount(if typeof(state) == "table" then state.chests else nil, level)
	end
	return counts
end

--[[
	Куда идти за секретами: самый ранний уровень, где найдено не всё, из тех,
	что уже открыты (пройденные и текущий). nil — всё найдено.
]]
function Secrets.huntLevel(counts: { number }, cleared: number): number?
	local last = Levels.current(cleared)
	for level = 1, last do
		if (counts[level] or 0) < Secrets.perLevel(level) then
			return level
		end
	end
	return nil
end

-- Всего секретов в игре и сколько найдено.
function Secrets.total(counts: { number }): (number, number)
	local found, all = 0, 0
	for level = 1, Levels.count() do
		found += counts[level] or 0
		all += Secrets.perLevel(level)
	end
	return found, all
end

return Secrets
