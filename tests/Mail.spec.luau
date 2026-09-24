--!nocheck
--[[
	Почта от буквят (Logic/Mail): открытка приходит за освоенную букву,
	прочитанная больше не поднимает флажок, мусор из профиля не ломает ящик.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Mail = require(ReplicatedStorage.Shared.Logic.Mail)
local MasteryRules = require(ReplicatedStorage.Shared.Logic.MasteryRules)
local Pets = require(ReplicatedStorage.Shared.Logic.Pets)
local Letters = require(ReplicatedStorage.Shared.Config.Letters)

local function mastered(...)
	local letters = {}
	for _, id in { ... } do
		letters[id] = { mastery = MasteryRules.MASTERED }
	end
	return letters
end

return function()
	describe("Logic/Mail", function()
		it("открытка приходит только за освоенную букву", function()
			local letters = mastered("a", "v")
			letters.b = { mastery = MasteryRules.MASTERED - 1 }
			expect(#Mail.received(letters)).to.equal(2)
			local unread = Mail.unread(letters, Mail.new())
			expect(unread[1]).to.equal("a")
			expect(unread[2]).to.equal("v")
		end)

		it("прочитанная открытка больше не ждёт в ящике", function()
			local letters = mastered("a", "b")
			local state = Mail.markRead(Mail.new(), letters, { "a" })
			expect(#Mail.unread(letters, state)).to.equal(1)
			state = Mail.markRead(state, letters, { "b", "b" })
			expect(#Mail.unread(letters, state)).to.equal(0)
			expect(#state.seen).to.equal(2)
		end)

		it("не прочесть открытку, которая не пришла", function()
			local state = Mail.markRead(Mail.new(), mastered("a"), { "ya", "нет_такой" })
			expect(#state.seen).to.equal(0)
		end)

		it("мусор в профиле не ломает ящик", function()
			expect(#Mail.sanitize(nil).seen).to.equal(0)
			expect(#Mail.sanitize({ seen = "а" }).seen).to.equal(0)
			local clean = Mail.sanitize({ seen = { "v", 5, "a", "a", "нет" } })
			expect(#clean.seen).to.equal(2)
			expect(clean.seen[1]).to.equal("a")
		end)

		it(
			"у каждой буквы свой зверёк с эмодзи для открытки",
			function()
				for _, id in Letters.ordered() do
					expect(Pets.SPECIES_ICONS[Pets.speciesOf(id)]).to.be.ok()
				end
				expect(Pets.speciesOf("a")).never.to.equal(Pets.speciesOf("b"))
			end
		)
	end)
end
