--!nocheck
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TunnelRun = require(ReplicatedStorage.ServerChallenges.TunnelRun)
local ObstacleCourse = require(ReplicatedStorage.ServerChallenges.ObstacleCourse)
local Tunnel = require(ReplicatedStorage.Shared.Config.Tunnel)
local Letters = require(ReplicatedStorage.Shared.Config.Letters)
local Obstacles = require(ReplicatedStorage.Shared.Config.Obstacles)
local Levels = require(ReplicatedStorage.Shared.Config.Levels)
local DifficultyCurve = require(ReplicatedStorage.Shared.Logic.DifficultyCurve)

local DIFFICULTY = 2
local LEVEL = 5

local function build(letters, difficulty, level)
	return TunnelRun.Build(nil, letters or { "m", "a", "u" }, difficulty or DIFFICULTY, level or LEVEL)
end

local function countOf(list, value)
	local count = 0
	for _, item in list do
		if item == value then
			count += 1
		end
	end
	return count
end

local function stateFor(spec)
	return {
		spec = spec,
		startedAt = os.clock(),
		gateStartedAt = os.clock(),
		answered = {},
		section = 0,
		caught = 0,
		missed = 0,
	}
end

local function targetLaneOf(gate)
	for _, opening in gate.openings do
		if opening.isTarget then
			return opening.lane
		end
	end
	return nil
end

return function()
	describe("TunnelRun.Build", function()
		it("в каждых воротах ровно один верный проём", function()
			for difficulty = 1, 5 do
				local spec = build(nil, difficulty)
				for _, gate in spec.params.gates do
					local targets = 0
					for _, opening in gate.openings do
						if opening.isTarget then
							targets += 1
						end
					end
					expect(targets).to.equal(1)
				end
			end
		end)

		it("верный проём несёт букву своего отрезка", function()
			local spec = build()
			for _, gate in spec.params.gates do
				for _, opening in gate.openings do
					if opening.isTarget then
						expect(opening.letterId).to.equal(gate.targetLetter)
					end
				end
			end
		end)

		it("проёмы не занимают одну дорожку дважды", function()
			local spec = build(nil, 5)
			for _, gate in spec.params.gates do
				local seen = {}
				for _, opening in gate.openings do
					expect(seen[opening.lane]).to.equal(nil)
					seen[opening.lane] = true
				end
			end
		end)

		it("проёмов не больше, чем дорожек", function()
			for difficulty = 1, 5 do
				local spec = build(nil, difficulty)
				for _, gate in spec.params.gates do
					expect(#gate.openings <= Tunnel.LANE_COUNT).to.equal(true)
					expect(#gate.openings >= 2).to.equal(true)
				end
			end
		end)

		it("отвлекающие проёмы не повторяют целевую букву", function()
			local spec = build({ "m", "a", "u", "o" })
			for _, gate in spec.params.gates do
				for _, opening in gate.openings do
					if not opening.isTarget then
						expect(opening.letterId).never.to.equal(gate.targetLetter)
					end
				end
			end
		end)

		it(
			"ворота идут по возрастанию расстояния и не выходят за длину",
			function()
				local spec = build()
				for index = 2, #spec.params.gates do
					expect(spec.params.gates[index].z > spec.params.gates[index - 1].z).to.equal(true)
				end
				expect(spec.params.gates[#spec.params.gates].z < spec.params.length).to.equal(true)
			end
		)

		--[[
			Паркур и задание не должны пересекаться (docs/14-TUNNEL-MODE.md § 2):
			пока ребёнок решает буквенную задачу, под ним ровный пол.
		]]
		it("препятствия не стоят вплотную к воротам", function()
			for difficulty = 1, 5 do
				local spec = build(nil, difficulty)
				for _, obstacle in spec.params.obstacles do
					for _, gate in spec.params.gates do
						local distance = math.abs(obstacle.z - gate.z)
						expect(distance >= Tunnel.CLEARANCE_AFTER_GATE).to.equal(true)
					end
				end
			end
		end)

		it("препятствия не налезают друг на друга", function()
			for difficulty = 1, 5 do
				local spec = build(nil, difficulty)
				for index = 2, #spec.params.obstacles do
					local gap = spec.params.obstacles[index].z - spec.params.obstacles[index - 1].z
					-- либо следующий отрезок (тогда разрыв большой), либо ровно шаг полосы
					expect(gap >= Tunnel.OBSTACLE_PITCH - 0.001).to.equal(true)
				end
			end
		end)

		it(
			"ставит только те элементы, которые сервер умеет строить",
			function()
				local spec = build(nil, 5)
				for _, obstacle in spec.params.obstacles do
					expect(Obstacles.get(obstacle.id)).to.be.ok()
					expect(obstacle.kind).to.equal(Obstacles.expect(obstacle.id).kind)
				end
			end
		)

		--[[
			Средний ряд элементов включается не сразу: новичок бежит по базовым,
			а маятники и платформы появляются, когда он уже уверенно проходит.
		]]
		it("на первой сложности только базовые элементы", function()
			expect(DifficultyCurve.pick(Tunnel.PARAMS.obstacleTier, 1)).to.equal(1)
			for _, obstacle in build(nil, 1).params.obstacles do
				expect(Obstacles.expect(obstacle.id).tier).to.equal(1)
			end
		end)

		it("на высокой сложности средний ряд разрешён", function()
			expect(DifficultyCurve.pick(Tunnel.PARAMS.obstacleTier, 5)).to.equal(2)
			expect(DifficultyCurve.pick(Tunnel.COURSE_PARAMS.obstacleTier, 5)).to.equal(2)
		end)

		--[[
			Живых элементов (маятник, платформа, гаснущие плиты) на одном отрезке
			не больше двух. Иначе отрезок начинает требовать реакции, и буква,
			ради которой он существует, теряется за аттракционом.
		]]
		it("живых элементов на отрезке не больше двух", function()
			for difficulty = 1, 5 do
				for _, spec in
					{ build(nil, difficulty), ObstacleCourse.Build(nil, { "m", "a", "u" }, difficulty) }
				do
					local previousZ = 0
					for _, gate in spec.params.gates do
						local moving = 0
						for _, obstacle in spec.params.obstacles do
							if
								obstacle.z > previousZ
								and obstacle.z < gate.z
								and Obstacles.isMoving(obstacle.id)
							then
								moving += 1
							end
						end
						expect(moving <= Tunnel.MAX_MOVING_PER_SEGMENT).to.equal(true)
						previousZ = gate.z
					end
				end
			end
		end)

		it(
			"сохранка стоит за каждыми воротами и не раньше их",
			function()
				local spec = build()
				expect(#spec.params.checkpoints).to.equal(#spec.params.gates)
				for index, checkpoint in spec.params.checkpoints do
					expect(checkpoint.z > spec.params.gates[index].z).to.equal(true)
					expect(checkpoint.z < spec.params.length).to.equal(true)
				end
			end
		)

		it("строится на любом уровне с любой очередью", function()
			for _, level in Levels.all do
				for _, first in Letters.ordered() do
					for difficulty = 1, 5, 4 do
						local ok = pcall(function()
							return TunnelRun.Build(nil, { first, "a" }, difficulty, level.index)
						end)
						expect(ok).to.equal(true)
					end
				end
			end
		end)

		it("без уровня туннель не строится", function()
			expect(pcall(TunnelRun.Build, nil, { "m", "a" }, 3, nil)).to.equal(false)
			expect(pcall(TunnelRun.Build, nil, { "m", "a" }, 3, 99)).to.equal(false)
		end)
	end)

	--[[
		Уровень как цепочка отрезков (docs/14-TUNNEL-MODE.md § 3.3).

		Проверяется то, что ребёнок почувствует сразу: отрезков столько, сколько
		у уровня; буквы на отрезках — новые буквы ступени, потом повторение;
		в воротах нет ни повторов, ни букв, которых он ещё не видел, ни —
		на первых уровнях — похожих пар вроде Б и В.
	]]
	describe("TunnelRun — уровень мира букв", function()
		it("ворот столько, сколько отрезков у уровня", function()
			for _, level in Levels.all do
				for difficulty = 1, 5 do
					local spec = build(nil, difficulty, level.index)
					expect(#spec.params.gates).to.equal(level.segments)
					expect(#spec.params.checkpoints).to.equal(level.segments)
					expect(spec.targetCount).to.equal(level.segments)
					expect(spec.level).to.equal(level.index)
				end
			end
		end)

		it("буквы отрезков — по плану уровня", function()
			local queue = { "m", "a", "u" }
			for _, level in Levels.all do
				local spec = build(queue, 3, level.index)
				local planned = Levels.targets(level.index, queue)
				for index, gate in spec.params.gates do
					expect(gate.targetLetter).to.equal(planned[index])
				end
			end
		end)

		it("проёмов не больше, чем разрешает уровень", function()
			for _, level in Levels.all do
				local spec = build(nil, 5, level.index)
				for _, gate in spec.params.gates do
					expect(#gate.openings <= level.maxChoices).to.equal(true)
					expect(#gate.openings >= 2).to.equal(true)
				end
			end
		end)

		it("в одних воротах буквы не повторяются", function()
			for _, level in Levels.all do
				for difficulty = 1, 5 do
					local spec = build(nil, difficulty, level.index)
					for _, gate in spec.params.gates do
						local seen = {}
						for _, opening in gate.openings do
							expect(seen[opening.letterId]).to.equal(nil)
							seen[opening.letterId] = true
						end
					end
				end
			end
		end)

		it(
			"в воротах только буквы, открытые к этому уровню",
			function()
				for _, level in Levels.all do
					local spec = build(Letters.ordered(), 5, level.index)
					for _, gate in spec.params.gates do
						for _, opening in gate.openings do
							expect(Letters.expect(opening.letterId).stage <= level.index).to.equal(true)
						end
					end
				end
			end
		)

		-- docs/02-LEARNING.md § 6
		it(
			"на первых уровнях похожие буквы не встают в одни ворота",
			function()
				for index = 1, Levels.CONFUSABLES_APART_UNTIL do
					for difficulty = 1, 5 do
						local spec = build(Letters.ordered(), difficulty, index)
						for _, gate in spec.params.gates do
							local pair = Letters.expect(gate.targetLetter).confusableWith
							for _, opening in gate.openings do
								expect(table.find(pair, opening.letterId)).to.equal(nil)
							end
						end
					end
				end
			end
		)

		it("первый уровень — выбор из двух между А, Б и В", function()
			for difficulty = 1, 5 do
				local spec = build({ "a", "b", "v" }, difficulty, 1)
				for _, gate in spec.params.gates do
					expect(#gate.openings).to.equal(2)
					for _, opening in gate.openings do
						expect(table.find({ "a", "b", "v" }, opening.letterId)).to.be.ok()
					end
				end
			end
		end)

		it(
			"каждая новая буква ступени получает свой отрезок",
			function()
				for _, level in Levels.all do
					local spec = build(nil, 3, level.index)
					local targets = {}
					for _, gate in spec.params.gates do
						table.insert(targets, gate.targetLetter)
					end
					for _, id in Levels.stage(level.index).letters do
						expect(countOf(targets, id) >= 1).to.equal(true)
					end
				end
			end
		)

		it("ответ засчитывается букве своего отрезка", function()
			local spec = build(nil, 3, 2)
			local state = stateFor(spec)
			local gate = spec.params.gates[2]

			state.answered[1] = true
			local result =
				TunnelRun.Validate(state, { kind = "gate", gateIndex = 2, lane = targetLaneOf(gate) })

			expect(result.letterId).to.equal(gate.targetLetter)
		end)

		--[[
			Через неверный проём ребёнок пробегает так же, как через верный.
			Поэтому новая буква объявляется после любого ответа — иначе после
			ошибки он бежал бы к новым воротам со старой буквой в голове.
		]]
		it(
			"после любых ворот звучит буква следующего отрезка",
			function()
				local spec = build(nil, 3, 1)
				local gates = spec.params.gates
				expect(gates[1].targetLetter).never.to.equal(gates[2].targetLetter)

				local hitState = stateFor(spec)
				local hit = TunnelRun.Validate(
					hitState,
					{ kind = "gate", gateIndex = 1, lane = targetLaneOf(gates[1]) }
				)
				expect(hit.nextLetter).to.equal(gates[2].targetLetter)
				expect(hit.nextGlyph).to.equal(gates[2].targetGlyph)
				expect(hit.voAfter[1]).to.equal(gates[2].targetVO)

				local wrongLane
				for _, opening in gates[1].openings do
					if not opening.isTarget then
						wrongLane = opening.lane
					end
				end
				local missState = stateFor(spec)
				local miss = TunnelRun.Validate(missState, { kind = "gate", gateIndex = 1, lane = wrongLane })
				expect(miss.correct).to.equal(false)
				expect(miss.nextLetter).to.equal(gates[2].targetLetter)
			end
		)

		it("на последних воротах объявлять больше нечего", function()
			local spec = build(nil, 3, 1)
			local last = #spec.params.gates
			local state = stateFor(spec)
			for index = 1, last - 1 do
				state.answered[index] = true
			end

			local result = TunnelRun.Validate(state, {
				kind = "gate",
				gateIndex = last,
				lane = targetLaneOf(spec.params.gates[last]),
			})
			expect(result.nextLetter).to.equal(nil)
			expect(result.voAfter).to.equal(nil)
		end)

		it(
			"продолженный уровень начинается с буквы невзятого отрезка",
			function()
				local spec = build(nil, 3, 1)
				local resumed = TunnelRun.Rebuild({
					challengeId = spec.challengeId,
					seed = spec.seed,
					letters = spec.letters,
					difficulty = spec.difficulty,
					level = spec.level,
					checkpoint = 2,
					savedAt = 0,
				})

				expect(resumed.params.targetLetter).to.equal(spec.params.gates[3].targetLetter)
				expect(resumed.params.targetGlyph).to.equal(spec.params.gates[3].targetGlyph)
			end
		)
	end)

	describe("TunnelRun.Validate", function()
		it("засчитывает проход через верный проём", function()
			local spec = build()
			local state = stateFor(spec)
			local gate = spec.params.gates[1]

			local result = TunnelRun.Validate(state, {
				kind = "gate",
				gateIndex = 1,
				lane = targetLaneOf(gate),
			})

			expect(result.handled).to.equal(true)
			expect(result.correct).to.equal(true)
			expect(state.caught).to.equal(1)
		end)

		it("не засчитывает одни ворота дважды", function()
			local spec = build()
			local state = stateFor(spec)
			local lane = targetLaneOf(spec.params.gates[1])

			TunnelRun.Validate(state, { kind = "gate", gateIndex = 1, lane = lane })
			local second = TunnelRun.Validate(state, { kind = "gate", gateIndex = 1, lane = lane })

			expect(second.handled).to.equal(false)
			expect(state.caught).to.equal(1)
		end)

		it(
			"неверный проём замедляет, но ничего не отнимает",
			function()
				local spec = build()
				local state = stateFor(spec)
				local gate = spec.params.gates[1]

				local wrongLane = nil
				for _, opening in gate.openings do
					if not opening.isTarget then
						wrongLane = opening.lane
					end
				end

				local result = TunnelRun.Validate(state, { kind = "gate", gateIndex = 1, lane = wrongLane })

				expect(result.correct).to.equal(false)
				expect(result.cooldown > 0).to.equal(true)
				expect(state.caught).to.equal(0)
				expect(state.missed).to.equal(1)
			end
		)

		it(
			"забег заканчивается финишем, а не последними воротами",
			function()
				local spec = build()
				local state = stateFor(spec)

				for index, gate in spec.params.gates do
					local result = TunnelRun.Validate(state, {
						kind = "gate",
						gateIndex = index,
						lane = targetLaneOf(gate),
					})
					expect(result.finished).to.equal(false)
				end

				local finish = TunnelRun.Validate(state, { kind = "finish" })
				expect(finish.finished).to.equal(true)
				expect(finish.silent).to.equal(true)
			end
		)

		it("не падает на мусоре от клиента", function()
			local spec = build()
			local state = stateFor(spec)

			expect(TunnelRun.Validate(state, nil).handled).to.equal(false)
			expect(TunnelRun.Validate(state, {}).handled).to.equal(false)
			expect(TunnelRun.Validate(state, { kind = "gate" }).handled).to.equal(false)
			expect(TunnelRun.Validate(state, { kind = "gate", gateIndex = 999, lane = 1 }).handled).to.equal(
				false
			)
			expect(TunnelRun.Validate(state, { kind = "gate", gateIndex = 1, lane = 99 }).handled).to.equal(
				false
			)
		end)
	end)

	describe("TunnelRun.Finish", function()
		it("три звезды за забег без ошибок", function()
			local spec = build()
			local state = stateFor(spec)
			state.caught = spec.targetCount

			expect(TunnelRun.Finish(state).stars).to.equal(3)
		end)

		it("хотя бы звезда даже при нулевом результате", function()
			local spec = build()
			expect(TunnelRun.Finish(stateFor(spec)).stars).to.equal(1)
		end)
	end)

	--[[
		Сохранка, пережившая выход из игры (docs/14-TUNNEL-MODE.md § 3.3).

		Главное, что здесь проверяется: забег восстанавливается ТОТ ЖЕ САМЫЙ.
		Если план начнёт зависеть от чего-то, кроме сида, букв и сложности,
		ребёнок вернётся в туннель, похожий на свой, но другой — и окажется
		посреди чужого пути. Этот тест сторожит именно это.
	]]
	describe("TunnelRun.Rebuild — продолжение забега", function()
		local function savedFrom(spec, checkpoint)
			return {
				challengeId = spec.challengeId,
				seed = spec.seed,
				letters = spec.letters,
				difficulty = spec.difficulty,
				level = spec.level,
				checkpoint = checkpoint,
				savedAt = 0,
			}
		end

		it("новый забег начинается с начала", function()
			expect(build().params.resumeFrom).to.equal(0)
		end)

		it("по тому же рецепту собирается тот же туннель", function()
			local spec = build()
			local again = TunnelRun.Rebuild(savedFrom(spec, 1))

			expect(again.params.length).to.equal(spec.params.length)
			-- Продолжение с первой сохранки начинается с буквы вторых ворот, а не первых.
			expect(again.params.targetLetter).to.equal(spec.params.gates[2].targetLetter)
			expect(#again.params.gates).to.equal(#spec.params.gates)
			expect(#again.params.obstacles).to.equal(#spec.params.obstacles)

			for index, gate in spec.params.gates do
				local twin = again.params.gates[index]
				expect(twin.z).to.equal(gate.z)
				expect(twin.targetLetter).to.equal(gate.targetLetter)
				for slot, opening in gate.openings do
					expect(twin.openings[slot].lane).to.equal(opening.lane)
					expect(twin.openings[slot].letterId).to.equal(opening.letterId)
					expect(twin.openings[slot].isTarget).to.equal(opening.isTarget)
				end
			end

			for index, obstacle in spec.params.obstacles do
				expect(again.params.obstacles[index].id).to.equal(obstacle.id)
				expect(again.params.obstacles[index].z).to.equal(obstacle.z)
				expect(again.params.obstacles[index].lane).to.equal(obstacle.lane)
			end
		end)

		it("продолжает с пройденной сохранки", function()
			local spec = build()
			expect(TunnelRun.Rebuild(savedFrom(spec, 2)).params.resumeFrom).to.equal(2)
		end)

		it(
			"испорченная сохранка не уводит дальше последних ворот",
			function()
				local spec = build()
				local far = TunnelRun.Rebuild(savedFrom(spec, 999))

				expect(far.params.resumeFrom).to.equal(far.targetCount)
				expect(TunnelRun.Rebuild(savedFrom(spec, -5)).params.resumeFrom).to.equal(0)
			end
		)

		it(
			"пройденные ворота засчитаны и второй раз не спрашиваются",
			function()
				local spec = TunnelRun.Rebuild(savedFrom(build(), 2))
				local state = stateFor(spec)
				TunnelRun.Resume(state)

				expect(state.caught).to.equal(2)

				local first = TunnelRun.Validate(state, {
					kind = "gate",
					gateIndex = 1,
					lane = targetLaneOf(spec.params.gates[1]),
				})
				expect(first.handled).to.equal(false)
				expect(state.caught).to.equal(2)
			end
		)

		it("оставшиеся ворота работают как обычно", function()
			local spec = TunnelRun.Rebuild(savedFrom(build(), 2))
			local state = stateFor(spec)
			TunnelRun.Resume(state)

			local result = TunnelRun.Validate(state, {
				kind = "gate",
				gateIndex = 3,
				lane = targetLaneOf(spec.params.gates[3]),
			})

			expect(result.handled).to.equal(true)
			expect(result.correct).to.equal(true)
			expect(state.caught).to.equal(3)
		end)
	end)

	--[[
		Полоса препятствий — тот же забег с перевёрнутыми пропорциями.
		Проверяем ровно это: что она осталась забегом с буквами, а не превратилась
		в паркур ради паркура.
	]]
	describe("ObstacleCourse", function()
		it(
			"на отрезок препятствий больше, а ворот меньше, чем в туннеле",
			function()
				-- Сравниваем пропорции, а не итог: длина туннеля задана уровнем, полосы — нет.
				local course = ObstacleCourse.Build(nil, { "m", "a", "u" }, 3)
				local courseRatio = #course.params.obstacles / #course.params.gates

				for _, level in Levels.all do
					local tunnel = TunnelRun.Build(nil, { "m", "a", "u" }, 3, level.index)
					expect(courseRatio > #tunnel.params.obstacles / #tunnel.params.gates).to.equal(true)
					expect(#course.params.gates < #tunnel.params.gates).to.equal(true)
				end
			end
		)

		it(
			"ворота с буквами есть всё равно: звёздочки идут только за них",
			function()
				for difficulty = 1, 5 do
					local spec = ObstacleCourse.Build(nil, { "m", "a", "u" }, difficulty)
					expect(#spec.params.gates >= 2).to.equal(true)
					for _, gate in spec.params.gates do
						local targets = 0
						for _, opening in gate.openings do
							if opening.isTarget then
								targets += 1
							end
						end
						expect(targets).to.equal(1)
					end
				end
			end
		)

		-- Полоса — не уровень: буква на ней одна, первая из очереди повторений.
		it("целевая буква одна на весь забег", function()
			local spec = ObstacleCourse.Build(nil, { "m", "a", "u" }, 3)
			expect(spec.level).to.equal(nil)
			for _, gate in spec.params.gates do
				expect(gate.targetLetter).to.equal("m")
			end
		end)

		it("строится на любой паре букв алфавита", function()
			local ids = Letters.ordered()
			for _, first in ids do
				for _, second in ids do
					if first ~= second then
						local ok = pcall(function()
							return ObstacleCourse.Build(nil, { first, second }, 3)
						end)
						expect(ok).to.equal(true)
					end
				end
			end
		end)

		it("отрезок длиннее, когда препятствий больше", function()
			local spec = ObstacleCourse.Build(nil, { "m", "a", "u" }, 5)
			local first = spec.params.gates[1]
			expect(first.z > Tunnel.MIN_GATE_SPACING).to.equal(true)
		end)
	end)
end
