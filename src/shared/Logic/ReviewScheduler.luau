--!strict
--[[
	Интервальное повторение. Чистая логика, покрыта тестами.
	Формализует docs/02-LEARNING.md § 6.

	Шаги интервалов: 15 минут → 1 день → 3 дня → 7 дней → 21 день.
	Успех двигает на шаг вперёд, ошибка — на шаг назад (НЕ в ноль: мы не обнуляем
	прогресс ребёнка за одну ошибку).

	Ребёнок никогда не видит слова «повторение»: для него это «буквята соскучились».
]]

local Types = require(script.Parent.Parent.Types)
local MasteryRules = require(script.Parent.MasteryRules)

local ReviewScheduler = {}

local MINUTE = 60
local DAY = 24 * 60 * 60

ReviewScheduler.INTERVALS = { 15 * MINUTE, 1 * DAY, 3 * DAY, 7 * DAY, 21 * DAY }

ReviewScheduler.MAX_REVIEW = 5
ReviewScheduler.MIN_REVIEW = 3
ReviewScheduler.MAX_CONFIDENT = 2
ReviewScheduler.NEW_PER_SESSION = 1

export type Queue = {
	warmup: { string }, -- знакомое для разогрева
	new: { string }, -- новая буква сессии (0 или 1)
	review: { string }, -- то, что пора повторить
	confident: { string }, -- давно освоенное, для уверенности
	flat: { string }, -- всё выше в порядке подачи
}

function ReviewScheduler.intervalFor(step: number): number
	local clamped = math.clamp(step, 1, #ReviewScheduler.INTERVALS)
	return ReviewScheduler.INTERVALS[clamped]
end

--[[
	Двигает шаг повторения после ответа. Возвращает НОВЫЙ прогресс.
]]
function ReviewScheduler.schedule(
	progress: Types.LetterProgress,
	correct: boolean,
	now: number
): Types.LetterProgress
	local next_: Types.LetterProgress = table.clone(progress)
	next_.types = table.clone(progress.types)

	local step = if correct then progress.reviewStep + 1 else progress.reviewStep - 1
	next_.reviewStep = math.clamp(step, 1, #ReviewScheduler.INTERVALS)
	next_.nextReview = now + ReviewScheduler.intervalFor(next_.reviewStep)

	return next_
end

function ReviewScheduler.isDue(progress: Types.LetterProgress, now: number): boolean
	return progress.mastery >= MasteryRules.FAMILIAR and progress.nextReview <= now
end

--[[
	Формирует очередь букв на сессию.

	availableLetterIds — буквы открытых островов В МЕТОДИЧЕСКОМ ПОРЯДКЕ
	(Config/Letters.ordered), чтобы новая буква бралась именно следующая по программе.
]]
function ReviewScheduler.buildQueue(
	progressByLetter: { [string]: Types.LetterProgress },
	availableLetterIds: { string },
	now: number
): Queue
	local due: { string } = {}
	local confident: { string } = {}
	local newLetter: string? = nil

	for _, id in availableLetterIds do
		local p = progressByLetter[id]
		if p == nil or p.mastery == MasteryRules.UNKNOWN then
			if newLetter == nil then
				newLetter = id
			end
		elseif ReviewScheduler.isDue(p, now) then
			table.insert(due, id)
		elseif p.mastery == MasteryRules.MASTERED then
			table.insert(confident, id)
		end
	end

	-- сначала то, что просрочено дольше всех
	table.sort(due, function(a: string, b: string): boolean
		return progressByLetter[a].nextReview < progressByLetter[b].nextReview
	end)
	-- из освоенных берём те, что дольше всех не встречались
	table.sort(confident, function(a: string, b: string): boolean
		return progressByLetter[a].lastSeen < progressByLetter[b].lastSeen
	end)

	local review: { string } = {}
	for i = 1, math.min(#due, ReviewScheduler.MAX_REVIEW) do
		table.insert(review, due[i])
	end

	local confidentPicked: { string } = {}
	for i = 1, math.min(#confident, ReviewScheduler.MAX_CONFIDENT) do
		table.insert(confidentPicked, confident[i])
	end

	-- Разогрев: первую букву сессии берём из знакомого, чтобы ребёнок начал с успеха.
	local warmup: { string } = {}
	if #review > 0 then
		warmup = { table.remove(review, 1) :: string }
	elseif #confidentPicked > 0 then
		warmup = { table.remove(confidentPicked, 1) :: string }
	end

	local newList: { string } = {}
	if newLetter ~= nil then
		table.insert(newList, newLetter)
	end

	local flat: { string } = {}
	for _, list in { warmup, newList, review, confidentPicked } do
		for _, id in list do
			table.insert(flat, id)
		end
	end

	return {
		warmup = warmup,
		new = newList,
		review = review,
		confident = confidentPicked,
		flat = flat,
	}
end

return ReviewScheduler
