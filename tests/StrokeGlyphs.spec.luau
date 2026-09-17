--!nocheck
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local StrokeGlyphs = require(ReplicatedStorage.Shared.Logic.StrokeGlyphs)
local Letters = require(ReplicatedStorage.Shared.Config.Letters)

return function()
	describe("StrokeGlyphs", function()
		it("у каждой из 33 букв есть штрихи", function()
			for _, id in Letters.ordered() do
				expect(StrokeGlyphs.has(id)).to.equal(true)
			end
			expect(#StrokeGlyphs.ids()).to.equal(33)
		end)

		-- Табличка — квадрат; штрих, вылезший за него, обрежет соседнюю табличку.
		it(
			"буква не выходит за квадрат ни в каком положении",
			function()
				for _, id in StrokeGlyphs.ids() do
					for _, mirrored in { false, true } do
						for _, rotation in { 0, 90, 180, -90 } do
							for _, stroke in StrokeGlyphs.strokes(id, mirrored, rotation) do
								expect(#stroke >= 2).to.equal(true)
								for _, point in stroke do
									expect(point[1] >= 0 and point[1] <= 1).to.equal(true)
									expect(point[2] >= 0 and point[2] <= 1).to.equal(true)
								end
							end
						end
					end
				end
			end
		)

		it(
			"два отражения и четыре четверти поворота возвращают букву",
			function()
				local plain = StrokeGlyphs.strokes("r")
				local twice = StrokeGlyphs.strokes("r", false, 360)
				expect(StrokeGlyphs.difference(plain, twice)).to.equal(0)
				local rotated = StrokeGlyphs.strokes("r", false, 180)
				expect(StrokeGlyphs.difference(plain, rotated) > 0).to.equal(true)
			end
		)

		it(
			"поворот на 90 — по часовой, как Rotation в интерфейсе",
			function()
				-- Верхний конец стойки Р (0.3, 0.12) уезжает к правому краю.
				local stem = StrokeGlyphs.strokes("r", false, 90)[1]
				local top = stem[2]
				expect(top[1] > 0.8).to.equal(true)
				expect(math.abs(top[2] - 0.3) < 1e-6).to.equal(true)
			end
		)

		it(
			"симметричные буквы совпадают с отражением, И и Е — нет",
			function()
				for _, id in { "a", "d", "zh", "m", "n", "o", "p", "t", "f", "h", "sh" } do
					expect(StrokeGlyphs.mirrorDiffers(id)).to.equal(false)
				end
				-- По расстоянию между линиями И и её отражение неотличимы: вся диагональ
				-- упирается в стойки. Сравнение по закраске это видит.
				for _, id in { "i", "j", "ye", "yo", "ya", "e", "z", "r", "yu" } do
					expect(StrokeGlyphs.mirrorDiffers(id)).to.equal(true)
				end
			end
		)
	end)
end
