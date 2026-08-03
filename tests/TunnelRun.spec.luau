--!nocheck
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TunnelRun = require(ReplicatedStorage.ServerChallenges.TunnelRun)
local Tunnel = require(ReplicatedStorage.Shared.Config.Tunnel)
local Letters = require(ReplicatedStorage.Shared.Config.Letters)

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

		it("препятствия не стоят вплотную к воротам", function()
			-- задание и паркур не должны пересекаться: docs/14-TUNNEL-MODE.md § 2
			local spec = build()
			for _, barrier in spec.params.barriers do
				for _, gate in spec.params.gates do
					expect(math.abs(barrier.z - gate.z) > 5).to.equal(true)
				end
			end
		end)

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
end
