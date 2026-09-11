--!nocheck
--[[
	Ворота с числами. Проверяем ровно то, на чём ломается обучение счёту:
	верный ответ должен быть один, задача — меняться от ворот к воротам,
	а забег — воспроизводиться из рецепта до последнего примера, иначе сохранка
	вернёт ребёнка в чужой туннель.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MathGates = require(ReplicatedStorage.ServerChallenges.MathGates)
local MathConfig = require(ReplicatedStorage.Shared.Config.Math)
local Tunnel = require(ReplicatedStorage.Shared.Config.Tunnel)

local DIFFICULTY = 2

local function build(stage, difficulty)
	return MathGates.Build(nil, {}, difficulty or DIFFICULTY, stage or 1)
end

local function stateFor(spec)
	return {
		spec = spec,
		startedAt = os.clock(),
		gateStartedAt = os.clock(),
		answered = {},
		caught = 0,
		missed = 0,
	}
end

local function laneOf(gate, wantTarget)
	for _, opening in gate.openings do
		if opening.isTarget == wantTarget then
			return opening.lane
		end
	end
	return nil
end

local function fingerprint(spec)
	local parts = { spec.params.length, spec.targetCount }
	for _, gate in spec.params.gates do
		table.insert(parts, `{gate.index}:{gate.answer}:{gate.prompt}:{table.concat(gate.vo, ",")}`)
		for _, opening in gate.openings do
			table.insert(parts, `{opening.lane}={opening.value}/{opening.pips}`)
		end
	end
	return table.concat(parts, "|")
end

return function()
	describe("MathGates.Build", function()
		it("в каждых воротах ровно один верный проём", function()
			for stage = 1, MathConfig.count() do
				for difficulty = 1, 5 do
					local spec = build(stage, difficulty)
					for _, gate in spec.params.gates do
						local targets = 0
						for _, opening in gate.openings do
							if opening.isTarget then
								targets += 1
							end
							expect(opening.value).to.be.a("number")
						end
						if targets ~= 1 then
							error(
								`ступень {stage}, сложность {difficulty}, ворота {gate.index}: верных проёмов {targets}`
							)
						end
					end
				end
			end
		end)

		--[[
			Главное отличие от букв: одна буква на забег, но задача на КАЖДЫЕ ворота.
			Один и тот же пример пять раз подряд не учит считать — ребёнок запомнит
			ответ и перестанет считать уже на вторых воротах.
		]]
		it("у каждых ворот своя задача", function()
			-- Сид фиксированный: тест обязан падать по делу, а не раз в сто прогонов.
			local spec = MathGates.Rebuild({
				challengeId = "math_gates",
				seed = 12345,
				letters = {},
				difficulty = 5,
				stage = 7,
				checkpoint = 0,
			})
			local seen = {}
			local distinct = 0
			for _, gate in spec.params.gates do
				if not seen[gate.prompt] then
					seen[gate.prompt] = true
					distinct += 1
				end
			end
			expect(distinct > 1).to.equal(true)
		end)

		it(
			"проёмы не залезают друг на друга и не выходят за дорожки",
			function()
				for stage = 1, MathConfig.count() do
					local spec = build(stage, 5)
					for _, gate in spec.params.gates do
						local used = {}
						for _, opening in gate.openings do
							expect(opening.lane >= 1).to.equal(true)
							expect(opening.lane <= Tunnel.LANE_COUNT).to.equal(true)
							expect(used[opening.lane]).to.equal(nil)
							used[opening.lane] = true
						end
					end
				end
			end
		)

		--[[
			Ступень главнее сложности: на «узнавании количества» вариантов ровно два,
			сколько бы ни поднялась адаптивная сложность. Три варианта там — это уже
			не «покажи два мячика», а перебор глазами.
		]]
		it(
			"ступень сужает число вариантов сильнее сложности",
			function()
				local spec = build(1, 5)
				for _, gate in spec.params.gates do
					expect(#gate.openings).to.equal(2)
				end
			end
		)

		it(
			"точки под числом есть, пока ступень их просит, и никогда не больше десяти",
			function()
				for stage = 1, MathConfig.count() do
					local spec = build(stage, 3)
					local showPips = MathConfig.expect(stage).showPips
					for _, gate in spec.params.gates do
						for _, opening in gate.openings do
							expect(opening.pips <= MathConfig.MAX_NUMBER).to.equal(true)
							if not showPips then
								expect(opening.pips).to.equal(0)
							end
						end
					end
				end
			end
		)

		--[[
			Умножение — единственное место, где ответ выходит за десяток, и держится
			оно на тарелках: ребёнок пересчитывает предметы, а не читает «двадцать пять».
			Нет тарелок — правило нарушено (docs/16-MATH.md § 1, правило 3).
		]]
		it("умножение показывает группы предметов", function()
			local spec = build(11, 3)
			for _, gate in spec.params.gates do
				expect(gate.groups).to.be.ok()
				expect(gate.each).to.be.ok()
				expect(gate.groups * gate.each).to.equal(gate.answer)
			end
		end)

		it("задача звучит с первых же ворот", function()
			local spec = build(3, 2)
			expect(#spec.params.taskVO > 0).to.equal(true)
			expect(spec.params.taskVO[1]).to.equal(spec.params.gates[1].vo[1])
		end)
	end)

	describe("MathGates.Rebuild", function()
		--[[
			На этом держится сохранка: в профиле лежит рецепт, а не геометрия.
			Разойдись сборка хоть в одном примере — вернувшийся ребёнок попал бы
			в туннель, похожий на свой, но другой.
		]]
		it(
			"тот же рецепт даёт тот же забег до последнего примера",
			function()
				local spec = build(6, 3)
				local again = MathGates.Rebuild({
					challengeId = "math_gates",
					seed = spec.seed,
					letters = {},
					difficulty = spec.difficulty,
					stage = spec.stage,
					checkpoint = 2,
				})
				expect(fingerprint(again)).to.equal(fingerprint(spec))
				expect(again.params.resumeFrom).to.equal(2)
			end
		)

		it("другая ступень — другие задачи", function()
			local first = MathGates.Build(nil, {}, 3, 2)
			local second = MathGates.Rebuild({
				challengeId = "math_gates",
				seed = first.seed,
				letters = {},
				difficulty = first.difficulty,
				stage = 8,
				checkpoint = 0,
			})
			expect(fingerprint(second)).never.to.equal(fingerprint(first))
			expect(second.params.mathStageId).to.equal(MathConfig.expect(8).id)
		end)

		it(
			"продолженный забег начинает объяснять с невзятых ворот",
			function()
				local spec = MathGates.Build(nil, {}, 3, 4)
				local resumed = MathGates.Rebuild({
					challengeId = "math_gates",
					seed = spec.seed,
					letters = {},
					difficulty = spec.difficulty,
					stage = spec.stage,
					checkpoint = 2,
				})
				expect(resumed.params.taskPrompt).to.equal(spec.params.gates[3].prompt)
			end
		)
	end)

	describe("MathGates.Validate", function()
		it(
			"верный проём засчитан, неверный только тормозит",
			function()
				local spec = build(7, 3)
				local state = stateFor(spec)

				local hit = MathGates.Validate(state, {
					kind = "gate",
					gateIndex = 1,
					lane = laneOf(spec.params.gates[1], true),
				})
				expect(hit.correct).to.equal(true)
				expect(hit.cooldown).to.equal(0)
				expect(state.caught).to.equal(1)

				local miss = MathGates.Validate(state, {
					kind = "gate",
					gateIndex = 2,
					lane = laneOf(spec.params.gates[2], false),
				})
				expect(miss.correct).to.equal(false)
				expect(miss.cooldown > 0).to.equal(true)
				expect(miss.tappedValue).to.be.a("number")
				-- Прогресс не отнимается: взятые ворота остаются взятыми
				expect(state.caught).to.equal(1)
			end
		)

		it("осваивается ступень счёта, а не буква", function()
			local spec = build(5, 3)
			local state = stateFor(spec)
			local result = MathGates.Validate(state, {
				kind = "gate",
				gateIndex = 1,
				lane = laneOf(spec.params.gates[1], true),
			})
			expect(result.topic).to.equal("math")
			expect(result.topicId).to.equal(MathConfig.expect(5).id)
		end)

		--[[
			После любых ворот звучит задача следующих. Через неверный проём ребёнок
			пробегает так же, как через верный, и повтори игра старую задачу, он
			побежал бы к следующим воротам с чужим примером в голове.
		]]
		it(
			"после ворот звучит следующая задача — и после промаха тоже",
			function()
				local spec = build(7, 3)
				local state = stateFor(spec)

				local hit = MathGates.Validate(state, {
					kind = "gate",
					gateIndex = 1,
					lane = laneOf(spec.params.gates[1], true),
				})
				expect(table.concat(hit.voAfter, ",")).to.equal(table.concat(spec.params.gates[2].vo, ","))

				local miss = MathGates.Validate(state, {
					kind = "gate",
					gateIndex = 2,
					lane = laneOf(spec.params.gates[2], false),
				})
				expect(table.concat(miss.voAfter, ",")).to.equal(table.concat(spec.params.gates[3].vo, ","))
				expect(miss.nextPrompt).to.equal(spec.params.gates[3].prompt)
			end
		)

		it("одни ворота засчитываются один раз", function()
			local spec = build(2, 3)
			local state = stateFor(spec)
			local lane = laneOf(spec.params.gates[1], true)

			expect(MathGates.Validate(state, { kind = "gate", gateIndex = 1, lane = lane }).handled).to.equal(
				true
			)
			expect(MathGates.Validate(state, { kind = "gate", gateIndex = 1, lane = lane }).handled).to.equal(
				false
			)
			expect(state.caught).to.equal(1)
		end)

		it("забег кончается на финишной черте", function()
			local spec = build(2, 3)
			local state = stateFor(spec)
			local result = MathGates.Validate(state, { kind = "finish" })
			expect(result.finished).to.equal(true)
			expect(result.silent).to.equal(true)
		end)
	end)

	describe("MathGates.Finish", function()
		it("три звезды только за чистый проход", function()
			local spec = build(3, 3)
			local state = stateFor(spec)
			state.caught = spec.targetCount
			expect(MathGates.Finish(state).stars).to.equal(3)

			state.missed = 1
			expect(MathGates.Finish(state).stars < 3).to.equal(true)
		end)

		--[[
			Проиграть нельзя: даже пустой проход даёт звезду, а не ноль.
			Ошибка стоит времени, а не прогресса — это общее правило игры.
		]]
		it("даже нулевой проход даёт звезду", function()
			local spec = build(3, 3)
			local state = stateFor(spec)
			state.missed = 5
			expect(MathGates.Finish(state).stars).to.equal(1)
		end)
	end)
end
