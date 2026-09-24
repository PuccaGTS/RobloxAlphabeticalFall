--!nocheck
--[[
	Вечер в парке (Config/Evening): день главнее, сумерки светлые, утро
	не приходит через полдень, а круг замыкается без скачка.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Evening = require(ReplicatedStorage.Shared.Config.Evening)

local function luminance(color: Color3): number
	return 0.2126 * color.R + 0.7152 * color.G + 0.0722 * color.B
end

return function()
	describe("Config: вечер в парке", function()
		it(
			"расписание идёт по порядку от нуля до конца круга",
			function()
				local timeline = Evening.TIMELINE
				expect(timeline[1].at).to.equal(0)
				expect(timeline[#timeline].at).to.equal(Evening.CYCLE)
				expect(timeline[1].look).to.equal("day")
				expect(timeline[#timeline].look).to.equal("day")
				for index, row in timeline do
					expect(Evening.LOOKS[row.look]).to.be.ok()
					if index > 1 then
						expect(row.at > timeline[index - 1].at).to.equal(true)
					end
				end
			end
		)

		it(
			"день занимает больше половины круга, сумерки — минуту-другую",
			function()
				local day, night = 0, 0
				for t = 0, Evening.CYCLE - 1 do
					local look = Evening.sample(t)
					if look.glow == 0 and look.clock == Evening.LOOKS.day.clock then
						day += 1
					end
					if look.glow >= Evening.NIGHT_FROM then
						night += 1
					end
				end
				expect(day / Evening.CYCLE > 0.6).to.equal(true)
				expect(night >= 90).to.equal(true)
				expect(night / Evening.CYCLE < 0.25).to.equal(true)
			end
		)

		it("сумерки светлые: подсветка не темнее дневной", function()
			local evening = Evening.LOOKS.evening
			expect(luminance(evening.outdoor) >= luminance(Evening.LOOKS.day.outdoor)).to.equal(true)
			expect(luminance(evening.ambient) >= luminance(Evening.LOOKS.day.ambient)).to.equal(true)
		end)

		it(
			"утро приходит из утренних сумерек, а не через полдень",
			function()
				-- Вечерние и утренние сумерки симметричны относительно полудня: скачок не виден.
				expect(Evening.LOOKS.evening.clock + Evening.LOOKS.dawn.clockFrom).to.equal(24)
				for t = 0, Evening.CYCLE - 1, 0.5 do
					local a = Evening.sample(t)
					local b = Evening.sample(t + 0.5)
					local jump = math.abs(a.clock - b.clock)
					-- Единственный скачок часов — в самый тёмный миг, из сумерек в сумерки.
					if jump > 1 then
						expect(a.clock).to.be.near(Evening.LOOKS.evening.clock, 0.01)
						expect(b.clock).to.be.near(Evening.LOOKS.dawn.clockFrom, 0.1)
					end
					expect(math.abs(a.brightness - b.brightness) < 0.2).to.equal(true)
				end
			end
		)

		it(
			"круг замыкается: конец круга — тот же день, что начало",
			function()
				local first = Evening.sample(0)
				local last = Evening.sample(Evening.CYCLE - 0.01)
				expect(last.clock).to.be.near(first.clock, 0.01)
				expect(last.glow).to.be.near(0, 0.01)
			end
		)

		it(
			"вне парка — день: смесь с долей ноль даёт дневной свет",
			function()
				local mixed = Evening.blend(Evening.LOOKS.day, Evening.sample(640), 0)
				expect(mixed.clock).to.equal(Evening.LOOKS.day.clock)
				expect(mixed.glow).to.equal(0)
				expect(Evening.inHub(Vector3.new(40, 5, -300))).to.equal(true)
				expect(Evening.inHub(Vector3.new(-2600, 250, 0))).to.equal(false)
				expect(Evening.inHub(Vector3.new(2900, 200, -50))).to.equal(false)
			end
		)
	end)
end
