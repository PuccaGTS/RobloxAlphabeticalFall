--!strict
--[[
	Буква дня: ежедневное задание и серия дней. См. docs/03-CHALLENGES.md § 7.

	Каждый день у ребёнка своя буква — первая в очереди повторений на момент,
	когда он пришёл. Три быстрых задания по ней (Буквопад, Пузыри, Зеркало)
	приносят 30 ⭐ и шаг серии дней.

	Чистая логика без Roblox API — покрыта тестами. Букву выбирает сервис:
	очередь повторений живёт в ProgressService, сюда приходит готовый id.

	Серия не сгорает. Пропущенные дни стоят ровно одного шага: в день возвращения
	серия не растёт, но и не падает. Решили не играть родители, а не ребёнок,
	и наказывать за это его нельзя (docs/03-CHALLENGES.md § 7). Награда за серию
	платится только за новый рекорд: иначе откат на шаг и повтор того же дня
	превращались бы в ферму.
]]

local Types = require(script.Parent.Parent.Types)
local Economy = require(script.Parent.Parent.Config.Economy)

local DailyLetter = {}

-- Три задания по порядку. Все короткие и все на узнавание одной буквы.
DailyLetter.TASKS = { "letter_rain", "bubbles", "mirror" }

--[[
	Замена Зеркалу для букв, у которых нет честного перевёрнутого варианта
	(О, Х): такая буква выглядит одинаково, как её ни крути. Лестница стартует
	с буквы дня и спрашивает, какая за ней, — это та же буква, другой навык.
]]
DailyLetter.MIRROR_FALLBACK = "alphabet_ladder"

export type State = Types.DailyLetter

export type Outcome = {
	done: number,
	total: number,
	finished: boolean,
	streak: number,
	bonus: number, -- за три задания, только в день завершения
	streakReward: number, -- за новый рекорд серии
}

function DailyLetter.new(): State
	return { day = 0, letterId = nil, done = 0, streak = 0, best = 0, lastDay = 0 }
end

local function isCount(value: any): boolean
	return typeof(value) == "number" and value == value and value >= 0 and value < math.huge
end

local function count(value: any): number
	return if isCount(value) then math.floor(value) else 0
end

-- Мусор из DataStore превращается в честный ноль, а не в ошибку на входе.
function DailyLetter.sanitize(raw: any): State
	local state = DailyLetter.new()
	if typeof(raw) ~= "table" then
		return state
	end
	state.day = count(raw.day)
	state.letterId = if typeof(raw.letterId) == "string" then raw.letterId else nil
	state.done = math.min(count(raw.done), #DailyLetter.TASKS)
	state.streak = count(raw.streak)
	state.best = math.max(count(raw.best), state.streak)
	state.lastDay = count(raw.lastDay)
	return state
end

--[[
	Буква на день: первая в очереди повторений. Очередь пуста бывает только
	у сломанного профиля — тогда берём из открытых букв по номеру дня, чтобы
	буква всё равно менялась.
]]
function DailyLetter.pick(queue: { string }, available: { string }, day: number): string?
	if #queue > 0 then
		return queue[1]
	end
	if #available == 0 then
		return nil
	end
	return available[day % #available + 1]
end

--[[
	Наступил новый день — новая буква и задания с нуля. Серию не трогает:
	она меняется только по завершении. Возвращает, сменился ли день.
]]
function DailyLetter.refresh(state: State, today: number, letterId: string?): boolean
	if state.day == today and state.letterId ~= nil then
		return false
	end
	state.day = today
	state.letterId = letterId
	state.done = 0
	return true
end

function DailyLetter.tasks(canMirror: boolean): { string }
	local tasks = table.clone(DailyLetter.TASKS)
	if not canMirror then
		tasks[table.find(tasks, "mirror") :: number] = DailyLetter.MIRROR_FALLBACK
	end
	return tasks
end

-- Следующее задание на сегодня или nil, если всё сделано (или буквы нет).
function DailyLetter.nextTask(state: State, today: number, canMirror: boolean): string?
	if state.day ~= today or state.letterId == nil then
		return nil
	end
	return DailyLetter.tasks(canMirror)[state.done + 1]
end

function DailyLetter.isDone(state: State, today: number): boolean
	return state.day == today and state.done >= #DailyLetter.TASKS
end

--[[
	Серия на сегодня. Вчера была буква — шаг вперёд. Был пропуск — шаг назад
	за пропуск и шаг вперёд за сегодня, то есть на месте. Первый раз — единица.
]]
function DailyLetter.nextStreak(state: State, today: number): number
	if state.lastDay == today then
		return state.streak
	end
	if state.lastDay == today - 1 then
		return state.streak + 1
	end
	return math.max(state.streak - 1, 0) + 1
end

--[[
	Засчитывает законченное задание. Засчитывается только то, которое сейчас
	по очереди, и только сегодняшнее: Буквопад с площади в счёт не идёт,
	как и задание, начатое вчера перед полуночью. Возвращает nil, если не засчитано.
]]
function DailyLetter.complete(state: State, today: number, challengeId: string, canMirror: boolean): Outcome?
	if DailyLetter.nextTask(state, today, canMirror) ~= challengeId then
		return nil
	end

	state.done += 1
	local total = #DailyLetter.TASKS
	local outcome: Outcome = {
		done = state.done,
		total = total,
		finished = state.done >= total,
		streak = state.streak,
		bonus = 0,
		streakReward = 0,
	}
	if not outcome.finished then
		return outcome
	end

	state.streak = DailyLetter.nextStreak(state, today)
	state.lastDay = today
	outcome.streak = state.streak
	outcome.bonus = Economy.REWARDS.letterOfTheDay

	if state.streak > state.best then
		state.best = state.streak
		outcome.streakReward = Economy.rewardForStreak(state.streak)
	end
	return outcome
end

return DailyLetter
