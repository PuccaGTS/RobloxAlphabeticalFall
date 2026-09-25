--!nocheck
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared

local VOText = require(Shared.Config.VOText)
local AudioRegistry = require(Shared.Config.AudioRegistry)
local Stages = require(Shared.Config.Stages)

return function()
	describe("VOText — субтитры", function()
		--[[
			Пока озвучка не записана, субтитр — единственный способ узнать задание.
			Реплика без текста — это задание, которое в тишине не понять вовсе.
		]]
		it("у каждой реплики есть текст", function()
			local music = {}
			for _, key in Stages.THEMES do
				music[key] = true
			end
			for _, key in AudioRegistry.captionKeys() do
				if not music[key] then
					local text = VOText.get(key)
					if text == nil or text == "" then
						error(`у реплики {key} нет текста для субтитров`)
					end
				end
			end
		end)

		it("буквы с собственным именем читаются по имени", function()
			expect(VOText.get("letter_soft")).to.equal("Мягкий знак")
			expect(VOText.get("letter_hard")).to.equal("Твёрдый знак")
			expect(VOText.get("letter_m")).to.equal("Буква М")
		end)

		it("задание из кусков — одной фразой", function()
			expect(VOText.phrase({ "mtask_howmuch", "num_2", "mop_plus", "num_2" })).to.equal(
				"Сколько будет два плюс два"
			)
			expect(VOText.phrase({ "mtask_digit", "num_7" })).to.equal("Беги на цифру семь")
		end)

		it(
			"неизвестный кусок пропускается, а не пишется ключом",
			function()
				expect(VOText.phrase({ "mtask_digit", "непонятно", "num_3" })).to.equal(
					"Беги на цифру три"
				)
			end
		)
	end)
end
