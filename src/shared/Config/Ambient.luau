--!strict
--[[
	Звуки природы: птицы над площадью и вода там, где она есть.

	Звуки — из библиотеки Pro Sound Effects, которую Roblox лицензировал для всех
	опытов (id в AudioRegistry). Играют в группе Ambient: на время реплики её
	приглушает AudioController, как и музыку, — голос главнее всего.

	Птицы — фон всей площади, без места: слышны везде, пока ребёнок не в забеге.
	Вода — в точке: фонтан слышно, только подойдя к нему, и чем ближе, тем громче.
	Так звук сам подсказывает, где интересное.
]]

local Ambient = {}

-- Фон площади: не громче тихого разговора, музыка остаётся главной.
Ambient.BED = { key = "amb_birds", volume = 0.35 }
-- В сумерки (Config/Evening) птицы засыпают и поют сверчки.
Ambient.EVENING_BED = { key = "amb_crickets", volume = 0.3 }

export type Spot = {
	key: string,
	volume: number,
	-- Дальше этого звука нет, на половине — едва слышно.
	radius: number,
	-- Музыка места: играет только ближайшая, общая музыка парка рядом молчит.
	zone: boolean?,
}

-- Звучащие места по виду декора (Config/Decor): у каждого такого предмета свой звук.
local SPOTS: { [string]: Spot } = {
	fountain = { key = "amb_fountain", volume = 0.7, radius = 70 },
}
Ambient.SPOTS = SPOTS

-- Водопад на горизонте (Config/Horizon.WATERFALL): шумит издалека, слышно у домов.
Ambient.WATERFALL = { key = "amb_stream", volume = 1, radius = 190 }

-- Карусель (Config/Rides.CAROUSEL): вальс шарманки, слышно только рядом с ней.
Ambient.CAROUSEL = { key = "amb_carousel", volume = 0.45, radius = 60, zone = true }

-- Зимняя полянка (Config/Playground winter): «Jingle Bells» у ёлки, слышно только рядом.
Ambient.WINTER = { key = "amb_winter_bells", volume = 0.4, radius = 55, zone = true }

-- Озеро с лебедями (Config/Rides.SWANS): «Танец маленьких лебедей» и плеск воды.
Ambient.SWANS = { key = "amb_swan_dance", volume = 0.4, radius = 60, zone = true }
Ambient.LAKE = { key = "amb_lake", volume = 0.5, radius = 45 }

-- Корабль-качели (Config/Rides.SHIP): морская песня, слышно только рядом.
Ambient.SHIP = { key = "amb_ship_shanty", volume = 0.4, radius = 60, zone = true }

-- Тир (Config/Playground gallery): ярмарочная музыка, слышно только рядом со стендом.
Ambient.GALLERY = { key = "amb_carnival", volume = 0.35, radius = 50, zone = true }
-- Пруд с рыбками (Config/Playground pond): тихий лягушачий хор в камышах.
Ambient.POND = { key = "amb_frogs", volume = 0.25, radius = 32 }

-- Грот с кристаллами (Config/Playground.GROTTO): шум водопада у входа, капли внутри.
Ambient.GROTTO_FALL = { key = "amb_stream", volume = 0.6, radius = 40 }
Ambient.GROTTO_DRIP = { key = "amb_cave_drip", volume = 0.6, radius = 16 }

-- Струйки воды водопада: за сколько секунд пробегают пласт сверху вниз.
Ambient.FALL_STRIPE_SECONDS = 1.6

Ambient.FADE_SECONDS = 2

--[[
	Звуковые зоны. На проверке 25.09.2026 у корабля-качелей разом играли музыка
	парка, морская песня, скрип, птицы и свисток поезда — «кеся-меся». Теперь
	у каждого места с музыкой (карусель, ёлка, лебеди, корабль, тир) своя зона:
	вошёл — музыка парка затихает совсем, играет только песня этого места,
	а песни соседних мест молчат, даже если их радиусы задевают друг друга.
	Шум воды и лягушек не музыка: он звучит как раньше, по расстоянию.
]]
Ambient.ZONE_FADE_SECONDS = 1.2
-- Доля радиуса зоны, с которой её песня слышна: у края не спорит с музыкой парка.
Ambient.ZONE_ENTER = 0.75

export type ZoneAt = { position: Vector3, radius: number }

-- Какая зона звучит для слушателя в точке at: ближайшая по доле радиуса, или nil.
function Ambient.zoneAt(at: Vector3, zones: { ZoneAt }): number?
	local best, bestShare = nil, math.huge
	for index, zone in zones do
		local flat = (at - zone.position) * Vector3.new(1, 0, 1)
		local share = flat.Magnitude / (zone.radius * Ambient.ZONE_ENTER)
		if share < 1 and share < bestShare then
			best, bestShare = index, share
		end
	end
	return best
end

return Ambient
