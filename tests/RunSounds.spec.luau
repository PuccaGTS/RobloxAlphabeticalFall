--!nocheck
-- Звуки аттракционов: каждый ключ есть в реестре и указывает на звук библиотеки.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RunSounds = require(ReplicatedStorage.Shared.Config.RunSounds)
local AudioRegistry = require(ReplicatedStorage.Shared.Config.AudioRegistry)

return function()
	describe("Config/RunSounds", function()
		it("у каждого звука есть ID в реестре", function()
			for _, list in { RunSounds.EVENTS, RunSounds.LOOPS } do
				for _, event in list do
					local id = AudioRegistry.ids[event.key]
					expect(id).to.be.ok()
					expect(string.match(id, "^rbxassetid://%d+$")).to.be.ok()
					expect(event.volume > 0 and event.volume <= 1).to.equal(true)
					if event.speed then
						expect(event.speed[1] <= event.speed[2]).to.equal(true)
					end
				end
			end
		end)

		it("разовый звук убирается не раньше, чем доиграет", function()
			for _, event in RunSounds.EVENTS do
				expect(event.seconds >= 1).to.equal(true)
			end
		end)
	end)
end
