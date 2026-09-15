--!nocheck
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Scales = require(ReplicatedStorage.ServerChallenges.Scales)
local MathConfig = require(ReplicatedStorage.Shared.Config.Math)
local AudioRegistry = require(ReplicatedStorage.Shared.Config.AudioRegistry)

local function stateFor(spec)
	return { spec = spec, startedAt = os.clock(), answered = {}, caught = 0, missed = 0 }
end

return function()
	describe("Scales.Build", function()
		it(
			"в каждом раунде ровно одна кучка уравновешивает весы",
			function()
				for stage = 1, MathConfig.count() do
					for difficulty = 1, 5 do
						local spec = Scales.Build(nil, {}, difficulty, stage, stage * 10 + difficulty)
						expect(#spec.params.rounds).to.equal(spec.targetCount)
						for _, round in spec.params.rounds do
							local equal = 0
							for slot, value in round.choices do
								if value == round.left then
									equal += 1
									expect(slot).to.equal(round.correctSlot)
								end
							end
							expect(equal).to.equal(1)
							expect(#round.choices >= 2).to.equal(true)
						end
					end
				end
			end
		)

		-- docs/16-MATH.md § 1: всё, что ребёнок считает, — от 1 до 10.
		it(
			"камней не больше десяти и не больше, чем позволяет ступень",
			function()
				for stage = 1, MathConfig.count() do
					local _, cap = Scales.topicFor(stage)
					expect(cap <= MathConfig.MAX_NUMBER).to.equal(true)
					local spec = Scales.Build(nil, {}, 5, stage, 7)
					for _, round in spec.params.rounds do
						for _, value in round.choices do
							expect(value >= 1 and value <= cap).to.equal(true)
						end
					end
				end
			end
		)

		it(
			"неверные кучки — соседние количества, а не случайные",
			function()
				local spec = Scales.Build(nil, {}, 5, MathConfig.count(), 3)
				for _, round in spec.params.rounds do
					for _, value in round.choices do
						expect(math.abs(value - round.left) <= 2).to.equal(true)
					end
				end
			end
		)

		it(
			"одно и то же количество два раунда подряд не повторяется",
			function()
				for seed = 1, 30 do
					local spec = Scales.Build(nil, {}, 5, MathConfig.count(), seed)
					for index = 2, #spec.params.rounds do
						expect(spec.params.rounds[index].left ~= spec.params.rounds[index - 1].left).to.equal(
							true
						)
					end
				end
			end
		)

		it(
			"ответы идут в ступень ребёнка, а выше «больше/меньше» — в неё",
			function()
				local compare = MathConfig.byId(Scales.EQUALITY_STAGE_ID)
				expect(compare).to.be.ok()
				expect(Scales.topicFor(1)).to.equal(MathConfig.expect(1).id)
				expect(Scales.topicFor(compare.stage)).to.equal(compare.id)
				expect(Scales.topicFor(MathConfig.count())).to.equal(compare.id)
			end
		)

		it(
			"число после верного ответа — записанная реплика",
			function()
				local spec = Scales.Build(nil, {}, 5, MathConfig.count(), 11)
				local keys = AudioRegistry.requiredKeys()
				for _, round in spec.params.rounds do
					expect(table.find(keys, `num_{round.left}`)).to.be.ok()
				end
			end
		)
	end)

	describe("Scales.Validate", function()
		it(
			"верная кучка ведёт к следующему раунду и называет число",
			function()
				local spec = Scales.Build(nil, {}, 3, 4, 8)
				local state = stateFor(spec)
				local round = spec.params.rounds[1]
				local result = Scales.Validate(state, { round = 1, slot = round.correctSlot })
				expect(result.correct).to.equal(true)
				expect(result.topic).to.equal("math")
				expect(result.topicId).to.equal(spec.params.mathStageId)
				expect(result.tappedValue).to.equal(round.left)
				expect(result.stepVO).to.equal(`num_{round.left}`)
				expect(state.round).to.equal(2)
			end
		)

		it(
			"неверная кучка качает весы, раунд остаётся, пауза перед новым выбором",
			function()
				local spec = Scales.Build(nil, {}, 3, 4, 8)
				local state = stateFor(spec)
				local round = spec.params.rounds[1]
				local wrong = if round.correctSlot == 1 then 2 else 1
				local result = Scales.Validate(state, { round = 1, slot = wrong })
				expect(result.correct).to.equal(false)
				expect(result.tappedValue).to.equal(round.choices[wrong])
				expect(result.cooldown > 0).to.equal(true)
				expect(state.round).to.equal(1)
				-- В паузу ответ не принимается: перебор кучек подряд не работает.
				expect(Scales.Validate(state, { round = 1, slot = round.correctSlot }).handled).to.equal(
					false
				)
			end
		)

		it("кончается после последнего раунда", function()
			local spec = Scales.Build(nil, {}, 1, 1, 6)
			local state = stateFor(spec)
			local last
			for index, round in spec.params.rounds do
				last = Scales.Validate(state, { round = index, slot = round.correctSlot })
			end
			expect(last.finished).to.equal(true)
			expect(Scales.Finish(state).stars).to.equal(3)
		end)

		it("не падает на мусоре от клиента", function()
			local state = stateFor(Scales.Build(nil, {}, 1, 1, 1))
			expect(Scales.Validate(state, nil).handled).to.equal(false)
			expect(Scales.Validate(state, { round = 1 }).handled).to.equal(false)
			expect(Scales.Validate(state, { round = 2, slot = 1 }).handled).to.equal(false)
			expect(Scales.Validate(state, { round = 1, slot = 99 }).handled).to.equal(false)
		end)
	end)
end
