--!strict
--[[
	Вечер в парке: раз в двенадцать минут солнце садится. Золотой час, розовые
	облака на закате, потом сиреневые сумерки — загораются фонари и окна домов,
	над клумбами светлячки, на небе звёзды, вместо птиц поют сверчки, а музыка
	сменяется колыбельной на музыкальной шкатулке. Две минуты — и розовое утро.

	Ночи нет: сумерки светлые, сиреневые, а не тёмные. Первая проба в Play
	показала, что небо движка к половине седьмого уже почти чёрное, облака
	как грозовые, и всё серое — это пугает, а не радует. Поэтому свет не
	«по часам», а по образам (LOOKS): подсветка, дымка и цвет облаков
	подобраны для каждого этапа руками.

	Время общее для всех — от серверных часов, закат у всех детей одновременно.
	Только в парке: на полянах занятий и в забеге всегда день, буквы видно
	одинаково хорошо в любой момент (Controllers/EveningController).
]]

local Evening = {}

export type Look = {
	clock: number, -- Lighting.ClockTime: где солнце
	--[[
		С какого времени начинать переход в этот образ. Утро не может прийти
		к рассвету через полдень: часы прыгают с вечерних сумерек на утренние,
		в самый тёмный миг, когда оба выглядят одинаково.
	]]
	clockFrom: number?,
	brightness: number,
	ambient: Color3,
	outdoor: Color3,
	exposure: number,
	tint: Color3, -- ColorCorrectionEffect.TintColor
	air: Color3, -- Atmosphere.Color
	decay: Color3, -- Atmosphere.Decay
	haze: number,
	glare: number,
	clouds: Color3,
	sun: number, -- видно ли солнце на небе (1 — да): красный диск на закате
	glow: number, -- вечерность: 0 — день, 1 — горят фонари, окна и светлячки
}

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

-- День — ровно тот свет, что ставит сервер (WorldService.styleLighting).
Evening.LOOKS = {
	day = {
		clock = 14,
		brightness = 2.1,
		ambient = rgb(105, 105, 120),
		outdoor = rgb(125, 125, 140),
		exposure = -0.1,
		tint = rgb(255, 251, 245),
		air = rgb(215, 228, 245),
		decay = rgb(150, 175, 210),
		haze = 0.7,
		glare = 0.2,
		clouds = rgb(255, 255, 255),
		sun = 0,
		glow = 0,
	},
	-- Золотой час: низкое тёплое солнце, длинные тени, медовые облака.
	golden = {
		clock = 16.9,
		brightness = 2.6,
		ambient = rgb(125, 108, 105),
		outdoor = rgb(165, 132, 115),
		exposure = -0.05,
		tint = rgb(255, 228, 196),
		air = rgb(255, 214, 170),
		decay = rgb(235, 160, 115),
		haze = 1.3,
		glare = 0.7,
		clouds = rgb(255, 222, 180),
		sun = 1,
		glow = 0,
	},
	-- Закат: солнце у горизонта, облака розовые, воздух персиковый.
	sunset = {
		clock = 17.75,
		brightness = 2.1,
		ambient = rgb(142, 112, 138),
		outdoor = rgb(185, 130, 152),
		exposure = 0.1,
		tint = rgb(255, 218, 214),
		air = rgb(255, 178, 160),
		decay = rgb(215, 120, 165),
		haze = 1.9,
		glare = 1.3,
		clouds = rgb(255, 172, 196),
		sun = 1,
		glow = 0.35,
	},
	--[[
		Сумерки: солнце село, но светло. Подсветка сиреневая и сильная —
		видно и дорожки, и игрушки, — а фонари, окна и светлячки уже горят.
	]]
	evening = {
		clock = 18.35,
		brightness = 0.8,
		ambient = rgb(118, 118, 170),
		outdoor = rgb(135, 135, 195),
		exposure = 0.3,
		tint = rgb(222, 222, 255),
		air = rgb(140, 145, 215),
		decay = rgb(90, 80, 160),
		haze = 1.2,
		glare = 0,
		clouds = rgb(175, 165, 225),
		sun = 0,
		glow = 1,
	},
	-- Розовое утро: часы перескакивают на рассветные сумерки и идут к полудню.
	dawn = {
		clock = 6.4,
		clockFrom = 24 - 18.35,
		brightness = 1.8,
		ambient = rgb(125, 112, 132),
		outdoor = rgb(160, 132, 152),
		exposure = 0,
		tint = rgb(255, 226, 232),
		air = rgb(255, 205, 205),
		decay = rgb(205, 150, 190),
		haze = 1.4,
		glare = 0.5,
		clouds = rgb(255, 212, 222),
		sun = 1,
		glow = 0.2,
	},
} :: { [string]: Look }

Evening.CYCLE = 12 * 60 -- полный круг: день, закат, сумерки, утро

--[[
	Расписание круга: в секунду at наступает образ look, между соседними
	строками свет плавно перетекает. День — восемь минут из двенадцати:
	вечер — событие, а не обычное состояние парка.
]]
Evening.TIMELINE = {
	{ at = 0, look = "day" },
	{ at = 480, look = "day" },
	{ at = 515, look = "golden" },
	{ at = 545, look = "sunset" },
	{ at = 575, look = "evening" },
	{ at = 690, look = "evening" },
	{ at = 705, look = "dawn" },
	{ at = Evening.CYCLE, look = "day" },
}

-- С какой вечерности горят фонари, окна, звёзды и звучит колыбельная.
Evening.NIGHT_FROM = 0.6

-- Парк — это всё вокруг площади. Поляны занятий и забеги стоят в тысячах студов от неё.
Evening.HUB_RADIUS = 1500

Evening.LAMP_LIGHTS = 6 -- настоящий свет только у ближайших фонарей: планшет не тянет больше
Evening.LAMP_RANGE = 18
Evening.FIREFLY_SPOTS = 14 -- клумб и кустов со светлячками
Evening.WINDOW_COLOR = rgb(255, 214, 130) -- тёплый свет в окнах

function Evening.inHub(position: Vector3): boolean
	return math.abs(position.X) < Evening.HUB_RADIUS and math.abs(position.Z) < Evening.HUB_RADIUS
end

local function smooth(k: number): number
	return k * k * (3 - 2 * k)
end

local NUMBERS = { "brightness", "exposure", "haze", "glare", "sun", "glow" }
local COLORS = { "ambient", "outdoor", "tint", "air", "decay", "clouds" }

-- Образ между a и b на доле пути k (0..1). Часы берутся из clockFrom образа b, если он есть.
function Evening.blend(a: Look, b: Look, k: number): Look
	local result: any = {}
	for _, key in NUMBERS do
		result[key] = (a :: any)[key] + ((b :: any)[key] - (a :: any)[key]) * k
	end
	for _, key in COLORS do
		result[key] = ((a :: any)[key] :: Color3):Lerp((b :: any)[key], k)
	end
	local from = b.clockFrom or a.clock
	result.clock = from + (b.clock - from) * k
	return result :: Look
end

-- Свет в секунду t круга (по серверным часам — у всех одинаковый).
function Evening.sample(t: number): Look
	t = t % Evening.CYCLE
	local timeline = Evening.TIMELINE
	for index = 1, #timeline - 1 do
		local from, to = timeline[index], timeline[index + 1]
		if t >= from.at and t < to.at then
			local k = smooth((t - from.at) / (to.at - from.at))
			return Evening.blend(Evening.LOOKS[from.look], Evening.LOOKS[to.look], k)
		end
	end
	return Evening.LOOKS.day
end

return Evening
