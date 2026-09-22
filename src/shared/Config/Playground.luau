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
} :: { Spot }

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

-- Центр места на земле (Y = 0: высоту земли добавляет тот, кто строит).
function Playground.position(spot: Spot): Vector3
	local angle = math.rad(spot.angle)
	return Vector3.new(math.cos(angle) * spot.distance, 0, math.sin(angle) * spot.distance)
end

return Playground
