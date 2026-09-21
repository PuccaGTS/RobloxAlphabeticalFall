--!nocheck
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Emotes = require(ReplicatedStorage.Shared.Config.Emotes)

return function()
	describe("Config: танцы и жесты", function()
		it(
			"у каждого жеста картинка, название и анимации для обоих типов персонажа",
			function()
				for _, emote in Emotes.list do
					expect(#emote.icon > 0).to.equal(true)
					expect(#emote.title > 0).to.equal(true)
					expect(emote.r15 > 0 and emote.r6 > 0).to.equal(true)
				end
			end
		)

		it(
			"жестов немного: ряд помещается в один экран планшета",
			function()
				expect(#Emotes.list >= 4 and #Emotes.list <= 7).to.equal(true)
			end
		)

		it("буквята радуются только настоящим жестам", function()
			for id in Emotes.PETS_JOIN do
				expect(Emotes.get(id) ~= nil).to.equal(true)
			end
		end)
	end)
end
