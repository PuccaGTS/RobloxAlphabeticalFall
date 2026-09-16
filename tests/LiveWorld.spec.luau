--!nocheck
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared

local LiveWorld = require(Shared.Config.LiveWorld)
local Decor = require(Shared.Config.Decor)

return function()
	describe("Config: живой мир", function()
		-- docs/18-CONTENT-BACKLOG.md § 7: стая бабочек роняет кадры на планшете.
		it("движущихся объектов не больше бюджета", function()
			expect(LiveWorld.movingBudget() <= LiveWorld.MAX_MOVING).to.equal(true)
			expect(LiveWorld.MAX_MOVING <= 40).to.equal(true)
		end)

		it(
			"бабочкам есть где жить, листьям — откуда падать",
			function()
				expect(#LiveWorld.butterflyHomes() > 0).to.equal(true)
				expect(#LiveWorld.leafSources() > 0).to.equal(true)
			end
		)

		it(
			"бабочки у клумб, а листья с деревьев — из той же расстановки, что и декор",
			function()
				local beds, trees = 0, 0
				for _, placement in Decor.placements do
					if placement.id == "flower_bed" then
						beds += 1
					elseif Decor.expect(placement.id).kind == "tree" then
						trees += 1
					end
				end
				-- Бабочки только у ближайших к площади клумб: иначе не уложиться в бюджет кадра.
				expect(#LiveWorld.butterflyHomes()).to.equal(math.min(beds, LiveWorld.MAX_BUTTERFLY_BEDS))
				expect(#LiveWorld.leafSources()).to.equal(trees)
				for _, source in LiveWorld.leafSources() do
					expect(source.height > 2).to.equal(true)
					expect(source.spread > 0).to.equal(true)
				end
			end
		)

		it("бабочки летают низко и недалеко от клумбы", function()
			expect(LiveWorld.BUTTERFLY_HEIGHT[1] < LiveWorld.BUTTERFLY_HEIGHT[2]).to.equal(true)
			expect(LiveWorld.BUTTERFLY_HEIGHT[2] <= 8).to.equal(true)
			expect(LiveWorld.BUTTERFLY_RADIUS <= 10).to.equal(true)
		end)
	end)
end
