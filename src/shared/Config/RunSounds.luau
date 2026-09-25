--!strict
--[[
	Звуки аттракционов забега (Controllers/RunHazardController).

	До них забег был немым: валун катился беззвучно, молот проносился мимо
	уха без свиста, и понять, что сейчас будет, можно было только глазами.
	Звук здесь — подсказка: скрип качелей отмечает, где доска развернулась,
	свист молота — что он прошёл низ, треск печеньки — что пора прыгать.

	Все звуки из лицензированной библиотеки Roblox (Pro Sound Effects и звуки
	самого Roblox): загружать нечего, ID живут в AudioRegistry (LIBRARY).
	Звучат в мире, а не в ушах: слышно только рядом с аттракционом.
]]

local RunSounds = {}

export type Event = {
	key: string, -- ключ AudioRegistry
	volume: number,
	speed: { number }?, -- разброс высоты: один и тот же хруст не звучит пулемётом
	seconds: number, -- сколько держать звук, прежде чем убрать
}

RunSounds.EVENTS = {
	bounce = { key = "sfx_run_bounce", volume = 0.8, speed = { 0.9, 1.15 }, seconds = 2 },
	crack = { key = "sfx_run_crack", volume = 0.7, speed = { 0.9, 1.2 }, seconds = 2 },
	crumble = { key = "sfx_run_crumble", volume = 0.45, speed = { 1, 1.3 }, seconds = 3 },
	stomp = { key = "sfx_run_stomp", volume = 0.9, speed = { 0.7, 0.85 }, seconds = 2 },
	whoosh = { key = "sfx_run_whoosh", volume = 0.6, speed = { 0.8, 1 }, seconds = 2 },
	roll = { key = "sfx_run_roll", volume = 0.7, seconds = 7 },
	creak = { key = "sfx_run_creak", volume = 0.35, speed = { 0.85, 1.1 }, seconds = 3 },
	-- Тучка-ветродуй дует губами: «фу-у-у» слышно раньше, чем долетит ветер.
	blow = { key = "sfx_run_blow", volume = 0.9, speed = { 0.9, 1.1 }, seconds = 4 },
	-- Буквенные кочки: верная звенит кристаллом, чужая булькает и мягко уходит вниз.
	stone_right = { key = "sfx_crystal", volume = 0.6, speed = { 1.1, 1.3 }, seconds = 3 },
	stone_sink = { key = "sfx_run_bloop", volume = 0.9, speed = { 0.8, 1 }, seconds = 2 },
} :: { [string]: Event }

-- Звуки, которые звучат всё время, пока аттракцион рядом: бульканье лавы.
RunSounds.LOOPS = {
	lava = { key = "amb_run_lava", volume = 0.5, seconds = 0 },
} :: { [string]: Event }

RunSounds.HEAR = 70 -- дальше этого от ребёнка звуки аттракциона не играем

return RunSounds
