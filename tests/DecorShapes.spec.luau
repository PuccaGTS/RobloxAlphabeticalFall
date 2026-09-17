--!nocheck
--[[
	Эскизы декора. Проверяем не красоту — её проверяют глазами, — а то, из-за чего
	эскиз ломает мир: габарит больше обещанного каталогом, деталь, висящая
	в воздухе, и лишние сотни частей на площади.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DecorShapes = require(ReplicatedStorage.ServerWorld.DecorShapes)
local Decor = require(ReplicatedStorage.Shared.Config.Decor)

-- Больше этого на предмет — уже не эскиз, а расход бюджета на дешёвом планшете.
local MAX_PARTS = 12

local function partsOf(model)
	local count = 0
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			count += 1
		end
	end
	return count
end

return function()
	describe("DecorShapes", function()
		it("эскиз есть у каждого предмета каталога", function()
			for _, item in Decor.items do
				if not item.file and not DecorShapes.has(item.id) then
					error(`у предмета «{item.title}» ({item.id}) нет эскиза`)
				end
			end
		end)

		--[[
			Габарит каталога — это то, по чему считается расстановка и запретные зоны.
			Эскиз крупнее обещанного лезет в проход, которого в конфиге не видно.
		]]
		it("эскиз вписывается в габарит каталога", function()
			for _, item in Decor.items do
				if item.file then
					continue
				end
				local model = DecorShapes.build(item)
				expect(model).to.be.ok()

				local size = model:GetExtentsSize()
				for _, axis in { "X", "Y", "Z" } do
					if size[axis] > item.size[axis] + 0.01 then
						error(
							`«{item.title}»: {axis} = {math.floor(size[axis] * 10) / 10}, `
								.. `а каталог обещает {item.size[axis]}`
						)
					end
				end
				model:Destroy()
			end
		end)

		--[[
			Эскиз собирается стоящим на нуле: ставит его на землю DecorService,
			и он рассчитывает именно на это. Уехавший вниз ноль — это дерево,
			наполовину утонувшее в плитке.
		]]
		it("эскиз стоит на нуле, а не висит и не тонет", function()
			for _, item in Decor.items do
				if item.file then
					continue
				end
				local model = DecorShapes.build(item)
				local box, size = model:GetBoundingBox()
				local bottom = box.Position.Y - size.Y / 2

				if math.abs(bottom) > 0.35 then
					error(
						`«{item.title}»: низ на {math.floor(bottom * 100) / 100}, а должен быть у нуля`
					)
				end
				model:Destroy()
			end
		end)

		it("деталей на предмет немного", function()
			for _, item in Decor.items do
				if item.file then
					continue
				end
				local model = DecorShapes.build(item)
				local parts = partsOf(model)

				expect(parts > 0).to.equal(true)
				if parts > MAX_PARTS then
					error(
						`«{item.title}»: {parts} деталей, а можно не больше {MAX_PARTS}`
					)
				end
				model:Destroy()
			end
		end)

		it("все детали закреплены", function()
			for _, item in Decor.items do
				if item.file then
					continue
				end
				local model = DecorShapes.build(item)
				for _, descendant in model:GetDescendants() do
					if descendant:IsA("BasePart") then
						expect(descendant.Anchored).to.equal(true)
					end
				end
				model:Destroy()
			end
		end)

		--[[
			Габарит модели Roblox считает в системе её привязки. Наклонённая привязка
			переворачивает «8 на 16» в «16 на 8» — и расстановка, посчитанная
			по каталогу, разъезжается. Поэтому привязка эскиза строго осевая.
		]]
		it("точка привязки эскиза не повёрнута", function()
			for _, item in Decor.items do
				if item.file then
					continue
				end
				local model = DecorShapes.build(item)
				local pivot = model:GetPivot()

				expect((pivot.Position - Vector3.zero).Magnitude < 0.01).to.equal(true)
				expect((pivot.LookVector - Vector3.new(0, 0, -1)).Magnitude < 0.01).to.equal(true)
				expect((pivot.UpVector - Vector3.new(0, 1, 0)).Magnitude < 0.01).to.equal(true)
				model:Destroy()
			end
		end)

		it("незнакомый предмет эскиза не получает", function()
			expect(DecorShapes.build({ id = "нет_такого", size = Vector3.new(1, 1, 1) })).to.equal(
				nil
			)
		end)
	end)
end
