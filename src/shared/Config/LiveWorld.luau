--!strict
--[[
	Живой мир площади: бабочки у клумб, листья с деревьев, утки, зайчики,
	карпы в пруду и радуга.
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
LiveWorld.MAX_BUTTERFLY_BEDS = 10 -- было 14: часть бюджета отдана уткам и зайчикам
LiveWorld.BUTTERFLY_RADIUS = 7 -- как далеко от клумбы улетает бабочка
LiveWorld.BUTTERFLY_HEIGHT = { 2, 5 } -- над землёй, в студах

LiveWorld.LEAVES_AT_ONCE = 8 -- было 12: четыре места отданы карпам и брызгам в пруду
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

--[[
	Зверьки в парке. Бабочки и листья — фон, а на зверька хочется посмотреть:
	утиная семья ходит гуськом вокруг фонтана, а зайчики пасутся на полянках
	и отпрыгивают, когда к ним подбегают. Трогать их можно, поймать — нет:
	это тоже фон, только живой.
]]
LiveWorld.DUCK_COUNT = 4 -- мама и три утёнка
LiveWorld.DUCK_LOOP = { center = Vector2.new(0, -34), radius = 11 } -- вокруг фонтана
LiveWorld.DUCK_LAP_SECONDS = 40
LiveWorld.DUCK_GAP = 0.28 -- на сколько радиан утёнок отстаёт от впереди идущего

--[[
	Карпы в пруду под горбатым мостиком (Config/Decor.POND_BLOBS). Плавают
	по кругу у самой поверхности, ныряют под мостик, и время от времени один
	выпрыгивает с брызгами — на это ребёнок и бежит посмотреть.
]]
LiveWorld.KOI_PER_POND = 3
LiveWorld.KOI_LAP_SECONDS = 18
LiveWorld.KOI_JUMP_EVERY = { 6, 12 } -- секунд между прыжками в одном пруду
LiveWorld.KOI_JUMP_SECONDS = 1.1
LiveWorld.KOI_JUMP_HEIGHT = 2.6
-- Раскраска карпов: тело и пятно.
LiveWorld.KOI_COLORS = {
	{ Color3.fromRGB(245, 120, 45), Color3.fromRGB(255, 250, 240) },
	{ Color3.fromRGB(255, 250, 240), Color3.fromRGB(230, 70, 50) },
	{ Color3.fromRGB(250, 195, 60), Color3.fromRGB(245, 120, 45) },
}

--[[
	Радуга над парком. Не движется — только проявляется и тает, поэтому
	в бюджет движущихся не входит: это семь лучей (Beam), а не детали.
	Появляется сама изредка и сразу после испытания на три звезды — ребёнок
	возвращается на площадь, а над ней радуга.
]]
LiveWorld.RAINBOW_CENTER = Vector3.new(0, 0, -190)
LiveWorld.RAINBOW_SPAN = 165 -- от центра до ноги внешней полосы
LiveWorld.RAINBOW_HEIGHT = 125 -- высота внешней дуги
LiveWorld.RAINBOW_BAND = 6.5 -- ширина полосы
LiveWorld.RAINBOW_SECONDS = 45
LiveWorld.RAINBOW_EVERY = { 180, 300 }
LiveWorld.RAINBOW_COLORS = {
	Color3.fromRGB(235, 80, 80),
	Color3.fromRGB(245, 150, 60),
	Color3.fromRGB(250, 220, 80),
	Color3.fromRGB(110, 200, 110),
	Color3.fromRGB(90, 170, 240),
	Color3.fromRGB(90, 110, 220),
	Color3.fromRGB(160, 100, 210),
}

export type Pond = { cframe: CFrame }

-- Пруды: по одному под каждым горбатым мостиком, в его развороте, на уровне земли.
function LiveWorld.ponds(): { Pond }
	local ponds: { Pond } = {}
	for _, placement in Decor.placements do
		if placement.id == Decor.POND_UNDER then
			table.insert(ponds, {
				cframe = CFrame.new(placement.x, Decor.groundY(placement.x, placement.z), placement.z)
					* CFrame.Angles(0, math.rad(placement.rotation), 0),
			})
		end
	end
	return ponds
end

-- Полянки зайчиков: угол от центра площади в градусах и расстояние.
LiveWorld.BUNNY_HOMES = {
	{ angle = 22, distance = 122 },
	{ angle = 97, distance = 176 },
	{ angle = 243, distance = 168 },
	{ angle = 318, distance = 112 },
}
LiveWorld.BUNNY_RADIUS = 9 -- как далеко от своей полянки гуляет
LiveWorld.BUNNY_SCARE_DISTANCE = 10 -- ближе этого ребёнок — зайчик отпрыгивает

function LiveWorld.bunnyHome(index: number): Vector3
	local home = LiveWorld.BUNNY_HOMES[index]
	local angle = math.rad(home.angle)
	local x, z = math.cos(angle) * home.distance, math.sin(angle) * home.distance
	return Vector3.new(x, Decor.groundY(x, z), z)
end

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
	return LiveWorld.butterflyCount()
		+ LiveWorld.LEAVES_AT_ONCE
		+ LiveWorld.DUCK_COUNT
		+ #LiveWorld.BUNNY_HOMES
		-- В каждом пруду карпы и одно кольцо брызг от прыжка.
		+ #LiveWorld.ponds() * (LiveWorld.KOI_PER_POND + 1)
end

return LiveWorld
