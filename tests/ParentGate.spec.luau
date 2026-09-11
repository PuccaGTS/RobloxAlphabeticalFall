--!nocheck
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ParentGate = require(ReplicatedStorage.Shared.Logic.ParentGate)

return function()
	describe("ParentGate — PIN", function()
		it("PIN — ровно четыре цифры", function()
			expect(ParentGate.isValidPin("0000")).to.equal(true)
			expect(ParentGate.isValidPin("1234")).to.equal(true)
			for _, bad in { "123", "12345", "12a4", " 123", "", 1234, nil, {} } do
				expect(ParentGate.isValidPin(bad)).to.equal(false)
			end
		end)

		it("в профиль уходит не сам PIN", function()
			local stored = ParentGate.hash("1234", "42")
			expect(string.find(stored, "1234", 1, true)).to.equal(nil)
			expect(string.sub(stored, 1, #ParentGate.HASH_PREFIX)).to.equal(ParentGate.HASH_PREFIX)
		end)

		it("хеш повторяется и зависит от соли", function()
			expect(ParentGate.hash("1234", "42")).to.equal(ParentGate.hash("1234", "42"))
			expect(ParentGate.hash("1234", "42")).never.to.equal(ParentGate.hash("1234", "43"))
			expect(ParentGate.hash("1234", "42")).never.to.equal(ParentGate.hash("1243", "42"))
		end)

		it("соседние PIN дают разные хеши", function()
			local seen = {}
			for value = 1230, 1239 do
				local hash = ParentGate.hash(string.format("%04d", value), "42")
				expect(seen[hash]).to.equal(nil)
				seen[hash] = true
			end
		end)

		it("верный PIN подходит, неверный и мусор — нет", function()
			local stored = ParentGate.hash("2580", "7")
			expect(ParentGate.matches("2580", "7", stored)).to.equal(true)
			expect(ParentGate.matches("2581", "7", stored)).to.equal(false)
			expect(ParentGate.matches("2580", "8", stored)).to.equal(false)
			expect(ParentGate.matches(2580, "7", stored)).to.equal(false)
			expect(ParentGate.matches("2580", "7", nil)).to.equal(false)
		end)
	end)

	describe("ParentGate — пауза после ошибок", function()
		it("пять ошибок подряд — минута паузы", function()
			local guard = ParentGate.newGuard()
			for attempt = 1, ParentGate.MAX_ATTEMPTS - 1 do
				expect(ParentGate.registerFailure(guard, 100)).to.equal(ParentGate.MAX_ATTEMPTS - attempt)
				expect(ParentGate.lockedFor(guard, 100)).to.equal(0)
			end
			expect(ParentGate.registerFailure(guard, 100)).to.equal(0)
			expect(ParentGate.lockedFor(guard, 100)).to.equal(ParentGate.LOCK_SECONDS)
			expect(ParentGate.lockedFor(guard, 130)).to.equal(30)
			expect(ParentGate.lockedFor(guard, 100 + ParentGate.LOCK_SECONDS)).to.equal(0)
		end)

		it("после паузы снова пять попыток", function()
			local guard = ParentGate.newGuard()
			for _ = 1, ParentGate.MAX_ATTEMPTS do
				ParentGate.registerFailure(guard, 0)
			end
			expect(ParentGate.registerFailure(guard, 100)).to.equal(ParentGate.MAX_ATTEMPTS - 1)
		end)

		it("верный PIN обнуляет счёт", function()
			local guard = ParentGate.newGuard()
			ParentGate.registerFailure(guard, 0)
			ParentGate.registerFailure(guard, 0)
			ParentGate.registerSuccess(guard)
			expect(ParentGate.registerFailure(guard, 0)).to.equal(ParentGate.MAX_ATTEMPTS - 1)
		end)
	end)

	describe("ParentGate — взрослый вопрос", function()
		it("ответ всегда двузначный", function()
			local random = Random.new(1)
			for _ = 1, 200 do
				local question = ParentGate.adultQuestion(random)
				expect(question.answer >= 10 and question.answer <= 99).to.equal(true)
			end
		end)

		it("принимает ответ с пробелами и только верный", function()
			local question = { text = "Сколько будет 7 × 8?", answer = 56 }
			expect(ParentGate.checkAnswer(question, "56")).to.equal(true)
			expect(ParentGate.checkAnswer(question, " 56 ")).to.equal(true)
			for _, bad in { "65", "5 6", "56а", "", nil, 56 } do
				expect(ParentGate.checkAnswer(question, bad)).to.equal(false)
			end
		end)
	end)
end
