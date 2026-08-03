--!nocheck
--[[
	Отдельный набор на сборку задания «Моста слогов».

	Причина: испытание падало с «не удалось собрать ни одной секции», когда в очередь
	попадали гласные, из которых не складывается ни одного слога (например О и А —
	слоги есть только для АУ, УА, ИА, АИ). Тест перебирает все пары букв,
	чтобы такой набор нельзя было получить снова.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SyllableBridge = require(ReplicatedStorage.ServerChallenges.SyllableBridge)
local Letters = require(ReplicatedStorage.Shared.Config.Letters)
local Syllables = require(ReplicatedStorage.Shared.Config.Syllables)

return function()
	describe("SyllableBridge.Build не падает ни на каком наборе букв", function()
		it("строит мост из любой пары букв алфавита", function()
			local ids = Letters.ordered()

			for _, first in ids do
				for _, second in ids do
					if first ~= second then
						for difficulty = 1, 5 do
							local ok, result = pcall(function()
								return SyllableBridge.Build(nil, { first, second }, difficulty)
							end)

							if not ok then
								warn(`пара {first}+{second}, сложность {difficulty}: {result}`)
							end
							expect(ok).to.equal(true)
							expect(#result.params.sections > 0).to.equal(true)
						end
					end
				end
			end
		end)

		it("строит мост из одной буквы", function()
			for _, id in Letters.ordered() do
				local ok, result = pcall(function()
					return SyllableBridge.Build(nil, { id }, 2)
				end)

				expect(ok).to.equal(true)
				expect(#result.params.sections > 0).to.equal(true)
			end
		end)

		it("на паре О и А — той самой, что роняла испытание", function()
			local spec = SyllableBridge.Build(nil, { "o", "a" }, 2)

			expect(#spec.params.sections).to.equal(spec.targetCount)
			for _, section in spec.params.sections do
				expect(Syllables.get(section.syllableId)).to.be.ok()
			end
		end)

		it(
			"даёт ровно столько секций, сколько просит сложность",
			function()
				for difficulty = 1, 5 do
					local spec = SyllableBridge.Build(nil, { "m", "a", "u" }, difficulty)
					expect(#spec.params.sections).to.equal(spec.targetCount)
				end
			end
		)

		it(
			"в каждой секции есть верный вариант и нет дублей",
			function()
				local spec = SyllableBridge.Build(nil, { "o", "a" }, 4)

				for _, section in spec.params.sections do
					local seen = {}
					local hasTarget = false
					for _, choice in section.choices do
						expect(seen[choice.letterId]).to.equal(nil)
						seen[choice.letterId] = true
						if choice.letterId == section.targetVowel then
							hasTarget = true
						end
					end
					expect(hasTarget).to.equal(true)
				end
			end
		)
	end)
end
