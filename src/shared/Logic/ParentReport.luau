--!strict
--[[
	Отчёт о прогрессе для родительского режима. Реализует docs/13-PARENT-MODE.md § 2.

	Чистая логика без Roblox API — покрыта тестами. Собирается ВСЕГДА на сервере:
	по docs/13-PARENT-MODE.md § 8 клиенту статистика уходит только после входа по PIN,
	поэтому в отчёт не попадает ничего из profile.parent — ни хеша PIN, ни лимитов.

	Тон отчёта задан докой и он же проверяется тестом: советы уважительные,
	без обвинений, без сравнения ребёнка с другими детьми и без «купите, чтобы ускорить».

	Ограничение, про которое стоит помнить: доки просят строку вида «занимался
	6 дней из последних 7», но профиль хранит только серию подряд (dailyStreak)
	и суммарное время. Поэтому здесь честно отдаётся серия, а посуточная история
	появится, когда в профиле заведут её хранение.
]]

local Types = require(script.Parent.Parent.Types)
local Letters = require(script.Parent.Parent.Config.Letters)
local Syllables = require(script.Parent.Parent.Config.Syllables)
local Words = require(script.Parent.Parent.Config.Words)
local MasteryRules = require(script.Parent.MasteryRules)

local ParentReport = {}

-- Сколько ошибок на букве считаем поводом упомянуть её отдельно.
ParentReport.HARD_MIN_WRONG = 3
ParentReport.HARD_MAX_ITEMS = 5
-- Ниже этой доли верных букву показываем как трудную, даже если ошибок немного.
ParentReport.HARD_MAX_ACCURACY = 0.7
ParentReport.MAX_TIPS = 4
-- Серия, с которой уместно похвалить родителя за режим.
ParentReport.GOOD_STREAK_DAYS = 5
-- Больше этого за сеанс ребёнку 4–5 лет уже много, см. docs/13-PARENT-MODE.md § 5.
ParentReport.LONG_SESSION_MIN = 25

export type HardLetter = {
	letterId: string,
	glyph: string,
	wrong: number,
	accuracy: number,
}

export type LetterDetail = {
	letterId: string,
	glyph: string,
	mastery: number,
	correct: number,
	wrong: number,
	accuracy: number,
	lastSeen: number,
	nextReview: number,
}

export type Tip = {
	id: string,
	text: string,
}

export type Report = {
	letters: {
		total: number,
		touched: number, -- сколько букв ребёнок вообще видел
		mastered: { string }, -- глифы, в методическом порядке программы
		learned: { string },
		familiar: { string },
	},
	hard: { HardLetter },
	syllables: { read: { string }, total: number },
	words: { collected: { string }, total: number },
	time: {
		totalMin: number,
		sessions: number,
		avgSessionMin: number,
		streakDays: number,
	},
	reviewsDue: number, -- сколько букв уже ждут повторения на момент now
	details: { LetterDetail },
	tips: { Tip },
}

local function accuracyOf(progress: Types.LetterProgress): number
	local total = progress.correct + progress.wrong
	if total == 0 then
		return 1
	end
	return progress.correct / total
end

-- Первое слово-иллюстрация буквы: нужно советам, чтобы предложить родителю
-- не абстракцию, а конкретную пару слов.
local function firstWordText(letterId: string): string?
	local letter = Letters.get(letterId)
	if letter == nil then
		return nil
	end
	for _, wordId in letter.examples do
		local word = Words.get(wordId)
		if word ~= nil then
			return word.text
		end
	end
	return nil
end

--[[
	Совет про путающуюся пару. Пары заданы в справочнике (confusableWith), а не
	угадываются: путаница М/Н или Г/К — методический факт, а не статистика.
	Берём ту пару, на которой ребёнок реально ошибается.
]]
local function confusableTip(profile: Types.Profile): Tip?
	local bestA, bestB, bestWrong = nil, nil, 0

	for _, letterId in Letters.ordered() do
		local letter = Letters.expect(letterId)
		local mine = profile.letters[letterId]
		if mine ~= nil then
			for _, otherId in letter.confusableWith do
				local other = profile.letters[otherId]
				if other ~= nil then
					local wrong = mine.wrong + other.wrong
					-- пару считаем один раз: берём ту сторону, что идёт раньше по программе
					local ordered = table.find(Letters.ordered(), letterId) or 0
					local otherOrdered = table.find(Letters.ordered(), otherId) or 0
					if wrong > bestWrong and ordered < otherOrdered then
						bestA, bestB, bestWrong = letterId, otherId, wrong
					end
				end
			end
		end
	end

	if bestA == nil or bestB == nil or bestWrong < ParentReport.HARD_MIN_WRONG then
		return nil
	end

	local glyphA = Letters.expect(bestA).glyph
	local glyphB = Letters.expect(bestB).glyph
	local wordA = firstWordText(bestA)
	local wordB = firstWordText(bestB)

	if wordA ~= nil and wordB ~= nil then
		return {
			id = "confusable",
			text = `{glyphA} и {glyphB} путаются — это нормально в 5 лет. Дома произносите слова `
				.. `{wordA} и {wordB}, пусть ребёнок покажет, что слышит первым.`,
		}
	end
	return {
		id = "confusable",
		text = `{glyphA} и {glyphB} путаются — это нормально в 5 лет. Проговаривайте их дома `
			.. `по очереди и просите ребёнка показать, какой звук он слышит.`,
	}
end

--[[
	Совет про слово, которое ребёнок уже может прочитать: все буквы изучены,
	а само слово ещё не собрано. Это самая ценная строка отчёта — она показывает
	родителю, что игра уже дала результат, применимый вне игры.
]]
local function readyWordTip(profile: Types.Profile): Tip?
	for _, wordId in Words.ids() do
		local word = Words.expect(wordId)
		if profile.words[wordId] ~= true then
			local ready = true
			for _, letterId in word.letters do
				local progress = profile.letters[letterId]
				if progress == nil or progress.mastery < MasteryRules.LEARNED then
					ready = false
					break
				end
			end
			if ready then
				return {
					id = "ready_word",
					text = `Ребёнок уже знает все буквы слова {word.text} — попробуйте вместе `
						.. `прочитать его на бумаге. Игра дала для этого всё необходимое.`,
				}
			end
		end
	end
	return nil
end

local function rhythmTips(profile: Types.Profile, avgSessionMin: number): { Tip }
	local tips: { Tip } = {}

	if profile.dailyStreak >= ParentReport.GOOD_STREAK_DAYS then
		table.insert(tips, {
			id = "streak",
			text = `Занимались {profile.dailyStreak} дней подряд — отличный темп. `
				.. `Больше 20 минут в день не нужно.`,
		})
	end

	if avgSessionMin > ParentReport.LONG_SESSION_MIN then
		table.insert(tips, {
			id = "long_sessions",
			text = `Средний сеанс — {math.floor(avgSessionMin)} минут. `
				.. `10–20 минут в день работают лучше, чем час за раз: память держится на повторениях.`,
		})
	end

	return tips
end

function ParentReport.build(profile: Types.Profile, now: number): Report
	local mastered: { string } = {}
	local learned: { string } = {}
	local familiar: { string } = {}
	local hard: { HardLetter } = {}
	local details: { LetterDetail } = {}
	local touched = 0
	local reviewsDue = 0

	-- Порядок — методический, из программы, а не алфавитный: так родитель видит
	-- ту же последовательность, по которой идёт ребёнок.
	for _, letterId in Letters.ordered() do
		local progress = profile.letters[letterId]
		if progress ~= nil then
			touched += 1
			local letter = Letters.expect(letterId)
			local accuracy = accuracyOf(progress)

			if progress.nextReview <= now then
				reviewsDue += 1
			end

			if progress.mastery >= MasteryRules.MASTERED then
				table.insert(mastered, letter.glyph)
			elseif progress.mastery == MasteryRules.LEARNED then
				table.insert(learned, letter.glyph)
			elseif progress.mastery == MasteryRules.FAMILIAR then
				table.insert(familiar, letter.glyph)
			end

			local looksHard = progress.wrong >= ParentReport.HARD_MIN_WRONG
				or (accuracy < ParentReport.HARD_MAX_ACCURACY and progress.wrong > 0)
			if looksHard then
				table.insert(hard, {
					letterId = letterId,
					glyph = letter.glyph,
					wrong = progress.wrong,
					accuracy = accuracy,
				})
			end

			table.insert(details, {
				letterId = letterId,
				glyph = letter.glyph,
				mastery = progress.mastery,
				correct = progress.correct,
				wrong = progress.wrong,
				accuracy = accuracy,
				lastSeen = progress.lastSeen,
				nextReview = progress.nextReview,
			})
		end
	end

	-- Трудные — сверху те, где ошибок больше; при равенстве держим порядок программы,
	-- чтобы список не прыгал между открытиями экрана.
	table.sort(hard, function(a, b)
		if a.wrong ~= b.wrong then
			return a.wrong > b.wrong
		end
		return a.letterId < b.letterId
	end)
	while #hard > ParentReport.HARD_MAX_ITEMS do
		table.remove(hard)
	end

	local syllablesRead: { string } = {}
	for _, syllableId in Syllables.ids() do
		if profile.syllables[syllableId] == true then
			table.insert(syllablesRead, Syllables.expect(syllableId).text)
		end
	end

	local wordsCollected: { string } = {}
	for _, wordId in Words.ids() do
		if profile.words[wordId] == true then
			table.insert(wordsCollected, Words.expect(wordId).text)
		end
	end

	local sessions = profile.stats.sessionsCount
	local avgSessionMin = if sessions > 0 then profile.stats.totalPlayMin / sessions else 0

	local tips: { Tip } = {}
	local confusable = confusableTip(profile)
	if confusable ~= nil then
		table.insert(tips, confusable)
	end
	local readyWord = readyWordTip(profile)
	if readyWord ~= nil then
		table.insert(tips, readyWord)
	end
	for _, tip in rhythmTips(profile, avgSessionMin) do
		table.insert(tips, tip)
	end
	while #tips > ParentReport.MAX_TIPS do
		table.remove(tips)
	end

	return {
		letters = {
			total = Letters.count(),
			touched = touched,
			mastered = mastered,
			learned = learned,
			familiar = familiar,
		},
		hard = hard,
		syllables = { read = syllablesRead, total = Syllables.count() },
		words = { collected = wordsCollected, total = #Words.ids() },
		time = {
			totalMin = profile.stats.totalPlayMin,
			sessions = sessions,
			avgSessionMin = avgSessionMin,
			streakDays = profile.dailyStreak,
		},
		reviewsDue = reviewsDue,
		details = details,
		tips = tips,
	}
end

return ParentReport
