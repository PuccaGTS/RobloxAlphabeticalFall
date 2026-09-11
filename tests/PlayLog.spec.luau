--!nocheck
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PlayLog = require(ReplicatedStorage.Shared.Logic.PlayLog)
local ProfileTemplate = require(ReplicatedStorage.Shared.Config.ProfileTemplate)

local NOW = 1770000000
local TODAY = PlayLog.dayOf(NOW)

local function startOfMoscowDay(day)
	return day * PlayLog.DAY_SEC - PlayLog.TZ_OFFSET_SEC
end

local function atDay(day, offset)
	return startOfMoscowDay(day) + offset
end

local function newProfile()
	return ProfileTemplate.new(NOW)
end

return function()
	describe("PlayLog.dayOf", function()
		it("разделяет дни по московской полуночи", function()
			local beforeMidnight = atDay(TODAY, PlayLog.DAY_SEC - 60)
			local afterMidnight = atDay(TODAY + 1, 60)

			expect(PlayLog.dayOf(beforeMidnight)).to.equal(TODAY)
			expect(PlayLog.dayOf(afterMidnight)).to.equal(TODAY + 1)

			-- московская полночь — это 21:00 по UTC, по которому живёт сервер
			local utcStart = math.floor(NOW / PlayLog.DAY_SEC) * PlayLog.DAY_SEC
			local utc2059 = utcStart + 20 * 60 * 60 + 59 * 60
			local utc2101 = utcStart + 21 * 60 * 60 + 60

			expect(PlayLog.dayOf(utc2059) + 1).to.equal(PlayLog.dayOf(utc2101))
		end)
	end)

	describe("PlayLog.addPlay", function()
		it("копит время дня и создаёт запись следующего", function()
			local profile = newProfile()

			PlayLog.addPlay(profile, atDay(TODAY, 60), 30)
			PlayLog.addPlay(profile, atDay(TODAY, 120), 60)
			PlayLog.addPlay(profile, atDay(TODAY + 1, 60), 90)

			expect(#profile.playLog).to.equal(2)
			expect(profile.playLog[1].day).to.equal(TODAY)
			expect(profile.playLog[1].sec).to.equal(90)
			expect(profile.playLog[2].day).to.equal(TODAY + 1)
			expect(profile.playLog[2].sec).to.equal(90)
			expect(profile.stats.totalPlayMin).to.be.near(3.0, 0.001)
		end)

		it("игнорирует нулевое и испорченное время", function()
			local profile = newProfile()

			PlayLog.addPlay(profile, atDay(TODAY, 60), 0)
			PlayLog.addPlay(profile, atDay(TODAY, 60), -1)
			PlayLog.addPlay(profile, atDay(TODAY, 60), 0 / 0)
			PlayLog.addPlay(profile, atDay(TODAY, 60), math.huge)

			expect(#profile.playLog).to.equal(0)
			expect(profile.stats.totalPlayMin).to.equal(0)
			expect(profile.dailyStreak).to.equal(0)
		end)

		it("удаляет дни старше срока хранения", function()
			local profile = newProfile()
			profile.playLog = {
				{ day = TODAY - PlayLog.KEEP_DAYS, sec = 100 },
				{ day = TODAY - PlayLog.KEEP_DAYS + 1, sec = 100 },
			}

			PlayLog.addPlay(profile, atDay(TODAY, 60), 60)

			expect(#profile.playLog).to.equal(2)
			expect(profile.playLog[1].day).to.equal(TODAY - PlayLog.KEEP_DAYS + 1)
			expect(profile.playLog[2].day).to.equal(TODAY)
		end)

		it(
			"при переводе часов назад пишет в последнюю запись",
			function()
				local profile = newProfile()
				profile.playLog = {
					{ day = TODAY - 2, sec = 10 },
					{ day = TODAY, sec = 20 },
				}

				PlayLog.addPlay(profile, atDay(TODAY - 1, 60), 30)

				expect(#profile.playLog).to.equal(2)
				expect(profile.playLog[1].day).to.equal(TODAY - 2)
				expect(profile.playLog[1].sec).to.equal(10)
				expect(profile.playLog[2].day).to.equal(TODAY)
				expect(profile.playLog[2].sec).to.equal(50)
			end
		)
	end)

	describe("PlayLog.Серия и активные дни", function()
		it(
			"серия растёт подряд и прерывается после пропуска",
			function()
				local profile = newProfile()

				PlayLog.addPlay(profile, atDay(TODAY - 3, 60), PlayLog.MIN_ACTIVE_SEC)
				expect(profile.dailyStreak).to.equal(1)

				PlayLog.addPlay(profile, atDay(TODAY - 2, 60), PlayLog.MIN_ACTIVE_SEC)
				expect(profile.dailyStreak).to.equal(2)

				-- второй сеанс в тот же день серию не удваивает
				PlayLog.addPlay(profile, atDay(TODAY - 2, 120), PlayLog.MIN_ACTIVE_SEC)
				expect(profile.dailyStreak).to.equal(2)

				PlayLog.addPlay(profile, atDay(TODAY, 60), PlayLog.MIN_ACTIVE_SEC)
				expect(profile.dailyStreak).to.equal(1)
			end
		)

		it("засчитывает серию только после минуты занятий", function()
			local profile = newProfile()

			PlayLog.addPlay(profile, atDay(TODAY, 60), PlayLog.MIN_ACTIVE_SEC - 1)
			expect(profile.dailyStreak).to.equal(0)
			expect(profile.lastLoginDay).to.equal(0)

			PlayLog.addPlay(profile, atDay(TODAY, 120), 1)
			expect(profile.dailyStreak).to.equal(1)
			expect(profile.lastLoginDay).to.equal(TODAY)
		end)

		it("серия прерывается, если пропущен день", function()
			local profile = newProfile()
			profile.dailyStreak = 5

			profile.lastLoginDay = TODAY
			expect(PlayLog.currentStreak(profile, atDay(TODAY, 60))).to.equal(5)

			profile.lastLoginDay = TODAY - 1
			expect(PlayLog.currentStreak(profile, atDay(TODAY, 60))).to.equal(5)

			profile.lastLoginDay = TODAY - 2
			expect(PlayLog.currentStreak(profile, atDay(TODAY, 60))).to.equal(0)
		end)

		it("считает только активные дни внутри окна", function()
			local log = {
				{ day = TODAY, sec = PlayLog.MIN_ACTIVE_SEC },
				{ day = TODAY - 1, sec = PlayLog.MIN_ACTIVE_SEC },
				{ day = TODAY - 2, sec = PlayLog.MIN_ACTIVE_SEC - 1 },
				{ day = TODAY - 7, sec = PlayLog.MIN_ACTIVE_SEC },
				{ day = TODAY + 1, sec = PlayLog.MIN_ACTIVE_SEC },
			}

			expect(PlayLog.activeDays(log, atDay(TODAY, 60), 7)).to.equal(2)
		end)
	end)

	describe("PlayLog.sanitize", function()
		it(
			"очищает, склеивает, сортирует и оставляет новые дни",
			function()
				expect(#PlayLog.sanitize("не таблица")).to.equal(0)

				local cleaned = PlayLog.sanitize({
					{ day = 10, sec = 20 },
					{ day = 8, sec = 5 },
					{ day = 10, sec = 40 },
					{ day = "день", sec = 10 },
					{ day = 7, sec = "секунды" },
					{ day = -1, sec = 10 },
					{ day = 6, sec = -1 },
					{ day = 5, sec = 0 / 0 },
					{ day = 0 / 0, sec = 10 },
				})

				expect(#cleaned).to.equal(2)
				expect(cleaned[1].day).to.equal(8)
				expect(cleaned[1].sec).to.equal(5)
				expect(cleaned[2].day).to.equal(10)
				expect(cleaned[2].sec).to.equal(60)

				local manyDays = {}
				for day = 1, PlayLog.KEEP_DAYS + 2 do
					table.insert(manyDays, { day = day, sec = 1 })
				end

				local capped = PlayLog.sanitize(manyDays)
				expect(#capped).to.equal(PlayLog.KEEP_DAYS)
				expect(capped[1].day).to.equal(3)
				expect(capped[#capped].day).to.equal(PlayLog.KEEP_DAYS + 2)
			end
		)
	end)
end
