--!nocheck
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MasteryRules = require(ReplicatedStorage.Shared.Logic.MasteryRules)

local DAY = 24 * 60 * 60
local NOW = 1_700_000_000

local function answer(challengeId, correct, reactionMs, hintsUsed)
	return {
		letterId = "m",
		challengeId = challengeId,
		correct = correct,
		reactionMs = reactionMs or 1500,
		hintsUsed = hintsUsed or 0,
	}
end

return function()
	describe("MasteryRules", function()
		it(
			"после первого успеха буква становится знакомой",
			function()
				local progress = MasteryRules.newProgress(NOW)
				local next_, transition = MasteryRules.applyAnswer(progress, answer("letter_rain", true), NOW)

				expect(next_.mastery).to.equal(MasteryRules.FAMILIAR)
				expect(transition).to.be.ok()
				expect(transition.from).to.equal(MasteryRules.UNKNOWN)
				expect(transition.to).to.equal(MasteryRules.FAMILIAR)
			end
		)

		it("не мутирует исходный прогресс", function()
			local progress = MasteryRules.newProgress(NOW)
			MasteryRules.applyAnswer(progress, answer("letter_rain", true), NOW)

			expect(progress.mastery).to.equal(MasteryRules.UNKNOWN)
			expect(progress.correct).to.equal(0)
		end)

		it(
			"для статуса «изученная» нужны два разных типа испытаний",
			function()
				local progress = MasteryRules.newProgress(NOW)

				-- три успеха, но все в одном испытании — статус не растёт
				for _ = 1, 3 do
					progress = MasteryRules.applyAnswer(progress, answer("letter_rain", true), NOW)
				end
				expect(progress.mastery).to.equal(MasteryRules.FAMILIAR)

				progress = MasteryRules.applyAnswer(progress, answer("bubbles", true), NOW)
				expect(progress.mastery).to.equal(MasteryRules.LEARNED)
			end
		)

		it("ошибка не понижает статус", function()
			local progress = MasteryRules.newProgress(NOW)
			progress = MasteryRules.applyAnswer(progress, answer("letter_rain", true), NOW)
			progress = MasteryRules.applyAnswer(progress, answer("letter_rain", false), NOW)

			expect(progress.mastery).to.equal(MasteryRules.FAMILIAR)
			expect(progress.wrong).to.equal(1)
			expect(progress.streak).to.equal(0)
		end)

		it("«освоенная» недостижима в тот же день", function()
			local progress = MasteryRules.newProgress(NOW)
			progress = MasteryRules.applyAnswer(progress, answer("letter_rain", true), NOW)
			progress = MasteryRules.applyAnswer(progress, answer("letter_rain", true), NOW)
			progress = MasteryRules.applyAnswer(progress, answer("bubbles", true), NOW)
			expect(progress.mastery).to.equal(MasteryRules.LEARNED)

			for _ = 1, 5 do
				progress = MasteryRules.applyAnswer(progress, answer("bubbles", true), NOW)
			end
			expect(progress.mastery).to.equal(MasteryRules.LEARNED)
		end)

		it(
			"«освоенная» даётся за успех после перерыва в два дня",
			function()
				local progress = MasteryRules.newProgress(NOW)
				progress = MasteryRules.applyAnswer(progress, answer("letter_rain", true), NOW)
				progress = MasteryRules.applyAnswer(progress, answer("letter_rain", true), NOW)
				progress = MasteryRules.applyAnswer(progress, answer("bubbles", true), NOW)
				progress = MasteryRules.applyAnswer(progress, answer("bubbles", true), NOW)

				local later = NOW + 2 * DAY + 60
				local next_, transition =
					MasteryRules.applyAnswer(progress, answer("letter_rain", true), later)

				expect(next_.mastery).to.equal(MasteryRules.MASTERED)
				expect(transition.to).to.equal(MasteryRules.MASTERED)
				expect(next_.masteredAt).to.equal(later)
			end
		)

		it(
			"не засчитывает «освоенную», если ответ был с подсказкой",
			function()
				local progress = MasteryRules.newProgress(NOW)
				progress = MasteryRules.applyAnswer(progress, answer("letter_rain", true), NOW)
				progress = MasteryRules.applyAnswer(progress, answer("letter_rain", true), NOW)
				progress = MasteryRules.applyAnswer(progress, answer("bubbles", true), NOW)
				progress = MasteryRules.applyAnswer(progress, answer("bubbles", true), NOW)

				local later = NOW + 3 * DAY
				progress = MasteryRules.applyAnswer(progress, answer("letter_rain", true, 1500, 1), later)

				expect(progress.mastery).to.equal(MasteryRules.LEARNED)
			end
		)

		it(
			"не учитывает неправдоподобно быстрые ответы в среднем времени реакции",
			function()
				local progress = MasteryRules.newProgress(NOW)
				progress = MasteryRules.applyAnswer(progress, answer("letter_rain", true, 10), NOW)

				expect(progress.answers).to.equal(0)
				expect(progress.avgReactionMs).to.equal(0)
				expect(progress.correct).to.equal(1)
			end
		)

		it("считает долю изученных букв набора", function()
			local map = {
				a = MasteryRules.newProgress(NOW),
				u = MasteryRules.newProgress(NOW),
			}
			map.a.mastery = MasteryRules.LEARNED

			expect(MasteryRules.learnedRatio(map, { "a", "u" })).to.equal(0.5)
			expect(MasteryRules.learnedRatio(map, {})).to.equal(0)
		end)
	end)
end
