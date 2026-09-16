--!strict
--[[
	Живой мир площади: бабочки у клумб и листья, падающие с деревьев.
	См. docs/18-CONTENT-BACKLOG.md § 7.

	Чистая атмосфера: ничего из этого не учит, не награждает и не мешает пройти.
	Рисует клиент (LiveWorldController), и у каждого ребёнка свои бабочки —
	серверу незачем гонять их по сети.

	Главное здесь — бюджет. Док прямо предупреждает: стая бабочек красиво смотрится
	на ПК и роняет кадры на дешёвом планшете, а ребёнок с лагами просто уходит.
	Поэтому число движущихся объектов задано здесь и держится тестом, а не глазами.

	Где летать и откуда падать, берём из расстановки декора (Config/Decor):
	бабочки — у клумб, листья — с деревьев. Передвинули клумбу — бабочки
	переехали вместе с ней, двух списков координат нет.
]]

local Decor = require(script.Parent.Decor)

local LiveWorld = {}

-- Потолок из docs/18 § 7: не больше 40 движущихся объектов в кадре на всё живое.
LiveWorld.MAX_MOVING = 40

LiveWorld.BUTTERFLIES_PER_BED = 2
--[[
	Бабочки живут не у всех клумб, а у ближайших к площади. Клумб в парке стало
	много, и бабочки у каждой съели бы весь бюджет кадра: здесь ребёнок бывает
	чаще всего, здесь им и летать.
]]
LiveWorld.MAX_BUTTERFLY_BEDS = 14
LiveWorld.BUTTERFLY_RADIUS = 7 -- как далеко от клумбы улетает бабочка
LiveWorld.BUTTERFLY_HEIGHT = { 2, 5 } -- над землёй, в студах

LiveWorld.LEAVES_AT_ONCE = 12
LiveWorld.LEAF_INTERVAL = 0.9 -- секунд между листьями
LiveWorld.LEAF_FALL_SECONDS = { 4, 6.5 }

-- Дальше этого от камеры ничего не запускаем: всё равно не видно, а кадр тратится.
LiveWorld.VISIBLE_DISTANCE = 140

LiveWorld.BUTTERFLY_COLORS = {
	Color3.fromRGB(255, 190, 90),
	Color3.fromRGB(150, 200, 255),
	Color3.fromRGB(240, 150, 210),
	Color3.fromRGB(255, 240, 140),
}

LiveWorld.LEAF_COLORS = {
	Color3.fromRGB(235, 175, 60),
	Color3.fromRGB(215, 110, 50),
	Color3.fromRGB(190, 160, 70),
}

-- Клумбы, у которых кружат бабочки: точки на земле.
function LiveWorld.butterflyHomes(): { Vector3 }
	local homes: { Vector3 } = {}
	for _, placement in Decor.placements do
		if placement.id == "flower_bed" then
			table.insert(
				homes,
				Vector3.new(placement.x, Decor.groundY(placement.x, placement.z), placement.z)
			)
		end
	end
	table.sort(homes, function(a: Vector3, b: Vector3): boolean
		return a.Magnitude < b.Magnitude
	end)
	while #homes > LiveWorld.MAX_BUTTERFLY_BEDS do
		table.remove(homes)
	end
	return homes
end

export type LeafSource = { position: Vector3, height: number, spread: number }

-- Деревья, с которых падают листья: основание, высота кроны и её радиус.
function LiveWorld.leafSources(): { LeafSource }
	local sources: { LeafSource } = {}
	for _, placement in Decor.placements do
		local item = Decor.get(placement.id)
		if item and item.kind == "tree" then
			local scale = placement.scale or 1
			table.insert(sources, {
				position = Vector3.new(placement.x, Decor.groundY(placement.x, placement.z), placement.z),
				height = item.size.Y * scale * 0.8,
				spread = math.max(item.size.X, item.size.Z) * scale / 2,
			})
		end
	end
	return sources
end

function LiveWorld.butterflyCount(): number
	return #LiveWorld.butterflyHomes() * LiveWorld.BUTTERFLIES_PER_BED
end

-- Сколько всего живого может двигаться одновременно.
function LiveWorld.movingBudget(): number
	return LiveWorld.butterflyCount() + LiveWorld.LEAVES_AT_ONCE
end

return LiveWorld
