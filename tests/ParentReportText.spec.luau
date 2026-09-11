--!nocheck
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared

local ParentReport = require(Shared.Logic.ParentReport)
local ParentReportText = require(Shared.Logic.ParentReportText)
local MasteryRules = require(Shared.Logic.MasteryRules)
local ProfileTemplate = require(Shared.Config.ProfileTemplate)
local Letters = require(Shared.Config.Letters)

local NOW = 1_700_000_000
local DAY = 24 * 60 * 60

local function reportWith(letters)
	local profile = ProfileTemplate.new(NOW)
	for letterId, fields in letters do
		local progress = MasteryRules.newProgress(NOW)
		for key, value in fields do
			progress[key] = value
		end
		profile.letters[letterId] = progress
	end
	return ParentReport.build(profile, NOW)
end

local function hasLine(lines, fragment)
	for _, line in lines do
		if string.find(line, fragment, 1, true) then
			return true
		end
	end
	return false
end

return function()
	describe("ParentReportText.plural", function()
		it("склоняет по-русски", function()
			local function f(n)
				return ParentReportText.plural(n, "буква", "буквы", "букв")
			end
			expect(f(1)).to.equal("буква")
			expect(f(2)).to.equal("буквы")
			expect(f(4)).to.equal("буквы")
			expect(f(5)).to.equal("букв")
			expect(f(11)).to.equal("букв")
			expect(f(12)).to.equal("букв")
			expect(f(14)).to.equal("букв")
			expect(f(21)).to.equal("буква")
			expect(f(22)).to.equal("буквы")
			expect(f(33)).to.equal("буквы")
			expect(f(0)).to.equal("букв")
			expect(f(111)).to.equal("букв")
		end)
	end)

	describe("ParentReportText.duration", function()
		it("часы и минуты как в доке", function()
			expect(ParentReportText.duration(160)).to.equal("2 ч 40 мин")
			expect(ParentReportText.duration(14)).to.equal("14 мин")
			expect(ParentReportText.duration(120)).to.equal("2 ч")
			expect(ParentReportText.duration(0.4)).to.equal("меньше минуты")
			expect(ParentReportText.duration(14.9)).to.equal("14 мин")
		end)
	end)

	describe("ParentReportText.bar", function()
		it("полоска всегда нужной длины", function()
			for _, letters in
				{
					{},
					{ a = { mastery = 3 }, b = { mastery = 2 }, v = { mastery = 1 } },
				}
			do
				local bar = ParentReportText.bar(reportWith(letters))
				expect(utf8.len(bar)).to.equal(ParentReportText.BAR_WIDTH)
			end
		end)

		it("все буквы освоены — полоска сплошная", function()
			local all = {}
			for _, id in Letters.ordered() do
				all[id] = { mastery = MasteryRules.MASTERED }
			end
			expect(ParentReportText.bar(reportWith(all))).to.equal(
				string.rep("█", ParentReportText.BAR_WIDTH)
			)
		end)
	end)

	describe("ParentReportText.summary", function()
		it("новый профиль: честные нули, без выдумок", function()
			local lines = ParentReportText.summary(reportWith({}))
			expect(lines[1]).to.equal("Азбука: 0 из 33 букв")
			expect(hasLine(lines, "Знает подряд от А: пока ни одной")).to.equal(true)
			expect(hasLine(lines, "Даются трудно")).to.equal(false)
		end)

		it("буквы подряд от А перечислены по порядку", function()
			local lines = ParentReportText.summary(reportWith({
				a = { mastery = MasteryRules.MASTERED },
				b = { mastery = MasteryRules.LEARNED },
				v = { mastery = MasteryRules.LEARNED },
				d = { mastery = MasteryRules.MASTERED }, -- после пропуска Г: в счёт подряд не идёт
			}))
			expect(hasLine(lines, "Знает подряд от А: 3 буквы — А Б В")).to.equal(
				true
			)
			expect(lines[1]).to.equal("Азбука: 4 из 33 букв")
		end)

		it("трудные буквы — с числом ошибок", function()
			local lines = ParentReportText.summary(reportWith({
				i = { mastery = 1, correct = 2, wrong = 7 },
			}))
			expect(hasLine(lines, "Даются трудно: И (7 ошибок)")).to.equal(true)
		end)

		-- Имени и пола ребёнка игра не знает: ни одного «занимался» или «занималась».
		it("не угадывает пол ребёнка", function()
			local lines = ParentReportText.summary(reportWith({ a = { mastery = 3 } }))
			for _, line in lines do
				expect(string.find(line, "лся", 1, true)).to.equal(nil)
				expect(string.find(line, "лась", 1, true)).to.equal(nil)
			end
		end)
	end)

	describe("ParentReportText.details", function()
		it("строка на каждую встреченную букву", function()
			local lines = ParentReportText.details(
				reportWith({
					a = { mastery = 3, correct = 9, wrong = 1, nextReview = NOW + 3 * DAY },
					b = { mastery = 1, correct = 1, wrong = 0, nextReview = NOW - 10 },
				}),
				NOW
			)
			expect(#lines).to.equal(2)
			expect(lines[1]).to.equal(
				"А — освоена · 10 ответов · 90% верных · повтор через 3 дня"
			)
			expect(
				hasLine(
					lines,
					"Б — в работе · 1 ответ · 100% верных · повторить сегодня"
				)
			).to.equal(true)
		end)

		it("пустой профиль — пояснение, а не пустой экран", function()
			expect(#ParentReportText.details(reportWith({}), NOW)).to.equal(1)
		end)
	end)

	describe("ParentReportText — дома и микрофон", function()
		it(
			"шесть карточек, первая — про то, чему игра не учит",
			function()
				expect(#ParentReportText.HOME).to.equal(6)
				expect(string.find(ParentReportText.HOME[1], "не чтению", 1, true)).to.be.ok()
			end
		)

		it("советов нет — есть что сказать всё равно", function()
			expect(#ParentReportText.tips(reportWith({}))).to.equal(1)
		end)
	end)
end
