--!nocheck
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared

local Economy = require(Shared.Config.Economy)
local MasteryRules = require(Shared.Logic.MasteryRules)

return function()
	describe("Economy", function()
		it("награждает за переход в «изученную»", function()
			local reward = Economy.rewardForMasteryTransition(MasteryRules.FAMILIAR, MasteryRules.LEARNED)
			expect(reward).to.equal(Economy.REWARDS.letterLearned)
		end)

		it("награждает за переход в «освоенную»", function()
			local reward = Economy.rewardForMasteryTransition(MasteryRules.LEARNED, MasteryRules.MASTERED)
			expect(reward).to.equal(Economy.REWARDS.letterMastered)
		end)

		it("не награждает дважды за один и тот же уровень", function()
			expect(Economy.rewardForMasteryTransition(MasteryRules.LEARNED, MasteryRules.LEARNED)).to.equal(0)
			expect(Economy.rewardForMasteryTransition(MasteryRules.MASTERED, MasteryRules.MASTERED)).to.equal(0)
		end)

		it("не награждает за первое знакомство с буквой", function()
			expect(Economy.rewardForMasteryTransition(MasteryRules.UNKNOWN, MasteryRules.FAMILIAR)).to.equal(0)
		end)

		it("за проход испытания всегда даёт не меньше гарантированного минимума", function()
			for stars = 1, 3 do
				expect(Economy.rewardForChallenge(stars) >= Economy.REWARDS.challengeMinimum).to.equal(true)
			end
			expect(Economy.rewardForChallenge(0) >= Economy.REWARDS.challengeMinimum).to.equal(true)
		end)

		it("три звезды выгоднее одной", function()
			expect(Economy.rewardForChallenge(3) > Economy.rewardForChallenge(1)).to.equal(true)
		end)

		it("не даёт звёздочек за несуществующую серию дней", function()
			expect(Economy.rewardForStreak(4)).to.equal(0)
			expect(Economy.rewardForStreak(7) > 0).to.equal(true)
		end)

		it("цены тиров не пересекаются и растут", function()
			for tier = 0, 3 do
				local current = Economy.PRICE_TIERS[tier]
				local next_ = Economy.PRICE_TIERS[tier + 1]
				expect(current.min < current.max).to.equal(true)
				expect(current.max < next_.min).to.equal(true)
			end
		end)

		it("первая покупка по карману после первого испытания", function()
			-- принцип из docs/04-ECONOMY.md: ребёнок тратит звёздочки в первые 5 минут
			local afterFirstChallenge = Economy.rewardForChallenge(2)
			expect(afterFirstChallenge >= Economy.PRICE_TIERS[0].min).to.equal(true)
		end)
	end)
end
