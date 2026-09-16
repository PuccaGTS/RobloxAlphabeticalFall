--!nocheck
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AlphabetLadder = require(ReplicatedStorage.ServerChallenges.AlphabetLadder)
local Letters = require(ReplicatedStorage.Shared.Config.Letters)

local DIFFICULTY = 3

-- Доступные буквы всегда идут подряд от начала алфавита: так их отдаёт ProgressService.
local function prefix(count)
	local ids = {}
	for index, id in Letters.ordered() do
		if index > count then
			break
		end
		table.insert(ids, id)
	end
	return ids
end

local function build(letters, difficulty)
	return AlphabetLadder.Build(nil, letters or prefix(6), difficulty or DIFFICULTY)
end

local function stateFor(spec)
	return {
		spec = spec,
		startedAt = os.clock(),
		sectionStartedAt = os.clock(),
		answered = {},
		section = 0,
		caught = 0,
		missed = 0,
	}
end

return function()
	describe("AlphabetLadder.Build", function()
		--[[
			Главный инвариант: ответ — это всегда следующая буква алфавита.
			Если он сломается, испытание будет учить не тому, чему собиралось.
		]]
		it(
			"на каждой ступени ответ — следующая буква алфавита",
			function()
				for difficulty = 1, 5 do
					local spec = build(nil, difficulty)
					for _, section in spec.params.sections do
						local next_ = Letters.after(section.fromId)
						expect(next_).to.be.ok()
						expect(section.targetId).to.equal(next_.id)
					end
				end
			end
		)

		it(
			"лестница поднимается подряд, без прыжков через букву",
			function()
				local spec = build(prefix(8), 5)
				for index = 2, #spec.params.sections do
					local previous = spec.params.sections[index - 1]
					local current = spec.params.sections[index]
					expect(current.fromId).to.equal(previous.targetId)
				end
			end
		)

		it("варианты содержат верный ответ ровно один раз", function()
			local spec = build()
			for _, section in spec.params.sections do
				local hits = 0
				for _, choice in section.choices do
					if choice.letterId == section.targetId then
						hits += 1
					end
				end
				expect(hits).to.equal(1)
			end
		end)

		it(
			"вариантов всегда больше одного: выбор обязан быть",
			function()
				for difficulty = 1, 5 do
					local spec = build(nil, difficulty)
					for _, section in spec.params.sections do
						expect(#section.choices >= 2).to.equal(true)
					end
				end
			end
		)

		--[[
			Буква, с которой поднимаемся, в вариантах не нужна: она уже под ногами,
			и предлагать её как ответ — это предлагать шаг на месте.
		]]
		it("буква под ногами не попадает в варианты", function()
			local spec = build(prefix(10), 5)
			for _, section in spec.params.sections do
				for _, choice in section.choices do
					expect(choice.letterId).never.to.equal(section.fromId)
				end
			end
		end)

		--[[
			Незнакомая буква может прийти только верным ответом и только с подсказкой.
			Отвлекать незнакомыми нельзя: угадывать среди них ребёнок не обязан.
		]]
		it("отвлекающие варианты только из доступных букв", function()
			local available = prefix(5)
			local spec = build(available)
			for _, section in spec.params.sections do
				for _, choice in section.choices do
					if choice.letterId ~= section.targetId then
						expect(table.find(available, choice.letterId)).to.be.ok()
					end
				end
			end
		end)

		--[[
			Лестница в две ступени — это не задание: «после А — Б, после Б — В,
			победа». Так было у новичка с тремя открытыми буквами.
		]]
		it(
			"лестница не короче пяти ступеней даже у новичка",
			function()
				for count = 2, 6 do
					local spec = build(prefix(count), 1)
					expect(#spec.params.sections >= AlphabetLadder.MIN_RUNGS).to.equal(true)
				end
			end
		)

		it(
			"незнакомая буква на лестнице всегда с подсказкой",
			function()
				local available = prefix(3)
				local spec = build(available, 1)
				local hinted = 0
				for _, section in spec.params.sections do
					local known = table.find(available, section.targetId) ~= nil
					expect(section.hint).to.equal(not known)
					if section.hint then
						hinted += 1
					end
				end
				expect(hinted > 0).to.equal(true)
			end
		)

		it("строится на любом отрезке алфавита", function()
			for count = 2, Letters.count() do
				local ok = pcall(function()
					return AlphabetLadder.Build(nil, prefix(count), 3)
				end)
				expect(ok).to.equal(true)
			end
		end)
	end)

	describe("AlphabetLadder.Validate", function()
		it(
			"засчитывает следующую букву и двигает лестницу",
			function()
				local spec = build()
				local state = stateFor(spec)
				local section = spec.params.sections[1]

				local result = AlphabetLadder.Validate(state, {
					sectionIndex = 1,
					letterId = section.targetId,
				})

				expect(result.correct).to.equal(true)
				expect(result.letterId).to.equal(section.targetId)
				expect(result.stepVO).to.equal(section.targetVO)
				expect(state.section).to.equal(1)
			end
		)

		it(
			"ошибка стоит времени, но не отнимает пройденного",
			function()
				local spec = build()
				local state = stateFor(spec)
				local section = spec.params.sections[1]

				local wrong = nil
				for _, choice in section.choices do
					if choice.letterId ~= section.targetId then
						wrong = choice.letterId
					end
				end

				local result = AlphabetLadder.Validate(state, { sectionIndex = 1, letterId = wrong })

				expect(result.correct).to.equal(false)
				expect(result.cooldown > 0).to.equal(true)
				expect(state.section).to.equal(0)
				expect(state.caught).to.equal(0)
			end
		)

		it(
			"пока идёт пауза после промаха, ответы не принимаются",
			function()
				local spec = build()
				local state = stateFor(spec)
				local section = spec.params.sections[1]

				local wrong = nil
				for _, choice in section.choices do
					if choice.letterId ~= section.targetId then
						wrong = choice.letterId
					end
				end

				AlphabetLadder.Validate(state, { sectionIndex = 1, letterId = wrong })
				local blocked =
					AlphabetLadder.Validate(state, { sectionIndex = 1, letterId = section.targetId })

				expect(blocked.handled).to.equal(false)
				expect(blocked.blocked).to.equal(true)
			end
		)

		it("заканчивается на последней ступени", function()
			local spec = build()
			local state = stateFor(spec)

			local last = nil
			for index, section in spec.params.sections do
				last = AlphabetLadder.Validate(state, { sectionIndex = index, letterId = section.targetId })
			end

			expect(last.finished).to.equal(true)
			expect(state.caught).to.equal(#spec.params.sections)
		end)

		it("не падает на мусоре от клиента", function()
			local spec = build()
			local state = stateFor(spec)

			expect(AlphabetLadder.Validate(state, nil).handled).to.equal(false)
			expect(AlphabetLadder.Validate(state, {}).handled).to.equal(false)
			expect(AlphabetLadder.Validate(state, { letterId = "нет такой" }).handled).to.equal(false)
			expect(AlphabetLadder.Validate(state, { sectionIndex = 99, letterId = "a" }).handled).to.equal(
				false
			)
		end)
	end)

	describe("AlphabetLadder.Finish", function()
		it("три звезды за подъём без ошибок", function()
			local spec = build()
			local state = stateFor(spec)
			state.caught = spec.targetCount

			expect(AlphabetLadder.Finish(state).stars).to.equal(3)
		end)

		it("хотя бы звезда даже при нулевом результате", function()
			local spec = build()
			expect(AlphabetLadder.Finish(stateFor(spec)).stars).to.equal(1)
		end)
	end)
end
