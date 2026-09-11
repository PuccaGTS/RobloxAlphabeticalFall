--!strict
--[[
	Отчёт о прогрессе для родительского режима. Реализует docs/13-PARENT-MODE.md § 2.

	Чистая логика без Roblox API — покрыта тестами. Собирается ВСЕГДА на сервере:
	по docs/13-PARENT-MODE.md § 8 клиенту статистика уходит только после входа по PIN,
	поэтому в отчёт не попадает ничего из profile.parent — ни хеша PIN, ни лимитов.

	Тон отчёта задан докой и он же проверяется тестом: советы уважительные,
	без обвинений, без сравнения ребёнка с другими детьми и без «купите, чтобы ускорить».

	Дни занятий и серия берутся из посуточной истории (Logic/PlayLog), а не из
	голого поля dailyStreak: поле хранит серию на день последней игры и не знает,
	что с тех пор ребёнок пропустил неделю.
]]

local Types = require(script.Parent.Parent.Types)
local Letters = require(script.Parent.Parent.Config.Letters)
local Stages = require(script.Parent.Parent.Config.Stages)
local MasteryRules = require(script.Parent.MasteryRules)
local PlayLog = require(script.Parent.PlayLog)
local Awards = require(script.Parent.Awards)

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
	--[[
		Сколько букв ребёнок знает ПОДРЯД от начала алфавита. Именно это родитель
		проверяет дома («назови по порядку»), и именно это отличает знание азбуки
		от набора выученных значков.
	]]
	alphabet: { inOrder: number, total: number },
	stages: { unlocked: number, total: number },
	time: {
		totalMin: number,
		sessions: number,
		avgSessionMin: number,
		streakDays: number, -- серия на момент отчёта: пропущен день — ноль
		-- «Занимался activeDays дней из последних windowDays»
		activeDays: number,
		windowDays: number,
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

-- Слово-иллюстрация буквы: нужно советам, чтобы предложить родителю
-- не абстракцию, а конкретную пару слов.
local function exampleWord(letterId: string): string?
	local letter = Letters.get(letterId)
	if letter == nil or letter.example == "" then
		return nil
	end
	return letter.example
end

--[[
	Совет про путающуюся пару. Пары заданы в справочнике (confusableWith), а не
	угадываются: похожие по написанию И/Й, Ш/Щ, Ь/Ъ — методический факт,
	а не статистика. Берём ту пару, на которой ребёнок реально ошибается.
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
	local wordA = exampleWord(bestA)
	local wordB = exampleWord(bestB)

	if wordA ~= nil and wordB ~= nil then
		return {
			id = "confusable",
			text = `{glyphA} и {glyphB} путаются — это нормально в 5 лет. Напишите на бумаге `
				.. `{wordA} и {wordB} и попросите ребёнка найти в них эти буквы.`,
		}
	end
	return {
		id = "confusable",
		text = `{glyphA} и {glyphB} путаются — это нормально в 5 лет. Напишите обе рядом `
			.. `и попросите ребёнка назвать каждую.`,
	}
end

-- Сколько букв ребёнок знает подряд от начала алфавита — общий счёт с постройками двора.
local function lettersInOrder(profile: Types.Profile): number
	return Awards.lettersInOrder(profile.letters)
end

--[[
	Совет про то, что ребёнок уже умеет вне игры: назвать первые буквы азбуки
	по порядку. Это самая ценная строка отчёта — она показывает родителю
	результат, применимый на бумаге, а не только на экране.
]]
local function inOrderTip(profile: Types.Profile): Tip?
	local count = lettersInOrder(profile)
	if count < 3 then
		return nil
	end

	local glyphs: { string } = {}
	for index, letterId in Letters.ordered() do
		if index > count then
			break
		end
		table.insert(glyphs, Letters.expect(letterId).glyph)
	end

	return {
		id = "in_order",
		text = `Ребёнок знает по порядку {count} букв: {table.concat(glyphs, " ")}. `
			.. `Попросите назвать их дома вслух — по игре он это уже умеет.`,
	}
end

local function rhythmTips(streakDays: number, avgSessionMin: number): { Tip }
	local tips: { Tip } = {}

	if streakDays >= ParentReport.GOOD_STREAK_DAYS then
		table.insert(tips, {
			id = "streak",
			text = `Занимались {streakDays} дней подряд — отличный темп. `
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

	-- Порядок алфавитный: ровно та последовательность, по которой идёт ребёнок.
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

	local unlockedStages = 0
	for _, stage in Stages.all do
		local state = profile.stages[stage.index]
		if state ~= nil and state.unlocked then
			unlockedStages += 1
		end
	end

	local sessions = profile.stats.sessionsCount
	local avgSessionMin = if sessions > 0 then profile.stats.totalPlayMin / sessions else 0
	local streakDays = PlayLog.currentStreak(profile, now)

	local tips: { Tip } = {}
	local confusable = confusableTip(profile)
	if confusable ~= nil then
		table.insert(tips, confusable)
	end
	local inOrder = inOrderTip(profile)
	if inOrder ~= nil then
		table.insert(tips, inOrder)
	end
	for _, tip in rhythmTips(streakDays, avgSessionMin) do
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
		alphabet = { inOrder = lettersInOrder(profile), total = Letters.count() },
		stages = { unlocked = unlockedStages, total = Stages.count() },
		time = {
			totalMin = profile.stats.totalPlayMin,
			sessions = sessions,
			avgSessionMin = avgSessionMin,
			streakDays = streakDays,
			activeDays = PlayLog.activeDays(profile.playLog, now, PlayLog.REPORT_WINDOW),
			windowDays = PlayLog.REPORT_WINDOW,
		},
		reviewsDue = reviewsDue,
		details = details,
		tips = tips,
	}
end

return ParentReport
