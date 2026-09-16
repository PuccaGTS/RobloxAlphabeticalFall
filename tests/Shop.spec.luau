--!nocheck
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage.Shared

local Shop = require(Shared.Config.Shop)
local Economy = require(Shared.Config.Economy)

return function()
	describe("Config: магазин", function()
		it("id совпадает с ключом таблицы", function()
			for id, item in Shop.all do
				expect(item.id).to.equal(id)
			end
		end)

		it("у предмета ровно один способ получения", function()
			for _, id in Shop.ids() do
				local item = Shop.expect(id)
				local ways = 0
				if item.price then
					ways += 1
				end
				if item.robuxProduct then
					ways += 1
				end
				if item.grantedBy then
					ways += 1
				end
				expect(ways).to.equal(1)
			end
		end)

		-- Названия читает родитель в витрине: два «Цилиндра» он бы не различил.
		it("названия вещей не повторяются", function()
			local seen = {}
			for _, item in Shop.all do
				expect(seen[item.title]).to.equal(nil)
				seen[item.title] = true
			end
		end)

		it("категория предмета известна", function()
			for _, id in Shop.ids() do
				expect(table.find(Shop.CATEGORIES, Shop.expect(id).category)).to.be.ok()
			end
		end)

		it("цена попадает в свой ценовой тир", function()
			for _, id in Shop.ids() do
				local item = Shop.expect(id)
				if item.price then
					local tier = Economy.PRICE_TIERS[item.tier]
					expect(tier).to.be.ok()
					expect(item.price >= tier.min).to.equal(true)
					expect(item.price <= tier.max).to.equal(true)
				end
			end
		end)

		it("витрина отсортирована от дешёвого к дорогому", function()
			local ids = Shop.ids()
			for index = 2, #ids do
				local prev = Shop.expect(ids[index - 1]).price or math.huge
				local current = Shop.expect(ids[index]).price or math.huge
				expect(prev <= current).to.equal(true)
			end
		end)

		it(
			"самый дешёвый предмет по карману после первого испытания",
			function()
				-- принцип из docs/04-ECONOMY.md: первая покупка в первые пять минут
				local cheapest = Shop.expect(Shop.ids()[1]).price
				expect(cheapest <= Economy.rewardForChallenge(2)).to.equal(true)
			end
		)

		it("у каждого предмета есть чем его показать", function()
			for _, id in Shop.ids() do
				local item = Shop.expect(id)
				expect(#item.icon > 0).to.equal(true)
				expect(item.visual ~= nil or item.trail ~= nil or item.skin ~= nil or item.accessory ~= nil).to.equal(
					true
				)
			end
		end)

		it(
			"носимый предмет собран больше чем из одной детали",
			function()
				-- из одного куба не получается ни кепка, ни корона — получается куб на голове
				for _, id in Shop.ids() do
					local item = Shop.expect(id)
					if item.visual then
						expect(#item.visual >= 2).to.equal(true)
						for _, piece in item.visual do
							expect(typeof(piece.size)).to.equal("Vector3")
							expect(typeof(piece.offset)).to.equal("CFrame")
						end
					end
				end
			end
		)

		it("в срезе MVP есть предметы всех категорий", function()
			for _, category in Shop.CATEGORIES do
				local found = false
				for _, id in Shop.ids() do
					if Shop.expect(id).category == category then
						found = true
						break
					end
				end
				expect(found).to.equal(true)
			end
		end)

		-- docs/17-CONTENT-PLAN.md § 6: в первой играбельной версии двадцать вещей.
		it(
			"витрина первой версии — не меньше двадцати вещей",
			function()
				expect(Shop.count() >= 20).to.equal(true)
			end
		)

		-- Сразу после первого испытания (около 25 ⭐) выбор должен быть, а не одна кепка.
		it(
			"по карману после первого испытания — больше одной вещи",
			function()
				local affordable = 0
				for _, id in Shop.ids() do
					local price = Shop.expect(id).price
					if price and price <= 25 then
						affordable += 1
					end
				end
				expect(affordable >= 3).to.equal(true)
			end
		)
	end)

	--[[
		Аксессуары каталога надеваются только на голову, спину и лицо: у следа
		и скина буквят нет слота в HumanoidDescription. Номер — целое положительное.
	]]
	describe("Config: аксессуары каталога", function()
		it("аксессуар только у шапок, рюкзаков и очков", function()
			local worn = 0
			for _, item in Shop.all do
				if item.accessory then
					worn += 1
					expect(item.category == "hat" or item.category == "back" or item.category == "face").to.equal(
						true
					)
					expect(item.accessory > 0 and item.accessory % 1 == 0).to.equal(true)
				end
			end
			expect(worn >= 20).to.equal(true)
		end)

		it("один аксессуар — одна вещь магазина", function()
			local seen = {}
			for id, item in Shop.all do
				if item.accessory then
					expect(seen[item.accessory]).to.equal(nil)
					seen[item.accessory] = id
				end
			end
		end)

		it(
			"кепка теперь настоящая, но запасной рецепт остался",
			function()
				local cap = Shop.expect("hat_cap")
				expect(cap.accessory).to.be.ok()
				expect(cap.visual).to.be.ok()
			end
		)

		it("в магазине не меньше шестидесяти вещей", function()
			expect(Shop.count() >= 60).to.equal(true)
		end)
	end)

	describe("Config: скины буквят", function()
		it(
			"скин — это наряд, а не буквёнок: у каждого есть цвет и материал",
			function()
				local skins = 0
				for _, item in Shop.all do
					if item.category == "petskin" then
						skins += 1
						expect(item.skin).to.be.ok()
						expect(typeof(item.skin.color)).to.equal("Color3")
						expect(typeof(item.skin.material)).to.equal("EnumItem")
						expect(item.visual).to.equal(nil)
						expect(item.trail).to.equal(nil)
					else
						expect(item.skin).to.equal(nil)
					end
				end
				expect(skins >= 3).to.equal(true)
			end
		)

		-- docs/04-ECONOMY.md § 3: скины буквят — редкий тир T3.
		it("продаваемые скины стоят в тире T3", function()
			for _, item in Shop.all do
				if item.category == "petskin" and item.price then
					expect(item.tier).to.equal(3)
				end
			end
		end)
	end)

	describe("Config: вещи за серию буквы дня", function()
		it("за 7 и 14 дней серии есть по вещи — шапка и след", function()
			expect(Shop.expect("hat_sun").category).to.equal("hat")
			expect(Shop.streakDays(Shop.expect("hat_sun"))).to.equal(7)
			expect(Shop.expect("trail_sun").category).to.equal("trail")
			expect(Shop.streakDays(Shop.expect("trail_sun"))).to.equal(14)
		end)

		it(
			"каждая выдача за серию приходится на день из таблицы наград",
			function()
				for _, id in Shop.ids() do
					local days = Shop.streakDays(Shop.expect(id))
					if days then
						expect(Economy.DAILY_STREAK_REWARDS[days]).to.be.ok()
					end
				end
			end
		)

		it(
			"выдаётся по рекорду: до порога ничего, после — всё положенное по порядку",
			function()
				expect(#Shop.streakItems(0)).to.equal(0)
				expect(#Shop.streakItems(6)).to.equal(0)
				local seven = Shop.streakItems(7)
				expect(#seven).to.equal(1)
				expect(seven[1]).to.equal("hat_sun")
				local month = Shop.streakItems(30)
				expect(month[1]).to.equal("hat_sun")
				expect(month[2]).to.equal("trail_sun")
			end
		)

		it("за 30 дней серии — радужный скин буквят", function()
			local month = Shop.streakItems(30)
			expect(table.find(month, "skin_rainbow")).to.be.ok()
			expect(Shop.expect("skin_rainbow").category).to.equal("petskin")
		end)

		it("чужой grantedBy не принимается за серию", function()
			expect(Shop.streakDays({ grantedBy = "letter_mastered:m" })).to.equal(nil)
			expect(Shop.streakDays({ grantedBy = "daily_streak:abc" })).to.equal(nil)
			expect(Shop.streakDays({ price = 10 })).to.equal(nil)
		end)
	end)

	--[[
		Переключатель родителя «скрыть покупки за Robux» (docs/13-PARENT-MODE.md § 3).
		Прячется показ, а не владение: снять с ребёнка оплаченное настройка не вправе.
	]]
	describe("Shop.visibleIds", function()
		it("без настройки видно всё", function()
			expect(#Shop.visibleIds(false)).to.equal(Shop.count())
			expect(#Shop.visibleIds(nil)).to.equal(Shop.count())
		end)

		it("со скрытием не остаётся ни одной покупки за Robux", function()
			for _, id in Shop.visibleIds(true) do
				expect(Shop.expect(id).robuxProduct).to.equal(nil)
			end
		end)

		it("звёздочки скрытием не затрагиваются", function()
			local starItems = 0
			for _, id in Shop.visibleIds(true) do
				if Shop.expect(id).price then
					starItems += 1
				end
			end

			local all = 0
			for _, id in Shop.ids() do
				if Shop.expect(id).price then
					all += 1
				end
			end
			expect(starItems).to.equal(all)
		end)

		it(
			"шлейф есть только у редких вещей и собран из встроенных частиц",
			function()
				local withEffect = 0
				for _, id in Shop.ids() do
					local item = Shop.expect(id)
					local effect = item.effect
					if effect then
						withEffect += 1
						expect(item.tier >= 2).to.equal(true)
						expect(Shop.PARTICLE_TEXTURES[effect.particles] ~= nil).to.equal(true)
						-- Планшет: частиц немного, иначе на площади с десятком детей просядет кадр.
						expect(effect.rate <= 20).to.equal(true)
					end
				end
				expect(withEffect >= 3).to.equal(true)
			end
		)
	end)
end
