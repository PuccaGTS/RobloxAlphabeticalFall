--!strict
--[[
	Катания в парке: игрушечный паровозик по кругу на эстакаде и колесо обозрения.

	Это игрушки, как батуты (Config/Playground): звёзд не дают, ничему не учат,
	проверять на сервере нечего. Сервер ставит детали, а едет всё на клиенте
	(Controllers/RideController) по серверным часам — у всех детей паровозик
	в одном и том же месте, и никакой сети на движение не тратится.

	Прокатиться можно: встал на посадочный круг — сел в вагончик или кабинку,
	и тебя везут. Прыжок — сошёл где угодно. Зачем: после горизонта
	(Config/Horizon) сверху есть на что посмотреть, а круг на паровозике
	показывает весь парк — куда бежать дальше.
]]

local Base = require(script.Parent.Base)

local Rides = {}

--[[
	Паровозик. Эстакада идёт кольцом между опушкой парка и домами — в этой
	полосе нет ни декора (Config/Decor.MAX_RADIUS), ни участков. Высота —
	чтобы ребёнок проходил под ней по дорожкам к домам, не пригибаясь.
]]
Rides.TRAIN = {
	radius = 268,
	height = 7, -- верх полотна над землёй
	segments = 72, -- полотно из прямых отрезков: 72 — круга не отличить от многоугольника
	pillarStep = 40, -- через сколько студов столб
	speed = 20, -- студов в секунду в среднем: у станции вдвое медленнее, на дальней стороне быстрее
	dwell = 10, -- сколько стоит на станции: сесть успевает и не торопящийся
	stationAngle = 45, -- в градусах: между дорожками к домам и между участками
	cars = 4, -- паровоз и три вагончика
	carGap = 8.5, -- от центра до центра вагона вдоль пути
}

-- Длина круга и полный цикл расписания: круг плюс стоянка.
function Rides.trainLap(): number
	return 2 * math.pi * Rides.TRAIN.radius / Rides.TRAIN.speed
end

function Rides.trainCycle(): number
	return Rides.trainLap() + Rides.TRAIN.dwell
end

--[[
	Где голова поезда в момент now (серверные часы): угол на кольце в радианах
	и стоит ли он на станции. Цикл начинается со стоянки: пока идёт посадка,
	поезд у платформы, потом круг против часовой стрелки и снова станция.
]]
function Rides.trainAt(now: number): (number, boolean)
	local cycle = Rides.trainCycle()
	local t = now % cycle
	local station = math.rad(Rides.TRAIN.stationAngle)
	if t < Rides.TRAIN.dwell then
		return station, true
	end
	local travelled = (t - Rides.TRAIN.dwell) / Rides.trainLap()
	-- Разгон и торможение: без них поезд трогается и встаёт рывком. Скорость
	-- у станции 0,4 от средней, напротив неё — 1,6.
	local eased = travelled - 0.6 * math.sin(travelled * math.pi * 2) / (math.pi * 2)
	return station + eased * math.pi * 2, false
end

-- Угол вагона на кольце: вагоны идут за головой.
function Rides.carAngle(headAngle: number, index: number): number
	return headAngle - (index - 1) * Rides.TRAIN.carGap / Rides.TRAIN.radius
end

-- Точка на полотне и направление движения по углу.
function Rides.trackFrame(angle: number): CFrame
	local radius = Rides.TRAIN.radius
	local position = Vector3.new(math.cos(angle) * radius, Rides.TRAIN.height, math.sin(angle) * radius)
	local forward = Vector3.new(-math.sin(angle), 0, math.cos(angle)) -- против часовой, если смотреть сверху
	return CFrame.lookAt(position, position + forward)
end

-- Станция: платформа внутри кольца, вход по пандусу вдоль пути.
Rides.STATION = {
	platformLength = 34,
	platformWidth = 7,
	rampLength = 24,
}

function Rides.stationFrame(): CFrame
	local angle = math.rad(Rides.TRAIN.stationAngle)
	-- Платформа стоит по центру поезда, который встал на стоянку: голова впереди.
	local middle = angle - (Rides.TRAIN.cars - 1) / 2 * Rides.TRAIN.carGap / Rides.TRAIN.radius
	local frame = Rides.trackFrame(middle)
	-- Внутрь кольца, к парку. Поезд идёт против часовой, так что центр — справа по ходу.
	return frame * CFrame.new(3 + Rides.STATION.platformWidth / 2, 0, 0)
end

--[[
	Колесо обозрения. Стоит в парке впереди-слева от точки появления: его видно
	поверх порталов, и первое, что хочется, — добежать и прокатиться.
	Место под него заведено в Config/Playground (ferris), чтобы декор его обходил.
]]
Rides.WHEEL = {
	spot = "ferris",
	diameter = 34,
	axle = 22.5, -- высота оси над землёй: нижняя кабинка стоит чуть выше травы
	cabins = 8,
	period = 44, -- полный оборот: медленно, как у настоящего
	cabinSize = Vector3.new(4.6, 4.2, 4.6),
}

-- Поворот колеса в момент now: 0 — первая кабина внизу.
function Rides.wheelAngle(now: number): number
	return (now % Rides.WHEEL.period) / Rides.WHEEL.period * math.pi * 2
end

--[[
	Центр кабины index в системе колеса (ось X колеса — вдоль оси вращения).
	Кабины висят на ободе и всегда вертикальны: крутится обод, а не пассажир.
]]
function Rides.cabinOffset(index: number, wheelAngle: number): Vector3
	local phase = wheelAngle + (index - 1) / Rides.WHEEL.cabins * math.pi * 2
	local r = Rides.WHEEL.diameter / 2
	-- Фаза 0 — внизу. Кабина подвешена ниже точки обода на половину своей высоты.
	return Vector3.new(0, -math.cos(phase) * r - Rides.WHEEL.cabinSize.Y / 2, math.sin(phase) * r)
end

-- Какая кабина сейчас ближе всех к земле.
function Rides.lowestCabin(wheelAngle: number): number
	local best, bestY = 1, math.huge
	for index = 1, Rides.WHEEL.cabins do
		local y = Rides.cabinOffset(index, wheelAngle).Y
		if y < bestY then
			best, bestY = index, y
		end
	end
	return best
end

-- Сколько объектов шевелится в кадре (для бюджета Config/LiveWorld): поезд и колесо.
Rides.MOVING = 2

-- Эстакада лежит в свободной полосе между парком и участками.
Rides.PLOT_INNER = Base.RING_RADIUS - Base.PLOT_SIZE / 2

return Rides
