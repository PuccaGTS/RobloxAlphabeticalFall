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

export type Spot = {
	key: string,
	volume: number,
	-- Дальше этого звука нет, на половине — едва слышно.
	radius: number,
}

-- Звучащие места по виду декора (Config/Decor): у каждого такого предмета свой звук.
local SPOTS: { [string]: Spot } = {
	fountain = { key = "amb_fountain", volume = 0.7, radius = 70 },
}
Ambient.SPOTS = SPOTS

-- Водопад на горизонте (Config/Horizon.WATERFALL): шумит издалека, слышно у домов.
Ambient.WATERFALL = { key = "amb_stream", volume = 1, radius = 190 }

-- Струйки воды водопада: за сколько секунд пробегают пласт сверху вниз.
Ambient.FALL_STRIPE_SECONDS = 1.6

Ambient.FADE_SECONDS = 2

return Ambient
