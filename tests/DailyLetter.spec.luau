--!nocheck
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DailyLetter = require(ReplicatedStorage.Shared.Logic.DailyLetter)
local Economy = require(ReplicatedStorage.Shared.Config.Economy)

local TODAY = 20500

-- Пройти букву дня целиком за сутки day.
local function finishDay(state, day)
	DailyLetter.refresh(state, day, "m")
	local outcome
	for _, challengeId in DailyLetter.tasks(true) do
		outcome = DailyLetter.complete(state, day, challengeId, true)
	end
	return outcome
end

return function()
	describe("DailyLetter.pick", function()
		it("берёт первую букву очереди повторений", function()
			expect(DailyLetter.pick({ "v", "a" }, { "a", "b", "v" }, TODAY)).to.equal("v")
		end)

		it("без очереди берёт открытую букву по номеру дня", function()
			local available = { "a", "b", "v" }
			local first = DailyLetter.pick({}, available, TODAY)
			local next_ = DailyLetter.pick({}, available, TODAY + 1)

			expect(table.find(available, first)).to.be.ok()
			expect(first).to.never.equal(next_)
			expect(DailyLetter.pick({}, {}, TODAY)).to.equal(nil)
		end)
	end)

	describe("DailyLetter задания", function()
		it(
			"идут по очереди: чужое и повторное не засчитывается",
			function()
				local state = DailyLetter.new()
				DailyLetter.refresh(state, TODAY, "m")

				expect(DailyLetter.nextTask(state, TODAY, true)).to.equal("letter_rain")
				expect(DailyLetter.complete(state, TODAY, "bubbles", true)).to.equal(nil)
				expect(DailyLetter.complete(state, TODAY, "tunnel_run", true)).to.equal(nil)

				local first = DailyLetter.complete(state, TODAY, "letter_rain", true)
				expect(first.done).to.equal(1)
				expect(first.finished).to.equal(false)
				expect(first.bonus).to.equal(0)
				expect(DailyLetter.nextTask(state, TODAY, true)).to.equal("bubbles")
			end
		)

		it(
			"три задания дают бонус и шаг серии, четвёртого нет",
			function()
				local state = DailyLetter.new()
				local outcome = finishDay(state, TODAY)

				expect(outcome.finished).to.equal(true)
				expect(outcome.bonus).to.equal(Economy.REWARDS.letterOfTheDay)
				expect(outcome.streak).to.equal(1)
				expect(DailyLetter.isDone(state, TODAY)).to.equal(true)
				expect(DailyLetter.nextTask(state, TODAY, true)).to.equal(nil)
				expect(DailyLetter.complete(state, TODAY, "mirror", true)).to.equal(nil)
			end
		)

		it(
			"букве без перевёрнутых вариантов Зеркало заменяет Лестница",
			function()
				local tasks = DailyLetter.tasks(false)
				expect(table.find(tasks, "mirror")).to.equal(nil)
				expect(tasks[3]).to.equal(DailyLetter.MIRROR_FALLBACK)
				-- исходный список не портится
				expect(DailyLetter.TASKS[3]).to.equal("mirror")
			end
		)

		it("новый день — новая буква и задания с нуля", function()
			local state = DailyLetter.new()
			finishDay(state, TODAY)

			expect(DailyLetter.refresh(state, TODAY, "b")).to.equal(false)
			expect(state.letterId).to.equal("m")

			expect(DailyLetter.refresh(state, TODAY + 1, "b")).to.equal(true)
			expect(state.letterId).to.equal("b")
			expect(state.done).to.equal(0)
			expect(state.streak).to.equal(1)
		end)

		it("вчерашнее задание сегодня не засчитывается", function()
			local state = DailyLetter.new()
			DailyLetter.refresh(state, TODAY, "m")
			expect(DailyLetter.complete(state, TODAY + 1, "letter_rain", true)).to.equal(nil)
		end)
	end)

	describe("DailyLetter серия", function()
		it("растёт подряд и платит по таблице экономики", function()
			local state = DailyLetter.new()
			local rewards = {}
			for day = 1, 3 do
				local outcome = finishDay(state, TODAY + day)
				rewards[day] = outcome.streakReward
				expect(outcome.streak).to.equal(day)
			end
			expect(rewards[1]).to.equal(0)
			expect(rewards[2]).to.equal(Economy.rewardForStreak(2))
			expect(rewards[3]).to.equal(Economy.rewardForStreak(3))
		end)

		it(
			"пропуск не сжигает серию: день возвращения её не растит",
			function()
				local state = DailyLetter.new()
				for day = 1, 4 do
					finishDay(state, TODAY + day)
				end
				expect(state.streak).to.equal(4)

				local back = finishDay(state, TODAY + 10)
				expect(back.streak).to.equal(4)

				local next_ = finishDay(state, TODAY + 11)
				expect(next_.streak).to.equal(5)
			end
		)

		it("награда за серию только за новый рекорд", function()
			local state = DailyLetter.new()
			state.streak = 1
			state.best = 3
			state.lastDay = TODAY - 1

			local outcome = finishDay(state, TODAY)
			expect(outcome.streak).to.equal(2)
			expect(outcome.streakReward).to.equal(0)
		end)
	end)

	describe("DailyLetter.sanitize", function()
		it("чинит мусор и не даёт рекорду быть ниже серии", function()
			local clean =
				DailyLetter.sanitize({ day = 0 / 0, done = -1, streak = 7, best = 2, letterId = {} })

			expect(clean.day).to.equal(0)
			expect(clean.done).to.equal(0)
			expect(clean.streak).to.equal(7)
			expect(clean.best).to.equal(7)
			expect(clean.letterId).to.equal(nil)
			expect(DailyLetter.sanitize("нет").streak).to.equal(0)
		end)
	end)
end
