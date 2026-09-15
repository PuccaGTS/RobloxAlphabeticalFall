--!nocheck
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared

local ProfileRestart = require(Shared.Logic.ProfileRestart)
local ProfileTemplate = require(Shared.Config.ProfileTemplate)
local MasteryRules = require(Shared.Logic.MasteryRules)
local Levels = require(Shared.Config.Levels)

local NOW = 1_800_000_000
local TODAY = 20_000

-- Профиль ребёнка, который поиграл: есть что стирать и что беречь.
local function played()
	local profile = ProfileTemplate.new(NOW)
	local letter = MasteryRules.newProgress(NOW)
	letter.mastery = 3
	profile.letters.a = letter
	profile.math.count_small = MasteryRules.newProgress(NOW)
	profile.stages[2] = { unlocked = true, chests = { "secret" } }
	profile.stages[1].chests = { "secret" }
	profile.runs.tunnel =
		{ challengeId = "tunnel", seed = 1, letters = { "a" }, difficulty = 1, checkpoint = 2, savedAt = NOW }
	profile.levels = { [Levels.WORLD] = 4 }
	profile.difficulty.letter_rain = 3
	profile.equipped.pets = { "a" }

	profile.stars = 420
	profile.inventory = { "cap" }
	profile.equipped.hat = "cap"
	profile.base.house = 2
	profile.tutorial = { catch = true, shop = true, run = true }
	profile.playLog = { { day = TODAY, sec = 900 } }
	profile.settings.music = 0.25
	profile.parent.pinHash = "hash"
	profile.parent.dailyLimitMin = 20
	profile.daily = { day = TODAY - 1, letterId = "k", done = 3, streak = 5, best = 7, lastDay = TODAY - 1 }
	return profile
end

return function()
	describe("ProfileRestart.apply", function()
		it("стирает всё, что ребёнок знает", function()
			local profile = played()
			ProfileRestart.apply(profile, TODAY)

			expect(next(profile.letters)).to.equal(nil)
			expect(next(profile.math)).to.equal(nil)
			expect(next(profile.runs)).to.equal(nil)
			expect(next(profile.difficulty)).to.equal(nil)
			expect(#profile.equipped.pets).to.equal(0)
			expect(Levels.sanitize(profile.levels)[Levels.WORLD]).to.equal(0)
		end)

		it(
			"оставляет открытой одну первую ступень, без найденных секретов",
			function()
				local profile = played()
				ProfileRestart.apply(profile, TODAY)

				expect(#profile.stages).to.equal(1)
				expect(profile.stages[1].unlocked).to.equal(true)
				expect(#profile.stages[1].chests).to.equal(0)
			end
		)

		it("не трогает заработанное и родительское", function()
			local profile = played()
			ProfileRestart.apply(profile, TODAY)

			expect(profile.stars).to.equal(420)
			expect(profile.inventory[1]).to.equal("cap")
			expect(profile.equipped.hat).to.equal("cap")
			expect(profile.base.house).to.equal(2)
			expect(profile.tutorial.run).to.equal(true)
			expect(profile.settings.music).to.equal(0.25)
			expect(profile.parent.pinHash).to.equal("hash")
			expect(profile.parent.dailyLimitMin).to.equal(20)
		end)

		it(
			"история занятий остаётся: иначе сброс снимал бы лимит на сегодня",
			function()
				local profile = played()
				ProfileRestart.apply(profile, TODAY)
				expect(#profile.playLog).to.equal(1)
				expect(profile.playLog[1].sec).to.equal(900)
			end
		)

		it(
			"серия буквы дня и рекорд остаются, вчерашняя буква выбирается заново",
			function()
				local profile = played()
				ProfileRestart.apply(profile, TODAY)

				expect(profile.daily.streak).to.equal(5)
				expect(profile.daily.best).to.equal(7)
				expect(profile.daily.lastDay).to.equal(TODAY - 1)
				expect(profile.daily.letterId).to.equal(nil)
				expect(profile.daily.done).to.equal(0)
			end
		)

		it(
			"сегодняшняя буква без заданий выбирается заново",
			function()
				local profile = played()
				profile.daily =
					{ day = TODAY, letterId = "k", done = 0, streak = 1, best = 1, lastDay = TODAY - 1 }
				ProfileRestart.apply(profile, TODAY)
				expect(profile.daily.letterId).to.equal(nil)
			end
		)

		it(
			"начатая сегодня буква остаётся со счётчиком: второй награды за день нет",
			function()
				local profile = played()
				profile.daily =
					{ day = TODAY, letterId = "k", done = 2, streak = 1, best = 1, lastDay = TODAY - 1 }
				ProfileRestart.apply(profile, TODAY)
				expect(profile.daily.letterId).to.equal("k")
				expect(profile.daily.done).to.equal(2)
				expect(profile.daily.day).to.equal(TODAY)
			end
		)

		it(
			"сброшенный профиль совпадает с новым по всему, что относится к обучению",
			function()
				local profile = played()
				ProfileRestart.apply(profile, TODAY)
				local blank = ProfileTemplate.new(NOW)
				local snapshot = ProfileTemplate.toSnapshot(profile)
				local fresh = ProfileTemplate.toSnapshot(blank)

				expect(next(snapshot.mastery)).to.equal(nil)
				expect(next(snapshot.math)).to.equal(nil)
				expect(#snapshot.stages).to.equal(#fresh.stages)
				expect(snapshot.levels[Levels.WORLD]).to.equal(fresh.levels[Levels.WORLD])
			end
		)
	end)
end
