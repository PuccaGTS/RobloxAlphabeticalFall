--!nocheck
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DetailLod = require(ReplicatedStorage.SourceClientControllers.DetailLodController)

return function()
	describe("DetailLodController", function()
		it(
			"прячет детали далёкого участка и показывает близкого",
			function()
				expect(DetailLod.isFar(DetailLod.HIDE_DISTANCE + 1, false)).to.equal(true)
				expect(DetailLod.isFar(DetailLod.SHOW_DISTANCE - 1, true)).to.equal(false)
			end
		)

		-- Между порогами решение не меняется: у границы детали не мигают при каждом шаге.
		it("между порогами оставляет как было", function()
			local between = (DetailLod.HIDE_DISTANCE + DetailLod.SHOW_DISTANCE) / 2
			expect(DetailLod.isFar(between, true)).to.equal(true)
			expect(DetailLod.isFar(between, false)).to.equal(false)
			expect(DetailLod.SHOW_DISTANCE < DetailLod.HIDE_DISTANCE).to.equal(true)
		end)
	end)
end
