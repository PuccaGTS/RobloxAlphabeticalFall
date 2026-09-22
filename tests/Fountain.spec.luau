--!nocheck
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared

local Fountain = require(Shared.Config.Fountain)
local Decor = require(Shared.Config.Decor)

return function()
	describe("Config: поющий фонтан", function()
		it("стоит там же, где фонтан на площади", function()
			local found = false
			for _, placement in Decor.placements do
				if placement.id == "fountain" then
					found = found
						or (Vector2.new(placement.x, placement.z) - Vector2.new(
								Fountain.CENTER.X,
								Fountain.CENTER.Z
							)).Magnitude
							< 0.5
				end
			end
			expect(found).to.equal(true)
			-- Струи кольца бьют из чаши, а не с травы вокруг.
			expect(Fountain.RING < Decor.expect("fountain").size.X / 2).to.equal(true)
		end)

		it("высота струи всегда от 0 до 1, вне шоу — ноль", function()
			for jet = 0, Fountain.JETS do
				for step = -10, math.floor(Fountain.SECONDS * 10) + 10 do
					local h = Fountain.height(jet, step / 10)
					expect(h >= 0 and h <= 1).to.equal(true)
				end
				expect(Fountain.height(jet, -1)).to.equal(0)
				expect(Fountain.height(jet, Fountain.SECONDS)).to.equal(0)
			end
		end)

		it("в финале бьют все струи, а к концу затихают", function()
			for jet = 0, Fountain.JETS do
				expect(Fountain.height(jet, 24)).to.equal(1)
				expect(Fountain.height(jet, Fountain.SECONDS - 0.05) < 0.1).to.equal(true)
			end
		end)

		it("волна бежит: соседние струи не бьют одинаково", function()
			local differ = 0
			for step = 0, 40 do
				local t = step / 10
				if math.abs(Fountain.height(1, t) - Fountain.height(3, t)) > 0.2 then
					differ += 1
				end
			end
			expect(differ > 10).to.equal(true)
		end)

		it("шоу идёт раз в интервал и короче его", function()
			expect(Fountain.SECONDS < Fountain.EVERY / 2).to.equal(true)
			expect(Fountain.showTime(Fountain.EVERY * 3 + 1)).to.equal(1)
			expect(Fountain.showTime(Fountain.EVERY * 3 + Fountain.SECONDS + 1)).to.equal(nil)
		end)
	end)
end
