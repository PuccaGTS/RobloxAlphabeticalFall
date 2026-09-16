--!strict
--[[
	Геометрия и параметры забега: и «Азбучного туннеля», и «Полосы препятствий».
	См. docs/14-TUNNEL-MODE.md и docs/19-OBSTACLES.md.

	Бег свободный: скорость задаёт ребёнок, а не игра. Поэтому здесь нет параметра
	скорости — есть только расстояния, из которых складывается ритм забега.
]]

local Obstacles = require(script.Parent.Obstacles)

local Tunnel = {}

Tunnel.LANE_COUNT = 3
Tunnel.LANE_WIDTH = 9 -- расстояние между центрами дорожек
Tunnel.WIDTH = Tunnel.LANE_COUNT * Tunnel.LANE_WIDTH
Tunnel.HEIGHT = 16
Tunnel.WALL_THICKNESS = 2

Tunnel.START_RUNWAY = 30 -- разгон перед первыми воротами
Tunnel.FINISH_RUNWAY = 35

--[[
	Расстояние между воротами не задано числом: оно вычисляется из того, сколько
	препятствий стоит на отрезке. Раньше здесь была константа, и на полосе
	препятствий элементы налезали друг на друга, стоило поднять их число.

	MIN_GATE_SPACING держит нижнюю границу: даже отрезок без единого препятствия
	остаётся достаточно длинным, чтобы ворота были видны заранее.
]]
Tunnel.MIN_GATE_SPACING = 55

--[[
	Длина отрезка мерится временем, а не студами (docs/14-TUNNEL-MODE.md § 3.4).

	Нижняя граница была сорок секунд, и на первой проверке отрезок назвали
	«слишком длинным и скучным»: паркур кончался, а дальше шли сотни студов
	ровного пола. Теперь граница тридцать секунд, а пустого пола нет вовсе —
	каждая беговая клетка получает форму (Logic/TrackShape): горку, ямку,
	вираж или змейку.
]]
Tunnel.SEGMENT_SECONDS_MIN = 30
Tunnel.SEGMENT_SECONDS_MAX = 70

--[[
	Беговая клетка: отрезок трассы между связками паркура, на котором трасса
	меняет форму. Клетки идут ПОСЛЕ элементов, поэтому последняя всегда
	упирается в зону ворот, а ворота стоят на ровном.

	Две клетки на отрезке есть всегда, даже на последних уровнях, где паркура
	хватает на всё время: без них трасса снова стала бы прямой доской.
	Больше пяти не бывает — длинная пробежка скучна даже с горками.
]]
Tunnel.RUN_PITCH = 50
Tunnel.MIN_RUN_CELLS = 2
Tunnel.MAX_RUN_CELLS = 5
--[[
	Отрезок между воротами режется на клетки. В клетке препятствия элемент
	начинается с отступом OBSTACLE_LEAD и обязан кончиться до конца клетки —
	так соседние элементы не касаются друг друга, а у платформы, которая
	отъезжает назад от своей ямы, есть куда отъехать. Длины элементов —
	Tunnel.obstacleLength, и тест держит, что каждый влезает в клетку.

	Ряд букв (docs/14-TUNNEL-MODE.md § 4.2) получает свою клетку на целом полу:
	раньше ряды вставали между препятствиями, и плитка могла повиснуть над
	ямой у балки или утонуть в ступенях.
]]
Tunnel.OBSTACLE_PITCH = 20
Tunnel.OBSTACLE_LEAD = 3
Tunnel.ROW_PITCH = 8 -- клетка ряда букв; плитка стоит в её середине
Tunnel.CLEARANCE_AFTER_GATE = 10 -- сколько ровного пола сразу за воротами
Tunnel.CLEARANCE_BEFORE_GATE = 14 -- ворота видно заранее, и под ними ничего не крутится
Tunnel.CHECKPOINT_OFFSET = 6 -- насколько сохранка стоит дальше своих ворот
Tunnel.COLLECT_HEIGHT = 2.5 -- на какой высоте висит буква на дорожке: по пояс ребёнку
Tunnel.COLLECT_SIZE = 2.6 -- сторона плитки с буквой
Tunnel.ROW_PLACE = 3 -- где в клетке ряда стоит плитка: подальше от платформы следующей клетки

--[[
	Секрет уровня: постамент в крайней дорожке и золотая буква над ним
	(docs/18-CONTENT-BACKLOG.md § 8). Постамент ниже прыжка, но выше шага —
	на него надо запрыгнуть, мимо него можно просто пробежать. Стоит в своей
	клетке, как ряд букв, и не мешает ни препятствиям, ни воротам.
]]
Tunnel.SECRET_PEDESTAL = Vector3.new(5, 3, 5)
Tunnel.SECRET_SIZE = 2.8 -- сторона золотой плитки
Tunnel.SECRET_LIFT = 2.6 -- на сколько плитка висит над постаментом: по пояс стоящему на нём

-- Куда ставится туннель игрока. У каждого он свой, поэтому разносим по оси X.
-- Трасса петляет (Logic/TrackShape.MAX_SIDE), поэтому соседние туннели разнесены с запасом.
Tunnel.PLOT_SPACING = 900
Tunnel.PLOT_ORIGIN = Vector3.new(2000, 200, 0)

--[[
	Два режима одного забега.

	tunnel_run — учебный: ворота часто, препятствий между ними немного.
	obstacle_course — «полоса»: пропорции перевёрнуты, препятствий много, ворот мало.
	Ребёнок выбирает сам, чего ему сегодня хочется, и обе дороги ведут к буквам.
]]
Tunnel.PARAMS = {
	gates = { 4, 4, 5, 5, 6 },
	--[[
		Рядов букв на дорожке между воротами (docs/14-TUNNEL-MODE.md § 4.2).
		Ряд встаёт только в просвет между препятствиями, поэтому на отрезке
		их не больше, чем препятствий, — сколько бы здесь ни было написано.
	]]
	collect = { 2, 2, 3, 3, 3 },
	choices = { 2, 2, 3, 3, 4 }, -- сколько проёмов в воротах
	obstacles = { 3, 3, 4, 4, 5 }, -- элементов между воротами
	-- Средние элементы — не с первого дня, сложные — только уверенным.
	-- У уровня мира букв свой потолок ряда (Config/Levels): первые уровни только базовые.
	obstacleTier = { 1, 1, 2, 2, 3 },
	-- Замедление после неверных ворот: ошибка стоит времени, а не прогресса.
	missSlowSeconds = { 1.6, 1.4, 1.2, 1.1, 1.0 },
	missSlowFactor = { 0.45, 0.45, 0.5, 0.5, 0.55 },
}

Tunnel.COURSE_PARAMS = {
	gates = { 2, 2, 3, 3, 3 },
	collect = { 2, 3, 3, 3, 4 },
	choices = { 2, 2, 3, 3, 4 },
	-- Полоса обязана оставаться паркурнее туннеля: даже поздние уровни мира букв
	-- с их 11–14 элементами на отрезке не должны её догонять.
	obstacles = { 12, 14, 15, 16, 17 },
	obstacleTier = { 1, 1, 2, 2, 3 },
	missSlowSeconds = { 1.6, 1.4, 1.2, 1.1, 1.0 },
	missSlowFactor = { 0.45, 0.45, 0.5, 0.5, 0.55 },
}

--[[
	Ворота с числами (docs/16-MATH.md § 3.1). Тот же коридор, но препятствий между
	воротами меньше, чем даже в учебном туннеле: считать на бегу тяжелее, чем узнавать
	букву, и отрезок здесь нужен ребёнку на счёт, а не на прыжки.

	Проёмов не больше трёх: четвёртый вариант ответа для пятилетки — это уже перебор
	глазами, а не счёт. Точное число ещё раз урезается ступенью (Config/Math.choices):
	на «узнавании количества» их два.

	Числа ворот здесь нет: его задаёт уровень пути (Config/MathLevels), как и в мире букв.
]]
Tunnel.MATH_PARAMS = {
	choices = { 2, 2, 3, 3, 3 },
	obstacles = { 1, 2, 2, 3, 3 },
	obstacleTier = { 1, 1, 1, 2, 2 },
	missSlowSeconds = { 1.6, 1.4, 1.2, 1.1, 1.0 },
	missSlowFactor = { 0.45, 0.45, 0.5, 0.5, 0.55 },
}

Tunnel.WALK_SPEED = 20 -- базовая скорость персонажа в туннеле
Tunnel.JUMP_POWER = 55

-- Размеры элементов полосы. Прыжок персонажа Roblox берёт около 7 студов —
-- всё, что ниже и уже этого, проходится с запасом, и запас тут намеренный.
-- Ни один элемент не длиннее OBSTACLE_PITCH, иначе они наложатся друг на друга.
Tunnel.BARRIER_HEIGHT = 2.5
Tunnel.BARRIER_LENGTH = 1.5
Tunnel.GAP_LENGTH = 5 -- длина ямы вдоль бега: перепрыгивается с разбега и без него
Tunnel.ARCH_CLEARANCE = 4 -- высота, ниже которой свод не пропускает
Tunnel.BEAM_LENGTH = 12
Tunnel.BEAM_WIDTH = 3
Tunnel.STEP_HEIGHT = 2.5
Tunnel.STEP_RUN = 4
Tunnel.STEP_COUNT = 2 -- столько ступеней вверх, потом столько же вниз

--[[
	Средний ряд элементов (docs/19-OBSTACLES.md § 3.2).

	Все числа подчинены одному правилу: ничто не движется быстрее ребёнка
	и ничто не требует точного тайминга. Маятник проходит свою дугу за четыре
	секунды, платформа — за четыре, плита стоит три с половиной. Ребёнок может
	просто подождать, а может обойти по соседней дорожке: ни один средний элемент
	не занимает больше одной дорожки, кроме льда, с которого некуда падать.
]]
-- Подвес такой длины, чтобы шар ходил на уровне ног, а не над головой.
Tunnel.PENDULUM_ROPE = 11.5
Tunnel.PENDULUM_BALL = 2 -- диаметр мягкого шара

--[[
	Отклонение подобрано под два условия сразу, оба держатся тестом:
	шар не залезает в соседние дорожки, и в крайней точке дуги свою дорожку
	можно спокойно пройти рядом с ним. Ждать «окна» не нужно — оно широкое.
]]
Tunnel.PENDULUM_SWING = math.rad(16)
Tunnel.PENDULUM_SECONDS = 4 -- одна дуга: меньше двух студов в секунду

--[[
	Платформа ездит над ямой, но яма под ней не длиннее обычной: она
	перепрыгивается и без платформы. Платформа — удобство, а не обязанность,
	и промахнуться мимо неё ничем не грозит.
]]
Tunnel.PLATFORM_SPAN = 5 -- длина ямы под платформой вдоль бега
Tunnel.PLATFORM_LENGTH = 5 -- длина самой платформы
Tunnel.PLATFORM_LEAD = 3 -- насколько платформа отъезжает назад от края ямы
Tunnel.PLATFORM_TRAVEL = 11 -- сколько платформа проходит от края до края
Tunnel.PLATFORM_SECONDS = 4 -- время в одну сторону

Tunnel.FADE_TILE_COUNT = 3
Tunnel.FADE_TILE_RUN = 4 -- длина плиты вдоль бега; три плиты = FADE_SPAN
Tunnel.FADE_SPAN = Tunnel.FADE_TILE_COUNT * Tunnel.FADE_TILE_RUN
Tunnel.FADE_SOLID_SECONDS = 3.5 -- сколько плита держит; не меньше окна на решение
--[[
	Плиты гаснут по очереди со сдвигом в треть цикла. Пока «нет» короче этого сдвига,
	двух погасших плит подряд не бывает никогда, и дорожка не исчезает целиком.
	Это держится тестом на конфиге, а не только этим комментарием.
]]
Tunnel.FADE_GONE_SECONDS = 1.6

Tunnel.TRAMPOLINE_LENGTH = 5
Tunnel.TRAMPOLINE_POWER = 70 -- вертикальный толчок; потолок туннеля выше подскока

Tunnel.ICE_LENGTH = 12
Tunnel.ICE_FRICTION = 0.08

--[[
	Третий ряд и новые элементы (docs/19-OBSTACLES.md § 3.2.1). Правила те же:
	медленно, обойти можно всегда, падение стоит секунд.
]]
-- Кочки: яма в одну дорожку и камни через неё. Шаг между камнями — простой прыжок.
Tunnel.STONES_SPAN = 12
Tunnel.STONE_SIZE = 3
Tunnel.STONE_COUNT = 3

-- Бревно: крутится на месте поперёк дорожки. Высотой с барьер — перепрыгивается.
Tunnel.ROLLER_DIAMETER = 2.5
Tunnel.ROLLER_SECONDS = 2 -- пол-оборота; бревно круглое, крутится только на вид

-- Поршень: мягкий блок выезжает из стены в крайнюю дорожку и уезжает обратно.
Tunnel.PISTON_DEPTH = 3 -- толщина вдоль бега
Tunnel.PISTON_HEIGHT = 5
Tunnel.PISTON_SECONDS = 4 -- в одну сторону; медленнее, чем ребёнок идёт пешком

--[[
	Карусель: диск с перекладинами крутится в одной дорожке. Оборот за двенадцать
	секунд — это меньше двух студов в секунду на конце перекладины, то есть
	медленнее, чем ребёнок идёт пешком.
]]
Tunnel.CAROUSEL_SPAN = 8 -- он же диаметр диска
Tunnel.CAROUSEL_BARS = 4
Tunnel.CAROUSEL_BAR_HEIGHT = 1.4 -- по колено: перешагивается, не сбивает
Tunnel.CAROUSEL_SECONDS = 12 -- полный оборот

--[[
	Подъёмник: площадка идёт вверх-вниз, наверху мостик над той же дорожкой.
	Четыре секунды в одну сторону — столько же, сколько у платформы: ждать
	приходится ровно столько, сколько ребёнок готов ждать.
]]
Tunnel.LIFT_SPAN = 10 -- длина мостика вдоль бега
Tunnel.LIFT_HEIGHT = 6 -- высота мостика: выше прыжка, поэтому подъёмник и нужен
Tunnel.LIFT_PAD = 4 -- сторона площадки
Tunnel.LIFT_SECONDS = 4

--[[
	Спираль: ступени по кругу вокруг столба, вверх и обратно вниз. Ничего
	не движется, торопиться некуда — шаг между ступенями обычный, как у лестницы.
]]
Tunnel.SPIRAL_SPAN = 12 -- он же диаметр витка
Tunnel.SPIRAL_STEPS = 8
Tunnel.SPIRAL_HEIGHT = 5 -- на сколько поднимает верхняя ступень

-- Гребёнка: стена поперёк коридора с узкой щелью в каждой дорожке.
Tunnel.COMB_THICKNESS = 1.5
Tunnel.COMB_SLOT = 4 -- ширина щели: пройти можно, но прицелиться надо

--[[
	Сколько «живых» элементов (маятник, платформа, плиты) может стоять на одном
	отрезке. Больше двух — и отрезок превращается в аттракцион на реакцию,
	а буквы за ним теряются (docs/19-OBSTACLES.md § 3.3).
]]
Tunnel.MAX_MOVING_PER_SEGMENT = 2

--[[
	Глубина, ниже которой считается, что ребёнок упал. Внизу его ждёт не смерть,
	а мягкая площадка и возврат к последней сохранке — см. docs/17-CONTENT-PLAN.md § 3.1.
]]
Tunnel.FALL_DEPTH = 20

function Tunnel.laneOffset(lane: number): number
	return (lane - (Tunnel.LANE_COUNT + 1) / 2) * Tunnel.LANE_WIDTH
end

-- Длина отрезка между воротами: клетки препятствий, рядов букв и пробежек.
function Tunnel.segmentLength(obstacleCount: number, rowCount: number?, runCount: number?): number
	local needed = Tunnel.CLEARANCE_AFTER_GATE
		+ obstacleCount * Tunnel.OBSTACLE_PITCH
		+ (rowCount or 0) * Tunnel.ROW_PITCH
		+ (runCount or 0) * Tunnel.RUN_PITCH
		+ Tunnel.CLEARANCE_BEFORE_GATE
	return math.max(needed, Tunnel.MIN_GATE_SPACING)
end

--[[
	Сколько секунд элемент отнимает сверх пробега своей клетки: подойти, примерить
	прыжок, подождать, пока шар отойдёт или платформа вернётся. Числа взяты из
	самих элементов — маятник ходит дугу за PENDULUM_SECONDS, плита держит
	FADE_SOLID_SECONDS, — и округлены вниз: ребёнок редко ждёт полный цикл.

	Это оценка для раскладки, а не замер. Точные числа подбираются на детях,
	и менять их здесь безопасно: длина отрезка пересчитается сама.
]]
local SECONDS: { [string]: number } = {
	barrier = 1,
	gap = 1,
	arch = 1.5, -- перепрыгнуть нельзя, надо заранее сменить дорожку
	beam = 2.5, -- по узкой балке идут шагом, а не бегут
	steps = 3,
	pendulum = 3,
	platform = 4, -- единственный элемент, где ждать приходится по-настоящему
	fading = 3.5,
	trampoline = 2,
	ice = 1.5,
	stones = 3, -- три прыжка подряд
	roller = 1.5,
	pistons = 3,
	comb = 2,
	carousel = 2.5, -- пропустить перекладину
	lift = 5, -- дождаться площадки, подняться, пройти мостик и спрыгнуть
	spiral = 3,
}

function Tunnel.obstacleSeconds(kind: string): number
	return SECONDS[kind] or 0
end

--[[
	Средняя цена элемента ряда: раскладка ещё не знает, что ей выпадет, а длину
	отрезка считать уже надо. Берём среднее по каталогу, доступному на этом ряду.
]]
function Tunnel.tierSeconds(tier: number): number
	local ids = Obstacles.upToTier(tier)
	if #ids == 0 then
		return 0
	end
	local total = 0
	for _, id in ids do
		total += Tunnel.obstacleSeconds(Obstacles.expect(id).kind)
	end
	return total / #ids
end

-- Сколько секунд занимает отрезок: пробег всей его длины плюс цена препятствий.
function Tunnel.segmentSeconds(
	obstacleCount: number,
	tier: number,
	rowCount: number?,
	runCount: number?
): number
	local length = Tunnel.segmentLength(obstacleCount, rowCount, runCount)
	return length / Tunnel.WALK_SPEED + obstacleCount * Tunnel.tierSeconds(tier)
end

--[[
	Сколько беговых клеток добавить, чтобы отрезок дотянул до нижней границы
	бюджета. Паркур считается первым: клетки добирают остаток, а не заменяют
	собой элементы. Выше потолка не бывает, и лишней клетки, из-за которой
	отрезок перевалил бы за верхнюю границу, тоже: последняя добавляется,
	только пока отрезок короче минимума.
]]
function Tunnel.runCells(obstacleCount: number, tier: number, rowCount: number?): number
	local count = Tunnel.MIN_RUN_CELLS
	while count < Tunnel.MAX_RUN_CELLS do
		if Tunnel.segmentSeconds(obstacleCount, tier, rowCount, count) >= Tunnel.SEGMENT_SECONDS_MIN then
			break
		end
		count += 1
	end
	return count
end

--[[
	Сколько элемент занимает вдоль бега, от своей точки z вперёд. Единственное
	место, где это записано: по нему режутся дыры в полу, по нему тест проверяет,
	что элемент влезает в свою клетку, и что буквы рядом не висят над ямой.
]]
local LENGTHS: { [string]: number } = {
	barrier = Tunnel.BARRIER_LENGTH,
	gap = Tunnel.GAP_LENGTH,
	arch = 1.5,
	beam = Tunnel.BEAM_LENGTH,
	steps = Tunnel.STEP_COUNT * 2 * Tunnel.STEP_RUN,
	pendulum = Tunnel.PENDULUM_BALL,
	-- Платформа отъезжает на PLATFORM_LEAD назад от ямы: это место даёт OBSTACLE_LEAD.
	platform = Tunnel.PLATFORM_TRAVEL + Tunnel.PLATFORM_LENGTH - Tunnel.PLATFORM_LEAD,
	fading = Tunnel.FADE_SPAN,
	trampoline = Tunnel.TRAMPOLINE_LENGTH,
	ice = Tunnel.ICE_LENGTH,
	stones = Tunnel.STONES_SPAN,
	roller = Tunnel.ROLLER_DIAMETER,
	pistons = Tunnel.PISTON_DEPTH,
	comb = Tunnel.COMB_THICKNESS,
	carousel = Tunnel.CAROUSEL_SPAN,
	lift = Tunnel.LIFT_SPAN,
	spiral = Tunnel.SPIRAL_SPAN,
}

function Tunnel.obstacleLength(kind: string): number?
	return LENGTHS[kind]
end

-- Насколько элемент заходит назад от своей точки z. Есть только у платформы.
function Tunnel.obstacleLead(kind: string): number
	return if kind == "platform" then Tunnel.PLATFORM_LEAD else 0
end

return Tunnel
