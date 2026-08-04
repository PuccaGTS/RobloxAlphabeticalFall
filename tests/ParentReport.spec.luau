--!nocheck
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ParentReport = require(ReplicatedStorage.Shared.Logic.ParentReport)
local ProfileTemplate = require(ReplicatedStorage.Shared.Config.ProfileTemplate)
local MasteryRules = require(ReplicatedStorage.Shared.Logic.MasteryRules)
local Letters = require(ReplicatedStorage.Shared.Config.Letters)
local Words = require(ReplicatedStorage.Shared.Config.Words)

local NOW = 1770000000
local DAY = 24 * 60 * 60

local function profileWith(letters, extra)
	local profile = ProfileTemplate.new(NOW)
	for letterId, fields in letters do
		local progress = MasteryRules.newProgress(NOW)
		for key, value in fields do
			progress[key] = value
		end
		profile.letters[letterId] = progress
	end
	for key, value in extra or {} do
		profile[key] = value
	end
	return profile
end

local function contains(list, value)
	return table.find(list, value) ~= nil
end

local function tipById(report, id)
	for _, tip in report.tips do
		if tip.id == id then
			return tip
		end
	end
	return nil
end

return function()
	describe("ParentReport.Состав", function()
		it("на новом профиле ничего не выдумывает", function()
			local report = ParentReport.build(ProfileTemplate.new(NOW), NOW)

			expect(report.letters.touched).to.equal(0)
			expect(#report.letters.mastered).to.equal(0)
			expect(#report.hard).to.equal(0)
			expect(#report.syllables.read).to.equal(0)
			expect(#report.words.collected).to.equal(0)
			expect(report.time.avgSessionMin).to.equal(0)
			expect(report.letters.total).to.equal(Letters.count())
		end)

		it("раскладывает буквы по статусам", function()
			local report = ParentReport.build(
				profileWith({
					a = { mastery = MasteryRules.MASTERED },
					u = { mastery = MasteryRules.LEARNED },
					o = { mastery = MasteryRules.FAMILIAR },
					i = { mastery = MasteryRules.UNKNOWN },
				}),
				NOW
			)

			expect(contains(report.letters.mastered, Letters.expect("a").glyph)).to.equal(true)
			expect(contains(report.letters.learned, Letters.expect("u").glyph)).to.equal(true)
			expect(contains(report.letters.familiar, Letters.expect("o").glyph)).to.equal(true)
			-- незнакомая буква не попадает ни в один список, но считается «виденной»
			expect(report.letters.touched).to.equal(4)
		end)

		it(
			"идёт в методическом порядке программы, а не по алфавиту",
			function()
				local report = ParentReport.build(
					profileWith({
						m = { mastery = MasteryRules.MASTERED },
						a = { mastery = MasteryRules.MASTERED },
					}),
					NOW
				)
				-- А идёт раньше М по программе, значит и в отчёте она первая
				expect(report.letters.mastered[1]).to.equal(Letters.expect("a").glyph)
			end
		)

		it(
			"считает буквы, у которых подошёл срок повторения",
			function()
				local report = ParentReport.build(
					profileWith({
						a = { nextReview = NOW - DAY },
						u = { nextReview = NOW + DAY },
						o = { nextReview = NOW },
					}),
					NOW
				)
				expect(report.reviewsDue).to.equal(2)
			end
		)

		it("считает среднюю длину сеанса", function()
			local profile = ProfileTemplate.new(NOW)
			profile.stats.totalPlayMin = 140
			profile.stats.sessionsCount = 10
			local report = ParentReport.build(profile, NOW)
			expect(report.time.avgSessionMin).to.equal(14)
		end)
	end)

	describe("ParentReport.Трудные буквы", function()
		it(
			"показывает буквы с ошибками, начиная с самой трудной",
			function()
				local report = ParentReport.build(
					profileWith({
						a = { correct = 10, wrong = 7 },
						u = { correct = 10, wrong = 5 },
						o = { correct = 10, wrong = 0 },
					}),
					NOW
				)

				expect(#report.hard).to.equal(2)
				expect(report.hard[1].wrong).to.equal(7)
				expect(report.hard[2].wrong).to.equal(5)
			end
		)

		it("не считает трудной букву без ошибок", function()
			local report = ParentReport.build(profileWith({ a = { correct = 20, wrong = 0 } }), NOW)
			expect(#report.hard).to.equal(0)
		end)

		it("не вываливает бесконечный список", function()
			local letters = {}
			for _, id in Letters.ordered() do
				letters[id] = { correct = 1, wrong = 9 }
			end
			local report = ParentReport.build(profileWith(letters), NOW)
			expect(#report.hard <= ParentReport.HARD_MAX_ITEMS).to.equal(true)
		end)
	end)

	describe("ParentReport.Советы", function()
		it(
			"советует пару слов, когда путаются похожие буквы",
			function()
				-- А и О заданы в справочнике как путающаяся пара
				local report = ParentReport.build(
					profileWith({
						a = { correct = 5, wrong = 6 },
						o = { correct = 5, wrong = 6 },
					}),
					NOW
				)

				local tip = tipById(report, "confusable")
				expect(tip).to.be.ok()
				expect(string.find(tip.text, Letters.expect("a").glyph, 1, true) ~= nil).to.equal(true)
			end
		)

		it("молчит про путаницу, когда ошибок почти нет", function()
			local report = ParentReport.build(
				profileWith({
					a = { correct = 20, wrong = 0 },
					o = { correct = 20, wrong = 0 },
				}),
				NOW
			)
			expect(tipById(report, "confusable")).to.never.be.ok()
		end)

		it(
			"предлагает прочитать слово, буквы которого уже изучены",
			function()
				local mama = Words.expect("mama")
				local letters = {}
				for _, letterId in mama.letters do
					letters[letterId] = { mastery = MasteryRules.LEARNED }
				end

				local report = ParentReport.build(profileWith(letters), NOW)
				local tip = tipById(report, "ready_word")

				expect(tip).to.be.ok()
				expect(string.find(tip.text, mama.text, 1, true) ~= nil).to.equal(true)
			end
		)

		it(
			"не предлагает слово, если хоть одна буква ещё не изучена",
			function()
				local mama = Words.expect("mama")
				local letters = {}
				for _, letterId in mama.letters do
					letters[letterId] = { mastery = MasteryRules.FAMILIAR }
				end
				local report = ParentReport.build(profileWith(letters), NOW)
				expect(tipById(report, "ready_word")).to.never.be.ok()
			end
		)

		it(
			"не предлагает слово, которое ребёнок уже собрал",
			function()
				local mama = Words.expect("mama")
				local letters = {}
				for _, letterId in mama.letters do
					letters[letterId] = { mastery = MasteryRules.MASTERED }
				end
				local profile = profileWith(letters)
				for _, wordId in Words.ids() do
					profile.words[wordId] = true
				end
				local report = ParentReport.build(profile, NOW)
				expect(tipById(report, "ready_word")).to.never.be.ok()
			end
		)

		it(
			"хвалит за регулярность и сразу ограничивает аппетит",
			function()
				local profile = ProfileTemplate.new(NOW)
				profile.dailyStreak = 6
				local tip = tipById(ParentReport.build(profile, NOW), "streak")

				expect(tip).to.be.ok()
				expect(string.find(tip.text, "20 минут", 1, true) ~= nil).to.equal(true)
			end
		)

		it("мягко предупреждает о слишком долгих сеансах", function()
			local profile = ProfileTemplate.new(NOW)
			profile.stats.totalPlayMin = 120
			profile.stats.sessionsCount = 4 -- по 30 минут
			expect(tipById(ParentReport.build(profile, NOW), "long_sessions")).to.be.ok()
		end)

		it("не сыплет советами", function()
			local letters = {}
			for _, id in Letters.ordered() do
				letters[id] = { mastery = MasteryRules.MASTERED, correct = 5, wrong = 9 }
			end
			local profile = profileWith(letters)
			profile.dailyStreak = 30
			profile.stats.totalPlayMin = 600
			profile.stats.sessionsCount = 10

			local report = ParentReport.build(profile, NOW)
			expect(#report.tips <= ParentReport.MAX_TIPS).to.equal(true)
		end)

		it(
			"в советах нет давления, продаж и сравнения с другими детьми",
			function()
				-- Тон задан docs/13-PARENT-MODE.md § 2 и § 7 и держится тестом
				local forbidden = {
					"Robux",
					"робукс",
					"купи",
					"скидк",
					"быстрее всех",
					"других детей",
					"отстаёт",
					"хуже",
				}

				local letters = {}
				for _, id in Letters.ordered() do
					letters[id] = { mastery = MasteryRules.LEARNED, correct = 5, wrong = 9 }
				end
				local profile = profileWith(letters)
				profile.dailyStreak = 10
				profile.stats.totalPlayMin = 600
				profile.stats.sessionsCount = 10

				for _, tip in ParentReport.build(profile, NOW).tips do
					for _, word in forbidden do
						if string.find(string.lower(tip.text), string.lower(word), 1, true) ~= nil then
							error(
								`совет «{tip.id}» содержит запрещённое «{word}»: {tip.text}`
							)
						end
					end
				end
			end
		)
	end)

	describe("ParentReport.Приватность", function()
		it("не выносит в отчёт родительский PIN и лимиты", function()
			local profile = ProfileTemplate.new(NOW)
			profile.parent.pinHash = "секретный-хеш"
			profile.parent.dailyLimitMin = 20

			local function scan(value, path)
				if type(value) == "string" then
					if string.find(value, "секретный-хеш", 1, true) ~= nil then
						error(`PIN утёк в отчёт: {path}`)
					end
				elseif type(value) == "table" then
					for key, nested in value do
						scan(nested, `{path}.{tostring(key)}`)
					end
				end
			end

			local report = ParentReport.build(profile, NOW)
			scan(report, "report")
			expect(report.parent).to.never.be.ok()
		end)

		it("не отдаёт ссылки на таблицы профиля", function()
			local profile = profileWith({ a = { mastery = MasteryRules.MASTERED } })
			local report = ParentReport.build(profile, NOW)

			table.insert(report.letters.mastered, "ЛИШНЕЕ")
			expect(profile.letters.a.mastery).to.equal(MasteryRules.MASTERED)
			expect(#ParentReport.build(profile, NOW).letters.mastered).to.equal(1)
		end)
	end)
end
