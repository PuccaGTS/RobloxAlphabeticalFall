--!strict
--[[
	Музыка по местам: что звучит на площади, в забеге мира букв и на тропе цифр.

	Своих треков три (`mus_theme_1..3`, docs/05-AUDIO-VO.md § 7), но они не загружены
	и с лицензией Suno не всё ясно (§ 7.1). Чтобы игра не молчала, в плейлистах
	стоят треки из музыкальной библиотеки Roblox — APM Music, которую Roblox
	лицензировал для любых опытов на платформе: загружать и покупать ничего не надо.
	Свои темы стоят в тех же плейлистах первыми и начнут звучать сами, как только
	у них появится id в AudioRegistry — пустой ключ плейлист просто пропускает.

	Отбирались спокойные инструментальные треки без слов: под музыкой звучит голос,
	называющий букву, и спорить с ним нельзя (docs/05-AUDIO-VO.md § 5). Поэтому
	пиццикато, фортепиано и колокольчики, а не барабаны и не синтезаторы.
]]

local Music = {}

export type Track = {
	key: string, -- ключ в AudioRegistry
	title: string,
	source: string, -- откуда трек: для страницы опыта и для того, кто будет менять
}

-- Треки библиотеки Roblox. id живут в AudioRegistry, здесь — что это за музыка.
local LIBRARY: { Track } = {
	{ key = "mus_lib_woodland", title = "Woodland Walks", source = "APM Music" },
	{ key = "mus_lib_playground", title = "Playground Stories (Underscore B)", source = "APM Music" },
	{ key = "mus_lib_garden", title = "Watching the Garden Grow (a)", source = "APM Music" },
	{ key = "mus_lib_exploration", title = "Exploration (Alternate) A", source = "APM Music" },
	{ key = "mus_lib_playful", title = "Playful (Underscore)", source = "APM Music" },
	{ key = "mus_lib_crafts", title = "Tiny Crafts (b)", source = "APM Music" },
	{ key = "mus_lib_shiny", title = "Shiny Life A", source = "APM Music" },
	{ key = "mus_lib_lullaby", title = "Music Box Lullaby", source = "APM Music" },
	{ key = "mus_lib_twinkle", title = "Twinkle Twinkle Little Star (a)", source = "APM Music" },
}
Music.LIBRARY = LIBRARY

--[[
	Плейлисты по местам. Треки идут по кругу, между ними — плавная смена.
	Площадь спокойнее всего: там читают таблички и выбирают, куда идти.
	Забег бодрее: там бегут и прыгают. На тропе цифр — «задумчивая» музыка:
	там считают.
]]
Music.PLAYLISTS = {
	hub = { "mus_theme_1", "mus_lib_woodland", "mus_lib_playground", "mus_lib_garden" },
	letters = { "mus_theme_2", "mus_lib_exploration", "mus_lib_playful" },
	math = { "mus_theme_3", "mus_lib_crafts", "mus_lib_shiny" },
	-- Сумерки в парке (Config/Evening): музыкальная шкатулка и колокольчики.
	evening = { "mus_lib_lullaby", "mus_lib_twinkle" },
}

Music.FADE_SECONDS = 2 -- смена трека и смена места
Music.VOLUME = 0.5 -- громкость внутри группы Music; общую громкость ставит родитель
-- Как часто проверять, где ребёнок. Смена места — телепорт, секунда задержки не слышна.
Music.CHECK_SECONDS = 1

-- Место по испытанию, в котором ребёнок бежит. Всё остальное — площадь.
Music.RUN_PLACE = {
	tunnel_run = "letters",
	math_gates = "math",
}

function Music.keys(): { string }
	local keys: { string } = {}
	for _, track in Music.LIBRARY do
		table.insert(keys, track.key)
	end
	return keys
end

return Music
