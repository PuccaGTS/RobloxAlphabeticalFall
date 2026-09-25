--!strict
--[[
	Игровые места в парке: то, с чем можно что-то сделать просто так.

	После первой прогулки по миру парк назвали сухим: дерево, фонарь, кубики —
	и снова дерево, фонарь, кубики. Смотреть на это можно, играть — нечем.
	Игровые места ломают этот ритм: в каждой части парка своё занятие руками
	и ногами, и ни одно из них не похоже на соседнее.

	Правила те же, что у декора (Config/Decor), и одно своё:

	  · ничего не даёт. Ни звёзд, ни прогресса: прыгать на батуте весело
	    само по себе, а «батут за звёзды» превратился бы в фарм;
	  · не стоит на дорожках, сундуках и участках — тест проверяет;
	  · вся игра — на клиенте (Controllers/PlaygroundController): сервер ставит
	    детали и метки, а подпрыгивает, звенит и лопается у каждого ребёнка своё.
	    Проверять тут нечего, а сеть не тратится.

	Декор обходит игровые места сам: их круги добавлены в запретные зоны Decor.
]]

local Playground = {}

export type Spot = {
	id: string,
	title: string, -- табличка над местом: ребёнок не читает, но родитель — да
	angle: number, -- направление от центра площади, в градусах
	distance: number,
	radius: number, -- сколько места занимает вместе с проходом вокруг
}

Playground.spots = {
	{ id = "trampolines", title = "🤸 Батуты", angle = 70, distance = 150, radius = 16 },
	{
		id = "xylophone",
		title = "🎵 Музыкальная дорожка",
		angle = 118,
		distance = 80,
		radius = 14,
	},
	{ id = "hopscotch", title = "🔢 Классики", angle = 168, distance = 128, radius = 12 },
	{ id = "sandbox", title = "⚽ Песочница", angle = 207, distance = 135, radius = 18 },
	{ id = "balloons", title = "🎈 Шарики", angle = 292, distance = 82, radius = 10 },
	{ id = "maze", title = "🌿 Лабиринт", angle = 338, distance = 160, radius = 18 },
	--[[
		Паркур-гора просто так: радужные платформы спиралью до смотровой
		площадки, батут на середину, колокольчик наверху и скат вниз. Видна
		с точки появления между порталами — первое, куда хочется побежать.
	]]
	{ id = "obby", title = "🧗 Паркур-гора", angle = 228, distance = 130, radius = 28 },
	--[[
		Колесо обозрения (Config/Rides): видно с точки появления поверх порталов.
		Кататься можно — встал на посадочный круг, и кабинка поднимает к облакам.
	]]
	{
		id = "ferris",
		title = "🎡 Колесо обозрения",
		angle = 252,
		distance = 205,
		radius = 24,
	},
	--[[
		Фото-зона: большая рамка «Я учу азбуку!» с радугой и буквами. Встал на метку —
		вспышка, щелчок затвора, конфетти, и камера на пару секунд смотрит на тебя,
		как фотограф: самое время нажать снимок экрана и показать маме.
	]]
	{ id = "photo", title = "📸 Фото", angle = 55, distance = 150, radius = 13 },
	-- Катания (Config/Rides): карусель с лошадками, горка-спираль и воздушный шар.
	{ id = "carousel", title = "🎠 Карусель", angle = 300, distance = 160, radius = 16 },
	{ id = "slide", title = "🌀 Горка", angle = 192, distance = 196, radius = 17 },
	{ id = "balloon", title = "🎈 Воздушный шар", angle = 120, distance = 190, radius = 14 },
	--[[
		Тайный сад: круг высоких кустов, а вход — с дальней от площади стороны,
		занавес из листвы, сквозь который проходишь. Внутри светящиеся грибы,
		светлячки, гирлянда и сундук (Config/Chests, chest_secret).
	]]
	{ id = "secret", title = "🌿 Тайный сад", angle = 276, distance = 216, radius = 16 },
	--[[
		Зимняя полянка посреди лета: снежный круг, каток, на котором по-настоящему
		скользишь, снеговик, нарядная ёлка с огоньками и подарками, снег идёт
		только над полянкой. Рядом тихо играет «Jingle Bells» (APM, без загрузки).
	]]
	{ id = "winter", title = "⛄ Зимняя полянка", angle = 99, distance = 222, radius = 22 },
	--[[
		Брызгалки: мягкий круг, из пола бьют струи — то бегут по кругу, то
		хлопают разом, — в середине гейзер, на входе две арки-занавеса, большая
		красная кнопка «всё сразу» и ведро на башне, которое время от времени
		опрокидывается на того, кто под ним. Кого окатило — с того капает.
	]]
	{ id = "splash", title = "💦 Брызгалки", angle = 172, distance = 226, radius = 16 },
	-- Озеро с лодочками-лебедями (Config/Rides.SWANS): видно с дорожки к домам.
	{ id = "lake", title = "🦢 Лебеди", angle = 10, distance = 218, radius = 26 },
	--[[
		Подсолнуховое поле у озера: подсолнухи выше ребёнка поворачивают головы
		вслед за ним, как за солнцем, а когда рядом никого — снова к солнцу.
		Посреди поля пугало в соломенной шляпе.
	]]
	{ id = "sunflowers", title = "🌻 Подсолнухи", angle = 354, distance = 232, radius = 14 },
	--[[
		Прокат (Config/Rental): ларёк, самокат, велосипед и лошадка-единорог.
		Встал на круг перед вещью — едешь на ней по всему парку.
	]]
	{ id = "rental", title = "🛴 Прокат", angle = 76, distance = 108, radius = 13 },
	--[[
		Бобовый стебель, как в сказке: до облаков по листьям спиралью, на середине
		гнездо-сохранка, наверху облачный остров с замком великана, золотой гусыней
		и пятым сундуком (Config/Chests, chest_sky). Остров видно с площади.
		Место на земле — только корень стебля; остров висит над ним.
	]]
	--[[
		Корабль-качели (Config/Rides.SHIP): пиратский кораблик на двух опорах
		над синим «морем» качается почти до горизонтали. Видно с площади.
	]]
	{ id = "ship", title = "🏴‍☠️ Корабль", angle = 30, distance = 176, radius = 18 },
	--[[
		Азбука-дорожка: 33 плитки от А до Я змейкой. Наступил — плитка называет
		свою букву; идёшь по порядку — плитки загораются за тобой, дошёл до Я
		по порядку — вся дорожка вспыхивает волной и звучат фанфары. Это та же
		песенка-алфавит, только ногами. Звёзд не даёт, как всё в парке.
	]]
	{ id = "abcpath", title = "🔤 Азбука-дорожка", angle = 342, distance = 100, radius = 19 },
	--[[
		Домик на дереве (Config/Rides.TREEHOUSE): верёвочная лестница, подвесной
		мостик между двумя деревьями и тарзанка вниз, в песочную яму.
	]]
	{
		id = "treehouse",
		title = "🌳 Домик на дереве",
		angle = 52,
		distance = 222,
		radius = 24,
	},
	--[[
		Грот с кристаллами: каменный холм, вход — сквозь завесу водопада.
		Внутри полумрак, по стенам светятся кристаллы, и каждый звенит своей
		нотой, если его тронуть. У дальней стены шестой сундук (Config/Chests,
		chest_grotto).
	]]
	{ id = "grotto", title = "💎 Грот", angle = 320, distance = 226, radius = 18 },
	--[[
		Рыбалка у пруда (docs/17-CONTENT-PLAN.md § 7.4): круглый пруд в камышах,
		мостки с удочкой. Встал на край мостков — голос называет букву, по пруду
		плавают рыбки с буквами на спинках; тап по нужной — клюёт, удочка
		выдёргивает её в ведро. Спокойный темп, никаких падений.
	]]
	{ id = "pond", title = "🎣 Рыбалка", angle = 37, distance = 130, radius = 17 },
	{
		id = "beanstalk",
		title = "🌱 Бобовый стебель",
		angle = 145,
		distance = 210,
		radius = 12,
	},
}

Playground.WINTER_RADIUS = 20 -- снежный круг
Playground.ICE_RADIUS = 10 -- каток посередине
--[[
	Коньки: на льду скорость не слушается сразу, а догоняет желаемую — так
	и катаются. GRIP — за сколько долей секунды она дотягивается до нужной
	(меньше — дольше скользишь), SPEED — сколько разгоняешься, если бежать.
]]
Playground.SKATE_GRIP = 0.9
Playground.SKATE_SPEED = 24

Playground.SPLASH_RADIUS = 13 -- мягкий круг брызгалок
Playground.SPLASH_JETS = 8 -- струй кольцом, плюс гейзер в середине
Playground.SPLASH_RING = 7 -- радиус кольца струй
Playground.SPLASH_JET_HEIGHT = 7 -- выше этого струя кольца не бьёт
Playground.SPLASH_GEYSER_HEIGHT = 14
Playground.SPLASH_CYCLE = 16 -- хореография струй повторяется раз в столько секунд
Playground.SPLASH_GEYSER_EVERY = 7 -- гейзер вздыхает раз в столько секунд
Playground.SPLASH_BURST = 3 -- сколько бьёт всё сразу после кнопки
Playground.SPLASH_BUCKET_EVERY = 15 -- ведро опрокидывается раз в столько секунд
Playground.SPLASH_BUCKET_TIP = 1.6 -- сколько оно висит опрокинутым
Playground.SPLASH_WET = 3 -- сколько секунд капает с окаченного

--[[
	Высота струи index (1..SPLASH_JETS — кольцо, 0 — гейзер) в секунду now
	по серверным часам, доля от 0 до 1. У всех детей одна и та же картина.
	  0–4    одна струя бежит по кругу;
	  4–8    все разом, раз в секунду;
	  8–12   чётные и нечётные по очереди;
	  12–16  все вполсилы — можно пробежать насквозь.
]]
function Playground.splashJet(index: number, now: number): number
	if index == 0 then
		return if now % Playground.SPLASH_GEYSER_EVERY < 1.3 then 1 else 0.15
	end
	local t = now % Playground.SPLASH_CYCLE
	if t < 4 then
		return if math.floor(t * 2) % Playground.SPLASH_JETS == index - 1 then 1 else 0
	elseif t < 8 then
		return if math.floor(t) % 2 == 0 then 1 else 0
	elseif t < 12 then
		return if math.floor(t / 0.75) % 2 == index % 2 then 0.9 else 0
	end
	return 0.55
end

-- Ведро: 0 — стоит, 1 — опрокинуто. Наклон и обратно — по полсекунды.
function Playground.splashBucket(now: number): number
	local t = now % Playground.SPLASH_BUCKET_EVERY
	local tip = Playground.SPLASH_BUCKET_TIP
	if t < 0.5 then
		return t / 0.5
	elseif t < tip then
		return 1
	elseif t < tip + 0.5 then
		return 1 - (t - tip) / 0.5
	end
	return 0
end

Playground.SUNFLOWER_ROWS = 4
Playground.SUNFLOWER_PER_ROW = 5
Playground.SUNFLOWER_WATCH = 28 -- ближе этого ребёнок — подсолнухи смотрят на него
Playground.SUNFLOWER_TURN = 2.2 -- как быстро поворачивают голову, рад/с

--[[
	Рыбалка. Вода — на земле (яму в земле не выкопать), рыбки плавают у самой
	поверхности. Мостки ведут от берега, обращённого к площади, к середине.
]]
Playground.POND = {
	radius = 10.5, -- вода
	shore = 3, -- песок вокруг воды
	pier = 8, -- на сколько мостки заходят в воду
	fish = 5, -- сколько рыбок плавает
	goal = 3, -- столько поймать подряд — праздник и задание дня про пруд
	bite = 1.1, -- сколько секунд рыбка летит от воды в ведро
}

Playground.SECRET_RADIUS = 12.5 -- радиус стены кустов
Playground.SECRET_HEDGE = 7 -- её высота: поверх не заглянуть :: { Spot }

-- Сила батутов: от маленького к большому. Выше 90 ребёнок улетает из кадра.
Playground.TRAMPOLINE_POWER = { 60, 75, 90 }

-- До-мажор от «до» до «до»: во сколько раз ускорить звук, чтобы получить ноту.
Playground.NOTE_SPEEDS = { 1, 9 / 8, 5 / 4, 4 / 3, 3 / 2, 5 / 3, 15 / 8, 2 }

Playground.PHOTO_POSE_SECONDS = 2.5 -- сколько камера держит кадр «фотографа»
Playground.PHOTO_COOLDOWN = 6

Playground.HOPSCOTCH_MAX = 10
Playground.BALL_COUNT = 4
Playground.BALLOON_COUNT = 7
Playground.BALLOON_REGROW = 6 -- через сколько секунд лопнутый шарик появляется снова

--[[
	Лабиринт — сетка клеток: # — куст, . — проход, * — середина с флажком.
	Маленький и без тупиков длиннее трёх клеток: заблудиться в нём четырёхлетке
	должно быть весело, а не страшно.
]]
Playground.MAZE = {
	"###.###",
	"#.....#",
	"#.###.#",
	"..#*#..",
	"#.#.#.#",
	"#.....#",
	"###.###",
}
Playground.MAZE_CELL = 5

--[[
	Бобовый стебель. Высоты — от земли у корня. Прыжок в парке поднимает на
	6,4 студа (JumpPower 50), поэтому обычная ступень не выше четырёх: пятилетке
	трудно, но честно. Один лист выше прыжка — на него только со стручка-батута.
]]
Playground.BEAN_TOP = 60 -- верх облачного острова
Playground.BEAN_ISLAND = 14 -- радиус острова
Playground.BEAN_ISLAND_THICK = 3
Playground.BEAN_JUMP = 50 * 50 / (2 * 196.2) -- на сколько поднимает обычный прыжок в парке
Playground.BEAN_POD_POWER = 50 -- толчок стручка-батута: к листу, до которого не допрыгнуть
Playground.BEAN_POD_HOLD = 0.1 -- столько секунд толчок держит скорость (PlaygroundController)
Playground.BEAN_FLOAT = 1.2 -- на сколько качается плавающий лист вверх и вниз

export type BeanLeaf = {
	index: number,
	y: number, -- верх листа над землёй
	angle: number, -- вокруг стебля, в радианах
	radius: number, -- от оси стебля до середины листа
	size: number, -- поперечник
	kind: "leaf" | "float" | "nest" | "pod" | "high",
	rise: number, -- на сколько выше предыдущего
	gap: number, -- от края до края с предыдущим, по горизонтали
}

--[[
	Листья по спирали снизу вверх. Каждый следующий ставится так, чтобы от края
	до края с предыдущим было ровно gap: угол поворота считается из радиусов.
	Три пояса: внизу большие листья и маленькие ступени, на середине — гнездо-
	сохранка и качающиеся листья, наверху маленькие листья, стручок-батут
	и выход наружу, из-под острова, — чтобы не стукнуться о него головой.
]]
function Playground.beanLeaves(): { BeanLeaf }
	local leaves: { BeanLeaf } = {}
	local y, angle = 0, 0
	local function add(kind, size: number, rise: number, gap: number, radius: number)
		local previous = leaves[#leaves]
		y += rise
		if previous then
			local reach = previous.size / 2 + size / 2 + gap
			local cosine = (previous.radius ^ 2 + radius ^ 2 - reach ^ 2) / (2 * previous.radius * radius)
			angle += math.acos(math.clamp(cosine, -1, 1))
		end
		local leaf: BeanLeaf = {
			index = #leaves + 1,
			y = y,
			angle = angle,
			radius = radius,
			size = size,
			kind = kind,
			rise = rise,
			gap = 0,
		}
		if previous then
			local a = Vector2.new(math.cos(previous.angle), math.sin(previous.angle)) * previous.radius
			local b = Vector2.new(math.cos(angle), math.sin(angle)) * radius
			leaf.gap = (a - b).Magnitude - previous.size / 2 - size / 2
		end
		table.insert(leaves, leaf)
	end
	for _ = 1, 7 do
		add("leaf", 6, 3, 2, 7)
	end
	add("nest", 7, 3.5, 2, 7.5)
	for index = 1, 5 do
		add(if index == 2 or index == 4 then "float" else "leaf", 5, 3.4, 3, 7.5)
	end
	-- Наружу из-под острова: стручок подбрасывает высоко, и над ним должно быть небо.
	add("leaf", 5, 3.4, 3, 12)
	add("pod", 5, 3.4, 3, 16.5)
	-- Выше прыжка и уже снаружи острова: сюда только со стручка, отсюда — на остров.
	add("high", 4.6, 8, 2.5, 18)
	return leaves
end

-- На сколько стручок поднимает ноги: удержание скорости и полёт после него.
function Playground.beanPodRise(): number
	local power = Playground.BEAN_POD_POWER
	return power * Playground.BEAN_POD_HOLD + power * power / (2 * 196.2)
end

local byId: { [string]: Spot } = {}
for _, spot in Playground.spots do
	assert(byId[spot.id] == nil, `Playground: дубликат места "{spot.id}"`)
	byId[spot.id] = spot
end

function Playground.expect(id: string): Spot
	local spot = byId[id]
	assert(spot, `Playground: неизвестное место "{id}"`)
	return spot
end

--[[
	Грот: круглая пещера под каменным холмом. Углы — в системе места:
	0° — вправо (+X), 90° — к дальней стене (+Z), вход на −90°, к площади.
]]
Playground.GROTTO = {
	radius = 11.5, -- до внутренней стороны стен
	height = 10, -- потолок
	doorway = 6, -- ширина входа
	crystalRing = 9.3, -- где растут кристаллы, от центра
	-- Кристаллы по стенам: у каждого своя нота (NOTE_SPEEDS), вход и сундук свободны.
	crystals = { -40, 0, 38, 68, 112, 142, 180, 220 },
	chest = 6.5, -- сундук у дальней стены, столько от центра
}

--[[
	Азбука-дорожка: плитки змейкой по рядам, А — у площади слева, Я — в дальнем
	ряду; с площади читается слева направо. Координаты — в системе места (−Z к площади).
]]
Playground.ABC = {
	rows = { 7, 7, 7, 6, 6 }, -- сколько плиток в ряду: всего 33
	tile = 3.4, -- сторона плитки
	pitch = 4.4, -- от центра до центра вдоль ряда
	rowGap = 5, -- между рядами
	speakEvery = 0.7, -- не чаще: бегущий ребёнок не копит очередь из названий
	celebrate = 7, -- столько горит праздник, потом дорожка гаснет
}

-- Где плитка order (1..33) в системе места: змейка, ряды от площади вдаль.
function Playground.abcTile(order: number): Vector3
	local spec = Playground.ABC
	local index = order
	for row, count in spec.rows do
		if index <= count then
			-- Короткий ряд сдвинут к стыку с прошлым: змейка не рвётся на повороте.
			local widest = 0
			for _, n in spec.rows do
				widest = math.max(widest, n)
			end
			local odd = row % 2 == 1
			local shift = (widest - count) * spec.pitch / 2 * (if odd then 1 else -1)
			local offset = (index - 1 - (count - 1) / 2) * spec.pitch + shift
			-- С площади (−Z) экранное «вправо» — это −X: нечётный ряд идёт к −X.
			local x = if odd then -offset else offset
			local z = (row - (#spec.rows + 1) / 2) * spec.rowGap
			return Vector3.new(x, 0, z)
		end
		index -= count
	end
	error(`Playground.abcTile: нет плитки {order}`)
end

-- Центр места на земле (Y = 0: высоту земли добавляет тот, кто строит).
function Playground.position(spot: Spot): Vector3
	local angle = math.rad(spot.angle)
	return Vector3.new(math.cos(angle) * spot.distance, 0, math.sin(angle) * spot.distance)
end

return Playground
