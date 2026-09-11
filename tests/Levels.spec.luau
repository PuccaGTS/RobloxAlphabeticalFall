--!nocheck
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Levels = require(ReplicatedStorage.Shared.Config.Levels)
local Stages = require(ReplicatedStorage.Shared.Config.Stages)
local Letters = require(ReplicatedStorage.Shared.Config.Letters)
local Tunnel = require(ReplicatedStorage.Shared.Config.Tunnel)

local function flatten(groups)
	local all = {}
	for _, group in groups do
		for _, id in group do
			table.insert(all, id)
		end
	end
	return all
end

return function()
	describe("Levels — путь мира букв", function()
		it(
			"уровней столько же, сколько ступеней, и идут они подряд",
			function()
				expect(Levels.count()).to.equal(Stages.count())
				for index, level in Levels.all do
					expect(level.index).to.equal(index)
					expect(Stages.get(index)).to.be.ok()
				end
			end
		)

		-- docs/14-TUNNEL-MODE.md § 3.3: 4–6 отрезков между сохранками
		it("в уровне от четырёх до шести отрезков", function()
			for _, level in Levels.all do
				expect(level.segments >= 4 and level.segments <= 6).to.equal(true)
			end
		end)

		it("путь не становится короче к концу", function()
			for index = 2, Levels.count() do
				expect(Levels.all[index].segments >= Levels.all[index - 1].segments).to.equal(true)
			end
		end)

		it(
			"проёмов от двух до числа дорожек, на первом уровне два",
			function()
				expect(Levels.all[1].maxChoices).to.equal(2)
				for _, level in Levels.all do
					expect(level.maxChoices >= 2 and level.maxChoices <= Tunnel.LANE_COUNT).to.equal(true)
				end
			end
		)

		-- Отрезков должно хватать на все новые буквы ступени, иначе одна из них не прозвучит.
		it("отрезков не меньше, чем новых букв на ступени", function()
			for _, level in Levels.all do
				expect(level.segments >= #Levels.stage(level.index).letters).to.equal(true)
			end
		end)
	end)

	describe("Levels.current — куда ведёт портал", function()
		it("новичка — на первый уровень", function()
			expect(Levels.current(0)).to.equal(1)
			expect(Levels.current(nil)).to.equal(1)
		end)

		it("после пройденного — на следующий", function()
			expect(Levels.current(1)).to.equal(2)
			expect(Levels.current(4)).to.equal(5)
		end)

		it("после всех — на последний, а не в пустоту", function()
			expect(Levels.current(Levels.count())).to.equal(Levels.count())
			expect(Levels.current(999)).to.equal(Levels.count())
		end)

		it("мусор из профиля ведёт на первый уровень", function()
			expect(Levels.current("пять")).to.equal(1)
			expect(Levels.current(-3)).to.equal(1)
		end)
	end)

	describe("Levels.targets — буква каждого отрезка", function()
		it("сначала три новые буквы ступени по алфавиту", function()
			for _, level in Levels.all do
				local fresh = Levels.stage(level.index).letters
				local targets = Levels.targets(level.index, Letters.ordered())
				for slot, id in fresh do
					expect(targets[slot]).to.equal(id)
				end
			end
		end)

		it("буква на каждый отрезок, не больше и не меньше", function()
			for _, level in Levels.all do
				expect(#Levels.targets(level.index, {})).to.equal(level.segments)
			end
		end)

		it(
			"повторение — только с прошлых ступеней, в порядке очереди",
			function()
				-- Очередь нарочно не по алфавиту и с буквами из будущего: они не должны попасть.
				local queue = { "ya", "g", "a", "e", "b" }
				local targets = Levels.targets(3, queue)
				local fresh = Levels.stage(3).letters

				expect(targets[#fresh + 1]).to.equal("g")
				expect(targets[#fresh + 2]).to.equal("a")
				for slot = #fresh + 1, #targets do
					expect(Letters.expect(targets[slot]).stage < 3).to.equal(true)
				end
			end
		)

		it("на первом уровне повторяются его же буквы", function()
			local targets = Levels.targets(1, { "a", "b", "v" })
			local fresh = Levels.stage(1).letters
			for _, id in targets do
				expect(table.find(fresh, id)).to.be.ok()
			end
		end)

		it("очередь из мусора не ломает уровень", function()
			local targets = Levels.targets(5, { "нет такой", "", "zz" })
			expect(#targets).to.equal(Levels.expect(5).segments)
			for _, id in targets do
				expect(Letters.get(id)).to.be.ok()
			end
		end)
	end)

	describe("Levels.distractorGroups — кем окружить букву", function()
		it(
			"никогда не предлагает саму букву и буквы из будущего",
			function()
				for _, level in Levels.all do
					for _, target in Levels.targets(level.index, Letters.ordered()) do
						for _, id in flatten(Levels.distractorGroups(level.index, target)) do
							expect(id).never.to.equal(target)
							expect(Letters.expect(id).stage <= level.index).to.equal(true)
						end
					end
				end
			end
		)

		it("своя ступень идёт первой", function()
			local groups = Levels.distractorGroups(4, "i")
			for _, id in groups[1] do
				expect(Letters.expect(id).stage).to.equal(4)
			end
		end)

		-- docs/02-LEARNING.md § 6: буквы пары не ставятся в одни ворота на первых ступенях
		it(
			"на первых уровнях похожие буквы уходят в самый конец",
			function()
				for index = 1, Levels.CONFUSABLES_APART_UNTIL do
					for _, target in Levels.stage(index).letters do
						local groups = Levels.distractorGroups(index, target)
						local confusable = Letters.expect(target).confusableWith
						for _, id in flatten({ groups[1], groups[2] }) do
							expect(table.find(confusable, id)).to.equal(nil)
						end
					end
				end
			end
		)

		it(
			"позже похожие буквы встают в ворота наравне с прочими",
			function()
				local late = Levels.CONFUSABLES_APART_UNTIL + 1
				expect(Levels.get(late)).to.be.ok()
				expect(#Levels.distractorGroups(late, "n")[3]).to.equal(0)
			end
		)

		-- Даже на первом уровне, где букв всего три, на ворота хватает без похожих.
		it("на любые ворота хватает букв без похожих", function()
			for _, level in Levels.all do
				for _, target in Levels.targets(level.index, Letters.ordered()) do
					local groups = Levels.distractorGroups(level.index, target)
					expect(#groups[1] + #groups[2] >= level.maxChoices - 1).to.equal(true)
				end
			end
		end)
	end)

	describe("Levels.sanitize", function()
		it(
			"чистит мусор до целого от нуля до числа уровней",
			function()
				expect(Levels.sanitize(nil).letters).to.equal(0)
				expect(Levels.sanitize("x").letters).to.equal(0)
				expect(Levels.sanitize({ letters = 3 }).letters).to.equal(3)
				expect(Levels.sanitize({ letters = 3.9 }).letters).to.equal(3)
				expect(Levels.sanitize({ letters = -1 }).letters).to.equal(0)
				expect(Levels.sanitize({ letters = 1e9 }).letters).to.equal(Levels.count())
				expect(Levels.sanitize({ letters = 0 / 0 }).letters).to.equal(0)
			end
		)

		it("чужие ключи не переживают чистку", function()
			expect(Levels.sanitize({ letters = 2, hacker = 11 }).hacker).to.equal(nil)
		end)
	end)
end
