--!nocheck
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared

local PlayLimit = require(Shared.Logic.PlayLimit)
local PlayLog = require(Shared.Logic.PlayLog)

return function()
	describe("PlayLimit — лимит в день", function()
		it("принимает только значения из доки", function()
			for _, minutes in { 15, 20, 30, 45 } do
				expect(PlayLimit.sanitizeLimit(minutes)).to.equal(minutes)
			end
			for _, bad in { 0, 10, 25, 60, -15, 15.5, "20", nil, 0 / 0 } do
				expect(PlayLimit.sanitizeLimit(bad)).to.equal(nil)
			end
		end)

		it("без лимита время не кончается никогда", function()
			expect(PlayLimit.isOver(nil, 10 * 60 * 60)).to.equal(false)
			expect(PlayLimit.minutesLeft(nil, 99999)).to.equal(nil)
		end)

		it("кончается ровно на лимите", function()
			expect(PlayLimit.isOver(20, 20 * 60 - 1)).to.equal(false)
			expect(PlayLimit.isOver(20, 20 * 60)).to.equal(true)
			expect(PlayLimit.minutesLeft(20, 5 * 60)).to.equal(15)
			expect(PlayLimit.minutesLeft(20, 25 * 60)).to.equal(0)
		end)

		-- Подделанный лимит не должен ни запирать ребёнка, ни угадываться за родителя.
		it("мусорный лимит считается выключенным", function()
			expect(PlayLimit.isOver(1, 3600)).to.equal(false)
		end)
	end)

	describe("PlayLimit — отдых", function()
		it("раз в двадцать минут, и только если включено", function()
			local every = PlayLimit.REST_EVERY_SEC
			expect(PlayLimit.restDue(true, every - 1, 0)).to.equal(false)
			expect(PlayLimit.restDue(true, every, 0)).to.equal(true)
			expect(PlayLimit.restDue(true, every + 60, every)).to.equal(false)
			expect(PlayLimit.restDue(true, 2 * every, every)).to.equal(true)
			expect(PlayLimit.restDue(false, 10 * every, 0)).to.equal(false)
		end)
	end)

	describe("PlayLimit — настройки родителя", function()
		it(
			"напоминание включено, пока его явно не выключили",
			function()
				expect(PlayLimit.sanitizeParent(nil).restReminder).to.equal(true)
				expect(PlayLimit.sanitizeParent({}).restReminder).to.equal(true)
				expect(PlayLimit.sanitizeParent({ restReminder = "нет" }).restReminder).to.equal(true)
				expect(PlayLimit.sanitizeParent({ restReminder = false }).restReminder).to.equal(false)
			end
		)

		it("PIN и лимит переживают чистку, мусор — нет", function()
			local clean = PlayLimit.sanitizeParent({ pinHash = "x:1", dailyLimitMin = 30, hacker = 1 })
			expect(clean.pinHash).to.equal("x:1")
			expect(clean.dailyLimitMin).to.equal(30)
			expect(clean.hacker).to.equal(nil)
			expect(PlayLimit.sanitizeParent({ pinHash = 42, dailyLimitMin = 999 }).pinHash).to.equal(nil)
		end)
	end)

	describe("PlayLog.secondsOn — сколько сыграно за сутки", function()
		it("считает только нужные сутки", function()
			local log = { { day = 100, sec = 300 }, { day = 101, sec = 720 } }
			expect(PlayLog.secondsOn(log, 101)).to.equal(720)
			expect(PlayLog.secondsOn(log, 100)).to.equal(300)
			expect(PlayLog.secondsOn(log, 102)).to.equal(0)
		end)

		it("мусор в записи не роняет счёт", function()
			expect(PlayLog.secondsOn({ { day = 5, sec = "много" }, { day = 5, sec = 60 } }, 5)).to.equal(
				60
			)
		end)
	end)
end
