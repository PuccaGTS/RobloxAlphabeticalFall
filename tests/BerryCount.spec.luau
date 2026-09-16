--!nocheck
--[[
	«Ягодная поляна»: собрать столько ягод, сколько сказал голос, и отнести
	в корзинку. Проверяем то, на чём ломается счёт: ягод на кустах всегда больше
	нужного, ответ считает сервер по сорванным ягодам, промах ничего не отнимает.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BerryCount = require(ReplicatedStorage.ServerChallenges.BerryCount)
local MathConfig = require(ReplicatedStorage.Shared.Config.Math)
local AudioRegistry = require(ReplicatedStorage.Shared.Config.AudioRegistry)
local VOText = require(ReplicatedStorage.Shared.Config.VOText)

local function stateFor(spec)
	return { spec = spec, startedAt = os.clock(), answered = {}, caught = 0, missed = 0 }
end

return function()
	-- Внутри: expect доступен только в теле набора тестов.
	local function pick(state, round, count)
		for berry = 1, count do
			local result = BerryCount.Validate(state, { kind = "pick", round = round, berry = berry })
			expect(result.handled).to.equal(true)
			expect(result.silent).to.equal(true)
		end
	end

	describe("BerryCount.Build", function()
		it(
			"на каждой ступени счёта строится и ягод больше, чем нужно",
			function()
				for stage = 1, MathConfig.count() do
					for difficulty = 1, 5 do
						local spec = BerryCount.Build(nil, {}, difficulty, stage, 7 * stage + difficulty)
						expect(#spec.params.rounds > 0).to.equal(true)
						for _, round in spec.params.rounds do
							expect(round.target >= 1).to.equal(true)
							expect(round.given + round.target <= MathConfig.MAX_NUMBER).to.equal(true)
							expect(#round.berries > round.target).to.equal(true)
							expect(#round.berries <= BerryCount.MAX_BERRIES).to.equal(true)
							expect(#round.vo >= 2).to.equal(true)
						end
					end
				end
			end
		)

		it("ягоды на разных кустах", function()
			local spec = BerryCount.Build(nil, {}, 5, 3, 11)
			for _, round in spec.params.rounds do
				local seen = {}
				for _, berry in round.berries do
					local key = `{math.floor(berry.x * 10)}:{math.floor(berry.z * 10)}`
					expect(seen[key]).to.equal(nil)
					seen[key] = true
				end
			end
		end)

		it(
			"задание зависит от ступени: счёт, пример, состав числа",
			function()
				local count = BerryCount.Build(nil, {}, 3, 1, 5).params.rounds[1]
				expect(count.vo[1]).to.equal("mtask_collect")
				expect(count.given).to.equal(0)

				for stage = 1, MathConfig.count() do
					local spec = MathConfig.expect(stage)
					local round = BerryCount.Build(nil, {}, 3, stage, 9).params.rounds[1]
					if spec.kind == "add" or spec.kind == "sub" then
						expect(round.vo[#round.vo]).to.equal("mtask_collect_that")
						expect(round.prompt ~= "").to.equal(true)
					elseif spec.kind == "compose" then
						expect(round.vo[1]).to.equal("mtask_fill")
						expect(round.given >= 1).to.equal(true)
					end
				end
			end
		)

		it("по тому же сиду — те же раунды", function()
			local a = BerryCount.Build(nil, {}, 4, 6, 123)
			local b = BerryCount.Build(nil, {}, 4, 6, 123)
			for index, round in a.params.rounds do
				expect(b.params.rounds[index].target).to.equal(round.target)
				expect(b.params.rounds[index].berries[1].x).to.equal(round.berries[1].x)
			end
		end)

		it(
			"все реплики задания объявлены и у них есть текст",
			function()
				for stage = 1, MathConfig.count() do
					for _, round in BerryCount.Build(nil, {}, 5, stage, 3).params.rounds do
						for _, key in round.vo do
							expect(AudioRegistry.ids[key]).to.be.ok()
							expect(VOText.get(key)).to.be.ok()
						end
					end
				end
				expect(AudioRegistry.ids.instr_berries).to.be.ok()
			end
		)
	end)

	describe("BerryCount.Validate", function()
		it(
			"столько, сколько надо, — засчитано и идёт следующий раунд",
			function()
				local spec = BerryCount.Build(nil, {}, 2, 1, 42)
				local state = stateFor(spec)
				local round = spec.params.rounds[1]
				pick(state, 1, round.target)
				local result = BerryCount.Validate(state, { kind = "basket", round = 1 })
				expect(result.correct).to.equal(true)
				expect(result.topic).to.equal("math")
				expect(result.topicId).to.equal(MathConfig.expect(1).id)
				expect(result.stepVO).to.equal(`num_{round.target + round.given}`)
				expect(state.caught).to.equal(1)
				expect(state.round).to.equal(2)
			end
		)

		it(
			"больше нужного — промах, пауза, ягоды заново, прогресс не отнят",
			function()
				local spec = BerryCount.Build(nil, {}, 2, 1, 42)
				local state = stateFor(spec)
				local round = spec.params.rounds[1]
				pick(state, 1, round.target + 1)
				local result = BerryCount.Validate(state, { kind = "basket", round = 1 })
				expect(result.correct).to.equal(false)
				expect(result.cooldown > 0).to.equal(true)
				expect(result.tappedValue).to.equal(round.target + 1 + round.given)
				expect(state.round).to.equal(1)
				expect(state.caught).to.equal(0)

				-- В паузу ягоды не срываются.
				local blocked = BerryCount.Validate(state, { kind = "pick", round = 1, berry = 1 })
				expect(blocked.handled).to.equal(false)

				state.blockedUntil = 0
				pick(state, 1, round.target)
				expect(BerryCount.Validate(state, { kind = "basket", round = 1 }).correct).to.equal(true)
			end
		)

		it(
			"пустые руки в корзинку ничего не отправляют, одна ягода не рвётся дважды",
			function()
				local spec = BerryCount.Build(nil, {}, 2, 1, 42)
				local state = stateFor(spec)
				expect(BerryCount.Validate(state, { kind = "basket", round = 1 }).handled).to.equal(false)
				pick(state, 1, 1)
				expect(BerryCount.Validate(state, { kind = "pick", round = 1, berry = 1 }).handled).to.equal(
					false
				)
			end
		)

		it("чужой раунд и мусор не принимаются", function()
			local spec = BerryCount.Build(nil, {}, 2, 1, 42)
			local state = stateFor(spec)
			expect(BerryCount.Validate(state, { kind = "pick", round = 2, berry = 1 }).handled).to.equal(
				false
			)
			expect(BerryCount.Validate(state, "ягода").handled).to.equal(false)
			expect(BerryCount.Validate(state, { kind = "pick", round = 1, berry = 999 }).handled).to.equal(
				false
			)
		end)

		it("последний раунд завершает задание", function()
			local spec = BerryCount.Build(nil, {}, 1, 2, 8)
			local state = stateFor(spec)
			local last
			for index, round in spec.params.rounds do
				pick(state, index, round.target)
				last = BerryCount.Validate(state, { kind = "basket", round = index })
			end
			expect(last.finished).to.equal(true)
			expect(BerryCount.Finish(state).stars).to.equal(3)
		end)
	end)
end
