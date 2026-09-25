--!nocheck
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared

local Tutorial = require(Shared.Logic.Tutorial)
local AudioRegistry = require(Shared.Config.AudioRegistry)
local Challenges = require(Shared.Config.Challenges)
local Playground = require(Shared.Config.Playground)

return function()
	describe("Tutorial — шаги", function()
		it("новичка ведёт сначала в Буквопад", function()
			expect(Tutorial.current({}).id).to.equal("catch")
			expect(Tutorial.isFresh({})).to.equal(true)
		end)

		it("идёт по порядку: Буквопад → магазин → портал", function()
			local state = {}
			expect(Tutorial.complete(state, "letter_rain")).to.equal("catch")
			expect(Tutorial.current(state).id).to.equal("shop")
			expect(Tutorial.complete(state, "purchase")).to.equal("shop")
			expect(Tutorial.current(state).id).to.equal("run")
			expect(Tutorial.complete(state, "tunnel_run")).to.equal("run")
			-- После первого уровня — прогулка по парку мимо трёх мест.
			expect(Tutorial.current(state).id).to.equal("walk_obby")
			expect(Tutorial.complete(state, "arrive:obby")).to.equal("walk_obby")
			expect(Tutorial.complete(state, "arrive:carousel")).to.equal("walk_carousel")
			expect(Tutorial.complete(state, "arrive:pond")).to.equal("walk_pond")
			expect(Tutorial.current(state)).to.equal(nil)
			expect(Tutorial.isDone(state)).to.equal(true)
		end)

		--[[
			Ребёнок не обязан слушаться стрелку. Побежал сначала в портал —
			шаг засчитан, и потом его туда уже не зовут.
		]]
		it("сделанное вне очереди засчитывается", function()
			local state = {}
			expect(Tutorial.complete(state, "tunnel_run")).to.equal("run")
			expect(Tutorial.current(state).id).to.equal("catch")
			Tutorial.complete(state, "letter_rain")
			Tutorial.complete(state, "purchase")
			for _, id in Tutorial.WALK do
				state[id] = true
			end
			expect(Tutorial.isDone(state)).to.equal(true)
		end)

		it("повтор и чужие события ничего не закрывают", function()
			local state = {}
			Tutorial.complete(state, "letter_rain")
			expect(Tutorial.complete(state, "letter_rain")).to.equal(nil)
			expect(Tutorial.complete(state, "alphabet_ladder")).to.equal(nil)
			expect(Tutorial.complete(state, "math_gates")).to.equal(nil)
			expect(Tutorial.current(state).id).to.equal("shop")
		end)

		it("пропуск отмечает всё сразу", function()
			expect(Tutorial.isDone(Tutorial.finished())).to.equal(true)
		end)
	end)

	describe("Tutorial — данные", function()
		it("чистит мусор из профиля", function()
			expect(next(Tutorial.sanitize(nil))).to.equal(nil)
			expect(next(Tutorial.sanitize("всё"))).to.equal(nil)
			local clean = Tutorial.sanitize({ catch = true, shop = "да", hacker = true })
			expect(clean.catch).to.equal(true)
			expect(clean.shop).to.equal(nil)
			expect(clean.hacker).to.equal(nil)
		end)

		it("узнаёт того, кто уже играл", function()
			expect(Tutorial.hasPlayed({ stars = 0, letters = {}, inventory = {} })).to.equal(false)
			expect(Tutorial.hasPlayed({ stars = 12 })).to.equal(true)
			expect(Tutorial.hasPlayed({ letters = { a = {} } })).to.equal(true)
			expect(Tutorial.hasPlayed({ inventory = { "hat_cap" } })).to.equal(true)
			expect(Tutorial.hasPlayed("мусор")).to.equal(false)
		end)
	end)

	describe("Tutorial — связь с игрой", function()
		-- Обучение не имеет права требовать новой записи: озвучки и так не хватает.
		it("говорит только объявленными репликами", function()
			local declared = {}
			for _, key in AudioRegistry.requiredKeys() do
				declared[key] = true
			end
			for _, step in Tutorial.STEPS do
				if step.vo then
					expect(declared[step.vo]).to.equal(true)
				end
			end
		end)

		it("каждое событие закрывает существующий шаг", function()
			for event, stepId in Tutorial.EVENTS do
				expect(Tutorial.get(stepId)).to.be.ok()
				local spot = string.match(event, "^arrive:(.+)$")
				if spot then
					expect(Playground.expect(spot)).to.be.ok()
				elseif event ~= "purchase" then
					expect(Challenges.get(event)).to.be.ok()
				end
			end
		end)

		-- Имена целей совпадают с тем, как WorldService называет пады: Pad_<испытание>.
		it("пад-цель указывает на существующее испытание", function()
			for _, step in Tutorial.STEPS do
				local challengeId = string.match(step.target, "^Pad_(.+)$")
				if challengeId then
					expect(Challenges.get(challengeId)).to.be.ok()
				end
			end
		end)
	end)
end
