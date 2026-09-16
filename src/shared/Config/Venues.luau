--!strict
--[[
	Локации занятий: у каждого задания своё место в мире.

	Правило, ради которого этот конфиг появился: **одно задание — одна локация**.
	Раньше любое занятие разворачивалось прямо там, где стоял ребёнок, посреди
	площади: весы вырастали между порталами, лестница — в кустах у магазина,
	и половину сцены закрывали чужие объекты. Ребёнок не понимал, где он и что
	происходит, а площадь при этом выглядела как склад.

	Теперь пад на площади — это дверь. Занятие начинается не здесь, а там:
	ребёнка переносит на свою поляну, где стоит только его задание и ничего
	больше. Закончил — вернулся к тому же паду.

	Локации живут далеко от площади, каждая на своём месте, и не видят друг друга.
	Туннели забегов стоят по X от +2000 (Config/Tunnel), поляны — по X от −2600:
	разъехаться по разным сторонам дешевле, чем считать, кто кому мешает.
]]

local Venues = {}

Venues.ORIGIN = Vector3.new(-2600, 250, 0)
Venues.SPACING = 260 -- между центрами соседних полян: втрое больше самой поляны
--[[
	Сторона поляны. Было 90, и лестница на восемь ступеней с вершиной уходила
	в задник. 120 вмещает любую сцену с запасом, и по краю остаётся место
	для оформления поляны (World/VenueThemes).
]]
Venues.SIZE = 120
Venues.FLOOR_THICKNESS = 2

--[[
	Где стоит ребёнок и где разворачивается задание.

	Ребёнок появляется у ближнего края лицом к центру, задание — в центре.
	Сцену строит клиент (контроллер испытания), и точку он получает от сервера
	в задании: иначе сцена успевала собраться на площади раньше, чем ребёнка
	туда перенесло.
]]
Venues.ENTRY_OFFSET = 26 -- насколько точка входа отстоит от центра поляны

export type Venue = {
	id: string, -- id испытания (Config/Challenges)
	title: string,
	ground: Color3,
	accent: Color3, -- бордюр, арка и табличка
	-- Чем обсажена поляна: эскизы из World/DecorShapes по кругу.
	decor: { string },
}

--[[
	Пять занятий с площади — пять полян. У каждой свой цвет и своя растительность,
	чтобы они не сливались в одну: ребёнок должен узнавать место, куда попал,
	раньше, чем услышит задание.

	Забеги (туннель, полоса, ворота с числами) сюда не входят: у них свой мир
	длиной в несколько сотен студов, он строится отдельно (Services/TunnelService).
]]
Venues.all = {
	{
		id = "letter_rain",
		title = "🌧 Поляна Буквопада",
		ground = Color3.fromRGB(140, 195, 235),
		accent = Color3.fromRGB(90, 150, 210),
		decor = { "tree_round", "letter_cubes", "lamp", "flower_bed" },
	},
	{
		id = "alphabet_ladder",
		title = "🪜 Гора Алфавита",
		ground = Color3.fromRGB(200, 180, 235),
		accent = Color3.fromRGB(150, 120, 205),
		decor = { "rock_small", "tree_pine", "letter_cubes", "lamp" },
	},
	{
		id = "bubbles",
		title = "🫧 Берег Пузырей",
		ground = Color3.fromRGB(150, 220, 225),
		accent = Color3.fromRGB(95, 185, 195),
		decor = { "rock_small", "letter_cubes", "flower_bed", "bench" },
	},
	{
		id = "mirror",
		title = "🪞 Зеркальный Двор",
		ground = Color3.fromRGB(230, 220, 205),
		accent = Color3.fromRGB(185, 165, 140),
		decor = { "lamp", "letter_cubes", "tree_round", "flower_bed" },
	},
	{
		id = "scales",
		title = "⚖ Двор Весов",
		ground = Color3.fromRGB(215, 200, 165),
		accent = Color3.fromRGB(170, 145, 105),
		decor = { "number_cubes", "bench", "tree_pine", "fountain" },
	},
	{
		id = "berries",
		title = "🍓 Ягодная поляна",
		ground = Color3.fromRGB(165, 210, 130),
		accent = Color3.fromRGB(200, 90, 110),
		decor = { "tree_round", "number_cubes", "bench", "tree_pine" },
	},
} :: { Venue }

local byId: { [string]: Venue } = {}
local orderOf: { [string]: number } = {}
for index, venue in Venues.all do
	assert(byId[venue.id] == nil, `Venues: дубликат локации {venue.id}`)
	byId[venue.id] = venue
	orderOf[venue.id] = index
end

function Venues.get(id: string): Venue?
	return byId[id]
end

function Venues.expect(id: string): Venue
	local venue = byId[id]
	assert(venue, `Venues: неизвестная локация "{id}"`)
	return venue
end

-- Порядковый номер поляны: из него считаются место и сид оформления.
function Venues.order(id: string): number
	local index = orderOf[id]
	assert(index, `Venues: неизвестная локация "{id}"`)
	return index
end

function Venues.count(): number
	return #Venues.all
end

function Venues.ids(): { string }
	local ids: { string } = {}
	for _, venue in Venues.all do
		table.insert(ids, venue.id)
	end
	return ids
end

--[[
	Центр поляны. Считается из порядкового номера, а не задан числом: добавится
	шестое занятие — поляна встанет рядом сама, и никто не впишет ей координаты
	соседа. Расстановку держит тест.
]]
function Venues.center(id: string): Vector3
	local index = orderOf[id]
	assert(index, `Venues: неизвестная локация "{id}"`)
	return Venues.ORIGIN - Vector3.new((index - 1) * Venues.SPACING, 0, 0)
end

-- Куда ставить ребёнка: у ближнего края, лицом к центру поляны.
function Venues.entry(id: string): CFrame
	local center = Venues.center(id)
	local from = center + Vector3.new(0, 3, Venues.ENTRY_OFFSET)
	return CFrame.lookAt(from, Vector3.new(center.X, from.Y, center.Z))
end

--[[
	Где разворачивается сама сцена задания: центр поляны на уровне пола,
	взгляд в ту же сторону, что и у ребёнка от входа.

	Свою высоту и свой разворот каждое испытание добавляет само: весы и зеркало
	смотрят на ребёнка и разворачиваются, лестница и пузыри уходят от него вперёд.
]]
function Venues.stage(id: string): CFrame
	local center = Venues.center(id)
	return CFrame.lookAt(center, center + Vector3.new(0, 0, -1))
end

return Venues
