--!nocheck
--[[
	«Пол — это лава!» (Challenges/LavaFloor). Главное: в каждом раунде есть куда
	встать, своих плит становится меньше, ответ принимается только от сервера,
	и ребёнок вне арены не получает ошибку узнавания.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LavaFloor = require(ReplicatedStorage.ServerChallenges.LavaFloor)
local Letters = require(ReplicatedStorage.Shared.Config.Letters)

local function stateFor(spec)
	return {
		spec = spec,
		startedAt = os.clock(),
		answered = {},
		caught = 0,
		missed = 0,
		lavaToken = 42,
	}
end

local function tileWith(round, letterId)
	for index, id in round.tiles do
		if id == letterId then
			return index
		end
	end
	return nil
end

local function tileWithout(round, letterId)
	for index, id in round.tiles do
		if id ~= letterId then
			return index
		end
	end
	return nil
end

return function()
	describe("LavaFloor.Build", function()
		it(
			"в каждом раунде есть свои плиты, и их не меньше двух",
			function()
				for difficulty = 1, 5 do
					local spec = LavaFloor.Build(nil, { "m", "a", "u" }, difficulty, nil, difficulty)
					for _, round in spec.params.rounds do
						expect(#round.tiles).to.equal(LavaFloor.GRID * LavaFloor.GRID)
						local own = 0
						for _, id in round.tiles do
							if id == "m" then
								own += 1
							end
						end
						expect(own).to.equal(round.targets)
						expect(own >= LavaFloor.MIN_TARGETS).to.equal(true)
					end
				end
			end
		)

		it("своих плит к концу меньше, чем в начале", function()
			local spec = LavaFloor.Build(nil, { "m", "a", "u" }, 5, nil, 1)
			local rounds = spec.params.rounds
			expect(rounds[#rounds].targets < rounds[1].targets).to.equal(true)
		end)

		it("чужие плиты — другие буквы, не цель", function()
			local spec = LavaFloor.Build(nil, { "m", "a", "u" }, 3, nil, 7)
			local others = 0
			for _, id in spec.params.rounds[1].tiles do
				expect(Letters.get(id)).to.be.ok()
				if id ~= "m" then
					others += 1
				end
			end
			expect(others > 0).to.equal(true)
		end)

		it("строится на любой паре букв алфавита", function()
			local ids = Letters.ordered()
			for _, first in ids do
				local ok = pcall(function()
					return LavaFloor.Build(nil, { first, ids[1] == first and ids[2] or ids[1] }, 3, nil, 3)
				end)
				expect(ok).to.equal(true)
			end
		end)

		it(
			"на поиск своей плиты времени не меньше пяти секунд",
			function()
				for difficulty = 1, 5 do
					local spec = LavaFloor.Build(nil, { "m", "a", "u" }, difficulty, nil, 1)
					expect(spec.params.seconds >= 5).to.equal(true)
				end
			end
		)
	end)

	describe("LavaFloor: сетка", function()
		it("центр плиты попадает в эту же плиту", function()
			for index = 1, LavaFloor.GRID * LavaFloor.GRID do
				expect(LavaFloor.tileAt(LavaFloor.tileCenter(index))).to.equal(index)
			end
		end)

		it("вне арены плиты нет", function()
			local far = LavaFloor.GRID * LavaFloor.PITCH
			expect(LavaFloor.tileAt(Vector3.new(far, 0, 0))).to.equal(nil)
			expect(LavaFloor.tileAt(Vector3.new(0, 0, -far))).to.equal(nil)
		end)
	end)

	describe("LavaFloor.Validate", function()
		it("своя плита — верно, чужая — нет", function()
			local spec = LavaFloor.Build(nil, { "m", "a", "u" }, 3, nil, 5)
			local state = stateFor(spec)
			local hit = LavaFloor.Validate(state, {
				kind = "round",
				round = 1,
				tile = tileWith(spec.params.rounds[1], "m"),
				token = 42,
			})
			expect(hit.handled).to.equal(true)
			expect(hit.correct).to.equal(true)

			local miss = LavaFloor.Validate(state, {
				kind = "round",
				round = 2,
				tile = tileWithout(spec.params.rounds[2], "m"),
				token = 42,
			})
			expect(miss.correct).to.equal(false)
			expect(miss.tappedLetterId).never.to.equal("m")
			expect(state.caught).to.equal(1)
			expect(state.missed).to.equal(1)
		end)

		it("без серверного токена ответ не принимается", function()
			local spec = LavaFloor.Build(nil, { "m", "a", "u" }, 3, nil, 5)
			local state = stateFor(spec)
			local tile = tileWith(spec.params.rounds[1], "m")
			expect(LavaFloor.Validate(state, { kind = "round", round = 1, tile = tile }).handled).to.equal(
				false
			)
			expect(LavaFloor.Validate(state, { kind = "round", round = 1, tile = tile, token = 1 }).handled).to.equal(
				false
			)
			expect(LavaFloor.Validate(state, { kind = "end" }).handled).to.equal(false)
		end)

		it("раунд засчитывается один раз", function()
			local spec = LavaFloor.Build(nil, { "m", "a", "u" }, 3, nil, 5)
			local state = stateFor(spec)
			local action =
				{ kind = "round", round = 1, tile = tileWith(spec.params.rounds[1], "m"), token = 42 }
			expect(LavaFloor.Validate(state, action).handled).to.equal(true)
			expect(LavaFloor.Validate(state, action).handled).to.equal(false)
		end)

		it("ребёнок вне арены — не ошибка", function()
			local spec = LavaFloor.Build(nil, { "m", "a", "u" }, 3, nil, 5)
			local state = stateFor(spec)
			local result = LavaFloor.Validate(state, { kind = "round", round = 1, token = 42 })
			expect(result.handled).to.equal(false)
			expect(state.missed).to.equal(0)
		end)

		it("конец раундов завершает испытание", function()
			local spec = LavaFloor.Build(nil, { "m", "a", "u" }, 3, nil, 5)
			local result = LavaFloor.Validate(stateFor(spec), { kind = "end", token = 42 })
			expect(result.finished).to.equal(true)
			expect(result.silent).to.equal(true)
		end)

		it("мусор вместо действия не роняет испытание", function()
			local spec = LavaFloor.Build(nil, { "m", "a", "u" }, 3, nil, 5)
			local state = stateFor(spec)
			expect(LavaFloor.Validate(state, nil).handled).to.equal(false)
			expect(LavaFloor.Validate(state, { kind = "round", round = "а", token = 42 }).handled).to.equal(
				false
			)
			expect(LavaFloor.Validate(state, { kind = "round", round = 999, token = 42 }).handled).to.equal(
				false
			)
		end)
	end)

	describe("LavaFloor.Finish", function()
		it("три звезды за все раунды", function()
			local spec = LavaFloor.Build(nil, { "m", "a", "u" }, 1, nil, 5)
			local state = stateFor(spec)
			state.caught = spec.targetCount
			expect(LavaFloor.Finish(state).stars).to.equal(3)
		end)

		it("хотя бы звезда даже без попаданий", function()
			local spec = LavaFloor.Build(nil, { "m", "a", "u" }, 1, nil, 5)
			expect(LavaFloor.Finish(stateFor(spec)).stars).to.equal(1)
		end)

		it("длится не дольше, чем разрешает конфиг", function()
			for difficulty = 1, 5 do
				local spec = LavaFloor.Build(nil, { "m", "a", "u" }, difficulty, nil, 1)
				expect(LavaFloor.duration(spec) <= 150).to.equal(true)
			end
		end)
	end)
end
