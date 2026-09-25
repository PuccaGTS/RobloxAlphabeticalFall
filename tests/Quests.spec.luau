--!nocheck
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Quests = require(ReplicatedStorage.Shared.Logic.Quests)
local Challenges = require(ReplicatedStorage.Shared.Config.Challenges)

local function allIds()
	local ids = {}
	for _, quest in Quests.POOL do
		table.insert(ids, quest.id)
	end
	return ids
end

return function()
	describe("Logic/Quests — выбор на день", function()
		it(
			"три разных задания, первое — уровень одного из миров",
			function()
				for day = 1, 40 do
					local list = Quests.pick(day, allIds())
					expect(#list).to.equal(Quests.PER_DAY)
					expect(Quests.get(list[1]).main).to.equal(true)
					local seen = {}
					for _, id in list do
						expect(seen[id]).to.equal(nil)
						seen[id] = true
					end
					for index = 2, #list do
						expect(Quests.get(list[index]).main).never.to.equal(true)
					end
				end
			end
		)

		it("миры чередуются по дням", function()
			local first = Quests.pick(10, allIds())[1]
			local second = Quests.pick(11, allIds())[1]
			expect(first).never.to.equal(second)
		end)

		it("невыполнимое не выбирается", function()
			local ids = {}
			for _, id in allIds() do
				if id ~= "chest" and id ~= "build" then
					table.insert(ids, id)
				end
			end
			for day = 1, 60 do
				for _, id in Quests.pick(day, ids) do
					expect(id ~= "chest" and id ~= "build").to.equal(true)
				end
			end
		end)

		it(
			"тот же день — те же задания, новый день — новый список",
			function()
				local state, fresh = Quests.refresh(Quests.new(), 100, allIds())
				expect(fresh).to.equal(true)
				local again, changed = Quests.refresh(state, 100, allIds())
				expect(changed).to.equal(false)
				expect(table.concat(again.list, ",")).to.equal(table.concat(state.list, ","))
				local _, nextDay = Quests.refresh(state, 101, allIds())
				expect(nextDay).to.equal(true)
			end
		)

		it(
			"каждое занятие из заданий есть в конфиге испытаний",
			function()
				for _, quest in Quests.POOL do
					local challengeId = string.match(quest.event, "^challenge:(.+)$")
					if challengeId then
						expect(table.find(Challenges.ids(), challengeId)).to.be.ok()
					end
				end
			end
		)
	end)

	describe("Logic/Quests — выполнение", function()
		local function withList(list)
			local state = Quests.new()
			state.day = 5
			state.list = list
			return state
		end

		it(
			"законченное занятие закрывает своё задание один раз",
			function()
				local state = withList({ "letters_level", "rain", "three" })
				local after, done = Quests.record(state, "finished", "letter_rain")
				expect(#done).to.equal(1)
				expect(done[1]).to.equal("rain")
				local _, again = Quests.record(after, "finished", "letter_rain")
				expect(#again).to.equal(0)
			end
		)

		it(
			"«три разных» считает разные занятия, а не повторы",
			function()
				local state = withList({ "letters_level", "three", "buy" })
				state = Quests.record(state, "finished", "bubbles")
				state = Quests.record(state, "finished", "bubbles")
				expect(state.progress.three).to.equal(1)
				state = Quests.record(state, "finished", "mirror")
				local _, done = Quests.record(state, "finished", "scales")
				expect(done[1]).to.equal("three")
			end
		)

		it("все три сделаны — allDone", function()
			local state = withList({ "letters_level", "buy", "build" })
			state = Quests.record(state, "level:letters")
			state = Quests.record(state, "purchase")
			expect(Quests.allDone(state)).to.equal(false)
			state = Quests.record(state, "build")
			expect(Quests.allDone(state)).to.equal(true)
		end)

		it("мусор из профиля не ломает задания", function()
			local clean = Quests.sanitize({
				day = "x",
				list = { "нет такого", "rain", "rain" },
				progress = { rain = -5 },
			})
			expect(clean.day).to.equal(0)
			expect(#clean.list).to.equal(1)
			expect(clean.progress.rain).to.equal(nil)
		end)
	end)
end
