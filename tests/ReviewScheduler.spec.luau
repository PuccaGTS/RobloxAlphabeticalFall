--!nocheck
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MasteryRules = require(ReplicatedStorage.Shared.Logic.MasteryRules)
local ReviewScheduler = require(ReplicatedStorage.Shared.Logic.ReviewScheduler)

local DAY = 24 * 60 * 60
local NOW = 1_700_000_000

local function progressAt(mastery, nextReview, lastSeen, step)
	local p = MasteryRules.newProgress(NOW)
	p.mastery = mastery
	p.nextReview = nextReview
	p.lastSeen = lastSeen or NOW
	p.reviewStep = step or 1
	return p
end

return function()
	describe("ReviewScheduler", function()
		it("успех сдвигает интервал вперёд", function()
			local p = progressAt(MasteryRules.FAMILIAR, NOW, NOW, 1)
			local next_ = ReviewScheduler.schedule(p, true, NOW)

			expect(next_.reviewStep).to.equal(2)
			expect(next_.nextReview).to.equal(NOW + DAY)
		end)

		it("ошибка откатывает на шаг назад, а не в ноль", function()
			local p = progressAt(MasteryRules.LEARNED, NOW, NOW, 4)
			local next_ = ReviewScheduler.schedule(p, false, NOW)

			expect(next_.reviewStep).to.equal(3)
			expect(next_.nextReview).to.equal(NOW + 3 * DAY)
		end)

		it("не уходит ниже первого шага", function()
			local p = progressAt(MasteryRules.FAMILIAR, NOW, NOW, 1)
			local next_ = ReviewScheduler.schedule(p, false, NOW)

			expect(next_.reviewStep).to.equal(1)
		end)

		it("не уходит выше последнего шага", function()
			local last = #ReviewScheduler.INTERVALS
			local p = progressAt(MasteryRules.MASTERED, NOW, NOW, last)
			local next_ = ReviewScheduler.schedule(p, true, NOW)

			expect(next_.reviewStep).to.equal(last)
		end)

		it("не мутирует исходный прогресс", function()
			local p = progressAt(MasteryRules.FAMILIAR, NOW, NOW, 1)
			ReviewScheduler.schedule(p, true, NOW)

			expect(p.reviewStep).to.equal(1)
		end)

		describe("очередь сессии", function()
			it("берёт ровно одну новую букву — следующую по программе", function()
				local progress = {
					a = progressAt(MasteryRules.LEARNED, NOW + DAY),
				}
				local queue = ReviewScheduler.buildQueue(progress, { "a", "u", "o", "m" }, NOW)

				expect(#queue.new).to.equal(1)
				expect(queue.new[1]).to.equal("u")
			end)

			it("начинает сессию со знакомой буквы, а не с новой", function()
				local progress = {
					a = progressAt(MasteryRules.FAMILIAR, NOW - 100),
				}
				local queue = ReviewScheduler.buildQueue(progress, { "a", "u" }, NOW)

				expect(#queue.warmup).to.equal(1)
				expect(queue.warmup[1]).to.equal("a")
				expect(queue.flat[1]).to.equal("a")
				expect(queue.flat[2]).to.equal("u")
			end)

			it("сначала подставляет то, что просрочено дольше всех", function()
				local progress = {
					a = progressAt(MasteryRules.FAMILIAR, NOW - 10),
					u = progressAt(MasteryRules.FAMILIAR, NOW - 5000),
					o = progressAt(MasteryRules.FAMILIAR, NOW - 100),
				}
				local queue = ReviewScheduler.buildQueue(progress, { "a", "u", "o" }, NOW)

				-- самая просроченная уходит в разогрев, дальше по убыванию просрочки
				expect(queue.warmup[1]).to.equal("u")
				expect(queue.review[1]).to.equal("o")
				expect(queue.review[2]).to.equal("a")
			end)

			it("не берёт больше MAX_REVIEW букв на повторение", function()
				local ids = {}
				local progress = {}
				for i = 1, 12 do
					local id = "x" .. i
					table.insert(ids, id)
					progress[id] = progressAt(MasteryRules.FAMILIAR, NOW - i)
				end

				local queue = ReviewScheduler.buildQueue(progress, ids, NOW)
				expect(#queue.review + #queue.warmup).to.equal(ReviewScheduler.MAX_REVIEW)
			end)

			it("добавляет освоенные буквы для уверенности, но не больше двух", function()
				local progress = {
					a = progressAt(MasteryRules.MASTERED, NOW + 10 * DAY, NOW - 5 * DAY),
					u = progressAt(MasteryRules.MASTERED, NOW + 10 * DAY, NOW - 4 * DAY),
					o = progressAt(MasteryRules.MASTERED, NOW + 10 * DAY, NOW - 3 * DAY),
				}
				local queue = ReviewScheduler.buildQueue(progress, { "a", "u", "o" }, NOW)

				-- одна ушла в разогрев, ещё максимум две остаются в confident
				expect(#queue.confident <= ReviewScheduler.MAX_CONFIDENT).to.equal(true)
				expect(queue.warmup[1]).to.equal("a")
			end)
		end)
	end)
end
