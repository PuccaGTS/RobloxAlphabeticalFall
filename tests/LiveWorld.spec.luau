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

		it(
			"зайчики живут в парке: не на дорожках, не в игровых местах и не у домов",
			function()
				for index = 1, #LiveWorld.BUNNY_HOMES do
					local home = LiveWorld.bunnyHome(index)
					local clear, why = Decor.isClear(home.X, home.Z, LiveWorld.BUNNY_RADIUS)
					if not clear then
						error(`зайчик {index} мешает: {why}`)
					end
					expect(Vector2.new(home.X, home.Z).Magnitude + LiveWorld.BUNNY_RADIUS <= Decor.MAX_RADIUS).to.equal(
						true
					)
				end
			end
		)

		it("утки ходят по площади и не заходят в порталы", function()
			local loop = LiveWorld.DUCK_LOOP
			for step = 0, 15 do
				local angle = step / 16 * math.pi * 2
				local point = loop.center + Vector2.new(math.cos(angle), math.sin(angle)) * loop.radius
				for _, zone in Decor.zones do
					if
						string.find(zone.why, "портал", 1, true)
						or string.find(zone.why, "появления", 1, true)
					then
						expect((point - zone.center).Magnitude >= zone.radius).to.equal(true)
					end
				end
			end
		end)

		it("бабочки летают низко и недалеко от клумбы", function()
			expect(LiveWorld.BUTTERFLY_HEIGHT[1] < LiveWorld.BUTTERFLY_HEIGHT[2]).to.equal(true)
			expect(LiveWorld.BUTTERFLY_HEIGHT[2] <= 8).to.equal(true)
			expect(LiveWorld.BUTTERFLY_RADIUS <= 10).to.equal(true)
		end)

		it(
			"под каждым горбатым мостиком пруд, и карпы плавают в его воде",
			function()
				expect(#LiveWorld.ponds() > 0).to.equal(true)
				local path = Decor.KOI_PATH
				-- Точки пути карпа обязаны лежать в одном из кругов воды, с запасом на тело рыбы.
				for step = 0, 35 do
					local angle = step / 36 * math.pi * 2
					local x, z = math.cos(angle) * path.radiusX, math.sin(angle) * path.radiusZ
					local wet = false
					for _, blob in Decor.POND_BLOBS do
						if Vector2.new(x - blob.x, z - blob.z).Magnitude < blob.radius - 0.8 then
							wet = true
						end
					end
					expect(wet).to.equal(true)
				end
				-- Вода кончается у опор мостика: пролёт 19 студов.
				for _, blob in Decor.POND_BLOBS do
					expect(math.abs(blob.x) + blob.radius <= Decor.expect(Decor.POND_UNDER).size.X / 2).to.equal(
						true
					)
				end
			end
		)
	end)
end
