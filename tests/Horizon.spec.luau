--!nocheck
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared

local Horizon = require(Shared.Config.Horizon)
local Decor = require(Shared.Config.Decor)
local Base = require(Shared.Config.Base)

return function()
	describe("Config: горизонт за изгородью", function()
		it(
			"ни один холм не заходит за изгородь — сквозь холм не пройти",
			function()
				for _, hill in Horizon.hills() do
					local reach = Horizon.innerReach(hill.position, hill.size, hill.yaw)
					expect(reach >= Base.GROUND_SIZE / 2 + Horizon.CLEARANCE).to.equal(true)
				end
			end
		)

		it("деревья растут на холмах, а не в парке", function()
			for _, hill in Horizon.hills() do
				for _, tree in hill.trees do
					expect(math.max(math.abs(tree.X), math.abs(tree.Z)) > Base.GROUND_SIZE / 2).to.equal(true)
				end
			end
		end)

		it("горы стоят дальше всех холмов", function()
			local farthest = 0
			for _, hill in Horizon.hills() do
				farthest = math.max(farthest, Vector2.new(hill.position.X, hill.position.Z).Magnitude)
			end
			for _, mountain in Horizon.mountains() do
				expect(Vector2.new(mountain.position.X, mountain.position.Z).Magnitude > farthest).to.equal(
					true
				)
			end
		end)

		it("пейзаж один и тот же при каждом запуске", function()
			local a, b = Horizon.hills(), Horizon.hills()
			expect(#a).to.equal(#b)
			for index, hill in a do
				expect(hill.position).to.equal(b[index].position)
			end
		end)

		it(
			"деревья и горы — предметы каталога декора с моделью-файлом",
			function()
				for _, id in Horizon.TREES do
					expect(Decor.get(id) ~= nil).to.equal(true)
				end
				expect(Decor.get(Horizon.MOUNTAIN) ~= nil).to.equal(true)
			end
		)

		it("земля горизонта накрывает горы", function()
			for _, mountain in Horizon.mountains() do
				local reach = math.max(math.abs(mountain.position.X), math.abs(mountain.position.Z))
				expect(reach + 200 < Horizon.FAR_GROUND_SIZE / 2).to.equal(true)
			end
		end)
	end)
end
