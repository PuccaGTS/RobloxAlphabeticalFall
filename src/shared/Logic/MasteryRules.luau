--!strict
--[[
	Правила освоения буквы. Чистая логика без Roblox API — покрыта тестами.
	Формализует docs/01-GDD.md § 4 и docs/02-LEARNING.md § 9.

	0 незнакомая → 1 знакомая  : один успех
	1 знакомая   → 2 изученная : >= 3 успехов в >= 2 разных типах испытаний
	2 изученная  → 3 освоенная : >= 5 успехов, >= 2 типов, успех ПОСЛЕ перерыва >= 2 дней,
	                             средняя реакция < 4 с, ответ без подсказки

	Понижения статуса нет никогда: ребёнка не откатывают за ошибку.
	Забывание отрабатывается через повторения (Logic/ReviewScheduler).
]]

local Types = require(script.Parent.Parent.Types)

local MasteryRules = {}

MasteryRules.UNKNOWN = 0
MasteryRules.FAMILIAR = 1
MasteryRules.LEARNED = 2
MasteryRules.MASTERED = 3

MasteryRules.LEARNED_MIN_CORRECT = 3
MasteryRules.LEARNED_MIN_TYPES = 2
MasteryRules.MASTERED_MIN_CORRECT = 5
MasteryRules.MASTERED_MIN_TYPES = 2
MasteryRules.MASTERED_MIN_GAP_SECONDS = 2 * 24 * 60 * 60
MasteryRules.MASTERED_MAX_AVG_REACTION_MS = 4000

-- Ответ быстрее этого порога физически невозможен для ребёнка: не засчитываем в статистику
-- освоения (но и не наказываем — просто не учитываем). См. docs/07-TECH-ARCH.md § 7.
MasteryRules.MIN_PLAUSIBLE_REACTION_MS = 120

export type Transition = {
	letterId: string,
	from: number,
	to: number,
}

function MasteryRules.newProgress(now: number): Types.LetterProgress
	return {
		mastery = MasteryRules.UNKNOWN,
		correct = 0,
		wrong = 0,
		streak = 0,
		types = {},
		lastSeen = now,
		learnedAt = nil,
		masteredAt = nil,
		reviewStep = 1,
		nextReview = now,
		avgReactionMs = 0,
		answers = 0,
	}
end

local function hasType(list: { string }, value: string): boolean
	return table.find(list, value) ~= nil
end

--[[
	Применяет один ответ и возвращает НОВЫЙ прогресс (исходный не мутируется)
	плюс переход статуса, если он произошёл.
]]
function MasteryRules.applyAnswer(
	progress: Types.LetterProgress,
	answer: Types.Answer,
	now: number
): (Types.LetterProgress, Transition?)
	local next_: Types.LetterProgress = table.clone(progress)
	next_.types = table.clone(progress.types)
	next_.lastSeen = now

	local plausible = answer.reactionMs >= MasteryRules.MIN_PLAUSIBLE_REACTION_MS

	if not answer.correct then
		next_.wrong += 1
		next_.streak = 0
		return next_, nil
	end

	next_.correct += 1
	next_.streak += 1

	if not hasType(next_.types, answer.challengeId) then
		table.insert(next_.types, answer.challengeId)
	end

	if plausible then
		next_.answers += 1
		-- скользящее среднее по засчитанным успешным ответам
		next_.avgReactionMs = progress.avgReactionMs
			+ (answer.reactionMs - progress.avgReactionMs) / next_.answers
	end

	local from = next_.mastery
	local to = from

	if from == MasteryRules.UNKNOWN then
		to = MasteryRules.FAMILIAR
	elseif from == MasteryRules.FAMILIAR then
		local enough = next_.correct >= MasteryRules.LEARNED_MIN_CORRECT
			and #next_.types >= MasteryRules.LEARNED_MIN_TYPES
		if enough then
			to = MasteryRules.LEARNED
		end
	elseif from == MasteryRules.LEARNED then
		local learnedAt = next_.learnedAt or now
		local gapOk = (now - learnedAt) >= MasteryRules.MASTERED_MIN_GAP_SECONDS
		local enough = next_.correct >= MasteryRules.MASTERED_MIN_CORRECT
			and #next_.types >= MasteryRules.MASTERED_MIN_TYPES
			and next_.avgReactionMs > 0
			and next_.avgReactionMs < MasteryRules.MASTERED_MAX_AVG_REACTION_MS
			and answer.hintsUsed == 0
			and plausible
		if gapOk and enough then
			to = MasteryRules.MASTERED
		end
	end

	if to == from then
		return next_, nil
	end

	next_.mastery = to
	if to == MasteryRules.LEARNED then
		next_.learnedAt = now
	elseif to == MasteryRules.MASTERED then
		next_.masteredAt = now
	end

	return next_, { letterId = answer.letterId, from = from, to = to }
end

-- Доля букв набора, дошедших хотя бы до статуса «изученная». Нужна для открытия островов.
function MasteryRules.learnedRatio(
	progressByLetter: { [string]: Types.LetterProgress },
	letterIds: { string }
): number
	if #letterIds == 0 then
		return 0
	end
	local learned = 0
	for _, id in letterIds do
		local p = progressByLetter[id]
		if p and p.mastery >= MasteryRules.LEARNED then
			learned += 1
		end
	end
	return learned / #letterIds
end

return MasteryRules
