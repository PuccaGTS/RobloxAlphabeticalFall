--!nocheck
--[[
	Прокат в парке (Config/Rental): у каждой вещи своя поза и скорость,
	все быстрее бега, но не настолько, чтобы улетать из кадра.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Rental = require(ReplicatedStorage.Shared.Config.Rental)
local AudioRegistry = require(ReplicatedStorage.Shared.Config.AudioRegistry)
local Playground = require(ReplicatedStorage.Shared.Config.Playground)

return function()
	describe("Config: прокат", function()
		it(
			"вещей три, у каждой значок, звук и понятная поза",
			function()
				expect(#Rental.list).to.equal(3)
				for _, vehicle in Rental.list do
					expect(Rental.get(vehicle.id)).to.equal(vehicle)
					expect(#vehicle.icon > 0).to.equal(true)
					local id = AudioRegistry.ids[vehicle.sound]
					expect(id ~= nil and id ~= "").to.equal(true)
					expect(vehicle.pose == "gallop" or Rental.POSES[vehicle.pose] ~= nil).to.equal(true)
				end
			end
		)

		it(
			"на прокате быстрее, чем бегом, но не быстрее двух бегов",
			function()
				for _, vehicle in Rental.list do
					expect(vehicle.speed > Rental.WALK_SPEED).to.equal(true)
					expect(vehicle.speed <= Rental.WALK_SPEED * 2).to.equal(true)
				end
			end
		)

		it("круги ларька помещаются в его место в парке", function()
			local spot = Playground.expect("rental")
			local half = (#Rental.list - 1) / 2 * Rental.PAD_SPACING + Rental.PAD_RADIUS
			expect(half < spot.radius).to.equal(true)
			-- Между соседними кругами есть проход: на чужой круг случайно не наступишь.
			expect(Rental.PAD_SPACING - Rental.PAD_RADIUS * 2 >= 1.5).to.equal(true)
		end)

		it("неизвестная вещь — не вещь", function()
			expect(Rental.get("rocket")).to.equal(nil)
			expect(Rental.get(42)).to.equal(nil)
		end)
	end)
end
