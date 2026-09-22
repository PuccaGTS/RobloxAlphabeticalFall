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

		it(
			"лошадки карусели скачут на помосте и под шатром",
			function()
				local spec = Rides.CAROUSEL
				for index = 1, spec.horses do
					for step = 0, 40 do
						local now = step * 0.37
						local frame = Rides.horseFrame(index, Rides.carouselAngle(now), now)
						local flat = Vector2.new(frame.Position.X, frame.Position.Z).Magnitude
						expect(flat + 2 < spec.platform / 2).to.equal(true)
						-- Голова лошадки (на 3 студа выше спины) не упирается в шатёр.
						expect(frame.Position.Y + 3.2 < spec.roof).to.equal(true)
						-- Смотрит по ходу: вперёд — туда, куда растёт угол.
						local ahead = Rides.horseFrame(index, Rides.carouselAngle(now) + 0.01, now).Position
						expect(frame.LookVector:Dot((ahead - frame.Position).Unit) > 0.9).to.equal(true)
					end
				end
			end
		)

		it(
			"карусель, горка и шар стоят на своих местах в парке",
			function()
				expect(Playground.expect(Rides.CAROUSEL.spot).radius >= Rides.CAROUSEL.platform / 2 + 5).to.equal(
					true
				)
				expect(
					Playground.expect(Rides.SLIDE.spot).radius
						>= Rides.SLIDE.radius + Rides.SLIDE.width / 2 + 4
				).to.equal(true)
				expect(Playground.expect(Rides.BALLOON.spot).radius >= 10).to.equal(true)
			end
		)

		it(
			"к лестнице горки проходишь под жёлобом не пригибаясь",
			function()
				local spec = Rides.SLIDE
				for _, height in Rides.slideHeightsAt(spec.ladderAngle) do
					expect(height > 6.5).to.equal(true)
				end
				-- Витки жёлоба друг над другом: между ними помещается ребёнок.
				local heights = Rides.slideHeightsAt(90)
				expect(#heights).to.equal(2)
				expect(heights[1] - heights[2] > 7).to.equal(true)
				-- Лестница не задевает жёлоб: жёлоб дальше от оси, чем сетка.
				expect(spec.radius - spec.width / 2 > spec.platform + 2).to.equal(true)
			end
		)

		it(
			"жёлоб горки идёт сверху вниз без скачков, а ребёнок разгоняется",
			function()
				local previous = Rides.slidePoint(0)
				expect(math.abs(previous.Y - Rides.SLIDE.height) < 1e-6).to.equal(true)
				for step = 1, 100 do
					local point = Rides.slidePoint(step / 100)
					expect(point.Y < previous.Y).to.equal(true)
					expect((point - previous).Magnitude < 2).to.equal(true)
					previous = point
				end
				expect(Rides.slideProgress(0)).to.equal(0)
				expect(Rides.slideProgress(Rides.SLIDE.seconds)).to.equal(1)
				local early = Rides.slideProgress(0.5) - Rides.slideProgress(0)
				local late = Rides.slideProgress(Rides.SLIDE.seconds)
					- Rides.slideProgress(Rides.SLIDE.seconds - 0.5)
				expect(late > early).to.equal(true)
			end
		)

		it(
			"воздушный шар взлетает с лужайки и садится туда же",
			function()
				local inward = Vector3.new(0.6, 0, -0.8)
				local cycle = Rides.balloonCycle()
				local offset, grounded = Rides.balloonAt(0, inward)
				expect(grounded).to.equal(true)
				expect(offset.Magnitude).to.equal(0)
				local landing = Rides.balloonAt(cycle - 0.01, inward)
				expect(landing.Magnitude < 0.5).to.equal(true)
				local highest = 0
				local previous = Vector3.zero
				for step = 1, math.floor(cycle * 10) do
					local here = Rides.balloonAt(step / 10, inward)
					highest = math.max(highest, here.Y)
					-- Без рывков: за десятую секунды меньше чем на полтора студа.
					expect((here - previous).Magnitude < 1.5).to.equal(true)
					previous = here
				end
				expect(math.abs(highest - Rides.BALLOON.height) < 0.5).to.equal(true)
			end
		)

		it(
			"воздушный шар летает выше колеса обозрения и в стороне от эстакады",
			function()
				local spot = Playground.expect(Rides.BALLOON.spot)
				local home = Playground.position(spot)
				local inward = (-home * Vector3.new(1, 0, 1)).Unit
				for step = 0, math.floor(Rides.balloonCycle()) do
					local offset, grounded = Rides.balloonAt(step, inward)
					local flat = Vector2.new(home.X + offset.X, home.Z + offset.Z).Magnitude
					-- Над площадью и парком, а не над домами и не над поездом.
					expect(flat < Rides.TRAIN.radius - 10).to.equal(true)
					local wheel = Playground.position(Playground.expect(Rides.WHEEL.spot))
					local nearWheel = (Vector2.new(home.X + offset.X, home.Z + offset.Z) - Vector2.new(
						wheel.X,
						wheel.Z
					)).Magnitude
					if not grounded and nearWheel < Rides.WHEEL.diameter then
						expect(offset.Y > Rides.WHEEL.axle + Rides.WHEEL.diameter / 2 + 10).to.equal(true)
					end
				end
			end
		)

		it("колесо стоит на своём месте в парке", function()
			local spot = Playground.expect(Rides.WHEEL.spot)
			expect(spot.radius >= Rides.WHEEL.diameter / 2 - 2).to.equal(true)
		end)
	end)
end
