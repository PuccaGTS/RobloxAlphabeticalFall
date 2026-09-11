--!nocheck
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TunnelRun = require(ReplicatedStorage.ServerChallenges.TunnelRun)
local ObstacleCourse = require(ReplicatedStorage.ServerChallenges.ObstacleCourse)
local Tunnel = require(ReplicatedStorage.Shared.Config.Tunnel)
local Letters = require(ReplicatedStorage.Shared.Config.Letters)
local Obstacles = require(ReplicatedStorage.Shared.Config.Obstacles)
local DifficultyCurve = require(ReplicatedStorage.Shared.Logic.DifficultyCurve)

local DIFFICULTY = 2

local function build(letters, difficulty)
	return TunnelRun.Build(nil, letters or { "m", "a", "u" }, difficulty or DIFFICULTY)
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

		it("целевая буква одна на весь забег", function()
			local spec = build()
			for _, gate in spec.params.gates do
				for _, opening in gate.openings do
					if opening.isTarget then
						expect(opening.letterId).to.equal(spec.params.targetLetter)
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
						expect(opening.letterId).never.to.equal(spec.params.targetLetter)
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

		it("строится на любой паре букв алфавита", function()
			local ids = Letters.ordered()
			for _, first in ids do
				for _, second in ids do
					if first ~= second then
						local ok = pcall(function()
							return TunnelRun.Build(nil, { first, second }, 3)
						end)
						expect(ok).to.equal(true)
					end
				end
			end
		end)
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
			expect(again.params.targetLetter).to.equal(spec.params.targetLetter)
			expect(#again.params.gates).to.equal(#spec.params.gates)
			expect(#again.params.obstacles).to.equal(#spec.params.obstacles)

			for index, gate in spec.params.gates do
				local twin = again.params.gates[index]
				expect(twin.z).to.equal(gate.z)
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
			"препятствий больше, а ворот меньше, чем в туннеле",
			function()
				local tunnel = TunnelRun.Build(nil, { "m", "a", "u" }, 3)
				local course = ObstacleCourse.Build(nil, { "m", "a", "u" }, 3)

				expect(#course.params.obstacles > #tunnel.params.obstacles).to.equal(true)
				expect(#course.params.gates < #tunnel.params.gates).to.equal(true)
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

		it("отрезок длиннее, когда препятствий больше", function()
			local spec = ObstacleCourse.Build(nil, { "m", "a", "u" }, 5)
			local first = spec.params.gates[1]
			expect(first.z > Tunnel.MIN_GATE_SPACING).to.equal(true)
		end)
	end)
end
