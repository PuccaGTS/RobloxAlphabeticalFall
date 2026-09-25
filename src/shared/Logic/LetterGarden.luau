--!strict
--[[
	Азбучная грядка у калитки (docs/17-CONTENT-PLAN.md § 7.4): три лунки.
	Наступил на пустую — посадил букву-семечко, голос называет её. Через
	SPROUT секунд из земли показывается росток с табличкой-буквой, через
	BLOOM — распускается цветок, в серединке картинка к букве (🍉 у А).
	Наступил на цветок — урожай: голос называет букву, звёзды, лунка пустеет.

	Зачем. Повод вернуться домой завтра: утром посадил — вечером собрал.
	Сажается следующая буква из выученных по кругу, так грядка ещё и
	повторяет алфавит — ребёнок видит «свои» буквы на цветах.

	Чистая логика без Roblox API — покрыта тестами. Время — os.time() сервера.
]]

local LetterGarden = {}

LetterGarden.BEDS = 3
LetterGarden.SPROUT = 15 * 60 -- через столько после посадки показывается росток
LetterGarden.BLOOM = 2 * 60 * 60 -- через столько распускается цветок: сажай днём — собирай вечером

export type Bed = { letterId: string?, plantedAt: number? }
export type State = { beds: { Bed }, harvested: number, next: number }
export type Stage = "empty" | "seed" | "sprout" | "bloom"

function LetterGarden.new(): State
	local beds = {}
	for index = 1, LetterGarden.BEDS do
		beds[index] = {}
	end
	return { beds = beds, harvested = 0, next = 1 }
end

local function isTime(value: any): boolean
	return typeof(value) == "number" and value == value and value > 0 and value < 1e11
end

function LetterGarden.sanitize(raw: any): State
	local state = LetterGarden.new()
	if typeof(raw) ~= "table" then
		return state
	end
	if typeof(raw.beds) == "table" then
		for index = 1, LetterGarden.BEDS do
			local bed = raw.beds[index]
			if
				typeof(bed) == "table"
				and typeof(bed.letterId) == "string"
				and #bed.letterId <= 4
				and isTime(bed.plantedAt)
			then
				state.beds[index] = { letterId = bed.letterId, plantedAt = math.floor(bed.plantedAt) }
			end
		end
	end
	if typeof(raw.harvested) == "number" and raw.harvested == raw.harvested and raw.harvested >= 0 then
		state.harvested = math.floor(math.min(raw.harvested, 1e6))
	end
	if typeof(raw.next) == "number" and raw.next == raw.next and raw.next >= 1 then
		state.next = math.floor(math.min(raw.next, 1e6))
	end
	return state
end

function LetterGarden.stage(bed: Bed, now: number): Stage
	if not bed.letterId or not bed.plantedAt then
		return "empty"
	end
	local age = now - bed.plantedAt
	if age >= LetterGarden.BLOOM then
		return "bloom"
	elseif age >= LetterGarden.SPROUT then
		return "sprout"
	end
	return "seed"
end

-- Сколько секунд осталось до цветка (0 — уже цветёт или лунка пуста).
function LetterGarden.left(bed: Bed, now: number): number
	if not bed.plantedAt then
		return 0
	end
	return math.max(0, LetterGarden.BLOOM - (now - bed.plantedAt))
end

--[[
	Следующая буква для посадки: из выученных по кругу. learned — id букв
	в порядке алфавита; пусто — первые буквы, чтобы грядка работала с первого дня.
]]
function LetterGarden.nextLetter(state: State, learned: { string }): string
	local list = if #learned > 0 then learned else { "a", "b", "v" }
	return list[(state.next - 1) % #list + 1]
end

-- Есть ли пустая лунка: иначе задание «посади букву» сегодня не выполнить.
function LetterGarden.hasEmpty(state: State, now: number): boolean
	for _, bed in state.beds do
		if LetterGarden.stage(bed, now) == "empty" then
			return true
		end
	end
	return false
end

-- Посадить в пустую лунку. Возвращает новое состояние и посаженную букву (nil — лунка занята).
function LetterGarden.plant(state: State, index: number, learned: { string }, now: number): (State, string?)
	local clean = LetterGarden.sanitize(state)
	local bed = clean.beds[index]
	if not bed or LetterGarden.stage(bed, now) ~= "empty" then
		return clean, nil
	end
	local letterId = LetterGarden.nextLetter(clean, learned)
	clean.beds[index] = { letterId = letterId, plantedAt = now }
	clean.next += 1
	return clean, letterId
end

-- Собрать распустившийся цветок. Возвращает новое состояние и букву урожая (nil — рано).
function LetterGarden.harvest(state: State, index: number, now: number): (State, string?)
	local clean = LetterGarden.sanitize(state)
	local bed = clean.beds[index]
	if not bed or LetterGarden.stage(bed, now) ~= "bloom" then
		return clean, nil
	end
	local letterId = bed.letterId
	clean.beds[index] = {}
	clean.harvested += 1
	return clean, letterId
end

return LetterGarden
