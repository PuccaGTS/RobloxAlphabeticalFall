--!nocheck
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Mirror = require(ReplicatedStorage.ServerChallenges.Mirror)
local Letters = require(ReplicatedStorage.Shared.Config.Letters)
local StrokeGlyphs = require(ReplicatedStorage.Shared.Logic.StrokeGlyphs)

local function stateFor(spec)
	return { spec = spec, startedAt = os.clock(), answered = {}, caught = 0, missed = 0 }
end

return function()
	describe("Mirror.Build", function()
		it("в каждом раунде ровно один правильный вариант", function()
			for difficulty = 1, 5 do
				local spec = Mirror.Build(nil, Letters.ordered(), difficulty, nil, difficulty)
				for _, round in spec.params.rounds do
					local correct = 0
					for slot, variant in round.variants do
						if variant.kind == "true" then
							correct += 1
							expect(slot).to.equal(round.correctSlot)
							expect(variant.rotation).to.equal(0)
							expect(variant.glyph).to.equal(Letters.expect(round.letterId).glyph)
						end
					end
					expect(correct).to.equal(1)
					expect(#round.variants >= 2).to.equal(true)
				end
			end
		end)

		--[[
			Неправильный вариант обязан ОТЛИЧАТЬСЯ от правильного. О на боку —
			та же О, Н вверх ногами — та же Н; такой раунд нечестен и учит угадывать.
		]]
		it(
			"нет неправильных вариантов, неотличимых от правильного",
			function()
				for _, letterId in Letters.ordered() do
					for _, kind in Mirror.wrongKinds(letterId) do
						if kind == "rotate" then
							expect(Mirror.ROTATE_SAME[letterId]).to.equal(nil)
						elseif kind == "lying" then
							expect(Mirror.LYING_SAME[letterId]).to.equal(nil)
						elseif kind == "mirror" then
							expect(StrokeGlyphs.mirrorDiffers(letterId)).to.equal(true)
						end
					end
				end
				expect(#Mirror.wrongKinds("o")).to.equal(0)
				expect(#Mirror.wrongKinds("h")).to.equal(0)
				expect(table.find(Mirror.wrongKinds("n"), "rotate")).to.equal(nil)
			end
		)

		it(
			"буквы без честных вариантов в раунды не попадают",
			function()
				local spec = Mirror.Build(nil, { "o", "h", "ya" }, 3, nil, 1)
				for _, round in spec.params.rounds do
					expect(round.letterId).to.equal("ya")
				end
			end
		)

		it(
			"симметричные буквы не отражаются, несимметричные — да",
			function()
				for _, id in { "a", "o", "t", "sh", "zh", "m" } do
					expect(table.find(Mirror.wrongKinds(id), "mirror")).to.equal(nil)
				end
				-- Р, З и Ю ждали картинок: готовых похожих знаков для них нет.
				for _, id in { "r", "z", "yu", "b", "ye", "k", "ch", "soft" } do
					expect(table.find(Mirror.wrongKinds(id), "mirror")).to.be.ok()
				end
			end
		)

		it(
			"отражённый вариант — та же буква, только отражённая",
			function()
				local spec = Mirror.Build(nil, { "r", "z", "yu" }, 1, nil, 5)
				for _, round in spec.params.rounds do
					for _, variant in round.variants do
						expect(variant.glyph).to.equal(Letters.expect(round.letterId).glyph)
						expect(variant.mirrored).to.equal(variant.kind == "mirror")
					end
				end
			end
		)

		-- Главные зеркальные путаницы (Я, И, Э) показываются отражёнными, если отражение есть.
		it("у Я, И и Э в раунде есть отражение", function()
			local spec = Mirror.Build(nil, { "ya", "i", "e" }, 1, nil, 4)
			for _, round in spec.params.rounds do
				local mirrored = false
				for _, variant in round.variants do
					if variant.kind == "mirror" then
						mirrored = true
					end
				end
				expect(mirrored).to.equal(true)
			end
		end)

		it("букв меньше, чем раундов, — идут по кругу", function()
			local spec = Mirror.Build(nil, { "b" }, 5, nil, 2)
			expect(#spec.params.rounds).to.equal(spec.targetCount)
			for _, round in spec.params.rounds do
				expect(round.letterId).to.equal("b")
			end
		end)

		it("первым звучит название буквы первого раунда", function()
			local spec = Mirror.Build(nil, { "m", "a" }, 2, nil, 3)
			expect(spec.params.taskVO[1]).to.equal(Letters.expect(spec.params.rounds[1].letterId).vo.name)
		end)
	end)

	describe("Mirror.Validate", function()
		it(
			"верный выбор ведёт к следующему раунду и называет его букву",
			function()
				local spec = Mirror.Build(nil, { "m", "a", "b" }, 3, nil, 8)
				local state = stateFor(spec)
				local round = spec.params.rounds[1]
				local result = Mirror.Validate(state, { round = 1, slot = round.correctSlot })
				expect(result.correct).to.equal(true)
				expect(result.letterId).to.equal(round.letterId)
				expect(result.stepVO).to.equal(round.vo)
				expect(result.voAfter[1]).to.equal(spec.params.rounds[2].vo)
				expect(state.round).to.equal(2)
			end
		)

		it("промах оставляет раунд и выбор на месте", function()
			local spec = Mirror.Build(nil, { "m", "a" }, 3, nil, 8)
			local state = stateFor(spec)
			local round = spec.params.rounds[1]
			local wrong = if round.correctSlot == 1 then 2 else 1
			local result = Mirror.Validate(state, { round = 1, slot = wrong })
			expect(result.correct).to.equal(false)
			expect(result.cooldown > 0).to.equal(true)
			expect(state.round).to.equal(1)
		end)

		it("ответить на чужой раунд нельзя", function()
			local spec = Mirror.Build(nil, { "m", "a" }, 3, nil, 8)
			local state = stateFor(spec)
			expect(Mirror.Validate(state, { round = 2, slot = 1 }).handled).to.equal(false)
		end)

		it("кончается после последнего раунда", function()
			local spec = Mirror.Build(nil, { "m", "a" }, 1, nil, 6)
			local state = stateFor(spec)
			local last
			for index, round in spec.params.rounds do
				last = Mirror.Validate(state, { round = index, slot = round.correctSlot })
			end
			expect(last.finished).to.equal(true)
			expect(Mirror.Finish(state).stars).to.equal(3)
		end)

		it("не падает на мусоре от клиента", function()
			local state = stateFor(Mirror.Build(nil, { "m" }, 1, nil, 1))
			expect(Mirror.Validate(state, nil).handled).to.equal(false)
			expect(Mirror.Validate(state, { round = 1 }).handled).to.equal(false)
			expect(Mirror.Validate(state, { round = 1, slot = 99 }).handled).to.equal(false)
		end)
	end)
end
