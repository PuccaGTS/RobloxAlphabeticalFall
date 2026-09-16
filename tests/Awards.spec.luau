--!nocheck
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared

local Awards = require(Shared.Logic.Awards)
local MasteryRules = require(Shared.Logic.MasteryRules)
local Letters = require(Shared.Config.Letters)
local Levels = require(Shared.Config.Levels)
local MathConfig = require(Shared.Config.Math)
local ProfileTemplate = require(Shared.Config.ProfileTemplate)

local NOW = 1_700_000_000

local function withLetters(count, mastery)
	local profile = ProfileTemplate.new(NOW)
	for index, letterId in Letters.ordered() do
		if index > count then
			break
		end
		local progress = MasteryRules.newProgress(NOW)
		progress.mastery = mastery
		profile.letters[letterId] = progress
	end
	return profile
end

return function()
	describe("Awards — заработанное учёбой", function()
		it("новичку не положено ничего", function()
			local earned = Awards.of(ProfileTemplate.new(NOW))
			expect(earned.flags).to.equal(0)
			expect(earned.arch).to.equal(false)
			expect(earned.spire).to.equal(false)
		end)

		it("флагов столько, сколько пройдено уровней", function()
			local profile = ProfileTemplate.new(NOW)
			profile.levels.letters = 4
			expect(Awards.of(profile).flags).to.equal(4)
			profile.levels.letters = 999
			expect(Awards.of(profile).flags).to.equal(Levels.count())
		end)

		it(
			"арка — за десять изученных подряд от А, не раньше",
			function()
				expect(Awards.of(withLetters(9, MasteryRules.LEARNED)).arch).to.equal(false)
				expect(Awards.of(withLetters(10, MasteryRules.LEARNED)).arch).to.equal(true)
				-- Знакомые не считаются: «подряд» — это хотя бы изученные.
				expect(Awards.of(withLetters(20, MasteryRules.FAMILIAR)).arch).to.equal(false)
			end
		)

		it("дыра в начале алфавита ломает «подряд»", function()
			local profile = withLetters(15, MasteryRules.MASTERED)
			profile.letters.a = nil
			expect(Awards.lettersInOrder(profile.letters)).to.equal(0)
			expect(Awards.of(profile).arch).to.equal(false)
		end)

		it("шпиль — только за все 33 освоенные", function()
			expect(Awards.of(withLetters(32, MasteryRules.MASTERED)).spire).to.equal(false)
			expect(Awards.of(withLetters(33, MasteryRules.MASTERED)).spire).to.equal(true)
			expect(Awards.of(withLetters(33, MasteryRules.LEARNED)).spire).to.equal(false)
		end)

		it(
			"флаги математики — по пройденным уровням своего пути",
			function()
				local profile = ProfileTemplate.new(NOW)
				expect(Awards.of(profile).mathFlags).to.equal(0)
				profile.levels.letters = 2
				profile.levels.math = 5
				local earned = Awards.of(profile)
				expect(earned.flags).to.equal(2)
				expect(earned.mathFlags).to.equal(5)
			end
		)

		it(
			"Шпиль Счёта — за девять освоенных базовых ступеней, умножение не нужно",
			function()
				local profile = ProfileTemplate.new(NOW)
				local function master(stage)
					local progress = MasteryRules.newProgress(NOW)
					progress.mastery = MasteryRules.MASTERED
					profile.math[MathConfig.expect(stage).id] = progress
				end
				for stage = 1, Awards.COUNT_SPIRE_STAGES - 1 do
					master(stage)
				end
				expect(Awards.of(profile).countSpire).to.equal(false)
				master(Awards.COUNT_SPIRE_STAGES)
				expect(Awards.of(profile).countSpire).to.equal(true)
				expect(profile.math[MathConfig.expect(MathConfig.count()).id]).to.equal(nil)
			end
		)

		it("испорченный профиль не роняет двор", function()
			local earned =
				Awards.of({ letters = "мусор", math = "мусор", levels = { letters = "три" } })
			expect(earned.flags).to.equal(0)
			expect(earned.mathFlags).to.equal(0)
			expect(earned.countSpire).to.equal(false)
			expect(earned.arch).to.equal(false)
			expect(Awards.of(nil).flags).to.equal(0)
		end)
	end)

	--[[
		Комнаты дома (docs/15-HOME-BASE.md § 5): их нельзя купить, они открываются
		за освоенное. Комната — это не «сколько-то первых букв», а именно та буква,
		которую ребёнок выучил: на полке стоит она.
	]]
	describe("Awards — комнаты дома", function()
		it("у новичка комнат нет", function()
			local earned = Awards.of(ProfileTemplate.new(NOW))
			expect(#earned.letterRooms).to.equal(0)
			expect(#earned.mathRooms).to.equal(0)
		end)

		it("изученной буквы мало, нужна освоенная", function()
			expect(#Awards.of(withLetters(5, MasteryRules.LEARNED)).letterRooms).to.equal(0)
			expect(#Awards.of(withLetters(5, MasteryRules.MASTERED)).letterRooms).to.equal(5)
		end)

		it("комнаты идут по алфавиту", function()
			local rooms = Awards.of(withLetters(3, MasteryRules.MASTERED)).letterRooms
			local ordered = Letters.ordered()
			for index, letterId in rooms do
				expect(letterId).to.equal(ordered[index])
			end
		end)

		it("ступень счёта тоже открывает комнату", function()
			local profile = ProfileTemplate.new(NOW)
			local spec = MathConfig.get(2)
			local progress = MasteryRules.newProgress(NOW)
			progress.mastery = MasteryRules.MASTERED
			profile.math[spec.id] = progress

			local rooms = Awards.of(profile).mathRooms
			expect(#rooms).to.equal(1)
			expect(rooms[1]).to.equal(spec.id)
		end)
	end)

	describe("Awards — флаги ступеней на крыше", function()
		it("флаг только за ступень, освоенную целиком", function()
			local Stages = require(ReplicatedStorage.Shared.Config.Stages)
			local first = #Stages.expect(1).letters
			expect(#Awards.of(withLetters(first - 1, MasteryRules.MASTERED)).stageFlags).to.equal(0)
			local earned = Awards.of(withLetters(first, MasteryRules.MASTERED))
			expect(#earned.stageFlags).to.equal(1)
			expect(earned.stageFlags[1]).to.equal(1)
			expect(#Awards.of(withLetters(first, MasteryRules.LEARNED)).stageFlags).to.equal(0)
		end)

		it("за весь алфавит — флаги всех ступеней", function()
			local Stages = require(ReplicatedStorage.Shared.Config.Stages)
			local earned = Awards.of(withLetters(Letters.count(), MasteryRules.MASTERED))
			expect(#earned.stageFlags).to.equal(Stages.count())
		end)
	end)
end
