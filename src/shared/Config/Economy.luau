--!strict
--[[
	Экономика: источники и размеры наград. См. docs/04-ECONOMY.md.

	Принцип: Звёздочки капают ТОЛЬКО за обучающие действия.
	Никаких наград за время в игре — иначе ребёнок будет «фармить» вместо учёбы.

	Полосу препятствий это правило тоже касается: за пройденный паркур не начисляется
	ничего. Звёздочки в ней дают только ворота с буквами, а итог забега засчитывается
	лишь тогда, когда на воротах был хотя бы один ответ (см. ChallengeService).

	Все начисления проходят через сервер (EconomyService), клиент ничего не считает.
]]

local MasteryRules = require(script.Parent.Parent.Logic.MasteryRules)

local Economy = {}

Economy.CURRENCY_NAME = "Звёздочки"

Economy.REWARDS = {
	correctAnswer = 1,
	challengeStars = { 5, 10, 20 }, -- за 1, 2 и 3 звезды результата
	challengeMinimum = 3, -- даём всегда, даже при худшем проходе
	letterLearned = 15, -- переход в статус 2, один раз на букву
	letterMastered = 40, -- переход в статус 3, один раз на букву
	stageCleared = 60, -- ступень пройдена настолько, что открылась следующая
	letterOfTheDay = 30,
	secretChest = 15,
	coopHelp = 10,
}

Economy.DAILY_STREAK_REWARDS = {
	[2] = 10,
	[3] = 20,
	[5] = 25,
	[7] = 50,
	[14] = 100,
	[30] = 250,
}

-- Защита экономики: потолок начислений в час на игрока. Превышение — сигнал в лог,
-- а не бан: ребёнок не должен пострадать от нашей ошибки в балансе.
Economy.MAX_STARS_PER_HOUR = 400

Economy.COOP_HELP_DAILY_CAP = 3

--[[
	Ценовые тиры витрины, см. docs/04-ECONOMY.md § 3.

	Диапазоны идут встык, без дыр между тирами. Раньше между ними были пробелы
	(26–49, 121–199 и так далее), и любая цена, попавшая в пробел, не принадлежала
	ни одному тиру — предмет за 35 ⭐ формально нарушал правила витрины,
	хотя с ним всё было в порядке.
]]
Economy.PRICE_TIERS = {
	[0] = { min = 10, max = 49 },
	[1] = { min = 50, max = 199 },
	[2] = { min = 200, max = 499 },
	[3] = { min = 500, max = 1199 },
	[4] = { min = 1200, max = 2000 },
}

function Economy.rewardForMasteryTransition(from: number, to: number): number
	if from < MasteryRules.LEARNED and to >= MasteryRules.LEARNED then
		local reward = Economy.REWARDS.letterLearned
		if to >= MasteryRules.MASTERED then
			reward += Economy.REWARDS.letterMastered
		end
		return reward
	end
	if from < MasteryRules.MASTERED and to >= MasteryRules.MASTERED then
		return Economy.REWARDS.letterMastered
	end
	return 0
end

function Economy.rewardForChallenge(stars: number): number
	local index = math.clamp(math.floor(stars), 1, #Economy.REWARDS.challengeStars)
	return math.max(Economy.REWARDS.challengeStars[index], Economy.REWARDS.challengeMinimum)
end

function Economy.rewardForStreak(day: number): number
	return Economy.DAILY_STREAK_REWARDS[day] or 0
end

return Economy
