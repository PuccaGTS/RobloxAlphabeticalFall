--!nocheck
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Quests = require(ReplicatedStorage.Shared.Logic.Quests)
local Challenges = require(ReplicatedStorage.Shared.Config.Challenges)
local Playground = require(ReplicatedStorage.Shared.Config.Playground)
local Shop = require(ReplicatedStorage.Shared.Config.Shop)

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
					-- Второе — уголок парка, третье — не парк: парк каждый день, но не весь список.
					expect(Quests.get(list[2]).park).to.equal(true)
					expect(Quests.get(list[3]).park).never.to.equal(true)
				end
			end
		)

		it(
			"соседние дни ведут в разные уголки парка, за круг — во все",
			function()
				local seen = {}
				local parks = 0
				for _, quest in Quests.POOL do
					if quest.park then
						parks += 1
					end
				end
				for day = 1, parks do
					local today = Quests.pick(day, allIds())[2]
					local tomorrow = Quests.pick(day + 1, allIds())[2]
					expect(today).never.to.equal(tomorrow)
					seen[today] = true
				end
				local count = 0
				for _ in seen do
					count += 1
				end
				expect(count).to.equal(parks)
			end
		)

		it("задание про парк ведёт к своему месту парка", function()
			for _, quest in Quests.POOL do
				if quest.park then
					local spot = string.match(quest.event, "^park:(.+)$")
					expect(spot).to.be.ok()
					expect(Playground.expect(spot)).to.be.ok()
					expect(quest.target).to.equal(`spot:{spot}`)
				end
			end
		end)

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
	describe("Logic/Quests — задание недели", function()
		local function fresh(day)
			return (Quests.refresh(Quests.new(), day, allIds()))
		end

		it(
			"неделя заводится сама, держится семь дней и сменяется на восьмой",
			function()
				local state = fresh(70)
				expect(state.week).to.be.ok()
				expect(state.week.week).to.equal(Quests.weekOf(70))
				state = Quests.recordWeek(state, "level:letters")
				local sameWeek = Quests.refresh(state, 76, allIds())
				expect(sameWeek.week.have).to.equal(state.week.have)
				local nextWeek = Quests.refresh(state, 77, allIds())
				expect(nextWeek.week.week).to.equal(Quests.weekOf(77))
				expect(nextWeek.week.have).to.equal(0)
			end
		)

		it(
			"уровни обоих миров идут в «пройди 5 уровней», и неделя закрывается один раз",
			function()
				local state = fresh(0)
				state.week = { week = 0, id = "week_levels", have = 0, seen = {}, done = false }
				local done
				for index = 1, 4 do
					state, done =
						Quests.recordWeek(state, if index % 2 == 0 then "level:math" else "level:letters")
					expect(done).to.equal(false)
				end
				state, done = Quests.recordWeek(state, "level:letters")
				expect(done).to.equal(true)
				local _, again = Quests.recordWeek(state, "level:letters")
				expect(again).to.equal(false)
			end
		)

		it(
			"уголки парка считаются разными, повтор не в счёт",
			function()
				local state = fresh(0)
				state.week = { week = 0, id = "week_park", have = 0, seen = {}, done = false }
				state = Quests.recordWeek(state, "park:balloon")
				state = Quests.recordWeek(state, "park:balloon")
				state = Quests.recordWeek(state, "park:grotto")
				expect(state.week.have).to.equal(2)
				expect(Quests.sanitize(state).week.seen[2]).to.equal("grotto")
			end
		)

		it(
			"награды недели — не продаются, идут по порядку и есть в магазине",
			function()
				for index, id in Quests.WEEK_REWARDS do
					local item = Shop.expect(id)
					expect(item.price).to.equal(nil)
					expect(Shop.weekNumber(item)).to.equal(index)
				end
				expect(Quests.weekReward({})).to.equal(Quests.WEEK_REWARDS[1])
				expect(Quests.weekReward({ Quests.WEEK_REWARDS[1] })).to.equal(Quests.WEEK_REWARDS[2])
				expect(Quests.weekReward(table.clone(Quests.WEEK_REWARDS))).to.equal(nil)
			end
		)

		it("мусор в неделе не ломает профиль", function()
			local clean = Quests.sanitize({ week = { week = 3, id = "нет такого", have = 99 } })
			expect(clean.week).to.equal(nil)
			clean = Quests.sanitize({ week = { week = 3, id = "week_play", have = 99, seen = { 1, "x" } } })
			expect(clean.week.have).to.equal(Quests.weekly("week_play").need)
			expect(#clean.week.seen).to.equal(1)
		end)
	end)
end
