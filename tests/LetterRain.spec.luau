--!nocheck
--[[
	Испытание «Буквопад». Модули испытаний в тестовом месте подключены отдельно
	(см. test.project.json → ReplicatedStorage.ServerChallenges), поэтому их логику
	можно проверять без запуска серверных сервисов.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LetterRain = require(ReplicatedStorage.ServerChallenges.LetterRain)
local Challenges = require(ReplicatedStorage.Shared.Config.Challenges)
local DifficultyCurve = require(ReplicatedStorage.Shared.Logic.DifficultyCurve)

local DIFFICULTY = 2

local function build(letters)
	return LetterRain.Build(nil, letters or { "m", "a", "p" }, DIFFICULTY)
end

local function stateFor(spec, startedAt)
	return {
		spec = spec,
		startedAt = startedAt or os.clock(),
		answered = {},
		caught = 0,
		missed = 0,
	}
end

local function firstIndexWhere(items, predicate)
	for index, item in items do
		if predicate(item) then
			return index
		end
	end
	return nil
end

return function()
	describe("LetterRain.Build", function()
		it("делает целью первую букву очереди повторений", function()
			local spec = build({ "p", "m", "a" })
			expect(spec.params.targetLetter).to.equal("p")
			expect(spec.params.targetGlyph).to.equal("П")
		end)

		it("создаёт ровно столько целевых букв, сколько нужно поймать", function()
			local spec = build()
			local targets = 0
			for _, item in spec.params.items do
				if item.isTarget then
					targets += 1
				end
			end

			local expected = DifficultyCurve.pick(Challenges.expect("letter_rain").params.targetCount, DIFFICULTY)
			expect(spec.targetCount).to.equal(expected)
			expect(targets).to.equal(expected)
		end)

		it("первая упавшая буква всегда целевая", function()
			for _ = 1, 20 do
				local spec = build()
				expect(spec.params.items[1].isTarget).to.equal(true)
			end
		end)

		it("отвлекающие буквы не совпадают с целевой", function()
			local spec = build()
			for _, item in spec.params.items do
				if not item.isTarget then
					expect(item.letterId).never.to.equal(spec.params.targetLetter)
				end
			end
		end)

		it("буквы появляются по возрастанию времени", function()
			local spec = build()
			for index = 2, #spec.params.items do
				expect(spec.params.items[index].spawnAt > spec.params.items[index - 1].spawnAt).to.equal(true)
			end
		end)

		it("две буквы подряд не падают в одну полосу", function()
			local spec = build()
			for index = 2, #spec.params.items do
				expect(spec.params.items[index].lane).never.to.equal(spec.params.items[index - 1].lane)
			end
		end)
	end)

	describe("LetterRain.Validate", function()
		it("засчитывает тап по целевой букве", function()
			local spec = build()
			local state = stateFor(spec)

			local result = LetterRain.Validate(state, { itemIndex = 1 })

			expect(result.handled).to.equal(true)
			expect(result.correct).to.equal(true)
			expect(result.letterId).to.equal(spec.params.targetLetter)
			expect(state.caught).to.equal(1)
		end)

		it("промах по чужой букве не отнимает пойманное", function()
			local spec = build()
			local state = stateFor(spec)

			local wrongIndex = firstIndexWhere(spec.params.items, function(item)
				return not item.isTarget
			end)
			-- сдвигаем старт назад, чтобы отвлекающая буква уже была на экране
			state.startedAt = os.clock() - spec.params.items[wrongIndex].spawnAt

			local result = LetterRain.Validate(state, { itemIndex = wrongIndex })

			expect(result.handled).to.equal(true)
			expect(result.correct).to.equal(false)
			expect(state.caught).to.equal(0)
			expect(state.missed).to.equal(1)
		end)

		it("ответ засчитывается целевой букве, а не той, по которой промахнулись", function()
			local spec = build()
			local state = stateFor(spec)

			local wrongIndex = firstIndexWhere(spec.params.items, function(item)
				return not item.isTarget
			end)
			state.startedAt = os.clock() - spec.params.items[wrongIndex].spawnAt

			local result = LetterRain.Validate(state, { itemIndex = wrongIndex })

			expect(result.letterId).to.equal(spec.params.targetLetter)
			expect(result.tappedLetterId).to.equal(spec.params.items[wrongIndex].letterId)
		end)

		it("после промаха ловля блокируется на время подсказки", function()
			local spec = build()
			local state = stateFor(spec)

			local wrongIndex = firstIndexWhere(spec.params.items, function(item)
				return not item.isTarget
			end)
			state.startedAt = os.clock() - spec.params.items[wrongIndex].spawnAt

			local miss = LetterRain.Validate(state, { itemIndex = wrongIndex })
			expect(miss.cooldown > 0).to.equal(true)
			expect(state.blockedUntil > os.clock()).to.equal(true)

			-- перебор не работает: следующий тап не засчитывается, пока идёт подсказка
			local nextTargetIndex = firstIndexWhere(spec.params.items, function(item)
				return item.isTarget
			end)
			local blocked = LetterRain.Validate(state, { itemIndex = nextTargetIndex })

			expect(blocked.handled).to.equal(false)
			expect(blocked.blocked).to.equal(true)
			expect(state.caught).to.equal(0)
		end)

		it("после окончания паузы ловля снова работает", function()
			local spec = build()
			local state = stateFor(spec)
			state.blockedUntil = os.clock() - 0.01

			local result = LetterRain.Validate(state, { itemIndex = 1 })

			expect(result.handled).to.equal(true)
			expect(result.correct).to.equal(true)
		end)

		it("верный ответ паузу не ставит", function()
			local spec = build()
			local state = stateFor(spec)

			local result = LetterRain.Validate(state, { itemIndex = 1 })

			expect(result.cooldown).to.equal(0)
			expect(state.blockedUntil).to.equal(nil)
		end)

		it("не принимает повторный тап по той же букве", function()
			local spec = build()
			local state = stateFor(spec)

			LetterRain.Validate(state, { itemIndex = 1 })
			local second = LetterRain.Validate(state, { itemIndex = 1 })

			expect(second.handled).to.equal(false)
			expect(state.caught).to.equal(1)
		end)

		it("игнорирует тап по букве, которая ещё не появилась", function()
			local spec = build()
			local state = stateFor(spec)
			local lastIndex = #spec.params.items

			local result = LetterRain.Validate(state, { itemIndex = lastIndex })
			expect(result.handled).to.equal(false)
		end)

		it("игнорирует тап по уже упавшей букве", function()
			local spec = build()
			local state = stateFor(spec)
			state.startedAt = os.clock() - (spec.params.flightTime + 10)

			local result = LetterRain.Validate(state, { itemIndex = 1 })
			expect(result.handled).to.equal(false)
		end)

		it("не падает на мусоре от клиента", function()
			local spec = build()
			local state = stateFor(spec)

			expect(LetterRain.Validate(state, nil).handled).to.equal(false)
			expect(LetterRain.Validate(state, {}).handled).to.equal(false)
			expect(LetterRain.Validate(state, { itemIndex = "1" }).handled).to.equal(false)
			expect(LetterRain.Validate(state, { itemIndex = 99999 }).handled).to.equal(false)
			expect(LetterRain.Validate(state, { itemIndex = -3 }).handled).to.equal(false)
		end)

		it("сообщает о завершении, когда поймано нужное количество", function()
			local spec = build()
			local state = stateFor(spec)

			local last = nil
			for index, item in spec.params.items do
				if item.isTarget then
					state.startedAt = os.clock() - item.spawnAt
					last = LetterRain.Validate(state, { itemIndex = index })
				end
			end

			expect(state.caught).to.equal(spec.targetCount)
			expect(last.finished).to.equal(true)
		end)
	end)

	describe("LetterRain.Finish", function()
		it("даёт три звезды за чистый проход", function()
			local spec = build()
			local state = stateFor(spec)
			state.caught = spec.targetCount

			expect(LetterRain.Finish(state).stars).to.equal(3)
		end)

		it("снимает звезду за промахи, но не наказывает сильнее", function()
			local spec = build()
			local state = stateFor(spec)
			state.caught = spec.targetCount
			state.missed = 4

			expect(LetterRain.Finish(state).stars).to.equal(2)
		end)

		it("даёт хотя бы одну звезду даже при нулевом результате", function()
			local spec = build()
			local state = stateFor(spec)

			expect(LetterRain.Finish(state).stars).to.equal(1)
		end)
	end)
end
