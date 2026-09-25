--!strict
--[[
	Катания в парке: игрушечный паровозик по кругу на эстакаде, колесо обозрения,
	карусель с лошадками, горка-спираль и воздушный шар.

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
	полосе нет ни декора (Config/Decor.MAX_RADIUS), ни участков.

	На проверке 25.09.2026: полотно было «прозрачным» (без столкновений, голова
	проваливалась), поезд не поймать — стоял у единственной станции 10 секунд
	из 94, — а навес задевал макушку. Теперь эстакада твёрдая и вдвое выше —
	под ней свободно, по ней можно пройтись, — а станций четыре, по одной
	между дорожками к домам: поезд стоит на каждой, и ждать его недолго.
]]
Rides.TRAIN = {
	radius = 268,
	height = 14, -- верх полотна над землёй
	segments = 72, -- полотно из прямых отрезков: 72 — круга не отличить от многоугольника
	pillarStep = 40, -- через сколько студов столб
	speed = 20, -- студов в секунду в среднем: трогается и тормозит плавно, в середине перегона вдвое быстрее
	dwell = 10, -- сколько стоит на станции: сесть успевает и не торопящийся
	stationAngle = 45, -- в градусах: первая станция, между дорожками к домам и между участками
	stations = 4, -- станций по кольцу, поровну: вторая через четверть круга
	cars = 4, -- паровоз и три вагончика
	carGap = 8.5, -- от центра до центра вагона вдоль пути
}

-- Длина круга без стоянок, перегон между станциями и полный цикл расписания.
function Rides.trainLap(): number
	return 2 * math.pi * Rides.TRAIN.radius / Rides.TRAIN.speed
end

function Rides.trainLeg(): number
	return Rides.trainLap() / Rides.TRAIN.stations
end

function Rides.trainCycle(): number
	return Rides.trainLap() + Rides.TRAIN.dwell * Rides.TRAIN.stations
end

-- Угол станции index (1..stations) на кольце, в радианах.
function Rides.stationAngle(index: number): number
	return math.rad(Rides.TRAIN.stationAngle) + (index - 1) / Rides.TRAIN.stations * math.pi * 2
end

--[[
	Где голова поезда в момент now (серверные часы): угол на кольце в радианах,
	стоит ли он и у какой станции (номер — только на стоянке). Цикл начинается
	со стоянки у первой станции, потом перегон против часовой стрелки ко второй,
	стоянка — и так по кругу.
]]
function Rides.trainAt(now: number): (number, boolean, number?)
	local spec = Rides.TRAIN
	local step = spec.dwell + Rides.trainLeg()
	local t = now % Rides.trainCycle()
	local leg = math.floor(t / step)
	local within = t - leg * step
	local from = Rides.stationAngle(leg + 1)
	if within < spec.dwell then
		return from, true, leg + 1
	end
	local travelled = (within - spec.dwell) / Rides.trainLeg()
	-- Разгон и торможение: у станции скорость ноль, в середине перегона — вдвое выше средней.
	local eased = travelled - math.sin(travelled * math.pi * 2) / (math.pi * 2)
	return from + eased * math.pi * 2 / spec.stations, false, nil
end

-- Через сколько секунд поезд встанет у станции index: 0 — стоит там сейчас.
function Rides.trainArrival(now: number, index: number): number
	local step = Rides.TRAIN.dwell + Rides.trainLeg()
	local cycle = Rides.trainCycle()
	local t = now % cycle
	local arrive = (index - 1) * step
	if t >= arrive and t < arrive + Rides.TRAIN.dwell then
		return 0
	end
	return (arrive - t) % cycle
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
	rampLength = 38,
	roofHeight = 10, -- от платформы до навеса: взрослый аватар в шляпе проходит
}

function Rides.stationFrame(index: number?): CFrame
	local angle = Rides.stationAngle(index or 1)
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

-- ===== Карусель =====

--[[
	Карусель с лошадками: круглый помост под полосатым шатром, шесть лошадок
	на золотых шестах скачут вверх-вниз, пока помост кружится. Играет вальс
	шарманки — слышно рядом. Встал на круг — сел на ближнюю лошадку, два круга.
]]
Rides.CAROUSEL = {
	spot = "carousel",
	platform = 20, -- поперечник помоста
	horses = 6,
	ring = 6.8, -- на каком расстоянии от оси скачут лошадки
	period = 16, -- полный оборот
	bob = 0.9, -- на сколько лошадка поднимается и опускается
	bobPeriod = 2.6,
	laps = 2,
	roof = 12.5, -- высота края шатра
}

function Rides.carouselAngle(now: number): number
	return (now % Rides.CAROUSEL.period) / Rides.CAROUSEL.period * math.pi * 2
end

--[[
	Где лошадка index в системе карусели (центр помоста на земле): угол на
	кольце плюс подскок. Смотрит лошадка по ходу вращения. Соседние скачут
	в противофазе — как на настоящей карусели.
]]
function Rides.horseFrame(index: number, angle: number, now: number): CFrame
	local spec = Rides.CAROUSEL
	local a = angle + (index - 1) / spec.horses * math.pi * 2
	local bob = spec.bob * math.sin(now / spec.bobPeriod * math.pi * 2 + (index % 2) * math.pi)
	-- CFrame.Angles(0, -a, 0) поворачивает +X к +Z: туда же, куда растёт угол.
	return CFrame.Angles(0, -a, 0) * CFrame.new(spec.ring, 2.6 + bob, 0) * CFrame.Angles(0, math.pi, 0)
end

-- ===== Горка-спираль =====

--[[
	Башня с лестницей-сеткой и спиральный жёлоб вокруг неё: полтора витка
	от смотровой площадки до травы. Встал наверху на круг — поехал, свисток
	съезжает вниз вместе с тобой, внизу вылетаешь на траву.
]]
Rides.SLIDE = {
	spot = "slide",
	height = 18, -- площадка наверху
	bottom = 1.2, -- конец жёлоба над травой
	radius = 9.5, -- радиус спирали жёлоба
	width = 4.2,
	turns = 1.5,
	seconds = 5, -- сколько едешь
	platform = 4.5, -- радиус площадки наверху
	ladderAngle = 300, -- где лестница: под жёлобом там больше семи студов
}

--[[
	Точка на оси жёлоба (поверхность, по которой едут) в системе горки:
	u = 0 — верх, u = 1 — низ. Жёлоб идёт от угла 0 в сторону роста угла.
]]
function Rides.slidePoint(u: number): Vector3
	local spec = Rides.SLIDE
	local a = u * spec.turns * math.pi * 2
	local y = spec.height - (spec.height - spec.bottom) * u
	return Vector3.new(math.cos(a) * spec.radius, y, math.sin(a) * spec.radius)
end

-- Сколько проехал к моменту t после старта: плавный разгон, потом всё быстрее.
function Rides.slideProgress(t: number): number
	local s = math.clamp(t / Rides.SLIDE.seconds, 0, 1)
	return s ^ 1.35
end

-- Высота оси жёлоба над землёй на угле φ (в градусах) — все проходы жёлоба там.
function Rides.slideHeightsAt(degrees: number): { number }
	local spec = Rides.SLIDE
	local heights = {}
	local total = spec.turns * 360
	local a = degrees % 360
	while a <= total do
		table.insert(heights, spec.height - (spec.height - spec.bottom) * a / total)
		a += 360
	end
	return heights
end

-- ===== Воздушный шар =====

--[[
	Полосатый шар с корзинкой. Стоит на лужайке, потом горелка ревёт, и шар
	поднимается выше колеса обозрения, делает круг над парком и садится туда же.
	Сесть можно, пока он на земле (круг зелёный), — как на паровозик.
]]
Rides.BALLOON = {
	spot = "balloon",
	ground = 14, -- стоит на лужайке
	rise = 16,
	drift = 34, -- круг над парком на высоте
	descend = 16,
	height = 80, -- на сколько поднимается корзина
	circle = 55, -- радиус круга над парком
	envelope = 18, -- поперечник купола
}

function Rides.balloonCycle(): number
	local spec = Rides.BALLOON
	return spec.ground + spec.rise + spec.drift + spec.descend
end

local function smooth(x: number): number
	x = math.clamp(x, 0, 1)
	return x * x * (3 - 2 * x)
end

--[[
	Где корзина относительно своей стоянки в момент now и стоит ли шар на земле.
	inward — направление к центру площади (единичный, горизонтальный): круг над
	парком ложится в ту сторону, чтобы шар пролетал над деревьями, а не над домами.
	Третье значение — горит ли горелка: на подъёме и на круге, но не на спуске.
]]
function Rides.balloonAt(now: number, inward: Vector3): (Vector3, boolean, boolean)
	local spec = Rides.BALLOON
	local t = now % Rides.balloonCycle()
	if t < spec.ground then
		return Vector3.zero, true, false
	end
	t -= spec.ground
	local airborne = spec.rise + spec.drift + spec.descend
	local y
	if t < spec.rise then
		y = spec.height * smooth(t / spec.rise)
	elseif t < spec.rise + spec.drift then
		y = spec.height
	else
		y = spec.height * (1 - smooth((t - spec.rise - spec.drift) / spec.descend))
	end
	-- По кругу, который проходит через стоянку: начало и конец — на ней.
	local phi = smooth(t / airborne) * math.pi * 2
	local side = Vector3.new(-inward.Z, 0, inward.X)
	local flat = inward * spec.circle * (1 - math.cos(phi)) + side * spec.circle * math.sin(phi)
	return flat + Vector3.new(0, y, 0), false, t < spec.rise + spec.drift
end

-- ===== Лодочки-лебеди =====

--[[
	Озеро с островком и ивой посередине, по кругу плывут три лодочки-лебедя.
	Встал на круг в конце мостков — сел в ближнюю лодочку и проплыл круг
	по озеру, лодочка привозит обратно к мосткам. Рядом играет «Танец
	маленьких лебедей» (APM, без загрузки) и плещется вода.
]]
Rides.SWANS = {
	spot = "lake",
	lake = 21, -- радиус воды
	island = 5, -- радиус островка посередине
	loop = 13, -- по какому кругу плывут лодочки
	boats = 3,
	period = 42, -- круг лодочки
	bob = 0.18, -- покачивание на воде
}

function Rides.swanAngle(now: number): number
	return (now % Rides.SWANS.period) / Rides.SWANS.period * math.pi * 2
end

--[[
	Лодочка index в системе озера (центр воды): на кругу, клювом по ходу,
	чуть покачивается. Плывут против часовой, если смотреть сверху.
]]
function Rides.swanFrame(index: number, angle: number, now: number): CFrame
	local spec = Rides.SWANS
	local a = angle + (index - 1) / spec.boats * math.pi * 2
	local bob = spec.bob * math.sin(now * 1.7 + index * 2)
	local roll = 0.04 * math.sin(now * 1.3 + index)
	-- Та же запись, что у лошадок: CFrame.Angles(0, -a, 0) несёт +X к +Z.
	return CFrame.Angles(0, -a, 0) * CFrame.new(spec.loop, bob, 0) * CFrame.Angles(0, math.pi, roll)
end

-- ===== Корабль-качели =====

--[[
	Пиратский кораблик на двух опорах качается, как огромные качели: сначала
	чуть-чуть, потом всё выше — почти до горизонтали, — и снова затихает.
	Пока стоит, круг посадки зелёный: встал — сел на скамейку на корме,
	качаешься одну раскачку и сходишь у того же круга. Рядом морская песня
	(APM, без загрузки), на отплытии кричат чайки, в качке скрипит дерево.
]]
Rides.SHIP = {
	spot = "ship",
	pivot = 15, -- высота оси над землёй
	arm = 9.5, -- от оси до палубы
	length = 16, -- длина корпуса вдоль качания
	width = 6,
	swing = math.rad(52), -- наибольший размах
	period = 5.6, -- полный мах туда и обратно
	dwell = 9, -- стоит у посадки
	ride = 32, -- раскачка от начала до остановки
	ramp = 8, -- столько размах растёт в начале и затихает в конце
	benches = { -5.4, -2.2, 2.2, 5.4 }, -- где скамейки вдоль корпуса
	riderBench = 1, -- на какую садится ребёнок: крайняя, с неё виднее всего
}

function Rides.shipCycle(): number
	return Rides.SHIP.dwell + Rides.SHIP.ride
end

--[[
	Угол корабля в момент now (серверные часы) и стоит ли он у посадки.
	Размах растёт плавно (ramp), держится и так же затихает — корабль не
	дёргается ни на старте, ни при остановке.
]]
function Rides.shipAt(now: number): (number, boolean, number)
	local spec = Rides.SHIP
	local t = now % Rides.shipCycle()
	if t < spec.dwell then
		return 0, true, 0
	end
	local s = t - spec.dwell
	local envelope = math.clamp(math.min(s / spec.ramp, (spec.ride - s) / spec.ramp), 0, 1)
	envelope = envelope * envelope * (3 - 2 * envelope)
	return spec.swing * envelope * math.sin(2 * math.pi * s / spec.period), false, envelope
end

-- Палуба корабля относительно оси: качается вокруг Z оси, висит на плечах arm.
function Rides.shipFrame(angle: number): CFrame
	return CFrame.Angles(0, 0, angle) * CFrame.new(0, -Rides.SHIP.arm, 0)
end

-- ===== Домик на дереве и тарзанка =====

--[[
	Два дерева-великана: на большом домик с круглым окошком, на малом —
	площадка с тарзанкой. Наверх — по верёвочной лестнице, между деревьями —
	подвесной мостик из досок со щелями (смотри под ноги). С малого дерева
	тарзанка уносит вниз, через лужайку к песочной яме: встал на круг —
	схватился за ролик и поехал, внизу отпустил и приземлился в песок.

	Координаты — в системе места (−Z смотрит на площадь, центр на земле).
]]
Rides.TREEHOUSE = {
	spot = "treehouse",
	deck = 13, -- верх площадок на деревьях
	big = Vector3.new(-11, 0, 7), -- большое дерево с домиком
	small = Vector3.new(11, 0, 7), -- малое дерево с тарзанкой
	bigDeck = 12, -- сторона площадки большого дерева: вокруг домика проход
	smallDeck = 7,
	planks = 11, -- досок в мостике
	sag = 1.2, -- на сколько мостик провисает посередине
	zipFrom = Vector3.new(11, 19.6, 2.6), -- трос у края малой площадки: ноги висящего — над досками
	zipTo = Vector3.new(-4, 7.2, -19), -- столб у песочной ямы
	zipSag = 1.4,
	hang = 3.4, -- корень ребёнка под тросом
	seconds = 4.2,
}

-- Точка троса тарзанки: u = 0 — у малого дерева, u = 1 — у столба внизу.
function Rides.zipPoint(u: number): Vector3
	local spec = Rides.TREEHOUSE
	return spec.zipFrom:Lerp(spec.zipTo, u) - Vector3.new(0, spec.zipSag * math.sin(math.pi * u), 0)
end

-- Сколько проехал к моменту t: срывается медленно, разгоняется, у столба тормозит.
function Rides.zipProgress(t: number): number
	local s = math.clamp(t / Rides.TREEHOUSE.seconds, 0, 1)
	local eased = s ^ 1.5
	-- Последняя пятая часть пути — плавное торможение.
	if eased > 0.8 then
		local k = (eased - 0.8) / 0.2
		eased = 0.8 + 0.2 * (1 - (1 - k) ^ 2)
	end
	return eased
end

-- Куда смотрит тарзанка по земле: от малого дерева к песочной яме.
function Rides.zipHeading(): Vector3
	local spec = Rides.TREEHOUSE
	return ((spec.zipTo - spec.zipFrom) * Vector3.new(1, 0, 1)).Unit
end

Rides.ZIP_JUMP = 8 -- с какой скоростью вперёд спрыгиваешь с сиденья внизу

-- Где приземляешься, спрыгнув внизу: чуть впереди конца троса. Песок — тут.
function Rides.zipLanding(): Vector3
	local spec = Rides.TREEHOUSE
	return (spec.zipTo + Rides.zipHeading() * 2.5) * Vector3.new(1, 0, 1)
end

-- Высота доски мостика index (1..planks) над площадками: провисает дугой.
function Rides.bridgeDip(index: number): number
	local spec = Rides.TREEHOUSE
	local u = (index - 0.5) / spec.planks
	return spec.sag * math.sin(math.pi * u)
end

-- Сколько объектов шевелится в кадре (для бюджета Config/LiveWorld):
-- поезд, колесо, карусель, воздушный шар, лебеди (плывут одним кругом)
-- и корабль-качели. Горка стоит, едет только ребёнок.
Rides.MOVING = 6

-- Эстакада лежит в свободной полосе между парком и участками.
Rides.PLOT_INNER = Base.RING_RADIUS - Base.PLOT_SIZE / 2

return Rides
