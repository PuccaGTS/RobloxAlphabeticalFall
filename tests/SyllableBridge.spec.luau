--!nocheck
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SyllableBridge = require(ReplicatedStorage.ServerChallenges.SyllableBridge)
local Syllables = require(ReplicatedStorage.Shared.Config.Syllables)
local Letters = require(ReplicatedStorage.Shared.Config.Letters)

local DIFFICULTY = 2

local function build(letters)
	return SyllableBridge.Build(nil, letters or { "m", "a", "u", "o" }, DIFFICULTY)
end

local function stateFor(spec)
	return {
		spec = spec,
		startedAt = os.clock(),
		sectionStartedAt = os.clock(),
		section = 0,
		caught = 0,
		missed = 0,
	}
end

return function()
	describe("SyllableBridge.Build", function()
		it("собирает секции только из существующих слогов", function()
			local spec = build()
			expect(#spec.params.sections > 0).to.equal(true)

			for _, section in spec.params.sections do
				expect(Syllables.get(section.syllableId)).to.be.ok()
			end
		end)

		it("слог не появляется раньше своих букв", function()
			local spec = build()
			for _, section in spec.params.sections do
				local syllable = Syllables.expect(section.syllableId)
				expect(syllable.minIsland >= Letters.expect(section.leftId).island).to.equal(true)
				expect(syllable.minIsland >= Letters.expect(section.targetVowel).island).to.equal(true)
			end
		end)

		it("работает на первом острове, где есть только гласные", function()
			-- АУ, УА — с них начинается чтение, и мост обязан собираться уже здесь
			local spec = build({ "a", "u", "i" })

			expect(#spec.params.sections > 0).to.equal(true)
			for _, section in spec.params.sections do
				expect(Syllables.get(section.syllableId)).to.be.ok()
				expect(section.leftId).never.to.equal(section.targetVowel)
			end
		end)

		it("правильная гласная всегда есть среди вариантов", function()
			local spec = build()
			for _, section in spec.params.sections do
				local found = false
				for _, choice in section.choices do
					if choice.letterId == section.targetVowel then
						found = true
					end
				end
				expect(found).to.equal(true)
			end
		end)

		it("варианты не повторяются", function()
			local spec = build()
			for _, section in spec.params.sections do
				local seen = {}
				for _, choice in section.choices do
					expect(seen[choice.letterId]).to.equal(nil)
					seen[choice.letterId] = true
				end
			end
		end)

		it("у каждой секции есть слитная озвучка слога", function()
			local spec = build()
			for _, section in spec.params.sections do
				-- ключ вида blend_ma: слог записан одним файлом, а не склеен из букв
				expect(string.sub(section.vo, 1, 6)).to.equal("blend_")
			end
		end)

		it("добирает гласные, если в очереди была одна согласная", function()
			local spec = build({ "m", "a" })
			expect(#spec.params.sections > 0).to.equal(true)
			expect(#spec.params.sections[1].choices >= 2).to.equal(true)
		end)
	end)

	describe("SyllableBridge.Validate", function()
		it("засчитывает верную гласную и возвращает слог", function()
			local spec = build()
			local state = stateFor(spec)
			local section = spec.params.sections[1]

			local result = SyllableBridge.Validate(state, {
				sectionIndex = 1,
				letterId = section.targetVowel,
			})

			expect(result.handled).to.equal(true)
			expect(result.correct).to.equal(true)
			expect(result.syllableId).to.equal(section.syllableId)
			expect(result.letterId).to.equal(section.targetVowel)
			expect(state.section).to.equal(1)
		end)

		it("не двигает секцию при неверном выборе", function()
			local spec = build()
			local state = stateFor(spec)
			local section = spec.params.sections[1]

			local wrong = nil
			for _, choice in section.choices do
				if choice.letterId ~= section.targetVowel then
					wrong = choice.letterId
					break
				end
			end

			local result = SyllableBridge.Validate(state, { sectionIndex = 1, letterId = wrong })

			expect(result.correct).to.equal(false)
			expect(result.cooldown > 0).to.equal(true)
			expect(state.section).to.equal(0)
			expect(state.caught).to.equal(0)
		end)

		it("после промаха выбор блокируется на время подсказки", function()
			local spec = build()
			local state = stateFor(spec)
			local section = spec.params.sections[1]

			local wrong = nil
			for _, choice in section.choices do
				if choice.letterId ~= section.targetVowel then
					wrong = choice.letterId
					break
				end
			end
			SyllableBridge.Validate(state, { sectionIndex = 1, letterId = wrong })

			local blocked = SyllableBridge.Validate(state, {
				sectionIndex = 1,
				letterId = section.targetVowel,
			})

			expect(blocked.handled).to.equal(false)
			expect(blocked.blocked).to.equal(true)
		end)

		it("игнорирует ответ не на текущую секцию", function()
			local spec = build()
			local state = stateFor(spec)

			local result = SyllableBridge.Validate(state, {
				sectionIndex = 3,
				letterId = spec.params.sections[1].targetVowel,
			})

			expect(result.handled).to.equal(false)
		end)

		it("игнорирует букву, которой нет среди вариантов", function()
			local spec = build()
			local state = stateFor(spec)

			local result = SyllableBridge.Validate(state, { sectionIndex = 1, letterId = "zzz" })
			expect(result.handled).to.equal(false)
		end)

		it("не падает на мусоре от клиента", function()
			local spec = build()
			local state = stateFor(spec)

			expect(SyllableBridge.Validate(state, nil).handled).to.equal(false)
			expect(SyllableBridge.Validate(state, {}).handled).to.equal(false)
			expect(SyllableBridge.Validate(state, { letterId = 42 }).handled).to.equal(false)
		end)

		it("сообщает о завершении на последней секции", function()
			local spec = build()
			local state = stateFor(spec)

			local last = nil
			for index, section in spec.params.sections do
				last = SyllableBridge.Validate(state, {
					sectionIndex = index,
					letterId = section.targetVowel,
				})
			end

			expect(state.caught).to.equal(#spec.params.sections)
			expect(last.finished).to.equal(true)
		end)
	end)

	describe("SyllableBridge.Finish", function()
		it("даёт три звезды за мост без ошибок", function()
			local spec = build()
			local state = stateFor(spec)
			state.caught = spec.targetCount

			expect(SyllableBridge.Finish(state).stars).to.equal(3)
		end)

		it("даёт хотя бы звезду, даже если ничего не собрано", function()
			local spec = build()
			expect(SyllableBridge.Finish(stateFor(spec)).stars).to.equal(1)
		end)
	end)
end
