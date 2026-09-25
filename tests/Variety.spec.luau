--!nocheck
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Variety = require(ReplicatedStorage.Shared.Logic.Variety)
local Economy = require(ReplicatedStorage.Shared.Config.Economy)

return function()
	describe("Logic/Variety — бонус за разнообразие", function()
		it(
			"первое за день занятие — с бонусом, повтор — без",
			function()
				local state, first = Variety.claim(Variety.new(), 100, "letter_rain")
				expect(first).to.equal(true)
				state, first = Variety.claim(state, 100, "letter_rain")
				expect(first).to.equal(false)
				state, first = Variety.claim(state, 100, "bubbles")
				expect(first).to.equal(true)
				expect(#state.done).to.equal(2)
			end
		)

		it("новые сутки — всё снова свежее", function()
			local state = Variety.claim(Variety.new(), 100, "letter_rain")
			local _, first = Variety.claim(state, 101, "letter_rain")
			expect(first).to.equal(true)
		end)

		it("мусор из профиля не ломает учёт", function()
			expect(Variety.sanitize(nil).day).to.equal(0)
			local clean = Variety.sanitize({ day = 5, done = { "a", "a", 7, "b" } })
			expect(#clean.done).to.equal(2)
			local _, first = Variety.claim("мусор", 1, "x")
			expect(first).to.equal(true)
		end)
	end)

	describe("Config/Economy — темп после пересчёта 24.09.2026", function()
		it(
			"семь занятий на площади дают больше, чем самая дорогая стартовая шапка",
			function()
				-- Худший итог каждого занятия, пять верных ответов и бонус за новое.
				local perChallenge = Economy.rewardForChallenge(1)
					+ 5 * Economy.REWARDS.correctAnswer
					+ Economy.REWARDS.varietyBonus
				expect(7 * perChallenge >= 200).to.equal(true)
			end
		)

		it(
			"первый уровень пути стоит больше обычного занятия, и дальние дороже",
			function()
				expect(Economy.rewardForLevel(1) > Economy.rewardForChallenge(3)).to.equal(true)
				expect(Economy.rewardForLevel(11) > Economy.rewardForLevel(1)).to.equal(true)
			end
		)
	end)
end
