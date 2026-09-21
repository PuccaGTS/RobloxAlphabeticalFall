--!nocheck
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared

local Rides = require(Shared.Config.Rides)
local Decor = require(Shared.Config.Decor)
local Base = require(Shared.Config.Base)
local Playground = require(Shared.Config.Playground)

return function()
	describe("Config: паровозик и колесо обозрения", function()
		it(
			"эстакада идёт между парком и домами: ни декор, ни участки её не задевают",
			function()
				local radius = Rides.TRAIN.radius
				for _, placement in Decor.placements do
					local item = Decor.expect(placement.id)
					local reach = Vector2.new(placement.x, placement.z).Magnitude
						+ math.max(item.size.X, item.size.Z) * (placement.scale or 1) / 2
					expect(reach < radius - 6).to.equal(true)
				end
				expect(radius + 6 < Rides.PLOT_INNER).to.equal(true)
			end
		)

		it(
			"станция стоит в полосе между парком и домами, пандус не упирается в участок",
			function()
				local station = Rides.stationFrame()
				local reach = Vector2.new(station.Position.X, station.Position.Z).Magnitude
				expect(reach > Decor.MAX_RADIUS).to.equal(true)
				expect(reach < Rides.TRAIN.radius).to.equal(true)
				-- Между участками: станция не у калитки ни одного дома.
				for index = 1, Base.PLOT_COUNT do
					local plot = Base.plotPosition(index)
					expect(
						(Vector2.new(plot.X, plot.Z) - Vector2.new(station.Position.X, station.Position.Z)).Magnitude
							> Base.PLOT_SIZE / 2 + 20
					).to.equal(true)
				end
			end
		)

		it(
			"поезд стоит у платформы в начале цикла и возвращается к ней после круга",
			function()
				local cycle = Rides.trainCycle()
				local start, standing = Rides.trainAt(0)
				expect(standing).to.equal(true)
				local finish, standingAgain = Rides.trainAt(cycle - 0.001)
				expect(standingAgain).to.equal(false)
				expect(math.abs((finish - start) - math.pi * 2) < 0.01).to.equal(true)
				local _, next = Rides.trainAt(cycle + 0.5)
				expect(next).to.equal(true)
			end
		)

		it(
			"поезд едет без рывков: за кадр голова сдвигается меньше чем на полстуда",
			function()
				local previous = Rides.trainAt(0)
				for step = 1, math.floor(Rides.trainCycle() * 60) do
					local angle = Rides.trainAt(step / 60)
					expect(math.abs(angle - previous) * Rides.TRAIN.radius < 0.8).to.equal(true)
					previous = angle
				end
			end
		)

		it(
			"нижняя кабинка колеса над травой, верхняя — выше всего парка",
			function()
				local lowest = math.huge
				local highest = -math.huge
				for index = 1, Rides.WHEEL.cabins do
					local y = Rides.WHEEL.axle + Rides.cabinOffset(index, 0).Y
					lowest = math.min(lowest, y - Rides.WHEEL.cabinSize.Y / 2)
					highest = math.max(highest, y)
				end
				expect(lowest > 0.5).to.equal(true)
				expect(highest > 30).to.equal(true)
			end
		)

		it(
			"нижней считается та кабинка, что ближе всех к земле",
			function()
				expect(Rides.lowestCabin(0)).to.equal(1)
				local step = math.pi * 2 / Rides.WHEEL.cabins
				-- Колесо повернулось на шаг: внизу теперь предыдущая по кругу кабинка.
				expect(Rides.lowestCabin(step)).to.equal(Rides.WHEEL.cabins)
			end
		)

		it("колесо стоит на своём месте в парке", function()
			local spot = Playground.expect(Rides.WHEEL.spot)
			expect(spot.radius >= Rides.WHEEL.diameter / 2 - 2).to.equal(true)
		end)
	end)
end
