--!nocheck
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Bubbles = require(ReplicatedStorage.ServerChallenges.Bubbles)
local Challenges = require(ReplicatedStorage.Shared.Config.Challenges)
local DifficultyCurve = require(ReplicatedStorage.Shared.Logic.DifficultyCurve)

local function stateFor(spec)
	return { spec = spec, startedAt = os.clock(), answered = {}, caught = 0, missed = 0 }
end

local function indexOf(spec, isTarget)
	for _, item in spec.params.items do
		if item.isTarget == isTarget then
			return item.index
		end
	end
	return nil
end

return function()
	describe("Bubbles.Build", function()
		it(
			"пузырей и целей столько, сколько велит сложность",
			function()
				local meta = Challenges.expect("bubbles")
				for difficulty = 1, 5 do
					local spec = Bubbles.Build(nil, { "m", "a", "u" }, difficulty, nil, 7)
					local targets = 0
					for _, item in spec.params.items do
						if item.isTarget then
							targets += 1
							expect(item.letterId).to.equal("m")
						else
							expect(item.letterId).never.to.equal("m")
						end
					end
					expect(#spec.params.items).to.equal(
						DifficultyCurve.pick(meta.params.totalBubbles, difficulty)
					)
					expect(targets).to.equal(spec.targetCount)
				end
			end
		)

		-- docs/03-CHALLENGES.md § 5: пузыри — место, чтобы различать похожие Ш и Щ.
		it(
			"похожие по начертанию буквы идут в отвлекающие первыми",
			function()
				local spec = Bubbles.Build(nil, { "sh", "shch", "a", "b" }, 5, nil, 11)
				local shch = 0
				for _, item in spec.params.items do
					if item.letterId == "shch" then
						shch += 1
					end
				end
				expect(shch > 0).to.equal(true)
			end
		)

		it("в одной колонке пузыри не слипаются", function()
			local spec = Bubbles.Build(nil, { "m", "a" }, 5, nil, 3)
			local byColumn = {}
			for _, item in spec.params.items do
				byColumn[item.column] = byColumn[item.column] or {}
				table.insert(byColumn[item.column], item.phase)
			end
			for _, phases in byColumn do
				table.sort(phases)
				for index = 2, #phases do
					local gap = (phases[index] - phases[index - 1]) * spec.params.height
					expect(gap >= 4).to.equal(true)
				end
			end
		end)

		it("один сид — одни и те же пузыри", function()
			local a = Bubbles.Build(nil, { "m", "a", "u" }, 3, nil, 42)
			local b = Bubbles.Build(nil, { "m", "a", "u" }, 3, nil, 42)
			for index, item in a.params.items do
				expect(b.params.items[index].letterId).to.equal(item.letterId)
				expect(b.params.items[index].column).to.equal(item.column)
			end
		end)
	end)

	describe("Bubbles.Validate", function()
		it("верный пузырь засчитывается один раз", function()
			local spec = Bubbles.Build(nil, { "m", "a", "u" }, 3, nil, 5)
			local state = stateFor(spec)
			local index = indexOf(spec, true)
			local first = Bubbles.Validate(state, { itemIndex = index })
			expect(first.correct).to.equal(true)
			expect(first.letterId).to.equal("m")
			expect(Bubbles.Validate(state, { itemIndex = index }).handled).to.equal(false)
		end)

		it(
			"не тот пузырь — рыбка: пауза, но ничего не отнимается",
			function()
				local spec = Bubbles.Build(nil, { "m", "a", "u" }, 3, nil, 5)
				local state = stateFor(spec)
				local miss = Bubbles.Validate(state, { itemIndex = indexOf(spec, false) })
				expect(miss.correct).to.equal(false)
				expect(miss.cooldown > 0).to.equal(true)
				expect(state.caught).to.equal(0)
				-- Во время паузы лопнуть нельзя: сначала подсказка.
				expect(Bubbles.Validate(state, { itemIndex = indexOf(spec, true) }).handled).to.equal(false)
			end
		)

		it("кончается, когда лопнуты все нужные", function()
			local spec = Bubbles.Build(nil, { "m", "a", "u" }, 3, nil, 9)
			local state = stateFor(spec)
			local last
			for _, item in spec.params.items do
				if item.isTarget then
					last = Bubbles.Validate(state, { itemIndex = item.index })
				end
			end
			expect(last.finished).to.equal(true)
			expect(Bubbles.Finish(state).stars).to.equal(3)
		end)

		it("не падает на мусоре от клиента", function()
			local state = stateFor(Bubbles.Build(nil, { "m", "a" }, 1, nil, 1))
			expect(Bubbles.Validate(state, nil).handled).to.equal(false)
			expect(Bubbles.Validate(state, { itemIndex = 999 }).handled).to.equal(false)
			expect(Bubbles.Validate(state, { itemIndex = "а" }).handled).to.equal(false)
		end)
	end)
end
