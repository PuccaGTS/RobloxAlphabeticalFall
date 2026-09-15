--!nocheck
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared

local MathLevels = require(Shared.Config.MathLevels)
local MathConfig = require(Shared.Config.Math)
local Levels = require(Shared.Config.Levels)
local Tunnel = require(Shared.Config.Tunnel)
local Migrations = require(Shared.Logic.Migrations)
local MathGates = require(ReplicatedStorage.ServerChallenges.MathGates)

return function()
	describe("MathLevels — путь мира математики", function()
		it(
			"уровень на каждую ступень счёта, номер совпадает",
			function()
				expect(MathLevels.count()).to.equal(MathConfig.count())
				for index, level in MathLevels.all do
					expect(level.index).to.equal(index)
					expect(#level.title > 0).to.equal(true)
				end
			end
		)

		it(
			"ворот к концу пути не меньше, проёмов не больше дорожек",
			function()
				for index, level in MathLevels.all do
					expect(level.gates >= 4).to.equal(true)
					expect(level.maxChoices >= 2 and level.maxChoices <= Tunnel.LANE_COUNT).to.equal(true)
					if index > 1 then
						expect(level.gates >= MathLevels.all[index - 1].gates).to.equal(true)
					end
				end
			end
		)

		it(
			"портал ведёт на следующий за пройденными и не дальше последнего",
			function()
				expect(MathLevels.current(nil)).to.equal(1)
				expect(MathLevels.current(3)).to.equal(4)
				expect(MathLevels.current(999)).to.equal(MathLevels.count())
				expect(MathLevels.current("три")).to.equal(1)
			end
		)

		it(
			"путь хранится рядом с путём букв и чистится от мусора",
			function()
				local clean = Levels.sanitize({ letters = 2, math = 5.7, hacker = 1 })
				expect(clean.letters).to.equal(2)
				expect(clean[MathLevels.WORLD]).to.equal(5)
				expect(clean.hacker).to.equal(nil)
				expect(Levels.sanitize({ math = 1e9 })[MathLevels.WORLD]).to.equal(MathLevels.count())
				expect(Levels.sanitize(nil)[MathLevels.WORLD]).to.equal(0)
			end
		)

		it(
			"ворота уровня: столько, сколько в плане, и проёмов не выше потолка",
			function()
				for _, level in MathLevels.all do
					for difficulty = 1, 5 do
						local spec = MathGates.Build(nil, {}, difficulty, level.index)
						expect(spec.targetCount).to.equal(level.gates)
						expect(spec.params.mathLevel).to.equal(level.index)
						for _, gate in spec.params.gates do
							expect(#gate.openings <= level.maxChoices).to.equal(true)
						end
					end
				end
			end
		)
	end)

	describe("Миграция 10 → 11: путь математики", function()
		it("новичок начинает с первого уровня", function()
			local profile = { version = 10, math = {}, levels = { letters = 3 } }
			Migrations.apply(profile, 11)
			expect(profile.levels.letters).to.equal(3)
			expect(profile.levels[MathLevels.WORLD]).to.equal(0)
		end)

		it(
			"открытые ступени засчитываются пройденными уровнями",
			function()
				local mastery = {}
				for stage = 1, 3 do
					mastery[MathConfig.expect(stage).id] = { mastery = 3 }
				end
				local expected = MathLevels.clearedFromMastery(function(stageId)
					return if mastery[stageId] then mastery[stageId].mastery else 0
				end)
				expect(expected > 0).to.equal(true)

				local profile = { version = 10, math = mastery, levels = { letters = 0 } }
				Migrations.apply(profile, 11)
				expect(profile.levels[MathLevels.WORLD]).to.equal(expected)
				expect(MathLevels.current(profile.levels[MathLevels.WORLD])).to.equal(
					MathConfig.current(function(stageId)
						return if mastery[stageId] then mastery[stageId].mastery else 0
					end)
				)
			end
		)

		it("мусор вместо прогресса не роняет миграцию", function()
			local profile = { version = 10, math = "мусор", levels = "тоже" }
			Migrations.apply(profile, 11)
			expect(profile.levels[MathLevels.WORLD]).to.equal(0)
		end)
	end)
end
