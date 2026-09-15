--!nocheck
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared

local Chests = require(Shared.Config.Chests)
local Shop = require(Shared.Config.Shop)
local Decor = require(Shared.Config.Decor)
local Base = require(Shared.Config.Base)

return function()
	describe("Config: сундуки в парке", function()
		it(
			"в каждом сундуке своя вещь, и она ведёт обратно в этот сундук",
			function()
				local seen = {}
				for _, chest in Chests.all do
					local item = Shop.get(chest.itemId)
					expect(item).to.be.ok()
					expect(Chests.chestIdOf(item.grantedBy)).to.equal(chest.id)
					expect(seen[chest.itemId]).to.equal(nil)
					seen[chest.itemId] = true
				end
			end
		)

		-- docs/04-ECONOMY.md § 1: случайных наград нет. У сундука ровно одна вещь, и она известна.
		it(
			"вещь из сундука не продаётся и не выдаётся иначе",
			function()
				for _, item in Shop.all do
					if Chests.chestIdOf(item.grantedBy) then
						expect(item.price).to.equal(nil)
						expect(item.robuxProduct).to.equal(nil)
					end
				end
			end
		)

		it(
			"у каждой вещи с пометкой «из сундука» сундук существует",
			function()
				for _, item in Shop.all do
					local grantedBy = item.grantedBy
					if grantedBy and string.sub(grantedBy, 1, #Chests.PREFIX) == Chests.PREFIX then
						expect(Chests.chestIdOf(grantedBy)).to.be.ok()
					end
				end
			end
		)

		it(
			"сундуки в парке: за площадью и её деревьями, но до участков",
			function()
				for _, chest in Chests.all do
					local position = Chests.position(chest)
					local distance = Vector2.new(position.X, position.Z).Magnitude
					expect(distance > Base.PLAZA_RADIUS + 15).to.equal(true)
					expect(distance + 3 < Chests.MAX_DISTANCE).to.equal(true)
				end
			end
		)

		it(
			"не на дорожках, падах и декоре — и не друг на друге",
			function()
				for index, chest in Chests.all do
					local position = Chests.position(chest)
					local clear, why = Decor.isClear(position.X, position.Z, 3)
					if not clear then
						warn(`[Tests] сундук {chest.id} стоит в зоне «{why}»`)
					end
					expect(clear).to.equal(true)

					-- Дорожки к домам идут лучами до самых участков, а зоны Decor держат только их начало.
					for path = 0, 3 do
						local angle = math.rad(path * 90)
						local along = Vector2.new(math.cos(angle), math.sin(angle))
						local point = Vector2.new(position.X, position.Z)
						local offset = point - along * point:Dot(along)
						if point:Dot(along) > 0 then
							expect(offset.Magnitude > 12).to.equal(true)
						end
					end

					for _, placed in Decor.placements do
						expect(
							(Vector2.new(position.X, position.Z) - Vector2.new(placed.x, placed.z)).Magnitude
								> 8
						).to.equal(true)
					end
					for other = index + 1, #Chests.all do
						local there = Chests.position(Chests.all[other])
						expect((position - there).Magnitude > 30).to.equal(true)
					end
				end
			end
		)

		it(
			"открыт ли сундук — по инвентарю, мусор не открывает",
			function()
				local chest = Chests.all[1]
				expect(Chests.isOpened(chest, { chest.itemId })).to.equal(true)
				expect(Chests.isOpened(chest, {})).to.equal(false)
				expect(Chests.isOpened(chest, nil)).to.equal(false)
				expect(Chests.chestIdOf("chest:нет_такого")).to.equal(nil)
				expect(Chests.chestIdOf("daily_streak:7")).to.equal(nil)
			end
		)
	end)
end
