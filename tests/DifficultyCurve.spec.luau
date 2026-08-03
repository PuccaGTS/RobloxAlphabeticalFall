--!nocheck
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DifficultyCurve = require(ReplicatedStorage.Shared.Logic.DifficultyCurve)

return function()
	describe("DifficultyCurve", function()
		it(
			"понижает уровень после трёх ошибок подряд и включает подсказки",
			function()
				local level = 3
				local streaks = DifficultyCurve.newStreaks()

				local result
				for _ = 1, 3 do
					result = DifficultyCurve.apply(level, streaks, false)
					level, streaks = result.level, result.streaks
				end

				expect(level).to.equal(2)
				expect(result.changed).to.equal(-1)
				expect(result.forceHints).to.equal(true)
			end
		)

		it("повышает уровень после пяти успехов подряд", function()
			local level = 2
			local streaks = DifficultyCurve.newStreaks()

			local result
			for _ = 1, 5 do
				result = DifficultyCurve.apply(level, streaks, true)
				level, streaks = result.level, result.streaks
			end

			expect(level).to.equal(3)
			expect(result.changed).to.equal(1)
		end)

		it("сбрасывает серию ошибок после верного ответа", function()
			local level = 3
			local streaks = DifficultyCurve.newStreaks()

			for _ = 1, 2 do
				local r = DifficultyCurve.apply(level, streaks, false)
				level, streaks = r.level, r.streaks
			end
			local r = DifficultyCurve.apply(level, streaks, true)

			expect(r.streaks.wrongInRow).to.equal(0)
			expect(r.level).to.equal(3)
		end)

		it("не выходит за потолок сложности", function()
			local level = DifficultyCurve.MAX_LEVEL
			local streaks = DifficultyCurve.newStreaks()

			for _ = 1, 20 do
				local r = DifficultyCurve.apply(level, streaks, true)
				level, streaks = r.level, r.streaks
			end

			expect(level).to.equal(DifficultyCurve.MAX_LEVEL)
		end)

		it("не опускается ниже первого уровня", function()
			local level = DifficultyCurve.MIN_LEVEL
			local streaks = DifficultyCurve.newStreaks()

			for _ = 1, 20 do
				local r = DifficultyCurve.apply(level, streaks, false)
				level, streaks = r.level, r.streaks
			end

			expect(level).to.equal(DifficultyCurve.MIN_LEVEL)
		end)

		it(
			"достаёт параметр испытания по уровню с зажимом по краям",
			function()
				local values = { 5, 5, 6, 7, 8 }

				expect(DifficultyCurve.pick(values, 1)).to.equal(5)
				expect(DifficultyCurve.pick(values, 4)).to.equal(7)
				expect(DifficultyCurve.pick(values, 99)).to.equal(8)
				expect(DifficultyCurve.pick(values, 0)).to.equal(5)
			end
		)
	end)
end
